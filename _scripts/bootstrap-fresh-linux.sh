#!/usr/bin/env bash
# bootstrap-fresh-linux.sh - first-boot setup for a fresh Debian/Ubuntu/WSL box
#
# SKETCH / first pass - the Linux counterpart to bootstrap-fresh.sh. Where the
# mac script leans on Homebrew + `brew bundle`, this leans on apt + the
# per-language installers (fnm/rustup/pipx) that brew bundle would otherwise
# have provided. Steps that are macOS-only (Xcode CLT, TouchID, `defaults`,
# Dock, permissions checklist) are dropped; everything else reuses the same
# shared restore scripts under _scripts/.
#
# Usage after the repo is cloned (or clone it via step 3 below):
#   ~/Code/dotfiles/_scripts/bootstrap-fresh-linux.sh
#
# Idempotent: every step checks state before acting.
#
# TODO before trusting this on a real box:
#   - Decide whether language managers should come from apt, official installers
#     (as below), or Homebrew-on-Linux. This uses official installers.
#   - secrets-restore.sh assumes the 1Password CLI (`op`) is present + signed in.

set -euo pipefail

# HTTPS so a brand-new box with no SSH key yet can clone (the private repo will
# prompt for a GitHub PAT / use the gh credential helper). clone-repos.sh later
# pulls the personal repos over SSH once the agent is loaded.
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/damsleth/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/Code/dotfiles}"
# Leave empty to skip the hostname step (common on WSL / shared boxes).
HOSTNAME_DEFAULT="${HOSTNAME_DEFAULT:-}"

