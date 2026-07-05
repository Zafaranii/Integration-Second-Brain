---
tags: [networking, bucket-1, tcp, timeouts, day-2]
created: 2025-07-05
bucket: 1
week: 1
day: 2
status: not-started
---

# Day 2 — Connection Timeouts vs Read Timeouts

> [!info] Why This Day Exists
> Timeout misconfiguration is one of the most common sources of production incidents in integration middleware. ACE, DataPower, and Kafka clients all have multiple independent timeout settings — and confusing them leads to either cascading failures (timeout too short) or hung threads that never recover (timeout too long or missing). This day gives you a precise mental model for each type.

**←** [[Day-01-TCP-Handshake-and-Sockets]] | **Index:** [[00 Core Networking Index]] | **Next:** [[Day-03-RST-Packets-and-Connection-Drops]] →

---

## Theory

### The Three Distinct Timeout Types

These are conceptually separate — they fire at different stages of the connection lifecycle and produce different error messages and symptoms.

---

#### 1. Connect Timeout

**What it measures:** Time allowed for the TCP 3-way handshake to complete — from the moment the SYN is sent to the moment the SYN-ACK is received.

**What happens at the TCP level:** The OS sent a SYN. No SYN-ACK came back within the window. The OS retransmits the SYN (with exponential backoff by default — 1s, 2s, 4s...). If your application-level connect timeout fires before the OS gives up, your application receives the error.

**Typical error messages:**

- ACE: `Connection timed out` / `CWSCA0027E`
- Java/HTTP client: `java.net.ConnectException: Connection timed out`
- curl: `curl: (28) Failed to connect ... Operation timed out`

**What it usually means:**

