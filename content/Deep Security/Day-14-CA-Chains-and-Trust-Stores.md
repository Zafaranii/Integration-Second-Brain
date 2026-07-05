---
tags: [security, bucket-2, tls, ca-chain, truststore, day-14]
created: 2025-07-05
bucket: 2
week: 3
day: 14
status: not-started
prerequisites: ["Day-13-Self-Signed-Certificates"]
---

# Day 14 — CA Chains and Trust Stores

> [!info] Why This Day Exists
> "unable to get local issuer certificate" and "PKIX path building failed" are two of the most common errors in every integration engineer's career, and both come down to one thing: an incomplete chain or an incomplete truststore. This is the theory that turns those errors from a support ticket into a two-minute `openssl verify` fix.

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-13-Self-Signed-Certificates]] | **Next:** [[Day-15-SNI-and-Week-3-Wrapup]] →

---

## 🧠 Theory Block (15 mins)

### The Chain of Trust

Real-world certificates are almost never signed directly by a root CA. Instead there's a chain:

```
Root CA certificate            (self-signed, pre-installed in OS/browser/truststore)
      │  signs
      ▼
Intermediate CA certificate    (issued by root, does the actual day-to-day signing)
      │  signs
      ▼
Leaf / server certificate      (your ace-prod-01.bank.internal cert)
```

Root CAs keep their private keys offline in vaults precisely because compromising a root is catastrophic — it can forge trust for anything. Intermediates are the ones actually online and signing customer certificates day to day, so a compromised intermediate can be revoked without invalidating the entire root's trust.

### Why "Incomplete Chain" Is the #1 Real-World Error

A server only needs to present its **leaf certificate** to establish a working TLS connection — but the _client_ needs the full path from leaf up to a root it already trusts, in order to verify it. If the server doesn't send the intermediate cert(s) along with the leaf, most clients cannot build that path themselves.

```
Server sends:  [Leaf]                          ← incomplete!
Client has:    [Root CA] (in OS truststore)
Client needs:  [Leaf] → [Intermediate] → [Root]  ← the gap is the intermediate
```

Browsers often work anyway because they cache intermediates seen on other sites or fetch them via AIA (Authority Information Access) extensions — but strict clients like Java's default `HttpsURLConnection`, most CLI tools, mobile apps, and IBM ACE's HTTP nodes will **fail immediately** with exactly this error. This is why a cert that "works fine in Chrome" can still break your ACE flow — Chrome is being more forgiving than your middleware is.

### Certificate Order Matters

When bundling a chain into one file, the order is always **leaf-first, root-last** (root itself is often omitted since the client should already have it):

```
-----BEGIN CERTIFICATE-----
... leaf/server cert ...
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
... intermediate cert ...
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
... (optional) root cert ...
-----END CERTIFICATE-----
```

### Truststores vs Keystores — the Distinction That Trips Everyone Up

|                       | Keystore                                            | Truststore                                                       |
| --------------------- | --------------------------------------------------- | ---------------------------------------------------------------- |
| Contains              | Your own private key + your own cert                | Other parties' (usually CA) certs only                           |
| Answers the question  | "Who am I, and can I prove it?"                     | "Who do I trust when _they_ claim an identity?"                  |
| Used during handshake | Server presents its keystore cert to the client     | Client checks the presented cert against its truststore          |
| In IBM ACE terms      | The server-side identity cert for an HTTPS Listener | The set of CAs ACE trusts when calling an outbound HTTPS backend |

A single `.jks` or `.p12` file can technically hold both roles' worth of entries, but treating them as conceptually separate is what prevents mistakes — a truststore should **never** contain a private key.

### PKIX Path Validation, Simplified

When a client validates a chain, it walks it end to end checking:

1. Each certificate's signature was made by the **next** certificate's public key up the chain.
2. Every certificate is within its validity window (`notBefore` / `notAfter`).
3. None of the certificates are revoked (via CRL or OCSP).
4. The final certificate in the path is a **root the client already trusts**.

Any single failure anywhere in that chain — an expired intermediate, a revoked cert, an untrusted root — fails the _entire_ connection, even if the leaf cert itself is perfectly valid.

---

## 🛠️ Hands-on Lab (40 mins)

### Exercise 1 — Inspect a Real Chain from a Live Server

