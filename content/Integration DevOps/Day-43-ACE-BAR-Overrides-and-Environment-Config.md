---
tags: [devops, bucket-4, ace, bar, overrides, day-43]
created: 2025-07-05
bucket: 4
week: 9
day: 43
status: not-started
---

# Day 43 — ACE BAR Overrides & Environment-Specific Configuration

> [!info] Why This Day Exists
> Day 42 built a BAR. But a BAR built with Dev's database name inside it cannot legally be called "the same artifact" once you change that name for Test. This day covers the exact mechanism — **override properties** — that lets one immutable BAR run correctly in Dev, Test, and Prod without ever being rebuilt.

**← Index:** [[00 Integration DevOps Index]] | **Previous:** [[Day-42-Automating-ACE-BAR-Builds-via-CLI]] | **Next:** [[Day-44-MQ-Docker-Containers-Setup]] →

---

## Theory

### Two Different Things People Confuse

| Mechanism                            | What it changes                                                                                                                                                                              | When applied                                                             |
| ------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| **Override properties**              | Values _inside_ the BAR's resources (e.g., an HTTP node's URL, a JDBC pool's connection string, an MQ node's queue manager name)                                                             | Applied to the BAR file itself, or at deploy time via the deploy command |
| **Configurable services / policies** | Named, server-side definitions (e.g., a policy called `JDBC_ORDERS_DB`) that flows reference _by name_ — the actual connection details live on the integration server, not in the BAR at all | Set once per integration server/environment, independent of any BAR      |

**Best practice:** use configurable services for anything that needs credentials or infrastructure endpoints (databases, MQ queue managers, HTTP hosts). Use override properties for the smaller set of values that must vary but don't belong in a server-side policy (e.g., a feature-flag flow property).

> [!important] Why This Split Exists
> If every environment value were an override property, your Prod pipeline would need Prod credentials sitting in a properties file inside your CI system — a serious security anti-pattern. Configurable services let the _server_ hold environment secrets locally, while the _pipeline_ only ever handles a BAR and a small, non-secret override file (Day 48 covers pushing genuinely secret values via Kubernetes Secrets instead).

---

### Discovering What's Overridable — `mqsireadbar`

Every resource in a BAR that supports overriding exposes a property. You don't have to guess these — extract them:

```bash
mqsireadbar -b MyApp.bar -p -o defaults.properties
cat defaults.properties
```

Typical output:

```properties
MyApp#OrderFlow.msgflow#HTTPInput.URLSpecifier=/orders
MyApp#OrderFlow.msgflow#MQOutput.destinationQueueName=DEV.ORDERS.OUT
MyApp#OrderFlow.msgflow#Compute.dataSource=DEV_ORDERS_DS
```

The format is always: `<application>#<flow-or-resource-path>#<node-name>.<property-name>=<value>`.

---

### Building an Environment-Specific Override File

You copy `defaults.properties`, rename per environment, and only change the lines that differ:

**`overrides/dev.properties`:**

```properties
MyApp#OrderFlow.msgflow#MQOutput.destinationQueueName=DEV.ORDERS.OUT
```

**`overrides/prod.properties`:**

```properties
MyApp#OrderFlow.msgflow#MQOutput.destinationQueueName=PROD.ORDERS.OUT
```

Note: you don't need to repeat properties that don't change — only include the deltas relevant to each environment (though many teams keep the full file per environment for auditability; either approach is valid, pick one and be consistent).

---

### Applying the Override — `mqsiapplybaroverride`

```bash
mqsiapplybaroverride \
  -b MyApp.bar \
  -k MyApp \
  -p overrides/prod.properties
```

| Flag | Meaning                                                              |
| ---- | -------------------------------------------------------------------- |
| `-b` | The BAR file to modify **in place**                                  |
| `-k` | Application (or library) name inside the BAR the override applies to |
| `-p` | Path to the properties file with the override values                 |

> [!warning] "In Place" Means In Place
> `mqsiapplybaroverride` modifies the given BAR file directly. If your pipeline needs to produce three different deployable artifacts (Dev/Test/Prod) from the same build, **copy the original BAR first**, then apply a different override to each copy. Never apply overrides to your one canonical build artifact and lose the pristine original.

