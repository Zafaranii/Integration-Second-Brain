---
tags: [security, bucket-2, mtls, debugging, day-20]
created: 2025-07-05
bucket: 2
week: 4
day: 20
status: not-started
prerequisites: ["Day-19-Kafka-mTLS-Basics"]
---

# Day 20 — mTLS Debugging (Week 4 Wrap-up)

> [!info] Why This Day Exists
> This is the day that pays for the rest of Week 4. Real mTLS incidents show up as one-line stack traces or a vague "handshake failed" from a partner team, and the difference between a 10-minute fix and a 3-hour escalation is knowing exactly which of a small number of causes produces which exact error string.

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-19-Kafka-mTLS-Basics]] | **Next:** [[Day-21-Hashing-vs-Encryption-vs-Signing]] →

---

## 🧠 Theory Block (15 mins)

### The mTLS Failure Taxonomy

mTLS failures always originate from one of two directions, and the error message usually — but not always — tells you which:

```
                    ┌─────────────────────────────┐
                    │   Which side is complaining?  │
                    └─────────────────────────────┘
                              │
          ┌───────────────────┴───────────────────┐
          ▼                                        ▼
  SERVER-SIDE rejection                    CLIENT-SIDE rejection
  (rejecting the CLIENT's cert)            (rejecting the SERVER's cert)
          │                                        │
  "bad certificate"                        "unable to get local issuer"
  "unknown_ca"                             "self signed certificate"
  "certificate_required"                   "certificate has expired"
  "handshake_failure" (after                "hostname mismatch"
   CertificateRequest)
```

### Error-to-Cause Quick Reference

| Error string                                                                | Which side sees it             | Root cause                                                                                  | Fix                                                            |
| --------------------------------------------------------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| `certificate_required` / `handshake_failure` right after CertificateRequest | Client (relayed)               | Client sent NO certificate at all                                                           | Confirm client keystore is actually configured/loaded          |
| `bad_certificate`                                                           | Server logs                    | Client cert is malformed, expired, or fails a server-side custom check                      | `openssl x509 -in client.crt -noout -dates`                    |
| `unknown_ca`                                                                | Server logs                    | Client cert's issuer isn't in the server's truststore                                       | Add the client's CA to the server truststore                   |
| `unable to get local issuer certificate`                                    | Client                         | Server didn't send full chain, OR client's truststore is missing an intermediate/root       | Server: send full chain. Client: check truststore completeness |
| `self signed certificate in certificate chain`                              | Client                         | Client's truststore doesn't include the (self-signed) root the server's chain terminates at | Import the correct root CA into client truststore              |
| PKIX path building failed: unable to find valid certification path          | Client (Java-specific wording) | Same as above — Java's verbose way of saying "chain incomplete"                             | Same as above                                                  |
| `NotYetValidCertificateException` / `CertificateExpiredException`           | Either                         | Clock skew, or a genuinely expired/not-yet-valid cert                                       | Check `notBefore`/`notAfter` AND system clock (NTP)            |

### The Systematic Debugging Order

When someone reports "mTLS is broken," resist the urge to guess. Work this order every time:

```
1. Is it TLS at all, or TCP? (Bucket 1 — can you even reach the port?)
2. Does the SAME check succeed as one-way TLS (no client cert presented)?
      → If yes: the SERVER's identity chain is fine; problem is client-side auth.
      → If no: fix the server's own cert/chain first (Week 3 skills) before touching mTLS.
3. Is the client actually SENDING a certificate? (openssl s_client -state shows this explicitly)
4. Is the client cert's issuing CA in the SERVER's truststore?
5. Is the client cert within its validity window? Check BOTH ends' system clocks.
6. Is the SERVER's cert's issuing CA in the CLIENT's truststore, with a complete chain?
7. Only after all of the above: consider application-level authorization (ACLs, RBAC) —
   by this point the identity handshake itself is proven working.
```

### A Note on Clock Skew

An underrated cause of intermittent mTLS failures in containerized/OpenShift environments: if a pod's system clock drifts (NTP misconfiguration, container restart without time sync), certificate validity window checks can fail unpredictably, especially right around a cert's `notBefore` time just after issuance. Always check `date` on both ends before assuming a chain/trust problem when a _newly issued_ certificate is intermittently rejected.

---

## 🛠️ Hands-on Lab (40 mins)

