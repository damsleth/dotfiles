export ZSH_CONFIG_DIR="${ZSH_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zsh}"
source "$ZSH_CONFIG_DIR/_main.zsh"

test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

# bun completions
[ -s "$HOME/.local/share/bun/_bun" ] && source "$HOME/.local/share/bun/_bun"

# cargo/rustup env (created by rustup-init); harmless if absent
[ -s "$HOME/.local/share/../bin/env" ] && . "$HOME/.local/share/../bin/env"
export FUNCTIONS_CORE_TOOLS_TELEMETRY_OPTOUT=1
