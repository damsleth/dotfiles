#!/usr/bin/env bash
# pull-all — git pull every repo directly under ~/code (or $CODE_DIR).
#
# Usage: pull-all [-j N]
#   -j N    run up to N pulls in parallel (default: 6)
#
# Skips: non-git dirs, repos with a dirty worktree, detached HEAD, or no upstream.

set -uo pipefail

CODE_DIR="${CODE_DIR:-$HOME/code}"
JOBS=6

while getopts ":j:h" opt; do
  case "$opt" in
    j) JOBS="$OPTARG" ;;
    h) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option" >&2; exit 2 ;;
  esac
done

if [ -t 1 ]; then
  C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'; C_RED=$'\e[31m'; C_GRN=$'\e[32m'
  C_YEL=$'\e[33m'; C_BLU=$'\e[34m'; C_RST=$'\e[0m'
else
  C_BOLD=; C_DIM=; C_RED=; C_GRN=; C_YEL=; C_BLU=; C_RST=
fi

[ -d "$CODE_DIR" ] || { echo "CODE_DIR does not exist: $CODE_DIR" >&2; exit 1; }

pull_one() {
  local repo="$1"
  local name
  name="$(basename "$repo")"

  if [ ! -d "$repo/.git" ]; then
    printf "%s[skip]%s %-25s not a git repo\n" "$C_DIM" "$C_RST" "$name"
    return 0
  fi

  local branch
  branch="$(git -C "$repo" symbolic-ref --short -q HEAD || true)"
  if [ -z "$branch" ]; then
    printf "%s[skip]%s %-25s detached HEAD\n" "$C_YEL" "$C_RST" "$name"
    return 0
  fi

  if ! git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    printf "%s[skip]%s %-25s no upstream for %s\n" "$C_YEL" "$C_RST" "$name" "$branch"
    return 0
  fi

  if ! git -C "$repo" diff --quiet || ! git -C "$repo" diff --cached --quiet; then
    printf "%s[skip]%s %-25s dirty worktree\n" "$C_YEL" "$C_RST" "$name"
    return 0
  fi

  local out rc
  out="$(git -C "$repo" pull --ff-only 2>&1)"
  rc=$?
  if [ $rc -ne 0 ]; then
    printf "%s[fail]%s %-25s %s\n" "$C_RED" "$C_RST" "$name" "$(echo "$out" | tail -n1)"
    return 1
  fi

  if echo "$out" | grep -q "Already up to date"; then
    printf "%s[ ok ]%s %-25s up to date (%s)\n" "$C_DIM" "$C_RST" "$name" "$branch"
  else
    local summary
    summary="$(echo "$out" | grep -E '^\s*[0-9]+ files? changed' | tail -n1)"
    [ -z "$summary" ] && summary="updated"
    printf "%s[ ok ]%s %-25s %s (%s)\n" "$C_GRN" "$C_RST" "$name" "$summary" "$branch"
  fi
}

export -f pull_one
export C_BOLD C_DIM C_RED C_GRN C_YEL C_BLU C_RST

printf "%spull-all%s  %s(code=%s, jobs=%s)%s\n" \
  "$C_BOLD" "$C_RST" "$C_DIM" "$CODE_DIR" "$JOBS" "$C_RST"

mapfile -t repos < <(find "$CODE_DIR" -mindepth 1 -maxdepth 1 -type d -not -name '.*' | sort)

if command -v xargs >/dev/null 2>&1 && [ "$JOBS" -gt 1 ]; then
  printf '%s\n' "${repos[@]}" | xargs -I{} -P "$JOBS" bash -c 'pull_one "$@"' _ {}
else
  for r in "${repos[@]}"; do pull_one "$r"; done
fi
