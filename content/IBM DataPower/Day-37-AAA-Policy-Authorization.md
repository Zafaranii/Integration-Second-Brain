---
tags: [datapower, bucket-3, security, aaa, day-37]
created: 2026-07-05
bucket: 3
week: 8
day: 37
status: not-started
---

# Day 37 — AAA Policy: Authorization Phases

> [!info] Why This Day Exists
> Being authenticated only proves who you are — Phases 3–6 decide what you're allowed to do, and how that decision gets communicated downstream. This is where role/group mapping and post-processing headers actually get built.

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-38-Crypto-Objects-Keys-and-Certificates]] →

---

## Theory

### Phases 3–6 Recap

| Phase               | Purpose                                                                         |
| ------------------- | ------------------------------------------------------------------------------- |
| 3. Extract Resource | Determine what resource/operation is being accessed (URL, SOAP operation, etc.) |
| 4. Authorization    | Decide whether the authenticated identity may access that resource              |
| 5. Post-processing  | Map the identity/authorization result into a downstream-usable form             |
| 6. Response         | Optional response-direction AAA processing                                      |

### Phase 3 — Extract Resource

Typically derived from the request URL, HTTP method, or (for SOAP) the operation name resolved from the WSDL/SOAP action. This is what Phase 4 evaluates permissions **against** — without a correctly extracted resource identifier, authorization has nothing meaningful to check.

### Phase 4 — Authorization Methods

| Method                      | Mechanism                                                                            |
| --------------------------- | ------------------------------------------------------------------------------------ |
| LDAP group membership       | Check if the authenticated identity belongs to a required group/OU                   |
| XACML                       | Policy-based authorization via an XACML PDP                                          |
| Custom (GatewayScript/XSLT) | Bespoke authorization logic, e.g., a lookup against an internal entitlements service |
| Local mapping               | Static allow/deny lists configured on the appliance                                  |

### Phase 5 — Post-processing / Credential Mapping

This phase transforms the authenticated (and now authorized) identity into whatever form the backend expects — commonly:

- Injecting a new header (e.g., `X-Authenticated-User: jdoe`) so the backend doesn't need to re-implement authentication.
- Mapping an external identity to an internal service account or role name.
- Stripping the original credential (e.g., removing the raw `Authorization` header) before forwarding to the backend, so the backend never sees the client's raw credential.

> [!warning] Post-Processing Is Also a Security Control
> Forgetting to strip the original client credential in Phase 5 means the backend receives the raw, potentially sensitive credential unnecessarily — increasing exposure if the backend is compromised or logs request headers. Explicit credential mapping/stripping is a deliberate hardening step, not an optional nicety.

### Phase 6 — Response-Direction AAA (Optional)

Less commonly used, but available for cases where the response itself needs identity-aware processing (e.g., filtering response content based on the caller's authorization level).

---

## Your Stack, Concretely

| Scenario                                                                               | DataPower reality                                                                                                                                         |
| -------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Partner authenticated via mTLS should only access `/orders/read`, not `/orders/write`  | Phase 3 extracts the URL/operation, Phase 4 checks the mapped role against an entitlements list, denies `write` operations for read-only partners         |
| Backend expects a simple internal service-account header, not the original OAuth token | Phase 5 maps the external token's subject to `X-Service-Account: partner-readonly`, and strips the original `Authorization` header before the backend hop |
| Compliance requirement: backend must never see raw partner credentials                 | Enforced entirely in Phase 5 post-processing — this is a policy-configuration discipline, not a default behavior                                          |

---

## Hands-on

### Exercise 1 — Read a Full Phase 3–5 AAA Fragment

```xml
<AAAPolicy name="PartnerMTLSAuthPolicy">
  <!-- Phases 1-2 from Day 36 -->
  <IdentityExtraction>
    <Method>ssl-client-cert</Method>
    <SubjectDNField>CN</SubjectDNField>
  </IdentityExtraction>
  <Authentication>
    <Method>valcred</Method>
    <ValCred class="CryptoValCred">PartnerCAValCred</ValCred>
  </Authentication>

  <!-- Phase 3 -->
  <ExtractResource>
    <Method>url</Method>
  </ExtractResource>

  <!-- Phase 4 -->
  <Authorization>
    <Method>custom</Method>
    <CustomAuthzFile>local:///scripts/check-partner-entitlements.js</CustomAuthzFile>
  </Authorization>

  <!-- Phase 5 -->
  <PostProcessing>
    <Method>custom</Method>
    <MapCredFile>local:///scripts/map-partner-identity.js</MapCredFile>
    <StripOriginalCredential>true</StripOriginalCredential>
  </PostProcessing>
</AAAPolicy>
```

Answer: which single property in this fragment is responsible for preventing the backend from ever seeing the client's raw certificate-derived identity claim in its original form, and why does this matter even though the identity was already validated?

### Exercise 2 — Write a Custom Authorization GatewayScript Stub

```javascript
// check-partner-entitlements.js
// Illustrative shape only -- exact AAA context variable retrieval
// varies by firmware; verify against current docs.

var identity = "partner-readonly" // would be read from AAA context in practice
var resource = session.input.readAsBuffer ? "/orders/write" : "/orders/write"

var entitlements = {
  "partner-readonly": ["/orders/read"],
  "partner-fullaccess": ["/orders/read", "/orders/write"],
}

var allowed = entitlements[identity] || []

if (allowed.indexOf(resource) === -1) {
  throw new Error("Authorization denied: " + identity + " cannot access " + resource)
}
```

Annotate: why does a denied authorization here still need to flow through the error rule mechanism from Day 34, rather than being handled as a distinct "auth failure" code path?

### Exercise 3 — CLI: Inspect Full AAA Policy Phases

```
configure terminal
switch domain LABDOM01
show aaa-policy PartnerMTLSAuthPolicy
```

---

## Validation

- [ ] You correctly identified `StripOriginalCredential` as the property preventing raw credential leakage to the backend.
- [ ] You can explain why authentication success does not imply authorization success — these are genuinely separate decisions (Phase 2 vs Phase 4).
- [ ] You connected the authorization-denial `throw` back to Day 34's error-rule mechanism rather than treating it as a special, separate failure path.

---

## Key Takeaways

- Phases 3–6 turn "who are you" into "what can you do, and how does the backend see you" — resource extraction, authorization, and identity mapping/stripping.
- Authorization (Phase 4) is a distinct decision from authentication (Phase 2) — never assume one implies the other.
- Credential mapping/stripping in Phase 5 is a deliberate hardening control, not an automatic default — omitting it is a common compliance gap.
- AAA failures at any phase are ordinary errors from the engine's perspective — they surface through the same error-rule mechanism as any other rejected transaction.

---

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-38-Crypto-Objects-Keys-and-Certificates]] →
