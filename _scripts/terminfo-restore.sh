#!/usr/bin/env bash
# terminfo-restore.sh - compile bundled terminfo entries into ~/.terminfo.
#
# Some terminals ship a custom terminfo entry that isn't in the base ncurses
# database, so `TERM` ends up naming an entry the system doesn't know about.
# The classic symptom is kitty's `xterm-kitty`:
#
#     $ reset
#     reset: unknown terminal type xterm-kitty
#     Terminal type?
#
# ...which also breaks clear/tput/tmux/less and `ssh`-ing into hosts that lack
# the entry. kitty installs its terminfo per-app (macOS) or via a distro package
# (Linux), neither of which is guaranteed on a fresh box, so we carry the source
# here and compile it into the per-user database ourselves.
#
# ~/.terminfo is a live, tool-written directory (tic writes here whenever you add
# a terminal), so it is deliberately NOT a stow package - stow would fold it into
# a symlink and future `tic` runs would scribble into this repo. We just tic.
#
# Sources live in _scripts/terminfo/*.terminfo (plain terminfo source, one or
# more entries per file). Add a terminal by dropping its source there.
#
# Idempotent: tic overwrites in place, so re-running is safe.

set -euo pipefail

info() { printf '\033[1;34m[term]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/terminfo"

if ! command -v tic >/dev/null 2>&1; then
    # tic ships with ncurses (macOS built-in; Debian/Ubuntu: `ncurses-bin`).
    warn "tic not found - install ncurses tools, then re-run. Skipping."
    exit 0
fi

if [[ ! -d "$SRC_DIR" ]]; then
    warn "no terminfo sources at $SRC_DIR - nothing to do."
    exit 0
fi

shopt -s nullglob
sources=("$SRC_DIR"/*.terminfo)
shopt -u nullglob

if [[ ${#sources[@]} -eq 0 ]]; then
    warn "no *.terminfo files in $SRC_DIR - nothing to do."
    exit 0
fi

for src in "${sources[@]}"; do
    name="$(basename "$src")"
    # -x: allow user-defined (extended) capabilities kitty/etc. rely on.
    # -o: write into the per-user database, no root needed.
    # Filter tic's benign "older tic versions..." note; keep any real error and
    # check tic's own exit status via PIPESTATUS (grep's status is unreliable
    # since it "fails" whenever every line was filtered out).
    tic -x -o "$HOME/.terminfo" "$src" 2>&1 \
        | grep -vF 'older tic versions may treat the description field as an alias' >&2 || true
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        warn "tic failed for $name"
        exit 1
    fi
    info "compiled $name -> ~/.terminfo"
done

info "Terminfo restore complete."
