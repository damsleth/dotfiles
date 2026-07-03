export ZSH_CONFIG_DIR="${ZSH_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zsh}"
source "$ZSH_CONFIG_DIR/_main.zsh"
source "$ZSH_CONFIG_DIR/late.zsh"
