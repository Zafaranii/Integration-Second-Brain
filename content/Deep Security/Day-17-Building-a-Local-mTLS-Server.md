---
tags: [security, bucket-2, mtls, day-17]
created: 2025-07-05
bucket: 2
week: 4
day: 17
status: not-started
prerequisites: ["Day-16-One-Way-TLS-vs-mTLS"]
---

# Day 17 — Building a Local mTLS Server

> [!info] Why This Day Exists
> Day 16 proved mTLS works using OpenSSL's built-in test server. Today you build a real, application-layer mTLS server — the kind of thing you'd stand up to test an ACE HTTPS Listener's client-auth configuration, or to sanity-check a partner integration before it touches a shared environment. This is the lab you'll reach for whenever someone says "the partner claims their cert is fine but our side rejects it" and you need an isolated environment to prove which side is wrong.

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-16-One-Way-TLS-vs-mTLS]] | **Next:** [[Day-18-Client-Keystores-and-Truststores]] →

---

## 🧠 Theory Block (15 mins)

### Why Build a Real Server Instead of Reusing `openssl s_server`

`openssl s_server` is excellent for handshake-level testing but doesn't behave like a real application — it can't easily return custom responses per client identity, log the authenticated client's DN, or simulate an actual API. A minimal Python HTTPS server with `ssl.CERT_REQUIRED` gives you a much closer approximation of how ACE's HTTPS Listener, DataPower's Front Side Handler, or a Spring Boot service actually enforces and exposes mTLS identity to application code.

### The Server-Side mTLS Configuration Contract

Any real mTLS server needs exactly four pieces of configuration, and confusing which is which is the single most common misconfiguration:

| Config item            | Value                                         | Role                                                           |
| ---------------------- | --------------------------------------------- | -------------------------------------------------------------- |
| Server certificate     | `server.crt` (+ chain)                        | What the server presents to prove ITS identity                 |
| Server private key     | `server.key`                                  | Matches the server cert, never shared                          |
| Client CA / truststore | `client-ca.crt` (or truststore containing it) | Which CA(s) the server will accept CLIENT certs from           |
| Verification mode      | "required" vs "optional" vs "none"            | Whether the server demands, requests, or ignores a client cert |

Note that the "client CA" the server trusts does **not** have to be the same CA that issued the server's own certificate — in real B2B integrations, the server's cert usually comes from a public/enterprise CA while the client CA is often the partner organization's own internal CA, explicitly added to the server's truststore as a one-off trust relationship.

### Verification Modes

```
CERT_NONE      → server never asks for a client cert (one-way TLS — Day 16 baseline)
CERT_OPTIONAL  → server asks, but proceeds even if the client doesn't provide one
                  (application code must then handle "no client cert" as a case)
CERT_REQUIRED  → server refuses the handshake entirely if no valid client cert is presented
                  (true mTLS enforcement — what production B2B integrations use)
```

`CERT_OPTIONAL` is a common source of a false sense of security: the TLS layer completes even without a client cert, so unless the application explicitly checks and rejects that case, you've built something that _looks_ like mTLS but doesn't actually enforce it.

---

## 🛠️ Hands-on Lab (40 mins)

### Exercise 1 — Reuse Your Lab PKI, Build a Python mTLS Server

```bash
cd ~/tls-lab/ca
mkdir -p mtls-app && cd mtls-app
cp ../leaf-fullchain.crt ../leaf.key ../root-ca.crt ../client.crt .

cat > mtls_server.py << 'EOF'
import ssl
import http.server

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        # In a real app server, the peer cert would be pulled from the
        # underlying socket's SSLObject — this demonstrates the concept.
        cert = self.connection.getpeercert()
        subject = dict(x[0] for x in cert.get('subject', [])) if cert else {}
        cn = subject.get('commonName', 'UNKNOWN')

        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.end_headers()
        self.wfile.write(f"Hello, authenticated client: CN={cn}\n".encode())

context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(certfile="leaf-fullchain.crt", keyfile="leaf.key")
context.load_verify_locations(cafile="root-ca.crt")   # trust anchor for CLIENT certs
context.verify_mode = ssl.CERT_REQUIRED                # enforce mTLS

httpd = http.server.HTTPServer(('localhost', 8443), Handler)
httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
print("mTLS server listening on https://localhost:8443")
httpd.serve_forever()
EOF

python3 mtls_server.py &
SERVER_PID=$!
sleep 1
```

