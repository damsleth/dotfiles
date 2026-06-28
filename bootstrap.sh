#!/usr/bin/env bash
# bootstrap.sh — set up dotfiles symlinks via GNU Stow.
#
# On first run (interactive, no flags) it opens a checkbox wizard so you pick
# which packages to install. Use flags to skip the prompt:
#
#   ./bootstrap.sh                 # interactive wizard (dotfiles only)
#   ./bootstrap.sh --preset min    # bare essentials   (zsh, vim, hushlogin)
#   ./bootstrap.sh --preset rec    # recommended set   (default / non-interactive)
#   ./bootstrap.sh --all           # every package for this platform
#   ./bootstrap.sh --no-wizard     # recommended set, no prompt
#   ./bootstrap.sh --full          # multi-tab wizard: dotfiles + brew + macOS + npm/pipx
#   ./bootstrap.sh --dry-run       # preview, change nothing  (combine with above)
#
# This script handles the dotfiles (stow) layer. The full multi-tab wizard
# (--full, or _scripts/dotfiles-wizard.sh) also drives Homebrew, macOS defaults
# and npm/pipx globals, then delegates the stow step back here via
# DOTFILES_PRESELECTED so there's a single source of truth for symlinking.
#
# If a private overlay exists (./private or $DOTFILES_PRIVATE), its packages
# are stowed on top after the public ones.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_PRIVATE="${DOTFILES_PRIVATE:-$DOTFILES_DIR/private}"
DRY_RUN=0
SELECT_MODE="wizard"   # wizard | preset | all | preselected
PRESET="rec"
FULL_WIZARD=0

# DOTFILES_PRESELECTED (env): a space-separated list of package keys. When set,
# the wizard is skipped entirely and exactly these packages are stowed. This is
# how the full multi-tab wizard delegates the stow step back to us without
# re-entering the picker (no recursion).
[[ -n "${DOTFILES_PRESELECTED:-}" ]] && SELECT_MODE="preselected"

for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=1 ;;
        --all)        SELECT_MODE="all" ;;
        --no-wizard|--yes|-y) SELECT_MODE="preset"; PRESET="rec" ;;
        --full)       FULL_WIZARD=1 ;;
        --preset)     SELECT_MODE="preset" ;;          # value taken from next arg
        --preset=*)   SELECT_MODE="preset"; PRESET="${arg#*=}" ;;
        min|rec|all|minimal|recommended|everything)
                      [[ "$SELECT_MODE" == "preset" ]] && PRESET="$arg" ;;
        -h|--help)    sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "[warn] unknown arg: $arg" >&2 ;;
    esac
done

OS="$(uname -s)"
PLATFORM="unknown"
case "$OS" in
    Darwin) PLATFORM="macos" ;;
    Linux)  PLATFORM="linux" ;;
esac

info()    { echo "[info]  $*"; }
success() { echo "[ok]    $*"; }
skip()    { echo "[skip]  $*"; }
warn()    { echo "[warn]  $*"; }

# --full hands off to the multi-tab wizard, which drives every layer (Homebrew,
# macOS defaults, npm/pipx) and delegates the stow step back here via
# DOTFILES_PRESELECTED. Done before our banner so the wizard owns the screen.
# Don't recurse when we're already the delegated stow run.
WIZARD="$DOTFILES_DIR/_scripts/dotfiles-wizard.sh"
if [[ $FULL_WIZARD -eq 1 && "$SELECT_MODE" != "preselected" ]]; then
    if [[ -x "$WIZARD" ]]; then
        WIZ_ARGS=(); [[ $DRY_RUN -eq 1 ]] && WIZ_ARGS=(--dry-run)
        exec "$WIZARD" "${WIZ_ARGS[@]}"
    fi
    warn "dotfiles-wizard.sh not found — falling back to dotfiles-only bootstrap"
fi

