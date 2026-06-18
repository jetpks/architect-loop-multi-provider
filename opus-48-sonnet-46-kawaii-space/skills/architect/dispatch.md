# Builder dispatch reference ✨

Verified against the `claude` CLI (Claude Code) headless mode, June 2026 — yay! The
builder is `claude -p` (`--print`, the non-interactive headless mode) pinned to
`claude-sonnet-4-6` — the *same binary the architect runs, one tier down* (sibling
energy~). Key facts the skill encodes: prompt blocks go in on **stdin** (Claude Code has no
`@file`, and a big quoted block as a shell argument gets mangled — boo!); the model is
pinned with `--model claude-sonnet-4-6` (the `sonnet` alias floats to the latest
Sonnet — so pin the full id!); there is **no `-C`/working-dir flag**, so per-lane
dispatch `cd`s into the worktree; permissions are the **tool allow/deny lists**
(`--allowedTools`/`--disallowedTools`) plus `--permission-mode`, not a sandbox;
web access is the built-in `WebSearch`/`WebFetch` tools (no extension to install — easy!).

**The one load-bearing difference from the Codex design (read this twice!):** Codex's
`--sandbox workspace-write` made `.git` physically read-only. Claude Code has
**no automatic filesystem sandbox** in headless mode (the sandbox is opt-in via
settings, off by default), so `.git` is not hardware-protected. "Builders never
commit" (R7) is now enforced in three layers, weakest to strongest: (1) a runtime
first line — deny the git-write tools with `--disallowedTools 'Bash(git
commit:*)' …`; (2) worktree isolation between lanes; (3) the authoritative check
— an architect post-flight `git -C <worktree> log <repo-base>..` that must be
empty. The deny rules are not airtight (a builder can shell out — `sh -c 'git
commit …'` — past the pattern match), so the post-flight `git log` is what the
loop actually trusts. If a lane committed, treat the worktree as tampered: reset
and re-dispatch. No hard feelings, just a do-over! (｡•̀ᴗ-)✧

## The space is your workspace 🪐 (paths, once!)

