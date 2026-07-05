---
tags: [networking, bucket-1, firewall, debugging, tcpdump, ncat, day-9]
created: 2025-07-05
bucket: 1
week: 2
day: 9
status: not-started
---

# Day 9 — Diagnosing Firewall Drops

> [!info] Why This Day Exists
> In a banking environment every network path must be explicitly opened by the firewall team. New integration means a firewall change request. When something doesn't connect, the first question is always: "Is this a firewall issue or a service issue?" This day gives you the tools and systematic approach to answer that question definitively — without guessing.

**←** [[Day-08-Forward-Proxies-and-CONNECT-Tunnels]] | **Index:** [[00 Core Networking Index]] | **Next:** [[Day-10-Networking-Wrap-up-and-Scenario-Debugging]] →

---

## Theory

### Firewall Drop vs Service Problem — The Core Distinction

| Behaviour    | Firewall drop (DENY/DROP)                | Service not running            | Firewall reset (REJECT)        |
| ------------ | ---------------------------------------- | ------------------------------ | ------------------------------ |
| TCP response | No response (SYN unanswered)             | RST immediately                | RST from firewall              |
| curl error   | `Connection timed out` (after N seconds) | `Connection refused` (instant) | `Connection refused` (instant) |
| Error timing | Slow — waits for OS retransmit timeout   | Fast — immediate RST           | Fast — immediate RST           |
| tcpdump      | SYN packets sent, no SYN-ACK ever        | SYN → RST                      | SYN → RST from firewall IP     |

> [!tip] Fast = RST, Slow = Firewall Drop
> This timing heuristic is the fastest first filter. If `curl` fails in under 1 second → connection refused (RST) → service or port issue. If `curl` hangs for 5–30 seconds then fails → silent firewall drop.

---

### The Diagnostic Toolkit

#### 1. `curl` — Quick sanity check

```bash
# With explicit timeout to avoid waiting forever
curl --connect-timeout 5 --max-time 10 http://TARGET:PORT/path

# For plain TCP (non-HTTP) port testing
curl --connect-timeout 5 telnet://TARGET:PORT
```

#### 2. `nc` (netcat) / `ncat` — TCP/UDP port testing

```bash
# Test if a TCP port is open (exits immediately)
nc -zv TARGET PORT
# -z: don't send data, just test connectivity
# -v: verbose output

# Examples:
nc -zv kafka-broker-1 9092    # Kafka
nc -zv mq-qmgr-host 1414      # MQ
nc -zv oracle-db 1521          # Oracle
nc -zv ldap-server 636         # LDAPS

# With timeout
nc -zv -w 5 TARGET PORT    # 5-second timeout

# Output interpretation:
# "Connection to TARGET PORT port [tcp/...] succeeded!" → Port open, service listening
# "Connection refused"                                   → RST — service not running or firewall rejects
# (hangs until timeout)                                  → Firewall silently dropping
```

#### 3. `telnet` — Classic port test (often already installed)

```bash
# Test TCP connectivity
telnet TARGET PORT
# If it connects → you'll see a blank screen (or service banner)
# If "Connection refused" → RST
# If hangs → firewall drop

# Exit: Ctrl+] then type 'quit'
```

#### 4. `traceroute` / `tracepath` — Where does the packet stop?

```bash
# Trace hops to target (TCP mode — bypasses ICMP blocks)
traceroute -T -p PORT TARGET    # TCP traceroute
tracepath TARGET                 # UDP-based, no root required

# Interpretation:
# Last hop with a response → that's where packets stop going
# Asterisks (***) → hops not responding to probes (firewalls often block probes)
# If you reach the target IP but connection still fails → firewall at target is blocking
```

#### 5. `tcpdump` — Packet-level truth

```bash
# On the SOURCE machine: are SYNs being sent?
sudo tcpdump -i any -n 'host TARGET and tcp port PORT'

# On the TARGET machine (if accessible): are SYNs arriving?
sudo tcpdump -i any -n 'host SOURCE_IP and tcp port PORT'

# Compare:
# SYNs visible on source but NOT on target → firewall between them is dropping
# SYNs visible on BOTH → firewall not blocking; problem is at the service level
```

#### 6. `ss` / `netstat` — Is anything listening?

