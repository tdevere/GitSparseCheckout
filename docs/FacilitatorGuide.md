# Facilitator Guide — Sparse Checkout Learning Module

> **For team leads and training coordinators** running
> `docs/LearningModule-SparseCheckout.md` as a structured team workshop.
> Individual self-paced use requires no facilitator.

---

## 1. Session formats

| Format           | Duration  | Group size | Recommended setting           |
| ---------------- | --------- | ---------- | ----------------------------- |
| Full workshop    | 90 min    | 4–12       | Shared screen + live demo env |
| Condensed review | 45 min    | Any        | Skip exercises, discuss only  |
| Self-paced       | 60–90 min | 1          | No facilitator needed         |

---

## 2. Materials checklist

Before the session:

- [ ] Confirm attendees have access to the ADO org:
      `https://dev.azure.com/MCAPDevOpsOrg/PermaSamples`
- [ ] Confirm a self-hosted agent is registered in the `Default` pool
- [ ] Share the module file path or a printed/PDF copy:
      `docs/LearningModule-SparseCheckout.md`
- [ ] Have build logs open in a browser tab for each authoritative run:
  - Build 705 — Full checkout
  - Build 709 — Sparse directories (cone)
  - Build 710 — Sparse patterns (non-cone)
  - Build 712 — Both set (directories won)
- [ ] Open `docs/ExpectedResults.md` as a reference panel

---

## 3. Suggested 90-minute workshop agenda

| Time      | Activity                                                              |
| --------- | --------------------------------------------------------------------- |
| 0:00–0:10 | Welcome + learning objectives (Module header, Section 1)              |
| 0:10–0:20 | **Pre-test** — participants complete 10 questions independently       |
| 0:20–0:35 | **Lesson 1 + 2** — Git sparse checkout fundamentals + cone mode       |
| 0:35–0:50 | **Lesson 3** — Pattern mode; compare with cone mode                   |
| 0:50–1:00 | **Lesson 4** — Documentation discrepancy; show Build 712 raw log      |
| 1:00–1:10 | **Lesson 5** — Debugging checklist and decision tree                  |
| 1:10–1:20 | **Post-test** — participants complete 10 questions independently      |
| 1:20–1:25 | Score and discuss delta; highlight any questions missed on both tests |
| 1:25–1:30 | Wrap-up, Q&A, further reading                                         |

---

## 4. Scoring and measuring learning delta

### Scoring each test

Each test contains 11 questions, one point each. Maximum score: 11.

```
Score 0–4  : Foundation knowledge gaps — plan follow-up coaching
Score 5–8  : Developing understanding — review missed questions as a group
Score 9–11 : Strong baseline / mastery
```

### Calculating delta

```
Delta = Post-test score − Pre-test score

Delta ≥ 3  : Significant learning occurred
Delta 1–2  : Moderate gain — repeat lessons with low scores
Delta 0    : Review delivery pace; may indicate a ceiling effect (high pre-score)
Delta < 0  : Investigate — usually a misread question; review answer key together
```

Record scores in a simple spreadsheet: participant name, pre-score, post-score,
delta. Aggregate across cohorts to measure module effectiveness over time.

---

## 5. Discussion pause points

Pause after each lesson and use the prompt below. Aim for 2–3 minutes.

### After Lesson 1 (Git sparse checkout fundamentals)

> "Before today, how were you explaining sparse checkout to customers?
> Was there anything in the fundamentals that contradicted what you believed?"

### After Lesson 2 (Cone mode — `sparseCheckoutDirectories`)

> "A customer opens a ticket: 'I set `sparseCheckoutDirectories: src` but my
> pipeline is also materialising all my YAML and JSON files in the root.
> Is this a bug?' How do you respond?"

_Expected answer_: not a bug; cone mode always materialises root-level tracked
files by design. Point them to `GIT_CONE_MODE: true` in the pipeline log.

### After Lesson 3 (Pattern mode — `sparseCheckoutPatterns`)

> "Same customer follow-up: 'I switched to patterns and now my root `.env`
> file is gone and my build script can't find it.' What went wrong and how
> do you fix it?"

_Expected answer_: pattern mode does not materialise root files unless
explicitly included. Add `/*.env` or `*.env` to `sparseCheckoutPatterns`.

### After Lesson 4 (Documentation discrepancy)

> "Build 712 showed that the agent ignored the documentation. If a customer
> comes in with a ticket where the documentation-expected behaviour is the
> one they're seeing (patterns win on their agent version), how do you handle
> the case where your evidence and their evidence contradict each other?"

_Key discussion points_: agent version matters; always ask for agent version
and git version first; Build 712 is evidence for v4.266.2 / git 2.43.0 only.

### After Lesson 5 (Debugging and decision tree)

> "Walk through the decision tree for a customer whose pipeline's
> `sparseCheckoutPatterns` seems to be silently failing. What log lines
> do you look for first?"

_Expected answer_: check `GIT_CONE_MODE` — if `true`, directories won instead
of patterns. Check `git sparse-checkout list` output for which directories
are actually set.

---

## 6. Common facilitation issues

| Issue                                         | Resolution                                                         |
| --------------------------------------------- | ------------------------------------------------------------------ |
| Attendees unfamiliar with git sparse checkout | Start with 5-min demo of `git sparse-checkout set --cone CDN`      |
| Build logs not accessible (permissions)       | Pre-pull relevant log excerpts into a shared doc                   |
| Disagreement about Build 712 discrepancy      | Emphasise: evidence beats documentation; open an ICM when in doubt |
| Pre-test scores mostly 8–10                   | Skip to Lesson 4 and 5; treat as advanced refresher                |
| Time overruns                                 | Cut Lesson 5 exercises; keep Lesson 4 as the key learning moment   |

---

## 7. Resources

| Resource                                          | Use                                          |
| ------------------------------------------------- | -------------------------------------------- |
| `docs/LearningModule-SparseCheckout.md`           | The module itself (pre/post tests + lessons) |
| `docs/LearningAgent-Profile.md`                   | ADEL agent identity and system prompt        |
| `docs/ExpectedResults.md`                         | Reference during Lessons 2–4                 |
| `docs/SparseCheckout-TechnicalSupportDocument.md` | Deep dive for advanced questions             |
| `docs/SME-Validation-QA.md`                       | 4 SME validation questions with evidence     |
| `docs/DocumentationDiscrepancyReport.md`          | ICM-ready discrepancy artifact               |
| `docs/Troubleshooting.md`                         | 10-item troubleshooting guide                |

---

_Module version: 1.0 — Based on authoritative builds 705, 709, 710, 712._  
_Agent: v4.266.2 / git 2.43.0 / Linux (Ubuntu, MCAPDevOpsOrg Default pool)_
