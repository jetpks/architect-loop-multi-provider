#!/usr/bin/env bash
set -euo pipefail

SRC_ROOT="$(cd "$(dirname "$0")" && pwd)/skills"
if [ "${1:-}" = "--project" ]; then
    DEST_ROOT="$(pwd)/.claude/skills"
else
    DEST_ROOT="$HOME/.claude/skills"
fi

mkdir -p "$DEST_ROOT"
for skill in "$SRC_ROOT"/*/; do
    name="$(basename "$skill")"
    rm -rf "${DEST_ROOT:?}/$name"
    cp -r "$skill" "$DEST_ROOT/$name"
    echo "Installed /$name to $DEST_ROOT/$name"
done

if command -v claude >/dev/null 2>&1; then
    echo "Claude Code found: $(claude --version)"
    echo "  Both roles run on this binary: architect = your interactive Opus 4.8 session,"
    echo "  builder = headless 'claude -p --model claude-sonnet-4-6'."
    echo "  Builder/researcher hours draw on the Agent SDK credit pool on your Claude plan."
else
    echo "Claude Code not found - install it from https://claude.com/claude-code"
fi
