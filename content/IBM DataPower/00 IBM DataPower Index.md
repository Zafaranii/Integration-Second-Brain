---
tags:
  - datapower
  - bucket-3
  - index
  - moc
created: 2026-07-05
bucket: 3
status: active
---

# Bucket 3 — IBM DataPower Gateway

> As an integration engineer, DataPower is the enforcement point where transport, security, and message contracts actually get checked before a request ever reaches your ACE flow or backend service. This module covers gateway service architecture (MPGW vs WSP), the processing policy engine (rules, matching, transforms, error handling), and the security subsystems (AAA, crypto objects, TLS profiles) that make DataPower a gateway rather than just a reverse proxy.

**Tags:** #datapower #gateway #index

---

## Map of Content

### Week 6 — Gateway Architecture

| Day                                                    | Topic                                   |
| ------------------------------------------------------ | --------------------------------------- |
| [[Day-26-DataPower-Architecture-Fundamentals\|Day 26]] | DataPower Architecture Fundamentals     |
| [[Day-27-Multi-Protocol-Gateway-Deep-Dive\|Day 27]]    | Multi-Protocol Gateway (MPGW) Deep Dive |
| [[Day-28-Web-Service-Proxy-vs-MPGW\|Day 28]]           | Web Service Proxy (WSP) vs MPGW         |
| [[Day-29-Front-Side-Handlers\|Day 29]]                 | Front-Side Handlers                     |
| [[Day-30-Back-Side-Routing\|Day 30]]                   | Back-Side Routing                       |

### Week 7 — Processing Policy

| Day                                                    | Topic                                 |
| ------------------------------------------------------ | ------------------------------------- |
| [[Day-31-Processing-Rules-and-Match-Actions\|Day 31]]  | Processing Rules and Match Actions    |
| [[Day-32-Transform-Actions-GatewayScript\|Day 32]]     | Transform Actions — GatewayScript     |
| [[Day-33-Transform-Actions-XSLT\|Day 33]]              | Transform Actions — XSLT              |
| [[Day-34-Error-Handling-and-Error-Rules\|Day 34]]      | Error Handling and Error Rules        |
| [[Day-35-Filter-Validate-and-Convert-Actions\|Day 35]] | Filter, Validate, and Convert Actions |

### Week 8 — Security and Wrap-up

| Day                                                     | Topic                                  |
| ------------------------------------------------------- | -------------------------------------- |
| [[Day-36-AAA-Policy-Authentication\|Day 36]]            | AAA Policy — Authentication Phases     |
| [[Day-37-AAA-Policy-Authorization\|Day 37]]             | AAA Policy — Authorization Phases      |
| [[Day-38-Crypto-Objects-Keys-and-Certificates\|Day 38]] | Crypto Objects — Keys and Certificates |
| [[Day-39-TLS-Profiles-and-SSL-Proxy\|Day 39]]           | TLS Profiles and SSL Proxy Profiles    |
| [[Day-40-DataPower-Wrapup-and-Troubleshooting\|Day 40]] | DataPower Wrap-up and Troubleshooting  |

---

## Concept Index

- **Gateway service types** → [[Day-26-DataPower-Architecture-Fundamentals]], [[Day-27-Multi-Protocol-Gateway-Deep-Dive]], [[Day-28-Web-Service-Proxy-vs-MPGW]]
- **Transport termination** → [[Day-29-Front-Side-Handlers]], [[Day-30-Back-Side-Routing]]
- **Processing policy engine** → [[Day-31-Processing-Rules-and-Match-Actions]], [[Day-32-Transform-Actions-GatewayScript]], [[Day-33-Transform-Actions-XSLT]]
- **Resilience & faults** → [[Day-34-Error-Handling-and-Error-Rules]], [[Day-30-Back-Side-Routing]]
- **Content actions** → [[Day-35-Filter-Validate-and-Convert-Actions]]
- **AuthN/AuthZ** → [[Day-36-AAA-Policy-Authentication]], [[Day-37-AAA-Policy-Authorization]]
- **PKI / TLS** → [[Day-38-Crypto-Objects-Keys-and-Certificates]], [[Day-39-TLS-Profiles-and-SSL-Proxy]]
- **Synthesis** → [[Day-40-DataPower-Wrapup-and-Troubleshooting]]

---

## Object Class Reference

| Concept                    | XML Class Name          |
| -------------------------- | ----------------------- |
| Multi-Protocol Gateway     | `MultiProtocolGateway`  |
| Web Service Proxy          | `WSGateway`             |
| Front Side Handler (HTTP)  | `HTTPFrontSideHandler`  |
| Front Side Handler (HTTPS) | `HTTPSFrontSideHandler` |
| Front Side Handler (MQ)    | `MQFrontSideHandler`    |
| Load Balancer Group        | `LoadBalancerGroup`     |
| Processing Policy          | `StylePolicy`           |
| Processing Rule            | `StylePolicyRule`       |
| Rule Action (generic)      | `StylePolicyAction`     |
| Matching Rule              | `MatchAction`           |
| AAA Policy                 | `AAAPolicy`             |
| Crypto Key                 | `CryptoKey`             |
| Crypto Certificate         | `CryptoCertificate`     |
| Identification Credential  | `CryptoIdentCred`       |
| Validation Credential      | `CryptoValCred`         |
| SSL Proxy Profile          | `SSLProxyProfile`       |

---

## Service Type Decision Tree

```
Need a gateway service?
│
├── Is the contract a governed WSDL (SOAP)?
│   ├── Yes → WSP (WSGateway) — automatic schema validation + SOAP faults
│   └── No  → continue
│
├── Is the payload REST/JSON, binary, or mixed protocol?
│   └── Yes → MPGW (MultiProtocolGateway)
│
├── Need to bridge MQ ↔ HTTP?
│   └── MPGW with MQFrontSideHandler + HTTP backend (or reverse)
│
└── Pure TLS termination, no transform, no contract enforcement?
    └── Either works — prefer WSP only if WSDL governance already exists
```

---

**Navigation:** [[Day-26-DataPower-Architecture-Fundamentals|Day 26 →]]
