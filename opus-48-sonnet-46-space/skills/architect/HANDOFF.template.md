# HANDOFF — [mission name]

> Cross-slice table of contents for the Architect Loop. Lives at
> artifacts/HANDOFF.md in the space repo (committed). Per-slice detail lives in
> artifacts/<NN>-<slice>.md — this file only indexes the slices and carries
> mission-wide state. Keep it short (~150 lines): the next session must grok it
> in under a minute. TL;DR first; exact paths/commands over prose.
> Not in the committed artifacts = didn't happen.

## TL;DR (keep current)

- Goal: [one sentence]
- Last slice: [<NN>-name] — [CONTINUE / KILL / awaiting verdict]
- Next action: [exact command or decision needed]

## Project goal

[One paragraph. What this is and what "done" means.]

## Verification gate (exact commands, per repo)

```
[install / test / lint / typecheck / build commands for each repo in scope]
```

## Repos in scope

[Repos under repos/ this mission spans. Each lane runs in a worktree under
tmp/architect/wt/ off its target repo's base commit.]

## Slice index

| NN | Slice | Status | freeze_sha | Integration branch | Verdict | File |
|----|-------|--------|-----------|--------------------|---------|------|
| 01 | name  | done   | abc1234   | slice/name         | CONTINUE | artifacts/01-name.md |

Status values: speccing → frozen → dispatched → in-flight → awaiting-verdict → done.

## Open items for the human / architect

[Anything blocking: unresolved disagreements (which slice), scope questions,
stop-condition checkpoints. Detail lives in the slice file; link it.]

## Decisions log (architect + human)

| Date | Decision | Why |
|------|----------|-----|
