# ~/.zsh/functions.zsh

# Cool And Useful Functions™️ for iTerm+zsh
# Written by @damsleth and found around the web
# Most recent additions at the top
# Last updated

# NOTE: personal/host-specific functions (kswon, serveDT, mfa, unepwd, …) live
# in the private overlay's ~/.zsh/local.zsh, not here. See _main.zsh.

# kitty/ghostty set TERM=xterm-kitty / xterm-ghostty, which breaks PSReadLine's
# line redraw (ghost-typed suggestions, dead backspace). Force xterm-256color
# for pwsh only, since .NET's terminfo detection runs once at process start.
pwsh() { TERM=xterm-256color command pwsh "$@" }

# q = ask codex a question.
# uses gpt-5.1-codex-mini with medium reasoning effort to get fast responses
# e.g. codex -s read-only --skip-git-repo-check e "hello"
unalias q 2>/dev/null
q() {
  codex \
    --model gpt-5.4-mini \
    --config reasoning_effort=medium \
    --sandbox read-only \
    --ask-for-approval never \
    e \
    --skip-git-repo-check \
    "$*"
}
alias q='noglob q' # prevent glob expansion to allow passing arguments with * and other special characters without quoting

toggle_low_power_mode() {
    case "$1" in
        1 | on)
            sudo pmset -a powermode 1
            echo "Low power mode on"
        ;;
        0 | off)
            sudo pmset -a powermode 0
            echo "Low power mode off"
        ;;
        *)
            if [ "$(pmset -g | grep 'powermode' | grep -o '[0-9]*')" -eq 1 ]; then
                sudo pmset -a powermode 0
                echo "Low power mode off"
            else
                sudo pmset -a powermode 1
                echo "Low power mode on"
            fi
        ;;
    esac
}

compresspdf() {
    gs -sDEVICE=pdfwrite -dNOPAUSE -dQUIET -dBATCH -dPDFSETTINGS=/${3:-"screen"} -dCompatibilityLevel=1.4 -sOutputFile="$2" "$1"
}

pruneLocal() {
    git fetch -p
    for branch in $(git branch -vv | grep ': gone]' | awk '{print $1}'); do
        git branch -D $branch
    done
}

mic() {
    if [[ ! $@ ]]; then
        if [[ $(osascript -e "input volume of (get volume settings)") -gt 0 ]]; then
            echo "mic off"
            osascript -e "set volume input volume 0"
        else
            echo "mic on"
            osascript -e "set volume input volume 100"
        fi
    else
        if [[ $1 == "on" ]]; then
            echo "mic on"
            osascript -e "set volume input volume 100"
        elif [[ $1 == "off" ]]; then
            echo "mic off"
            osascript -e "set volume input volume 0"
        elif [[ $1 =~ ^[0-9]+$ ]]; then
            local v=$1
            (( v > 100 )) && v=100
            (( v < 0 )) && v=0
            osascript -e "set volume input volume $v"
            echo "mic set to $v%"
        else
            echo "specify either 'on', 'off', a number or nothing"
        fi
    fi
}

countdown() {
    local OLD_IFS="${IFS}"
    IFS=":"
    local ARR=( $1 )
    local SECONDS=$((  (ARR[0] * 60 * 60) + (ARR[1] * 60) + ARR[2]  ))
    local START=$(date +%s)
    local END=$((START + SECONDS))
    local CUR=$START
    while [[ $CUR -lt $END ]]
    do
        CUR=$(date +%s)
        LEFT=$((END-CUR))
        printf "\r%02d:%02d:%02d" \
        $((LEFT/3600)) $(( (LEFT/60)%60)) $((LEFT%60))
        sleep 1
    done
    IFS="${OLD_IFS}"
    osascript -e 'display notification "'"$3"'" with title "'$2'"'
}

serve(){
    hostname="${1:=$(whoami)}"
    port="${2:=8081}"
    (trap 'kill 0' SIGINT; hs -p $port -s & lt -p $port -s $hostname -l "127.0.0.1" -o --print-requests)
}

serve-node(){
    hostname="${1:=$(whoami)}"
    port="${2:=8081}"
    (trap 'kill 0' SIGINT; node -p ${2} -s & lt -p ${2} -s ${1} -l "127.0.0.1" -o --print-requests)
}

