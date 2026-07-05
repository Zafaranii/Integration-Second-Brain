---
tags: [networking, bucket-1, load-balancing, l4, l7, nginx, day-6]
created: 2025-07-05
bucket: 1
week: 2
day: 6
status: not-started
---

# Day 6 — L4 vs L7 Load Balancing

> [!info] Why This Day Exists
> Every request reaching your ACE flows has already passed through at least one load balancer. OpenShift Routes, API Connect gateways, and DataPower clusters all use load balancing. Understanding the L4/L7 distinction explains why some features (TLS offload, path routing, sticky sessions) are possible in some configurations and not others.

**←** [[Day-05-Packet-Captures-for-Middleware]] | **Index:** [[00 Core Networking Index]] | **Next:** [[Day-07-OpenShift-Ingress-Routes-and-DNS]] →

---

## Theory

### L4 Load Balancing — Transport Layer

**What it sees:** IP addresses + TCP/UDP ports only. The load balancer operates on network packets — it does not read HTTP headers, URLs, or any application-layer content.

**How it works:**

```
Client → [L4 LB] → Backend A
                 → Backend B
                 → Backend C
```

The LB makes routing decisions based purely on source IP, destination IP, and port. It typically uses connection tracking (DNAT — Destination Network Address Translation) to rewrite the destination IP while keeping the TCP flow intact.

**Capabilities:**

- Routes any TCP or UDP traffic (not just HTTP)
- Very fast — minimal packet processing
- Lower resource usage than L7

**Limitations:**

