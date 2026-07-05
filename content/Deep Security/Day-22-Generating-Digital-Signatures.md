---
tags: [security, bucket-2, cryptography, signatures, day-22]
created: 2025-07-05
bucket: 2
week: 5
day: 22
status: not-started
prerequisites: ["Day-21-Hashing-vs-Encryption-vs-Signing"]
---

# Day 22 — Generating Digital Signatures

> [!info] Why This Day Exists
> Day 21 covered signing conceptually. Today goes one level deeper into how a real signature is constructed (padding schemes, why RSA needs them, ECDSA's different mechanics) and gives you enough hands-on practice to debug "signature verification failed" errors in webhook validation, JWS tokens (Day 23), or partner API payload signing — a very common requirement in banking API integrations.

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-21-Hashing-vs-Encryption-vs-Signing]] | **Next:** [[Day-23-JWT-and-JWS-Basics]] →

---

## 🧠 Theory Block (15 mins)

### What Actually Happens Inside `openssl dgst -sign`

```
1. Compute hash(message)                      — e.g. SHA-256, fixed-length digest
2. Apply a padding scheme to the digest        — RSA needs this; ECDSA doesn't
3. Raise the padded value to the private       — the actual asymmetric "signing" math
   key's exponent (RSA) / compute (r,s)
   values via elliptic curve math (ECDSA)
4. Output: the signature bytes
```

The hash step is not optional flavor — it exists because RSA/ECDSA signing math operates on fixed-size numeric blocks, and real messages are arbitrary length. Hashing first also means the actual cryptographic operation is fast regardless of message size — you're always signing a fixed 32-byte (SHA-256) digest, whether the original message is 10 bytes or 10 gigabytes.

### RSA Signatures Need a Padding Scheme

| Padding scheme                       | Status                                                                                        |
| ------------------------------------ | --------------------------------------------------------------------------------------------- |
| PKCS#1 v1.5                          | Older, deterministic, still extremely widely used and supported everywhere                    |
| PSS (Probabilistic Signature Scheme) | Modern, includes randomness in the padding, provably more resistant to certain attack classes |

`openssl dgst -sign` defaults to PKCS#1 v1.5 unless you explicitly request PSS. When integrating with a partner's API signature requirements, the padding scheme is exactly the kind of detail that must match precisely — a signature generated with PSS will **not** verify against code expecting PKCS#1 v1.5, even though both are "RSA signatures using SHA-256."

```bash
# Explicit PSS example (contrast with the default PKCS#1 v1.5 in the lab below)
openssl dgst -sha256 -sign key.pem -sigopt rsa_padding_mode:pss -out sig.bin message.txt
```

### ECDSA — Different Math, Same Guarantee

ECDSA (Elliptic Curve Digital Signature Algorithm) produces a signature as a pair of numbers `(r, s)` derived from elliptic curve point arithmetic, rather than RSA's modular exponentiation. For equivalent security strength, ECDSA keys and signatures are dramatically smaller than RSA's (a 256-bit EC key ≈ a 3072-bit RSA key in strength), which is why ECDSA dominates in high-throughput or bandwidth-constrained signing scenarios (this is also why `ES256` is a common JWT algorithm choice — Day 23).

> [!warning] ECDSA Needs a Good Random Nonce Every Single Time
> ECDSA signing requires a fresh, unpredictable random value (the nonce, `k`) for every signature. If the same `k` is ever reused across two different signatures from the same private key, an attacker can mathematically recover the private key itself from the two signatures — this is exactly what happened in several real-world Bitcoin wallet and Sony PS3 firmware key compromises. Deterministic ECDSA (RFC 6979) eliminates this risk by deriving `k` deterministically from the message and key rather than trusting a random number generator — modern libraries increasingly default to it, but it's worth knowing why the requirement exists.

### Signature Verification Is Asymmetric in Effort, Not Just in Keys

Verification (using the public key) is a completely independent computation from signing — it does **not** involve re-deriving or reversing the private key operation. The verifier recomputes `hash(received message)` and checks that the signature, combined with the public key, is mathematically consistent with that hash. Any change to the message, the signature bytes, or use of the wrong public key produces a clean, unambiguous failure — there's no "partially valid" signature.

---

## 🛠️ Hands-on Lab (40 mins)

### Exercise 1 — Sign and Verify with Explicit PKCS#1 v1.5 vs PSS

