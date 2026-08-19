# ~/.config/zsh/aliases.zsh
# General Aliases

alias vim="nvim" # default vim to neovim
alias vi="/usr/bin/vim" # vi opens the classic vim
# EDITOR=${vim}
alias ....="cd ../../.."
alias ...="cd ../.."
alias ..="cd .."
alias a="arch -arm64" # run command under ARM64 architecture
alias app="open -a" # open application by name
alias bandwidth="sudo bandwhich -i en0" # monitor bandwidth on en0
alias bw="bandwidth" # alias for bandwidth
alias brew=/opt/homebrew/bin/brew # Homebrew (Apple Silicon)
alias brew86=/usr/local/bin/brew # Homebrew (Intel)
alias brewlist='brew desc $(brew list --installed-on-request) | fzf -e -i' # list installed Homebrew packages with descriptions
alias cal="ncal -w3" # calendar with week numbers
alias cat0="/bin/cat $*" # use system cat with all args
alias ch="code ." # open current dir in VS Code Insiders
alias cleanupds="find . -type f -name '*.DS_Store' -ls -delete" # remove .DS_Store files recursively
alias cloc="cloc --exclude-dir=node_modules,dist,build,coverage,lib,bin,docs ./" # count lines of code from ./ and down, exclude common dirs
alias cloneweek="thab ~/Code/CLI/cloneweek/ cloneweek.zsh" # run cloneweek.zsh in cloneweek dir and return
# update color preset for all open iTerm2 sessions
iterm2_set_preset() {
  local preset="$1"

  osascript <<EOF >/dev/null
 tell application "iTerm2"
   repeat with w in windows
     repeat with t in tabs of w
       repeat with s in sessions of t
         set color preset of s to "$preset"
       end repeat
     end repeat
   end repeat
 end tell
EOF
}

dark() {
  dark-mode on &&
  wallpaper 'Black' &&
  # iterm2_set_preset 'IR_Black' &&
  echo 'dark mode enabled'
}
alias decode-jwt="jwt-decode" # decode JWT tokens
alias dl="cd ~/Downloads" # go to Downloads
alias edge='open -a "Microsoft Edge"' # open Edge browser
alias edgecors='open -a Microsoft\ Edge --args --disable-web-security --user-data-dir=/tmp/edge-cors' # open Edge with CORS disabled
alias edgekill="ps ux | grep '[E]dge Helper --type=renderer' | grep -v extension-process | tr -s ' ' | cut -d ' ' -f2 | xargs kill" # kill Edge renderer processes
alias emptytrash="sudo rm -rfv /Volumes/*/.Trashes; sudo rm -rfv ~/.Trash; sudo rm -rfv /private/var/log/asl/*.asl; sqlite3 ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV* 'delete from LSQuarantineEvent'" # empty all trashes and quarantine
alias f="fzf -e" # fuzzy finder
alias g="git status" # git
alias gaa="git add ." # git add all
alias gateway="netstat -nr | grep default | grep en0 | tr -s ' ' | cut -d' ' -f2" # get default gateway for en0
alias gco="git checkout" # git checkout
alias gcob="git checkout -b" # git checkout new branch
alias gl="git pull --all" # git pull all remotes
alias globals="npm list -g --depth=0" # list global npm packages
alias hs="http-server ./" # serve current dir over HTTP
alias i="arch -x86_64" # run command under x86_64 architecture
alias ip="dig +short myip.opendns.com @resolver1.opendns.com" # get public IP
alias ipl="ifconfig en0 | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'" # get local IP for en0
alias karabiner="code ~/.config/karabiner/" # edit Karabiner config
alias kittyconf="code ~/.config/kitty/kitty.conf" # edit Kitty config
alias lf="lfcd" # launch lf file manager and cd
alias lfconfig="code ~/.config/lf" # edit lf config
alias li='ipl | rev | cut -d"." -f2- | rev' # get local subnet prefix
light() {
  dark-mode off &&
  wallpaper '/System/Library/Desktop Pictures/Peak.madesktop' &&
  # iterm2_set_preset 'BlulocoLight' &&
  echo 'light mode enabled'
}

alias b="cd ~/brain" # go to brain dir
alias ksp="~/Library/Application Support/Steam/steamapps/common/Kerbal Space Program"
alias notes="cd ~/brain/vault" # go to notes
alias light-mode="dark-mode off" # disable dark mode
alias lsoft="lsof -nPi tcp" # list open TCP ports
# DISABLE EZA ALIASES (makes agentic ai work a lot harder)
# alias l="eza -la1 --icons --git --group-directories-first" # enhanced ls
# alias ls="eza -a --icons --git --group-directories-first --grid" # enhanced ls
alias mark="op run --no-masking mark" # run 1Password op mark
alias mdl="mdless" # markdown pager
alias nc="ncat" # netcat alternative
alias oh="open ." # open current dir in Finder - mnemonic: open here
alias pdfjoin="/System/Library/Automator/Combine PDF Pages.action/Contents/Resources/join.py" # join PDFs
alias phonebook="sqlite3 -line ~/Library/Messages/chat.db 'select id from handle' | sed '/^$/d' | sed 's/id = //' | fzf" # fuzzy search iMessage contacts
alias poshtheme="code ~/.config/powershell/ktheme_rainbow.omp.json" # edit PowerShell theme
alias power="watt" # watt CLI
alias powershell="pwsh" # PowerShell
alias pruneall="pruneRemote && pruneLocal" # prune all git remotes and locals
alias pruneRemote="git remote prune origin" # prune git remotes
alias psconfig="code ~/.config/powershell/" # edit PowerShell config
alias reload="source ~/.zshrc" # reload zsh config
alias scan="sudo nmap -T5 -v -sV -Pn" # aggressive nmap scan
alias sloc="cloc" # count lines of code
[[ "$TERM" == "xterm-kitty" ]] && alias ssh="kitten ssh" # kitty only: auto-copy xterm-kitty terminfo to remote hosts (fixes tmux "missing or unsuitable terminal" + broken backspace)
alias subnetinfo='sudo nmap -sn "$(li).*" -oG - | awk "/Up$/{print \$2}" | xargs -I{} arp -a {} | awk "{print \$1, \$2, \$3, \$4, \$5}"' # scan subnet and show MAC/vendor info
alias subnet='sudo nmap -sn "$(li).*" -oG -' # scan subnet for live hosts
alias subnetf='arp -a | grep -v "(incomplete)" | grep "$(ipl | rev | cut -c5- | rev)" | grep -Eo "\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b"' # filter ARP for subnet
alias fsubnet="subnetf" # alias for subnetf
alias tb="nc termbin.com 9999" # paste to termbin
alias thab='(){cd $1 && $2 && cd -;}' # run command in dir and return. - mnemonic: There and Back Again
alias timing="/usr/bin/time -p zsh -i -c 'exit' 2>&1 | grep '^real' | cut -d' ' -f2" # measure zsh startup time
alias tmp="cd ~/Code/tmp" # go to tmp dir
alias today="date '+%Y-%m-%d'" # today's date
alias traceroute="sudo mtr --report-wide --report-cycles=1" # traceroute with mtr
alias updateall='sudo softwareupdate -i -a; brew update; brew upgrade; brew cleanup; npm install npm -g; npm update -g; sudo gem update --system; sudo gem update; sudo gem cleanup' # update all system and dev tools
alias vær="curl wttr.in" # weather in Norwegian
alias week="date +%V" # ISO week number
alias wttr="curl wttr.in" # weather
alias zshconfig="code ~/code/dotfiles/zsh/" # edit zsh config
