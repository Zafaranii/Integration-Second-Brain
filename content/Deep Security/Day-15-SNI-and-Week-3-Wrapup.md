---
tags: [security, bucket-2, tls, sni, wrapup, day-15]
created: 2025-07-05
bucket: 2
week: 3
day: 15
status: not-started
prerequisites: ["Day-14-CA-Chains-and-Trust-Stores"]
---

# Day 15 — SNI & Week 3 Wrap-up / Scenario Debugging

> [!info] Why This Day Exists
> One IP address, dozens of HTTPS hostnames — this is every OpenShift Route, every DataPower MPG, every load balancer fronting multiple ACE integration servers. SNI is the mechanism that makes that possible, and it's also a classic source of "wrong certificate returned" bugs when it's misconfigured or when a client doesn't send it at all.

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-14-CA-Chains-and-Trust-Stores]] | **Next:** [[Day-16-One-Way-TLS-vs-mTLS]] →

---

## 🧠 Theory Block (15 mins)

### The Problem SNI Solves

TLS establishes encryption _before_ any HTTP request (including the `Host:` header) is sent. So if a single IP:port is fronting multiple HTTPS sites — `api.bank.com` and `partner.bank.com` on the same load balancer — how does the server know _which_ certificate to present, if it hasn't seen the `Host` header yet?

```
Without SNI:
  Client → [TCP handshake] → [TLS ClientHello — no hostname info] → Server: "...which cert do I send??"

With SNI:
  Client → [TCP handshake] → [TLS ClientHello + SNI="api.bank.com"] → Server picks the right cert
```

**SNI (Server Name Indication)** is a TLS extension sent inside the `ClientHello` — in plaintext, before encryption is established — that tells the server which hostname the client intends to reach. The server uses it to select the correct certificate (and often the correct backend routing) before the handshake proceeds.

> [!warning] SNI Is Sent in Cleartext
> Because SNI is part of the unencrypted `ClientHello`, anyone sniffing the wire (or a firewall doing DPI) can see which hostname you're connecting to, even over HTTPS — this is why some enterprise firewalls block or allow traffic based on the SNI field. (Encrypted Client Hello, or ECH, is an emerging standard addressing this, but it's not yet ubiquitous in enterprise environments.)

### SNI in Your Stack, Concretely

| Component                                | SNI role                                                                                                                                                  |
| ---------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| OpenShift Route (re-encrypt/passthrough) | Uses SNI to route to the correct backend Service/Pod without terminating TLS itself, in passthrough mode                                                  |
| DataPower MPG (multi-protocol gateway)   | Front Side Handler can select cert profiles per SNI, serving multiple hostnames from one listener                                                         |
| ACE HTTP Listener                        | A single listener with one keystore alias serves one identity; multiple hostnames on one port typically require a front-end proxy doing SNI-based routing |
| `curl` / Java clients                    | Automatically send SNI matching the hostname in the URL — unless you're connecting by raw IP, which sends no SNI at all                                   |

### What Happens Without SNI (or a Mismatch)

If a client connects with no SNI (e.g. using a bare IP address instead of a hostname), the server has two choices: serve a configured **default certificate** for that listener, or refuse the connection. This is a very common "why does curl to the IP fail but curl to the hostname work" bug — the IP-based request never sent the SNI hostname the server was matching on.

### SAN vs SNI — Don't Confuse Them

|            | SAN                                                          | SNI                                                                               |
| ---------- | ------------------------------------------------------------ | --------------------------------------------------------------------------------- |
| Lives in   | The certificate itself                                       | The TLS `ClientHello`                                                             |
| Set by     | Whoever requested/issued the cert                            | The connecting client, at runtime                                                 |
| Purpose    | Lists which hostnames THIS cert is valid for                 | Tells the server WHICH hostname the client wants, so it knows which cert to serve |
| Checked by | The client, after receiving the cert (hostname verification) | The server, before sending any cert                                               |

They work together: SNI gets you routed to the right cert; SAN is then checked by the client to confirm that cert is actually valid for the hostname it asked for.

---

## 🛠️ Hands-on Lab (40 mins)

### Exercise 1 — Observe SNI in a Packet Capture

```bash
sudo tcpdump -i any -n 'tcp port 443 and host github.com' -w /tmp/sni.pcap &
curl -s https://github.com/ > /dev/null
kill %1

# Wireshark filter to find it
wireshark /tmp/sni.pcap
# Filter: tls.handshake.extensions_server_name
```

