---
tags: [datapower, bucket-3, troubleshooting, wrapup, day-40]
created: 2026-07-05
bucket: 3
week: 8
day: 40
status: not-started
---

# Day 40 — DataPower Wrap-up and Troubleshooting

> [!info] Why This Day Exists
> This closes Bucket 3 by tying every prior day into an actual troubleshooting workflow — the tools you reach for when a service misbehaves in production — plus a synthesis of the full request lifecycle across all 15 days.

**← Index:** [[00 IBM DataPower Index]]

---

## Theory

### The Three Core Diagnostic Tools

| Tool                           | Purpose                                                                                                                                                                                                               |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Probe**                      | Attaches to a service and captures a detailed, step-by-step trace of a transaction as it moves through the StylePolicy — showing exactly which rule matched, which actions ran, and the message content at each stage |
| **Log Targets**                | Persistent, queryable logging destinations (file, syslog, SNMP, etc.) — where sanitized error detail (Day 34) and general transaction logs should be routed                                                           |
| **Packet/Transaction Capture** | Lower-level capture of raw bytes on the wire, useful when the issue is suspected to be below the message-processing layer (malformed transport, TLS handshake failure)                                                |

### Probe — The Single Most Useful Tool for Policy Bugs

Probe shows, per transaction: which `PolicyMapEntry`/`MatchAction` fired, the exact input/output of each action (including Transform actions), and where in the sequence a Reject/Abort occurred. This is the direct, concrete way to validate everything from Weeks 6–8 — instead of guessing why a rule didn't match, Probe shows you the actual match evaluation.

### Log Target Best Practices (Ties to Day 34)

- Route detailed/raw error information to a log target, never into the client-facing error body.
- Separate log targets by severity/purpose where possible (audit trail vs. debug-level trace) so production log volume doesn't bury security-relevant events.
- Confirm log targets are covered by `write memory` persistence (Day 26) — a log target configured only in running config disappears on reboot along with everything else unpersisted.

### Full Request Lifecycle Synthesis (Days 26–39)

```
1. Client connects → Front Side Handler terminates transport (Day 29)
   - If HTTPS: SSL Proxy Profile handles handshake, optional mTLS enforcement (Day 39)
   - Uses CryptoIdentCred/CryptoValCred underneath (Day 38)

2. Gateway service (MPGW or WSP) receives the parsed/unparsed body (Days 26-28)
   - RequestType/ResponseType governs parser behavior

3. StylePolicy resolves the first matching request-direction rule (Day 31)

4. Rule actions execute in sequence, commonly:
   AAA (Days 36-37) → Validate/Filter (Day 35) → Transform (Days 32-33) → Route (Day 30)

5. Back-side routing sends the (possibly transformed) message to the backend
   - Static, dynamic (Route action), or Load Balancer Group (Day 30)

6. Response flows back through a response-direction rule (Day 31)
   - Possibly its own Transform/Convert actions

7. Any failure at any stage → error-direction rule (Day 34)
   - Sanitized response to client, detailed trace to log target (this day)
```

### Common Root-Cause Patterns Across This Bucket

| Symptom                                                             | Likely root cause (day reference)                                                                        |
| ------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| "Service rejects everything, no rule seems to run"                  | `RequestType` mismatch at the parser level (Day 27), before any rule executes                            |
| "Works for most partners, fails for one"                            | Incomplete cert chain in a `CryptoValCred` (Day 38)                                                      |
| "mTLS doesn't actually seem enforced"                               | `ClientAuthType` left as optional, or missing `ValCred` (Day 39)                                         |
| "Config change didn't survive the maintenance window"               | Running config never persisted via `write memory` (Day 26)                                               |
| "Field renamed as part of format conversion, but it wasn't"         | Convert action used alone, without a following Transform (Day 35)                                        |
| "Client sees a raw backend hostname/stack trace in an error"        | Error rule (Day 34) not sanitizing before response, or missing entirely                                  |
| "Authenticated fine, but everyone can still hit the write endpoint" | Phase 4 Authorization not actually implemented/wired, only Phase 2 Authentication configured (Day 36-37) |

---

## Your Stack, Concretely

