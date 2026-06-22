#!/usr/bin/env bash
# dotfiles-wizard.sh — multi-tab TUI for setting up a machine from this repo.
#
# Tab between checklists and pick what to apply in each:
#   Dotfiles   stow packages (zsh, nvim, terminals, …)
#   Homebrew   Brewfile categories            (macOS only)
#   macOS      system defaults by category    (macOS only)
#   npm        global npm packages
#   pipx       pipx packages
#
# Keys:  Tab / ← →   switch tab        ↑ ↓ / j k   move
#        space       toggle item       a / n       all / none (this tab)
#        m / r / e   min/rec/all preset (Dotfiles tab)
#        Enter       apply selections  q           quit
#
# Modes:
#   ./_scripts/dotfiles-wizard.sh                 # full multi-tab wizard, applies on Enter
#   ./_scripts/dotfiles-wizard.sh --dry-run       # full wizard, preview only
#   ./_scripts/dotfiles-wizard.sh --tab dotfiles --emit          # single tab, print keys (used by bootstrap.sh)
#   ./_scripts/dotfiles-wizard.sh --tab dotfiles --emit --preset rec   # non-interactive keys
#   ./_scripts/dotfiles-wizard.sh --list          # list dotfile packages, exit
#
# Pure bash (runs on macOS bash 3.2): no associative arrays, no mapfile.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOOTSTRAP="$REPO_ROOT/bootstrap.sh"
BREWFILE="$REPO_ROOT/Brewfile"
MACOS_SH="$SCRIPT_DIR/macos.sh"
LANG_SH="$SCRIPT_DIR/lang-restore.sh"
NPM_MANIFEST="$SCRIPT_DIR/npm-globals.txt"
PIPX_MANIFEST="$SCRIPT_DIR/pipx-packages.txt"

# ── dotfiles package catalog ──────────────────────────────────────────────────
# key | category | platform(all|macos) | presets(csv of min,rec,all) | description
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

# ── args ────────────────────────────────────────────────────────────────────
PLATFORM="$(uname -s)"
TAB_FILTER=""        # restrict to a single tab (e.g. dotfiles)
EMIT=0               # print selected keys to stdout, never apply
DRY=0
RUNMODE="interactive" # interactive | list | print-preset
PRESET="rec"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --platform) PLATFORM="${2:-all}"; shift 2 ;;
        --tab)      TAB_FILTER="${2:-}"; shift 2 ;;
        --emit)     EMIT=1; shift ;;
        --preset)   RUNMODE="print-preset"; PRESET="${2:-rec}"; shift 2 ;;
        --dry-run|-n) DRY=1; shift ;;
        --list)     RUNMODE="list"; shift ;;
        -h|--help)  sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "dotfiles-wizard: unknown arg '$1'" >&2; exit 2 ;;
    esac
done
case "$PLATFORM" in macos|darwin|Darwin) PLATFORM="macos" ;; esac

field() { printf '%s' "$1" | cut -d'|' -f"$2"; }
preset_has() { case ",$1," in *,"$2",*) return 0 ;; *) return 1 ;; esac; }

# ── non-interactive dotfiles modes (back-compat with the old wizard.sh) ───────
if [[ "$RUNMODE" == "list" ]]; then
    printf '%-12s %-16s %-10s %s\n' KEY CATEGORY PRESETS DESCRIPTION >&2
    for line in "${PACKAGES[@]}"; do
        plat="$(field "$line" 3)"
        [[ "$plat" == "macos" && "$PLATFORM" != "macos" ]] && continue
        printf '%-12s %-16s %-10s %s\n' \
            "$(field "$line" 1)" "$(field "$line" 2)" "$(field "$line" 4)" "$(field "$line" 5)" >&2
    done
    exit 0
