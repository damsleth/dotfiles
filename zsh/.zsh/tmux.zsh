# zsh/tmux.zsh
# tmux configuration for Zsh - utility functions for tmux session management

# Load local environment variables for tmux-related commands
if [[ -f "$ZSH_CONFIG_DIR/.env" ]]; then
    set -a
    source "$ZSH_CONFIG_DIR/.env"
    set +a
fi

# Ensure stale TMUX env is removed to avoid false tmux detection
unset TMUX

# attach to or create a new tmux session: tmux -CC attach -t <session_name> || tmux -CC new -s <session_name>
# mnemonic: "ta" for "tmux-attach"
tmux-attach(){
    session_name="${1:=kmux}"
    tmux -CC new -A -s "${session_name}"
}
alias ta='tmux-attach'

# Personal remote-tmux (Craycon/GTH) lives in the private overlay's local.zsh.

alias t='tmux'