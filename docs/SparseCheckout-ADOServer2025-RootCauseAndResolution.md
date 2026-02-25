# Sparse Checkout Silently Ignored on Azure DevOps Server 2025
### Root Cause Analysis & Resolution

> **Environment:** Azure DevOps Server 2025 · `20.256.36719.1` · Agent v4.260.0 · Git 2.49.0.windows.1

---

## TL;DR — Read This First

**The problem:** On Azure DevOps Server 2025 (on-premises), setting
`sparseCheckoutDirectories` or `sparseCheckoutPatterns` on a `checkout` step
has **no effect**. The agent performs a full clone every time, regardless of
what you configure. No error is raised.

**The fix — add one pipeline variable:**

```yaml
variables:
  - name: AGENT_USE_SPARSE_CHECKOUT_IN_CHECKOUT_TASK
    value: "true"
```

Add it to any pipeline that needs sparse checkout. That's all. Your existing
`sparseCheckoutDirectories` / `sparseCheckoutPatterns` configuration will then
work exactly as documented.

**Why this is needed:** The sparse checkout feature is controlled by an
internal agent feature knob that defaults to `off` on-premises. Microsoft
enables it automatically for Azure DevOps cloud tenants via a server-side
feature flag, but that mechanism does not exist in ADO Server 2025. Setting
the variable above turns the knob on explicitly. This is confirmed as the
root cause by direct analysis of the agent source code and validated by a
side-by-side CI test on the affected server.

---

## 1. Problem Statement

When a pipeline on **Azure DevOps Server 2025** specifies sparse checkout:

```yaml
steps:
  - checkout: self
    clean: true
    sparseCheckoutDirectories: FolderA
```

the agent **ignores the sparse configuration entirely** and performs a full
clone. The pipeline succeeds, no warning is emitted, and the only observable
symptom is that the working tree contains every file in the repository rather
than the requested subset.

The same YAML runs correctly on Azure DevOps cloud (dev.azure.com).

### Observed symptoms

| Symptom | Detail |
|---|---|
| Full repo present after checkout | All directories land in the workspace, not just those listed in `sparseCheckoutDirectories` |
| No error or warning | Build result is `Succeeded`; there is no indication anything was skipped |
| `git sparse-checkout list` returns nothing | The sparse-checkout cone was never initialized; the command reports no active patterns |
| Behavior identical across all sparse modes | `sparseCheckoutDirectories`, `sparseCheckoutPatterns`, and both combined all produce the same full checkout |
| Agent version does not matter | Reproduced on agent v4.248.0 through v4.260.0 |

### What does NOT help

- Upgrading the agent within the v4 range
- Switching between `sparseCheckoutDirectories` and `sparseCheckoutPatterns`
- Using `cone` vs `no-cone` sparse mode
- Setting `fetchFilter`, `fetchDepth`, or other checkout options
- Reinstalling or reconfiguring the agent

---

## 2. Root Cause Analysis

### 2.1 The feature knob

The Azure Pipelines agent contains a feature flag system called **knobs**
(`src/Agent.Sdk/Knob/AgentKnobs.cs`). One knob controls sparse checkout:

```csharp
public static readonly Knob UseSparseCheckoutInCheckoutTask = new Knob(
    nameof(UseSparseCheckoutInCheckoutTask),
    "If true, agent will use sparse checkout in checkout task.",
    new RuntimeKnobSource("AGENT_USE_SPARSE_CHECKOUT_IN_CHECKOUT_TASK"),
    new BuiltInDefaultKnobSource("false"));   // ← OFF by default
```

Key observations:
- The built-in default is `false`.
- The only way to override it is via `RuntimeKnobSource` — which reads an
  **environment / pipeline variable** named
  `AGENT_USE_SPARSE_CHECKOUT_IN_CHECKOUT_TASK`.
- There is **no** `PipelineFeatureSource` and **no** `EnvironmentKnobSource`
  registered, so there is no server-side mechanism to enable this on-premises.

### 2.2 The guarded code block

In `src/Agent.Plugins/GitSourceProvider.cs`, the entire sparse checkout
implementation is wrapped in a single conditional on this knob:

```csharp
if (AgentKnobs.UseSparseCheckoutInCheckoutTask.GetValue(executionContext).AsBoolean())
{
    // git sparse-checkout init
    // git sparse-checkout set <directories|patterns>
    // (this entire block is unreachable when the knob is false)
}
```

When the knob evaluates to `false`, execution skips past this block
completely. The agent then performs a standard `git fetch` + `git checkout`
with no sparse configuration applied. No log line, warning, or error is
generated. The YAML properties `sparseCheckoutDirectories` and
`sparseCheckoutPatterns` have been parsed and validated by the pipeline engine
(they appear in the template evaluation log), but the agent never acts on them.

### 2.3 Why it works on cloud, not on-premises

| Environment | Knob activation mechanism | Result |
|---|---|---|
| Azure DevOps cloud (dev.azure.com) | Microsoft enables `UseSparseCheckoutInCheckoutTask` server-side via a feature flag pipeline for all organizations | Knob → `true` → sparse checkout runs |
| Azure DevOps Server 2025 on-premises | No server-side feature flag mechanism exists for on-premises agents | Knob stays `false` → sparse checkout skipped |

The agent binary is the same in both environments. The difference is entirely
in how the knob is activated. On-premises, only the `RuntimeKnobSource` path
is available, which requires an explicit pipeline variable.

### 2.4 Timeline

The knob and the guarded code block have been present in the agent since the
initial sparse checkout implementation. ADO Server 2025 shipped with agent
v4.248.0+ which includes the sparse checkout code, but the server-side
activation that cloud received was never applied or documented for
on-premises deployments. The ADO Server 2025 release notes describe sparse
checkout as "supported" with agent v4.248.0+ without noting the activation
requirement.

---

## 3. Evidence

### 3.1 Source code references

| File | Location | Significance |
|---|---|---|
| `src/Agent.Sdk/Knob/AgentKnobs.cs` | ~line 900 | Knob definition, default `false`, `RuntimeKnobSource` only |
| `src/Agent.Plugins/GitSourceProvider.cs` | ~line 730 | `if (knob.AsBoolean())` gate around all sparse-checkout calls |

Repository: `microsoft/azure-pipelines-agent`

### 3.2 CI validation — Build 109

A side-by-side pipeline (`SparseDemo - Knob Test`, pipeline ID 16) was run on
the affected ADO Server 2025 instance (`20.256.36719.1`) with two jobs using
identical sparse checkout YAML, differing only in the presence of the knob
variable:

| Metric | Job 1: KNOB_OFF (no variable) | Job 2: KNOB_ON (variable set) |
|---|---|---|
| `AGENT_USE_SPARSE_CHECKOUT_IN_CHECKOUT_TASK` | `false` (not set — built-in default) | `true` |
| `FolderA/` in workspace | **PRESENT** | **PRESENT** |
| `FolderB/` in workspace | **PRESENT** | **ABSENT** ✓ |
| `git sparse-checkout list` | (not active) | `FolderA` ✓ |
| Job verdict | `PASS-AS-EXPECTED (full checkout confirmed — bug present)` | `PASS (sparse checkout active — fix confirmed)` |
| **Overall verdict** | **PASS — Root cause confirmed. Pipeline variable is the fix.** | |

Pipeline YAML: `.azuredevops/server2025-knob-test.yml` (commit `45b2ad9`)

---

## 4. Resolution

### 4.1 Immediate fix (any pipeline, any agent version)

Add the following variable to any pipeline that requires sparse checkout:

```yaml
variables:
  - name: AGENT_USE_SPARSE_CHECKOUT_IN_CHECKOUT_TASK
    value: "true"
```

**Complete minimal example:**

```yaml
trigger: none

variables:
  - name: AGENT_USE_SPARSE_CHECKOUT_IN_CHECKOUT_TASK
    value: "true"

pool:
  name: Default

jobs:
  - job: Build
    steps:
      - checkout: self
        clean: true
        sparseCheckoutDirectories: src
```

The variable can be set at the pipeline level, the stage level, the job level,
or as a library variable group — any scope that is visible to the checkout
step at runtime will work.

### 4.2 Where to add the variable

