# zsh/source.zsh
# HOMEBREW_PREFIX (and ZSH_OS) come from env.zsh, sourced just before this file.

# Lazy-load cargo/rustup env when rustup is installed outside Homebrew.
_load_cargo_env() {
    [[ -r "${CARGO_HOME:-$HOME/.cargo}/env" ]] && source "${CARGO_HOME:-$HOME/.cargo}/env"
}
cargo() {
    unfunction cargo rustc rustup 2>/dev/null
    _load_cargo_env
    cargo "$@"
}
rustc() {
    unfunction cargo rustc rustup 2>/dev/null
    _load_cargo_env
    rustc "$@"
}
rustup() {
    unfunction cargo rustc rustup 2>/dev/null
    _load_cargo_env
    rustup "$@"
}

# Lazy-load chruby: defer sourcing until first use of chruby/ruby (Homebrew install only)
if [[ -n "$HOMEBREW_PREFIX" && -r "$HOMEBREW_PREFIX/opt/chruby/share/chruby/chruby.sh" ]]; then
    chruby() {
        unfunction chruby 2>/dev/null
        source "$HOMEBREW_PREFIX/opt/chruby/share/chruby/chruby.sh"
        source "$HOMEBREW_PREFIX/opt/chruby/share/chruby/auto.sh"
        chruby "$@"
    }
fi

# ESP-IDF aliases (lazy initialization)
alias idf='source "$HOME/esp/esp-idf/export.sh" && idf.py'
alias initidf='source "$HOME/esp/esp-idf/export.sh"'

# FZF shell integration (enables Ctrl+T, Ctrl+R, Alt+C keybindings).
# Locations vary by install method: Homebrew, Debian/Ubuntu pkg, git install.
_fzf_keybindings=""
_fzf_completion=""
for _fzf_dir in \
    "${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/opt/fzf/shell}" \
    /usr/share/doc/fzf/examples \
    /usr/share/fzf \
    "$HOME/.fzf/shell"; do
    [[ -z "$_fzf_dir" ]] && continue
    [[ -r "$_fzf_dir/key-bindings.zsh" ]] && _fzf_keybindings="$_fzf_dir/key-bindings.zsh"
    [[ -r "$_fzf_dir/completion.zsh"  ]] && _fzf_completion="$_fzf_dir/completion.zsh"
    [[ -n "$_fzf_keybindings" && -n "$_fzf_completion" ]] && break
done
[[ -n "$_fzf_keybindings" ]] && source "$_fzf_keybindings"
[[ -n "$_fzf_completion"  ]] && source "$_fzf_completion"
unset _fzf_dir _fzf_keybindings _fzf_completion

# zsh-autosuggestions plugin
if [[ -r "$ZSH_CONFIG_DIR/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
    source "$ZSH_CONFIG_DIR/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

# fnm shell integration
if (( $+commands[fnm] )); then
    eval "$(fnm env --use-on-cd --shell zsh)"
    # Re-prepend ~/.local/bin so our wrapper scripts win over fnm multishell
    path=("$HOME/.local/bin" ${path:#"$HOME/.local/bin"})
fi

# Starship prompt (skip silently if not installed)
if (( $+commands[starship] )); then
    export STARSHIP_CONFIG="$ZSH_CONFIG_DIR/starship.toml"
    eval "$(starship init zsh)"
fi

# Autojump: Homebrew puts it under $HOMEBREW_PREFIX/etc/profile.d; Debian/Ubuntu under /usr/share.
for _autojump in \
    "${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/etc/profile.d/autojump.sh}" \
    /usr/share/autojump/autojump.sh; do
    if [[ -n "$_autojump" && -r "$_autojump" ]]; then
        source "$_autojump"
        break
    fi
done
unset _autojump
