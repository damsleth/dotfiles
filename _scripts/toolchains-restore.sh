#!/usr/bin/env bash
# toolchains-restore.sh - install language runtimes that brew alone doesn't cover.
#
# Brewfile gives you the version managers (fnm, rust, pyenv) but not their content.
# A fresh box with brew bundle complete still has zero Node versions installed,
# no rustup, and no ~/go workspace. This script fills those gaps.
#
# Idempotent: re-running is safe.

set -euo pipefail

# Match the PATH a fresh zsh would build, so brew-installed managers (fnm,
# corepack, rustup) and ~/.cargo/bin entries are reachable when this script
# is invoked from bootstrap-fresh.sh or a bare bash subshell.
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$PATH"

info() { printf '\033[1;34m[tool]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }

# ----------------------------------------------------------------------------
# Node via fnm
# ----------------------------------------------------------------------------
# fnm installs side-by-side Node versions. After a fresh brew install of fnm,
# there are zero versions. Install each version listed in fnm-versions.txt;
# if a line ends with " default", that version becomes the fnm default.
# Falls back to `fnm install --lts` when no list is found.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FNM_LIST="$SCRIPT_DIR/fnm-versions.txt"

if command -v fnm >/dev/null 2>&1; then
    eval "$(fnm env --shell bash)"
    installed="$(fnm list 2>/dev/null || true)"

    if [[ -f "$FNM_LIST" ]]; then
        default_version=""
        while IFS= read -r raw; do
            line="${raw%%#*}"; line="$(echo "$line" | xargs)"
            [[ -z "$line" ]] && continue
            version="$(awk '{print $1}' <<<"$line")"
            tag="$(awk '{print $2}' <<<"$line")"
            if echo "$installed" | grep -q "$version"; then
                info "fnm: $version already installed"
            else
                info "fnm install $version"
                fnm install "$version" || warn "fnm install failed: $version"
            fi
            [[ "$tag" == "default" ]] && default_version="$version"
        done < "$FNM_LIST"
        if [[ -n "$default_version" ]]; then
            info "fnm default $default_version"
            fnm default "$default_version" 2>/dev/null || warn "fnm default failed: $default_version"
        fi
    else
        if [[ -z "$(echo "$installed" | grep -E 'v[0-9]+\.[0-9]+\.[0-9]+' || true)" ]]; then
            info "fnm: no version list and no installed versions - installing LTS"
            fnm install --lts
            fnm default lts-latest 2>/dev/null || true
        else
            info "fnm: no fnm-versions.txt, at least one version already installed - skipping"
        fi
    fi

    if command -v corepack >/dev/null 2>&1; then
        info "corepack enable"
        corepack enable 2>/dev/null || warn "corepack enable failed (run manually)"
    fi
else
    warn "fnm not on PATH - install via brew bundle first"
fi

# ----------------------------------------------------------------------------
# Rust via rustup
# ----------------------------------------------------------------------------
# Brewfile has `brew "rust"` (static toolchain). rustup is the toolchain manager
# that lets you switch between stable/nightly and install components like
# rust-analyzer cleanly. Not in Brewfile because rustup-init is interactive
# and modifies shell rc files by default.
if ! command -v rustup >/dev/null 2>&1; then
    info "installing rustup (default stable toolchain, no PATH edits)"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain stable --profile default --no-modify-path
    # shellcheck source=/dev/null
    [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
else
    info "rustup already installed - skipping"
fi

# ----------------------------------------------------------------------------
# Go workspace
# ----------------------------------------------------------------------------
# brew installs the go binary, but $GOPATH/bin needs to exist before `go install`
# can write into it.
mkdir -p "$HOME/go/bin"
info "ensured ~/go/bin exists"

info "Toolchain restore complete."
