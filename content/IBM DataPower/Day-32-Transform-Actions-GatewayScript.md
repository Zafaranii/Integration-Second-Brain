---
tags: [datapower, bucket-3, processing-policy, gatewayscript, day-32]
created: 2026-07-05
bucket: 3
week: 7
day: 32
status: not-started
---

# Day 32 — Transform Actions: GatewayScript

> [!info] Why This Day Exists
> GatewayScript is DataPower's JavaScript (Node.js-derived) runtime for in-flight message manipulation. It's the modern default for new development over XSLT (Day 33), especially for JSON-heavy REST traffic.

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-33-Transform-Actions-XSLT]] →

---

## Theory

### What GatewayScript Is

A CommonJS-style JavaScript runtime embedded in the DataPower firmware, exposing DataPower-specific globals and modules alongside standard JS. A Transform action of type `gatewayscript` points at a `.js` file (typically stored under `local:///scripts/`) that executes once per matched message.

### Core Session Object

| API                            | Purpose                                                               |
| ------------------------------ | --------------------------------------------------------------------- |
| `session.input.readAsBuffer()` | Read the raw request/response body as a Buffer                        |
| `session.input.readAsJSON()`   | Parse and return the body as a JSON object (throws if not valid JSON) |
| `session.input.readAsXML()`    | Parse and return the body as an XML DOM                               |
| `session.output.write(data)`   | Write data to become the message body for the next action             |
| `session.output.route(url)`    | Set the runtime backend routing URL (seen in Day 30)                  |

### Context Variables

DataPower exposes transaction metadata via context variable access (commonly through APIs like `apiGateway` on newer firmware, or the older `dp` module patterns depending on firmware version) — always verify the exact module/API surface against the firmware's actual documentation rather than assuming parity across versions, since GatewayScript APIs have evolved significantly across DataPower firmware releases.

> [!warning] Firmware Version Drift Is Real
> Do not assume a GatewayScript snippet written against one firmware version's API surface (module names, method signatures) runs unchanged on another. Older firmware and newer firmware diverge here more than XSLT does — XSLT is a W3C standard, GatewayScript's DataPower-specific modules are not.

### Error Handling Inside GatewayScript

Uncaught exceptions inside a GatewayScript transform typically abort the rule and are caught by the service's error rule (Day 34) rather than propagating a raw JS stack trace to the client — this is why explicit `try/catch` with meaningful error messages is a best practice, not just tidiness.

### Performance Note

GatewayScript operating in **non-XML mode** (Day 27) on JSON payloads avoids the cost of XML tokenization entirely — this is the primary reason GatewayScript + non-XML MPGW is the standard modern pairing for REST APIs, versus forcing JSON through an XML-oriented XSLT pipeline.

---

## Your Stack, Concretely

| Scenario                                                         | DataPower reality                                                                                            |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| REST API needs a field renamed/added before hitting the backend  | GatewayScript Transform action, `readAsJSON()` → mutate object → `session.output.write(JSON.stringify(obj))` |
| Legacy backend expects XML but new client sends JSON             | GatewayScript (or Convert action, Day 35) bridges JSON-in to XML-out before the backend hop                  |
| A malformed request should fail cleanly with a custom error body | GatewayScript `try/catch` around parsing, explicit reject/error signal consumed by the error rule (Day 34)   |

---

## Hands-on

### Exercise 1 — Basic JSON Field Transform

```javascript
// add-request-id.js
try {
  var body = session.input.readAsJSON()

  if (!body || typeof body !== "object") {
    throw new Error("Request body is not a valid JSON object")
  }

  // Inject a correlation identifier for downstream tracing
  body.requestId = "REQ-" + Date.now()

  session.output.write(JSON.stringify(body))
} catch (e) {
  // Let the error propagate to the service's error rule (Day 34)
  throw e
}
```

Annotate: why is `session.output.write` called with a **stringified** object rather than the raw JS object, and what would happen downstream if this step were skipped?

### Exercise 2 — Export Fragment Wiring the Script Into a Rule

```xml
<StylePolicyRule name="AddRequestIdRule">
  <Action class="StylePolicyAction">
    <Type>gatewayscript</Type>
    <GatewayScriptFile>local:///scripts/add-request-id.js</GatewayScriptFile>
  </Action>
</StylePolicyRule>
```

Confirm: does this rule need a `MatchAction` to actually run? (Yes — every `StylePolicyRule` is only invoked via a `PolicyMapEntry` pairing it with a match, per Day 31. A rule floating unreferenced in the export does nothing.)

### Exercise 3 — Defensive Parsing Pattern

Write a GatewayScript snippet that:

1. Attempts to read the body as JSON.
2. If parsing fails, catches the exception and explicitly throws a descriptive error (`"Invalid JSON payload received"`) rather than letting a generic parser exception surface.
3. On success, validates that a required field `orderId` is present, throwing a distinct descriptive error if missing.

```javascript
// validate-order-body.js
var body
try {
  body = session.input.readAsJSON()
} catch (e) {
  throw new Error("Invalid JSON payload received")
}

if (!body.orderId) {
  throw new Error("Missing required field: orderId")
}

session.output.write(JSON.stringify(body))
```

---

## Validation

- [ ] Your Exercise 1 answer correctly notes that `session.output.write` expects a string/buffer, not a raw object — skipping `JSON.stringify` would write `[object Object]` or fail outright.
- [ ] You can explain why a `StylePolicyRule` referencing a GatewayScript file is inert without a `PolicyMapEntry` + `MatchAction` pairing (ties back to Day 31).
- [ ] Your Exercise 3 snippet distinguishes a **parse failure** from a **validation failure** with two different, descriptive error messages — this distinction matters for the error rule's diagnostic value (Day 34).

---

## Key Takeaways

- GatewayScript is DataPower's JS runtime for programmatic message manipulation — the modern default for JSON/REST work.
- `session.input`/`session.output` are the core read/write surface; always write strings/buffers, never raw JS objects.
- GatewayScript's DataPower-specific module surface can drift across firmware versions — verify against current docs rather than assuming API parity, unlike XSLT which is standardized.
- Uncaught exceptions fall through to the error rule — explicit, descriptive `throw`s are a debugging investment, not boilerplate.

---

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-33-Transform-Actions-XSLT]] →
