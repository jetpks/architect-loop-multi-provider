# HANDOFF — [project name]

> Space memory for the Architect Loop. Lives at artifacts/HANDOFF.md in the
> space repo (committed). The builder (Sonnet 4.6 via `claude -p`) updates this
> after every run; the architect (Opus 4.8) writes rulings and verdicts here.
> Raw evidence only in builder sections — tables, numbers, commit SHAs, test
> output. No interpretation, no "promising". Every claim must be backed by a
> command result from the run that wrote it.
> Not in this file = didn't happen.

## TL;DR (keep current — next session must grok this in under a minute)

- Goal: [one sentence]
- Last slice: [name] — [PASS/FAIL/pending judgment]
- Next action: [exact command or decision needed]

## Project goal

[One paragraph. What this is and what "done" means.]

## Verification gate (exact commands)

```
[install / test / lint / typecheck / build commands for this repo]
```

## Repos in scope

[List repos under repos/ this mission spans. Each builder runs in a worktree
under tmp/architect/wt/ off that repo's base commit.]

## Frozen contracts

[Links to artifacts/ files holding frozen schemas/interfaces. Read-only after
freeze — for everyone, including the builder.]

## Current slice

- Spec: [link or one-line summary]
- Gates: artifacts/gates/<slice>.md (frozen via `space architect freeze <slice>` BEFORE work began; freeze_sha in .space.yml)
- Lanes: [1 | N disjoint lanes — file sets; reports in artifacts/lanes/<slice>-<lane>.md]
- Thinking: [ultrathink | think hard] — [why] (builder thinking budget, set in-block)

| Gate | Command | Threshold | Raw result | Architect verdict |
|------|---------|-----------|------------|-------------------|
|      |         |           |            | PASS/FAIL/INVALID |

## Raw results (latest run — builder writes, architect never edits)

[Tables, numbers, test output, commit SHAs. No adjectives.]

## Open disagreements (builder writes; architect rules)

| # | Builder's position | Spec's position | Evidence (real files) | Ruling |
|---|--------------------|-----------------|------------------------|--------|
|   |                    |                 |                        | ACCEPT/REJECT/MODIFY — why |

## Decisions log (architect + human)

| Date | Decision | Why |
|------|----------|-----|

## Next slice (builder may propose; architect decides)

[Proposal]

## Session log

| Date | Role | Slice | Commits | Gates P/F | Notes |
|------|------|-------|---------|-----------|-------|
