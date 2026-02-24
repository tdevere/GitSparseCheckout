# SME Validation — Azure DevOps Sparse Checkout Behavior

**Prepared:** February 24, 2026  
**ADO Organization:** `https://dev.azure.com/MCAPDevOpsOrg`  
**ADO Project:** `PermaSamples`  
**Repository:** `GitSparseCheckout`  
**Agent:** `MCAPDevOpsOrgADOAgent` (Agent v4.266.2, Linux, git 2.43.0)  
**Purpose:** Answer four specific SME validation questions using evidence from live pipeline
runs. Each answer includes the relevant build log output, the git commands the agent actually
issued, and a plain-English explanation suitable for a non-technical audience.

---

## Questions Under Review

> **Q1.** Sparse checkout limits file materialization, but does not prevent root-level files
> from being downloaded during the initial repo fetch.
>
> **Q2.** Azure DevOps Server initializes the full repository structure before sparse filtering
> is applied.
>
> **Q3.** There is no supported way to perform a true "single-folder-only checkout" in a
> manner that prevents root-level files and other folders from appearing in the workspace.
>
> **Q4.** Even when used with fetch filters (blobless or treeless clones), sparse checkout
> will not remove other folders or root-level files from the workspace.

---

## Q1 — "Sparse checkout limits file materialization, but does not prevent root-level files from being downloaded during the initial repo fetch."

### Verdict: Partially correct — and the distinction matters

This question conflates two separate git operations: **fetch** (network transfer) and
**checkout** (writing files to disk). They behave differently under sparse checkout.

### What actually happens in sequence on the agent

```
STEP 1  git init
STEP 2  git remote add origin <url>
STEP 3  git sparse-checkout init --cone          ← cone mode sets rules BEFORE fetch
STEP 4  git sparse-checkout set CDN tools        ← rules written to .git/info/sparse-checkout
STEP 5  git fetch origin                         ← ALL objects are negotiated (see note)
STEP 6  git checkout <commit>                    ← sparse rules applied HERE to disk writes
```

The `.git/info/sparse-checkout` file is written **before** `git fetch` runs. However, whether
git actually skips fetching blob objects depends on whether a **partial clone filter**
(`--filter=blob:none` or `--filter=tree:0`) is also in use. Azure DevOps pipelines do **not**
apply a partial clone filter by default.

### What Build 709 (`sparseCheckoutDirectories: CDN`) proves

The `##[command]` lines captured directly from the Build 709 pipeline log:

```
##[command]git sparse-checkout init --cone
##[command]git sparse-checkout set CDN tools
##[command]git -c http.extraheader="..." fetch --no-tags --prune ...
##[command]git checkout --progress --force refs/remotes/origin/main
```

The fetch step has **no `--filter` flag** — all blobs are downloaded. After checkout, root-level
files ARE present on disk despite only `CDN` being listed in `sparseCheckoutDirectories`:

```
ROOT_FILE_PRESENT  : RootFile1.yml
ROOT_FILE_PRESENT  : RootFile2.yml
ROOT_FILE_PRESENT  : config.json
ROOT_FILE_PRESENT  : root-notes.txt
ROOT_FILE_COUNT    : 6
GIT_CONE_MODE      : true
```

### Plain-English explanation

Think of the repository as a filing cabinet in a remote office. "Fetch" is the courier
bringing a copy of every document to your building's mailroom. "Checkout" is you walking
to the mailroom and deciding which documents to carry to your desk. Sparse checkout controls
what reaches **your desk** — but the full cabinet still arrived in the mailroom.

For cone mode (`sparseCheckoutDirectories`), git's cone-mode rule is: *always include all
files that live directly in the root of the cabinet, plus everything inside your chosen
folder.* This is by design — cone mode was built for performance (fast include/exclude
decisions), not for root-file exclusion.

### Corrected statement

