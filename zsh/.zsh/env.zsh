# ~/.zsh/env.zsh

# Platform detection (use ZSH_OS rather than OSTYPE so we can branch cleanly)
case "$OSTYPE" in
    darwin*) ZSH_OS="macos" ;;
    linux*)  ZSH_OS="linux" ;;
    *)       ZSH_OS="other" ;;
esac
export ZSH_OS

# Locate Homebrew prefix (Apple Silicon, Intel mac, or Linuxbrew). Empty if not installed.
HOMEBREW_PREFIX=""
for _brew_candidate in /opt/homebrew /usr/local /home/linuxbrew/.linuxbrew; do
    if [[ -x "$_brew_candidate/bin/brew" ]]; then
        HOMEBREW_PREFIX="$_brew_candidate"
        break
    fi
done
unset _brew_candidate
export HOMEBREW_PREFIX

# Load Homebrew environment FIRST so we can build PATH on top of it
# (otherwise brew shellenv's path_helper overwrites our custom PATH later)
if [[ -n "$HOMEBREW_PREFIX" ]]; then
    brew_shellenv_cache="${XDG_CACHE_HOME:-$HOME/.cache}/brew_shellenv.${ZSH_OS}.zsh"
    if [[ -r "$brew_shellenv_cache" ]]; then
        source "$brew_shellenv_cache"
    else
        mkdir -p "${brew_shellenv_cache:h}"
        "$HOMEBREW_PREFIX/bin/brew" shellenv >| "$brew_shellenv_cache"
        source "$brew_shellenv_cache"
    fi
fi

# SSLKEYLOGFILE logs TLS session keys - security risk, disabled unless debugging
# export SSLKEYLOGFILE=$HOME/.sslkey.log
LC_COLLATE="en_US.UTF-8"
LC_CTYPE="en_US.UTF-8"
LC_MESSAGES="en_US.UTF-8"
LC_MONETARY="en_US.UTF-8"
LC_NUMERIC="en_US.UTF-8"
LC_TIME="en_US.UTF-8"
LC_ALL="en_US.UTF-8"
CASE_SENSITIVE="false"
HYPHEN_INSENSITIVE="true"
ZSH_DISABLE_COMPFIX="true"
DISABLE_UPDATE_PROMPT="true"
DISABLE_AUTO_TITLE="false"
ENABLE_CORRECTION="true"
COMPLETION_WAITING_DOTS="true"
HIST_STAMPS="yyyy-mm-dd"

# History settings
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY
setopt EXTENDED_HISTORY

OLLAMA_ORIGINS="app://obsidian.md*"
OLLAMA_MODELS="~/.ollama/models"
# claude code enable use of language servers
ENABLE_LSP_TOOL=1

# export VISUAL='code-insiders -w' # use C-x C-e to edit current terminal input in VSCode. so nice!
export VISUAL='nvim' # use C-x C-e to edit current terminal input
export SSH_KEY_PATH="~/.ssh/dsa_id"
# whisper-cpp Metal resources (macOS only, requires brew install whisper-cpp)
if (( $+commands[brew] )) && brew --prefix whisper-cpp &>/dev/null; then
    export GGML_METAL_PATH_RESOURCES="$(brew --prefix whisper-cpp)/share/whisper-cpp"
fi
# Go toolchain root: the dir that contains bin/, src/, pkg/ — NOT its bin/.
# (Its bin/ is appended to PATH below.) Derived from the binary's real path so
# it's immune to any stale GOROOT already in the environment.
if [[ -x /usr/local/go/bin/go ]]; then           # macOS / tarball install
    export GOROOT=/usr/local/go
elif (( $+commands[go] )); then                   # package install (symlinked)
    export GOROOT="${${commands[go]:A}:h:h}"      # resolve symlinks, up two dirs
else
    unset GOROOT
fi
# XDG Base Directory defaults (used by the tool homes below)
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export ZSH_CONFIG_DIR="${ZSH_CONFIG_DIR:-$XDG_CONFIG_HOME/zsh}"

