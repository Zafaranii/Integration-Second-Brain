---
tags: [devops, bucket-4, gitops, argocd, day-46]
created: 2025-07-05
bucket: 4
week: 10
day: 46
status: not-started
---

# Day 46 — GitOps Concepts

> [!info] Why This Day Exists
> Days 41–45 built the habit of "config lives in files, not in someone's fingers." GitOps takes that one step further: it makes Git the _only_ legitimate way to change a running system, with an automated controller enforcing that reality continuously — not just at deploy time.

**← Index:** [[00 Integration DevOps Index]] | **Previous:** [[Day-45-Automating-MQ-Setup-with-Declarative-Config]] | **Next:** [[Day-47-OpenShift-Kubernetes-ConfigMaps]] →

---

## Theory

### The Four GitOps Principles

1. **Declarative** — the entire desired system state is described declaratively (YAML manifests), not as a sequence of imperative commands.
2. **Versioned and immutable** — the desired state is stored in Git, giving you a full audit trail and trivial rollback (`git revert`).
3. **Pulled automatically** — an agent running _inside_ the cluster pulls the desired state from Git; you don't push changes to the cluster from an external CI job.
4. **Continuously reconciled** — the agent continuously compares live cluster state to the Git-declared state and corrects drift automatically.

---

### Push-Based CI/CD vs Pull-Based GitOps

| Aspect                   | Push-based (traditional CI/CD)                                              | Pull-based (GitOps)                                                                             |
| ------------------------ | --------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Who initiates deployment | CI pipeline runs `oc apply` against the cluster                             | A controller inside the cluster (ArgoCD/Flux) pulls from Git                                    |
| Cluster credentials      | CI system needs cluster-admin-level credentials external to the cluster     | Only the in-cluster controller needs cluster credentials; CI never touches the cluster directly |
| Drift handling           | None — if someone manually `oc edit`s a Deployment, CI doesn't know or care | Controller detects drift and can auto-heal it back to Git state                                 |
| Audit trail              | Pipeline logs (can be deleted, rotated, or tampered with)                   | Git history — cryptographically-anchored, near-impossible to quietly rewrite                    |
| Rollback                 | Re-run an old pipeline job                                                  | `git revert`, controller reconciles automatically                                               |

> [!important] The Security Argument Is the Real Argument
> Push-based pipelines require your CI/CD system to hold credentials capable of modifying production clusters. That is a huge attack surface — compromise the CI system, compromise production. GitOps confines cluster-write credentials to a controller _inside_ the cluster's own trust boundary; the pipeline's job stops at "make sure Git reflects the desired state," and never touches the cluster API directly.

---

### The Reconciliation Loop

```
┌─────────────┐        pulls        ┌──────────────┐
│  Git Repo    │◀────────────────── │  ArgoCD/Flux │
│ (desired     │                    │  controller  │
│  state)      │  compares to  ───▶ │ (in-cluster) │
└─────────────┘   live cluster      └──────┬───────┘
                                            │ applies diff
                                            ▼
                                  ┌───────────────────┐
                                  │  Live Cluster      │
                                  │  (actual state)    │
                                  └───────────────────┘
```

This loop runs continuously (typically every few minutes, or on a webhook from Git). If a human runs `oc scale deployment/myapp --replicas=10` manually, the very next reconciliation pass notices the live state (10 replicas) no longer matches Git (say, 3 replicas) and **reverts it back to 3** — unless that drift is explicitly permitted.

---

### Repository Layout Pattern: Base + Overlays (Kustomize)

```
gitops-repo/
├── base/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml
    │   └── replica-patch.yaml
    ├── test/
    │   └── kustomization.yaml
    └── prod/
        ├── kustomization.yaml
        └── replica-patch.yaml
```

`base/` holds the common shape of the Deployment (identical to the "build once" BAR concept from Week 9). Each `overlays/<env>/` directory patches only what differs — replica count, resource limits, ConfigMap references — exactly mirroring the override-properties pattern from Day 43, now expressed as Kustomize patches instead of `.properties` files.

