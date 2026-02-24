# Engineering Escalation — Finding 2
## ADO Server 2025: `sparseCheckoutDirectories` / `sparseCheckoutPatterns` silently ignored

| Field | Value |
|---|---|
| **Date** | 2026-02-24 |
| **Prepared by** | MCAPDevOpsOrg / PermaSamples demo project |
| **Severity** | High — documented feature silently non-functional |
| **Affects** | Azure DevOps Server 2025, version `20.256.36719.x` |
| **Does NOT affect** | Azure DevOps Services (cloud, `dev.azure.com`) |
| **Status** | Reproduced on local ADO Server instance. Awaiting engineering fix. |

---

## 1. Executive Summary

On **Azure DevOps Server 2025** (`20.256.36719.1`), setting
`sparseCheckoutDirectories` or `sparseCheckoutPatterns` in a pipeline YAML
`checkout` step has **no effect**. The pipeline succeeds and the agent
performs a **full clone** of the repository. No `git sparse-checkout`
command is issued anywhere in the build log.

The **task version label** shown in the log is identical to cloud:
`Get sources v1.0.0`. However, the **server-bundled binary** is an older
build that predates sparse checkout support. The cloud-hosted version of
the same v1.0.0 label implements sparse checkout correctly.

**The fix requires engineering to update the "Get sources" task binary
bundled with the ADO Server 2025 installer / cumulative update.**

---

## 2. Environment

| Property | Value |
|---|---|
| ADO Server version | `20.256.36719.1` (AzureDevOps25H2) |
| Server URL | `https://adoserver/DefaultCollection/` |
| Agent version | v4.260.0 |
| Agent OS | Windows (`ADOSERVER\AGENT1`) |
| git version | 2.49.0.windows.1 |
| Task label shown in log | `Get sources / Version: 1.0.0` |
| Task label on cloud | `Get sources / Version: 1.0.0` (same label, different binary) |

---

## 3. Reproduction — Test Matrix B Results

Four pipelines were run on the server (builds 100–103,
project `ADO_TEAM_PROJECT`, repo `GitSparseCheckout`).

| Build | Pipeline | Sparse property set | Expected workspace | Actual workspace | Result |
|---|---|---|---|---|---|
| **100** | B4 Full Baseline | None | All files | All files | ✅ PASS (baseline) |
| **101** | B1 Sparse Dirs | `sparseCheckoutDirectories: CDN tools` | CDN/ only | **All files** | ❌ FINDING 2 |
| **102** | B2 Sparse Patterns | `sparseCheckoutPatterns: CDN/**` | CDN/ only | **All files** | ❌ FINDING 2 |
| **103** | B3 Sparse Both | Both set | CDN/ only | **All files** | ❌ FINDING 2 |

---

## 4. Primary Evidence — Zero `git sparse-checkout` Commands

The single fastest diagnostic is to search the "Get sources" step log for
the string `sparse-checkout`. On a working implementation (cloud), this
returns at minimum:

```
##[command]git sparse-checkout init --cone
##[command]git sparse-checkout set CDN tools
```

On **ADO Server 2025**, the search returns **zero hits** across all three
sparse builds (101, 102, 103).

### Build 101 — Full "Get sources" git command sequence

This is the **complete git command log** for build 101 (`sparseCheckoutDirectories: CDN tools`).
Note the absence of any `sparse-checkout` command. The task performed a
standard full clone using `git fetch` + `git checkout`:

```
##[section]Starting: Checkout (sparseCheckoutDirectories: CDN tools)
Task         : Get sources
Version      : 1.0.0
Syncing repository: GitSparseCheckout (Git)
##[command]git version
##[command]git lfs version
##[command]git init "C:\Agents\AGENT1_vsts-agent-win-x64-4.260.0\_work\11\s"
##[command]git remote add origin https://adoserver/DefaultCollection/ADO_TEAM_PROJECT/_git/GitSparseCheckout
##[command]git config gc.auto 0
##[command]git config --get-all http.https://adoserver/DefaultCollection/ADO_TEAM_PROJECT/_git/GitSparseCheckout.extraheader
##[command]git config --get-all http.extraheader
##[command]git config --get-regexp .*extraheader
##[command]git config --get-all http.proxy
##[command]git config http.version HTTP/1.1
##[command]git --config-env=http.extraheader=env_var_http.extraheader fetch --force --tags --prune --prune-tags --progress --no-recurse-submodules origin
##[command]git --config-env=http.extraheader=env_var_http.extraheader fetch --force --tags --prune --prune-tags --progress --no-recurse-submodules origin +9e38deb90f36720979b6dc501a420697516442a1
##[command]git checkout --progress --force 9e38deb90f36720979b6dc501a420697516442a1
##[section]Finishing: Checkout (sparseCheckoutDirectories: CDN tools)
```