Everything runs inside a space-cadet space (see `SKILL.md` → "Where everything
lives"). Throughout this file:

- `<space>` → the space root (the dir with `.space.yml`; `space current` prints
  it). Its own git repo — `repos/` and `tmp/` are gitignored.
- `<repo-root>` → the lane's target repo, `<space>/repos/<repo>`. Its own git
  repo; a worktree is added off its **base commit** `<repo-base>` (NOT the gate
  freeze, which is a commit in the space repo).
- **Memory** lives at `<space>/architect/` (`HANDOFF.md`, `gates/`, `lanes/`,
  `prd/`) — versioned by the space. **Scratch** lives at `<space>/tmp/architect/`
  (worktrees, dispatch blocks, run-logs) — gitignored by the space, so it never
  pollutes the space history *or* the target repos.

Use **absolute paths** for the block, the run-log, and the lane-report path,
since `claude -p` has no `-C` and each lane `cd`s into its worktree.

**Preflight (once per environment) 🌸:** run `claude --version`, and confirm the
builder model resolves with a one-shot canary
(`echo ok | claude -p --model claude-sonnet-4-6 --max-turns 1`). No API key — the
builder runs on your Claude plan — but note headless `claude -p` draws on the
Agent SDK credit pool (separate from interactive usage since June 15 2026; see
`DESIGN.md` §4). On the first real dispatch in a new environment, launch ONE
canary lane and confirm it starts cleanly before fanning anything out. Patience pays off!

## Canonical headless dispatch (architect-driven) 🚀

Write the builder block to a file first, then feed it on **stdin** — never as a
shell argument! Big prompt blocks contain quotes that shells (especially Windows
PowerShell) mangle; a stdin redirect injects the file verbatim and sidesteps it.
`claude -p` with no prompt argument reads the prompt from stdin.
`--output-format stream-json --verbose` streams JSONL events to stdout; redirect
it to a run-log for liveness/stall checks. The lane's actual deliverable is the
report the builder writes with its `Write` tool to the absolute lane-report path
you give it (`<space>/architect/lanes/<slice>-<lane>.md`).

Single-lane slice (dispatch in the target repo's checkout, `<repo-root>`). Run
this too as a **background Bash tool call** (`run_in_background`) so your turn
doesn't block for the whole multi-hour run (nobody likes waiting~):

```bash
( cd <repo-root> && \
  claude -p --model claude-sonnet-4-6 \
    --permission-mode acceptEdits \
    --allowedTools 'Read,Edit,Write,Grep,Glob,Bash,WebSearch,WebFetch' \
    --disallowedTools 'Bash(git commit:*),Bash(git push:*),Bash(git reset:*),Bash(git merge:*),Bash(git rebase:*),Bash(git checkout:*),Bash(git branch:*)' \
    --output-format stream-json --verbose \
    --max-turns 200 \
    < <space>/tmp/architect/<slice>.block.md \
    > <space>/tmp/architect/<slice>.last-run.jsonl 2>&1 )
```

`acceptEdits` auto-approves file writes; listing `Bash` in `--allowedTools`
auto-approves shell commands so the run never blocks on a prompt; any tool *not*
on the allow list is denied rather than prompted in `-p` mode (so the builder
can't wander outside its toolset — stay in your lane, cutie!), and the `--disallowedTools` deny rules win
over the allow list (deny always takes precedence) as the runtime first line
against commits.

## Worktree fan-out (2–4 lanes — the architect owns the parallelism) 🌳

One isolated worktree + one fresh `claude -p` per lane, each launched as its own
**background Bash tool call** (your harness's `run_in_background`). Lanes declare
a target repo + file-touch set checked for overlap from the spec; each writes raw
results to its own `<space>/architect/lanes/<slice>-<lane>.md`, so nothing
collides — no stepping on toes! Claude Code has no `-C`, so each lane runs inside
a subshell `cd`'d into its worktree, with absolute paths for the block, the
run-log, and the lane report. The worktree itself lives in the space's gitignored
scratch, off the **target repo's** base commit.

```bash
# per lane: worktree off the TARGET REPO's base commit, placed in the space's
# scratch root (absolute path, so it lands outside the repo and outside memory).
git -C <repo-root> worktree add <space>/tmp/architect/wt/<slice>-<NN> \
  -b lane/<slice>-<NN> <repo-base>

# write the lane's builder block, then dispatch it. Issue this as its OWN Bash
# tool call with run_in_background — one call per lane. The command is a single
# BLOCKING claude -p (no trailing `&`, no `for` loop).
( cd <space>/tmp/architect/wt/<slice>-<NN> && \
  claude -p --model claude-sonnet-4-6 \
    --permission-mode acceptEdits \
    --allowedTools 'Read,Edit,Write,Grep,Glob,Bash,WebSearch,WebFetch' \
    --disallowedTools 'Bash(git commit:*),Bash(git push:*),Bash(git reset:*),Bash(git merge:*),Bash(git rebase:*),Bash(git checkout:*),Bash(git branch:*)' \
    --output-format stream-json --verbose --max-turns 200 \
    < <space>/tmp/architect/wt/<slice>-<NN>.block.md \
    > <space>/tmp/architect/wt/<slice>-<NN>.last-run.jsonl 2>&1 )
```

**Background with the harness, never with shell `&`! (｡•́︿•̀｡)** A `for NN … do (…) & done`
loop is a *launcher* process: it returns the instant it has spawned the lane
children, the harness reaps those now-orphaned `claude` processes, and every lane
dies at once with no `result` — partial diffs, no reports (this exact failure has
happened: three lanes killed at the same second, zero output — tragic!). One blocking
`claude -p` per background Bash tool keeps each lane attached to a
harness-tracked task that survives the full multi-hour run and reports completion
per lane. Redirect stderr (`2>&1`) into the run-log too, so a dispatch error
lands somewhere instead of vanishing into the void.

A worktree keeps each lane's working files apart, so parallel lanes never touch
each other's files — personal space respected! Lanes in different repos can't
collide at all. Nothing reaches a branch until the architect's checks pass — but
because Claude Code has no sandbox protecting `.git`, that is enforced by the
deny rules above plus the post-flight `git log`/`git status` checks below, not by
the runtime (see the load-bearing note at the top).

### Integration (architect-only, after per-lane post-flight passes) 🧩

Per touched repo — a cross-repo mission yields one `slice/<name>` branch per repo:

```bash
git -C <repo-root> checkout -b slice/<name> <repo-base>
# per passing lane in THIS repo, sequentially:
git -C <space>/tmp/architect/wt/<slice>-<NN> add -A
git -C <space>/tmp/architect/wt/<slice>-<NN> commit -m "lane <NN>: <what>"
git -C <repo-root> merge --no-ff lane/<slice>-<NN>
<run the gate commands>          # integration smoke after every merge
# cleanup:
git -C <repo-root> worktree remove <space>/tmp/architect/wt/<slice>-<NN>
git -C <repo-root> branch -d lane/<slice>-<NN>
```

Then consolidate the lane reports into `<space>/architect/HANDOFF.md` (recording
each repo's `slice/<name>` branch) and commit the space.

A merge conflict = the lane plan wasn't disjoint = a spec defect. Kill the
conflicting lane and re-spec; don't hand-resolve builder conflicts (resist the urge, friend!).

- Background each lane as its own harness task and let the **per-lane completion
  notification** bring you back (multi-hour runs are totally normal~); read
  `<space>/tmp/architect/wt/<slice>-<NN>.last-run.jsonl` and the worktree state
  afterwards. Do not write a blocking `while pgrep …; sleep` wait loop as a Bash
  command — that is itself a launcher that ties up a turn. When you return to a
  lane, check liveness via run-log growth (the stall rules below still apply
  unchanged).
- Pin the model explicitly (`--model claude-sonnet-4-6`). The `sonnet` alias
  floats to the latest Sonnet — fine interactively, but automations pin the full
  id so a model bump can't silently change builder behavior mid-project (no surprises!).
- Effort = thinking budget. Claude Code has no per-invocation effort flag the way
  Codex exposed `model_reasoning_effort`; the builder sets thinking depth **in the
  block** via the escalation keywords (`think` < `think hard` < `think harder` <
  `ultrathink`), or you floor
  it with the `MAX_THINKING_TOKENS` env var on the dispatch. Default unattended
  builder work to a high budget (open the block with "Think harder…"); downgrade
  a routine, tightly-specified lane to "think hard" (record which and why in the
  spec).
- **Builders never commit, and the architect verifies it! 🔒** Claude Code has no
  sandbox to make `.git` read-only, so this is enforced by the deny rules at
  dispatch *and* checked after the run: before integrating a lane, confirm
  `git -C <worktree> log <repo-base>..` is empty and `git -C <worktree> status`
  shows only files inside the lane's declared set. A commit or an out-of-bounds
  write fails the lane — reset and re-dispatch (lanes are cheap, hard rule 7).
- Same-slice follow-up (e.g. answering PHASE 0 disagreements after the human
  rules): from the lane's worktree, `claude -p --continue "<rulings + proceed>"`
  resumes that worktree's most recent session with full context — sessions are
  scoped per directory, so `--continue` (`-c`) is deterministic even with
  parallel lanes (handy~). (Alternatively pin `--session-id <uuid>` at dispatch and resume
  with `--resume <uuid>`.) Resume the **same way you dispatch** — one background
  Bash tool call per lane, each a single blocking `claude -p --continue …`, never
  a `&` loop (a `&` launcher orphans the resumed lanes exactly as it does fresh
  ones). Never resume across slices — every slice gets a fresh context (clean slate!).
- Cross-model review gate (high-stakes slices): the architect is Opus 4.8 and the
  builder is Sonnet 4.6 — both Claude Code, so this is a cross-*tier* read inside
  one lab, not cross-vendor (see `DESIGN.md` R3). The architect (Opus) reading the
  diff is already the stronger-model fresh-context pass. For an extra adversarial
  pass, pipe the instruction + diff to a fresh read-only reviewer:
  ```bash
  { echo "Review this diff against the spec. Flag ONLY correctness/requirement/invariant gaps with file:line evidence. No style."; \
    git -C <repo-root> diff <repo-base>...HEAD; } \
  | claude -p --model claude-sonnet-4-6 --allowedTools 'Read,Grep,Glob'
  ```
- Scratch lives under the space's already-gitignored `tmp/`, so there's nothing
  to add to any repo's `.gitignore` — the target repos stay pristine. ✨

## Stall detection and rescue 🚑

A dispatched run is STALLED when its `stream-json` run-log
(`<space>/tmp/architect/…last-run.jsonl`) has not grown for 15+ minutes AND the
last event is an in-flight `Bash` tool call (a `tool_use` for `Bash` with no
matching `tool_result` yet). Silent gaps between events are normal model thinking
(just pondering~); a shell command that should take seconds sitting in flight for
15+ minutes is not.

Diagnose before killing — be a good detective! Find the command's child under the `claude` PID
(claude → shell → child). Hot-spinning (high CPU) or blocked (zero CPU and none
of its expected side effects on disk) — hung either way.

Kill the NARROWEST thing: the stuck child process, not the `claude` run. The
command returns a failure to the builder, which adapts with its full context
intact (resilient little thing!). Kill the whole run only when the builder re-enters the same hang or the
worktree is broken; then discard the lane and re-dispatch (hard rule 7).

Claude Code runs the `Bash` tool directly with no sandbox, so the Codex-era
sandbox-specific hang sources don't apply — but long-running and interactive
commands still hang an unattended run (sneaky!). Spec consequence: give every potentially
long command an explicit timeout in the builder block (the `Bash` tool also takes
a per-call timeout), cap the run with `--max-turns` as a loop backstop, steer
builders toward the repo's existing test fixtures over hand-rolled long-running
harnesses, and when a gate needs a runtime that can't run unattended (interactive
prompts, servers without a timeout), have the builder record the exact failure as
a disagreement/blocker and verify what it can — gate verdicts are architect-run
anyway (hard rule 4). Write the gate file anticipating this.

## Manual alternative (human-driven) 🧑‍💻

Paste the builder block into an interactive `claude` session (no `-p`) started
from the lane's worktree. Claude Code's agent loop runs plan→act→test against the
block's stopping condition while you watch and steer — approve tools as they
come, or set `/permissions` first. Use when the human wants to babysit a run
(sometimes you just wanna watch~).

## Builder block template 📝

```
Execute the architect spec below. Operating rules:

PHASE 0 — Before any code: reply with your plan and EVERY disagreement you have
with this spec, with reasons, citing real files in this repo. Silent compliance
is a failure. Silent scope additions are a failure. If you have no
disagreements, state what you checked before concluding the spec is sound.
Verify the named APIs/formats/versions against the live dependencies before
planning around them.

PHASE 1 — Freeze shared contracts (schemas/interfaces) in this repo's docs/
first. After freeze they are read-only for everyone including you. The
acceptance gates are pasted below and are read-only at all times — editing
anything they point at to game them fails the slice regardless of results.

PHASE 2 — Build YOUR LANE ONLY: exactly the files listed in BOUNDARIES, in this
repo (your worktree). You are one of several parallel lane agents working in
isolated worktrees, possibly across different repos; files outside your lane
belong to other agents — touching them fails your lane. No placeholder
implementations — search the codebase before implementing; full implementations
only. Verify your work by running the lane's gate commands and record the
verbatim output. Do NOT commit and do NOT run any git write command
(commit/add/branch/reset/checkout) — the architect commits and merges after
verification, and verifies you made no commits. Do NOT delete lock files or
escalate privileges if a command fails; record the exact error and continue.
Give every potentially long command an explicit timeout; if a runtime will not
start unattended (interactive prompt, server with no timeout), record the exact
failure in your lane report and route around it — never busy-wait or retry in a
loop. When done, write your lane report to the LANE REPORT PATH given below with
RAW results only — tables, numbers, command output — no interpretation, no
"promising". Every status claim must be backed by a command result from this
run. Keep the report compact — tables and numbers, not prose. End it with
exactly one status line:
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

=== LANE REPORT PATH (write your report here — absolute) ===
<space>/architect/lanes/<slice>-<lane>.md

=== DISAGREEMENT RULINGS (from last session) ===
...

=== ACCEPTANCE GATES (frozen in the space at architect/gates/<slice>.md — read-only; verbatim below) ===
...
```

## Builder-side standing setup (one time per machine/repo) 🛠️

- The builder is the same `claude` binary as the architect, one tier down —
  nothing extra to install (love that!). Pin the model per dispatch
  (`--model claude-sonnet-4-6`); a `~/.claude/settings.json` `"model"` default is
  fine interactively, but automations pin it explicitly so a default can't
  silently swap the builder.
- Each target repo's `CLAUDE.md` is the builder's standing context — Claude Code
  loads it root-down automatically from the worktree. Put exact build/test
  commands and repo gotchas there; the loop's PHASE rules stay in the dispatch
  block so they version with the skill. (Claude Code does **not** auto-read
  `AGENTS.md`; if a repo keeps its build/test docs there, add `@AGENTS.md` to its
  `CLAUDE.md` to pull it in.)
- The builder is a bare `claude -p` over the block — it is not invoking the
  `/architect` skills, the block is its entire instruction set. (`--bare` would
  give a leaner builder context but also drops `CLAUDE.md`/skills/hooks — keep
  `CLAUDE.md`, so skip `--bare` unless the repo has no standing build/test doc.)
- Billing: headless `claude -p` draws on the Agent SDK credit pool on your Claude
  plan (separate from interactive usage limits since June 15 2026). There's no
  per-window quota that dies mid-run the way a chat session can, but a long
  parallel fan-out does spend that pool (so spend wisely~). The architect runs as your interactive
  Claude Code session.
