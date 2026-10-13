#!/usr/bin/env bash
# repo-sync — report status of every git repo under ~/code and fast-forward-pull the clean ones.
#
# Pulls only when a repo is on a branch with an upstream AND the worktree is clean,
# using `git pull --ff-only` (never creates a merge commit; fails loudly if diverged).
# Dirty / detached / no-upstream / deselected repos are reported and left untouched.

set -uo pipefail

CODE_DIR="${CODE_DIR:-$HOME/code}"
CONFIG_FILE="${REPO_SYNC_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/repo-sync/config.json}"
STATE_FILE="${REPO_SYNC_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/repo-sync/state.json}"
mkdir -p "$(dirname "$CONFIG_FILE")" "$(dirname "$STATE_FILE")"
DRY_RUN=0
CONFIGURE=0

usage() {
  cat <<EOF
repo-sync — status + fast-forward pull for every git repo under \$CODE_DIR

Usage: repo-sync [-n|--dry-run] [-c|--configure] [-h|--help]
  -n, --dry-run     report status only; never pull
  -c, --configure   interactive tree picker (↑/↓ or j/k move, space toggle, q save & quit)
                    toggling a folder row selects/deselects every repo beneath it
  -h, --help        this help

Files (override with env):
  ~/.config/repo-sync/config.json       REPO_SYNC_CONFIG  repos deselected from the sync
  ~/.local/state/repo-sync/state.json  REPO_SYNC_STATE   last-sync timestamp + per-repo state, rewritten every run

Env: CODE_DIR (default: ~/code)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--dry-run) DRY_RUN=1 ;;
    -c|--configure) CONFIGURE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown arg: %s (see --help)\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

command -v jq >/dev/null || { printf 'repo-sync needs jq (brew install jq)\n' >&2; exit 1; }
[ -d "$CODE_DIR" ] || { printf 'CODE_DIR does not exist: %s\n' "$CODE_DIR" >&2; exit 1; }

if [ -t 1 ]; then
  C_DIM=$'\e[2m'; C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YEL=$'\e[33m'; C_BLU=$'\e[34m'; C_RST=$'\e[0m'
else
  C_DIM=; C_RED=; C_GRN=; C_YEL=; C_BLU=; C_RST=
fi

# Discover repos: find .git dirs, prune the usual noise + salvaged .git.broken-* backups.
discover_repos() {
  find "$CODE_DIR" \
      \( -path '*/node_modules' -o -name '.git.broken-*' \) -prune -o \
      -type d -name .git -print0 2>/dev/null |
    while IFS= read -r -d '' gitdir; do
      repo="$(dirname "$gitdir")"; printf '%s\n' "${repo#"$CODE_DIR"/}"
    done | LC_ALL=C sort
}

mapfile -t REPOS < <(discover_repos)
[ "${#REPOS[@]}" -gt 0 ] || { printf 'no git repos under %s\n' "$CODE_DIR" >&2; exit 1; }

# config: store the *deselected* repos, so new clones join the sync by default.
declare -A EXCLUDED=()
if [ -f "$CONFIG_FILE" ]; then
  while IFS= read -r rel; do [ -n "$rel" ] && EXCLUDED["$rel"]=1; done \
    < <(jq -r '.excluded[]? // empty' "$CONFIG_FILE" 2>/dev/null)
fi