Sparse checkout **does** prevent root-level files from being written to the workspace when
`sparseCheckoutPatterns` (non-cone mode) is used with a pattern like `CDN/**`. It does
**not** prevent root-level files from being written when `sparseCheckoutDirectories` (cone
mode) is used — cone mode always materializes root-level tracked files. Neither mode reduces
network transfer unless a separate `--filter` partial clone is configured, which Azure DevOps
does not currently configure automatically.

---

## Q2 — "Azure DevOps Server initializes the full repository structure before sparse filtering is applied."

### Verdict: Correct in effect — but the mechanism needs precision

The word "initializes" needs unpacking because there are two things being initialized:
the **git object database** (`.git/objects/`) and the **working tree** (actual files on disk).

### The git object database

When `clean: true` is set (as in all four of our test pipelines), the agent runs
`git clean -ffdx` and `git reset --hard` before checkout. The full object graph — every
commit, tree, and blob for the fetched ref — is written to `.git/objects/`. This is true
regardless of sparse checkout mode. There is no way to prevent this without a partial clone
filter.

### The working tree

This is where sparse checkout does its work. Our Build 710 (`sparseCheckoutPatterns: CDN/**`)
shows the working tree correctly restricted:

```
DIR_PRESENT        : CDN/     → YES
DIR_PRESENT        : FolderA/ → NO (not in workspace)
DIR_PRESENT        : FolderB/ → NO (not in workspace)
ROOT_FILE_COUNT    : 0
```

So the **working tree** is filtered. The **object database** is not.

### The agent checkout task execution order (agent v4.266.2)

```
1.  git version                          ← compatibility check
2.  git init                             ← creates .git/ (empty)
3.  git remote add / set-url             ← registers remote
4.  git sparse-checkout init [--cone]    ← writes sparse config
5.  git sparse-checkout set <paths>      ← writes filter rules
6.  git -c <auth> fetch <ref>            ← ALL blobs arrive (no --filter)
7.  git checkout <sha>                   ← working tree written per rules
8.  git log -1                           ← diagnostic
```

Sparse filtering at steps 4–5 happens **before** fetch at step 6, so git knows the rules.
But because there is no `--filter=blob:none` at step 6, all blobs transfer anyway. The "full
repository structure" arrives in `.git/objects/` at step 6; the working tree is selectively
populated at step 7.

### Plain-English explanation

Imagine the repository is a book manuscript stored at a publisher. The agent's "fetch" step
downloads a complete photocopy of the entire manuscript to the agent's private storage
(`.git/`). The sparse checkout rules then determine which pages get printed and placed on the
agent's desk (the working directory). The full photocopy is always made first — the printing
rules only affect what ends up on the desk.

### Corrected statement

The statement is correct in practical effect. Azure DevOps fetches all repository objects to
the agent's local git store before sparse filtering determines which files appear in the
working directory. The sparse rules control working-tree materialization, not network
transfer. Azure DevOps does not currently expose a pipeline option to add a partial clone
filter (`--filter`) to the fetch command.

---

## Q3 — "There is no supported way to perform a true 'single-folder-only checkout' in a manner that prevents root-level files and other folders from appearing in the workspace."

### Verdict: Incorrect — `sparseCheckoutPatterns` achieves this today

This is the most important correction in this document. Build 710 is direct, reproducible
evidence that a true single-folder-only working tree is achievable using a supported,
documented Azure DevOps pipeline property.

### Pipeline YAML used in Build 710

```yaml
# filepath: .azuredevops/sparse-patterns.yml
steps:
  - checkout: self
    clean: true
    persistCredentials: true
    sparseCheckoutPatterns: |
      CDN/**
      tools/**
    displayName: "Checkout (sparseCheckoutPatterns: CDN/** tools/**)"
```

> **Note:** `tools/**` is included only so the inspection scripts used in this test are
> available on the agent. In a production pipeline with no inspection step, `CDN/**` alone
> is sufficient.

### Git commands issued by the agent (from Build 710 `##[command]` log lines)

