---
tags: [networking, bucket-1, tcp, handshake, sockets, day-1]
created: 2025-07-05
bucket: 1
week: 1
day: 1
status: not-started
---

# Day 1 — TCP Handshake and Sockets

> [!info] Why This Day Exists
> Every connection your ACE flow makes to a backend — HTTP, MQ, Kafka, Oracle — starts with a TCP handshake. Understanding it at the packet level means you can read Wireshark captures, interpret error messages accurately, and explain what's happening when a connection "fails" — to network teams, security teams, and in post-incident reviews.

**← Index:** [[00 Core Networking Index]] | **Next:** [[Day-02-Connection-Timeouts-vs-Read-Timeouts]] →

---

## Theory

### What a Socket Is

A socket is an OS-level file descriptor representing one end of a network connection. It is uniquely identified by a **4-tuple**:

```
(local IP : local port, remote IP : remote port)
```

Two connections to the same server port are different sockets as long as they differ in any one field — this is how a server handles thousands of simultaneous connections all arriving on port 443.

When ACE opens an HTTP connection to a backend API, the OS assigns an **ephemeral port** (typically 32768–60999 on Linux) on the local side. The remote side is the backend's IP and well-known port. That 4-tuple is the connection identity.

---

### The 3-Way Handshake

```
Client                              Server
  |                                   |
  |--- SYN (seq=x) ----------------> |  Client picks random ISN x, sets SYN flag
  |                                   |
  |<-- SYN-ACK (seq=y, ack=x+1) ----|  Server picks random ISN y, acknowledges x
  |                                   |
  |--- ACK (ack=y+1) --------------> |  Client acknowledges y. Connection: ESTABLISHED
  |                                   |
  |<========= data flows ============>|
```

**Critical details:**

- **ISN (Initial Sequence Number)** is randomly chosen — not 0. Randomisation prevents TCP sequence prediction attacks.
- **ACK number = received sequence number + 1** — meaning "I received up to byte X, send me X+1 next."
- Two independent sequence streams exist simultaneously — one per direction.
- **Half-open connections:** If the SYN-ACK is never answered (client crashed), the server holds the half-open state. SYN flood attacks exhaust this state table.

---

### Graceful Close — 4-Way Termination

```
Active closer                       Passive closer
  |--- FIN -----------------------> |  "I'm done sending"
  |<-- ACK ------------------------ |  "Got your FIN"
  |<-- FIN ------------------------ |  "I'm done sending too"
  |--- ACK -----------------------> |  "Got your FIN"
     [TIME_WAIT starts here]
```

Each side independently closes its **send** direction. The connection is full-duplex until both sides close — you can have half-closed connections where one side still streams data while the other has sent FIN.

---

### TIME_WAIT State

After the active closer sends the final ACK, it enters **TIME_WAIT** for `2 × MSL` (Maximum Segment Lifetime ≈ 60 seconds). During this time:

- The 4-tuple is reserved — no new connection can reuse it
- Catches any delayed duplicate packets from the old connection

> [!warning] Port Exhaustion Risk
> Services that open many short-lived connections — ACE polling an HTTP API every second, or a DataPower service under heavy load — can accumulate thousands of TIME_WAIT sockets. When ephemeral ports are exhausted, new connections fail with **"cannot assign requested address"** or **"address already in use"**.
>
> Check: `ss -s | grep timewait`

---

### TCP Connection States Reference

| State         | Meaning                                        | Stack Relevance                                 |
| ------------- | ---------------------------------------------- | ----------------------------------------------- |
| `LISTEN`      | Server ready for incoming connections          | ACE HTTP Listener, DataPower Front Side Handler |
| `SYN_SENT`    | Client sent SYN, awaiting SYN-ACK              | ACE connecting to a backend                     |
| `ESTABLISHED` | Connection active, data flowing                | Normal operation                                |
| `FIN_WAIT_1`  | Sent FIN, waiting for ACK                      | Graceful close initiated                        |
| `FIN_WAIT_2`  | FIN acknowledged, waiting for remote FIN       | —                                               |
| `TIME_WAIT`   | Both FINs exchanged, waiting for stale packets | Can accumulate under load                       |
| `CLOSE_WAIT`  | Got remote FIN, haven't sent own FIN yet       | Bug signal — see below                          |

> [!warning] CLOSE_WAIT Is a Bug Signal
> Accumulating `CLOSE_WAIT` sockets almost always means the **application** received a FIN (remote closed the connection) but never called `close()` on the socket. In ACE, this typically means a connection pool is leaking. In DataPower, it means a backend terminated the connection but DataPower didn't clean up. Check your HTTP node timeout and connection pool settings.

