# Learning Module: Azure DevOps Sparse Checkout — Pipeline Analysis and Real-World Behavior

**Audience:** Azure DevOps Support Engineers (L1–L3)  
**Prerequisites:** YAML pipeline basics; basic git concepts (clone, checkout, commit)  
**Estimated time:** 45 minutes  
**Format:** Self-paced reading with evidence review  
**Live evidence repo:** `https://dev.azure.com/MCAPDevOpsOrg/PermaSamples/_git/GitSparseCheckout`  
**Related docs:** `SparseCheckout-ADOServer2025-RootCauseAndResolution.md`, `SparseCheckout-TechnicalSupportDocument.md`

---

## Learning Objectives

After completing this module, you will be able to:

1. Explain the difference between cone mode (`sparseCheckoutDirectories`) and pattern mode
   (`sparseCheckoutPatterns`) and predict what files each will materialise in a workspace.
2. Read `##[command]git sparse-checkout` log lines to determine which mode was active and
   what paths were applied.
3. Explain why cone mode always includes root-level files and advise a customer who wants
   to prevent this.
4. Describe the observed conflict resolution behavior when both properties are set, and
   how this differs from the published documentation.
5. Diagnose a `partiallySucceeded` build caused by a file excluded by sparse checkout.
6. Explain why sparse checkout is silently ignored on ADO Server 2025 on-premises and
   state the fix.

---

## Pre-Test

> Complete this before reading the lessons. Do not look up answers.
> Record your answers — you will compare them to the post-test at the end.

---

### Pre-Test — Topic A: git Sparse Checkout Fundamentals

**A1.** When `sparseCheckoutDirectories: CDN` is set, which best describes the workspace?

- (a) Only the `CDN/` folder and its contents
- (b) The `CDN/` folder, its contents, and all root-level files in the repository
- (c) The `CDN/` folder and all other folders at the same level
- (d) All repository files except those inside `CDN/`

**A2.** What does "cone mode" refer to in git sparse checkout?

- (a) A security mode that restricts which branches can be checked out
- (b) A performance-optimized mode using prefix matching on directory names, always
  including root-level files
- (c) A mode that compresses the checkout into a single archive file
- (d) A feature exclusive to Azure DevOps, not part of standard git

**A3.** A customer uses `sparseCheckoutPatterns: src/**` but notices `README.md` is
missing from the workspace. Is this expected?

- (a) No — root-level files are always present regardless of sparse checkout mode
- (b) Yes — pattern mode only materialises paths matching the pattern; `README.md` does not match `src/**`
- (c) No — this indicates a configuration error
- (d) Yes — but only on Linux agents

**A4.** What git commands does Azure DevOps issue when `sparseCheckoutDirectories` is used?

- (a) `git clone --sparse --depth=1`
- (b) `git sparse-checkout init --cone` followed by `git sparse-checkout set <dirs>`
- (c) `git sparse-checkout init` followed by `git sparse-checkout set --no-cone <dirs>`
- (d) `git fetch --filter=blob:none`

---

### Pre-Test — Topic B: Azure DevOps Pipeline YAML Properties

**B1.** This checkout step is configured:

```yaml
- checkout: self
  sparseCheckoutPatterns: |
    billing/**
    shared/**
```

What is the expected workspace?

- (a) Only `billing/` and `shared/`; root files absent
- (b) Only `billing/`; `sparseCheckoutPatterns` only accepts a single entry
- (c) All repository files — patterns are only applied on Windows agents
- (d) `billing/` and `shared/` along with all root-level files

**B2.** A pipeline has `clean: true` on the checkout step and `workspace: clean: all`
on the job. Are they redundant?

- (a) Yes — both do the same thing
- (b) No — `clean: true` clears source files before checkout; `workspace: clean: all`
  clears the entire job workspace before the job starts; both are valid but address
  different phases
