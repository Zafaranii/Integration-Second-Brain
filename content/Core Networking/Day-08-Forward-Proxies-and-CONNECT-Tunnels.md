---
tags: [networking, bucket-1, proxy, forward-proxy, connect-tunnel, datapower, day-8]
created: 2025-07-05
bucket: 1
week: 2
day: 8
status: not-started
---

# Day 8 — Forward Proxies and CONNECT Tunnels

> [!info] Why This Day Exists
> In a banking environment, integration servers and DataPower gateways almost never connect directly to external APIs or partner systems. Traffic goes through a corporate forward proxy first. Understanding how CONNECT tunneling works — and how to configure ACE, DataPower, and Kafka clients to use a proxy — is essential operational knowledge. Misconfigured proxy settings are among the most common causes of "ACE can't reach external endpoint" tickets.

**←** [[Day-07-OpenShift-Ingress-Routes-and-DNS]] | **Index:** [[00 Core Networking Index]] | **Next:** [[Day-09-Diagnosing-Firewall-Drops]] →

---

## Theory

### Forward Proxy vs Reverse Proxy

|                   | Forward Proxy                                                      | Reverse Proxy                                       |
| ----------------- | ------------------------------------------------------------------ | --------------------------------------------------- |
| Who configures it | The **client** — the client explicitly sends requests to the proxy | The **server side** — clients don't know it exists  |
| What it hides     | The client's identity from the server                              | The backend server's identity from the client       |
| Direction         | Client → Proxy → External Server                                   | External Client → Proxy → Internal Server           |
| Examples          | Corporate internet proxy, Squid                                    | nginx, HAProxy, DataPower, OpenShift Route          |
| Use case          | Control and audit outbound internet access from internal network   | Expose internal services, TLS offload, load balance |

In a bank: your ACE/DataPower needs to call an external partner API → traffic must go through the forward proxy. The proxy checks the destination against allowed rules, logs the request, and forwards it. No direct internet access from internal servers.

---

### Plain HTTP Through a Proxy

For plain HTTP requests, the client sends a normal HTTP request but addresses it to the proxy instead of the server. The proxy reads the `Host` header and the full URL, forwards it, gets the response, and returns it to the client.

```
Client → Proxy

GET http://api.partner.com/v1/accounts HTTP/1.1
Host: api.partner.com
```

The client sends the full URL (not just the path) because the proxy needs to know where to forward it.

---

### HTTPS / TLS Through a Proxy — The CONNECT Method

Plain proxy forwarding breaks for HTTPS: the proxy can't read the encrypted TLS payload, so it can't forward the request. The solution is the HTTP CONNECT method, which creates a **tunnel**.

**How CONNECT works:**

```
Step 1: Client → Proxy
  CONNECT api.partner.com:443 HTTP/1.1
  Host: api.partner.com:443

Step 2: Proxy → Client (if allowed)
  HTTP/1.1 200 Connection Established

Step 3: Client performs TLS handshake with api.partner.com THROUGH the tunnel
  [TLS ClientHello → api.partner.com]
  [TLS ServerHello, Certificate ← api.partner.com]
  [TLS handshake complete]

Step 4: Encrypted HTTPS traffic flows through the proxy
  [Encrypted application data — proxy cannot read this]
```

The proxy sees: client wants to connect to `api.partner.com:443`. It opens a TCP connection to `api.partner.com:443` and forwards all bytes blindly in both directions. The TLS handshake happens between the client and the actual server — the proxy is just a byte relay.

**What the proxy can and cannot do:**

- ✅ Can: allow/deny by destination hostname and port
- ✅ Can: log which destinations were accessed and by whom
- ✅ Can: require proxy authentication (Proxy-Authorization header)
- ❌ Cannot: read the encrypted HTTPS payload (unless doing SSL inspection)
- ❌ Cannot: modify the request/response

---

### SSL Inspection (TLS Interception)

