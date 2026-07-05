---
tags: [networking, bucket-1, synthesis, debugging, scenarios, day-10]
created: 2025-07-05
bucket: 1
week: 2
day: 10
status: not-started
---

# Day 10 — Networking Wrap-up & Scenario Debugging

> [!info] Why This Day Exists
> Knowledge of individual networking concepts is not the same as being able to debug a live incident. This day is pure synthesis: no new theory. You'll work through realistic scenarios drawn from the kinds of issues that actually appear in banking integration environments, applying every concept from Days 1–9.

**←** [[Day-09-Diagnosing-Firewall-Drops]] | **Index:** [[00 Core Networking Index]]

---

## Concept Map — How Everything Connects

```
                      EXTERNAL CLIENT
                           │
                    [Corporate DNS]
                           │
                    [Ingress VIP / Route] ──── [[Day-07-OpenShift-Ingress-Routes-and-DNS]]
                           │  L7 routing
                    [DataPower Pod]
                           │
                 ┌─────────┴──────────┐
                 │                    │
       [ACE Pod]               [External API]
         │                       via Forward Proxy
         │                    ── [[Day-08-Forward-Proxies-and-CONNECT-Tunnels]]
    ┌────┴─────────────┐
    │         │        │
 [MQ QM]  [Kafka]  [Oracle]
    │         │        │
TCP level: handshakes, timeouts, RSTs, keepalives
[[Day-01]] [[Day-02]] [[Day-03]] [[Day-04]]

All of it debuggable via:
  Wireshark + tcpdump [[Day-05]]
  nc / ncat / ss [[Day-09]]
  Load balanced across multiple backends [[Day-06]]
  Blocked or allowed by firewall/NetworkPolicy [[Day-09]] [[Day-07]]
```

---

## Master Debugging Decision Tree

Save this. Use it in incidents.

```
Something can't connect. Start here:
│
├─ 1. DNS: nslookup TARGET
│    ├── Fails → DNS not configured, wrong hostname, CoreDNS issue (in cluster)
│    └── OK → continue
│
├─ 2. Port test: nc -zv -w 5 HOST PORT
│    ├── Instant "Connection refused" → RST → go to 2a
│    ├── Hangs then timeout → firewall DROP → go to 2b
│    └── "succeeded!" → port open → go to 3
│
│    2a. RST case:
│    ├── ss -tlnp | grep PORT (on target)
│    │   ├── Nothing → service not running / wrong port
│    │   └── Something → binding issue (127.0.0.1 only?) or firewall REJECT
│    └── Check: is target behind OpenShift? → kubectl get endpoints / NetworkPolicy
│
│    2b. Timeout / DROP case:
│    ├── tcpdump on source: SYNs being sent?
│    │   └── No → routing issue / iptables on local machine blocking egress
│    ├── tcpdump on target: SYNs arriving?
│    │   ├── Yes → target iptables/NetworkPolicy blocking (not an intermediate firewall)
│    │   └── No → intermediate firewall dropping
│    └── traceroute -T -p PORT HOST → where do hops stop?
│
├─ 3. TLS: openssl s_client -connect HOST:PORT
│    ├── Fails → TLS config issue (cert expired, wrong CA, cipher mismatch)
│    └── OK → continue
│
├─ 4. Application: curl http(s)://HOST:PORT/health
│    ├── Fails → application layer issue (check app logs)
│    └── OK → network is fine; problem is elsewhere
│
└─ 5. Intermittent / after-idle failures:
     ├── "Connection reset" after idle → firewall idle timeout > pool idle timeout
     │   → [[Day-02-Connection-Timeouts-vs-Read-Timeouts]] + [[Day-03-RST-Packets-and-Connection-Drops]]
     ├── Works, then hangs for exactly N seconds, then fails → read timeout too short
     └── Kafka consumer rebalancing → session.timeout.ms tuning
```

---

## Scenario Debugging Exercises

Work through each scenario. For each: identify the root cause, identify the tool/command that would confirm it, and write the fix.

---

### Scenario 1 — The First-Request-After-Idle Failure