| Scenario                                                                | DataPower reality                                                                                                                                                                                                 |
| ----------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Production incident: partner reports intermittent 502s                  | Start with Probe on the affected service, cross-reference log target output for the exact rule/action where the transaction failed, check whether it's a backend timeout (Day 30) vs. a policy rejection (Day 34) |
| Security review asks "prove mTLS is enforced end-to-end"                | Walk the object chain from FSH → SSLProxyProfile (`ClientAuthType=required`) → ValCred → AAA policy's identity extraction (Days 29, 36, 38, 39) as documented evidence                                            |
| New team member asks "where do I even start reading a DataPower export" | Domain → gateway service → FrontProtocol/StylePolicy references → PolicyMapEntry rules → individual actions — the exact order this bucket was taught in                                                           |

---

## Hands-on

### Exercise 1 — Write a Probe-Based Troubleshooting Runbook

Draft a short runbook (5–7 steps) for "Partner reports requests are being rejected with a generic error; we don't know which rule or action is responsible." Your runbook should explicitly mention: attaching Probe to the affected service, identifying the matched `PolicyMapEntry`, inspecting the failing action's input/output, and cross-referencing the error-direction rule that ultimately fired.

### Exercise 2 — CLI: Persistence and Config Audit Sequence

Write the full CLI sequence you'd run after a change window to confirm changes are both correct and persisted:

```
configure terminal
switch domain LABDOM01
show mpgw OrdersMPGW
show style-policy OrdersPolicy
show aaa-policy ApiKeyAuthPolicy
show ssl-proxy-profile ExternalServerSSLProfile
write memory
show running-config | diff startup-config
```

(Note: exact diff/compare syntax varies by firmware — the discipline is what matters: verify object state, then explicitly persist, then confirm persistence.)

### Exercise 3 — Full-Bucket Synthesis Exercise

Without looking back at prior days, sketch (in your own notes, prose or diagram) the complete object graph for a single hardened, mTLS-secured REST API on DataPower — starting from the `HTTPSFrontSideHandler` and ending at the backend `LoadBalancerGroup`, naming every object class involved (FSH → SSLProxyProfile → IdentCred/ValCred → Key/Certificate → MPGW → StylePolicy → PolicyMapEntry → MatchAction → StylePolicyRule → AAAPolicy → Validate/Transform/Route actions → LoadBalancerGroup). Then check it against Days 26–39.

### Exercise 4 — Export Fragment Audit

Given a hypothetical teammate's export containing an `HTTPSFrontSideHandler`, an `SSLProxyProfile` with `ClientAuthType=optional`, and an `AAAPolicy` doing `ssl-client-cert` identity extraction — identify the gap (mTLS is not actually enforced at the transport layer, so the AAA policy may receive no certificate to extract from at all in some connections) and state the one-line fix.

---

## Validation

- [ ] Your Exercise 1 runbook explicitly sequences Probe → matched rule/action → error-direction rule, not just "check the logs."
- [ ] You can explain, unprompted, the full 7-stage request lifecycle from the Theory section without referring back to it.
- [ ] Your Exercise 3 object graph correctly places `CryptoKey`/`CryptoCertificate` beneath `CryptoIdentCred`/`CryptoValCred`, beneath `SSLProxyProfile`, beneath the FSH — the full Day 38→39→29 chain.
- [ ] You identified the Exercise 4 gap (`ClientAuthType=optional` undermines the AAA policy's assumption that a client cert will always be present).

---

## Key Takeaways

- Probe is the primary tool for diagnosing "why didn't my rule/action do what I expected" — it shows actual match evaluation and per-action input/output, not just logs after the fact.
- Log targets are where sanitized-vs-detailed error information diverges (Day 34) — detailed traces belong there, not in client responses.
- Nearly every real DataPower incident maps back to one of a small number of root-cause patterns: parser-level type mismatches, incomplete cert chains, unpersisted config, or a security control that's wired but not actually enforced end-to-end.
- The full request lifecycle (FSH → service → StylePolicy → rule → actions → routing → response/error) is the mental model that ties all 15 days of this bucket together — every object introduced exists to fill one slot in that pipeline.

---

## 🎉 Bucket 3 Complete

You've covered:

- **Week 6** — Gateway architecture: MPGW vs WSP, Front-Side Handlers, back-side routing
- **Week 7** — Processing policy: rules, matching, GatewayScript/XSLT transforms, error handling, Filter/Validate/Convert
- **Week 8** — Security: AAA (authentication + authorization), crypto objects, TLS/SSL proxy profiles, and this troubleshooting synthesis

**← Index:** [[00 IBM DataPower Index]]