```
##[command]git sparse-checkout init
##[command]git sparse-checkout set --no-cone CDN/** tools/**
##[command]git fetch --no-tags --prune --progress --no-recurse-submodules ...
##[command]git checkout --progress --force refs/remotes/origin/main
```

The `--no-cone` flag confirms non-cone (pattern) mode. No `CDN` directory listing, no
cone semantics, no root-file side-effect.

### Build 710 inspection log (Log ID 11, 249 lines)

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

`ROOT_FILE_COUNT: 0` — zero root-level files. `SUMMARY_FAIL: 0` — every check passed.
`CDN/` is present with all nested content readable via sentinel values. `FolderA/`,
`FolderB/`, and all other directories do not exist on the agent.

### Why `sparseCheckoutPatterns` works where `sparseCheckoutDirectories` does not

| Property | Git mode | Root files | Other folders | True single-folder only? |
|---|---|---|---|---|
| `sparseCheckoutDirectories: CDN` | cone | **Always present** | Absent | ❌ Root files always appear |
| `sparseCheckoutPatterns: CDN/**` | non-cone | **Absent** | Absent | ✅ Yes |

Cone mode was designed to make large monorepo checkouts fast by using a simple
prefix-matching algorithm. As a deliberate trade-off, cone mode **always** includes all
files at the repository root. The git documentation states this explicitly:

> *"The cone mode will always include the files directly in the root directory."*  
> — `git-sparse-checkout(1)` man page

Non-cone (pattern) mode uses `.gitignore`-style pattern matching with no such constraint,
allowing `CDN/**` to match only files under `CDN/` and nothing else.

### Corrected statement

This statement is **incorrect**. Using `sparseCheckoutPatterns` with the pattern `CDN/**`
produces a working tree that contains only the `CDN/` directory and its contents. No
root-level files appear. No other folders appear. This is a supported, documented Azure
Pipelines YAML property available in both Azure DevOps Service and Azure DevOps Server.
Build 710 (`SUMMARY_PASS: 14`, `SUMMARY_FAIL: 0`, `ROOT_FILE_COUNT: 0`) is the reproducible
proof.

---

## Q4 — "Even when used with fetch filters (blobless or treeless clones), sparse checkout will not remove other folders or root-level files from the workspace."

### Verdict: Incorrect framing — fetch filters and workspace content are independent concerns

This question mixes two separate mechanisms. They must be evaluated separately.

### Part A — Working tree (files on disk the build process touches)

Fetch filters (`--filter=blob:none` for blobless, `--filter=tree:0` for treeless) are
about what git stores in `.git/objects/`. They have **no effect** on which files appear in
the working tree. Working tree content is controlled entirely by **sparse checkout rules**.

Build 710 proves that `sparseCheckoutPatterns: CDN/**` removes root-level files and other
folders from the working tree **without any fetch filter being involved**. Fetch filters are
not needed to achieve working-tree isolation.

### Part B — Object database (what git downloads from the server)

This part of the statement is **correct**. Even with `--filter=blob:none`, git still records
the full tree structure (commit objects and tree objects) — it just defers downloading blob
objects (file contents) until they are accessed. Combined with sparse checkout, blobs for
`FolderA/` would never be requested because the sparse rules prevent git from needing to
check out those files. But this is a storage and bandwidth optimization — it does not change
what appears in the working tree.

### Azure DevOps support for fetch filters today

Azure DevOps does not expose fetch filters as a first-class YAML property in the `checkout`
step. The `checkout` step supports `sparseCheckoutDirectories` and `sparseCheckoutPatterns`
but has no `filter:` property. Applying `--filter=blob:none` requires a manual script step
using raw `git` commands, which is an unsupported workaround.

### Practical guidance — matching mechanism to customer goal

