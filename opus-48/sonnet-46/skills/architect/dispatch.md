# Builder dispatch reference

Verified against the `claude` CLI (Claude Code) headless mode, June 2026. The
builder is `claude -p` (`--print`, the non-interactive headless mode) pinned to
`claude-sonnet-4-6` — the *same binary the architect runs, one tier down*. Key
facts the skill encodes: prompt blocks go in on **stdin** (Claude Code has no
`@file`, and a big quoted block as a shell argument gets mangled); the model is
pinned with `--model claude-sonnet-4-6` (the `sonnet` alias floats to the latest
Sonnet — pin the full id); there is **no `-C`/working-dir flag**, so per-lane
dispatch `cd`s into the worktree; permissions are the **tool allow/deny lists**
(`--allowedTools`/`--disallowedTools`) plus `--permission-mode`, not a sandbox;
web access is the built-in `WebSearch`/`WebFetch` tools (no extension to install).

**The one load-bearing difference from the Codex design:** Codex's
`--sandbox workspace-write` made `.git` physically read-only. Claude Code has
**no automatic filesystem sandbox** in headless mode (the sandbox is opt-in via
settings, off by default), so `.git` is not hardware-protected. "Builders never
commit" (R7) is now enforced in three layers, weakest to strongest: (1) a runtime
first line — deny the git-write tools with `--disallowedTools 'Bash(git
commit:*)' …`; (2) worktree isolation between lanes; (3) the authoritative check
— an architect post-flight `git -C <worktree> log <freeze-sha>..` that must be
empty. The deny rules are not airtight (a builder can shell out — `sh -c 'git
commit …'` — past the pattern match), so the post-flight `git log` is what the
loop actually trusts. If a lane committed, treat the worktree as tampered: reset
and re-dispatch.

**Preflight (once per environment):** run `claude --version`, and confirm the
builder model resolves with a one-shot canary
(`echo ok | claude -p --model claude-sonnet-4-6 --max-turns 1`). No API key — the
builder runs on your Claude plan — but note headless `claude -p` draws on the
Agent SDK credit pool (separate from interactive usage since June 15 2026; see
`DESIGN.md` §4). On the first real dispatch in a new environment, launch ONE
canary lane and confirm it starts cleanly before fanning anything out.

## Canonical headless dispatch (architect-driven)

Write the builder block to a file first, then feed it on **stdin** — never as a
shell argument. Big prompt blocks contain quotes that shells (especially Windows
PowerShell) mangle; a stdin redirect injects the file verbatim and sidesteps it.
`claude -p` with no prompt argument reads the prompt from stdin.
`--output-format stream-json --verbose` streams JSONL events to stdout; redirect
it to a run-log for liveness/stall checks. The lane's actual deliverable is the
report the builder writes with its `Write` tool to `docs/lanes/<slice>-<lane>.md`.

Single-lane slice (dispatch in the main checkout). Run this too as a **background
Bash tool call** (`run_in_background`) so your turn doesn't block for the whole
multi-hour run:

```bash
claude -p --model claude-sonnet-4-6 \
  --permission-mode acceptEdits \
  --allowedTools 'Read,Edit,Write,Grep,Glob,Bash,WebSearch,WebFetch' \
  --disallowedTools 'Bash(git commit:*),Bash(git push:*),Bash(git reset:*),Bash(git merge:*),Bash(git rebase:*),Bash(git checkout:*),Bash(git branch:*)' \
  --output-format stream-json --verbose \
  --max-turns 200 \
  < .architect/dispatch-block.md \
  > .architect/last-run.jsonl 2>&1
```

