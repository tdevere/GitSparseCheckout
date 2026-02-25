# Learning Module: Azure DevOps Sparse Checkout

**Audience:** Azure DevOps Support Engineers (L1–L3)  
**Estimated time:** 20 minutes  
**Related docs:** `SparseCheckout-ADOServer2025-RootCauseAndResolution.md`, `SparseCheckout-TechnicalSupportDocument.md`

---

## Learning Objectives

1. Predict what files appear in a workspace for a given `sparseCheckoutDirectories` or `sparseCheckoutPatterns` configuration.
2. Read `##[command]git sparse-checkout` log lines to determine which mode ran and what it applied.
3. Diagnose a `partiallySucceeded` build caused by sparse checkout excluding a required file.
4. Explain why sparse checkout is silently ignored on ADO Server 2025 and state the one-line fix.

---

## Pre-Test

> Answer before reading. Record your answers — compare to post-test at the end.

**P1.** A pipeline running on **Azure DevOps Services (cloud)** uses `sparseCheckoutDirectories: CDN`. The repo has `CDN/`, `FolderA/`, `README.md`, and `config.json` at the root. What will the workspace contain?

- (a) Only `CDN/`
- (b) `CDN/`, `README.md`, and `config.json`
- (c) `CDN/` and `FolderA/`
- (d) Everything — sparse checkout requires a separate enable step

**P2.** On Azure DevOps Server 2025 (on-premises), a pipeline with `sparseCheckoutDirectories: src` performs a full checkout with no error. What is the most likely cause?

- (a) The agent version is too old to support sparse checkout
- (b) An agent feature knob defaults to `false` on-premises; the sparse checkout code block is never reached
- (c) `sparseCheckoutDirectories` is only supported on Azure DevOps cloud
- (d) The `git sparse-checkout` command is missing from the agent machine

**P3.** You see this in a log from a pipeline running on **Azure DevOps Services (cloud)**:

```
##[command]git sparse-checkout init --cone
##[command]git sparse-checkout set app
bash: /home/runner/work/1/s/scripts/deploy.sh: No such file or directory
##[error]Bash exited with code '127'.
```

What caused the failure?

- (a) `deploy.sh` has a syntax error
- (b) `scripts/` was not in the sparse checkout scope and was never copied to the workspace
- (c) The agent does not have execute permission on the script
- (d) Cone mode does not support bash scripts

---

*Record your answers. Proceed to the lessons.*

---

# Lessons

---

## Lesson 1 — Two Properties, Two Modes

Azure DevOps offers two sparse checkout properties:

```yaml
sparseCheckoutDirectories: CDN        # cone mode
sparseCheckoutPatterns: |             # pattern mode
  CDN/**
```

The property you choose determines the git mode. The mode determines whether root-level
files are included. That single difference drives most sparse checkout support cases.

---

## Lesson 2 — `sparseCheckoutDirectories`: Cone Mode Always Includes Root Files

**What the agent issues** (Build 709, `sparseCheckoutDirectories: CDN tools`):

```
##[command]git sparse-checkout init --cone
##[command]git sparse-checkout set CDN tools
```

**What the workspace contained:**

```
DIR_PRESENT     : CDN/
DIR_PRESENT     : tools/
ROOT_FILE_COUNT : 6        ← root files always present in cone mode
GIT_CONE_MODE   : true
```

**Why:** `--cone` activates git's cone mode, which uses fast prefix matching on
top-level directory names. The unavoidable trade-off:

> **Cone mode always includes every file directly in the repository root.**

This is a git design rule, not an ADO behavior. It cannot be disabled.

**Takeaway:** If a customer needs root files absent, `sparseCheckoutDirectories` cannot
do it. Switch to `sparseCheckoutPatterns`.

---

## Lesson 3 — `sparseCheckoutPatterns`: True Isolation

**What the agent issues** (Build 710, `sparseCheckoutPatterns: CDN/**`):

