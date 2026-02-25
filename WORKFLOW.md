# ADO Issue Investigation Workflow

> **Purpose:** A repeatable, agent-assisted playbook for triaging Azure DevOps
> pipeline behaviour issues — from first contact to root cause, fix, and
> learning artefact update.
>
> **Origin:** Distilled from the sparse checkout investigation (Findings 1 & 2,
> February 2026). Improve this document in place during each new case — see
> [§ Improving This Workflow](#improving-this-workflow).

---

## Quick Start — New Case

```
git checkout main && git pull
git checkout -b case/YYYY-MM-DD-<slug>
cp docs/CaseTemplate.md docs/cases/YYYY-MM-DD-<slug>.md
# fill in Section 1 (Intake) from the customer ticket
# open the VS Code task: "New Case Setup" to do this automatically
```

Then follow the phases below.

---

## Phase 1 — Intake

**Goal:** Capture enough context to decide whether this is a known issue or
a new investigation.

**Checklist (copy into your case doc):**

| Field | Value |
|---|---|
| ADO platform | `Azure DevOps Services (cloud)` / `Azure DevOps Server <version>` |
| Agent version | `$(Agent.Version)` from build log |
| Agent OS | `$(Agent.OS)` from build log |
| git version | `git --version` output from build log |
| Pipeline YAML snippet | paste the `checkout:` step |
| Observed behaviour | what the customer sees |
| Expected behaviour | what the customer expected |
| Build URL / ID | link to the failing build |

**Gate:** Do you have the agent version, git version, platform, and YAML?
If not, request them before proceeding.

**Known issue shortcuts:**
- Full clone on ADO Server 2025 despite sparse config → [Finding 2](docs/SparseCheckout-ADOServer2025-RootCauseAndResolution.md)
- Both `sparseCheckoutDirectories` + `sparseCheckoutPatterns` set, wrong folder appears → [Finding 1 / DocumentationDiscrepancyReport](docs/DocumentationDiscrepancyReport.md)
- `partiallySucceeded` + exit 127 → [Troubleshooting §5](docs/Troubleshooting.md)

---

## Phase 2 — Environment Baseline

**Goal:** Establish a known-good full-checkout run to confirm the agent and
repo are healthy before testing sparse configurations.

**Steps:**
1. Register `.azuredevops/full-checkout.yml` on the target ADO org/server.
2. Queue it. Confirm `SUMMARY_PASS: N`, `SUMMARY_FAIL: 0`.
3. Note the build ID — this is your **baseline build**.

**Gate:** Baseline must pass fully before writing hypothesis pipelines.
A failing baseline means an environment problem, not a sparse checkout problem.

**Reference:** [full-checkout.yml](.azuredevops/full-checkout.yml),
[ExpectedResults.md](docs/ExpectedResults.md)

---

## Phase 3 — Reproduce

**Goal:** Reproduce the customer's exact configuration in a controlled pipeline.

**Steps:**
1. Create a new pipeline YAML in `.azuredevops/` named
   `case-<slug>-repro.yml`.
2. Copy the customer's `checkout:` step verbatim.
3. Add an inspection step using `tools/inspect-workspace.ps1` /
   `tools/inspect-workspace.sh` (gated on `Agent.OS`).
4. Set `continueOnError: true` on all inspection steps.
5. Queue and capture the build ID and full log.

**Naming convention:**
```
name: "Case_<Slug>_Repro_$(Build.BuildId)"
```

**Gate:** Does the reproduction build show the same symptom as the customer
reported? If not, the YAML or environment differs — resolve before proceeding.

---

## Phase 4 — Hypothesis Pipelines

**Goal:** Isolate the variable by running controlled variants side-by-side.

**Pattern:** Create 2–4 pipeline jobs or pipeline files that vary exactly one
property at a time. Use the existing pipelines as reference implementations:

| Reference pipeline | What it isolates |
|---|---|
| [sparse-directories.yml](.azuredevops/sparse-directories.yml) | cone mode, root-file behaviour |
| [sparse-patterns.yml](.azuredevops/sparse-patterns.yml) | pattern mode, zero root files |
| [sparse-both.yml](.azuredevops/sparse-both.yml) | precedence when both properties set |
| [server2025-knob-test.yml](.azuredevops/server2025-knob-test.yml) | knob-off vs knob-on side-by-side |
| [server2025-workaround-test.yml](.azuredevops/server2025-workaround-test.yml) | two workarounds validated |

**Checklist:**
- [ ] Each job/pipeline has a distinct `evidenceLabel` variable
- [ ] Every inspection step uses `SCREAMING_SNAKE_CASE` log tags
- [ ] `SUMMARY_PASS` and `SUMMARY_FAIL` appear in every run
- [ ] `continueOnError: true` on all inspection steps

---

## Phase 5 — Evidence Collection

**Goal:** Produce a grep-able evidence record linking build IDs to log lines.

**For each hypothesis build, capture:**

```
BUILD_ID         : <id>
SPARSE_MODE      : <label>
GIT_CONE_MODE    : YES / NO
ROOT_FILE_COUNT  : <n>
SUMMARY_PASS     : <n>
SUMMARY_FAIL     : <n>
KEY_OBSERVATION  : <one sentence — what was surprising or confirmed>
```

Add this block to your case doc under `## Evidence Log`.

**Tools available:**
- `tools/get-build-logs.ps1` — fetch raw log text by build ID
- `tools/get-build-issues.ps1` — fetch warnings and errors only
- `tools/fetch-build-logs.ps1` — download full log artifact

**Gate:** You must have at least one `FAIL` build and one `PASS` build that
differ by exactly one variable before moving to root cause.

---

## Phase 6 — Source Attribution

**Goal:** Trace the behaviour to source code, not just to a symptom.

**Standard starting points:**

1. **Azure Pipelines Agent** — the primary source for checkout task behaviour:
   - Repo: `https://github.com/microsoft/azure-pipelines-agent`
   - Key files:
     - `src/Agent.Sdk/Knob/AgentKnobs.cs` — feature knob defaults
     - `src/Agent.Plugins/RepositoryPlugin.cs` — checkout task entry
     - `src/Agent.Plugins/PipelineArtifact/GitSourceProvider.cs` — sparse checkout block

2. **Azure Pipelines Tasks** — for task-level behaviour (e.g., `UseGitLFS`, `fetchDepth`):
   - Repo: `https://github.com/microsoft/azure-pipelines-tasks`
   - Key path: `Tasks/GitV2/`

3. **Agent knob search pattern:**
   ```
   # Search AgentKnobs.cs for the relevant feature
   grep -i "sparse" src/Agent.Sdk/Knob/AgentKnobs.cs
   ```
   A knob with `new BuiltInDefaultKnobSource("false")` is OFF by default
   everywhere unless the service side overrides it. On ADO Server (on-prem)
   no service-side override mechanism exists.

**Document the finding as:**
```
ROOT_CAUSE_FILE  : src/Agent.Sdk/Knob/AgentKnobs.cs
ROOT_CAUSE_LINE  : UseSparseCheckoutInCheckoutTask — default "false"
ROOT_CAUSE_CLASS : Feature knob defaults to off on-premises
```

---

## Phase 7 — Fix Validation

**Goal:** Confirm the fix in a controlled pipeline before advising the customer.

**Steps:**
1. Apply the proposed fix to a new pipeline job or file.
2. Run it side-by-side with the broken repro (same agent, same repo).
3. Confirm `SUMMARY_FAIL: 0` in the fix run, `SUMMARY_FAIL: N` in the broken run.
4. Capture both build IDs in the case doc.

**If the fix is a workaround (not a platform fix):**
- Document both approaches (e.g., pipeline variable vs. post-checkout script).
- Reference [CustomerWorkaround-Finding2.md](docs/CustomerWorkaround-Finding2.md)
  as a template for the customer-facing workaround guide.

**Gate:** Fix must be validated on the **same platform** (cloud vs. on-prem)
as the original repro. A fix that only works on cloud does not close an
on-prem case.

---

## Phase 8 — Close-Out

**Goal:** Leave the repo and template better than you found it.

**Close-out checklist:**

- [ ] Case doc `docs/cases/YYYY-MM-DD-<slug>.md` is complete (all phases filled)
- [ ] If a **new root-cause class** was found:
  - [ ] Add a Finding to [DocumentationDiscrepancyReport.md](docs/DocumentationDiscrepancyReport.md) or create a new `<Topic>-RootCauseAndResolution.md` in `docs/`
  - [ ] Add a new Lesson to [LearningModule-SparseCheckout.md](docs/LearningModule-SparseCheckout.md)
  - [ ] Add a new row to [ExpectedResults.md](docs/ExpectedResults.md) if a new pipeline was created
  - [ ] Add a workaround YAML section to [CustomerWorkaround-Finding2.md](docs/CustomerWorkaround-Finding2.md) or create a new customer doc
- [ ] If the workflow itself needed adjustment: update `WORKFLOW.md` (see below)
- [ ] Commit everything on your case branch
- [ ] Open a PR to `main`; squash-merge
- [ ] After merge: `git push origin main:backup/main-YYYY-MM-DD` to tag the new baseline
- [ ] Push `main` to GitHub — the updated template is now live for the next case

---

## Improving This Workflow

> This section is **appended to during a case** and promoted at close-out.

If you hit a step that was missing, unclear, or wrong — note it here:

```
## Workflow Gaps Found During Case: <slug>

GAP_PHASE   : <phase number>
GAP_SUMMARY : <one sentence — what was missing or wrong>
PROPOSED_FIX: <how to improve the workflow step>
```

At close-out, promote accepted gaps into the relevant phase above and clear
this section.

---

## Reference Map

| Need | File |
|---|---|
| Start a new case | `docs/CaseTemplate.md` → copy to `docs/cases/` |
| Expected sentinel outcomes per mode | [docs/ExpectedResults.md](docs/ExpectedResults.md) |
| Troubleshooting common issues | [docs/Troubleshooting.md](docs/Troubleshooting.md) |
| Technical deep-dive | [docs/SparseCheckout-TechnicalSupportDocument.md](docs/SparseCheckout-TechnicalSupportDocument.md) |
| Customer-facing fix guide | [docs/CustomerWorkaround-Finding2.md](docs/CustomerWorkaround-Finding2.md) |
| Learning module (pre/post test) | [docs/LearningModule-SparseCheckout.md](docs/LearningModule-SparseCheckout.md) |
| Fetch build logs | `tools/get-build-logs.ps1` |
| Queue a pipeline | `tools/queue-knob-build.ps1` |
| Inspect pipeline definitions | `tools/inspect-pipeline-defs.ps1` |

---

*Template version: 2026-02-25 — sparse checkout investigation, Findings 1 & 2*
