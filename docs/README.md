# Azure DevOps Sparse Checkout Demo – Documentation

## Purpose

This repository exists to demonstrate and document the behavioural differences
between the four sparse-checkout modes available in Azure DevOps YAML pipelines,
specifically on **self-hosted agents**.

## Repository structure

```
.azuredevops/          Azure DevOps pipeline definitions (4 pipelines)
CDN/                   Target folder for sparse checkout tests
FolderA/               Non-target folder (should be absent in sparse runs)
FolderB/               Non-target folder (should be absent in sparse runs)
docs/                  This documentation
tools/                 Cross-platform workspace inspection scripts
RootFile1.yml          Root sentinel (present in cone mode, absent in pattern mode)
RootFile2.yml          Root sentinel
config.json            Root sentinel
root-notes.txt         Root sentinel
```

## Pipelines

| Pipeline file                          | Checkout mode                        |
|----------------------------------------|--------------------------------------|
| `.azuredevops/full-checkout.yml`       | Normal full checkout                 |
| `.azuredevops/sparse-directories.yml`  | `sparseCheckoutDirectories` (cone)   |
| `.azuredevops/sparse-patterns.yml`     | `sparseCheckoutPatterns` (non-cone)  |
| `.azuredevops/sparse-both.yml`         | Both set – patterns win              |

## How to register pipelines in Azure DevOps

1. In your Azure DevOps project, go to **Pipelines → New pipeline**.
2. Choose **Azure Repos Git** (or the appropriate SCM).
3. Select **Existing Azure Pipelines YAML file**.
4. Choose one of the `.azuredevops/*.yml` files.
5. Before running, set the `agentPoolName` variable to the name of your
   self-hosted agent pool (default value is `Default`).
6. **Do not** rename the pool variable; the inspection scripts rely on the
   `SPARSE_MODE` environment variable injected by the pipeline, not the pool.

## Prerequisites

| Requirement                   | Notes                                                |
|-------------------------------|------------------------------------------------------|
| Git ≥ 2.26                    | Required for `git sparse-checkout list`              |
| Git ≥ 2.35 (recommended)      | Required for reliable cone-mode `sparseCheckoutDirectories` |
| Azure DevOps Agent ≥ 2.200    | Required for `sparseCheckoutDirectories` support     |
| Azure DevOps Agent ≥ 2.210    | Required for `sparseCheckoutPatterns` support        |
| PowerShell 5.1+ **or** bash   | For the inspection scripts                           |

## Key concepts

### sparseCheckoutDirectories (cone mode)

Uses git's **cone mode** (`git sparse-checkout set --cone`).  
Set the `sparseCheckoutDirectories` property in the `checkout` step to a
space-separated list of directory names (no leading slash, no wildcards).

```yaml
- checkout: self
  sparseCheckoutDirectories: CDN
```

**Critical behaviour**: cone mode **always materialises root-level tracked
files**, even when only a subdirectory is requested.  This is a fundamental
property of git cone mode — the working tree always includes all files
directly in the root of the repository.

### sparseCheckoutPatterns (non-cone / pattern mode)

Uses git's **non-cone mode** (`git sparse-checkout set --no-cone`).  
Set `sparseCheckoutPatterns` to a newline-separated list of glob patterns.

```yaml
- checkout: self
  sparseCheckoutPatterns: |
    CDN/**
```

Pattern mode only materialises files whose paths match the given patterns.
Root-level files are **not** materialised unless explicitly included (e.g. `*.yml`).

### When both are set – patterns win

If `sparseCheckoutDirectories` and `sparseCheckoutPatterns` are both present
in the same `checkout` step, Azure DevOps uses `sparseCheckoutPatterns` and
**silently ignores** `sparseCheckoutDirectories`.

## Running inspection scripts locally

### PowerShell (Windows)

```powershell
$env:SPARSE_MODE  = "FULL-CHECKOUT"
$env:SOURCES_DIR  = "C:\path\to\repo"
.\tools\inspect-workspace.ps1
```

### Bash (Linux / macOS)

```bash
export SPARSE_MODE="FULL-CHECKOUT"
export SOURCES_DIR="/path/to/repo"
bash tools/inspect-workspace.sh
```

## Reading the evidence

Each inspection run emits tagged lines that are easy to `grep`:

| Tag prefix              | Meaning                                          |
|-------------------------|--------------------------------------------------|
| `DIR_PRESENT`           | A top-level directory exists                     |
| `ROOT_FILE_PRESENT`     | A root-level file exists                         |
| `CONTENT_CHECK`         | Sentinel string found inside a file              |
| `GIT_SPARSE_LIST`       | Output of `git sparse-checkout list`             |
| `GIT_CONE_MODE`         | Value of `core.sparseCheckoutCone` git config    |
| `SUMMARY_PASS / _FAIL`  | Pass/fail counts for the sentinel file table     |
| `EXPECTED_BEHAVIOUR`    | Prose description of what the run should show    |
| `PROOF_POSITIVE`        | The single pair of observations that proves it   |

See [ExpectedResults.md](ExpectedResults.md) for a side-by-side comparison.

## Troubleshooting

See [Troubleshooting.md](Troubleshooting.md).
