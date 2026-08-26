#!/usr/bin/env bash
# binlink — interactively symlink/unlink CLI executables from ~/code repos into a PATH dir.
#
# Usage: ./binlink.sh
# Env overrides:
#   CODE_DIR  (default: ~/code)
#   BIN_DIR   (default: ~/.local/bin)

set -euo pipefail

CODE_DIR="${CODE_DIR:-$HOME/code}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"

# --- colors -----------------------------------------------------------------
if [ -t 1 ]; then
  C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'; C_RED=$'\e[31m'; C_GRN=$'\e[32m'
  C_YEL=$'\e[33m'; C_BLU=$'\e[34m'; C_CYN=$'\e[36m'; C_RST=$'\e[0m'
else
  C_BOLD=; C_DIM=; C_RED=; C_GRN=; C_YEL=; C_BLU=; C_CYN=; C_RST=
fi

die()  { printf "%s%s%s\n" "$C_RED" "$*" "$C_RST" >&2; exit 1; }
info() { printf "%s%s%s\n" "$C_CYN" "$*" "$C_RST"; }
ok()   { printf "%s%s%s\n" "$C_GRN" "$*" "$C_RST"; }
warn() { printf "%s%s%s\n" "$C_YEL" "$*" "$C_RST"; }

# --- preflight --------------------------------------------------------------
[ -d "$CODE_DIR" ] || die "CODE_DIR does not exist: $CODE_DIR"

if [ ! -d "$BIN_DIR" ]; then
  warn "BIN_DIR does not exist: $BIN_DIR"
  read -r -p "Create it? [Y/n] " yn
  case "${yn:-y}" in
    [Nn]*) die "aborted." ;;
    *)     mkdir -p "$BIN_DIR" || die "could not create $BIN_DIR" ;;
  esac
fi

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "Note: $BIN_DIR is not in \$PATH — links will be created but not callable until you add it." ;;
esac

# --- helpers ----------------------------------------------------------------

# Print executable candidates within a single repo, one per line.
# Candidates: regular files with the executable bit set OR with a shebang,
# excluding common build/venv/dependency dirs.
find_executables() {
  local repo="$1"
  find "$repo" \
    \( -path '*/node_modules' -o -path '*/.git' -o -path '*/.venv' \
       -o -path '*/venv' -o -path '*/target' -o -path '*/dist' \
       -o -path '*/build' -o -path '*/.next' -o -path '*/__pycache__' \
       -o -path '*/.cache' \) -prune -o \
    -type f -print 2>/dev/null \
  | while IFS= read -r f; do
      # executable bit set
      if [ -x "$f" ]; then
        printf "%s\n" "$f"
        continue
      fi
      # has a shebang
      if [ -r "$f" ] && IFS= read -r first <"$f" 2>/dev/null; then
        case "$first" in
          '#!'*) printf "%s\n" "$f" ;;
        esac
      fi
    done
}

# Pick one item from stdin via a numbered menu. Echoes the chosen line on stdout.
# Empty input → returns nonzero. "q" or empty selection → returns nonzero.
pick_one() {
  local prompt="$1"
  local -a items=()
  local line
  while IFS= read -r line; do items+=("$line"); done
  [ "${#items[@]}" -eq 0 ] && return 1

  local i
  for i in "${!items[@]}"; do
    printf "  %s%3d%s  %s\n" "$C_DIM" "$((i+1))" "$C_RST" "${items[$i]}"
  done >&2

  local sel
  while :; do
    printf "%s%s%s " "$C_BOLD" "$prompt" "$C_RST" >&2
    read -r sel || return 1
    [ -z "$sel" ] && return 1
    case "$sel" in
      q|Q) return 1 ;;
      *[!0-9]*|"") warn "enter a number or q to cancel" >&2 ;;
      *)
        if [ "$sel" -ge 1 ] && [ "$sel" -le "${#items[@]}" ]; then
          printf "%s\n" "${items[$((sel-1))]}"
          return 0
        fi
        warn "out of range" >&2
        ;;
    esac
  done
}

# --- actions ----------------------------------------------------------------

