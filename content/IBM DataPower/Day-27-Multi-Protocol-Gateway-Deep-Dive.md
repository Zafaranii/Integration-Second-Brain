---
tags: [datapower, bucket-3, architecture, day-27]
created: 2026-07-05
bucket: 3
week: 6
day: 27
status: not-started
---

# Day 27 — Multi-Protocol Gateway (MPGW) Deep Dive

> [!info] Why This Day Exists
> MPGW is the workhorse service you'll build most REST APIs, non-SOAP XML proxies, and protocol bridges on. Getting its core properties wrong — especially `RequestType` — is the single most common cause of "the gateway rejects everything" incidents.

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-28-Web-Service-Proxy-vs-MPGW]] →

---

## Theory

### Design Intent

MPGW makes **no assumption** about message shape — SOAP, REST/JSON, binary, or MQ payload. It is protocol-agnostic mediation, in contrast to WSP's WSDL-awareness (Day 28).

### Key MPGW Properties

| Property                       | Meaning                                                                                                             |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------- |
| `FrontProtocol`                | One or more Front Side Handlers bound to this service — multiple FSH feed one policy                                |
| `Type`                         | `dynamic-backend` vs `static-backend` — controls whether the back-end URL can be computed at runtime                |
| `StylePolicy`                  | The processing policy (rules) applied to traffic                                                                    |
| `RequestType` / `ResponseType` | `passthrough`, `soap`, `xml`, `nonxml`, `binary` — dictates how the parser treats the body **before** any rule runs |
| `UserSummary`                  | Free-text description — never leave blank in production; this is what shows in list views under incident pressure   |

> [!warning] RequestType Mismatches Are Silent Killers
> Setting `RequestType=soap` on a REST/JSON payload causes immediate parse rejection — before your processing rule even gets a chance to run. If a service "rejects everything with no rule match," check `RequestType` first, not the StylePolicy.

### Non-XML Mode

MPGW can run in **non-XML mode**, meaning the parser doesn't tokenize the body as XML at all. This is mandatory for JSON/binary passthrough performance and required if you want GatewayScript's native JSON handling instead of forcing JSON→XML conversion.

### Shared Policy Blast Radius

One `StylePolicy` object can be attached to multiple MPGWs by reference. A shared-policy edit is a blast-radius event across every service referencing it — always check reverse-references before editing a shared StylePolicy in production.

---

## Your Stack, Concretely

| Scenario                                       | DataPower reality                                                                                                      |
| ---------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| REST API fronting an ACE-hosted microservice   | Built as MPGW, `RequestType=nonxml`, static or dynamic backend pointing at the ACE HTTP Listener's internal address    |
| Legacy XML proxy needing XPath content routing | MPGW with `RequestType=xml`, Route action inspecting payload (Day 30/31)                                               |
| One StylePolicy shared across 5 REST APIs      | Editing it to add a new header-stripping rule affects all 5 — exactly the "shared policy" risk from the theory section |

---

## Hands-on

### Exercise 1 — Build a Complete MPGW Export Fragment

```xml
<MultiProtocolGateway name="OrdersMPGW">
  <mAdminState>enabled</mAdminState>
  <UserSummary>REST proxy for Orders API - fronts internal orders-svc</UserSummary>
  <FrontProtocol class="HTTPFrontSideHandler">OrdersFSH</FrontProtocol>
  <Type>static-backend</Type>
  <RequestType>nonxml</RequestType>
  <ResponseType>nonxml</ResponseType>
  <BackendUrl>http://orders-internal.svc.cluster.local:8082/orders</BackendUrl>
  <StylePolicy class="StylePolicy">OrdersPolicy</StylePolicy>
</MultiProtocolGateway>

<HTTPFrontSideHandler name="OrdersFSH">
  <mAdminState>enabled</mAdminState>
  <Port>9443</Port>
  <LocalAddress>0.0.0.0</LocalAddress>
</HTTPFrontSideHandler>
```

### Exercise 2 — Diagnose a Broken Config

```xml
<MultiProtocolGateway name="BrokenGW">
  <mAdminState>enabled</mAdminState>
  <FrontProtocol class="HTTPFrontSideHandler">MissingFSH</FrontProtocol>
  <Type>static-backend</Type>
  <RequestType>soap</RequestType>
  <BackendUrl>orders-internal:8082/orders</BackendUrl>
</MultiProtocolGateway>
```

List every defect. Reason through: does `MissingFSH` exist anywhere? Is `RequestType=soap` appropriate for a plain REST backend? Is `BackendUrl` a valid absolute URL (missing scheme)? Is a `StylePolicy` even required for traffic to flow?

### Exercise 3 — CLI Status Commands

```
configure terminal
switch domain LABDOM01
show mpgw OrdersMPGW
show interface
```

Note the difference between `mAdminState` and the operational state shown by `show mpgw <name>` — admin-enabled but op-down happens when a dependent object (like the FSH port) can't actually bind.

---

## Validation

- [ ] You listed at least three defects in Exercise 2 (missing FSH reference, mismatched `RequestType` vs actual payload, malformed `BackendUrl` missing scheme).
- [ ] You can explain, in one sentence, why `RequestType` is evaluated before any StylePolicy rule executes.
- [ ] You can state the operational risk of one shared `StylePolicy` referenced by five MPGWs.

---

## Key Takeaways

- MPGW is protocol-agnostic; WSP is not — that's the core architectural split.
- `RequestType`/`ResponseType` are evaluated at the parser level, before any rule logic runs — get these wrong and rules never even get a chance.
- StylePolicy is referenced, not contained — shared policies mean shared blast radius.
- Non-XML mode is mandatory for JSON/binary performance and native GatewayScript JSON handling.

---

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-28-Web-Service-Proxy-vs-MPGW]] →
