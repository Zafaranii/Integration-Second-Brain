---
tags: [security, bucket-2, mtls, kafka, day-19]
created: 2025-07-05
bucket: 2
week: 4
day: 19
status: not-started
prerequisites: ["Day-18-Client-Keystores-and-Truststores"]
---

# Day 19 — Kafka mTLS Basics

> [!info] Why This Day Exists
> Every Kafka-based streaming pipeline you touch — including your Flink event-streams work — eventually needs to run somewhere more locked-down than a dev sandbox with `PLAINTEXT` listeners. `SSL` and `SASL_SSL` listener configuration is where TLS/mTLS theory becomes a very specific set of broker and client properties that either work or throw a wall of Java `SSLHandshakeException` stack traces. This day maps the concepts directly onto Kafka's config surface.

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-18-Client-Keystores-and-Truststores]] | **Next:** [[Day-20-mTLS-Debugging]] →

---

## 🧠 Theory Block (15 mins)

### Kafka's Security Protocols

| `security.protocol` | Encryption | Client Authentication                                                                |
| ------------------- | ---------- | ------------------------------------------------------------------------------------ |
| `PLAINTEXT`         | None       | None — dev/test only                                                                 |
| `SSL`               | Yes (TLS)  | Optional — only if broker sets `ssl.client.auth=required` (**this is Kafka's mTLS**) |
| `SASL_PLAINTEXT`    | None       | Yes, via SASL (username/password or Kerberos) — auth without encryption              |
| `SASL_SSL`          | Yes (TLS)  | Yes, via SASL layered on top of TLS                                                  |

There's a subtlety worth internalizing: Kafka calls its mTLS mode simply `SSL` with `ssl.client.auth=required` — there is no separate `"MTLS"` protocol name. If a broker's `server.properties` shows `security.protocol=SSL` but doesn't also set `ssl.client.auth`, client certificate authentication is likely **not** being enforced, even though the channel is encrypted — this is the Kafka-specific version of the `CERT_OPTIONAL` trap from Day 17.

### The Four Broker-Side Properties That Define mTLS Enforcement

```properties
listeners=SSL://0.0.0.0:9093
ssl.keystore.location=/etc/kafka/secrets/broker.keystore.p12
ssl.keystore.password=changeit
ssl.keystore.type=PKCS12
ssl.truststore.location=/etc/kafka/secrets/broker.truststore.p12
ssl.truststore.password=changeit
ssl.client.auth=required          # ← the switch: none | requested | required
```

`ssl.client.auth`:

- `none` → one-way TLS only (broker proves identity; any client, cert or not, may connect)
- `requested` → the Kafka-equivalent of `CERT_OPTIONAL` (Day 17) — broker asks, but proceeds without one
- `required` → true mTLS — no valid client cert, no connection, ever

### The Matching Client-Side Properties

```properties
security.protocol=SSL
ssl.keystore.location=/etc/kafka/client-secrets/client.keystore.p12
ssl.keystore.password=changeit
ssl.keystore.type=PKCS12
ssl.truststore.location=/etc/kafka/client-secrets/client.truststore.p12
ssl.truststore.password=changeit
```

This is a mirror image of the broker's config, and the same keystore/truststore mental model from Days 16–18 applies exactly: the client's keystore is its identity (checked by the broker against the broker's truststore); the client's truststore is what lets it trust the broker's cert (checked against the CA that signed the broker's cert).

### Where mTLS Fits Relative to ACLs

mTLS answers "who is this client, cryptographically." It does **not** by itself answer "what is this client allowed to do." In a properly hardened Kafka cluster, the client's certificate CN (or a SASL principal) is mapped to a Kafka **principal**, and then Kafka ACLs (`kafka-acls.sh`) decide which topics that principal can produce to or consume from. mTLS without ACLs authenticates everyone but authorizes nothing — a common half-finished hardening effort.

---

## 🛠️ Hands-on Lab (40 mins)

### Exercise 1 — Build Broker and Client Keystores/Truststores from Your Lab PKI

```bash
cd ~/tls-lab/ca

# Broker identity (reuse the leaf cert/key as the "broker")
openssl pkcs12 -export -in leaf-fullchain.crt -inkey leaf.key \
  -name broker -out broker.keystore.p12 -passout pass:changeit

# Broker's truststore — trusts the root CA (so it can validate CLIENT certs signed by it)
keytool -importcert -alias lab-root-ca -file root-ca.crt \
  -keystore broker.truststore.p12 -storetype PKCS12 -storepass changeit -noprompt

# Client identity
openssl pkcs12 -export -in client.crt -inkey client.key \
  -name integration-client-01 -out client.keystore.p12 -passout pass:changeit

# Client's truststore — trusts the root CA (so it can validate the BROKER's cert)
keytool -importcert -alias lab-root-ca -file root-ca.crt \
  -keystore client.truststore.p12 -storetype PKCS12 -storepass changeit -noprompt
```

### Exercise 2 — Configure a Local Kafka Broker for SSL with Client Auth Required

_(Assumes a local Kafka install; adjust paths to your environment.)_

```properties
# server.properties additions
listeners=SSL://0.0.0.0:9093
advertised.listeners=SSL://localhost:9093
ssl.keystore.location=/home/claude/tls-lab/ca/broker.keystore.p12
ssl.keystore.password=changeit
ssl.keystore.type=PKCS12
ssl.truststore.location=/home/claude/tls-lab/ca/broker.truststore.p12
ssl.truststore.password=changeit
ssl.truststore.type=PKCS12
ssl.client.auth=required
```

```bash
# Restart the broker after applying config, then confirm the listener is up
ss -tlnp | grep 9093
```

### Exercise 3 — Configure and Test a Console Producer with mTLS

```bash
cat > client-ssl.properties << 'EOF'
security.protocol=SSL
ssl.keystore.location=/home/claude/tls-lab/ca/client.keystore.p12
ssl.keystore.password=changeit
ssl.keystore.type=PKCS12
ssl.truststore.location=/home/claude/tls-lab/ca/client.truststore.p12
ssl.truststore.password=changeit
ssl.truststore.type=PKCS12
EOF

kafka-console-producer.sh --broker-list localhost:9093 \
  --topic mtls-test-topic \
  --producer.config client-ssl.properties
```

Type a test message and confirm it sends without error. Then consume it back:

```bash
kafka-console-consumer.sh --bootstrap-server localhost:9093 \
  --topic mtls-test-topic --from-beginning \
  --consumer.config client-ssl.properties
```

### Exercise 4 — Prove Enforcement by Removing the Client Keystore Config

```bash
cat > no-client-cert.properties << 'EOF'
security.protocol=SSL
ssl.truststore.location=/home/claude/tls-lab/ca/client.truststore.p12
ssl.truststore.password=changeit
ssl.truststore.type=PKCS12
EOF

kafka-console-producer.sh --broker-list localhost:9093 \
  --topic mtls-test-topic \
  --producer.config no-client-cert.properties
```

With `ssl.client.auth=required` on the broker, this should fail with an `SSLHandshakeException` — no client keystore means no client certificate to present, and the broker refuses the connection outright.

---

## ✅ Validation (5 mins)

You've proven this day's material if you can:

1. Explain why Kafka has no separate "mTLS protocol" — it's `SSL` plus `ssl.client.auth=required`.
2. Correctly map broker-side and client-side keystore/truststore properties to the same identity/trust model used in Days 16–18.
3. Reproduce a client connection failure by omitting the client keystore against a broker configured with `ssl.client.auth=required`.
4. State clearly that mTLS authenticates identity but does not by itself authorize topic access — that's the separate job of Kafka ACLs.

---

## Key Takeaways

- Kafka's mTLS is `security.protocol=SSL` + `ssl.client.auth=required` — there's no distinct protocol name for it.
- `ssl.client.auth=requested` is Kafka's version of the `CERT_OPTIONAL` trap: encrypted, but not actually enforcing client identity.
- Broker and client each need a matching keystore (own identity) and truststore (who they trust), exactly mirroring the generic mTLS model from Week 4 so far.
- Authentication (mTLS) and authorization (ACLs) are separate concerns — hardening one without the other is a half-finished security posture.

---

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-18-Client-Keystores-and-Truststores]] | **Next:** [[Day-20-mTLS-Debugging]] →
