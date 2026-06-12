# ~/.zsh/secrets.zsh -- 1Password secrets, cached in the macOS login keychain
#
# The op:// reference *paths* below are NOT secrets and are safe to commit.
# Real values are resolved via the 1Password CLI (Touch ID with desktop-app
# integration on, or `opinit` once per session without it -- see comp.zsh),
# then cached in the login keychain. macOS unlocks that keychain at logon, so
# new shells export the cached values silently; `op` is only consulted on a
# cache miss. After rotating a key in 1Password, run `secret --sync`.
#
# Note: cached values are readable without a prompt by anything running as
# your user (`security find-generic-password`) -- the same exposure as
# exporting them from .zshrc, which is the point.

# name -> 1Password reference
typeset -gA OP_SECRETS=(
  # OPENAI_API_KEY        "op://Employee/Openai/llm_iterm2"
  # ANTHROPIC_API_KEY     "op://Employee/Anthropic Claude API/Obsidian-2026"
  CLOUDFLARE_API_TOKEN  "op://Employee/cloudflare/KMBP Cloudflare Pages API token"
  THINGS_AUTH_TOKEN     "op://Employee/THINGS_AUTH_TOKEN/password"
)

# secret                 -> list known secret names
# secret NAME            -> resolve (keychain, then 1Password) and export NAME
# secret NAME -p         -> print the value instead of exporting
# secret -a | --all      -> export every known secret
# secret --sync          -> re-read everything from 1Password, refresh the cache
# secret --forget [NAME] -> drop NAME (or everything) from the keychain cache
secret() {
  # no args: list available names
  if [[ -z $1 ]]; then
    print -l -- ${(ok)OP_SECRETS}
    return 0
  fi

  local name
  case $1 in
    -a|--all)
      for name in ${(k)OP_SECRETS}; do secret "$name" || return; done
      return 0 ;;
    --sync)
      for name in ${(k)OP_SECRETS}; do secret "$name" --fresh || return; done
      return 0 ;;
    --forget)
      for name in ${2:-${(k)OP_SECRETS}}; do
        security delete-generic-password -a "$USER" -s "zsh-secret-$name" >/dev/null 2>&1
      done
      return 0 ;;
  esac

  local ref=${OP_SECRETS[$1]}
  [[ -z $ref ]] && { print -u2 "secret: unknown '$1' (run 'secret' to list)"; return 1; }

  local val
  # keychain first (silent -- the login keychain is unlocked at logon) ...
  if [[ $2 != --fresh ]]; then
    val=$(security find-generic-password -a "$USER" -s "zsh-secret-$1" -w 2>/dev/null)
  fi
  # ... then 1Password, caching the result for future shells
  if [[ -z $val ]]; then
    (( $+commands[op] )) || { print -u2 "secret: 1Password CLI (op) not installed"; return 1; }
    val=$(op read "$ref") || { print -u2 "secret: failed to read $1"; return 1; }
    security add-generic-password -U -a "$USER" -s "zsh-secret-$1" -w "$val" 2>/dev/null
  fi

  if [[ $2 == (-p|--print) ]]; then
    print -r -- "$val"
  else
    export "$1=$val"
  fi
}

# Export cached secrets into every new shell. Keychain-only -- never triggers
# 1Password -- and skips names already inherited from a parent shell (tmux,
# nested zsh), so only cold terminal windows pay the ~10ms/secret lookup.
() {
  local name val
  for name in ${(k)OP_SECRETS}; do
    [[ -n ${(P)name} ]] && continue
    val=$(security find-generic-password -a "$USER" -s "zsh-secret-$name" -w 2>/dev/null) || continue
    [[ -n $val ]] && export "$name=$val"
  done
}

# Complete `secret` with the known names. Guarded so load order doesn't matter.
_secret() { compadd -- ${(k)OP_SECRETS} }
(( $+functions[compdef] )) && compdef _secret secret
