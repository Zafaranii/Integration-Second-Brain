---
tags: [security, bucket-2, cryptography, hashing, signing, day-21]
created: 2025-07-05
bucket: 2
week: 5
day: 21
status: not-started
prerequisites: ["Day-20-mTLS-Debugging"]
---

# Day 21 — Hashing vs Encryption vs Signing

> [!info] Why This Day Exists
> These three words get used interchangeably in casual conversation and that sloppiness causes real design mistakes — "let's hash the password to protect it" (correct), "let's encrypt the password so we can check it later" (usually wrong), "let's sign the payload to keep it secret" (category error — signing doesn't hide anything). Today draws the exact boundaries.

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-20-mTLS-Debugging]] | **Next:** [[Day-22-Generating-Digital-Signatures]] →

---

## 🧠 Theory Block (15 mins)

### The Three Operations, Precisely Defined

| Operation      | Direction                      | Key needed?                                          | Guarantees                                                                    |
| -------------- | ------------------------------ | ---------------------------------------------------- | ----------------------------------------------------------------------------- |
| **Hashing**    | One-way, irreversible          | None                                                 | Integrity / fingerprinting — "has this data changed?"                         |
| **Encryption** | Two-way, reversible            | Yes (symmetric or asymmetric)                        | Confidentiality — "can only the intended party read this?"                    |
| **Signing**    | One-way generation, verifiable | Yes (asymmetric — private to sign, public to verify) | Authenticity + integrity — "did the claimed sender produce this, unmodified?" |

### Hashing — Fingerprints, Not Secrets

A hash function (SHA-256, SHA-3) takes arbitrary-length input and produces a fixed-length output. It is **deterministic** (same input always produces the same output) and **one-way** (you cannot recover the input from the output). Its purpose is proving data integrity, not hiding data.

```
"hello world"  ──SHA-256──►  b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde
```

Change one character and the entire output changes unpredictably (the **avalanche effect**) — this is what makes hashing useful for detecting tampering: compare the hash of received data against an expected hash, and any modification, however small, is immediately obvious.

> [!warning] Hashing Passwords Requires More Than a Bare Hash Function
> A raw `SHA-256(password)` is fast to compute — which is exactly the wrong property for password storage, because it makes brute-force and rainbow-table attacks cheap. Password storage needs a **slow, salted** algorithm purpose-built for this (bcrypt, scrypt, Argon2), which deliberately makes each guess expensive. Plain SHA-256/SHA-1/MD5 on passwords is a well-known anti-pattern, not a shortcut.

### Encryption — Confidentiality, Reversible by Design

Encryption transforms plaintext into ciphertext such that only someone holding the correct key can reverse it back to plaintext.

```
Symmetric:                              Asymmetric:
   same key encrypts & decrypts            public key encrypts, private key decrypts
   (AES)                                   (RSA, ECIES)
   fast, but key must be shared safely     slower, but solves key-distribution problem
```

In practice, TLS uses **both**: an asymmetric handshake (Days 11–20) to safely agree on a random symmetric key, then fast symmetric encryption (AES-GCM) for the actual bulk data — asymmetric crypto is too slow to encrypt an entire HTTP response or Kafka message stream directly.

### Signing — Authenticity Without Confidentiality

Signing uses the **inverse** key relationship from encryption: the **private** key produces a signature, and the corresponding **public** key verifies it. Signing does not hide the original message at all — the message can travel in plaintext right alongside its signature. What signing proves is: "the holder of this private key produced this exact signature over this exact data, and the data hasn't been altered since."

```
Sign:    hash(message) → encrypt-with-PRIVATE-key → signature
Verify:  decrypt-signature-with-PUBLIC-key → compare against hash(received message)
```

(This is a simplification — real signature schemes like RSA-PSS or ECDSA are more involved than literally "encrypt the hash," but the directional key relationship — private signs, public verifies — is exactly right and is the important mental model.)

### The Matrix That Prevents Confusion