**There is no `git sparse-checkout` command anywhere in this sequence.**

Compare to the expected cloud sequence (from Build 712, MCAPDevOpsOrg):

```
##[command]git sparse-checkout init --cone
##[command]git sparse-checkout set FolderA tools
```

---

## 5. Workspace Inspection Evidence

The inspection script (`tools/inspect-workspace.ps1`) confirms a full
clone was materialised in all sparse builds.

### Build 100 — Baseline (FULL-CHECKOUT, expected all files)

```
INSPECTION_MODE    : FULL-CHECKOUT
DIR_PRESENT        : CDN/
DIR_PRESENT        : FolderA/
DIR_PRESENT        : FolderB/
DIR_PRESENT        : tools/
GIT_CONE_MODE      : (empty – no sparse state)
GIT_SPARSE_FLAG    : (empty – no sparse state)
SUMMARY_PASS       : 14
SUMMARY_FAIL       : 0
```

### Build 101 — Sparse Dirs (SHOULD be CDN/ only — IS all files)

```
INSPECTION_MODE    : SPARSE-DIRECTORIES
DIR_PRESENT        : CDN/
DIR_PRESENT        : FolderA/       <-- SHOULD BE ABSENT
DIR_PRESENT        : FolderB/       <-- SHOULD BE ABSENT
GIT_CONE_MODE      : (empty – sparse-checkout init never called)
GIT_SPARSE_FLAG    : (empty – sparse-checkout init never called)
SUMMARY_PASS       : 10
SUMMARY_FAIL       : 4              <-- FolderA/a1.txt, FolderA/a2.txt,
                                        FolderB/b1.txt, FolderB/b2.txt
                                        all FAIL-UNEXPECTED
```

The 4 FAIL-UNEXPECTED rows are the structural proof: files that should
have been excluded by the sparse setting are present on disk.

---

## 6. Root Cause Analysis

### What the pipeline engine does (confirmed)

The YAML parser on ADO Server 2025 **does** recognise `sparseCheckoutDirectories`
and `sparseCheckoutPatterns`. This can be confirmed from the expanded YAML
in the build preparation log (log segment 2 of any build), which shows:

```
Evaluating: in(pair['key'], 'clean', 'fetchDepth', 'fetchFilter', 'fetchTags',
'lfs', 'persistCredentials', 'submodules', 'path', 'workspaceRepo',
'sparseCheckoutDirectories', 'sparseCheckoutPatterns')
```

The properties are in the schema. They are parsed. They are passed to the task.

### What the task binary does (the bug)

The task binary bundled with ADO Server 2025 (`20.256.36719.1`) does not
contain the code path that translates `sparseCheckoutDirectories` or
`sparseCheckoutPatterns` inputs into `git sparse-checkout` commands.

The binary silently discards the inputs and falls through to a standard
full `git fetch` + `git checkout` sequence.

### Version label deception

Both the cloud-hosted and server-bundled task display `Version: 1.0.0`.
This is because the ADO task versioning scheme uses a **major version**
label, not a build-specific label. The cloud version is a continuously
updated rolling release; the server version is frozen at the time the
server installer was built.

The task binary on the server predates the commit that added
`git sparse-checkout` call sites to the "Get sources" task implementation.

### Confirming comparison

| | Cloud ADO Services | ADO Server 2025 |
|---|---|---|
| Task label | `Get sources v1.0.0` | `Get sources v1.0.0` |
| Sparse checkout supported | **YES** | **NO** |
| `git sparse-checkout init` in log | YES | ZERO |
| Working tree after sparse YAML | Sparse (correct) | Full (bug) |

---

## 7. Recommended Engineering Fix

The fix is a **task binary update** to the "Get sources" task bundled
with ADO Server 2025.

The updated binary should be identical to (or equivalent to) the cloud
version of the task, which correctly implements:

1. Check if `sparseCheckoutDirectories` or `sparseCheckoutPatterns` is set.
2. If `sparseCheckoutDirectories` is set: call `git sparse-checkout init --cone`,
   then `git sparse-checkout set <dirs>` before or after the fetch.
3. If `sparseCheckoutPatterns` is set: call `git sparse-checkout init`
   (non-cone), write the patterns to `.git/info/sparse-checkout`,
   then `git sparse-checkout reapply`.
4. If both are set: current cloud behaviour applies Finding 1 logic
   (directories wins — this is a separate issue but is acceptable).

