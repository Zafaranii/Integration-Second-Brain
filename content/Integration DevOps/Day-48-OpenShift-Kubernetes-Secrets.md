---
tags: [devops, bucket-4, openshift, kubernetes, secrets, day-48]
created: 2025-07-05
bucket: 4
week: 10
day: 48
status: not-started
---

# Day 48 — OpenShift/Kubernetes Deployments: Secrets

> [!info] Why This Day Exists
> Every credential Day 44's queue manager needed — `MQ_APP_PASSWORD`, `MQ_ADMIN_PASSWORD` — was passed as a plain environment variable in a `docker run` command. In a shared cluster with RBAC, audit logging, and multiple teams, that's not acceptable. Kubernetes Secrets exist to close this gap — imperfectly, as you'll see, which is exactly why understanding the caveats matters.

**← Index:** [[00 Integration DevOps Index]] | **Previous:** [[Day-47-OpenShift-Kubernetes-ConfigMaps]] | **Next:** [[Day-49-Pod-Debugging]] →

---

## Theory

### Secret Types You'll Actually Encounter

| Type                             | Purpose                                                   | Example use in this stack                                                   |
| -------------------------------- | --------------------------------------------------------- | --------------------------------------------------------------------------- |
| `Opaque`                         | Generic key-value secret (the default)                    | MQ admin/app passwords, ACE configurable service credentials                |
| `kubernetes.io/dockerconfigjson` | Registry credentials for pulling private container images | Pulling your custom ACE runtime image from a private registry               |
| `kubernetes.io/tls`              | TLS certificate + private key pair                        | HTTPS termination on a Route, or MQ channel TLS (`CipherSpec`) key material |
| `kubernetes.io/basic-auth`       | Username/password pair with fixed keys                    | Backend API basic-auth credentials referenced by an HTTP Request node       |

---

### The Critical Caveat: Base64 Is Not Encryption

```bash
echo -n 'passw0rd' | base64
# cGFzc3dvcmQ=
echo -n 'cGFzc3dvcmQ=' | base64 -d
# passw0rd
```

A Secret's `data` field is **base64-encoded, not encrypted**. Anyone with `get`/`describe` RBAC permission on Secrets in that namespace, or access to `etcd` backups, can trivially recover the plaintext. Kubernetes Secrets protect you from _accidental_ exposure (they're not shown in plain-text in `oc get pods -o yaml` env dumps by default the way literal values would be) and give you a place to apply **RBAC scoping** and **encryption-at-rest** (a cluster-level etcd configuration) — they are not, by themselves, a secrets-management solution.

> [!warning] Never Commit Rendered Secret Manifests to Git
> This is the direct tension with Day 46's GitOps principle "Git is the single source of truth." A raw `Secret` YAML with base64 data committed to Git is only as safe as your Git repository's access control — which is usually far broader than your production namespace's RBAC. Real GitOps shops solve this with **Sealed Secrets** (encrypts the secret so only the target cluster's controller can decrypt it) or **External Secrets Operator** (pulls secrets at runtime from Vault/AWS Secrets Manager/etc., keeping only a _reference_ in Git, never the value). This lab uses plain Secrets for learning mechanics — treat that choice as a simplification, not a production pattern.

---

### Creating Secrets

```bash
# Imperative, literal (fine for local testing, never for GitOps repos)
oc create secret generic mq-credentials \
  --from-literal=MQ_APP_PASSWORD=passw0rd \
  --from-literal=MQ_ADMIN_PASSWORD=passw0rd \
  -n integration-dev

# From a YAML manifest (still base64-encoded, still shouldn't go to Git in plaintext form)
cat > mq-secret.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: mq-credentials
  namespace: integration-dev
type: Opaque
data:
  MQ_APP_PASSWORD: cGFzc3dvcmQ=
  MQ_ADMIN_PASSWORD: cGFzc3dvcmQ=
EOF
oc apply -f mq-secret.yaml
```

---

### Consuming Secrets in a Pod

**As environment variables (most common for MQ container env vars):**

```yaml
env:
  - name: MQ_APP_PASSWORD
    valueFrom:
      secretKeyRef:
        name: mq-credentials
        key: MQ_APP_PASSWORD
```

**As a mounted volume (better for TLS certs/keys — avoids secrets showing up in `env` dumps or process listings):**

```yaml
volumes:
  - name: tls-secret-volume
    secret:
      secretName: mq-tls-cert
containers:
  - name: qm1
    volumeMounts:
      - name: tls-secret-volume
        mountPath: /etc/mqm/tls
        readOnly: true
```

