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

if command -v pi >/dev/null 2>&1; then
    echo "pi CLI found: $(pi --version)"
    if [ -z "${OPENROUTER_API_KEY:-}" ]; then
        echo "  WARNING: OPENROUTER_API_KEY is not set - the builder needs it for minimax/minimax-m3"
    fi
    echo "  Builder model: pi --list-models minimax/minimax-m3"
    echo "  Web access:    pi install npm:pi-web-access  (zero-config via Exa)"
else
    echo "pi CLI not found - install the builder from https://pi.dev"
fi