info()    { printf '\033[1;34m[boot]\033[0m %s\n' "$*"; }
success() { printf '\033[1;32m[ok]\033[0m   %s\n' "$*"; }
warn()    { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
err()     { printf '\033[1;31m[err]\033[0m  %s\n' "$*" >&2; }

# ----------------------------------------------------------------------------
# Sanity check
# ----------------------------------------------------------------------------
if [[ "$(uname -s)" != "Linux" ]]; then
    err "This script is Linux-only. For macOS, run bootstrap-fresh.sh."
    exit 1
fi
if ! command -v apt-get >/dev/null 2>&1; then
    err "This script targets Debian/Ubuntu/WSL (needs apt)."
    exit 1
fi

# Keep sudo warm for the duration (same trick as the mac script).
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &

# ----------------------------------------------------------------------------
# 1. Hostname (optional)
# ----------------------------------------------------------------------------
if [[ -n "$HOSTNAME_DEFAULT" ]] && command -v hostnamectl >/dev/null 2>&1; then
    current_hostname="$(hostnamectl --static 2>/dev/null || echo "")"
    if [[ "$current_hostname" != "$HOSTNAME_DEFAULT" ]]; then
        info "Setting hostname to $HOSTNAME_DEFAULT (was: ${current_hostname:-unset})"
        sudo hostnamectl set-hostname "$HOSTNAME_DEFAULT" || warn "hostnamectl failed (WSL?)"
    else
        success "Hostname already $HOSTNAME_DEFAULT"
    fi
else
    info "Skipping hostname step (HOSTNAME_DEFAULT unset or no hostnamectl)"
fi

# ----------------------------------------------------------------------------
# 2. Base apt prerequisites (what Xcode CLT + brew give you on mac)
# ----------------------------------------------------------------------------
info "Installing base prerequisites via apt"
sudo apt-get update
sudo apt-get install -y \
    git curl ca-certificates gnupg \
    stow build-essential unzip \
    || warn "apt prerequisites reported an issue"
success "Base prerequisites installed"

# ----------------------------------------------------------------------------
# 3. Clone dotfiles
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
# 4. Stow symlinks + Linux apt/snap packages (shared bootstrap.sh)
# ----------------------------------------------------------------------------
# bootstrap.sh auto-detects Linux and runs the apt (bat, snapd) + snap
# (core, msedit) blocks plus the bat->batcat symlink, then stows everything.
if [[ -x "$DOTFILES_DIR/bootstrap.sh" ]]; then
    info "Running bootstrap.sh (stow + Linux packages)"
    "$DOTFILES_DIR/bootstrap.sh"
else
    warn "bootstrap.sh not found or not executable"
fi

# ----------------------------------------------------------------------------
# 5. Prime PATH for the remaining steps
# ----------------------------------------------------------------------------
# Stow just linked ~/.zshrc, but we're in bash - replicate the parts later
# steps need. No /opt/homebrew here (that's the mac path).
info "Priming PATH and version managers for the remaining steps"
export PATH="$HOME/bin:$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.npm-packages/bin:$HOME/go/bin:/usr/local/bin:$PATH"
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

# ----------------------------------------------------------------------------
# 6. Language runtime managers (brew bundle's job on mac)
# ----------------------------------------------------------------------------
# toolchains-restore.sh / lang-restore.sh expect fnm, rustup and pipx to exist.
# Install them here so those scripts aren't no-ops on a fresh box.
if ! command -v pipx >/dev/null 2>&1; then
    info "Installing pipx via apt"
    sudo apt-get install -y pipx && pipx ensurepath || warn "pipx install failed"
fi

if ! command -v fnm >/dev/null 2>&1; then
    info "Installing fnm (official installer, --skip-shell so it won't edit stowed rc)"
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell || warn "fnm install failed"
    # The installer drops the binary in ~/.local/share/fnm but, with
    # --skip-shell, never puts it on PATH. The zsh fnm integration only loads
    # when `command -v fnm` succeeds, so symlink fnm into ~/.local/bin (already
    # exported by the dotfiles) - otherwise Node is unreachable in the user's
    # interactive shell on Linux. Mirrors the bat->batcat link.
    if [[ -x "$HOME/.local/share/fnm/fnm" ]]; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$HOME/.local/share/fnm/fnm" "$HOME/.local/bin/fnm"
    fi
    export PATH="$HOME/.local/bin:$HOME/.local/share/fnm:$PATH"
fi
if command -v fnm >/dev/null 2>&1; then
    eval "$(fnm env --shell bash)"
fi

if ! command -v rustup >/dev/null 2>&1; then
    info "Installing rustup (--no-modify-path so it won't edit stowed rc)"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --no-modify-path || warn "rustup install failed"
    [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
fi

# ----------------------------------------------------------------------------
# 7. Language toolchains (fnm LTS, rustup default, GOPATH)
# ----------------------------------------------------------------------------
if [[ -x "$DOTFILES_DIR/_scripts/toolchains-restore.sh" ]]; then
    info "Restoring language toolchains"
    "$DOTFILES_DIR/_scripts/toolchains-restore.sh" || warn "toolchains-restore.sh exited non-zero"
    if command -v fnm >/dev/null 2>&1; then
        eval "$(fnm env --shell bash)"   # re-eval now that a default Node exists
    fi
fi

# ----------------------------------------------------------------------------
# 8. pipx + npm global packages
# ----------------------------------------------------------------------------
if [[ -x "$DOTFILES_DIR/_scripts/lang-restore.sh" ]]; then
    info "Restoring pipx + npm globals"
    "$DOTFILES_DIR/_scripts/lang-restore.sh" || warn "lang-restore.sh exited non-zero"
fi

# ----------------------------------------------------------------------------
# 9. Secrets from 1Password (if op is installed + signed in)
# ----------------------------------------------------------------------------
if [[ -x "$DOTFILES_DIR/_scripts/secrets-restore.sh" ]]; then
    info "Restoring machine-local secrets from 1Password"
    "$DOTFILES_DIR/_scripts/secrets-restore.sh" || warn "secrets-restore.sh exited non-zero"
fi

# ----------------------------------------------------------------------------
# 10. Clone personal repos referenced by ~/.local/bin symlinks
# ----------------------------------------------------------------------------
if [[ -x "$DOTFILES_DIR/_scripts/clone-repos.sh" ]]; then
    info "Cloning personal repos (hugr, YAAMS, teaminal, ...)"
    "$DOTFILES_DIR/_scripts/clone-repos.sh" || warn "clone-repos.sh exited non-zero (SSH agent loaded?)"
fi

# ----------------------------------------------------------------------------
# 11. Editable-install self-written tools from their ~/code clones
# ----------------------------------------------------------------------------
# Must run AFTER clone-repos.sh (needs the checkouts) and after pipx exists.
if [[ -x "$DOTFILES_DIR/_scripts/tools-restore.sh" ]]; then
    info "Editable-installing local tools (cognitive-ledger, yaams, owa-tools, owa-piggy)"
    "$DOTFILES_DIR/_scripts/tools-restore.sh" || warn "tools-restore.sh exited non-zero"
fi

# ----------------------------------------------------------------------------
# 12. owa-piggy auth - intentionally NOT run here
# ----------------------------------------------------------------------------
# owa-piggy refresh tokens live ~24h, so they can't be staged in this repo and
# still be valid at restore time. Seeding them would mean committing fresh
# tokens via the owa-piggy reseed launchd - spreading tokens across repos and
# adding cross-repo entropy. Run `owa-piggy login` manually after bootstrap.

# ----------------------------------------------------------------------------
# 13. Sanity-check the restore
# ----------------------------------------------------------------------------
if [[ -x "$DOTFILES_DIR/_scripts/verify-restore.sh" ]]; then
    echo
    info "Running verify-restore.sh..."
    "$DOTFILES_DIR/_scripts/verify-restore.sh" || warn "verify-restore reported failures - see above"
fi

# ----------------------------------------------------------------------------
# Done
# ----------------------------------------------------------------------------
cat <<EOF

$(success "Fresh Linux bootstrap complete.")

Remaining manual checks:
  1. Restart your shell or: exec zsh
  2. If on WSL, confirm systemd is enabled so snap packages (core, msedit) work.
  3. Ensure your SSH key / 1Password SSH agent is loaded if clone-repos.sh skipped repos.
  4. If anything failed in verify-restore.sh above, re-run: _scripts/verify-restore.sh
EOF
