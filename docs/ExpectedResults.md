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

## 4. sparse-both.yml — Both set (patterns win)

**Pipeline name**: `SparseDemo_SparseBoth`  
**Evidence label**: `SPARSE-BOTH-PATTERNS-WIN`

### Configuration in the pipeline

```yaml
sparseCheckoutDirectories: FolderA    # intentionally set – should be IGNORED
sparseCheckoutPatterns: |
  CDN/**                               # should WIN
```

> The directories value is **intentionally set to `FolderA`** (not CDN) so
> that if it were honoured, `FolderA/a1.txt` would appear in the workspace.
> Its absence proves that `sparseCheckoutPatterns` won.

### Expected directory listing

```
DIR_PRESENT        : CDN/
```

> `FolderA/` must **not** be present.  If it is, the agent is not following
> the documented precedence rule.

### Expected root-level files — NONE (same as pattern mode)

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
PROOF_POSITIVE     : FolderA/a1.txt ABSENT + CDN/cdnfile1.txt PRESENT + RootFile1.yml ABSENT.
```

---

## Summary comparison table

| Observation                    | Full | Dirs (cone) | Patterns | Both |
|--------------------------------|------|-------------|----------|------|
| CDN/ directory present         | ✅    | ✅           | ✅        | ✅    |
| FolderA/ directory present     | ✅    | ❌           | ❌        | ❌    |
| FolderB/ directory present     | ✅    | ❌           | ❌        | ❌    |
| RootFile1.yml present          | ✅    | ✅ (cone!)   | ❌        | ❌    |
| RootFile2.yml present          | ✅    | ✅ (cone!)   | ❌        | ❌    |
| CDN/cdnfile1.txt present       | ✅    | ✅           | ✅        | ✅    |
| CDN/nested/cdnfile2.txt present| ✅    | ✅           | ✅        | ✅    |
| FolderA/a1.txt present         | ✅    | ❌           | ❌        | ❌    |
| core.sparseCheckoutCone        | —    | true        | false    | false|
| SUMMARY_FAIL count             | 0    | 0           | 0        | 0    |

> ⚠️ **The most important distinction** is the `RootFile1.yml` row:
> - Cone mode (`sparse-directories`) → **PRESENT** (cone always includes root)
> - Pattern mode (`sparse-patterns`, `sparse-both`) → **ABSENT**

---

## What to do if results differ from expected

See [Troubleshooting.md](Troubleshooting.md).
