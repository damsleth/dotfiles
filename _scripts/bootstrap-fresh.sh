#!/usr/bin/env bash
# bootstrap-fresh.sh - first-boot setup for a brand-new macOS install
#
# Usage after the private repo is cloned:
#   ~/Code/dotfiles/_scripts/bootstrap-fresh.sh
#
# For a brand-new Mac, use the public-safe gist bootstrap first; it installs
# git/gh, authenticates GitHub, clones this private repo, then runs this script.
#
# Idempotent: every step checks state before acting.

set -euo pipefail

DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/damsleth/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/Code/dotfiles}"
DOTFILES_PRIVATE="${DOTFILES_PRIVATE:-$DOTFILES_DIR/private}"
HOSTNAME_DEFAULT="${HOSTNAME_DEFAULT:-}"

info()    { printf '\033[1;34m[boot]\033[0m %s\n' "$*"; }
success() { printf '\033[1;32m[ok]\033[0m   %s\n' "$*"; }
warn()    { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
err()     { printf '\033[1;31m[err]\033[0m  %s\n' "$*" >&2; }

find_restore_script() {
    local name="$1" candidate
    for candidate in "$DOTFILES_DIR/_scripts/$name" "$DOTFILES_PRIVATE/_scripts/$name"; do
        [[ -x "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
    done
    return 1
}

# ----------------------------------------------------------------------------
# Sanity check
# ----------------------------------------------------------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
    err "This script is macOS-only. For Linux, run bootstrap.sh directly."
    exit 1
fi

sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &

# ----------------------------------------------------------------------------
# 1. Hostname
# ----------------------------------------------------------------------------
if [[ -n "$HOSTNAME_DEFAULT" ]]; then
    current_hostname="$(scutil --get ComputerName 2>/dev/null || echo "")"
    if [[ "$current_hostname" != "$HOSTNAME_DEFAULT" ]]; then
        info "Setting hostname to $HOSTNAME_DEFAULT (was: ${current_hostname:-unset})"
        sudo scutil --set ComputerName "$HOSTNAME_DEFAULT"
        sudo scutil --set LocalHostName "$HOSTNAME_DEFAULT"
        sudo scutil --set HostName "$HOSTNAME_DEFAULT"
    else
        success "Hostname already $HOSTNAME_DEFAULT"
    fi
else
    info "Skipping hostname step (HOSTNAME_DEFAULT unset)"
fi

# ----------------------------------------------------------------------------
# 2. Xcode Command Line Tools
# ----------------------------------------------------------------------------
if ! xcode-select -p >/dev/null 2>&1; then
    info "Installing Xcode Command Line Tools (GUI prompt will appear)"
    xcode-select --install
    info "Waiting for Xcode CLT install to complete..."
    until xcode-select -p >/dev/null 2>&1; do sleep 5; done
    success "Xcode CLT installed"
else
    success "Xcode CLT already installed"
fi

# ----------------------------------------------------------------------------
# 3. Homebrew
# ----------------------------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
    info "Installing Homebrew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
else
    success "Homebrew already installed"
fi

# ----------------------------------------------------------------------------
# 4. TouchID for sudo
# ----------------------------------------------------------------------------
if [[ ! -f /etc/pam.d/sudo_local ]]; then
    info "Enabling TouchID for sudo"
    sudo cp /etc/pam.d/sudo_local.template /etc/pam.d/sudo_local
    sudo sed -i '' 's/^#auth/auth/' /etc/pam.d/sudo_local
    success "TouchID sudo enabled"
else
    success "TouchID sudo already configured"
fi

# ----------------------------------------------------------------------------
# 5. Clone dotfiles
# ----------------------------------------------------------------------------
if [[ ! -d "$DOTFILES_DIR/.git" ]]; then
    info "Cloning dotfiles to $DOTFILES_DIR"
    mkdir -p "$(dirname "$DOTFILES_DIR")"
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
else
    info "dotfiles repo already present at $DOTFILES_DIR - pulling latest"
    git -C "$DOTFILES_DIR" pull --ff-only || warn "git pull failed - continuing"
fi

# ----------------------------------------------------------------------------
# 6. brew bundle (Brewfile) - App Store sign-in first
# ----------------------------------------------------------------------------
# `brew bundle` will silently skip every `mas` line if the App Store isn't
# signed in. Install/check mas first, then pause only if needed.
if ! command -v mas >/dev/null 2>&1; then
    info "Installing mas before brew bundle so App Store sign-in can be checked"
    brew install mas
fi

mas_signed_in() {
    # `mas account` was removed in v2 and `mas config`'s "store" field is the
    # ISO country code (NO = Norway, not "not signed in"). Definitive signal:
    # `mas list` returns lines only when signed in. On a fresh box with no
    # purchases yet, fall back to the iTunes account plist, which is populated
    # the moment App Store sign-in completes.
    mas list 2>/dev/null | grep -q . && return 0
    defaults read ~/Library/Preferences/MobileMeAccounts.plist 2>/dev/null \
        | grep -q "AccountID =" && return 0
    return 1
}

while ! mas_signed_in; do
    open -a "App Store" 2>/dev/null || true
    cat <<'EOF'

  [pause] Before brew bundle runs:
    1. Open the App Store and sign in with your Apple ID.
    2. The Brewfile installs several mas apps (Xcode, Amphetamine, etc.).
       Without sign-in, those lines are silently skipped.

EOF
    read -rp "  Press Enter once signed in: " _
done
success "App Store account available to mas"

if [[ -f "$DOTFILES_DIR/Brewfile" ]]; then
    info "Running brew bundle (Brewfile)"
    brew bundle --file="$DOTFILES_DIR/Brewfile"
else
    warn "No Brewfile at $DOTFILES_DIR/Brewfile - skipping"
fi
if [[ -f "$DOTFILES_PRIVATE/Brewfile" ]]; then
    info "Running private brew bundle"
    brew bundle --file="$DOTFILES_PRIVATE/Brewfile"
fi

# ----------------------------------------------------------------------------
# 7. Stow packages (bootstrap.sh)
# ----------------------------------------------------------------------------
if [[ -x "$DOTFILES_DIR/bootstrap.sh" ]]; then
    info "Running bootstrap.sh (stow packages)"
    "$DOTFILES_DIR/bootstrap.sh"
else
    warn "bootstrap.sh not found or not executable"
fi

# ----------------------------------------------------------------------------
# 7b. Runtime env for subsequent steps
# ----------------------------------------------------------------------------
# Stow just linked ~/.zshrc, but we're in a bash subshell - sourcing it won't
# work cleanly, and a fresh zsh login is what normally builds PATH. Replicate
# the parts later steps need so they don't fail with "npm not on PATH" etc.
info "Priming PATH and version managers for the remaining steps"
export PATH="$HOME/bin:$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.npm-packages/bin:$HOME/go/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$PATH"
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
if command -v fnm >/dev/null 2>&1; then
    eval "$(fnm env --shell bash)"
fi

# ----------------------------------------------------------------------------
# 8. macOS defaults
# ----------------------------------------------------------------------------
if [[ -x "$DOTFILES_DIR/_scripts/macos.sh" ]]; then
    info "Applying macOS defaults"
    "$DOTFILES_DIR/_scripts/macos.sh"
else
    warn "macos.sh not found - skipping"
fi

# ----------------------------------------------------------------------------
# 9. Secrets from 1Password
# ----------------------------------------------------------------------------
secrets_restore="$(find_restore_script secrets-restore.sh || true)"
if [[ -n "$secrets_restore" ]]; then
    info "Restoring machine-local secrets from 1Password"
    "$secrets_restore" || warn "secrets-restore.sh exited non-zero"
fi

# ----------------------------------------------------------------------------
# 10. Clone personal repos referenced by ~/.local/bin symlinks
# ----------------------------------------------------------------------------
if [[ -x "$DOTFILES_DIR/_scripts/clone-repos.sh" ]]; then
    info "Cloning personal repos from overlay manifest"
    "$DOTFILES_DIR/_scripts/clone-repos.sh" || warn "clone-repos.sh exited non-zero (SSH agent loaded?)"
fi

# ----------------------------------------------------------------------------
# 11. Install language toolchains brew alone doesn't cover (fnm LTS, rustup, GOPATH)
# ----------------------------------------------------------------------------
# Must run BEFORE lang-restore.sh: fnm provides Node (and therefore npm), and
# rustup provides cargo. Without these, the npm-globals restore is a no-op.
if [[ -x "$DOTFILES_DIR/_scripts/toolchains-restore.sh" ]]; then
    info "Restoring language toolchains"
    "$DOTFILES_DIR/_scripts/toolchains-restore.sh" || warn "toolchains-restore.sh exited non-zero"
    # Re-eval fnm now that a default Node version exists, so npm is on PATH
    # for lang-restore.sh below.
    if command -v fnm >/dev/null 2>&1; then
        eval "$(fnm env --shell bash)"
    fi
fi

# ----------------------------------------------------------------------------
# 11b. Reinstall pipx + npm global packages
# ----------------------------------------------------------------------------
if [[ -x "$DOTFILES_DIR/_scripts/lang-restore.sh" ]]; then
    info "Restoring pipx + npm globals"
    "$DOTFILES_DIR/_scripts/lang-restore.sh" || warn "lang-restore.sh exited non-zero"
fi

# ----------------------------------------------------------------------------
# 11c. Editable-install self-written tools from their ~/code clones
# ----------------------------------------------------------------------------
# Runs after clone-repos.sh (step 10) and pipx (brew bundle, step 6).
tools_restore="$(find_restore_script tools-restore.sh || true)"
if [[ -n "$tools_restore" ]]; then
    info "Editable-installing local tools"
    "$tools_restore" || warn "tools-restore.sh exited non-zero"
fi

# ----------------------------------------------------------------------------
# 12. Short-lived local-tool auth - intentionally NOT run here
# ----------------------------------------------------------------------------
# Auth tokens for private tools are deliberately left out of the orchestrator.
# Authenticate manually after bootstrap once private tools are installed.

# ----------------------------------------------------------------------------
# 13. Dock layout
# ----------------------------------------------------------------------------
if [[ -x "$DOTFILES_DIR/_scripts/dock.sh" ]]; then
    info "Resetting Dock layout"
    "$DOTFILES_DIR/_scripts/dock.sh" || warn "dock.sh exited non-zero"
fi

# ----------------------------------------------------------------------------
# 14. Sanity-check the restore
# ----------------------------------------------------------------------------
if [[ -x "$DOTFILES_DIR/_scripts/verify-restore.sh" ]]; then
    echo
    info "Running verify-restore.sh..."
    "$DOTFILES_DIR/_scripts/verify-restore.sh" || warn "verify-restore reported failures - see above"
fi

# ----------------------------------------------------------------------------
# 15. Permissions and system extensions checklist
# ----------------------------------------------------------------------------
if [[ -x "$DOTFILES_DIR/_scripts/permissions-checklist.sh" ]]; then
    echo
    info "Printing permissions/system extensions checklist"
    "$DOTFILES_DIR/_scripts/permissions-checklist.sh" || warn "permissions-checklist.sh exited non-zero"
fi

# ----------------------------------------------------------------------------
# Done
# ----------------------------------------------------------------------------
cat <<EOF

$(success "Fresh bootstrap complete.")

Remaining manual checks:
  1. Sign into iCloud, App Store, GitHub Desktop (if not already)
  2. Confirm 1Password SSH Agent is enabled if the checklist reported it missing
  3. Approve anything listed by _scripts/permissions-checklist.sh
  4. Open VS Code and let Settings Sync restore settings/extensions
  5. Restart shell or: exec zsh
  6. If anything failed in verify-restore.sh above, re-run: _scripts/verify-restore.sh
EOF