---

## Your Stack, Concretely

| Scenario                            | TCP reality                                                                                                                                                                                                           |
| ----------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ACE HTTP Request node → backend API | OS performs 3-way handshake to backend IP:port. ACE sends HTTP bytes over the established socket. FIN-ACK on completion (or socket returned to pool).                                                                 |
| DataPower MPG → ACE flow            | **Two separate TCP connections**: client→DataPower (handshake 1), DataPower→ACE (handshake 2). DataPower always terminates and re-establishes — it is never a transparent passthrough at the TCP level.               |
| Kafka producer → broker             | **Persistent connection** established at startup. One handshake, then all messages flow over that same connection. No new handshake per message — this is why broker reconnection events cause brief producer stalls. |
| MQ channel between queue managers   | One persistent TCP connection per MQ channel. Channel "not started" = TCP connection failed or refused. Channel dropping = TCP connection closed or RST received.                                                     |
| ACE → Oracle JDBC                   | Persistent connection pool. Each pool connection = one TCP socket. Pool size directly maps to socket count visible on the Oracle server.                                                                              |

---

## Hands-on

### Exercise 1 — Observe a Live Handshake in Wireshark

```bash
# Install Wireshark if not present
sudo apt install wireshark   # or brew install --cask wireshark on Mac

# Capture HTTP traffic to httpbin.org (port 80 for plaintext visibility)
sudo tcpdump -i any -n 'host httpbin.org and tcp' -w /tmp/handshake.pcap &

# Make a request
curl http://httpbin.org/get

# Stop capture
kill %1

# Open in Wireshark
wireshark /tmp/handshake.pcap
```

**What to find in Wireshark:**

1. First packet with `[SYN]` flag — note the random Sequence Number
2. Second packet with `[SYN, ACK]` — note: ACK = client's seq + 1, server has its own seq
3. Third packet with `[ACK]` — connection established
4. HTTP GET bytes flowing inside `[PSH, ACK]` packets
5. `[FIN, ACK]` termination sequence at the end

**Useful Wireshark filters:**

```
tcp.flags.syn == 1 && tcp.flags.ack == 0    # SYN packets only
tcp.flags.fin == 1                           # FIN packets
tcp.flags.reset == 1                         # RST packets
tcp.stream eq 0                              # Follow one conversation
```

---

### Exercise 2 — Inspect Socket States on Your Machine

```bash
# All TCP connections with state
ss -tn

# With process names (requires sudo)
sudo ss -tnp

# Summary including TIME_WAIT count
ss -s

# Watch state distribution in real time
watch -n 1 'ss -s'

# Count TIME_WAIT sockets
ss -tn state time-wait | wc -l

# See what's in LISTEN state (what your machine is serving)
ss -tlnp
```

---

### Exercise 3 — Trigger a RST and Identify It

```bash
# Start a capture
sudo tcpdump -i lo -n 'tcp port 9999' -w /tmp/rst.pcap &

# Try to connect to a port with nothing listening
curl http://localhost:9999 || true

kill %1
wireshark /tmp/rst.pcap
```

In Wireshark, filter `tcp.flags.reset == 1`. You'll see the RST from the OS — no SYN-ACK, no connection, just an immediate reset. This is exactly what "connection refused" looks like at the packet level.

---

### Exercise 4 — Observe a Half-Closed Connection

```bash
# Start a listener
nc -l 12345 &

# Connect to it
nc localhost 12345 &

# Verify ESTABLISHED on both ends
ss -tn | grep 12345

# Kill only the server side (simulates backend crash)
kill %1

# Observe the client socket
ss -tn | grep 12345
# State transitions from ESTABLISHED → CLOSE_WAIT
# This is what a leaked connection looks like
```

---

## Key Takeaways

- A TCP socket is a 4-tuple — two connections can share a server port as long as they differ elsewhere.
- The 3-way handshake establishes two independent sequence number streams, one per direction.
- TIME_WAIT is normal and protective. It becomes a problem only under high connection churn (check ephemeral port range and connection pool reuse).
- CLOSE_WAIT accumulation is an application bug, not a network problem.
- DataPower always terminates TCP — it establishes two connections, not one. Never transparent.

---

**← Index:** [[00 Core Networking Index]] | **Next:** [[Day-02-Connection-Timeouts-vs-Read-Timeouts]] →
