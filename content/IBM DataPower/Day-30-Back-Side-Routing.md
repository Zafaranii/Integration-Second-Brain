---
tags: [datapower, bucket-3, architecture, day-30]
created: 2026-07-05
bucket: 3
week: 6
day: 30
status: not-started
---

# Day 30 — Back-Side Routing

> [!info] Why This Day Exists
> Back-side routing is where "content-based routing" and "load-balanced failover" actually get implemented. It's also where a careless dynamic-routing rule turns into an SSRF vulnerability — this day closes out Week 6's architecture arc before Week 7 goes deep on the rule engine itself.

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-31-Processing-Rules-and-Match-Actions]] →

---

## Theory

### Routing Modes

Back-side routing determines where the (possibly transformed) message goes after processing rules run — distinct from front-side binding, which only governs how the connection arrived.

| Mode                      | Mechanism                                                                                                       |
| ------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Static                    | `BackendUrl` fixed at config time                                                                               |
| Dynamic (XPath Routing)   | A **Route** processing action evaluates an expression against the message/context to compute the URL at runtime |
| Loopback                  | Message routed back into DataPower itself — used for pure validation/echo services                              |
| Load Balancer Group (LBG) | Backend is a pool object (`LoadBalancerGroup`) with multiple members and a selection algorithm                  |

### The Route Action

A Route action inside a `StylePolicyRule` sets the runtime routing URL (conceptually `var://service/routing-url`), which the gateway consults **after** the rule completes — overriding any static `BackendUrl`. This is how "route order X to region A, order Y to region B" content-based routing is implemented.

### Load Balancer Group Properties

| Property      | Meaning                                                                      |
| ------------- | ---------------------------------------------------------------------------- |
| `Algorithm`   | `round-robin`, `weighted`, `random`, `least-connections`                     |
| `Member`      | Each backend entry — IP/host, port, weight                                   |
| `HealthCheck` | Active probing (interval, method, expected response) to mark members up/down |

> [!warning] Retry ≠ Failover
> LBG failover applies at **connection-establishment time**, not mid-response. If a backend accepts the TCP connection then hangs, that's a `ConnectTimeout`/`ResponseTimeout` scenario — not LBG failover. Don't conflate the two when writing an incident postmortem.

> [!danger] Dynamic Routing Is an SSRF Vector
> If the routing URL is derived from untrusted input (e.g., a header value used directly as a hostname), that's an SSRF-class vulnerability. Production XPath/GatewayScript Route actions must validate the computed destination against an allow-list before committing — never trust raw client-supplied destination values.

---

## Your Stack, Concretely

| Scenario                                  | DataPower reality                                                                                                      |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Single backend, no redundancy             | Static `BackendUrl` — simplest, but zero failover                                                                      |
| Two-region active/active backend          | `LoadBalancerGroup` with round-robin + `HealthCheck`, referenced from the MPGW instead of a bare `BackendUrl`          |
| Order payload routed by `region` field    | Route action (GatewayScript or XPath) inspects the parsed body and sets the routing URL before the rule completes      |
| A backend accepts TCP then never responds | Diagnosed via `ResponseTimeout`, not LBG health status — the LBG member still looks "up" from a TCP-accept perspective |

---

## Hands-on

### Exercise 1 — Static vs LBG Export Comparison

Static (single, no failover):

```xml
<MultiProtocolGateway name="StaticGW">
  <Type>static-backend</Type>
  <BackendUrl>http://orders-a.internal:8080/orders</BackendUrl>
</MultiProtocolGateway>
```

LBG-backed (failover-capable):

```xml
<MultiProtocolGateway name="LBGatedGW">
  <Type>static-backend</Type>
  <LoadBalancerGroup class="LoadBalancerGroup">OrdersLBG</LoadBalancerGroup>
</MultiProtocolGateway>

<LoadBalancerGroup name="OrdersLBG">
  <mAdminState>enabled</mAdminState>
  <Algorithm>round-robin</Algorithm>
  <Member>
    <RemoteAddress>orders-a.internal</RemoteAddress>
    <RemotePort>8080</RemotePort>
    <Weight>1</Weight>
  </Member>
  <Member>
    <RemoteAddress>orders-b.internal</RemoteAddress>
    <RemotePort>8080</RemotePort>
    <Weight>1</Weight>
  </Member>
  <HealthCheck>
    <Interval>30</Interval>
    <Method>HEAD</Method>
    <Path>/health</Path>
    <ExpectedStatus>200</ExpectedStatus>
  </HealthCheck>
</LoadBalancerGroup>
```

### Exercise 2 — GatewayScript Dynamic Route Snippet

Content-based routing: if payload field `region` = `"EU"`, route to the EU backend, else default to US.

```javascript
// dynamic-route.js
var body = session.input.readAsJSON()

var target = "http://orders-us.internal:8080/orders"
if (body && body.region === "EU") {
  target = "http://orders-eu.internal:8080/orders"
}

// Set the routing URL for the gateway to use post-rule
session.output.route(target)
```

Annotate: why must the region check happen **before** the routing decision commits, and what happens if `body.region` is attacker-controlled and unvalidated against an allow-list?

### Exercise 3 — CLI: Inspect LBG Member Health

```
configure terminal
switch domain LABDOM01
show load-balancer-group OrdersLBG
```

Write down what a `down` status on one member should trigger operationally (alerting, not silent degradation).

---

## Validation

- [ ] Your LBG XML includes `Algorithm`, two `Member` entries, and a `HealthCheck` block — omitting `HealthCheck` means DataPower has no proactive way to detect a dead member.
- [ ] You identified the SSRF risk in Exercise 2 and can state the one-line mitigation (allow-list validation before route commit).
- [ ] You can explain the difference between "LBG failover" and "request retry after timeout" without conflating them.
- [ ] Quick recall: which action sets the runtime routing URL, and does it override a static `BackendUrl`?

---

## Key Takeaways

- Static routing is simplest but has zero failover; LBG adds pooling, algorithm-based selection, and active health checks.
- The Route action overrides static `BackendUrl` at runtime — this is the mechanism behind all content-based routing.
- LBG failover is connection-time only; a hung-but-connected backend is a timeout problem, not an LBG problem.
- Any dynamic routing driven by client-supplied data is an SSRF surface unless validated against an allow-list.

---

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-31-Processing-Rules-and-Match-Actions]] →

---

🎉 **Week 6 Complete** — MPGW/WSP architecture, FSH, and back-side routing form the skeleton. Week 7 builds the muscle: processing policy internals.
