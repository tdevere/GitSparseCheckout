# Workaround: Sparse Checkout Silently Ignored on Azure DevOps Server 2025

**Applies to:** Azure DevOps Server 2025 (build `20.256.36719.x`)  
**Affected feature:** `sparseCheckoutDirectories` and `sparseCheckoutPatterns` pipeline YAML properties  
**Severity:** Functional regression — sparse checkout configuration is silently ignored  
**Status:** Workaround available; engineering fix pending in a future task update

---

## Problem description

When a YAML pipeline on Azure DevOps Server 2025 specifies a sparse checkout
using the `sparseCheckoutDirectories` or `sparseCheckoutPatterns` checkout
properties, the agent performs a **full clone** of the repository instead.
No error is raised and the build does not fail — the behaviour is a silent
regression.

```yaml
# This configuration is silently ignored on Server 2025:
- checkout: self
  sparseCheckoutDirectories: CDN tools   # ← has no effect
```

The agent logs show the checkout completing normally, but inspection of the
working directory confirms that all repository directories are present — not
just the ones named in the sparse property.

---

## Root cause

The regression is in the **Azure Pipelines checkout task binary** shipped
with Azure DevOps Server 2025 (`20.256.36719.x`).  The task omits the
`git sparse-checkout init` and `git sparse-checkout set` calls that prior
versions made.  The `sparseCheckoutDirectories` and `sparseCheckoutPatterns`
YAML fields are parsed correctly by the pipeline engine but are never acted
on by the task.

Confirmed evidence (from build logs on an affected agent):

```
# Expected for a sparse checkout — absent on Server 2025:
git sparse-checkout init --cone
git sparse-checkout set CDN tools

# What actually appears in the checkout log: nothing sparse-related.
```

Git itself (`2.49.0.windows.1`) is not at fault.  When sparse-checkout
commands are issued directly at the `git.exe` level, they work correctly.
This is the basis for both workarounds below.

---

## Workaround options

Two workarounds are available.  Both have been validated by automated
pipeline tests on the affected server version.  Choose based on your
repository size and network constraints.

| | Workaround A — Post-checkout prune | Workaround B — Efficient sparse clone ✓ Recommended |
|---|---|---|
| **How it works** | Full fetch by the task, then git prunes the working tree | `checkout:none`; git init + sparse config before fetch; only named subtrees transfer |
| **Network transfer** | Full repo size | Only the sparse subtrees |
| **Disk I/O** | Write all files, delete unwanted | Write only sparse files |
| **Setup complexity** | Minimal — no auth changes needed | Requires `Allow scripts to access OAuth token` |
| **Best for** | Small repos (< ~500 MB) or when OAuth token setting is unavailable | Any repo size; essential for large repos |

---

## Workaround A — Post-checkout prune

Add a `powershell` step immediately after the `checkout` step.  Remove
`sparseCheckoutDirectories` from the checkout (it is broken and will be
ignored anyway).  The script calls `git sparse-checkout` directly.

```yaml
steps:
  # 1. Full checkout — do NOT set sparseCheckoutDirectories (broken on Server 2025)
  - checkout: self
    clean: true
    persistCredentials: true

  # 2. Apply sparse checkout manually via git commands
  - powershell: |
      $ErrorActionPreference = 'Continue'
      Push-Location "$(Build.SourcesDirectory)"

      git sparse-checkout init --cone
      if ($LASTEXITCODE -ne 0) { Write-Host "##[error]sparse-checkout init failed"; exit 1 }

      # Replace 'CDN' with your target directory (or space-separate multiple dirs)
      git sparse-checkout set CDN
      if ($LASTEXITCODE -ne 0) { Write-Host "##[error]sparse-checkout set failed"; exit 1 }

      Write-Host "Sparse directories: $(git sparse-checkout list 2>&1)"
      Pop-Location
    displayName: "Apply sparse checkout (Workaround A)"
    continueOnError: false
```

**After this step**, the working tree contains only the `CDN` directory.
All other directories have been removed from the working tree (the git
object store is unaffected — a subsequent `git sparse-checkout set` can
re-include them without re-fetching).

---

## Workaround B — Efficient sparse clone (recommended)

This workaround avoids fetching blobs that will never be used.  It bypasses
the ADO checkout task entirely (`checkout: none`) and uses `git` directly,
configuring sparse checkout **before** the fetch so the server transmits
only the requested subtree.

### One-time pipeline setup

Enable the OAuth token for the pipeline.  This grants the script access
to `System.AccessToken` for git authentication.

1. Open the pipeline in Azure DevOps.
2. Select **Edit** → **...** menu → **Triggers** → **YAML** tab.
3. Under **Get sources**, check **Allow scripts to access the OAuth token**.
4. Save the pipeline.

Alternatively, the option can be set programmatically via the
`_apis/build/definitions/{id}` PATCH endpoint by adding:

```json
"options": [
  {
    "enabled": true,
    "definition": { "id": "b68d2893-4bc1-4c47-b4ef-c6ec1f1a4c3a" }
  }
]
```

### YAML

