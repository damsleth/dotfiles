#!/usr/bin/env bash
# permissions-checklist.sh - low-friction checklist for macOS approvals that
# cannot be fully granted from a shell script.

set -euo pipefail

info() { printf '\033[1;34m[perm]\033[0m %s\n' "$*"; }
pass() { printf '\033[1;32m[ok]\033[0m   %s\n' "$*"; }
warn() { printf '\033[1;33m[todo]\033[0m %s\n' "$*"; }

if [[ "$(uname -s)" != "Darwin" ]]; then
    info "Not macOS - no permissions checklist needed."
    exit 0
fi

app_present() {
    local app="$1"
    [[ -d "/Applications/$app.app" || -d "$HOME/Applications/$app.app" ]]
}

info "System extensions and background items"
if systemextensionsctl list 2>/dev/null | grep -qi "karabiner"; then
    pass "Karabiner system extension appears registered"
else
    warn "Approve Karabiner in System Settings -> Privacy & Security / Login Items & Extensions"
fi

if app_present "Tailscale"; then
    if pgrep -qx "Tailscale"; then
        pass "Tailscale is running"
    else
        warn "Open Tailscale once and approve VPN/background item prompts"
    fi
fi

if app_present "LuLu"; then
    if systemextensionsctl list 2>/dev/null | grep -qi "lulu"; then
        pass "LuLu system extension appears registered"
    else
        warn "Open LuLu once and approve its Network Extension"
    fi
fi

info "App permission grants"
if app_present "1Password"; then
    if [[ -S "$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock" ]]; then
        pass "1Password SSH agent socket exists"
    else
        warn "Open 1Password -> Settings -> Developer -> enable SSH Agent"
    fi
fi

for app in Rectangle Stats Karabiner-Elements; do
    if app_present "$app"; then
        warn "Open $app once and grant requested Accessibility/Notifications/Login Item permissions"
    fi
done

info "Manual System Settings pages worth checking"
cat <<'EOF'
  - Privacy & Security -> Accessibility: Rectangle, Karabiner, Stats if requested
  - Privacy & Security -> Full Disk Access: Terminal/Ghostty, VS Code, backup tools if needed
  - Privacy & Security -> Developer Tools: Terminal/Ghostty, VS Code
  - Login Items & Extensions: 1Password, Tailscale, Karabiner, LuLu, helper tools
  - Network -> VPN: Tailscale connected and trusted
EOF