```bash
# On the target machine: confirm the service is listening
ss -tlnp | grep PORT

# If nothing appears → service is not running on that port
# If something appears → service is running; check firewall or binding (127.0.0.1 vs 0.0.0.0)
```

---

### The Diagnostic Sequence

Work through this in order. Stop when you find the layer that's broken.

```
Step 1: DNS — can you resolve the hostname?
  nslookup TARGET_HOSTNAME
  If fails → DNS problem (wrong hostname, DNS not configured)
  If succeeds → proceed

Step 2: Reachability — can you reach the IP at all?
  ping TARGET_IP
  (Note: ICMP ping is often blocked in banks — a failed ping doesn't prove unreachability)
  Better: traceroute -T -p PORT TARGET_IP

Step 3: Port connectivity — is the port open?
  nc -zv -w 5 TARGET PORT
  Fast success → port open, proceed to Step 5
  Fast refuse  → RST (Step 4a)
  Timeout      → firewall drop (Step 4b)

Step 4a: RST case — why is the port refusing?
  On target machine: ss -tlnp | grep PORT
  If nothing listening → service not started, or listening on wrong port/interface
  If something listening → firewall REJECT rule, or binding to 127.0.0.1 only

Step 4b: Timeout case — where is the drop?
  Run tcpdump on source: see if SYNs are being sent
  Run tcpdump on target: see if SYNs are arriving
  SYN on source but not target → intermediate firewall
  SYN on both but no SYN-ACK → target firewall (iptables on the target itself)

Step 5: TLS — does TLS work on top of the open port?
  openssl s_client -connect TARGET:PORT
  If fails → TLS config issue (cert, cipher, version — Bucket 2 territory)

Step 6: Application — does the service respond correctly?
  curl http://TARGET:PORT/health
  If fails → application layer issue
```

---

### Banking-Specific Firewall Patterns

**Pattern 1: Stateful firewall with connection tracking**
Most common. Only the initiating direction needs an "allow" rule. Return traffic is permitted automatically because the firewall tracks connection state. A rule allowing `10.10.1.0/24 → 10.20.1.5:1414` also allows the return traffic from the MQ server.

**Pattern 2: Separate ingress and egress rules**
Some environments require explicit rules in both directions. Symptom: connection works from source A to target B, but replies don't make it back. `tcpdump` on target shows SYN arriving and SYN-ACK being sent, but source never receives it.

**Pattern 3: Application-level proxy rules**
Certain destinations (usually external internet) can only be reached via a specific proxy (see [[Day-08-Forward-Proxies-and-CONNECT-Tunnels]]). Direct connections are dropped. Symptom: connection timeout even to valid external endpoints.

**Pattern 4: DMZ restrictions**
DataPower lives in a DMZ. Rules typically allow: internet → DataPower (ports 443/80), DataPower → internal ACE (port 7080), DataPower → internal MQ (port 1414). Traffic from internal zones directly to internet is blocked. ACE cannot initiate connections to the internet — all external calls must go through DataPower or the proxy.

---

### OpenShift-Specific: NetworkPolicy Blocking

Inside OpenShift, `NetworkPolicy` acts as a firewall at the pod level. Symptom: you can reach a service's ClusterIP from outside the cluster (via Route) but pods cannot reach each other.

```bash
# Check for NetworkPolicies in the target namespace
kubectl get networkpolicy -n TARGET_NAMESPACE

# If policies exist, check if your source pod/namespace is in an allow rule
kubectl describe networkpolicy POLICY_NAME -n TARGET_NAMESPACE

# Test from source pod
kubectl exec -it SOURCE_POD -n SOURCE_NS -- nc -zv TARGET_SERVICE.TARGET_NS 9092

# If blocked → add NetworkPolicy rule or ask cluster admin to
```

---

## Hands-on

### Exercise 1 — Build Your Diagnostic Muscle Memory

Run through all tools against a known-good endpoint:

```bash
TARGET=google.com
PORT=443

# DNS
nslookup $TARGET

# Connectivity (TCP traceroute)
traceroute -T -p $PORT $TARGET

# Port test
nc -zv -w 5 $TARGET $PORT

# TLS
openssl s_client -connect $TARGET:$PORT -brief

# Application
curl -I https://$TARGET
```

Then repeat against a port that's closed:

