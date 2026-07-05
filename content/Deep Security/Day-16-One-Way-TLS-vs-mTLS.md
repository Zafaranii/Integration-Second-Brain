---
tags: [security, bucket-2, mtls, day-16]
created: 2025-07-05
bucket: 2
week: 4
day: 16
status: not-started
prerequisites: ["Day-15-SNI-and-Week-3-Wrapup"]
---

# Day 16 — One-Way TLS vs mTLS

> [!info] Why This Day Exists
> Everything in Week 3 was one-way TLS: the server proves who it is, the client stays anonymous at the TLS layer (auth happens later, e.g. via a bearer token). mTLS flips that — both sides present certificates. This is the model behind bank-to-bank integrations, Kafka broker-to-client security, and most zero-trust service mesh designs. Getting the mental model right here makes Days 17–20 mechanical rather than confusing.

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-15-SNI-and-Week-3-Wrapup]] | **Next:** [[Day-17-Building-a-Local-mTLS-Server]] →

---

## 🧠 Theory Block (15 mins)

### One-Way TLS — What You Already Know

```
Client                                    Server
  |                                         |
  |----------- ClientHello ---------------->|
  |<---------- ServerHello, Certificate ----|   Server proves identity
  |------------ (key exchange) ------------>|
  |<===== encrypted channel established ===>|
  |                                         |
  | Client identity? Not established at    |
  | the TLS layer at all — if needed, it's |
  | proven LATER, inside the encrypted     |
  | channel (e.g. HTTP Basic Auth, OAuth   |
  | bearer token, API key header)          |
```

This is what every browser-to-website HTTPS connection looks like. The client trusts the server; the server has no cryptographic idea who the client is until an application-layer credential shows up.

### Mutual TLS (mTLS) — Both Sides Present Certificates

```
Client                                    Server
  |                                         |
  |----------- ClientHello ---------------->|
  |<---------- ServerHello, Certificate ----|   Server proves identity
  |<---------- CertificateRequest ----------|   Server DEMANDS a client cert
  |----------- Certificate (client's) ----->|   Client proves identity
  |----------- CertificateVerify ---------->|   Client signs to prove key possession
  |------------ (key exchange) ------------>|
  |<===== encrypted channel, BOTH sides ===>|
  |      cryptographically authenticated    |
```

