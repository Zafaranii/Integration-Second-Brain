---
tags: [networking, bucket-1, openshift, ingress, routes, dns, day-7]
created: 2025-07-05
bucket: 1
week: 2
day: 7
status: not-started
---

# Day 7 — OpenShift Ingress, Routes & DNS

> [!info] Why This Day Exists
> You deploy to OpenShift regularly. Routes appear, services resolve, traffic flows — but what is actually doing that? This day demystifies the full networking path from external client to your ACE or DataPower pod, including DNS resolution inside the cluster, which is the source of many "why can't service A reach service B" issues.

**←** [[Day-06-L4-vs-L7-Load-Balancing]] | **Index:** [[00 Core Networking Index]] | **Next:** [[Day-08-Forward-Proxies-and-CONNECT-Tunnels]] →

---

## Theory

### The Path from Client to Pod

```
External Client
      │
      ▼
[External DNS] resolves *.apps.cluster.example.com → OpenShift Ingress VIP
      │
      ▼
[OpenShift Ingress / HAProxy Router] (L7 load balancer)
      │  matches Route by hostname + path
      ▼
[Kubernetes Service] (ClusterIP — L4, kube-proxy/iptables)
      │  selects a healthy pod endpoint
      ▼
[Pod] (your ACE / DataPower / API container)
```

Each layer has a distinct job. Most "networking issues" in OpenShift can be pinpointed to one of these four layers.

---

### OpenShift Routes

A Route is an OpenShift-specific resource (not a standard Kubernetes resource — it predates the Ingress spec). Under the hood, it configures the HAProxy router to forward traffic for a specific hostname to a specific Service.

**Route anatomy:**

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: my-ace-flow
  namespace: integration
spec:
  host: my-ace-flow.apps.cluster.example.com # Hostname to match
  path: /api/v1 # Optional path prefix
  to:
    kind: Service
    name: my-ace-service # Target Service
    weight: 100
  port:
    targetPort: 7080 # Service port to use
  tls:
    termination: edge # TLS handling — see below
    insecureEdgeTerminationPolicy: Redirect # Redirect HTTP→HTTPS
```

**TLS termination modes:**

| Mode          | Meaning                                                                | Use case                                                   |
| ------------- | ---------------------------------------------------------------------- | ---------------------------------------------------------- |
| `edge`        | HAProxy terminates TLS; forwards HTTP to pod                           | Most common. TLS cert lives on the Route.                  |
| `passthrough` | HAProxy does NOT terminate TLS; forwards encrypted TCP directly to pod | Pod handles TLS itself (e.g. DataPower with its own cert). |
| `reencrypt`   | HAProxy terminates TLS, then re-encrypts for the backend pod           | Zero-trust: encrypted on both segments.                    |

> [!note] DataPower on OpenShift
> DataPower pods typically use `passthrough` routes because DataPower handles its own TLS via SSL Server Profiles. The HAProxy router sees TLS traffic but forwards it directly to the DataPower pod's port without termination.

**Wildcard DNS:**

OpenShift clusters use a wildcard DNS entry: `*.apps.cluster.example.com → Ingress VIP`. Any Route with a hostname matching `*.apps.cluster.example.com` is automatically reachable externally. This is why creating a Route immediately makes a service accessible — the DNS is already there.

---

### Kubernetes Services — Cluster-Internal Load Balancing

A Service provides a stable virtual IP (ClusterIP) in front of a dynamic set of pods. Pods come and go; the Service IP stays fixed.

**How kube-proxy makes it work:**

kube-proxy watches the Kubernetes API for Service and Endpoint changes, then programs iptables (or IPVS) rules to DNAT traffic destined for the ClusterIP to one of the healthy pod IPs.

```bash
# See Service ClusterIPs
kubectl get svc -n integration

# See the actual pod IPs behind a service (Endpoints)
kubectl get endpoints my-ace-service -n integration

# See the iptables rules that implement the routing (on a node)
sudo iptables -t nat -L KUBE-SERVICES -n | grep my-ace-service
```

**Service types:**
| Type | Accessibility | Use case |
|------|--------------|---------|
| `ClusterIP` | Only inside cluster | Service-to-service communication |
| `NodePort` | Node IP + static port | External access without a Route (less common) |
| `LoadBalancer` | External IP (cloud/MetalLB) | Expose non-HTTP services externally |
| `ExternalName` | DNS CNAME to external hostname | Reference an external service by internal DNS name |

---

### DNS Inside OpenShift (CoreDNS)

OpenShift runs **CoreDNS** as the cluster-internal DNS server. Every pod has `/etc/resolv.conf` pointing to CoreDNS.

**DNS resolution rules inside a pod:**

```
Service DNS name formats:
<service-name>                                    → resolves if in same namespace
<service-name>.<namespace>                        → cross-namespace
<service-name>.<namespace>.svc                   → explicit cluster-local
<service-name>.<namespace>.svc.cluster.local      → fully qualified (FQDN)

Examples:
my-ace-service                                    → my-ace-service.integration.svc.cluster.local
kafka.messaging                                   → kafka.messaging.svc.cluster.local
```

**Common DNS failure modes:**

| Error                                           | Cause                                                                         | Fix                                                               |
| ----------------------------------------------- | ----------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| `Name or service not known`                     | Wrong service name, wrong namespace, or service doesn't exist                 | `kubectl get svc -n <namespace>` to verify                        |
| Service resolves but connection refused         | Service exists but no healthy pods (endpoints empty)                          | `kubectl get endpoints <svc>` — empty = no pods matching selector |
| Cross-namespace DNS works locally, fails in pod | Pod's search domain doesn't include target namespace                          | Use `<svc>.<namespace>` form explicitly                           |
| External hostname doesn't resolve from pod      | Network policy blocks egress to external DNS, or corporate DNS not configured | Check NetworkPolicy egress rules                                  |

**Debugging DNS from inside a pod:**

```bash
# Get a debug shell inside the cluster
kubectl run -it --rm dns-debug --image=nicolaka/netshoot --restart=Never -- bash