serve-npm(){
    echo "this command runs 'npm start' and localtunnel with the specified hostname (default '$(whoami)')"
    echo "make sure your npm start script runs node on 8082"
    hostname="${1:=$(whoami)}"
    (trap 'kill 0' SIGINT; npm start & lt -p 8082 -s ${1} -l "127.0.0.1" -o --print-requests)
}

pipe(){
    stuff="${1:=./index.html}"
    hostname="${2:=$(whoami)}"
    port="${3:=8000}"
    (trap 'kill 0' SIGINT; ncat -lkp ${3} --sh-exec "printf 'HTTP/1.1 200\n\n<h1>';cat ${1}" & lt -p ${3} -s ${2} -l "127.0.0.1" -o)
}

kp(){
    local pid=$(ps -ef | sed 1d | eval "fzf -e ${FZF_DEFAULT_OPTS} -m --header='[kill:process]'" | awk '{print $2}')
    if [ "x$pid" != "x" ]
    then
        echo $pid | xargs kill -${1:-9}
        kp
    fi
}

sms(){
    recipient="${1}"
    message="${2}"
cat<<EOF | osascript - "${recipient}" "${message}"
on run {targetBuddyPhone, targetMessage}
    tell application "Messages"
        set targetService to 1st service whose service type = iMessage
        set targetBuddy to buddy targetBuddyPhone of targetService
        send targetMessage to targetBuddy
    end tell
end run
EOF
}

msg(){
    limit=20
    if [ ! -z $1 ]; then limit=$1; fi;
    sqlite3 -line ~/Library/Messages/chat.db "SELECT m.ROWID, text, MAX(date) lastMessageDate, is_from_me, h.id FROM message m INNER JOIN handle h ON h.ROWID=m.handle_id WHERE is_from_me = 0 GROUP BY h.ROWID LIMIT $limit " | sed -E -n '/ROWID = |is_from_me = |lastMessageDate = /'\!p | sed -e 's/text = /----\n\n/g' -e 's/id = //g' -e 's/^ *//g' -e 's/^\n//g'
}

allmsg(){
    sqlite3 -line ~/Library/Messages/chat.db "SELECT m.ROWID, text, MAX(date) lastMessageDate, is_from_me, h.id FROM message m INNER JOIN handle h ON h.ROWID=m.handle_id WHERE is_from_me = 0 GROUP BY h.ROWID" | sed -E -n '/ROWID = |is_from_me = |lastMessageDate = /'\!p | sed -e 's/text = //g' -e 's/id = //g' -e 's/^ *//g' -e 's/^\n//g'
}

otp() {
    if [[ -z "$1" ]]; then provider="microsoft"; else provider=$1; fi
    otp=$(sqlite3 -line ~/Library/Messages/chat.db "SELECT m.ROWID, text, MAX(date) lastMessageDate, h.id FROM message m INNER JOIN handle h ON h.ROWID=m.handle_id WHERE id = '$provider'" | grep text | grep -oE '[0-9]{6}')
    echo $otp | pbcopy
    echo "$otp"
    echo "otp copied to clipboard"
}

watt() {
    info=$(ioreg -w 0 -f -r -c AppleSmartBattery)
    voltage=$(echo $info | grep '"Voltage" = ' | grep -oE '[0-9]+')
    amp=$(echo $info | grep '"Amperage" = ' | grep -oE '[0-9]+')
    amp=$(bc <<< "if ($amp >= 2^63) $amp - 2^64 else $amp")
    watts="$(( (voltage / 1000.0) * (amp / 1000.0) ))"
    printf "%.3f\n" $watts
}

