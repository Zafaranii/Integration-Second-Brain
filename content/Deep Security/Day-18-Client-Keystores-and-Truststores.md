---
tags: [security, bucket-2, mtls, keytool, keystore, day-18]
created: 2025-07-05
bucket: 2
week: 4
day: 18
status: not-started
prerequisites: ["Day-17-Building-a-Local-mTLS-Server"]
---

# Day 18 — Client Keystores & Truststores (Java/keytool)

> [!info] Why This Day Exists
> IBM ACE, API Connect, and most of the CP4I stack run on the JVM, which means TLS/mTLS configuration in practice usually means editing `.jks` or `.p12` files with `keytool`, not raw PEM files with OpenSSL. This is the day that connects everything you've learned about keys, certs, and chains to the actual file format and tooling you'll touch in a real IBM integration server's `server.conf.yaml` or an ACE security profile.

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-17-Building-a-Local-mTLS-Server]] | **Next:** [[Day-19-Kafka-mTLS-Basics]] →

---

## 🧠 Theory Block (15 mins)

### JKS vs PKCS12 — Two Container Formats

|                          | JKS                                 | PKCS12 (`.p12` / `.pfx`)                        |
| ------------------------ | ----------------------------------- | ----------------------------------------------- |
| Proprietary to           | Java (legacy Sun format)            | Industry standard (RSA PKCS#12), cross-platform |
| Can hold                 | Private keys + certs, or certs only | Private keys + certs, or certs only             |
| Modern Java default      | Deprecated as default since Java 9+ | **Default keystore type since Java 9**          |
| OpenSSL interoperability | Poor — needs conversion             | Native — OpenSSL reads/writes PKCS12 directly   |
| Recommendation           | Migrate away when possible          | Preferred for anything new                      |

Both formats can function as _either_ a keystore or a truststore — the distinction is purely about **what you choose to put inside**, not the file format itself. A "truststore.jks" is just a JKS file where every entry happens to be a `trustedCertEntry` (a bare certificate) rather than a `PrivateKeyEntry`.

### The Entry Types That Matter

```bash
keytool -list -v -keystore somefile.jks -storepass changeit
```

will show one of two entry types per alias:

| Entry type         | Contains                             | Belongs in                   |
| ------------------ | ------------------------------------ | ---------------------------- |
| `PrivateKeyEntry`  | Private key + its own cert (+ chain) | Keystore (identity)          |
| `trustedCertEntry` | A bare certificate, no private key   | Truststore (trust decisions) |

If you ever run `keytool -list` on what's supposed to be a truststore and see a `PrivateKeyEntry`, that's a real finding — a truststore should never contain private key material, and its presence there is an unnecessary exposure of identity material to anything that reads that "trust-only" file.

### Converting Between OpenSSL PEM and Java Keystore Formats

This is the bridge you'll cross constantly: a CA hands you PEM files, but your IBM ACE integration server config wants a `.jks` or `.p12`.

```
PEM key + cert  ──openssl pkcs12──►  .p12 bundle  ──keytool importkeystore──►  .jks
```

`.p12` is the natural intermediate format because OpenSSL can build one directly from PEM files, and `keytool` can both read `.p12` natively (as of modern Java, you can often even point ACE straight at a `.p12` without ever producing a `.jks` at all) and import from it into a `.jks` if the legacy format is specifically required.

### Alias Naming Discipline

Every entry in a keystore/truststore has an **alias** — a label used to reference it in application config. In enterprise environments with many certs rotating on different schedules, sloppy alias naming (`cert1`, `mykey`, `newcert2`) is a recurring source of "which one is actually being used" confusion. A convention like `<service>-<env>-<year>` (e.g. `ace-prod-2026`) pays for itself the first time a cert needs emergency rotation.

---

## 🛠️ Hands-on Lab (40 mins)

### Exercise 1 — Convert Your Lab PEM Files into a PKCS12 Keystore

```bash
cd ~/tls-lab/ca

# Bundle the leaf key + cert + chain into a PKCS12 keystore
openssl pkcs12 -export \
  -in leaf-fullchain.crt \
  -inkey leaf.key \
  -name "ace-lab-2026" \
  -out server-identity.p12 \
  -passout pass:changeit
```

### Exercise 2 — Inspect It with keytool

```bash
keytool -list -v -keystore server-identity.p12 -storetype PKCS12 -storepass changeit
```

Confirm: `Entry type: PrivateKeyEntry`, alias `ace-lab-2026`, and a certificate chain length matching leaf + intermediate.

### Exercise 3 — Convert PKCS12 to a Legacy JKS (When Explicitly Required)

```bash
keytool -importkeystore \
  -srckeystore server-identity.p12 -srcstoretype PKCS12 -srcstorepass changeit \
  -destkeystore server-identity.jks -deststoretype JKS -deststorepass changeit
```

```bash
# Confirm the alias and entry type survived the conversion intact
keytool -list -v -keystore server-identity.jks -storepass changeit | grep -E "Alias name|Entry type"
```

### Exercise 4 — Build a Proper Truststore Containing Only the Root CA

```bash
keytool -importcert -alias lab-root-ca \
  -file root-ca.crt \
  -keystore lab-truststore.p12 -storetype PKCS12 -storepass changeit -noprompt

# Confirm — must show trustedCertEntry, and MUST NOT show any PrivateKeyEntry
keytool -list -v -keystore lab-truststore.p12 -storetype PKCS12 -storepass changeit | grep -E "Alias name|Entry type"
```

### Exercise 5 — Build the Client-Side Identity Keystore for mTLS

```bash
openssl pkcs12 -export \
  -in client.crt -inkey client.key \
  -name "integration-client-01" \
  -out client-identity.p12 -passout pass:changeit

keytool -list -v -keystore client-identity.p12 -storetype PKCS12 -storepass changeit | grep -E "Alias name|Entry type"
```

### Exercise 6 — End-to-End: Point a Real Java mTLS Client at Your Lab Server

```bash
cd ~/tls-lab/ca/mtls-app
python3 mtls_server.py &
SERVER_PID=$!
sleep 1

# Use keytool-managed stores with curl's openssl-engine equivalent isn't native,
# so demonstrate the equivalent PEM extraction FROM the keystore (a common real-world need):
keytool -importkeystore -srckeystore ../client-identity.p12 -srcstoretype PKCS12 -srcstorepass changeit \
  -destkeystore /tmp/verify.p12 -deststoretype PKCS12 -deststorepass changeit
openssl pkcs12 -in /tmp/verify.p12 -nodes -passin pass:changeit | openssl x509 -noout -subject

kill $SERVER_PID
```

This final round-trip (PEM → PKCS12 via OpenSSL → verify via keytool → back to PEM via OpenSSL) is exactly the kind of format-hopping you'll do when a partner hands you a `.jks` but your validation tooling only speaks OpenSSL, or vice versa.

---

## ✅ Validation (5 mins)

You've proven this day's material if you can:

1. Build a PKCS12 keystore from PEM files with `openssl pkcs12 -export` and correctly list its contents with `keytool -list -v`.
2. Explain the difference between `PrivateKeyEntry` and `trustedCertEntry` and identify why finding the former in a truststore is a security finding.
3. Convert a PKCS12 keystore to legacy JKS and confirm the alias and chain length are unchanged after conversion.
4. Round-trip a certificate from PEM → PKCS12 → back to PEM and confirm the subject is unchanged, demonstrating you can bridge OpenSSL-world and Java-world tooling in either direction.

---

## Key Takeaways

- JKS and PKCS12 are both containers that can hold either identity (private key + cert) or trust (bare certs) material — the format doesn't dictate the role, the contents do.
- PKCS12 is the modern default and the natural bridge format between OpenSSL's PEM world and Java's keystore world.
- `keytool -list -v` and checking `Entry type` is the fastest way to confirm whether a file is safely a pure truststore or accidentally contains private key material.
- Disciplined alias naming (service-env-year) prevents "which cert is actually active" confusion during rotation — a real operational cost, not just tidiness.

---

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-17-Building-a-Local-mTLS-Server]] | **Next:** [[Day-19-Kafka-mTLS-Basics]] →
