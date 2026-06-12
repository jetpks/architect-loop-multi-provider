---
name: architect-research
description: >
  Discovery-scale research harness: fan out parallel researchers across six
  lanes — latest academic papers, most popular repos, cutting-edge repos, design
  patterns from production-grade libraries, general web, and expert opinion
  (blogs/X/talks of named experts) — then verify claims against sources and
  synthesize a decision-oriented report. Use when
  brainstorming a project or feature, choosing a technology, or asked to
  "research X", "what's the state of the art", "deep research". For narrow
  slice-level fact checks inside the build loop, /architect handles those inline.
effort: high
---

# Architect Research

You are the research orchestrator. Researchers gather; **you** decompose,
verify, and write — judgment never delegates. Per-lane researcher blocks and
verified endpoints are in `lanes.md` next to this file; read it when you fan
out.

## Scale before anything

- **Simple fact-find** → answer directly or 1 researcher (3–10 searches).
  Don't run a harness on a question one search answers.
- **Comparison / focused question** → 2–4 researchers on distinct perspectives.
- **Brainstorm / SOTA survey / technology choice** → the full five-lane fan-out.

## Procedure

### 1. Scope → brief

If the question is ambiguous, ask at most 2–3 clarifying questions, then
compress everything into a **research brief**: the question, the decision it
informs, constraints, and what "answered" looks like. The brief is the north
star — every later step is checked against it, and it's restated at the top of
the final report so the reader can audit scope drift.

### 2. Plan (perspective-diverse, overlap-checked)

Decompose into 3–5 sub-questions from **distinct perspectives** — different
angles on the topic, never keyword variants of one query. For brainstorm scale,
default to the five lanes:

1. **Academic** — latest papers, surveys, citation snowballing
2. **Popular repos** — what the ecosystem actually uses
3. **Cutting-edge repos** — what's emerging right now (and isn't hype)
4. **Production patterns** — how the best libraries in the niche design it
5. **General web** — postmortems, comparisons, official docs, everything else
6. **Expert opinion** *(second wave)* — what the named experts in the field
   say on their blogs, talks, and X/social. Dispatches in step 4, not here:
   its roster (survey authors, top-repo maintainers, recurring names) comes
   from the first wave's findings.

Review the query set for overlap before dispatch — overlapping researchers
duplicate work and leave gaps. State the plan in a few lines; proceed unless
the user redirects.

### 3. Fan out

One fresh researcher per lane, all parallel, in the background:

```bash
codex exec --sandbox read-only -c web_search="live" \
  -m gpt-5.5 -c model_reasoning_effort="high" \
  -o .architect/research/<NN>-<lane>.md \
  - < .architect/research/<NN>-<lane>.prompt.md
```

Write each lane block to a `.prompt.md` file and pass it via stdin (`-`) —
never as a shell argument; quote-mangling shells make codex hang on stdin.

(Web search is on by default in current Codex; `"live"` forces fresh results.
Older CLIs: `--enable web_search` (0.13x) or `-c tools.web_search=true`
(< 0.133); `--search` is TUI-only — exec rejects it. Launch ONE canary lane
and confirm it starts cleanly before fanning out. If Codex is unavailable,
run lanes as read-only Claude subagents with web search — the lane blocks
work verbatim.)

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
