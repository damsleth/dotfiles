#!/usr/bin/env bash
# test-bootstrap-container.sh - run _scripts/bootstrap-fresh-linux.sh end-to-end
# in a throwaway Ubuntu container (podman), with per-step timing. Linux host.
#
# Why: the Linux orchestrator chains apt/snap installs, language-manager
# bootstraps, stow, and the restore scripts. This exercises the whole thing on
# a clean box without touching the host, and reports how long each step took.
# See _scripts/TESTING.md for the full writeup.
#
# Usage:
#   _scripts/test-bootstrap-container.sh
#
# Optionally JIT-inject an SSH key so the private-repo clones + the editable
# tools-restore step actually run (otherwise they degrade to warnings - the
# container has no GitHub auth). The key is read into a 0600 tempfile, mounted
# read-only, copied into the container user's ~/.ssh, and the container runs
# --rm so it vanishes on exit. The key is NEVER written into the repo or logged.
# Prefer a dedicated read-only deploy key over your personal key.
#
#   # from 1Password (op CLI must be signed in):
#   SSH_TEST_KEY_OP_REF='op://Vault/GitHub deploy key/private key' \
#       _scripts/test-bootstrap-container.sh
#
#   # from a key file on the host:
#   SSH_TEST_KEY_FILE=~/.ssh/throwaway_ed25519 \
#       _scripts/test-bootstrap-container.sh
#
# Env knobs:
#   PODMAN     container CLI (default "sudo podman" for reliable rootful
#              networking; set PODMAN=podman to use rootless)
#   IMAGE      image (default docker.io/library/ubuntu:24.04)
#   KEEP_LOG   if non-empty, keep the timestamped log and print its path

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PODMAN="${PODMAN:-sudo podman}"
IMAGE="${IMAGE:-docker.io/library/ubuntu:24.04}"

command -v "${PODMAN%% *}" >/dev/null 2>&1 || {
    echo "[err] '${PODMAN%% *}' not found - install podman (or set PODMAN=)" >&2; exit 1; }

# --- temp artifacts, cleaned on exit ----------------------------------------
KEY_TMP=""
ENTRY_TMP="$(mktemp)"
LOG="$(mktemp "${TMPDIR:-/tmp}/dotfiles-bootstrap-test.XXXXXX.log")"
cleanup() {
    [[ -n "$KEY_TMP" && -f "$KEY_TMP" ]] && rm -f "$KEY_TMP"
    rm -f "$ENTRY_TMP"
    if [[ -n "${KEEP_LOG:-}" ]]; then echo "[log] $LOG"; else rm -f "$LOG"; fi
}
trap cleanup EXIT

# --- resolve the optional SSH key (1Password ref or file) -------------------
HAVE_KEY=0
if [[ -n "${SSH_TEST_KEY_OP_REF:-}" ]]; then
    command -v op >/dev/null 2>&1 || {
        echo "[err] op (1Password CLI) not found, needed for SSH_TEST_KEY_OP_REF" >&2; exit 1; }
    KEY_TMP="$(mktemp)"; chmod 600 "$KEY_TMP"
    op read "$SSH_TEST_KEY_OP_REF" > "$KEY_TMP" || { echo "[err] op read failed" >&2; exit 1; }
    HAVE_KEY=1
    echo "[info] SSH key sourced from 1Password"
elif [[ -n "${SSH_TEST_KEY_FILE:-}" ]]; then
    [[ -f "$SSH_TEST_KEY_FILE" ]] || { echo "[err] SSH_TEST_KEY_FILE not found: $SSH_TEST_KEY_FILE" >&2; exit 1; }
    KEY_TMP="$(mktemp)"; chmod 600 "$KEY_TMP"; cat "$SSH_TEST_KEY_FILE" > "$KEY_TMP"
    HAVE_KEY=1
    echo "[info] SSH key sourced from file"
else
    echo "[info] no SSH key provided - private clones + tools-restore will warn-skip"
fi

# --- in-container entrypoint (literal heredoc; runs as root, drops to tester) -
# Quoted 'ENTRY' so nothing expands on the host; $HAVE_KEY arrives via -e.
cat > "$ENTRY_TMP" <<'ENTRY'
#!/usr/bin/env bash
set -u
export DEBIAN_FRONTEND=noninteractive
T0=$EPOCHSECONDS
stamp() { printf '[harness +%ds] %s\n' "$((EPOCHSECONDS - T0))" "$*"; }

stamp "===== preparing container ====="
P0=$EPOCHSECONDS
apt-get update -qq
PKGS="sudo ca-certificates"
[[ "${HAVE_KEY:-0}" == "1" ]] && PKGS="$PKGS openssh-client"
apt-get install -y -qq $PKGS >/dev/null

