---
tags:
  - index
  - moc
  - roadmap
  - integration
created: 2025-07-05
status: active
---

# 🧠 Integration Second Brain — Master Index

> **Pacing:** 1 Hour Daily / 5 Days a Week — **Format:** 15m Theory → 40m Hands-on → 5m Validation
> Ten weeks, four buckets, one throughline: get a request from a client socket to a working backend response, understand every layer it passed through, and be able to prove — not assume — that it's deployed correctly.

**Start Date:** 2026-07-05

---

## 🗺️ Bucket Overview

| #   | Bucket                             | Weeks | Focus                                                                                          | Index                                                      |
| --- | ---------------------------------- | ----- | ---------------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| 1   | 🌐 Core Networking & Routing       | 1–2   | TCP internals, load balancing, OpenShift routing, proxies/firewalls                            | [[Core Networking/00 Core Networking Index\|Open →]]       |
| 2   | 🔒 Deep Security                   | 3–5   | TLS/mTLS handshakes, CSRs & chains, keystores/truststores, crypto primitives, JWT              | [[Deep Security/00 Deep Security Index\|Open →]]           |
| 3   | 🛡️ IBM DataPower Gateway           | 6–8   | MPGW/WSP architecture, processing policy, AAA, crypto objects, TLS profiles                    | [[IBM DataPower/00 IBM DataPower Index\|Open →]]           |
| 4   | ⚙️ Integration DevOps & Automation | 9–10  | CI/CD for middleware, ACE BAR automation, MQ-as-code, GitOps, OpenShift deployment & debugging | [[Integration DevOps/00 Integration DevOps Index\|Open →]] |

---

## 📅 Full 50-Day Roadmap

### Bucket 1 — Core Networking (Weeks 1–2)

| Day                                                                          | Topic                                   |
| ---------------------------------------------------------------------------- | --------------------------------------- |
| [[Core Networking/Day-01-TCP-Handshake-and-Sockets\|Day 1]]                  | TCP Handshake and Sockets               |
| [[Core Networking/Day-02-Connection-Timeouts-vs-Read-Timeouts\|Day 2]]       | Connection Timeouts vs Read Timeouts    |
| [[Core Networking/Day-03-RST-Packets-and-Connection-Drops\|Day 3]]           | RST Packets and Connection Drops        |
| [[Core Networking/Day-04-TCP-Keepalives-vs-HTTP-Keep-Alive\|Day 4]]          | TCP Keepalives vs HTTP Keep-Alive       |
| [[Core Networking/Day-05-Packet-Captures-for-Middleware\|Day 5]]             | Packet Captures for Middleware          |
| [[Core Networking/Day-06-L4-vs-L7-Load-Balancing\|Day 6]]                    | L4 vs L7 Load Balancing                 |
| [[Core Networking/Day-07-OpenShift-Ingress-Routes-and-DNS\|Day 7]]           | OpenShift Ingress, Routes & DNS         |
| [[Core Networking/Day-08-Forward-Proxies-and-CONNECT-Tunnels\|Day 8]]        | Forward Proxies and CONNECT Tunnels     |
| [[Core Networking/Day-09-Diagnosing-Firewall-Drops\|Day 9]]                  | Diagnosing Firewall Drops               |
| [[Core Networking/Day-10-Networking-Wrap-up-and-Scenario-Debugging\|Day 10]] | Networking Wrap-up & Scenario Debugging |

### Bucket 2 — Deep Security (Weeks 3–5)

