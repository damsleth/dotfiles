#!/usr/bin/env bash
# Public-safety and restore-contract audit for the tracked dotfiles repo.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0

info() { printf '\033[1;34m[audit]\033[0m %s\n' "$*"; }
pass() { printf '\033[1;32m[ok]\033[0m    %s\n' "$*"; }
fail() { printf '\033[1;31m[fail]\033[0m  %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }

cd "$REPO_ROOT"

require_clean_match() {
    local label="$1" pattern="$2" matches
    local exclude="${3:-}"
    matches="$(git grep -nIE "$pattern" -- . ':(exclude)AGENTS.md' ':(exclude)_scripts/audit-public.sh' || true)"
    if [[ -n "$exclude" && -n "$matches" ]]; then
        matches="$(printf '%s\n' "$matches" | grep -Ev "$exclude" || true)"
    fi
    if [[ -n "$matches" ]]; then
        fail "$label"
        printf '%s\n' "$matches" >&2
    else
        pass "$label"
    fi
}

info "Checking shell syntax"
for f in bootstrap.sh _scripts/*.sh; do
    if ! syntax_out="$(bash -n "$f" 2>&1)"; then
        fail "bash syntax: $f"
        printf '%s\n' "$syntax_out" >&2
    fi
done
for f in zsh/.zshrc zsh/.zsh/*.zsh; do
    [[ -f "$f" ]] || continue
    if ! syntax_out="$(zsh -n "$f" 2>&1)"; then
        fail "zsh syntax: $f"
        printf '%s\n' "$syntax_out" >&2
    fi
done
pass "shell syntax"

info "Checking public leak patterns"
require_clean_match "private or routable-looking IP addresses" '(^|[^0-9])(10\.[0-9]|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.)'
require_clean_match "email addresses" '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' 'git@github\.com'
require_clean_match "literal bearer/shared secrets" '(Bearer |shared-secret)'
require_clean_match "personal 1Password refs" 'op://(Employee|Private|Personal|Work)/'

ssh_audit_tmp="$(mktemp "${TMPDIR:-/tmp}/dotfiles-ssh-audit.XXXXXX")"
if git grep -nIE '(HostName[[:space:]]+[^*[:space:]]+|Host[[:space:]]+[^*[:space:]]+)' -- ssh/.ssh >"$ssh_audit_tmp" 2>/dev/null; then
    fail "ssh package contains host-specific config"
    cat "$ssh_audit_tmp" >&2
else
    pass "ssh package is public-safe"
fi
rm -f "$ssh_audit_tmp"

info "Checking package catalog"
catalog="$(awk -F'"' '/^  "/ { split($2, f, "|"); print f[1] }' _scripts/dotfiles-wizard.sh)"
for pkg in $catalog; do
    [[ -d "$pkg" ]] || fail "catalog package missing: $pkg"
done
for d in */; do
    pkg="${d%/}"
    case "$pkg" in
        _*|private) continue ;;
    esac
    if ! printf '%s\n' "$catalog" | grep -qx "$pkg"; then
        fail "top-level package not in catalog: $pkg"
    fi
done
pass "package catalog checked"

info "Checking Stow simulation"
tmp_target="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-audit.XXXXXX")"
trap 'rm -rf "$tmp_target"' EXIT
for pkg in $catalog; do
    stow --simulate \
        --dir="$REPO_ROOT" \
        --target="$tmp_target" \
        --no-folding \
        --ignore='\.DS_Store$' \
        --ignore='^plugins$' \
        --ignore='^\.zsh/local\.zsh$' \
        --ignore='^\.zsh/secrets\.zsh$' \
        "$pkg" >/dev/null 2>&1 || fail "stow simulation failed: $pkg"
done
pass "stow simulation"

if command -v shellcheck >/dev/null 2>&1; then
    info "Checking shellcheck"
    shellcheck -S warning bootstrap.sh _scripts/*.sh || fail "shellcheck"
fi

if [[ $FAIL -eq 0 ]]; then
    pass "public audit passed"
else
    fail "$FAIL audit issue(s)"
fi

exit "$FAIL"
