---
tags: [devops, bucket-4, cicd, pipelines, day-41]
created: 2025-07-05
bucket: 4
week: 9
day: 41
status: not-started
---

# Day 41 — CI/CD Concepts for Middleware

> [!info] Why This Day Exists
> Middleware CI/CD is not the same problem as application CI/CD. A stateless microservice can be killed and replaced freely. A queue manager has disk-resident state. An ACE integration server holds configurable services that differ per environment. Getting this wrong means either shipping untested flows to production, or spending your career manually re-clicking through the same deployment wizard forty times a year.

**← Index:** [[00 Integration DevOps Index]] | **Next:** [[Day-42-Automating-ACE-BAR-Builds-via-CLI]] →

---

## Theory

### CI vs CD vs Continuous Deployment — Precise Definitions

| Term                            | Definition                                                                                                          | Middleware example                                                                          |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| **Continuous Integration (CI)** | Every commit is automatically built and tested against a shared mainline                                            | Every push to a flow's repo triggers `ibmint package` + flow unit tests                     |
| **Continuous Delivery (CD)**    | Every build that passes CI is automatically deployed to a staging environment and is _always in a releasable state_ | BAR is auto-deployed to a Test integration server; promotion to Prod is a manual gate       |
| **Continuous Deployment**       | Every build that passes all tests is automatically deployed to production, no human gate                            | Rare in regulated middleware environments — usually one manual approval remains before Prod |

Most integration teams practice **Continuous Delivery**, not full Continuous Deployment — there is almost always a change-control gate before production for anything touching MQ or a core ESB.

---

### Why Middleware CI/CD Is Structurally Harder Than App CI/CD

| Challenge            | Application world                        | Middleware world                                                                                                                |
| -------------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Artifact type        | Container image (self-contained)         | BAR file (references external configurable services by _name_, not value)                                                       |
| State                | Usually stateless, horizontally scalable | Queue managers hold persistent, disk-resident message state                                                                     |
| Environment coupling | Config injected via env vars cleanly     | ACE default policies, JDBC/JMS providers, and MQ connection details are bound by name inside the BAR and resolved at the server |
| Testing              | Unit tests run in isolation easily       | Flow tests often need a live queue manager, a mock backend, or a running integration node                                       |
| Rollback             | Redeploy previous image tag              | Redeploy previous BAR _and_ verify no destructive MQ object changes were applied in between                                     |

> [!warning] The Silent Trap: Environment-Baked BARs
> If your ACE Toolkit build embeds environment-specific values (a Dev database URL, a Dev queue manager name) directly into the flow instead of using a **configurable service reference**, you cannot promote that BAR anywhere else without a rebuild — which breaks the "build once" rule and invalidates every test you ran in Dev. Day 43 covers the override mechanism that fixes this.

---

### The Canonical Middleware Pipeline

```
┌─────────┐   ┌────────┐   ┌────────────┐   ┌─────────┐   ┌──────────────┐   ┌──────┐
│ Commit  │──▶│ Build  │──▶│ Flow/Unit  │──▶│ Package │──▶│ Deploy → Dev │──▶│ Test │
│ (git)   │   │(ibmint)│   │   Tests    │   │  (BAR)  │   │              │   │      │
└─────────┘   └────────┘   └────────────┘   └─────────┘   └──────────────┘   └──┬───┘
                                                                                  │
                          ┌───────────────────────────────────────────────────────┘
                          ▼
                ┌──────────────────┐   ┌────────────┐   ┌─────────────────┐   ┌──────┐
                │ Promote same BAR │──▶│ Deploy Test│──▶│ Manual Approval │──▶│ Prod │
                │ (no rebuild)     │   │  /UAT      │   │      Gate       │   │      │
                └──────────────────┘   └────────────┘   └─────────────────┘   └──────┘
```

**Key principle repeated because it is the single most-violated rule in real ACE/MQ shops:** the BAR built for Dev is bit-for-bit the same BAR deployed to Prod. Only the _override properties_ file, ConfigMap, or Secret changes.

---

### Pipeline as Code

Pipelines themselves should be version-controlled, not clicked together in a Jenkins UI. Two common formats:

**Jenkinsfile (declarative):**

```groovy
pipeline {
    agent { docker { image 'my-ace-build-agent:12.0' } }
    stages {
        stage('Build') {
            steps { sh 'ibmint package --input-path . --output-bar-file app.bar --application MyApp' }
        }
        stage('Test') {
            steps { sh './run-flow-tests.sh app.bar' }
        }
        stage('Deploy Dev') {
            steps { sh './deploy.sh app.bar dev-overrides.properties dev-integration-server' }
        }
    }
}
```