```bash
# Fetch the full chain a real server presents
openssl s_client -connect github.com:443 -showcerts < /dev/null 2>/dev/null > /tmp/github_chain.txt

# Count how many certificates were actually sent
grep -c "BEGIN CERTIFICATE" /tmp/github_chain.txt

# Show the subject/issuer of each cert in the chain, in order
openssl s_client -connect github.com:443 -showcerts < /dev/null 2>/dev/null | \
  awk '/BEGIN CERT/,/END CERT/{print > "/tmp/cert" NR ".pem"}'  # (simplified — see next step for clean extraction)
```

Cleaner extraction into individual files:

```bash
csplit -z -f /tmp/chain_cert_ -b '%02d.pem' /tmp/github_chain.txt '/-----BEGIN CERTIFICATE-----/' '{*}' 2>/dev/null
for f in /tmp/chain_cert_*.pem; do
  echo "--- $f ---"
  openssl x509 -in "$f" -noout -subject -issuer 2>/dev/null
done
```

### Exercise 2 — Build Your Own Two-Tier CA and Sign a Leaf Cert

```bash
mkdir -p ~/tls-lab/ca && cd ~/tls-lab/ca

# 1. Create a root CA (self-signed)
openssl genrsa -out root-ca.key 4096
openssl req -x509 -new -key root-ca.key -sha256 -days 3650 -out root-ca.crt \
  -subj "/CN=Lab Root CA/O=Lab/C=EG"

# 2. Create an intermediate CA, signed by the root
openssl genrsa -out intermediate.key 4096
openssl req -new -key intermediate.key -out intermediate.csr -subj "/CN=Lab Intermediate CA/O=Lab/C=EG"
openssl x509 -req -in intermediate.csr -CA root-ca.crt -CAkey root-ca.key \
  -CAcreateserial -out intermediate.crt -days 1825 -sha256 \
  -extfile <(echo "basicConstraints=CA:TRUE,pathlen:0")

# 3. Create a leaf server cert, signed by the intermediate
openssl genrsa -out leaf.key 2048
openssl req -new -key leaf.key -out leaf.csr -subj "/CN=myserver.lab.internal/O=Lab/C=EG"
openssl x509 -req -in leaf.csr -CA intermediate.crt -CAkey intermediate.key \
  -CAcreateserial -out leaf.crt -days 365 -sha256 \
  -extfile <(echo "subjectAltName=DNS:myserver.lab.internal")

# 4. Build the leaf-first chain bundle
cat leaf.crt intermediate.crt > leaf-fullchain.crt
```

### Exercise 3 — Prove Verification Fails Without the Intermediate, Succeeds With It

```bash
# Attempt verification using ONLY the root as trust anchor, and ONLY the leaf cert — should FAIL
openssl verify -CAfile root-ca.crt leaf.crt

# Now verify using the leaf + intermediate chain against the root — should SUCCEED
openssl verify -CAfile root-ca.crt -untrusted intermediate.crt leaf.crt
```

The first command reproduces "unable to get local issuer certificate" in miniature. The second shows exactly what fixes it: supplying the missing link.

### Exercise 4 — Build a Java Truststore Containing Only Your Root CA

```bash
keytool -importcert -alias lab-root-ca -file root-ca.crt \
  -keystore lab-truststore.jks -storepass changeit -noprompt

# Confirm what's inside — should show ONLY the CA, no private key
keytool -list -v -keystore lab-truststore.jks -storepass changeit | grep -E "Alias name|Entry type"
```

`Entry type: trustedCertEntry` confirms this is a pure truststore — no private key present, exactly as it should be.

---

## ✅ Validation (5 mins)

You've proven this day's material if you can:

1. Reproduce "unable to get local issuer certificate" on purpose using `openssl verify` with a missing intermediate, then fix it with `-untrusted`.
2. Explain why a browser can succeed against a server that a Java client fails against, using the same certificate.
3. State the leaf-first ordering rule for chain bundles from memory.
4. Explain the keystore/truststore distinction in one sentence each, without conflating them.

---

## Key Takeaways

- Root CAs sign intermediates; intermediates sign leaf certs — roots stay offline, intermediates do the daily signing.
- The server must send the full chain (leaf + intermediates); clients like Java and CLI tools won't fetch missing intermediates the way forgiving browsers sometimes do.
- Chain bundle order is always leaf-first, root-last (root often omitted).
- Keystores answer "who am I" (private key + own cert); truststores answer "who do I trust" (CA certs only, never a private key).
- A single broken link anywhere in the chain — expired, revoked, or untrusted root — fails the whole connection regardless of leaf cert validity.

---

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-13-Self-Signed-Certificates]] | **Next:** [[Day-15-SNI-and-Week-3-Wrapup]] →
