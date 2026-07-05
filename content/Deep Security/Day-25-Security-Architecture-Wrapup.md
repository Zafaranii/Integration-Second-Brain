---
tags: [security, bucket-2, wrapup, capstone, day-25]
created: 2025-07-05
bucket: 2
week: 5
day: 25
status: not-started
prerequisites: ["Day-24-Base64-vs-Encryption"]
---

# Day 25 — Security Architecture Wrap-up & Scenario Debugging

> [!info] Why This Day Exists
> This is the capstone for the entire bucket. No new theory — instead, one continuous scenario that forces you to apply Weeks 3, 4, and 5 in the order a real incident would actually surface them: TLS chain, then mutual auth, then token integrity. If you can work through this end to end without flipping back to earlier days, Bucket 2 is solid.

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-24-Base64-vs-Encryption]]

---

## 🧠 Theory Block (15 mins) — The Full Stack, One Picture

```
┌─────────────────────────────────────────────────────────────────┐
│  Layer 4: Application-level integrity/authenticity (Week 5)      │
│    JWT/JWS — signed access token, tamper-evident, NOT confidential│
├─────────────────────────────────────────────────────────────────┤
│  Layer 3: Mutual authentication (Week 4)                         │
│    Client presents cert → server verifies against its truststore │
│    Server presents cert → client verifies against ITS truststore │
├─────────────────────────────────────────────────────────────────┤
│  Layer 2: Transport encryption + server identity (Week 3)        │
│    TLS handshake, cert chain, SNI routing to the right cert       │
├─────────────────────────────────────────────────────────────────┤
│  Layer 1: Reliable byte stream (Bucket 1)                        │
│    TCP 3-way handshake, established connection                   │
└─────────────────────────────────────────────────────────────────┘
```

**The critical architectural insight:** each layer solves a problem the layer below it cannot. TCP doesn't know about certificates. TLS/mTLS doesn't know about application-level claims like "this user has role=admin." A JWT doesn't know or care whether the transport it arrived over was encrypted at all. Treating any one layer as a substitute for another — "we don't need mTLS, the JWT is signed" or "we don't need TLS, the payload is Base64'd" — is exactly the class of design mistake this bucket exists to prevent.

### End-to-End Request Lifecycle in a Real Banking Integration

```
1. TCP handshake to the ACE HTTPS Listener                    (Bucket 1)
2. TLS handshake — ACE presents its server cert + chain,      (Week 3)
   client verifies against its truststore, SNI selects
   the right cert if multiple hostnames share the listener
3. mTLS — client ALSO presents its cert, ACE verifies it       (Week 4)
   against ITS truststore (client-CA trust relationship)
4. Encrypted channel established — both identities proven
5. Client sends HTTP request with Authorization: Bearer <JWT>  (Week 5)
6. ACE (or an upstream API gateway) verifies the JWT signature
   against the issuer's public key, checks exp/aud/iss claims
7. Only NOW does application logic (ESQL, Java compute node)
   see the validated, authenticated, authorized request
```

Notice steps 2–3 and step 6 are answering **different questions**: "is this connection cryptographically trustworthy at the transport level" versus "is this specific request, from this specific claimed identity, valid and not expired." A system can have perfect mTLS and still be vulnerable if step 6 is skipped (anyone with network access to the mTLS-trusted client cert could send any claims they want), and a system can have perfect JWT validation but still be vulnerable to network-level attacks if there's no transport encryption/authentication happening at all underneath it.

---

## 🛠️ Hands-on Lab (40 mins) — Full Capstone Scenario

**The scenario:** you're standing up a partner-facing endpoint that must (a) encrypt all traffic, (b) cryptographically authenticate the partner as a specific known client, and (c) accept only requests carrying a validly signed, non-expired token for that same partner.

### Step 1 — Rebuild the Full PKI (Weeks 3–4 Recap)

