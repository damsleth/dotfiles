#!/usr/bin/env python3
"""binlink: pick which scripts and binaries from your source folders are symlinked into ~/.local/bin.

binlink         interactive picker
binlink -l      list the links that point into your folders
binlink -h      this help

  up/down (j/k) move · space link/unlink (on a folder: all of it) · r rename link
  a add folder · d remove folder · enter apply · q quit without changes

A file counts as a command when it is executable, starts with #!, or ends in .sh/.bash/.zsh.
Folders are scanned recursively, build output included: in a cargo target/ only the top of each
profile dir (debug/, release/) is looked at, in a virtualenv only bin/.

Folders live in ~/.config/binlink/config.json. The first run seeds them from the folders your
existing links in BIN_DIR point into under CODE_DIR. Removing a folder leaves its links alone.
Env: BIN_DIR (default ~/.local/bin), CODE_DIR (default ~/code)
"""
from __future__ import annotations

import json
import os
import re
import select
import shutil
import stat
import sys
import termios
import tty
from dataclasses import dataclass, field
from pathlib import Path

HOME        = Path.home()
BIN_DIR     = Path(os.environ.get("BIN_DIR") or HOME / ".local/bin").expanduser()
CODE_DIR    = Path(os.environ.get("CODE_DIR") or HOME / "code").expanduser()
CONFIG_PATH = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config") / "binlink" / "config.json"

BOLD   = "\033[1m"
DIM    = "\033[2m"
GREEN  = "\033[32m"
RED    = "\033[31m"
CYAN   = "\033[36m"
YELLOW = "\033[33m"
RESET  = "\033[0m"
CHECK  = "◉"
EMPTY  = "◯"
HALF   = "◐"
ARROW  = "▸"

# ponytail: pruned by name; a command kept under one of these needs its dir added as a folder of its own
SKIP_DIRS   = {".git", ".hg", "node_modules", "__pycache__", ".mypy_cache", ".pytest_cache", ".ruff_cache",
               ".tox", ".cache", ".claude", ".worktrees", "tests", "test", "testdata", "fixtures", "CMakeFiles"}
CARGO_JUNK  = {"deps", "build", "incremental", ".fingerprint", "examples"}   # hashed test bins, build scripts
SHELL_EXTS  = {".sh", ".bash", ".zsh"}   # a shell runs these through sh even without #! or +x
SCRIPT_EXTS = SHELL_EXTS | {".py", ".js", ".mjs", ".cjs", ".ts", ".rb", ".pl", ".lua"}
VENV_NOISE  = re.compile(r"(python|pip)[\d.]*")


def _short(p: str | Path) -> str:
    p = str(p)
    return "~" + p[len(str(HOME)):] if p == str(HOME) or p.startswith(str(HOME) + os.sep) else p


def _abs(p: str) -> str:
    return os.path.abspath(os.path.expanduser(p))


def is_command(p: str) -> bool:
    name = os.path.basename(p)
    ext = os.path.splitext(name)[1].lower()
    if name.startswith(".") or VENV_NOISE.fullmatch(name):
        return False
    try:
        st = os.lstat(p)
    except OSError:
        return False
    if not stat.S_ISREG(st.st_mode):   # symlinks (venv python*) point elsewhere: link the real thing
        return False
    if ext in SHELL_EXTS or (st.st_mode & 0o111 and (not ext or ext in SCRIPT_EXTS)):
        return True   # +x with any other extension is a .dylib, .so or a stray mode bit
    try:
        with open(p, "rb") as f:
            return f.read(2) == b"#!"
    except OSError:
        return False


def scan(folder: str) -> list[str]:
    out = []
    for dirpath, dirs, files in os.walk(_abs(folder)):
        if "pyvenv.cfg" in files:                          # virtualenv: commands only in bin/
            dirs[:], files = [d for d in dirs if d == "bin"], []
        elif {"deps", ".fingerprint"} <= set(dirs):        # cargo profile dir: binaries sit on top
            dirs[:] = [d for d in dirs if d not in CARGO_JUNK]
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
        out += [p for p in (os.path.join(dirpath, f) for f in sorted(files)) if is_command(p)]
    return out


def default_name(p: str) -> str:
    stem, ext = os.path.splitext(os.path.basename(p))
    return stem if ext.lower() in SCRIPT_EXTS else os.path.basename(p)


def current_links() -> dict[str, list[str]]:
    """Resolved target -> names of the symlinks in BIN_DIR pointing at it."""
    links: dict[str, list[str]] = {}
    if BIN_DIR.is_dir():
        for e in sorted(os.scandir(BIN_DIR), key=lambda e: e.name):
            if e.is_symlink():
                links.setdefault(os.path.realpath(e.path), []).append(e.name)
    return links