```yaml
steps:
  # 1. Skip the broken ADO checkout task entirely
  - checkout: none
    displayName: "Skip Get sources (checkout: none)"

  # 2. Sparse clone — configure BEFORE fetch so only target blobs transfer
  - powershell: |
      $ErrorActionPreference = 'Continue'
      $src    = "$(Build.SourcesDirectory)"   # empty dir; agent created it
      $repo   = "$(Build.Repository.Uri)"
      $branch = "$(Build.SourceBranch)" -replace '^refs/heads/', ''
      $token  = $env:SYSTEM_ACCESSTOKEN

      if (-not $token) {
          Write-Host "##[error]SYSTEM_ACCESSTOKEN is empty."
          Write-Host "##[error]Enable 'Allow scripts to access OAuth token' in pipeline options."
          exit 1
      }

      $b64        = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$token"))
      $authHeader = "Authorization: Basic $b64"

      Push-Location $src

      git init
      git remote add origin $repo

      # Configure sparse BEFORE fetch — this limits what the server sends
      git sparse-checkout init --cone
      git sparse-checkout set CDN          # ← replace with your target directory

      # Fetch: --filter=blob:none means only CDN blobs are transferred
      git -c "http.extraheader=$authHeader" fetch `
          --filter=blob:none --no-tags --depth=1 origin $branch

      if ($LASTEXITCODE -ne 0) {
          # Fallback: server does not support partial clone filter
          Write-Host "##[warning]blob:none filter not supported; retrying full fetch"
          git -c "http.extraheader=$authHeader" fetch `
              --no-tags --depth=1 origin $branch
      }

      git checkout FETCH_HEAD

      Write-Host "Sparse directories : $(git sparse-checkout list 2>&1)"
      Write-Host "Cone mode          : $(git config core.sparseCheckoutCone 2>&1)"
      Pop-Location
    displayName: "Sparse clone (Workaround B — efficient)"
    continueOnError: false
    env:
      SYSTEM_ACCESSTOKEN: $(System.AccessToken)
```

> **Note on `--filter=blob:none`:** This is a server-side partial clone
> filter that requires the server's git upload-pack to support it
> (`uploadpack.allowFilter = true`, enabled by default in recent git
> versions).  If the server rejects the filter, the script falls back to a
> full fetch automatically.  The working tree will still be sparse; only the
> network saving is lost.

---

## Validation evidence

The following results were produced by an automated test pipeline
(`server2025-workaround-test.yml`) running on an affected server.

**Build 107 — `succeeded`**

| Job | Result | Meaning |
|-----|--------|---------|
| `CONTROL` — native `sparseCheckoutDirectories` | `FAIL-AS-EXPECTED` | Bug confirmed: full clone performed despite sparse property set |
| `TEST_WorkaroundA` — post-checkout prune | `PASS` | Workaround A effective |
| `TEST_WorkaroundB` — wipe + re-checkout | `PASS` | Workaround B (simple) effective |
| `TEST_WorkaroundB_Efficient` — true sparse clone | `PASS` | **Workaround B-Efficient effective** |

Key evidence from the B-Efficient job log:

```
DIR_PRESENT         : CDN/
DIR_COUNT           : 1

SENTINEL_CDN        : PRESENT  (content readable, SENTINEL confirmed)
SENTINEL_FOLDERA    : ABSENT - PASS
SENTINEL_FOLDERB    : ABSENT - PASS

GIT_CONE_MODE       : true - PASS
FETCH_FILTER        : blob:none (only sparse subtree blobs fetched)

CHECK               : CDN present               PASS
CHECK               : CDN content readable      PASS
CHECK               : FolderA absent            PASS
CHECK               : FolderB absent            PASS
CHECK               : cone mode active          PASS

WORKAROUND_RESULT   : PASS
WORKAROUND_MEANING  : B-Efficient sparse clone successful - only CDN subtree materialised
```

Summary output:

```
SUMMARY_CONTROL_VERDICT  : FAIL-AS-EXPECTED    (correct - bug confirmed)
SUMMARY_WORKAROUND_A     : PASS     (workaround effective)
SUMMARY_WORKAROUND_B     : PASS     (workaround effective)
SUMMARY_WORKAROUND_BEFF  : PASS     (PREFERRED - filter clone OK)

OVERALL_VERDICT          : PASS
OVERALL_MEANING          : Bug confirmed; all workarounds proven effective.
                           B-Efficient is preferred for large repos.
```

---

## Environment at time of validation

| Property | Value |
|----------|-------|
| ADO Server version | `20.256.36719.1` (AzureDevOps25H2) |
| Agent version | `4.260.0` |
| Git version | `2.49.0.windows.1` |
| Agent OS | Windows NT |
| Validation date | 2026-02-25 |

---

## Frequently asked questions

**Q: Do I need to change my pipeline trigger or pool configuration?**  
No. Only the `checkout` step and the addition of a `powershell` step are
required.

**Q: Will this workaround break when Microsoft releases a fix?**  
Workaround A is idempotent — running `git sparse-checkout set` on an already
sparse repo is safe.  Workaround B replaces the checkout task entirely; once
the task is fixed you can remove the workaround and restore the standard
`sparseCheckoutDirectories` property.

**Q: Does `--depth=1` interact with sparse checkout?**  
`--depth=1` limits history to a single commit (shallow clone) and is
independent of sparse checkout.  Remove it if your pipeline needs full
history (e.g., for changelog generation or `git describe`).

**Q: Does this affect Linux/macOS self-hosted agents?**  
The regression is in the task binary, which is cross-platform.  The
PowerShell steps shown above use the `powershell` task (Windows).  For
Linux/macOS agents, replace `- powershell:` with `- bash:` and adjust
path separators and `[Convert]::ToBase64String` to a `base64` shell command:

```bash
ENCODED=$(printf ":%s" "$SYSTEM_ACCESSTOKEN" | base64)
AUTH_HEADER="Authorization: Basic $ENCODED"
```

---

## Reporting and tracking

If you encounter this issue, please reference this document and provide:

1. The output of `System.ServerVersion` from your pipeline (add a step:
   `Write-Host "SERVER_VERSION: $(System.ServerVersion)"`)
2. The full checkout task log showing the absence of `git sparse-checkout`
   commands
3. A directory listing of `$(Build.SourcesDirectory)` after checkout

Include these when filing a support ticket with Microsoft.