logpower(){
  while true;
  do
    output=$(power);
    if [ "$output" != "$prev_output" ];
    then
        if [ "$1" = "-t" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - $output";
        else
            echo "$output";
        fi
        prev_output="$output";
    fi;
    sleep 60;
done
}

# fzf function to find executable files in the PATH and run them
fp(){
local loc=$(echo $PATH | sed -e $'s/:/\\\n/g' | eval "fzf ${FZF_DEFAULT_OPTS} --header='[find:path]'")
if [[ -d $loc ]]; then
    echo "$(rg --files $loc | rev | cut -d"/" -f1 | rev)" | eval "fzf ${FZF_DEFAULT_OPTS} --header='[find:exe] => ${loc}' >/dev/null"
    fp
fi
}

# make directory and change into it
mkd() {
mkdir -p "$@" && cd "$_";
}

# print all 256 colors with their codes
allcolors(){
for i in {0..255}; do print -Pn "%K{$i}  %k%F{$i}${(l:3::0:)i}%f " ${${(M)$((i%6)):#3}:+$'\n'}; done
}

randfile() {
  # Usage: randfile <directory>
  # if no directory is specified, it defaults to the current directory
  # non recursive, only files directly in the specified directory are considere
  dir="${1:-.}" && echo $(find "$dir" -maxdepth 1 -type f | shuf -n 1)
}

# wallpaper function that accepts color names or file paths
wallpaper(){
# show help if -h or --help is passed
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  echo "wallpaper function that accepts color names or file paths"
  return 0
fi
# normalize input to lowercase for matching
input="$1"
input_lc=$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')
colors="black|cyan|silver|teal|stone|plum|ocher|gold|electric blue"

if [[ "$input_lc" =~ ^($colors)$ ]]; then
    # capitalize only the first letter of the normalized color (e.g. "electric blue" -> "Electric blue")
    first_char=$(printf '%s' "${input_lc:0:1}" | tr '[:lower:]' '[:upper:]')
    rest="${input_lc:1}"
    cap="${first_char}${rest}"
    wp="/System/Library/Desktop Pictures/Solid Colors/${cap}.png"
else
    wp="$input"
fi

osascript -e 'tell application "System Events" to set picture of every desktop to "'$wp'"'
}

jwt-decode() {
  python3 - "$1" <<'EOF'
import sys, base64, json

token = sys.argv[1]
parts = token.split('.')

for i, label in enumerate(['Header', 'Payload']):
    if i >= len(parts):
        break
    part = parts[i]
    part += '=' * (4 - len(part) % 4)
    try:
        decoded = base64.urlsafe_b64decode(part)
        print(f'=== {label} ===')
        print(json.dumps(json.loads(decoded), indent=2))
    except Exception as e:
        print(f'Error decoding {label}: {e}', file=sys.stderr)
EOF
}

# ULTRATHINK
ut(){
python3 - <<'PY'
s="ultrathink"
colors=[31,33,32,36,34,35]
for i,ch in enumerate(s):
    c=colors[i%len(colors)]
    print(f"\033[{c}m{ch}\033[0m", end="")
print()
PY
}

edgeProfiles(){
  jq -r '.profile.info_cache | to_entries[] |
    "\(.key)\t\(.value.user_name // "-")\t\(.value.name // "-")"' \
    "$HOME/Library/Application Support/Microsoft Edge/Local State"
}

transfer(){
if [ $# -eq 0 ];
  then echo "No arguments specified.\nUsage:\n transfer <file|directory>\n ... | transfer <file_name>" >&2;
  return 1;
fi;
if tty -s;
  then file="$1";file_name=$(basename "$file");
  if [ ! -e "$file" ];
    then echo "$file: No such file or directory" >&2;
    return 1;
  fi;
    if [ -d "$file" ];
      then file_name="$file_name.zip" ,;(cd "$file"&&zip -r -q - .)|curl --progress-bar --upload-file "-" "https://transfer.sh/$file_name"|tee /dev/null,;
    else cat "$file"|curl --progress-bar --upload-file "-" "https://transfer.sh/$file_name"|tee /dev/null;
    fi;
  else file_name=$1;curl --progress-bar --upload-file "-" "https://transfer.sh/$file_name"|tee /dev/null;
fi;
}

ibadge(){
  badge="${1}"
  printf "\e]1337;SetBadgeFormat=%s\a" \
  $(echo -n "${1}" | base64)
}

# set iterm profile: itheme <profile_name>
itheme() { echo -e "\033]50;SetProfile=$1\a" }

# change directory to the last directory visited in lf
lfcd () {
    cd "$(command lf -print-last-dir "$@")"
}

# get the current working directory of a process by its PID
pwdx() {
  # note: NF is the number of columns, so $NF gives us the last column
  lsof -a -p $1 -d cwd -n | tail -1 | awk '{print $1, "\t", $NF}'
}

# get the current working directory of a process listening to a port
portpwdx() {
  # pid=$(lsof -i :5858 | tail -1 | perl -pe 's/[^\s]+\s+([^\s]+)\s.*/$1/')
  pid=$(lsof -i :$1 | tail -1 | perl -pe 's/[^\s]+\s+([^\s]+)\s.*/$1/')
  if [[ ! -z $pid ]]; then
    echo $pid
    pwdx $pid
    return 0
  else
    echo "No process listening to port $1"
    return -1
  fi
}

# tabcolor function to change the color of the current iterm tab, 
# accepts color names or hex values, if no argument is given, a random color will be generated
tabcolor(){
  local input="$1"
  unset color input_lc colors
  
  # if no input, set random hex color
  if [[ -z "$input" ]]; then
    input=$(printf '#%06X' $((16#$(od -An -N2 -tx1 /dev/urandom | tr -d ' ')))) 
  fi
  
  input_lc=$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')
  colors="black|red|green|brown|yellow|blue|magenta|cyan|white|default"

  if [[ "$input_lc" =~ ^($colors)$ ]]; then
    case "$input_lc" in
      black) color="#000000" ;;
      red) color="#FF0000" ;;
      green) color="#00FF00" ;;
      brown) color="#A52A2A" ;;
      yellow) color="#FFFF00" ;;
      blue) color="#0000FF" ;;
      magenta) color="#FF00FF" ;;
      cyan) color="#00FFFF" ;;
      white) color="#FFFFFF" ;;
      default) color="#FFFFFF" ;;
    esac
  elif [[ "$input" =~ ^#[0-9a-fA-F]{6}$ ]]; then
    color="$input"
  else
    echo "Invalid color: $input. Please provide a valid color name or hex code with 6 digits."
    return 1
  fi

  printf "\033]6;1;bg;red;brightness;%d\007" $((16#${color:1:2})) # red
  printf "\033]6;1;bg;green;brightness;%d\007" $((16#${color:3:2})) # green
  printf "\033]6;1;bg;blue;brightness;%d\007" $((16#${color:5:2})) # blue
}
alias tc=tabcolor


# symlinks a binary to ~/.local/bin and creates the directory if it doesn't exist
binlink() {
  if [ $# -eq 0 ]; then
    echo "  "
    echo "  binlink is a wrapper around ln -s for linking executables to ~/.local/bin for easy access,"
    echo "  and to avoid conflicts with /usr/local/bin or /opt/homebrew/bin."
    echo "  ~/.local/bin should be in your PATH,"
    echo "  before the above directories to take precedence."
    echo "  "
    echo "  Usage: binlink <executable> [link_name]"
    echo "  Example: binlink myscript.sh myscript"
    echo "  if link_name is not provided, "
    echo "  the name of the executable will be used as the link name."
    return 1
  fi
    local target="$1"
    local abs_target
    abs_target="$(cd "$(dirname -- "$target")" && pwd)/$(basename -- "$target")"
    local link_name
    if [ -z "$2" ]; then
      link_name="$(basename -- "$target")"
    else
      link_name="$2"
    fi
    local link_path="$HOME/.local/bin/$link_name"

    if [ ! -e "$abs_target" ]; then
      echo "Error: Target '$abs_target' does not exist."
      return 1
    fi

    ln -sf "$abs_target" "$link_path"
    echo "Linked '$abs_target' to '$link_path'"
}



# unlinks a binary from ~/.local/bin
binunlink() {
  if [ $# -eq 0 ]; then
    echo "Usage: binunlink <link_name>"
    echo "See \`binlink\` for more details"
    return 1
  fi

  local link_name="$1"
  local link_path="$HOME/.local/bin/$link_name"

  if [ ! -e "$link_path" ]; then
    echo "Error: Link '$link_path' does not exist."
    return 1
  fi

  rm -f "$link_path"
  echo "Unlinked '$link_path'"
}