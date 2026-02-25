# Documentation Discrepancy Report

> **Artifact type**: Internal engineering feedback / ICM attachment  
> **Status**: Open — two findings confirmed  
> **Last updated**: 2026-02-24  
> **Author**: MCAPDevOpsOrg / PermaSamples demo project

---

## 1. Summary

This report covers **two confirmed findings** related to Azure DevOps sparse checkout
behaviour that differ from documentation or expected behaviour.

### Finding 1 — Wrong property wins (cloud ADO Services)

The Azure DevOps public documentation states that when both
`sparseCheckoutDirectories` and `sparseCheckoutPatterns` are set in a pipeline
`checkout` step, `sparseCheckoutPatterns` takes precedence and
`sparseCheckoutDirectories` is silently ignored.

**Live pipeline evidence from Build 712 proves the opposite on the tested
agent and git version: `sparseCheckoutDirectories` took precedence and
`sparseCheckoutPatterns` was silently ignored — with no warning, error, or
indication in the pipeline UI that one property was dropped.**

### Finding 2 — Properties silently ignored (ADO Server 2025 on-prem)

On Azure DevOps Server 2025 (`20.256.36719.1`), setting `sparseCheckoutDirectories`
or `sparseCheckoutPatterns` in a pipeline `checkout` step has no effect.
The pipeline succeeds and performs a full clone.  No `git sparse-checkout` command
is issued.  The task header shows `Get sources v1.0.0` — the same version label as
the cloud-hosted task — but the server-bundled binary does not implement sparse
checkout support.

> **Root cause:** ADO Server bundles task binaries at server release time.
> The cloud-hosted `Get sources v1.0.0` is continuously updated and includes
> sparse checkout support.  The ADO Server 2025 bundled binary predates that
> implementation.

---

## 2. Documentation claim

**URL:**  
`https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/steps-checkout`

**Relevant excerpt (paraphrased):**

> _"If both `sparseCheckoutDirectories` and `sparseCheckoutPatterns` are
> specified, `sparseCheckoutPatterns` is used and `sparseCheckoutDirectories`
> is ignored."_

**Expected behaviour per documentation:**

| Property set                | Mode used               | Directories materialised  |
| --------------------------- | ----------------------- | ------------------------- |
| `sparseCheckoutDirectories` | cone mode               | listed directories + root |
| `sparseCheckoutPatterns`    | non-cone / pattern      | matched paths only        |
| **BOTH**                    | **non-cone (patterns)** | **matched paths only**    |

---

## 3. Observed behaviour

**Pipeline:** `04-Sparse-Both-Patterns-Win` (Pipeline ID 74, MCAPDevOpsOrg / PermaSamples)  
**Build ID:** 712  
**Agent:** `MCAPDevOpsADOAgent`, agent v4.266.2, Linux (Ubuntu)  
**Git version:** 2.43.0  
**Checkout configuration:**

```yaml
- checkout: self
  clean: true
  persistCredentials: true
  sparseCheckoutDirectories: FolderA tools # intentional probe value
  sparseCheckoutPatterns: |
    CDN/**                                    # documented to win
    tools/**
```

**Actual raw git commands logged by the agent (from Build 712 log):**

```
##[command]git sparse-checkout init --cone
##[command]git sparse-checkout set FolderA tools
```

`CDN/**` and `tools/**` (the pattern values) were **never passed to git**.
The agent ran cone mode using `sparseCheckoutDirectories` values only.

**`git sparse-checkout list` output in the run:**

```
FolderA
tools
```

Neither `CDN` nor any pattern appeared.

---

## 4. Observed workspace state (Build 712)

| Path                    | Expected (per docs) | Observed    | Delta            |
| ----------------------- | ------------------- | ----------- | ---------------- |
| CDN/cdnfile1.txt        | PRESENT             | **ABSENT**  | ❌ Wrong         |
| CDN/nested/cdnfile2.txt | PRESENT             | **ABSENT**  | ❌ Wrong         |
| FolderA/a1.txt          | ABSENT              | **PRESENT** | ❌ Wrong         |
| FolderB/b1.txt          | ABSENT              | ABSENT      | ✅ Coincidence   |
| RootFile1.yml           | ABSENT              | **PRESENT** | ❌ Wrong (cone!) |
| RootFile2.yml           | ABSENT              | **PRESENT** | ❌ Wrong (cone!) |

