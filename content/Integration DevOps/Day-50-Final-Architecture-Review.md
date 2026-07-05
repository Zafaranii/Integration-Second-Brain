---
tags: [devops, bucket-4, capstone, review, day-50]
created: 2025-07-05
bucket: 4
week: 10
day: 50
status: not-started
---

# Day 50 — Final 10-Week Architecture Review

> [!info] Why This Day Exists
> Ten weeks ago you started with a TCP handshake. Today you can build a message flow, secure its transport, package it reproducibly, and roll it onto a self-healing cluster. This day has no new commands — it's the synthesis exercise that turns four separate buckets of knowledge into one mental model you can actually use when production is on fire.

**← Index:** [[00 Integration DevOps Index]] | **Previous:** [[Day-49-Pod-Debugging]]

---

## Theory

### The End-to-End Request Lifecycle, Bucket by Bucket

```
Client Request
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│ BUCKET 1 — Networking                                        │
│ TCP handshake, DNS resolution, OpenShift Route/Ingress,       │
│ L4/L7 load balancing decide which pod receives the packet     │
└──────────────────────┬─────────────────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ BUCKET 2 — Security & Transport                               │
│ TLS handshake terminates (at Route, or re-encrypted to pod),   │
│ mutual auth / certs validated before payload is trusted        │
└──────────────────────┬─────────────────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ BUCKET 3 — Core Middleware                                     │
│ ACE integration server processes the message flow;             │
│ MQ persists/queues messages; DataPower may front/mediate it   │
└──────────────────────┬─────────────────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ BUCKET 4 — DevOps & Automation (this module)                  │
│ The BAR running that flow, the MQSC that defined the queue,    │
│ the ConfigMap/Secret feeding it, and the pod it runs in were   │
│ ALL produced by a pipeline and reconciled by GitOps            │
└─────────────────────────────────────────────────────────────┘
```

The insight worth internalizing: **Bucket 4 doesn't sit "after" the others — it's the substrate underneath all of them.** Every queue manager in Bucket 3's labs, every TLS certificate in Bucket 2, every Route in Bucket 1, could itself have been deployed and is now running via the exact mechanisms from this bucket (ConfigMaps, Secrets, GitOps reconciliation).

---

### Consolidated Decision Tree — All Four Buckets

```
Something is broken. Where do you look first?
│
├── "Connection refused / timed out / RST"
│     → Bucket 1: check ss/netstat, firewall, routing
│
├── "SSL handshake failed / certificate invalid"
│     → Bucket 2: check cert chain, expiry, cipher mismatch
│
├── Message flow throws an exception, or a queue depth is climbing
│     → Bucket 3: check ACE flow logs, MQ channel status, DLQ contents
│
├── Deployment won't roll out, pod crash-looping, config not applying
│     → Bucket 4: oc describe pod → logs --previous → check
│       ConfigMap/Secret refs → verify GitOps sync status
│
└── "It works in Dev but not in Prod"
      → Almost always Bucket 4: check whether the SAME artifact
        (BAR/image) was promoted, and whether overrides/ConfigMaps/
        Secrets for Prod are actually correct — this is the #1
        real-world failure mode across the entire 10 weeks
```

---

### The Single Idea That Ties All 10 Weeks Together

> [!important] Build Once. Declare Everything. Trust Nothing You Can't Prove.
>
> - **Build once** (Day 41–43): one BAR, one image, promoted unchanged — proven with a checksum, not an assumption.
> - **Declare everything** (Day 44–47): queues, channels, ConfigMaps, Deployments exist as text in Git, not as someone's memory of a `runmqsc` session.
> - **Trust nothing you can't prove**: every day in this bucket ended with a Validation section for a reason. "It should work" and "I confirmed it works" are different claims, and only one of them survives an incident review.

---

## Hands-on Lab — Capstone Scenario

### Scenario Setup

You've inherited an integration: `OrderProcessing`. Reported symptom: **"Orders submitted through the API aren't reaching the fulfillment queue, and it was working yesterday."**

