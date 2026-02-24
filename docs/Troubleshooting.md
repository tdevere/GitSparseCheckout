# Troubleshooting Guide

## Contents

1. [Git version too old](#1-git-version-too-old)
2. [Agent version too old](#2-agent-version-too-old)
3. [Sparse checkout not taking effect](#3-sparse-checkout-not-taking-effect)
4. [Root-level files appear in pattern-mode pipeline](#4-root-level-files-appear-in-pattern-mode-pipeline)
5. [All files absent after sparse checkout](#5-all-files-absent-after-sparse-checkout)
6. [Agent workspace not cleaned between runs](#6-agent-workspace-not-cleaned-between-runs)
7. [Permission errors on Windows self-hosted agents](#7-permission-errors-on-windows-self-hosted-agents)
8. [PowerShell script exits with error](#8-powershell-script-exits-with-error)
9. [Bash script not found or not executable](#9-bash-script-not-found-or-not-executable)
10. [sparse-both.yml shows FolderA materialised](#10-sparse-bothyml-shows-foldera-materialised)

---

## 1. Git version too old

### Symptom

```
##[error] No value provided for input: sparseCheckoutDirectories
```

or

```
GIT_SPARSE_LIST    : (not in sparse-checkout mode or git < 2.26)
```

### Cause

`sparseCheckoutDirectories` requires git ≥ 2.35 on the agent.  
`sparseCheckoutPatterns` requires git ≥ 2.36.

### Fix

Upgrade git on the self-hosted agent:

**Windows** (using winget):

```powershell
winget upgrade Git.Git
```

**Ubuntu / Debian**:

```bash
sudo add-apt-repository ppa:git-core/ppa -y
sudo apt-get update && sudo apt-get install -y git
```

**Verify**:

```
git --version
# Should print: git version 2.4x.x
```

---

## 2. Agent version too old

### Symptom

The `sparseCheckoutDirectories` or `sparseCheckoutPatterns` property is
silently ignored and a full checkout is performed instead.

### Cause

Azure DevOps agent support for these properties was added in:

- `sparseCheckoutDirectories` → agent ≥ 2.200
- `sparseCheckoutPatterns` → agent ≥ 2.210

### Fix

Update the self-hosted agent:

```bash
# Download the latest agent from:
# https://github.com/microsoft/azure-pipelines-agent/releases
# Re-run config.sh / config.cmd after extracting
```

Or via Azure DevOps: **Agent Pools → your pool → Agents → Update**.

---

## 3. Sparse checkout not taking effect

### Symptom

All four pipelines show identical file listings – all files present.

### Cause

- Agent is too old (see #2).
- The agent is reusing a workspace directory from a previous full checkout
  without running `git sparse-checkout`.
- `clean: true` is not propagating correctly.

### Fix

1. Confirm `clean: true` and `workspace: clean: all` are set (both are in the
   provided pipeline YAMLs).
2. Manually delete the agent work directory for the pipeline:
   - Windows: `C:\agent\_work\<build_number>\s`
   - Linux: `/home/agent/_work/<build_number>/s`
3. Run `git sparse-checkout disable` manually in the workspace and re-queue.

---

## 4. Root-level files appear in pattern-mode pipeline

### Symptom

`sparse-patterns.yml` or `sparse-both.yml` logs show:

```
ROOT_FILE_PRESENT  : RootFile1.yml
OUTCOME: FAIL-UNEXPECTED
```

### Cause

The git config `core.sparseCheckoutCone` is still `true` from a previous cone-mode
run because the workspace was not fully cleaned.

### Fix

Add a pre-checkout step (already handled by `clean: true`) or manually run:

```bash
cd <sources_dir>
git sparse-checkout disable
git sparse-checkout init --no-cone
```

Alternatively, delete the workspace directory and re-run.

---

## 5. All files absent after sparse checkout

### Symptom

`CDN/cdnfile1.txt` is absent even in `sparse-directories.yml`.

### Cause

- Pattern syntax error (e.g. trailing space after `CDN`).
- The `CDN` directory does not exist in the branch being built.
- `sparseCheckoutDirectories` value has a leading slash (`/CDN` instead of `CDN`).

### Fix

- Check that `sparseCheckoutDirectories: CDN` has no leading slash.
- Verify the branch contains the `CDN/` folder: `git ls-tree HEAD CDN/`.
- Review the agent log for the exact `git sparse-checkout set` command called.

---

## 6. Agent workspace not cleaned between runs

### Symptom

Results are inconsistent between pipeline runs on the same agent.

### Cause

Self-hosted agents reuse workspace directories by default.  
If `clean: true` is not effective, remnants from a previous checkout persist.

### Fix

Both `workspace: clean: all` (job-level) and `clean: true` (checkout step)
are configured in the provided pipelines. If problems persist:

1. Enable **Workspace cleanup** at the agent pool level in Azure DevOps UI.
2. Or add a manual cleanup step before checkout:

```yaml
- script: |
    if exist "$(Build.SourcesDirectory)" rd /s /q "$(Build.SourcesDirectory)"
  displayName: "Manual workspace cleanup (Windows)"
  condition: eq(variables['Agent.OS'], 'Windows_NT')
```

---

## 7. Permission errors on Windows self-hosted agents

### Symptom

```
##[error] Access to the path '...' is denied.
```

### Cause

The agent service account does not have write access to the work folder.

### Fix

- Ensure the agent service account (e.g. `NT AUTHORITY\NETWORK SERVICE`) has
  **Full Control** on the agent work directory (`C:\agent\_work`).
- Run the agent service as a domain user with appropriate rights.
- Do not run the inspection scripts with sudo / elevated rights – they do not
  require it.

---

## 8. PowerShell script exits with error

### Symptom

```
##[error] The term 'Get-ChildItem' is not recognized
```

or StrictMode errors.

### Cause

Script is being run by `cmd.exe` instead of `powershell.exe`/`pwsh.exe`, or
the pipeline step type is `script:` instead of `powershell:`.

### Fix

The pipeline YAMLs use `- powershell:` (not `- script:`) for Windows steps.
Verify the step type is `powershell` in the YAML. If the agent does not have
PowerShell, install it:

```powershell
winget install Microsoft.PowerShell
```

---

## 9. Bash script not found or not executable

### Symptom

```
bash: tools/inspect-workspace.sh: No such file or directory
```

### Cause

- The pipeline is set to sparse-checkout before the tools directory is present
  (i.e., `tools/` was excluded by the sparse pattern).
- Line endings are CRLF on a Linux agent.

### Fix

The inspection scripts are inside `tools/` which is NOT inside `CDN/`.  
The scripts will only be available after a **full** checkout or if `tools/`
is added to the sparse patterns. For sparse runs, the PowerShell script is
used on Windows agents. If you run sparse pipelines on Linux agents, either:

1. Add `tools/**` to `sparseCheckoutPatterns`.
2. Or inline the inspection logic directly in the pipeline YAML.

To fix CRLF issues on Linux:

```bash
git config core.autocrlf false
dos2unix tools/inspect-workspace.sh
```

---

## 10. sparse-both.yml shows FolderA materialised

### Symptom

```
DIR_PRESENT        : FolderA/
FolderA/a1.txt  EXISTS=YES  OUTCOME=FAIL-UNEXPECTED
```

### Cause

The agent or git version being used does not implement the documented precedence
rule (`sparseCheckoutPatterns` wins over `sparseCheckoutDirectories`).

### Fix

1. Check agent version: **must be ≥ 2.210** for `sparseCheckoutPatterns`.
2. Check git version: must be ≥ 2.36.
3. File a bug with the Azure DevOps team if versions are current and the
   behaviour is still incorrect.

### Workaround

Remove `sparseCheckoutDirectories` from the checkout step when using
`sparseCheckoutPatterns`. Do not rely on the precedence rule in production
pipelines if agent versions are not controlled.

---

## General diagnostics checklist

Run this checklist before filing a bug:

```
[ ] git --version         → ≥ 2.36
[ ] Agent version         → ≥ 2.210  (check Agent.Version in pipeline logs)
[ ] clean: true           → present in checkout step
[ ] workspace: clean: all → present in job definition
[ ] agentPoolName         → set to your actual self-hosted pool
[ ] Branch exists         → CDN/ directory present on the target branch
[ ] git sparse-checkout list → run manually in workspace; check output
```