```bash
nc -zv -w 5 $TARGET 9999
# → Connection refused (RST)

nc -zv -w 3 192.0.2.1 80
# → Timeout (unreachable / firewall drop)
```

### Exercise 2 — Two-Sided tcpdump (Firewall vs Service)

```bash
# Terminal 1 (source machine): watch for outgoing SYNs
sudo tcpdump -i any -n 'tcp port 19876'

# Terminal 2: attempt connection
nc -zv localhost 19876

# You'll see: SYN sent on lo interface, RST received → nothing listening

# Now start a listener
nc -l 19876 &

# Try again from Terminal 2
nc -zv localhost 19876

# Terminal 1: now you'll see SYN + SYN-ACK + ACK → successful handshake
```

### Exercise 3 — iptables to Simulate Firewall Drop vs Reject

```bash
# Simulate SILENT DROP (firewall DROP rule)
sudo iptables -A INPUT -p tcp --dport 18888 -j DROP

nc -zv -w 3 localhost 18888
# → Timeout (because DROP silently discards the packet)

# Remove DROP rule, add REJECT (sends RST)
sudo iptables -D INPUT -p tcp --dport 18888 -j DROP
sudo iptables -A INPUT -p tcp --dport 18888 -j REJECT --reject-with tcp-reset

nc -zv -w 3 localhost 18888
# → Connection refused (immediate RST)

# Clean up
sudo iptables -D INPUT -p tcp --dport 18888 -j REJECT --reject-with tcp-reset
```

### Exercise 4 — OpenShift NetworkPolicy Blocking Test

```bash
# Deploy two test pods in different namespaces
kubectl create namespace ns-source
kubectl create namespace ns-target

kubectl run server -n ns-target --image=nginx --port=80
kubectl expose pod server -n ns-target --port=80

kubectl run client -n ns-source --image=nicolaka/netshoot -- sleep 3600

# Test connectivity (should work — no NetworkPolicy yet)
kubectl exec client -n ns-source -- nc -zv server.ns-target 80

# Apply a NetworkPolicy that denies all ingress to ns-target
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: ns-target
spec:
  podSelector: {}
  ingress: []
EOF

# Test again — now blocked
kubectl exec client -n ns-source -- nc -zv -w 3 server.ns-target 80
# → Timeout (NetworkPolicy is DROP, not REJECT)

# Cleanup
kubectl delete namespace ns-source ns-target
```

---

## Cheat Sheet: Quick Reference

```bash
# ─── Quick port test ──────────────────────────────
nc -zv -w 5 HOST PORT

# ─── Is service listening? ────────────────────────
ss -tlnp | grep PORT

# ─── DNS resolve ─────────────────────────────────
nslookup HOSTNAME
dig HOSTNAME

# ─── TLS connectivity ─────────────────────────────
openssl s_client -connect HOST:PORT

# ─── Watch SYNs in real time ─────────────────────
sudo tcpdump -i any -n 'tcp port PORT and tcp[tcpflags] & tcp-syn != 0'

# ─── Watch RSTs ──────────────────────────────────
sudo tcpdump -i any -n 'tcp[tcpflags] & tcp-rst != 0'

# ─── Trace route (TCP mode) ──────────────────────
traceroute -T -p PORT HOST

# ─── Stack-specific ports ────────────────────────
# MQ: 1414 | Kafka: 9092/9093 | ACE: 7080/7083
# DataPower: 8080/8443/9090 | Oracle: 1521 | LDAPS: 636
```

---

## Key Takeaways

- Fast failure = RST = connection refused = service problem (not a firewall drop).
- Slow failure = timeout = silent firewall DROP.
- `nc -zv -w 5 HOST PORT` is your fastest first test. Learn the output cold.
- Two-sided `tcpdump` is definitive: SYN on source but not on target = firewall in between.
- In OpenShift, NetworkPolicy is a pod-level firewall — it produces timeouts (DROP), not RSTs, making it easy to confuse with an external firewall.
- Always check: is the service listening? (`ss -tlnp`) before blaming the firewall.

---

**←** [[Day-08-Forward-Proxies-and-CONNECT-Tunnels]] | **Index:** [[00 Core Networking Index]] | **Next:** [[Day-10-Networking-Wrap-up-and-Scenario-Debugging]] →