def load_config() -> dict:
    try:
        return json.loads(CONFIG_PATH.read_text())
    except FileNotFoundError:
        # first run: start from the folders the existing links already point into
        code = os.path.realpath(CODE_DIR) + os.sep
        return {"folders": sorted({_short(os.path.dirname(t)) for t in current_links() if t.startswith(code)})}


def save_config(cfg: dict) -> None:
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = CONFIG_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps(cfg, indent=2) + "\n")
    tmp.replace(CONFIG_PATH)


@dataclass
class FolderRow:
    path: str            # as stored in the config
    is_new: bool = False


@dataclass
class ToolRow:
    folder: str
    path: str
    real: str
    name: str
    linked: list[str] = field(default_factory=list)   # names in BIN_DIR that point at it now
    want: bool = False

    @property
    def changed(self) -> bool:
        return self.want != bool(self.linked) or (self.want and self.name not in self.linked)


Row = FolderRow | ToolRow


def folder_rows(folder: str, links: dict[str, list[str]], seen: set[str], is_new: bool = False) -> list[Row]:
    rows: list[Row] = [FolderRow(folder, is_new)]
    for p in scan(folder):
        real = os.path.realpath(p)
        if real in seen:   # nested or overlapping folders: the first one owns the file
            continue
        seen.add(real)
        names = links.get(real, [])
        rows.append(ToolRow(folder, p, real, names[0] if names else default_name(p), names, bool(names)))
    return rows


def build_rows(cfg: dict) -> list[Row]:
    links, seen, rows = current_links(), set(), []
    for f in cfg.get("folders", []):
        rows += folder_rows(f, links, seen)
    return rows


def taken(rows: list[Row], row: ToolRow, name: str) -> str | None:
    """Why row can't be linked as name, or None. Never overwrite something binlink didn't make."""
    if any(r is not row and isinstance(r, ToolRow) and r.want and r.name == name for r in rows):
        return f"another file is already set to link as {name}"
    dst = BIN_DIR / name
    if os.path.lexists(dst) and name not in row.linked:
        where = f" → {_short(os.readlink(dst))}" if dst.is_symlink() else ""
        return f"{_short(dst)} already exists{where}; press r to pick another name"
    return None


def apply(rows: list[Row]) -> list[str]:
    log = []
    todo = [r for r in rows if isinstance(r, ToolRow) and r.changed]
    BIN_DIR.mkdir(parents=True, exist_ok=True)
    for r in sorted(todo, key=lambda r: r.want):   # unlinks first, so their names are free
        try:
            if not r.want:
                for n in r.linked:
                    if os.path.realpath(BIN_DIR / n) == r.real:   # recheck right before deleting
                        os.remove(BIN_DIR / n)
                log.append(f"{RED}unlinked{RESET}  {', '.join(r.linked)}")
                continue
            dst = BIN_DIR / r.name
            if os.path.lexists(dst):
                log.append(f"{YELLOW}skipped{RESET}   {r.name}: {_short(dst)} already exists")
            elif r.linked:
                os.rename(BIN_DIR / r.linked[0], dst)
                log.append(f"{GREEN}renamed{RESET}   {r.linked[0]} → {r.name}")
            else:
                mode = os.stat(r.path).st_mode
                note = ""
                if not mode & 0o100:
                    os.chmod(r.path, mode | 0o111)
                    note = f"  {DIM}(chmod +x){RESET}"
                os.symlink(r.path, dst)
                log.append(f"{GREEN}linked{RESET}    {r.name} → {_short(r.path)}{note}")
        except OSError as e:
            log.append(f"{RED}failed{RESET}    {r.name}: {e}")
    return log


# ── TUI (same keys and frame as freespace -c) ─────────────────────────────────

def _read_key() -> str:
    """One keypress. "" when the terminal was resized (the caller redraws), "q" on EOF."""
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    size = shutil.get_terminal_size()
    try:
        tty.setraw(fd)
        while not select.select([fd], [], [], 0.2)[0]:
            if shutil.get_terminal_size() != size:
                return ""
        key = os.read(fd, 1)
        if key == b"\x1b":
            # arrows are ESC [ A; a lone Esc has no tail, so never block waiting for one
            for _ in range(2):
                if not select.select([fd], [], [], 0.05)[0]:
                    break
                key += os.read(fd, 1)
        if b"\x03" in key:
            return "\x03"
        return key.decode(errors="replace") if key else "q"
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)


