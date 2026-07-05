---
tags:
  - devops
  - bucket-4
  - index
  - moc
created: 2025-07-05
bucket: 4
status: active
---

# Bucket 4 — Integration DevOps & Automation

> As an integration engineer, building a flow or defining a queue is only half the job — the other half is making sure that artifact gets from your laptop to production the same way, every time, without a human manually clicking through the ACE Toolkit or typing `runmqsc` commands from memory. This module covers pipelining middleware builds, treating MQ and ACE configuration as versioned code, and deploying/debugging on OpenShift using GitOps principles.

**Tags:** #devops #cicd #gitops #openshift #index

---

## Map of Content

### Week 9 — Build & Package Automation

| Day                                                            | Topic                                           |
| -------------------------------------------------------------- | ----------------------------------------------- |
| [[Day-41-CICD-Concepts-for-Middleware\|Day 41]]                | CI/CD Concepts for Middleware                   |
| [[Day-42-Automating-ACE-BAR-Builds-via-CLI\|Day 42]]           | Automating ACE BAR Builds via CLI               |
| [[Day-43-ACE-BAR-Overrides-and-Environment-Config\|Day 43]]    | ACE BAR Overrides & Environment-Specific Config |
| [[Day-44-MQ-Docker-Containers-Setup\|Day 44]]                  | MQ Docker Containers — Setup & Basics           |
| [[Day-45-Automating-MQ-Setup-with-Declarative-Config\|Day 45]] | Automating MQ Setup with Declarative Config     |

### Week 10 — Deployment, GitOps & Synthesis

| Day                                                | Topic                                         |
| -------------------------------------------------- | --------------------------------------------- |
| [[Day-46-GitOps-Concepts\|Day 46]]                 | GitOps Concepts                               |
| [[Day-47-OpenShift-Kubernetes-ConfigMaps\|Day 47]] | OpenShift/Kubernetes Deployments — ConfigMaps |
| [[Day-48-OpenShift-Kubernetes-Secrets\|Day 48]]    | OpenShift/Kubernetes Deployments — Secrets    |
| [[Day-49-Pod-Debugging\|Day 49]]                   | Pod Debugging                                 |
| [[Day-50-Final-Architecture-Review\|Day 50]]       | Final 10-Week Architecture Review             |

---

## Concept Index

- **Pipeline theory** → [[Day-41-CICD-Concepts-for-Middleware]]
- **ACE build automation** → [[Day-42-Automating-ACE-BAR-Builds-via-CLI]], [[Day-43-ACE-BAR-Overrides-and-Environment-Config]]
- **MQ as code** → [[Day-44-MQ-Docker-Containers-Setup]], [[Day-45-Automating-MQ-Setup-with-Declarative-Config]]
- **Declarative deployment philosophy** → [[Day-46-GitOps-Concepts]]
- **Kubernetes/OpenShift config injection** → [[Day-47-OpenShift-Kubernetes-ConfigMaps]], [[Day-48-OpenShift-Kubernetes-Secrets]]
- **Runtime troubleshooting** → [[Day-49-Pod-Debugging]]
- **Synthesis / capstone** → [[Day-50-Final-Architecture-Review]]

---

## Toolchain Reference

| Tool                        | Purpose                                                        | Typical Invocation                                               |
| --------------------------- | -------------------------------------------------------------- | ---------------------------------------------------------------- |
| `ibmint`                    | Modern ACE CLI compiler/packager (ACE 11+)                     | `ibmint package --input-path . --output-bar-file app.bar`        |
| `mqsicreatebar`             | Legacy ACE/IIB BAR builder (headless Eclipse)                  | `mqsicreatebar -data <workspace> -b app.bar -a MyApp`            |
| `mqsiapplybaroverride`      | Applies environment-specific property overrides to a built BAR | `mqsiapplybaroverride -b app.bar -k app -p overrides.properties` |
| `mqsireadbar`               | Inspects BAR contents / extracts default override properties   | `mqsireadbar -b app.bar -p -o defaults.properties`               |
| `runmqsc`                   | Interactive/scripted MQ administration                         | `runmqsc QM1 < config.mqsc`                                      |
| `crtmqm` / `strmqm`         | Create / start a queue manager                                 | `crtmqm QM1 && strmqm QM1`                                       |
| `docker` / `docker-compose` | Container runtime for MQ, ACE, and CI build agents             | `docker run`, `docker compose up`                                |
| `oc`                        | OpenShift CLI (superset of kubectl)                            | `oc apply -f deployment.yaml`                                    |
| `kubectl`                   | Kubernetes CLI                                                 | `kubectl get pods -n integration`                                |
| `git`                       | Source of truth for GitOps                                     | `git push`, `git tag`                                            |
| ArgoCD / Flux               | GitOps controllers — reconcile cluster state to Git state      | `argocd app sync my-app`                                         |

---

## CI/CD Pipeline Stage Reference

```
Commit → Build → Unit/Flow Test → Package (BAR/Image) → Deploy Dev
   → Integration Test → Promote (same artifact) → Deploy Test/UAT
   → Approval Gate → Promote (same artifact) → Deploy Prod
```

> [!important] The One Rule That Matters Most
> **Build once, promote the binary.** A BAR file (or container image) built for Dev must be the _exact same artifact_ deployed to Prod. Only configuration — override properties, ConfigMaps, Secrets — changes between environments. If you rebuild source per environment, you have lost the guarantee that what you tested is what you shipped.

---

## Pipeline / Deployment Failure Decision Tree

```
Pipeline or deployment failing?
│
├── Build stage fails
│   ├── Compile error → check .msgflow/.esql syntax, ibmint output
│   └── "Toolkit version mismatch" → pin ACE version in CI build image
│
├── Package stage fails
│   └── "BAR override key not found" → override references a resource not in the BAR (Day 43)
│
├── Deploy stage fails
│   ├── Pod stuck Pending → check resource quota / PVC binding (Day 49)
│   ├── CrashLoopBackOff → check `oc logs --previous` (Day 49)
│   └── ConfigMap/Secret not mounted → check volume/env references (Day 47/48)
│
├── Runtime failure post-deploy
│   ├── MQ channel won't start → check declarative MQSC applied correctly (Day 45)
│   └── App can't read config → override properties vs ConfigMap precedence confusion (Day 43/47)
│
└── GitOps drift detected
    └── Someone changed cluster state manually → let controller reconcile, or fix Git and re-sync (Day 46)
```
