#!/usr/bin/env bash
# clone-repos.sh - clone repos listed in a repos.txt into ~/code/<name>.
# Idempotent: existing clones are skipped (use --pull to refresh).
#
# Usage:
#   _scripts/clone-repos.sh           # clone missing
#   _scripts/clone-repos.sh --pull    # also git pull existing
#   _scripts/clone-repos.sh --dry-run # print plan
#
# Your list of repos is personal, so it's NOT in this public repo. The list is
# resolved in order:
#   1. $REPOS_FILE (if set)
#   2. $DOTFILES_PRIVATE/_scripts/repos.txt   (private overlay)
#   3. <repo>/private/_scripts/repos.txt      (in-tree overlay)
#   4. _scripts/repos.txt                     (if you keep one locally)
# If none exist, this is a no-op (see repos.txt.example for the format).
#
# Requires a working SSH agent / 1Password SSH agent (see ssh/.ssh/config).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DOTFILES_PRIVATE="${DOTFILES_PRIVATE:-$DOTFILES_DIR/private}"
CODE_DIR="${CODE_DIR:-$HOME/code}"
PULL=0
DRY_RUN=0

for arg in "$@"; do
    case "$arg" in
        --pull) PULL=1 ;;
        --dry-run|-n) DRY_RUN=1 ;;
        *) echo "unknown flag: $arg" >&2; exit 2 ;;
    esac
done

# Resolve the repos list from the first location that exists.
REPOS_FILE="${REPOS_FILE:-}"
if [[ -z "$REPOS_FILE" ]]; then
    for cand in "$DOTFILES_PRIVATE/_scripts/repos.txt" "$SCRIPT_DIR/repos.txt"; do
        [[ -f "$cand" ]] && { REPOS_FILE="$cand"; break; }
    done
fi
if [[ -z "$REPOS_FILE" || ! -f "$REPOS_FILE" ]]; then
    echo "[skip] no repos.txt found (set \$REPOS_FILE or add one to the private overlay; see repos.txt.example)"
    exit 0
fi
mkdir -p "$CODE_DIR"

info()    { echo "[clone] $*"; }
success() { echo "[ok]    $*"; }
skip()    { echo "[skip]  $*"; }
warn()    { echo "[warn]  $*"; }

# Pre-seed github.com host key so BatchMode SSH (and the first interactive
# clone) doesn't prompt or get rejected. Idempotent.
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
if ! ssh-keygen -F github.com >/dev/null 2>&1; then
    info "Seeding ~/.ssh/known_hosts with github.com host keys"
    ssh-keyscan -H github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null || \
        warn "ssh-keyscan github.com failed - first clone may prompt"
fi

# 1Password SSH agent gate. clone-repos uses git@github.com:* URLs which require
# a working agent. On a fresh Mac the user has to (a) open 1Password, (b) sign in,
# (c) enable Developer -> SSH Agent before the socket appears. If we run before
# that, every clone fails. Block once and let the user fix it before retrying.
agent_sock="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
if [[ "$(uname -s)" == "Darwin" ]] && [[ $DRY_RUN -eq 0 ]] && [[ ! -S "$agent_sock" ]]; then
    cat <<'EOF'

  [pause] 1Password SSH Agent socket not found.
    git@github.com clones need it. To enable:
      1. Open 1Password, sign in, unlock.
      2. Settings -> Developer -> turn on "Use the SSH agent".
      3. Confirm the unlock prompts on first use.

EOF
    read -rp "  Press Enter when the agent is enabled (or Ctrl-C to abort): " _
    if [[ ! -S "$agent_sock" ]]; then
        warn "Agent socket still missing - clones will likely fail. Continuing anyway."
    fi
fi

while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | xargs)"
    [[ -z "$line" ]] && continue

    spec="$(echo "$line" | awk '{print $1}')"
    override="$(echo "$line" | awk '{print $2}')"

    repo_name="${spec##*/}"
    target="$CODE_DIR/${override:-$repo_name}"
    url="git@github.com:${spec}.git"

    if [[ -d "$target/.git" ]]; then
        if [[ $PULL -eq 1 ]]; then
            info "pulling $target"
            if [[ $DRY_RUN -eq 1 ]]; then
                echo "[dry] git -C $target pull --ff-only"
            else
                git -C "$target" pull --ff-only || warn "pull failed for $target"
            fi
        else
            skip "$target (already cloned)"
        fi
        continue
    fi

    if [[ -e "$target" ]]; then
        warn "$target exists but is not a git repo - skipping"
        continue
    fi

    info "cloning $url -> $target"
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[dry] git clone $url $target"
        success "$target"
    elif git clone "$url" "$target"; then
        success "$target"
    else
        warn "clone failed: $url (check SSH auth / repo visibility)"
    fi
done < "$REPOS_FILE"