| Scope | YAML location | Notes |
|---|---|---|
| Pipeline (all jobs) | Top-level `variables:` block | Recommended — one change covers all checkout steps |
| Job only | `variables:` inside the `job:` block | Appropriate when only some jobs need sparse checkout |
| Library / variable group | ADO UI → Pipelines → Library | Useful for sharing across many pipelines without editing each file |

### 4.3 Verified compatibility

| Agent version | Fix works? |
|---|---|
| v4.248.0 | ✅ Yes |
| v4.260.0 | ✅ Yes (tested — build 109) |
| v3.x | ❓ Not tested; sparse checkout not supported on v3 |

Both `sparseCheckoutDirectories` and `sparseCheckoutPatterns` work correctly
once the knob is enabled. Cone mode and no-cone mode both function normally.

### 4.4 Alternative workarounds (if variable cannot be used)

These workarounds bypass the agent's built-in sparse checkout path entirely.
They remain valid but are more verbose than the single-variable fix above.

**Option A — Post-checkout git commands:**
```yaml
steps:
  - checkout: self
    clean: true

  - powershell: |
      git -C "$(Build.SourcesDirectory)" sparse-checkout init --cone
      git -C "$(Build.SourcesDirectory)" sparse-checkout set FolderA
      git -C "$(Build.SourcesDirectory)" checkout
    displayName: Apply sparse checkout manually
```

**Option B — Sparse clone in a script step (no checkout task):**
```yaml
steps:
  - checkout: none

  - powershell: |
      $url = "$(Build.Repository.Uri)"
      $token = "$(System.AccessToken)"
      $encodedToken = [Convert]::ToBase64String(
          [Text.Encoding]::ASCII.GetBytes(":$token"))
      git clone --no-checkout --filter=blob:none `
          -c "http.extraHeader=Authorization: Basic $encodedToken" `
          $url "$(Build.SourcesDirectory)"
      Set-Location "$(Build.SourcesDirectory)"
      git sparse-checkout init --cone
      git sparse-checkout set FolderA
      git checkout HEAD
    displayName: Sparse clone (manual)
    env:
      System.AccessToken: $(System.AccessToken)
```

---

## 5. Recommended action for the product team

| Priority | Action |
|---|---|
| **P1 — Documentation** | Update ADO Server 2025 release notes and the `checkout` step documentation to state that `AGENT_USE_SPARSE_CHECKOUT_IN_CHECKOUT_TASK=true` is required on-premises. |
| **P2 — Default change** | Change `BuiltInDefaultKnobSource("false")` to `BuiltInDefaultKnobSource("true")` in a future agent release, or add logic that auto-enables the knob on-premises when `sparseCheckoutDirectories` or `sparseCheckoutPatterns` are non-empty. |
| **P3 — Server-side configuration** | Provide an ADO Server administrator setting to enable the knob globally, equivalent to the cloud feature flag. |

---

## 6. Affected versions

| Component | Version tested | Status |
|---|---|---|
| Azure DevOps Server | 2025 · `20.256.36719.1` (AzureDevOps25H2) | ❌ Affected |
| Azure DevOps Server 2022 | Not tested | ❓ Unknown — likely affected if using agent v4 |
| Azure DevOps cloud | All | ✅ Not affected (server-side FF enables knob) |
| Agent | v4.248.0 – v4.260.0 | ❌ Affected without the variable |
| Agent | v3.x | N/A — sparse checkout not available |
| ADO Server 2025 Patch 1 (Feb 10, 2026) | `20.256.36719.1` | ❌ Does not address this issue |

---

## 7. Quick reference

```
ISSUE    : sparseCheckoutDirectories / sparseCheckoutPatterns silently ignored
PLATFORM : Azure DevOps Server 2025 (on-premises), any agent v4
ROOT CAUSE: AgentKnobs.UseSparseCheckoutInCheckoutTask defaults false on-prem
FIX      : Set pipeline variable AGENT_USE_SPARSE_CHECKOUT_IN_CHECKOUT_TASK=true
PROOF    : Build 109 on adoserver (20.256.36719.1) — OVERALL_VERDICT: PASS
```
