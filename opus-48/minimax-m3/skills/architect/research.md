# Research fan-out reference

Read this only when a research trigger fires (see SKILL.md step 3). The fan-out
uses `pi`/minimax-m3 as parallel web-research subagents — read-only (no
edit/write/bash), web via the `pi-web-access` tools — and the architect keeps
all judgment: it verifies the load-bearing claims and writes the PRD itself.

## Fan out

Decompose the question into 3–5 narrow, NON-OVERLAPPING research questions.
Cover different angles, not the same angle five times — typical split:
official docs/reference, changelog/breaking changes, community failure reports,
alternatives/comparisons, security/operational constraints.

One fresh `pi -p` per question, launched in the background. The researcher
toolset is read-only (`read,grep,find,ls`) plus the web tools
(`web_search,fetch_content`) — no `edit`/`write`/`bash`, so it cannot touch the
repo (and there is no worktree-cwd problem to worry about, unlike build lanes).
**Stagger the launches** — minimax-m3 over OpenRouter silently drops concurrent
requests: firing 5 at once left only 1 with output and the rest exited 0 bytes
with empty stderr. Sleep a few seconds between launches, and re-dispatch any lane
whose output file lands at 0 bytes. Capture the final report by redirecting
stdout (the `-o` analog):

```bash
pi -p --provider openrouter --model minimax/minimax-m3 --thinking high \
  -t read,grep,find,ls,web_search,fetch_content \
  @.architect/research/<NN>-<topic>.prompt.md \
  > .architect/research/<NN>-<topic>.md
```

Write each research block to a `.prompt.md` file and pass it with `@file`, never
as a shell argument — `@file` injects the contents verbatim and sidesteps
quote-mangling shells.

- Read-only by toolset: with no `edit`/`write`/`bash`, researchers can't write
  to the repo; their report is the redirected stdout.
- Web comes from `pi-web-access` (`web_search` synthesizes with citations,
  `fetch_content` pulls a page/PDF/repo). It's zero-config via Exa (no key
  needed). Launch ONE canary researcher and confirm it actually fetches live
  URLs before fanning out.
- `--thinking high`, not `xhigh` — research is coverage work; xhigh buys nothing
  here. Synthesis happens on the architect's side.
- Scope each researcher to ≤5 subjects and put hard context rules in the
  block (snippet over page; quote ≤2 sentences; stop the moment you can
  answer) — a researcher that fills its context window dies without writing
  its output. Bisect and re-dispatch dead lanes; don't re-run as-is.

## Research block template

```
You are a web research agent. Answer ONE question. Do not write code, do not
make recommendations — judgment belongs to the architect who reads your output.

QUESTION: <one narrow question>

OUTPUT FORMAT — a markdown report:
- Findings as bullets. EVERY finding carries: source URL, source date (if
  shown), the exact figure or a short direct quote, and a confidence tag
  (high = primary source / med = reputable secondary / low = single blog or
  forum post).
- Prefer primary sources (official docs, changelogs, release notes, source
  code) over blog posts. Record exact version numbers and dates.
- When sources disagree, report the disagreement — do not resolve it.
- If you cannot find evidence for something, write NOT FOUND — never infer or
  fill gaps from prior knowledge without flagging it as such.
- End with: the 2-3 findings most likely to change an implementation decision.
```

## Gather (architect — this is your work, not another agent's)

1. Read every findings file in `.architect/research/`.
2. Identify the **load-bearing claims** — facts the spec will depend on
   (an API shape, a version constraint, a limit, a deprecation). Adversarially
   verify each: cross-check against a second independent source or the live
   dependency itself. Discard single-source low-confidence claims or mark them
   as open questions.
3. Write `docs/prd/<slice>.md`: problem, decision + why, requirements,
   non-goals, verified facts **with citations**, open questions for the human.
   You write it — researchers gather, the architect judges and decides.
4. Commit the PRD. Raw findings stay in `.architect/research/` (gitignored) —
   only the distilled, cited PRD is repo memory.
5. The slice spec references the PRD instead of restating it; the builder's
   PHASE 0 is expected to challenge the PRD's claims like anything else.