- (c) `clean: true` deletes source files; `workspace: clean: all` deletes build outputs only
- (d) `workspace: clean: all` is only valid on self-hosted agents

**B3.** A build completes `partiallySucceeded`. A step with `continueOnError: true`
has a red icon in the run summary. What should you look for first?

- (a) `##[error]` lines in that step's log
- (b) Re-run the pipeline without `continueOnError: true`
- (c) Check whether the agent pool has the correct permissions
- (d) `partiallySucceeded` always indicates a network timeout

---

### Pre-Test — Topic C: Conflict Behavior When Both Properties Are Set

**C1.** A pipeline has both `sparseCheckoutDirectories: FolderA` and
`sparseCheckoutPatterns: CDN/**`. According to the official documentation, what should happen?

- (a) Both properties apply; workspace contains `FolderA/` and `CDN/`
- (b) `sparseCheckoutPatterns` is used; `sparseCheckoutDirectories` is ignored
- (c) `sparseCheckoutDirectories` is used; `sparseCheckoutPatterns` is ignored
- (d) The pipeline fails with a validation error

**C2.** How do you definitively determine which property "won" without modifying the pipeline?

- (a) Read the `agent.log` file on the agent machine
- (b) Find `##[command]git sparse-checkout` lines in the log; check for `--cone` and
  which directory names appear in the `set` command
- (c) Query the task definition via the ADO REST API
- (d) Run `git log --sparse` on the repository after the build

---

### Pre-Test — Topic D: Diagnosing Sparse Checkout Issues

**D1.** A pipeline uses `sparseCheckoutDirectories: src`. The step that runs
`tools/build.sh` fails with `partiallySucceeded`. What is the most likely cause?

- (a) The build script has a syntax error
- (b) `tools/` is not in the sparse scope and was never copied to the workspace
- (c) The agent does not have permission to read `tools/`
- (d) `sparseCheckoutDirectories` does not support multiple path entries

**D2.** You see these log lines:

```
##[command]git sparse-checkout init --cone
##[command]git sparse-checkout set src tools
```

The customer says the pipeline was configured with `sparseCheckoutPatterns: src/**`.
What do you tell them?

- (a) The pipeline is correct — `--cone` and pattern mode are the same thing
- (b) The pipeline used cone mode; `sparseCheckoutPatterns` was not applied
- (c) This indicates a network error during checkout
- (d) `--cone` is always present and does not indicate which property was used

**D3.** On Azure DevOps Server 2025 (on-premises), a pipeline with
`sparseCheckoutDirectories: src` performs a full checkout with no error. What is the root cause?

- (a) The agent version does not support sparse checkout
- (b) `git sparse-checkout` is not available on Windows agents
- (c) The agent feature knob `UseSparseCheckoutInCheckoutTask` defaults to `false`
  on-premises; the sparse checkout code block is never reached
- (d) `sparseCheckoutDirectories` is only supported on Azure DevOps cloud

---

_End of pre-test. Record your answers and proceed to the lessons._

---

# Lessons

---

## Lesson 1 — Sparse Checkout: Two Modes, Different Behaviors

Azure DevOps exposes two YAML properties on the `checkout` step:

```yaml
# Cone mode — list folder names directly
sparseCheckoutDirectories: CDN

# Pattern mode — use glob patterns
sparseCheckoutPatterns: |
  CDN/**
```

These look similar but produce meaningfully different results. The agent translates
them into different `git sparse-checkout` commands, and git's behavior differs
fundamentally between the two modes.

**Key takeaway:** The property name determines the mode. The mode determines whether
root files are included. Everything else follows from that.

---

## Lesson 2 — `sparseCheckoutDirectories`: Cone Mode and the Root-File Rule

### What the agent actually runs

Build 709 used `sparseCheckoutDirectories: CDN tools`. The agent issued:

```
##[command]git sparse-checkout init --cone
##[command]git sparse-checkout set CDN tools
```

Post-checkout workspace (key results):