fi
if [[ "$RUNMODE" == "print-preset" ]]; then
    preset_has "min,rec,all" "$PRESET" || { echo "dotfiles-wizard: unknown preset '$PRESET' (use min|rec|all)" >&2; exit 2; }
    for line in "${PACKAGES[@]}"; do
        plat="$(field "$line" 3)"
        [[ "$plat" == "macos" && "$PLATFORM" != "macos" ]] && continue
        preset_has "$(field "$line" 4)" "$PRESET" && { field "$line" 1; echo; }
    done
    exit 0
fi

# ── build the item model across all tabs ──────────────────────────────────────
# Each ITEMS entry: tab|key|category|platform|description   (SEL is parallel)
ITEMS=()
SEL=()
add_item() { ITEMS+=("$1|$2|$3|$4|$5"); SEL+=("$6"); }

build_dotfiles() {
    local line key cat plat presets desc sel
    for line in "${PACKAGES[@]}"; do
        key="$(field "$line" 1)"; cat="$(field "$line" 2)"; plat="$(field "$line" 3)"
        presets="$(field "$line" 4)"; desc="$(field "$line" 5)"
        preset_has "$presets" rec && sel=1 || sel=0
        add_item dotfiles "$key" "$cat" "$plat" "$desc" "$sel"
    done
}

# Brewfile categories: a title is a "# Foo" line sandwiched between two "# ====" rulers.
brew_categories() {
    awk '
        function isrule(s){ return s ~ /^# =+/ }
        {
            if (isrule($0) && prev ~ /^# / && isrule(prevprev)) {
                title=substr(prev,3)
                # slug comes from the FULL title (must match brew_generate); the
                # displayed label is tidied (drop REVIEW:/REFERENCE: + trailing notes).
                slug=tolower(title); gsub(/[^a-z0-9]+/,"-",slug); gsub(/^-+|-+$/,"",slug)
                disp=title; sub(/^(REVIEW|REFERENCE): */, "", disp); sub(/ - .*/, "", disp)
                cur=slug; titlemap[slug]=disp
                if (!(slug in seen)) { order[++n]=slug; seen[slug]=1 }
            } else if ($0 ~ /^(brew|cask|mas) /) { cnt[cur]++ }
            prevprev=prev; prev=$0
        }
        END { for(i=1;i<=n;i++){ s=order[i]; if(cnt[s]>0 && s!="taps") printf "%s|%s|%d\n", s, titlemap[s], cnt[s] } }
    ' "$BREWFILE"
}

build_homebrew() {
    [[ "$PLATFORM" == "macos" && -f "$BREWFILE" ]] || return 0
    local cline slug title count
    while IFS= read -r cline; do
        [[ -z "$cline" ]] && continue
        slug="$(printf '%s' "$cline" | cut -d'|' -f1)"
        title="$(printf '%s' "$cline" | cut -d'|' -f2)"
        count="$(printf '%s' "$cline" | cut -d'|' -f3)"
        add_item homebrew "$slug" "" all "$title  ($count pkgs)" 1
    done < <(brew_categories)
}

build_macos() {
    [[ "$PLATFORM" == "macos" && -x "$MACOS_SH" ]] || return 0
    local cline slug title desc
    while IFS= read -r cline; do
        [[ -z "$cline" ]] && continue
        slug="$(printf '%s' "$cline" | cut -d'|' -f1)"
        title="$(printf '%s' "$cline" | cut -d'|' -f2)"
        desc="$(printf '%s' "$cline" | cut -d'|' -f3)"
        add_item macos "$slug" "" all "$title — $desc" 1
    done < <("$MACOS_SH" --list-categories 2>/dev/null)
}

# Manifest lines: drop blanks/comments, strip trailing inline comments.
read_manifest() {
    [[ -f "$1" ]] || return 0
    local raw spec
    while IFS= read -r raw; do
        spec="${raw%%#*}"
        spec="$(printf '%s' "$spec" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [[ -z "$spec" ]] && continue
        printf '%s\n' "$spec"
    done < "$1"
}

build_npm()  { local s; while IFS= read -r s; do [[ -n "$s" ]] && add_item npm  "$s" "" all "$s" 1; done < <(read_manifest "$NPM_MANIFEST"); }
build_pipx() { local s; while IFS= read -r s; do [[ -n "$s" ]] && add_item pipx "$s" "" all "$s" 1; done < <(read_manifest "$PIPX_MANIFEST"); }

# ── decide which tabs are active ──────────────────────────────────────────────
TABS=()
add_tab() { TABS+=("$1"); }
if [[ -n "$TAB_FILTER" ]]; then
    add_tab "$TAB_FILTER"
else
    add_tab dotfiles
    [[ "$PLATFORM" == "macos" ]] && { add_tab homebrew; add_tab macos; }
    add_tab npm
    add_tab pipx
fi

tab_label() {
    case "$1" in
        dotfiles) echo "Dotfiles" ;; homebrew) echo "Homebrew" ;;
        macos) echo "macOS" ;; npm) echo "npm" ;; pipx) echo "pipx" ;;
        *) echo "$1" ;;
    esac
}