```bash
mkdir -p ~/tls-lab/capstone && cd ~/tls-lab/capstone

# Root CA
openssl req -x509 -newkey rsa:4096 -keyout root-ca.key -out root-ca.crt \
  -days 3650 -nodes -subj "/CN=Capstone Root CA/O=Lab"

# Server (our side) leaf cert
openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr -subj "/CN=partner-api.lab.internal"
openssl x509 -req -in server.csr -CA root-ca.crt -CAkey root-ca.key -CAcreateserial \
  -out server.crt -days 365 -extfile <(echo "subjectAltName=DNS:partner-api.lab.internal")

# Partner (client) cert — imagine this was actually issued by THEIR CA in real life;
# for this lab we sign it with the same root to keep the trust story simple
openssl genrsa -out partner-client.key 2048
openssl req -new -key partner-client.key -out partner-client.csr -subj "/CN=partner-org-001"
openssl x509 -req -in partner-client.csr -CA root-ca.crt -CAkey root-ca.key -CAcreateserial \
  -out partner-client.crt -days 365

# Rogue actor — completely unrelated CA, to prove rejection later
openssl req -x509 -newkey rsa:2048 -keyout rogue.key -out rogue-ca.crt \
  -days 365 -nodes -subj "/CN=Rogue CA"
openssl genrsa -out rogue-client.key 2048
openssl req -new -key rogue-client.key -out rogue-client.csr -subj "/CN=fake-partner"
openssl x509 -req -in rogue-client.csr -CA rogue-ca.crt -CAkey rogue.key -CAcreateserial \
  -out rogue-client.crt -days 365
```

### Step 2 — Build the mTLS + JWT-Validating Server (Weeks 4–5 Combined)

```bash
cat > capstone_server.py << 'EOF'
import ssl, http.server, base64, json, hashlib
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.exceptions import InvalidSignature

with open("jwt-signing-pubkey.pem", "rb") as f:
    JWT_PUBKEY = serialization.load_pem_public_key(f.read())

def b64url_decode(s):
    s += '=' * (-len(s) % 4)
    return base64.urlsafe_b64decode(s)

def verify_jwt(token):
    try:
        header_b64, payload_b64, sig_b64 = token.split('.')
        signing_input = f"{header_b64}.{payload_b64}".encode()
        signature = b64url_decode(sig_b64)
        JWT_PUBKEY.verify(signature, signing_input, padding.PKCS1v15(), hashes.SHA256())
        payload = json.loads(b64url_decode(payload_b64))
        return True, payload
    except (InvalidSignature, Exception) as e:
        return False, str(e)

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        cert = self.connection.getpeercert()
        subject = dict(x[0] for x in cert.get('subject', [])) if cert else {}
        client_cn = subject.get('commonName', 'UNKNOWN')

        auth = self.headers.get('Authorization', '')
        if not auth.startswith('Bearer '):
            self.send_response(401); self.end_headers()
            self.wfile.write(b"Missing bearer token\n"); return

        token = auth[7:]
        ok, result = verify_jwt(token)
        if not ok:
            self.send_response(401); self.end_headers()
            self.wfile.write(f"Invalid token: {result}\n".encode()); return

        if result.get('sub') != client_cn:
            self.send_response(403); self.end_headers()
            self.wfile.write(b"Token subject does not match mTLS client identity\n"); return

        self.send_response(200); self.end_headers()
        self.wfile.write(f"OK — mTLS CN={client_cn}, JWT sub={result['sub']}, verified.\n".encode())

context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(certfile="server.crt", keyfile="server.key")
context.load_verify_locations(cafile="root-ca.crt")
context.verify_mode = ssl.CERT_REQUIRED

httpd = http.server.HTTPServer(('localhost', 8443), Handler)
httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
print("Capstone mTLS + JWT server on https://localhost:8443")
httpd.serve_forever()
EOF

pip install cryptography --break-system-packages -q
```

### Step 3 — Generate a JWT Signing Key and a Valid Token

