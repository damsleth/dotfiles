# Brewfile - curated install manifest for a fresh machine
#
# Usage:
#   brew bundle --file=~/Code/dotfiles/Brewfile
#
# This file is the *curated* manifest. The unmodified dump from the previous
# machine lives in Brewfile.full as reference.
#
# Convention:
#   - active lines  = install this
#   - "REVIEW" blocks = previously installed, decide whether you still want them.
#     Uncomment to keep, delete to drop.

# ============================================================================
# Taps
# ============================================================================
tap "homebrew/services"
tap "1password/tap"
tap "charmbracelet/tap"
tap "dagger/tap"
tap "dotnet/dev-proxy"
tap "felixkratz/formulae"
tap "heroku/brew"
tap "mongodb/brew"

# REVIEW: niche taps - keep only if you still use the tool they ship
# tap "christo-auer/eilmeldung", "https://github.com/christo-auer/eilmeldung"
# tap "drawthingsai/draw-things"
# tap "gcenx/wine"
# tap "ggozad/formulas"
# tap "gromgit/fuse"
# tap "imxieyi/waifu2x"
# tap "jandedobbeleer/oh-my-posh"    # using starship now
# tap "jellycuts/formulae"
# tap "kegworks-app/kegworks"        # wine wrapper
tap "koekeishiya/formulae"           # skhd (global hotkeys, e.g. opt+space kitty toggle)
# tap "macos-fuse-t/cask"
# tap "majd/repo"                    # ipatool
# tap "matthart1983/tap"             # netwatch
# tap "nickciolpan/tap"              # cli-snitch
# tap "nikitabobko/tap"              # aerospace WM
# tap "osrf/simulation"              # gazebo robotics
# tap "romkatv/powerlevel10k"        # dropped p10k
# tap "roryclear/tap"                # clearcam
# tap "timescam/tap"
# tap "vldmrkl/formulae"             # airdrop-cli
# tap "zegervdv/zathura"

# ============================================================================
# Shell + terminal foundation
# ============================================================================
brew "stow"
brew "starship"
brew "tmux"
brew "fzf"
brew "zsh-syntax-highlighting"
brew "bat"
brew "eza"
brew "fd"
brew "ripgrep"
brew "jq"
brew "btop"
brew "neovim"
brew "lazygit"
brew "tree"
brew "dockutil"
brew "skhd"            # global hotkey daemon (opt+space toggles kitty)

# ============================================================================
# Git / GitHub / dev workflow
# ============================================================================
brew "git"
brew "git-lfs"
brew "gh"
brew "mkcert"
brew "shellcheck"
brew "gnupg"

# ============================================================================
# Languages, runtimes, version managers
# ============================================================================
brew "fnm"            # Node version manager
brew "pyenv"          # Python version manager
brew "rbenv"          # Ruby version manager
brew "go"
brew "rust"
brew "openjdk"
brew "python@3.13"
brew "ruby-install"
brew "chruby"
brew "pipx"

# REVIEW: extra runtimes
# brew "php"
# brew "composer"
# brew "powershell"
# brew "nushell"
# brew "poetry"
# brew "python@3.9"
# brew "python@3.10"
# brew "python@3.11"

# ============================================================================
# Networking / DNS / system
# ============================================================================
brew "curl"
brew "wget"
brew "httpie"
brew "curlie"
brew "nmap"
brew "mtr"
brew "trippy"
brew "iftop"
brew "netcat"
brew "socat"
brew "cloudflared"
brew "ddclient"
brew "blueutil"

# REVIEW: deeper net/security tooling
# brew "termshark"
# brew "tcpreplay"
# brew "tcptraceroute"
# brew "nethogs"
# brew "bandwhich"
# brew "fping"
# brew "inetutils"
# brew "sshpass"
# brew "spoof-mac"
# brew "theharvester"
# brew "checkdmarc"
# brew "parsedmarc"
# brew "binwalk"
# brew "radare2"
# brew "mmdbinspect"

# ============================================================================
# Cloud / infra CLIs
# ============================================================================
brew "azure-cli"
brew "azcopy"
brew "hcloud"
brew "docker"
brew "podman"
brew "qemu"