```bash
cp MyApp.bar deploy/MyApp-dev.bar
cp MyApp.bar deploy/MyApp-test.bar
cp MyApp.bar deploy/MyApp-prod.bar

mqsiapplybaroverride -b deploy/MyApp-dev.bar   -k MyApp -p overrides/dev.properties
mqsiapplybaroverride -b deploy/MyApp-test.bar  -k MyApp -p overrides/test.properties
mqsiapplybaroverride -b deploy/MyApp-prod.bar  -k MyApp -p overrides/prod.properties
```

This gives you three artifacts that are byte-different only in the override section, but share identical compiled flow logic — satisfying "build once" while still allowing per-environment values.

---

## Hands-on Lab

### Exercise 1 — Extract Default Overrides From Your Day 42 BAR

```bash
cd ~/mw-pipeline/workspace/build
mqsireadbar -b MyApp.bar -p -o defaults.properties
cat defaults.properties
```

If `mqsireadbar` reports no overridable properties, add an HTTP Input node URL or an MQ Output node queue name property to your test flow in the ACE Toolkit, re-export, rebuild via Day 42's `ibmint package`, and retry.

### Exercise 2 — Create Three Environment Override Files

```bash
mkdir -p ~/mw-pipeline/overrides
cd ~/mw-pipeline/overrides

cp ../workspace/build/defaults.properties dev.properties
cp ../workspace/build/defaults.properties test.properties
cp ../workspace/build/defaults.properties prod.properties

# Edit each to point at environment-appropriate queue names, e.g.:
sed -i 's/DEV\./TEST./' test.properties
sed -i 's/DEV\./PROD./' prod.properties

diff dev.properties prod.properties
```

### Exercise 3 — Produce Three Deployable Artifacts From One Build

```bash
cd ~/mw-pipeline
mkdir -p deploy
cp workspace/build/MyApp.bar deploy/MyApp-dev.bar
cp workspace/build/MyApp.bar deploy/MyApp-test.bar
cp workspace/build/MyApp.bar deploy/MyApp-prod.bar

mqsiapplybaroverride -b deploy/MyApp-dev.bar  -k MyApp -p overrides/dev.properties
mqsiapplybaroverride -b deploy/MyApp-test.bar -k MyApp -p overrides/test.properties
mqsiapplybaroverride -b deploy/MyApp-prod.bar -k MyApp -p overrides/prod.properties
```

### Exercise 4 — Prove the Flow Logic Is Identical Across All Three

```bash
cd deploy
for f in MyApp-dev.bar MyApp-test.bar MyApp-prod.bar; do
  cp "$f" "${f%.bar}.zip"
  unzip -p "${f%.bar}.zip" "MyApp/OrderFlow.msgflow" | sha256sum
done
```

The compiled flow artifact hash should be **identical** across all three — only the override manifest differs. This is the concrete, provable version of "build once, promote many."

---

## Validation

- [ ] `defaults.properties` was successfully extracted and contains at least one overridable property.
- [ ] `diff dev.properties prod.properties` shows only the expected environment-specific lines changed.
- [ ] Three BAR files exist in `deploy/`, each successfully overridden without error.
- [ ] The compiled flow artifact hash (Exercise 4) matches across all three BARs, proving the override mechanism never touched compiled logic.

---

## Key Takeaways

- **Override properties** change values inside a BAR; **configurable services** are server-side named resources — use configurable services for anything credential-bearing.
- `mqsireadbar -p -o` discovers exactly what's overridable in a given BAR — don't guess property names by hand.
- `mqsiapplybaroverride` modifies BARs **in place** — always copy the pristine build artifact before applying per-environment overrides.
- You can cryptographically prove "build once, promote many" by hashing the compiled flow artifact inside each environment's final BAR.

---

**← Index:** [[00 Integration DevOps Index]] | **Previous:** [[Day-42-Automating-ACE-BAR-Builds-via-CLI]] | **Next:** [[Day-44-MQ-Docker-Containers-Setup]] →
