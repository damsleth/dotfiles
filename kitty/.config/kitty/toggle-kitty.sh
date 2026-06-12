#!/bin/sh
# Toggle kitty visibility: hide when frontmost, otherwise bring to front.
# Launches kitty if it isn't running. Bound to opt+space via skhd (~/.config/skhd/skhdrc).
osascript <<'EOF'
tell application "System Events"
    if (count of (processes whose bundle identifier is "net.kovidgoyal.kitty")) is 0 then
        do shell script "open -a kitty"
        return
    end if
    set kittyProc to first process whose bundle identifier is "net.kovidgoyal.kitty"
    if frontmost of kittyProc then
        set visible of kittyProc to false
    else
        set frontmost of kittyProc to true
    end if
end tell
EOF
