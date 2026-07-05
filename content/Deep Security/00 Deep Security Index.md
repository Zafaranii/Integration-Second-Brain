---
tags:
  - security
  - bucket-2
  - index
  - moc
created: 2025-07-05
bucket: 2
status: active
---

# Bucket 2 — Deep Security (TLS, mTLS & Cryptography)

> Bucket 1 got packets from A to B. Bucket 2 makes sure nobody in between can read or tamper with them, and that both ends can prove who they are. This is the material that turns "SSL handshake failed" from a mystery into a five-minute diagnosis — CSRs, cert chains, mTLS, and the crypto primitives (hashing, signing, JWT) sitting underneath every OAuth flow and Kafka SASL_SSL listener you'll ever touch.

**Tags:** #security #tls #mtls #cryptography #index

---

## Map of Content

### Week 3 — TLS Fundamentals

| Day                                              | Topic                                     |
| ------------------------------------------------ | ----------------------------------------- |
| [[Day-11-TLS-1.2-vs-1.3-Handshake\|Day 11]]      | TLS 1.2 vs 1.3 — Handshake Deep Dive      |
| [[Day-12-Private-Keys-and-CSRs-OpenSSL\|Day 12]] | Private Keys & CSRs with OpenSSL          |
| [[Day-13-Self-Signed-Certificates\|Day 13]]      | Self-Signed Certificates                  |
| [[Day-14-CA-Chains-and-Trust-Stores\|Day 14]]    | CA Chains & Trust Stores                  |
| [[Day-15-SNI-and-Week-3-Wrapup\|Day 15]]         | SNI & Week 3 Wrap-up / Scenario Debugging |

### Week 4 — Mutual TLS (mTLS)

| Day                                                 | Topic                                         |
| --------------------------------------------------- | --------------------------------------------- |
| [[Day-16-One-Way-TLS-vs-mTLS\|Day 16]]              | One-Way TLS vs mTLS                           |
| [[Day-17-Building-a-Local-mTLS-Server\|Day 17]]     | Building a Local mTLS Server                  |
| [[Day-18-Client-Keystores-and-Truststores\|Day 18]] | Client Keystores & Truststores (Java/keytool) |
| [[Day-19-Kafka-mTLS-Basics\|Day 19]]                | Kafka mTLS Basics                             |
| [[Day-20-mTLS-Debugging\|Day 20]]                   | mTLS Debugging                                |

### Week 5 — Applied Cryptography

| Day                                                 | Topic                                     |
| --------------------------------------------------- | ----------------------------------------- |
| [[Day-21-Hashing-vs-Encryption-vs-Signing\|Day 21]] | Hashing vs Encryption vs Signing          |
| [[Day-22-Generating-Digital-Signatures\|Day 22]]    | Generating Digital Signatures             |
| [[Day-23-JWT-and-JWS-Basics\|Day 23]]               | JWT / JWS Basics                          |
| [[Day-24-Base64-vs-Encryption\|Day 24]]             | Base64 vs Encryption                      |
| [[Day-25-Security-Architecture-Wrapup\|Day 25]]     | Architecture Wrap-up & Scenario Debugging |

---

## Concept Index

- **TLS handshake internals** → [[Day-11-TLS-1.2-vs-1.3-Handshake]]
- **Key material & CSR generation** → [[Day-12-Private-Keys-and-CSRs-OpenSSL]]
- **Self-signed vs CA-signed** → [[Day-13-Self-Signed-Certificates]], [[Day-14-CA-Chains-and-Trust-Stores]]
- **Trust chains / truststores** → [[Day-14-CA-Chains-and-Trust-Stores]], [[Day-18-Client-Keystores-and-Truststores]]
- **Virtual hosting over TLS** → [[Day-15-SNI-and-Week-3-Wrapup]]
- **Mutual authentication** → [[Day-16-One-Way-TLS-vs-mTLS]], [[Day-17-Building-a-Local-mTLS-Server]]
- **Java keystore tooling** → [[Day-18-Client-Keystores-and-Truststores]]
- **Kafka security** → [[Day-19-Kafka-mTLS-Basics]]
- **Handshake failure diagnosis** → [[Day-20-mTLS-Debugging]]
- **Crypto primitives** → [[Day-21-Hashing-vs-Encryption-vs-Signing]], [[Day-22-Generating-Digital-Signatures]]
- **Tokens** → [[Day-23-JWT-and-JWS-Basics]]
- **Encoding vs encryption confusion** → [[Day-24-Base64-vs-Encryption]]
- **Synthesis** → [[Day-25-Security-Architecture-Wrapup]]

---

## File & Artifact Reference

| Artifact        | Extension                | Format                     | Contains                              | Ever leaves the host? |
| --------------- | ------------------------ | -------------------------- | ------------------------------------- | --------------------- |
| Private key     | `.key` / `.pem`          | PEM (Base64)               | Secret key material                   | **Never**             |
| CSR             | `.csr`                   | PEM                        | Public key + identity claims          | Yes — to the CA       |
| Certificate     | `.crt` / `.pem` / `.cer` | PEM or DER                 | Public key + CA signature             | Yes — freely          |
| Chain / bundle  | `.pem` / `.chain`        | PEM, concatenated          | Leaf + intermediate(s), leaf-first    | Yes                   |
| Java Keystore   | `.jks` / `.p12`          | JKS or PKCS12              | Private key + own cert (**identity**) | No                    |
| Java Truststore | `.jks` / `.p12`          | JKS or PKCS12              | CA certs only (**trust decisions**)   | Often shared          |
| PKCS12 bundle   | `.p12` / `.pfx`          | Binary, password-protected | Key + cert, cross-platform            | No                    |

---

## TLS/mTLS Debugging Decision Tree

```
"SSL/TLS" or "certificate" error?
│
├── "unable to get local issuer certificate" → Chain incomplete → Day 14
├── "self signed certificate in chain" → Untrusted root not in truststore → Day 13 / 14
├── "certificate has expired" → openssl x509 -enddate -noout -in cert.pem
├── "hostname mismatch" / "does not match" → SAN/CN vs requested host → Day 15
├── "bad certificate" (seen server-side during mTLS) → Client cert rejected → Day 20
├── "handshake_failure" / "certificate_required" (client-side, no cert sent) → Day 16 / 20
├── "unsupported protocol" / "no protocols available" → TLS version mismatch → Day 11
├── "PKIX path building failed" → Truststore missing intermediate/root CA → Day 18
└── Signature/JWT rejected downstream but TLS is fine → Day 21–23
```

---

## How This Bucket Builds

```
Week 3: One-way TLS            Week 4: Mutual TLS              Week 5: Crypto primitives
(server proves identity)  →    (both sides prove identity) →   (the math underneath it all)
       │                              │                                │
  CSR, chain, SNI              keystore/truststore pairs        hash / sign / JWT
       │                              │                                │
       └──────────────────────────────┴────────────────────────────────┘
                                       │
                          Day 25: full mTLS + JWT capstone scenario
```
