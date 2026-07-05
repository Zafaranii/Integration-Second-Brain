---
tags: [security, bucket-2, tls, openssl, csr, day-12]
created: 2025-07-05
bucket: 2
week: 3
day: 12
status: not-started
prerequisites: ["Day-11-TLS-1.2-vs-1.3-Handshake"]
---

# Day 12 — Private Keys and CSRs with OpenSSL

> [!info] Why This Day Exists
> Before any certificate exists, someone has to generate a key pair and ask a CA to sign it. This is the step every enterprise "please get a cert for this ACE integration server" ticket starts with. If you can't generate a correct CSR yourself, you're dependent on someone else for every new TLS endpoint you stand up — and you can't verify what a security team hands you actually matches what you asked for.

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-11-TLS-1.2-vs-1.3-Handshake]] | **Next:** [[Day-13-Self-Signed-Certificates]] →

---

## 🧠 Theory Block (15 mins)

### Asymmetric Key Pairs — The Foundation

A key pair is two mathematically linked numbers:

```
Private Key  → kept secret, used to DECRYPT or SIGN
Public Key   → shared freely,  used to ENCRYPT or VERIFY
```

Anything encrypted with the public key can only be decrypted with the matching private key, and anything signed with the private key can be verified by anyone holding the public key. A certificate is fundamentally just **a public key plus identity claims plus a trusted third party's signature over both**.

### RSA vs EC — The Two Algorithms You'll Actually Use

| Property                      | RSA                                              | EC (Elliptic Curve, e.g. `prime256v1`)                                 |
| ----------------------------- | ------------------------------------------------ | ---------------------------------------------------------------------- |
| Typical key size              | 2048 / 4096 bit                                  | 256 / 384 bit                                                          |
| Speed                         | Slower for key generation & signing              | Much faster                                                            |
| Handshake size                | Larger certs, larger key exchange messages       | Smaller — good for high-throughput/mobile                              |
| Enterprise middleware support | Universal (IBM MQ, ACE, DataPower, ancient Java) | Widely supported now, but check older JCE/keystore compatibility first |
| Common curve names            | N/A                                              | `prime256v1` (P-256), `secp384r1` (P-384)                              |

For interviews and real IBM stacks: **RSA 2048 is still the safe enterprise default** unless a specific mandate calls for EC. Never go below 2048-bit RSA — 1024-bit is considered broken for anything security-sensitive.

### The Certificate Signing Request (CSR) Workflow

```
 You                                    Certificate Authority (CA)
  │                                              │
  │ 1. Generate private key (never shared)       │
  │ 2. Generate CSR:                             │
  │      - your public key                       │
  │      - identity info (CN, SAN, O, OU...)     │
  │      - signed by YOUR OWN private key         │
  │      (proves you hold the matching private   │
  │       key, without revealing it)              │
  │                                              │
  │────────── send CSR (.csr file) ─────────────>│
  │                                              │ 3. CA verifies identity (domain control, org vetting)
  │                                              │ 4. CA signs your public key + identity with
  │                                              │    the CA's OWN private key
  │<───────── returns signed certificate ─────────│
  │                                              │
  │ 5. Install cert + private key together        │
```

**Critical point:** the CSR itself is signed by the _requester's_ private key (a self-signature proving possession), not by the CA. The CA's signature only appears on the final certificate it issues back.

### Anatomy of a CSR — What Actually Goes In It

| Field                          | Meaning                                                  | Real-world example                                             |
| ------------------------------ | -------------------------------------------------------- | -------------------------------------------------------------- |
| CN (Common Name)               | Primary hostname (legacy; largely superseded by SAN)     | `ace-prod-01.bank.internal`                                    |
| SAN (Subject Alternative Name) | **Modern requirement** — list of all valid hostnames/IPs | `DNS:ace-prod-01.bank.internal, DNS:ace-prod-02.bank.internal` |
| O (Organization)               | Legal entity name                                        | `AAIB`                                                         |
| OU (Organizational Unit)       | Department/team                                          | `Integration Engineering`                                      |
| C, ST, L                       | Country, State, Locality                                 | `EG, Giza, Giza`                                               |

