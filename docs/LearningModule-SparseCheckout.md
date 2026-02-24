# Learning Module: Azure DevOps Sparse Checkout — Pipeline Analysis and Real-World Behavior

**Produced by:** [ADEL — Azure DevOps Engineering Learner](LearningAgent-Profile.md)  
**Audience:** Azure DevOps Support Engineers (L1–L3)  
**Prerequisites:** Familiarity with YAML pipeline basics; basic git concepts (clone, checkout, commit)  
**Estimated time:** 90 minutes  
**Format:** Self-paced reading with evidence review  
**Live evidence repo:** `https://dev.azure.com/MCAPDevOpsOrg/PermaSamples/_git/GitSparseCheckout`  
**Related docs:** `SparseCheckout-TechnicalSupportDocument.md`, `SME-Validation-QA.md`  
**Evaluator profile:** [VALE — Validation Agent for Learning Evaluation](StudentAgent-Profile.md)

---

## Why This Module Exists

A customer opened a support case with the following complaint:

> _"We configured `sparseCheckoutDirectories: CDN` in our pipeline and root-level files
> from our repository keep appearing in our build workspace. We don't want them there.
> We also tried setting both `sparseCheckoutDirectories` and `sparseCheckoutPatterns`
> at the same time and our pipeline behaved in a way that contradicts the documentation."_

This is not a unique case. The same pattern appears in support queues regularly because
the Azure DevOps sparse checkout feature has two distinct operating modes that behave very
differently, the documentation does not clearly explain the trade-offs, and at least one
documented behavior has been observed to be incorrect on tested agent versions.

This module walks you through the complete investigation — the same investigation performed
to resolve a real escalation — so you can handle the next one with confidence.

---

## Learning Objectives

After completing this module, you will be able to:

1. Explain the difference between cone mode (`sparseCheckoutDirectories`) and pattern mode
   (`sparseCheckoutPatterns`) and describe the specific file materialization behavior of each.
2. Predict what files will appear in an agent workspace for a given checkout YAML configuration
   without running the pipeline.
3. Read Azure DevOps pipeline log `##[command]` lines to determine which git sparse checkout
   mode was activated and what rules were applied.
4. Explain why cone mode always includes root-level files and how to advise a customer who
   wants to prevent this.
5. Describe the observed conflict resolution behavior when both `sparseCheckoutDirectories`
   and `sparseCheckoutPatterns` are set simultaneously, including how this differs from the
   published documentation.
6. Diagnose a `partiallySucceeded` pipeline result caused by a missing file that was excluded
   by sparse checkout.
7. Write the correct YAML checkout step for the three most common sparse checkout customer
   needs.

---

## Pre-Test

> Complete this test **before** reading any of the lessons below. Do not look up answers.
> Your score here is your baseline — it measures what you already know. You will take a
> parallel test at the end to measure what you learned.
>
> Record your answers somewhere before continuing.

---

### Pre-Test — Topic A: git Sparse Checkout Fundamentals

**A1.** When `sparseCheckoutDirectories: CDN` is set in an Azure DevOps pipeline, which of
the following best describes what will appear in the agent workspace?

- (a) Only the `CDN/` folder and its contents
- (b) The `CDN/` folder, its contents, and all root-level files in the repository
- (c) The `CDN/` folder and all other folders at the same level
- (d) All repository files except those inside `CDN/`

**A2.** What does the term "cone mode" refer to in the context of git sparse checkout?

- (a) A security mode that restricts which branches can be checked out
- (b) A performance-optimized mode that uses prefix matching on directory names, always
  including root-level files
- (c) A mode that compresses the checkout into a single archive file
- (d) A feature exclusive to Azure DevOps that is not part of standard git

**A3.** A customer says their pipeline is checking out only `src/` using
`sparseCheckoutPatterns: src/**` but they notice that no other files or folders appear
in the workspace — not even their `README.md`. Is this behavior expected?

- (a) No — root-level files should always be present regardless of sparse checkout mode
- (b) Yes — `sparseCheckoutPatterns` only materializes paths that match the pattern;
  `README.md` is a root file and does not match `src/**`
- (c) No — this indicates a configuration error in the pipeline
- (d) Yes — but only if the agent is running on Linux

**A4.** What git command does Azure DevOps issue when `sparseCheckoutDirectories` is used?
Select the answer that most closely matches what the agent executes.

- (a) `git clone --sparse --depth=1`
- (b) `git sparse-checkout init --cone` followed by `git sparse-checkout set <dirs>`
- (c) `git sparse-checkout init` followed by `git sparse-checkout set --no-cone <dirs>`
- (d) `git fetch --filter=blob:none`

---

### Pre-Test — Topic B: Azure DevOps Pipeline YAML Properties

**B1.** A pipeline YAML contains the following checkout step. What is the expected result?

```yaml
- checkout: self
  sparseCheckoutPatterns: |
    billing/**
    shared/**
```