Click the ClientHello packet — under `Handshake Protocol → Extension: server_name`, you'll see `github.com` sitting in **cleartext**, before any encryption begins.

### Exercise 2 — Force SNI Mismatch and Watch It Fail

```bash
# Connect by IP with an explicit (wrong) SNI value using openssl s_client
IP=$(dig +short github.com | head -1)
openssl s_client -connect $IP:443 -servername wrong-host.example.com < /dev/null 2>&1 | grep -E "subject=|Verify return code"
```

The certificate returned won't match `wrong-host.example.com`, and the verify return code will show a hostname mismatch failure — this is precisely the "certificate does not match hostname" error you'll see against a real multi-tenant load balancer if the SNI value doesn't match any configured site.

### Exercise 3 — Compare Connecting With and Without SNI

```bash
# WITH proper SNI (via hostname)
curl -v https://github.com/ 2>&1 | grep -E "SSL connection|subject:"

# WITHOUT SNI (raw IP, no -servername/--resolve trick)
IP=$(dig +short github.com | head -1)
curl -v -k "https://$IP/" -H "Host: github.com" 2>&1 | grep -E "SSL connection|subject:"
```

Notice the second command's certificate `subject:` may differ or the connection may behave differently depending on what default cert the server presents for connections with no matching SNI — this is exactly the load-balancer misconfiguration pattern to watch for.

### Exercise 4 — Week 3 Capstone Scenario: Full Diagnosis Chain

Simulate the full week's worth of failure modes in sequence using your lab CA from Day 14:

```bash
cd ~/tls-lab/ca

# Scenario: serve the leaf WITHOUT the intermediate (broken chain, Day 14)
openssl s_server -accept 8443 -cert leaf.crt -key leaf.key -www &
SERVER_PID=$!

# Client attempt with only the root trusted — reproduces PKIX path error
openssl s_client -connect localhost:8443 -CAfile root-ca.crt < /dev/null 2>&1 | grep -E "Verify return code|verify error"

kill $SERVER_PID

# Fix: serve the FULL chain instead
openssl s_server -accept 8443 -cert leaf-fullchain.crt -key leaf.key -www &
SERVER_PID=$!

openssl s_client -connect localhost:8443 -CAfile root-ca.crt < /dev/null 2>&1 | grep -E "Verify return code"

kill $SERVER_PID
```

Confirm: broken chain shows a non-zero verify error code; full chain shows `Verify return code: 0 (ok)`.

---

## ✅ Validation (5 mins)

You've proven Week 3's material if you can:

1. Explain, using the packet capture, why SNI must be sent in cleartext and what that implies for firewall/DPI visibility.
2. Distinguish SAN (in the cert) from SNI (in the ClientHello) clearly enough to answer it as an interview question.
3. Diagnose a "connects fine by hostname, fails by IP" report as an SNI/default-certificate issue within the first two questions you ask.
4. Run the full Day 14→15 capstone above from memory: generate a chain, break it, observe the PKIX failure, fix it, confirm `Verify return code: 0 (ok)`.

> [!info] Week 3 Debugging Checklist
> When any TLS connection fails, check in this order: (1) protocol version match — Day 11; (2) is the chain complete server-side — Day 14; (3) is the root CA in the client's truststore — Day 14; (4) does the SNI sent match a SAN entry on the returned cert — Day 15; (5) are we within the validity window. This order resolves the overwhelming majority of real-world TLS tickets.

---

## Key Takeaways

- SNI lets one IP:port serve multiple hostnames' worth of certificates by having the client announce its target hostname inside the (cleartext) ClientHello.
- SNI is sent unencrypted — a real privacy/visibility consideration for anyone sniffing HTTPS traffic.
- SAN (in the cert) and SNI (in the ClientHello) are complementary but distinct: SNI picks the cert, SAN validates it was the right one.
- A "works by hostname, fails by IP" symptom almost always means SNI-based routing with no matching default certificate for bare-IP connections.
- Week 3's four days compose into a single debugging checklist: protocol → chain → trust → hostname match.

---

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-14-CA-Chains-and-Trust-Stores]] | **Next:** [[Day-16-One-Way-TLS-vs-mTLS]] →
