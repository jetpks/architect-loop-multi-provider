---
name: architect-research
description: >
  Discovery-scale research harness: a cheap scout researcher maps the topic,
  the orchestrator designs topic-specific parallel researcher lanes from the
  scout report (drawing on a source-class tactics library — academic, repos,
  production patterns, web, experts), then verifies claims against sources and
  synthesizes a decision-oriented report. Use when
  brainstorming a project or feature, choosing a technology, or asked to
  "research X", "what's the state of the art", "deep research". For narrow
  slice-level fact checks inside the build loop, /architect handles those inline.
---

# Architect Research

You are the research orchestrator. Researchers gather; **you** design the
decomposition, verify, and write — judgment never delegates. The source-class
tactics library (search mechanics + verified endpoints per source class) is in
`lanes.md` next to this file; read it when you design lanes.

## Scale before anything

- **Simple fact-find** → answer directly or 1 researcher (3–10 searches).
  Don't run a harness on a question one search answers.
- **Comparison / focused question** → 2–4 researchers on distinct
  perspectives, no scout — you already know the terrain.
- **Brainstorm / SOTA survey / technology choice** → scout first, then a
  designed fan-out of 4–6 researchers.

## Procedure

### 1. Scope → brief

If the question is ambiguous, ask at most 2–3 clarifying questions, then
compress everything into a **research brief**: the question, the decision it
informs, constraints, and what "answered" looks like. The brief is the north
star — every later step is checked against it, and it's restated at the top of
the final report so the reader can audit scope drift.

### 2. Scout, then design the lanes

The surveyed production deep-research systems and 4/5 leading OSS frameworks
use LLM-designed, topic-specific decomposition rather than a fixed lane
taxonomy. Lanes are designed per topic, not taken from a template.

**Scout (brainstorm scale only):** dispatch ONE cheap researcher (~10
searches, same `claude -p` command as step 3) to map the terrain: canonical
terminology, the 5–10 load-bearing systems/papers/repos, the named people,
which source classes look rich vs empty, and the topic's natural fault lines.
The scout returns a map, not findings — discovering the topic's actual
perspectives from sources substantially increased source diversity in STORM's
ablations. Skip the scout when you already know the terrain (comparisons,
fact-finds) — an upfront pass that tells you nothing new is pure latency.

**Design (you, from the scout report):** decompose into 3–6 sub-questions
along the topic's own fault lines — distinct perspectives, never keyword
variants of one query. For each lane pick the source-class tactics it needs
from `lanes.md` (academic snowballing, dependents-not-stars repo evidence,
production-grade pattern mining, general web, expert tracking) — one lane may
mix tactics; most topics don't need every source class. Scope each lane to
≤5 subjects and give every lane an explicit search budget. Reserve **expert
opinion** as a second-wave lane: its roster (survey authors, maintainers,
recurring names) comes from the first wave's findings.

Review the lane set for overlap AND for gaps against the brief before
dispatch. State the plan in a few lines; proceed unless the user redirects.

### 3. Fan out

One fresh researcher per lane, each launched as its own **background Bash tool
call** (`run_in_background`) — one call per lane, not a shell `&` loop (a `&`
launcher orphans the lanes and the harness reaps them all at once). Read-only by
toolset (`Read,Grep,Glob`) plus the web tools (`WebSearch,WebFetch`); the
report is the redirected stdout:

```bash
claude -p --model claude-sonnet-4-6 \
  --allowedTools 'Read,Grep,Glob,WebSearch,WebFetch' \
  --max-turns 40 \
  < .architect/research/<NN>-<lane>.prompt.md \
  > .architect/research/<NN>-<lane>.md
```

Write each lane block to a `.prompt.md` file and feed it on stdin — never as a
shell argument; a quote-mangling shell will corrupt a big block, the stdin
redirect injects it verbatim.

(Web comes from the built-in `WebSearch` and `WebFetch` tools — no extension or
key. With only the read-only + web tools on the allow list, every write/bash
call is denied, so the researcher can't touch the repo. Launch ONE canary lane
and confirm it actually fetches live URLs before fanning out. These lane blocks
also run verbatim as read-only Claude subagents with web search if you'd rather
keep research inside the architect's own session.)

Every lane block carries the full contract — objective, output format, source
guidance, boundaries — plus:

- **Search budget** by tier: simple 5, standard 15, deep 25 searches.
- **Saturation rule**: two consecutive searches yielding no new load-bearing
  facts → return what you have.
- **Findings discipline**: every finding has URL + date + exact figure or
  short quote + confidence tag (high = primary source / med = reputable
  secondary / low = single blog or forum). NOT FOUND beats inference.
  Disagreements between sources are reported, never resolved. No
  recommendations — judgment is the orchestrator's.

### 4. Gap round (max 2 extra rounds, usually 1)

Read all findings. Score coverage against the brief: which sub-questions have
supported answers? Spawn targeted gap-fill researchers **only** for the
unanswered ones. This is also where the **expert-opinion lane** dispatches:
extract the expert roster from the first wave (survey authors, maintainers,
recurring names) and send the lane-6 researcher after them. Hard stop after
two refinement rounds — past that you're chasing nonexistent information.

### 5. Verify (your work, against raw sources)

- Extract the **load-bearing claims** — the facts the decision depends on.
- Require **≥2 independent sources** per load-bearing claim. Independent means
  independent *origin* — two articles rewriting the same press release are one
  source.
- Tag each: **VERIFIED** (≥2 independent agree) / **UNVERIFIED** (<2, no
  contradiction) / **DISPUTED** (sources disagree — report both positions and
  *why* they differ: date, method, definition) / **SUSPICIOUS** (contradicts
  available evidence).
- **Adversarial pass** on the top claims: search "<claim> criticism",
  "<X> problems", "<X> vs <alternative>" — actively try to falsify.
- **Citations are only URLs fetched this session.** Never cite from memory —
  even search-grounded agents fabricate 3–13% of URLs. Spot-check the
  load-bearing ones by fetching them yourself.
- **Recency discipline**: every quantitative or current-state claim carries a
  source date; prefer the most recent authoritative treatment; date-restrict
  searches on fast-moving topics. Anything that smells like training-data
  leakage gets re-verified or cut.
- **Source hierarchy**: primary (papers, official docs, changelogs, first-party
  engineering blogs) > reputable secondary > SEO listicles (pointers only,
  never citations).
- **Opinion ≠ fact.** Expert opinions are reported as positions — quoted,
  dated, conflict-of-interest flagged — and never count toward the ≥2-source
  rule for factual claims. Expert *disagreements* are first-class findings:
  they mark the genuinely open questions.

### 6. Synthesize (one pass, one author — you)

Parallelize gathering, never synthesis. Write `docs/research/<topic>.md`:

- **Answer first** (BLUF), then evidence, then method.
- The brief, restated.
- Per major finding: the claim + confidence tag + **what it implies for the
  decision** + **what evidence would change this conclusion**.
- Disputes surfaced with both positions — never silently averaged.
- **Expert positions map**: who believes what (quoted, dated,
  conflict-of-interest flagged), and where credible experts disagree.
- **Open questions**: each UNVERIFIED/DISPUTED item with the specific search
  or experiment that would resolve it (this doubles as the next round's input).
- Citations dated and tier-labeled: `[primary, 2026-04]`.

Commit the report. Raw findings stay in `.architect/research/` (gitignored).

### 7. Hand off

If this feeds the build loop: distill the report into `docs/prd/<slice>.md`
per `/architect` and continue there. The builder's PHASE 0 will challenge the
PRD's claims — that's a feature.