### Exercise 1 — Use `-state` and `-debug` to See Exactly What the Client Sent

```bash
cd ~/tls-lab/ca/mtls-app
python3 mtls_server.py &
SERVER_PID=$!
sleep 1

# -state shows each handshake state transition explicitly
openssl s_client -connect localhost:8443 -CAfile ../root-ca.crt -state < /dev/null 2>&1 | grep -E "SSL_connect|CERT"

kill $SERVER_PID
```

Look for `SSLv3/TLS write client certificate` — if this shows an **empty** certificate message, you've directly confirmed "client sent no cert" as the cause, rather than guessing.

### Exercise 2 — Diagnose an Expired Client Certificate

```bash
cd ~/tls-lab/ca

# Issue a client cert that's already expired (backdated, 1-day validity, already passed)
openssl genrsa -out expired-client.key 2048
openssl req -new -key expired-client.key -out expired-client.csr -subj "/CN=expired-client"
faketime '2020-01-01' openssl x509 -req -in expired-client.csr -CA intermediate.crt -CAkey intermediate.key \
  -CAcreateserial -out expired-client.crt -days 1 -sha256 2>/dev/null || \
  openssl x509 -req -in expired-client.csr -CA intermediate.crt -CAkey intermediate.key \
  -CAcreateserial -out expired-client.crt -days 1 -sha256

# Confirm expiry directly rather than guessing
openssl x509 -in expired-client.crt -noout -dates

cd mtls-app
python3 mtls_server.py &
SERVER_PID=$!
sleep 1
openssl s_client -connect localhost:8443 -CAfile ../root-ca.crt \
  -cert ../expired-client.crt -key ../expired-client.key < /dev/null 2>&1 | grep -E "Verify return code|expired"
kill $SERVER_PID
```

(If `faketime` isn't installed, the `-dates` check alone is sufficient to demonstrate reading validity windows — the key habit is checking dates first, not assuming.)

### Exercise 3 — Diagnose an Untrusted Client CA (Server-Side Rejection)

```bash
cd ~/tls-lab/ca/mtls-app
python3 mtls_server.py &
SERVER_PID=$!
sleep 1

# Use the rogue client cert from Day 17 — signed by a CA the server does NOT trust
openssl s_client -connect localhost:8443 -CAfile ../root-ca.crt \
  -cert ../rogue-client.crt -key ../rogue-client.key < /dev/null 2>&1 | grep -E "alert|Verify return code"

kill $SERVER_PID
```

### Exercise 4 — Build a One-Page Runbook From What You Just Reproduced

Fill this table in with your own reproduction results as an artifact for future incidents:

| Symptom you saw                         | Command that confirmed it                | Fix applied                              |
| --------------------------------------- | ---------------------------------------- | ---------------------------------------- |
| Empty client certificate message        | `openssl s_client -state`                | Load client keystore in app config       |
| `certificate has expired`               | `openssl x509 -noout -dates`             | Reissue cert / check system clock        |
| `unknown ca` / `tlsv1 alert unknown ca` | Compare cert issuer to server truststore | Import correct CA into server truststore |

---

## ✅ Validation (5 mins)

You've proven Week 4's material if you can:

1. Given only an error string (from the quick reference table), state which side is rejecting and the most likely root cause, without running any commands first.
2. Use `openssl s_client -state` to prove definitively whether a client sent a certificate at all, rather than inferring it from a vague error.
3. Walk the 7-step systematic debugging order from memory when handed a fresh "mTLS is broken" report.
4. Explain why clock skew is a plausible cause specifically for _intermittent_ failures on _newly issued_ certificates.

---

## Key Takeaways

- mTLS errors split cleanly into "server rejecting the client's cert" vs "client rejecting the server's cert" — the error wording usually indicates which, and confirming with `-state` removes any doubt.
- The systematic debugging order (TCP → one-way TLS baseline → client cert sent? → CA trusted? → validity window → reverse-direction chain) resolves nearly every real mTLS incident without guesswork.
- Clock skew is an underrated, container-environment-specific cause of intermittent certificate validity failures.
- A one-page symptom→command→fix runbook built from your own reproductions is worth more during an actual incident than re-deriving theory under pressure.

---

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-19-Kafka-mTLS-Basics]] | **Next:** [[Day-21-Hashing-vs-Encryption-vs-Signing]] →