### Exercise 2 — Fail Without a Client Cert, Succeed With One

```bash
# No client cert — should be rejected at the TLS layer, never reach the app
curl -v --cacert root-ca.crt https://localhost:8443/ 2>&1 | grep -E "SSL certificate|alert|error"

# With client cert — should succeed and show the authenticated CN
curl -v --cacert root-ca.crt --cert client.crt --key ../client.key https://localhost:8443/
```

The first attempt should never even print an HTTP response — the connection dies during the TLS handshake, before the Python app code runs at all. This distinction (rejected at TLS vs rejected by application logic) is important operationally: mTLS failures show up in TCP/TLS logs, not application logs.

### Exercise 3 — Prove `CERT_OPTIONAL`'s False Sense of Security

```bash
# Edit the server to use CERT_OPTIONAL instead, restart it
kill $SERVER_PID
sed -i 's/CERT_REQUIRED/CERT_OPTIONAL/' mtls_server.py
python3 mtls_server.py &
SERVER_PID=$!
sleep 1

# Connect with NO client cert — with CERT_OPTIONAL this now SUCCEEDS at the TLS layer
curl -v --cacert root-ca.crt https://localhost:8443/
```

You'll get back `Hello, authenticated client: CN=UNKNOWN` — the connection succeeded despite no client identity being presented. This is exactly the misconfiguration that turns "mTLS-protected" into "TLS with an optional, unenforced identity claim." Revert to `CERT_REQUIRED` before continuing.

```bash
kill $SERVER_PID
sed -i 's/CERT_OPTIONAL/CERT_REQUIRED/' mtls_server.py
```

### Exercise 4 — Test Rejection of a Client Cert from an Untrusted CA

```bash
# Generate a completely separate, unrelated CA and client cert
openssl req -x509 -newkey rsa:2048 -keyout rogue-ca.key -out rogue-ca.crt \
  -days 365 -nodes -subj "/CN=Rogue CA/O=NotTrusted"
openssl genrsa -out rogue-client.key 2048
openssl req -new -key rogue-client.key -out rogue-client.csr -subj "/CN=rogue-client"
openssl x509 -req -in rogue-client.csr -CA rogue-ca.crt -CAkey rogue-ca.key \
  -CAcreateserial -out rogue-client.crt -days 365

python3 mtls_server.py &
SERVER_PID=$!
sleep 1

# Attempt to authenticate with the ROGUE client cert — server should reject it
curl -v --cacert root-ca.crt --cert rogue-client.crt --key rogue-client.key https://localhost:8443/ 2>&1 | grep -E "alert|unknown ca|error"

kill $SERVER_PID
```

Expect a TLS alert like `unknown ca` or `tlsv1 alert unknown ca` — the server's truststore (`root-ca.crt`) doesn't include the rogue CA, so no client cert it issues will ever be accepted, no matter how technically valid that cert is on its own.

---

## ✅ Validation (5 mins)

You've proven this day's material if you can:

1. Stand up the mTLS server, show a request without a client cert failing at the TLS layer (not the app layer).
2. Successfully authenticate with the correct client cert and show the server correctly extracting and displaying the client's CN.
3. Explain, from having seen it happen, why `CERT_OPTIONAL` is dangerous if application code doesn't independently enforce identity.
4. Demonstrate that a certificate from an untrusted CA is rejected even though it's a perfectly well-formed, validly-signed certificate — signed by the _wrong_ signer.

---

## Key Takeaways

- A real mTLS server needs four distinct configuration pieces: its own cert+key, and a separate trust anchor for client certs, plus an explicit verification mode.
- `CERT_REQUIRED` enforces mTLS at the TLS layer — rejected connections never reach application code, which shows up as connection-level failures, not HTTP error responses.
- `CERT_OPTIONAL` is a trap: the handshake succeeds either way, and enforcement silently shifts to application code that may not actually check for it.
- Certificate validity and certificate trust are separate checks — a well-formed cert from the wrong (untrusted) CA is still rejected, and that's the mechanism working correctly.

---

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-16-One-Way-TLS-vs-mTLS]] | **Next:** [[Day-18-Client-Keystores-and-Truststores]] →
