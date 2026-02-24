# Expected Results – Side-by-Side Comparison

This document describes exactly what the pipeline logs should show for each of
the four pipelines.  Use it to validate that your agent is behaving correctly.

---

## Legend

| Symbol | Meaning                                        |
|--------|------------------------------------------------|
| ✅      | File / directory is present in workspace       |
| ❌      | File / directory is absent from workspace      |
| ⚠️      | Presence varies by git version or agent config |

---

## 1. full-checkout.yml — Normal full checkout

**Pipeline name**: `SparseDemo_FullCheckout`  
**Evidence label**: `FULL-CHECKOUT`

### Expected directory listing

```
DIR_PRESENT        : CDN/
DIR_PRESENT        : FolderA/
DIR_PRESENT        : FolderB/
```

### Expected root-level files

```
ROOT_FILE_PRESENT  : RootFile1.yml
ROOT_FILE_PRESENT  : RootFile2.yml
ROOT_FILE_PRESENT  : config.json
ROOT_FILE_PRESENT  : root-notes.txt
```

### Sentinel table — all rows should be PASS

| Path                        | EXISTS | EXPECTED | OUTCOME |
|-----------------------------|--------|----------|---------|
| CDN/cdnfile1.txt            | YES    | YES      | PASS    |
| CDN/nested/cdnfile2.txt     | YES    | YES      | PASS    |
| FolderA/a1.txt              | YES    | YES      | PASS    |
| FolderB/b1.txt              | YES    | YES      | PASS    |
| RootFile1.yml               | YES    | YES      | PASS    |
| RootFile2.yml               | YES    | YES      | PASS    |

### Key log lines to look for

```
SUMMARY_PASS       : 14
SUMMARY_FAIL       : 0
PROOF_POSITIVE     : All PASS rows, zero FAIL rows.
```

---

## 2. sparse-directories.yml — sparseCheckoutDirectories (cone mode)

**Pipeline name**: `SparseDemo_SparseDirectories`  
**Evidence label**: `SPARSE-DIRECTORIES`

### Expected directory listing

```
DIR_PRESENT        : CDN/
```

> `FolderA/` and `FolderB/` should **not** appear.

### Expected root-level files (CONE MODE BEHAVIOUR)

```
ROOT_FILE_PRESENT  : RootFile1.yml
ROOT_FILE_PRESENT  : RootFile2.yml
ROOT_FILE_PRESENT  : config.json
ROOT_FILE_PRESENT  : root-notes.txt
```

> ⚠️ **This is expected cone-mode behaviour.** Git cone mode **always
> includes root-level tracked files** in the working tree, even when you
> request only a specific subdirectory.  This is NOT a bug.

### Sentinel table

| Path                        | EXISTS | EXPECTED | OUTCOME |
|-----------------------------|--------|----------|---------|
| CDN/cdnfile1.txt            | YES    | YES      | PASS    |
| CDN/nested/cdnfile2.txt     | YES    | YES      | PASS    |
| FolderA/a1.txt              | NO     | NO       | PASS    |
| FolderB/b1.txt              | NO     | NO       | PASS    |
| RootFile1.yml               | YES    | YES      | PASS    |
| RootFile2.yml               | YES    | YES      | PASS    |

### Key log lines to look for

```
GIT_CONE_MODE      : true
CONE_MODE_NOTE     : git cone mode materialises ALL root-level tracked files.
PROOF_POSITIVE     : RootFile1.yml PRESENT + FolderA/a1.txt ABSENT.
```

---

## 3. sparse-patterns.yml — sparseCheckoutPatterns (non-cone / pattern mode)

**Pipeline name**: `SparseDemo_SparsePatterns`  
**Evidence label**: `SPARSE-PATTERNS`

### Expected directory listing

```
DIR_PRESENT        : CDN/
```

> `FolderA/` and `FolderB/` should **not** appear.

### Expected root-level files — NONE

> No root-level files should appear.  Pattern `CDN/**` does not match files
> in the repository root.  This is the key difference from cone mode.

### Sentinel table

| Path                        | EXISTS | EXPECTED | OUTCOME |
|-----------------------------|--------|----------|---------|
| CDN/cdnfile1.txt            | YES    | YES      | PASS    |
| CDN/nested/cdnfile2.txt     | YES    | YES      | PASS    |
| FolderA/a1.txt              | NO     | NO       | PASS    |
| FolderB/b1.txt              | NO     | NO       | PASS    |
| RootFile1.yml               | NO     | NO       | PASS    |
| RootFile2.yml               | NO     | NO       | PASS    |

### Key log lines to look for

```
GIT_CONE_MODE      : false
PROOF_POSITIVE     : RootFile1.yml ABSENT + CDN/cdnfile1.txt PRESENT.
```

---

## 4. sparse-both.yml — Both set (⚠️ directories won — Build 712)

