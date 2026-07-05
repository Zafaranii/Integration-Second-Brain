---
tags: [devops, bucket-4, openshift, kubernetes, debugging, day-49]
created: 2025-07-05
bucket: 4
week: 10
day: 49
status: not-started
---

# Day 49 — Pod Debugging

> [!info] Why This Day Exists
> Everything built across Days 41–48 will eventually fail in a cluster at 3 AM — a bad ConfigMap, a missing Secret key, a resource limit too tight for an ACE integration server's JVM heap. This day is the practical toolkit for going from "the pod is red" to "I know exactly why and how to fix it," fast.

**← Index:** [[00 Integration DevOps Index]] | **Previous:** [[Day-48-OpenShift-Kubernetes-Secrets]] | **Next:** [[Day-50-Final-Architecture-Review]] →

---

## Theory

### Pod Lifecycle States

| State                            | Meaning                                                               | Common causes in this stack                                                     |
| -------------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `Pending`                        | Pod accepted but not yet scheduled/running                            | Insufficient cluster resources, unbound PVC, image pull not yet started         |
| `ContainerCreating`              | Scheduled, but container not yet started                              | Slow image pull, ConfigMap/Secret referenced doesn't exist                      |
| `Running`                        | Container process is executing                                        | Normal — but check readiness, not just this state                               |
| `CrashLoopBackOff`               | Container starts, exits, and Kubernetes is backing off retry attempts | App-level crash — bad config, missing license accept, JVM OOM                   |
| `Error` / `CreateContainerError` | Container failed to even start                                        | Bad image, invalid command, missing mounted file the entrypoint expects         |
| `Completed`                      | Container exited with code 0                                          | Expected for Jobs/init containers; **unexpected** for a long-running MQ/ACE pod |
| `ImagePullBackOff`               | Cluster can't pull the specified image                                | Wrong image tag, missing/invalid `dockerconfigjson` pull secret                 |

---

### The Debugging Command Ladder

Work top-to-bottom — each command narrows the problem:

```bash
# 1. Is it even scheduled? What state is it in?
oc get pods -n integration-dev

# 2. Why is it in that state? (events at the bottom are gold)
oc describe pod <pod-name> -n integration-dev

# 3. What did the app itself say before it died?
oc logs <pod-name> -n integration-dev

# 4. What did the PREVIOUS crashed instance say? (critical for CrashLoopBackOff)
oc logs <pod-name> -n integration-dev --previous

# 5. Get an interactive shell inside the running container
oc rsh <pod-name> -n integration-dev
# or, for a specific container in a multi-container pod:
oc exec -it <pod-name> -c <container-name> -n integration-dev -- bash

# 6. If the container can't even start, debug via an ephemeral copy
oc debug pod/<pod-name> -n integration-dev
```

> [!important] `--previous` Is the Command Most People Forget
> When a pod is in `CrashLoopBackOff`, `oc logs` by default shows the logs of the **current** (freshly restarted, likely empty or just-starting) container instance. The actual error that caused the crash is almost always in the **previous** instance's logs. If you only remember one flag from this page, make it `--previous`.

---

### Reading `oc describe pod` — What Actually Matters

The output is long. Skip to the **Events** section at the bottom first:

```
Events:
  Type     Reason     Age   From               Message
  ----     ------     ----  ----               -------
  Normal   Scheduled  2m    default-scheduler  Successfully assigned...
  Normal   Pulling    2m    kubelet            Pulling image "my-registry/ace:1.0.0"
  Warning  Failed     1m    kubelet            Failed to pull image: unauthorized
  Warning  BackOff    30s   kubelet            Back-off pulling image
```

This example immediately tells you: don't bother looking at application logs — the container never even started. The fix is a missing/invalid image pull Secret, not an ACE configuration problem.

Also check higher up in the `describe` output:

- **`Limits`/`Requests`** — a JVM-based ACE integration server OOM-killed due to a memory limit set too low shows as `Reason: OOMKilled` under `Last State`.
- **`Volumes`** — confirms whether your ConfigMap/Secret mounts from Days 47–48 actually resolved, or are silently missing.
- **`Conditions`** — `PodScheduled`, `Initialized`, `ContainersReady`, `Ready` — tells you exactly which lifecycle gate failed.

---

### Common Failure → Fix Table for This Stack