**Situation:** ACE flow calls an external REST API. Works fine when traffic is steady. Every Monday morning (after weekend quiet period) the first call fails with `Connection reset by peer`. Subsequent calls succeed immediately.

**Questions:**

1. What network concept explains this?
2. Which day's content covers the root cause?
3. What's the fix, specifically?

> [!example]- Answer
> **Root cause:** Firewall idle timeout. The corporate firewall removes connection tracking entries after N minutes of inactivity (typically 5–30 min). ACE's HTTP connection pool keeps sockets open thinking they're still valid. Monday morning, the pool tries to reuse a connection that the firewall killed over the weekend.
>
> **Confirming tool:** `tcpdump` on the ACE machine — you'll see ACE sends a request (PSH packet) on an existing socket, and receives a RST in response (from the firewall or from the remote end after the firewall confused the packet).
>
> **Fix:** Set ACE HTTP connection pool `idleTimeout` to less than the firewall's idle timeout. If firewall kills at 5 minutes, set pool idle to 3 minutes. See [[Day-02-Connection-Timeouts-vs-Read-Timeouts]] and [[Day-04-TCP-Keepalives-vs-HTTP-Keep-Alive]].

---

### Scenario 2 — DataPower Can't Reach New Backend

**Situation:** New ACE integration server deployed in `integration-v2` namespace in OpenShift. DataPower MPG configured to call it at `ace-server.integration-v2:7080`. DataPower returns `backend connection failed` immediately (not a timeout — it's fast).

**Questions:**

1. Classify the failure: RST or timeout?
2. What's the most likely cause given the speed of failure?
3. What do you check first?

> [!example]- Answer
> **Classification:** Fast failure = RST = connection refused.
>
> **Likely cause:** The `ace-server` Service doesn't exist in `integration-v2` namespace yet, OR the Service exists but has no Endpoints (pods not ready), OR a NetworkPolicy in `integration-v2` is blocking inbound from DataPower's namespace.
>
> **Check sequence:**
>
> 1. `kubectl get svc ace-server -n integration-v2` → exists?
> 2. `kubectl get endpoints ace-server -n integration-v2` → any pod IPs listed?
> 3. `kubectl get pods -n integration-v2 -l app=ace-server` → pods Running and Ready?
> 4. `kubectl get networkpolicy -n integration-v2` → any policy blocking DataPower pods?
> 5. From a DataPower pod: `nc -zv ace-server.integration-v2 7080`

---

### Scenario 3 — Kafka Consumer Rebalancing Every Few Minutes

**Situation:** Flink job consuming from Kafka. Running fine in dev, but in production the consumer group is rebalancing every 2–3 minutes. Messages are being reprocessed. No code change between environments.

**Questions:**

1. Which timeout setting is the direct cause?
2. What's different about production that triggers it?
3. How do you confirm and fix?

> [!example]- Answer
> **Direct cause:** `session.timeout.ms` is too short relative to the consumer's processing time. The broker is declaring the consumer dead (not receiving heartbeats within the session timeout window) and triggering a rebalance.
>
> **Production difference:** Production messages are larger / more complex / hitting a slower DB → processing takes longer → heartbeat thread is delayed → broker times out the consumer.
>
> **Confirm:** Kafka broker logs will show `Consumer group... consumer... session timed out`. Consumer logs will show `Rebalancing due to group membership change`.
>
> **Fix:**
>
> ```properties
> session.timeout.ms=120000      # Increase: how long broker waits for heartbeat
> heartbeat.interval.ms=10000   # Keep at ~1/3 of session timeout
> max.poll.interval.ms=300000   # Max time between poll() calls — increase if processing is slow
> ```
>
> Also consider: process records faster, or reduce `max.poll.records` so each batch is smaller.
> See [[Day-02-Connection-Timeouts-vs-Read-Timeouts]].

---

### Scenario 4 — MQ Channel Drops After 30 Minutes Idle

**Situation:** MQ sender channel between two queue managers. Transfers messages fine. If there are no messages for 30+ minutes, the channel stops (status: STOPPED). Manual restart brings it back. No error in MQ logs except `MQRC 2009 (connection broken)`.

**Questions:**

1. What's the root cause?
2. Which MQ configuration parameter fixes it?
3. What value should you set it to?

> [!example]- Answer
> **Root cause:** Firewall idle timeout (almost certainly 30 minutes based on the symptom pattern). The firewall removes the connection tracking entry after 30 minutes of no traffic. The next MQ heartbeat or message attempt hits a stale TCP connection → RST or silent drop → MQ channel status STOPPED.
>
> **Fix parameter:** `HBINT` (HeartBeat INTerval) on the MQ channel.
>
> **Value:** Set to less than the firewall's idle timeout. If firewall kills at 30 min (1800s), set HBINT to 900s (15 min) to be safe.
>
> ```
> ALTER CHANNEL(MY.SENDER.CHANNEL) CHLTYPE(SDR) HBINT(900)
> ```
>
> The MQ heartbeat now keeps the firewall connection tracking entry alive.
> See [[Day-04-TCP-Keepalives-vs-HTTP-Keep-Alive]].

---

### Scenario 5 — New Firewall Rule Added, Still Can't Connect

**Situation:** Network team confirms they added a firewall rule allowing `ACE_Pod_CIDR → Oracle_DB:1521`. But JDBC connections from ACE still time out. The network team insists the rule is correct.

**Questions:**

1. How do you definitively prove whether the firewall is still blocking or not?
2. What else could cause the timeout even with a correct firewall rule?
3. What commands do you run, on which machines?

> [!example]- Answer
> **Definitive test:** Two-sided `tcpdump`.
>
> On ACE machine:
>
> ```bash
> sudo tcpdump -i any -n 'host ORACLE_IP and tcp port 1521 and tcp[tcpflags] & tcp-syn != 0'
> ```
>
> Attempt a connection from ACE to Oracle.
>
> On Oracle machine (if accessible):
>
> ```bash
> sudo tcpdump -i any -n 'host ACE_IP and tcp port 1521'
> ```
>
> **Interpret:**
>
> - SYN on ACE machine, NOT on Oracle → firewall still blocking (rule not applied correctly, or wrong CIDR)
> - SYN on BOTH machines → firewall is open; problem is at Oracle
>   - Is Oracle listener running? `ss -tlnp | grep 1521`
>   - Is Oracle binding to 0.0.0.0 or only 127.0.0.1? `ss -tlnp | grep 1521` shows the bind address
>   - Is Oracle's local iptables blocking? `sudo iptables -L -n | grep 1521`
>   - Are ACE's Oracle connection details correct (hostname/SID/service name)?
>
> Also check: the ACE pod's source IP may be the OpenShift node IP (after SNAT), not the pod CIDR. The firewall rule may need to allow node IPs, not pod CIDRs.

---

### Scenario 6 — Intermittent 503 from DataPower to ACE (Load Balanced)

**Situation:** DataPower calls ACE, which has 3 replicas behind a Kubernetes Service. Intermittently (roughly 1 in 20 requests), DataPower gets a 503. ACE logs show no error for those requests. DataPower error log says `backend returned 503` or `connection refused`.

**Questions:**

1. Which layer is returning the 503?
2. What's the likely root cause given the "no error in ACE logs" observation?
3. How do you investigate?

> [!example]- Answer
> **Layer:** The Kubernetes Service / kube-proxy layer, not ACE itself. The 503 is being generated before the request reaches any ACE pod — that's why ACE logs are clean.
>
> **Likely root cause:** One of the 3 ACE pod replicas is in a bad state (unready, restarting, crashlooping) and is still in the Service Endpoints list. kube-proxy is occasionally routing requests to that unhealthy pod.
>
> **Investigation:**
>
> ```bash
> # Check pod status
> kubectl get pods -n integration -l app=ace-server
> # Look for pods with status != Running or restarts > 0
>
> # Check endpoints — any pods with no ready status?
> kubectl get endpoints ace-service -n integration
>
> # Describe the service
> kubectl describe service ace-service -n integration
>
> # Check pod readiness probe
> kubectl describe pod ACE_POD_NAME -n integration | grep -A 10 "Readiness"
>
> # Watch events
> kubectl get events -n integration --sort-by='.lastTimestamp'
> ```
>
> **Likely fix:** The ACE readiness probe is either misconfigured (not probing the right path/port) or too lenient (allows an unhealthy pod to stay in the endpoint set). A pod that's OOMKilling or restarting should fail its readiness probe and be removed from Endpoints automatically.

---

## Week 1–2 Synthesis: What You Can Now Do

After 10 days, you should be able to:

| Scenario                               | Tools you'd use                         | Days it draws from                                                                                                                                  |
| -------------------------------------- | --------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| "ACE can't connect to backend"         | nc, tcpdump, ss, curl                   | [[Day-01-TCP-Handshake-and-Sockets\|1]], [[Day-09-Diagnosing-Firewall-Drops\|9]]                                                                    |
| "Connection drops after idle"          | tcpdump, check pool config, check HBINT | [[Day-02-Connection-Timeouts-vs-Read-Timeouts\|2]], [[Day-03-RST-Packets-and-Connection-Drops\|3]], [[Day-04-TCP-Keepalives-vs-HTTP-Keep-Alive\|4]] |
| "RST in logs every morning"            | tcpdump at exact failure time           | [[Day-03-RST-Packets-and-Connection-Drops\|3]]                                                                                                      |
| "DataPower can't call external API"    | Check proxy config, openssl via proxy   | [[Day-08-Forward-Proxies-and-CONNECT-Tunnels\|8]]                                                                                                   |
| "Pod A can't reach Pod B in OpenShift" | kubectl, NetworkPolicy, endpoints       | [[Day-07-OpenShift-Ingress-Routes-and-DNS\|7]], [[Day-09-Diagnosing-Firewall-Drops\|9]]                                                             |
| "Is this a firewall issue?"            | Two-sided tcpdump                       | [[Day-05-Packet-Captures-for-Middleware\|5]], [[Day-09-Diagnosing-Firewall-Drops\|9]]                                                               |
| "Load balancer not distributing"       | nginx logs, curl with header            | [[Day-06-L4-vs-L7-Load-Balancing\|6]]                                                                                                               |
| "Kafka consumer keeps rebalancing"     | broker logs, consumer config            | [[Day-02-Connection-Timeouts-vs-Read-Timeouts\|2]]                                                                                                  |

---

## Retro: What to Review Before Moving to the Next Bucket

Rate yourself 1–5 on each:

- [ ] I can explain what a TCP 3-way handshake does and why TIME_WAIT exists — [[Day-01-TCP-Handshake-and-Sockets|Day 1]]
- [ ] I can distinguish a connect timeout from a read timeout from an idle timeout — [[Day-02-Connection-Timeouts-vs-Read-Timeouts|Day 2]]
- [ ] I can explain what causes "connection reset by peer" and trace it to a specific cause — [[Day-03-RST-Packets-and-Connection-Drops|Day 3]]
- [ ] I can explain the difference between TCP keepalive and HTTP Keep-Alive without confusing them — [[Day-04-TCP-Keepalives-vs-HTTP-Keep-Alive|Day 4]]
- [ ] I can write a tcpdump command to capture MQ, Kafka, or HTTP traffic and read the result in Wireshark — [[Day-05-Packet-Captures-for-Middleware|Day 5]]
- [ ] I can explain L4 vs L7 and tell which one OpenShift Routes use — [[Day-06-L4-vs-L7-Load-Balancing|Day 6]]
- [ ] I can trace the full path from an external client to a pod in OpenShift including DNS — [[Day-07-OpenShift-Ingress-Routes-and-DNS|Day 7]]
- [ ] I can explain HTTP CONNECT tunneling and configure a proxy in ACE or DataPower — [[Day-08-Forward-Proxies-and-CONNECT-Tunnels|Day 8]]
- [ ] I can distinguish a firewall DROP from a service RST and explain which tool proves it — [[Day-09-Diagnosing-Firewall-Drops|Day 9]]

Any score below 3 → revisit that day's hands-on before starting Bucket 2.

---

**← Index:** [[00 Core Networking Index]]
