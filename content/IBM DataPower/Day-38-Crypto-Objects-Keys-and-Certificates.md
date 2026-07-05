---
tags: [datapower, bucket-3, security, crypto, day-38]
created: 2026-07-05
bucket: 3
week: 8
day: 38
status: not-started
---

# Day 38 — Crypto Objects: Keys and Certificates

> [!info] Why This Day Exists
> Every TLS handshake and every mTLS-based AAA policy (Day 36) ultimately depends on a small set of crypto object types being correctly wired together. Getting the Key/Certificate/Identification/Validation object relationships straight is the prerequisite for Day 39's TLS profiles.

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-39-TLS-Profiles-and-SSL-Proxy]] →

---

## Theory

### The Four Core Crypto Object Types

| Object                    | Class               | Purpose                                                                                                      |
| ------------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------ |
| Crypto Key                | `CryptoKey`         | A private key, referencing a key file (typically PEM, stored under `cert:///`)                               |
| Crypto Certificate        | `CryptoCertificate` | A public certificate, referencing a cert file                                                                |
| Identification Credential | `CryptoIdentCred`   | Pairs a `CryptoKey` + `CryptoCertificate` together — this is "my identity" for presenting during a handshake |
| Validation Credential     | `CryptoValCred`     | A set of trusted CA certificates used to **validate** a peer's presented certificate                         |

> [!warning] Ident vs Val — Don't Confuse the Direction
> `CryptoIdentCred` is about **presenting** your own identity (server proving who it is to a client, or a client proving who it is via mTLS). `CryptoValCred` is about **trusting** someone else's identity (validating a peer's cert against known CAs). Day 36's `ValCred` reference in the AAA policy is a Validation Credential — DataPower was verifying the partner's cert, not presenting its own.

### File Storage Convention

Key and certificate files typically live under the `cert:///` directory (a special, more access-restricted filestore than `local:///`) — this separation exists because private key material warrants stricter access control than general scripts/stylesheets.

### Certificate Chains

A `CryptoValCred` can reference multiple CA certificates to validate a full chain (root + intermediate), not just a single cert. An incomplete chain (missing intermediate) is one of the most common "TLS handshake fails intermittently" root causes — the peer's cert validates fine against some validators (which cache/fetch intermediates) but fails against DataPower's strict validation if the intermediate isn't explicitly included.

### Object Relationship Diagram (Conceptual)

```
CryptoKey ──┐
            ├──> CryptoIdentCred ──> (used by) SSLProxyProfile as "my identity"
CryptoCertificate ──┘

CryptoCertificate (CA root/intermediate) ──> CryptoValCred ──> (used by) SSLProxyProfile
                                                                  or AAAPolicy as "who I trust"
```

---

## Your Stack, Concretely

| Scenario                                                               | DataPower reality                                                                                                                                                   |
| ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| DataPower needs to present its own server certificate for an HTTPS FSH | `CryptoKey` (server private key) + `CryptoCertificate` (server cert) combined into a `CryptoIdentCred`, referenced by an `SSLProxyProfile` (Day 39)                 |
| DataPower needs to validate a partner's client certificate for mTLS    | Partner's issuing CA cert(s) loaded as `CryptoCertificate` objects, combined into a `CryptoValCred`, referenced by the AAA policy (Day 36) or the `SSLProxyProfile` |
| TLS handshake fails only for some clients, not others                  | Likely an incomplete certificate chain in the `CryptoValCred` — missing intermediate CA is the most common cause                                                    |

---

## Hands-on

### Exercise 1 — Read a Full Ident/Val Crypto Export

```xml
<CryptoKey name="ServerPrivateKey">
  <mAdminState>enabled</mAdminState>
  <Filename>cert:///server-private.key</Filename>
</CryptoKey>

<CryptoCertificate name="ServerCert">
  <mAdminState>enabled</mAdminState>
  <Filename>cert:///server-cert.pem</Filename>
</CryptoCertificate>

<CryptoIdentCred name="ServerIdentCred">
  <mAdminState>enabled</mAdminState>
  <Key class="CryptoKey">ServerPrivateKey</Key>
  <Certificate class="CryptoCertificate">ServerCert</Certificate>
</CryptoIdentCred>

<CryptoCertificate name="PartnerRootCA">
  <mAdminState>enabled</mAdminState>
  <Filename>cert:///partner-root-ca.pem</Filename>
</CryptoCertificate>

<CryptoCertificate name="PartnerIntermediateCA">
  <mAdminState>enabled</mAdminState>
  <Filename>cert:///partner-intermediate-ca.pem</Filename>
</CryptoCertificate>

<CryptoValCred name="PartnerCAValCred">
  <mAdminState>enabled</mAdminState>
  <Certificate class="CryptoCertificate">PartnerRootCA</Certificate>
  <Certificate class="CryptoCertificate">PartnerIntermediateCA</Certificate>
</CryptoValCred>
```

Answer: this `PartnerCAValCred` is the exact object referenced in Day 36's `ValCred` field — trace through why both `PartnerRootCA` **and** `PartnerIntermediateCA` need to be present for validation to succeed against a partner cert signed by the intermediate.

### Exercise 2 — Diagnose a Broken Ident Cred

```xml
<CryptoIdentCred name="BrokenServerIdentCred">
  <mAdminState>enabled</mAdminState>
  <Key class="CryptoKey">ServerPrivateKey</Key>
</CryptoIdentCred>
```

Identify the defect (missing `Certificate` reference) and explain what would happen operationally if this Ident Cred were bound to an HTTPS FSH's SSL Proxy Profile — a server can't present "just a private key" without the matching public certificate.

### Exercise 3 — CLI: Inspect Crypto Objects

```
configure terminal
switch domain LABDOM01
show crypto-key
show crypto-certificate
show crypto-ident-cred
show crypto-val-cred
```

Write down what you'd check first if a teammate reports "the handshake fails with an unknown CA error" (answer shape: check the relevant `CryptoValCred`'s certificate list for a missing intermediate, per Exercise 1's reasoning).

---

## Validation

- [ ] You correctly explained why both root and intermediate CA certs are needed in `PartnerCAValCred` for chain validation to succeed.
- [ ] You identified the missing `Certificate` reference in Exercise 2's broken Ident Cred and can state why a key alone is insufficient to present an identity.
- [ ] You can state, from memory, the direction distinction between Ident Cred ("presenting yourself") and Val Cred ("trusting a peer") without needing to look it up.

---

## Key Takeaways

- Four core objects: `CryptoKey`, `CryptoCertificate`, `CryptoIdentCred` (presenting identity), `CryptoValCred` (trusting a peer).
- Ident Cred = key + cert, used to present your own identity; Val Cred = one or more CA certs, used to validate someone else's identity.
- Incomplete certificate chains in a Val Cred are the most common cause of intermittent/partner-specific TLS failures.
- These objects are referenced from both `SSLProxyProfile` (Day 39) and `AAAPolicy` (Day 36) — they are the shared crypto substrate underneath both transport-level TLS and application-level mTLS authentication.

---

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-39-TLS-Profiles-and-SSL-Proxy]] →