**Pipeline name**: `SparseDemo_SparseBoth`  
**Evidence label**: `SPARSE-BOTH-PATTERNS-WIN`  
**Authoritative build**: Build 712 (MCAPDevOpsOrg, agent v4.266.2, git 2.43.0)

> ⚠️ **DOCUMENTATION DISCREPANCY**  
> The Azure DevOps documentation states patterns win when both properties are
> set. **Build 712 proved the opposite on this agent version: directories won.**
> Results below reflect the **actual observed behaviour**.

### Configuration in the pipeline

```yaml
sparseCheckoutDirectories: FolderA tools   # WON on Build 712 (cone mode used)
sparseCheckoutPatterns: |                  # IGNORED on Build 712
  CDN/**
  tools/**
```

### Actual observed directory listing (Build 712)

```
DIR_PRESENT        : FolderA/
```

> `CDN/` was **absent** — patterns were silently ignored.  
> `FolderA/` was **present** — directories were honoured.

### Actual observed root-level files (CONE MODE — directories won)

```
ROOT_FILE_PRESENT  : RootFile1.yml
ROOT_FILE_PRESENT  : RootFile2.yml
ROOT_FILE_PRESENT  : config.json
ROOT_FILE_PRESENT  : root-notes.txt
```

> Root files are present because **cone mode** was used (git ran
> `sparse-checkout init --cone`). This is the key signal that directories won.

### Sentinel table — observed in Build 712

| Path                        | EXISTS | EXPECTED (per docs) | OUTCOME           |
|-----------------------------|--------|---------------------|-------------------|
| CDN/cdnfile1.txt            | NO     | YES                 | FAIL-MISSING ⚠️  |
| CDN/nested/cdnfile2.txt     | NO     | YES                 | FAIL-MISSING ⚠️  |
| FolderA/a1.txt              | YES    | NO                  | FAIL-UNEXPECTED ⚠️|
| FolderB/b1.txt              | NO     | NO                  | PASS              |
| RootFile1.yml               | YES    | NO                  | FAIL-UNEXPECTED ⚠️|
| RootFile2.yml               | YES    | NO                  | FAIL-UNEXPECTED ⚠️|

### Key log lines from Build 712

```
GIT_CONE_MODE      : true
SUMMARY_PASS       : 2
SUMMARY_FAIL       : 12
```

Raw git commands logged by the agent (from Build 712 logs):

```
##[command]git sparse-checkout init --cone
##[command]git sparse-checkout set FolderA tools
```

`CDN/**` was **never passed to git**. The agent chose `sparseCheckoutDirectories`
and discarded `sparseCheckoutPatterns` without any warning or error.

### Proof line

```
PROOF_POSITIVE     : FolderA/a1.txt PRESENT + RootFile1.yml PRESENT + CDN/ ABSENT
                     → sparseCheckoutDirectories won on agent v4.266.2 / git 2.43.0
```

---

## Summary comparison table

| Observation                    | Full | Dirs (cone) | Patterns | Both ⚠️ (dirs won — Build 712) |
|--------------------------------|------|-------------|----------|----------------------------------|
| CDN/ directory present         | ✅    | ✅           | ✅        | ❌ patterns ignored               |
| FolderA/ directory present     | ✅    | ❌           | ❌        | ⚠️ YES — dirs won                |
| FolderB/ directory present     | ✅    | ❌           | ❌        | ❌                                |
| RootFile1.yml present          | ✅    | ✅ (cone!)   | ❌        | ⚠️ YES — cone mode used          |
| RootFile2.yml present          | ✅    | ✅ (cone!)   | ❌        | ⚠️ YES — cone mode used          |
| CDN/cdnfile1.txt present       | ✅    | ✅           | ✅        | ❌ CDN absent                     |
| CDN/nested/cdnfile2.txt present| ✅    | ✅           | ✅        | ❌ CDN absent                     |
| FolderA/a1.txt present         | ✅    | ❌           | ❌        | ⚠️ YES — proves dirs won         |
| core.sparseCheckoutCone        | —    | true        | false    | true (cone mode)                  |
| SUMMARY_FAIL count             | 0    | 0           | 0        | 12 (sentinel expected CDN)        |

> ⚠️ **Key discrepancy (Build 712):** Documentation says patterns win when both
> properties are set. On agent v4.266.2 / git 2.43.0, **directories won**.
> The `Both` column above reflects **observed behaviour**, not documentation claims.
>
> - Cone mode (`sparse-directories`) → `RootFile1.yml` **PRESENT**
> - Pattern mode (`sparse-patterns`) → `RootFile1.yml` **ABSENT**
> - Both set (`sparse-both`, Build 712) → `RootFile1.yml` **PRESENT** ← directories won

---

## What to do if results differ from expected

See [Troubleshooting.md](Troubleshooting.md).
