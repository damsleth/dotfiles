#!/usr/bin/env bash
# wizard.sh — interactive picker for which dotfile packages to install.
#
# Pure bash (works on macOS's bash 3.2), zero dependencies. Navigate with the
# arrow keys (or j/k), space toggles the highlighted package, Enter installs.
# m/r/e pick a preset, a/n select all/none, q quits. Works over SSH and in tmux
# (single-keypress reads, no stty raw mode); falls back to the recommended set
# when there's no TTY (e.g. bootstrap --no-wizard / piped input).
#
# Used by bootstrap.sh on first run. Can also be run directly:
#   _scripts/wizard.sh                 # interactive, prints chosen packages
#   _scripts/wizard.sh --preset rec    # non-interactive, prints a preset's set
#   _scripts/wizard.sh --list          # list all packages and exit
#
# Selected package names are printed to STDOUT, one per line (UI goes to
# STDERR), so callers can do:  pkgs=$(_scripts/wizard.sh) && stow $pkgs
#
# Presets: min (bare essentials) · rec (recommended) · all (everything).

set -euo pipefail

# ── package catalog ─────────────────────────────────────────────────────────
# Fields: key | category | platform(all|macos) | presets(csv) | description
PACKAGES=(
  "zsh|Shell|all|min,rec,all|Zsh config — starship prompt, aliases, functions, completions"
  "vim|Editors|all|min,rec,all|Vim config (~/.vimrc)"
  "nvim|Editors|all|rec,all|Neovim, LazyVim-based (~/.config/nvim)"
  "vscode|Editors|macos|all|VS Code settings/keybindings/snippets (Settings Sync usually owns these)"
  "ghostty|Terminals|all|rec,all|Ghostty terminal config + light/dark theme switcher"
  "kitty|Terminals|all|rec,all|Kitty terminal config + theme switcher"
  "btop|Monitoring|all|rec,all|btop resource monitor theme"
  "trippy|Networking|all|rec,all|trippy (mtr-like traceroute) config"
  "glow|CLI tools|all|rec,all|glow markdown renderer config"
  "lf|CLI tools|all|rec,all|lf file manager config + file previewer"
  "ssh|SSH|all|min,rec,all|SSH client template — Include ~/.ssh/config.d/*, 1Password agent (no keys)"
  "hushlogin|Misc|all|min,rec,all|~/.hushlogin — silences the login banner"
  "karabiner|macOS keyboard|macos|all|Karabiner-Elements complex modifications"
  "skhd|macOS keyboard|macos|all|skhd hotkey daemon (opt+space window toggle, etc.)"
)

# Default to the host OS so a standalone run shows the right packages; callers
# (bootstrap.sh) pass --platform explicitly.
PLATFORM="$(uname -s)"
MODE="interactive"   # interactive | print-preset | list
PRESET="rec"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform) PLATFORM="${2:-all}"; shift 2 ;;
    --platform=*) PLATFORM="${1#*=}"; shift ;;
    --preset)   MODE="print-preset"; PRESET="${2:-rec}"; shift 2 ;;
    --preset=*) MODE="print-preset"; PRESET="${1#*=}"; shift ;;
    --list)     MODE="list"; shift ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 0 ;;
    *) echo "wizard: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

# Normalize platform to all|macos (anything not macOS is treated as "all" but
# macOS-only packages are filtered out).
case "$PLATFORM" in macos|darwin|Darwin) PLATFORM="macos" ;; *) PLATFORM="other" ;; esac

# ── field helpers ────────────────────────────────────────────────────────────
field() { printf '%s' "$(printf '%s' "$1" | cut -d'|' -f"$2")"; }   # field "$line" N (no trailing newline)

# Indices of packages visible on this platform.
VISIBLE=()
i=0
for line in "${PACKAGES[@]}"; do
  plat="$(field "$line" 3)"
  if [[ "$plat" == "macos" && "$PLATFORM" != "macos" ]]; then :; else VISIBLE+=("$i"); fi
  i=$((i+1))
done

preset_has() { case ",$1," in *,"$2",*) return 0 ;; *) return 1 ;; esac; }

# ── non-interactive modes ────────────────────────────────────────────────────
if [[ "$MODE" == "list" ]]; then
  printf '%-12s %-16s %-8s %s\n' KEY CATEGORY PLATFORM DESCRIPTION >&2
  for idx in "${VISIBLE[@]}"; do
    line="${PACKAGES[$idx]}"
    printf '%-12s %-16s %-8s %s\n' "$(field "$line" 1)" "$(field "$line" 2)" "$(field "$line" 3)" "$(field "$line" 5)" >&2
  done
  exit 0
fi

if [[ "$MODE" == "print-preset" ]]; then
  case "$PRESET" in min|rec|all) ;; minimal) PRESET=min ;; recommended) PRESET=rec ;; everything) PRESET=all ;;
    *) echo "wizard: unknown preset '$PRESET' (use min|rec|all)" >&2; exit 2 ;; esac
  for idx in "${VISIBLE[@]}"; do
    line="${PACKAGES[$idx]}"
    preset_has "$(field "$line" 4)" "$PRESET" && field "$line" 1 && echo
  done
  exit 0
fi

# ── interactive checklist ────────────────────────────────────────────────────
# Bail to the recommended preset if there's no TTY to prompt on.
# (WIZARD_FORCE_TTY=1 forces the interactive loop over a pipe, for testing.)
if [[ "${WIZARD_FORCE_TTY:-0}" != "1" && ( ! -t 0 || ! -t 1 ) ]]; then
  for idx in "${VISIBLE[@]}"; do
    line="${PACKAGES[$idx]}"
    preset_has "$(field "$line" 4)" rec && field "$line" 1 && echo
  done
  exit 0
fi

