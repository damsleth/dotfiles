#!/usr/bin/env bash
# tccrm — remove apps from macOS Privacy & Security listings (the TCC database).
set -euo pipefail

usage() { cat <<'H'
tccrm — remove apps from macOS Privacy & Security listings (TCC)

usage: tccrm [pattern]          pick apps (one line per app, all its permissions), delete
       tccrm --rows [pattern]   pick individual permission rows instead
       tccrm --stale            pick apps whose binary/bundle no longer exists on disk
       tccrm --all <client>     drop every permission for one bundle id or path, no prompt
       tccrm -h | --help

fzf: tab = multi-select, enter = delete, esc = abort. Confirms before deleting.
Backups of the user db: ~/.cache/tccrm/. Reopen System Settings to see changes.
The terminal running this needs Full Disk Access.

what macOS lets us delete:
  user db  (Files & Folders, Media, Apple Events, App Data, ...)   yes, via sqlite
  system db, bundle id (FDA, Accessibility, Screen Recording, ...) yes, via tccutil reset
  system db, bare path (e.g. ~/.local/share/claude/versions/2.1.x) NO — SIP-protected and
      tccutil only takes bundle ids. tccrm opens the right System Settings pane so you
      can press minus. `sudo tccutil reset SystemPolicyAllFiles` wipes ALL FDA grants.
  Location Services toggles live in locationd, not TCC. Not covered.
H
}

USER_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
SYS_DB="/Library/Application Support/com.apple.TCC/TCC.db"
BAK="$HOME/.cache/tccrm"

# rows: db(u|s) \t service \t client \t client_type(0=bundle,1=path)
rows() {
  local q="select '%s', replace(service,'kTCCService',''), client, client_type from access order by client, service"
  sqlite3 -separator $'\t' "$USER_DB" "$(printf "$q" u)"
  sqlite3 -separator $'\t' "$SYS_DB"  "$(printf "$q" s)"
}
# grouped: client \t client_type \t services
grouped() {
  local q="select client, client_type, group_concat(distinct replace(service,'kTCCService','')) from access group by client"
  { sqlite3 -separator $'\t' "$USER_DB" "$q"; sqlite3 -separator $'\t' "$SYS_DB" "$q"; } |
    awk -F'\t' '{k=$1 FS $2; s[k]=(k in s)? s[k]","$3 : $3} END{for(k in s) print k FS s[k]}' | sort
}
exists() { # client client_type
  case "$1" in com.apple.*|/System/*) return 0;; esac  # not Spotlight-indexed
  if [ "$2" = 1 ]; then [ -e "$1" ]
  else [ -n "$(mdfind "kMDItemCFBundleIdentifier == '$1'" | head -1)" ]
  fi
}
esc() { printf %s "${1//\'/\'\'}"; }

open_pane() { # service
  local p; case "$1" in
    SystemPolicyAllFiles) p=Privacy_AllFiles;; ScreenCapture) p=Privacy_ScreenCapture;;
    ListenEvent) p=Privacy_ListenEvent;; SystemPolicyDeveloperFiles) p=Privacy_DevTools;;
    *) p="Privacy_$1";;   --stale) picked=$(grouped | while IFS=$'\t' read -r client ctype svcs; do
             exists "$client" "$ctype" || printf '%s\t%s\t%s\n' "$client" "$ctype" "$svcs"; done)
           [ -n "$picked" ] || { echo "nothing stale"; exit 0; } ;;
  *)      picked=$(grouped | grep -i -- "${1:-}" | "${FZF[@]}" --with-nth=1,3) || exit 0 ;;
esac
[ -n "${picked:-}" ] || exit 0
echo "$picked" | cut -f1,3; confirm "app(s)" "$(echo "$picked" | wc -l | tr -d ' ')"
echo "$picked" | while IFS=$'\t' read -r client _ _; do del_client "$client"; done
  open "x-apple.systempreferences:com.apple.preference.security?$p"
}

# delete every row for a client: prints what it could not delete
del_client() { # client
  sqlite3 "$USER_DB" "delete from access where client='$(esc "$1")'"
  sqlite3 -separator $'\t' "$SYS_DB" "select replace(service,'kTCCService',''), client_type from access where client='$(esc "$1")'" |
  while IFS=$'\t' read -r svc ctype; do
    if [ "$ctype" = 0 ]; then sudo tccutil reset "$svc" "$1"
    else echo "CANNOT (system db, bare path): $svc $1 — opening System Settings, press minus"; open_pane "$svc"; fi
  done
}
del_row() { # db service client client_type
  if [ "$1" = u ]; then sqlite3 "$USER_DB" "delete from access where service='kTCCService$2' and client='$(esc "$3")'"
  elif [ "$4" = 0 ]; then sudo tccutil reset "$2" "$3"
  else echo "CANNOT (system db, bare path): $2 $3 — opening System Settings, press minus"; open_pane "$2"; fi
}
confirm() { # label count
  printf '\ndelete %s %s? [y/N] ' "$2" "$1"; read -r yn; [[ "$yn" =~ ^[Yy] ]] || exit 1
  mkdir -p "$BAK"; cp "$USER_DB" "$BAK/tcc-user-$(date +%Y%m%d-%H%M%S).db"
}
FZF=(fzf -m --delimiter=$'\t' --header='tab: select, enter: delete, esc: abort')

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --all)  [ -n "${2:-}" ] || { usage; exit 1; }
          if [[ "$2" = /* ]]; then del_client "$2"; else sudo tccutil reset All "$2"; fi ;;
  --rows) picked=$(rows | grep -i -- "${2:-}" | "${FZF[@]}" --with-nth=1,2,3) || exit 0
          echo "$picked" | cut -f1-3; confirm "row(s)" "$(echo "$picked" | wc -l | tr -d ' ')"
          echo "$picked" | while IFS=$'\t' read -r db svc client ctype; do del_row "$db" "$svc" "$client" "$ctype"; done ;;
  --stale) picked=$(grouped | while IFS=$'\t' read -r client ctype svcs; do
             exists "$client" "$ctype" || printf '%s\t%s\t%s\n' "$client" "$ctype" "$svcs"; done)
           [ -n "$picked" ] || { echo "nothing stale"; exit 0; } ;;
  *)      picked=$(grouped | grep -i -- "${1:-}" | "${FZF[@]}" --with-nth=1,3) || exit 0 ;;
esac
[ -n "${picked:-}" ] || exit 0
echo "$picked" | cut -f1,3; confirm "app(s)" "$(echo "$picked" | wc -l | tr -d ' ')"
echo "$picked" | while IFS=$'\t' read -r client _ _; do del_client "$client"; done
