#!/usr/bin/env bash
# vscode-restore.sh - install VS Code extensions from vscode-extensions.txt
#
# Usage:
#   ./_scripts/vscode-restore.sh         # interactive: prompts before installing 100+ extensions
#   ./_scripts/vscode-restore.sh --yes   # non-interactive
#   ./_scripts/vscode-restore.sh --dump  # refresh vscode-extensions.txt from current install

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXT_FILE="$DOTFILES_DIR/_scripts/vscode-extensions.txt"

info()  { echo "[vscode] $*"; }
warn()  { echo "[warn]   $*" >&2; }

if ! command -v code >/dev/null 2>&1; then
    warn "'code' CLI not found. Install via VS Code -> Command Palette -> 'Shell Command: Install code in PATH'."
    exit 1
fi

if [[ "${1:-}" == "--dump" ]]; then
    info "Dumping current extensions to $EXT_FILE"
    code --list-extensions | sort > "$EXT_FILE"
    info "Captured $(wc -l < "$EXT_FILE") extensions."
    exit 0
fi

if [[ ! -f "$EXT_FILE" ]]; then
    warn "No extensions list at $EXT_FILE"
    exit 1
fi

count=$(wc -l < "$EXT_FILE" | tr -d ' ')

if [[ "${1:-}" != "--yes" ]]; then
    echo "About to install $count VS Code extensions from $EXT_FILE."
    echo "Many may be cruft from prior experiments - consider trimming the file first."
    read -rp "Proceed? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }
fi

installed_count=0
failed_count=0
already_installed=$(code --list-extensions | sort)

while IFS= read -r ext; do
    [[ -z "$ext" || "$ext" == \#* ]] && continue
    if grep -qx "$ext" <<<"$already_installed"; then
        continue
    fi
    if code --install-extension "$ext" --force >/dev/null 2>&1; then
        echo "  + $ext"
        installed_count=$((installed_count + 1))
    else
        echo "  ! failed: $ext"
        failed_count=$((failed_count + 1))
    fi
done < "$EXT_FILE"

info "Installed: $installed_count, failed: $failed_count"
