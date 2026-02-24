# Azure DevOps YAML Sparse Checkout Demo

> Demonstrates and documents the behavioural differences between Azure DevOps
> `sparseCheckoutDirectories` (git cone mode) and `sparseCheckoutPatterns`
> (git non-cone mode) on self-hosted agents, with deterministic pipeline logs.

---

## Live demo — MCAPDevOpsOrg / PermaSamples

**Repository:**
[`PermaSamples / GitSparseCheckout`](https://dev.azure.com/MCAPDevOpsOrg/PermaSamples/_git/GitSparseCheckout)

**Pipelines (run manually — `trigger: none`):**

| #   | Pipeline name               | ADO link                                                                         | Pipeline ID |
| --- | --------------------------- | -------------------------------------------------------------------------------- | ----------- |
| 1   | 01-Full-Checkout            | [Run ▶](https://dev.azure.com/MCAPDevOpsOrg/PermaSamples/_build?definitionId=71) | 71          |
| 2   | 02-Sparse-Directories       | [Run ▶](https://dev.azure.com/MCAPDevOpsOrg/PermaSamples/_build?definitionId=72) | 72          |
| 3   | 03-Sparse-Patterns          | [Run ▶](https://dev.azure.com/MCAPDevOpsOrg/PermaSamples/_build?definitionId=73) | 73          |
| 4   | 04-Sparse-Both-Patterns-Win | [Run ▶](https://dev.azure.com/MCAPDevOpsOrg/PermaSamples/_build?definitionId=74) | 74          |

> **Before running**: ensure a self-hosted agent is registered in the `Default`
> pool of this org, **or** override the `agentPoolName` variable at queue time
> to match your pool. All pipelines have `trigger: none` — queue them manually.

---

## Pipelines

| Pipeline                   | File                                                                         | What it proves                                                                                      |
| -------------------------- | ---------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Full checkout              | [`.azuredevops/full-checkout.yml`](.azuredevops/full-checkout.yml)           | Baseline – all files present                                                                        |
| Sparse directories (cone)  | [`.azuredevops/sparse-directories.yml`](.azuredevops/sparse-directories.yml) | `sparseCheckoutDirectories: CDN` materialises CDN/ **and** root-level files                         |
| Sparse patterns (non-cone) | [`.azuredevops/sparse-patterns.yml`](.azuredevops/sparse-patterns.yml)       | `sparseCheckoutPatterns: CDN/**` materialises only CDN/, root files absent                          |
| Both set (dirs win ⚠️)     | [`.azuredevops/sparse-both.yml`](.azuredevops/sparse-both.yml)               | When both are set, **directories won** on agent v4.266.2 / git 2.43.0 — contradicting documentation |

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

#### When both are set — ⚠️ DOCUMENTATION DISCREPANCY

According to the Azure DevOps documentation:

> _"If both `sparseCheckoutDirectories` and `sparseCheckoutPatterns` are
> specified, `sparseCheckoutPatterns` is used and `sparseCheckoutDirectories`
> is ignored."_

**However, live pipeline evidence (Build 712, agent v4.266.2, git 2.43.0)
proves the opposite: `sparseCheckoutDirectories` WON.**

The `sparse-both.yml` pipeline was configured with
`sparseCheckoutDirectories: FolderA` and `sparseCheckoutPatterns: CDN/**`.
Build 712 showed `FolderA/a1.txt` **PRESENT** and `CDN/cdnfile1.txt`
**ABSENT**, confirming that the agent used cone mode (directories) and
silently ignored the patterns property.

Build 712 raw log evidence:

```
##[command]git sparse-checkout init --cone
##[command]git sparse-checkout set FolderA tools
```

`CDN/**` was never passed to git. `SUMMARY_FAIL: 12` in that run reflects
sentinel checks that expected CDN files but found FolderA files instead.

> **Recommendation**: do not rely on this precedence behaviour across agent
> versions. Test explicitly on your target agent version.
> See: `docs/SparseCheckout-TechnicalSupportDocument.md` — Section 8.

---

## Repo layout

```
.azuredevops/
│   full-checkout.yml          # Normal full checkout (baseline)
│   sparse-directories.yml     # sparseCheckoutDirectories=CDN (cone mode)
│   sparse-patterns.yml        # sparseCheckoutPatterns=CDN/** (non-cone)
│   sparse-both.yml            # Both set; ⚠️ dirs won on Build 712 (contradicts docs)
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

| Observable                | Full | Cone (dirs) | Pattern | Both (⚠️ dirs won — Build 712) |
| ------------------------- | ---- | ----------- | ------- | ------------------------------ |
| `CDN/` present            | ✅   | ✅          | ✅      | ❌ ← patterns ignored          |
| `FolderA/` present        | ✅   | ❌          | ❌      | ⚠️ YES ← dirs won              |
| `FolderB/` present        | ✅   | ❌          | ❌      | ❌                             |
| `RootFile1.yml` present   | ✅   | ✅ ← cone!  | ❌      | ⚠️ YES ← cone mode used!       |
| `FolderA/a1.txt` present  | ✅   | ❌          | ❌      | ⚠️ YES ← proves dirs won       |
| `core.sparseCheckoutCone` | —    | `true`      | `false` | `true` ← cone mode             |

> **Root-level files** are the clearest signal: cone mode materialises them,
> pattern mode does not.

---

## Setup

The repo and all 4 pipelines are already created in
[MCAPDevOpsOrg / PermaSamples](https://dev.azure.com/MCAPDevOpsOrg/PermaSamples).

To run the demo:

1. Register a self-hosted agent in the `Default` pool of the org — **or**
   queue each pipeline and override `agentPoolName` with your pool name.
2. Run the 4 pipelines (use the links in the **Live demo** section above).
3. Compare the **Inspect workspace** step logs across all 4 runs.

To reproduce in a different org:

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