**Inspection script output:**

```
SUMMARY_PASS       : 2
SUMMARY_FAIL       : 12
GIT_CONE_MODE      : true
```

`GIT_CONE_MODE: true` confirms cone mode was active — the agent chose
`sparseCheckoutDirectories` and discarded `sparseCheckoutPatterns`.

---

## 5. Impact

### Finding 1 — `sparseCheckoutDirectories` wins

| Impact area        | Description                                                                  |
| ------------------ | ---------------------------------------------------------------------------- |
| Customer pipelines | Customers who rely on documented precedence (patterns win) may silently get  |
|                    | cone mode instead, materialising unintended directories and root files.      |
| Support cases      | Engineers following the documentation will give incorrect troubleshooting    |
|                    | guidance for customers on affected agent versions.                           |
| Silent failure     | No warning, error, or log indicator is emitted when one property is dropped. |
|                    | Customers have no way to discover the issue from the pipeline UI alone.      |

### Finding 2 — ADO Server 2025 silently ignores sparse checkout properties

| Impact area        | Description                                                                  |
| ------------------ | ---------------------------------------------------------------------------- |
| Customer pipelines | Any pipeline using `sparseCheckoutDirectories` or `sparseCheckoutPatterns`   |
|                    | on ADO Server 2025 (`20.256.36719.x`) performs a full clone silently.        |
|                    | No error, warning, or log entry indicates the property was ignored.          |
| Support cases      | The task header shows `Get sources v1.0.0` on both cloud and on-prem — the   |
|                    | same label — making it impossible to distinguish from logs alone without     |
|                    | searching for the presence or absence of `git sparse-checkout` commands.     |
| Scope              | Affects all ADO Server 2025 customers using self-hosted agents. Customers    |
|                    | on ADO Server 2022 or earlier are unaffected (different task bundle).        |

---

## 6. Reproduction steps

1. Create an Azure DevOps pipeline with the following `checkout` step:

```yaml
- checkout: self
  sparseCheckoutDirectories: FolderA
  sparseCheckoutPatterns: |
    CDN/**
```

2. Run the pipeline on a self-hosted agent running agent v4.266.2 and git 2.43.0.
3. Examine the `git sparse-checkout init` and `git sparse-checkout set`
   commands in the build log.
4. Run `git sparse-checkout list` in the workspace.

**Expected (per docs):** CDN/ present, FolderA/ absent, cone mode = false  
**Observed (Build 712):** FolderA/ present, CDN/ absent, cone mode = true

---

## 7. Version matrix

### Finding 1 — Precedence behaviour when both properties set

| Agent version  | Git version        | Host                  | Behaviour                        | Source                |
| -------------- | ------------------ | --------------------- | -------------------------------- | --------------------- |
| v4.266.2       | 2.43.0 (Linux)     | Cloud ADO Services    | `sparseCheckoutDirectories` wins | Build 712 (confirmed) |
| Other versions | Unknown            | Unknown               | Unknown                          | Not yet tested        |

### Finding 2 — Sparse checkout properties silently ignored

| ADO Server version   | Agent version | Git version         | Behaviour                            | Source                              |
| -------------------- | ------------- | ------------------- | ------------------------------------ | ----------------------------------- |
| `20.256.36719.1`     | v4.266.2      | 2.51.1 (Windows)    | Properties silently ignored; full checkout | Customer case, 2026-02-24      |
| Cloud ADO Services   | v4.266.2      | 2.43.0 (Linux)      | Properties honoured; sparse checkout issued | Build 709 (confirmed)         |

> ⚠️ Both environments display `Get sources / Version: 1.0.0` in the task header.
> The version label is identical but the underlying binary differs:
> cloud ADO Services ships a continuously updated build; ADO Server 2025 bundles
> the task binary at server release time and does not receive task-level updates
> between server upgrades.
>
> This table should be expanded as additional server versions and agent versions
> are tested.

