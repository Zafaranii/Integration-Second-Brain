---
tags: [datapower, bucket-3, architecture, day-26]
created: 2026-07-05
bucket: 3
week: 6
day: 26
status: not-started
---

# Day 26 — DataPower Architecture Fundamentals

> [!info] Why This Day Exists
> Before you touch a single processing rule, you need the appliance's mental model: domains, objects, and services. Almost every DataPower incident decomposes into "which domain, which object, which service type" — get this skeleton solid before Week 7's policy internals.

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-27-Multi-Protocol-Gateway-Deep-Dive]] →

---

## Theory

### The Appliance Model

DataPower is a hardened, purpose-built network appliance (physical, virtual, or containerized as IBM DataPower Gateway for Kubernetes) that terminates protocols, executes a declarative processing policy against messages in-flight, and re-originates the request to a backend. It is **not** a general-purpose server — no shell, no arbitrary OS package installs on physical/VM form factors. All behavior is configured via objects, not scripts on disk (with the partial exception of GatewayScript/XSLT files, which are themselves managed objects/files).

### Domains — The Isolation Boundary

| Domain type        | Characteristics                                                                  |
| ------------------ | -------------------------------------------------------------------------------- |
| `default`          | Appliance-wide admin; generally does not host application traffic                |
| Application domain | Isolated object namespace, separate `local:///` filesystem, separate log targets |

Two application domains cannot see each other's objects. This is DataPower's equivalent of a Kubernetes namespace or an MQ queue manager boundary — object names are only unique **within** a domain.

### Object Model

- Everything is an **object** with a class (`MultiProtocolGateway`, `CryptoKey`, etc.). Objects reference each other by `name` + `class` — configuration is a directed graph, not a flat file.
- Objects carry an **admin-state** (`mAdminState`: enabled/disabled) independent of their **operational state** (up/down at runtime).
- Configuration exists in two forms: **running config** (in memory, changes take effect immediately) and **persisted config** (written via `write memory` / "Save Config" to `local:///config`). A running-config-only change is lost on reboot.

> [!warning] Running vs Persisted Config
> This is the single most common "it worked yesterday, gone today" incident cause in DataPower shops. If a change was made in running config and nobody ran `write memory`, a reboot or firmware patch silently reverts it. Always confirm persistence after any change window.

### Gateway Service Types

| Service                       | Purpose                                                                |
| ----------------------------- | ---------------------------------------------------------------------- |
| Multi-Protocol Gateway (MPGW) | Generic any-to-any protocol gateway, protocol-agnostic body handling   |
| Web Service Proxy (WSP)       | WSDL-aware SOAP proxy with built-in schema validation                  |
| XML Firewall (legacy)         | Deprecated single-purpose predecessor to MPGW — appears in old exports |
| API Gateway (newer firmware)  | OpenAPI/Swagger-driven REST-first proxy                                |

### Request Lifecycle (Conceptual)

1. Front Side Handler accepts the transport-level connection.
2. Service resolves which Processing Policy (`StylePolicy`) applies.
3. Processing Rule(s) execute in sequence: Match → Actions.
4. Back-side routing determines the (possibly transformed) message's destination.
5. Response flows back through a (possibly different) response-direction rule.

---

## Your Stack, Concretely

| Scenario                                         | DataPower reality                                                                                                                                                                                                                          |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| ACE flow calling a partner API through DataPower | DataPower terminates the client TCP connection at an FSH, applies a StylePolicy, then **opens a brand-new TCP connection** to the ACE HTTP Listener. Two independent handshakes, exactly like the DataPower→ACE hop described in Bucket 1. |
| Two app teams sharing one physical appliance     | Each team gets an application **domain** — object names, logs, and `local:///` storage are isolated even though the underlying hardware/firmware is shared.                                                                                |
| A firmware patch window                          | Any running-config-only change not persisted via `write memory` is lost when the box reboots post-patch — this is a frequent post-patch incident cause.                                                                                    |
| MQ ↔ HTTP bridging requirement                  | Handled by an MPGW (not WSP), since WSP assumes SOAP/WSDL and MQ payloads are typically non-SOAP.                                                                                                                                          |

---

## Hands-on

### Exercise 1 — Read a Minimal Domain Export

DataPower's config backup/migration format is **export XML** (`Administration > Configuration > Export Configuration`, or CLI `write memory` / `copy running-config`). Below is a trimmed, real-shape export for a domain with a disabled placeholder service:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<datapower-configuration version="7.6" domain="APIDOM01">
  <configuration>
    <Domain name="APIDOM01">
      <mAdminState>enabled</mAdminState>
    </Domain>
    <MultiProtocolGateway name="PlaceholderMPGW">
      <mAdminState>disabled</mAdminState>
      <FrontProtocol class="HTTPFrontSideHandler">PlaceholderFSH</FrontProtocol>
      <StylePolicy class="StylePolicy">PlaceholderPolicy</StylePolicy>
    </MultiProtocolGateway>
    <HTTPFrontSideHandler name="PlaceholderFSH">
      <mAdminState>disabled</mAdminState>
      <Port>8080</Port>
      <LocalAddress>0.0.0.0</LocalAddress>
    </HTTPFrontSideHandler>
  </configuration>
</datapower-configuration>
```

Answer, in your own notes:

1. Which element defines the isolation boundary?
2. If `PlaceholderMPGW` were `enabled` but `PlaceholderFSH` stayed `disabled`, what happens operationally?
3. Why does `MultiProtocolGateway` reference `FrontProtocol`/`StylePolicy` by name+class instead of embedding them inline?

### Exercise 2 — CLI Navigation

```
# Enter config mode
configure terminal

# Switch into the application domain
switch domain APIDOM01

# List all MPGW objects in the current domain
show mpgw

# Show detailed status of one service
show mpgw PlaceholderMPGW

# Persist running config to flash
write memory
```

### Exercise 3 — Build Your Own Skeleton Export

Create an export XML for domain `LABDOM01` containing one **enabled** `MultiProtocolGateway` named `EchoGW`, referencing an enabled `HTTPFrontSideHandler` named `EchoFSH` on port `9080`. Save it as `Day26-lab-export.xml` in your vault's attachments folder.

---

## Validation

- [ ] Your Exercise 3 XML has matching `name` attributes between the `FrontProtocol` reference and the actual `HTTPFrontSideHandler` object — a mismatch is the #1 cause of "service won't start."
- [ ] You can explain why `write memory` is distinct from an object simply being `enabled` in running config.
- [ ] Self-test: what isolates App Team A's objects from App Team B's on the same physical appliance? (Answer: domain, not service.)

---

## Key Takeaways

- DataPower configuration is a directed graph of named, classed objects — not a flat file.
- Domains are the hard isolation boundary; object names are only unique within a domain.
- Admin-state ≠ operational state; a dependent object being down can leave a service admin-enabled but operationally dead.
- Running config changes are volatile until `write memory` persists them.
- Four service types exist, but MPGW and WSP are the two you'll live in day-to-day.

---

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-27-Multi-Protocol-Gateway-Deep-Dive]] →
