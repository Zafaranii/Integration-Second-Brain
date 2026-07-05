---
tags: [security, bucket-2, cryptography, jwt, jws, day-23]
created: 2025-07-05
bucket: 2
week: 5
day: 23
status: not-started
prerequisites: ["Day-22-Generating-Digital-Signatures"]
---

# Day 23 — JWT / JWS Basics

> [!info] Why This Day Exists
> Every OAuth2/OIDC flow you've touched in the API Connect/Keycloak world — access tokens, ID tokens — is very likely a JWT under the hood. Days 21 and 22 gave you the raw primitives; today shows exactly how a JWT assembles them into the token format you see arriving in an `Authorization: Bearer` header, and — critically — what a JWT does and does not protect against.

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-22-Generating-Digital-Signatures]] | **Next:** [[Day-24-Base64-vs-Encryption]] →

---

## 🧠 Theory Block (15 mins)

### JWT Structure — Three Base64URL Segments

```
eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVP-mB92K27...
└────────── HEADER ──────────┘.└──────────── PAYLOAD ────────────┘.└────── SIGNATURE ──────┘
```

| Segment   | Encoding         | Contents                                                                                               |
| --------- | ---------------- | ------------------------------------------------------------------------------------------------------ |
| Header    | Base64URL(JSON)  | `{"alg": "RS256", "typ": "JWT"}` — signing algorithm + token type                                      |
| Payload   | Base64URL(JSON)  | Claims — `sub`, `iss`, `exp`, `iat`, and any custom claims                                             |
| Signature | Base64URL(bytes) | Signature over `Base64URL(header) + "." + Base64URL(payload)`, using the algorithm named in the header |

### JWS vs JWT — The Relationship

**JWS (JSON Web Signature)** is the general signing mechanism/spec. **JWT (JSON Web Token)** is a specific, standardized _use_ of either JWS (signed) or JWE (encrypted) to carry a set of claims. In practice, "JWT" almost always means a JWS-signed token — the vast majority of access tokens and ID tokens you'll encounter are signed, not encrypted, meaning **anyone can read the payload** without any key at all.

> [!warning] A JWT Is Tamper-Evident, Not Confidential
> This is the single most common JWT misunderstanding. Base64URL is an _encoding_, not encryption — decoding the payload requires zero secrets (Day 24 makes this explicit). Never put a password, an SSN, or any genuinely secret data inside a JWT payload just because it's "signed." Signing guarantees the payload wasn't altered after issuance; it says nothing about who can read it.

### Standard Claims Worth Knowing

| Claim | Meaning                                                                                              |
| ----- | ---------------------------------------------------------------------------------------------------- |
| `iss` | Issuer — who created and signed this token                                                           |
| `sub` | Subject — who/what the token is about (usually a user or client ID)                                  |
| `aud` | Audience — who the token is intended for; a resource server should reject tokens not addressed to it |
| `exp` | Expiration time (Unix timestamp) — tokens presented after this MUST be rejected                      |
| `iat` | Issued-at time                                                                                       |
| `nbf` | Not-before — token isn't valid until this time                                                       |

### The `alg: none` Attack — A Real Historical Vulnerability

The JWS spec technically allows `"alg": "none"` — an unsigned token. Several early JWT libraries, if not configured carefully, would accept a token with header `{"alg":"none"}` and an **empty** signature segment as valid, because the verification code path for "none" trivially always "succeeds." An attacker could take any legitimate token, change the payload claims (e.g. `"role": "user"` → `"role": "admin"`), set `alg` to `none`, strip the signature, and some vulnerable verifiers would accept it outright.

**Mitigation:** always verify against an explicit, expected algorithm allow-list server-side (e.g. "I will only ever accept RS256") rather than trusting whatever `alg` value the incoming token itself claims.

### RS256 vs HS256 — A Critical Architectural Distinction

|                                  | HS256 (HMAC-SHA256)                            | RS256 (RSA-SHA256)                                                                                       |
| -------------------------------- | ---------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| Key type                         | Symmetric — ONE shared secret                  | Asymmetric — private key signs, public key verifies                                                      |
| Who can verify                   | Only holders of the shared secret              | Anyone with the public key                                                                               |
| Who can also forge a valid token | **Anyone who can verify** (same key does both) | Only the private key holder                                                                              |
| Typical use                      | Single-service, internal-only tokens           | Multi-service ecosystems (OAuth/OIDC — any resource server can verify without being able to mint tokens) |

This is a genuine security design decision, not a style preference: if a JWT is verified by multiple independent services (as in a typical OAuth/OIDC deployment with Keycloak or API Connect), **HS256 would mean every verifying service also holds the power to mint valid tokens** — a serious blast-radius problem if any one service is compromised. RS256 (or ES256) cleanly separates "can verify" from "can mint."

---

## 🛠️ Hands-on Lab (40 mins)

### Exercise 1 — Manually Decode a JWT's Header and Payload