# Build only the item sets for active tabs.
for t in "${TABS[@]}"; do
    case "$t" in
        dotfiles) build_dotfiles ;;
        homebrew) build_homebrew ;;
        macos)    build_macos ;;
        npm)      build_npm ;;
        pipx)     build_pipx ;;
    esac
done

# ── TUI plumbing ──────────────────────────────────────────────────────────────
# VIS holds the ITEMS indices visible in the active tab (platform-filtered).
VIS=()
compute_vis() {
    VIS=()
    local i tab plat
    for i in "${!ITEMS[@]}"; do
        tab="$(field "${ITEMS[$i]}" 1)"; plat="$(field "${ITEMS[$i]}" 4)"
        [[ "$tab" == "$1" ]] || continue
        [[ "$plat" == "macos" && "$PLATFORM" != "macos" ]] && continue
        VIS+=("$i")
    done
}
tab_count() {  # selected/total for a tab
    local i tab plat sel=0 tot=0
    for i in "${!ITEMS[@]}"; do
        tab="$(field "${ITEMS[$i]}" 1)"; plat="$(field "${ITEMS[$i]}" 4)"
        [[ "$tab" == "$1" ]] || continue
        [[ "$plat" == "macos" && "$PLATFORM" != "macos" ]] && continue
        tot=$((tot+1)); [[ "${SEL[$i]}" == "1" ]] && sel=$((sel+1))
    done
    printf '%d/%d' "$sel" "$tot"
}

# Selected keys for a tab (space-separated), in catalog order.
selected_keys() {
    local i tab plat out=""
    for i in "${!ITEMS[@]}"; do
        tab="$(field "${ITEMS[$i]}" 1)"; plat="$(field "${ITEMS[$i]}" 4)"
        [[ "$tab" == "$1" ]] || continue
        [[ "$plat" == "macos" && "$PLATFORM" != "macos" ]] && continue
        [[ "${SEL[$i]}" == "1" ]] && out="$out $(field "${ITEMS[$i]}" 2)"
    done
    printf '%s' "${out# }"
}

apply_preset_dotfiles() {  # min|rec|all → set dotfiles SEL from catalog presets
    local p="$1" i key line
    for i in "${VIS[@]}"; do
        key="$(field "${ITEMS[$i]}" 2)"
        for line in "${PACKAGES[@]}"; do
            [[ "$(field "$line" 1)" == "$key" ]] || continue
            preset_has "$(field "$line" 4)" "$p" && SEL[$i]=1 || SEL[$i]=0
        done
    done
}
set_all_vis() { local i; for i in "${VIS[@]}"; do SEL[$i]="$1"; done; }

if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
    C_DIM="$(tput dim 2>/dev/null || true)"; C_B="$(tput bold 2>/dev/null || true)"
    C_R="$(tput sgr0 2>/dev/null || true)"; C_GRN="$(tput setaf 2 2>/dev/null || true)"
    C_CYN="$(tput setaf 6 2>/dev/null || true)"; C_REV="$(tput rev 2>/dev/null || true)"
    COLS="$(tput cols 2>/dev/null || echo 80)"