> [!warning] SAN Is Not Optional Anymore
> Since 2017, browsers and most strict TLS clients (Java 11+, modern `curl`) **ignore the CN entirely** for hostname validation and only check the SAN list. A CSR generated without a `subjectAltName` extension will produce a certificate that fails hostname verification in most modern clients, even if the CN looks correct. This trips up more engineers than any other cert issue.

---

## 🛠️ Hands-on Lab (40 mins)

### Exercise 1 — Generate an RSA Private Key

```bash
mkdir -p ~/tls-lab && cd ~/tls-lab

# Generate a 2048-bit RSA private key
openssl genrsa -out server.key 2048

# Inspect it — confirm it's a valid RSA key and see the modulus
openssl rsa -in server.key -text -noout | head -20

# Lock down permissions — private keys should never be world-readable
chmod 600 server.key
ls -l server.key
```

### Exercise 2 — Generate a CSR with a Proper SAN Extension

Modern OpenSSL needs a small config snippet to embed SAN — the classic `-subj` flag alone doesn't carry SAN.

```bash
cat > csr.cnf << 'EOF'
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[dn]
CN = ace-prod-01.bank.internal
O  = AAIB
OU = Integration Engineering
C  = EG
ST = Giza
L  = Giza

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = ace-prod-01.bank.internal
DNS.2 = ace-prod-02.bank.internal
IP.1  = 10.20.30.40
EOF

openssl req -new -key server.key -out server.csr -config csr.cnf
```

### Exercise 3 — Verify the CSR Before Sending It Anywhere

```bash
# Decode and inspect the full CSR content
openssl req -in server.csr -text -noout

# Specifically confirm the SAN extension made it in — this is the #1 thing to check
openssl req -in server.csr -text -noout | grep -A1 "Subject Alternative Name"

# Confirm the CSR's self-signature is valid (proves you hold the private key)
openssl req -in server.csr -noout -verify
```

You should see `Subject Alternative Name: DNS:ace-prod-01.bank.internal, DNS:ace-prod-02.bank.internal, IP Address:10.20.30.40` and `verify OK`.

### Exercise 4 — Confirm Public Key Match Between Key and CSR

A frequent real-world failure: someone submits a CSR generated from a _different_ key than the one installed on the server. Catch this before it becomes a production incident.

```bash
# Hash the public key material from each artifact — they MUST match
openssl rsa -in server.key -pubout -outform der 2>/dev/null | openssl md5
openssl req -in server.csr -pubkey -noout -outform der 2>/dev/null | openssl md5
```

Identical MD5 output confirms the CSR was derived from this exact private key.

---

## ✅ Validation (5 mins)

You've proven this day's material if you can:

1. Generate a key and CSR from scratch and explain, out loud, why the CSR is self-signed rather than left unsigned.
2. Run `openssl req -in server.csr -text -noout` and correctly identify the SAN block versus the CN.
3. Explain why a certificate issued from a CSR with no SAN will fail hostname validation in a modern Java 11+ or curl client, even with a perfectly correct CN.
4. Use the MD5 public-key-match trick to prove a `.key` and `.csr` pair (or `.key` and `.crt` pair) belong together — this is the single fastest way to rule out "wrong key" as the cause of a keystore error.

> [!warning] Never Send the .key File Anywhere
> Only the `.csr` goes to the CA. If you ever find yourself about to email, Slack, or upload a `.key` file to a ticketing system, stop — that private key is now compromised and the certificate built from it should be considered burned once discovered.

---

## Key Takeaways

- A key pair is generated locally; only the public half (via the CSR) ever leaves the machine that will hold the private key.
- The CSR is self-signed by the requester to prove possession of the private key — the CA's signature appears only on the certificate it returns.
- SAN has effectively replaced CN for hostname validation in every modern TLS client — a CSR without SAN is a CSR that will cause production failures.
- RSA 2048 is the safe enterprise default; EC is faster and increasingly supported but verify compatibility with older Java/keystore tooling first.
- Matching public key hashes between `.key`, `.csr`, and eventual `.crt` is the fastest sanity check when a keystore error's root cause is unclear.

---

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-11-TLS-1.2-vs-1.3-Handshake]] | **Next:** [[Day-13-Self-Signed-Certificates]] →
