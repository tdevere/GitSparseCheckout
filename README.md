# Azure DevOps YAML Sparse Checkout Demo

> Demonstrates and documents the behavioural differences between Azure DevOps
> `sparseCheckoutDirectories` (git cone mode) and `sparseCheckoutPatterns`
> (git non-cone mode) on self-hosted agents, with deterministic pipeline logs.

---

## Pipelines

| Pipeline                   | File                                                                         | What it proves                                                              |
| -------------------------- | ---------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| Full checkout              | [`.azuredevops/full-checkout.yml`](.azuredevops/full-checkout.yml)           | Baseline – all files present                                                |
| Sparse directories (cone)  | [`.azuredevops/sparse-directories.yml`](.azuredevops/sparse-directories.yml) | `sparseCheckoutDirectories: CDN` materialises CDN/ **and** root-level files |
| Sparse patterns (non-cone) | [`.azuredevops/sparse-patterns.yml`](.azuredevops/sparse-patterns.yml)       | `sparseCheckoutPatterns: CDN/**` materialises only CDN/, root files absent  |
| Both set (patterns win)    | [`.azuredevops/sparse-both.yml`](.azuredevops/sparse-both.yml)               | When both are set, patterns win and directories are ignored                 |

---

## Quick concept guide

### The two sparse checkout modes explained

#### `sparseCheckoutDirectories` — Cone mode

```yaml
- checkout: self
  clean: true
  persistCredentials: true
  sparseCheckoutDirectories: CDN
```

Internally runs `git sparse-checkout set --cone CDN`.

**Key behaviour**: git cone mode **always materialises all root-level tracked
files** in addition to the requested subdirectory. This is by design in git
itself. If you request only `CDN/` and the repo has `RootFile1.yml` at the
root, that file **will** appear in the workspace.

Use this mode when you need a single subtree **and** root files (e.g. your
build script is at the root and your assets are under `CDN/`).

#### `sparseCheckoutPatterns` — Non-cone / pattern mode

```yaml
- checkout: self
  clean: true
  persistCredentials: true
  sparseCheckoutPatterns: |
    CDN/**
```

Internally runs `git sparse-checkout set --no-cone` with the given patterns.

**Key behaviour**: only files whose paths match the patterns are materialised.
Root-level files are **not** included unless you explicitly add a pattern for
them (e.g. `*.yml`).

Use this mode when you need a single subtree and explicitly do **not** want
root-level files in your workspace.

#### When both are set — patterns always win

According to the Azure DevOps documentation:

> _"If both `sparseCheckoutDirectories` and `sparseCheckoutPatterns` are
> specified, `sparseCheckoutPatterns` is used and `sparseCheckoutDirectories`
> is ignored."_

The `sparse-both.yml` pipeline proves this by intentionally setting
`sparseCheckoutDirectories: FolderA` (which would materialise FolderA if
honoured) while `sparseCheckoutPatterns: CDN/**` is also set.
The absence of `FolderA/a1.txt` in the logs confirms patterns won.

---

## Repo layout

```
.azuredevops/
│   full-checkout.yml          # Normal full checkout (baseline)
│   sparse-directories.yml     # sparseCheckoutDirectories=CDN (cone mode)
│   sparse-patterns.yml        # sparseCheckoutPatterns=CDN/** (non-cone)
│   sparse-both.yml            # Both set; proves patterns win
│
CDN/
│   cdnfile1.txt               # Sentinel – always present in CDN-targeting runs
│   cdnfile2.txt
│   styles.css
│   bundle.js
│   nested/
│       cdnfile2.txt           # Nested sentinel
│       deep/
│           asset.json         # Deeply nested sentinel
│
FolderA/
│   a1.txt                     # Sentinel – absent in all sparse runs
│   a2.txt
│
FolderB/
│   b1.txt                     # Sentinel – absent in all sparse runs
│   b2.txt
│
tools/
│   inspect-workspace.ps1      # Cross-platform inspection (PowerShell 5.1+)
│   inspect-workspace.sh       # Cross-platform inspection (bash)
│
docs/
│   README.md                  # How to run and read the results
│   ExpectedResults.md         # Side-by-side comparison of expected log output
│   Troubleshooting.md         # Common issues and fixes
│
RootFile1.yml                  # Root sentinel – present in cone mode, absent in pattern mode
RootFile2.yml                  # Root sentinel
config.json                    # Root sentinel
root-notes.txt                 # Root sentinel
```

---

## The key observable difference

| Observable                | Full | Cone (dirs) | Pattern | Both (patterns win)      |
| ------------------------- | ---- | ----------- | ------- | ------------------------ |
| `CDN/` present            | ✅   | ✅          | ✅      | ✅                       |
| `FolderA/` present        | ✅   | ❌          | ❌      | ❌                       |
| `FolderB/` present        | ✅   | ❌          | ❌      | ❌                       |
| `RootFile1.yml` present   | ✅   | ✅ ← cone!  | ❌      | ❌                       |
| `FolderA/a1.txt` present  | ✅   | ❌          | ❌      | ❌ ← proves patterns win |
| `core.sparseCheckoutCone` | —    | `true`      | `false` | `false`                  |

> **Root-level files** are the clearest signal: cone mode materialises them,
> pattern mode does not.

---

## Setup

1. Push this repository to your Azure DevOps project.
2. Create four pipelines, one per file in `.azuredevops/`.
3. Set the `agentPoolName` pipeline variable to your self-hosted pool name.
4. Run each pipeline and compare the **Inspect workspace** step logs.

Full instructions: [docs/README.md](docs/README.md)  
Expected log output: [docs/ExpectedResults.md](docs/ExpectedResults.md)  
Issues and fixes: [docs/Troubleshooting.md](docs/Troubleshooting.md)

---

## Requirements

- Git ≥ 2.36 on the self-hosted agent
- Azure DevOps Pipeline Agent ≥ 2.210
- PowerShell 5.1+ (Windows) **or** bash (Linux/macOS)
- No admin rights required; no external dependencies