else
    C_DIM=""; C_B=""; C_R=""; C_GRN=""; C_CYN=""; C_REV=""; COLS=80
fi
CLEAR=$'\e[H\e[J'
DESC_MAX=$(( COLS - 34 )); (( DESC_MAX < 20 )) && DESC_MAX=20

render() {
    local cur="$1" active="$2" idx line cat desc box mark last_cat="" pos t lbl cnt
    printf '%s' "$CLEAR" >&2
    # tab bar
    printf '  ' >&2
    for t in "${TABS[@]}"; do
        lbl="$(tab_label "$t")"; cnt="$(tab_count "$t")"
        if [[ "$t" == "$active" ]]; then
            printf '%s %s %s%s ' "$C_REV" "$lbl" "$cnt" "$C_R" >&2
        else
            printf '%s%s %s%s  ' "$C_DIM" "$lbl" "$cnt" "$C_R" >&2
        fi
    done
    printf '\n  %s' "$C_DIM" >&2
    printf '%.0s─' $(seq 1 $(( COLS > 4 ? COLS-4 : 60 ))) >&2
    printf '%s\n' "$C_R" >&2
    # active tab list
    for pos in "${!VIS[@]}"; do
        idx="${VIS[$pos]}"; line="${ITEMS[$idx]}"
        cat="$(field "$line" 3)"; desc="$(field "$line" 5)"
        if [[ -n "$cat" && "$cat" != "$last_cat" ]]; then
            printf '  %s%s%s\n' "$C_DIM" "$cat" "$C_R" >&2; last_cat="$cat"
        fi
        (( ${#desc} > DESC_MAX )) && desc="${desc:0:DESC_MAX-1}…"
        [[ "${SEL[$idx]}" == "1" ]] && box="${C_GRN}[x]${C_R}" || box="[ ]"
        [[ "$pos" == "$cur" ]] && mark="${C_CYN}›${C_R}" || mark=" "
        if [[ "$pos" == "$cur" ]]; then
            printf '  %s %s %s%-14s%s %s%s%s\n' "$mark" "$box" "$C_B" "$(field "$line" 2)" "$C_R" "$C_REV" "$desc" "$C_R" >&2
        else
            printf '  %s %s %-14s %s%s%s\n' "$mark" "$box" "$(field "$line" 2)" "$C_DIM" "$desc" "$C_R" >&2
        fi
    done
    # footer
    printf '\n  %sTab/←→%s switch  %s↑↓%s move  %sspace%s toggle  %sa/n%s all/none' \
        "$C_B" "$C_R" "$C_B" "$C_R" "$C_B" "$C_R" "$C_B" "$C_R" >&2
    [[ "$active" == "dotfiles" ]] && printf '  %sm/r/e%s preset' "$C_B" "$C_R" >&2
    printf '  %sEnter%s %s  %sq%s quit\n' "$C_B" "$C_R" "$([[ $EMIT -eq 1 ]] && echo emit || echo apply)" "$C_B" "$C_R" >&2
}

read_key() {
    local k rest
    IFS= read -rsn1 k 2>/dev/null || return 1
    if [[ "$k" == $'\e' ]]; then
        IFS= read -rsn2 -t 1 rest 2>/dev/null
        KEY="$k$rest"
    else
        KEY="$k"
    fi
}

# ── no-TTY fallbacks ──────────────────────────────────────────────────────────
if [[ "${WIZARD_FORCE_TTY:-0}" != "1" && ( ! -t 0 || ! -t 1 ) ]]; then
    if [[ $EMIT -eq 1 ]]; then
        # headless emit → recommended dotfiles set
        compute_vis dotfiles
        apply_preset_dotfiles rec
        selected_keys dotfiles | tr ' ' '\n'
        exit 0
    fi
    echo "dotfiles-wizard: needs an interactive terminal for the full wizard." >&2
    echo "  headless? use:  ./bootstrap.sh --no-wizard   (dotfiles only)" >&2
    exit 1
fi

# ── interactive loop ──────────────────────────────────────────────────────────
ACTIVE=0                       # index into TABS
cur=0
compute_vis "${TABS[$ACTIVE]}"
printf '\e[?25l' >&2           # hide cursor
trap 'printf "\e[?25h\n" >&2' EXIT

switch_tab() {                 # $1 = +1 | -1
    ACTIVE=$(( (ACTIVE + $1 + ${#TABS[@]}) % ${#TABS[@]} ))
    compute_vis "${TABS[$ACTIVE]}"
    cur=0
}

CONFIRMED=0
while true; do
    NCOUNT=${#VIS[@]}
    (( cur >= NCOUNT )) && cur=$(( NCOUNT > 0 ? NCOUNT-1 : 0 ))
    render "$cur" "${TABS[$ACTIVE]}"
    read_key || break
    case "$KEY" in
        $'\t'|$'\e[C'|l|L)  switch_tab 1 ;;
        $'\e[Z'|$'\e[D'|h|H) switch_tab -1 ;;
        $'\e[A'|k|K) (( NCOUNT > 0 )) && cur=$(( (cur - 1 + NCOUNT) % NCOUNT )) ;;
        $'\e[B'|j|J) (( NCOUNT > 0 )) && cur=$(( (cur + 1) % NCOUNT )) ;;
        ' ')         (( NCOUNT > 0 )) && { idx="${VIS[$cur]}"; SEL[$idx]=$(( 1 - ${SEL[$idx]} )); } ;;
        a|A)         set_all_vis 1 ;;
        n|N)         set_all_vis 0 ;;
        m|M)         [[ "${TABS[$ACTIVE]}" == "dotfiles" ]] && apply_preset_dotfiles min ;;
        r|R)         [[ "${TABS[$ACTIVE]}" == "dotfiles" ]] && apply_preset_dotfiles rec ;;
        e|E)         [[ "${TABS[$ACTIVE]}" == "dotfiles" ]] && apply_preset_dotfiles all ;;
        q|Q)         printf '\n' >&2; echo "dotfiles-wizard: cancelled" >&2; exit 0 ;;
        '')          CONFIRMED=1; break ;;   # Enter
    esac