useradd -m -s /bin/bash tester
echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/tester
chmod 0440 /etc/sudoers.d/tester
mkdir -p /home/tester/Code
cp -a /host-dotfiles /home/tester/Code/dotfiles

if [[ "${HAVE_KEY:-0}" == "1" && -f /sshkey ]]; then
    install -d -m 700 -o tester -g tester /home/tester/.ssh
    install -m 600 -o tester -g tester /sshkey /home/tester/.ssh/id_ed25519
    ssh-keyscan -H github.com 2>/dev/null >> /home/tester/.ssh/known_hosts || true
    stamp "SSH key installed for tester (private clones enabled)"
fi
chown -R tester:tester /home/tester
stamp "container prep done in $((EPOCHSECONDS - P0))s"
echo

stamp "===== running bootstrap-fresh-linux.sh as 'tester' ====="
B0=$EPOCHSECONDS
# Prefix each orchestrator line with elapsed seconds so the host can compute
# per-step durations from the [boot] anchors.
su - tester -c 'export GIT_TERMINAL_PROMPT=0 HOSTNAME_DEFAULT= DOTFILES_DIR=$HOME/Code/dotfiles; timeout 1500 bash "$DOTFILES_DIR/_scripts/bootstrap-fresh-linux.sh"' 2>&1 \
  | while IFS= read -r line; do printf '[%ds] %s\n' "$((EPOCHSECONDS - B0))" "$line"; done
rc=${PIPESTATUS[0]}
echo
stamp "orchestrator exit code: $rc (total $((EPOCHSECONDS - B0))s)"
echo

stamp "===== post-run sanity ====="
echo "-- fnm reachable in a login shell (only Node v26 expected) --"
ls -l /home/tester/.local/bin/fnm 2>&1 | sed 's/^/   /'
su - tester -c 'command -v fnm && fnm list' 2>&1 | sed 's/^/   /'
echo "-- node / go / rustc --"
su - tester -c 'eval "$(fnm env)" 2>/dev/null; command -v node && node --version; command -v go && go version; command -v rustc && rustc --version' 2>&1 | sed 's/^/   /'
echo "-- editable local tools on PATH (only if an SSH key was provided) --"
su - tester -c 'manifest=$HOME/Code/dotfiles/private/_scripts/local-tools.txt; if [ -f "$manifest" ]; then sed "s/#.*//" "$manifest" | xargs -n1 sh -c '''[ -n "$0" ] && command -v "$0" >/dev/null 2>&1 && echo "present: $0"'''; fi' 2>&1 | sed 's/^/   /'
echo "===== [harness] done ====="
ENTRY

# --- run --------------------------------------------------------------------
PODMAN_ARGS=(run --rm
    -e "HAVE_KEY=$HAVE_KEY"
    -v "$REPO_DIR:/host-dotfiles:ro"
    -v "$ENTRY_TMP:/entry.sh:ro")
[[ $HAVE_KEY -eq 1 ]] && PODMAN_ARGS+=(-v "$KEY_TMP:/sshkey:ro")
PODMAN_ARGS+=("$IMAGE" bash /entry.sh)

echo "[info] image=$IMAGE  repo=$REPO_DIR  podman='$PODMAN'"
H0=$(date +%s)
$PODMAN "${PODMAN_ARGS[@]}" 2>&1 | tee "$LOG"
WALL=$(( $(date +%s) - H0 ))

# --- per-step timing summary (parsed from the [boot] anchors) ---------------
echo
echo "================= per-step timing ================="
end_t="$(grep -aoE '\(total [0-9]+s\)' "$LOG" | grep -oE '[0-9]+' | tail -1)"
prev_t=""; prev_label=""
while IFS= read -r raw; do
    clean="$(printf '%s' "$raw" | sed -E 's/\x1b\[[0-9;]*m//g')"
    t="$(printf '%s' "$clean" | sed -E 's/^\[([0-9]+)s\].*/\1/')"
    label="$(printf '%s' "$clean" | sed -E 's/^\[[0-9]+s\] *\[boot\] *//')"
    [[ -n "$prev_t" ]] && printf '  %5ds  %s\n' "$((t - prev_t))" "$prev_label"
    prev_t="$t"; prev_label="$label"
done < <(grep -aE '^\[[0-9]+s\] .*\[boot\]' "$LOG")
[[ -n "$prev_t" && -n "$end_t" ]] && printf '  %5ds  %s\n' "$((end_t - prev_t))" "$prev_label"
echo "  -----"
grep -aoE 'container prep done in [0-9]+s' "$LOG" | tail -1 | sed 's/^/  /'
grep -aoE 'orchestrator exit code: [0-9]+ \(total [0-9]+s\)' "$LOG" | tail -1 | sed 's/^/  /'
echo "  host wall: ${WALL}s"
echo "==================================================="
