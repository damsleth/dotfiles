# zsh/late.zsh
# Sourced from .zshrc AFTER _main.zsh finishes loading every module — same
# position these lines used to occupy inline in .zshrc. Keep it that way:
# anything added here must genuinely need to run last, not just "somewhere".

# iTerm2 shell integration (only present when installed via iTerm2's menu)
test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

# rustup/uv-style installer snippet: appends to PATH only if not already present.
# env.zsh already adds ~/.local/bin and explicitly strips this literal
# "share/../bin" path form as a denormalized duplicate, so this is a no-op
# safety net for whatever tool's installer wrote it — keep the path as-is.
[ -s "$HOME/.local/share/../bin/env" ] && . "$HOME/.local/share/../bin/env"

# Azure Functions Core Tools: opt out of telemetry
export FUNCTIONS_CORE_TOOLS_TELEMETRY_OPTOUT=1

# Extra terminfo search path (kitty/ghostty custom entries)
export TERMINFO_DIRS="$HOME/.config/terminfo:"
