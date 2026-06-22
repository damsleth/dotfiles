#!/usr/bin/env bash
# lang-restore.sh - reinstall pipx and npm global packages from snapshot lists.
#
# Lists:
#   _scripts/pipx-packages.txt   one pipx package name per line
#   _scripts/npm-globals.txt     one npm spec per line (scoped names ok)
#
# Refresh the snapshots from the current machine:
#   _scripts/lang-restore.sh --dump
#
# Restore on a fresh box:
#   _scripts/lang-restore.sh

set -euo pipefail

# Match the PATH a fresh zsh would build, plus eval fnm so its Node/npm shim
# is reachable when this script runs from a bash subshell that hasn't sourced
# ~/.zshrc (e.g. during first-boot bootstrap).
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$HOME/.npm-packages/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$PATH"
if command -v fnm >/dev/null 2>&1; then
    eval "$(fnm env --shell bash)" 2>/dev/null || true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Manifest paths are env-overridable so callers (dotfiles-wizard.sh) can point
# them at a filtered temp list of just the packages the user selected.
PIPX_FILE="${PIPX_FILE:-$SCRIPT_DIR/pipx-packages.txt}"
NPM_FILE="${NPM_FILE:-$SCRIPT_DIR/npm-globals.txt}"
MODE="restore"

for arg in "$@"; do
    case "$arg" in
        --dump) MODE="dump" ;;
        --restore) MODE="restore" ;;
        *) echo "unknown flag: $arg" >&2; exit 2 ;;
    esac
done

info()    { echo "[lang] $*"; }
warn()    { echo "[warn] $*"; }

if [[ "$MODE" == "dump" ]]; then
    if command -v pipx >/dev/null 2>&1; then
        info "dumping pipx packages -> $PIPX_FILE"
        pipx list --short | awk '{print $1}' | sort -u > "$PIPX_FILE"
    else
        warn "pipx not on PATH - skipping pipx dump"
    fi
    if command -v npm >/dev/null 2>&1; then
        info "dumping npm globals -> $NPM_FILE"
        npm list -g --depth=0 --json 2>/dev/null \
            | jq -r '.dependencies | keys[]' \
            | grep -v -E '^(npm|corepack|install|or|pip)$' \
            | sort -u > "$NPM_FILE"
    else
        warn "npm not on PATH - skipping npm dump"
    fi
    info "done. review and commit."
    exit 0
fi

# Restore mode
if [[ -f "$PIPX_FILE" ]]; then
    if ! command -v pipx >/dev/null 2>&1; then
        warn "pipx not installed - run 'brew install pipx' first, then re-run this script"
    else
        while IFS= read -r pkg; do
            pkg="${pkg%%#*}"; pkg="$(echo "$pkg" | xargs)"
            [[ -z "$pkg" ]] && continue
            if pipx list --short 2>/dev/null | awk '{print $1}' | grep -qx "$pkg"; then
                echo "[skip] pipx $pkg (already installed)"
            else
                info "pipx install $pkg"
                pipx install "$pkg" || warn "pipx install failed: $pkg"
            fi
        done < "$PIPX_FILE"
    fi
else
    warn "no pipx-packages.txt - skipping pipx restore"
fi

if [[ -f "$NPM_FILE" ]]; then
    if ! command -v npm >/dev/null 2>&1; then
        warn "npm not on PATH - skipping npm restore"
    else
        while IFS= read -r pkg; do
            pkg="${pkg%%#*}"; pkg="$(echo "$pkg" | xargs)"
            [[ -z "$pkg" ]] && continue
            info "npm i -g $pkg"
            npm i -g "$pkg" || warn "npm install failed: $pkg"
        done < "$NPM_FILE"
    fi
else
    warn "no npm-globals.txt - skipping npm restore"
fi
