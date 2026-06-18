# HANDOFF — [mission name] ✨

> The little space-memory heart of the Architect Loop! 💖 Lives at
> `<space>/architect/HANDOFF.md`. The builder (Sonnet 4.6 via `claude -p`) writes
> raw evidence in its lane reports; the architect (Opus 4.8) consolidates here
> and writes rulings and verdicts. (ﾉ◕ヮ◕)ﾉ*:･ﾟ✧
> Raw evidence only in builder/result sections — tables, numbers, commit SHAs,
> test output. No interpretation, no "promising"! Every claim must be backed by a
> command result from the run that wrote it.
> Not in this file = didn't happen. 🚫

## TL;DR (keep current — next session must grok this in under a minute) ⚡

- Goal: [one sentence]
- Last slice: [name] — [PASS/FAIL/pending judgment]
- Next action: [exact command or decision needed]

## Mission goal 🎯

[One paragraph. What this is and what "done" means.]

## Repos in scope 🪐

> The mission spans these clones under `<space>/repos/`. A slice's lanes each
> target one of them.

| Repo (`repos/<name>`) | Role in the mission | Verification gate | Integration branch |
|-----------------------|---------------------|-------------------|--------------------|
|                       |                     | [test/lint/build] | slice/[name]       |

## Frozen contracts ❄️

[Links to the per-repo docs/ files holding frozen schemas/interfaces. Read-only
after freeze — for everyone, including the builder.]

## Current slice 🍰

- Spec: [link or one-line summary]
- Gates: architect/gates/[slice].md (frozen in the space at commit [sha] BEFORE work began)
- Lanes: [1 | N disjoint lanes — repo + file sets; reports in architect/lanes/[slice]-[lane].md]
- Thinking: [ultrathink | think hard] — [why] (builder thinking budget, set in-block)

| Gate | Repo | Command | Threshold | Raw result | Architect verdict |
|------|------|---------|-----------|------------|-------------------|
|      |      |         |           |            | PASS/FAIL/INVALID |

## Raw results (latest run — from builder lane reports, architect never edits) 📊

[Tables, numbers, test output, commit SHAs. No adjectives.]

## Open disagreements (builder raises; architect rules) 💬

| # | Builder's position | Spec's position | Evidence (real files) | Ruling |
|---|--------------------|-----------------|------------------------|--------|
|   |                    |                 |                        | ACCEPT/REJECT/MODIFY — why |

## Decisions log (architect + human) 📝

| Date | Decision | Why |
|------|----------|-----|

## Next slice (builder may propose; architect decides) 🌱

[Proposal]

## Session log 📚

| Date | Role | Slice | Repo(s) | Commits | Gates P/F | Notes |
|------|------|-------|---------|---------|-----------|-------|
