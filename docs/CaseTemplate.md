# Case: <!-- YYYY-MM-DD — Short descriptive slug -->

> Copy this file to `docs/cases/YYYY-MM-DD-<slug>.md` at the start of a new case.
> Fill each section as you work through [WORKFLOW.md](../../WORKFLOW.md).
> Delete instruction comments (lines starting with `>`) when a section is complete.

---

## Phase 1 — Intake

| Field | Value |
|---|---|
| Case opened | <!-- YYYY-MM-DD --> |
| ADO platform | <!-- `Azure DevOps Services (cloud)` or `Azure DevOps Server <version>` --> |
| Agent version | <!-- e.g. v4.260.0 — from `$(Agent.Version)` in build log --> |
| Agent OS | <!-- e.g. `Windows_NT`, `Linux` --> |
| git version | <!-- e.g. `git version 2.43.0` --> |
| Pool type | <!-- self-hosted / Microsoft-hosted --> |
| Build URL | <!-- paste link --> |
| Baseline build ID | <!-- full-checkout.yml build ID — filled in Phase 2 --> |

### Customer YAML

```yaml
# paste the customer's checkout: step here
```

### Observed vs Expected

| | Description |
|---|---|
| Observed | <!-- what the customer sees --> |
| Expected | <!-- what the customer expected --> |

### Known-issue check

- [ ] Checked [DocumentationDiscrepancyReport.md](../DocumentationDiscrepancyReport.md)
- [ ] Checked [Troubleshooting.md](../Troubleshooting.md)
- [ ] Checked [SparseCheckout-ADOServer2025-RootCauseAndResolution.md](../SparseCheckout-ADOServer2025-RootCauseAndResolution.md)
- [ ] Not a known issue — proceed with investigation

---

## Phase 2 — Baseline

| Field | Value |
|---|---|
| Baseline build ID | |
| Baseline result | <!-- PASS / FAIL --> |
| SUMMARY_PASS | |
| SUMMARY_FAIL | |

> Gate: baseline must show `SUMMARY_FAIL: 0` before proceeding.

---

## Phase 3 — Reproduce

| Field | Value |
|---|---|
| Repro pipeline file | <!-- `.azuredevops/case-<slug>-repro.yml` --> |
| Repro build ID | |
| Symptom reproduced | <!-- YES / NO --> |

### Repro log excerpt

```
# paste the key log lines here (sparse-checkout command lines, SUMMARY_PASS/FAIL)
```

> Gate: symptom must match customer report before proceeding.

---

## Phase 4 — Hypothesis Pipelines

> List each hypothesis and the pipeline/job used to test it.

| Hypothesis | Pipeline / Job | Build ID | Result |
|---|---|---|---|
| <!-- e.g. cone mode causes root files to appear --> | | | |
| <!-- e.g. knob defaults false on-prem --> | | | |

---

## Phase 5 — Evidence Log

> One block per significant build. Copy and fill the template.

```
BUILD_ID         :
SPARSE_MODE      :
PLATFORM         :   # cloud / ADO Server <version>
GIT_CONE_MODE    :   # YES / NO
ROOT_FILE_COUNT  :
SUMMARY_PASS     :
SUMMARY_FAIL     :
KEY_OBSERVATION  :
```

```
BUILD_ID         :
SPARSE_MODE      :
PLATFORM         :
GIT_CONE_MODE    :
ROOT_FILE_COUNT  :
SUMMARY_PASS     :
SUMMARY_FAIL     :
KEY_OBSERVATION  :
```

> Gate: must have at least one FAIL and one PASS differing by exactly one variable.

---

## Phase 6 — Root Cause

| Field | Value |
|---|---|
| ROOT_CAUSE_FILE | |
| ROOT_CAUSE_LINE | |
| ROOT_CAUSE_CLASS | <!-- e.g. "Feature knob defaults to off on-premises" --> |
| Agent source repo | <!-- link to file/line in microsoft/azure-pipelines-agent --> |

### Explanation

<!-- 2–5 sentences: what is the code doing, why does the symptom appear, why does it
     differ between cloud and on-prem (or agent versions, etc.) -->

---

## Phase 7 — Fix Validation

| Field | Value |
|---|---|
| Fix description | |
| Fix pipeline file | |
| Fix build ID | |
| Broken build ID | <!-- for comparison --> |
| SUMMARY_FAIL (broken) | |
| SUMMARY_FAIL (fixed) | |
| Platform validated on | <!-- cloud / ADO Server <version> --> |

> Gate: fix build must show SUMMARY_FAIL: 0 on the same platform as the repro.

---

## Phase 8 — Close-Out

- [ ] Case doc complete (all phases filled)
- [ ] New root-cause class found?
  - [ ] Finding added to `DocumentationDiscrepancyReport.md` or new `*-RootCauseAndResolution.md` created
  - [ ] New lesson added to `LearningModule-SparseCheckout.md`
  - [ ] New row added to `ExpectedResults.md`
  - [ ] Customer workaround doc created/updated
- [ ] `WORKFLOW.md` updated if any gaps were found (see below)
- [ ] PR opened to `main` and squash-merged
- [ ] Backup branch pushed: `git push origin main:backup/main-YYYY-MM-DD`

---

## Workflow Gaps Found During This Case

> Append below if you hit anything missing, unclear, or wrong in WORKFLOW.md.
> Promote accepted items into WORKFLOW.md before closing.

```
GAP_PHASE   :
GAP_SUMMARY :
PROPOSED_FIX:
```
