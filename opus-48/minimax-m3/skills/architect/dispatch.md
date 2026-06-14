# Builder dispatch reference

Verified against `pi` 0.79.2 (`pi --help`, June 2026). The builder is `pi`
driven against OpenRouter on `minimax/minimax-m3`. Key facts the skill encodes:
`pi -p` (`--print`) is the non-interactive, headless mode (the `codex exec`
analog); `pi` has no working-dir flag, so per-lane dispatch `cd`s into the
worktree; permissions are controlled by the **tool allowlist** (`-t`), not a
sandbox; web access comes from the `pi-web-access` extension (tools
`web_search`, `fetch_content`).

**The one load-bearing difference from the Codex design:** `pi` has **no
sandbox**, so `.git` is *not* hardware-protected. "Builders never commit" is
still a hard rule (R7), but it is now enforced by worktree isolation + the
builder block instruction + an **architect post-flight check**
(`git -C <worktree> log <freeze-sha>..` must be empty), not by the runtime.
If a lane committed, treat the worktree as tampered: reset and re-dispatch.

**Preflight (once per environment):** run `pi --version`, confirm
`OPENROUTER_API_KEY` is set, and `pi --list-models minimax/minimax-m3` resolves.
On the first dispatch in a new environment, launch ONE canary run and confirm it
starts cleanly before fanning anything out.

## Canonical headless dispatch (architect-driven)

Write the builder block to a file first, then pass it with `@file` — never as a
shell argument. Big prompt blocks contain quotes that shells (especially Windows
PowerShell) mangle; `@file` injects the file contents verbatim and sidesteps it.
`--mode json` streams JSONL events to stdout; redirect it to a run-log for
liveness/stall checks. The lane's actual deliverable is the report the builder
writes with its `write` tool to `docs/lanes/<slice>-<lane>.md`.

Single-lane slice (dispatch in the main checkout):

```bash
pi -p --provider openrouter --model minimax/minimax-m3 --thinking xhigh \
  --session-id <slice> \
  -t read,bash,edit,write,grep,find,web_search,fetch_content \
  --mode json @.architect/dispatch-block.md \
  > .architect/last-run.jsonl
```

## Worktree fan-out (2–4 lanes — the architect owns the parallelism)

One isolated worktree + one fresh `pi -p` per lane, all launched in parallel in
the background. Lanes have file-touch sets checked for overlap from the spec;
each writes raw results to its own `docs/lanes/<slice>-<lane>.md`, so nothing
collides. `pi` has no `-C`, so each lane runs inside a subshell `cd`'d into its
worktree, with absolute paths for the block and the run-log.

```bash
# per lane, off the freeze commit
git -C <repo-root> worktree add .architect/wt/<slice>-<NN> \
  -b lane/<slice>-<NN> <freeze-sha>

# write the lane's builder block, then dispatch (background, all lanes parallel)
( cd <repo-root>/.architect/wt/<slice>-<NN> && \
  pi -p --provider openrouter --model minimax/minimax-m3 --thinking xhigh \
    --session-id <slice>-<NN> \
    -t read,bash,edit,write,grep,find,web_search,fetch_content \
    --mode json @<repo-root>/.architect/wt/<slice>-<NN>.block.md \
    > <repo-root>/.architect/wt/<slice>-<NN>.last-run.jsonl ) &
```

A worktree keeps each lane's working files apart, so parallel lanes never touch
each other's files. Nothing reaches a branch until the architect's checks pass —
but because `pi` has no sandbox, that is enforced by the post-flight `git log`
and `git status` checks below, not by the runtime (see the load-bearing note at
the top).

### Integration (architect-only, after per-lane post-flight passes)

```bash
git -C <repo-root> checkout -b slice/<name> <freeze-sha>
# per passing lane, sequentially:
git -C <repo-root>/.architect/wt/<slice>-<NN> add -A
git -C <repo-root>/.architect/wt/<slice>-<NN> commit -m "lane <NN>: <what>"
git -C <repo-root> merge --no-ff lane/<slice>-<NN>
<run the gate commands>          # integration smoke after every merge
# cleanup:
git -C <repo-root> worktree remove .architect/wt/<slice>-<NN>
git -C <repo-root> branch -d lane/<slice>-<NN>
```

A merge conflict = the lane plan wasn't disjoint = a spec defect. Kill the
conflicting lane and re-spec; don't hand-resolve builder conflicts.

- Run in the background (multi-hour runs are normal); read
  `.architect/last-run.jsonl` and the repo state afterwards.
- Pin the model explicitly (`--provider openrouter --model minimax/minimax-m3`).
  `pi` defaults can be set in `~/.pi/agent/settings.json`, but automations
  should not rely on session defaults.
- Effort maps to `--thinking` (`off|minimal|low|medium|high|xhigh`): `xhigh`
  default for unattended builder work; downgrade a routine, tightly-specified
  lane to `high` (record which and why in the spec).
- **Builders never commit, and the architect verifies it.** `pi` has no sandbox
  to make `.git` read-only, so this is enforced after the run, not during it:
  before integrating a lane, confirm `git -C <worktree> log <freeze-sha>..` is
  empty and `git -C <worktree> status` shows only files inside the lane's
  declared set. A commit or an out-of-bounds write fails the lane — reset and
  re-dispatch (lanes are cheap, hard rule 7).
- Same-slice follow-up (e.g. answering PHASE 0 disagreements after the human
  rules): re-invoke the same session with
  `pi -p --session-id <slice>-<NN> "<rulings + proceed>"`. The `--session-id`
  pinned at dispatch makes the follow-up deterministic even with parallel lanes.
  Never resume across slices — every slice gets a fresh context.