- (a) Only `billing/` and `shared/` appear in the workspace; root files are absent
- (b) Only `billing/` appears; `sparseCheckoutPatterns` only accepts a single entry
- (c) All repository files appear because patterns are only applied on Windows agents
- (d) `billing/` and `shared/` appear along with all root-level files

**B2.** A pipeline is configured with `clean: true` on the checkout step and
`workspace: clean: all` on the job. What does each setting do, and are they redundant?

- (a) They are redundant — both do the same thing
- (b) `clean: true` clears the workspace before checkout; `workspace: clean: all` is a
  job-level setting that also clears the workspace — they address the same agent directory
  but are not strictly redundant in terms of when they run
- (c) `clean: true` deletes source files; `workspace: clean: all` deletes build outputs only
- (d) `workspace: clean: all` is only valid on self-hosted agents

**B3.** A support engineer sets `continueOnError: true` on an inspection script step.
The build completes with result `partiallySucceeded`. What should the engineer look for
in the pipeline logs to understand why?

- (a) Look for the `##[error]` lines in any step marked with `continueOnError: true`
- (b) Re-run the pipeline without `continueOnError: true` to force a hard failure
- (c) Check whether the agent pool has the correct permissions
- (d) `partiallySucceeded` always indicates a network timeout

---

### Pre-Test — Topic C: Conflict Behavior When Both Properties Are Set

**C1.** A pipeline YAML contains both `sparseCheckoutDirectories: FolderA` and
`sparseCheckoutPatterns: CDN/**` on the same checkout step. According to the official
Azure DevOps documentation, what should happen?

- (a) Both properties are applied and the workspace contains both `FolderA/` and `CDN/`
- (b) `sparseCheckoutPatterns` is used and `sparseCheckoutDirectories` is ignored
- (c) `sparseCheckoutDirectories` is used and `sparseCheckoutPatterns` is ignored
- (d) The pipeline fails with a validation error

**C2.** How would you definitively determine which sparse checkout property "won" when
both are configured, without modifying the pipeline?

- (a) Read the `agent.log` file on the agent machine
- (b) Look for `##[command]git sparse-checkout` lines in the pipeline log and check whether
  `--cone` was used and which directory names appear in the `set` command
- (c) Use the Azure DevOps REST API to query the task definition
- (d) Run `git log --sparse` on the repository after the build completes

---

### Pre-Test — Topic D: Diagnosing Sparse Checkout Issues

**D1.** A customer reports that their pipeline completes with `partiallySucceeded` and
the step that runs their build script fails with "file not found." The script lives in a
`tools/` directory. The pipeline uses `sparseCheckoutDirectories: src`. What is the
most likely cause?

- (a) The build script has a syntax error
- (b) The `tools/` directory is not in the sparse checkout scope and was never copied
  to the agent workspace
- (c) The agent does not have permission to read `tools/`
- (d) `sparseCheckoutDirectories` does not support multiple path entries

**D2.** You are reading a pipeline log and you see the following lines:

```
##[command]git sparse-checkout init --cone
##[command]git sparse-checkout set src tools
```

A customer claims their pipeline was supposed to use `sparseCheckoutPatterns: src/**`.
Based on these log lines alone, what can you tell the customer?

- (a) The pipeline is working correctly — `--cone` and pattern mode are the same thing
- (b) The pipeline used cone mode (`sparseCheckoutDirectories`), not pattern mode;
  `sparseCheckoutPatterns` was not applied
- (c) This log output indicates a network error during checkout
- (d) The `--cone` flag is always present and does not indicate which property was used

---

_End of pre-test. Record your answers and proceed to the lessons._

---

---

# Lessons

---

## Lesson 1 — What Is Sparse Checkout and Why Do Support Engineers Need to Understand It?

### The customer's words

> _"Our repository has hundreds of folders. Our CDN pipeline only needs the `CDN/` folder.
> Can we tell Azure DevOps to only download that folder? Checkout is taking 4 minutes and
> we're checking out a thousand files we never use."_

This is the single most common sparse checkout support request. The customer's goal is
simple: less stuff on the agent. The answer is also simple — but only if you understand
what the two available options actually do.

### Plain-English mental model

Picture your repository as a warehouse with many numbered shelving units. When a pipeline
runs, the agent sends a truck to the warehouse to pick up everything and bring it to the
build server (the "workspace"). A full checkout means the truck empties the entire warehouse.
That takes time and fills up the truck.

**Sparse checkout** is a pick-list you hand the truck driver: "I only need shelving units
5 and 12." The driver should only load those. The warehouse (the repository on the server)
is unchanged — everything is still there. You are only controlling what gets loaded onto
the truck and driven to the build server.

The complication is that the Azure DevOps "truck driver" (the checkout task) has two
modes for reading the pick-list, and they behave differently. That is what this module
is about.

### The technical reality

Azure DevOps exposes two YAML properties on the `checkout` step for sparse checkout:

```yaml
# Option A — Lists folder names directly
sparseCheckoutDirectories: CDN

# Option B — Uses glob patterns
sparseCheckoutPatterns: |
  CDN/**
```

These look similar. They produce meaningfully different results. The rest of this module
examines exactly how they differ and what each one is right for.

### Key takeaway

> Sparse checkout controls which files appear **in the agent workspace** (what gets placed
> on the desk). It does not change the repository structure, it does not delete files from
> the server, and by default it does not reduce how many bytes cross the network — it only
> controls what git writes to disk.

---

## Lesson 2 — `sparseCheckoutDirectories`: Cone Mode and the Root-File Rule

### The customer's words

> _"I set `sparseCheckoutDirectories: CDN` and my workspace still has `config.json`,
> `README.md`, and `appsettings.yml` in it. Those files are not inside `CDN/`. Why
> are they there?"_

This is the most frequently misunderstood behavior in sparse checkout. Let us prove
exactly what happens before explaining why.

### Live evidence — Build 709

Build 709 used this exact configuration:

```yaml
# filepath: .azuredevops/sparse-directories.yml
- checkout: self
  clean: true
  persistCredentials: true
  sparseCheckoutDirectories: CDN tools
  displayName: "Checkout (sparseCheckoutDirectories: CDN tools)"
```

Here are the **actual git commands the Azure DevOps agent issued**, captured verbatim from
the Build 709 pipeline log:

```
##[command]git sparse-checkout init --cone
##[command]git sparse-checkout set CDN tools
```

And here is what the workspace contained after checkout:

```
DIR_PRESENT        : CDN/
DIR_PRESENT        : tools/
DIR_COUNT          : 3   (CDN/, tools/, and .git/)
ROOT_FILE_PRESENT  : .gitignore
ROOT_FILE_PRESENT  : README.md
ROOT_FILE_PRESENT  : RootFile1.yml
ROOT_FILE_PRESENT  : RootFile2.yml
ROOT_FILE_PRESENT  : config.json
ROOT_FILE_PRESENT  : root-notes.txt
ROOT_FILE_COUNT    : 6
GIT_CONE_MODE      : true
```

`CDN/` is there. `tools/` is there (because we listed it). `FolderA/` and `FolderB/`
are absent. But **six root-level files appeared even though the customer did not ask
for them**.

### Why this happens — the cone mode design

The `--cone` flag in `git sparse-checkout init --cone` activates git's **cone mode**.
Cone mode was designed specifically for very large repositories (Microsoft's internal
Windows source code was the primary use case). In massive repos, evaluating a
`.gitignore`-style pattern against every file path is too slow.

Cone mode solves this with a simpler algorithm: it only looks at directory names at
the top level of the tree. This is much faster. But the trade-off is a rule that cannot
be disabled:

> **Cone mode always includes all files that are direct children of the repository root.**

This is documented in the git man page for `git-sparse-checkout`:

> _"The cone mode will always include the files directly in the root directory."_

So when the customer writes `sparseCheckoutDirectories: CDN`, they are asking for cone
mode, and cone mode delivers `CDN/` plus every file sitting directly in the root.
This is not a bug — it is the documented behavior of cone mode in git itself.

### What this means for your customer

| Customer goal                    | `sparseCheckoutDirectories` outcome  | Does it meet the goal? |
| -------------------------------- | ------------------------------------ | ---------------------- |
| Only CDN folder in workspace     | CDN/ present                         | ✅                     |
| Root files absent from workspace | Root files always present            | ❌                     |
| Other folders absent             | FolderA/, FolderB/ absent            | ✅                     |
| Fast checkout (fewer files)      | Fewer than full; root files included | ⚠️ Partial             |

If the customer's root contains large files, sensitive files, or files that interfere
with their build process, `sparseCheckoutDirectories` alone will not solve their problem.

### Key takeaway

> `sparseCheckoutDirectories` activates cone mode. Cone mode always materializes
> root-level files — you cannot opt out of this. If you need root files to be absent,
> you must use `sparseCheckoutPatterns` instead.

---

## Lesson 3 — `sparseCheckoutPatterns`: Pattern Mode and True Isolation

### The customer's words

> _"Is there any way to get ONLY the CDN folder? Nothing else — no root files, no other
> folders. Just CDN."_

Yes. This is exactly what `sparseCheckoutPatterns` was designed for.

### Live evidence — Build 710

Build 710 used this configuration:

```yaml
# filepath: .azuredevops/sparse-patterns.yml
- checkout: self
  clean: true
  persistCredentials: true
  sparseCheckoutPatterns: |
    CDN/**
    tools/**
  displayName: "Checkout (sparseCheckoutPatterns: CDN/** tools/**)"
```

The **actual git commands** from the Build 710 pipeline log:

```
##[command]git sparse-checkout init
##[command]git sparse-checkout set --no-cone CDN/** tools/**
```

Notice: **no `--cone` flag** on `init`. And the `set` command uses `--no-cone` explicitly.
This is pattern mode.

The workspace after checkout:

```
DIR_PRESENT        : CDN/
DIR_PRESENT        : tools/
DIR_COUNT          : 3
ROOT_FILE_COUNT    : 0
CONTENT_CHECK      : CDN/cdnfile1.txt → # SENTINEL: CDN_FILE_1_PRESENT
CONTENT_CHECK      : CDN/nested/cdnfile2.txt → # SENTINEL: CDN_NESTED_CDNFILE2_PRESENT
CONTENT_CHECK      : FolderA/a1.txt → (file not present – skipped)
CONTENT_CHECK      : RootFile1.yml → (file not present – skipped)
GIT_CONE_MODE      : false
GIT_SPARSE_FLAG    : true
SUMMARY_PASS       : 14
SUMMARY_FAIL       : 0
```

`ROOT_FILE_COUNT: 0` — zero root files. `SUMMARY_FAIL: 0` — every check passed.
`CDN/` is fully present with all nested folder content readable. `FolderA/`, `FolderB/`,
`README.md`, `config.json` — none of them exist on the agent.

### How patterns work

`CDN/**` is a glob pattern. The `**` means "any path at any depth." So `CDN/**` matches:

- `CDN/cdnfile1.txt` ✅
- `CDN/nested/cdnfile2.txt` ✅
- `CDN/nested/deep/asset.json` ✅
- `README.md` ❌ (not under CDN/)
- `FolderA/a1.txt` ❌ (not under CDN/)

Pattern mode evaluates every file path in the repository against the list of patterns.
Only files whose paths match at least one pattern are written to disk. There is no
automatic root-file inclusion. There is no cone behavior. What you ask for is exactly
what you get.

### Comparison: cone mode vs pattern mode

|                  | `sparseCheckoutDirectories` (cone) | `sparseCheckoutPatterns` (non-cone) |
| ---------------- | ---------------------------------- | ----------------------------------- | --- |
| git init flag    | `--cone`                           | (none) / `--no-cone`                |
| Root files       | **Always present**                 | Only if pattern matches             |
| Listed folder(s) | Present with all nested content    | Present (files matching pattern)    |
| Unlisted folders | Absent                             | Absent                              |
| Multiple entries | Space-separated: `CDN tools`       | One per line under `                | `   |
| Best for         | Fast checkout, root files okay     | Strict isolation, no root files     |

### Key takeaway

> `sparseCheckoutPatterns` is the only Azure DevOps sparse checkout option that can
> produce a workspace with zero root-level files. Use it when the customer needs
> true single-folder isolation. The pattern `CDN/**` gives `CDN/` and nothing else.

---

## Lesson 4 — What Happens When Both Properties Are Set

### The customer's words

> _"I set both `sparseCheckoutDirectories` and `sparseCheckoutPatterns` in the same
> checkout step because the documentation said patterns would win. But my workspace
> looks like it used directories instead. The docs say patterns win but that's not
> what I'm seeing."_

This is the most operationally significant finding from our test runs. The customer is
right to be confused — and the documentation is wrong.

### The documentation claim

The official Azure DevOps documentation states:

> _"If both `sparseCheckoutDirectories` and `sparseCheckoutPatterns` are specified,
> `sparseCheckoutPatterns` is used and `sparseCheckoutDirectories` is ignored."_

### What the live build proves

Build 712 was designed specifically to test this. The checkout step was configured with
**both properties pointing at different folders** — deliberately — so the workspace
contents would make it unambiguous which property was used:

```yaml
# filepath: .azuredevops/sparse-both.yml
- checkout: self
  clean: true
  persistCredentials: true
  # If directories win → FolderA/ appears, CDN/ absent
  sparseCheckoutDirectories: FolderA tools
  # If patterns win → CDN/ appears, FolderA/ absent
  sparseCheckoutPatterns: |
    CDN/**
    tools/**
  displayName: "Checkout (BOTH: directories=FolderA, patterns=CDN/** → patterns should win)"
```

The **actual git commands** issued by the agent during Build 712:

```
##[command]git sparse-checkout init --cone
##[command]git sparse-checkout set FolderA tools
```

`sparseCheckoutPatterns` (`CDN/**`) was never referenced. The agent ran cone mode with
`FolderA` — the value from `sparseCheckoutDirectories`. Then `git sparse-checkout list`
confirmed:

```
FolderA
tools
```

Only `FolderA` and `tools`. `CDN` does not appear.

The workspace after checkout:

```
DIR_PRESENT        : FolderA/
DIR_PRESENT        : tools/
DIR_COUNT          : 3
ROOT_FILE_COUNT    : 6        ← cone mode, so root files present
CONTENT_CHECK      : CDN/cdnfile1.txt → (file not present – skipped)
CONTENT_CHECK      : FolderA/a1.txt → # SENTINEL: FOLDER_A_FILE1_PRESENT
GIT_CONE_MODE      : true
SUMMARY_PASS       : 2
SUMMARY_FAIL       : 12
```

`SUMMARY_FAIL: 12` — the inspection script expected patterns to win (CDN present,
FolderA absent, zero root files). Directories won instead, producing 12 failures.
**This is not a real build failure — it is the evidence.**

### Why this matters in a support case

If a customer has:

```yaml
sparseCheckoutDirectories: src
sparseCheckoutPatterns: |
  deployments/**
```

…expecting the deployments pattern to be used (as the documentation says), they will
instead get the `src/` cone-mode checkout — plus all root files. The `deployments/**`
pattern is silently discarded. The pipeline log will not warn them. The build result
will be `succeeded` (not failed), and the workspace will contain files the customer
did not intend to check out.

### Scope of this finding

This behavior was confirmed on:

- Azure DevOps Agent **v4.266.2**
- git **2.43.0**
- Linux (Ubuntu) agent OS

This should be tested on:

- Microsoft-hosted agents (Ubuntu, Windows)
- Different agent versions
- Older git versions

The behavior may differ. What is certain is that the current documentation cannot be
relied upon as a guarantee on the tested configuration.

### How to advise a customer

If a customer reports this, the investigative sequence is:

1. Ask them to provide the raw pipeline log for the failing build.
2. Locate the `##[command]git sparse-checkout` lines.
3. Check whether `--cone` appears in the `init` command.
4. Check which directory names appear in the `set` command.
5. Compare those names against what is in `sparseCheckoutDirectories` vs `sparseCheckoutPatterns`.
6. If `--cone` and the directory names match `sparseCheckoutDirectories` values, the
   directories property won.

### Key takeaway

> Do not set both `sparseCheckoutDirectories` and `sparseCheckoutPatterns` in the same
> checkout step. On agent v4.266.2, `sparseCheckoutDirectories` wins and `sparseCheckoutPatterns`
> is silently ignored — the opposite of what the documentation states. Advise the
> customer to choose one property and use it exclusively.

---

## Lesson 5 — Diagnosing Silent Failures and Reading the Evidence

### The customer's words

> _"Our pipeline says `partiallySucceeded` but I can't tell what went wrong. Nothing
> looks failed in the summary view."_

This is a class of problem that sparse checkout makes more likely. Here is the pattern
and how to crack it.

### Why sparse checkout causes silent failures

Every pipeline in our test suite used `continueOnError: true` on the inspection step.
This is a recommended setting for non-critical steps — it means the step can fail
without aborting the entire pipeline. The pipeline finishes, marks itself as
`partiallySucceeded`, and moves on.

When a script step fails because a file it needs is not in the workspace (because sparse
checkout excluded it), you get exactly this outcome:

1. Step starts.
2. Step calls a script at a path inside the workspace.
3. The path does not exist because sparse checkout never copied that file.
4. The shell reports "No such file or directory" with exit code 127.
5. Because `continueOnError: true`, the pipeline marks the step failed but continues.
6. The build result is `partiallySucceeded`.

Our Build 706, 707, and 708 (the first attempt at sparse builds before we added `tools/`
to the sparse scope) all failed this way. Here is the exact evidence from Build 706's
pipeline log:

```
2026-02-24T16:56:38.5398282Z bash: /home/azureuser/myagent/_work/3/s/tools/inspect-workspace.sh:
  No such file or directory
2026-02-24T16:56:38.5417532Z
2026-02-24T16:56:38.5461645Z ##[error]Bash exited with code '127'.
2026-02-24T16:56:38.5493663Z ##[section]Finishing: Inspect workspace (Bash)
```

The fix was to add `tools` to the `sparseCheckoutDirectories` (or `tools/**` to
`sparseCheckoutPatterns`) so the script was available in the workspace.

### The diagnostic checklist for a `partiallySucceeded` sparse checkout build

1. **Open the pipeline run.** In the summary view, expand each step and look for any step
   with a yellow warning icon instead of a green checkmark.

2. **Read the step log for the failing step.** Look for `##[error]` lines. Common patterns:
   - `No such file or directory` → the file at that path was excluded by sparse checkout
   - `Bash exited with code '127'` → the script itself was the missing file
   - `cannot find path` (Windows) → same issue on PowerShell steps

3. **Find the checkout step log.** Look for `##[command]git sparse-checkout set` and read
   the directory names. If a folder that your subsequent steps need is not in that list,
   it is not in the workspace.

4. **Compare the checkout step log to the YAML.** Find the `sparseCheckoutDirectories`
   or `sparseCheckoutPatterns` value in the pipeline YAML and compare it to what git
   actually ran. They should match — if they do not, you have found a conflict override
   (see Lesson 4).

5. **Check whether there is a `continueOnError: true` on the failing step.** If yes,
   the failure was swallowed. Remove it temporarily to promote the build result to
   `failed` and make the error easier to find.

### Reading `##[command]` lines as primary evidence

The `##[command]` prefix in pipeline logs marks lines where the agent is reporting the
exact command it is about to execute. These lines are your primary source of truth —
they tell you what actually ran, as opposed to what the YAML instructed. For sparse
checkout, the key lines to find are:

```
##[command]git sparse-checkout init [--cone]
##[command]git sparse-checkout set [--no-cone] <paths>
```

| What you see                       | What it means                                                   |
| ---------------------------------- | --------------------------------------------------------------- |
| `init --cone`                      | Cone mode active → root files will be present                   |
| `init` (no flag)                   | Non-cone mode active → root files absent unless pattern matches |
| `set CDN tools`                    | These exact folder names are in the workspace                   |
| `set --no-cone CDN/**`             | Pattern `CDN/**` is in the workspace filter                     |
| `set FolderA tools` (expected CDN) | `sparseCheckoutDirectories` won over `sparseCheckoutPatterns`   |

### Key takeaway

> `partiallySucceeded` with `continueOnError: true` steps is often a missing-file
> problem caused by sparse checkout. The diagnostic path is: identify the failing step →
> find the missing path → check whether that path is in the sparse checkout scope →
> add it or fix the scope. The `##[command]git sparse-checkout set` log line tells you
> exactly what is in scope.

---

## Post-Test

> You have now completed all five lessons. Take the post-test below.
> Compare your answers to the pre-test to measure what you have learned.
> **Answer key with explanations follows the post-test — do not skip ahead.**

---

### Post-Test — Topic A: git Sparse Checkout Fundamentals

**A1.** A pipeline uses `sparseCheckoutDirectories: billing`. The repository has the
following files at its root: `billing/`, `shared/`, `README.md`, `config.yml`.
What will the workspace contain?

- (a) Only `billing/`
- (b) `billing/`, `README.md`, and `config.yml`
- (c) `billing/` and `shared/`
- (d) All files — sparse checkout requires explicit opt-in

**A2.** What is the fundamental performance reason that cone mode was introduced to git,
and what is the trade-off that results in root-level files always being present?

- (a) Cone mode reduces network bandwidth; the trade-off is slower checkout speed
- (b) Cone mode uses fast prefix matching on top-level directory names instead of
  evaluating full path patterns; the trade-off is that the algorithm always includes
  root-level files as part of the prefix structure
- (c) Cone mode encrypts file transfers; the trade-off is CPU overhead at the root
- (d) Cone mode caches blob objects; the trade-off is that cached blobs are always
  written to the root

**A3.** A support customer insists that their pipeline is not downloading `FolderB/`.
They are using `sparseCheckoutPatterns: FolderA/**`. Without running the pipeline,
what do you tell them about `shared/lib.ts`, a file that lives outside of both FolderA
and FolderB?

- (a) It will be present because it is not in FolderB
- (b) It will be present because pattern mode always includes root-level files
- (c) It will be absent unless its path matches a configured pattern (it does not match
  `FolderA/**`)
- (d) It depends on whether the file was modified in the last commit

**A4.** The pipeline log for a build shows `##[command]git sparse-checkout init` with
**no flags**, followed by `##[command]git sparse-checkout set --no-cone src/**`.
Which YAML property produced this behavior?

- (a) `sparseCheckoutDirectories: src`
- (b) `sparseCheckoutPatterns: src/**`
- (c) `sparseCheckoutDirectories: src/**`
- (d) `sparseCheckoutPatterns: src` (without the `**`)

---

### Post-Test — Topic B: Azure DevOps Pipeline YAML Properties

**B1.** Rewrite the following YAML so that only `api/` and `contracts/` appear in the
workspace with zero root-level files:

```yaml
- checkout: self
  sparseCheckoutDirectories: api contracts
```

_(Write the corrected YAML — no need to pick from options.)_

**B2.** A customer is using `continueOnError: true` on several steps. Their pipeline
shows `partiallySucceeded`. They claim the build is fine and ship to production.
What risk does this create, and what would you recommend they do?

- (a) No risk — `partiallySucceeded` is the same as `succeeded` for deployment purposes
- (b) Steps that failed silently may have produced no output, missing artifacts, or
  incomplete analysis; they should audit every step with `continueOnError: true` in the
  failing build and determine whether the output of each step is actually needed
- (c) The risk is only relevant if the agent is Linux-based
- (d) They should set `continueOnError: false` globally, which prevents any partial results

**B3.** A new engineer writes a pipeline with `sparseCheckoutPatterns`. They notice
that their build tool (which lives in `tools/build.sh`) is missing from the workspace.
The sparse pattern is `src/**`. What is the single-line fix, and why does it work?

- (a) Change `src/**` to `src/**  tools/**` on the same line — patterns can be merged
- (b) Add `tools/**` as a second line under `sparseCheckoutPatterns` — each pattern on
  its own line instructs git to also match `tools/build.sh`
- (c) Set `sparseCheckoutDirectories: tools` on the same checkout step alongside patterns
- (d) Move `tools/build.sh` to the `src/` folder

---

### Post-Test — Topic C: Conflict Behavior When Both Properties Are Set

**C1.** On an Azure DevOps self-hosted agent running agent version 4.266.2 with git 2.43.0,
a pipeline has both `sparseCheckoutDirectories: deployments` and
`sparseCheckoutPatterns: src/**` set. A colleague says "the docs say patterns win so
`src/**` will be used." What is the correct response?

- (a) Your colleague is correct — follow the documentation
- (b) The documentation states patterns win but live testing on agent v4.266.2 / git 2.43.0
  shows that `sparseCheckoutDirectories` wins; advise the customer to verify by checking
  the `##[command]git sparse-checkout set` line in their build log
- (c) Neither property applies when both are set — the checkout reverts to full checkout
- (d) The documentation is correct on Windows agents but not on Linux agents

**C2.** A customer's `sparse-both` pipeline produces `SUMMARY_FAIL: 12` in the inspection
log. The inspection script was expecting `CDN/` to be present. The actual workspace
contains `FolderA/`. What is the definitive interpretation of these facts?

- (a) The inspection script has a bug
- (b) The pipeline used `sparseCheckoutDirectories` (which pointed at `FolderA`) rather
  than `sparseCheckoutPatterns` (which pointed at `CDN/**`); the 12 failures are evidence
  of how far the actual behavior deviated from the expected pattern-mode outcome
- (c) `FolderA/` and `CDN/` are the same folder under a different alias
- (d) The agent ran out of memory during checkout

---

### Post-Test — Topic D: Diagnosing Sparse Checkout Issues

**D1.** A customer sends you this log snippet and asks why their pipeline is
`partiallySucceeded`:

```
##[command]git sparse-checkout init --cone
##[command]git sparse-checkout set app
2026-02-24T10:00:01.000Z ##[section]Starting: Run deployment script
2026-02-24T10:00:01.100Z [command]/usr/bin/bash
  /home/runner/work/1/s/scripts/deploy.sh
2026-02-24T10:00:01.120Z bash: /home/runner/work/1/s/scripts/deploy.sh:
  No such file or directory
2026-02-24T10:00:01.130Z ##[error]Bash exited with code '127'.
```

What caused this and how do you fix it?

- (a) The script has a typo — `deploy.sh` does not exist in the repository
- (b) Cone mode checked out only `app/` (plus root files). The `scripts/` directory
  was not listed in `sparseCheckoutDirectories` and was therefore never copied to the
  workspace. Fix: add `scripts` to `sparseCheckoutDirectories`, or if root files are
  also unwanted, change to `sparseCheckoutPatterns: | app/** scripts/**`
- (c) The agent user does not have execute permission on the script
- (d) `bash` is not installed on this agent

**D2.** You are writing a new pipeline with `sparseCheckoutPatterns`. List the two
specific `##[command]` lines you would expect to see in the build log if the pipeline
is configured correctly for pattern mode.

_(Write the two expected log lines — no need to pick from options.)_

---

## Post-Test Answer Key

> Read through each answer and its explanation. If your post-test answer differs from
> the pre-test answer, the explanation below tells you what the lesson taught.

### Topic A Answers

**A1. Answer: (b)** — `billing/`, `README.md`, and `config.yml`  
Cone mode always includes root-level files. `billing/` was requested. `shared/` was not.
`README.md` and `config.yml` are root-level files and are always included. (Lesson 2)

**A2. Answer: (b)**  
Cone mode trades root-file exclusion control for speed. By only looking at top-level
directory prefixes, git can make include/exclude decisions without evaluating every file
path. The cost is mandatory root-file inclusion. (Lesson 2)

**A3. Answer: (c)** — `shared/lib.ts` will be absent  
Pattern mode (`sparseCheckoutPatterns`) materializes only paths that match at least one
pattern. `shared/lib.ts` does not match `FolderA/**`. It is absent. If it were needed,
`shared/**` would need to be added as a second pattern. (Lesson 3)

**A4. Answer: (b)** — `sparseCheckoutPatterns: src/**`  
The absence of `--cone` on `init` and the presence of `--no-cone` on `set` are the
diagnostic signatures of pattern mode, which is activated by `sparseCheckoutPatterns`.
(Lessons 3 and 5)

---

### Topic B Answers

**B1. Correct YAML:**

```yaml
- checkout: self
  sparseCheckoutPatterns: |
    api/**
    contracts/**
```

`sparseCheckoutDirectories` activates cone mode, which always includes root files. To
exclude root files, you must switch to `sparseCheckoutPatterns`. (Lesson 2 and 3)

**B2. Answer: (b)**  
`partiallySucceeded` means one or more steps failed but were ignored by
`continueOnError: true`. In a sparse checkout context, the failing step may have
produced no output because a required file was excluded from the workspace. Shipping
with unverified `partiallySucceeded` builds is a risk. (Lesson 5)

**B3. Answer: (b)**  
Add `tools/**` as a second line under `sparseCheckoutPatterns`. Each pattern line
independently contributes paths to the workspace. Adding `tools/**` causes git to also
write `tools/build.sh` to disk. Do not combine with `sparseCheckoutDirectories` on the
same step — see Topic C. (Lesson 3 and 4)

---

### Topic C Answers

**C1. Answer: (b)**  
The documentation states patterns win. Live build evidence on agent v4.266.2 / git 2.43.0
shows directories win. The `##[command]git sparse-checkout set` log line is the definitive
arbiter — read it, do not trust the docs blindly. (Lesson 4)

**C2. Answer: (b)**  
`SUMMARY_FAIL: 12` quantifies the deviation between expected (pattern-mode) and actual
(cone-mode) behavior. The 12 failures are not a build problem — they are structured
evidence that the wrong property won. `CDN/` absent and `FolderA/` present, in a test
where they were intentionally set to different folders, proves which property the agent
used. (Lesson 4)

---

### Topic D Answers

**D1. Answer: (b)**  
Cone mode set `app` as the only directory. `scripts/` was not listed and was therefore
absent from the workspace. The `bash: No such file or directory` message and exit code
127 are the standard indicators of this pattern. Fix: add `scripts` to the sparse
checkout scope. (Lesson 5)

**D2. Expected log lines:**

```
##[command]git sparse-checkout init
##[command]git sparse-checkout set --no-cone <your-patterns>
```

The key indicators of pattern mode: `init` has **no** `--cone` flag, and `set` uses
`--no-cone` explicitly. If you see `init --cone` instead, cone mode was activated —
which means `sparseCheckoutDirectories` was used or won a conflict. (Lesson 5)

---

## Quick-Reference Card — Use This During a Live Case

### Identify which mode is active

| Log line you see                           | Mode             | Property used               |
| ------------------------------------------ | ---------------- | --------------------------- |
| `git sparse-checkout init --cone`          | Cone             | `sparseCheckoutDirectories` |
| `git sparse-checkout init`                 | Pattern          | `sparseCheckoutPatterns`    |
| `git sparse-checkout set CDN tools`        | Cone dirs listed | Directories                 |
| `git sparse-checkout set --no-cone CDN/**` | Pattern          | Patterns                    |

### Predict workspace contents

| Property                       | Root files       | Listed folders    | Other folders |
| ------------------------------ | ---------------- | ----------------- | ------------- |
| `sparseCheckoutDirectories: X` | **YES — always** | YES               | NO            |
| `sparseCheckoutPatterns: X/**` | NO               | YES               | NO            |
| Both set (v4.266.2)            | **YES (cone)**   | Dirs value folder | NO            |

### Customer wants these outcomes → use this YAML

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

**"Only CDN and api, no root files":**

```yaml
- checkout: self
  sparseCheckoutPatterns: |
    CDN/**
    api/**
```

**"Sparse checkout but my build scripts in tools/ are missing":**

```yaml
# Add tools to whichever property you are using
sparseCheckoutDirectories: CDN tools
# or
sparseCheckoutPatterns: |
  CDN/**
  tools/**
```

### Diagnosing `partiallySucceeded`

1. Find any step with a yellow icon in the run summary
2. Open that step's log
3. Look for `##[error]` and `No such file or directory`
4. Find the path in the error — is that path inside a folder listed in sparse checkout?
5. If not, add that folder to the sparse checkout scope
6. Check: is there a `continueOnError: true` hiding the error? Remove it temporarily to
   confirm the error is real

---

## Further Reading

| Resource                                                                                                                   | Notes                                                                                                                 |
| -------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| [Azure Pipelines checkout YAML schema](https://docs.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/steps-checkout) | Official docs — read critically, the "patterns win" claim for the both-set case is not reliable on all agent versions |
| [git-sparse-checkout man page](https://git-scm.com/docs/git-sparse-checkout)                                               | Authoritative source for cone mode vs non-cone mode behavior                                                          |
| `docs/SparseCheckout-TechnicalSupportDocument.md` (this repo)                                                              | Full technical analysis with all four build results, YAML listings, and raw log evidence                              |
| `docs/SME-Validation-QA.md` (this repo)                                                                                    | Point-by-point answers to the four SME validation questions with build evidence                                       |
| Build 705 (full checkout baseline)                                                                                         | Pipeline 71, `full-checkout.yml` — all files present, clean baseline                                                  |
| Build 709 (cone mode)                                                                                                      | Pipeline 72, `sparse-directories.yml` — CDN + root files, no FolderA                                                  |
| Build 710 (pattern mode)                                                                                                   | Pipeline 73, `sparse-patterns.yml` — CDN only, ROOT_FILE_COUNT: 0                                                     |
| Build 712 (both set)                                                                                                       | Pipeline 74, `sparse-both.yml` — directories won, patterns ignored                                                    |

---

_Learning module produced by [ADEL — Azure DevOps Engineering Learner](LearningAgent-Profile.md)_  
_February 24, 2026 — Evidence base: live builds 705, 709, 710, 712_  
_Agent: v4.266.2 · git: 2.43.0 · OS: Linux_
