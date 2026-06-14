#!/usr/bin/env python3
"""Sanity checks for the architect-loop skill repo. Stdlib only.

Catches the failure modes we've actually hit:
- SKILL.md frontmatter description > 1024 chars -> Codex refuses to load the
  skill (observed live: "invalid description: exceeds maximum length").
- A skill file referencing a sibling file that doesn't exist.
- README/DESIGN relative links pointing at deleted/moved files.
- Unbalanced ``` fences (breaks the builder-block templates when pasted).

Run: python tests/validate_skills.py   (exit 0 = pass)
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKILLS = ROOT / "skills"
MAX_DESC = 1024
REQUIRED_SIBLINGS = {
    "architect": ["dispatch.md", "research.md", "HANDOFF.template.md"],
    "architect-research": ["lanes.md"],
}
errors: list[str] = []


def check_frontmatter(skill_dir: Path) -> None:
    skill_md = skill_dir / "SKILL.md"
    if not skill_md.exists():
        errors.append(f"{skill_dir.name}: missing SKILL.md")
        return
    text = skill_md.read_text(encoding="utf-8")
    m = re.match(r"---\n(.*?)\n---\n", text, re.DOTALL)
    if not m:
        errors.append(f"{skill_dir.name}: SKILL.md has no frontmatter block")
        return
    fm = m.group(1)
    name = re.search(r"^name:\s*(\S+)", fm, re.MULTILINE)
    if not name or name.group(1) != skill_dir.name:
        errors.append(f"{skill_dir.name}: frontmatter name != directory name")
    desc = re.search(r"^description:\s*>?\s*\n?(.*?)(?=^\w+:|\Z)", fm, re.MULTILINE | re.DOTALL)
    if not desc:
        errors.append(f"{skill_dir.name}: frontmatter has no description")
    else:
        flat = re.sub(r"\s+", " ", desc.group(1)).strip()
        if len(flat) > MAX_DESC:
            errors.append(
                f"{skill_dir.name}: description {len(flat)} chars > {MAX_DESC} "
                "(Codex refuses to load the skill)"
            )


def check_siblings(skill_dir: Path) -> None:
    for sibling in REQUIRED_SIBLINGS.get(skill_dir.name, []):
        if not (skill_dir / sibling).exists():
            errors.append(f"{skill_dir.name}: required file {sibling} missing")
    skill_md = (skill_dir / "SKILL.md").read_text(encoding="utf-8")
    for ref in re.findall(r"`([\w][\w.-]*\.md)`", skill_md):
        if ref in ("SKILL.md", "AGENTS.md", "CLAUDE.md", "HANDOFF.md", "CONVENTIONS.md",
                   "PLAN.md", "MEMORY.md", "README.md", "GEMINI.md"):
            continue  # repo-of-use files, not siblings of the skill
        if ref == "DESIGN.md" and (ROOT / "DESIGN.md").exists():
            continue  # lives at the skill repo root, referenced as such
        if re.match(r"(docs|lane|gate|prd|research)", ref):
            continue
        if not (skill_dir / ref).exists():
            errors.append(f"{skill_dir.name}: SKILL.md references `{ref}` which doesn't exist")


def check_fences(path: Path) -> None:
    if path.read_text(encoding="utf-8").count("```") % 2 != 0:
        errors.append(f"{path.relative_to(ROOT)}: odd number of ``` fences")


def check_local_links(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    for label, target in re.findall(r"\[([^\]]+)\]\(([^)#\s]+)\)", text):
        if target.startswith(("http://", "https://", "mailto:")):
            continue
        if not (ROOT / target).exists():
            errors.append(f"{path.name}: link '{label}' -> {target} doesn't exist")


def main() -> int:
    skill_dirs = sorted(d for d in SKILLS.iterdir() if d.is_dir())
    if not skill_dirs:
        errors.append("no skill directories found under skills/")
    for d in skill_dirs:
        check_frontmatter(d)
        check_siblings(d)
        for md in d.glob("*.md"):
            check_fences(md)
    for doc in ("README.md", "DESIGN.md"):
        p = ROOT / doc
        if p.exists():
            check_fences(p)
            check_local_links(p)
        else:
            errors.append(f"{doc} missing")
    if errors:
        print(f"FAIL — {len(errors)} problem(s):")
        for e in errors:
            print(f"  - {e}")
        return 1
    print(f"OK — {len(skill_dirs)} skills validated, README/DESIGN links + fences clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
