---
tags: [datapower, bucket-3, processing-policy, day-31]
created: 2026-07-05
bucket: 3
week: 7
day: 31
status: not-started
---

# Day 31 — Processing Rules and Match Actions

> [!info] Why This Day Exists
> The StylePolicy is DataPower's actual rule engine — everything from Week 6 (services, FSH, routing) exists to feed traffic into this engine. Understanding how rules match and execute in sequence is the prerequisite for every action type in the rest of this week.

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-32-Transform-Actions-GatewayScript]] →

---

## Theory

### StylePolicy Structure

A `StylePolicy` object is a container for one or more `StylePolicyRule` objects. Each rule has:

- A **direction**: `request`, `response`, or `error` (Day 34) — a rule only fires for traffic moving in the direction it's bound to.
- A **Match** reference (a `MatchAction` object) that determines whether the rule applies to a given message.
- An ordered list of **actions** (`StylePolicyAction`) that execute sequentially if the match succeeds.

> [!warning] Rule Evaluation Order Matters
> Within a StylePolicy, rules are evaluated in the order they appear, and **the first matching rule for a given direction wins** — subsequent rules for that same direction are not evaluated unless the matched rule explicitly falls through or the policy is structured with a catch-all default. This trips up anyone assuming all matching rules fire like independent event handlers; they don't.

### Match Actions

A `MatchAction` object defines matching criteria independently of any one rule, so it can be reused across rules/services. Matching can be based on:

| Match type        | Example basis                                      |
| ----------------- | -------------------------------------------------- |
| URL match         | Request URI pattern (glob or regex)                |
| HTTP header match | Presence/value of a specific header (e.g., `Host`) |
| HTTP method match | `GET`, `POST`, etc.                                |
| XPath match       | Content of the parsed XML body                     |
| Error code match  | Used only in error-direction rules (Day 34)        |

A single `MatchAction` object can combine multiple criteria (e.g., URL glob **and** HTTP method) — all specified criteria must be satisfied for the match to succeed (logical AND across criteria within one MatchAction).

### Actions Within a Rule

Once matched, a rule executes its actions **in the order listed** — a Transform action's output becomes the input to the next action in the same rule. Common action types (detailed in later days):

| Action                    | Purpose                             | Day   |
| ------------------------- | ----------------------------------- | ----- |
| Transform (GatewayScript) | Programmatic message manipulation   | 32    |
| Transform (XSLT)          | XSLT-based transformation           | 33    |
| AAA                       | Authentication/authorization        | 36–37 |
| Filter                    | Conditional accept/reject           | 35    |
| Validate                  | Schema/WS-I compliance check        | 35    |
| Convert                   | Format conversion (e.g., XML↔JSON) | 35    |
| Route                     | Dynamic backend selection           | 30    |

---

## Your Stack, Concretely

| Scenario                                                 | DataPower reality                                                                                                                                      |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Different processing for `GET /orders` vs `POST /orders` | Two `StylePolicyRule` objects, each bound to a `MatchAction` filtering on HTTP method, both under the same `direction=request`                         |
| A catch-all rule for unmatched traffic                   | A rule with a broad/wildcard `MatchAction` placed **last** in the policy — order-dependent, must be after all specific rules                           |
| Reusing the same header-based match across 3 services    | One `MatchAction` object referenced by 3 different `StylePolicyRule` objects across services — same reuse-by-reference pattern as `StylePolicy` itself |

---

## Hands-on

### Exercise 1 — Read a Multi-Rule StylePolicy Export

```xml
<StylePolicy name="OrdersPolicy">
  <mAdminState>enabled</mAdminState>
  <PolicyMapEntry>
    <Direction>request</Direction>
    <Match class="MatchAction">MatchGetOrders</Match>
    <Rule class="StylePolicyRule">GetOrdersRule</Rule>
  </PolicyMapEntry>
  <PolicyMapEntry>
    <Direction>request</Direction>
    <Match class="MatchAction">MatchPostOrders</Match>
    <Rule class="StylePolicyRule">PostOrdersRule</Rule>
  </PolicyMapEntry>
  <PolicyMapEntry>
    <Direction>request</Direction>
    <Match class="MatchAction">MatchAllDefault</Match>
    <Rule class="StylePolicyRule">DefaultRejectRule</Rule>
  </PolicyMapEntry>
</StylePolicy>

<MatchAction name="MatchGetOrders">
  <HTTPTypeMatch>GET</HTTPTypeMatch>
  <UrlMatch>/orders*</UrlMatch>
</MatchAction>

<MatchAction name="MatchPostOrders">
  <HTTPTypeMatch>POST</HTTPTypeMatch>
  <UrlMatch>/orders*</UrlMatch>
</MatchAction>

<MatchAction name="MatchAllDefault">
  <UrlMatch>*</UrlMatch>
</MatchAction>
```

Answer: if a `PUT /orders/123` request arrives, which rule fires? Why must `MatchAllDefault` be listed **last** in the `PolicyMapEntry` sequence for this to work correctly?

### Exercise 2 — Write a Rule With Multiple Sequential Actions

Build the export fragment for `PostOrdersRule` containing two actions in sequence: a Transform (GatewayScript, stubbed for now — full detail Day 32) followed by a Route action.

```xml
<StylePolicyRule name="PostOrdersRule">
  <Action class="StylePolicyAction">
    <Type>gatewayscript</Type>
    <GatewayScriptFile>local:///scripts/validate-order-body.js</GatewayScriptFile>
  </Action>
  <Action class="StylePolicyAction">
    <Type>route</Type>
    <RouteFile>local:///scripts/dynamic-route.js</RouteFile>
  </Action>
</StylePolicyRule>
```

Reason about action ordering: what breaks if `route` were listed **before** the `gatewayscript` validation action, given that the routing decision in Day 30's exercise depended on a parsed body field?

### Exercise 3 — CLI Rule Inspection

```
configure terminal
switch domain LABDOM01
show style-policy OrdersPolicy
```

---

## Validation

- [ ] You correctly identified that `PUT /orders/123` falls through to `DefaultRejectRule` since neither `MatchGetOrders` nor `MatchPostOrders` matches the method.
- [ ] You can explain, in one sentence, why match-rule ordering (`MatchAllDefault` last) is functionally required, not just a style convention.
- [ ] You identified that putting `route` before the validating `gatewayscript` action would route based on unvalidated/unparsed data — same class of bug as Day 30's SSRF warning, now framed as an ordering mistake.

---

## Key Takeaways

- StylePolicy = ordered rules; each rule = one Match + a sequential action list.
- First matching rule wins per direction — this is not an independent-event-handler model.
- MatchAction objects are reusable across rules and services, same reference pattern as StylePolicy itself.
- Action order within a rule is execution order — a later action always sees the prior action's output, never the reverse.

---

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-32-Transform-Actions-GatewayScript]] →
