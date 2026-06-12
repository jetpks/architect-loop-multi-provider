# architect-loop

**Claude Fable is your architect. GPT-5.5 Codex is your builder. The repo is the
only memory.** Two Claude Code skills that run the cross-vendor agent loop on
flat-rate subscriptions — no API keys, no token bills.

> Fable thinks, Codex builds, the repo remembers, you judge.

---

## Install (30 seconds)

```bash
git clone https://github.com/DanMcInerney/architect-loop
cd architect-loop && ./install.sh        # Windows: .\install.ps1
npm i -g @openai/codex@latest            # the builder (Codex CLI >= 0.133)
```

That's it. `./install.sh --project` installs to the current repo only instead
of globally. You need [Claude Code](https://claude.com/claude-code) on any paid
plan and the Codex CLI signed into a ChatGPT plan.

## Use (two commands)

In any repo, inside Claude Code:

```
/architect-research <what you're thinking about building>
```

…when you're **brainstorming or picking a technology**. Fans out parallel
Codex web-researchers across six lanes, verifies every claim against sources,
and writes a cited, decision-oriented report to `docs/research/`.

```
/architect
```

…when you're **building**. One short session per work block: Claude judges the
last run's evidence, specs the next one-PR slice with frozen acceptance gates,
and dispatches a fresh autonomous Codex run that works for hours. Repeat.

---

## How it works in one picture

```
            ┌──────────── /architect-research (optional, first) ────────────┐
            │  6 parallel Codex researchers:                                │
            │  academic · popular repos · cutting-edge · production         │
            │  patterns · general web · expert opinion                      │
            │            → Fable verifies claims, writes the report         │
            └──────────────────────────┬────────────────────────────────────┘
                                       ▼
 CLAUDE FABLE (architect, minutes)            GPT-5.5 CODEX (builder, hours)
 ──────────────────────────────────           ─────────────────────────────────
 1 rule on builder disagreements       ──►    PHASE 0  plan + MANDATORY
 2 run the gates ITSELF, judge raw                      disagreements
   evidence vs frozen gates            ◄──    PHASE 1  freeze contracts
 3 spec next one-PR slice                     PHASE 2  ≤4 disjoint lanes +
 4 freeze gates → commit → dispatch                     1 reviewer lane →
 5 post-flight tamper check                             commit, push, update
                                                        HANDOFF with raw
                                                        results only
            └─────── docs/HANDOFF.md + docs/gates/ + git ───────┘
                       the repo carries everything;
                  not in the handoff = didn't happen
```

**Who does what:**

| | Model | Effort | Job |
|---|---|---|---|
| Architect | Claude Fable | `high` (pinned by the skill) | judgment only: arbitration, judging evidence, specs, kill/continue |
| Builder | GPT-5.5 via `codex exec` | `xhigh` (architect may dial per slice) | implementation, hours at a time, unattended |
| Researchers | GPT-5.5 via `codex exec -c web_search="live"` | `high` | gathering only — never recommendations |
| Memory | the repo | — | `docs/HANDOFF.md`, `docs/gates/`, `docs/research/`, git history |
| You | human | — | read the handoff between blocks; kill/continue authority |

## Why this shape works

Every serious source on agent harnesses — Anthropic's harness-engineering
posts, the most-installed community skills, the reward-hacking literature —
converged on the same four moves, and this loop enforces all of them
mechanically:

1. **Not in `docs/HANDOFF.md` = didn't happen.** State lives in the repo, not
   the chat. That's why 5 minutes of architect time per block is enough.
2. **Gates freeze before results exist.** Acceptance criteria are committed to
   `docs/gates/` *before* dispatch; a builder edit to any gate file (caught by
   `git diff`) fails the slice automatically. No goalpost-moving, by
   construction.
3. **Nobody grades their own work.** The builder reports raw numbers only;
   the architect runs the gate commands itself; cross-model review for
   high-stakes slices. Different models from different labs = no same-model
   sycophancy.
4. **Disagreement is mandatory.** The builder must challenge the spec (citing
   real files) before writing code — silent compliance is a defect. The
   architect rules on every disagreement: ACCEPT / REJECT / MODIFY + why.
5. **Fresh context per slice.** Every slice is a new Codex process; the
   architect's window holds judgment only. If a run breaks the repo:
   `git reset`, re-dispatch. Code is cheap; rescue prompting isn't.

The economics: judgment minutes on the expensive model, typing hours on the
flat-rate one. Both halves run on subscriptions you already have.

## The research skill, a layer deeper

`/architect-research` isn't "search the web and summarize." It encodes the
methodology the best deep-research systems converged on:

- **Brief first** — your question is compressed into a research brief that
  every later step is audited against.
- **Six lanes, fanned out in parallel** (each a fresh
  `codex exec -c web_search="live"`, read-only sandbox):
  1. **Academic** — arXiv recency queries + Semantic Scholar citation
     snowballing, survey-first
  2. **Popular repos** — dependents counts as adoption evidence (stars are
     gameable; ~4.5M fake stars documented)
  3. **Cutting-edge repos** — star-velocity + the emerging-vs-hype gate
  4. **Production patterns** — how the 2-3 best libraries in the niche design
     APIs, errors, extension points, tests — then a cross-library diff
  5. **General web** — postmortems, comparisons, official docs
  6. **Expert opinion** *(second wave)* — blogs/talks/X of the field's named
     experts, roster-seeded from what lanes 1-5 surface
- **Verification with teeth** — ≥2 independent sources per load-bearing claim,
  VERIFIED/UNVERIFIED/DISPUTED/SUSPICIOUS tags, adversarial falsification
  searches, citations only from URLs actually fetched (agents fabricate 3-13%
  of URLs otherwise).
- **One author** — Fable writes the report in a single pass: answer first,
  confidence per claim, "what would change this conclusion", open questions.
  Expert *opinions* are positions, never facts; expert *disagreements* are
  flagged as the genuinely open questions.

The report feeds `/architect`'s PRD when you're ready to build.

## What's in the box

| File | What it is |
|---|---|
| [DESIGN.md](DESIGN.md) | **The design document** — 12 enforced rules, failure-mode table, ~40 cited sources |
| [skills/architect/SKILL.md](skills/architect/SKILL.md) | The architect role: hard rules + procedure |
| [skills/architect/dispatch.md](skills/architect/dispatch.md) | Verified `codex exec` commands + the PHASE 0/1/2 builder block |
| [skills/architect/research.md](skills/architect/research.md) | Slice-scale inline fact-check fan-out |
| [skills/architect/HANDOFF.template.md](skills/architect/HANDOFF.template.md) | The repo-memory file the builder maintains |
| [skills/architect-research/SKILL.md](skills/architect-research/SKILL.md) | Discovery research: brief → plan → fan-out → verify → synthesize |
| [skills/architect-research/lanes.md](skills/architect-research/lanes.md) | Per-lane researcher prompts with verified endpoints |

## FAQ

**Do I need API keys?** No. Claude Code runs on your Claude plan; Codex CLI on
your ChatGPT plan. (Optional: `CODEX_API_KEY` per-token billing for overnight
runs that must not hit subscription rate windows.)

**What does a builder run cost?** It draws on your ChatGPT plan's 5-hour and
weekly quotas. Community reference points: a 6.5-hour autonomous run ≈ 20% of
a $100-tier weekly quota.

**What if the builder wrecks the repo?** One slice per run + a commit per lane
means `git reset` to the freeze commit and re-dispatch. The handoff records
what went wrong so the next spec avoids it.

**Can I watch the builder work?** Yes — `/architect` always prints the builder
block, so instead of the background dispatch you can paste it into an
interactive `codex` session prefixed with `/goal` and babysit the run.

**Why two skills?** Research-grade fan-out costs ~15× chat-level tokens — it
should be a deliberate act, not a side-effect of the build loop. `/architect`
still does small inline fact-checks on its own.

**Where do the rules come from?** [DESIGN.md](DESIGN.md) — every rule cites
its source (Anthropic engineering, the Fable prompting guide, verified Codex
CLI docs, superpowers, the Ralph loop, the reward-hacking literature).

## License

MIT