# REVIEW: cloud/infra extras
# brew "render"
# brew "cfssl"
# brew "dagger/tap/dagger"
# brew "dotnet/dev-proxy/dev-proxy"
# brew "mongodb/brew/mongodb-community"
# brew "mongodb/brew/mongodb-database-tools"
# brew "mongocli"
# brew "redis"
# brew "pgvector"
# brew "nginx"
# brew "grpc"
# brew "grpcurl"
# brew "protobuf"

# ============================================================================
# AI / LLM tooling
# ============================================================================
brew "gemini-cli"
brew "llm"
brew "llama.cpp"
brew "whisper-cpp"

# REVIEW: heavier ML bits
# brew "llmfit"
# brew "mlx-lm"
# brew "pi-coding-agent"

# ============================================================================
# Files / archives / search
# ============================================================================
brew "coreutils"
brew "moreutils"
brew "grep"
brew "ncdu"
brew "watch"
brew "pv"

# ============================================================================
# Media / images / docs
# ============================================================================
brew "ffmpeg"
brew "yt-dlp"
brew "imagemagick"
brew "exiftool"
brew "pandoc"
brew "gifsicle"
brew "gifski"
brew "ffmpegthumbnailer"
brew "media-info"

# REVIEW: extra media tools
# brew "ffmpeg@4"
# brew "ffmpeg@6"
# brew "tesseract"
# brew "tesseract-lang"
# brew "chafa"
# brew "fluid-synth"
# brew "macvim", args: ["HEAD"]
# brew "mplayer"
# brew "w3m"

# ============================================================================
# File managers / TUI utilities
# ============================================================================
# brew "ranger"
brew "fastfetch"

# REVIEW: overlapping file managers - pick one
brew "lf"
# brew "nnn"
# brew "vifm"
# brew "midnight-commander"
# brew "ctpv"

# ============================================================================
# App Store apps (mas)
# ============================================================================
# Requires App Store sign-in before `brew bundle` runs.
# Refresh list (once signed in) with:
#   mas list | awk '{ id=$1; $1=""; sub(/^ +/,""); sub(/ \([^)]*\)$/,""); print "mas \"" $0 "\", id: " id }'
brew "mas"
mas "Xcode",             id: 497799835
mas "Windows App",       id: 1295203466
mas "Amphetamine",       id: 937984704
mas "TestFlight",        id: 899247664
mas "Lungo",             id: 1263070803
mas "Battery Indicator", id: 1206020918
mas "AdBlock Pro",       id: 1018301773
mas "Day Progress",      id: 6450280202
mas "Notchmeister",      id: 1599169747
mas "Actions",           id: 1586435171

# ============================================================================
# REVIEW: misc / toys / experiments - uncomment what you still want
# ============================================================================
# brew "asciiquarium"
# brew "nethack"
# brew "figlet"
# brew "neofetch"          # superseded by fastfetch
# brew "calcurse"
# brew "sampler"
# brew "gource"
# brew "csvlens"
brew "glow"
# brew "mdless"
# brew "mdfried"
# brew "hexer"
# brew "f3"
# brew "dfu-util"
# brew "shc"
# brew "terminal-notifier"
# brew "switchaudio-osx"
# brew "osx-cpu-temp"
# brew "pngcheck"
# brew "semver"
brew "cloc"
# brew "ctop"
# brew "fresh-editor"
# brew "rxvt-unicode"
# brew "shpotify"
# brew "spotify_player"
# brew "spotifyd"
# brew "signal-cli"
# brew "sqlcipher"
# brew "testdisk"
# brew "xclip"
# brew "zrok"
# brew "copyparty"
brew "autojump"
# brew "colordiff"
# brew "bandwhich"

# ============================================================================
# Casks - terminals / editors
# ============================================================================
cask "ghostty"
cask "visual-studio-code"

cask "kitty"

# REVIEW: alternate terminals
# cask "warp"
# cask "iterm2"
# cask "wave"

# ============================================================================
# Casks - daily-driver apps
# ============================================================================
cask "1password"
cask "1password-cli"
cask "karabiner-elements"
cask "rectangle"
cask "stats"
cask "obsidian"
cask "dropbox"
cask "tailscale-app"
cask "vlc"
cask "keka"
cask "localsend"
cask "slack"
cask "spotify"

# ============================================================================
# Casks - dev / quicklook
# ============================================================================
cask "db-browser-for-sqlite"
cask "qlcolorcode"
cask "qlmarkdown"
cask "qlimagesize"
cask "syntax-highlight"
cask "suspicious-package"

