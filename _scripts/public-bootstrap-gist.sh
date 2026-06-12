#!/usr/bin/env bash
# Public-safe bootstrap for a fresh Mac.
#
# Intended gist usage:
#   curl -fsSL https://gist.githubusercontent.com/<you>/<gist-id>/raw/bootstrap-dotfiles.sh | bash
#
# It installs only the prerequisites needed to authenticate with GitHub, clone
# the dotfiles repo, and hand off to _scripts/bootstrap-fresh.sh. The repo is
# public; GitHub auth is still set up so your private overlay can be cloned too.

set -euo pipefail

DOTFILES_REPO="${DOTFILES_REPO:-damsleth/dotfiles}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/Code/dotfiles}"

info() { printf '\033[1;34m[gist]\033[0m %s\n' "$*"; }
pass() { printf '\033[1;32m[ok]\033[0m    %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m  %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[fail]\033[0m  %s\n' "$*" >&2; }

if [[ "$(uname -s)" != "Darwin" ]]; then
    fail "This bootstrap is macOS-only."
    exit 1
fi

sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &

if ! xcode-select -p >/dev/null 2>&1; then
    info "Installing Xcode Command Line Tools"
    xcode-select --install
    until xcode-select -p >/dev/null 2>&1; do sleep 5; done
fi

if ! command -v brew >/dev/null 2>&1; then
    info "Installing Homebrew"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

info "Installing GitHub/bootstrap prerequisites"
brew install git gh stow 1password-cli

if ! gh auth status -h github.com >/dev/null 2>&1; then
    info "Authenticating GitHub CLI (enables cloning your private overlay later)"
    gh auth login -h github.com -p https -s repo,read:org
fi
gh auth setup-git -h github.com

if [[ ! -d "$DOTFILES_DIR/.git" ]]; then
    info "Cloning dotfiles repo to $DOTFILES_DIR"
    mkdir -p "$(dirname "$DOTFILES_DIR")"
    gh repo clone "$DOTFILES_REPO" "$DOTFILES_DIR"
else
    info "dotfiles repo already exists - pulling latest"
    git -C "$DOTFILES_DIR" pull --ff-only
fi

if [[ -x "$DOTFILES_DIR/_scripts/bootstrap-fresh.sh" ]]; then
    pass "Handing off to private bootstrap"
    "$DOTFILES_DIR/_scripts/bootstrap-fresh.sh"
else
    fail "Missing $DOTFILES_DIR/_scripts/bootstrap-fresh.sh"
    exit 1
fi
