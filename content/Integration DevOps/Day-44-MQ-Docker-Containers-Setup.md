---
tags: [devops, bucket-4, mq, docker, day-44]
created: 2025-07-05
bucket: 4
week: 9
day: 44
status: not-started
---

# Day 44 — MQ Docker Containers: Setup & Basics

> [!info] Why This Day Exists
> You cannot test MQ-dependent flows in CI against a shared corporate queue manager — it's slow, it's not isolated, and someone else's test data will collide with yours. Every serious ACE/MQ pipeline spins up a disposable, containerized queue manager per test run. This day gets you comfortable with that container as a first-class citizen.

**← Index:** [[00 Integration DevOps Index]] | **Previous:** [[Day-43-ACE-BAR-Overrides-and-Environment-Config]] | **Next:** [[Day-45-Automating-MQ-Setup-with-Declarative-Config]] →

---

## Theory

### The Official MQ Container Image

IBM publishes MQ as a container image on IBM Container Registry / Docker Hub:

```
icr.io/ibm-messaging/mq:latest        # or pin a specific version, e.g. :9.3.5.0-r1
```

A **Developer Edition** license is embedded for non-production use — critical for CI, since you don't want a production entitlement check running inside a throwaway test container.

---

### Required Environment Variables

| Variable            | Purpose                                                             | Example                      |
| ------------------- | ------------------------------------------------------------------- | ---------------------------- |
| `LICENSE`           | Must be `accept` or the container refuses to start                  | `LICENSE=accept`             |
| `MQ_QMGR_NAME`      | Name of the queue manager to auto-create                            | `MQ_QMGR_NAME=QM1`           |
| `MQ_APP_PASSWORD`   | Password for the default `app` user (used by client connections)    | `MQ_APP_PASSWORD=passw0rd`   |
| `MQ_ADMIN_PASSWORD` | Password for the `admin` user (web console, `runmqsc` remote admin) | `MQ_ADMIN_PASSWORD=passw0rd` |
| `MQ_ENABLE_METRICS` | Exposes Prometheus-format metrics                                   | `MQ_ENABLE_METRICS=true`     |

---

### Ports You Need to Know

| Port   | Purpose                                              |
| ------ | ---------------------------------------------------- |
| `1414` | MQ listener — client channel connections (`SVRCONN`) |
| `9443` | MQ Web Console + REST Admin API (HTTPS)              |
| `9157` | Prometheus metrics endpoint (if enabled)             |

---

### Persistence — Why Volumes Matter Here More Than Almost Anywhere Else

A queue manager's data — queue contents, logs, object definitions — lives under `/mnt/mqm` inside the container. Without a volume:

```
docker stop mycontainer && docker rm mycontainer
```

...**permanently destroys every message and every queue definition.** This is fine for a disposable CI test queue manager (that's the point — every test run starts clean). It is _not_ fine for anything you intend to keep between restarts (a local dev queue manager you're iterating against over a week).

| Use case                           | Volume strategy                                       |
| ---------------------------------- | ----------------------------------------------------- |
| CI ephemeral test QM               | No volume — fresh state every run is a feature        |
| Local persistent dev QM            | Named volume: `-v qm1data:/mnt/mqm`                   |
| Declarative config replay (Day 45) | Bind-mount a config directory, not the data directory |

---

### Single-Instance vs Multi-Instance vs Native HA

| Mode                  | Description                                                                      | When you'd use it               |
| --------------------- | -------------------------------------------------------------------------------- | ------------------------------- |
| Single-instance       | One queue manager, one container/pod                                             | Dev, CI, most Test environments |
| Multi-instance        | Active/standby QM pair sharing networked storage, automatic failover             | Traditional on-prem Prod HA     |
| Native HA (OpenShift) | 3-replica MQ queue manager using Raft-like replication, no shared storage needed | Modern OpenShift-based Prod HA  |

This bucket's labs use **single-instance** containers exclusively — HA topologies are an infrastructure-team concern layered on top of everything you're learning here.

