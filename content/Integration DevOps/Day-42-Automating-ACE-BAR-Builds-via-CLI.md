---
tags: [devops, bucket-4, ace, bar, cli, day-42]
created: 2025-07-05
bucket: 4
week: 9
day: 42
status: not-started
---

# Day 42 — Automating ACE BAR Builds via CLI

> [!info] Why This Day Exists
> Clicking "Export BAR" in the ACE Toolkit does not scale, is not repeatable, and cannot run at 2 AM when a pipeline triggers. Everything the Toolkit does under the hood is exposed as a CLI command — `ibmint` (ACE 11+) or the legacy `mqsicreatebar`. Automating this is the single highest-leverage skill for middleware CI/CD.

**← Index:** [[00 Integration DevOps Index]] | **Previous:** [[Day-41-CICD-Concepts-for-Middleware]] || **Next:** [[Day-43-ACE-BAR-Overrides-and-Environment-Config]] →

---

## Theory

### What a BAR File Actually Is

A `.bar` file is a **zip archive** with a specific internal layout:

```
MyApp.bar
├── META-INF/
│   └── broker.xml          # application descriptor, deploy metadata
├── MyApp/
│   ├── MyFlow.msgflow      # compiled message flow (binary .cmf inside)
│   ├── MyMap.msgflow.map   # ESQL/mapping compiled artifacts
│   └── MyLib/               # referenced shared libraries
└── overrides.descriptor     # default override property definitions
```

You can prove this right now:

```bash
cp MyApp.bar MyApp.zip
unzip -l MyApp.zip
```

The important consequence: **a BAR is a container of compiled artifacts plus a manifest of default properties**, not a snapshot of environment values. Nothing environment-specific should be baked in at build time.

---

### `ibmint` vs `mqsicreatebar`

| Aspect                | `mqsicreatebar` (legacy, IIB/ACE ≤10)                | `ibmint` (ACE 11+)                               |
| --------------------- | ---------------------------------------------------- | ------------------------------------------------ |
| Mechanism             | Headless Eclipse instance                            | Native Java CLI, no Eclipse workspace needed     |
| Speed                 | Slow — full Eclipse bootstrap per invocation         | Fast, purpose-built                              |
| Workspace requirement | Requires an Eclipse `-data` workspace directory      | Works directly against a project folder          |
| Status                | Deprecated, still present for backward compatibility | Current standard — use this for anything ACE 11+ |

> [!warning] Pin Your Toolkit Version in CI
> `ibmint`'s compiled output is not guaranteed byte-identical across ACE fix pack versions. Your CI build agent image **must** pin an exact ACE version (e.g., `12.0.9.0`), matching what's installed on the target integration servers. A pipeline that silently picks up "latest" ACE in its build container is a production incident waiting to happen.

---

### Core `ibmint` Commands

| Command          | Purpose                                                                                                                                                                                 |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ibmint package` | Compiles a project folder into a `.bar`                                                                                                                                                 |
| `ibmint compile` | Compiles a project without packaging (useful for a fast "does it build" CI gate)                                                                                                        |
| `ibmint list`    | Lists installed integration runtimes/registries                                                                                                                                         |
| `ibmint deploy`  | Deploys a BAR straight to a running integration server (bypasses BAR-file promotion — generally **not** used in strict "build once, promote" pipelines; prefer explicit deploy scripts) |

**Basic package syntax:**

```bash
ibmint package \
  --input-path ./MyApp \
  --output-bar-file ./build/MyApp.bar \
  --application MyApp
```

**Packaging multiple applications + shared libraries into one BAR:**

```bash
ibmint package \
  --input-path ./workspace \
  --output-bar-file ./build/AllApps.bar \
  --application OrderProcessing \
  --application PaymentGateway \
  --library CommonUtils
```

**Compile-only fast-fail CI gate (no packaging cost):**

```bash
ibmint compile --input-path ./MyApp --clean
echo "Exit code: $?"   # non-zero = compile error, fail the pipeline immediately
```

---

### Legacy `mqsicreatebar` Syntax (for reference — older environments)

```bash
mqsicreatebar \
  -data /home/build/workspace \
  -b ./build/MyApp.bar \
  -a MyApp \
  -cleanBuild
