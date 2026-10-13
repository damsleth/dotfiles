#!/usr/bin/env bash
# Self-check for freespace.py: dry-run safety, defaults, age filters, protection rules, config + TUI behaviour.
# ponytail: fake HOME + stubbed tools (getconf too, so the real temp dir is never touched). Run: ./test-freespace.sh
set -euo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/freespace.py"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'chmod -R u+w "$T"; rm -rf "$T"' EXIT
export S HOME="$T/home" FAKE_TMP="$T/var/T/" PATH="$T/bin:$PATH"
CFG="$HOME/.config/freespace/config.json"
mkdir -p "$T/bin" "$T/var/T" "$T/var/X/com.microsoft.edgemac.code_sign_clone" "$T/uvcache" \
  "$HOME"/{.npm/_cacache,.cache/npm,.Trash,.cache/huggingface,Library/Logs,Library/Caches/Homebrew,.config/freespace} \
  "$HOME"/code/{app,keep}/node_modules
for c in brew dotnet pnpm go docker; do printf '#!/bin/sh\ntouch "%s/ran-%s"\n' "$T" "$c" >"$T/bin/$c"; done
# uv reports a non-default cache dir, like UV_CACHE_DIR would
printf '#!/bin/sh\n[ "$*" = "cache dir" ] && { echo "%s/uvcache"; exit; }\ntouch "%s/ran-uv"\n' "$T" "$T" >"$T/bin/uv"
printf '#!/bin/sh\necho "$FAKE_TMP"\n' >"$T/bin/getconf"
printf '#!/bin/sh\n[ "$1" = env ] && exit\ntouch "%s/ran-go"\n' "$T" >"$T/bin/go"   # "go env" is a query, not a cleanup
chmod +x "$T/bin"/*
# existing config with a protected project; new targets (nuget, trash, tmp, ...) fall back to defaults
printf '{"targets":{"homebrew":true},"skip_projects":["%s"]}\n' "$HOME/code/keep" >"$CFG"
touch "$HOME"/.cache/npm/a "$HOME"/.npm/_cacache/b "$HOME"/.Trash/c "$HOME"/.cache/huggingface/m \
  "$HOME"/code/{app,keep}/node_modules/x "$T/var/T/new" "$HOME/Library/Logs/new" "$T/uvcache/u" \
  "$HOME"/code/app/{legacy.py,legacy.pyc}
touch -t 202001010000 "$T/var/T/old" "$HOME/Library/Logs/old" "$HOME/olddoc"
# a dir name with a newline must not turn into "app2" + "/node_modules"
mkdir -p "$HOME/code/app2"$'\n'/node_modules "$HOME/code/app2"; touch "$HOME/code/app2/src.txt"
# installed egg-info inside a venv stays, project build output goes
mkdir -p "$HOME/code/py/.venv/lib/python3.14/site-packages/pkg.egg-info" "$HOME/code/py/pkg.egg-info"
touch "$HOME/code/py/.venv/pyvenv.cfg"
# protecting something inside an artifact keeps the whole artifact
mkdir -p "$HOME/code/app3/node_modules/vendor/keep"

gone() { [ ! -e "$1" ] || { echo "FAIL: $1 still exists"; exit 1; }; }
kept() { [ -e "$1" ] || { echo "FAIL: $1 was removed"; exit 1; }; }
fails() { if "$@" </dev/null >/dev/null 2>&1; then echo "FAIL: should have failed: $*"; exit 1; fi; }

# dry-run, -c without a tty, unknown or trailing flags: nothing deleted
"$S" --dry-run >/dev/null
fails "$S" -c
fails "$S" -c-typo
fails "$S" config --dry-run
fails "$S" -h --bogus
kept "$HOME/.cache/npm/a"; kept "$HOME/code/app/node_modules"

# broken or mistyped config aborts before cleaning anything
cp "$CFG" "$T/cfg.good"
echo '{"targets":{"homebrew":tru' >"$CFG";        fails "$S" -f
echo '{"targets":{"trash":"false"}}' >"$CFG";     fails "$S" -f
echo '{"scan_roots":["~"]}' >"$CFG";              fails "$S" -f
kept "$HOME/.Trash/c"; kept "$HOME/code/app/node_modules"
cp "$T/cfg.good" "$CFG"
python3 -I -c 'import json,sys; c=json.load(open(sys.argv[1])); c["skip_projects"].append(sys.argv[2]); json.dump(c,open(sys.argv[1],"w"))' \
  "$CFG" "$HOME/code/app3/node_modules/vendor/keep"

# N at the prompt aborts
echo n | "$S" >/dev/null; kept "$HOME/.cache/npm/a"

# $TMPDIR pointing at ~ is ignored; getconf decides
echo y | TMPDIR="$HOME" "$S" >/dev/null
gone "$HOME/.cache/npm"; gone "$HOME/.npm/_cacache"; gone "$T/var/X/com.microsoft.edgemac.code_sign_clone"
gone "$HOME/.Trash/c"; kept "$HOME/.Trash"; kept "$HOME/olddoc"
gone "$T/var/T/old"; kept "$T/var/T/new"; gone "$HOME/Library/Logs/old"; kept "$HOME/Library/Logs/new"
gone "$HOME/code/app/node_modules"; kept "$HOME/code/keep/node_modules/x"; kept "$HOME/code/app3/node_modules/vendor/keep"
gone "$HOME/code/app/legacy.pyc"; kept "$HOME/code/app/legacy.py"
gone "$HOME/code/app2"$'\n'/node_modules; kept "$HOME/code/app2/src.txt"
gone "$HOME/code/py/pkg.egg-info"; kept "$HOME/code/py/.venv/lib/python3.14/site-packages/pkg.egg-info"
kept "$HOME/.cache/huggingface/m"                     # off by default
kept "$T/ran-uv"; kept "$T/ran-brew"; gone "$T/ran-docker"; gone "$T/ran-go"   # go: no cache dir, docker: off

# getconf answering with ~ (or a parent of it) means no temp cleanup at all
FAKE_TMP="$HOME" "$S" -f >/dev/null; kept "$HOME/olddoc"

# a symlinked Trash is refused, not emptied
mkdir -p "$HOME/Documents/sub"; touch "$HOME/Documents/sentinel"
rm -rf "$HOME/.Trash"; ln -s "$HOME/Documents" "$HOME/.Trash"
"$S" -f >/dev/null; kept "$HOME/Documents/sentinel"; kept "$HOME/Documents/sub"

# python-level checks: plan dedupe, tool cache dirs, root validation, discovery, TUI save + render
mkdir -p "$HOME/code/org/group/app/node_modules" "$HOME/code/eggonly/x.egg-info" "$HOME/other/proj/node_modules" \
  "$HOME/code/dup/node_modules/pkg/__pycache__"
touch "$HOME/afile"
printf '{"scan_roots":["~/code","~/code/dup"],"skip_projects":["~/code/keep","~/gone"]}\n' >"$CFG"
python3 -I - "$S" >/dev/null <<'PY'
import io, json, os, sys
from importlib.machinery import SourceFileLoader
fs = sys.modules["fs"] = __import__("types").ModuleType("fs"); SourceFileLoader("fs", sys.argv[1]).exec_module(fs)   # load_module is gone in 3.15
H = str(fs.HOME)

# overlapping roots + nested artifacts: every planned path once, none inside another
plan = fs._build_plan(fs.load_config())
paths = [p for i in plan if not i.cmd for p in i.paths]
assert len(paths) == len(set(paths)), "duplicate paths"
assert not any(fs._inside(p, set(paths)) for p in paths), "nested paths"
uv = next(i for i in plan if i.label == "uv cache")
assert uv.paths == [os.path.dirname(H) + "/uvcache"], uv.paths

# scan roots: too broad, relative, a file, a duplicate
for bad in ("~", "/", "code", "~/afile"):
    assert fs._root_error(bad), bad
assert fs._root_error("~/code/", ["~/code"]) and fs._root_error("~/code") is None

# nested and egg-only projects are listed, so they can be protected
projects = fs._discover_projects(["~/code"])
for p in ("org", "eggonly", "py"):
    assert f"{H}/code/{p}" in projects, p

# TUI: an untouched save keeps protections that aren't on screen; a new root's projects appear at once
cfg = fs.load_config()
fs._render = lambda *a, **k: 0
fs._read_key = iter(["\r"]).__next__
fs._interactive(cfg)
assert json.load(open(fs.CONFIG_PATH))["skip_projects"] == ["~/code/keep", "~/gone"]
rows = fs._build_rows(fs.load_config())
last = max(j for j, r in enumerate(rows) if isinstance(r, fs.ScanRootRow))
rows.insert(last + 1, fs.ScanRootRow(path="~/other", label="~/other", is_new=True))
fs._refresh_projects(rows, cfg)
assert any(isinstance(r, fs.ProjectRow) and r.path == f"{H}/other/proj" for r in rows)

# render: a frame never exceeds the terminal, and shows the cursor when there's room
fs = sys.modules["fs2"] = __import__("types").ModuleType("fs2"); SourceFileLoader("fs2", sys.argv[1]).exec_module(fs)   # load_module is gone in 3.15
rows = fs._build_rows(fs.load_config())
for lines in range(2, 30):
    for msg in (None, "hello"):
        fs.shutil.get_terminal_size = lambda lines=lines: os.terminal_size((80, lines))
        out, sys.stdout = sys.stdout, io.StringIO()
        try:
            fs._render(rows, 5, 0, msg)
            frame = sys.stdout.getvalue()
        finally:
            sys.stdout = out
        assert frame.count("\n") + 1 <= lines, (lines, msg)
        assert lines < 4 or "▸" in frame, (lines, msg)
PY

# TUI in a real pty: a lone Esc doesn't block, Ctrl-C right after still quits and restores the terminal
python3 -I - <<'PY'
import os, pty, select, time
pid, fd = pty.fork()
if pid == 0:
    os.execv(os.environ["S"], [os.environ["S"], "-c"])
out = b""
def pump(until):
    global out
    while time.time() < until:
        if select.select([fd], [], [], 0.05)[0]:
            try:
                out += os.read(fd, 65536)
            except OSError:
                return
end = time.time() + 15
while b"No unsaved changes" not in out and time.time() < end:
    pump(time.time() + 0.2)
os.write(fd, b"\x1b"); pump(time.time() + 0.3); os.write(fd, b"\x03")
deadline = time.time() + 3
while time.time() < deadline:
    if os.waitpid(pid, os.WNOHANG)[0]:
        break
    pump(time.time() + 0.1)
else:
    os.kill(pid, 9)
    raise SystemExit("FAIL: Esc then Ctrl-C did not quit")
pump(time.time() + 0.2)
assert b"\x1b[?1049l" in out and b"\x1b[?7h" in out, "terminal not restored"
PY

# config TUI: deleting every scan root persists as [], "a" refuses ~ and re-adds under the "scan roots" separator
printf '{"scan_roots":["~/code","~/Downloads"]}\n' >"$CFG"
python3 -I - "$S" >/dev/null <<'PY'
import sys
from importlib.machinery import SourceFileLoader
fs = sys.modules["fs"] = __import__("types").ModuleType("fs"); SourceFileLoader("fs", sys.argv[1]).exec_module(fs)   # load_module is gone in 3.15
fs._render = lambda *a, **k: 0

def drive(keys, prompt=None):
    it = iter(keys)
    fs._read_key = lambda: next(it)
    fs._prompt_inline = lambda q: prompt
    return fs._interactive(fs.load_config())

def to(kind):  # j presses from row 0 to the first row of this kind (separators are skipped)
    rows = fs._build_rows(fs.load_config())
    idx = next(i for i, r in enumerate(rows) if isinstance(r, kind))
    return ["j"] * sum(1 for r in rows[1:idx + 1] if not isinstance(r, fs.SeparatorRow))

drive(to(fs.ScanRootRow) + ["d", "j", "d", "\r"])
assert fs.load_config()["scan_roots"] == [], fs.load_config()["scan_roots"]
drive(["a", "\r"], prompt="~/new")                     # cursor on the first category row: not dev projects
assert fs.load_config()["scan_roots"] == []
rows = fs._build_rows(fs.load_config())
cat = next(i for i, r in enumerate(rows) if isinstance(r, fs.CategoryRow) and r.cat_id == "devprojects")
nav = ["j"] * sum(1 for r in rows[1:cat + 1] if not isinstance(r, fs.SeparatorRow))
drive(nav + ["a", "\r"], prompt="~")                   # too broad: refused
assert fs.load_config()["scan_roots"] == []
drive(nav + ["a", "\r"], prompt="~/new")
assert fs.load_config()["scan_roots"] == ["~/new"], fs.load_config()["scan_roots"]
PY

# scan roots toggle like categories: deselecting a root keeps everything under it (saved as the root itself,
# so later projects are kept too); one project back on saves the others individually; selecting it clears them
printf '{"scan_roots":["~/code"]}\n' >"$CFG"
python3 -I - "$S" >/dev/null <<'PY'
import sys
from importlib.machinery import SourceFileLoader
fs = sys.modules["fs"] = __import__("types").ModuleType("fs"); SourceFileLoader("fs", sys.argv[1]).exec_module(fs)   # load_module is gone in 3.15
fs._render = lambda *a, **k: 0
skip = lambda: fs.load_config()["skip_projects"]

def drive(keys):
    fs._read_key = iter(keys).__next__
    fs._interactive(fs.load_config())

rows = fs._build_rows(fs.load_config())
root = next(i for i, r in enumerate(rows) if isinstance(r, fs.ScanRootRow))
nav = ["j"] * sum(1 for r in rows[1:root + 1] if not isinstance(r, fs.SeparatorRow))
kids = [r for r in rows if isinstance(r, fs.ProjectRow) and not r.inherited]
assert len(kids) > 2 and all(k.enabled for k in kids) and rows[root].enabled

drive(nav + [" ", "\r"]);              assert skip() == ["~/code"], skip()
rows = fs._build_rows(fs.load_config())
assert not rows[root].enabled and not any(r.enabled for r in rows if isinstance(r, fs.ProjectRow))
drive(nav + ["j", " ", "\r"])           # first project back on: root goes partial, the rest saved one by one
assert "~/code" not in skip() and len(skip()) == len(kids) - 1, skip()
rows = fs._build_rows(fs.load_config())
assert rows[root].partial and not rows[root].enabled
drive(nav + [" ", "\r"]);              assert skip() == [], skip()   # partial root selected: everything clean
PY

# --dry-run lists the biggest items first
mkdir -p "$HOME/.cache/huggingface" "$HOME/.cache/npm" "$HOME/Library/Caches/pip"
head -c 300000 /dev/zero >"$HOME/.cache/npm/big"; head -c 30000 /dev/zero >"$HOME/Library/Caches/pip/mid"
"$S" --dry-run | sed 's/\x1b\[[0-9;]*m//g' | awk '/^(npm cache|pip cache)/{print $1}' | tr '\n' ' ' | grep -qx 'npm pip ' \
  || { echo "FAIL: dry-run not sorted by size"; exit 1; }

echo ok
