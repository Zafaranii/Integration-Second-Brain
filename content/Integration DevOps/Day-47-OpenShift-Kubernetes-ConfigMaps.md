---
tags: [devops, bucket-4, openshift, kubernetes, configmaps, day-47]
created: 2025-07-05
bucket: 4
week: 10
day: 47
status: not-started
---

# Day 47 — OpenShift/Kubernetes Deployments: ConfigMaps

> [!info] Why This Day Exists
> Once your BAR (Day 43) or MQSC script (Day 45) needs to vary by environment inside a Kubernetes/OpenShift deployment, you need a Kubernetes-native mechanism for injecting that non-secret configuration. That mechanism is the **ConfigMap** — the direct cluster-native cousin of an ACE override-properties file.

**← Index:** [[00 Integration DevOps Index]] | **Previous:** [[Day-46-GitOps-Concepts]] | **Next:** [[Day-48-OpenShift-Kubernetes-Secrets]] →

---

## Theory

### What a ConfigMap Is (and Isn't)

A ConfigMap is a Kubernetes API object holding key-value pairs of **non-sensitive** configuration data. It is **not encrypted at rest by default** and **not access-controlled beyond normal RBAC** — never put credentials, tokens, or passwords in one (that's what Secrets, Day 48, are for, and even those have caveats).

| Good ConfigMap contents                                  | Bad ConfigMap contents (use a Secret instead) |
| -------------------------------------------------------- | --------------------------------------------- |
| `server.conf.yaml` snippet for an ACE integration server | Queue manager admin password                  |
| MQSC declarative scripts (Day 45's files)                | TLS private keys                              |
| Feature flags, log level, timeout values                 | Database connection passwords                 |
| A whole `overrides.properties` file for a BAR            | API tokens                                    |

---

### Three Ways to Create a ConfigMap

```bash
# 1. From literal key-value pairs
oc create configmap ace-loglevel --from-literal=LOG_LEVEL=DEBUG

# 2. From a file — the filename becomes the key, file contents become the value
oc create configmap mq-config --from-file=01-queues.mqsc

# 3. From a YAML manifest (preferred for GitOps — this is what lives in your repo)
cat > configmap.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: ace-overrides
  namespace: integration-dev
data:
  overrides.properties: |
    MyApp#OrderFlow.msgflow#MQOutput.destinationQueueName=DEV.ORDERS.OUT
EOF
oc apply -f configmap.yaml
```

For GitOps (Day 46), option 3 is the only one that belongs in your repository — options 1 and 2 are imperative one-off commands, useful for quick local testing but they leave no trace in Git.

---

### Two Ways to Consume a ConfigMap in a Pod

**As environment variables:**

```yaml
env:
  - name: LOG_LEVEL
    valueFrom:
      configMapKeyRef:
        name: ace-loglevel
        key: LOG_LEVEL
```

**As a mounted volume (file on disk inside the container):**

```yaml
volumes:
  - name: mq-config-volume
    configMap:
      name: mq-config
containers:
  - name: qm1
    volumeMounts:
      - name: mq-config-volume
        mountPath: /etc/mqm
        readOnly: true
```

| Consumption method | Use when                                                                                                                                            |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Env var            | A single simple value (log level, feature flag)                                                                                                     |
| Volume mount       | Multi-line files your app expects to `read()` from disk — this is exactly how Day 45's MQSC scripts and ACE's `overrides.properties` get into a pod |

> [!warning] ConfigMap Updates Don't Always Propagate Instantly
> Volume-mounted ConfigMaps _do_ update on disk inside the pod when the ConfigMap changes (after a sync delay, typically under a minute) — but most applications, including MQ and ACE, only read config files **at startup**. Updating a ConfigMap will not retroactively reconfigure a running queue manager; you still need a rolling restart of the pod to pick up the new values.

---

### Immutable ConfigMaps

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ace-overrides-v2
data:
  overrides.properties: |
    MQOutput.destinationQueueName=DEV.ORDERS.OUT
immutable: true
```

Setting `immutable: true` prevents accidental edits and gives the kubelet a performance optimization (it stops watching the object for changes). The tradeoff: to change config, you must create a **new** ConfigMap (e.g., `ace-overrides-v3`) and update the Deployment to reference it — which, conveniently, also gives you a clean rollback path and pairs naturally with GitOps's immutable-and-versioned principle from Day 46.

---

## Hands-on Lab

### Exercise 1 — Create a ConfigMap From Day 45's MQSC Files

```bash
cd ~/mw-pipeline/mq-config
oc create configmap mq-declarative-config \
  --from-file=01-queues.mqsc \
  --from-file=02-channels.mqsc \
  --from-file=03-auth.mqsc \
  -n integration-dev

oc get configmap mq-declarative-config -n integration-dev -o yaml
```

### Exercise 2 — Mount It Into an MQ Deployment

```bash
cat > mq-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: qm1
  namespace: integration-dev
spec:
  replicas: 1
  selector:
    matchLabels: { app: qm1 }
  template:
    metadata:
      labels: { app: qm1 }
    spec:
      containers:
        - name: qm1
          image: icr.io/ibm-messaging/mq:latest
          env:
            - { name: LICENSE, value: "accept" }
            - { name: MQ_QMGR_NAME, value: "QM1" }
          ports:
            - { containerPort: 1414 }
            - { containerPort: 9443 }
          volumeMounts:
            - name: mq-config-volume
              mountPath: /etc/mqm
              readOnly: true
      volumes:
        - name: mq-config-volume
          configMap:
            name: mq-declarative-config
EOF

oc apply -f mq-deployment.yaml
oc get pods -n integration-dev -w
```

### Exercise 3 — Verify the Config Landed Inside the Pod

```bash
POD=$(oc get pods -n integration-dev -l app=qm1 -o jsonpath='{.items[0].metadata.name}')
oc exec -it "$POD" -n integration-dev -- ls -la /etc/mqm
oc exec -it "$POD" -n integration-dev -- cat /etc/mqm/01-queues.mqsc
oc exec -it "$POD" -n integration-dev -- bash -c 'echo "DISPLAY QLOCAL(ORDERS.*)" | runmqsc QM1'
```

### Exercise 4 — Update Config and Observe the Restart Requirement

```bash
oc get configmap mq-declarative-config -n integration-dev -o yaml > current-config.yaml
# Edit current-config.yaml: bump a MAXDEPTH value in the 01-queues.mqsc data key
oc apply -f current-config.yaml

# The file on disk updates within ~60s, but QM1 already read it at startup —
# confirm the running queue manager did NOT pick up the change:
oc exec -it "$POD" -n integration-dev -- bash -c 'echo "DISPLAY QLOCAL(ORDERS.IN) MAXDEPTH" | runmqsc QM1'

# Now roll the deployment to force a fresh read:
oc rollout restart deployment/qm1 -n integration-dev
oc rollout status deployment/qm1 -n integration-dev

NEWPOD=$(oc get pods -n integration-dev -l app=qm1 -o jsonpath='{.items[0].metadata.name}')
oc exec -it "$NEWPOD" -n integration-dev -- bash -c 'echo "DISPLAY QLOCAL(ORDERS.IN) MAXDEPTH" | runmqsc QM1'
```

---

## Validation

- [ ] `oc get configmap mq-declarative-config -o yaml` shows all three MQSC files as separate data keys.
- [ ] `oc exec ... cat /etc/mqm/01-queues.mqsc` inside the running pod matches the source file exactly.
- [ ] `ORDERS.IN` and related objects exist inside the containerized queue manager, created automatically from the mounted ConfigMap — no manual `runmqsc` typing.
- [ ] Exercise 4 demonstrates, with real command output, that a ConfigMap change requires `oc rollout restart` to take effect on a running MQ pod.

---

## Key Takeaways

- ConfigMaps hold non-sensitive configuration only — never credentials or keys.
- YAML-manifest creation (not `--from-literal`/`--from-file` one-liners) is the form that belongs in a GitOps repository.
- Volume-mounted ConfigMaps are how Day 45's declarative MQSC files and Day 43's override-properties concept both reach a running container in Kubernetes.
- Updating a ConfigMap does not retroactively reconfigure a running MQ or ACE pod — a rollout restart is required because both read config only at startup.

---

**← Index:** [[00 Integration DevOps Index]] | **Previous:** [[Day-46-GitOps-Concepts]] | **Next:** [[Day-48-OpenShift-Kubernetes-Secrets]] →
