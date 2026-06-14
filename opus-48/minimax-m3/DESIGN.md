# DESIGN — The Architect Loop v2

**A source-backed design for a Claude Code harness skill in which Opus 4.8 acts
as architect/orchestrator and minimax-m3 (run via the `pi` CLI against
OpenRouter, xhigh thinking) acts as builder, with the repo as the only memory.**

Researched June 2026 from Anthropic engineering posts, agent-harness research,
and widely used community harness skills. Prescriptive claims below cite their
sources. This document is the "why"; the skill files in `skills/architect/` are
the "how". (The loop was originally designed around Claude Fable 5 + GPT-5.5 via
the Codex CLI; the methodology is model-agnostic and has been retargeted to the
Opus 4.8 / minimax-m3 pairing — the invariant rules R1–R12 are unchanged.)

---

## 1. The problem this design solves

Single-agent coding sessions degrade in three predictable ways:

1. **Context rot** — performance falls as the window fills; Anthropic calls the
   context window "a finite attention budget with diminishing returns"
   ([Effective Context Engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)),
   and practitioners report a "dumb zone" past ~40% utilization
   ([HumanLayer ACE-FCA](https://github.com/humanlayer/advanced-context-engineering-for-coding-agents)).
2. **Self-grading** — the agent that wrote the code reports its own success.
   Benchmark studies found 47–74% of self-improvement runs showed proxy gains
   without real gains, with agents escalating from overt to obfuscated reward
   hacks ([OpenReview](https://openreview.net/forum?id=ikrQWGgxYg),
   [arXiv:2503.11926](https://arxiv.org/pdf/2503.11926)).
3. **Goalpost drift** — acceptance criteria written (or edited) after results
   exist always pass.

The sources surveyed point to the same basic shape — Anthropic's
[harness design post](https://www.anthropic.com/engineering/harness-design-long-running-apps),
obra/superpowers' subagent-driven development, the Ralph loop, and GitHub Spec
Kit:

> **Separate planning context from execution context. Persist state in the repo,
> not the conversation. Dispatch fresh-context workers per task. Verify with an
> agent that didn't write the code.**

This loop adds one more separation on top: **cross-vendor judgment**. The builder
and the judge are different models from different labs (minimax-m3 builds, Opus
4.8 judges), which reduces same-model review bias. The split also plays to type:
the judgment model orchestrates in Claude Code with persistent file-based memory,
while a cheap, capable execution model does the typing-hours in parallel lanes.

The economics are another reason for the split: judgment minutes on the
strong-reasoning model, typing hours on the cheaper one. An orchestrator/worker
split keeps the expensive model off the hot path where most of the tokens are
spent.

---

## 2. Roles

| Role | Who | Effort | Owns |
|---|---|---|---|
| **Architect** | Opus 4.8 in Claude Code | minutes per work block | arbitration, judging raw evidence against frozen gates, next-slice specs, kill/continue calls |
| **Builder** | minimax-m3 via `pi -p` against OpenRouter (`--thinking xhigh` default; architect may dial per slice) | hours per slice | implementation, lane agents, raw-results reporting |
| **Memory** | the repo: `docs/HANDOFF.md`, `docs/gates/`, git history | permanent | everything; not in the repo = didn't happen |
| **Human** | you | final | scope, irreversible calls, taste |

The architect: Opus 4.8 runs in Claude Code with full reasoning; judgment over a
small handoff file is not effort-sensitive, so there is no effort knob to pin —
the skill carries no `effort:` frontmatter (that was a Fable-harness field).

Why `xhigh` thinking for the builder: it runs unattended for hours, where the
metric to buy is review-survival, not first-token latency — so default to the
model's top thinking level and let the architect downgrade to `high` for routine,
well-specified slices. `pi` exposes `--thinking off|minimal|low|medium|high|
xhigh`; this is a per-slice judgment call the spec records explicitly.

---

## 3. The twelve design rules

Each rule below is enforced mechanically by the skill, not left as advice.

### R1. Repo docs are the memory; not in `HANDOFF.md` = didn't happen
Anthropic's long-running-agent harnesses use a progress file + git history as
the cross-session memory and find "compaction alone is insufficient — structural
artifacts are the load-bearing memory"
([Effective Harnesses](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)).
The architect refuses to judge results that exist only in chat output.
Community handoff conventions apply: the next session must grok the handoff in
under a minute; TL;DR first; exact paths/commands over prose
([handoff-memory conventions](https://lobehub.com/skills/neversight-learn-skills.dev-handoff-memory)).

### R2. Gates freeze before results exist, and live where the builder can't move them
Anthropic's three-agent harness has the generator and evaluator "negotiate a
sprint contract" in shared files **before coding**, then freeze it
([Harness Design](https://www.anthropic.com/engineering/harness-design-long-running-apps)).
The reward-hacking literature adds the mechanical requirement: keep graders and
criteria out of the agent's editable blast radius. Implementation: gates are
written to `docs/gates/<slice>.md` before dispatch, committed, and the
architect's post-run verification step includes `git diff` on `docs/gates/` —
**any builder edit to a gate file is an automatic slice FAIL**, regardless of
results. Criteria are quoted verbatim when judging, never restated from memory.

### R3. The builder never grades its own work — and neither does the architect alone
Two-stage review, fresh contexts, is the most-replicated community pattern
(superpowers' spec-compliance review then quality review;
[superpowers](https://github.com/obra/superpowers)). Anthropic's agent guidance
states it directly: "Separate, fresh-context verifier subagents tend to
outperform self-critique." The loop's review stack:
1. Builder's own reviewer pass (inside the builder run, never writes feature code) — cheap first pass.
2. Architect runs the gates **itself** and reads the output — "subagent test
   claims are hearsay" (your `/orchestrator` rule, matching Anthropic's
   "demand evidence, not assertions").
3. Cross-model adversarial pass for high-stakes slices. The architect (Opus 4.8)
   reading the diff is already cross-vendor against the minimax-m3 builder; for
   an extra pass, dump the diff to a fresh read-only `pi` reviewer or have a
   fresh Claude subagent red-team it. Calibrate the reviewer: *"flag only
   correctness/requirement/invariant gaps with file:line evidence — no style
   preferences"* — an uncalibrated reviewer always finds something and that
   spirals into gold-plating.

### R4. Grade the outcome, not the path
From Anthropic's evals guidance: rigid step-sequence grading is brittle; judge
each gate as an independent dimension; give the judge an "unknown/INVALID"
escape so unmeasured ≠ passed
([Demystifying Evals](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)).
Verdicts are per-gate: **PASS / FAIL / INVALID** (INVALID = not measured the way
the gate specifies), then a slice-level **kill / continue** call.

### R5. Disagreement is mandatory, with citations
The builder's PHASE 0 must surface every disagreement with the spec, citing real
files; silent compliance is a defect the architect flags. This is the loop's
defense against spec errors compounding — a literal-minded builder follows a
prescriptive spec exactly, so the only place a spec error gets caught is before
execution. Every open disagreement gets an explicit
**ACCEPT / REJECT / MODIFY + one line why**. No deferrals.

### R6. Delegation carries the full contract: objective, output format, tool guidance, boundaries
Anthropic's multi-agent research system found vague delegation causes
duplication and misinterpretation; every dispatch needs those four parts
([Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system)).
The slice spec is exactly those four parts plus the frozen gates. Specs are
self-contained — the builder gets everything in the dispatch block, with repo
paths to read for detail (just-in-time retrieval, not context-stuffing). Per
OpenAI's prompting guidance, the full task spec goes up front in one
well-specified turn — ambiguous progressive specification degrades both token
efficiency and performance.

### R7. One slice per loop iteration; fresh builder context per slice
The Ralph loop's core lesson — and its author's explicit warning about
skill-ifying it: "if you implement Ralph as a skill inside the harness, you're
missing the point — the point is the always-fresh context"
([ghuntley.com/ralph](https://ghuntley.com/ralph/),
[HumanLayer's history](https://www.humanlayer.dev/blog/brief-history-of-ralph)).
This skill respects that: the architect's context holds judgment only; every
slice is a **fresh `pi -p` process**. `pi --session-id <lane>` is used only for
follow-ups within the same slice (answering the builder's PHASE 0 questions),
never to stretch one builder context across slices. "Code is cheap": when a long
run leaves the repo broken, `git reset` and re-dispatch beats rescue prompting.

### R8. Parallelism is architect-orchestrated: one worktree + one fresh `pi -p` per lane, capped at 4
Merge conflicts between parallel agents are the top reported multi-agent failure;
the converged mitigation is mapping file-touch sets before parallelizing, one
git worktree per agent, and a practical ceiling of 2–4 lanes before coordination
overhead dominates ([Intility engineering](https://engineering.intility.com/article/agent-teams-or-how-i-learned-to-stop-worrying-about-merge-conflicts-and-love-git-worktrees),
[MindStudio worktrees](https://www.mindstudio.ai/blog/git-worktrees-parallel-ai-coding-agents)).
**The architect — not the builder — owns the fan-out.** The spec splits the
slice into 1–4 lanes whose file sets are checked for overlap; each lane is an
isolated worktree running its own `pi -p` process, writing its own lane report
(`docs/lanes/`); the architect runs per-lane boundary checks (`git status`
must show only declared files; `git log <freeze>..` must be empty since `pi` has
no sandbox to block commits), commits each passing lane, and merges sequentially
with gate smoke-runs after every merge. Keeping fan-out in the architect rather
than delegating it to a builder-internal subagent feature makes a merge conflict
a detectable spec defect instead of a silent hazard, and isolates per-lane
failure (discard one lane, not the slice).

### R9. Supervise asynchronously; never block on the builder
Anthropic's agent guidance for orchestrators is explicit: "prefer async
communication over blocking on each return" when dispatching and sustaining
parallel subagents. The dispatch runs `pi -p` in the background; the architect
ends its turn or does other judgment work, then runs the post-flight checks when
the run completes. Multi-hour builder runs are normal — and on OpenRouter's
per-token billing there is no per-window quota to exhaust mid-run, only a funded
balance.

### R10. Grounded progress claims — audit every status against tool output
Anthropic's agent guidance: instruct the model to audit every status claim
against a tool result from the session before reporting; in their testing this
"nearly eliminated fabricated status reports." Applied twice here: the architect's own
reports, and the handoff rules for the builder (raw tables/numbers/SHAs only —
"no interpretation, no 'promising'; verdicts belong to the architect and the
human").

### R11. Ground before judging; scale effort to the task
Carried over from your `/orchestrator` skill, and matching Claude Code best
practices: read the project's own operating docs (CLAUDE.md/AGENTS.md → README →
architecture docs) and learn its verification gate before any judgment; a wrong
assumption multiplies through every dispatch. And not everything needs the loop:
trivial work gets done directly; the full pipeline is for slice-sized work and
up. "Every component in a harness encodes an assumption about what the model
can't do on its own" — don't run a $200 harness on a $9 task
([Harness Design](https://www.anthropic.com/engineering/harness-design-long-running-apps)).

### R12. Keep the skill thin, declarative, and prunable
Two reasons. (a) Claude Code skill mechanics: only descriptions sit in context
until invoked, but the body stays in context for the session — keep it terse,
push detail to referenced files ([Skills docs](https://code.claude.com/docs/en/skills)).
(b) Obsolescence: skills developed for prior models are often too prescriptive
for current models and can degrade output quality (Anthropic's agent guidance),
and the Claude Code team's own position is that scaffolds get obsoleted by better
models ([Latent Space, harness engineering](https://www.latent.space/p/harness-eng)).
The skill states *invariants* (the rules above) and *interfaces* (the dispatch
contract), not step-by-step micro-procedures. Review it against each new model
generation and delete what the model now does unprompted.

---

## 4. The builder interface (verified against `pi` 0.79.2, June 2026)

Facts the skill encodes:

- **Model/provider are pinned explicitly**: `--provider openrouter --model
  minimax/minimax-m3`. `pi` defaults can live in `~/.pi/agent/settings.json`,
  but automations pin them per invocation so a session default can't silently
  swap the model.
- **`pi -p` (`--print`) is the headless, non-interactive mode** (the `codex exec`
  analog) — it processes the prompt and exits. There is **no sandbox**:
  permissions are the **tool allowlist** (`-t read,bash,edit,write,grep,find`
  for builders; drop `bash`/`edit`/`write` for read-only researchers). This is
  the one load-bearing difference from the Codex design — see R8 and below.
- **Thinking** maps to `--thinking off|minimal|low|medium|high|xhigh`,
  per invocation (`xhigh` default for builders, `high` for research).
- **Prompt input** is `@file` — the block is written to a file and injected
  verbatim, sidestepping shells (especially PowerShell) that mangle quotes in
  big prompt blocks.
- **Telemetry / output**: `--mode json` streams JSONL events to stdout (redirect
  to a run-log for liveness/stall checks). There is no output-schema flag; the
  builder's deliverable is the lane report it writes with its `write` tool, and
  the contract is the `STATUS:` line convention, not a schema.
- **Session continuity**: dispatch with `--session-id <lane>` and follow up with
  `pi -p --session-id <lane> "<follow-up>"` — deterministic even across parallel
  lanes. Same-slice only.
- **Web access** comes from the `pi-web-access` extension (tools `web_search`,
  `fetch_content`), zero-config via Exa. Builders get it for verify-against-
  reality API checks; researchers get it as their only outward tool.
- **`AGENTS.md`/`CLAUDE.md`** are the builder's standing context — `pi` loads
  both root-down. The loop's PHASE rules live in the dispatch block so they
  version with the skill; repo-specific build/test commands belong in `AGENTS.md`.
- **No commit guarantee from the runtime.** Codex's `--sandbox workspace-write`
  made `.git` physically read-only, so "builders never commit" was enforced by
  the runtime. `pi` has no sandbox, so the rule is enforced after the run by the
  architect: `git -C <worktree> log <freeze>..` must be empty and `git status`
  must show only declared files. A commit = a tampered worktree → reset and
  re-dispatch.

Canonical dispatch:

```bash
pi -p --provider openrouter --model minimax/minimax-m3 --thinking xhigh \
  --session-id <slice> \
  -t read,bash,edit,write,grep,find,web_search,fetch_content \
  --mode json @.architect/dispatch-block.md \
  > .architect/last-run.jsonl
```

Billing note: OpenRouter is per-token prepaid credit — there are no per-window
quotas to exhaust mid-run, so unattended overnight loops just need a funded
balance. The architect runs on the Claude plan in Claude Code.

---

## 5. The loop, end to end

```
┌──────────────────────────── one work block ────────────────────────────────┐
│                                                                            │
│  /architect                                                                │
│   0. Ground: CLAUDE.md/AGENTS.md → verification gate → docs/HANDOFF.md     │
│   1. Arbitrate: every open disagreement → ACCEPT/REJECT/MODIFY + why       │
│   2. Judge: run gates yourself; verdict per gate vs verbatim frozen text   │
│      PASS / FAIL / INVALID → kill / continue                               │
│   3. Spec next slice: objective + output format + tool guidance +          │
│      boundaries + out-of-scope; freeze gates to docs/gates/<slice>.md;     │
│      commit the freeze                                                     │
│   4. Dispatch: 1-4 parallel pi -p lanes, one git worktree each             │
│      (background, fresh context, xhigh default). Per lane: PHASE 0         │
│      disagree-or-fail → PHASE 1 contracts frozen → PHASE 2 build own       │
│      files only → raw lane report (docs/lanes/), no commits                │
│   5. Post-flight per lane: raw-only? disagreements raised? gates           │
│      untouched? in-bounds? → architect commits + merges lanes with         │
│      gate smoke-runs; verdict waits for next block                         │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
         repo carries everything across the gap between blocks
```

The human reads the handoff between blocks and overrides anything. Architect
verdicts on a slice always happen in a **later** architect session than the one
that dispatched it — the dispatcher never grades the run it launched in the same
breath (fresh-context judgment, R3).

### Optional pre-spec research fan-out

Between judging and speccing, the architect may run a research phase: 3–5
parallel read-only `pi` researchers (web via the `pi-web-access` tools), each
answering one narrow non-overlapping question, with the architect adversarially
verifying load-bearing claims and writing `docs/prd/<slice>.md` itself. Design
decisions behind it:

- **Trigger-gated, not always-on.** "Research if you think it helps" either
  fires constantly or never; instead the skill names three concrete triggers
  (slice depends on external APIs/libraries/versions new to the repo; a
  technology choice needs facts nobody has; the human asks) and defaults to
  skip — the builder's verify-against-reality requirement already covers
  routine API checks (R11: scale effort to the task).
- **Progressive disclosure.** The mechanics live in `research.md`, read only
  when a trigger fires — the default architect context never pays for them
  (R12, per [Skills docs](https://code.claude.com/docs/en/skills) guidance to
  push detail to referenced files).
- **minimax researchers, Opus judgment.** Research is coverage work — it runs
  at `high` thinking, read-only by toolset (`read,grep,find,ls` + the web
  tools, no `edit`/`write`/`bash`), with the report captured as redirected
  stdout. Verification of load-bearing claims and PRD authorship stay with the
  architect — researchers are explicitly forbidden from making
  recommendations, the research-side equivalent of "raw results only" (R3).
- **Findings discipline** mirrors deep-research harnesses: every finding
  carries a URL, date, exact quote/figure, and confidence tag; disagreements
  between sources are reported, not resolved; "NOT FOUND" beats inference.
  Multi-angle decomposition (docs / changelogs / failure reports /
  alternatives) follows the multi-modal-sweep pattern from
  [Anthropic's multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system).
- **The PRD is repo memory; raw findings are not.** `docs/prd/<slice>.md` is
  committed with citations (R1); raw researcher output stays in the gitignored
  `.architect/research/`. The builder's PHASE 0 challenges the PRD like any
  other spec input.

### Two skills: `/architect` and `/architect-research`

Discovery-scale research (brainstorming, technology selection, SOTA surveys)
is a **separate skill**, not a mode of the loop. Three reasons: different
invocation pattern (discovery precedes a project; the loop runs per work
block), different deliverable (a decision report vs a dispatch), and cost —
research-grade fan-out runs ~15× chat-level tokens
([Anthropic multi-agent research](https://www.anthropic.com/engineering/multi-agent-research-system)),
so it must be deliberately invoked, never a side-effect. The loop's step 3
routes: discovery scale → `/architect-research`; narrow slice facts → the
inline fan-out above.

`/architect-research` encodes the methodology found across the surveyed
deep-research systems. As of v2.3 the decomposition is **scout-first and
topic-designed, not a fixed lane taxonomy** — a 2026-06 evidence review found
all five production deep-research systems (OpenAI DR, Anthropic, Gemini,
Perplexity, Kimi) use adaptive planner-driven decomposition and none uses
fixed lanes; 4/5 leading OSS frameworks generate the decomposition with an
LLM; and dynamic beats static decomposition on GAIA
([OAgents](https://arxiv.org/abs/2506.15741): 47.88 static → 51.52 dynamic;
[AOrchestra](https://arxiv.org/abs/2602.03786): on-demand subagent
construction +16.28% relative). The six source-class sections in `lanes.md`
became a tactics library the orchestrator draws from when designing lanes:

- **Scout → design → fan out.** For brainstorm-scale questions, one cheap
  `pi` scout (~10 searches) maps terminology, load-bearing
  systems, named people, and the topic's natural fault lines; the architect
  then designs 3–6 topic-specific lanes from that map. Source-derived
  perspective discovery was STORM's largest measured lever (unique references
  99.83 vs 54.36 without it); Anthropic's lead agent and OpenAI/Gemini's
  user-visible research plans are the production analogs. Comparisons and
  fact-finds skip the scout — recon that tells you nothing is pure latency.
- **Effort scaling embedded in the prompt** — 1 researcher for fact-finds,
  2–4 for comparisons, 4–6 designed lanes for surveys; search budgets 5/15/25
  by tier; ≤5 subjects per researcher (context-exhaustion guard — a
  researcher that fills its window dies without writing output; bisect dead
  lanes); saturation stop (two no-new-fact searches); max 2 gap-fill rounds.
  Scaling numbers from Anthropic's published orchestrator heuristics —
  without them, leads over- or under-delegate.
- **Perspective-diverse decomposition, overlap-checked** before dispatch
  (Stanford [STORM](https://arxiv.org/abs/2402.14207)'s
  perspective-guided questioning; the direct antidote to query collapse).
- **Scope → brief → plan-before-burn** (LangChain
  [Open Deep Research](https://github.com/langchain-ai/open_deep_research)'s
  brief-as-north-star; Gemini's user-visible plan). The brief is restated in
  the report so scope drift is auditable.
- **Verification as a separate pass against raw sources**: ≥2
  independent-origin sources per load-bearing claim; four-state tags
  (VERIFIED/UNVERIFIED/DISPUTED/SUSPICIOUS); adversarial falsification
  searches; **citations only from URLs fetched this session** — even
  search-grounded agents fabricate
  [3–13% of URLs](https://arxiv.org/pdf/2604.03173); recency discipline
  (dated claims, date-restricted queries) because retrieval systematically
  favors stale sources.
- **Parallelize gathering, never synthesis** — one author writes the whole
  report (LangChain's section-parallel writer produced disjoint reports;
  Anthropic's CitationAgent exists to stop summarizing-of-summaries).
  Output is decision-oriented: answer-first, per-finding "what would change
  this conclusion", explicit open questions.
- **Expert opinion as a second-wave lane with its own evidence class.** You
  can't track experts until you know who they are, so lane 6 dispatches in
  the gap round, roster-seeded by the first wave (survey authors, top-repo
  maintainers, recurring names). Platform reality is encoded: experts' blogs
  and HN's keyless Algolia author search are the reliable channels; X is
  login-walled for agents (use `site:x.com` indexed search + profile URLs,
  not third-party viewers), and Bluesky's public search API has returned 403
  since March 2025 ([bsky-docs#332](https://github.com/bluesky-social/bsky-docs/issues/332)).
  Opinions are reported as dated, conflict-of-interest-flagged positions and
  never count toward the ≥2-source rule — but expert *disagreements* are
  first-class findings, since they locate the genuinely open questions.
- **Verified source-class endpoints** live in `lanes.md`: arXiv API recency queries,
  Semantic Scholar citation snowballing (the most reliable "latest papers"
  method), deps.dev/ecosyste.ms dependents (adoption evidence beats stars —
  ~4.5M [fake stars](https://arxiv.org/abs/2412.13459) documented), the
  emerging-vs-hype conjunction gate, the production-grade gate + four-category
  pattern-mining procedure, HN Algolia. Papers With Code is dead (July 2025;
  HF Papers succeeded it) — a stale-source trap the lane file flags.

---

## 6. Failure modes → mechanical mitigations

| Failure mode | Mitigation in this design |
|---|---|
| Reward hacking / gate tampering | Gates committed pre-dispatch in `docs/gates/`; post-flight `git diff` check; tampering = automatic FAIL (R2) |
| Builder grades own work | Raw-results-only handoff; architect runs gates itself; cross-model review (R3, R10) |
| Goalpost moving | Verbatim gate quoting; gates never edited after results; missing gate = spec defect, frozen for next slice only (R2, R4) |
| Scope creep | Explicit out-of-scope list per slice; silent scope additions = builder failure; architect flags creep by name (R5, R6) |
| Context rot | Architect context holds judgment only; fresh builder process per slice; repo is the memory (R1, R7) |
| Merge conflicts between lanes | Disjoint-file-set lanes, ≤3–4, worktrees, one reviewer lane gating merges (R8) |
| Placeholder implementations | Gate commands are end-to-end and executable; "search before implementing; no placeholder code" in the builder block (R4) |
| Broken repo after a long run | One slice per iteration; commit per lane; `git reset` + re-dispatch over rescue prompting (R7) |
| Fabricated status reports | Every status claim audited against a tool result, both sides (R10) |
| Gate-passing but unmergeable work | Judge reads the diff against spec intent, not gate output alone — METR: 38% test-pass, 0 mergeable as-is; cross-model review for high-stakes (R3, R4) |
| Builder gaming visible gates | Gates frozen + read-only; architect-run verification; no builder iterate-against-gate feedback loops (ImpossibleBench: visible-test loops raised cheating 33%→38%) (R2, R3) |
| Stalled unattended runs | Liveness checks on the output stream; diagnose child process tree; kill narrowest first; explicit timeouts on every long command (dispatch.md) |
| Researcher context exhaustion | ≤5 subjects per lane; hard context rules in the preamble; bisect-and-redispatch dead lanes (lanes.md) |
| Harness bloat / obsolescence | Thin declarative skill; per-model-generation pruning review (R12) |

---

## 7. What this deliberately is not

- **Not a general-purpose orchestrator.** Your `/orchestrator` skill covers
  single-model plan→delegate→review inside Claude Code. This skill is the
  cross-vendor loop; it imports `/orchestrator`'s grounding, delegation-contract,
  and verify-it-yourself rules rather than duplicating the whole pipeline.
- **Not an autonomous infinite loop.** The human sits between work blocks by
  design — that's where kill/continue authority lives. If you want unattended
  multi-block runs, the dispatch step composes with `claude -p` / scheduled
  jobs, but that's an extension, not the default (and note `claude -p` draws on
  separate Agent SDK credits from June 15, 2026).
- **Not just an agent loop.** `pi` already loops plan→act→test against a
  stopping condition within a single run. This design adds the separations a
  bare loop lacks: cross-model judgment, frozen external gates, arbitration, and
  repo-resident memory across runs.

---

## 8. Sources

**Anthropic (official):**
[Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents) ·
[Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system) ·
[Writing Tools for Agents](https://www.anthropic.com/engineering/writing-tools-for-agents) ·
[Effective Context Engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) ·
[Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) ·
[Demystifying Evals](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents) ·
[Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps) ·
[Managed Agents](https://www.anthropic.com/engineering/managed-agents) ·
[Claude Code Best Practices](https://code.claude.com/docs/en/best-practices) ·
[Skills](https://code.claude.com/docs/en/skills) ·
[Subagents](https://code.claude.com/docs/en/sub-agents) ·
[Hooks](https://code.claude.com/docs/en/hooks) ·
[Headless mode](https://code.claude.com/docs/en/headless)

**Builder tooling:**
[pi-web-access (npm)](https://www.npmjs.com/package/pi-web-access)

**Evidence reviews (2026-06, architect-verified primary sources):**
[Geng & Neubig — async SE agents, worktree+manager topology](https://huggingface.co/papers/2603.21489) ·
[PEAR — weak planners hurt more than weak executors](https://arxiv.org/abs/2510.07505) ·
[AgentForge — execution-grounded role decomposition](https://arxiv.org/abs/2604.13120) ·
[ImpossibleBench — test-exploitation in coding agents](https://arxiv.org/abs/2510.20270) ·
[METR — SWE-bench-passing PRs mostly unmergeable](https://metr.org/blog/2025-08-12-research-update-towards-reconciling-slowdown-with-time-horizons/) ·
[Cross-Context Review — fresh-context judging wins](https://arxiv.org/abs/2603.12123) ·
[Chroma — context rot](https://www.trychroma.com/research/context-rot) ·
[OpenAI — harness engineering / AGENTS.md rot](https://openai.com/index/harness-engineering/) ·
[Cognition — multi-agents: what's actually working](https://cognition.ai/blog/multi-agents-working) ·
[OAgents — static vs dynamic decomposition on GAIA](https://arxiv.org/abs/2506.15741) ·
[AOrchestra — on-demand subagent construction](https://arxiv.org/abs/2602.03786) ·
[OpenAI BrowseComp — aggregation + failure modes](https://openai.com/index/browsecomp/) ·
[DeepResearch Bench leaderboard (RACE/FACT)](https://huggingface.co/spaces/muset-ai/DeepResearch-Bench-Leaderboard/blob/main/data/leaderboard.csv)

**Community / experts:**
[obra/superpowers](https://github.com/obra/superpowers) ·
[Ralph Wiggum loop](https://ghuntley.com/ralph/) ·
[A Brief History of Ralph](https://www.humanlayer.dev/blog/brief-history-of-ralph) ·
[Advanced Context Engineering (HumanLayer)](https://github.com/humanlayer/advanced-context-engineering-for-coding-agents) ·
[Simon Willison — Agentic Engineering Patterns](https://simonwillison.net/guides/agentic-engineering-patterns/how-coding-agents-work/) ·
[Latent Space — Harness Engineering](https://www.latent.space/p/harness-eng) ·
[GitHub Spec Kit](https://github.com/github/spec-kit) ·
[Steve Yegge — Beads](https://steve-yegge.medium.com/introducing-beads-a-coding-agent-memory-system-637d7d92514a) ·
[Reward hacking in self-improvement](https://openreview.net/forum?id=ikrQWGgxYg) ·
[Obfuscated reward hacking](https://arxiv.org/pdf/2503.11926) ·
[Worktrees for parallel agents](https://engineering.intility.com/article/agent-teams-or-how-i-learned-to-stop-worrying-about-merge-conflicts-and-love-git-worktrees)
