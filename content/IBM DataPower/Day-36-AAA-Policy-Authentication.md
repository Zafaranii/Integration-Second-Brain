---
tags: [datapower, bucket-3, security, aaa, day-36]
created: 2026-07-05
bucket: 3
week: 8
day: 36
status: not-started
---

# Day 36 — AAA Policy: Authentication Phases

> [!info] Why This Day Exists
> The AAA Policy is DataPower's security enforcement engine — a six-phase pipeline that runs identity extraction, authentication, authorization, and post-processing as a single reusable object. Today covers the first phases (identity + authentication); Day 37 covers authorization and mapping.

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-37-AAA-Policy-Authorization]] →

---

## Theory

### AAA as a Six-Phase Pipeline

An `AAAPolicy` object is invoked as a single action inside a `StylePolicyRule` (same reference pattern as every other action from Week 7), but internally it executes a fixed sequence of phases:

| Phase                  | Purpose                                                                       |
| ---------------------- | ----------------------------------------------------------------------------- |
| 1. Identity Extraction | Pull a candidate identity out of the request (header, cert, token, etc.)      |
| 2. Authentication      | Verify that identity against a source of truth                                |
| 3. Extract Resource    | Determine what resource is being accessed                                     |
| 4. Authorization       | Decide if the authenticated identity may access that resource                 |
| 5. Post-processing     | Map/transform the identity into a downstream-usable form (e.g., a new header) |
| 6. (Response)          | Optional response-side AAA processing on the way back                         |

Today's focus is Phases 1–2 — everything downstream depends on a correctly extracted and authenticated identity.

### Phase 1 — Identity Extraction Methods

| Method                   | Source                                                           |
| ------------------------ | ---------------------------------------------------------------- |
| HTTP Basic Auth          | `Authorization: Basic ...` header                                |
| HTTP header              | Any custom header (e.g., `X-Client-Id`)                          |
| WS-Security token (SOAP) | UsernameToken / BinarySecurityToken in the SOAP header           |
| SSL client certificate   | Subject DN of a presented client cert (ties to Day 38–39's mTLS) |
| SAML assertion           | Extracted subject from a SAML token                              |
| Cookie/token             | Custom token extraction                                          |

### Phase 2 — Authentication Methods

Once an identity is extracted, it must be verified against something:

| Method                      | Verification source                                                   |
| --------------------------- | --------------------------------------------------------------------- |
| LDAP                        | Bind against an LDAP/AD directory                                     |
| RADIUS                      | RADIUS server                                                         |
| Local user list             | Appliance-local user database (rare in production, common in dev/lab) |
| Custom (GatewayScript/XSLT) | A script implementing bespoke verification logic                      |
| SAML                        | Validate assertion signature/issuer                                   |

> [!warning] Extraction ≠ Authentication
> A common conceptual error: assuming "we extracted a username from the header" means the user is authenticated. Extraction only identifies **who the request claims to be**; Phase 2 is what actually verifies that claim. A misconfigured AAA policy that extracts but never authenticates is a security hole, not a working policy.

---

## Your Stack, Concretely

| Scenario                                                       | DataPower reality                                                                                                                                                                             |
| -------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Partner API secured via mutual TLS                             | Identity extracted from the client cert's Subject DN (Phase 1), authenticated by validating the cert chain against a trusted CA (Phase 2) — ties directly into Day 38–39's crypto/TLS objects |
| Internal service-to-service call using a shared API key header | Identity extraction from `X-Api-Key` header (Phase 1), authentication via a custom GatewayScript lookup against a key store (Phase 2)                                                         |
| Legacy SOAP partner using WS-Security UsernameToken            | Identity extraction from the SOAP header token (Phase 1), authentication via LDAP bind (Phase 2)                                                                                              |

---

## Hands-on

### Exercise 1 — Read an AAA Policy Export (Phases 1–2 Only)

```xml
<AAAPolicy name="PartnerMTLSAuthPolicy">
  <mAdminState>enabled</mAdminState>
  <IdentityExtraction>
    <Method>ssl-client-cert</Method>
    <SubjectDNField>CN</SubjectDNField>
  </IdentityExtraction>
  <Authentication>
    <Method>valcred</Method>
    <ValCred class="CryptoValCred">PartnerCAValCred</ValCred>
  </Authentication>
</AAAPolicy>
```

Answer: what phase does `IdentityExtraction` correspond to, and what phase does `Authentication` correspond to? What object (introduced properly in Day 38) does `ValCred` reference, and why is that reference necessary for Phase 2 to actually verify anything?

### Exercise 2 — Write an API-Key Header AAA Fragment

Build the Phase 1–2 fragment for identity extraction from an `X-Api-Key` header, authenticated via a custom GatewayScript lookup:

```xml
<AAAPolicy name="ApiKeyAuthPolicy">
  <mAdminState>enabled</mAdminState>
  <IdentityExtraction>
    <Method>http-header</Method>
    <HeaderName>X-Api-Key</HeaderName>
  </IdentityExtraction>
  <Authentication>
    <Method>custom</Method>
    <CustomAuthFile>local:///scripts/validate-api-key.js</CustomAuthFile>
  </Authentication>
</AAAPolicy>
```

### Exercise 3 — Wire the AAA Policy Into a Rule

```xml
<StylePolicyRule name="SecuredOrdersRule">
  <Action class="StylePolicyAction">
    <Type>aaa</Type>
    <AAAPolicyFile class="AAAPolicy">ApiKeyAuthPolicy</AAAPolicyFile>
  </Action>
  <Action class="StylePolicyAction">
    <Type>gatewayscript</Type>
    <GatewayScriptFile>local:///scripts/validate-order-body.js</GatewayScriptFile>
  </Action>
</StylePolicyRule>
```

Confirm: given Day 31's action-ordering rule, why must the `aaa` action be listed **before** the body-validation GatewayScript action? (Answer shape: unauthenticated requests should be rejected before spending processing time validating/parsing their body.)

### Exercise 4 — CLI: Inspect an AAA Policy

```
configure terminal
switch domain LABDOM01
show aaa-policy ApiKeyAuthPolicy
```

---

## Validation

- [ ] You correctly mapped `IdentityExtraction` → Phase 1 and `Authentication` → Phase 2 in Exercise 1.
- [ ] You can explain why the `ValCred` reference is required for Phase 2 to be meaningful (a mere identity claim proves nothing without something to validate it against).
- [ ] You confirmed the `aaa` action belongs before body-parsing actions in a hardened rule sequence, consistent with Day 35's "gate before expensive work" discipline.

---

## Key Takeaways

- AAA is a six-phase pipeline; Phases 1–2 (Identity Extraction, Authentication) are the foundation everything else depends on.
- Extraction identifies a claimed identity; Authentication verifies it — conflating the two is a real security misconfiguration, not just terminology sloppiness.
- AAA policies are reusable objects, referenced from a rule exactly like Transform/Filter/Validate actions.
- AAA should run early in a rule's action sequence — reject unauthenticated traffic before spending cycles on parsing/validation.

---

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-37-AAA-Policy-Authorization]] →
