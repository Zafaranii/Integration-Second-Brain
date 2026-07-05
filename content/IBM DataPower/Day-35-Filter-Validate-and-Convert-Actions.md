---
tags: [datapower, bucket-3, processing-policy, day-35]
created: 2026-07-05
bucket: 3
week: 7
day: 35
status: not-started
---

# Day 35 — Filter, Validate, and Convert Actions

> [!info] Why This Day Exists
> Not every rule action is a full Transform. Filter, Validate, and Convert are lighter-weight, purpose-built actions that handle three extremely common needs — conditional gating, schema enforcement, and format conversion — without hand-rolling logic in GatewayScript or XSLT every time. This closes out Week 7's processing-policy arc.

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-36-AAA-Policy-Authentication]] →

---

## Theory

### Filter Action

A Filter action conditionally accepts or rejects a message based on a configured condition (often an XPath or matching expression), **without** requiring a full script. Conceptually a lightweight gate placed inline in a rule's action sequence — if the condition fails, the transaction is rejected before later actions run.

### Validate Action

A Validate action checks the message body against a schema — XSD for XML, or (on firmware supporting it) a JSON Schema for JSON bodies. Key properties:

| Property            | Meaning                                                  |
| ------------------- | -------------------------------------------------------- |
| `SchemaFile`        | Reference to the XSD/JSON Schema used for validation     |
| `ValidateDirection` | Whether validation applies to request, response, or both |

Recall from Day 28: WSP performs this **automatically** from its bound WSDL. In MPGW, an explicit Validate action is the only way to get equivalent schema enforcement — this is precisely the gap that gets missed in "WSP downgraded to MPGW" migrations.

### Convert Action

A Convert action transforms between structural formats — most commonly XML↔JSON — without needing custom GatewayScript/XSLT for the mechanical conversion itself. Useful when:

- A legacy XML backend needs to be presented as JSON to modern clients (Convert JSON→XML on request, XML→JSON on response).
- A partner sends XML but internal processing/logging standardizes on JSON.

> [!warning] Convert Is Structural, Not Semantic
> A Convert action performs structural translation (element↔key mapping) — it does **not** perform field renaming, business-rule validation, or semantic restructuring. Those still require a Transform action (GatewayScript/XSLT). Don't reach for Convert expecting it to also rename fields; chain a Transform after it if renaming is needed.

### Action Ordering Recap (Ties to Day 31)

A typical hardened rule sequence: **Validate → Filter → Convert → Transform → Route**, though exact ordering depends on the use case — the key discipline is that gating/rejection actions (Validate, Filter) should generally run **before** expensive transformation work, so malformed or disallowed messages fail fast.

---

## Your Stack, Concretely

| Scenario                                                                           | DataPower reality                                                                                                                   |
| ---------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Enforce an XSD contract on an MPGW (no WSDL, so no automatic WSP-style validation) | Explicit Validate action referencing the XSD, placed early in the request rule                                                      |
| Reject any request missing a specific header before doing any expensive processing | Filter action checking header presence, placed first in the rule                                                                    |
| Legacy SOAP backend, modern JSON-speaking client                                   | Convert action (JSON→XML) on request, Convert action (XML→JSON) on response, likely paired with a Transform for field-level mapping |

---

## Hands-on

### Exercise 1 — Write a Hardened Rule: Validate → Filter → Convert → Transform

```xml
<StylePolicyRule name="HardenedOrdersRule">
  <Action class="StylePolicyAction">
    <Type>validate</Type>
    <SchemaFile>local:///schemas/order-request.xsd</SchemaFile>
    <ValidateDirection>request</ValidateDirection>
  </Action>
  <Action class="StylePolicyAction">
    <Type>filter</Type>
    <FilterCondition>header('X-Api-Key') != ''</FilterCondition>
  </Action>
  <Action class="StylePolicyAction">
    <Type>convert</Type>
    <ConvertFrom>json</ConvertFrom>
    <ConvertTo>xml</ConvertTo>
  </Action>
  <Action class="StylePolicyAction">
    <Type>xform</Type>
    <StylesheetFile>local:///xslt/order-field-mapping.xsl</StylesheetFile>
  </Action>
</StylePolicyRule>
```

Answer: why does `validate` run against the **original** body, before `convert` changes its structural format — what would validating **after** conversion get wrong (schema mismatch: the XSD is written for the pre-conversion or post-conversion shape, and mixing this up invalidates every request)?

### Exercise 2 — Diagnose a Convert-Only Misunderstanding

A teammate expects the following single-action rule to also rename the JSON field `cust_id` to `customerId` during conversion:

```xml
<StylePolicyRule name="NaiveConvertRule">
  <Action class="StylePolicyAction">
    <Type>convert</Type>
    <ConvertFrom>xml</ConvertFrom>
    <ConvertTo>json</ConvertTo>
  </Action>
</StylePolicyRule>
```

Explain in writing why this won't rename the field, and what needs to be added (a Transform action after Convert) to actually achieve the rename.

### Exercise 3 — CLI: List Actions Configured on a Rule

```
configure terminal
switch domain LABDOM01
show style-policy-rule HardenedOrdersRule
```

---

## Validation

- [ ] You correctly reasoned that Validate must run against the body's original format, matching the schema written for that format — not the post-Convert shape.
- [ ] You correctly identified that Convert is purely structural and does not perform field renaming — Exercise 2's teammate needs a Transform action chained after Convert.
- [ ] You can state the general ordering discipline: gating actions (Validate, Filter) before expensive transformation work, so bad input fails fast.

---

## Key Takeaways

- Filter and Validate are lightweight, purpose-built gating actions — use them instead of hand-rolling equivalent logic in GatewayScript where possible.
- Validate in MPGW is the manual equivalent of what WSP gives you automatically from a WSDL (Day 28) — a required addition in any MPGW handling contract-governed payloads.
- Convert handles structural format translation only (XML↔JSON); semantic changes (renaming, restructuring) still require a Transform action.
- Ordering discipline — validate/filter early, transform/route later — keeps rejected traffic cheap and keeps schema checks aligned to the correct body format.

---

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-36-AAA-Policy-Authentication]] →

---

🎉 **Week 7 Complete** — Processing rules, matching, transforms (GatewayScript + XSLT), error handling, and the supporting Filter/Validate/Convert actions round out the policy engine. Week 8 moves into security: AAA and crypto.
