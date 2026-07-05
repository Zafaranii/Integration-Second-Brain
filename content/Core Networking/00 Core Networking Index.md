---
tags:
  - networking
  - bucket-1
  - index
  - moc
created: 2025-07-05
bucket: 1
status: active
---

# Bucket 1 — Core Networking & Routing

> As an integration engineer, the network is your actual runtime environment. This module covers how TCP works under the hood, how traffic is routed and balanced (especially in OpenShift), and how to punch securely through enterprise firewalls using proxies.

**Tags:** #networking #routing #index

---

## Map of Content

### Week 1 — The Anatomy of a Connection

| Day                                                    | Topic                                |
| ------------------------------------------------------ | ------------------------------------ |
| [[Day-01-TCP-Handshake-and-Sockets\|Day 1]]            | TCP Handshake and Sockets            |
| [[Day-02-Connection-Timeouts-vs-Read-Timeouts\|Day 2]] | Connection Timeouts vs Read Timeouts |
| [[Day-03-RST-Packets-and-Connection-Drops\|Day 3]]     | RST Packets and Connection Drops     |
| [[Day-04-TCP-Keepalives-vs-HTTP-Keep-Alive\|Day 4]]    | TCP Keepalives vs HTTP Keep-Alive    |
| [[Day-05-Packet-Captures-for-Middleware\|Day 5]]       | Packet Captures for Middleware       |

### Week 2 — Load Balancing, Routing & Proxies

| Day                                                          | Topic                                   |
| ------------------------------------------------------------ | --------------------------------------- |
| [[Day-06-L4-vs-L7-Load-Balancing\|Day 6]]                    | L4 vs L7 Load Balancing                 |
| [[Day-07-OpenShift-Ingress-Routes-and-DNS\|Day 7]]           | OpenShift Ingress, Routes & DNS         |
| [[Day-08-Forward-Proxies-and-CONNECT-Tunnels\|Day 8]]        | Forward Proxies and CONNECT Tunnels     |
| [[Day-09-Diagnosing-Firewall-Drops\|Day 9]]                  | Diagnosing Firewall Drops               |
| [[Day-10-Networking-Wrap-up-and-Scenario-Debugging\|Day 10]] | Networking Wrap-up & Scenario Debugging |

---

## Concept Index

- **TCP internals** → [[Day-01-TCP-Handshake-and-Sockets]], [[Day-03-RST-Packets-and-Connection-Drops]], [[Day-04-TCP-Keepalives-vs-HTTP-Keep-Alive]]
- **Timeouts** → [[Day-02-Connection-Timeouts-vs-Read-Timeouts]]
- **Debugging tools** → [[Day-05-Packet-Captures-for-Middleware]], [[Day-09-Diagnosing-Firewall-Drops]]
- **Load balancing** → [[Day-06-L4-vs-L7-Load-Balancing]]
- **OpenShift networking** → [[Day-07-OpenShift-Ingress-Routes-and-DNS]]
- **Proxies & firewalls** → [[Day-08-Forward-Proxies-and-CONNECT-Tunnels]], [[Day-09-Diagnosing-Firewall-Drops]]
- **Synthesis** → [[Day-10-Networking-Wrap-up-and-Scenario-Debugging]]

---

## Stack Port Reference

| Component     | Default Port       | TLS Port    | Notes                  |
| ------------- | ------------------ | ----------- | ---------------------- |
| IBM MQ        | 1414               | 1415        | Per listener config    |
| IBM ACE HTTP  | 7080               | 7083        | Per integration server |
| IBM DataPower | 8080 / 9090 (mgmt) | 8443        | Per MPG/service config |
| Kafka         | 9092               | 9093        | Per broker             |
| MongoDB       | 27017              | —           |                        |
| Oracle JDBC   | 1521               | —           |                        |
| OpenShift API | 6443               | —           | kubectl target         |
| LDAP          | 389                | 636 (LDAPS) |                        |
| SFTP          | 22                 | —           |                        |

---

## Debugging Decision Tree

```
Connection failure?
│
├── "Connection refused" → Port not open or service not listening → check ss/netstat on target
├── "Connection timed out" → Firewall silently dropping → Day 9 tools
├── "Connection reset by peer" → RST packet → Day 3
├── "Read timed out" → Connected but no data → Day 2
├── "No route to host" → Routing issue / host unreachable → traceroute
└── "SSL handshake failed" → Bucket 2 (TLS)
```
