---
tags: [devops, bucket-4, mq, mqsc, declarative, day-45]
created: 2025-07-05
bucket: 4
week: 9
day: 45
status: not-started
---

# Day 45 — Automating MQ Setup with Declarative Config

> [!info] Why This Day Exists
> Typing `DEFINE QLOCAL` interactively into `runmqsc` is fine for exploration but is not a repeatable process. Real environments define every queue, channel, and topic as version-controlled MQSC scripts (or JSON-based config) that run automatically the moment a queue manager container starts — MQ configuration as code, the direct precursor to Week 10's GitOps concepts.

**← Index:** [[00 Integration DevOps Index]] | **Previous:** [[Day-44-MQ-Docker-Containers-Setup]] | **Next:** [[Day-46-GitOps-Concepts]] →

---

## Theory

### Two Declarative Approaches

| Approach                                                           | Mechanism                                                                                                                                        | Best for                                                                        |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------- |
| **MQSC-at-startup**                                                | Drop `.mqsc` script files into `/etc/mqm/` inside the container; the entrypoint runs them automatically against the queue manager on first start | Most teams — simplest, most portable, works identically on Docker and OpenShift |
| **JSON-based config (`mqsc.ini` / MQ's declarative config layer)** | A structured config format some MQ tooling and the MQ Operator support for object definitions                                                    | Larger estates using the MQ Operator's CRD-driven queue manager definitions     |

This lab focuses on the MQSC-at-startup approach — it is universally supported and maps directly onto both `docker run` and OpenShift ConfigMap mounting (Day 47).

---

### Idempotency — The Property That Makes This Safe to Re-Run

An MQSC script that runs every time a container starts **must** be idempotent — running it twice must produce the same end state, not an error on the second run.

```mqsc
* BAD — fails on second run with "object already exists"
DEFINE QLOCAL(ORDERS.IN)

* GOOD — REPLACE makes it idempotent
DEFINE QLOCAL(ORDERS.IN) REPLACE
```

> [!warning] `REPLACE` Has Teeth
> `REPLACE` on a queue definition does not delete messages already on that queue — it redefines the object's _attributes_. But be deliberate with it on channels and authority records too; a `REPLACE` that silently drops a `MAXDEPTH` override you set manually in Prod outside of code is exactly the kind of drift GitOps (Day 46) exists to catch and prevent.

---

### A Realistic Declarative MQSC Script

**`config/01-queues.mqsc`:**

```mqsc
* Application queues
DEFINE QLOCAL(ORDERS.IN)  REPLACE MAXDEPTH(50000) DEFPSIST(YES)
DEFINE QLOCAL(ORDERS.OUT) REPLACE MAXDEPTH(50000) DEFPSIST(YES)
DEFINE QLOCAL(ORDERS.DLQ) REPLACE MAXDEPTH(50000) DEFPSIST(YES)

* Set the queue manager's dead letter queue
ALTER QMGR DEADQ(ORDERS.DLQ)
```

**`config/02-channels.mqsc`:**

```mqsc
* Client channel for ACE to connect through
DEFINE CHANNEL(ORDERS.SVRCONN) CHLTYPE(SVRCONN) REPLACE
SET CHLAUTH(ORDERS.SVRCONN) TYPE(ADDRESSMAP) ADDRESS(*) USERSRC(CHANNEL)
```

**`config/03-auth.mqsc`:**

```mqsc
* Grant the app user put/get access
SET AUTHREC PROFILE(ORDERS.IN)  OBJTYPE(QUEUE) PRINCIPAL('app') AUTHADD(PUT,GET,BROWSE,INQ)
SET AUTHREC PROFILE(ORDERS.OUT) OBJTYPE(QUEUE) PRINCIPAL('app') AUTHADD(PUT,GET,BROWSE,INQ)
```

Splitting into numbered files (`01-`, `02-`, `03-`) controls execution order — the container's entrypoint runs files from `/etc/mqm/` alphabetically.

---

### Wiring It Into `docker-compose`

```yaml
version: "3.8"
services:
  qm1:
    image: icr.io/ibm-messaging/mq:latest
    container_name: qm1
    environment:
      LICENSE: accept
      MQ_QMGR_NAME: QM1
      MQ_APP_PASSWORD: passw0rd
      MQ_ADMIN_PASSWORD: passw0rd
    ports:
      - "1414:1414"
      - "9443:9443"
    volumes:
      - ./config:/etc/mqm/:ro
```

Mounting `./config` (your version-controlled MQSC files) read-only into `/etc/mqm/` means: **the entire queue manager topology for this environment is defined by files sitting in Git**, not by anyone's memory of what they typed into `runmqsc` six months ago.

---

## Hands-on Lab

### Exercise 1 — Build the Config Directory

```bash
mkdir -p ~/mw-pipeline/mq-config
cd ~/mw-pipeline/mq-config

cat > 01-queues.mqsc << 'EOF'
DEFINE QLOCAL(ORDERS.IN)  REPLACE MAXDEPTH(50000) DEFPSIST(YES)
DEFINE QLOCAL(ORDERS.OUT) REPLACE MAXDEPTH(50000) DEFPSIST(YES)
DEFINE QLOCAL(ORDERS.DLQ) REPLACE MAXDEPTH(50000) DEFPSIST(YES)
ALTER QMGR DEADQ(ORDERS.DLQ)
EOF

cat > 02-channels.mqsc << 'EOF'
DEFINE CHANNEL(ORDERS.SVRCONN) CHLTYPE(SVRCONN) REPLACE
SET CHLAUTH(ORDERS.SVRCONN) TYPE(ADDRESSMAP) ADDRESS(*) USERSRC(CHANNEL)
EOF

cat > 03-auth.mqsc << 'EOF'
SET AUTHREC PROFILE(ORDERS.IN)  OBJTYPE(QUEUE) PRINCIPAL('app') AUTHADD(PUT,GET,BROWSE,INQ)
SET AUTHREC PROFILE(ORDERS.OUT) OBJTYPE(QUEUE) PRINCIPAL('app') AUTHADD(PUT,GET,BROWSE,INQ)
EOF
```

### Exercise 2 — Write the `docker-compose.yml`

```bash
cd ~/mw-pipeline
cat > docker-compose.yml << 'EOF'
version: "3.8"
services:
  qm1:
    image: icr.io/ibm-messaging/mq:latest
    container_name: qm1
    environment:
      LICENSE: accept
      MQ_QMGR_NAME: QM1
      MQ_APP_PASSWORD: passw0rd
      MQ_ADMIN_PASSWORD: passw0rd
    ports:
      - "1414:1414"
      - "9443:9443"
    volumes:
      - ./mq-config:/etc/mqm/:ro
EOF

docker compose up -d
docker compose logs -f qm1
```

### Exercise 3 — Verify Objects Were Created Automatically (No Manual `runmqsc` Typing)

```bash
docker exec -it qm1 bash -c 'echo "DISPLAY QLOCAL(ORDERS.*)" | runmqsc QM1'
docker exec -it qm1 bash -c 'echo "DISPLAY CHANNEL(ORDERS.SVRCONN)" | runmqsc QM1'
docker exec -it qm1 bash -c 'echo "DISPLAY QMGR DEADQ" | runmqsc QM1'
```

### Exercise 4 — Prove Idempotency

```bash
docker compose down
docker compose up -d
docker compose logs qm1 | grep -i error
# Expect: no errors from re-running the same MQSC scripts on a fresh container
```

### Exercise 5 — Simulate a Config Change Through Git, Not Through `runmqsc`

```bash
cd ~/mw-pipeline/mq-config
sed -i 's/MAXDEPTH(50000)/MAXDEPTH(100000)/' 01-queues.mqsc

cd ~/mw-pipeline
git init -q 2>/dev/null; git add mq-config docker-compose.yml
git commit -q -m "Increase ORDERS queue max depth to 100000" 2>/dev/null || true

docker compose down && docker compose up -d
docker exec -it qm1 bash -c 'echo "DISPLAY QLOCAL(ORDERS.IN) MAXDEPTH" | runmqsc QM1'
```

Notice the workflow: the change happened in a text file, was committed, and only then was the queue manager recreated to pick it up. Nobody connected interactively and typed `ALTER QLOCAL`.

---

## Validation

- [ ] All three MQSC files applied without error on first `docker compose up`.
- [ ] `ORDERS.DLQ` is correctly set as the queue manager's dead letter queue via `DISPLAY QMGR DEADQ`.
- [ ] Re-running `docker compose down && docker compose up -d` produces zero MQSC errors (idempotency proof).
- [ ] The `MAXDEPTH` change in Exercise 5 is reflected after recreation, and the change is visible in `git log` as the source of truth.

---

## Key Takeaways

- MQSC-at-startup (files in `/etc/mqm/`) is the simplest, most portable way to treat MQ object definitions as code.
- Every declarative MQSC script must be **idempotent** — `REPLACE` on definitions, careful `SET AUTHREC` usage — since it will run on every container start.
- `docker-compose.yml` mounting a version-controlled config directory turns "queue manager setup" from institutional memory into an auditable Git history.
- This pattern — config in Git, applied declaratively, never edited live — is a direct rehearsal for GitOps, which is Day 46's topic.

---

**← Index:** [[00 Integration DevOps Index]] | **Previous:** [[Day-44-MQ-Docker-Containers-Setup]] | **Next:** [[Day-46-GitOps-Concepts]] →