```
DIR_PRESENT        : CDN/
DIR_PRESENT        : tools/
ROOT_FILE_COUNT    : 6        ← root files always present in cone mode
GIT_CONE_MODE      : true
```

`FolderA/` and `FolderB/` were absent. But six root-level files appeared even though
none were requested.

### Why — the cone mode design rule

The `--cone` flag activates git's cone mode, designed for very large repositories.
It uses fast prefix matching on top-level directory names. The trade-off is a rule
that cannot be disabled:

> **Cone mode always includes all files that are direct children of the repository root.**

This is git's documented behavior, not an ADO bug. `sparseCheckoutDirectories` always
activates cone mode.

### What this means for a customer

| Customer goal | Outcome | Met? |
|---|---|---|
| Only CDN folder | CDN/ present | ✅ |
| Root files absent | Root files always present | ❌ |
| Other folders absent | FolderA/, FolderB/ absent | ✅ |

**Key takeaway:** If a customer needs root-level files to be absent,
`sparseCheckoutDirectories` cannot do it. They must use `sparseCheckoutPatterns`.

---

## Lesson 3 — `sparseCheckoutPatterns`: True Isolation

### What the agent actually runs

Build 710 used `sparseCheckoutPatterns: CDN/**`. The agent issued:

```
##[command]git sparse-checkout init
##[command]git sparse-checkout set --no-cone CDN/**
```

Notice: **no `--cone` on `init`** and `--no-cone` on `set`. This is pattern mode.

Post-checkout workspace (key results):

```
DIR_PRESENT        : CDN/
ROOT_FILE_COUNT    : 0        ← zero root files
GIT_CONE_MODE      : false
SUMMARY_PASS       : 14
SUMMARY_FAIL       : 0
```

### How patterns work

`CDN/**` matches any path under `CDN/` at any depth. There is no automatic root-file
inclusion. Only paths matching at least one pattern are written to disk.

### Comparison: cone mode vs pattern mode

| | `sparseCheckoutDirectories` (cone) | `sparseCheckoutPatterns` (non-cone) |
|---|---|---|
| git init flag | `--cone` | (none) / `--no-cone` |
| Root files | **Always present** | Only if pattern matches |
| Listed folder(s) | Present with all nested content | Present (files matching pattern) |
| Multiple entries | Space-separated: `CDN tools` | One per line |
| Best for | Fast checkout, root files OK | Strict isolation, no root files |

> ⚠️ **Mode-switching warning.** Switching from `sparseCheckoutDirectories` to
> `sparseCheckoutPatterns` removes any root-level files that were previously present
> (build scripts, `.env`, `Makefile`). Audit every downstream step before switching.

**Key takeaway:** `sparseCheckoutPatterns` is the only option that produces a workspace
with zero root-level files. The pattern `CDN/**` gives `CDN/` and nothing else.

---

## Lesson 4 — What Happens When Both Properties Are Set

### The documentation claim

> _"If both `sparseCheckoutDirectories` and `sparseCheckoutPatterns` are specified,
> `sparseCheckoutPatterns` is used and `sparseCheckoutDirectories` is ignored."_

### What live Build 712 proved

Build 712 intentionally set both properties pointing at **different folders** so the
workspace would make it unambiguous which property won:

```yaml
sparseCheckoutDirectories: FolderA tools   # if this wins → FolderA/ present, CDN/ absent
sparseCheckoutPatterns: |                  # if this wins → CDN/ present, FolderA/ absent
  CDN/**
  tools/**
```

The git commands actually issued:

```
##[command]git sparse-checkout init --cone
##[command]git sparse-checkout set FolderA tools
```

`CDN/**` was never referenced. Result:

```
DIR_PRESENT        : FolderA/
GIT_CONE_MODE      : true
SUMMARY_FAIL       : 12    ← 12 sentinels expected CDN; FolderA appeared instead
```

