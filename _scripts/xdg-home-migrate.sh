#!/usr/bin/env bash
set -euo pipefail

# Move high-confidence dot-folder state/caches out of $HOME into XDG locations.
# Default is dry-run. Run with --apply to move data.

APPLY=0
if [[ "${1:-}" == "--apply" ]]; then
  APPLY=1
elif [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
Usage: xdg-home-migrate.sh [--apply]

Dry-run by default. With --apply, copies/merges data to XDG locations and then
moves the old root dot-dir/subdir into ~/.xdg-migration-backups/<timestamp>/ so
$HOME is uncluttered but rollback remains easy.
EOF
  exit 0
fi

HOME_DIR="${HOME:?}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME_DIR/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME_DIR/.local/share}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME_DIR/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME_DIR/.local/state}"
BACKUP_ROOT="$XDG_STATE_HOME/xdg-home-migration/backups/$(date +%Y%m%d-%H%M%S)"

say() { printf '%s\n' "$*"; }
run() {
  if (( APPLY )); then
    say "+ $*"
    "$@"
  else
    say "DRY + $*"
  fi
}

ensure_parent() {
  local path="$1"
  run mkdir -p "$(dirname "$path")"
}

backup_path() {
  local src="$1"
  [[ -e "$src" || -L "$src" ]] || return 0
    local rel="${src#"$HOME_DIR"/}"
  local dest="$BACKUP_ROOT/$rel"
  ensure_parent "$dest"
  run mv "$src" "$dest"
}

merge_dir_then_backup() {
  local src="$1"
  local dest="$2"
  [[ -d "$src" && ! -L "$src" ]] || { say "skip: $src not present"; return 0; }
  say "merge: $src -> $dest"
  run mkdir -p "$dest"
  # rsync preserves contents and handles existing destination dirs better than mv.
  run rsync -a "$src/" "$dest/"
  backup_path "$src"
}

move_dir_if_target_absent_else_merge() {
  local src="$1"
  local dest="$2"
  [[ -d "$src" && ! -L "$src" ]] || { say "skip: $src not present"; return 0; }
  if [[ -e "$dest" || -L "$dest" ]]; then
    merge_dir_then_backup "$src" "$dest"
  else
    say "move: $src -> $dest"
    ensure_parent "$dest"
    run mv "$src" "$dest"
  fi
}

remove_ds_store_and_empty_parents() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  [[ -f "$dir/.DS_Store" ]] && run rm -f "$dir/.DS_Store"
  if [[ -z "$(find "$dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    backup_path "$dir"
  else
    say "left: $dir still has non-migrated content"
  fi
}

say "Mode: $([[ $APPLY -eq 1 ]] && echo apply || echo dry-run)"
say "Backup root: $BACKUP_ROOT"
say ""

# Package/tool caches and toolchains.
move_dir_if_target_absent_else_merge "$HOME_DIR/.npm" "$XDG_CACHE_HOME/npm"
move_dir_if_target_absent_else_merge "$HOME_DIR/.platformio" "$XDG_DATA_HOME/platformio"
move_dir_if_target_absent_else_merge "$HOME_DIR/.espressif" "$XDG_DATA_HOME/espressif"

# Azure CLI honors AZURE_CONFIG_DIR. Some related Azure tools may still create their own dot dirs.
move_dir_if_target_absent_else_merge "$HOME_DIR/.azure" "$XDG_CONFIG_HOME/azure"

# Bun/Gem already have XDG env vars in zsh; merge old leftovers if any.
move_dir_if_target_absent_else_merge "$HOME_DIR/.bun" "$XDG_DATA_HOME/bun"
move_dir_if_target_absent_else_merge "$HOME_DIR/.gem" "$XDG_DATA_HOME/gem"

# Bundler split: cache to XDG cache, config/plugin are configured separately going forward.
move_dir_if_target_absent_else_merge "$HOME_DIR/.bundle/cache" "$XDG_CACHE_HOME/bundle"
remove_ds_store_and_empty_parents "$HOME_DIR/.bundle"

# NuGet split: packages/http cache go to cache; config goes to ~/.config/NuGet.
move_dir_if_target_absent_else_merge "$HOME_DIR/.nuget/packages" "$XDG_CACHE_HOME/NuGet/packages"
move_dir_if_target_absent_else_merge "$HOME_DIR/.nuget/NuGet" "$XDG_CONFIG_HOME/NuGet"
remove_ds_store_and_empty_parents "$HOME_DIR/.nuget"

say ""
say "Done. If this was a dry-run, rerun with: $0 --apply"
say "After applying: open a new shell and test npm/dotnet/pio/idf.py/az. Backups stay under $BACKUP_ROOT."
