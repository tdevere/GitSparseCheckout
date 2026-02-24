# GitHub Copilot Instructions

> These instructions apply to all AI-assisted code generation in this
> repository.  Follow them strictly when suggesting edits to any file here.

---

## Repository purpose

This is a demonstration and documentation repository for Azure DevOps YAML
pipeline sparse checkout behaviour on self-hosted agents.  All code exists
to produce **deterministic, comparable pipeline logs** – not to build a
production application.

---

## Coding conventions

### General

- Prefer **readability over cleverness**.  Log output must be human-readable
  without post-processing.
- Every log line that carries evidence must start with a **SCREAMING_SNAKE_CASE
  tag** followed by spaces and a colon, e.g. `SENTINEL_CHECK  : ...`.
  This makes the logs `grep`-able.
- Do not introduce randomness, UUIDs, or timestamps as part of evidence values.
  Timestamps for inspection reports are acceptable in the header only.
- Keep sentinel strings **stable** – do not change `SENTINEL: FOO_PRESENT`
  values once set; pipelines and tests rely on them.

### PowerShell scripts (`tools/inspect-workspace.ps1`)

- Compatible with **Windows PowerShell 5.1** and PowerShell 7+.
- Use `Set-StrictMode -Version 2.0`.
- Use `$ErrorActionPreference = 'Continue'` – never abort the build.
- Never use `exit 1`; always `exit 0`.
- Use `[ordered]@{}` for sentinel dictionaries to guarantee stable output order.
- Use `Write-Host` (not `Write-Output`) so that log sinks capture the text.
- Avoid aliases (`gci` → `Get-ChildItem`, `%` → `ForEach-Object`).
- Path separators: use `[System.IO.Path]::DirectorySeparatorChar` when building
  full paths; store relative paths with forward slashes and convert when needed.
- Do not require admin rights; do not use `Start-Process -Verb RunAs`.

### Shell scripts (`tools/inspect-workspace.sh`)

- Target **bash 3.2+** (macOS ships with bash 3.2).
- The shebang must be `#!/usr/bin/env bash`.
- Use `set -u` (treat unset vars as errors) but guard reads appropriately.
- Do **not** use `set -e` – the script must always complete and return 0.
- Avoid bashisms that require bash 4+ (e.g. associative arrays `declare -A`).
- Quote all variable expansions: `"${VAR}"`, `"${array[@]}"`.
- Use `|| true` after commands that may fail when you want to continue.
- Do not require `sudo`, `jq`, `yq`, `python`, or any tool not present on a
  default agent image.

### Azure DevOps pipeline YAML (`.azuredevops/*.yml`)

- Indent with **2 spaces**; no tabs.
- Every pipeline must include a `name:` field using `$(Build.BuildId)`.
- Every pipeline must set `trigger: none` and `pr: none`.
- Every checkout step must include `clean: true` and `persistCredentials: true`.
- Every job must include `workspace: clean: all`.
- Use **variables** for pool name (`agentPoolName`); never hardcode a pool name.
- Step display names must be descriptive enough to identify the step in the UI
  without opening the log.
- All steps that call inspection scripts must set `continueOnError: true`.
- Use `- powershell:` (not `- script:`) for PowerShell steps on Windows.
- Use `- bash:` for bash steps on Linux/macOS.
- Use `condition: eq(variables['Agent.OS'], 'Windows_NT')` to gate PS steps.
- Use `condition: ne(variables['Agent.OS'], 'Windows_NT')` to gate bash steps.

---

## Logging format rules

All evidence-bearing log lines must follow this format exactly:

```
TAG_IN_CAPS        : value
```

- Tag is left-padded to column 19 with spaces (or aligned consistently within
  a section).
- Values must not contain leading or trailing whitespace.
- Boolean-style values use `YES` / `NO`, not `true` / `false`, in evidence lines.
- Pass/fail outcomes use `PASS`, `FAIL-MISSING`, or `FAIL-UNEXPECTED`.

Section headers must use the `Write-Section` / `write_section` helper and be
wrapped with `=` rules of 70 characters.

---

## Determinism requirements

- Do **not** use `Get-Random`, `$RANDOM`, `New-Guid`, or any randomisation.
- Do not use dynamic hostnames, usernames, or paths as primary evidence values.
  (They may appear in diagnostic headers but not in sentinel checks.)
- The **sentinel table** rows must always appear in the same order.
  Use `[ordered]@{}` in PowerShell; preserve list order in bash.
- The `SUMMARY_PASS` and `SUMMARY_FAIL` lines must always appear and always
  contain integer values, even if zero.

---

## What NOT to do

- Do not add `exit 1` anywhere in the inspection scripts.
- Do not install packages, modules, or extensions inside scripts.
- Do not write to files outside the `SOURCES_DIR` path.
- Do not hardcode agent paths (`C:\agent`, `/home/agent`, etc.).
- Do not add pipeline steps that modify repository content.
- Do not add secrets or real credentials – use clearly fake placeholder values.
- Do not add GitHub Actions syntax (`.github/workflows/`) to the pipeline files.

---

## Fixture file conventions

- Every fixture file must contain a `SENTINEL: <SCREAMING_NAME>_PRESENT` line.
- Fake PII strings (e.g. `user-id-XXXX`) are intentional and must be kept
  synthetic – never use real names, email addresses, or identifiers.
- File contents must be small (< 30 lines) and self-documenting.

---

## Scope of changes

- Pipeline YAML changes must not alter the `agentPoolName` variable value
  from `Default` – it is the user's responsibility to override that in Azure DevOps.
- Script changes must maintain backward compatibility with PowerShell 5.1.
- Do not rename the `SPARSE_MODE` or `SOURCES_DIR` environment variable names –
  both scripts and pipeline YAMLs depend on them.
