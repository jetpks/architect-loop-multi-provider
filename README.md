# architect-loop — multi-provider

A monorepo of [architect-loop](https://github.com/DanMcInerney/architect-loop)
variants. The pattern is the same in every one: a strong **architect** model
plans and reviews (judgment only — it never writes code), while one or more
cheaper **builder** agents do the implementation and research in fresh,
isolated git worktrees. What differs between variants is *which* models fill
those two roles and *which* CLI runs the builder.

Each variant is a complete, self-contained copy of the project — its own
skills, design doc, install scripts, and tests. Pick the one whose
architect/builder pairing matches the plans and CLIs you have, and install from
that directory.

## Variants

| Directory | Architect | Builder | Builder CLI | What the builder costs |
|---|---|---|---|---|
| [`fable/gpt-55`](fable/gpt-55) | Claude Fable | GPT-5.5 Codex | `codex exec` (xhigh) | ChatGPT plan 5-hour / weekly quotas |

The directory layout mirrors the convention `<architect>/<builder>`. More
provider variants land as they're validated.

### Which one?

- **[`fable/gpt-55`](fable/gpt-55)** — you have a ChatGPT plan and want the
  builder's hours billed against it. No API keys; uses the Codex CLI.

## Install

Each variant installs independently from its own directory:

```bash
git clone https://github.com/jetpks/architect-loop-multi-provider
cd architect-loop-multi-provider/fable/gpt-55   # or another variant directory
./install.sh                                     # Windows: .\install.ps1
# then install that variant's builder CLI — see the variant's README
```

`./install.sh --project` installs to the current repo only instead of
globally. Every variant needs [Claude Code](https://claude.com/claude-code) on
a paid plan for the architect; the builder CLI and any keys differ per variant
(see the table above and the variant's own README).

## Use

Installed, every variant exposes the same two Claude Code skills:

```
/architect                                      # the build loop
/architect-research <what you're considering>   # the research loop
```

`/architect` runs one work block: judge the last run, spec the next one-PR
slice into 1–4 worktree-isolated lanes, dispatch builders, then judge raw
evidence against frozen gates and merge what passes. `/architect-research` is
the discovery-scale research harness for when you're still deciding *what* to
build. The repo is the only memory (`docs/HANDOFF.md`, `docs/gates/`,
`docs/lanes/`, git history).

For the full design, rules, and the source-backed rationale behind the shape,
read the `DESIGN.md` inside any variant.

## Origin

The original idea came from
[this X post by @jumperz](https://x.com/jumperz/status/2065454404623384859)
about using Fable with Codex subagents, and the upstream project lives at
[DanMcInerney/architect-loop](https://github.com/DanMcInerney/architect-loop).
This fork collects the provider variants into one tree so they live side by
side instead of on separate branches.

## License

MIT — see [LICENSE](LICENSE). Each variant carries the same license.