[[ $DRY_RUN -eq 1 ]] && info "Dry run — no changes will be made"
info "Platform: $PLATFORM ($OS)"
info "Dotfiles: $DOTFILES_DIR"
echo

STOW_FLAGS=(
    "--dir=$DOTFILES_DIR"
    "--target=${HOME}"
    "--verbose"
    "--no-folding"
    "--ignore=\\.DS_Store$"
    "--ignore=^plugins$"
)
# --no-folding: link individual files into real directories instead of folding a
# whole package dir into one symlink. This lets the private overlay add files to
# a directory the public repo also populates (e.g. ~/.zsh/local.zsh alongside the
# public ~/.zsh/*.zsh) without a stow conflict.
[[ $DRY_RUN -eq 1 ]] && STOW_FLAGS+=("--simulate")

# System packages to apt-install on Debian/Ubuntu/WSL. Homebrew covers these
# on macOS via the Brewfile, so this runs on Linux only. golang-go provides the
# `go` binary that toolchains-restore.sh expects (it only sets up GOPATH).
APT_PACKAGES=(bat golang-go snapd yt-dlp)

# Snap packages once snapd is in place (Debian/Ubuntu only). `core` is the base
# snap most others depend on; install it first. whisper-cpp has no official
# Linux binary and isn't in apt, so we use the community snap (publisher
# unproven, MIT). It's strictly confined: it can only read audio/model files
# under $HOME. For files elsewhere: sudo snap connect whisper-cpp:removable-media
SNAP_PACKAGES=(core msedit whisper-cpp)

# ── package selection ─────────────────────────────────────────────────────────
SELECTED=()
select_packages() {
    # Preselected: caller (the full wizard) already picked the packages.
    if [[ "$SELECT_MODE" == "preselected" ]]; then
        SELECTED=()
        for pkg in $DOTFILES_PRESELECTED; do SELECTED+=("$pkg"); done
        return
    fi
    if [[ ! -x "$WIZARD" ]]; then
        warn "dotfiles-wizard.sh not found/executable — falling back to a built-in recommended set"
        SELECTED=(zsh vim nvim ghostty kitty btop trippy glow lf hushlogin)
        return
    fi
    # --tab dotfiles --emit → single-tab picker that prints chosen keys to stdout
    # (no apply). This is exactly the old wizard.sh contract.
    local out
    case "$SELECT_MODE" in
        all)    out="$("$WIZARD" --tab dotfiles --emit --platform "$PLATFORM" --preset all)" ;;
        preset) out="$("$WIZARD" --tab dotfiles --emit --platform "$PLATFORM" --preset "$PRESET")" ;;
        wizard) out="$("$WIZARD" --tab dotfiles --emit --platform "$PLATFORM")" ;;  # interactive (or rec if no TTY)
    esac
    # read lines into SELECTED (bash 3.2: no mapfile)
    SELECTED=()
    while IFS= read -r line; do [[ -n "$line" ]] && SELECTED+=("$line"); done <<< "$out"
}

stow_one() {  # stow_one <dir> <package>
    local dir="$1" pkg="$2"
    if [[ ! -d "$dir/$pkg" ]]; then skip "$pkg (not in $(basename "$dir"))"; return; fi
    if stow "${STOW_FLAGS[@]:1}" "--dir=$dir" "$pkg" 2>&1; then success "$pkg"
    else warn "$pkg — stow reported an issue (may already be linked)"; fi
}

install_apt_packages() {
    if ! command -v apt-get >/dev/null 2>&1; then
        skip "apt not found — skipping Debian/Ubuntu package install"; return
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
        skip "would run: sudo apt install -y ${APT_PACKAGES[*]}"
    else
        info "Installing apt packages: ${APT_PACKAGES[*]}"
        sudo apt install -y "${APT_PACKAGES[@]}" || warn "apt install reported an issue"
    fi
    # On Debian/Ubuntu the bat binary is named `batcat`. Our configs call `bat`
    # (the cat alias in zsh/env.zsh, the lf preview script), so symlink it.
    if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
        local batcat_path bat_link
        batcat_path="$(command -v batcat)"; bat_link="$HOME/.local/bin/bat"
        if [[ $DRY_RUN -eq 1 ]]; then skip "would symlink $bat_link -> $batcat_path"
        else mkdir -p "$HOME/.local/bin"; ln -sf "$batcat_path" "$bat_link"; success "linked bat -> batcat ($bat_link)"; fi
    fi
}