> [!tip] Env Vars vs Volumes for Secrets
> Environment variables are visible to anything that can read `/proc/<pid>/environ` inside the container, and can leak into crash dumps or verbose logging accidentally. Volume-mounted secrets (read as files) avoid that specific leak vector. For anything beyond a simple password — TLS material, keystores — prefer the volume mount.

---

## Hands-on Lab

### Exercise 1 — Create the MQ Credentials Secret

```bash
oc create secret generic mq-credentials \
  --from-literal=MQ_APP_PASSWORD=passw0rd \
  --from-literal=MQ_ADMIN_PASSWORD=passw0rd \
  -n integration-dev

oc get secret mq-credentials -n integration-dev -o yaml
```

Confirm the `data` values are base64 strings, not plaintext — then decode one yourself to prove the point:

```bash
oc get secret mq-credentials -n integration-dev -o jsonpath='{.data.MQ_APP_PASSWORD}' | base64 -d
echo
```

### Exercise 2 — Reference the Secret From the Day 47 Deployment

```bash
cat >> mq-deployment.yaml << 'EOF'
        # (append inside the existing container's env list from Day 47)
EOF
```

Edit `mq-deployment.yaml`'s container `env:` block to add:

```yaml
env:
  - { name: LICENSE, value: "accept" }
  - { name: MQ_QMGR_NAME, value: "QM1" }
  - name: MQ_APP_PASSWORD
    valueFrom:
      secretKeyRef: { name: mq-credentials, key: MQ_APP_PASSWORD }
  - name: MQ_ADMIN_PASSWORD
    valueFrom:
      secretKeyRef: { name: mq-credentials, key: MQ_ADMIN_PASSWORD }
```

```bash
oc apply -f mq-deployment.yaml
oc rollout status deployment/qm1 -n integration-dev
```

### Exercise 3 — Confirm the Secret Value Never Appears in Plaintext Where It Shouldn't

```bash
POD=$(oc get pods -n integration-dev -l app=qm1 -o jsonpath='{.items[0].metadata.name}')

# The pod spec references the secret by name/key only — no plaintext value here
oc get pod "$POD" -n integration-dev -o yaml | grep -A2 MQ_APP_PASSWORD

# But inside the running container, the env var IS resolved to plaintext
# (this is expected — the app needs the real value to authenticate)
oc exec -it "$POD" -n integration-dev -- printenv MQ_APP_PASSWORD
```

This exercise is deliberately here to make the boundary concrete: the **manifest** never shows the plaintext password; the **running process** necessarily does. Anyone who can `oc exec` into that pod, or who can `oc get secret -o yaml`, can see it.

### Exercise 4 — RBAC Scoping Check (Read-Only Exploration)

```bash
# Check who/what can read secrets in this namespace
oc adm policy who-can get secrets -n integration-dev
```

Review that list. If it includes broader groups than expected (e.g., all developers rather than just the deployment service account), that's a real finding worth raising with your platform/security team — this is exactly the kind of gap Sealed Secrets or an External Secrets Operator is designed to close.

---

## Validation

- [ ] `oc get secret mq-credentials -o yaml` shows base64-encoded (not plaintext) values.
- [ ] You can decode a secret value with `base64 -d` and explain out loud why that proves base64 is encoding, not encryption.
- [ ] The MQ pod's `env` resolves `MQ_APP_PASSWORD` correctly (queue manager starts and accepts app connections), while the Deployment YAML itself contains no plaintext password.
- [ ] `oc adm policy who-can get secrets -n integration-dev` output has been reviewed and matches your expectation of least privilege.

---

## Key Takeaways

- Kubernetes Secrets are base64-encoded, **not encrypted** — treat them as "obscured with RBAC scoping," not "cryptographically protected," unless etcd encryption-at-rest is separately configured.
- Never commit rendered Secret manifests with real values to a GitOps repository — use Sealed Secrets or an External Secrets Operator so Git holds only references.
- Prefer volume-mounted secrets over environment variables for anything beyond a simple password, especially TLS material.
- The pod manifest hiding a value and the running process resolving that value are two different security boundaries — know which one you're relying on at each point.

---

**← Index:** [[00 Integration DevOps Index]] | **Previous:** [[Day-47-OpenShift-Kubernetes-ConfigMaps]] | **Next:** [[Day-49-Pod-Debugging]] →
