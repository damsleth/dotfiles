#!/usr/bin/env bash
# verify-restore.sh - sanity-check that a fresh-machine restore actually worked.
# Exits non-zero if any check fails. Safe to re-run.

set -uo pipefail

# Match the PATH a fresh zsh would build, so we can test that tools are reachable
# even when this script is invoked from non-login contexts (eg. bootstrap-fresh.sh).
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$PATH"

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/Code/dotfiles}"
FAIL=0

# Several checks below are macOS-specific (Homebrew, mas/App Store, the macOS
# 1Password SSH agent socket path). On Debian/Ubuntu those would always "fail"
# since packages come from apt + snap, so they are skipped there.
IS_MACOS=0
[[ "$(uname -s)" == "Darwin" ]] && IS_MACOS=1

pass() { printf '\033[1;32m[ok]\033[0m   %s\n' "$*"; }
fail() { printf '\033[1;31m[fail]\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
info() { printf '\033[1;34m[chk]\033[0m  %s\n' "$*"; }

check_cmd() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then pass "$cmd on PATH"
    else fail "$cmd missing from PATH"
    fi
}

if [[ $IS_MACOS -eq 1 ]]; then
    info "Homebrew packages match Brewfile"
    if [[ -f "$DOTFILES_DIR/Brewfile" ]] && command -v brew >/dev/null 2>&1; then
        if brew bundle check --file="$DOTFILES_DIR/Brewfile" >/dev/null 2>&1; then
            pass "brew bundle check clean"
        else
            fail "brew bundle check found missing items - run: brew bundle --file=$DOTFILES_DIR/Brewfile"
        fi
    else
        fail "Brewfile or brew not found"
    fi
else
    info "Homebrew/Brewfile check skipped (macOS only; Linux uses apt + snap)"
fi

info "Core CLIs on PATH"
for c in stow git gh op nvim jq fzf rg fd bat eza btop starship; do
    check_cmd "$c"
done

info "Secrets + accounts"
mas_signed_in() {
    # `mas account` was removed in v2 and `mas config`'s "store" field is the
    # ISO country code (NO = Norway, not "not signed in"). `mas list` proves
    # sign-in conclusively; fall back to the iTunes account plist for fresh
    # machines with no purchases yet.
    mas list 2>/dev/null | grep -q . && return 0
    defaults read ~/Library/Preferences/MobileMeAccounts.plist 2>/dev/null \
        | grep -q "AccountID =" && return 0
    return 1
}
# ~/.zsh/.env is restored on every platform.
if [[ -f "$HOME/.zsh/.env" ]]; then
    pass "$HOME/.zsh/.env present"
else
    fail "$HOME/.zsh/.env missing (run: _scripts/secrets-restore.sh)"
fi
if [[ $IS_MACOS -eq 1 ]]; then
    if command -v mas >/dev/null 2>&1 && mas_signed_in; then
        pass "mas signed in"
    else
        fail "mas is not signed in - App Store apps may be missing"
    fi
    if [[ -S "$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock" ]]; then
        pass "1Password SSH agent socket present"
    else
        fail "1Password SSH agent socket missing"
    fi
fi

info "Personal CLIs on PATH"
for c in did-cli owa-piggy owa-cal owa-mail hugr yaams teaminal mark; do
    check_cmd "$c"
done

info "SSH config + GitHub auth"
if [[ -L "$HOME/.ssh/config" ]] || [[ -f "$HOME/.ssh/config" ]]; then
    pass "$HOME/.ssh/config present"
else
    fail "$HOME/.ssh/config missing"
fi
if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
    pass "$HOME/.ssh/id_ed25519 present"
else
    fail "$HOME/.ssh/id_ed25519 missing (run: _scripts/secrets-restore.sh)"
fi
# BatchMode=yes refuses unknown hosts, so pre-seed github.com first.
if ! ssh-keygen -F github.com >/dev/null 2>&1; then
    ssh-keyscan -H github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
fi
if ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    pass "github SSH auth ok"
else
    fail "github SSH auth not working (load private key into 1Password agent)"
fi

info "pipx + npm global packages installed"
if command -v pipx >/dev/null 2>&1 && [[ -f "$DOTFILES_DIR/_scripts/pipx-packages.txt" ]]; then
    installed="$(pipx list --short 2>/dev/null | awk '{print $1}')"
    while IFS= read -r pkg; do
        pkg="${pkg%%#*}"; pkg="$(echo "$pkg" | xargs)"
        [[ -z "$pkg" ]] && continue
        if echo "$installed" | grep -qx "$pkg"; then
            pass "pipx $pkg"
        else
            fail "pipx $pkg missing"
        fi
    done < "$DOTFILES_DIR/_scripts/pipx-packages.txt"
fi
if command -v npm >/dev/null 2>&1 && [[ -f "$DOTFILES_DIR/_scripts/npm-globals.txt" ]]; then
    installed_npm="$(npm list -g --depth=0 --json 2>/dev/null | jq -r '.dependencies | keys[]' 2>/dev/null)"
    while IFS= read -r pkg; do
        pkg="${pkg%%#*}"; pkg="$(echo "$pkg" | xargs)"
        [[ -z "$pkg" ]] && continue
        if echo "$installed_npm" | grep -qx "$pkg"; then
            pass "npm $pkg"
        else
            fail "npm $pkg missing"
        fi
    done < "$DOTFILES_DIR/_scripts/npm-globals.txt"
fi

info "Personal repos cloned"
for d in hugr YAAMS cognitive-ledger owa-tools owa-piggy teaminal homebrew-tap; do
    if [[ -d "$HOME/code/$d/.git" ]]; then pass "$HOME/code/$d"
    else fail "$HOME/code/$d missing (run: _scripts/clone-repos.sh)"
    fi
done

echo
if [[ $FAIL -eq 0 ]]; then
    printf '\033[1;32m[done] all checks passed\033[0m\n'
    exit 0
else
    printf '\033[1;31m[done] %d check(s) failed\033[0m\n' "$FAIL"
    exit 1
fi
