#!/usr/bin/env bash
# Self-check for binlink.py: command detection, cargo/venv pruning, first-run seed, taken names, TUI apply.
# ponytail: fake HOME + BIN_DIR in a tmpdir, keys fed straight into _interactive. Run: ./test-binlink.sh
set -euo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/binlink.py"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export HOME="$T" CODE_DIR="$T/src" BIN_DIR="$T/bin" XDG_CONFIG_HOME="$T/.config"
cd "$T"
mkdir -p src/scripts src/rs/target/debug/{deps,build/x,.fingerprint} src/rs/tests src/py/.venv/{bin,lib} bin
printf 'echo a\n'               > src/scripts/a.sh        # .sh: no #! or +x needed
printf '#!/usr/bin/env python3\n' > src/scripts/b.py      # shebang, not +x
printf 'print(1)\n'             > src/scripts/c.py        # plain module: not a command
printf 'MIT\n'                  > src/scripts/LICENSE
printf 'echo\n'                 > src/scripts/.hidden.sh
printf '\xcf\xfa'               > src/scripts/tool;      chmod +x src/scripts/tool
printf '\xcf\xfa'               > src/scripts/lib.dylib; chmod +x src/scripts/lib.dylib
for f in target/debug/rsbin target/debug/deps/rsbin-0abc target/debug/build/x/build-script-build tests/fixture; do
  printf '\xcf\xfa' > "src/rs/$f"; chmod +x "src/rs/$f"
done
printf 'dep\n' > src/rs/target/debug/rsbin.d
touch src/py/.venv/pyvenv.cfg
for f in bin/mycli bin/pip lib/site.py; do printf '#!/x/python\n' > "src/py/.venv/$f"; chmod +x "src/py/.venv/$f"; done
ln -s /usr/bin/python3 src/py/.venv/bin/python
ln -s "$T/src/scripts/b.py" bin/bee                       # existing link: seeds ~/src/scripts
printf 'mine\n' > bin/a                                    # takes a.sh's default name

python3 -I - "$S" >/dev/null <<'PY'
import os, sys, types
from importlib.machinery import SourceFileLoader
b = sys.modules["b"] = types.ModuleType("b"); SourceFileLoader("b", sys.argv[1]).exec_module(b)
H = os.environ["HOME"]
rel = lambda ps: sorted(os.path.relpath(p, H + "/src") for p in ps)

assert rel(b.scan("~/src/scripts")) == ["scripts/a.sh", "scripts/b.py", "scripts/tool"], b.scan("~/src/scripts")
assert rel(b.scan("~/src/rs")) == ["rs/target/debug/rsbin"], b.scan("~/src/rs")
assert rel(b.scan("~/src/py")) == ["py/.venv/bin/mycli"], b.scan("~/src/py")
assert b.load_config() == {"folders": ["~/src/scripts"]}, b.load_config()

b._render = lambda *a, **k: 0
def drive(keys, prompts=()):
    b._read_key, p = iter(keys).__next__, iter(prompts)
    b._prompt_inline = lambda *a: next(p)
    return b._interactive(b.load_config())

# rows: 0 folder, 1 a.sh (off, "a" taken), 2 b.py (linked as bee), 3 tool (off)
assert drive([" ", "j", " ", "q"]) is None and not os.path.lexists(H + "/bin/tool")   # q applies nothing
assert os.path.islink(H + "/bin/bee")
log = drive(["j", " ", "r", "j", " ", "j", " ", "a", "a", "\r"], prompts=["aa", "~/src/rs", "/nope"])
assert os.readlink(H + "/bin/aa") == H + "/src/scripts/a.sh" and os.access(H + "/src/scripts/a.sh", os.X_OK), log
assert not os.path.lexists(H + "/bin/bee"), log                      # unlinked
assert os.readlink(H + "/bin/tool") == H + "/src/scripts/tool", log
assert open(H + "/bin/a").read() == "mine\n"                          # taken name never touched
assert b.load_config() == {"folders": ["~/src/scripts", "~/src/rs"]}, b.load_config()

# folder toggle links everything under it; d drops the folder but keeps its links
drive(["j", "j", "j", "j", " ", "\r"])                                 # row 4: ~/src/rs folder
assert os.readlink(H + "/bin/rsbin") == H + "/src/rs/target/debug/rsbin"
drive(["j", "j", "j", "j", "d", "\r"])
assert b.load_config() == {"folders": ["~/src/scripts"]} and os.path.islink(H + "/bin/rsbin")
PY
echo "binlink self-check: OK"