# selection state, parallel to PACKAGES (1 = selected)
SEL=()
for line in "${PACKAGES[@]}"; do SEL+=("0"); done

apply_preset() {  # apply_preset min|rec|all
  local p="$1" idx line
  for idx in "${VISIBLE[@]}"; do
    line="${PACKAGES[$idx]}"
    if preset_has "$(field "$line" 4)" "$p"; then SEL[$idx]=1; else SEL[$idx]=0; fi
  done
}
set_all() { local idx; for idx in "${VISIBLE[@]}"; do SEL[$idx]="$1"; done; }

apply_preset rec   # start on the recommended set

if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
  C_DIM="$(tput dim 2>/dev/null || true)"; C_B="$(tput bold 2>/dev/null || true)"
  C_R="$(tput sgr0 2>/dev/null || true)"; C_GRN="$(tput setaf 2 2>/dev/null || true)"
  C_CYN="$(tput setaf 6 2>/dev/null || true)"; C_REV="$(tput rev 2>/dev/null || true)"
  COLS="$(tput cols 2>/dev/null || echo 80)"
else
  C_DIM=""; C_B=""; C_R=""; C_GRN=""; C_CYN=""; C_REV=""; COLS=80
fi
# Home + clear-to-end (less flicker than a full clear on each keypress).
CLEAR=$'\e[H\e[J'
NCOUNT=${#VISIBLE[@]}
# Budget for the description column so long lines truncate instead of wrapping.
DESC_MAX=$(( COLS - 30 )); (( DESC_MAX < 20 )) && DESC_MAX=20

render() {  # render <cursor-position 0..NCOUNT-1>
  local cur="$1" last_cat="" pos=0 idx line key cat desc box mark sel=0 i
  for i in "${VISIBLE[@]}"; do [[ "${SEL[$i]}" == "1" ]] && sel=$((sel+1)); done
  printf '%s' "$CLEAR" >&2
  {
    printf '%s┌─ dotfiles installer ──────────────────────────────┐%s\n' "$C_CYN" "$C_R"
    printf '  %s↑/↓%s move   %sspace%s toggle   %sEnter%s install   %sq%s quit\n\n' \
           "$C_B" "$C_R" "$C_B" "$C_R" "$C_B" "$C_R" "$C_B" "$C_R"
    for idx in "${VISIBLE[@]}"; do
      line="${PACKAGES[$idx]}"; cat="$(field "$line" 2)"
      key="$(field "$line" 1)"; desc="$(field "$line" 5)"
      [[ "$cat" != "$last_cat" ]] && { printf '  %s%s%s\n' "$C_B" "$cat" "$C_R"; last_cat="$cat"; }
      (( ${#desc} > DESC_MAX )) && desc="${desc:0:DESC_MAX-1}…"
      if [[ "${SEL[$idx]}" == "1" ]]; then box="${C_GRN}[x]${C_R}"; else box="[ ]"; fi
      if (( pos == cur )); then mark="${C_CYN}›${C_R}"; else mark=" "; fi
      if (( pos == cur )); then
        printf '  %s %s %s%-10s%s %s%s%s\n' "$mark" "$box" "${C_REV}${C_B}" "$key" "$C_R" "$C_DIM" "$desc" "$C_R"
      else
        printf '  %s %s %s%-10s%s %s%s%s\n' "$mark" "$box" "$C_B" "$key" "$C_R" "$C_DIM" "$desc" "$C_R"
      fi
      pos=$((pos+1))
    done
    printf '\n  %s%d selected%s of %d    %spresets:%s [m]in [r]ec [e]very  [a]ll [n]one\n' \
           "$C_GRN" "$sel" "$C_R" "$NCOUNT" "$C_DIM" "$C_R"
    printf '%s└────────────────────────────────────────────────────┘%s' "$C_CYN" "$C_R"
  } >&2
}

# Read one keystroke into KEY, decoding arrow-key escape sequences.
read_key() {
  local k rest
  IFS= read -rsn1 k 2>/dev/null || return 1
  if [[ "$k" == $'\e' ]]; then
    IFS= read -rsn2 -t 1 rest 2>/dev/null   # tail of an escape seq (e.g. "[A")
    k="$k$rest"
  fi
  KEY="$k"
}

cur=0
printf '\e[?25l' >&2                                   # hide cursor
trap 'printf "\e[?25h\n" >&2' EXIT                     # restore on any exit
while true; do
  render "$cur"
  read_key || break
  case "$KEY" in
    $'\e[A'|k|K) cur=$(( (cur - 1 + NCOUNT) % NCOUNT )) ;;   # up
    $'\e[B'|j|J) cur=$(( (cur + 1) % NCOUNT )) ;;            # down
    $'\e[H'|g)   cur=0 ;;                                    # home / top
    $'\e[F'|G)   cur=$(( NCOUNT - 1 )) ;;                    # end / bottom
    ' ')         idx="${VISIBLE[$cur]}"; SEL[$idx]=$(( 1 - ${SEL[$idx]} )) ;;  # toggle
    m|M) apply_preset min ;;
    r|R) apply_preset rec ;;
    e|E) apply_preset all ;;
    a|A) set_all 1 ;;
    n|N) set_all 0 ;;
    q|Q) printf '\n' >&2; echo "wizard: cancelled" >&2; exit 130 ;;
    ''|$'\r'|$'\n')  break ;;        # Enter → install
    *)   : ;;            # ignore anything else
  esac
done

# ── emit selection ───────────────────────────────────────────────────────────
any=0
for idx in "${VISIBLE[@]}"; do
  if [[ "${SEL[$idx]}" == "1" ]]; then field "${PACKAGES[$idx]}" 1; echo; any=1; fi
done
[[ "$any" == "0" ]] && echo "wizard: nothing selected" >&2
exit 0
