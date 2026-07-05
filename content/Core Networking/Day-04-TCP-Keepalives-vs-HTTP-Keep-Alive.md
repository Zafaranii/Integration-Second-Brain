---
tags: [networking, bucket-1, tcp, keepalive, http, day-4]
created: 2025-07-05
bucket: 1
week: 1
day: 4
status: not-started
---

# Day 4 — TCP Keepalives vs HTTP Keep-Alive

> [!info] Why This Day Exists
> These two concepts share a name but operate at completely different layers and solve different problems. Confusing them leads to misconfigured middleware and persistent connection issues. By the end of this day you should be able to explain both, configure both, and know which one to reach for when debugging a connection problem.

**←** [[Day-03-RST-Packets-and-Connection-Drops]] | **Index:** [[00 Core Networking Index]] | **Next:** [[Day-05-Packet-Captures-for-Middleware]] →

---

## Theory

### TCP Keepalive — OS Level

TCP keepalive is an **OS-level mechanism** that sends small probe packets on an idle connection to verify the remote end is still alive.

**How it works:**

```
After [tcp_keepalive_time] seconds of inactivity:

   Local OS                          Remote OS
      |--- TCP Probe (empty ACK) ---> |
      |<-- ACK -----------------------|   → Remote alive, reset timer

If no response after [tcp_keepalive_intvl] seconds, retry.
After [tcp_keepalive_probes] failed retries → close connection, notify application.
```

**Linux default values:**

```bash
sysctl net.ipv4.tcp_keepalive_time    # default: 7200 (2 hours)
sysctl net.ipv4.tcp_keepalive_intvl   # default: 75 seconds
sysctl net.ipv4.tcp_keepalive_probes  # default: 9
```

With defaults: TCP keepalive starts probing after **2 hours** of idle, then retries 9 times at 75s intervals. Total detection time for a dead connection: 2 hours + (9 × 75s) ≈ **2 hours 11 minutes**. This is almost certainly longer than any firewall's idle timeout.

> [!warning] The Default TCP Keepalive Is Useless for Middleware
> 2 hours is far longer than typical banking firewall idle timeouts (5–30 minutes). TCP keepalive with default values will not prevent your pooled connections from being killed by the firewall. You must either **tune the OS values** or **set the application-level idle timeout shorter than the firewall's** (see [[Day-02-Connection-Timeouts-vs-Read-Timeouts]]).

**Enabling TCP keepalive per socket (Java):**

```java
// Java doesn't easily expose the per-socket keepalive timing.
// You can enable it, but the timing is controlled by the OS:
socket.setKeepAlive(true);
```

**Tuning at the OS level (affects all sockets with keepalive enabled):**

```bash
# More aggressive values suitable for middleware
sudo sysctl -w net.ipv4.tcp_keepalive_time=60     # start probing after 60s idle
sudo sysctl -w net.ipv4.tcp_keepalive_intvl=10    # probe every 10s
sudo sysctl -w net.ipv4.tcp_keepalive_probes=3    # 3 failed probes = dead
# Make persistent:
echo "net.ipv4.tcp_keepalive_time=60" >> /etc/sysctl.conf
```

---

### HTTP Keep-Alive — Application Level

HTTP Keep-Alive (also called HTTP persistent connections or connection reuse) is a completely different concept. It operates at the **HTTP application layer**, not the TCP layer.

**The problem it solves:**

Without Keep-Alive (HTTP/1.0 default behaviour):

```
For each HTTP request:
  1. TCP 3-way handshake        ← overhead
  2. [optional: TLS handshake]  ← more overhead
  3. HTTP request sent
  4. HTTP response received
  5. TCP FIN-ACK close          ← overhead
```

With Keep-Alive (HTTP/1.1 default):

```
First request:
  1. TCP handshake
  2. [optional: TLS handshake]
  3. HTTP request + response

Subsequent requests on the SAME TCP connection:
  3. HTTP request + response    ← no new handshake
  3. HTTP request + response
  3. HTTP request + response
  ...
  N. TCP close (eventually)
```

**HTTP headers involved:**

```
# Client requests keep-alive (implicit in HTTP/1.1, explicit in HTTP/1.0):
Connection: keep-alive

# Server confirms and sets the timeout:
Connection: keep-alive
Keep-Alive: timeout=30, max=100
# → Keep this connection alive for up to 30 seconds of idle, up to 100 requests

# Either side can close:
Connection: close
```

**HTTP/2 and HTTP/3:** Keep-alive as a concept is absorbed into the protocol. HTTP/2 multiplexes many requests over one TCP connection natively — there's no "Connection: keep-alive" header because reuse is always on. DataPower supports HTTP/2 on both front and back side.

---

### How They Interact

Both can be active simultaneously, and they're not redundant:

|                                | TCP Keepalive                      | HTTP Keep-Alive                                              |
| ------------------------------ | ---------------------------------- | ------------------------------------------------------------ |
| Layer                          | TCP (OS)                           | HTTP (Application)                                           |
| Purpose                        | Detect dead connections            | Reuse connections for multiple requests                      |
| Probe frequency                | Every N seconds of idle            | N/A — not probe-based                                        |
| Visible to application         | Only when connection declared dead | Yes — connection pool manages reuse                          |
| Helps with firewall idle drops | Only if tuned aggressively         | No — HTTP Keep-Alive timeout must be < firewall idle timeout |

