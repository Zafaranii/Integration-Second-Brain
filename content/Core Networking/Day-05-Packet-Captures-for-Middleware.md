---
tags: [networking, bucket-1, wireshark, tcpdump, debugging, day-5]
created: 2025-07-05
bucket: 1
week: 1
day: 5
status: not-started
---

# Day 5 — Packet Captures for Middleware

> [!info] Why This Day Exists
> Packet captures are the ground truth of network debugging. Logs lie (they show what the application thinks happened). Packet captures show what actually happened at the wire level. This day builds the tcpdump + Wireshark toolkit specifically for the protocols in your stack: HTTP, MQ, Kafka, and JDBC over TCP.

**←** [[Day-04-TCP-Keepalives-vs-HTTP-Keep-Alive]] | **Index:** [[00 Core Networking Index]] | **Next:** [[Day-06-L4-vs-L7-Load-Balancing]] →

---

## Theory

### tcpdump — Command-Line Capture

`tcpdump` is the standard tool for capturing packets on Linux. It runs in the terminal, writes to `.pcap` files, and is available on most servers (including inside containers, if not stripped).

**Basic syntax:**

```bash
sudo tcpdump [options] [filter expression]
```

**Key options:**

```bash
-i any           # Capture on all interfaces (or specify: eth0, lo, ens3)
-n               # Don't resolve hostnames (faster, less noise)
-nn              # Don't resolve hostnames OR port names
-w file.pcap     # Write to file (open in Wireshark later)
-r file.pcap     # Read from file
-s 0             # Capture full packet (default often truncates to 96 bytes)
-v / -vv         # More verbose output
-c 1000          # Stop after 1000 packets
-X               # Print packet content as hex + ASCII
```

**Filter expressions (BPF — Berkeley Packet Filter):**

```bash
# By host
host 10.0.0.5
src host 10.0.0.5
dst host 10.0.0.5

# By port
port 1414           # MQ
port 9092           # Kafka
port 1521           # Oracle
tcp port 8080       # HTTP on ACE
tcp port 9090       # DataPower management

# Combinations
host 10.0.0.5 and port 1414
tcp port 9092 and not port 22
host 10.0.0.5 and (port 80 or port 443)

# By TCP flags
'tcp[tcpflags] & tcp-syn != 0'    # SYN packets
'tcp[tcpflags] & tcp-rst != 0'    # RST packets
'tcp[tcpflags] & tcp-fin != 0'    # FIN packets
```

---

### Wireshark — GUI Analysis

Wireshark opens `.pcap` files and provides:

- Colour-coded packet list
- Full protocol dissection (it understands HTTP, Kafka wire protocol, TLS, MQ to some extent)
- Follow TCP Stream (reconstructs the full conversation as readable text)
- Statistics → Conversations (see all TCP connections in the capture)
- IO Graph (visualise traffic over time)

**Essential Wireshark display filters:**

```
# TCP state filters
tcp.flags.syn == 1 && tcp.flags.ack == 0    # SYN only
tcp.flags.reset == 1                         # RST packets
tcp.flags.fin == 1                           # FIN packets

# Follow one stream
tcp.stream eq 0                              # Change 0 to stream number

# HTTP
http                                         # All HTTP traffic
http.request.method == "POST"
http.response.code == 500

# TLS
tls                                          # All TLS records
tls.handshake                                # Handshake messages only
tls.record.content_type == 21               # TLS alerts

# By host/port
ip.addr == 10.0.0.5
tcp.port == 1414

# Latency — time between request and response
http.time > 1.0                             # HTTP responses taking > 1 second
```

---

### Protocol-Specific Capture Strategies

#### IBM MQ (port 1414 / 1415 for TLS)

```bash
# Capture all MQ traffic
sudo tcpdump -i any -n -w mq.pcap 'tcp port 1414'
```

Wireshark partially dissects MQ (IBM MQ protocol dissector is built-in). You can see:

- Channel connect/disconnect events
- MQPUT/MQGET operations (partially decoded)
- MQ heartbeat packets (look for small packets during idle periods)

> [!note] TLS Caveat
> If your MQ channels use TLS (port 1415), the payload is encrypted and you'll only see the TLS handshake + encrypted records. You need the session keys or plaintext access to read the content. For debugging connection-level issues (handshake failures, RSTs), TLS captures are still useful — you don't need to decrypt to see the RST.

#### Kafka (port 9092 / 9093 for TLS)

```bash
# Capture Kafka traffic
sudo tcpdump -i any -n -w kafka.pcap 'tcp port 9092'
```

Wireshark has a Kafka protocol dissector. You can see:

- Producer `Produce` requests
- Consumer `Fetch` requests
- Metadata requests
- Heartbeat/OffsetCommit requests

Useful for verifying: is a producer actually connecting to the broker? Is a consumer fetching?

#### ACE HTTP (port 7080 / 7083)

```bash
# Capture ACE integration server HTTP traffic
sudo tcpdump -i any -n -w ace.pcap 'tcp port 7080 or tcp port 7083'
```

In Wireshark, right-click any HTTP packet → "Follow TCP Stream" to see the full HTTP conversation including headers and body.

#### Oracle JDBC (port 1521)

```bash
# Capture Oracle JDBC connection traffic
sudo tcpdump -i any -n -w oracle.pcap 'tcp port 1521'
```

Oracle uses its own TNS protocol. Wireshark dissects it partially — you can see connection attempts, TNS connect packets, and disconnects.

---

