# ~/.zshenv — read by EVERY zsh (login or not, interactive or not). Keep it minimal.
#
# Unlike .zshrc/_main.zsh (interactive-only), this is the sole user file a
# non-interactive, non-login shell reads — e.g. the shells Claude Code / tooling
# spawn. Point SSH_AUTH_SOCK at the 1Password agent so its consumers work in
# those shells too — notably git's op-ssh-sign commit signing, which otherwise
# hits the empty launchd agent and dies with "1Password: failed to fill whole
# buffer". Interactive ssh already uses the IdentityAgent line in ssh_config.
if [[ "$OSTYPE" == darwin* ]]; then
  _op_sock="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
  [[ -S "$_op_sock" ]] && export SSH_AUTH_SOCK="$_op_sock"
  unset _op_sock
fi
