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

# Builder sandbox backend (pi-sandbox confines each builder to its worktree).
case "$(uname -s)" in
    Darwin)
        if [ -x /usr/bin/sandbox-exec ]; then
            echo "Sandbox: macOS Seatbelt (/usr/bin/sandbox-exec) - OK"
        else
            echo "Sandbox: /usr/bin/sandbox-exec missing - builders fall back to combined-lane dispatch"
        fi
        ;;
    Linux)
        if command -v landrun >/dev/null 2>&1; then
            echo "Sandbox: Linux Landlock (landrun) - OK"
        else
            echo "Sandbox: landrun not found - install it (https://github.com/Zouuup/landrun, kernel 5.13+)"
            echo "         or builders fall back to combined-lane dispatch"
        fi
        ;;
    *)
        echo "Sandbox: none on $(uname -s) - builders use combined-lane dispatch (see dispatch.md)"
        ;;
esac