**`sparseCheckoutDirectories` won. The documentation is wrong on agent v4.266.2 / git 2.43.0.**

### How to diagnose in a live case

1. Get the pipeline log — find `##[command]git sparse-checkout set`
2. Check for `--cone` on `init`
3. Compare the directory names in `set` against `sparseCheckoutDirectories` vs `sparseCheckoutPatterns`
4. If names match `sparseCheckoutDirectories` values → directories won

**First-reply checklist — request from customer:**
- Agent version (visible in pipeline log header)
- Git version (add `git --version` to a script step)
- Complete `checkout:` YAML block
- Pipeline log for the "Get sources" step

**Key takeaway:** Do not set both properties on the same step. On agent v4.266.2,
`sparseCheckoutDirectories` wins silently. The `##[command]git sparse-checkout set`
line is the definitive evidence — not the YAML, not the documentation.

---

## Lesson 5 — Diagnosing `partiallySucceeded` Sparse Checkout Builds

### The pattern

When sparse checkout excludes a file that a subsequent step depends on:

1. Step calls a path inside the workspace
2. The path does not exist — sparse checkout never copied it
3. Shell reports `No such file or directory`, exit code 127
4. `continueOnError: true` swallows the failure
5. Build result: `partiallySucceeded`

Example from Build 706 (before `tools/` was added to the sparse scope):

```
bash: /home/runner/work/1/s/tools/inspect-workspace.sh: No such file or directory
##[error]Bash exited with code '127'.
```

### Diagnostic checklist

1. Find any step with a yellow icon in the run summary
2. Open that step's log — look for `##[error]` and `No such file or directory`
3. Note the missing path — is that folder in the sparse checkout scope?
4. Find `##[command]git sparse-checkout set` in the checkout log — is the folder listed?
5. If not, add it to the sparse scope
6. If `continueOnError: true` is hiding the error, remove it temporarily to confirm

### Reading `##[command]` lines

| Log line | Meaning |
|---|---|
| `git sparse-checkout init --cone` | Cone mode → root files present |
| `git sparse-checkout init` | Pattern mode → root files absent unless matched |
| `git sparse-checkout set CDN tools` | These exact folders are in the workspace |
| `git sparse-checkout set --no-cone CDN/**` | This pattern controls the workspace |

**Key takeaway:** `##[command]` lines record what the agent actually executed — they are
primary evidence. `SUMMARY_FAIL: N` in the inspection log quantifies the deviation;
use it to measure scope, not as a build verdict.

---

## Lesson 6 — ADO Server 2025: Sparse Checkout Silently Ignored

### The symptom

On **Azure DevOps Server 2025 (on-premises)**, setting `sparseCheckoutDirectories` or
`sparseCheckoutPatterns` has no effect. The agent performs a full clone every time.
No error is raised. The same YAML works correctly on Azure DevOps cloud.

### Root cause — the feature knob

In the agent source code (`src/Agent.Sdk/Knob/AgentKnobs.cs`):

```csharp
public static readonly Knob UseSparseCheckoutInCheckoutTask = new Knob(
    nameof(UseSparseCheckoutInCheckoutTask),
    "If true, agent will use sparse checkout in checkout task.",
    new RuntimeKnobSource("AGENT_USE_SPARSE_CHECKOUT_IN_CHECKOUT_TASK"),
    new BuiltInDefaultKnobSource("false"));   // ← OFF by default
```

In `src/Agent.Plugins/GitSourceProvider.cs`, the entire sparse checkout code block is wrapped in:

```csharp
if (AgentKnobs.UseSparseCheckoutInCheckoutTask.GetValue(executionContext).AsBoolean())
{
    // git sparse-checkout init / set  — never reached when knob is false
}
```

On Azure DevOps cloud, Microsoft enables this knob server-side for all organizations.
On ADO Server 2025 on-premises, no equivalent mechanism exists — the knob stays `false`.

### The fix — one pipeline variable