The extra flight is `CertificateRequest` — the server explicitly asking the client for a certificate — followed by the client sending its own `Certificate` and a `CertificateVerify` message (a signature proving it holds the matching private key, not just that it copied someone else's public cert).

### Why mTLS Instead of "Just Use a Token"

|                  | Bearer token / API key (over one-way TLS)     | mTLS                                                           |
| ---------------- | --------------------------------------------- | -------------------------------------------------------------- |
| Proven at        | Application layer, after TLS is already up    | TLS layer itself, before any app data flows                    |
| If leaked        | Usable from ANY machine until revoked/expired | Useless without the matching private key, which never travels  |
| Revocation       | Token blacklist / short expiry                | Cert revocation (CRL/OCSP) or truststore removal               |
| Typical use case | User-facing APIs, mobile apps, OAuth flows    | Service-to-service, B2B integrations, internal zero-trust mesh |
| Overhead         | Low                                           | Higher — key/cert lifecycle management per client              |

In banking integration work specifically, mTLS is standard for **server-to-server** channels (bank ↔ payment switch, ACE ↔ partner API) precisely because the identity guarantee is tied to possession of a private key that can be stored in an HSM or protected keystore, rather than a string that can be copy-pasted anywhere.

### The Two New Artifacts mTLS Requires

Where one-way TLS only needed the **server's** keystore + the **client's** truststore, mTLS needs a second pair in the opposite direction:

```
                    SERVER                          CLIENT
Identity:      server keystore  ─────proves────►   verified against
                                                     client's truststore
                                                          │
Identity:      verified against  ◄────proves──────  client keystore
               server's truststore
```

Both parties now need **both** a keystore (their own identity) **and** a truststore (who they'll accept from the other side). This is the conceptual leap Day 17 and 18 make concrete.

---

## 🛠️ Hands-on Lab (40 mins)

### Exercise 1 — Reproduce a One-Way TLS Handshake and Confirm No Client Auth Occurs

```bash
cd ~/tls-lab/ca

openssl s_server -accept 8443 -cert leaf-fullchain.crt -key leaf.key -www &
SERVER_PID=$!

# Connect with NO client certificate at all — should still succeed (one-way TLS)
openssl s_client -connect localhost:8443 -CAfile root-ca.crt < /dev/null 2>&1 | grep -E "Verify return code|CN ="

kill $SERVER_PID
```

Connection succeeds — server never asked for a client cert.

### Exercise 2 — Add `-Verify` and Watch the Server Demand a Client Cert

```bash
# -Verify N tells openssl s_server to REQUEST (and require) a client cert
openssl s_server -accept 8443 -cert leaf-fullchain.crt -key leaf.key \
  -CAfile root-ca.crt -Verify 1 -www &
SERVER_PID=$!

# Attempt WITHOUT a client cert — should now fail or be rejected
openssl s_client -connect localhost:8443 -CAfile root-ca.crt < /dev/null 2>&1 | grep -E "Verify return code|alert"

kill $SERVER_PID
```

Expect an alert such as `handshake failure` or `certificate required` — this is the exact server-side behavior change that defines mTLS versus one-way TLS.

### Exercise 3 — Generate a Client Identity and Successfully Authenticate

```bash
# Create a client key + CSR, signed by the same lab intermediate (in real life, could be a different CA)
openssl genrsa -out client.key 2048
openssl req -new -key client.key -out client.csr -subj "/CN=integration-client-01/O=Lab/C=EG"
openssl x509 -req -in client.csr -CA intermediate.crt -CAkey intermediate.key \
  -CAcreateserial -out client.crt -days 365 -sha256

openssl s_server -accept 8443 -cert leaf-fullchain.crt -key leaf.key \
  -CAfile root-ca.crt -Verify 1 -www &
SERVER_PID=$!

# Connect WITH the client cert — should now succeed
openssl s_client -connect localhost:8443 -CAfile root-ca.crt \
  -cert client.crt -key client.key < /dev/null 2>&1 | grep -E "Verify return code|CN ="

kill $SERVER_PID
```

### Exercise 4 — Capture and Identify the Extra mTLS Flight in Wireshark

```bash
openssl s_server -accept 8443 -cert leaf-fullchain.crt -key leaf.key -CAfile root-ca.crt -Verify 1 -www &
SERVER_PID=$!

sudo tcpdump -i lo -n 'tcp port 8443' -w /tmp/mtls.pcap &
TCPDUMP_PID=$!

openssl s_client -connect localhost:8443 -CAfile root-ca.crt -cert client.crt -key client.key < /dev/null > /dev/null 2>&1

kill $TCPDUMP_PID $SERVER_PID
wireshark /tmp/mtls.pcap
```

Filter `tls.handshake.type == 13` (CertificateRequest) and `tls.handshake.type == 15` (CertificateVerify) — these two message types only ever appear in an mTLS handshake, never in one-way TLS.

---

## ✅ Validation (5 mins)

You've proven this day's material if you can:

1. Explain the two new handshake messages mTLS adds (`CertificateRequest`, `CertificateVerify`) and what each proves.
2. Reproduce both the failure (no client cert against a `-Verify 1` server) and the success (with a valid client cert) cases.
3. Articulate why mTLS is a stronger service-to-service identity guarantee than a bearer token, in terms of what leaking each credential actually allows an attacker to do.
4. State, correctly, that in mTLS both parties need both a keystore AND a truststore — not just one or the other.

---

## Key Takeaways

- One-way TLS proves only the server's identity; any client identity is established later, at the application layer.
- mTLS adds two handshake messages — `CertificateRequest` from the server, `CertificateVerify` from the client — cryptographically proving client identity before any app data flows.
- A leaked bearer token is usable anywhere; a leaked client certificate without its private key is useless — this is mTLS's core security advantage for service-to-service channels.
- Both parties need a keystore (own identity) and a truststore (who they accept) in mTLS — one-way TLS only required this pairing on one side.

---

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-15-SNI-and-Week-3-Wrapup]] | **Next:** [[Day-17-Building-a-Local-mTLS-Server]] →
