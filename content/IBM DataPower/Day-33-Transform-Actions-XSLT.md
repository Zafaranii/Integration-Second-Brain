---
tags: [datapower, bucket-3, processing-policy, xslt, day-33]
created: 2026-07-05
bucket: 3
week: 7
day: 33
status: not-started
---

# Day 33 — Transform Actions: XSLT

> [!info] Why This Day Exists
> XSLT predates GatewayScript as DataPower's transformation mechanism and remains dominant in legacy SOAP/XML estates. You need to read and write it competently even if GatewayScript is your default for new work — most production DataPower configs you'll inherit are XSLT-heavy.

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-34-Error-Handling-and-Error-Rules]] →

---

## Theory

### Why XSLT Still Matters Here

DataPower's XSLT engine is a standards-based W3C implementation (XSLT 1.0 broadly, with XSLT 3.0/XQuery support on newer firmware) plus a set of **`dp:` extension functions** unique to DataPower for accessing transaction context, variables, and appliance-specific behavior that plain XSLT has no concept of.

### Transform Action Wiring

A Transform action of type `xslt` (or the class-level `Type` equivalent, depending on firmware/schema version) references a stylesheet file, typically under `local:///xslt/`. The stylesheet receives the parsed input message as its context document.

### Key `dp:` Extension Functions

| Function                                      | Purpose                                                                                                    |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `dp:variable('var://context/...')`            | Read a DataPower context variable                                                                          |
| `dp:set-variable('var://context/...', value)` | Set a DataPower context variable (e.g., for the routing URL, or to pass data to a later action)            |
| `dp:reject(message)`                          | Explicitly reject the transaction with a custom message, functionally similar to throwing in GatewayScript |
| `dp:url-decode()` / `dp:url-encode()`         | URL encode/decode helpers                                                                                  |

> [!warning] `dp:` Functions Are Not Portable XSLT
> A stylesheet using `dp:` extension functions is **not** a generic, vendor-neutral XSLT — it will not run correctly (or at all) outside DataPower. This matters if you're asked to "just run this transform in a regular XSLT processor for testing" — you can't, without stubbing the `dp:` namespace.

### XSLT vs GatewayScript — When Each Wins

| Criterion                        | XSLT                            | GatewayScript                                    |
| -------------------------------- | ------------------------------- | ------------------------------------------------ |
| Payload shape                    | XML-native                      | JSON-native (and XML, less ergonomically)        |
| Legacy SOAP estates              | Dominant, mature tooling        | Less common historically                         |
| Complex XML-to-XML restructuring | Strong (templates, XPath)       | Workable but more verbose                        |
| JSON manipulation                | Awkward (requires XML bridging) | Native                                           |
| Team skill availability          | Declining in some shops         | Generally more available (JS-literate engineers) |

---

## Your Stack, Concretely

| Scenario                                                                     | DataPower reality                                                                    |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Legacy SOAP-to-SOAP field mapping between partner schema and internal schema | XSLT Transform action, standard template-matching against both schemas               |
| Reading a custom HTTP header to drive conditional logic in a transform       | `dp:variable('var://service/header/X-Custom-Header')` inside the stylesheet          |
| A transform needs to reject a message with a specific error code/message     | `dp:reject()` call inside the XSLT, functionally paralleling a GatewayScript `throw` |

---

## Hands-on

### Exercise 1 — Read a Field-Mapping XSLT

```xml
<xsl:stylesheet version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:dp="http://www.datapower.com/extensions"
    extension-element-prefixes="dp">

  <xsl:template match="/PartnerOrder">
    <InternalOrder>
      <OrderId><xsl:value-of select="@id"/></OrderId>
      <CustomerRef><xsl:value-of select="Customer/RefNumber"/></CustomerRef>
      <Region>
        <xsl:value-of select="dp:variable('var://service/header/X-Region')"/>
      </Region>
    </InternalOrder>
  </xsl:template>

</xsl:stylesheet>
```

Answer: which line in this stylesheet makes it non-portable outside DataPower, and why would this transform fail silently (or error) if run in a plain `xsltproc`/Saxon environment without modification?

### Exercise 2 — Write an Export Fragment Wiring the XSLT Into a Rule

```xml
<StylePolicyRule name="PartnerOrderTransformRule">
  <Action class="StylePolicyAction">
    <Type>xform</Type>
    <StylesheetFile>local:///xslt/partner-order-to-internal.xsl</StylesheetFile>
  </Action>
</StylePolicyRule>
```

### Exercise 3 — Rejection Pattern in XSLT

Write a stylesheet fragment that checks for a required attribute `@id` on `/PartnerOrder` and calls `dp:reject()` with a descriptive message if it's absent — the XSLT-world equivalent of Day 32's GatewayScript `throw new Error(...)` validation pattern.

```xml
<xsl:template match="/PartnerOrder">
  <xsl:choose>
    <xsl:when test="not(@id)">
      <xsl:value-of select="dp:reject('Missing required attribute: id')"/>
    </xsl:when>
    <xsl:otherwise>
      <InternalOrder>
        <OrderId><xsl:value-of select="@id"/></OrderId>
      </InternalOrder>
    </xsl:otherwise>
  </xsl:choose>
</xsl:template>
```

---

## Validation

- [ ] You identified the `dp:variable(...)` call as the non-portable line, and can explain that the `dp:` namespace has no meaning to a generic XSLT processor.
- [ ] You can state, in one sentence, when you'd reach for XSLT over GatewayScript for a new transform (XML-heavy legacy SOAP estate vs. JSON-native REST).
- [ ] Your Exercise 3 fragment mirrors the same validate-then-reject shape as Day 32's GatewayScript exercise — confirm you can articulate the two mechanisms (`dp:reject()` vs `throw`) as functionally parallel but syntactically distinct.

---

## Key Takeaways

- DataPower XSLT is standards-based W3C XSLT plus proprietary `dp:` extension functions — the extensions are what make it DataPower-specific and non-portable.
- XSLT remains the dominant transform mechanism in legacy SOAP/XML estates; GatewayScript is the modern default for JSON/REST.
- `dp:reject()` and GatewayScript's `throw` are functionally parallel rejection mechanisms — same concept, different syntax, both surfaced to the error rule (Day 34).
- Reading and maintaining existing XSLT is a required skill even if you write new transforms in GatewayScript going forward.

---

**← Index:** [[00 IBM DataPower Index]] | **Next:** [[Day-34-Error-Handling-and-Error-Rules]] →
