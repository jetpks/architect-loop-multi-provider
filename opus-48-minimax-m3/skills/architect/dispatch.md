# Builder dispatch reference

Verified against `pi` 0.79.2 (`pi --help`, June 2026). The builder is `pi`
driven against OpenRouter on `minimax/minimax-m3`. Key facts the skill encodes:
`pi -p` (`--print`) is the non-interactive, headless mode (the `codex exec`
analog); `pi` has no working-dir flag; permissions are controlled by the **tool
allowlist** (`-t`), not a sandbox; web access comes from the `pi-web-access`
extension (tools `web_search`, `fetch_content`).

## The load-bearing difference from Codex — and how we close it

`pi` has **no built-in sandbox**, and two things follow that the Codex design
got for free from `--sandbox workspace-write`:

1. `.git` is not protected, so "builders never commit" (R7) isn't runtime-enforced.
2. `pi`'s `bash` tool does **not** stay in the launched worktree cwd — minimax-m3
   keys off the absolute main-checkout paths in the spec and `cd`s back into the
   main checkout, so naive `git worktree` isolation does not hold (a real 2-lane
   run had both builders' edits land in the main tree).

We close both with **one OS policy sandbox** wrapped around every `pi` launch —
the `pi-sandbox` helper shipped next to this skill (`sandbox/pi-sandbox`). It
confines a `pi` process to a single writable root (the lane's worktree, or the
main checkout for a single lane); reads and network stay open. Because a git
worktree's objects and index live in the *main* repo's `.git` — outside the
writable root — `git add`/`commit` fail with `EPERM`, and a stray `cd` into the
main checkout can read but **not write**. So worktree isolation and the
no-commit rule are enforced by the kernel, restoring parity with Codex. This is
verified on macOS (Seatbelt) and Linux (Landlock); see "The sandbox" below.

The post-flight `git log`/`git status` checks stay as cheap defense-in-depth,
but they are no longer the only thing standing between a builder and `.git`.

**Preflight (once per environment):** `pi --version`; `OPENROUTER_API_KEY` set;
`pi --list-models minimax/minimax-m3` resolves; the `pi-sandbox` helper resolves
(below) and its backend is present (`/usr/bin/sandbox-exec` on macOS, `landrun`
on Linux). First dispatch in a new environment is a canary — launch ONE
sandboxed run and confirm it starts cleanly (run-log growing, empty stderr,
report written *inside* the worktree) before fanning out.

## The sandbox (`pi-sandbox`)

`install.sh` copies the helper to `~/.claude/skills/architect/sandbox/pi-sandbox`
(or `<repo>/.claude/skills/architect/sandbox/pi-sandbox` with `--project`).
Resolve it once per session and reuse:

```bash
PI_SANDBOX="$(ls ~/.claude/skills/architect/sandbox/pi-sandbox \
                 .claude/skills/architect/sandbox/pi-sandbox 2>/dev/null | head -1)"
```

It takes a writable root, then `--`, then the command:

```bash
"$PI_SANDBOX" <writable-root> -- pi -p --provider openrouter --model minimax/minimax-m3 ...
```

- **macOS** — Apple Seatbelt via `/usr/bin/sandbox-exec`, base allow-list adapted
  from `openai/codex`'s proven profile. Children inherit the policy, so the
  `bash` tool `pi` spawns is confined too. (`sandbox-exec` is deprecated but
  functional and is what Codex itself uses; no signing needed.)
- **Linux** — Landlock LSM (kernel 5.13+, unprivileged, no namespaces) via
  [`landrun`](https://github.com/Zouuup/landrun). Landlock has no deny rule, so
  the *combined-lane* case (writable root = main checkout) leans on the
  post-flight check for `.git`; the worktree case is fully covered because the
  real `.git` is outside the root.
- **No sandbox** (Windows, or Linux without `landrun`) — `pi-sandbox` exits 2.
  Fall back to a single combined lane in the main checkout plus the post-flight
  `git log` check (see "No-sandbox fallback").

Writable paths under the sandbox: the root, the root-local `$TMPDIR`, `/dev/null`,
and `pi`'s own state dir (`~/.pi`). Everything else is read-only; network is open.

## Canonical headless dispatch (single lane, main checkout)

Write the builder block to a file first, then pass it with `@file` — never as a
shell argument. Big prompt blocks contain quotes that shells (especially Windows
PowerShell) mangle; `@file` injects the file contents verbatim. `--mode json`
streams JSONL events to stdout; redirect it to a run-log for liveness/stall
checks. The lane's deliverable is the report the builder writes with its `write`
tool to `docs/lanes/<slice>.md`.

```bash
"$PI_SANDBOX" "$PWD" -- \
  pi -p --provider openrouter --model minimax/minimax-m3 --thinking xhigh \
    --session-id <slice> \
    -t read,bash,edit,write,grep,find,web_search,fetch_content \
    --mode json @.architect/dispatch-block.md \
  > .architect/last-run.jsonl 2> .architect/last-run.err
```

Sandboxing the main checkout still buys the no-commit guarantee (`.git` is carved
out of the writable root on macOS; covered by post-flight on Linux).

## Worktree fan-out (2–4 lanes — the architect owns the parallelism)

One isolated worktree + one fresh `pi -p` per lane, each wrapped in `pi-sandbox`
confined to its own worktree, launched in the background. Lanes have file-touch
sets checked for overlap from the spec; each writes raw results to its own
`docs/lanes/<slice>-<lane>.md`, so nothing collides. Because each `pi` can only
write inside its worktree, a builder that `cd`s out is harmless — the escape
write is denied.

```bash
# per lane, off the freeze commit
WT="<repo-root>/.architect/wt/<slice>-<NN>"
git -C <repo-root> worktree add "$WT" -b lane/<slice>-<NN> <freeze-sha>

# write the lane's builder block to .architect/<slice>-<NN>.block.md, then
# dispatch in the background. pi-sandbox cd's into the worktree itself, so no
# `cd` is needed here; wrap in bash -c so the &/redirect survive a fish shell.
bash -c "'$PI_SANDBOX' '$WT' -- \
  pi -p --provider openrouter --model minimax/minimax-m3 --thinking xhigh \
    --session-id <slice>-<NN> \
    -t read,bash,edit,write,grep,find,web_search,fetch_content \
    --mode json @<repo-root>/.architect/<slice>-<NN>.block.md \
  > <repo-root>/.architect/<slice>-<NN>.last-run.jsonl 2>&1" &
sleep 8   # stagger — see concurrency note
```

Two launch gotchas the build run hit:

- **The tool shell may be `fish`**, where `(...)` is command substitution, so a
  `( cd … ) &` subshell breaks. Launch via `bash -c '…'` so the
  background/redirect syntax is POSIX (and `pi-sandbox` sets the cwd, so no `cd`
  is needed anyway).
- **Claude Code's safety classifier blocks spawning autonomous, bash-capable
  `pi` loops** without explicit human say-so. Expect to need a one-time Bash
  permission rule for `pi`/`pi-sandbox` (or the human's go-ahead) before
  unattended dispatch.

**Concurrency note:** minimax-m3 over OpenRouter **silently drops concurrent
requests** — launching 5 at once left only 1 with output, the rest exited 0
bytes with empty stderr. **Stagger the launches** (`sleep 8` between them) and
re-dispatch any lane whose run-log lands at 0 bytes.

## Truncated runs (pi step cap) → same-session continuation

A `pi -p` run can hit a step cap and **terminate mid-task** (seen at ~70 turns):
it exits 0 and the worktree is integrity-clean, but there is **no `STATUS:` line
and no lane report** — incomplete, not tampered. Don't reset it. Re-invoke the
**same session** to resume with full context:

```bash
"$PI_SANDBOX" "$WT" -- \
  pi -p --provider openrouter --model minimax/minimax-m3 --thinking xhigh \
    --session-id <slice>-<NN> --mode json @<repo-root>/.architect/<slice>-<NN>.continue.md \
  > <repo-root>/.architect/<slice>-<NN>.continue.jsonl 2>&1
```

The continuation block restates what's done, what remains (tests, lane report,
the `STATUS:` line), and the unchanged frozen gates. The pinned `--session-id` is
what makes the resume deterministic. If a run truncates repeatedly, the slice is
too big — re-spec it smaller.

## Integration (architect-only, after per-lane post-flight passes)

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

The architect runs these `git` writes outside the sandbox — the builder never
could. A merge conflict = the lane plan wasn't disjoint = a spec defect. Kill the
conflicting lane and re-spec; don't hand-resolve builder conflicts.

Per-lane post-flight, with evidence (now backed by the sandbox, kept as
defense-in-depth):

- `git -C <worktree> log <freeze-sha>..` is **empty** — a commit means the
  sandbox was bypassed or absent; treat as tampered, reset and re-dispatch (R7).
- `git -C <worktree> status` shows **only files inside the lane's declared set** —
  an out-of-bounds write fails the lane.
- `git diff` on `docs/gates/` is clean.

Notes:

- Pin the model explicitly (`--provider openrouter --model minimax/minimax-m3`).
  `pi` defaults can be set in `~/.pi/agent/settings.json`, but automations should
  not rely on session defaults.
- Effort maps to `--thinking` (`off|minimal|low|medium|high|xhigh`): `xhigh`
  default for unattended builder work; downgrade a routine, tightly-specified
  lane to `high` (record which and why in the spec).
- Same-slice follow-up (e.g. answering PHASE 0 disagreements after the human
  rules): re-invoke the same session through the sandbox with
  `"$PI_SANDBOX" "$WT" -- pi -p --session-id <slice>-<NN> "<rulings + proceed>"`.
  Never resume across slices — every slice gets a fresh context.
- Cross-model review gate (high-stakes slices): the architect is Opus 4.8 and
  the builder is minimax-m3, so the architect reading the diff is *already* a
  cross-vendor review. For an extra adversarial pass, dump the diff and feed it
  to a fresh read-only reviewer (no sandbox needed — read-only toolset):
  ```bash
  git -C <repo-root> diff <base>...HEAD > .architect/review-<slice>.diff
  pi -p --provider openrouter --model minimax/minimax-m3 --thinking high \
    -t read,grep,find @.architect/review-<slice>.diff \
    "Review this diff against the spec. Flag ONLY correctness/requirement/invariant gaps with file:line evidence. No style."
  ```
- Add `.architect/` to the repo's `.gitignore`.

## No-sandbox fallback (Windows, or Linux without landrun)

When `pi-sandbox` exits 2, there is no runtime isolation, so parallel worktrees
are unsafe (the cwd-escape returns). Fall back to **one combined lane in the main
checkout** — the spec still decomposes into disjoint lanes, but a single builder
builds their union, so there is no cwd to escape and no inter-lane interleaving.
Dispatch `pi -p` directly (no wrapper) and lean entirely on post-flight:
`git log <freeze>..` empty (no commits/stashes) and `git status` in-bounds. A
violation fails the slice — reset and re-dispatch.

## Stall detection and rescue

A dispatched run is STALLED when its `--mode json` run-log has not grown for 15+
minutes AND the last event is an in-flight `bash` tool call. Silent gaps between
events are normal model thinking; a shell command that should take seconds
sitting in flight for 15+ minutes is not.

Diagnose before killing: find the command's child under the `pi` PID
(sandbox-exec → pi/node → shell → child). Hot-spinning (high CPU) or blocked
(zero CPU and none of its expected side effects on disk) — hung either way.

Kill the NARROWEST thing: the stuck child process, not the `pi` run. The command
returns a failure to the builder, which adapts with its full context intact. Kill
the whole run only when the builder re-enters the same hang or the worktree is
broken; then discard the lane and re-dispatch (R7).

Long-running and interactive commands hang an unattended run (the reference build
hit real 30s/60s hangs on hand-rolled subprocess/SIGINT spike scripts). Spec
consequence: give every potentially long command an explicit timeout in the
builder block (`timeout 300 bundle exec rake test`), steer builders toward the
repo's existing test fixtures over hand-rolled long-running harnesses, and when a
gate needs a runtime that can't run unattended (interactive prompts, servers
without a timeout), have the builder record the exact failure as a
disagreement/blocker and verify what it can — gate verdicts are architect-run
anyway (R4). Write the gate file anticipating this.

## Manual alternative (human-driven)

Paste the builder block into an interactive `pi` session (no `-p`), optionally
still wrapped: `"$PI_SANDBOX" "$PWD" -- pi`. `pi`'s agent loop runs plan→act→test
against the block's stopping condition while you watch and steer.

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
outside your lane belong to other agents — touching them fails your lane. Work
in the checkout you were launched in; do not cd elsewhere (you are sandboxed to
this worktree — writes outside it will fail anyway). No placeholder
implementations — search the codebase before implementing; full implementations
only. Verify your work by running the lane's gate commands and record the
verbatim output. The checkout IS your workspace — run tests directly against it;
do NOT `git stash` (or any other git write) to get a clean tree. Do NOT commit
and do NOT run any git write command (commit/add/branch/reset/checkout/stash) —
the architect commits and merges after verification, and verifies you made no
commits. (Git writes will fail under the sandbox regardless; record the error and
continue.) Do NOT delete lock files or escalate privileges if a command fails;
record the exact error and continue. Give every potentially long command an
explicit timeout; if a runtime will not start unattended (interactive prompt,
server with no timeout), record the exact failure in your lane report and route
around it — never busy-wait or retry in a loop. When done, write your lane report
to docs/lanes/<slice>-<lane>.md with RAW results only — tables, numbers, command
output — no interpretation, no "promising". Every status claim must be backed by
a command result from this run. Keep the report compact — tables and numbers, not
prose. End it with exactly one status line:
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

- `install.sh` installs the `pi-sandbox` helper alongside the skill. On Linux,
  also install [`landrun`](https://github.com/Zouuup/landrun) (kernel 5.13+);
  without it, dispatch falls back to the combined lane.
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
