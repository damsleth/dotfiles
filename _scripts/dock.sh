#!/usr/bin/env bash
# dock.sh - reset macOS Dock to a known layout via dockutil
#
# Idempotent: clears the Dock and rebuilds in order.
# Requires: brew install dockutil  (already in Brewfile)

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "macOS only"
    exit 0
fi

if ! command -v dockutil >/dev/null 2>&1; then
    echo "dockutil not installed. Run: brew install dockutil"
    exit 1
fi

info() { echo "[dock] $*"; }

info "Clearing existing Dock"
dockutil --remove all --no-restart

# Apps - in order, left to right
APPS=(
    "/Applications/Ghostty.app"
    "/System/Applications/Calendar.app"
    "/System/Applications/Mail.app"
    "/Applications/Slack.app"
    "/Applications/Visual Studio Code.app"
    "/Applications/Obsidian.app"
    "/Applications/Spotify.app"
    "/Applications/1Password.app"
)

for app in "${APPS[@]}"; do
    if [[ -d "$app" ]]; then
        info "+ $(basename "$app" .app)"
        dockutil --add "$app" --no-restart
    else
        info "- skip (missing): $app"
    fi
done

# Folders (right side, after the divider)
info "+ ~/Downloads"
dockutil --add "$HOME/Downloads" --view grid --display folder --sort dateadded --no-restart

info "Restarting Dock"
killall Dock

info "Done."
