# Slice <NN>: <name>

> One self-contained slice of the Architect Loop, at artifacts/<NN>-<slice>.md
> (`<NN>` = zero-padded ordinality). Grown section by section, one commit per
> section. The builder NEVER edits this file — the architect writes every
> section, and transcribes the Builder Report verbatim from the builder's scratch
> report in tmp/architect/. Frozen sections (Grounds, Contract, Rubric) are
> read-only after the freeze commit; only Builder Prompt, Builder Report, and
> Verdict are appended afterward.

## Grounds

<!-- WHY. Research/PRD distilled: problem, decision + why, requirements,
non-goals, verified facts WITH citation URLs, open questions for the human.
Optional — omit the section entirely for slices that needed no research.
Commit: "slice <NN>: grounds". -->

## Contract

<!-- WHAT / HOW — the full, self-contained delegation contract.
Commit: "slice <NN>: contract". -->

- **Objective** — what to build and why (cite Grounds if present).
- **Output format** — raw tables, numbers, commit SHAs, test output paths; no
  interpretation.
- **Tool guidance** — exact verification commands for the target repo; the
  APIs/formats/versions to verify against live dependencies before writing code.
- **Boundaries** — may-touch / must-not-touch / out-of-scope; no placeholders
  (search before implementing); no refactors beyond the task.
- **Lane plan** — 1–4 lanes, each declaring: target repo `repos/<repo>`,
  file-touch set (overlap-checked), objective, output format, boundaries. Most
  slices are one lane.
- **Effort** — `think hard` … `ultrathink` per lane, with one line of why.

## Rubric   ❄️ FREEZE

<!-- PROOF. Exact gate commands + thresholds. The commit that ADDS this section
is THE FREEZE — record its SHA as freeze_sha in the handoff slice index. Quote
verbatim when judging (read it from the freeze commit, not HEAD). Read-only
afterward — any later change to Grounds/Contract/Rubric = automatic slice FAIL.
Commit: "slice <NN>: rubric (freeze)". -->

| Gate | Command | Threshold |
|------|---------|-----------|
|      |         |           |

## Builder Prompt

<!-- The exact lane-prompt(s) dispatched, recorded as provenance. Architect-
authored (template in dispatch.md + this lane's slice of the Contract + the
frozen Rubric). One ### subsection per lane. A copy is written to
tmp/architect/<slice>-<lane>.prompt.md for stdin dispatch.
Commit: "slice <NN>: dispatched". -->

### Lane 01 — repos/<repo> — files: <touch set>

```
<the verbatim lane-prompt fed to claude -p>
```

## Builder Report

<!-- RAW EVIDENCE ONLY — tables, numbers, command output, commit SHAs. The
builder writes this to tmp/architect/<slice>-<lane>.report.md; the architect
transcribes it here VERBATIM (no interpretation, no "promising"). One ###
subsection per lane. Include the builder's PHASE 0 disagreements and its final
STATUS line. Commit: "slice <NN>: evidence". -->

### Lane 01

<!-- transcribed verbatim from tmp/architect/<slice>-<lane>.report.md -->

## Verdict

<!-- ARCHITECT JUDGMENT, written in a LATER session than the dispatch (never
grade the run you launched). Commit: "slice <NN>: verdict". -->

- **Disagreement rulings** — each PHASE 0 disagreement: ACCEPT / REJECT / MODIFY
  + one line why.
- **Rubric integrity** — `git diff <freeze-sha> HEAD -- artifacts/<NN>-<slice>.md`
  touches no frozen-section lines? (any change = FAIL)

| Gate | Raw result | Verdict |
|------|------------|---------|
|      |            | PASS/FAIL/INVALID |

- **Slice** — KILL / CONTINUE + the single decisive reason.