| Customer goal | Mechanism needed | Supported ADO YAML property? |
|---|---|---|
| Stop other folders from appearing in workspace | `sparseCheckoutPatterns: CDN/**` | ✅ Yes |
| Stop root files from appearing in workspace | `sparseCheckoutPatterns: CDN/**` | ✅ Yes |
| Reduce network download size | `--filter=blob:none` (partial clone) | ❌ No (script workaround only) |
| Reduce `.git/objects/` disk usage | `--filter=blob:none` (partial clone) | ❌ No (script workaround only) |
| All of the above | `sparseCheckoutPatterns` + manual `--filter` | ⚠️ Partial |

For the customer's immediate stated goal — preventing root files and other folders from
appearing in the build workspace — `sparseCheckoutPatterns` alone solves the problem
completely, as demonstrated by Build 710. No fetch filter is required.

### Corrected statement

Fetch filters affect which objects git stores locally in `.git/objects/`; they do not
directly control which files appear in the working directory. Sparse checkout rules control
the working directory. The statement inverts the relationship: `sparseCheckoutPatterns:
CDN/**` **is** sufficient to produce a working directory containing only `CDN/` content,
with or without fetch filters. Fetch filters provide additional disk savings in the git
object store but are not required for working-tree isolation and are not a supported
first-class YAML property in Azure DevOps today.

---

## Consolidated Answers

| # | Customer's statement | Verdict | Build evidence |
|---|---|---|---|
| Q1 | Sparse checkout does not prevent root-level files during fetch | **Partially correct** — root files are prevented by `sparseCheckoutPatterns`; not by `sparseCheckoutDirectories`. Network transfer is unaffected either way. | Build 709 (root files present in cone mode), Build 710 (root files absent in pattern mode) |
| Q2 | ADO initializes full repository structure before sparse filtering | **Correct in effect** — all objects fetched to `.git/`; working tree filtered at checkout step | Build 710 `##[command]` sequence |
| Q3 | No supported way to perform true single-folder-only checkout | **Incorrect** — `sparseCheckoutPatterns: CDN/**` achieves this exactly | Build 710: `ROOT_FILE_COUNT: 0`, `SUMMARY_FAIL: 0` |
| Q4 | Fetch filters will not remove folders or root files from workspace | **Incorrect framing** — fetch filters are irrelevant to working-tree content; sparse checkout rules control the working tree independently | Build 710, `git-sparse-checkout(1)` documentation |

---

## Recommended YAML

Based on all four live test runs, the recommended checkout step for a single-folder-only
build is:

```yaml
steps:
  - checkout: self
    clean: true
    persistCredentials: true
    sparseCheckoutPatterns: |
      CDN/**
```

- Use `sparseCheckoutPatterns` alone
- Do **not** add `sparseCheckoutDirectories` in the same step — when both are set,
  `sparseCheckoutDirectories` wins on agent v4.266.2 (opposite of what the documentation
  states), confirmed by Build 712
- Change `CDN/**` to whichever application folder the build needs
- Root-level files will not appear; other application folders will not appear
- No changes to the agent, the git version, or the ADO server configuration are required

---

## Test Environment Reference

| Item | Value |
|---|---|
| ADO Org | `https://dev.azure.com/MCAPDevOpsOrg` |
| ADO Project | `PermaSamples` |
| Repository | `GitSparseCheckout` |
| Agent name | `MCAPDevOpsOrgADOAgent` |
| Agent version | `4.266.2` |
| Agent OS | Linux (`azureuser`) |
| git version | `2.43.0` |
| Full checkout build | **705** (Pipeline 71, `full-checkout.yml`) |
| Cone mode build | **709** (Pipeline 72, `sparse-directories.yml`) |
| Pattern mode build | **710** (Pipeline 73, `sparse-patterns.yml`) |
| Both-set build | **712** (Pipeline 74, `sparse-both.yml`) |

All build logs are retrievable via `tools/fetch-build-logs.ps1`.  
Full technical analysis is in `docs/SparseCheckout-TechnicalSupportDocument.md`.

---

*Document generated from live ADO pipeline evidence — February 24, 2026.*
