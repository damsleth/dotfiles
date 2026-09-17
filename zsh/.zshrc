export ZSH_CONFIG_DIR="${ZSH_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zsh}"
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv zsh)"
source "$ZSH_CONFIG_DIR/_main.zsh"
source "$ZSH_CONFIG_DIR/late.zsh"

# bun completions
[ -s ~/.local/share/bun/_bun ] && source ~/.local/share/bun/_bun

# >>> Codex installer >>>
export PATH="$HOME/.local/bin:$PATH"
# <<< Codex installer <<<