```
##[command]git sparse-checkout init
##[command]git sparse-checkout set --no-cone CDN/**
```

**What the workspace contained:**

```
DIR_PRESENT     : CDN/
ROOT_FILE_COUNT : 0        ← zero root files
GIT_CONE_MODE   : false
SUMMARY_PASS    : 14
SUMMARY_FAIL    : 0
```

No `--cone` on `init`. `--no-cone` on `set`. Zero root files. Every sentinel passed.

**Mode comparison:**

| | `sparseCheckoutDirectories` | `sparseCheckoutPatterns` |
|---|---|---|
| git flag | `--cone` | `--no-cone` |
| Root files | **Always present** | Only if pattern matches |
| Multiple entries | Space-separated: `CDN tools` | One per line |
| Best for | Fast checkout, root files OK | Strict isolation, no root files |

> ⚠️ Switching from directories to patterns removes root-level files that were previously
> present (build scripts, `.env`, `Makefile`). Audit downstream steps before switching.

---

## Lesson 4 — When Both Properties Are Set: Docs Are Wrong

**The documentation states:** patterns win and directories are ignored.

**Build 712 proved the opposite.** Both properties were set pointing at different folders:

```yaml
sparseCheckoutDirectories: FolderA    # if this wins → FolderA/ present
sparseCheckoutPatterns: CDN/**        # if this wins → CDN/ present
```

The agent issued:

```
##[command]git sparse-checkout init --cone
##[command]git sparse-checkout set FolderA tools
```

`CDN/**` was never referenced. `FolderA/` appeared. `SUMMARY_FAIL: 12` — 12 sentinels
expected CDN; directories won silently.

**Confirmed on:** agent v4.266.2 / git 2.43.0 / Linux.

**Takeaway:** Do not set both properties on the same step. The `##[command]git sparse-checkout set`
log line is the definitive evidence — not the YAML, not the docs.

---

## Lesson 5 — Diagnosing `partiallySucceeded`

When sparse checkout excludes a file a step depends on:

1. Step calls a path that was never copied to the workspace
2. Shell: `No such file or directory`, exit code 127
3. `continueOnError: true` swallows it → build result: `partiallySucceeded`

**Diagnostic steps:**
1. Find the step with a yellow icon — open its log
2. Look for `##[error]` + `No such file or directory`
3. Find `##[command]git sparse-checkout set` in the checkout log
4. Is the missing folder in that `set` command? If not, add it to the sparse scope

**Log line guide:**

| Line | Meaning |
|---|---|
| `init --cone` | Cone mode → root files present |
| `init` (no flag) | Pattern mode → root files absent unless matched |
| `set CDN tools` | Only these folders are in the workspace |
| `set --no-cone CDN/**` | Only paths matching this pattern are in the workspace |

---

## Lesson 6 — ADO Server 2025: Sparse Checkout Silently Ignored

**Symptom:** `sparseCheckoutDirectories` or `sparseCheckoutPatterns` has no effect on
ADO Server 2025 on-premises. Full clone every time. No error.

**Root cause** (`src/Agent.Sdk/Knob/AgentKnobs.cs`):

```csharp
new BuiltInDefaultKnobSource("false")   // knob is OFF by default
```

The entire sparse checkout code block in `GitSourceProvider.cs` is wrapped in:

```csharp
if (AgentKnobs.UseSparseCheckoutInCheckoutTask.GetValue(ctx).AsBoolean()) { ... }
```

On Azure DevOps cloud, Microsoft enables this knob server-side. On ADO Server 2025
on-premises, no such mechanism exists — the knob stays `false`, the block is never entered.

**Fix — add one pipeline variable:**

```yaml
variables:
  - name: AGENT_USE_SPARSE_CHECKOUT_IN_CHECKOUT_TASK
    value: "true"
```

Validated in Build 109 on ADO Server 2025 (`20.256.36719.1`, agent v4.260.0).