```yaml
variables:
  - name: AGENT_USE_SPARSE_CHECKOUT_IN_CHECKOUT_TASK
    value: "true"
```

This sets the `RuntimeKnobSource` to `true` and unblocks the sparse checkout code path.
Validated in **Build 109** on ADO Server 2025 (`20.256.36719.1`, agent v4.260.0):
knob off → full checkout; knob on → correct sparse checkout.

> Full root cause analysis: `docs/SparseCheckout-ADOServer2025-RootCauseAndResolution.md`

**Key takeaway:** If a customer on ADO Server 2025 reports that sparse checkout has no
effect, the fix is a single pipeline variable. It is not an agent bug, not a git version
issue, and not a YAML error.

---

## Post-Test

> You have completed all six lessons. Take the post-test below.
> Compare your answers to the pre-test. The answer key follows.

---

### Post-Test — Topic A: git Sparse Checkout Fundamentals

**A1.** A pipeline uses `sparseCheckoutDirectories: billing`. The repo root contains
`billing/`, `shared/`, `README.md`, `config.yml`. What will the workspace contain?

- (a) Only `billing/`
- (b) `billing/`, `README.md`, and `config.yml`
- (c) `billing/` and `shared/`
- (d) All files — sparse checkout requires explicit opt-in

**A2.** What is the performance reason cone mode was introduced, and what is the
trade-off that causes root-level files to always be present?

- (a) Cone mode reduces network bandwidth; the trade-off is slower checkout speed
- (b) Cone mode uses fast prefix matching on top-level directory names instead of
  evaluating full path patterns; the trade-off is mandatory root-level file inclusion
- (c) Cone mode encrypts file transfers; the trade-off is CPU overhead at the root
- (d) Cone mode caches blob objects; cached blobs are written to the root

**A3.** A customer uses `sparseCheckoutPatterns: FolderA/**`. Will `shared/lib.ts`
be present in the workspace?

- (a) Yes — it is not in FolderA so it is excluded but still present
- (b) Yes — pattern mode always includes root-level files
- (c) No — `shared/lib.ts` does not match `FolderA/**`; it will be absent
- (d) It depends on whether the file was modified in the last commit

**A4.** The pipeline log shows `##[command]git sparse-checkout init` (no flags) then
`##[command]git sparse-checkout set --no-cone src/**`. Which YAML property caused this?

- (a) `sparseCheckoutDirectories: src`
- (b) `sparseCheckoutPatterns: src/**`
- (c) `sparseCheckoutDirectories: src/**`
- (d) `sparseCheckoutPatterns: src` (without `**`)

---

### Post-Test — Topic B: Azure DevOps Pipeline YAML

**B1.** Rewrite this YAML so that only `api/` and `contracts/` appear with zero root files:

```yaml
- checkout: self
  sparseCheckoutDirectories: api contracts
```

_(Write the corrected YAML — no multiple choice.)_

**B2.** A customer's build shows `partiallySucceeded` and they ship to production
without investigation. What is the risk?

- (a) No risk — `partiallySucceeded` equals `succeeded` for deployment purposes
- (b) Steps that failed silently may have produced no output or incomplete artifacts;
  every step with `continueOnError: true` in the failing build should be audited
- (c) The risk only applies on Linux agents
- (d) Setting `continueOnError: false` globally prevents this

**B3.** A `sparseCheckoutPatterns: src/**` pipeline is missing `tools/build.sh`.
What is the single fix?

- (a) Change `src/**` to `src/** tools/**` on the same line
- (b) Add `tools/**` as a second line under `sparseCheckoutPatterns`
- (c) Add `sparseCheckoutDirectories: tools` on the same checkout step alongside patterns
- (d) Move `tools/build.sh` into `src/`

---

### Post-Test — Topic C: Conflict Behavior

**C1.** A colleague says "the docs say patterns win, so `sparseCheckoutPatterns` will
be used." The customer is on agent v4.266.2 / git 2.43.0. What do you say?