---

### ArgoCD Application Manifest (Declarative GitOps Definition)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: order-processing-prod
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/myorg/gitops-repo.git
    targetRevision: main
    path: overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: integration-prod
  syncPolicy:
    automated:
      prune: true # remove resources deleted from Git
      selfHeal: true # revert manual drift automatically
```

`selfHeal: true` is the line that turns "we deploy from Git" into true GitOps — without it, ArgoCD will show drift but won't correct it automatically.

---

## Hands-on Lab

### Exercise 1 — Build a Kustomize Base/Overlay Structure

```bash
mkdir -p ~/mw-pipeline/gitops-repo/{base,overlays/dev,overlays/prod}
cd ~/mw-pipeline/gitops-repo

cat > base/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-processing
spec:
  replicas: 1
  selector:
    matchLabels: { app: order-processing }
  template:
    metadata:
      labels: { app: order-processing }
    spec:
      containers:
        - name: ace-runtime
          image: my-registry/order-processing-ace:1.0.0
          ports: [{ containerPort: 7080 }]
EOF

cat > base/kustomization.yaml << 'EOF'
resources:
  - deployment.yaml
EOF
```

### Exercise 2 — Create Environment Overlays

```bash
cat > overlays/dev/kustomization.yaml << 'EOF'
resources:
  - ../../base
patches:
  - target:
      kind: Deployment
      name: order-processing
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 1
EOF

cat > overlays/prod/kustomization.yaml << 'EOF'
resources:
  - ../../base
patches:
  - target:
      kind: Deployment
      name: order-processing
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 3
EOF
```

### Exercise 3 — Render Each Overlay Locally (No Cluster Required Yet)

```bash
# kustomize is built into kubectl
kubectl kustomize overlays/dev
kubectl kustomize overlays/prod
```

Confirm the only diff between the two rendered manifests is `replicas: 1` vs `replicas: 3` — everything else is inherited unchanged from `base/`.

### Exercise 4 — Manual Drift Simulation (Conceptual, No Live ArgoCD Required)

If you have access to a cluster with ArgoCD installed:

```bash
argocd app create order-processing-dev \
  --repo https://github.com/myorg/gitops-repo.git \
  --path overlays/dev \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace integration-dev \
  --sync-policy automated --self-heal

# Simulate manual drift
kubectl scale deployment/order-processing --replicas=5 -n integration-dev

# Watch ArgoCD's next reconciliation pass revert it
argocd app get order-processing-dev --refresh
```

If you don't have a cluster available yet, write out in your own words what you'd expect `argocd app get --refresh` to report immediately after the manual scale command, and again 2–3 minutes later — you'll validate this for real once Day 47's cluster environment is up.

---

## Validation

- [ ] `kubectl kustomize overlays/dev` and `kubectl kustomize overlays/prod` both render valid, complete Deployment manifests.
- [ ] The only difference between the two rendered outputs is the intentional per-environment patch (replica count).
- [ ] You can explain, without looking back at the theory section, why GitOps confines cluster-write credentials to an in-cluster controller rather than an external CI job.
- [ ] You can state what `selfHeal: true` does and why omitting it means ArgoCD only _reports_ drift instead of _fixing_ it.

---

## Key Takeaways

- GitOps = declarative + versioned + pulled + continuously reconciled — all four properties matter, not just "config lives in Git."
- Pull-based deployment keeps cluster-admin credentials inside the cluster's trust boundary instead of exposing them to external CI systems.
- Kustomize's base/overlay pattern is the Kubernetes-native equivalent of Day 43's BAR override properties — same philosophy, different mechanism.
- `selfHeal: true` is what actually enforces "Git is the only source of truth" — without it you only get drift _visibility_, not drift _correction_.

---

**← Index:** [[00 Integration DevOps Index]] | **Previous:** [[Day-45-Automating-MQ-Setup-with-Declarative-Config]] | **Next:** [[Day-47-OpenShift-Kubernetes-ConfigMaps]] →
