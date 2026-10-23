#!/usr/bin/env bash
# whyslow: snapshot what's eating the Mac and have a cheap model explain it.
#
#   whyslow          snapshot + diagnosis (claude -p, haiku, no tools) + token/cost footer
#   whyslow -n       print the snapshot only, no model call
#   WHYSLOW_MODEL=sonnet whyslow   use another model
set -u  # no pipefail: ps | head SIGPIPEs by design

snapshot() {
  echo "== machine"
  echo "ram_gb=$(( $(sysctl -n hw.memsize) / 1073741824 ))  cores=$(sysctl -n hw.ncpu)"
  uptime
  echo "== top summary (second sample; the first one's CPU is bogus)"
  top -l 2 -n 0 -s 1 | awk '/^Processes:/{n++} n==2' | grep -E '^(Processes|CPU usage|PhysMem|VM):'
  echo "== swap / pressure"
  sysctl -n vm.swapusage
  memory_pressure | tail -1
  pmset -g therm 2>/dev/null | grep -iv 'no .* recorded' || true
  # basenames only: full app paths cost tokens and say nothing
  echo "== top cpu (pid %cpu %mem rss_kb name)"
  ps -Ao pid=,pcpu=,pmem=,rss=,comm= -r | head -15 | awk '{n=$5; for(i=6;i<=NF;i++) n=n" "$i; sub(/.*\//,"",n); print $1,$2,$3,$4,n}'
  echo "== top memory"
  ps -Ao pid=,pcpu=,pmem=,rss=,comm= -m | head -15 | awk '{n=$5; for(i=6;i<=NF;i++) n=n" "$i; sub(/.*\//,"",n); print $1,$2,$3,$4,n}'
  echo "== most repeated process names (count total_rss_mb name)"
  ps -Ao rss=,comm= | awk '{n=$2; for(i=3;i<=NF;i++) n=n" "$i; sub(/.*\//,"",n); c[n]++; r[n]+=$1} END{for(n in c) if(c[n]>2) printf "%d %d %s\n", c[n], r[n]/1024, n}' | sort -rn | head -8
  echo "== vms / containers running"
  ps -Ao comm= | awk '{sub(/.*\//,""); if (tolower($0) ~ /^(com\.docker|docker|orbstack|qemu|utm|prl_|vmware|colima|limactl)|virtualmachine/) c[$0]++} END{for(n in c) print c[n], n; if (!length(c)) print "none"}'
}

PROMPT='You diagnose why a Mac feels sluggish from one resource snapshot. Reply in plain text for a terminal: no markdown headings, no tables, no em-dashes.

How to reason:
- Memory first. PhysMem "wired" is kernel and driver memory and can never be swapped. Compare wired to the sum of app RSS. If wired is huge (over ~40% of RAM) while apps are small and no VM or container is running, call it a kernel or driver leak; long uptime makes this likelier, and the fix is a reboot.
- Swap nearly full, low "free percentage", or many swapouts mean memory starvation: that alone explains sluggishness.
- CPU: ps %cpu over 100 means multiple cores. Name what the busy process is: corespotlightd/mds/mds_stores/mdworker = Spotlight indexing; routined = location learning; donotdisturbd = Focus; WindowServer = rendering (high with animated wallpapers, many displays or windows); kernel_task high = thermal throttling; VTDecoderXPCService = video decoding (often a live wallpaper or a video).
- Load average well above core count means CPU contention; well below it means the problem is memory or I/O, not CPU.
- Many copies of the same process (the repeated list) add up even when each is small.
- Only claim what the numbers show. Quote the numbers.

Output exactly:
1. One headline line: the main cause in plain words.
2. Three to six "- " bullets with causes, biggest first, each with its numbers.
3. "Fix:" then numbered steps in order of impact, each one line, concrete.'

if [[ "${1:-}" == "-n" ]]; then snapshot; exit; fi
for c in claude jq; do command -v $c >/dev/null || { echo "whyslow: $c not on PATH; try whyslow -n" >&2; exit 1; }; done
# --safe-mode: no hooks, plugins, skills, MCP or CLAUDE.md; --tools "": it only reads text
# json output carries usage; costUSD is list price, not what a subscription bills
snapshot | claude -p --model "${WHYSLOW_MODEL:-haiku}" --safe-mode --tools "" --no-session-persistence \
    --output-format json --system-prompt "$PROMPT" |
  jq -r '.result, "", (.usage | "-- tokens: \(.input_tokens + .cache_read_input_tokens + .cache_creation_input_tokens) in (\(.cache_read_input_tokens) cache read, \(.cache_creation_input_tokens) cache write), \(.output_tokens) out"), "-- cost: $\(.total_cost_usd * 10000 | round / 10000) (list price)"'