**GitLab CI (`.gitlab-ci.yml`):**

```yaml
stages: [build, test, deploy-dev, deploy-test, deploy-prod]

build:
  stage: build
  script:
    - ibmint package --input-path . --output-bar-file app.bar --application MyApp
  artifacts:
    paths: [app.bar]

deploy-dev:
  stage: deploy-dev
  script:
    - ./deploy.sh app.bar overrides/dev.properties
  environment: dev
```

Note the `artifacts:` block in GitLab CI — this is what enforces "build once": the exact `app.bar` produced in the `build` job is passed forward to every later stage, never rebuilt.

---

## Hands-on Lab

### Exercise 1 — Build a Minimal Bash Pipeline Runner

This simulates pipeline stage logic without requiring a full Jenkins/GitLab install, so you can internalize the _mechanics_ — gating, artifact-passing, fail-fast — before wiring a real CI tool to it.

```bash
mkdir -p ~/mw-pipeline/{src,artifacts,overrides}
cd ~/mw-pipeline

cat > pipeline.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

STAGE_LOG="pipeline.log"
: > "$STAGE_LOG"

run_stage () {
  local name="$1"; shift
  echo "=== STAGE: $name ===" | tee -a "$STAGE_LOG"
  if "$@" >> "$STAGE_LOG" 2>&1; then
    echo "  -> PASSED"
  else
    echo "  -> FAILED (see $STAGE_LOG)"
    exit 1
  fi
}

build ()   { echo "Building artifact..."; echo "app-v1.0" > artifacts/app.bar; }
test_it () { echo "Running flow tests..."; [ -f artifacts/app.bar ]; }
deploy ()  { echo "Deploying $1 to $2..."; cp artifacts/app.bar "artifacts/deployed-$2.bar"; }

run_stage "Build"        build
run_stage "Test"         test_it
run_stage "Deploy-Dev"   deploy artifacts/app.bar dev
run_stage "Deploy-Test"  deploy artifacts/app.bar test

echo "Pipeline complete. Artifact promoted unchanged through all stages."
EOF

chmod +x pipeline.sh
./pipeline.sh
```

### Exercise 2 — Prove the "Build Once" Rule with a Checksum Gate

```bash
cat >> pipeline.sh << 'EOF'

echo "=== STAGE: Integrity-Check ==="
ORIG_SUM=$(sha256sum artifacts/app.bar | awk '{print $1}')
DEV_SUM=$(sha256sum artifacts/deployed-dev.bar | awk '{print $1}')
TEST_SUM=$(sha256sum artifacts/deployed-test.bar | awk '{print $1}')

if [ "$ORIG_SUM" == "$DEV_SUM" ] && [ "$DEV_SUM" == "$TEST_SUM" ]; then
  echo "  -> PASSED: identical artifact promoted through every stage"
else
  echo "  -> FAILED: artifact drift detected between environments"
  exit 1
fi
EOF

./pipeline.sh
```

### Exercise 3 — Sketch Your Own `.gitlab-ci.yml`

Using the reference in the theory section, write a `.gitlab-ci.yml` for a fictional `OrderProcessing` ACE application with four stages: `build`, `flow-test`, `deploy-dev`, `deploy-uat`. Do not implement the scripts yet — just get the stage/dependency graph correct. You'll wire real `ibmint` commands into it on Day 42.

---

## Validation

- [ ] `./pipeline.sh` runs end-to-end and prints "Pipeline complete."
- [ ] The Integrity-Check stage passes, proving the same artifact hash reached every environment.
- [ ] You can explain, in one sentence, why baking a Dev database URL directly into a `.msgflow` breaks the pipeline you just built.
- [ ] Your draft `.gitlab-ci.yml` has an explicit `artifacts:` block on the build stage.

---

## Key Takeaways

- CI/CD for middleware differs from apps mainly because of **stateful runtimes** (MQ) and **name-bound configuration** (ACE configurable services).
- Most integration teams run **Continuous Delivery**, with a manual gate before Prod — full Continuous Deployment is rare for regulated systems.
- The non-negotiable rule: **build once, promote the binary**, changing only environment-specific overrides between stages.
- Pipelines belong in version control (Jenkinsfile, `.gitlab-ci.yml`) just like the flows they build.

---

**← Index:** [[00 Integration DevOps Index]] | **Next:** [[Day-42-Automating-ACE-BAR-Builds-via-CLI]] →
