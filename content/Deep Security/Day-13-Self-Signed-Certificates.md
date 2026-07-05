---
tags: [security, bucket-2, tls, self-signed, day-13]
created: 2025-07-05
bucket: 2
week: 3
day: 13
status: not-started
prerequisites: ["Day-12-Private-Keys-and-CSRs-OpenSSL"]
---

# Day 13 — Self-Signed Certificates

> [!info] Why This Day Exists
> Every local dev environment, every internal-only CP4I test namespace, and every "just get something working before the real cert arrives" moment needs a self-signed cert. Understanding exactly what a self-signed cert is — and isn't — protecting against is what stops you from either (a) accidentally shipping one to production, or (b) being needlessly afraid of one in a lab environment.

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-12-Private-Keys-and-CSRs-OpenSSL]] | **Next:** [[Day-14-CA-Chains-and-Trust-Stores]] →

---

## 🧠 Theory Block (15 mins)

### What "Self-Signed" Actually Means

A self-signed certificate is one where the **issuer and subject are the same entity** — the private key that signs the certificate is the same private key whose matching public key is inside it.

```
Normal (CA-signed):                     Self-signed:
┌────────────────┐                     ┌────────────────┐
│ Issuer: DigiCert │                     │ Issuer: MyServer │
│ Subject: myapp    │  signed by         │ Subject: MyServer│  signed by
│ Signature: DigiCert's│ DigiCert's       │ Signature: MyServer's│ MyServer's
│   private key      │ private key       │   own private key     │ OWN private key
└────────────────┘                     └────────────────┘
```

### What This Buys You (and What It Doesn't)

| Property                                       | Self-signed cert                                        | CA-signed cert                          |
| ---------------------------------------------- | ------------------------------------------------------- | --------------------------------------- |
| Encrypts the channel                           | ✅ Yes — TLS still negotiates a session key             | ✅ Yes                                  |
| Proves server identity to a stranger           | ❌ No — anyone can generate one claiming to be anything | ✅ Yes — CA vetted the identity         |
| Trusted by browsers/clients out of the box     | ❌ No — triggers "not trusted" warnings                 | ✅ Yes, if a known root CA              |
| Susceptible to MITM if attacker swaps the cert | ⚠️ Yes, unless the client pins the exact cert           | ⚠️ Only if the CA itself is compromised |
| Appropriate for                                | Local dev, internal lab, testing pipelines              | Anything a third party must trust       |

The critical misunderstanding to avoid: **encryption and authentication are two separate guarantees.** A self-signed cert still encrypts the TCP stream just as strongly as a CA-signed one using the same cipher suite. What it _fails_ to do is let the client cryptographically prove "this server really is who it claims to be," because there's no independent, previously-trusted third party vouching for it. A man-in-the-middle can trivially generate their _own_ self-signed cert and present it instead — the client has no way to tell the difference unless it already knows exactly which cert (or CA) to expect.

### Where Self-Signed Certs Legitimately Belong in Your Stack

- Local ACE integration server testing before a real cert is issued
- Internal CP4I/OpenShift dev namespaces not exposed externally
- The two `GlobalCacheA`/`GlobalCacheB` replication listeners in a lab, before hardening
- Any scenario where you fully control **both ends** and can manually distribute the exact public cert to the truststore on the other side (this is the escape hatch that makes self-signed usable safely — see Day 14)

### Where They Do Not Belong

Anything a third party (a partner bank, a mobile app, a public API consumer) connects to. If they must trust it without manual cert distribution, you need a CA — public or internal.

---

## 🛠️ Hands-on Lab (40 mins)

### Exercise 1 — Generate a Self-Signed Certificate in One Step

```bash
cd ~/tls-lab

# Generate key + self-signed cert together, valid 365 days, with SAN
openssl req -x509 -newkey rsa:2048 -keyout selfsigned.key -out selfsigned.crt \
  -days 365 -nodes \
  -subj "/CN=localhost/O=Lab/OU=Testing/C=EG" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
```

`-x509` tells OpenSSL to output a self-signed certificate directly instead of a CSR — it signs the cert with the same key it just generated.

### Exercise 2 — Verify the Self-Signature

```bash
# Confirm issuer == subject
openssl x509 -in selfsigned.crt -noout -issuer -subject

# Verify the cert's signature against its own embedded public key
openssl verify -CAfile selfsigned.crt selfsigned.crt
```

You should see identical issuer/subject lines, and `verify` should print `selfsigned.crt: OK` — because you told it to trust exactly this file as its own root.

### Exercise 3 — Stand Up a Local HTTPS Server and Observe the Trust Failure

```bash
# Serve a directory over HTTPS using the self-signed cert
openssl s_server -accept 8443 -cert selfsigned.crt -key selfsigned.key -www &

# Connect WITHOUT trusting the cert — observe the failure
curl -v https://localhost:8443/ 2>&1 | grep -E "SSL certificate problem|self.signed"
```

Expect: `SSL certificate problem: self-signed certificate`. This is curl correctly refusing to trust an unknown issuer — exactly the behavior a mobile app or partner system would show against your lab server.

### Exercise 4 — Deliberately Trust It, Then Reconnect

```bash
# Explicitly tell curl to trust THIS specific cert
curl -v --cacert selfsigned.crt https://localhost:8443/ 2>&1 | grep -E "SSL connection|HTTP/"

# Compare against the insecure escape hatch (never use in real diagnostics beyond a quick check)
curl -k -v https://localhost:8443/ 2>&1 | grep "HTTP/"

kill %1
```

`--cacert selfsigned.crt` is the correct pattern: you're not disabling verification, you're telling the client exactly which authority to trust, which is precisely how a real internal-lab trust relationship is built manually (this is the seed of Day 14's truststore concept).

---

## ✅ Validation (5 mins)

You've proven this day's material if you can:

1. Generate a self-signed cert in a single `openssl req -x509` command and correctly explain what `-x509` changes versus a plain `-new` CSR command.
2. Articulate, without hedging, that a self-signed cert encrypts exactly as strongly as a CA-signed one but provides no independent identity guarantee.
3. Reproduce the `curl` trust failure and then fix it with `--cacert`, explaining why `-k` is a debugging shortcut and not a real fix.
4. Name one place in your own stack (lab GlobalCacheA/B, a local ACE test server) where a self-signed cert is the _correct_ choice, and one place where it would be a security incident.

---

## Key Takeaways

- Self-signed = issuer and subject are the same key; encryption strength is unaffected, but there is no third-party identity guarantee.
- The failure mode isn't "weak encryption" — it's that an attacker can present their own self-signed cert and the client can't distinguish it from the real one without already knowing what to expect.
- `curl --cacert <file>` (explicitly trusting one specific cert) is the correct pattern for legitimate self-signed use — `-k` is a diagnostic shortcut, never a fix.
- Self-signed certs are appropriate exactly where you control both ends and can manually distribute the public cert — internal labs, local dev, controlled test environments.

---

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-12-Private-Keys-and-CSRs-OpenSSL]] | **Next:** [[Day-14-CA-Chains-and-Trust-Stores]] →