- Cross-model review gate (high-stakes slices): the architect is Opus 4.8 and
  the builder is minimax-m3, so the architect reading the diff is *already* a
  cross-vendor review. For an extra adversarial pass, dump the diff and feed it
  to a fresh read-only reviewer:
  ```bash
  git -C <repo-root> diff <base>...HEAD > .architect/review-<slice>.diff
  pi -p --provider openrouter --model minimax/minimax-m3 --thinking high \
    -t read,grep,find @.architect/review-<slice>.diff \
    "Review this diff against the spec. Flag ONLY correctness/requirement/invariant gaps with file:line evidence. No style."
  ```
- Add `.architect/` to the repo's `.gitignore`.

## Stall detection and rescue

A dispatched run is STALLED when its `--mode json` run-log
(`.architect/...last-run.jsonl`) has not grown for 15+ minutes AND the last event
is an in-flight `bash` tool call. Silent gaps between events are normal model
thinking; a shell command that should take seconds sitting in flight for 15+
minutes is not.

Diagnose before killing: find the command's child under the `pi` PID
(pi → shell → child). Hot-spinning (high CPU) or blocked (zero CPU and none of
its expected side effects on disk) — hung either way.

Kill the NARROWEST thing: the stuck child process, not the `pi` run. The command
returns a failure to the builder, which adapts with its full context intact.
Kill the whole run only when the builder re-enters the same hang or the worktree
is broken; then discard the lane and re-dispatch (hard rule 7).

`pi` runs the `bash` tool directly with no sandbox, so the Codex-era
sandbox-specific hang sources don't apply — but long-running and interactive
commands still hang an unattended run. Spec consequence: give every potentially
long command an explicit timeout in the builder block, steer builders toward the
repo's existing test fixtures over hand-rolled long-running harnesses, and when a
gate needs a runtime that can't run unattended (interactive prompts, servers
without a timeout), have the builder record the exact failure as a
disagreement/blocker and verify what it can — gate verdicts are architect-run
anyway (hard rule 4). Write the gate file anticipating this.

## Manual alternative (human-driven)

Paste the builder block into an interactive `pi` session (no `-p`). `pi`'s agent
loop runs plan→act→test against the block's stopping condition while you watch
and steer. Use when the human wants to babysit a run.

## Builder block template

```
Execute the architect spec below. Operating rules:

PHASE 0 — Before any code: reply with your plan and EVERY disagreement you have
with this spec, with reasons, citing real files in this repo. Silent compliance
is a failure. Silent scope additions are a failure. If you have no
disagreements, state what you checked before concluding the spec is sound.
Verify the named APIs/formats/versions against the live dependencies before
planning around them.

PHASE 1 — Freeze shared contracts (schemas/interfaces) in docs/ first. After
freeze they are read-only for everyone including you. The files under
docs/gates/ are read-only at all times — editing them fails the slice
regardless of results.

PHASE 2 — Build YOUR LANE ONLY: exactly the files listed in BOUNDARIES. You
are one of several parallel lane agents working in isolated worktrees; files
outside your lane belong to other agents — touching them fails your lane.
No placeholder implementations — search the codebase before implementing;
full implementations only. Verify your work by running the lane's gate
commands and record the verbatim output. Do NOT commit and do NOT run any
git write command (commit/add/branch/reset/checkout) — the architect commits and
merges after verification, and verifies you made no commits. Do NOT delete lock
files or escalate privileges if a command fails; record the exact error and
continue. Give every potentially long command an explicit timeout; if a runtime
will not start unattended (interactive prompt, server with no timeout), record
the exact failure in your lane report and route around it — never busy-wait or
retry in a loop. When done, write your lane report to
docs/lanes/<slice>-<lane>.md with RAW results only — tables, numbers, command
output — no interpretation, no "promising". Every status claim must be backed
by a command result from this run. Keep the report compact — tables and
numbers, not prose. End it with exactly one status line:
STATUS: COMPLETE | COMPLETE_WITH_CONCERNS (list them) | BLOCKED (exact
blocker + what you tried). Verdicts belong to the architect and the
human. Persist until your lane is fully handled end-to-end; do not stop at
analysis or partial fixes.

=== OBJECTIVE (and why) ===
...

=== OUTPUT FORMAT ===
...

=== TOOL GUIDANCE (verification commands; verify-against-reality list) ===
...

=== BOUNDARIES (may touch / must not touch / out of scope) ===
...

=== DISAGREEMENT RULINGS (from last session) ===
...

=== ACCEPTANCE GATES (frozen at docs/gates/<slice>.md — read-only) ===
...
```

## Builder-side standing setup (one time per machine/repo)

- `~/.pi/agent/settings.json` may set `defaultProvider`/`defaultModel`, but
  dispatch still pins them explicitly. The `pi-web-access` extension must be
  installed (`pi install npm:pi-web-access`) so builders can verify APIs against
  live docs — it works zero-config via Exa (no key needed).
- Repo `AGENTS.md` (and `CLAUDE.md`) is the builder's standing context — `pi`
  loads both root-down. Put exact build/test commands and repo gotchas there;
  the loop's PHASE rules stay in the dispatch block so they version with the
  skill.
- Billing is OpenRouter per-token prepaid credit — there are no per-window
  quotas to exhaust mid-run, so unattended overnight loops just need a funded
  balance. The architect runs on the Claude plan in Claude Code.
