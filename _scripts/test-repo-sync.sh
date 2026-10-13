#!/usr/bin/env bash
# Self-check for repo-sync.sh: config exclusion, state.json shape, --configure toggle+persist.
# ponytail: fake repos in a tmpdir, no network. Run: ./test-repo-sync.sh
set -euo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/repo-sync.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/code/a" "$T/code/b/nested"
for d in a b/nested; do (cd "$T/code/$d"; git init -q; git commit -q --allow-empty -m init); done
echo dirt > "$T/code/a/f.txt"
export CODE_DIR="$T/code" REPO_SYNC_CONFIG="$T/config.json" REPO_SYNC_STATE="$T/state.json"

"$S" >/dev/null
jq -e '.repos|length==2' "$REPO_SYNC_STATE" >/dev/null
jq -e '.last_sync|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")' "$REPO_SYNC_STATE" >/dev/null
jq -e '.repos["a"].dirty_files==1 and .repos["a"].state=="dirty"' "$REPO_SYNC_STATE" >/dev/null
jq -e '.repos["b/nested"].state=="clean" and .repos["b/nested"].included' "$REPO_SYNC_STATE" >/dev/null

# --configure: j moves to b/nested, space deselects, q saves
printf 'j\x20q' | "$S" --configure >/dev/null
jq -e '.excluded==["b/nested"]' "$REPO_SYNC_CONFIG" >/dev/null
# arrow keys reach the same row
printf '\x1b[B\x20q' | "$S" --configure >/dev/null
jq -e '.excluded==[]' "$REPO_SYNC_CONFIG" >/dev/null

# deselected repo is reported and skipped
echo '{"excluded":["b/nested"]}' > "$REPO_SYNC_CONFIG"
"$S" >/dev/null
jq -e '.counts.deselected==1 and .repos["b/nested"].included==false' "$REPO_SYNC_STATE" >/dev/null

"$S" --dry-run >/dev/null
jq -e '.mode=="dry-run"' "$REPO_SYNC_STATE" >/dev/null

# --- tree view: folder rows aggregate, repo+folder paths get their own row -----
T2="$(mktemp -d)"; trap 'rm -rf "$T" "$T2"' EXIT
mkdir -p "$T2/code/grp/one" "$T2/code/grp/two" "$T2/code/grp-x" "$T2/code/solo"
for d in grp grp/one grp/two grp-x solo; do
  (cd "$T2/code/$d"; git init -q; git commit -q --allow-empty -m init)
done
export CODE_DIR="$T2/code" REPO_SYNC_CONFIG="$T2/config.json" REPO_SYNC_STATE="$T2/state.json"

# parents before children, subtrees contiguous ("grp-x" must not land inside "grp/"),
# and "grp" (repo *and* folder) gets both a folder row and its own repo row
rendered="$(printf 'q' | "$S" --configure |
  sed $'s/\e\\[[0-9;?]*[a-zA-Z]//g' | sed -n '/\[.\] /{s/^ *\[.\] //;s/ *$//;p;}' | tr '\n' ',')"
[ "$rendered" = "grp/,grp,one,two,grp-x,solo," ] || {
  printf 'unexpected tree rows: %s\n' "$rendered" >&2; exit 1; }

# cursor starts on the "grp/" folder row: space deselects grp + grp/one + grp/two only
printf '\x20q' | "$S" --configure >/dev/null
jq -e '.excluded==["grp","grp/one","grp/two"]' "$REPO_SYNC_CONFIG" >/dev/null

# the repo row for "grp" toggles just that repo -> folder goes mixed
printf 'j\x20q' | "$S" --configure >/dev/null
jq -e '.excluded==["grp/one","grp/two"]' "$REPO_SYNC_CONFIG" >/dev/null

# a mixed folder toggles ON, not OFF
printf '\x20q' | "$S" --configure >/dev/null
jq -e '.excluded==[]' "$REPO_SYNC_CONFIG" >/dev/null

echo "repo-sync self-check: OK"