# Inside the pod:
# Check resolv.conf
cat /etc/resolv.conf

# Resolve a service
nslookup my-ace-service.integration.svc.cluster.local

# Resolve external hostname
nslookup api.external-bank.com

# Trace the resolution path
dig my-ace-service.integration.svc.cluster.local @$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}')
```

---

### DataPower DNS Caching (Critical Gotcha)

DataPower caches DNS lookups internally. When a backend DNS entry changes (e.g. a Service IP changes after cluster reconfiguration), DataPower continues using the old cached IP until:

- The cache TTL expires
- DataPower is restarted
- You manually flush the DNS cache via the REST Management API

**In OpenShift:** Service ClusterIPs are stable — they don't change unless the Service is deleted and recreated. But if you're pointing DataPower at an **external** hostname that changes IP (e.g. a partner API behind a DNS-based LB), DataPower may hold a stale IP.

**Flush DataPower DNS cache:**

```bash
# Via DataPower CLI
idg# configure
idg(config)# dns flush-cache

# Via REST Management API
curl -k -X POST -u admin:password \
  https://datapower-pod:5554/mgmt/actionqueue/default \
  -H "Content-Type: application/json" \
  -d '{"DNSNameCacheFlush": {}}'
```

---

### NetworkPolicy — Pod-Level Firewall

NetworkPolicy resources define which pods can talk to which other pods and external endpoints. If your ACE pod can't reach a Kafka broker or a database, a NetworkPolicy may be blocking it even though the Service and DNS are correct.

```yaml
# Example: Allow ACE pods to reach Kafka pods on port 9092
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ace-to-kafka
  namespace: messaging
spec:
  podSelector:
    matchLabels:
      app: kafka
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: integration
          podSelector:
            matchLabels:
              app: ace-server
      ports:
        - port: 9092
```

**Debugging NetworkPolicy:**

```bash
# Check if any NetworkPolicies exist in a namespace
kubectl get networkpolicy -n integration
kubectl get networkpolicy -n messaging

# Describe them to see selectors
kubectl describe networkpolicy allow-ace-to-kafka -n messaging

# Test connectivity from a pod
kubectl exec -it <ace-pod> -n integration -- curl http://kafka.messaging:9092
# If this fails and no NetworkPolicy → Service/DNS problem
# If this fails and NetworkPolicy exists → NetworkPolicy is likely blocking
```

---

## Hands-on

### Exercise 1 — Trace a Route's Full Path

Pick any exposed service in your OpenShift cluster.

```bash
# 1. Get the Route
kubectl get route -n integration

# 2. Find the Service it points to
kubectl describe route <route-name> -n integration | grep "Service"

# 3. Find the Endpoints (actual pod IPs) behind that Service
kubectl get endpoints <service-name> -n integration

# 4. Get the pod names for those IPs
kubectl get pods -n integration -o wide | grep <pod-IP>

# 5. Verify: the Route → Service → pods chain is intact
```

### Exercise 2 — DNS Resolution from Inside a Pod

```bash
# Deploy a debug pod
kubectl run dns-debug -n integration --image=nicolaka/netshoot --restart=Never -- sleep 3600

# Shell into it
kubectl exec -it dns-debug -n integration -- bash

# Inside the pod:
cat /etc/resolv.conf

# Resolve services in your namespace (same namespace as debug pod)
nslookup ace-service

# Cross-namespace
nslookup kafka.messaging.svc.cluster.local

# External
nslookup google.com

# If external fails but internal works → DNS egress NetworkPolicy blocking external resolution
exit

# Cleanup
kubectl delete pod dns-debug -n integration
```

### Exercise 3 — Inspect a Service's Endpoints

```bash
# A Service with no Endpoints = "connection refused" even though DNS works
kubectl get endpoints -n integration

# Find a Service with 0 endpoints (if any) and debug why:
kubectl describe endpoints <empty-svc> -n integration
# Look at: events section, check if selector matches any pods

kubectl get pods -n integration --show-labels | grep <expected-label>
# If no pods match the selector → no endpoints → requests fail at L4
```

---

## Key Takeaways

- External traffic path: DNS → Ingress Router (L7/HAProxy) → Service (L4/kube-proxy) → Pod.
- Routes = OpenShift's L7 routing config. Three TLS modes: edge (HAProxy terminates), passthrough (pod handles TLS), reencrypt (both segments encrypted).
- Service DNS format inside pods: `<service>.<namespace>.svc.cluster.local`. Use the full form for cross-namespace calls.
- Empty Endpoints = no healthy pods matching the Service selector. Not a DNS or network policy problem.
- NetworkPolicy is a silent blocker — connection refused with no error in the network path, just in the pod-to-pod iptables rules.
- DataPower caches DNS — flush manually when backend IPs change.

---

**←** [[Day-06-L4-vs-L7-Load-Balancing]] | **Index:** [[00 Core Networking Index]] | **Next:** [[Day-08-Forward-Proxies-and-CONNECT-Tunnels]] →
