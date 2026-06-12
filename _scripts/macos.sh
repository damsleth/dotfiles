#!/usr/bin/env bash
# macos.sh - opinionated macOS system defaults
# Idempotent: safe to re-run.
# Usage: ./_scripts/macos.sh

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Not macOS - skipping."
    exit 0
fi

# Ask sudo upfront so the rest runs unattended.
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &

info() { echo "[macos] $*"; }

# ============================================================================
# Appearance
# ============================================================================
info "Dark mode"
defaults write NSGlobalDomain AppleInterfaceStyle -string "Dark"

info "Battery percentage in menu bar"
defaults write com.apple.controlcenter BatteryShowPercentage -bool true

info "Mute startup chime"
sudo nvram StartupMute=%01 2>/dev/null || true

# ============================================================================
# General
# ============================================================================
info "Expand save panel by default"
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true

info "Expand print panel by default"
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

info "Save to disk by default, not iCloud"
defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false

info "Disable smart quotes and dashes (devs type literally)"
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

info "Disable press-and-hold for keys (enables key repeat)"
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

info "Fast key repeat (requires logout/login to take effect)"
defaults write NSGlobalDomain KeyRepeat -int 1
defaults write NSGlobalDomain InitialKeyRepeat -int 10

info "F-keys behave as standard function keys (not media keys)"
defaults write NSGlobalDomain com.apple.keyboard.fnState -bool true

info "Rebind 'Move focus to next window' to Opt+Tab (default Cmd+\`)"
# Symbolic hotkey 27 = next window in active app. parameters = (ascii, virtual_keycode, modifier_mask)
# Tab: ascii 9, keycode 48. Option modifier mask: 0x080000 = 524288.
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 27 '
{
    enabled = 1;
    value = {
        parameters = (9, 48, 524288);
        type = standard;
    };
}'
# Takes effect after logout/login; activateSettings -u nudges some daemons but not all.
/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true

info "Always show scrollbars while scrolling"
defaults write NSGlobalDomain AppleShowScrollBars -string "WhenScrolling"

info "Drag windows from any empty area with ctrl+cmd (Sequoia+)"
defaults write NSGlobalDomain NSWindowShouldDragOnGesture -bool true

# ============================================================================
# Trackpad / mouse
# ============================================================================
info "Trackpad: tap to click (built-in + Bluetooth)"
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

info "Trackpad: enable three-finger drag (built-in + Bluetooth)"
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -bool true

# ============================================================================
# Finder
# ============================================================================
info "Finder: show all filename extensions"
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

info "Finder: show hidden files"
defaults write com.apple.finder AppleShowAllFiles -bool true

info "Finder: show path bar + status bar"
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true

info "Finder: POSIX path in title bar"
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true

info "Finder: keep folders on top when sorting"
defaults write com.apple.finder _FXSortFoldersFirst -bool true

info "Finder: default search scope = current folder"
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"

info "Finder: disable warning when changing file extension"
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

info "Finder: list view as default"
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

info "Finder: don't write .DS_Store on network/USB"
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

info "Finder: new windows open in \$HOME"
defaults write com.apple.finder NewWindowTarget -string "PfHm"
defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/"

# ============================================================================
# Security
# ============================================================================
info "Require password immediately on sleep / screensaver"
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0

# ============================================================================
# Dock + Mission Control
# ============================================================================
info "Dock: smaller, autohide, no recent apps"
defaults write com.apple.dock tilesize -int 42
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0.4
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock mineffect -string "scale"
defaults write com.apple.dock minimize-to-application -bool true

info "Mission Control: don't rearrange spaces by recent use"
defaults write com.apple.dock mru-spaces -bool false

# ============================================================================
# Screenshots
# ============================================================================
info "Screenshots: save to ~/Pictures/Screenshots as PNG, no shadow"
mkdir -p "$HOME/Pictures/Screenshots"
defaults write com.apple.screencapture location -string "$HOME/Pictures/Screenshots"
defaults write com.apple.screencapture type -string "png"
defaults write com.apple.screencapture disable-shadow -bool true

# ============================================================================
# Safari (only if installed/used)
# ============================================================================
info "Safari: dev menu + full URL"
defaults write com.apple.Safari IncludeDevelopMenu -bool true 2>/dev/null || true
defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true 2>/dev/null || true

# ============================================================================
# Apply
# ============================================================================
info "Flushing preferences cache (cfprefsd) and restarting affected apps..."
# cfprefsd caches plist values in memory; without flushing it, freshly-written
# defaults can appear to "not be set" until next login.
killall cfprefsd 2>/dev/null || true
for app in "Finder" "Dock" "SystemUIServer"; do
    killall "$app" 2>/dev/null || true
done

info "Done. Key repeat / InitialKeyRepeat require logout/login to fully apply."