| Day                                                               | Topic                                |
| ----------------------------------------------------------------- | ------------------------------------ |
| [[Deep Security/Day-11-TLS-1.2-vs-1.3-Handshake\|Day 11]]         | TLS 1.2 vs 1.3 — Handshake Deep Dive |
| [[Deep Security/Day-12-Private-Keys-and-CSRs-OpenSSL\|Day 12]]    | Private Keys & CSRs with OpenSSL     |
| [[Deep Security/Day-13-Self-Signed-Certificates\|Day 13]]         | Self-Signed Certificates             |
| [[Deep Security/Day-14-CA-Chains-and-Trust-Stores\|Day 14]]       | CA Chains & Trust Stores             |
| [[Deep Security/Day-15-SNI-and-Week-3-Wrapup\|Day 15]]            | SNI & Week 3 Wrap-up                 |
| [[Deep Security/Day-16-One-Way-TLS-vs-mTLS\|Day 16]]              | One-Way TLS vs mTLS                  |
| [[Deep Security/Day-17-Building-a-Local-mTLS-Server\|Day 17]]     | Building a Local mTLS Server         |
| [[Deep Security/Day-18-Client-Keystores-and-Truststores\|Day 18]] | Client Keystores & Truststores       |
| [[Deep Security/Day-19-Kafka-mTLS-Basics\|Day 19]]                | Kafka mTLS Basics                    |
| [[Deep Security/Day-20-mTLS-Debugging\|Day 20]]                   | mTLS Debugging                       |
| [[Deep Security/Day-21-Hashing-vs-Encryption-vs-Signing\|Day 21]] | Hashing vs Encryption vs Signing     |
| [[Deep Security/Day-22-Generating-Digital-Signatures\|Day 22]]    | Generating Digital Signatures        |
| [[Deep Security/Day-23-JWT-and-JWS-Basics\|Day 23]]               | JWT / JWS Basics                     |
| [[Deep Security/Day-24-Base64-vs-Encryption\|Day 24]]             | Base64 vs Encryption                 |
| [[Deep Security/Day-25-Security-Architecture-Wrapup\|Day 25]]     | Security Architecture Wrap-up        |

### Bucket 3 — IBM DataPower (Weeks 6–8)

| Day                                                                   | Topic                                   |
| --------------------------------------------------------------------- | --------------------------------------- |
| [[IBM DataPower/Day-26-DataPower-Architecture-Fundamentals\|Day 26]]  | DataPower Architecture Fundamentals     |
| [[IBM DataPower/Day-27-Multi-Protocol-Gateway-Deep-Dive\|Day 27]]     | Multi-Protocol Gateway (MPGW) Deep Dive |
| [[IBM DataPower/Day-28-Web-Service-Proxy-vs-MPGW\|Day 28]]            | Web Service Proxy (WSP) vs MPGW         |
| [[IBM DataPower/Day-29-Front-Side-Handlers\|Day 29]]                  | Front-Side Handlers                     |
| [[IBM DataPower/Day-30-Back-Side-Routing\|Day 30]]                    | Back-Side Routing                       |
| [[IBM DataPower/Day-31-Processing-Rules-and-Match-Actions\|Day 31]]   | Processing Rules and Match Actions      |
| [[IBM DataPower/Day-32-Transform-Actions-GatewayScript\|Day 32]]      | Transform Actions — GatewayScript       |
| [[IBM DataPower/Day-33-Transform-Actions-XSLT\|Day 33]]               | Transform Actions — XSLT                |
| [[IBM DataPower/Day-34-Error-Handling-and-Error-Rules\|Day 34]]       | Error Handling and Error Rules          |
| [[IBM DataPower/Day-35-Filter-Validate-and-Convert-Actions\|Day 35]]  | Filter, Validate, and Convert Actions   |
| [[IBM DataPower/Day-36-AAA-Policy-Authentication\|Day 36]]            | AAA Policy — Authentication Phases      |
| [[IBM DataPower/Day-37-AAA-Policy-Authorization\|Day 37]]             | AAA Policy — Authorization Phases       |
| [[IBM DataPower/Day-38-Crypto-Objects-Keys-and-Certificates\|Day 38]] | Crypto Objects — Keys and Certificates  |
| [[IBM DataPower/Day-39-TLS-Profiles-and-SSL-Proxy\|Day 39]]           | TLS Profiles and SSL Proxy Profiles     |
| [[IBM DataPower/Day-40-DataPower-Wrapup-and-Troubleshooting\|Day 40]] | DataPower Wrap-up and Troubleshooting   |