# ---------------------------------------------------------------- --configure
configure() {
  local i p k row typ n=${#REPOS[@]}
  local -a sel=()
  local -A ridx=() isdir=() beneath=()

  for i in "${!REPOS[@]}"; do
    row="${REPOS[i]}"; ridx["$row"]=$i
    [ -n "${EXCLUDED[$row]:-}" ] && sel[i]=0 || sel[i]=1
    p="$row"
    while [[ "$p" == */* ]]; do p="${p%/*}"; isdir["$p"]=1; beneath["$p"]+="$i "; done
  done
  # a repo that is itself a folder counts as a member of its own folder row
  for row in "${!isdir[@]}"; do
    [ -n "${ridx[$row]:-}" ] && beneath["$row"]+="${ridx[$row]} "
  done

  # Tree rows: one row per ancestor folder + one per repo. A repo that is also a
  # folder (e.g. BRKH/ISOFAKS) gets both, so it can still be picked on its own.
  # Sort on the path with '/' → \001 and a \001 suffix on repo rows, so parents
  # sort before their children and no sibling ("a/b-x") splits a subtree ("a/b/*").
  local -a rows=()
  mapfile -t rows < <(
    for i in "${!REPOS[@]}"; do
      p="${REPOS[i]}"
      printf '%s\001\tr\t%s\n' "${p//\//$'\001'}" "$p"
      while [[ "$p" == */* ]]; do p="${p%/*}"; printf '%s\td\t%s\n' "${p//\//$'\001'}" "$p"; done
    done | LC_ALL=C sort -u -t$'\t' -k1,1 | cut -f2-
  )

  local nrows=${#rows[@]} cur=0 top=0 h key rest
  local -a rdepth=() rlabel=() rmem=()
  for (( i=0; i<nrows; i++ )); do
    typ="${rows[i]%%$'\t'*}"; p="${rows[i]#*$'\t'}"
    k="${p//[^\/]/}"; rdepth[i]=${#k}
    if [ "$typ" = d ]; then
      rlabel[i]="${p##*/}/"; rmem[i]="${beneath[$p]}"
    else
      rlabel[i]="${p##*/}"; rmem[i]="${ridx[$p]}"
      [ -n "${isdir[$p]:-}" ] && rdepth[i]=$(( rdepth[i] + 1 ))  # nested under its own folder row
    fi
  done

  stty -echo -icanon 2>/dev/null
  printf '\e[?25l'
  trap 'stty echo icanon 2>/dev/null; printf "\e[?25h\n"' EXIT

  while :; do
    # ponytail: `tput lines` reads fd 1, which is a pipe inside $(...) — it would
    # always answer 24. Ask the tty directly so the list fills the real window.
    h=$(( $({ stty size </dev/tty || echo '24 80'; } 2>/dev/null | cut -d' ' -f1) - 5 ))
    (( h < 3 )) && h=3
    (( cur < top )) && top=$cur
    (( cur >= top + h )) && top=$(( cur - h + 1 ))

    printf '\e[H\e[2J%srepo-sync%s  %s↑/↓ or j/k move · space toggle (folders toggle all) · q save & quit%s\n\n' \
      "$C_BLU" "$C_RST" "$C_DIM" "$C_RST"
    for (( i=top; i<top+h && i<nrows; i++ )); do
      local -a mem=(); read -ra mem <<<"${rmem[i]}"
      local on=0 mark line
      for p in "${mem[@]}"; do (( on += sel[p] )); done
      if   (( on == ${#mem[@]} )); then mark="${C_GRN}[x]${C_RST}"
      elif (( on == 0 ));          then mark="[ ]"
      else                              mark="${C_YEL}[~]${C_RST}"; fi
      line="$(printf '%*s%b %s' $(( rdepth[i] * 2 )) '' "$mark" "${rlabel[i]}")"
      if [ "$i" -eq "$cur" ]; then printf '\e[7m %-70b\e[0m\n' "$line"; else printf ' %b\n' "$line"; fi
    done

    local picked=0
    for (( i=0; i<n; i++ )); do (( picked += sel[i] )); done
    printf '\n%s%d/%d repos selected%s\n' "$C_DIM" "$picked" "$n" "$C_RST"

    IFS= read -rsn1 key || break
    if [ "$key" = $'\e' ]; then
      IFS= read -rsn2 -t 0.01 rest || rest=""
      case "$rest" in '[A') key=k ;; '[B') key=j ;; *) key="" ;; esac
    fi
    case "$key" in
      k) (( cur > 0 )) && cur=$((cur-1)) ;;
      j) (( cur < nrows-1 )) && cur=$((cur+1)) ;;
      ' ')  # folder row toggles every repo beneath it: all selected → off, else → on
        local -a mem=(); read -ra mem <<<"${rmem[cur]}"
        local on=0 want
        for p in "${mem[@]}"; do (( on += sel[p] )); done
        (( on == ${#mem[@]} )) && want=0 || want=1
        for p in "${mem[@]}"; do sel[p]=$want; done ;;
      q) break ;;
    esac
  done

  stty echo icanon 2>/dev/null; printf '\e[?25h'; trap - EXIT

  local -a excl=()
  for (( i=0; i<n; i++ )); do [ "${sel[i]}" -eq 0 ] && excl+=("${REPOS[i]}"); done
  printf '%s\n' "${excl[@]+"${excl[@]}"}" |
    jq -R . | jq -s '{excluded: map(select(. != ""))}' > "$CONFIG_FILE.tmp" &&
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  printf 'wrote %s (%d of %d repos deselected)\n' "$CONFIG_FILE" "${#excl[@]}" "$n"
}

[ "$CONFIGURE" -eq 1 ] && { configure; exit 0; }

# --------------------------------------------------------------------- sync
n_total=0 n_clean=0 n_dirty=0 n_pulled=0 n_uptodate=0 n_skipped=0 n_error=0 n_excluded=0
records="$(mktemp)"; trap 'rm -f "$records"' EXIT

# ponytail: sequential; network-bound pulls over ~90 repos are fine for a manual tool.
# Add `xargs -P` only if this gets annoyingly slow.
for rel in "${REPOS[@]}"; do
  repo="$CODE_DIR/$rel"
  n_total=$((n_total+1))

  branch="$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  dirty_n="$(git -C "$repo" status --porcelain 2>/dev/null | grep -c . || true)"
  [ "${dirty_n:-0}" -gt 0 ] && n_dirty=$((n_dirty+1)) || n_clean=$((n_clean+1))

  # upstream + ahead/behind (no network — uses last known remote-tracking ref)
  upstream="$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  ahead=0 behind=0 ab=""
  if [ -n "$upstream" ]; then
    read -r behind ahead <<<"$(git -C "$repo" rev-list --left-right --count "$upstream"...HEAD 2>/dev/null || echo '0 0')"
    [ "${ahead:-0}" -gt 0 ] && ab="${ab}${C_YEL}↑${ahead}${C_RST}"
    [ "${behind:-0}" -gt 0 ] && ab="${ab}${C_BLU}↓${behind}${C_RST}"
  fi

  # status label
  if [ -z "$branch" ]; then
    state="${C_DIM}detached${C_RST}"; state_p=detached
  elif [ "${dirty_n:-0}" -gt 0 ]; then
    state="${C_YEL}dirty(${dirty_n})${C_RST}"; state_p="dirty"
  else
    state="${C_GRN}clean${C_RST}"; state_p=clean
  fi

  # pull decision
  included=true
  if [ -n "${EXCLUDED[$rel]:-}" ]; then
    included=false
    action="${C_DIM}skip: deselected${C_RST}"; action_p="skip: deselected"; n_excluded=$((n_excluded+1))
  elif [ "$DRY_RUN" -eq 1 ]; then
    action="${C_DIM}(dry-run)${C_RST}"; action_p="dry-run"
  elif [ -z "$branch" ]; then
    action="${C_DIM}skip: detached${C_RST}"; action_p="skip: detached"; n_skipped=$((n_skipped+1))
  elif [ -z "$upstream" ]; then
    action="${C_DIM}skip: no upstream${C_RST}"; action_p="skip: no upstream"; n_skipped=$((n_skipped+1))
  elif [ "${dirty_n:-0}" -gt 0 ]; then
    action="${C_DIM}skip: dirty${C_RST}"; action_p="skip: dirty"; n_skipped=$((n_skipped+1))
  else
    if out="$(git -C "$repo" pull --ff-only --quiet 2>&1)"; then
      if [ "${behind:-0}" -gt 0 ]; then
        action="${C_GRN}pulled${C_RST}"; action_p=pulled; n_pulled=$((n_pulled+1))
      else
        action="${C_DIM}up-to-date${C_RST}"; action_p=up-to-date; n_uptodate=$((n_uptodate+1))
      fi
      behind=0
    else
      err="$(printf '%s' "$out" | head -1)"
      action="${C_RED}pull failed${C_RST}: $err"; action_p="pull failed: $err"; n_error=$((n_error+1))
    fi
  fi

  [ "$included" = true ] && printf '%-42s %-18b %-12b %b\n' "$rel" "$state" "${ab:--}" "$action"

  jq -nc --arg repo "$rel" --arg branch "$branch" --arg upstream "$upstream" \
        --arg state "$state_p" --arg action "$action_p" --argjson included "$included" \
        --argjson dirty "${dirty_n:-0}" --argjson ahead "${ahead:-0}" --argjson behind "${behind:-0}" \
        '{$repo, $branch, $upstream, $state, dirty_files:$dirty, $ahead, $behind, $included, $action}' \
    >> "$records"
done

jq -s --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg mode "$( [ "$DRY_RUN" -eq 1 ] && echo dry-run || echo sync )" --arg cd "$CODE_DIR" \
  --argjson counts "$(jq -nc --argjson t "$n_total" --argjson c "$n_clean" --argjson d "$n_dirty" \
      --argjson p "$n_pulled" --argjson u "$n_uptodate" --argjson s "$n_skipped" \
      --argjson e "$n_error" --argjson x "$n_excluded" \
      '{total:$t,clean:$c,dirty:$d,pulled:$p,up_to_date:$u,skipped:$s,errors:$e,deselected:$x}')" \
  '{last_sync:$ts, mode:$mode, code_dir:$cd, counts:$counts,
    repos: (map({key:.repo, value:(del(.repo))}) | from_entries)}' \
  "$records" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

printf '\n%s%d repos%s: %d clean, %d dirty' "$C_DIM" "$n_total" "$C_RST" "$n_clean" "$n_dirty"
[ "$n_excluded" -gt 0 ] && printf ', %d deselected' "$n_excluded"
[ "$DRY_RUN" -eq 0 ] && printf ' | %d pulled, %d up-to-date, %d skipped, %d errors' \
  "$n_pulled" "$n_uptodate" "$n_skipped" "$n_error"
printf '\n%sstate: %s%s\n' "$C_DIM" "$STATE_FILE" "$C_RST"