install_snap_packages() {
    if [[ $DRY_RUN -eq 0 ]] && ! command -v snap >/dev/null 2>&1; then
        skip "snap not found — skipping snap packages (is snapd installed/running?)"; return
    fi
    for pkg in "${SNAP_PACKAGES[@]}"; do
        if [[ $DRY_RUN -eq 1 ]]; then skip "would run: sudo snap install $pkg"
        else info "Installing snap: $pkg"; sudo snap install "$pkg" || warn "snap install $pkg reported an issue"; fi
    done
}

# Expose a consistent `whisper-cpp` command on both platforms.
#   - macOS (Homebrew): installs it as `whisper-cli` — symlink into ~/.local/bin
#   - Linux (snap):      exposes it as `whisper-cpp.cli` — register a snap alias
link_whisper_cpp() {
    if command -v whisper-cpp >/dev/null 2>&1; then skip "whisper-cpp (already on PATH)"; return; fi
    case "$PLATFORM" in
        macos)
            local src; src="$(command -v whisper-cli 2>/dev/null || true)"
            if [[ -z "$src" ]]; then skip "whisper-cpp (whisper-cli not found — run brew bundle first)"; return; fi
            if [[ $DRY_RUN -eq 1 ]]; then skip "would symlink ~/.local/bin/whisper-cpp -> $src"
            else mkdir -p "$HOME/.local/bin"; ln -sf "$src" "$HOME/.local/bin/whisper-cpp"; success "linked whisper-cpp -> whisper-cli"; fi ;;
        linux)
            if ! command -v whisper-cpp.cli >/dev/null 2>&1; then skip "whisper-cpp (snap whisper-cpp.cli not found)"; return; fi
            if [[ $DRY_RUN -eq 1 ]]; then skip "would run: sudo snap alias whisper-cpp.cli whisper-cpp"
            else info "Aliasing snap whisper-cpp.cli -> whisper-cpp"; sudo snap alias whisper-cpp.cli whisper-cpp || warn "snap alias failed"; fi ;;
    esac
}

# ── run ───────────────────────────────────────────────────────────────────────
select_packages
if [[ ${#SELECTED[@]} -eq 0 ]]; then
    warn "No packages selected — nothing to stow."
else
    info "Stowing ${#SELECTED[@]} package(s): ${SELECTED[*]}"
    for pkg in "${SELECTED[@]}"; do stow_one "$DOTFILES_DIR" "$pkg"; done
fi

# Private overlay: stow every package dir found in it (personal configs/hosts).
if [[ -d "$DOTFILES_PRIVATE" ]]; then
    echo
    info "Private overlay found at $DOTFILES_PRIVATE — stowing its packages..."
    for d in "$DOTFILES_PRIVATE"/*/; do
        pkg="$(basename "$d")"
        [[ "$pkg" == "_scripts" ]] && continue
        stow_one "$DOTFILES_PRIVATE" "$pkg"
    done
fi

if [[ "$PLATFORM" == "linux" ]]; then
    echo; info "Installing Linux (apt) packages..."; install_apt_packages
    echo; info "Installing snap packages...";        install_snap_packages
fi

echo
info "Linking whisper-cpp command..."
link_whisper_cpp

echo
if [[ $DRY_RUN -eq 1 ]]; then
    info "Dry run complete — nothing was changed."
else
    info "Done. Restart your shell or run: source ~/.zshrc"
fi
