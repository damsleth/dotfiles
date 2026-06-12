#!/usr/bin/env bash
# wizard.sh — interactive picker for which dotfile packages to install.
#
# Pure bash (works on macOS's bash 3.2), zero dependencies, no raw-terminal
# mode — so it's safe over SSH, in tmux, and on dumb terminals. You toggle
# packages by number; presets pre-check sensible sets.
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
  C_CYN="$(tput setaf 6 2>/dev/null || true)"; C_YEL="$(tput setaf 3 2>/dev/null || true)"
  CLEAR="$(tput clear 2>/dev/null || true)"
else
  C_DIM=""; C_B=""; C_R=""; C_GRN=""; C_CYN=""; C_YEL=""; CLEAR=""
fi

render() {
  printf '%s' "$CLEAR" >&2
  {
    printf '%s┌─ dotfiles installer ─────────────────────────────────────┐%s\n' "$C_CYN" "$C_R"
    printf '%s  Pick what to install. Type numbers to toggle, then Enter.%s\n\n' "$C_DIM" "$C_R"
    local last_cat="" idx line key cat desc count=0
    # display number → package index map
    NUMMAP=()
    for idx in "${VISIBLE[@]}"; do
      line="${PACKAGES[$idx]}"; cat="$(field "$line" 2)"
      key="$(field "$line" 1)"; desc="$(field "$line" 5)"
      if [[ "$cat" != "$last_cat" ]]; then printf '  %s%s%s\n' "$C_B" "$cat" "$C_R"; last_cat="$cat"; fi
      count=$((count+1)); NUMMAP[$count]=$idx
      if [[ "${SEL[$idx]}" == "1" ]]; then
        printf '    %s[x]%s %2d) %s%-11s%s %s%s%s\n' "$C_GRN" "$C_R" "$count" "$C_B" "$key" "$C_R" "$C_DIM" "$desc" "$C_R"
      else
        printf '    [ ] %2d) %-11s %s%s%s\n' "$count" "$key" "$C_DIM" "$desc" "$C_R"
      fi
    done
    NCOUNT=$count
    local sel=0 idx2; for idx2 in "${VISIBLE[@]}"; do [[ "${SEL[$idx2]}" == "1" ]] && sel=$((sel+1)); done
    printf '\n  %s%d selected%s of %d\n' "$C_GRN" "$sel" "$C_R" "$NCOUNT"
    printf '  %spresets%s [m]inimal  [r]ecommended  [e]verything   %s|%s  [a]ll  [n]one\n' "$C_B" "$C_R" "$C_DIM" "$C_R"
    printf '  %sEnter%s install   %sq%s quit\n' "$C_B" "$C_R" "$C_B" "$C_R"
    printf '%s└──────────────────────────────────────────────────────────┘%s\n' "$C_CYN" "$C_R"
    printf '%s> %s' "$C_YEL" "$C_R"
  } >&2
}

while true; do
  render
  IFS= read -r reply || { echo >&2; break; }
  # trim
  reply="$(printf '%s' "$reply" | tr 'A-Z' 'a-z' | xargs 2>/dev/null || true)"
  [[ -z "$reply" ]] && break   # Enter → install
  for tok in $reply; do
    case "$tok" in
      q|quit) echo >&2; echo "wizard: cancelled" >&2; exit 130 ;;
      m|min|minimal)      apply_preset min ;;
      r|rec|recommended)  apply_preset rec ;;
      e|all-preset|everything) apply_preset all ;;
      a)   set_all 1 ;;
      n|none) set_all 0 ;;
      [0-9]*-[0-9]*)  # range a-b
        lo="${tok%-*}"; hi="${tok#*-}"
        if [[ "$lo" =~ ^[0-9]+$ && "$hi" =~ ^[0-9]+$ ]]; then
          n=$lo; while [[ $n -le $hi ]]; do
            t="${NUMMAP[$n]:-}"; [[ -n "$t" ]] && SEL[$t]=$(( 1 - ${SEL[$t]} )); n=$((n+1));
          done
        fi ;;
      [0-9]*)
        t="${NUMMAP[$tok]:-}"; [[ -n "$t" ]] && SEL[$t]=$(( 1 - ${SEL[$t]} )) ;;
      *) : ;;  # ignore junk
    esac
  done
done

# ── emit selection ───────────────────────────────────────────────────────────
any=0
for idx in "${VISIBLE[@]}"; do
  if [[ "${SEL[$idx]}" == "1" ]]; then field "${PACKAGES[$idx]}" 1; echo; any=1; fi
done
[[ "$any" == "0" ]] && echo "wizard: nothing selected" >&2
exit 0