- (a) Your colleague is correct — follow the documentation
- (b) Live testing on that version shows `sparseCheckoutDirectories` wins; advise the
  customer to verify by checking the `##[command]git sparse-checkout set` line in
  their build log
- (c) Neither applies when both are set — the checkout reverts to full checkout
- (d) The documentation is correct on Windows but not Linux

**C2.** A `sparse-both` pipeline produces `SUMMARY_FAIL: 12`. The inspection script
expected `CDN/` but the workspace contains `FolderA/`. What does this mean?

- (a) The inspection script has a bug
- (b) `sparseCheckoutDirectories` (pointing at `FolderA`) won over `sparseCheckoutPatterns`
  (pointing at `CDN/**`); the 12 failures quantify the deviation from expected behavior
- (c) `FolderA/` and `CDN/` are the same folder under a different alias
- (d) The agent ran out of memory during checkout

---

### Post-Test — Topic D: Diagnosing Issues

**D1.** A customer sends this log and asks why the build is `partiallySucceeded`:

```
##[command]git sparse-checkout init --cone
##[command]git sparse-checkout set app
bash: /home/runner/work/1/s/scripts/deploy.sh: No such file or directory
##[error]Bash exited with code '127'.
```

What caused it and how do you fix it?

- (a) The script has a typo — `deploy.sh` does not exist in the repository
- (b) Cone mode checked out only `app/` plus root files; `scripts/` was not listed
  in `sparseCheckoutDirectories` and was never copied. Fix: add `scripts` to
  `sparseCheckoutDirectories`, or switch to `sparseCheckoutPatterns: | app/** scripts/**`
- (c) The agent user does not have execute permission on the script
- (d) `bash` is not installed on this agent

**D2.** A customer on Azure DevOps Server 2025 reports `sparseCheckoutDirectories`
has no effect despite using agent v4.260.0. What is the cause and fix?

- (a) Upgrade to a higher agent version
- (b) Add `sparseCheckoutPatterns` alongside `sparseCheckoutDirectories`
- (c) The feature knob `UseSparseCheckoutInCheckoutTask` defaults to `false` on-premises;
  fix by adding pipeline variable `AGENT_USE_SPARSE_CHECKOUT_IN_CHECKOUT_TASK=true`
- (d) Reinstall the agent

**D3.** Write the two `##[command]` lines you expect in a correctly configured pattern-mode pipeline.

_(Write the two lines — no multiple choice.)_

---

## Post-Test Answer Key

### Topic A

**A1. (b)** — `billing/`, `README.md`, `config.yml`. Cone mode always includes root files. `shared/` was not requested. _(Lesson 2)_

**A2. (b)** — Fast prefix matching on top-level directory names; trade-off is mandatory root-file inclusion. _(Lesson 2)_

**A3. (c)** — `shared/lib.ts` does not match `FolderA/**`; it is absent. If needed, add `shared/**` as a second pattern. _(Lesson 3)_

**A4. (b)** — `sparseCheckoutPatterns: src/**`. No `--cone` on `init` and `--no-cone` on `set` are the pattern-mode signatures. _(Lessons 3, 5)_

### Topic B

**B1. Correct YAML:**

```yaml
- checkout: self
  sparseCheckoutPatterns: |
    api/**
    contracts/**
```

`sparseCheckoutDirectories` activates cone mode and always includes root files. Switch to `sparseCheckoutPatterns` to exclude them. _(Lessons 2, 3)_

**B2. (b)** — Silent failures may produce no output or missing artifacts; audit every `continueOnError: true` step. _(Lesson 5)_

**B3. (b)** — Add `tools/**` as a second line. Each pattern independently contributes paths. Do not mix with `sparseCheckoutDirectories`. _(Lessons 3, 4)_

### Topic C