done
printf '\e[?25h' >&2
trap - EXIT

[[ $CONFIRMED -eq 1 ]] || exit 0

# ── emit mode: print selected keys for the (single) tab, never apply ──────────
if [[ $EMIT -eq 1 ]]; then
    keys="$(selected_keys "${TABS[$ACTIVE]}")"
    [[ -z "$keys" ]] && { echo "dotfiles-wizard: nothing selected" >&2; exit 0; }
    printf '%s\n' $keys
    exit 0
fi

# ── apply mode: drive each domain's existing script with the selections ───────
say() { printf '\n\033[1;34m▶ %s\033[0m\n' "$*" >&2; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }

dotfiles_keys="$(selected_keys dotfiles)"
homebrew_cats="$(selected_keys homebrew | tr ' ' ',')"
macos_cats="$(selected_keys macos | tr ' ' ',')"
npm_pkgs="$(selected_keys npm)"
pipx_pkgs="$(selected_keys pipx)"

# Confirmation summary
printf '\n%sAbout to apply:%s\n' "$C_B" "$C_R" >&2
[[ -n "$dotfiles_keys" ]] && printf '  dotfiles : %s\n' "$dotfiles_keys" >&2
[[ -n "$homebrew_cats" ]] && printf '  homebrew : %s\n' "$homebrew_cats" >&2
[[ -n "$macos_cats"    ]] && printf '  macOS    : %s\n' "$macos_cats" >&2
[[ -n "$npm_pkgs"      ]] && printf '  npm      : %s\n' "$npm_pkgs" >&2
[[ -n "$pipx_pkgs"     ]] && printf '  pipx     : %s\n' "$pipx_pkgs" >&2
[[ $DRY -eq 1 ]] && printf '  %s(dry-run — nothing will change)%s\n' "$C_DIM" "$C_R" >&2
printf '%sApply? [Y/n] %s' "$C_B" "$C_R" >&2
read -r ans </dev/tty 2>/dev/null || ans=""
case "$ans" in [nN]*) echo "cancelled" >&2; exit 0 ;; esac