def _prompt_inline(question: str, default: str = "") -> str | None:
    sys.stdout.write(f"\033[?25h\n  {question}{f' [{default}]' if default else ''}: ")
    sys.stdout.flush()
    try:
        return sys.stdin.readline().strip() or default or None
    except (KeyboardInterrupt, EOFError):
        return None
    finally:
        sys.stdout.write("\033[?25l")
        sys.stdout.flush()


def _kids(rows: list[Row], folder: str) -> list[ToolRow]:
    return [r for r in rows if isinstance(r, ToolRow) and r.folder == folder]


def _row_line(rows: list[Row], row: Row, is_cur: bool, width: int) -> str:
    mark = f"{CYAN}{ARROW}{RESET} " if is_cur else "  "
    if isinstance(row, FolderRow):
        kids = _kids(rows, row.path)
        dot = (f"{GREEN}{CHECK}{RESET}" if kids and all(k.want for k in kids)
               else f"{YELLOW}{HALF}{RESET}" if any(k.want for k in kids) else f"{DIM}{EMPTY}{RESET}")
        tag = f"  {GREEN}← new{RESET}" if row.is_new else ""
        empty = f"  {DIM}(no commands found){RESET}" if not kids else ""
        return f"{mark}{dot}  {BOLD}{_short(_abs(row.path))}{RESET}{tag}{empty}"
    dot = f"{GREEN}{CHECK}{RESET}" if row.want else f"{DIM}{EMPTY}{RESET}"
    names = ", ".join([row.name] + [n for n in row.linked if n != row.name and row.want])
    rel = os.path.relpath(row.path, _abs(row.folder))
    rel = "" if rel == names else rel
    tag = ""
    if row.changed:
        tag = (f"  {RED}← will unlink{RESET}" if not row.want
               else f"  {GREEN}← will link{RESET}" if not row.linked
               else f"  {YELLOW}← rename from {row.linked[0]}{RESET}")
    name = f"{names:<{width}}" if row.want else f"{DIM}{names:<{width}}{RESET}"
    return f"{mark}     {dot}  {name}  {DIM}{rel}{RESET}{tag}"


def _render(rows: list[Row], cursor: int, top: int, message: str | None, folders_changed: bool = False) -> int:
    """Draw one frame that fits the terminal; returns the scroll offset that keeps the cursor visible."""
    header = [
        f"{BOLD}binlink{RESET}  {DIM}→ {_short(BIN_DIR)}   ({_short(CONFIG_PATH)}){RESET}",
        f"{DIM}up/down navigate  {YELLOW}·{DIM}  space link/unlink  {YELLOW}·{DIM}  r rename"
        f"  {YELLOW}·{DIM}  a add folder  {YELLOW}·{DIM}  d remove folder"
        f"  {YELLOW}·{DIM}  enter apply  {YELLOW}·{DIM}  q quit{RESET}",
        "",
    ]
    tools = [r for r in rows if isinstance(r, ToolRow) and r.changed]
    n_link = sum(1 for r in tools if r.want and not r.linked)
    n_unlink = sum(1 for r in tools if not r.want)
    n_rename = len(tools) - n_link - n_unlink
    parts = [f"{n} to {what}" for n, what in ((n_link, "link"), (n_unlink, "unlink"), (n_rename, "rename")) if n]
    if folders_changed:
        parts.append("folder changes")
    summary = (f"  {YELLOW}{', '.join(parts)}{RESET}  {DIM}— enter to apply  ·  q to discard{RESET}"
               if parts else f"  {DIM}No unsaved changes{RESET}")
    footer = ["", "", summary] + (["", f"  {YELLOW}{message}{RESET}"] if message else [])

    width = min(max((len(r.name) for r in rows if isinstance(r, ToolRow)), default=0), 28)
    body = rows or [None]
    term = shutil.get_terminal_size().lines
    if term - len(header) - len(footer) < 3:
        header, footer = header[:1], footer[:1] + footer[-1:]
    height = max(term - len(header) - len(footer), 1)
    top = max(min(max(top, cursor - height + 1), cursor, max(len(body) - height, 0)), 0)
    visible = [f"  {DIM}No folders yet: press a to add one.{RESET}" if r is None
               else _row_line(rows, r, i == cursor, width) for i, r in enumerate(body[top:top + height], top)]
    above, below = top, max(len(body) - top - height, 0)
    if above or below:
        footer[0] = f"  {DIM}{'↑ ' + str(above) + ' more' if above else ''}"\
                    f"{'  ·  ' if above and below else ''}{'↓ ' + str(below) + ' more' if below else ''}{RESET}"
    lines = (header + visible + footer)[:term]
    sys.stdout.write("\033[H" + "\n".join(l + "\033[K" for l in lines) + "\033[J")
    sys.stdout.flush()
    return top