**C1. (b)** — Documentation says patterns win; live evidence on v4.266.2 / git 2.43.0 shows directories win. Verify with `##[command]git sparse-checkout set`. _(Lesson 4)_

**C2. (b)** — `SUMMARY_FAIL: 12` quantifies the deviation. `CDN/` absent and `FolderA/` present proves which property won. _(Lesson 4)_

### Topic D

**D1. (b)** — `scripts/` not in sparse scope → never copied → exit 127. Add `scripts` to the sparse checkout scope. _(Lesson 5)_

**D2. (c)** — Feature knob defaults `false` on-premises. Fix: `AGENT_USE_SPARSE_CHECKOUT_IN_CHECKOUT_TASK=true`. _(Lesson 6)_

**D3. Expected lines:**

```
##[command]git sparse-checkout init
##[command]git sparse-checkout set --no-cone <your-patterns>
```

`init` with no `--cone`; `set` with `--no-cone`. If you see `init --cone`, cone mode was activated. _(Lessons 3, 5)_

---

## Quick-Reference Card

### Identify which mode is active

| Log line | Mode | Property used |
|---|---|---|
| `git sparse-checkout init --cone` | Cone | `sparseCheckoutDirectories` |
| `git sparse-checkout init` | Pattern | `sparseCheckoutPatterns` |
| `git sparse-checkout set CDN tools` | Cone | Directories |
| `git sparse-checkout set --no-cone CDN/**` | Pattern | Patterns |

### Predict workspace contents

| Property | Root files | Listed folders | Other folders |
|---|---|---|---|
| `sparseCheckoutDirectories: X` | **YES — always** | YES | NO |
| `sparseCheckoutPatterns: X/**` | NO | YES | NO |
| Both set (v4.266.2) | **YES (cone)** | Dirs value folder | NO |

### Customer outcome → YAML to use

**"Only CDN, root files OK":**
```yaml
- checkout: self
  sparseCheckoutDirectories: CDN
```

**"Only CDN, no root files":**
```yaml
- checkout: self
  sparseCheckoutPatterns: |
    CDN/**
```

**"Build scripts in `tools/` are missing from sparse checkout":**
```yaml
sparseCheckoutDirectories: CDN tools
# or
sparseCheckoutPatterns: |
  CDN/**
  tools/**
```

**"Sparse checkout does nothing on ADO Server 2025":**
```yaml
variables:
  - name: AGENT_USE_SPARSE_CHECKOUT_IN_CHECKOUT_TASK
    value: "true"
```

### Diagnosing `partiallySucceeded`

1. Find steps with a yellow icon in the run summary
2. Open the step log — look for `##[error]` and `No such file or directory`
3. Note the missing path — is that folder in `##[command]git sparse-checkout set`?
4. If not, add it to the sparse checkout scope
5. Is `continueOnError: true` hiding the error? Remove it temporarily to confirm

---

## Further Reading

| Resource | Notes |
|---|---|
| [Azure Pipelines checkout YAML schema](https://docs.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/steps-checkout) | Official docs — the "patterns win" claim for the both-set case is unreliable on tested agent versions |
| [git-sparse-checkout man page](https://git-scm.com/docs/git-sparse-checkout) | Authoritative source for cone vs non-cone behavior |
| `docs/SparseCheckout-ADOServer2025-RootCauseAndResolution.md` | Full root cause analysis for the Server 2025 knob issue with Build 109 evidence |
| `docs/SparseCheckout-TechnicalSupportDocument.md` | Full technical analysis with all four build results and raw log evidence |
| `docs/CustomerWorkaround-Finding2.md` | Customer-facing fix guide for ADO Server 2025 |

---

_February 2026 — Evidence base: live builds 705, 709, 710, 712 (cloud); Build 109 (ADO Server 2025)_  
_Agent: v4.266.2 · git: 2.43.0 · OS: Linux (cloud) · Agent: v4.260.0 (ADO Server 2025)_
