---
tags: [datapower, bucket-3, architecture, day-28]
created: 2026-07-05
bucket: 3
week: 6
day: 28
status: not-started
---

# Day 28 — Web Service Proxy (WSP) vs MPGW

> [!info] Why This Day Exists
> WSP is "MPGW plus WSDL contract enforcement baked in." Knowing exactly what that extra layer buys you — and what silently disappears if a team "downgrades" a SOAP service from WSP to MPGW — is a recurring architecture-review question.

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-29-Front-Side-Handlers]] →

---

## Theory

### Design Intent

WSP **ingests a WSDL at configuration time** and derives, from it: the operations exposed, the expected schema per operation, and (by default) automatic schema validation. This is WSP's core differentiator from MPGW, which is deliberately payload-agnostic.

### Key WSP Properties

| Property                     | Meaning                                                                                            |
| ---------------------------- | -------------------------------------------------------------------------------------------------- |
| `WSDLFile` / `LocalWSDLFile` | The source WSDL the proxy is built from                                                            |
| `SOAPHandler`                | Front-side listener config — SOAP-aware counterpart to MPGW's `FrontProtocol`                      |
| `Type`                       | `proxy` (pass to real backend per WSDL binding) vs `differentiated` (per-operation policy/backend) |
| `ValidateBody`               | Enables automatic schema validation against the WSDL's embedded/referenced XSDs                    |

WSP also natively understands SOAP faults — a rule failure can auto-generate a compliant `<soap:Fault>` with zero custom logic. MPGW requires you to build this yourself (Day 34).

### MPGW vs WSP — Decision Table

| Criterion          | MPGW                                       | WSP                                    |
| ------------------ | ------------------------------------------ | -------------------------------------- |
| Protocol awareness | None (agnostic)                            | SOAP/WSDL-aware                        |
| Schema validation  | Manual (Validate action)                   | Automatic from WSDL                    |
| REST/JSON support  | Native                                     | Poor/unsupported                       |
| Backend discovery  | Static URL or dynamic routing              | Derived from WSDL `<service>`/`<port>` |
| Fault generation   | Manual                                     | Automatic SOAP Fault                   |
| Use when           | REST, non-XML, mixed protocol, MQ bridging | Pure SOAP with governed WSDL contracts |

> [!warning] The "Downgrade" Trap
> Teams sometimes rebuild a WSP as an MPGW to gain REST support alongside legacy SOAP, then wonder why schema violations that used to be auto-rejected now pass through — the automatic WSDL-validation disappeared and nobody added an explicit Validate action to compensate.

---

## Your Stack, Concretely

| Scenario                                                          | DataPower reality                                                                                                                           |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| External partner-facing SOAP API with formally versioned WSDL     | WSP — governance and contract enforcement matter, automatic validation reduces custom rule logic                                            |
| Mobile BFF exposing JSON REST, backed by HTTP/MQ/SOAP downstreams | MPGW — protocol diversity and JSON support are non-negotiable                                                                               |
| Migrating a SOAP service to also serve REST                       | Keep WSP for the SOAP contract; stand up a **separate** MPGW for REST rather than collapsing both into one MPGW and losing WSDL enforcement |

---

## Hands-on

### Exercise 1 — Read a WSP Export Fragment

```xml
<WSGateway name="BillingWSP">
  <mAdminState>enabled</mAdminState>
  <WSDLFile>local:///wsdl/BillingService.wsdl</WSDLFile>
  <Type>proxy</Type>
  <SOAPHandler class="HTTPFrontSideHandler">BillingFSH</SOAPHandler>
  <ValidateBody>on</ValidateBody>
  <StylePolicy class="StylePolicy">BillingPolicy</StylePolicy>
</WSGateway>
```

Write down which two behaviors here (`WSDLFile` + `ValidateBody`) have **no MPGW equivalent property** — meaning if this were rebuilt as an MPGW, you'd need explicit rule actions to match functional parity.

### Exercise 2 — Convert Requirements Into the Correct Service Type

For each scenario, decide MPGW or WSP and justify in one sentence:

1. Internal team needs to expose a governed SOAP contract to 40 external partners; contract changes go through formal WSDL versioning.
2. A mobile BFF needs to expose JSON REST endpoints backed by 3 different downstream protocols (HTTP, MQ, SOAP).
3. A legacy SOAP service needs a quick pass-through proxy for TLS termination only, no transformation.
4. A team wants raw XML pass-through with custom XPath-based content routing, no WSDL exists.

### Exercise 3 — CLI Comparison of Object Counts

```
configure terminal
switch domain LABDOM01
show wsgateway
show mpgw
```

Useful in real audits to spot "why is this SOAP service built as an MPGW."

---

## Validation

- [ ] Exercise 2 answers: (1) WSP — governed WSDL contract; (2) MPGW — protocol diversity + JSON; (3) WSP if a WSDL exists and governance matters, MPGW acceptable if truly pass-through with no contract enforcement need; (4) MPGW — no WSDL, XPath routing is MPGW's strength.
- [ ] You can name the one WSP property with zero direct MPGW equivalent (`ValidateBody` / WSDL-derived schema enforcement).
- [ ] You can explain in one sentence why "downgrading" WSP→MPGW silently drops contract enforcement.

---

## Key Takeaways

- WSP = MPGW + WSDL contract enforcement baked in, not a fundamentally different engine.
- Automatic schema validation and SOAP fault generation are WSP-only conveniences — MPGW can replicate them, but only with explicit rule actions.
- Choosing MPGW for a REST/JSON/mixed-protocol requirement is correct; choosing MPGW for a governed SOAP contract usually means someone will rebuild validation logic that WSP gave for free.

---

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-29-Front-Side-Handlers]] →