Some corporate proxies perform **SSL inspection**: they act as a man-in-the-middle, terminating the client's TLS and re-establishing a new TLS connection to the server. They issue their own certificate signed by a corporate CA.

**How you know it's happening:**

- When you connect to an external HTTPS endpoint through the proxy, the certificate you receive is signed by an internal corporate CA (not by Let's Encrypt, DigiCert, etc.)
- `openssl s_client -connect api.partner.com:443 -proxy corporate-proxy:8080` shows an internal CA in the chain

**Impact on your integrations:**

- ACE and DataPower must trust the corporate CA certificate (add it to their trust stores)
- Certificate pinning breaks under SSL inspection — if your client pins the server's cert fingerprint, it will fail because the proxy presents a different cert
- DataPower SSL Client Profiles need the corporate CA in their Validation Credentials

---

### Proxy Authentication

Corporate proxies usually require authentication.

**Basic authentication (username:password in header):**

```
CONNECT api.partner.com:443 HTTP/1.1
Proxy-Authorization: Basic dXNlcjpwYXNz==
```

**NTLM/Kerberos (Windows-integrated auth):**
More complex multi-step negotiation — common in Microsoft-centric banks. Java/ACE JVM settings need to handle this.

---

### Configuring Proxy in Your Stack

#### IBM ACE — HTTP Request Node

ACE reads JVM proxy settings from the integration server's `server.conf.yaml` or JVM args:

```yaml
# server.conf.yaml
RestAdminListener:
  port: 7600

HTTPSConnector:
  proxyHost: "corporate-proxy.bank.internal"
  proxyPort: 8080
  proxyUser: "svc-ace-proxy"
  proxyPassword: "{encrypted}"
```

Or via JVM system properties in `jvm.options`:

```
-Dhttps.proxyHost=corporate-proxy.bank.internal
-Dhttps.proxyPort=8080
-Dhttp.proxyHost=corporate-proxy.bank.internal
-Dhttp.proxyPort=8080
-Dhttp.nonProxyHosts=*.bank.internal|localhost|127.0.0.1
```

`nonProxyHosts` is critical — it tells ACE which destinations to reach directly without going through the proxy. Internal services, Kafka brokers, MQ queue managers — all should be in `nonProxyHosts`.

---

#### IBM DataPower — Forward Proxy Object

DataPower has a dedicated **Forward Proxy** object:

```
Objects → Network → Forward Proxy
  Name: corp-forward-proxy
  Hostname: corporate-proxy.bank.internal
  Port: 8080
  [Optional] Username / Password for proxy auth
```

This Forward Proxy object is then referenced in:

- **SSL Client Profile**: set the Forward Proxy → DataPower will CONNECT through the proxy for all HTTPS backend calls using this SSL Client Profile
- **HTTP Back Side Handler** on a Multi-Protocol Gateway

> [!tip] DataPower Proxy Scope
> The Forward Proxy setting on an SSL Client Profile only applies to HTTPS calls using that profile. Plain HTTP backend calls are configured separately. If you want all DataPower outbound traffic to use the proxy, every SSL Client Profile and HTTP handler must reference it.

---

#### Kafka Clients Through a Proxy

Kafka's binary protocol does not natively support HTTP CONNECT proxies. Options:

1. **Network-level proxy (SOCKS5):** Kafka Java client supports SOCKS5 proxy via JVM settings. SOCKS5 is a protocol-agnostic proxy that works at the TCP level.

   ```properties
   # kafka producer/consumer properties
   security.protocol=SSL
   # JVM args for SOCKS5
   -DsocksProxyHost=socks-proxy.bank.internal
   -DsocksProxyPort=1080
   ```

2. **Network route exception:** The Kafka broker IPs are explicitly allowed through the firewall without proxy. This is the most common approach — Kafka brokers are internal or in a specific DMZ zone that internal servers can reach directly.

3. **Kafka REST Proxy:** A REST wrapper in front of Kafka that your service calls via HTTPS (which can go through the corporate proxy). Adds latency and a component.

---

### CONNECT Tunnel Verification

```bash
# Test if you can CONNECT through the proxy to an external HTTPS endpoint
curl -v -x http://corporate-proxy:8080 https://api.partner.com/health

# Test proxy authentication
curl -v -x http://user:pass@corporate-proxy:8080 https://api.partner.com/health

# Verify which cert you're getting (checking for SSL inspection)
openssl s_client -connect api.partner.com:443 -proxy corporate-proxy:8080 2>/dev/null | \
  openssl x509 -noout -issuer -subject

# If issuer is an internal CA → SSL inspection is happening
```

---

## Hands-on

### Exercise 1 — Run a Local Forward Proxy (Squid)

```bash
# Start a Squid proxy in Docker
docker run -d --name squid -p 3128:3128 ubuntu/squid

# Test plain HTTP through it
curl -v -x http://localhost:3128 http://httpbin.org/get

# Test HTTPS through CONNECT tunnel
curl -v -x http://localhost:3128 https://httpbin.org/get

# Watch Squid access log to confirm CONNECT tunnel
docker exec squid tail -f /var/log/squid/access.log
# You'll see: CONNECT httpbin.org:443 - 200 → tunnel established
```

### Exercise 2 — Block a Destination and Observe the Error

```bash
# Add an ACL to Squid to deny httpbin.org
docker exec -it squid bash -c "
echo 'acl blocked_sites dstdomain .httpbin.org
http_access deny blocked_sites' >> /etc/squid/squid.conf
squid -k reconfigure
"

# Retry the request
curl -v -x http://localhost:3128 https://httpbin.org/get

# You'll get: 403 Forbidden (from the proxy, not from httpbin.org)
# The CONNECT was denied — the tunnel was never established
```

### Exercise 3 — Configure JVM Proxy and Verify nonProxyHosts

```bash
# Simulate what ACE sees with JVM proxy settings
java \
  -Dhttps.proxyHost=localhost \
  -Dhttps.proxyPort=3128 \
  -Dhttp.nonProxyHosts="*.local|localhost|127.0.0.1" \
  -jar your-http-client.jar https://httpbin.org/get

# The request to httpbin.org should go through Squid
# A request to localhost:7080 should go direct (matched by nonProxyHosts)
```

### Exercise 4 — Identify SSL Inspection on Your Network

```bash
# From your workstation or from an ACE/DataPower pod, run:
openssl s_client -connect google.com:443 2>/dev/null | openssl x509 -noout -issuer

# If the issuer is something like:
# issuer=C=EG, O=AlBilad Bank, CN=AlBilad Proxy CA
# → SSL inspection is active. Your ACE and DataPower trust stores need this CA cert.

# If the issuer is:
# issuer=C=US, O=Google Trust Services, CN=GTS CA 1C3
# → No SSL inspection (or you're connecting directly)
```

---

## Key Takeaways

- Forward proxy = outbound traffic controller. Clients route through it to reach the internet.
- HTTP CONNECT creates a TCP tunnel through the proxy. The proxy forwards bytes blindly — it never sees the TLS payload (unless doing SSL inspection).
- SSL inspection means your integrations will receive a certificate signed by a corporate CA — trust stores in ACE and DataPower must include that CA.
- `nonProxyHosts` / `http.nonProxyHosts` in JVM settings controls which internal destinations bypass the proxy — always exclude internal hostnames, Kafka brokers, MQ queue managers.
- DataPower has a dedicated Forward Proxy object — it must be referenced by each SSL Client Profile that calls external HTTPS endpoints.
- Kafka doesn't speak HTTP CONNECT — use SOCKS5 proxy support or firewall route exceptions for Kafka traffic.

---

**←** [[Day-07-OpenShift-Ingress-Routes-and-DNS]] | **Index:** [[00 Core Networking Index]] | **Next:** [[Day-09-Diagnosing-Firewall-Drops]] →