### Bucket 4 — Integration DevOps (Weeks 9–10)

| Day                                                                               | Topic                                           |
| --------------------------------------------------------------------------------- | ----------------------------------------------- |
| [[Integration DevOps/Day-41-CICD-Concepts-for-Middleware\|Day 41]]                | CI/CD Concepts for Middleware                   |
| [[Integration DevOps/Day-42-Automating-ACE-BAR-Builds-via-CLI\|Day 42]]           | Automating ACE BAR Builds via CLI               |
| [[Integration DevOps/Day-43-ACE-BAR-Overrides-and-Environment-Config\|Day 43]]    | ACE BAR Overrides & Environment-Specific Config |
| [[Integration DevOps/Day-44-MQ-Docker-Containers-Setup\|Day 44]]                  | MQ Docker Containers — Setup & Basics           |
| [[Integration DevOps/Day-45-Automating-MQ-Setup-with-Declarative-Config\|Day 45]] | Automating MQ Setup with Declarative Config     |
| [[Integration DevOps/Day-46-GitOps-Concepts\|Day 46]]                             | GitOps Concepts                                 |
| [[Integration DevOps/Day-47-OpenShift-Kubernetes-ConfigMaps\|Day 47]]             | OpenShift/Kubernetes — ConfigMaps               |
| [[Integration DevOps/Day-48-OpenShift-Kubernetes-Secrets\|Day 48]]                | OpenShift/Kubernetes — Secrets                  |
| [[Integration DevOps/Day-49-Pod-Debugging\|Day 49]]                               | Pod Debugging                                   |
| [[Integration DevOps/Day-50-Final-Architecture-Review\|Day 50]]                   | Final 10-Week Architecture Review               |

---

## 🔗 Cross-Bucket Concept Index

Some topics recur across buckets — this is where the whole vault actually connects into one system rather than four separate courses.