```

| Flag          | Meaning                                                                                                                                  |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `-data`       | Path to the Eclipse workspace directory                                                                                                  |
| `-b`          | Output BAR file path                                                                                                                     |
| `-a`          | Application name to include                                                                                                              |
| `-cleanBuild` | Forces a full rebuild, ignoring incremental compile cache — always use this in CI, never trust incremental state on a shared build agent |

---

## Hands-on Lab

### Exercise 1 — Stand Up an ACE Build Agent Container

```bash
# Pull the official ACE image (adjust tag to your pinned version)
docker pull icr.io/appconnect/ace:12.0

# Run it as an interactive build shell, mounting a local workspace
mkdir -p ~/mw-pipeline/workspace/MyApp
docker run -it --rm \
  -v ~/mw-pipeline/workspace:/workspace \
  icr.io/appconnect/ace:12.0 bash
```

> [!tip] Why containerize the build agent at all?
> This is the same reasoning as pinning ACE version above: a container image _is_ the pin. Every pipeline run gets the identical ACE toolkit binary, OS libraries, and JDK — eliminating "works on my machine" entirely from the build stage.

### Exercise 2 — Scaffold a Minimal Application Project

Inside the container (or locally if ACE toolkit CLI is installed):

```bash
cd /workspace
ibmint create application --name MyApp
cd MyApp
ls -la
# Expect: application.descriptor, a default .msgflow may need to be added
```

If you don't have a flow yet, copy in any exported `.msgflow` from your Toolkit workspace, or use a flow from Bucket 3's labs.

### Exercise 3 — Package It via CLI

```bash
ibmint package \
  --input-path /workspace/MyApp \
  --output-bar-file /workspace/build/MyApp.bar \
  --application MyApp

echo "Exit code: $?"
ls -la /workspace/build/
```

### Exercise 4 — Inspect the Output Like a Zip File

```bash
cd /workspace/build
cp MyApp.bar MyApp.zip
unzip -l MyApp.zip
```

Confirm you see `META-INF/broker.xml` and your compiled flow artifact.

### Exercise 5 — Wire It Into the Pipeline Script from Day 41

```bash
cd ~/mw-pipeline
cat > build.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
docker run --rm \
  -v "$(pwd)/workspace:/workspace" \
  icr.io/appconnect/ace:12.0 \
  ibmint package \
    --input-path /workspace/MyApp \
    --output-bar-file /workspace/build/MyApp.bar \
    --application MyApp
EOF
chmod +x build.sh
./build.sh
```

Replace the fake `build ()` function from Day 41's `pipeline.sh` with a call to `./build.sh`, so your pipeline now produces a **real** BAR file instead of a placeholder string.

---

## Validation

- [ ] `unzip -l MyApp.bar` shows `META-INF/broker.xml` and your compiled flow.
- [ ] Running the packaging command twice with `--clean`/fresh containers produces BAR files of the same size (proves determinism given a pinned image).
- [ ] `ibmint compile --input-path ./MyApp` returns a non-zero exit code when you intentionally introduce an ESQL syntax error — confirming your CI compile-gate actually fails builds.
- [ ] `pipeline.sh` from Day 41 now calls `build.sh` and produces a real `MyApp.bar` in the `artifacts/` (or `build/`) directory.

---

## Key Takeaways

- A BAR is a zip container of compiled flow artifacts plus a default-override manifest — never a place to bake in environment values.
- `ibmint` is the current standard CLI; `mqsicreatebar` is legacy but still found in older estates.
- Containerizing the build agent and pinning the exact ACE version is what makes the build **reproducible** — a prerequisite for trusting any pipeline result.
- `ibmint compile` (no packaging) is a cheap, fast fail-gate to run on every commit before investing in a full package step.

---

**← Index:** [[00 Integration DevOps Index]] | **Previous:** [[Day-41-CICD-Concepts-for-Middleware]] || **Next:** [[Day-43-ACE-BAR-Overrides-and-Environment-Config]] →
