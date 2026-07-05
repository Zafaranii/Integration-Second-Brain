---
tags: [datapower, bucket-3, architecture, day-29]
created: 2026-07-05
bucket: 3
week: 6
day: 29
status: not-started
---

# Day 29 — Front-Side Handlers

> [!info] Why This Day Exists
> The FSH is where DataPower actually terminates a transport connection. One gateway service can bind multiple FSH objects — the fan-in pattern behind "internal HTTP + external mTLS into one policy" designs you'll see constantly in real deployments.

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-30-Back-Side-Routing]] →

---

## Theory

### FSH's Job

Terminate a specific transport/protocol connection and hand the resulting message to the owning gateway service's processing policy. A gateway service (MPGW/WSP) can bind **multiple FSH objects simultaneously** — e.g., one HTTP FSH on 8080 and one HTTPS FSH on 8443, both feeding the same StylePolicy.

### Common FSH Classes

| Class                                               | Purpose                                                               |
| --------------------------------------------------- | --------------------------------------------------------------------- |
| `HTTPFrontSideHandler`                              | Plain HTTP listener                                                   |
| `HTTPSFrontSideHandler`                             | TLS-terminated HTTP, references an `SSLProxyProfile` (Day 39)         |
| `MQFrontSideHandler`                                | Listens on an MQ queue, converts MQMD + payload into the message flow |
| `FTPFrontSideHandler` / `FTPServerFrontSideHandler` | File-transfer triggered processing                                    |
| `XTCFrontSideHandler`                               | Custom TCP protocols                                                  |

### Key HTTPS FSH Properties

- `SSLServerConfigType` — direct SSL Proxy Profile reference vs. hostname-based (SNI) resolution
- `SSLProxyProfile` — points at the crypto identity (Day 38–39) used for the server-side TLS handshake
- `PersistentConnections` — whether keep-alive is honored downstream

### Binding Rule — Same Port, Multiple Services

DataPower requires a **unique {IP, port} pair per FSH object** unless using **name-based virtual hosting** — a single shared FSH bound to multiple services, differentiated by Host-header Matching Rules (Day 31). This is different from two separate FSH objects colliding on the same tuple, which is a hard configuration conflict.

> [!warning] MQ FSH Exposes MQMD Fields
> The FSH surfaces MQMD fields (`CorrelId`, `ReplyToQ`, `MsgId`) into the processing context, so GatewayScript/XSLT rules can read/set them — critical for request-reply MQ patterns bridged to HTTP.

---

## Your Stack, Concretely

| Scenario                                                                   | DataPower reality                                                                                                                                   |
| -------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Internal-only health check endpoint + external partner endpoint on one API | Two FSH objects (`HTTPFrontSideHandler` + `HTTPSFrontSideHandler`), one shared `StylePolicy`, AAA enforcement branched by entry point               |
| MQ-triggered ACE flow needing request-reply semantics                      | `MQFrontSideHandler` reads `ReplyToQ`/`CorrelId` from the inbound message, GatewayScript threads them through to the response leg                   |
| Two teams both want port 443 on the same appliance IP                      | Either name-based virtual hosting on one shared FSH, or distinct IPs on a multi-homed interface — never two FSH objects on the identical {IP, port} |

---

## Hands-on

### Exercise 1 — Write a Dual-FSH MPGW Export

```xml
<MultiProtocolGateway name="DualEntryGW">
  <mAdminState>enabled</mAdminState>
  <FrontProtocol class="HTTPFrontSideHandler">InternalFSH</FrontProtocol>
  <FrontProtocol class="HTTPSFrontSideHandler">ExternalFSH</FrontProtocol>
  <Type>static-backend</Type>
  <RequestType>nonxml</RequestType>
  <BackendUrl>http://internal-svc:8080/api</BackendUrl>
  <StylePolicy class="StylePolicy">DualEntryPolicy</StylePolicy>
</MultiProtocolGateway>

<HTTPFrontSideHandler name="InternalFSH">
  <mAdminState>enabled</mAdminState>
  <Port>8080</Port>
  <LocalAddress>10.10.1.5</LocalAddress>
</HTTPFrontSideHandler>

<HTTPSFrontSideHandler name="ExternalFSH">
  <mAdminState>enabled</mAdminState>
  <Port>8443</Port>
  <LocalAddress>0.0.0.0</LocalAddress>
  <SSLServerConfigType>direct</SSLServerConfigType>
  <SSLProxyProfile class="SSLProxyProfile">ExternalServerSSLProfile</SSLProxyProfile>
</HTTPSFrontSideHandler>
```

### Exercise 2 — MQ FSH Fragment

Write the export for an `MQFrontSideHandler` named `OrderQueueFSH` listening on queue manager `QM1`, queue `ORDERS.IN.Q`, reply queue `ORDERS.OUT.Q`. Reason about which two MQMD-derived fields you'd expect to be readable in GatewayScript later — pick two of `CorrelId`, `MsgId`, `ReplyToQ` and justify.

### Exercise 3 — Port Conflict Diagnosis

```xml
<HTTPFrontSideHandler name="FSH_A">
  <Port>8080</Port>
  <LocalAddress>0.0.0.0</LocalAddress>
</HTTPFrontSideHandler>
<HTTPFrontSideHandler name="FSH_B">
  <Port>8080</Port>
  <LocalAddress>0.0.0.0</LocalAddress>
</HTTPFrontSideHandler>
```

Explain in writing exactly why deployment fails here (identical {IP, port} tuple across two _separate_ FSH objects), and how this differs from the valid "one shared FSH, multiple services via Host header" pattern.

### Exercise 4 — CLI Check for Listener Conflicts

```
configure terminal
switch domain LABDOM01
show tcp-connections
show interface
```

---

## Validation

- [ ] Your Exercise 1 XML has two distinct `FrontProtocol` entries under one `MultiProtocolGateway`, sharing a single `StylePolicy`.
- [ ] You correctly identified the Exercise 3 defect as a duplicate {IP, port} binding, not a naming issue.
- [ ] You can state, in one sentence, the difference between "multiple FSH on one service" (valid fan-in) vs "two FSH on the same tuple" (invalid conflict).
- [ ] You can name which FSH class you'd choose for a legacy request-reply MQ integration.

---

## Key Takeaways

- One gateway service can bind multiple FSH objects — this is the standard pattern for differentiated internal/external entry points.
- {IP, port} uniqueness is enforced per FSH object; virtual hosting via Host header is the correct way to share a port across services.
- MQ FSH surfaces MQMD fields into the processing context — essential for request-reply bridging.
- HTTPS FSH always references an `SSLProxyProfile` — there is no "just enable TLS" toggle without a crypto identity behind it (Day 38–39).

---

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-30-Back-Side-Routing]] →