DRY_FLAG=(); [[ $DRY -eq 1 ]] && DRY_FLAG=(--dry-run)

# 1. Homebrew first — installs stow + tools the later steps lean on.
if [[ -n "$homebrew_cats" ]]; then
    say "Homebrew ($homebrew_cats)"
    tmp_brew="$(mktemp)"
    awk -v sel=",$homebrew_cats," '
        function isrule(s){ return s ~ /^# =+/ }
        {
            if (isrule($0) && prev ~ /^# / && isrule(prevprev)) {
                title=substr(prev,3); slug=tolower(title); gsub(/[^a-z0-9]+/,"-",slug); gsub(/^-+|-+$/,"",slug); cur=slug
            }
            if ($0 ~ /^tap /) print
            else if ($0 ~ /^(brew|cask|mas) /) { if (cur=="taps" || index(sel, ","cur",")>0) print }
            prevprev=prev; prev=$0
        }
    ' "$BREWFILE" > "$tmp_brew"
    if [[ $DRY -eq 1 ]]; then
        printf '%s[dry] brew bundle --file=%s with %d lines%s\n' "$C_DIM" "$tmp_brew" "$(grep -c . "$tmp_brew")" "$C_R" >&2
    elif command -v brew >/dev/null 2>&1; then
        brew bundle --file="$tmp_brew" || warn "brew bundle reported errors"
    else
        warn "brew not found — skipping Homebrew step"
    fi
    rm -f "$tmp_brew"
fi

# 2. Dotfiles — delegate to bootstrap.sh (single source of truth for stow + overlay).
if [[ -n "$dotfiles_keys" ]]; then
    say "Dotfiles (stow): $dotfiles_keys"
    DOTFILES_PRESELECTED="$dotfiles_keys" bash "$BOOTSTRAP" "${DRY_FLAG[@]}" || warn "bootstrap.sh reported errors"
fi

# 3. macOS defaults (selected categories).
if [[ -n "$macos_cats" && "$PLATFORM" == "macos" ]]; then
    say "macOS defaults ($macos_cats)"
    bash "$MACOS_SH" --only "$macos_cats" "${DRY_FLAG[@]}" || warn "macos.sh reported errors"
fi

# 4. npm + pipx globals — write filtered manifests, hand to lang-restore.sh.
if [[ -n "$npm_pkgs" || -n "$pipx_pkgs" ]]; then
    say "Global packages (npm/pipx)"
    if [[ $DRY -eq 1 ]]; then
        [[ -n "$npm_pkgs"  ]] && printf '%s[dry] npm i -g %s%s\n' "$C_DIM" "$npm_pkgs" "$C_R" >&2
        [[ -n "$pipx_pkgs" ]] && printf '%s[dry] pipx install %s%s\n' "$C_DIM" "$pipx_pkgs" "$C_R" >&2
    elif [[ -x "$LANG_SH" ]]; then
        tmp_npm="$(mktemp)"; tmp_pipx="$(mktemp)"
        for p in $npm_pkgs;  do echo "$p" >> "$tmp_npm";  done
        for p in $pipx_pkgs; do echo "$p" >> "$tmp_pipx"; done
        NPM_FILE="$tmp_npm" PIPX_FILE="$tmp_pipx" bash "$LANG_SH" --restore || warn "lang-restore.sh reported errors"
        rm -f "$tmp_npm" "$tmp_pipx"
    else
        warn "lang-restore.sh not found — skipping globals"
    fi
fi

say "Done."
[[ "$PLATFORM" == "macos" && -n "$macos_cats" ]] && echo "  (some macOS settings need a logout/login to fully apply)" >&2
exit 0
