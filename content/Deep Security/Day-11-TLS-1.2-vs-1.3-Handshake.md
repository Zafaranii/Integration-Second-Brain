---
tags: [security, bucket-2, tls, handshake, day-11]
created: 2025-07-05
bucket: 2
week: 3
day: 11
status: not-started
prerequisites: ["Day-01-TCP-Handshake-and-Sockets"]
---

# Day 11 — TLS 1.2 vs 1.3: Handshake Deep Dive

> [!info] Why This Day Exists
> Every `BIP3xxxS` keystore error, every DataPower SSL proxy failure, every "handshake_failure" you'll ever see in ACE or API Connect logs happens during the sequence covered today. You can't read a TLS packet capture, tune a cipher suite list, or explain a downgrade attack to a security team without knowing exactly what happens between the TCP 3-way handshake finishing and the first byte of HTTP data flowing.

**← Index:** [[00 Deep Security Index]] | **Next:** [[Day-12-Private-Keys-and-CSRs-OpenSSL]] →

---

## 🧠 Theory Block (15 mins)

### TLS Sits Above TCP, Below the Application

```
┌─────────────────────────┐
│   HTTP / Kafka / JDBC    │  ← Application protocol
├─────────────────────────┤
│           TLS            │  ← Today's topic — encryption, auth
├─────────────────────────┤
│           TCP             │  ← Bucket 1 — reliable byte stream
├─────────────────────────┤
│            IP             │
└─────────────────────────┘
```

TLS negotiation happens **after** the TCP 3-way handshake completes and **before** any application bytes are sent. If TCP fails, you never see a TLS error — you see a TCP one (Day 1–3).

### TLS 1.2 Full Handshake (2 Round Trips)

```
Client                                          Server
  |------ ClientHello ------------------------->|  (supported versions, cipher suites, random_C)
  |<----- ServerHello ---------------------------|  (chosen version, chosen cipher, random_S)
  |<----- Certificate ---------------------------|  (server's cert chain)
  |<----- ServerKeyExchange ----------------------|  (if using (EC)DHE — ephemeral key params + signature)
  |<----- ServerHelloDone ------------------------|
  |------ ClientKeyExchange -------------------->|  (pre-master secret, encrypted with server pubkey OR DH params)
  |------ ChangeCipherSpec ---------------------->|  "everything from here is encrypted"
  |------ Finished ------------------------------>|  (encrypted — MAC of entire handshake)
  |<----- ChangeCipherSpec -----------------------|
  |<----- Finished --------------------------------|
  |<=========== application data ================>|
```

**Two full round trips** before any application data moves. `ClientKeyExchange` can use two different mechanisms:

- **Static RSA** — client generates the pre-master secret and encrypts it with the server's RSA public key. **No forward secrecy**: if the server's private key is ever compromised, every past session recorded off the wire can be decrypted.
- **(EC)DHE** — Diffie-Hellman with ephemeral keys. Each session gets a unique key; compromising the long-term private key does not expose past traffic. This is **forward secrecy**.

### TLS 1.3 Handshake (1 Round Trip)

```
Client                                          Server
  |------ ClientHello ------------------------->|  (+ key_share: client's DH public value, guessed early)
  |<----- ServerHello ------------------------------|  (+ key_share: server's DH public value)
  |<----- {EncryptedExtensions} ---------------------|  (encrypted from here on)
  |<----- {Certificate} ------------------------------|
  |<----- {CertificateVerify} -------------------------|  (signature over the handshake transcript)
  |<----- {Finished} ------------------------------------|
  |------ {Finished} --------------------------------->|
  |<=========== application data (1-RTT) ===============>|
```

TLS 1.3 **removes the negotiation** — the client guesses the key exchange group in `key_share` and sends its ephemeral public value in the _first_ message. If the server supports that group, the handshake completes in **one round trip**. Everything after `ServerHello` is encrypted immediately (`{}` denotes encrypted-but-not-yet-authenticated).

### What TLS 1.3 Removed Outright

| Removed in 1.3                                                         | Why                                                            |
| ---------------------------------------------------------------------- | -------------------------------------------------------------- |
| Static RSA key exchange                                                | No forward secrecy — banned entirely                           |
| Renegotiation                                                          | Source of multiple CVEs (triggering mid-session cert changes)  |
| Compression                                                            | CRIME/BREACH-class attacks exploited compressed+encrypted data |
| RC4, DES, 3DES, MD5, SHA-1 in cipher suites                            | Cryptographically broken or weak                               |
| CBC-mode ciphers vulnerable to padding oracles (Lucky13, POODLE-class) | Replaced with AEAD-only ciphers                                |

TLS 1.3 cipher suites are also **renamed and simplified** — they only specify the AEAD cipher + hash (e.g. `TLS_AES_128_GCM_SHA256`), because the key exchange algorithm is now negotiated separately via `key_share` groups, not baked into the suite name like TLS 1.2's `TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256`.

### 0-RTT Resumption (TLS 1.3 only) — Know the Risk

TLS 1.3 supports **0-RTT**: on a second connection to a server you've talked to before, the client can send application data (e.g. an HTTP request) in the _very first_ flight, using a resumption secret from a prior session. This is fast — but that early data has **no replay protection**. An attacker who captures a 0-RTT ClientHello + early data can replay it. Never enable 0-RTT for non-idempotent operations (POST that debits an account, for instance). Most enterprise middleware (ACE, DataPower) either disables 0-RTT by default or requires explicit opt-in for exactly this reason.