```bash
cd ~/tls-lab

JWT="eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cHM6Ly9hdXRoLmxhYi5pbnRlcm5hbCIsImV4cCI6MTgwMDAwMDAwMH0.placeholder_signature"

echo "$JWT" | cut -d'.' -f1 | tr '_-' '/+' | base64 -d 2>/dev/null; echo
echo "$JWT" | cut -d'.' -f2 | tr '_-' '/+' | base64 -d 2>/dev/null; echo
```

Note: you just read the full claims of a signed token **without any key, secret, or verification step whatsoever** — this is the hands-on proof of "signed, not encrypted."

### Exercise 2 — Manually Construct a Valid RS256 JWT

```bash
HEADER='{"alg":"RS256","typ":"JWT"}'
PAYLOAD='{"sub":"integration-client-01","iss":"lab-auth","exp":9999999999}'

b64url() { base64 | tr '+/' '-_' | tr -d '='; }

HEADER_B64=$(echo -n "$HEADER" | b64url)
PAYLOAD_B64=$(echo -n "$PAYLOAD" | b64url)
SIGNING_INPUT="${HEADER_B64}.${PAYLOAD_B64}"

# Sign with RSA private key (from Day 12), producing the signature segment
SIGNATURE_B64=$(echo -n "$SIGNING_INPUT" | openssl dgst -sha256 -sign server.key -binary | b64url)

JWT="${SIGNING_INPUT}.${SIGNATURE_B64}"
echo "$JWT"
```

### Exercise 3 — Verify the JWT You Just Built

```bash
IFS='.' read -r H P S <<< "$JWT"

# Recompute the signature over the same signing input, compare against the token's signature
echo -n "${H}.${P}" | openssl dgst -sha256 -sign server.key -binary | b64url

echo "Token's actual signature segment:"
echo "$S"
```

If both values match exactly, you've manually reproduced what every JWT library does internally during verification — recompute, compare, accept or reject.

### Exercise 4 — Reproduce the `alg: none` Vulnerability Concept

```bash
# Take the legitimate payload, escalate a claim, forge an "alg: none" token
FORGED_HEADER=$(echo -n '{"alg":"none","typ":"JWT"}' | b64url)
FORGED_PAYLOAD=$(echo -n '{"sub":"integration-client-01","iss":"lab-auth","exp":9999999999,"role":"admin"}' | b64url)
FORGED_JWT="${FORGED_HEADER}.${FORGED_PAYLOAD}."

echo "Forged token (empty signature, alg=none):"
echo "$FORGED_JWT"
```

This token has a syntactically valid JWT shape but zero cryptographic backing. A correctly written verifier must explicitly reject `alg: none` and any algorithm outside its expected allow-list — this is exactly the check to look for (or add) when reviewing JWT verification code.

### Exercise 5 — Confirm Tampering Breaks Verification

```bash
# Take the LEGITIMATE signed JWT from Exercise 2, tamper with the payload, keep the OLD signature
TAMPERED_PAYLOAD=$(echo -n '{"sub":"integration-client-01","iss":"lab-auth","exp":9999999999,"role":"admin"}' | b64url)
TAMPERED_JWT="${HEADER_B64}.${TAMPERED_PAYLOAD}.${SIGNATURE_B64}"

# Recompute what the signature SHOULD be for the tampered payload
echo -n "${HEADER_B64}.${TAMPERED_PAYLOAD}" | openssl dgst -sha256 -sign server.key -binary | b64url
echo "vs the OLD (now stale) signature still attached:"
echo "$SIGNATURE_B64"
```

The recomputed signature differs from the stale one still attached to the tampered token — any real verifier comparing these would reject it, exactly as intended.

---

## ✅ Validation (5 mins)

You've proven this day's material if you can:

1. Decode a JWT's header and payload with nothing but `base64 -d` and explain why this is possible without any key.
2. Manually construct and verify a valid RS256 JWT by hand, matching the recomputed signature to the token's actual signature segment.
3. Explain the `alg: none` vulnerability and state the correct mitigation (explicit algorithm allow-listing at the verifier).
4. Explain, in terms of blast radius, why RS256 is preferred over HS256 in any ecosystem with multiple independent token-verifying services.

---

## Key Takeaways

- A JWT is three Base64URL segments — header, payload, signature — and is tamper-evident, not confidential; anyone can read the payload without any secret.
- `alg: none` is a real historical vulnerability class; verifiers must enforce an explicit expected-algorithm allow-list rather than trusting the token's own `alg` header.
- HS256 uses one shared secret for both signing and verifying, meaning every verifier can also mint tokens — a real blast-radius concern in multi-service ecosystems, which is why RS256/ES256 (asymmetric) is preferred for OAuth/OIDC-style deployments.
- Verification is just "recompute the expected signature over header+payload, compare to what arrived" — the exact mechanic you reproduced by hand in this lab.

---

**← Index:** [[00 Deep Security Index]] | **Prev:** [[Day-22-Generating-Digital-Signatures]] | **Next:** [[Day-24-Base64-vs-Encryption]] →