- Firewall is **silently dropping** SYN packets (the most common cause in a bank)
- Target host is unreachable (routing issue)
- Target service is not listening on that port (but in this case you'd get RST, not timeout — unless a firewall is in between)
- Target host is overloaded and not processing the SYN queue fast enough

**Typical values:** 5–30 seconds for internal backends. Too short = false failures during transient network blips. Too long = your thread hangs for 30s on every firewall drop.

---

#### 2. Read Timeout (Socket Timeout)

**What it measures:** Time allowed for data to arrive on an **already-established** connection. Specifically: after the TCP connection is up and a request has been sent, how long to wait for the first byte of the response.

**What happens at the TCP level:** The connection is ESTABLISHED. The request was sent. The application is blocked on `read()` waiting for bytes. No bytes arrive within the timeout window. The application closes the socket and raises a timeout error.

**Typical error messages:**

- ACE: `Read timed out` / `SocketTimeoutException`
- DataPower: `backend response timeout`
- Java: `java.net.SocketTimeoutException: Read timed out`
- curl: `curl: (28) Operation timed out after N milliseconds`

**What it usually means:**

- Backend received the request but is taking too long to process it (slow DB query, upstream dependency chain)
- Backend is partially up but stuck (e.g. thread pool exhausted, GC pause)
- Network packet loss on an established connection (rare on internal networks)
- Backend crashed mid-processing (no response ever comes)

**Typical values:** Tuned per integration. A simple lookup API: 3–5s. A report-generation API: 30–120s. Setting this too short causes spurious failures on legitimately slow operations; too long means threads pile up waiting on a degraded backend.

---

#### 3. Idle Timeout (Connection Pool Keep-Alive Timeout)

**What it measures:** How long a **pooled, idle** connection is kept open before being closed. Applies to connection pools in ACE HTTP nodes and DataPower backend connection pools.

**The problem it solves:** Firewalls and NAT devices often silently close idle TCP connections (typically after 5–30 minutes of inactivity). When ACE tries to reuse a pooled connection that the firewall has silently killed, the first write fails with a RST or broken pipe — the connection looks alive from the application side but is dead from the network side.

**Typical error messages:**

- `Connection reset by peer` on the first request after an idle period
- `Broken pipe` on write
- ACE: `CWSCA0025E`

**The fix:** Set idle timeout **shorter** than the firewall's idle timeout so your pool proactively closes connections before the firewall kills them. If firewall kills at 5 minutes, set idle timeout to 3–4 minutes.

> [!tip] How to Find the Firewall's Idle Timeout
> Ask your network team. In a bank, this is typically documented in the firewall ruleset. Common values: 300s (5 min) for internal zones, 60s for DMZ rules. If you can't get it, set idle timeout to 60s and watch if the problem disappears.

---

#### 4. Response Timeout (DataPower-specific)

DataPower has an additional concept: **backend response timeout** on the MPG service. This is similar to a read timeout but is measured from when DataPower forwarded the request to the backend — it fires if the entire backend response (not just the first byte) doesn't arrive within the window.

Configured per service in the Multi-Protocol Gateway → Backend settings. Default is often 60 seconds — too long for most banking APIs.

---

### Timeout Interaction in ACE + DataPower

```
Client ──── DataPower ──────────────── ACE ──────── Backend
                │                        │
         [DP read timeout]        [ACE read timeout]
         (client→DP)              (ACE→backend)
                │                        │
         [DP backend timeout]     [ACE connect timeout]
         (DP→ACE)                 (ACE→backend)
```

**The key insight:** DataPower and ACE each have their own independent timeout settings. The DataPower→ACE backend timeout must be **longer** than the ACE→backend read timeout, or DataPower will cut the connection before ACE has a chance to respond.

A common misconfiguration: DataPower backend timeout = 30s, ACE calls a slow backend with read timeout = 60s → DataPower gives up and returns an error to the client while ACE is still waiting for the backend.

---

### Timeout Settings by Component

#### IBM ACE — HTTP Request Node

```
connectTimeout     → Connect timeout (ms) — default: 60000
readTimeout        → Read/socket timeout (ms) — default: 60000
```

Set via node properties in the message flow, or via policy files.

#### IBM DataPower — Multi-Protocol Gateway

```
Backend → Timeout → Response timeout (seconds)
```

Also configurable per SSL Client Profile for TLS handshake timeouts.

#### Kafka Clients

```
# Producer
request.timeout.ms          → Max time to wait for broker ack (default: 30000)
delivery.timeout.ms         → Total time including retries (default: 120000)

# Consumer
session.timeout.ms          → Broker considers consumer dead if no heartbeat (default: 45000)
request.timeout.ms          → Per-request timeout (default: 30000)
```

#### Java HTTP Client (used by ACE internals)

```java
HttpClient.newBuilder()
    .connectTimeout(Duration.ofSeconds(5))    // Connect timeout
    .build();

HttpRequest.newBuilder()
    .timeout(Duration.ofSeconds(30))          // Read timeout
    .build();
```

---

## Your Stack, Concretely

| Error Pattern                                            | Likely Timeout Type                              | First Action                                              |
| -------------------------------------------------------- | ------------------------------------------------ | --------------------------------------------------------- |
| Fails immediately after idle period, then works on retry | Idle timeout / stale pool connection             | Check firewall idle timeout vs pool idle timeout          |
| Hangs for exactly N seconds then fails                   | Read timeout firing                              | Backend too slow — check backend logs for slow processing |
| Fails immediately on fresh deploy, consistently          | Connect timeout or connection refused            | Check firewall rules, check backend is actually listening |
| DataPower errors before ACE even tried the backend       | DataPower backend timeout too short              | Align DP timeout > ACE timeout + backend processing time  |
| Kafka consumer group rebalancing frequently              | session.timeout.ms too short for processing time | Increase consumer session timeout                         |

---

## Hands-on

### Exercise 1 — Observe Connect Timeout vs Read Timeout

```bash
# Connect timeout — connect to a non-routable IP (will hang until timeout)
# 203.0.113.x is documentation range, nothing routes there
curl --connect-timeout 5 http://203.0.113.1/test
# → "Connection timed out" after ~5 seconds

# Read timeout — connect succeeds but server never responds
# netcat listens and accepts the connection but sends nothing back
nc -l 8888 &
curl --max-time 5 http://localhost:8888/test
# → "Operation timed out" after 5 seconds
# The difference: connect succeeded (nc accepted), but no data came back
kill %1
```

### Exercise 2 — Simulate a Stale Pooled Connection

```bash
# Start a server
python3 -c "
import socket, time
s = socket.socket()
s.bind(('localhost', 9999))
s.listen(1)
conn, _ = s.accept()
print('Connected. Sleeping 10s then closing...')
time.sleep(10)
conn.close()
s.close()
print('Server closed connection')
" &

# Connect a client and hold the connection
nc -v localhost 9999 &
sleep 12   # Wait for server to close the connection
# Now try to write to the dead connection
echo "hello" | nc -v localhost 9999
# → Connection refused (or RST) — the connection is dead but client didn't know
```

### Exercise 3 — Map Your ACE Timeouts

Open one of your ACE message flows. Find an HTTP Request node. Check:

1. What is the `connectTimeout` set to?
2. What is the `readTimeout` set to?
3. Is there a policy overriding these?

Then find the DataPower MPG that fronts this ACE service. What is the backend response timeout?

Draw the timeout chain on paper:

```
Client → [DataPower backend timeout: ?s] → [ACE connect: ?s] → [ACE read: ?s] → Backend
```

Verify: DataPower timeout > ACE read timeout? If not, you have a misconfiguration.

---

## Key Takeaways

- **Connect timeout** fires during the TCP handshake — usually a firewall or routing problem.
- **Read timeout** fires on an established connection — usually a slow or stuck backend.
- **Idle timeout** fires on a pooled connection — set shorter than the firewall's idle kill time.
- In ACE + DataPower chains, timeout values must be coordinated — outer timeouts must exceed inner timeouts or you'll get false upstream failures.
- Kafka has its own separate timeout hierarchy (session, request, delivery) — treat it as a separate tuning problem.

---

**←** [[Day-01-TCP-Handshake-and-Sockets]] | **Index:** [[00 Core Networking Index]] | **Next:** [[Day-03-RST-Packets-and-Connection-Drops]] →