```bash
cd ~/tls-lab
echo '{"amount": 500, "currency": "EGP", "ref": "TXN-2026-001"}' > payload.json

# Default (PKCS#1 v1.5)
openssl dgst -sha256 -sign server.key -out sig_pkcs1.bin payload.json
openssl rsa -in server.key -pubout -out pubkey.pem 2>/dev/null

openssl dgst -sha256 -verify pubkey.pem -signature sig_pkcs1.bin payload.json

# Explicit PSS
openssl dgst -sha256 -sign server.key -sigopt rsa_padding_mode:pss -out sig_pss.bin payload.json
openssl dgst -sha256 -verify pubkey.pem -sigopt rsa_padding_mode:pss -signature sig_pss.bin payload.json
```

### Exercise 2 — Prove Padding Scheme Mismatch Fails Verification

```bash
# Try verifying a PSS signature as if it were PKCS#1 v1.5 (the default expectation)
openssl dgst -sha256 -verify pubkey.pem -signature sig_pss.bin payload.json
```

Expect `Verification Failure` — this reproduces, in isolation, the exact class of bug that occurs when two systems disagree on padding scheme despite both being "correct RSA-SHA256."

### Exercise 3 — Generate and Use an EC Key for Signing

```bash
# Generate an EC key on the P-256 curve (matches ES256 in JWT terms — Day 23)
openssl ecparam -name prime256v1 -genkey -noout -out ec-key.pem
openssl ec -in ec-key.pem -pubout -out ec-pubkey.pem

openssl dgst -sha256 -sign ec-key.pem -out ec-sig.bin payload.json
openssl dgst -sha256 -verify ec-pubkey.pem -signature ec-sig.bin payload.json
```

### Exercise 4 — Compare Signature and Key Sizes Directly

```bash
echo "RSA 2048 signature size:"; wc -c < sig_pkcs1.bin
echo "EC P-256 signature size:"; wc -c < ec-sig.bin

echo "RSA public key size:"; wc -c < pubkey.pem
echo "EC public key size:"; wc -c < ec-pubkey.pem
```

Confirm the EC artifacts are meaningfully smaller for comparable real-world security strength — the practical reason EC is favored in bandwidth- or storage-sensitive signing contexts (mobile clients, high-volume token issuance).

### Exercise 5 — Confirm Tamper Detection on Both Algorithms

```bash
cp payload.json payload_tampered.json
sed -i 's/500/5000/' payload_tampered.json

echo "RSA verify against tampered payload:"
openssl dgst -sha256 -verify pubkey.pem -signature sig_pkcs1.bin payload_tampered.json

echo "EC verify against tampered payload:"
openssl dgst -sha256 -verify ec-pubkey.pem -signature ec-sig.bin payload_tampered.json
```

Both must report `Verification Failure` — a one-digit change in a JSON payload is enough to invalidate either signature type.

---

## ✅ Validation (5 mins)

You've proven this day's material if you can:

1. Explain why signing always hashes the message first rather than signing the raw bytes directly.
2. Reproduce a padding-scheme mismatch (PSS signature verified as PKCS#1 v1.5) and correctly diagnose it as a scheme mismatch, not a broken key or corrupted signature.
3. Generate and use an EC key pair for signing and explain, with real numbers from your own lab, why EC signatures/keys are smaller than RSA's for comparable security.
4. State the ECDSA nonce-reuse risk from memory and name the mitigation (RFC 6979 deterministic nonces).

---

## Key Takeaways

- Signing always hashes first, then applies asymmetric math to the fixed-size digest — this is what makes signing performance independent of message size.
- RSA signatures require an explicit padding scheme (PKCS#1 v1.5 or PSS); mismatched schemes between signer and verifier cause clean, hard-to-diagnose verification failures despite both being "valid RSA-SHA256."
- ECDSA achieves equivalent security with much smaller keys/signatures than RSA, at the cost of requiring a fresh unpredictable nonce per signature — nonce reuse is catastrophic and has caused real-world private key recovery incidents.
- Signature verification either cleanly succeeds or cleanly fails — there is no partial validity, which is exactly the tamper-evidence guarantee signing is meant to provide.

---

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-21-Hashing-vs-Encryption-vs-Signing]] | **Next:** [[Day-23-JWT-and-JWS-Basics]] →
