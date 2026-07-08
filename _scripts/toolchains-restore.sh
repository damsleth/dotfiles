#!/usr/bin/env bash
# toolchains-restore.sh - install language runtimes that brew alone does not cover.

set -euo pipefail

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=1 ;;
        -h|--help)
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown flag: $arg" >&2; exit 2 ;;
    esac
done

export PATH="$HOME/.cargo/bin:$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$PATH"

info() { echo "[tool] $*"; }
warn() { echo "[warn] $*" >&2; }
run_or_show() {
    if [[ $DRY_RUN -eq 1 ]]; then
        info "would run: $*"
    else
        "$@"
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FNM_LIST="$SCRIPT_DIR/fnm-versions.txt"

if command -v fnm >/dev/null 2>&1; then
    installed="$(fnm list 2>/dev/null || true)"
    if [[ -f "$FNM_LIST" ]]; then
        default_version=""
        while IFS= read -r line; do
            line="${line%%#*}"
            line="$(echo "$line" | xargs)"
            [[ -z "$line" ]] && continue

            version="$(awk '{print $1}' <<<"$line")"
            tag="$(awk '{print $2}' <<<"$line")"
            if echo "$installed" | grep -q "$version"; then
                info "fnm: $version already installed"
            else
                info "fnm install $version"
                run_or_show fnm install "$version" || warn "fnm install failed: $version"
            fi

            [[ "$tag" == "default" ]] && default_version="$version"
        done < "$FNM_LIST"

        if [[ -n "$default_version" ]]; then
            info "fnm default $default_version"
            run_or_show fnm default "$default_version" || warn "fnm default failed: $default_version"
        fi
    elif [[ -z "$(echo "$installed" | grep -E 'v[0-9]+\.[0-9]+\.[0-9]+' || true)" ]]; then
        info "fnm: no version list and no installed versions - installing LTS"
        run_or_show fnm install --lts || warn "fnm install --lts failed"
        run_or_show fnm default lts-latest || warn "fnm default lts-latest failed"
    else
        info "fnm: no fnm-versions.txt, at least one version installed - skipping"
    fi

    if command -v corepack >/dev/null 2>&1; then
        info "corepack enable"
        run_or_show corepack enable 2>/dev/null || warn "corepack enable failed (run manually)"
    fi
else
    warn "fnm not on PATH - install via brew bundle first"
fi

if ! command -v rustup >/dev/null 2>&1; then
    info "installing rustup (default stable toolchain, no PATH edits)"
    if [[ $DRY_RUN -eq 1 ]]; then
        info "would install rustup from https://sh.rustup.rs"
    else
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
            | sh -s -- -y --default-toolchain stable --profile minimal --no-modify-path \
            || warn "rustup install failed"
        [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
    fi
else
    info "rustup already installed - skipping"
fi

if [[ $DRY_RUN -eq 1 ]]; then
    info "would mkdir -p $HOME/go/bin"
else
    mkdir -p "$HOME/go/bin"
fi
info "ensured ~/go/bin exists"

info "Toolchain restore complete."