`acceptEdits` auto-approves file writes; listing `Bash` in `--allowedTools`
auto-approves shell commands so the run never blocks on a prompt; any tool *not*
on the allow list is denied rather than prompted in `-p` mode (so the builder
can't wander outside its toolset), and the `--disallowedTools` deny rules win
over the allow list (deny always takes precedence) as the runtime first line
against commits.

## Worktree fan-out (2–4 lanes — the architect owns the parallelism)

One isolated worktree + one fresh `claude -p` per lane, each launched as its own
**background Bash tool call** (your harness's `run_in_background`). Lanes have
file-touch sets checked for overlap from the spec; each writes raw results to its
own `docs/lanes/<slice>-<lane>.md`, so nothing collides. Claude Code has no `-C`,
so each lane runs inside a subshell `cd`'d into its worktree, with absolute paths
for the block and the run-log.

```bash
# per lane, off the freeze commit
git -C <repo-root> worktree add .architect/wt/<slice>-<NN> \
  -b lane/<slice>-<NN> <freeze-sha>

# write the lane's builder block, then dispatch it. Issue this as its OWN Bash
# tool call with run_in_background — one call per lane. The command is a single
# BLOCKING claude -p (no trailing `&`, no `for` loop).
( cd <repo-root>/.architect/wt/<slice>-<NN> && \
  claude -p --model claude-sonnet-4-6 \
    --permission-mode acceptEdits \
    --allowedTools 'Read,Edit,Write,Grep,Glob,Bash,WebSearch,WebFetch' \
    --disallowedTools 'Bash(git commit:*),Bash(git push:*),Bash(git reset:*),Bash(git merge:*),Bash(git rebase:*),Bash(git checkout:*),Bash(git branch:*)' \
    --output-format stream-json --verbose --max-turns 200 \
    < <repo-root>/.architect/wt/<slice>-<NN>.block.md \
    > <repo-root>/.architect/wt/<slice>-<NN>.last-run.jsonl 2>&1 )
```

**Background with the harness, never with shell `&`.** A `for NN … do (…) & done`
loop is a *launcher* process: it returns the instant it has spawned the lane
children, the harness reaps those now-orphaned `claude` processes, and every lane
dies at once with no `result` — partial diffs, no reports (this exact failure has
happened: three lanes killed at the same second, zero output). One blocking
`claude -p` per background Bash tool keeps each lane attached to a
harness-tracked task that survives the full multi-hour run and reports completion
per lane. Redirect stderr (`2>&1`) into the run-log too, so a dispatch error
lands somewhere instead of vanishing.

A worktree keeps each lane's working files apart, so parallel lanes never touch
each other's files. Nothing reaches a branch until the architect's checks pass —
but because Claude Code has no sandbox protecting `.git`, that is enforced by the
deny rules above plus the post-flight `git log`/`git status` checks below, not by
the runtime (see the load-bearing note at the top).

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

- Background each lane as its own harness task and let the **per-lane completion
  notification** bring you back (multi-hour runs are normal); read
  `.architect/last-run.jsonl` and the repo state afterwards. Do not write a
  blocking `while pgrep …; sleep` wait loop as a Bash command — that is itself a
  launcher that ties up a turn. When you return to a lane, check liveness via
  run-log growth (the stall rules below still apply unchanged).
- Pin the model explicitly (`--model claude-sonnet-4-6`). The `sonnet` alias
  floats to the latest Sonnet — fine interactively, but automations pin the full
  id so a model bump can't silently change builder behavior mid-project.
- Effort = thinking budget. Claude Code has no per-invocation effort flag the way
  Codex exposed `model_reasoning_effort`; the builder sets thinking depth **in the
  block** via the escalation keywords (`think` < `think hard` < `think harder` <
  `ultrathink`), or you floor
  it with the `MAX_THINKING_TOKENS` env var on the dispatch. Default unattended
  builder work to a high budget (open the block with "Think harder…"); downgrade
  a routine, tightly-specified lane to "think hard" (record which and why in the
  spec).
- **Builders never commit, and the architect verifies it.** Claude Code has no
  sandbox to make `.git` read-only, so this is enforced by the deny rules at
  dispatch *and* checked after the run: before integrating a lane, confirm
  `git -C <worktree> log <freeze-sha>..` is empty and `git -C <worktree> status`
  shows only files inside the lane's declared set. A commit or an out-of-bounds
  write fails the lane — reset and re-dispatch (lanes are cheap, hard rule 7).
- Same-slice follow-up (e.g. answering PHASE 0 disagreements after the human
  rules): from the lane's worktree, `claude -p --continue "<rulings + proceed>"`
  resumes that worktree's most recent session with full context — sessions are
  scoped per directory, so `--continue` (`-c`) is deterministic even with
  parallel lanes. (Alternatively pin `--session-id <uuid>` at dispatch and resume
  with `--resume <uuid>`.) Resume the **same way you dispatch** — one background
  Bash tool call per lane, each a single blocking `claude -p --continue …`, never
  a `&` loop (a `&` launcher orphans the resumed lanes exactly as it does fresh
  ones). Never resume across slices — every slice gets a fresh context.
- Cross-model review gate (high-stakes slices): the architect is Opus 4.8 and the
  builder is Sonnet 4.6 — both Claude Code, so this is a cross-*tier* read inside
  one lab, not cross-vendor (see `DESIGN.md` R3). The architect (Opus) reading the
  diff is already the stronger-model fresh-context pass. For an extra adversarial
  pass, pipe the instruction + diff to a fresh read-only reviewer:
  ```bash
  { echo "Review this diff against the spec. Flag ONLY correctness/requirement/invariant gaps with file:line evidence. No style."; \
    git -C <repo-root> diff <base>...HEAD; } \
  | claude -p --model claude-sonnet-4-6 --allowedTools 'Read,Grep,Glob'
  ```
- Add `.architect/` to the repo's `.gitignore`.

## Stall detection and rescue

A dispatched run is STALLED when its `stream-json` run-log
(`.architect/…last-run.jsonl`) has not grown for 15+ minutes AND the last event
is an in-flight `Bash` tool call (a `tool_use` for `Bash` with no matching
`tool_result` yet). Silent gaps between events are normal model thinking; a shell
command that should take seconds sitting in flight for 15+ minutes is not.

Diagnose before killing: find the command's child under the `claude` PID
(claude → shell → child). Hot-spinning (high CPU) or blocked (zero CPU and none
of its expected side effects on disk) — hung either way.

Kill the NARROWEST thing: the stuck child process, not the `claude` run. The
command returns a failure to the builder, which adapts with its full context
intact. Kill the whole run only when the builder re-enters the same hang or the
worktree is broken; then discard the lane and re-dispatch (hard rule 7).

Claude Code runs the `Bash` tool directly with no sandbox, so the Codex-era
sandbox-specific hang sources don't apply — but long-running and interactive
commands still hang an unattended run. Spec consequence: give every potentially
long command an explicit timeout in the builder block (the `Bash` tool also takes
a per-call timeout), cap the run with `--max-turns` as a loop backstop, steer
builders toward the repo's existing test fixtures over hand-rolled long-running
harnesses, and when a gate needs a runtime that can't run unattended (interactive
prompts, servers without a timeout), have the builder record the exact failure as
a disagreement/blocker and verify what it can — gate verdicts are architect-run
anyway (hard rule 4). Write the gate file anticipating this.

## Manual alternative (human-driven)

Paste the builder block into an interactive `claude` session (no `-p`). Claude
Code's agent loop runs plan→act→test against the block's stopping condition while
you watch and steer — approve tools as they come, or set `/permissions` first.
Use when the human wants to babysit a run.

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

- The builder is the same `claude` binary as the architect, one tier down —
  nothing extra to install. Pin the model per dispatch
  (`--model claude-sonnet-4-6`); a `~/.claude/settings.json` `"model"` default is
  fine interactively, but automations pin it explicitly so a default can't
  silently swap the builder.
- Repo `CLAUDE.md` is the builder's standing context — Claude Code loads it
  root-down automatically. Put exact build/test commands and repo gotchas there;
  the loop's PHASE rules stay in the dispatch block so they version with the
  skill. (Claude Code does **not** auto-read `AGENTS.md`; if the repo keeps its
  build/test docs there, add `@AGENTS.md` to `CLAUDE.md` to pull it in.)
- The builder is a bare `claude -p` over the block — it is not invoking the
  `/architect` skills, the block is its entire instruction set. (`--bare` would
  give a leaner builder context but also drops `CLAUDE.md`/skills/hooks — keep
  `CLAUDE.md`, so skip `--bare` unless the repo has no standing build/test doc.)
- Billing: headless `claude -p` draws on the Agent SDK credit pool on your Claude
  plan (separate from interactive usage limits since June 15 2026). There's no
  per-window quota that dies mid-run the way a chat session can, but a long
  parallel fan-out does spend that pool. The architect runs as your interactive
  Claude Code session.