| Concept                                               | Where it lives                                                                                                                                                                                                                                                                                                                                                                                                         |
| ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **TLS / SSL handshake failures**                      | First diagnosed at the transport level in [[Core Networking/Day-09-Diagnosing-Firewall-Drops\|B1 Day 9]], explained in full in [[Deep Security/Day-11-TLS-1.2-vs-1.3-Handshake\|B2 Day 11]], enforced at the gateway in [[IBM DataPower/Day-39-TLS-Profiles-and-SSL-Proxy\|B3 Day 39]]                                                                                                                                 |
| **mTLS / mutual authentication**                      | [[Deep Security/Day-16-One-Way-TLS-vs-mTLS\|B2 Day 16]], applied as gateway policy in [[IBM DataPower/Day-36-AAA-Policy-Authentication\|B3 Day 36]]                                                                                                                                                                                                                                                                    |
| **Certificates & crypto objects**                     | Generated/understood in [[Deep Security/Day-12-Private-Keys-and-CSRs-OpenSSL\|B2 Day 12]]–[[Deep Security/Day-14-CA-Chains-and-Trust-Stores\|14]], consumed as DataPower objects in [[IBM DataPower/Day-38-Crypto-Objects-Keys-and-Certificates\|B3 Day 38]], mounted as Kubernetes Secrets in [[Integration DevOps/Day-48-OpenShift-Kubernetes-Secrets\|B4 Day 48]]                                                   |
| **OpenShift networking**                              | Routes/Ingress/DNS in [[Core Networking/Day-07-OpenShift-Ingress-Routes-and-DNS\|B1 Day 7]], the pods behind those routes deployed/debugged in [[Integration DevOps/Day-47-OpenShift-Kubernetes-ConfigMaps\|B4 Day 47]]–[[Integration DevOps/Day-49-Pod-Debugging\|49]]                                                                                                                                                |
| **Tokens / JWT**                                      | Cryptographic basis in [[Deep Security/Day-23-JWT-and-JWS-Basics\|B2 Day 23]], validated as part of gateway AuthN/AuthZ in [[IBM DataPower/Day-37-AAA-Policy-Authorization\|B3 Day 37]]                                                                                                                                                                                                                                |
| **MQ**                                                | Ports/protocol referenced throughout Bucket 1's [[Core Networking/00 Core Networking Index\|Stack Port Reference]], bridged at the gateway via `MQFrontSideHandler` in [[IBM DataPower/Day-30-Back-Side-Routing\|B3 Day 30]], containerized and automated as code in [[Integration DevOps/Day-44-MQ-Docker-Containers-Setup\|B4 Day 44]]–[[Integration DevOps/Day-45-Automating-MQ-Setup-with-Declarative-Config\|45]] |
| **Gateway service selection (MPGW vs WSP)**           | [[IBM DataPower/Day-28-Web-Service-Proxy-vs-MPGW\|B3 Day 28]], same request having already been load-balanced per [[Core Networking/Day-06-L4-vs-L7-Load-Balancing\|B1 Day 6]]                                                                                                                                                                                                                                         |
| **"Build once, promote" / config-as-code philosophy** | First appears conceptually in [[Deep Security/Day-13-Self-Signed-Certificates\|B2's]] cert lifecycle discipline, becomes the explicit organizing principle of all of Bucket 4, esp. [[Integration DevOps/Day-43-ACE-BAR-Overrides-and-Environment-Config\|B4 Day 43]] and [[Integration DevOps/Day-46-GitOps-Concepts\|Day 46]]                                                                                        |

---

## 🌳 Unified Request-Failure Decision Tree

Start here when something is broken and you don't yet know which bucket owns the problem:

```
Something failed. Where do you look?
│
├── Client can't even reach the service
│   → "Connection refused/timed out/reset" → BUCKET 1 (Day 3, 9)
│
├── Connection reaches the service, but TLS/cert error
│   → "handshake failure / cert invalid / hostname mismatch" → BUCKET 2 (Day 11–20)
│
├── TLS is fine, but request is rejected AT THE GATEWAY
│   → AAA policy rejection, schema/contract validation failure → BUCKET 3 (Day 31–37)
│
├── Gateway accepted it, but the ACE flow / MQ queue behind it misbehaves
│   → Flow exception, message on DLQ, channel not running → BUCKET 3 Day 30 (routing)
│     + your Bucket-3-adjacent middleware knowledge (ACE/MQ mechanics)
│
├── Everything above is fine, but the DEPLOYMENT itself is broken
│   → Pod CrashLoopBackOff, ConfigMap/Secret not mounted, wrong image → BUCKET 4 (Day 47–49)
│
└── "It worked in Dev, broken in Prod"
      → Compare BUCKET 4 Day 43 (BAR overrides) / Day 46 (GitOps drift) —
        this is the #1 real-world failure mode and it is almost never a
        code problem once you've ruled out Buckets 1–3
```

---

## ✅ How to Use This Vault

1. Work top to bottom: Bucket 1 → 2 → 3 → 4. Each bucket assumes the previous one's vocabulary (Bucket 3's AAA policies assume you already know mTLS from Bucket 2; Bucket 4's Secrets assume you know what a cert/key pair actually is from Bucket 2).
2. Every day file ends with a **Validation** section — don't advance until you can tick every box for real, not from memory.
3. When debugging anything for real (lab or production), start at the **Unified Decision Tree** above, not at whichever bucket you're most comfortable in.
4. Day 25, Day 40, and Day 50 are each a synthesis/capstone day for their bucket — Day 50 additionally synthesizes _all four_ buckets together.

---

**Buckets:** [[Core Networking/00 Core Networking Index|Bucket 1]] · [[Deep Security/00 Deep Security Index|Bucket 2]] · [[IBM DataPower/00 IBM DataPower Index|Bucket 3]] · [[Integration DevOps/00 Integration DevOps Index|Bucket 4]]