# REVIEW: heavier dev tooling / niche apps
cask "ghidra"
cask "wireshark-app"
cask "powershell"
# cask "arduino-ide"
# cask "xquartz"
# cask "macfuse"
# cask "fuse-t"
# cask "mounty"
# cask "imazing"
# cask "pieces"
# cask "pieces-os"
cask "codex"
# cask "codexbar"
# cask "copilot-cli"
# cask "fig"               # deprecated
# cask "amethyst"          # window manager - not using
# cask "kegworks"          # wine wrapper
# cask "gqrx"              # SDR
# cask "blackhole-2ch"
# cask "cscreen"
# cask "majd/repo/ipatool"
# cask "swiftbar"
# cask "xbar"
# cask "motrix"
# cask "notunes"
# cask "upscayl"

# ============================================================================
# Casks - fonts
# ============================================================================
cask "font-hack-nerd-font"
cask "font-jetbrains-mono-nerd-font"
cask "font-monaspace"

# REVIEW: extra fonts
cask "font-monocraft"
cask "font-tamzen"

# ============================================================================
# VS Code extensions
# ============================================================================
# Managed separately in vscode/extensions.txt + _scripts/vscode-restore.sh.
# Keeping them out of Brewfile so the restore script can prompt before
# reinstalling 170+ extensions on a fresh machine.

# ============================================================================
# REFERENCE: apps in /Applications NOT covered above
# ============================================================================
# Snapshot of the current machine's /Applications. Anything already covered
# by an active cask, an active mas line, or a commented REVIEW entry above
# is NOT listed here. Uncomment to add to the install, or leave as a manual
# reinstall checklist.

# --- Could be installed via cask ----------------------------------------
# cask "alfred"
# cask "audacity"
# cask "balenaetcher"
# cask "battle-net"
# cask "bazecor"
# cask "betterdisplay"
# cask "burp-suite"
# cask "chatgpt"
# cask "claude"
# cask "coconutbattery"
# cask "cool-retro-term"
# cask "devcleaner"
# cask "discord"
# cask "docker"                 # Docker Desktop
# cask "grandperspective"
# cask "itunes-backup-explorer"
# cask "key-codes"
# cask "lm-studio"
cask "lulu"
# cask "meta-quest-link"
# cask "microsoft-edge"
# cask "microsoft-office"       # full Office suite
# cask "microsoft-teams"
# cask "modrinth"
# cask "mongodb-compass"
# cask "mqtt-explorer"
# cask "mullvadvpn"
# cask "netspot"
# cask "ollama"
# cask "omnidisksweeper"
# cask "onedrive"
# cask "openscad"
# cask "playcover-community"
# cask "proxyman"
# cask "qflipper"
# cask "raspberry-pi-imager"
# cask "sensiblesidebuttons"
# cask "signal"
# cask "slack"
# cask "sniffnet"
# cask "spotify"
# cask "steam"
# cask "the-unarchiver"
# cask "things"                 # or mas variant
# cask "vmware-fusion"
# cask "vnc-viewer"
# cask "yaak"

# --- Manual download / Steam / drivers / niche --------------------------
# No cask/mas - reinstall by hand:
#   been                            # ?
#   CH34xVCPDriver, CP210xVCPDriver # USB-serial drivers
#   Cleft                           # ?
#   Fresco                          # Adobe Fresco
#   iTermAI, iTermBrowserPlugin     # iTerm extensions
#   Joystick Mapper                 # paid utility
#   KisMac2                         # wifi tool
#   Lost Person Behavior            # BRKH reference app
#   Metodebok                       # BRKH reference
#   Microsoft 365 Copilot Shim      # bundled with Office install
#   Minecraft                       # launcher download
#   NDI Access Manager / Test Patterns # NDI Tools bundle
#   OpenSoundMeter                  # github release
#   Picturama                       # photo manager
#   Politiloggen                    # NO police log
#   SYSGeeker NTFS for Mac          # licensed util
#   TaHoma                          # Somfy app
#   XPENG                           # car app
#
# Steam games (reinstall via Steam after `cask "steam"`):
#   Crimsonland, Factorio, Katana ZERO, Oxygen Not Included,
#   Project Zomboid, RUNNING WITH RIFLES, StuntSki Lite,
#   The Past Within, The Powder Toy, Unrailed!

# vim: set ft=ruby:
