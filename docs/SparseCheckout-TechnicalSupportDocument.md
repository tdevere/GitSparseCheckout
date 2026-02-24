# Azure DevOps Sparse Checkout — Technical Support Document

**Prepared:** February 24, 2026  
**ADO Organization:** `https://dev.azure.com/MCAPDevOpsOrg`  
**ADO Project:** `PermaSamples`  
**Repository:** `GitSparseCheckout`  
**Agent:** `MCAPDevOpsOrgADOAgent` (Agent v4.266.2, Linux, git 2.43.0)  
**Purpose:** Document the observed behavior of Azure DevOps YAML sparse checkout properties,
compare them against published documentation, and provide definitive guidance based on
live pipeline evidence.

---

## Table of Contents

1. [Background — What Is Sparse Checkout?](#1-background--what-is-sparse-checkout)
2. [The Two Sparse Checkout Properties](#2-the-two-sparse-checkout-properties)
3. [Test Repository Structure](#3-test-repository-structure)
4. [Pipeline Design — How the Tests Were Built](#4-pipeline-design--how-the-tests-were-built)
5. [Test 1 — Full Checkout (Baseline)](#5-test-1--full-checkout-baseline)
6. [Test 2 — sparseCheckoutDirectories (Cone Mode)](#6-test-2--sparsecheckoutdirectories-cone-mode)
7. [Test 3 — sparseCheckoutPatterns (Pattern Mode)](#7-test-3--sparsecheckoutpatterns-pattern-mode)
8. [Test 4 — Both Properties Set at the Same Time](#8-test-4--both-properties-set-at-the-same-time)
9. [Comparative Evidence Table](#9-comparative-evidence-table)
10. [Documentation Discrepancy — Critical Finding](#10-documentation-discrepancy--critical-finding)
11. [Root Cause Explanation](#11-root-cause-explanation)
12. [Actionable Guidance](#12-actionable-guidance)
13. [Appendix A — Full YAML Listings](#13-appendix-a--full-yaml-listings)
14. [Appendix B — Raw Log Evidence](#14-appendix-b--raw-log-evidence)

---

## 1. Background — What Is Sparse Checkout?

When Azure DevOps runs a pipeline, one of its first jobs is to **check out** the source
code from the repository onto the build agent's hard drive. Normally this means copying
**every file and folder** in the repository — this is called a *full checkout*.

**Sparse checkout** is a feature that lets you tell the pipeline "only copy a specific
subset of folders onto the agent — you don't need the rest." This matters in large
repositories where checking out the entire codebase takes a long time or uses a lot of
disk space. For example, if a pipeline only builds the `CDN/` folder, it is wasteful to
also copy `FolderA/`, `FolderB/`, and everything else.

### The "workspace" concept

Think of the build agent's hard drive as a temporary desk. During a full checkout, the
pipeline places every file from the repository on that desk. With sparse checkout, you
give the pipeline a list of folders and it only places those folders on the desk. Files
and folders that were not listed are simply never copied; they do not exist anywhere on
the agent during that build.

---

## 2. The Two Sparse Checkout Properties

Azure DevOps exposes two YAML properties for controlling sparse checkout behavior.
They work very differently despite appearing similar.

### Property A — `sparseCheckoutDirectories`

```yaml
- checkout: self
  sparseCheckoutDirectories: CDN
```

This property activates **git cone mode**. "Cone mode" is a term from the git version
control tool itself. When you use cone mode:

- The folder(s) you list — here `CDN` — are copied to the agent, including **all nested
  subfolders** inside them.
- Every **root-level file** in the repository is **also copied**, even though you did not
  ask for them. This is a fundamental property of how git cone mode works — it always
  includes files that sit directly in the root of the repository (not inside any folder).
- Any folder you did **not** list — for example `FolderA/` or `FolderB/` — is not copied.

The word "cone" refers to a visual metaphor: if you imagine the repository as an inverted
tree, cone mode draws a cone shape around your selected folder, which automatically
includes the root of the tree.

### Property B — `sparseCheckoutPatterns`

```yaml
- checkout: self
  sparseCheckoutPatterns: |
    CDN/**
```

This property activates **git non-cone pattern mode**. When you use pattern mode:

- Only the paths that **literally match** the patterns you list are copied to the agent.
- The pattern `CDN/**` means "every file inside the `CDN/` folder and its subfolders."
- Root-level files are **not** copied, because nothing in the pattern list says to copy them.
- Any folder not covered by a pattern — `FolderA/`, `FolderB/`, etc. — is not copied.

Pattern mode gives more precise control. If you want only `CDN/` and absolutely nothing
else, this is the property to use.

---

## 3. Test Repository Structure

A dedicated repository was created with a simple, predictable file layout so that the
presence or absence of each file in a build's workspace could serve as unambiguous
evidence of what sparse checkout did.

```
GitSparseCheckout/                  ← repository root
│
├── CDN/                            ← target folder for sparse tests
│   ├── cdnfile1.txt                  (SENTINEL: CDN_FILE_1_PRESENT)
│   ├── cdnfile2.txt
│   ├── cdnfile3.txt
│   └── nested/
│       ├── cdnfile2.txt              (SENTINEL: CDN_NESTED_CDNFILE2_PRESENT)
│       └── cdnfile3.txt
│
├── FolderA/                        ← used as a "decoy" in the both-set test
│   ├── a1.txt                        (SENTINEL: FOLDER_A_FILE1_PRESENT)
│   └── a2.txt
│
├── FolderB/                        ← never targeted, always expected absent
│   ├── b1.txt
│   └── b2.txt
│
├── tools/                          ← inspection scripts (must always be present)
│   ├── inspect-workspace.sh
│   └── inspect-workspace.ps1
│
├── RootFile1.yml                   ← (SENTINEL: ROOT_FILE1_PRESENT) key evidence file
├── RootFile2.yml
├── config.json
├── root-notes.txt
├── README.md
└── .gitignore
```

**Sentinel files** are files that contain a unique string inside them (e.g.,
`# SENTINEL: CDN_FILE_1_PRESENT`). The inspection script reads each sentinel file
and reports whether the content was found. This confirms not only that the file exists
on disk but that it was correctly checked out with its full contents.

The `tools/` folder contains the inspection scripts that run inside each pipeline
to report what files are present. Because sparse checkout can prevent `tools/` from
being copied to the agent (which would cause the inspection step to silently fail),
it is explicitly included in every sparse checkout configuration.

---

## 4. Pipeline Design — How the Tests Were Built

Four pipelines were created in Azure DevOps, each targeting the same repository.
Each pipeline differs only in its `checkout:` step — every other step is identical:
a banner step that prints environment information, followed by an inspection step that
walks the workspace and records exactly what files exist.

| Pipeline ID | Name | YAML File | Build ID (live run) |
|---|---|---|---|
| 71 | Full Checkout | `full-checkout.yml` | **705** |
| 72 | Sparse Directories | `sparse-directories.yml` | **709** |
| 73 | Sparse Patterns | `sparse-patterns.yml` | **710** |
| 74 | Sparse Both | `sparse-both.yml` | **712** |

All pipelines are set to `trigger: none` and `pr: none`, meaning they only run when
manually queued. This was intentional — the tests needed to be run at controlled times
to compare results.

Every checkout step includes `clean: true` (the agent clears its workspace before
checking out) and `workspace: clean: all` at the job level, ensuring that no files from
a previous build could influence results.

The inspection step that walks the workspace uses `continueOnError: true`, which means
that if the step fails (for example, because a file it expected to find is missing), the
pipeline does not immediately abort — it reports the failure in the log and continues.
This was important because a missing file is itself the evidence we were looking for.

---

## 5. Test 1 — Full Checkout (Baseline)

### Purpose

Establish a baseline. Confirm that when no sparse checkout properties are used, all
files in the repository are present on the agent. This gives us a reference point to
compare against the sparse runs.

### YAML Checkout Step

```yaml
- checkout: self
  clean: true
  persistCredentials: true
  displayName: "Checkout (full)"
```

No `sparseCheckoutDirectories` or `sparseCheckoutPatterns` properties are present.
This is a standard checkout with no restrictions.

### Live Build: 705 — Result: ✅ Succeeded

**Agent git command issued by ADO (reconstructed from log):**
```
git checkout  (standard full checkout, no sparse options)
```

**Inspection log output (Build 705, Log ID 11, 259 lines):**

```
DIR_PRESENT        : .azuredevops/
DIR_PRESENT        : .git/
DIR_PRESENT        : .github/
DIR_PRESENT        : .vscode/
DIR_PRESENT        : CDN/
DIR_PRESENT        : FolderA/
DIR_PRESENT        : FolderB/
DIR_PRESENT        : docs/
DIR_PRESENT        : tools/
DIR_COUNT          : 9
ROOT_FILE_PRESENT  : .gitignore
ROOT_FILE_PRESENT  : README.md
ROOT_FILE_PRESENT  : RootFile1.yml
ROOT_FILE_PRESENT  : RootFile2.yml
ROOT_FILE_PRESENT  : config.json
ROOT_FILE_PRESENT  : root-notes.txt
ROOT_FILE_COUNT    : 7
CONTENT_CHECK      : CDN/cdnfile1.txt → # SENTINEL: CDN_FILE_1_PRESENT
CONTENT_CHECK      : CDN/nested/cdnfile2.txt → # SENTINEL: CDN_NESTED_CDNFILE2_PRESENT
CONTENT_CHECK      : FolderA/a1.txt → # SENTINEL: FOLDER_A_FILE1_PRESENT
CONTENT_CHECK      : RootFile1.yml → # SENTINEL: ROOT_FILE1_PRESENT
GIT_CONE_MODE      : false
GIT_SPARSE_FLAG    : false
SUMMARY_MODE       : FULL-CHECKOUT
SUMMARY_PASS       : 14
SUMMARY_FAIL       : 0
PROOF_POSITIVE     : All PASS rows, zero FAIL rows.
```

### What This Tells Us

Every folder and file in the repository is present (`DIR_COUNT: 9`, all sentinels
readable). `GIT_SPARSE_FLAG: false` confirms git did not activate sparse checkout.
`SUMMARY_PASS: 14 / SUMMARY_FAIL: 0` — the inspection script ran 14 checks and all
passed. This is the expected, normal state.

> **Note:** `ROOT_FILE_COUNT: 7` includes `nul` as a cosmetic artifact from Windows stderr
> redirection on older shell commands — not a real file. The repository contains 6 real root files.

---

## 6. Test 2 — sparseCheckoutDirectories (Cone Mode)

### Purpose

Demonstrate what happens when you use `sparseCheckoutDirectories` to request only the
`CDN/` folder. The key question: do root-level files appear even though they were not
requested?

### YAML Checkout Step

```yaml
- checkout: self
  clean: true
  persistCredentials: true
  sparseCheckoutDirectories: CDN tools
  displayName: "Checkout (sparseCheckoutDirectories: CDN tools)"
```

**Note:** `tools` was added alongside `CDN` specifically so that the inspection scripts
are available on the agent. Without it, the scripts themselves would be excluded by
sparse checkout, causing the inspection step to fail silently. The behavior being tested
is the `CDN` entry — `tools` is infrastructure only.

### What ADO Does With This Setting

Azure DevOps translates `sparseCheckoutDirectories: CDN tools` into the following
git commands:

```bash
git sparse-checkout init --cone
git sparse-checkout set CDN tools
```

The `--cone` flag tells git to use cone mode. `git sparse-checkout set` tells git which
top-level folders to materialize. Git then also automatically includes all root-level
files (files sitting directly in the repository root, not inside any folder) — this
is non-negotiable in cone mode.

### Live Build: 709 — Result: ✅ Succeeded

**Inspection log output (Build 709, Log ID 11, 254 lines):**

```
DIR_PRESENT        : .git/
DIR_PRESENT        : CDN/
DIR_PRESENT        : tools/
DIR_COUNT          : 3
ROOT_FILE_PRESENT  : .gitignore
ROOT_FILE_PRESENT  : README.md
ROOT_FILE_PRESENT  : RootFile1.yml
ROOT_FILE_PRESENT  : RootFile2.yml
ROOT_FILE_PRESENT  : config.json
ROOT_FILE_PRESENT  : root-notes.txt
ROOT_FILE_COUNT    : 6
CONTENT_CHECK      : CDN/cdnfile1.txt → # SENTINEL: CDN_FILE_1_PRESENT
CONTENT_CHECK      : CDN/nested/cdnfile2.txt → # SENTINEL: CDN_NESTED_CDNFILE2_PRESENT
CONTENT_CHECK      : FolderA/a1.txt → (file not present – skipped)
CONTENT_CHECK      : RootFile1.yml → # SENTINEL: ROOT_FILE1_PRESENT
GIT_CONE_MODE      : true
GIT_SPARSE_FLAG    : true
SUMMARY_MODE       : SPARSE-DIRECTORIES
SUMMARY_PASS       : 14
SUMMARY_FAIL       : 0
CONE_MODE_NOTE     : git cone mode materialises ALL root-level tracked files.
PROOF_POSITIVE     : RootFile1.yml PRESENT + FolderA/a1.txt ABSENT.
```

### What This Tells Us

**Directories present:** Only `.git/`, `CDN/`, and `tools/` — exactly the two folders
requested, plus the git metadata folder. `FolderA/`, `FolderB/`, `.azuredevops/`, `docs/`,
`.vscode/` are all absent.

**Root files present:** All 6 root files appeared — `RootFile1.yml`, `RootFile2.yml`,
`config.json`, `root-notes.txt`, `README.md`, `.gitignore` — **even though none of these
were listed in `sparseCheckoutDirectories`**.

**`GIT_CONE_MODE: true`** — git itself confirms cone mode was activated.

**Key takeaway:** When you use `sparseCheckoutDirectories`, you will always receive all
root-level tracked files in the repository. There is no way to suppress this behavior
within cone mode — it is built into how git cone mode works at a fundamental level.
If your repository has sensitive or large files sitting in the root, they will be copied
to the agent even if you did not ask for them.

---

## 7. Test 3 — sparseCheckoutPatterns (Pattern Mode)

### Purpose

Demonstrate what happens when you use `sparseCheckoutPatterns` with the glob pattern
`CDN/**`. The key question: do root-level files appear?

### YAML Checkout Step

```yaml
- checkout: self
  clean: true
  persistCredentials: true
  sparseCheckoutPatterns: |
    CDN/**
    tools/**
  displayName: "Checkout (sparseCheckoutPatterns: CDN/** tools/**)"
```

The `|` character in YAML means the value that follows is a multi-line block. Each
line is a separate pattern. `CDN/**` means "the CDN folder and everything inside it."
`tools/**` is again included purely as infrastructure to make the inspection scripts
available.

### What ADO Does With This Setting

Azure DevOps translates `sparseCheckoutPatterns` into:

```bash
git sparse-checkout init   (no --cone flag)
git sparse-checkout set --no-cone CDN/** tools/**
```

The absence of `--cone` is critical. In non-cone (pattern) mode, git applies the
patterns as strict glob filters. Only file paths that match at least one pattern are
materialized. Root-level files do not match `CDN/**` or `tools/**`, so they are not
copied.

### Live Build: 710 — Result: ✅ Succeeded

**Inspection log output (Build 710, Log ID 11, 249 lines):**

```
DIR_PRESENT        : .git/
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
SUMMARY_MODE       : SPARSE-PATTERNS
SUMMARY_PASS       : 14
SUMMARY_FAIL       : 0
PROOF_POSITIVE     : RootFile1.yml ABSENT + CDN/cdnfile1.txt PRESENT.
```

### What This Tells Us

**Directories present:** Only `CDN/` and `tools/` (plus `.git/`). Same directory count
as Test 2.

**Root files present: zero (`ROOT_FILE_COUNT: 0`).** `RootFile1.yml`, `config.json`,
`README.md` — none of them appear. The inspection script checked for `RootFile1.yml`
explicitly and confirmed it was absent.

**`GIT_CONE_MODE: false`** — pattern mode does not use cone mode. `GIT_SPARSE_FLAG: true`
confirms sparse checkout is active, but in its non-cone form.

**Key takeaway:** `sparseCheckoutPatterns` is the property to use when you want strict
isolation — only the folders and files whose paths match your patterns will be present
on the agent. Root-level files are not included unless you explicitly add a pattern such
as `*.yml` to cover them.

---

## 8. Test 4 — Both Properties Set at the Same Time

### Purpose

The Microsoft documentation for Azure DevOps states:

> *"If both `sparseCheckoutDirectories` and `sparseCheckoutPatterns` are specified,
> `sparseCheckoutPatterns` is used and `sparseCheckoutDirectories` is ignored."*

This test was designed to verify that claim. The pipeline was configured with
**both properties set simultaneously, deliberately pointing at different folders**, so
that the presence or absence of each folder in the workspace would prove which property
"won."

### The Test Design (Why the Settings Were Chosen This Way)

```yaml
sparseCheckoutDirectories: FolderA tools
sparseCheckoutPatterns: |
  CDN/**
  tools/**
```

- `sparseCheckoutDirectories` is set to `FolderA` (plus `tools` for infrastructure).
  If directories win, the workspace will contain `FolderA/` and root files, but NOT `CDN/`.
- `sparseCheckoutPatterns` is set to `CDN/**` (plus `tools/**`). If patterns win,
  the workspace will contain `CDN/` and NO root files, but NOT `FolderA/`.

The two properties are deliberately pointing at **different** folders on purpose. This
makes the outcome unambiguous — there is no way to get both `FolderA/` and `CDN/**` from
a single sparse checkout; whichever folder appears tells us which property was used.

### YAML Checkout Step

```yaml
- checkout: self
  clean: true
  persistCredentials: true
  sparseCheckoutDirectories: FolderA tools
  sparseCheckoutPatterns: |
    CDN/**
    tools/**
  displayName: "Checkout (BOTH: directories=FolderA, patterns=CDN/** tools/** → patterns win)"
```

### What ADO Actually Did — From the Raw Build Log

The actual git commands that Azure DevOps issued to the agent during build 712 were
captured directly from the pipeline log:

```
##[command]git sparse-checkout init --cone
##[command]git sparse-checkout set FolderA tools
```

Notice: ADO executed `--cone` mode and used the `sparseCheckoutDirectories` values
(`FolderA tools`). **The `sparseCheckoutPatterns` property was completely ignored.**

After the checkout completed, the banner step ran `git sparse-checkout list` and reported:

```
FolderA
tools
```

Only `FolderA` and `tools` appear in the sparse checkout list — there is no mention of
`CDN/**` anywhere.

### Live Build: 712 — Result: ✅ Succeeded

**Inspection log output (Build 712, Log ID 11, 262 lines):**

```
DIR_PRESENT        : .git/
DIR_PRESENT        : FolderA/
DIR_PRESENT        : tools/
DIR_COUNT          : 3
ROOT_FILE_PRESENT  : .gitignore
ROOT_FILE_PRESENT  : README.md
ROOT_FILE_PRESENT  : RootFile1.yml
ROOT_FILE_PRESENT  : RootFile2.yml
ROOT_FILE_PRESENT  : config.json
ROOT_FILE_PRESENT  : root-notes.txt
ROOT_FILE_COUNT    : 6
CONTENT_CHECK      : CDN/cdnfile1.txt → (file not present – skipped)
CONTENT_CHECK      : CDN/nested/cdnfile2.txt → (file not present – skipped)
CONTENT_CHECK      : FolderA/a1.txt → # SENTINEL: FOLDER_A_FILE1_PRESENT
CONTENT_CHECK      : RootFile1.yml → # SENTINEL: ROOT_FILE1_PRESENT
GIT_CONE_MODE      : true
GIT_SPARSE_FLAG    : true
SUMMARY_MODE       : SPARSE-BOTH-PATTERNS-WIN
SUMMARY_PASS       : 2
SUMMARY_FAIL       : 12
```

### What This Tells Us

| Evidence | Expected (per docs) | Actual (observed) |
|---|---|---|
| `CDN/` present | YES (patterns win → CDN/** used) | **NO** |
| `FolderA/` present | NO (patterns win → dirs ignored) | **YES** |
| `RootFile1.yml` present | NO (pattern mode, no root files) | **YES** |
| `GIT_CONE_MODE` | false (pattern mode) | **true** (cone mode) |
| Which property won | `sparseCheckoutPatterns` | **`sparseCheckoutDirectories`** |

`SUMMARY_FAIL: 12` — the inspection script was configured to expect the pattern-mode outcome
(CDN present, FolderA absent, no root files). Because directories won instead, 12 of its
14 checks failed. **This is not a real build problem — it is the evidence.** The 12 failures
tell us precisely how far the actual behavior deviated from what the documentation promised.

---

## 9. Comparative Evidence Table

The following table summarizes the key observations across all four live builds.

| Observable | Build 705 — Full | Build 709 — Directories | Build 710 — Patterns | Build 712 — Both |
|---|:---:|:---:|:---:|:---:|
| `CDN/` in workspace | ✅ YES | ✅ YES | ✅ YES | ❌ NO |
| `FolderA/` in workspace | ✅ YES | ❌ NO | ❌ NO | ⚠️ YES |
| `FolderB/` in workspace | ✅ YES | ❌ NO | ❌ NO | ❌ NO |
| `RootFile1.yml` in workspace | ✅ YES | ⚠️ YES | ❌ NO | ⚠️ YES |
| Root file count | 7 | **6** (cone) | **0** (pattern) | **6** (cone) |
| `GIT_CONE_MODE` | false | **true** | false | **true** |
| `GIT_SPARSE_FLAG` | false | true | true | true |
| SUMMARY_PASS | 14 | 14 | 14 | **2** |
| SUMMARY_FAIL | 0 | 0 | 0 | **12** |

**Legend:** ✅ expected and present · ❌ expected absent · ⚠️ present but unexpected per documentation

---

## 10. Documentation Discrepancy — Critical Finding

### What the Documentation Says

The official Azure DevOps documentation states:

> *"If both `sparseCheckoutDirectories` and `sparseCheckoutPatterns` are specified,
> `sparseCheckoutPatterns` is used and `sparseCheckoutDirectories` is ignored."*

Source: [Azure Pipelines — Check out sources](https://docs.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/steps-checkout)

### What the Live Build Proves

Build 712 proves the opposite is true on the tested configuration.

When both properties were set, Azure DevOps:
1. Issued `git sparse-checkout init --cone` — activating cone mode
2. Issued `git sparse-checkout set FolderA tools` — using the `sparseCheckoutDirectories` values
3. Never referenced `CDN/**` or any `sparseCheckoutPatterns` values at any point

**`sparseCheckoutDirectories` won. `sparseCheckoutPatterns` was silently ignored.**

### Environment at Time of Test

This behavior was observed on:
- **Azure DevOps Agent:** v4.266.2
- **Git:** 2.43.0
- **Operating System:** Linux (Ubuntu, `azureuser`)
- **ADO Org:** `MCAPDevOpsOrg` (self-hosted agent pool `Default`)

This finding should be verified against:
- Microsoft-hosted agents (Ubuntu and Windows)
- Different agent versions
- Different git versions

The behavior may differ in other environments. The key point is that **the documentation
cannot be relied upon as a guarantee** — customers should test the actual behavior in
their own agent environment.

---

## 11. Root Cause Explanation

### Why Does Cone Mode Include Root Files?

This is not a bug — it is how git's cone mode was designed. The git project introduced
cone mode specifically for very large repositories (like the Windows OS source code)
where the standard sparse checkout was too slow because it had to evaluate complex
patterns against every single file path.

Cone mode works by a simpler rule: "give me this set of top-level folders, plus all
files that are direct children of the repository root." This simpler rule allows git
to make decisions much faster by examining only the top-level directory structure. The
trade-off is that you cannot opt out of root-level files — they are always included
as part of the design.

If a customer's repository has large files, configuration files with secrets, or files
they do not want copied to every build agent, those files should be moved into a
subdirectory rather than left at the repository root.

### Why Is There No Warning When Both Properties Are Set?

When Azure DevOps encounters both `sparseCheckoutDirectories` and `sparseCheckoutPatterns`
in the same checkout step, it appears to silently prefer one over the other without
emitting any warning in the build log. The build log for pipeline 74 (build 712) showed
no message such as "ignoring sparseCheckoutPatterns because sparseCheckoutDirectories is
also specified" — the cone mode commands were simply issued and the patterns property was
never mentioned.

This is a significant usability gap. A user who follows the documentation's guidance that
"patterns win" and writes `sparseCheckoutPatterns: CDN/**` alongside
`sparseCheckoutDirectories: FolderA` expecting CDN to be checked out will instead get
FolderA, with no indication in the log that their patterns were discarded.

---

## 12. Actionable Guidance

### Use Case 1: I want a specific folder AND I'm okay with root-level files being present

**Use `sparseCheckoutDirectories`.**

```yaml
- checkout: self
  sparseCheckoutDirectories: CDN
```

This is the simpler option and works reliably. Root-level files will always be present
alongside your target folder — plan for this.

---

### Use Case 2: I want only a specific folder and NO root-level files

**Use `sparseCheckoutPatterns` alone. Do NOT also set `sparseCheckoutDirectories`.**

```yaml
- checkout: self
  sparseCheckoutPatterns: |
    CDN/**
```

This gives strict isolation. Only paths matching `CDN/**` will be materialized. Root files,
other folders — nothing else appears.

---

### Use Case 3: I need to put both properties in the YAML

**Do not do this.** The documented behavior (patterns win) does not match observed
behavior on agent v4.266.2 / git 2.43.0 (directories win). Pick one property and use it
exclusively. If you find yourself needing both, you likely want `sparseCheckoutPatterns`
with multiple entries:

```yaml
- checkout: self
  sparseCheckoutPatterns: |
    CDN/**
    FolderA/**
    tools/**
```

This gives you all three folders in strict pattern mode — no root files, no other folders.

---

### Use Case 4: My pipeline's inspection/tool scripts are in a tools/ folder

**Add `tools` to `sparseCheckoutDirectories` or `tools/**` to `sparseCheckoutPatterns`.**

If your build scripts live in a directory that is not your target folder, sparse checkout
will exclude them and the step that calls them will fail silently (`continueOnError: true`
means the pipeline shows `partiallySucceeded` rather than `failed`, which can mask the
problem entirely). Always include infrastructure folders explicitly.

---

### Summary Decision Tree

```
Do you need root-level files to be present?
│
├─ YES → sparseCheckoutDirectories: <your-folder>
│
└─ NO
   │
   ├─ Do you only need exactly one property with no interaction risk?
   │  └─ YES → sparseCheckoutPatterns: |
   │              <your-folder>/**
   │
   └─ Do you need multiple folders without root files?
      └─ YES → sparseCheckoutPatterns: |
                 <folder1>/**
                 <folder2>/**
```

---

## 13. Appendix A — Full YAML Listings

### A1. full-checkout.yml (Pipeline ID 71)

```yaml
name: "SparseDemo_FullCheckout_$(Build.BuildId)"
trigger: none
pr: none

variables:
  - name: agentPoolName
    value: "Default"
  - name: evidenceLabel
    value: "FULL-CHECKOUT"

pool:
  name: $(agentPoolName)

jobs:
  - job: FullCheckout
    displayName: "Full Checkout – Baseline"
    workspace:
      clean: all
    steps:
      - checkout: self
        clean: true
        persistCredentials: true
        displayName: "Checkout (full)"

      - bash: |
          export SPARSE_MODE="$(evidenceLabel)"
          export SOURCES_DIR="$(Build.SourcesDirectory)"
          bash "$(Build.SourcesDirectory)/tools/inspect-workspace.sh"
        displayName: "Inspect workspace (Bash)"
        condition: ne(variables['Agent.OS'], 'Windows_NT')
        continueOnError: true
```

---

### A2. sparse-directories.yml (Pipeline ID 72)

```yaml
name: "SparseDemo_SparseDirectories_$(Build.BuildId)"
trigger: none
pr: none

variables:
  - name: agentPoolName
    value: "Default"
  - name: evidenceLabel
    value: "SPARSE-DIRECTORIES"

pool:
  name: $(agentPoolName)

jobs:
  - job: SparseDirectories
    displayName: "Sparse Checkout – sparseCheckoutDirectories (cone mode)"
    workspace:
      clean: all
    steps:
      - checkout: self
        clean: true
        persistCredentials: true
        sparseCheckoutDirectories: CDN tools
        displayName: "Checkout (sparseCheckoutDirectories: CDN tools)"

      - bash: |
          export SPARSE_MODE="$(evidenceLabel)"
          export SOURCES_DIR="$(Build.SourcesDirectory)"
          bash "$(Build.SourcesDirectory)/tools/inspect-workspace.sh"
        displayName: "Inspect workspace (Bash)"
        condition: ne(variables['Agent.OS'], 'Windows_NT')
        continueOnError: true
```

---

### A3. sparse-patterns.yml (Pipeline ID 73)

```yaml
name: "SparseDemo_SparsePatterns_$(Build.BuildId)"
trigger: none
pr: none

variables:
  - name: agentPoolName
    value: "Default"
  - name: evidenceLabel
    value: "SPARSE-PATTERNS"

pool:
  name: $(agentPoolName)

jobs:
  - job: SparsePatterns
    displayName: "Sparse Checkout – sparseCheckoutPatterns (non-cone)"
    workspace:
      clean: all
    steps:
      - checkout: self
        clean: true
        persistCredentials: true
        sparseCheckoutPatterns: |
          CDN/**
          tools/**
        displayName: "Checkout (sparseCheckoutPatterns: CDN/** tools/**)"

      - bash: |
          export SPARSE_MODE="$(evidenceLabel)"
          export SOURCES_DIR="$(Build.SourcesDirectory)"
          bash "$(Build.SourcesDirectory)/tools/inspect-workspace.sh"
        displayName: "Inspect workspace (Bash)"
        condition: ne(variables['Agent.OS'], 'Windows_NT')
        continueOnError: true
```

---

### A4. sparse-both.yml (Pipeline ID 74)

```yaml
name: "SparseDemo_SparseBoth_$(Build.BuildId)"
trigger: none
pr: none

variables:
  - name: agentPoolName
    value: "Default"
  - name: evidenceLabel
    value: "SPARSE-BOTH-PATTERNS-WIN"

pool:
  name: $(agentPoolName)

jobs:
  - job: SparseBoth
    displayName: "Sparse Checkout – Both set (patterns win)"
    workspace:
      clean: all
    steps:
      - checkout: self
        clean: true
        persistCredentials: true
        # sparseCheckoutDirectories targets FolderA — if this wins, FolderA appears.
        sparseCheckoutDirectories: FolderA tools
        # sparseCheckoutPatterns targets CDN/** — if this wins, CDN appears.
        sparseCheckoutPatterns: |
          CDN/**
          tools/**
        displayName: "Checkout (BOTH: directories=FolderA, patterns=CDN/** → patterns should win)"

      - bash: |
          export SPARSE_MODE="$(evidenceLabel)"
          export SOURCES_DIR="$(Build.SourcesDirectory)"
          bash "$(Build.SourcesDirectory)/tools/inspect-workspace.sh"
        displayName: "Inspect workspace (Bash)"
        condition: ne(variables['Agent.OS'], 'Windows_NT')
        continueOnError: true
```

---

## 14. Appendix B — Raw Log Evidence

The following are the complete evidence sections extracted from each build's inspection
log using the `tools/fetch-build-logs.ps1` script. These lines were emitted by
`tools/inspect-workspace.sh` running directly on the build agent and are unmodified
from the ADO pipeline log.

### B1. Build 705 — Full Checkout (Log ID 11, 259 lines)

```
DIR_PRESENT        : .azuredevops/
DIR_PRESENT        : .git/
DIR_PRESENT        : .github/
DIR_PRESENT        : .vscode/
DIR_PRESENT        : CDN/
DIR_PRESENT        : FolderA/
DIR_PRESENT        : FolderB/
DIR_PRESENT        : docs/
DIR_PRESENT        : tools/
DIR_COUNT          : 9
ROOT_FILE_PRESENT  : .gitignore
ROOT_FILE_PRESENT  : README.md
ROOT_FILE_PRESENT  : RootFile1.yml
ROOT_FILE_PRESENT  : RootFile2.yml
ROOT_FILE_PRESENT  : config.json
ROOT_FILE_PRESENT  : root-notes.txt
ROOT_FILE_COUNT    : 7
SENTINEL FILE CHECKS
CONTENT_CHECK      : CDN/cdnfile1.txt → # SENTINEL: CDN_FILE_1_PRESENT
CONTENT_CHECK      : CDN/nested/cdnfile2.txt → # SENTINEL: CDN_NESTED_CDNFILE2_PRESENT
CONTENT_CHECK      : FolderA/a1.txt → # SENTINEL: FOLDER_A_FILE1_PRESENT
CONTENT_CHECK      : RootFile1.yml → # SENTINEL: ROOT_FILE1_PRESENT
GIT_CONE_MODE      : false
GIT_SPARSE_FLAG    : false
SUMMARY_MODE       : FULL-CHECKOUT
SUMMARY_PASS       : 14
SUMMARY_FAIL       : 0
EXPECTED_BEHAVIOUR : All repository files should be present.
EXPECTED_BEHAVIOUR : CDN/, FolderA/, FolderB/ all materialised.
EXPECTED_BEHAVIOUR : All root-level files present.
PROOF_POSITIVE     : All PASS rows, zero FAIL rows.
```

### B2. Build 709 — sparseCheckoutDirectories (Log ID 11, 254 lines)

```
DIR_PRESENT        : .git/
DIR_PRESENT        : CDN/
DIR_PRESENT        : tools/
DIR_COUNT          : 3
ROOT_FILE_PRESENT  : .gitignore
ROOT_FILE_PRESENT  : README.md
ROOT_FILE_PRESENT  : RootFile1.yml
ROOT_FILE_PRESENT  : RootFile2.yml
ROOT_FILE_PRESENT  : config.json
ROOT_FILE_PRESENT  : root-notes.txt
ROOT_FILE_COUNT    : 6
SENTINEL FILE CHECKS
CONTENT_CHECK      : CDN/cdnfile1.txt → # SENTINEL: CDN_FILE_1_PRESENT
CONTENT_CHECK      : CDN/nested/cdnfile2.txt → # SENTINEL: CDN_NESTED_CDNFILE2_PRESENT
CONTENT_CHECK      : FolderA/a1.txt → (file not present – skipped)
CONTENT_CHECK      : RootFile1.yml → # SENTINEL: ROOT_FILE1_PRESENT
GIT_CONE_MODE      : true
GIT_SPARSE_FLAG    : true
SUMMARY_MODE       : SPARSE-DIRECTORIES
SUMMARY_PASS       : 14
SUMMARY_FAIL       : 0
EXPECTED_BEHAVIOUR : sparseCheckoutDirectories=CDN (cone mode).
EXPECTED_BEHAVIOUR : CDN/ materialised; FolderA/ and FolderB/ absent.
EXPECTED_BEHAVIOUR : Root-level files PRESENT (cone-mode always includes root).
CONE_MODE_NOTE     : git cone mode materialises ALL root-level tracked files.
PROOF_POSITIVE     : RootFile1.yml PRESENT + FolderA/a1.txt ABSENT.
```

### B3. Build 710 — sparseCheckoutPatterns (Log ID 11, 249 lines)

```
DIR_PRESENT        : .git/
DIR_PRESENT        : CDN/
DIR_PRESENT        : tools/
DIR_COUNT          : 3
ROOT_FILE_COUNT    : 0
SENTINEL FILE CHECKS
CONTENT_CHECK      : CDN/cdnfile1.txt → # SENTINEL: CDN_FILE_1_PRESENT
CONTENT_CHECK      : CDN/nested/cdnfile2.txt → # SENTINEL: CDN_NESTED_CDNFILE2_PRESENT
CONTENT_CHECK      : FolderA/a1.txt → (file not present – skipped)
CONTENT_CHECK      : RootFile1.yml → (file not present – skipped)
GIT_CONE_MODE      : false
GIT_SPARSE_FLAG    : true
SUMMARY_MODE       : SPARSE-PATTERNS
SUMMARY_PASS       : 14
SUMMARY_FAIL       : 0
EXPECTED_BEHAVIOUR : sparseCheckoutPatterns=CDN/** (non-cone / pattern mode).
EXPECTED_BEHAVIOUR : Only paths matching CDN/** are materialised.
EXPECTED_BEHAVIOUR : Root-level files ABSENT (pattern mode does not include root).
EXPECTED_BEHAVIOUR : FolderA/ and FolderB/ absent.
PROOF_POSITIVE     : RootFile1.yml ABSENT + CDN/cdnfile1.txt PRESENT.
```

### B4. Build 712 — Both Properties Set (Log ID 11, 262 lines)

```
DIR_PRESENT        : .git/
DIR_PRESENT        : FolderA/
DIR_PRESENT        : tools/
DIR_COUNT          : 3
ROOT_FILE_PRESENT  : .gitignore
ROOT_FILE_PRESENT  : README.md
ROOT_FILE_PRESENT  : RootFile1.yml
ROOT_FILE_PRESENT  : RootFile2.yml
ROOT_FILE_PRESENT  : config.json
ROOT_FILE_PRESENT  : root-notes.txt
ROOT_FILE_COUNT    : 6
SENTINEL FILE CHECKS
CONTENT_CHECK      : CDN/cdnfile1.txt → (file not present – skipped)
CONTENT_CHECK      : CDN/nested/cdnfile2.txt → (file not present – skipped)
CONTENT_CHECK      : FolderA/a1.txt → # SENTINEL: FOLDER_A_FILE1_PRESENT
CONTENT_CHECK      : RootFile1.yml → # SENTINEL: ROOT_FILE1_PRESENT
GIT_CONE_MODE      : true
GIT_SPARSE_FLAG    : true
SUMMARY_MODE       : SPARSE-BOTH-PATTERNS-WIN
SUMMARY_PASS       : 2
SUMMARY_FAIL       : 12
EXPECTED_BEHAVIOUR : BOTH sparseCheckoutDirectories=FolderA AND sparseCheckoutPatterns=CDN/** set.
EXPECTED_BEHAVIOUR : Azure DevOps uses sparseCheckoutPatterns; directories ignored.
EXPECTED_BEHAVIOUR : CDN/ materialised; FolderA/ ABSENT (proves directories ignored).
EXPECTED_BEHAVIOUR : Root-level files ABSENT (pattern mode).
```

**Git commands actually issued (captured from Build 712 raw log):**

```
##[command]git sparse-checkout init --cone
##[command]git sparse-checkout set FolderA tools
```

**`git sparse-checkout list` output (from banner step, Build 712):**

```
FolderA
tools
```

`CDN` and `CDN/**` do not appear anywhere in the git sparse-checkout state — confirming
`sparseCheckoutPatterns` was completely ignored by the agent.

---

*Document generated from live ADO pipeline evidence — February 24, 2026.*  
*Repository: `https://dev.azure.com/MCAPDevOpsOrg/PermaSamples/_git/GitSparseCheckout`*  
*All build logs are retrievable via `tools/fetch-build-logs.ps1`.*
