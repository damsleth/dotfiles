#!/usr/bin/env bash
# macos.sh - opinionated macOS system defaults
# Idempotent: safe to re-run.
#
# Usage:
#   ./_scripts/macos.sh                      # apply every category
#   ./_scripts/macos.sh --only finder,dock   # apply just these categories
#   ./_scripts/macos.sh --list-categories    # print "slug|Title|description" lines
#   ./_scripts/macos.sh --dry-run            # print what would change, touch nothing
#
# The category list + --only/--list-categories interface is what dotfiles-wizard.sh
# drives for its "macOS" tab; the slugs below are the contract.

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Not macOS - skipping."
    exit 0
fi

# ── args ────────────────────────────────────────────────────────────────────
ONLY=""          # empty = all categories
DRY=0
MODE="apply"     # apply | list
while [[ $# -gt 0 ]]; do
    case "$1" in
        --only)            ONLY="${2:-}"; shift 2 ;;
        --only=*)          ONLY="${1#*=}"; shift ;;
        --list-categories) MODE="list"; shift ;;
        --dry-run|-n)      DRY=1; shift ;;
        -h|--help)         sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "macos.sh: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

info() { echo "[macos] $*"; }

# Mutating commands route through run() so --dry-run can preview without touching
# the system. Multi-line args (the symbolichotkeys dict) survive as one argument.
run() {
    if [[ $DRY -eq 1 ]]; then printf '[dry]  %s\n' "$*"; else "$@"; fi
}

# ── category catalog ─────────────────────────────────────────────────────────
# slug | Title | description (shown in the wizard). Order here = apply order.
CATEGORIES=(
    "appearance|Appearance|Dark mode, battery %, mute startup chime"
    "general|General|Save/print panels, disable smart quotes, fast key repeat, Opt+Tab window switch, scrollbars"
    "trackpad|Trackpad|Tap to click, three-finger drag"
    "finder|Finder|Show extensions/hidden files/path bar, list view, no .DS_Store on network/USB"
    "security|Security|Require password immediately on sleep / screensaver"
    "dock|Dock + Mission Control|Smaller autohide dock, no recents, scale minimize, stable spaces"
    "screenshots|Screenshots|Save to ~/Pictures/Screenshots as PNG, no shadow"
    "safari|Safari|Develop menu + full URL in the address bar"
)

if [[ "$MODE" == "list" ]]; then
    for c in "${CATEGORIES[@]}"; do echo "$c"; done
    exit 0
fi

# wants <slug> → true if this category should run (no --only = everything).
wants() {
    [[ -z "$ONLY" ]] && return 0
    case ",$ONLY," in *,"$1",*) return 0 ;; *) return 1 ;; esac
}

# ── category implementations ──────────────────────────────────────────────────
cat_appearance() {
    info "Dark mode"
    run defaults write NSGlobalDomain AppleInterfaceStyle -string "Dark"
    info "Battery percentage in menu bar"
    run defaults write com.apple.controlcenter BatteryShowPercentage -bool true
    info "Mute startup chime"
    run sudo nvram StartupMute=%01 2>/dev/null || true
}

cat_general() {
    info "Expand save panel by default"
    run defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
    run defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
    info "Expand print panel by default"
    run defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
    run defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true
    info "Save to disk by default, not iCloud"
    run defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false
    info "Disable smart quotes and dashes (devs type literally)"
    run defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
    run defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
    run defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
    run defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
    run defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
    info "Disable press-and-hold for keys (enables key repeat)"
    run defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
    info "Fast key repeat (requires logout/login to take effect)"
    run defaults write NSGlobalDomain KeyRepeat -int 1
    run defaults write NSGlobalDomain InitialKeyRepeat -int 10
    info "F-keys behave as standard function keys (not media keys)"
    run defaults write NSGlobalDomain com.apple.keyboard.fnState -bool true
    info "Rebind 'Move focus to next window' to Opt+Tab (default Cmd+\`)"
    # Symbolic hotkey 27 = next window in active app. parameters = (ascii, virtual_keycode, modifier_mask)
    # Tab: ascii 9, keycode 48. Option modifier mask: 0x080000 = 524288.
    run defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 27 '
{
    enabled = 1;
    value = {
        parameters = (9, 48, 524288);
        type = standard;
    };
}'
    # Takes effect after logout/login; activateSettings -u nudges some daemons but not all.
    run /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true
    info "Always show scrollbars while scrolling"
    run defaults write NSGlobalDomain AppleShowScrollBars -string "WhenScrolling"
    info "Drag windows from any empty area with ctrl+cmd (Sequoia+)"
    run defaults write NSGlobalDomain NSWindowShouldDragOnGesture -bool true
}