# Tool homes - XDG-compliant locations (keeps $HOME tidy)
export GEM_HOME="$XDG_DATA_HOME/gem"
export BUN_INSTALL="$XDG_DATA_HOME/bun"
export CARGO_HOME="$XDG_DATA_HOME/cargo"
export RUSTUP_HOME="$XDG_DATA_HOME/rustup"
export BUNDLE_USER_CONFIG="$XDG_CONFIG_HOME/bundle/config"
export BUNDLE_USER_CACHE="$XDG_CACHE_HOME/bundle"
export BUNDLE_USER_PLUGIN="$XDG_DATA_HOME/bundle/plugin"
export COMPOSER_HOME="$XDG_CONFIG_HOME/composer"
export DOCKER_CONFIG="$XDG_CONFIG_HOME/docker"
export NPM_CONFIG_CACHE="$XDG_CACHE_HOME/npm"
export NPM_CONFIG_PREFIX="$XDG_DATA_HOME/npm"
export NPM_CONFIG_USERCONFIG="$XDG_CONFIG_HOME/npm/npmrc"
export NPM_PACKAGES="$NPM_CONFIG_PREFIX"
export NUGET_PACKAGES="$XDG_CACHE_HOME/NuGet/packages"
export NUGET_HTTP_CACHE_PATH="$XDG_CACHE_HOME/NuGet/http-cache"
export PLATFORMIO_CORE_DIR="$XDG_DATA_HOME/platformio"
export IDF_TOOLS_PATH="$XDG_DATA_HOME/espressif"
export AZURE_CONFIG_DIR="$XDG_CONFIG_HOME/azure"
export HEADROOM_CONFIG_DIR="$XDG_CONFIG_HOME/headroom"
export HEADROOM_WORKSPACE_DIR="$XDG_STATE_HOME/headroom"
export SHELL_SESSION_DIR="$XDG_STATE_HOME/zsh/sessions"
export TERMINFO="$XDG_DATA_HOME/terminfo"

export LESS="-R"
export FZF_DEFAULT_COMMAND="fd . $HOME"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND="fd -t d . $HOME"
export HISTFILE="$XDG_STATE_HOME/zsh/history"
export HOMEBREW_NO_ENV_HINTS=1 # hide homebrew auto update hints

# AZURE AI
export AZURE_API_KEY="op://Employee/AzureAI/credential"
export AZURE_API_VERSION="2024-08-01-preview"
export AZURE_EMBEDDING_API_VERSION="op://Employee/AzureAI/EMBEDDING_API_VERSION"
export AZURE_API_BASE="op://Employee/AzureAI/API_BASE"

# DOTNET
export DOTNET_ROOT=/usr/local/share/dotnet

# FNM - Fast Node Manager
FNM_RESOLVE_ENGINES=true

# PATHS
# Keep PATH/path tied, exported, and unique across both array and string updates.
typeset -gxTU PATH path
path=(
    "$HOME/bin"
    "$HOME/.local/bin"
    ${HOMEBREW_PREFIX:+"$HOMEBREW_PREFIX/bin"}
    ${HOMEBREW_PREFIX:+"$HOMEBREW_PREFIX/sbin"}
    /bin
    /sbin
    /usr/bin
    /usr/sbin
    /usr/local/bin
    /usr/local/sbin
    /usr/local/opt/libarchive/bin
    /usr/local/share/dotnet
    "$HOME/.dotnet/tools"
    "$GOROOT/bin"
    "$GEM_HOME/bin"
    "$BUN_INSTALL/bin"
    "$CARGO_HOME/bin"
    "$HOME/.deno/bin"
    "$HOME/.rvm/bin"
    "$NPM_CONFIG_PREFIX/bin"
    "$HOME/.codeium/windsurf/bin"
    "$HOME/.opencode/bin"
    "$HOME/.antigravity/antigravity/bin"
    $path
)
# macOS-only app bundles
if [[ "$ZSH_OS" == "macos" ]]; then
    path=(/Applications/Obsidian.app/Contents/MacOS $path)
    alias cat="bat --paging=never" # use bat instead of cat
    alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale" # Tailscale CLI
fi
# Remove any literal, unexpanded entry inherited from other initializers.
path=(${path:#"~/.dotnet/tools"})
# Drop the denormalized duplicate of ~/.local/bin inherited from the launchd env.
path=(${path:#"$HOME/.local/share/../bin"})
export MANPATH="/opt/local/share/man:/usr/local/man:/usr/local/opt/coreutils/libexec/gnuman:$MANPATH"