---

## Hands-on Lab

### Exercise 1 — Run Your First Containerized Queue Manager

```bash
docker run -d \
  --name qm1 \
  --env LICENSE=accept \
  --env MQ_QMGR_NAME=QM1 \
  --env MQ_APP_PASSWORD=passw0rd \
  --env MQ_ADMIN_PASSWORD=passw0rd \
  -p 1414:1414 \
  -p 9443:9443 \
  icr.io/ibm-messaging/mq:latest

# Watch it come up
docker logs -f qm1
```

Wait for the log line indicating the queue manager is running and the listener has started.

### Exercise 2 — Connect In and Run Interactive `runmqsc`

```bash
docker exec -it qm1 bash

# Inside the container:
runmqsc QM1
```

At the `runmqsc` prompt:

```
DEFINE QLOCAL(TEST.QUEUE) REPLACE
DISPLAY QLOCAL(TEST.QUEUE)
END
```

### Exercise 3 — Verify From the Host via the Web Console

```bash
# The web console is HTTPS on 9443, self-signed cert by default
curl -sk https://localhost:9443/ibmmq/console/
```

Or open `https://localhost:9443/ibmmq/console/` in a browser, log in as `admin` with the password you set, and confirm `TEST.QUEUE` appears under QM1's queue list.

### Exercise 4 — Persistence Proof: Volume vs No Volume

```bash
# WITHOUT a volume — destroy and recreate, watch state vanish
docker stop qm1 && docker rm qm1
docker run -d --name qm1 --env LICENSE=accept --env MQ_QMGR_NAME=QM1 \
  --env MQ_APP_PASSWORD=passw0rd -p 1414:1414 -p 9443:9443 \
  icr.io/ibm-messaging/mq:latest
docker exec -it qm1 bash -c 'echo "DISPLAY QLOCAL(TEST.QUEUE)" | runmqsc QM1'
# Expect: AMQ8147 (object does not exist) — TEST.QUEUE is gone

# WITH a named volume — state survives recreation
docker stop qm1 && docker rm qm1
docker volume create qm1data
docker run -d --name qm1 --env LICENSE=accept --env MQ_QMGR_NAME=QM1 \
  --env MQ_APP_PASSWORD=passw0rd -p 1414:1414 -p 9443:9443 \
  -v qm1data:/mnt/mqm \
  icr.io/ibm-messaging/mq:latest

docker exec -it qm1 bash -c 'echo "DEFINE QLOCAL(TEST.QUEUE) REPLACE" | runmqsc QM1'
docker stop qm1 && docker start qm1
docker exec -it qm1 bash -c 'echo "DISPLAY QLOCAL(TEST.QUEUE)" | runmqsc QM1'
# Expect: TEST.QUEUE still exists after stop/start with the volume attached
```

---

## Validation

- [ ] `docker logs qm1` shows the queue manager reached a running state with the listener active.
- [ ] `TEST.QUEUE` is visible both via `runmqsc DISPLAY` and via the web console.
- [ ] You can articulate, from Exercise 4's output, exactly which data survives a `docker rm` with a volume attached vs without one.
- [ ] `docker exec -it qm1 dspmq` shows `QM1` with status `RUNNING`.

---

## Key Takeaways

- MQ's official container image ships with a Developer Edition license baked in — ideal for disposable CI queue managers, never for production entitlement.
- `LICENSE=accept` is mandatory; the container will not start without it.
- Volumes are the dividing line between "ephemeral test QM" (no volume, fresh every run) and "persistent dev QM" (named volume).
- Single-instance containers are sufficient for Dev/Test/CI; HA (multi-instance or Native HA) is a separate, infrastructure-layer concern.

---

**← Index:** [[00 Integration DevOps Index]] | **Previous:** [[Day-43-ACE-BAR-Overrides-and-Environment-Config]] | **Next:** [[Day-45-Automating-MQ-Setup-with-Declarative-Config]] →
