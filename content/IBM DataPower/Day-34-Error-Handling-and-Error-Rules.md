---
tags: [datapower, bucket-3, processing-policy, error-handling, day-34]
created: 2026-07-05
bucket: 3
week: 7
day: 34
status: not-started
---

# Day 34 — Error Handling and Error Rules

> [!info] Why This Day Exists
> Every `throw` in GatewayScript (Day 32) and every `dp:reject()` in XSLT (Day 33) has to go somewhere. This day covers where — and how to make sure a failure surfaces a useful, controlled response instead of a raw stack trace or a silent hang.

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-35-Filter-Validate-and-Convert-Actions]] →

---

## Theory

### The Third Direction: `error`

Recall from Day 31 that `StylePolicyRule` objects bind to a direction: `request`, `response`, or `error`. The `error` direction is special — it fires when processing in the request or response direction fails (uncaught exception, explicit reject, validation failure, timeout, etc.), rather than firing on normal inbound/outbound traffic.

### Error Rule Matching

Error-direction rules can match on:

| Match basis           | Example                                            |
| --------------------- | -------------------------------------------------- |
| Error code            | e.g., a specific internal DataPower error code     |
| Error message pattern | Glob/regex against the error text                  |
| Catch-all             | No specific criteria — matches any unhandled error |

Just like request/response rules (Day 31), **the first matching error rule wins**, and a catch-all error rule should be last in the policy's error `PolicyMapEntry` sequence.

### Reject vs Abort — Distinct Outcomes

| Outcome    | Behavior                                                                                                                                                      |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Reject** | Transaction fails with a controlled, typically client-facing error response (e.g., custom JSON/XML error body, appropriate HTTP status)                       |
| **Abort**  | Transaction terminates more abruptly — commonly used when continuing processing would be unsafe/meaningless, with less emphasis on a polished client response |

> [!warning] Uncontrolled Errors Leak Information
> An error rule that doesn't sanitize the outgoing error body risks leaking internal details — backend hostnames, stack traces, internal object names — to an external client. Production error rules should map internal errors to a **generic, sanitized external message** while the internal detail goes to a log target (Day 40) for the actual troubleshooting.

### Building a Custom Error Response

A typical error rule pattern: match the error → run a Transform action (GatewayScript or XSLT) that constructs a clean, client-appropriate error body → set the appropriate HTTP status via context variable → return.

---

## Your Stack, Concretely

| Scenario                                                          | DataPower reality                                                                                                                                                            |
| ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| GatewayScript validation throws "Missing required field: orderId" | Falls through to the service's error rule; a well-built error rule renders this as a clean `400 Bad Request` JSON body to the client, without leaking the raw exception text |
| Backend connection times out                                      | Surfaces as an error-direction event distinct from an explicit application-level reject — often needs its own matching error rule mapping to a `504`-style response          |
| A misconfigured StylePolicy has no error rule at all              | DataPower falls back to a default/generic error response — acceptable for a dev sandbox, unacceptable for a production API where consistent error contracts matter           |

---

## Hands-on

### Exercise 1 — Read an Error-Direction PolicyMapEntry

```xml
<StylePolicy name="OrdersPolicy">
  <!-- ... request/response entries from Day 31 ... -->

  <PolicyMapEntry>
    <Direction>error</Direction>
    <Match class="MatchAction">MatchValidationError</Match>
    <Rule class="StylePolicyRule">ValidationErrorRule</Rule>
  </PolicyMapEntry>
  <PolicyMapEntry>
    <Direction>error</Direction>
    <Match class="MatchAction">MatchAllErrors</Match>
    <Rule class="StylePolicyRule">GenericErrorRule</Rule>
  </PolicyMapEntry>
</StylePolicy>

<MatchAction name="MatchValidationError">
  <ErrorMessageMatch>*Missing required field*</ErrorMessageMatch>
</MatchAction>

<MatchAction name="MatchAllErrors">
  <ErrorMessageMatch>*</ErrorMessageMatch>
</MatchAction>
```

Answer: why must `MatchAllErrors` be listed after `MatchValidationError`, using the same reasoning as Day 31's request-direction ordering rule?

### Exercise 2 — Write a Sanitizing Error Transform

A GatewayScript snippet used inside `GenericErrorRule` to build a clean, generic client-facing error body while the raw error detail is left to the log target rather than the response:

```javascript
// generic-error-response.js
// Assume the raw caught error text is available via a context variable
// (exact retrieval API varies by firmware — verify against current docs).
var rawErrorText = session.input.readAsBufferSync
  ? session.input.readAsBufferSync().toString()
  : "unknown error"

var clientSafeBody = {
  status: "error",
  message: "The request could not be processed. Please contact support with reference ID below.",
  referenceId: "ERR-" + Date.now(),
}

// rawErrorText is intentionally NOT included in clientSafeBody --
// it belongs in a log target (Day 40), not the client response.

session.output.write(JSON.stringify(clientSafeBody))
```

Annotate: why is `rawErrorText` deliberately excluded from `clientSafeBody`, and where should it actually go instead?

### Exercise 3 — CLI: Check Error Rule Firing History

```
configure terminal
switch domain LABDOM01
show log-target
```

(Real diagnosis of "which error rule fired and why" typically involves reviewing the domain's log target output and/or a Probe trace — covered fully in Day 40.)

---

## Validation

- [ ] You can explain why error-rule ordering follows the same first-match-wins logic as request/response rules from Day 31.
- [ ] You identified that raw error/exception detail must never land directly in the client-facing response body — it belongs in a log target.
- [ ] You can distinguish Reject (controlled, client-facing) from Abort (abrupt termination) in one sentence each.

---

## Key Takeaways

- The `error` direction is a first-class rule direction, matched and ordered exactly like `request`/`response`.
- Reject produces a controlled, typically client-facing outcome; Abort is a more abrupt termination for unsafe-to-continue states.
- A missing or generic-only error rule is a production risk — inconsistent, potentially information-leaking error responses are the usual symptom.
- Sanitize client-facing error bodies; route the real diagnostic detail to a log target, not the response.

---

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-35-Filter-Validate-and-Convert-Actions]] →