Work through the full stack using only the tools from the last 10 weeks. Treat each step as a real diagnostic action against your own lab environment (or, if a live cluster/QM isn't available in this session, write out the exact command you would run and what output would confirm/rule out each layer).

### Step 1 — Bucket 1: Is the Request Even Arriving?

```bash
oc get route order-processing -n integration-prod
curl -v https://order-processing-integration-prod.apps.mycluster.com/orders
ss -tn | grep :443
```

Rule out: DNS resolution failure, Route misconfiguration, connection-level drop.

### Step 2 — Bucket 2: Is TLS Terminating Correctly?

```bash
openssl s_client -connect order-processing-integration-prod.apps.mycluster.com:443 -servername order-processing-integration-prod.apps.mycluster.com < /dev/null | grep -A2 "Verify return code"
oc get secret order-processing-tls -n integration-prod -o yaml | grep -i "not after\|notAfter" 2>/dev/null || \
  oc get secret order-processing-tls -n integration-prod -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -enddate
```

Rule out: expired cert, cipher mismatch, wrong SNI routing.

### Step 3 — Bucket 3: Is the Flow Processing the Message?

```bash
POD=$(oc get pods -n integration-prod -l app=order-processing -o jsonpath='{.items[0].metadata.name}')
oc logs "$POD" -n integration-prod --tail=100
oc exec -it "$POD" -n integration-prod -- bash -c 'echo "DISPLAY QLOCAL(ORDERS.OUT) CURDEPTH" | runmqsc QM1'
oc exec -it "$POD" -n integration-prod -- bash -c 'echo "DISPLAY QLOCAL(ORDERS.DLQ) CURDEPTH" | runmqsc QM1'
```

Rule out: flow exception, message landing on the DLQ instead of `ORDERS.OUT`.

### Step 4 — Bucket 4: Was Yesterday's Working State Actually Today's Deployed State?

This is where most "it worked yesterday" incidents actually resolve:

```bash
# What does Git say SHOULD be running?
git log --oneline -5 -- overlays/prod/

# What is ArgoCD's view of sync status?
argocd app get order-processing-prod

# Is there drift?
argocd app diff order-processing-prod

# What BAR/image is actually running vs what's declared?
oc get deployment order-processing -n integration-prod -o jsonpath='{.spec.template.spec.containers[0].image}'

# Was the override/ConfigMap for prod changed recently without a corresponding pipeline run?
oc get configmap order-processing-overrides -n integration-prod -o yaml
```

### Step 5 — Synthesize the Root Cause

Write a one-paragraph incident summary answering:

1. Which bucket/layer was the actual root cause?
2. Which single Validation check (from any of the 50 days) would have caught this _before_ it reached Prod?
3. What pipeline or GitOps change (Day 41–48) would prevent this exact failure from recurring?

---

## Validation

- [ ] You worked through all four diagnostic steps in order, ruling layers out rather than guessing.
- [ ] Your Step 5 summary names one specific, concrete Validation check from an earlier day (not a vague "should test more") that would have caught the regression pre-Prod.
- [ ] Your proposed pipeline/GitOps fix references a real mechanism from this bucket (checksum gate, `selfHeal`, immutable ConfigMap versioning, etc.) — not a generic "be more careful."
- [ ] You can now redraw, from memory, the four-bucket request lifecycle diagram from the theory section.

---

## Key Takeaways — The Whole 10 Weeks in Four Lines

- **Bucket 1** taught you that the network is not abstract — it's sockets, states, and timeouts you can observe directly.
- **Bucket 2** taught you that trust must be established and verified, not assumed, before data moves.
- **Bucket 3** taught you the actual mechanics of the middleware doing the integration work.
- **Bucket 4** taught you that none of the above matters if you can't reproduce, promote, and prove it — reliably, the same way, every time.

> [!info] Course Complete
> This closes the 10-week curriculum. The next natural step is to run this capstone scenario for real against your own lab cluster, then pick one real production incident from your own history and re-diagnose it using this same four-step method.

---

**← Index:** [[00 Integration DevOps Index]] | **Previous:** [[Day-49-Pod-Debugging]]