**Takeaway:** Not an agent bug, not a git version issue, not a YAML error. One variable.

---

## Post-Test

> Compare your answers to the pre-test. Answer key below.

**Q1.** A customer on **Azure DevOps Services (cloud)** needs only `api/` and `contracts/` in their workspace with **no root files**.
Write the correct checkout YAML.

*(Write the YAML — no multiple choice.)*

**Q2.** A colleague says: "the docs say `sparseCheckoutPatterns` wins when both properties are
set — so patterns will be used." The customer is on **Azure DevOps Services (cloud)**, agent v4.266.2 / git 2.43.0. What do you say,
and what evidence would you check?

*(Short answer.)*

**Q3.** A customer on **Azure DevOps Server 2025 (on-premises)** says sparse checkout stopped working after they migrated
from Azure DevOps Services (cloud). Agent is v4.260.0, YAML is unchanged, no errors in the log. What is
the cause and fix?

- (a) Reinstall the agent
- (b) The YAML syntax changed between cloud and Server 2025
- (c) The feature knob `UseSparseCheckoutInCheckoutTask` defaults to `false` on-premises;
  add pipeline variable `AGENT_USE_SPARSE_CHECKOUT_IN_CHECKOUT_TASK=true`
- (d) Upgrade to agent v4.270.0

---

## Post-Test Answer Key

**Q1. Correct YAML:**
```yaml
- checkout: self
  sparseCheckoutPatterns: |
    api/**
    contracts/**
```
`sparseCheckoutDirectories` activates cone mode and always includes root files. `sparseCheckoutPatterns` does not. *(Lessons 2, 3)*

**Q2.** The documentation is wrong on this version. Live Build 712 on agent v4.266.2 / git 2.43.0 shows
`sparseCheckoutDirectories` wins. Check the `##[command]git sparse-checkout set` line in the build log —
if `--cone` appears and the directory names match `sparseCheckoutDirectories` values, directories won. *(Lesson 4)*

**Q3. (c)** — Feature knob defaults `false` on-premises. One variable fixes it. *(Lesson 6)*

---

## Pre-Test Answer Key

**P1. (b)** — Cone mode always includes root-level files. `FolderA/` was not requested so it is absent. *(Lesson 2)*

**P2. (b)** — The `UseSparseCheckoutInCheckoutTask` knob defaults `false` on-premises; the sparse checkout code block is unreachable. *(Lesson 6)*

**P3. (b)** — `scripts/` was not listed in `sparseCheckoutDirectories`; cone mode only checked out `app/`. *(Lesson 5)*

---

## Quick Reference

### Property → mode → root files

| Property | Mode | Root files |
|---|---|---|
| `sparseCheckoutDirectories` | Cone (`--cone`) | **Always present** |
| `sparseCheckoutPatterns` | Pattern (`--no-cone`) | Absent unless matched |
| Both set (v4.266.2) | Cone wins | **Present** |

### Common customer needs

| Need | YAML |
|---|---|
| CDN only, root files OK | `sparseCheckoutDirectories: CDN` |
| CDN only, no root files | `sparseCheckoutPatterns: \| CDN/**` |
| CDN + build scripts in tools/ | `sparseCheckoutDirectories: CDN tools` |
| Sparse checkout broken on ADO Server 2025 | Add `AGENT_USE_SPARSE_CHECKOUT_IN_CHECKOUT_TASK: "true"` variable |

### Diagnosing `partiallySucceeded`

1. Yellow step icon → open log → find `No such file or directory`
2. Check `##[command]git sparse-checkout set` — is the missing folder listed?
3. If not: add it. If `continueOnError: true` is hiding the error: remove it temporarily.

---

*Evidence base: builds 705, 709, 710, 712 (ADO cloud, agent v4.266.2, git 2.43.0, Linux); Build 109 (ADO Server 2025, agent v4.260.0)*