do_link() {
  info "Repos under $CODE_DIR:"
  local repo
  repo="$(find "$CODE_DIR" -mindepth 1 -maxdepth 1 -type d -print \
            | sed 's|.*/||' | grep -v '^\.' | sort \
            | pick_one 'Pick a repo (q to cancel):')" || {
    warn "cancelled"; return
  }
  local repo_path="$CODE_DIR/$repo"

  info "\nExecutables in $repo:"
  local exe
  exe="$(find_executables "$repo_path" \
          | sed "s|^$repo_path/||" \
          | sort \
          | pick_one 'Pick an executable (q to cancel):')" || {
    warn "cancelled"; return
  }
  local exe_path="$repo_path/$exe"

  local default_name
  default_name="$(basename "$exe")"
  default_name="${default_name%.sh}"
  default_name="${default_name%.py}"
  default_name="${default_name%.js}"
  default_name="${default_name%.mjs}"

  printf "\n%sLink name in %s%s [%s]: %s" "$C_BOLD" "$BIN_DIR" "$C_RST" "$default_name" ""
  local link_name
  read -r link_name
  link_name="${link_name:-$default_name}"

  local target="$BIN_DIR/$link_name"

  if [ ! -x "$exe_path" ]; then
    warn "$exe is not marked executable."
    read -r -p "chmod +x it? [Y/n] " yn
    case "${yn:-y}" in [Nn]*) ;; *) chmod +x "$exe_path" && ok "chmod +x $exe_path" ;; esac
  fi

  if [ -L "$target" ] || [ -e "$target" ]; then
    if [ -L "$target" ]; then
      local existing
      existing="$(readlink "$target")"
      warn "$target already exists → $existing"
    else
      warn "$target already exists (regular file)"
    fi
    read -r -p "Overwrite? [y/N] " yn
    case "${yn:-n}" in
      [Yy]*) rm -f "$target" ;;
      *) warn "skipped"; return ;;
    esac
  fi

  ln -s "$exe_path" "$target"
  ok "linked: $target → $exe_path"
}

# List symlinks in BIN_DIR whose target resolves under CODE_DIR.
list_managed_links() {
  local f raw_tgt tgt_dir tgt
  for f in "$BIN_DIR"/*; do
    [ -L "$f" ] || continue
    raw_tgt="$(readlink "$f" 2>/dev/null || true)"
    [ -n "$raw_tgt" ] || continue
    case "$raw_tgt" in
      /*) ;;
      *) raw_tgt="$(dirname "$f")/$raw_tgt" ;;
    esac
    tgt_dir="$(cd "$(dirname "$raw_tgt")" 2>/dev/null && pwd -P)" || continue
    tgt="$tgt_dir/$(basename "$raw_tgt")"
    case "$tgt" in
      "$CODE_DIR"/*) printf "%s\t%s\n" "$f" "$tgt" ;;
    esac
  done
}

do_unlink() {
  info "Symlinks in $BIN_DIR pointing into $CODE_DIR:"
  local sel
  sel="$(list_managed_links \
          | awk -F'\t' '{printf "%-30s → %s\n", $1, $2}' \
          | pick_one 'Pick a link to remove (q to cancel):')" || {
    warn "nothing to unlink (or cancelled)"; return
  }
  # recover the link path (everything before " → ")
  local link_path
  link_path="${sel%% → *}"
  link_path="${link_path%"${link_path##*[![:space:]]}"}"   # rtrim
  rm -- "$link_path"
  ok "removed: $link_path"
}

do_list() {
  info "Managed symlinks ($BIN_DIR → $CODE_DIR):"
  local any=0
  while IFS=$'\t' read -r link tgt; do
    any=1
    printf "  %s%s%s → %s\n" "$C_BLU" "$link" "$C_RST" "$tgt"
  done < <(list_managed_links)
  if [ "$any" -eq 0 ]; then
    warn "  (none)"
  fi
}

# --- main loop --------------------------------------------------------------

main_menu() {
  while :; do
    printf "\n%sbinlink%s  %s(code=%s, bin=%s)%s\n" \
      "$C_BOLD" "$C_RST" "$C_DIM" "$CODE_DIR" "$BIN_DIR" "$C_RST"
    printf "  %s1%s  link an executable\n"   "$C_DIM" "$C_RST"
    printf "  %s2%s  unlink a managed link\n" "$C_DIM" "$C_RST"
    printf "  %s3%s  list managed links\n"    "$C_DIM" "$C_RST"
    printf "  %sq%s  quit\n"                   "$C_DIM" "$C_RST"
    printf "%s> %s" "$C_BOLD" "$C_RST"
    local choice
    read -r choice || exit 0
    case "$choice" in
      1) do_link ;;
      2) do_unlink ;;
      3) do_list ;;
      q|Q|"") exit 0 ;;
      *) warn "unknown choice: $choice" ;;
    esac
  done
}

main_menu