| Symptom                                                              | Likely cause                                                                                    | Fix                                                                                             |
| -------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `CrashLoopBackOff` on an MQ pod, `--previous` logs show license text | `LICENSE=accept` env var missing or misspelled                                                  | Fix the Deployment env block, redeploy                                                          |
| `CreateContainerConfigError`                                         | Pod references a ConfigMap/Secret key that doesn't exist                                        | `oc describe pod` will name the exact missing key — check for typos against Day 47/48 manifests |
| `OOMKilled` on an ACE integration server pod                         | JVM heap settings exceed the pod's memory `limits`                                              | Raise the pod's `resources.limits.memory`, or tune ACE JVM heap via configurable service        |
| Pod `Pending` indefinitely                                           | PVC stuck `Pending` (no matching StorageClass) or insufficient node resources                   | `oc get pvc`, `oc describe pvc`; `oc describe node` for resource pressure                       |
| `ImagePullBackOff`                                                   | Wrong tag, or private registry pull secret missing/expired                                      | `oc describe pod` shows the exact pull error; verify `imagePullSecrets` on the ServiceAccount   |
| Pod `Running` but MQ channel won't connect                           | Readiness probe passing but MQSC config (Day 45/47) didn't apply — check mount, not the network | `oc exec ... runmqsc` to inspect live object state directly                                     |

---

## Hands-on Lab

### Exercise 1 — Deliberately Break Your Day 47 MQ Deployment

```bash
# Break it: reference a ConfigMap key that doesn't exist
oc get deployment qm1 -n integration-dev -o yaml > qm1-broken.yaml
sed -i 's/mq-declarative-config/mq-declarative-config-typo/' qm1-broken.yaml
oc apply -f qm1-broken.yaml
oc get pods -n integration-dev -w
```

### Exercise 2 — Diagnose It Using the Command Ladder

```bash
POD=$(oc get pods -n integration-dev -l app=qm1 -o jsonpath='{.items[0].metadata.name}')
oc describe pod "$POD" -n integration-dev | tail -20
```

Confirm the Events section names the missing ConfigMap. Fix it:

```bash
sed -i 's/mq-declarative-config-typo/mq-declarative-config/' qm1-broken.yaml
oc apply -f qm1-broken.yaml
oc rollout status deployment/qm1 -n integration-dev
```

### Exercise 3 — Simulate an OOMKilled Crash Loop

```bash
oc get deployment qm1 -n integration-dev -o yaml > qm1-oom.yaml
# Add an intentionally tiny memory limit under the container's resources block:
#   resources:
#     limits:
#       memory: "32Mi"
oc apply -f qm1-oom.yaml
oc get pods -n integration-dev -w
```

Once you see `CrashLoopBackOff`:

```bash
POD=$(oc get pods -n integration-dev -l app=qm1 -o jsonpath='{.items[0].metadata.name}')
oc describe pod "$POD" -n integration-dev | grep -A3 "Last State"
oc logs "$POD" -n integration-dev --previous
```

Confirm `Reason: OOMKilled`. Fix by restoring a realistic memory limit (e.g., `1Gi`) and redeploy.

### Exercise 4 — Interactive Live Debugging

```bash
POD=$(oc get pods -n integration-dev -l app=qm1 -o jsonpath='{.items[0].metadata.name}')
oc rsh "$POD" -n integration-dev

# Inside the pod:
dspmq
echo "DISPLAY QLOCAL(ORDERS.*)" | runmqsc QM1
ps aux
exit
```

### Exercise 5 — `oc debug` for a Pod That Won't Even Start

```bash
# For a pod stuck in ImagePullBackOff or similar, spin up an ephemeral debug copy
oc debug pod/"$POD" -n integration-dev
```

This creates a copy of the pod spec with an interactive shell, letting you inspect environment, mounts, and command args even when the real pod can't successfully start.

---

## Validation

- [ ] You caused and correctly diagnosed a `CreateContainerConfigError` from a bad ConfigMap reference using `oc describe pod` events alone (no logs needed — the pod never started).
- [ ] You caused and correctly diagnosed an `OOMKilled` crash loop using `oc logs --previous` and the `Last State` section of `oc describe pod`.
- [ ] You successfully used `oc rsh`/`oc exec` to run a live `runmqsc` command inside a running MQ pod.
- [ ] You can state, without checking notes, the one command flag people most often forget when debugging `CrashLoopBackOff`.

---

## Key Takeaways

- Work the debugging ladder in order: `get pods` → `describe pod` (check Events last) → `logs` → `logs --previous` → `exec`/`rsh` → `oc debug`.
- `--previous` is essential for `CrashLoopBackOff` — the current container instance's logs are usually empty or unhelpful.
- `oc describe pod`'s Events section usually tells you which _category_ of problem you have (scheduling, image pull, config, OOM) before you even look at application logs.
- `OOMKilled` shows up under `Last State`, not `State` — check both.

---

**← Index:** [[00 Integration DevOps Index]] | **Previous:** [[Day-48-OpenShift-Kubernetes-Secrets]] | **Next:** [[Day-50-Final-Architecture-Review]] →
