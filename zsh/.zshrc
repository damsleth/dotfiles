# ponytail: no OS-specific paths here. Homebrew prefix + shellenv are detected
# portably in $ZSH_CONFIG_DIR/env.zsh (ZSH_OS / HOMEBREW_PREFIX). If an installer
# appends a hardcoded /opt/homebrew or /home/linuxbrew line, delete it.
export ZSH_CONFIG_DIR="${ZSH_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zsh}"
source "$ZSH_CONFIG_DIR/_main.zsh"
source "$ZSH_CONFIG_DIR/late.zsh"

# bun completions
[ -s ~/.local/share/bun/_bun ] && source ~/.local/share/bun/_bun

# >>> Codex installer >>>
export PATH="$HOME/.local/bin:$PATH"
# <<< Codex installer <<<