```bash
openssl genrsa -out jwt-signing-key.pem 2048
openssl rsa -in jwt-signing-key.pem -pubout -out jwt-signing-pubkey.pem

b64url() { base64 | tr '+/' '-_' | tr -d '='; }
HEADER=$(echo -n '{"alg":"RS256","typ":"JWT"}' | b64url)
PAYLOAD=$(echo -n '{"sub":"partner-org-001","iss":"lab-auth","exp":9999999999}' | b64url)
SIG=$(echo -n "${HEADER}.${PAYLOAD}" | openssl dgst -sha256 -sign jwt-signing-key.pem -binary | b64url)
VALID_JWT="${HEADER}.${PAYLOAD}.${SIG}"
echo "$VALID_JWT" > valid_jwt.txt
```

### Step 4 — Run the Full Scenario: Four Failure Modes, Then Success

```bash
python3 capstone_server.py &
SERVER_PID=$!
sleep 1

echo "--- Test 1: No client cert at all (mTLS enforcement) ---"
curl -s -o /dev/null -w "%{http_code}\n" --cacert root-ca.crt https://localhost:8443/

echo "--- Test 2: Wrong CA client cert (rogue actor) ---"
curl -s -o /dev/null -w "%{http_code}\n" --cacert root-ca.crt \
  --cert rogue-client.crt --key rogue-client.key https://localhost:8443/ 2>/dev/null || echo "TLS handshake rejected (expected)"

echo "--- Test 3: Valid mTLS, but NO token ---"
curl -s -w "\nHTTP %{http_code}\n" --cacert root-ca.crt \
  --cert partner-client.crt --key partner-client.key https://localhost:8443/

echo "--- Test 4: Valid mTLS, tampered token ---"
TAMPERED="${VALID_JWT}x"
curl -s -w "\nHTTP %{http_code}\n" --cacert root-ca.crt \
  --cert partner-client.crt --key partner-client.key \
  -H "Authorization: Bearer $TAMPERED" https://localhost:8443/

echo "--- Test 5: Everything correct ---"
curl -s -w "\nHTTP %{http_code}\n" --cacert root-ca.crt \
  --cert partner-client.crt --key partner-client.key \
  -H "Authorization: Bearer $(cat valid_jwt.txt)" https://localhost:8443/

kill $SERVER_PID
```

---

## ✅ Validation (5 mins)

You've completed Bucket 2 if all five tests above produced the expected result:

| Test                          | Expected outcome                                | Layer being enforced                              |
| ----------------------------- | ----------------------------------------------- | ------------------------------------------------- |
| 1. No client cert             | Connection fails at TLS layer                   | Week 4 — mTLS enforcement                         |
| 2. Rogue CA client cert       | TLS handshake rejected                          | Week 4 — truststore trust boundary                |
| 3. Valid mTLS, no token       | `401 Missing bearer token`                      | Week 5 — JWT is a separate, additional check      |
| 4. Valid mTLS, tampered token | `401 Invalid token`                             | Week 5 — signature verification catches tampering |
| 5. Everything correct         | `200 OK`, showing matched mTLS CN and JWT `sub` | Full stack working together                       |

If you can explain _why_ each layer independently caused its specific test to fail — not just that it failed — Bucket 2 is genuinely internalized, not just completed.

---

## Key Takeaways — Bucket 2, End to End

- TLS, mTLS, and JWT/JWS each answer a different question, and none substitutes for another: transport encryption + server identity (Week 3), mutual cryptographic identity (Week 4), and tamper-evident application-level claims (Week 5) stack on top of each other rather than overlapping.
- The overwhelming majority of real-world security incidents in integration systems come from silently skipping one of these layers while assuming another one "already covers it" — the classic examples being `CERT_OPTIONAL` masquerading as enforced mTLS, and a signed-but-unencrypted JWT assumed to be confidential.
- A working systematic debugging order — TCP, then TLS chain, then mTLS client auth, then token validation — resolves nearly any real incident in this space without guesswork, because it mirrors the exact order these checks happen on the wire.
- Every hands-on exercise in this bucket used tools (`openssl`, `keytool`, `curl`, plain Python) that exist on essentially any Linux box or OpenShift pod — there's no dependency on a GUI tool to diagnose any of this in production.

---

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-24-Base64-vs-Encryption]]

**This completes Bucket 2 — Deep Security.**