| Need                                                       | Use                               | NOT                                                                |
| ---------------------------------------------------------- | --------------------------------- | ------------------------------------------------------------------ |
| "Has this file been tampered with?"                        | Hash + compare                    | Encryption (doesn't detect tampering by itself)                    |
| "Can only the recipient read this?"                        | Encryption                        | Hashing (irreversible — recipient couldn't read it either)         |
| "Did this really come from who it claims, unaltered?"      | Signing                           | Hashing alone (proves integrity, not who produced it)              |
| "Store a password for later login checks"                  | Slow salted hash (bcrypt/Argon2)  | Encryption (reversible = a risk if the key leaks) or a fast hash   |
| "Send a Kafka message only the intended consumer can read" | Encryption (e.g. field-level AES) | Signing alone (doesn't hide the payload)                           |
| "Prove a JWT wasn't modified after issuance"               | Signing (JWS)                     | Encryption (a JWS is not secret, just tamper-evident) — see Day 23 |

---

## 🛠️ Hands-on Lab (40 mins)

### Exercise 1 — Observe the Avalanche Effect

```bash
echo -n "hello world" | openssl dgst -sha256
echo -n "hello worle" | openssl dgst -sha256   # one character different
```

The two outputs share nothing recognizable in common, despite a one-character input difference — this is the property that makes hashing useful for tamper detection.

### Exercise 2 — Demonstrate Why a Bare Fast Hash Is Wrong for Passwords

```bash
# Time how fast SHA-256 can be brute-forced on a small keyspace — illustrative only
time for i in $(seq 1 100000); do echo -n "password$i" | openssl dgst -sha256 > /dev/null; done
```

Note the elapsed time for 100,000 attempts — then contrast conceptually with bcrypt/Argon2, which are deliberately designed to make each single attempt take milliseconds rather than microseconds, making the same brute-force sweep orders of magnitude more expensive.

### Exercise 3 — Symmetric Encryption Round-Trip (Confidentiality, Reversible)

```bash
# Encrypt with AES-256-GCM using a passphrase-derived key
echo "sensitive banking payload" > plaintext.txt
openssl enc -aes-256-gcm -pbkdf2 -salt -in plaintext.txt -out ciphertext.bin -pass pass:MySecretPass123

# Confirm it's unreadable
cat ciphertext.bin | strings

# Decrypt it back — reversibility, the defining trait of encryption
openssl enc -d -aes-256-gcm -pbkdf2 -in ciphertext.bin -out decrypted.txt -pass pass:MySecretPass123
diff plaintext.txt decrypted.txt && echo "MATCH — encryption is reversible with the right key"
```

### Exercise 4 — Signing Round-Trip (Authenticity, Not Confidentiality)

```bash
cd ~/tls-lab

# Sign the plaintext with your PRIVATE key
openssl dgst -sha256 -sign server.key -out signature.bin plaintext.txt

# The message itself remains PLAINTEXT and readable — signing didn't hide it
cat plaintext.txt

# Anyone with the PUBLIC key can verify authenticity + integrity
openssl x509 -pubkey -noout -in selfsigned.crt > pubkey.pem 2>/dev/null || openssl rsa -in server.key -pubout -out pubkey.pem
openssl dgst -sha256 -verify pubkey.pem -signature signature.bin plaintext.txt
```

Expect `Verified OK`. Now tamper with the file and re-verify:

```bash
echo "extra byte" >> plaintext.txt
openssl dgst -sha256 -verify pubkey.pem -signature signature.bin plaintext.txt
```

Expect `Verification Failure` — proving the signature is tamper-evident even though the message was never encrypted.

---

## ✅ Validation (5 mins)

You've proven this day's material if you can:

1. State, without hedging, that hashing is one-way, encryption is two-way, and signing uses the private/public key pair in the _opposite_ direction from encryption.
2. Explain in one sentence why raw SHA-256 is inappropriate for password storage and name a correct alternative (bcrypt/scrypt/Argon2).
3. Complete the symmetric encryption round-trip and the signature round-trip labs, and clearly show that a tampered signed message fails verification while remaining fully readable throughout.
4. Correctly place a real requirement (e.g. "verify this webhook payload wasn't altered in transit") into the matrix — signing, not encryption or bare hashing.

---

## Key Takeaways

- Hashing proves integrity via a one-way fingerprint; it cannot be reversed and was never meant to hide anything.
- Encryption is reversible confidentiality — the whole point is that someone with the right key can get the original data back.
- Signing inverts the key roles from encryption (private key signs, public key verifies) and proves authenticity + integrity without ever hiding the underlying message.
- Password storage specifically needs slow, salted hashing (bcrypt/Argon2) — a bare fast hash function is a known anti-pattern, not a lighter-weight shortcut.

---

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-20-mTLS-Debugging]] | **Next:** [[Day-22-Generating-Digital-Signatures]] →
