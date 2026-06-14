# Builder dispatch reference

Verified live against Codex CLI 0.139 (June 2026). Facts that correct common
misinformation: the model slug is `gpt-5.5` (not `gpt-5.5-codex` — the
-codex-suffixed line is deprecated); `--search` and `-a/--ask-for-approval`
are **TUI-only flags — `codex exec` rejects both** (exec is non-interactive
by design; the sandbox flag is the only permission control); Goal Mode's only
real subcommands are bare `/goal`, `/goal pause|resume|clear`.

**Preflight (once per environment):** run `codex --version`. Need ≥ 0.133.
On the first dispatch in a new environment, launch ONE canary run and confirm
it starts cleanly before fanning anything out — CLI flags churn between
versions.

## Canonical headless dispatch (architect-driven)

Write the builder block to a file first, then pass it via **stdin** (`-`) —
never as a shell argument. Big prompt blocks contain quotes that shells
(especially Windows PowerShell) mangle; a mangled argument makes codex fall
back to waiting on stdin and hang forever in a background shell.

Single-lane slice (dispatch in the main checkout):

```bash
codex exec -C <repo-root> --sandbox workspace-write \
  -m gpt-5.5 -c model_reasoning_effort="xhigh" \
  --json -o .architect/last-run.md \
  - < .architect/dispatch-block.md
```

## Worktree fan-out (2–4 lanes — the architect owns the parallelism)

One isolated worktree + one fresh `codex exec` per lane, all launched in
parallel in the background. Lanes have file-touch sets checked for overlap from
the spec; each writes raw results to its own `docs/lanes/<slice>-<lane>.md`,
so nothing collides.

```bash
# per lane, off the freeze commit
git -C <repo-root> worktree add .architect/wt/<slice>-<NN> \
  -b lane/<slice>-<NN> <freeze-sha>

# write the lane's builder block, then dispatch (background, all lanes parallel)
codex exec -C <repo-root>/.architect/wt/<slice>-<NN> --sandbox workspace-write \
  -m gpt-5.5 -c model_reasoning_effort="xhigh" \
  --json -o .architect/wt/<slice>-<NN>.last-run.md \
  - < .architect/wt/<slice>-<NN>.block.md
```

A worktree's `.git` is a pointer file and the resolved git dir is
sandbox-protected too — builders cannot commit or touch shared history from
any lane. That's a feature: nothing reaches a branch until the architect's
checks pass.

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
  `.architect/last-run.md` and the repo state afterwards.
- Pin the model explicitly — automations have been reported silently falling
  back to older models.
- Effort: `xhigh` default (based on the cited review-survival data for
  unattended work);
  architect downgrades routine, tightly-specified slices to `"high"`.
- Same-slice follow-up (e.g. answering PHASE 0 disagreements after the human
  rules): `codex exec resume --last "<rulings + proceed>"`. Never resume
  across slices — every slice gets a fresh context.
- Optional: `--output-schema <schema.json>` to force a machine-checkable final
  report.
- Cross-model review gate: `codex review --base <branch>` (or `--uncommitted`),
  with custom focus text appended.
- Add `.architect/` to the repo's `.gitignore`.
- **Builders never commit — the architect does.** workspace-write protects
  `.git` as read-only (verified on Windows, Codex 0.139 — no config toggle;
  `writable_roots` does not bypass it; worktree pointer files are resolved and
  protected too). This is load-bearing for the loop: lanes do not have commit
  access, so nothing reaches a branch until the architect's tamper, boundary,
  and gate checks pass.

## Stall detection and rescue (verified live: Windows, Codex 0.139)

A dispatched run is STALLED when its `--json` output file has not grown for
15+ minutes AND the last event is an `in_progress` command_execution. Silent
gaps between events are normal model thinking; a shell command that should
take seconds sitting in flight for 15+ minutes is not.

Diagnose before killing: find the command's child under the codex PID
(codex → shell → child). Hot-spinning (high CPU) or blocked (zero CPU and
none of its expected side effects on disk) — hung either way.

Kill the NARROWEST thing: the stuck child process, not the codex run. The
command returns a failure to the builder, which adapts with its full context
intact — this has rescued a run with 1.5h of grounding invested. Kill the
whole run only when the builder re-enters the same hang or the worktree is
broken; then discard the lane and re-dispatch (hard rule 7).

Known sandbox hang sources (verified): `asyncio.create_subprocess_exec` and
anything built on it — Playwright browser launch, anyio subprocess pools —
fails or hangs under workspace-write, while plain `subprocess.run` works.
Hand-rolled long-running fixture scripts piped through PowerShell
here-strings are a repeat offender; steer builders toward the repo's existing
test fixtures.

Spec consequence: when a gate needs a runtime the sandbox cannot execute
(browser e2e, asyncio-subprocess harnesses), expect the builder to record the
exact failure as a disagreement/blocker and verify what it can; the architect
runs that gate outside the sandbox at judgment time — gate verdicts are
architect-run anyway (hard rule 4). Write the gate file anticipating this.

## Manual alternative (human-driven)

Paste the builder block into an interactive `codex` session prefixed with
`/goal ` — Codex loops plan→act→test→review against the stopping condition
until done. Use when the human wants to watch or steer the run.

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
commands and record the verbatim output. Do NOT commit — the sandbox protects
.git by design; the architect commits and merges after verification. Do NOT
delete lock files or escalate privileges if a git command fails; record the
exact error and continue. Give every potentially long command an explicit
timeout; if a runtime will not start under the sandbox (asyncio subprocess,
browser launch), record the exact failure in your lane report and route
around it — never busy-wait or retry in a loop. When done, write your lane report to
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

- `~/.codex/config.toml`: `model = "gpt-5.5"`. Parallelism is
  architect-orchestrated worktrees — it does NOT depend on Codex's experimental
  `[features] multi_agent` config. (A lane agent may still use Codex-internal
  subagents for its own intra-lane work if that feature is enabled; optional.)
- Repo `AGENTS.md`: exact build/test commands and repo gotchas only — the
  loop's PHASE rules stay in the dispatch block so they version with the skill.
- Subscription quotas are per-5h window + weekly cap; long runs draw the weekly
  pool. For overnight unattended runs that must not die mid-run, `CODEX_API_KEY`
  per-token billing avoids window exhaustion.