- Cannot route by URL path (`/api/v1` vs `/health`)
- Cannot route by HTTP header or cookie
- Cannot terminate TLS (it can't read the encrypted payload)
- Cannot do request-level load balancing — only connection-level (one connection always goes to one backend for its lifetime)
- Cannot inspect or transform the payload

**Where you see L4 in your stack:**

- Kubernetes Service of type `ClusterIP` / `NodePort` uses kube-proxy (iptables or IPVS) — that's L4
- Hardware load balancers in front of OpenShift clusters are often L4
- MQ cluster load balancing (CCDT-based) is L4

---

### L7 Load Balancing — Application Layer

**What it sees:** Full HTTP request — method, URL, headers, cookies, body (if configured). The load balancer terminates the TCP connection, reads the HTTP request, makes a routing decision, then opens a new TCP connection to the backend.

**How it works:**

```
Client ← TCP connection 1 → [L7 LB] ← TCP connection 2 → Backend A
                                     ← TCP connection 3 → Backend B
```

The L7 LB always terminates and re-establishes. Two separate TCP connections, always.

**Capabilities:**

- Route by URL path: `/api/v1/*` → Service A, `/api/v2/*` → Service B
- Route by HTTP method, header value, cookie
- Terminate TLS (decrypt traffic, make routing decision, optionally re-encrypt)
- Sticky sessions based on cookie value (not just IP)
- Rate limiting per endpoint
- Request/response transformation
- Health checks via HTTP (check a specific path, not just port reachability)
- Access logging with HTTP context (method, path, status, latency)

**Where you see L7 in your stack:**

- OpenShift Routes (HAProxy-based) → L7
- IBM API Connect gateway (DataPower-based) → L7
- DataPower Multi-Protocol Gateway → L7
- Kafka client-side: the Kafka client does its own metadata-aware routing (L7 equivalent, but at the protocol level)

---

### Load Balancing Algorithms

| Algorithm            | How it works                                                | Best for                                                           |
| -------------------- | ----------------------------------------------------------- | ------------------------------------------------------------------ |
| Round Robin          | Request 1 → A, request 2 → B, request 3 → C, repeat         | Equal-capacity backends, uniform request cost                      |
| Weighted Round Robin | A gets 2x requests vs B                                     | Mixed-capacity backends                                            |
| Least Connections    | Route to backend with fewest active connections             | Variable request duration (some requests take 100ms, some take 5s) |
| IP Hash              | Hash source IP → always same backend                        | Stateful apps that can't use sticky cookies                        |
| Random               | Random backend selection                                    | Simple, surprisingly effective at scale                            |
| Least Response Time  | Route to fastest backend (measured by health check latency) | Heterogeneous backend performance                                  |

> [!tip] Least Connections for Integration Backends
> If your ACE backends process requests of wildly varying duration (a simple lookup vs a complex orchestration flow), least connections is usually better than round robin. Round robin can pile requests onto a backend that's already busy with slow requests.

---

### Health Checks

**Active health checks — L4:**

```
LB → TCP connect to backend:port → success = healthy, failure = unhealthy
```

Checks that the port is accepting connections. Does not verify the application is actually working.

**Active health checks — L7:**

```
LB → HTTP GET /health → 200 = healthy, non-200 or timeout = unhealthy
```

Can verify the application is actually serving requests. Can check response body for specific content.

**Passive health checks:**
The LB monitors real traffic — if a backend returns 5xx errors or times out consistently, it marks it unhealthy. No synthetic probe traffic.

**In OpenShift:** Routes use HAProxy active health checks. Pods also have separate `livenessProbe` and `readinessProbe` — the Deployment uses these to decide whether to include a pod in the Service endpoints, and the Route/LB uses active checks on top of that.

---

### Sticky Sessions

Sometimes you need the same client to always reach the same backend (session state, connection-level state like MQ channel).

**L4 sticky (IP Hash):** Same client IP → same backend. Breaks if client is behind NAT (all clients appear as one IP) or if client IP changes.

**L7 sticky (Cookie-based):** LB sets a cookie on the first response. Client includes the cookie in subsequent requests. LB reads the cookie and routes to the same backend. Works regardless of IP.

> [!warning] Sticky Sessions and Stateless Design
> Sticky sessions are a workaround for stateful backends. If at all possible, design backends to be stateless — any backend can serve any request. This makes rolling deployments, scaling, and failover much simpler. When a sticky backend dies, the client's session is lost anyway.

---

## Your Stack, Concretely

| Component                                 | Layer                     | Algorithm                               | TLS Termination         |
| ----------------------------------------- | ------------------------- | --------------------------------------- | ----------------------- |
| OpenShift Route (HAProxy)                 | L7                        | Round Robin (default)                   | Yes — Route handles TLS |
| Kubernetes ClusterIP Service (kube-proxy) | L4                        | Round Robin (IPVS) or Random (iptables) | No                      |
| IBM API Connect gateway cluster           | L7                        | Varies by config                        | Yes                     |
| DataPower cluster (multiple pods)         | L7 (when behind Route)    | OpenShift Route handles it              | Route terminates        |
| Kafka client                              | L7 (protocol-level)       | Leader-aware per partition              | Client handles TLS      |
| MQ cluster (CLRQMGR)                      | L4-ish (connection level) | Round Robin across cluster members      | Per-channel config      |

---

## Hands-on

### Exercise 1 — L7 Load Balancer with nginx: Round Robin

```bash
# Create a Docker network
docker network create lb-demo

# Start 3 backends that identify themselves
for i in 1 2 3; do
  docker run -d --name web$i --network lb-demo \
    -v $(pwd)/web$i.html:/usr/share/nginx/html/index.html \
    nginx
  echo "<h1>Backend $i</h1>" > web$i.html
done

# Create nginx load balancer config
cat > lb.conf << 'EOF'
upstream backends {
    server web1;
    server web2;
    server web3;
}

server {
    listen 80;
    location / {
        proxy_pass http://backends;
        add_header X-Backend $upstream_addr;
    }
}
EOF

# Start the LB
docker run -d --name lb --network lb-demo -p 8090:80 \
  -v $(pwd)/lb.conf:/etc/nginx/conf.d/default.conf \
  nginx

# Send 9 requests and see round-robin distribution
for i in {1..9}; do
  curl -s -o /dev/null -D - http://localhost:8090 | grep X-Backend
done
```

### Exercise 2 — Switch to Least Connections

```bash
# Edit lb.conf: change 'upstream backends {' block to:
cat > lb.conf << 'EOF'
upstream backends {
    least_conn;
    server web1;
    server web2;
    server web3;
}
...
EOF

# Reload nginx config inside the container
docker exec lb nginx -s reload

# Send requests again — observe distribution may differ
for i in {1..9}; do
  curl -s -o /dev/null -D - http://localhost:8090 | grep X-Backend
done
```

### Exercise 3 — Simulate Backend Health Check Failure

```bash
# Stop one backend
docker stop web2

# Send 9 more requests — verify web2 never appears in responses
for i in {1..9}; do
  curl -s -o /dev/null -D - http://localhost:8090 | grep X-Backend
done
# All responses should be from web1 and web3 only
```

### Exercise 4 — L7 Path-Based Routing

```bash
# Add a second upstream and path-based routing to lb.conf
cat > lb.conf << 'EOF'
upstream api_backends {
    server web1;
    server web2;
}

upstream static_backends {
    server web3;
}

server {
    listen 80;

    location /api/ {
        proxy_pass http://api_backends;
        add_header X-Upstream api_backends;
    }

    location / {
        proxy_pass http://static_backends;
        add_header X-Upstream static_backends;
    }
}
EOF

docker exec lb nginx -s reload

curl -v http://localhost:8090/api/users 2>&1 | grep X-Upstream
# → api_backends

curl -v http://localhost:8090/index.html 2>&1 | grep X-Upstream
# → static_backends
```

### Exercise 5 — Cleanup

```bash
docker rm -f lb web1 web2 web3
docker network rm lb-demo
```

---

## Key Takeaways

- **L4** routes by IP+port, is fast, cannot read HTTP. Used for TCP load balancing at scale.
- **L7** routes by HTTP content, terminates TLS, enables path routing and sticky cookies. More resource-intensive.
- OpenShift Routes are L7 (HAProxy). Kubernetes Services are L4 (kube-proxy).
- DataPower and API Connect are L7 — they always terminate and re-establish TCP.
- Least connections beats round robin when request processing times are variable.
- Sticky sessions are a stateful backend workaround — prefer stateless design where possible.

---

**←** [[Day-05-Packet-Captures-for-Middleware]] | **Index:** [[00 Core Networking Index]] | **Next:** [[Day-07-OpenShift-Ingress-Routes-and-DNS]] →
