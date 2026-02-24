# Documentation Discrepancy Report

> **Artifact type**: Internal engineering feedback / ICM attachment  
> **Status**: Open — behaviour confirmed on agent v4.266.2 / git 2.43.0  
> **Date produced**: 2026-02-24  
> **Author**: MCAPDevOpsOrg / PermaSamples demo project

---

## 1. Summary

The Azure DevOps public documentation states that when both
`sparseCheckoutDirectories` and `sparseCheckoutPatterns` are set in a pipeline
`checkout` step, `sparseCheckoutPatterns` takes precedence and
`sparseCheckoutDirectories` is silently ignored.

**Live pipeline evidence from Build 712 proves the opposite on the tested
agent and git version: `sparseCheckoutDirectories` took precedence and
`sparseCheckoutPatterns` was silently ignored — with no warning, error, or
indication in the pipeline UI that one property was dropped.**

---

## 2. Documentation claim

**URL:**  
`https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/steps-checkout`

**Relevant excerpt (paraphrased):**

> _"If both `sparseCheckoutDirectories` and `sparseCheckoutPatterns` are
> specified, `sparseCheckoutPatterns` is used and `sparseCheckoutDirectories`
> is ignored."_

**Expected behaviour per documentation:**

| Property set                | Mode used              | Directories materialised  |
|-----------------------------|------------------------|---------------------------|
| `sparseCheckoutDirectories` | cone mode              | listed directories + root |
| `sparseCheckoutPatterns`    | non-cone / pattern     | matched paths only        |
| **BOTH**                    | **non-cone (patterns)** | **matched paths only**   |

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
  sparseCheckoutDirectories: FolderA tools   # intentional probe value
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
|-------------------------|---------------------|-------------|------------------|
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

| Impact area              | Description                                                                  |
|--------------------------|------------------------------------------------------------------------------|
| Customer pipelines       | Customers who rely on documented precedence (patterns win) may silently get  |
|                          | cone mode instead, materialising unintended directories and root files.      |
| Support cases            | Engineers following the documentation will give incorrect troubleshooting    |
|                          | guidance for customers on affected agent versions.                           |
| Silent failure           | No warning, error, or log indicator is emitted when one property is dropped. |
|                          | Customers have no way to discover the issue from the pipeline UI alone.      |

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

| Agent version | Git version | Behaviour                     | Source               |
|---------------|-------------|-------------------------------|----------------------|
| v4.266.2      | 2.43.0      | `sparseCheckoutDirectories` wins | Build 712 (confirmed) |
| Other versions| Unknown     | Unknown                        | Not yet tested       |

> ⚠️ This table should be expanded as additional agent/git versions are tested.
> The discrepancy may have been introduced in a specific agent version or may
> depend on a git version behaviour change.

---

## 8. Evidence artefacts

| Artefact                                              | Location                                        |
|-------------------------------------------------------|-------------------------------------------------|
| Full technical analysis (14 sections)                 | `docs/SparseCheckout-TechnicalSupportDocument.md` |
| Raw log extraction script                             | `tools/fetch-build-logs.ps1`                    |
| ADO build logs — Build 712                            | `https://dev.azure.com/MCAPDevOpsOrg/PermaSamples/_build/results?buildId=712` |
| Authoritative expected vs. observed comparison        | `docs/ExpectedResults.md` — Section 4           |
| Pipeline YAML under test                              | `.azuredevops/sparse-both.yml`                  |

---

## 9. Recommended actions

| Priority | Recommendation                                                                     |
|----------|------------------------------------------------------------------------------------|
| HIGH     | Update documentation to reflect version-dependent behaviour, or verify the claim   |
|          | on the latest agent version and correct if it no longer holds.                     |
| HIGH     | Add an explicit warning or log message when the agent silently drops one property. |
| MEDIUM   | Publish a version matrix in the documentation (agent version + git version +       |
|          | observed precedence).                                                              |
| MEDIUM   | Add a `##[warning]` in the pipeline log when both properties are set.              |
| LOW      | Consider a pipeline linting rule (e.g., in `azure-pipelines-advisor`) that flags  |
|          | use of both properties simultaneously.                                             |

---

*Prepared by: MCAPDevOpsOrg demo project, 2026-02-24*  
*Based on: Build 712 — agent v4.266.2 / git 2.43.0 / MCAPDevOpsOrg / PermaSamples*
