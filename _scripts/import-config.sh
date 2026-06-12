#!/usr/bin/env bash
# import-config.sh — Move a ~/.config/<tool> dir (or ~/.<file>) into a new stow package.
#
# Usage:
#   _scripts/import-config.sh <tool>            # ~/.config/<tool>  -> <tool> package
#   _scripts/import-config.sh --home <name>     # ~/.<name>         -> <name> package
#   _scripts/import-config.sh --dry-run <tool>  # show what would happen
#
# Idempotent: if the package already exists, the script aborts.
# After running, review the package, optionally add to bootstrap.sh, then commit.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="config"
DRY_RUN=0
TOOL=""

for arg in "$@"; do
    case "$arg" in
        --home) MODE="home" ;;
        --dry-run|-n) DRY_RUN=1 ;;
        -*) echo "unknown flag: $arg" >&2; exit 2 ;;
        *) TOOL="$arg" ;;
    esac
done

[[ -z "$TOOL" ]] && { echo "usage: $0 [--home] [--dry-run] <tool>"; exit 2; }

if [[ "$MODE" == "config" ]]; then
    SRC="$HOME/.config/$TOOL"
    DEST_REL="$TOOL/.config/$TOOL"
else
    SRC="$HOME/.$TOOL"
    DEST_REL="$TOOL/.$TOOL"
fi
DEST="$DOTFILES_DIR/$DEST_REL"
PKG_DIR="$DOTFILES_DIR/$TOOL"

if [[ ! -e "$SRC" ]]; then
    echo "[err] source missing: $SRC" >&2
    exit 1
fi
if [[ -L "$SRC" ]]; then
    echo "[err] $SRC is already a symlink - already stowed?" >&2
    exit 1
fi
if [[ -e "$PKG_DIR" ]]; then
    echo "[err] package already exists: $PKG_DIR" >&2
    exit 1
fi

echo "[info] importing $SRC -> $DEST_REL"
if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry] mkdir -p $(dirname "$DEST")"
    echo "[dry] mv $SRC $DEST"
    echo "[dry] (cd $DOTFILES_DIR && stow --target=$HOME --verbose $TOOL)"
else
    mkdir -p "$(dirname "$DEST")"
    mv "$SRC" "$DEST"
    (cd "$DOTFILES_DIR" && stow --target="$HOME" --verbose "$TOOL")
fi

echo
echo "[ok] imported. next steps:"
echo "  1. review $DEST_REL for secrets/state/caches; delete what shouldn't be tracked"
echo "  2. optionally add \"$TOOL\" to COMMON_PACKAGES in bootstrap.sh"
echo "  3. git add $TOOL && git commit -m \"feat: add $TOOL package\""