def _folders(rows: list[Row]) -> list[str]:
    return [r.path for r in rows if isinstance(r, FolderRow)]


def _interactive(cfg: dict) -> list[str] | None:
    """Run the picker. Returns the apply log, or None when quit without applying."""
    rows = build_rows(cfg)
    original = _folders(rows)
    cursor = top = 0
    message: str | None = None
    if f"{BIN_DIR}" not in os.environ.get("PATH", "").split(os.pathsep):
        message = f"{_short(BIN_DIR)} is not in $PATH: links work but aren't callable until it is."

    sys.stdout.write("\033[?1049h\033[?7l\033[?25l")
    sys.stdout.flush()
    try:
        while True:
            cursor = min(cursor, max(len(rows) - 1, 0))
            top = _render(rows, cursor, top, message, _folders(rows) != original)
            message = None
            key = _read_key()
            row = rows[cursor] if rows else None

            if key in ("q", "\x03"):
                return None
            elif key in ("k", "\x1b[A"):
                cursor = max(0, cursor - 1)
            elif key in ("j", "\x1b[B"):
                cursor = min(len(rows) - 1, cursor + 1)
            elif key in ("\r", "\n"):
                cfg["folders"] = _folders(rows)
                save_config(cfg)
                return apply(rows)

            elif key == " " and isinstance(row, ToolRow):
                why = None if row.want else taken(rows, row, row.name)
                if why:
                    message = why
                else:
                    row.want = not row.want
            elif key == " " and isinstance(row, FolderRow):
                kids = _kids(rows, row.path)
                want = not all(k.want for k in kids)
                skipped = []
                for k in kids:
                    if k.want != want:
                        if want and taken(rows, k, k.name):
                            skipped.append(k.name)
                        else:
                            k.want = want
                if skipped:
                    message = f"Name taken, left alone (r to rename): {', '.join(skipped)}"

            elif key == "r" and isinstance(row, ToolRow):
                new = _prompt_inline(f"Link {os.path.basename(row.path)} as", row.name)
                why = new and new != row.name and taken(rows, row, new)
                if not new or "/" in new or new.startswith("."):
                    message = "Rename cancelled."
                elif why:
                    message = why
                else:
                    row.name, row.want = new, True

            elif key == "a":
                path = _prompt_inline("Add folder")
                if path:
                    path = _short(_abs(path))
                if not path:
                    message = "Add cancelled."
                elif not os.path.isdir(_abs(path)):
                    message = f"Not a directory: {path}"
                elif _abs(path) in {_abs(f) for f in _folders(rows)}:
                    message = f"Already a folder: {path}"
                else:
                    seen = {r.real for r in rows if isinstance(r, ToolRow)}
                    new_rows = folder_rows(path, current_links(), seen, is_new=True)
                    cursor = len(rows)
                    rows += new_rows
                    message = f"Added {path}: {len(new_rows) - 1} command(s)  (enter to save)"

            elif key == "d" and row is not None:
                folder = row.path if isinstance(row, FolderRow) else row.folder
                start = next(i for i, r in enumerate(rows) if isinstance(r, FolderRow) and r.path == folder)
                end = start + 1 + len(_kids(rows, folder))
                del rows[start:end]
                cursor = min(start, max(len(rows) - 1, 0))
                message = f"Removed {folder} (its links stay; enter to save, q to undo)"
    finally:
        sys.stdout.write("\033[?25h\033[?7h\033[?1049l")
        sys.stdout.flush()


def main() -> None:
    args = sys.argv[1:]
    if args in (["-h"], ["--help"]):
        print(__doc__.strip())
    elif args in (["-l"], ["--list"]):
        for r in build_rows(load_config()):
            if isinstance(r, ToolRow) and r.linked:
                print(f"{', '.join(r.linked):<24} → {_short(r.path)}")
    elif args:
        sys.exit(f"unknown option: {' '.join(args)}  (try -h)")
    elif not (sys.stdin.isatty() and sys.stdout.isatty()):
        sys.exit("binlink needs an interactive terminal (or use -l).")
    else:
        log = _interactive(load_config())
        if log is None:
            print("No changes.")
        else:
            print("\n".join(log) or f"Saved {_short(CONFIG_PATH)}; no link changes.")


if __name__ == "__main__":
    main()