The fix should be delivered as a **cumulative update / patch** to
ADO Server 2025 that replaces the bundled task binary without requiring
a full server upgrade.

---

## 8. Customer Workaround (Available Now)

While waiting for the server patch, customers can bypass the broken task
property using one of two YAML workarounds. The pipeline YAML for both
approaches is in `.azuredevops/server2025-workaround-sparse.yml`.

### Approach A — Post-checkout prune (simple)

```yaml
- checkout: self
  clean: true
  persistCredentials: true
  # sparseCheckoutDirectories: CDN  <-- omit; has no effect on Server 2025

- powershell: |
    Push-Location "$(Build.SourcesDirectory)"
    git sparse-checkout init --cone
    git sparse-checkout set CDN
    Write-Host "GIT_CONE_MODE       : $(git config core.sparseCheckoutCone)"
    Write-Host "GIT_SPARSE_LIST     : $(git sparse-checkout list)"
    Write-Host "WORKAROUND_STATUS   : sparse working tree applied"
    Pop-Location
  displayName: "Apply sparse checkout (Server 2025 workaround – Approach A)"
  continueOnError: false
```

> ⚠️ Full fetch still occurs before pruning. Bandwidth is not saved.
> Working tree IS sparse after the step runs.

### Approach B — Manual clone (efficient, no full fetch)

```yaml
- checkout: none   # skip the broken task entirely

- powershell: |
    $src    = "$(Build.SourcesDirectory)"
    $repo   = "$(Build.Repository.Uri)"
    $branch = "$(Build.SourceBranch)" -replace '^refs/heads/',''
    $enc    = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$env:SYSTEM_ACCESSTOKEN"))
    $hdr    = "Authorization: Basic $enc"

    if (Test-Path $src) { Remove-Item $src -Recurse -Force }
    New-Item -ItemType Directory -Path $src | Out-Null
    Push-Location $src

    git init
    git remote add origin $repo
    git sparse-checkout init --cone
    git sparse-checkout set CDN
    git -c "http.extraheader=$hdr" fetch --filter=blob:none --depth=1 origin $branch
    git checkout FETCH_HEAD

    Write-Host "GIT_CONE_MODE       : $(git config core.sparseCheckoutCone)"
    Write-Host "GIT_SPARSE_LIST     : $(git sparse-checkout list)"
    Write-Host "WORKAROUND_STATUS   : manual sparse clone complete"
    Pop-Location
  displayName: "Manual sparse clone (Server 2025 workaround – Approach B)"
  env:
    SYSTEM_ACCESSTOKEN: $(System.AccessToken)
```

> ✅ True sparse behaviour at the network level — only the named directory
> is transferred. Requires `Allow scripts to access OAuth token` enabled
> on the pipeline job.

---

## 9. Evidence Artefacts

| Artefact | Location |
|---|---|
| Reproduction pipeline YAMLs | `.azuredevops/full-checkout.yml`, `sparse-directories.yml`, `sparse-patterns.yml`, `sparse-both.yml` |
| Workaround pipeline YAML | `.azuredevops/server2025-workaround-sparse.yml` |
| Workspace inspection script | `tools/inspect-workspace.ps1` |
| Live evidence builds | Builds 100–103, `https://adoserver/DefaultCollection/ADO_TEAM_PROJECT/_build` |
| Documentation discrepancy report | `docs/DocumentationDiscrepancyReport.md` |
| Full technical analysis (14 sections) | `docs/SparseCheckout-TechnicalSupportDocument.md` |
| Expected vs observed reference | `docs/ExpectedResults.md` |
| RECO reproduction agent profile | `docs/ReproductionAgent-Profile.md` |
| Cloud baseline (Finding 1, Build 712) | `https://dev.azure.com/MCAPDevOpsOrg/PermaSamples/_build/results?buildId=712` |

---

## 10. Test Reproduction Steps for Engineering

1. Stand up an ADO Server 2025 instance at version `20.256.36719.1`.
2. Register a self-hosted agent (any OS; Windows confirmed above).
3. Import or push the `GitSparseCheckout` repository.
4. Create pipeline from `.azuredevops/sparse-directories.yml`.
5. Run the pipeline.
6. Open the "Get sources" step log.
7. Search for `sparse-checkout`.
8. **Expected (buggy) result**: zero hits.
9. **Expected (fixed) result**: `##[command]git sparse-checkout init --cone`
   followed by `##[command]git sparse-checkout set CDN tools`.

---

_End of escalation document._  
_Prepared: 2026-02-24 | Server: `adoserver` `20.256.36719.1` | Builds: 100–103_