cat_trackpad() {
    info "Trackpad: tap to click (built-in + Bluetooth)"
    run defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
    run defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
    run defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
    info "Trackpad: enable three-finger drag (built-in + Bluetooth)"
    run defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true
    run defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -bool true
}

cat_finder() {
    info "Finder: show all filename extensions"
    run defaults write NSGlobalDomain AppleShowAllExtensions -bool true
    info "Finder: show hidden files"
    run defaults write com.apple.finder AppleShowAllFiles -bool true
    info "Finder: show path bar + status bar"
    run defaults write com.apple.finder ShowPathbar -bool true
    run defaults write com.apple.finder ShowStatusBar -bool true
    info "Finder: POSIX path in title bar"
    run defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
    info "Finder: keep folders on top when sorting"
    run defaults write com.apple.finder _FXSortFoldersFirst -bool true
    info "Finder: default search scope = current folder"
    run defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
    info "Finder: disable warning when changing file extension"
    run defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
    info "Finder: list view as default"
    run defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
    info "Finder: don't write .DS_Store on network/USB"
    run defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
    run defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true
    info "Finder: new windows open in \$HOME"
    run defaults write com.apple.finder NewWindowTarget -string "PfHm"
    run defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/"
}

cat_security() {
    info "Require password immediately on sleep / screensaver"
    run defaults write com.apple.screensaver askForPassword -int 1
    run defaults write com.apple.screensaver askForPasswordDelay -int 0
}

cat_dock() {
    info "Dock: smaller, autohide, no recent apps"
    run defaults write com.apple.dock tilesize -int 42
    run defaults write com.apple.dock autohide -bool true
    run defaults write com.apple.dock autohide-delay -float 0
    run defaults write com.apple.dock autohide-time-modifier -float 0.4
    run defaults write com.apple.dock show-recents -bool false
    run defaults write com.apple.dock mineffect -string "scale"
    run defaults write com.apple.dock minimize-to-application -bool true
    info "Mission Control: don't rearrange spaces by recent use"
    run defaults write com.apple.dock mru-spaces -bool false
}

cat_screenshots() {
    info "Screenshots: save to ~/Pictures/Screenshots as PNG, no shadow"
    run mkdir -p "$HOME/Pictures/Screenshots"
    run defaults write com.apple.screencapture location -string "$HOME/Pictures/Screenshots"
    run defaults write com.apple.screencapture type -string "png"
    run defaults write com.apple.screencapture disable-shadow -bool true
}

cat_safari() {
    info "Safari: dev menu + full URL"
    run defaults write com.apple.Safari IncludeDevelopMenu -bool true 2>/dev/null || true
    run defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true 2>/dev/null || true
}

# ── run selected categories ───────────────────────────────────────────────────
# Ask sudo upfront (some categories use it) so the rest runs unattended.
if [[ $DRY -eq 0 ]]; then
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
fi

ran=0
for c in "${CATEGORIES[@]}"; do
    slug="${c%%|*}"
    wants "$slug" || continue
    "cat_${slug}"
    ran=1
done

if [[ $ran -eq 0 ]]; then
    info "No matching categories for --only '$ONLY' — nothing to do."
    exit 0
fi

# ── apply ─────────────────────────────────────────────────────────────────────
info "Flushing preferences cache (cfprefsd) and restarting affected apps..."
# cfprefsd caches plist values in memory; without flushing it, freshly-written
# defaults can appear to "not be set" until next login.
run killall cfprefsd 2>/dev/null || true
for app in "Finder" "Dock" "SystemUIServer"; do
    run killall "$app" 2>/dev/null || true
done

info "Done. Key repeat / InitialKeyRepeat require logout/login to fully apply."
