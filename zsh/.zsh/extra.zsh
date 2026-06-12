# ~/.zsh/extra.zsh

# Welcome message for root
if [ "$EUID" -eq 0 ]; then
    for letter in H E L L O " " R O O T; do echo -n "$letter"; sleep 0.03; done; echo
fi

# C-x C-e: open current command line in $EDITOR (bash-equivalent)
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line