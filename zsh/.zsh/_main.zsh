# ~/.zsh/_main.zsh -- Main loader for all zsh config
# by @damsleth  --   Last updated 2025-10-23

DEFAULT_USER="damsleth" # set this to your own username

# VSCode shell integration, only loads if inside a VSCode terminal
# NOTE: this skips the rest of the .zshrc loading, because it interferes with the AI integration
if [[ "$TERM_PROGRAM" == "vscode" ]]; then
    source ~/.zsh/env.zsh
    source ~/.zsh/alias.zsh

    # Lazy-load cargo (needed for Rust builds)
    cargo()  { unfunction cargo rustc rustup 2>/dev/null; source $HOME/.cargo/env; cargo "$@" }
    rustc()  { unfunction cargo rustc rustup 2>/dev/null; source $HOME/.cargo/env; rustc "$@" }
    rustup() { unfunction cargo rustc rustup 2>/dev/null; source $HOME/.cargo/env; rustup "$@" }

    # ESP-IDF lazy init
    alias idf='source "$HOME/esp/esp-idf/export.sh" && idf.py'
    alias initidf='source "$HOME/esp/esp-idf/export.sh"'

    # fnm
    if (( $+commands[fnm] )); then
        eval "$(fnm env --use-on-cd --shell zsh)"
    fi

    integration_path="$(code --locate-shell-integration-path zsh 2>/dev/null)"
    [[ -n "$integration_path" ]] && source "$integration_path"

    export PROMPT='%~ %# '
    export RPROMPT=''
    export PS1='%~ %# '
    return 0
fi


# ------ DEBUG LOGGING ------

# debug
# set -x

# profiling zsh startup - uncomment to enable
# zmodload zsh/zprof

# Load datetime module for fast timing (uses $EPOCHREALTIME)
zmodload zsh/datetime

# Set to 1 to time sourcing of files and output after loading - 0 to disable
TIME_SOURCING_ENABLED=0
# Set to 1 to output each file load time as it's sourced - 0 to disable
TIME_SOURCING_VERBOSE=0

# Array to store file loading times
declare -A load_times
start_time=$EPOCHREALTIME
rainbow_colors=(210 216 222 157 159 153 147 183 176)

print_rainbow_letters() {
    local text="$1"
    local i=1
    local char color
    
    for char in ${(s::)text}; do
        color=${rainbow_colors[$(( ((i - 1) % ${#rainbow_colors}) + 1 ))]}
        print -nP -- "%F{$color}${char//\%/%%}%f"
        i=$(( i + 1 ))
    done
    
    print
}

# Function to time the sourcing of a file
main_zshrc_timing() {
    if [[ $TIME_SOURCING_ENABLED -eq 0 ]]; then
        source "$1"
    else
        local file="$1"
        local start=$EPOCHREALTIME
        source "$file"
        local end=$EPOCHREALTIME
        local duration=$(( end - start ))
        load_times["$file"]="$duration"
        # echo "Loaded $file in $duration seconds"
    fi
}

# ----------- END DEBUG LOGGING -----------

# Source extra (early) config: instant prompt, welcome, etc.
main_zshrc_timing ~/.zsh/extra.zsh

# Environment variables and PATH
main_zshrc_timing ~/.zsh/env.zsh

# Aliases
main_zshrc_timing ~/.zsh/alias.zsh

# Agent-specific aliases, functions and completions
main_zshrc_timing ~/.zsh/agents.zsh

# Functions
main_zshrc_timing ~/.zsh/func.zsh

# Source external tools and prompt config (Starship, Cargo, chruby, etc.)
main_zshrc_timing ~/.zsh/source.zsh

# GitHub Copilot CLI aliases
main_zshrc_timing ~/.zsh/ghcs.zsh

# Completions
main_zshrc_timing ~/.zsh/comp.zsh

# On-demand 1Password secret retrieval (`secret NAME`). After comp.zsh so compdef exists.
main_zshrc_timing ~/.zsh/secrets.zsh

# tmux config
main_zshrc_timing ~/.zsh/tmux.zsh

# Machine-local / personal config (private overlay, or your own). Not tracked by
# the public repo — put host-specific functions, secrets-touching helpers, and
# anything you don't want published in ~/.zsh/local.zsh.
[[ -r ~/.zsh/local.zsh ]] && main_zshrc_timing ~/.zsh/local.zsh

# Any additional customizations can go here
export LSCOLORS="Exfxcxdxbxbxcxabagacad"
export CLICOLOR=1

if [[ $TIME_SOURCING_ENABLED -eq 1 ]]; then
    
    # Calculate total time
    end_time=$EPOCHREALTIME
    total_time=$(( (end_time - start_time) * 1000 ))
    
    # Table of load times for each file
    if [[ $TIME_SOURCING_VERBOSE -eq 1 ]]; then
        # echo "---------------------------------------"
        
        # Collect file and time pairs into an array
        files_and_times=()
        for file in ${(k)load_times}; do
            files_and_times+=("${load_times[$file]}:$file")
        done
        
        # Sort by load time descending and print one entry per line
        line_index=0
        for entry in ${(On)files_and_times}; do
            time=${entry%%:*}
            file=${entry#*:}
            file_no_quotes=${file//\"/}
            short_file="${file_no_quotes##*/}"
            if [[ -z "$short_file" ]]; then
                short_file="_main"
            fi
            short_file="${short_file%.zsh}"
            ms=$(printf "%.0f" $(( time * 1000 )))
            
            file_color=${rainbow_colors[$(( (line_index % ${#rainbow_colors}) + 1 ))]}
            line_index=$(( line_index + 1 ))
            
            print -Pn "%F{$file_color}${short_file}%f\t%F{$file_color}${ms}ms%f\n"
        done
        total_time_rounded=$(printf "%.0f" "$total_time")
        print -Pn "%B%F{15}total\t${total_time_rounded}ms%f%b\n"
    else
        STARTUP_TIME=$(printf "%.0fms" "$total_time")
        total_time_ms=$(printf "%.0f" "$total_time")
        print_rainbow_letters "${total_time_ms}ms"
        # print_rainbow_letters "${STARTUP_TIME}"
    fi
fi

# profiling end - uncomment to enable
# zprof
# PATH ordering is managed in ~/.zsh/env.zsh.
