# Research fan-out reference

Read this only when a research trigger fires (see SKILL.md step 3). The fan-out
uses `claude -p` (Sonnet 4.6) as parallel web-research subagents — read-only
(no `Edit`/`Write`/`Bash`), built-in `WebSearch`/`WebFetch` — and the architect
keeps all judgment: it verifies the load-bearing claims and writes the PRD
itself.

## Fan out

Decompose the question into 3–5 narrow, NON-OVERLAPPING research questions.
Cover different angles, not the same angle five times — typical split:
official docs/reference, changelog/breaking changes, community failure reports,
alternatives/comparisons, security/operational constraints.

One fresh `claude -p` per question, each launched as its own **background Bash
tool call** (`run_in_background`) — one call per researcher, not a shell `&`
loop (a `&` launcher orphans the researchers and the harness reaps them all at
once; same trap as builder dispatch). The researcher toolset is read-only
(`Read,Grep,Glob`) plus the
web tools (`WebSearch,WebFetch`) — no `Edit`/`Write`/`Bash`, so it cannot touch
the repo. Capture the final report by redirecting stdout (the report *is* the
text result in the default `text` output format):

```bash
claude -p --model claude-sonnet-4-6 \
  --allowedTools 'Read,Grep,Glob,WebSearch,WebFetch' \
  --max-turns 40 \
  < .architect/research/<NN>-<topic>.prompt.md \
  > .architect/research/<NN>-<topic>.md
```

Write each research block to a `.prompt.md` file and feed it on stdin, never as
a shell argument — a quote-mangling shell will corrupt a big block; the stdin
redirect injects it verbatim.

- Read-only by toolset: with only `Read,Grep,Glob,WebSearch,WebFetch` on the
  allow list and nothing else granted, any write/bash call is denied — the
  researcher can't touch the repo. Its report is the redirected stdout.
- Web comes from the built-in `WebSearch` and `WebFetch` tools — no extension or
  key. Launch ONE canary researcher and confirm it actually fetches live URLs
  before fanning out. Restrict domains with `WebFetch(domain:…)` allow rules in
  prompt-injection-sensitive repos.
- Thinking budget: keep research at a modest level (a plain block, or "think
  hard") — research is coverage work; deep thinking buys nothing here. Synthesis
  happens on the architect's side.
- Scope each researcher to ≤5 subjects and put hard context rules in the
  block (snippet over page; quote ≤2 sentences; stop the moment you can
  answer) — a researcher that fills its context window dies without emitting
  its report. Bisect and re-dispatch dead lanes; don't re-run as-is.

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
