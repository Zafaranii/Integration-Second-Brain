---
tags: [datapower, bucket-3, security, tls, day-39]
created: 2026-07-05
bucket: 3
week: 8
day: 39
status: not-started
---

# Day 39 — TLS Profiles and SSL Proxy Profiles

> [!info] Why This Day Exists
> The `SSLProxyProfile` is where Day 38's crypto objects actually get bound to a live TLS handshake — on either the client side (DataPower as a TLS client to a backend) or the server side (DataPower as a TLS server to an inbound client, including mTLS). This is the last architectural piece before Day 40's wrap-up.

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-40-DataPower-Wrapup-and-Troubleshooting]] →

---

## Theory

### SSL Proxy Profile — Two Directions

An `SSLProxyProfile` can be configured as:

| Direction | Used by                          | Purpose                                                                                                                                                        |
| --------- | -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Server    | `HTTPSFrontSideHandler` (Day 29) | DataPower terminates inbound TLS as the server — presents its own Ident Cred, optionally requires/validates a client cert (mTLS)                               |
| Client    | MPGW/WSP backend connection      | DataPower initiates outbound TLS as the client to a backend — presents an Ident Cred if the backend requires mTLS, validates the backend's cert via a Val Cred |

### Key SSL Proxy Profile Properties

| Property             | Meaning                                                                                                                                              |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Direction`          | `server` or `client`                                                                                                                                 |
| `IdentCred`          | The `CryptoIdentCred` (Day 38) DataPower presents as its own identity                                                                                |
| `ValCred`            | The `CryptoValCred` (Day 38) used to validate the peer's presented certificate                                                                       |
| `ClientAuthType`     | (Server direction only) whether client certificates are `required`, `optional`, or not requested at all — this is the actual mTLS enforcement toggle |
| `Ciphers`            | Allowed cipher suite list — restricting this is a common hardening/compliance requirement                                                            |
| `ProtocolMinVersion` | Minimum TLS version accepted (e.g., disabling TLS 1.0/1.1)                                                                                           |

> [!warning] `ClientAuthType=required` Is the mTLS Switch
> Simply attaching an `IdentCred` to a server-direction profile only makes DataPower present _its own_ certificate (standard one-way TLS). Mutual TLS additionally requires `ClientAuthType` set to require a client cert, **plus** a `ValCred` to validate that presented client cert. Missing either half gives you one-way TLS while believing you've configured mTLS.

### Relationship to AAA (Day 36)

When `ClientAuthType=required` is set on a server-direction profile, the TLS handshake itself rejects connections lacking a valid client cert — this happens **before** any StylePolicy rule or AAA policy runs. The AAA policy's `ssl-client-cert` identity extraction (Day 36) then reads the **already-validated** cert's Subject DN. This means TLS-level validation and AAA-level extraction are two distinct checks that happen to use the same underlying certificate.

---

## Your Stack, Concretely

| Scenario                                                       | DataPower reality                                                                                                                                                          |
| -------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| External partner API requiring mTLS                            | Server-direction `SSLProxyProfile`: `IdentCred` = DataPower's server cert, `ClientAuthType=required`, `ValCred` = partner's CA chain (same `PartnerCAValCred` from Day 38) |
| DataPower calling a backend that itself requires mTLS          | Client-direction `SSLProxyProfile` on the MPGW's backend connection: `IdentCred` = DataPower's client-facing identity toward that backend, `ValCred` = the backend's CA    |
| Compliance mandate: disable TLS 1.0/1.1, restrict weak ciphers | `ProtocolMinVersion` set to TLS 1.2 (or higher), `Ciphers` list restricted to an approved suite set — applied on every relevant `SSLProxyProfile`                          |

---

## Hands-on

### Exercise 1 — Read a Full mTLS Server-Direction Profile

```xml
<SSLProxyProfile name="ExternalServerSSLProfile">
  <mAdminState>enabled</mAdminState>
  <Direction>server</Direction>
  <IdentCred class="CryptoIdentCred">ServerIdentCred</IdentCred>
  <ValCred class="CryptoValCred">PartnerCAValCred</ValCred>
  <ClientAuthType>required</ClientAuthType>
  <ProtocolMinVersion>TLSv1.2</ProtocolMinVersion>
  <Ciphers>HIGH:!aNULL:!MD5</Ciphers>
</SSLProxyProfile>
```

This is the exact object referenced by Day 29's `ExternalFSH`. Answer: trace the full chain from Day 29 → this profile → Day 38's `ServerIdentCred`/`PartnerCAValCred` objects. What single property, if changed from `required` to `optional`, would silently downgrade this from enforced mTLS to "client cert accepted if offered, but not mandatory"?

### Exercise 2 — Write a Client-Direction Profile for an Outbound mTLS Backend Call

```xml
<SSLProxyProfile name="BackendClientSSLProfile">
  <mAdminState>enabled</mAdminState>
  <Direction>client</Direction>
  <IdentCred class="CryptoIdentCred">BackendClientIdentCred</IdentCred>
  <ValCred class="CryptoValCred">BackendCAValCred</ValCred>
  <ProtocolMinVersion>TLSv1.2</ProtocolMinVersion>
</SSLProxyProfile>
```

Note there's no `ClientAuthType` here — explain why that property is meaningless in the `client` direction (it only governs whether the _server side_ demands a cert from its peer).

### Exercise 3 — Diagnose a One-Way-TLS-Believed-to-Be-mTLS Misconfiguration

```xml
<SSLProxyProfile name="MisconfiguredMTLS">
  <mAdminState>enabled</mAdminState>
  <Direction>server</Direction>
  <IdentCred class="CryptoIdentCred">ServerIdentCred</IdentCred>
</SSLProxyProfile>
```

List every missing piece required for this to actually enforce mTLS (missing `ValCred`, missing `ClientAuthType=required`).

### Exercise 4 — CLI: Inspect an SSL Proxy Profile

```
configure terminal
switch domain LABDOM01
show ssl-proxy-profile ExternalServerSSLProfile
```

---

## Validation

- [ ] You traced the full object chain: FSH → SSLProxyProfile → IdentCred/ValCred → underlying Key/Certificate objects, across Days 29, 38, and 39.
- [ ] You correctly identified `ClientAuthType` as the property controlling enforced vs. optional client cert presentation.
- [ ] You listed both missing pieces in Exercise 3 (`ValCred` and `ClientAuthType=required`) rather than just one.
- [ ] You can explain why `ClientAuthType` is irrelevant on a client-direction profile.

---

## Key Takeaways

- `SSLProxyProfile` is directional — server profiles govern inbound TLS (including mTLS enforcement), client profiles govern outbound TLS to backends.
- One-way TLS only requires an `IdentCred` on the server side; mTLS additionally requires `ValCred` + `ClientAuthType=required`.
- TLS-level client cert validation happens before any StylePolicy/AAA rule runs — AAA's identity extraction (Day 36) reads an already-validated certificate.
- Cipher and protocol-version restrictions live on this object too — it's the natural place to enforce compliance-driven TLS hardening.

---

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-40-DataPower-Wrapup-and-Troubleshooting]] →