### Capture Inside OpenShift / Containers

Capturing inside a running container is trickier. Options:

**Option 1 — exec into the pod and use tcpdump (if installed)**

```bash
kubectl exec -it <pod-name> -- tcpdump -i any -w /tmp/capture.pcap
kubectl cp <pod-name>:/tmp/capture.pcap ./capture.pcap
```

**Option 2 — Use an ephemeral debug container (Kubernetes 1.23+)**

```bash
kubectl debug -it <pod-name> --image=nicolaka/netshoot -- tcpdump -i any -w /tmp/capture.pcap
```

`netshoot` is a network debugging container image with tcpdump, Wireshark CLI (tshark), dig, curl, ncat, iperf — all in one.

**Option 3 — Capture on the node at the pod's virtual interface**

```bash
# Find the node your pod is on
kubectl get pod <pod-name> -o wide

# SSH to the node, find the veth interface for that pod
ip link | grep veth

# Capture on that veth interface
sudo tcpdump -i veth<id> -w /tmp/node-capture.pcap
```

---

### Reading a Capture: Systematic Approach

When you open a `.pcap` file for a connection problem, work through this checklist:

1. **Statistics → Conversations** — how many TCP connections are in this capture? Are there unexpected connections?
2. **Filter `tcp.flags.reset == 1`** — any RSTs? When in the connection lifecycle? (During handshake = refused. After established = abort.)
3. **Filter `tcp.flags.syn == 1 && tcp.flags.ack == 0`** — SYNs. Did they all get SYN-ACK responses, or are some unanswered? (Unanswered SYN = firewall drop)
4. **Follow TCP Stream** on the failed connection — read the raw HTTP/protocol exchange
5. **Check timestamps** — how long between request and response? Where is the latency?

---

## Hands-on

### Exercise 1 — Capture and Dissect an HTTP Flow

```bash
# Capture
sudo tcpdump -i any -n -s 0 -w /tmp/http-flow.pcap 'host httpbin.org and tcp' &

# Generate traffic
curl http://httpbin.org/get
curl http://httpbin.org/post -X POST -d '{"test": "data"}'

kill %1
wireshark /tmp/http-flow.pcap
```

In Wireshark:

1. Find the first TCP stream. Follow it (right-click → Follow → TCP Stream).
2. Read the HTTP GET request headers.
3. Read the HTTP 200 response + JSON body.
4. Switch to the second stream — find the POST request and body.
5. Check Statistics → Conversations — how many TCP connections were opened?

---

### Exercise 2 — Capture a RST and Timeout Side by Side

```bash
sudo tcpdump -i any -n -s 0 -w /tmp/failures.pcap &

# Connection refused (RST)
curl http://localhost:19876 || true

# Connect timeout (SYN with no response — use an unrouteable IP)
curl --connect-timeout 3 http://192.0.2.1 || true

kill %1
wireshark /tmp/failures.pcap
```

In Wireshark:

- Filter `tcp.flags.reset == 1` — find the RST for the refused connection
- Filter `tcp.flags.syn == 1` — find the unanswered SYN retransmits for the timeout case

---

### Exercise 3 — Capture a Kafka Connection Lifecycle

```bash
# Start Kafka (reuse your Docker Compose from Bucket 1 setup)
docker compose up -d kafka

sudo tcpdump -i any -n -s 0 -w /tmp/kafka.pcap 'tcp port 9092' &

# Run a producer
python3 -c "
from kafka import KafkaProducer
p = KafkaProducer(bootstrap_servers='localhost:9092')
p.send('test-topic', b'hello from packet capture')
p.flush()
p.close()
"

kill %1
wireshark /tmp/kafka.pcap
```

In Wireshark, look for the Kafka protocol dissector:

- Metadata request (producer asking broker about the topic)
- Produce request
- Produce response with acknowledgement

---

### Exercise 4 — Build a tcpdump Cheat Sheet for Your Stack

Fill in this table for your own environment. These are the commands you'll use in production debugging:

```bash
# MQ: watch a specific queue manager's traffic
sudo tcpdump -i any -n -w mq-qm1.pcap 'tcp port 1414 and host <QM_HOST>'

# ACE: watch traffic between ACE and a specific backend
sudo tcpdump -i any -n -w ace-backend.pcap 'tcp and host <BACKEND_HOST>'

# Kafka: watch producer traffic to a specific broker
sudo tcpdump -i any -n -w kafka-broker1.pcap 'tcp port 9092 and host <BROKER_HOST>'

# DataPower: watch DataPower's outbound connections to ACE
sudo tcpdump -i any -n -w dp-to-ace.pcap 'tcp port 7080 and host <ACE_HOST>'

# Any connection issues — RSTs only
sudo tcpdump -i any -n 'tcp[tcpflags] & tcp-rst != 0'
```

---

## Key Takeaways

- `tcpdump` captures packets at the wire level — the ground truth that logs cannot provide.
- Wireshark's display filters let you isolate exactly what you need from a noisy capture.
- RSTs and unanswered SYNs are the two patterns that explain most middleware connection failures.
- Capturing inside OpenShift pods requires either a tcpdump-capable image or the `kubectl debug` ephemeral container approach.
- Build and save your tcpdump cheat sheet for your specific stack — you'll use it in production.

---

**←** [[Day-04-TCP-Keepalives-vs-HTTP-Keep-Alive]] | **Index:** [[00 Core Networking Index]] | **Next:** [[Day-06-L4-vs-L7-Load-Balancing]] →