A typical production setup:

- HTTP Keep-Alive timeout set to 50s (firewall kills at 60s → safe margin)
- TCP keepalive enabled with 30s start time as a secondary safety net
- Application connection pool idle timeout set to 45s (third layer)

---

### DataPower: Keep-Alive Configuration

In DataPower's Multi-Protocol Gateway:

**Front side (client→DataPower):**

- HTTP Front Side Handler → Connection settings → Persistent connections: on/off
- Max persistent connections, timeout

**Back side (DataPower→backend):**

- HTTP Back Side Handler settings on the backend URL
- `Allow HTTP keepalive connections to back-end servers`: yes/no
- Connection timeout for backend pool

DataPower defaults tend to be conservative — check these when you see DataPower opening a new TCP connection for every request to a backend (visible as high connection rate in backend logs).

---

### ACE: HTTP Connection Pooling

ACE's HTTP Request node uses a connection pool per backend URL. Key properties:

```
maxConnections          → Pool size
connectionIdleTimeout   → How long to keep idle connections (set < firewall idle timeout)
persistentConnections   → Enable HTTP Keep-Alive reuse
```

Without `persistentConnections`, ACE opens a new TCP connection for every HTTP call. For high-throughput flows, this is a significant performance overhead.

---

### MQ Channels: Application-Level Heartbeat

IBM MQ has its own heartbeat mechanism that is conceptually similar to TCP keepalive but at the application layer:

```
HBINT (HeartBeat INTerval): how often MQ sends heartbeat messages on an idle channel
Default: 300 seconds (5 minutes)
```

If HBINT is larger than the firewall's idle timeout, the channel drops silently. Solution: set HBINT to less than the firewall idle timeout.

```
# MQ channel definition
ALTER CHANNEL(MY.CHANNEL) CHLTYPE(SVRCONN) HBINT(60)
```

This is exactly the same problem as the HTTP idle pool issue, just in the MQ protocol.

---

## Hands-on

### Exercise 1 — Observe HTTP Keep-Alive Reuse

```bash
# WITHOUT keep-alive: separate connection per request
for i in {1..3}; do
  curl -v --no-keepalive http://httpbin.org/get 2>&1 | grep -E "Connected|Connection"
done
# You'll see "Connected to httpbin.org" for each request — new TCP connection every time

# WITH keep-alive (default in curl)
curl -v http://httpbin.org/get http://httpbin.org/ip 2>&1 | grep -E "Connected|Re-using"
# You'll see "Re-using existing connection" for the second request
```

### Exercise 2 — Observe TCP Keepalive Probes in Wireshark

```bash
# Temporarily set very aggressive keepalive for testing
sudo sysctl -w net.ipv4.tcp_keepalive_time=5
sudo sysctl -w net.ipv4.tcp_keepalive_intvl=2
sudo sysctl -w net.ipv4.tcp_keepalive_probes=3

# Start capture
sudo tcpdump -i lo -n 'tcp port 9999' -w /tmp/keepalive.pcap &

# Create an idle TCP connection
nc -l 9999 &
nc localhost 9999 &

# Wait 10 seconds without sending any data
sleep 10

# Stop capture
kill $(jobs -p)

wireshark /tmp/keepalive.pcap
```

**In Wireshark:** Filter `tcp`. Look for empty ACK packets with no data payload — these are the keepalive probes. Every 2 seconds after 5s of idle.

**Restore sysctl values after:**

```bash
sudo sysctl -w net.ipv4.tcp_keepalive_time=7200
sudo sysctl -w net.ipv4.tcp_keepalive_intvl=75
sudo sysctl -w net.ipv4.tcp_keepalive_probes=9
```

### Exercise 3 — Find MQ HBINT Settings

```bash
# On your MQ installation (or a local Docker MQ):
# List heartbeat intervals on all server-connection channels
echo "DIS CHANNEL(*) CHLTYPE(SVRCONN) HBINT" | runmqsc YOUR_QMGR

# Compare each HBINT value to your known firewall idle timeouts
# Any channel with HBINT > firewall_idle_timeout is at risk of silent drops
```

---

## Key Takeaways

- **TCP keepalive** = OS probe on idle connections. Default 2-hour interval is useless for middleware — tune it or rely on application-layer idle timeouts instead.
- **HTTP Keep-Alive** = reuse one TCP connection for multiple HTTP requests. Reduces handshake overhead significantly. Idle timeout must be tuned shorter than the firewall's idle timeout.
- They are **not alternatives** — they solve different problems and can coexist.
- MQ HBINT is the MQ equivalent of HTTP Keep-Alive idle timeout — set it shorter than the firewall idle timeout or channels drop silently.
- In DataPower and ACE, always verify persistent connections are enabled and idle timeouts are coordinated with network team's firewall rules.

---

**←** [[Day-03-RST-Packets-and-Connection-Drops]] | **Index:** [[00 Core Networking Index]] | **Next:** [[Day-05-Packet-Captures-for-Middleware]] →