---

## 8. Evidence artefacts

| Artefact                                       | Location                                                                      |
| ---------------------------------------------- | ----------------------------------------------------------------------------- |
| Full technical analysis (14 sections)          | `docs/SparseCheckout-TechnicalSupportDocument.md`                             |
| Raw log extraction script                      | `tools/fetch-build-logs.ps1`                                                  |
| ADO build logs — Build 712 (Finding 1)         | `https://dev.azure.com/MCAPDevOpsOrg/PermaSamples/_build/results?buildId=712` |
| ADO build logs — Build 709 (dirs-only baseline)| `https://dev.azure.com/MCAPDevOpsOrg/PermaSamples/_build/results?buildId=709` |
| Authoritative expected vs. observed comparison | `docs/ExpectedResults.md` — Section 4                                         |
| Pipeline YAML under test (Finding 1)           | `.azuredevops/sparse-both.yml`                                                |
| Pipeline YAML — dirs-only (Finding 2 baseline) | `.azuredevops/sparse-dirs.yml`                                                |

---

## 9. Recommended actions

### Finding 1 — `sparseCheckoutDirectories` wins

| Priority | Recommendation                                                                     |
| -------- | ---------------------------------------------------------------------------------- |
| HIGH     | Update documentation to reflect version-dependent behaviour, or verify the claim   |
|          | on the latest agent version and correct if it no longer holds.                     |
| HIGH     | Add an explicit warning or log message when the agent silently drops one property. |
| MEDIUM   | Publish a version matrix in the documentation (agent version + git version +       |
|          | observed precedence).                                                              |
| MEDIUM   | Add a `##[warning]` in the pipeline log when both properties are set.              |
| LOW      | Consider a pipeline linting rule (e.g., in `azure-pipelines-advisor`) that flags   |
|          | use of both properties simultaneously.                                             |

### Finding 2 — ADO Server 2025 silent ignore

| Priority | Recommendation                                                                            |
| -------- | ----------------------------------------------------------------------------------------- |
| HIGH     | Document and communicate that `sparseCheckoutDirectories` / `sparseCheckoutPatterns`      |
|          | are not functional on ADO Server 2025 (`20.256.36719.x`) with the bundled task binary.    |
| HIGH     | Issue a server patch or task bundle update that includes sparse checkout support.         |
| HIGH     | Add a `##[warning]` to the task log when sparse properties are set but the server         |
|          | binary does not support them, so customers know the property was received but not acted on.|
| MEDIUM   | Provide a documented workaround (manual `git sparse-checkout` script step) in the         |
|          | ADO Server 2025 release notes and the `steps.checkout` schema reference page.             |
| LOW      | Add a server version check to the task so it can emit a clear error rather than           |
|          | silently falling back to full checkout.                                                   |

**Immediate customer workaround (Finding 2):**

Replace `sparseCheckoutDirectories` with a manual script step after a standard `checkout: self`:

```yaml
- checkout: self
  clean: true
  persistCredentials: true
  # sparseCheckoutDirectories not supported on ADO Server 2025 — use manual step below

- powershell: |
    Push-Location "$(Build.SourcesDirectory)"
    git sparse-checkout init --cone
    git sparse-checkout set CDN
    Write-Host "SPARSE_MODE_MANUAL : YES"
    Write-Host "SPARSE_DIRS_SET    : CDN"
    Pop-Location
  displayName: "Manual sparse checkout (ADO Server 2025 workaround)"
  continueOnError: false
```

> ⚠️ This workaround fetches the full repo before pruning the working tree.
> Network bandwidth is not saved. For bandwidth reduction, evaluate `fetchDepth`
> or `fetchFilter: blob:none` based on server support.

---

_Prepared by: MCAPDevOpsOrg / PermaSamples demo project, 2026-02-24_  
_Finding 1: Build 712 — agent v4.266.2 / git 2.43.0 / cloud ADO Services / MCAPDevOpsOrg_  
_Finding 2: Customer case 2026-02-24 — agent v4.266.2 / git 2.51.1 Windows / ADO Server 2025 `20.256.36719.1`_