### Version Negotiation & Downgrade Protection

The `ClientHello` in TLS 1.3 sets `legacy_version = TLS 1.2` in the outer field for backward compatibility with old middleboxes, and puts the _real_ supported versions in a `supported_versions` extension. TLS 1.3 servers embed a special value in `ServerHello.random` if they detect a downgrade attempt, which TLS 1.3-aware clients check for and abort on — this closes the class of attack where a man-in-the-middle strips the extension to force a weaker protocol.

---

## 🛠️ Hands-on Lab (40 mins)

### Exercise 1 — Force Each Protocol Version and Compare

```bash
# Force TLS 1.2 and dump the full handshake
openssl s_client -connect www.google.com:443 -tls1_2 -msg -state < /dev/null 2>&1 | tee /tmp/tls12.log | grep -E "Protocol|Cipher|SSL_connect"

# Force TLS 1.3 and dump the full handshake
openssl s_client -connect www.google.com:443 -tls1_3 -msg -state < /dev/null 2>&1 | tee /tmp/tls13.log | grep -E "Protocol|Cipher|SSL_connect"
```

Compare the two log files:

```bash
grep -c "TLS 1.2 Handshake" /tmp/tls12.log
grep -c "TLS 1.3 Handshake" /tmp/tls13.log

# Count distinct message flights before "Application Data" appears in each
grep -B0 "Application Data" -m1 -n /tmp/tls12.log
grep -B0 "Application Data" -m1 -n /tmp/tls13.log
```

You should see meaningfully more handshake message lines logged before the first `Application Data` marker in the TLS 1.2 capture than in the 1.3 one.

### Exercise 2 — Capture and Time the Round Trips

```bash
# Packet capture while forcing each version
sudo tcpdump -i any -n 'host www.google.com and tcp port 443' -w /tmp/tls_compare.pcap &
TCPDUMP_PID=$!

openssl s_client -connect www.google.com:443 -tls1_2 < /dev/null > /dev/null 2>&1
sleep 1
openssl s_client -connect www.google.com:443 -tls1_3 < /dev/null > /dev/null 2>&1

kill $TCPDUMP_PID
wireshark /tmp/tls_compare.pcap
```

In Wireshark, filter `tls.handshake` and use **Statistics → Flow Graph** on each TCP stream. Count the client→server and server→client legs before `Application Data` — 1.2 shows two round trips of handshake traffic, 1.3 shows one.

### Exercise 3 — Inspect Negotiated Cipher Suites

```bash
# List every cipher suite OpenSSL is willing to offer for TLS 1.2
openssl ciphers -v 'TLSv1.2'

# List TLS 1.3 suites (fixed, small set)
openssl ciphers -v 'TLSv1.3'

# Ask a specific server which suite it actually picked
openssl s_client -connect www.google.com:443 -tls1_2 < /dev/null 2>&1 | grep "Cipher    :"
openssl s_client -connect www.google.com:443 -tls1_3 < /dev/null 2>&1 | grep "Cipher    :"
```

Notice the TLS 1.3 cipher name has no key-exchange algorithm embedded (`TLS_AES_256_GCM_SHA384`) versus the TLS 1.2 name that does (`ECDHE-RSA-AES256-GCM-SHA384`).

### Exercise 4 — Simulate a Downgrade Refusal

```bash
# Try to connect to a TLS-1.3-only test endpoint using only SSLv3/TLS1.0 — should fail cleanly
openssl s_client -connect www.google.com:443 -ssl3 < /dev/null 2>&1 | grep -E "error|failure"
```

Expect `no protocols available` or a handshake failure — this is the server correctly refusing an insecure downgrade, exactly what you want to see in a security review, not something to "fix."

---

## ✅ Validation (5 mins)

You've proven this day's material if you can:

1. Show the negotiated protocol on a live connection: `openssl s_client -connect <host>:443 < /dev/null 2>&1 | grep "Protocol"` prints `TLSv1.3` (or 1.2 when forced).
2. Point to the packet capture and correctly identify where TLS 1.2 spends **two round trips** versus TLS 1.3's **one**.
3. Explain, without notes, why static RSA key exchange breaks forward secrecy and why TLS 1.3 removed it entirely.
4. State the specific risk of 0-RTT and identify one operation in your own stack (e.g. an ACE flow triggering a debit) that must never be allowed over 0-RTT.

> [!warning] Common Misreading
> "TLS 1.3 is faster" is true but the _reason_ matters in interviews and design reviews: it's not a faster algorithm, it's **fewer round trips** because negotiation was eliminated in favor of the client guessing correctly up front. Don't reduce this to "1.3 good, 1.2 bad" without being able to explain the round-trip mechanics.

---

## Key Takeaways

- TLS negotiation happens after TCP's 3-way handshake and before any application bytes — a TLS error always implies TCP already succeeded.
- TLS 1.2 needs 2 round trips before data flows; TLS 1.3 needs 1, because the client speculatively sends its key share in the first flight.
- Forward secrecy (via (EC)DHE) means compromising a long-term private key later doesn't expose previously captured traffic — TLS 1.3 makes this mandatory by removing static RSA key exchange.
- TLS 1.3 cipher suite names only describe the AEAD cipher, not the key exchange — that's negotiated separately via `key_share` groups.
- 0-RTT trades a round trip for replay risk — never use it for non-idempotent operations.

---

**← Index:** [[00 Deep Security Index]] | **Next:** [[Day-12-Private-Keys-and-CSRs-OpenSSL]] →
