# zsh/comp.zsh

zcompdump="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
mkdir -p "${zcompdump:h}"

# root completions
if [[ "$EUID" -eq 0 ]]; then
# The autoload command in marks a function (like compinit or bashcompinit)
# to be loaded from disk only when it is first called
# rather than immediately when the shell starts.
  autoload -U compinit -u
  compinit -u -d "$zcompdump"
else
  # non-root completions
  zstyle ':completion:*' menu select
  zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

  # fpath additions must happen BEFORE compinit so completion functions resolve
  fpath+=~/.zfunc
  [[ -n "$DOCKER_CONFIG" ]] && fpath=("$DOCKER_CONFIG/completions" $fpath)
  # argcomplete (previously in .zshenv)
  fpath=( $HOME/.espressif/python_env/idf5.4_py3.13_env/lib/python3.13/site-packages/argcomplete/bash_completion.d "${fpath[@]}" )
  [[ -n "$HOMEBREW_PREFIX" && -d "$HOMEBREW_PREFIX/share/zsh/site-functions" ]] && \
      fpath=( "$HOMEBREW_PREFIX/share/zsh/site-functions" "${fpath[@]}" )

  # Initialize completion system BEFORE sourcing anything that calls compdef.
  autoload -U bashcompinit
  bashcompinit
  autoload -Uz compinit
  compinit -C -d "$zcompdump"

  # bun (uses compdef)
  [[ -r "$BUN_INSTALL/_bun" ]] && source "$BUN_INSTALL/_bun"

  # 1password (cached completion script calls compdef on line 2)
  op_completion_cache="${XDG_CACHE_HOME:-$HOME/.cache}/op_completion.zsh"
  if [[ ! -r "$op_completion_cache" || "$(command -v op)" -nt "$op_completion_cache" ]]; then
    mkdir -p "${op_completion_cache:h}"
    op completion zsh >| "$op_completion_cache" 2>/dev/null
  fi
  [[ -r "$op_completion_cache" ]] && source "$op_completion_cache"

  # likec4 (yargs completion, calls compdef; cache since it's a slow node CLI)
  likec4_completion_cache="${XDG_CACHE_HOME:-$HOME/.cache}/likec4_completion.zsh"
  if [[ ! -r "$likec4_completion_cache" || "$(command -v likec4)" -nt "$likec4_completion_cache" ]]; then
    mkdir -p "${likec4_completion_cache:h}"
    likec4 completion >| "$likec4_completion_cache" 2>/dev/null
  fi
  [[ -r "$likec4_completion_cache" ]] && source "$likec4_completion_cache"

  # 1Password CLI sign-in helper. Only needed when desktop-app integration
  # ("Settings -> Developer -> Integrate with 1Password CLI") is OFF; with it ON,
  # `op read` / `secret` trigger Touch ID directly and this is unnecessary.
  # Individual tokens are loaded on demand via `secret NAME` (see secrets.zsh);
  # `secret --all` reproduces the old bulk-export behaviour.
  opinit() {
    if pgrep -x "1Password" >/dev/null; then
      eval "$(op signin)" && echo "1Password: signed in. Use 'secret NAME' to load a token."
    else
      echo "1Password app isn't running"
    fi
  }
fi

# --- unused completions, uncomment when needed ---
# azure CLI
# source $(brew --prefix)/etc/bash_completion.d/az
# flyctl
# compdef _flyctl fly

# Compile completion dump only if it's newer than compiled version or compiled version doesn't exist
# This runs in background to avoid startup delay
{
  if [[ -s "$zcompdump" && (! -s "${zcompdump}.zwc" || "$zcompdump" -nt "${zcompdump}.zwc") ]]; then
    zcompile "$zcompdump"
  fi
} &!