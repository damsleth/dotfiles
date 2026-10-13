#!/usr/bin/env python3
"""freespace — clean caches and free disk space.

  freespace             list what will go, ask y/N, clean
  freespace --force     run without the confirmation prompt  (alias: -f)
  freespace -c          interactive config TUI  (aliases: config, --config)
  freespace --dry-run   list sizes without deleting  (alias: -n)
"""

from __future__ import annotations

import fnmatch
import json
import os
import select
import shutil
import subprocess
import sys
import termios
import tty
from dataclasses import dataclass
from pathlib import Path

HOME        = Path(os.path.realpath(Path.home()))   # canonical, so planned paths compare as strings
CONFIG_PATH = HOME / ".config" / "freespace" / "config.json"

BOLD   = "\033[1m"
DIM    = "\033[2m"
GREEN  = "\033[32m"
RED    = "\033[31m"
CYAN   = "\033[36m"
YELLOW = "\033[33m"
RESET  = "\033[0m"
CHECK  = "◉"
EMPTY  = "◯"
ARROW  = "▸"

# ── Schema ────────────────────────────────────────────────────────────────────

CATEGORIES: list[tuple[str, str, list[tuple[str, str, bool]]]] = [
    ("edge", "Microsoft Edge", [
        ("edge_codesign", "code-sign clones",   True),
        ("edge_browser",  "browser cache",      True),
    ]),
    ("pkgmgr", "Package Managers", [
        ("homebrew",   "Homebrew",   True),
        ("pip",        "pip",        True),
        ("uv",         "uv",         True),
        ("npm",        "npm",        True),
        ("pnpm",       "pnpm",       True),
        ("node_gyp",   "node-gyp",   True),
        ("bun",        "bun",        True),
        ("nuget",      "NuGet",      True),
    ]),
    ("compiled", "Compiled / Build", [
        ("cargo_registry", "cargo registry",  True),
        ("go_build",       "go build cache",  True),
        ("go_mod",         "go module cache", False),
    ]),
    ("apps", "App Caches", [
        ("spotify",    "Spotify",         True),
        ("steam",      "Steam",           True),
        ("codex",      "Codex runtimes",  True),
        ("claude_cli", "Claude CLI",      True),
        ("teaminal",   "Teaminal",        True),
        ("typescript", "TypeScript",      True),
        ("vscode",     "VS Code",         True),
        ("playwright", "Playwright browsers  (re-download)", False),
        ("qmd",        "qmd models/index  (rebuild)",        False),
    ]),
    ("system", "System", [
        ("xcode_derived", "Xcode DerivedData",        True),
        ("xcode_ios",     "Xcode iOS DeviceSupport",  True),
        ("user_logs",     "User logs older than 7 days",       True),
        ("tmp",           "Temp files older than 3 days",      True),
        ("trash",         "Trash",                              True),
        ("docker",        "Docker unused images/volumes",       False),
    ]),
    ("devprojects", "Dev Projects", [
        ("scan_node_modules", "node_modules",               True),
        ("scan_pycache",      "__pycache__ / *.pyc",        True),
        ("scan_pytest",       ".pytest_cache",              True),
        ("scan_mypy",         ".mypy_cache / .ruff_cache",  True),
        ("scan_venv",         ".venv / venv",               False),
        ("scan_egg",          "*.egg-info",                 True),
    ]),
    ("ml", "Machine Learning", [
        ("huggingface", "HuggingFace models  (slow to re-download)", False),
    ]),
]

DEFAULT_SCAN_ROOTS = ["~/code"]

# scan target -> artifact dir patterns; one find per scan root covers all of them
ARTIFACTS = {
    "scan_node_modules": ["node_modules"],
    "scan_pycache":      ["__pycache__"],
    "scan_pytest":       [".pytest_cache"],
    "scan_mypy":         [".mypy_cache", ".ruff_cache"],
    "scan_venv":         [".venv", "venv"],
    "scan_egg":          ["*.egg-info"],
}
LABELS = {key: label for _, _, children in CATEGORIES for key, label, _ in children}

# ── Config I/O ────────────────────────────────────────────────────────────────

def _canon(p: str) -> str:
    return os.path.realpath(os.path.expanduser(p))


def _canon_leaf(p: str | Path) -> str:
    """Resolve symlinks in the parents only, so a symlinked leaf is unlinked, never followed."""
    p = os.path.expanduser(str(p))
    return os.path.join(os.path.realpath(os.path.dirname(p)), os.path.basename(p))


def _root_error(root: str, others: list[str] | tuple = ()) -> str | None:
    """Why a scan root is unsafe or unusable, or None when it's fine."""
    if not root.startswith(("/", "~")):
        return f"{root}: use an absolute path or ~/..."
    c = _canon(root)
    if c in ("/", str(HOME)):
        return f"{root}: too broad, pick a folder of projects"   # would reach into apps, Library, volumes
    if os.path.exists(c) and not os.path.isdir(c):
        return f"{root}: not a folder"
    if c in {_canon(o) for o in others}:
        return f"{root}: already a scan root"
    return None


def _config_problem(data) -> str | None:
    if not isinstance(data, dict):
        return "expected a JSON object"
    targets = data.get("targets", {})
    if not isinstance(targets, dict) or not all(isinstance(v, bool) for v in targets.values()):
        return "targets must map names to true/false"
    for key in ("scan_roots", "skip_projects"):
        v = data.get(key, [])
        if not isinstance(v, list) or not all(isinstance(p, str) for p in v):
            return f"{key} must be a list of paths"
    for root in data.get("scan_roots", []):
        if err := _root_error(root):
            return f"scan root {err}"
    return None


def load_config() -> dict:
    cfg: dict = {"targets": {}, "scan_roots": list(DEFAULT_SCAN_ROOTS), "skip_projects": []}
    if CONFIG_PATH.exists():
        # a broken config stops the run: falling back to defaults would re-enable targets you turned off
        try:
            data = json.loads(CONFIG_PATH.read_text())
        except (OSError, ValueError) as e:
            sys.exit(f"freespace: can't read {CONFIG_PATH}: {e}\nFix or delete it. Nothing was cleaned.")
        if problem := _config_problem(data):
            sys.exit(f"freespace: {CONFIG_PATH}: {problem}\nFix or delete it. Nothing was cleaned.")
        cfg.update(data)
    for _, _, children in CATEGORIES:
        for key, _, default in children:
            cfg["targets"].setdefault(key, default)
    return cfg


def save_config(cfg: dict) -> None:
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = CONFIG_PATH.with_name(CONFIG_PATH.name + ".tmp")
    tmp.write_text(json.dumps(cfg, indent=2) + "\n")
    os.replace(tmp, CONFIG_PATH)   # atomic: a crash mid-write never leaves a truncated config

# ── Cleanup ───────────────────────────────────────────────────────────────────

def _size_bytes(paths: list[str]) -> int:
    total = 0
    for p in paths:
        rp = Path(p).expanduser()
        if not rp.exists():
            continue
        try:
            out = subprocess.check_output(
                ["du", "-sk", str(rp)], stderr=subprocess.DEVNULL, text=True
            )
            total += int(out.split()[0]) * 1024
        except Exception:
            pass
    return total


def _human(b: int) -> str:
    if b >= 1_073_741_824: return f"{b/1_073_741_824:.1f}G"
    if b >= 1_048_576:     return f"{b/1_048_576:.1f}M"
    if b >= 1_024:         return f"{b/1_024:.1f}K"
    return f"{b}B"


def _user_tmp() -> Path | None:
    """The per-user temp dir as macOS reports it. $TMPDIR is ignored: set to ~, the tmp cleanup would empty ~."""
    try:
        out = subprocess.run(["getconf", "DARWIN_USER_TEMP_DIR"], capture_output=True, text=True).stdout.strip()
    except OSError:
        return None
    tmp = Path(os.path.realpath(out)) if out else None
    return None if tmp is None or HOME.is_relative_to(tmp) else tmp   # never "/" or anything holding ~


def _ask_paths(cmd: list[str]) -> list[Path]:
    """Cache dirs a tool reports (honours UV_CACHE_DIR, GOCACHE, NuGet config, ...); "name: /path" lines are fine."""
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.TimeoutExpired):
        return []
    found = [line.split(": ", 1)[-1].strip() for line in out.splitlines()]
    return [Path(p) for p in found if p.startswith("/")]


def _find_artifacts(roots: list[str], keys: list[str]) -> dict[str, list[str]]:
    """Artifact paths per scan target: one NUL-separated find per root, so odd names (even newlines) stay intact."""
    pats = [(pat, key) for key in keys for pat in ARTIFACTS[key]]
    found: dict[str, list[str]] = {key: [] for key in keys}
    if not pats:
        return found
    names: list[str] = []
    for pat, _ in pats:
        names += ["-o", "-name", pat]
    expr = ["-type", "d", "(", *names[1:], ")", "-prune", "-print0"]
    if "scan_pycache" in keys:   # stray .pyc next to its .py; the ones in __pycache__ are pruned above
        expr += ["-o", "-type", "f", "-name", "*.pyc", "-print0"]
    for root in roots:
        rp = _canon(root)
        if not os.path.isdir(rp):
            continue
        out = subprocess.run(["find", rp, *expr], capture_output=True).stdout
        for p in map(os.fsdecode, filter(None, out.split(b"\0"))):
            name = os.path.basename(p)
            found[next((k for pat, k in pats if fnmatch.fnmatchcase(name, pat)), "scan_pycache")].append(p)
    return found


def _skip_set(cfg: dict) -> set[str]:
    return {_canon(p) for p in cfg.get("skip_projects", [])}


def _under(p: str, parent: str) -> bool:
    return p == parent or p.startswith(parent.rstrip("/") + "/")


def _protected(p: str, skip: set[str]) -> bool:
    """Inside a protected path, or holding one (deleting p would take the protected path along)."""
    return any(_under(p, s) or _under(s, p) for s in skip)


def _inside(p: str, paths: set[str]) -> bool:
    """Some proper parent of p is in paths."""
    parent = os.path.dirname(p)
    while parent != p:
        if parent in paths:
            return True
        p, parent = parent, os.path.dirname(parent)
    return False


@dataclass
class Item:
    label: str
    paths: list[str]                # measured before/after; deleted unless cmd is set
    cmd:   list[str] | None = None  # tool-native cleanup, run instead of deleting paths
    unit:  str = ""                 # set: the label shows the path count, e.g. "(34 dirs)"

    @property
    def name(self) -> str:
        return f"{self.label}  ({len(self.paths)} {self.unit})" if self.unit else self.label


def _build_plan(cfg: dict) -> list[Item]:
    t = cfg["targets"]
    roots = cfg.get("scan_roots", DEFAULT_SCAN_ROOTS)
    plan: list[Item] = []
    LC = HOME / "Library/Caches"

    def add(key: str, label: str, *paths: Path, cmd: list[str] | None = None, ask: list[str] | None = None) -> None:
        if not t.get(key):
            return
        if cmd and not shutil.which(cmd[0]):
            print(f"{DIM}skip {label}: {cmd[0]} not installed{RESET}")
            return
        if ask and shutil.which(ask[0]):
            paths = tuple(_ask_paths(ask)) or paths   # measure where the tool really keeps it
        existing = [_canon_leaf(p) for p in paths if p.exists()]
        if existing:
            plan.append(Item(label, existing, cmd))

    tmp = _user_tmp()
    if tmp is None and (t.get("tmp") or t.get("edge_codesign")):
        print(f"{YELLOW}skip temp files + Edge clones: can't determine the user temp dir safely{RESET}")
    if tmp:
        add("edge_codesign", "Edge code-sign clones",     tmp.parent / "X/com.microsoft.edgemac.code_sign_clone")
    add("edge_browser",   "Edge browser cache",          LC / "Microsoft Edge")
    add("homebrew",       "Homebrew cache + old versions", LC / "Homebrew", cmd=["brew", "cleanup", "--prune=all", "-s"])
    add("pip",            "pip cache",                   LC / "pip", HOME / ".cache/pip")
    add("uv",             "uv cache",                    HOME / ".cache/uv", cmd=["uv", "cache", "clean"],
                                                         ask=["uv", "cache", "dir"])
    add("npm",            "npm cache",                   HOME / ".cache/npm", HOME / ".npm/_cacache")
    add("pnpm",           "pnpm store (unreferenced)",   HOME / ".local/share/pnpm/store", HOME / "Library/pnpm/store",
                                                         cmd=["pnpm", "store", "prune"], ask=["pnpm", "store", "path"])
    add("node_gyp",       "node-gyp cache",              LC / "node-gyp")
    add("bun",            "bun cache",                   HOME / ".cache/bun", HOME / ".bun/install/cache")
    add("nuget",          "NuGet caches",                HOME / ".cache/NuGet", HOME / ".nuget/packages",
                                                         HOME / ".local/share/NuGet",
                                                         cmd=["dotnet", "nuget", "locals", "all", "--clear"],
                                                         ask=["dotnet", "nuget", "locals", "all", "--list"])
    add("cargo_registry", "cargo registry",              HOME / ".cargo/registry/cache")
    add("go_build",       "go build cache",              LC / "go-build", ask=["go", "env", "GOCACHE"])
    # module files are read-only, so rmtree can't remove them
    add("go_mod",         "go module cache",             HOME / "go/pkg/mod", cmd=["go", "clean", "-modcache"],
                                                         ask=["go", "env", "GOMODCACHE"])
    add("spotify",        "Spotify cache",               LC / "com.spotify.client", HOME / ".cache/spotify-player")
    add("steam",          "Steam cache",                 LC / "Steam")
    add("codex",          "Codex runtimes",              HOME / ".cache/codex-runtimes")
    add("claude_cli",     "Claude CLI cache",            LC / "claude-cli-nodejs")
    add("teaminal",       "Teaminal cache",              HOME / ".cache/teaminal")
    add("typescript",     "TypeScript cache",            HOME / ".cache/typescript")
    add("vscode",         "VS Code caches",              HOME / "Library/Application Support/Code/Cache",
                                                         HOME / "Library/Application Support/Code/CachedData")
    add("playwright",     "Playwright browsers",         LC / "ms-playwright")
    add("qmd",            "qmd models/index",            HOME / ".cache/qmd")
    add("xcode_derived",  "Xcode DerivedData",           HOME / "Library/Developer/Xcode/DerivedData")
    add("xcode_ios",      "Xcode iOS DeviceSupport",     HOME / "Library/Developer/Xcode/iOS DeviceSupport")
    logs = HOME / "Library/Logs"
    add("user_logs",      "User logs older than 7 days", logs, cmd=["find", str(logs), "-type", "f", "-mtime", "+7", "-delete"])
    if tmp:
        # ponytail: files only; a dir's mtime says nothing about whether an app still lives in it
        add("tmp",        "Temp files older than 3 days", tmp, cmd=["find", str(tmp), "-type", "f", "-mtime", "+3", "-delete"])
    add("huggingface",    "HuggingFace models",          HOME / ".cache/huggingface")

    if t.get("trash"):
        trash_dir = HOME / ".Trash"
        if trash_dir.is_symlink():   # would list, and empty, whatever it points at
            print(f"{YELLOW}skip Trash: ~/.Trash is a symlink{RESET}")
        else:
            try:
                trash = [_canon_leaf(p) for p in trash_dir.iterdir()]   # contents only, keep the folder
            except PermissionError:
                trash = []
                print(f"{YELLOW}skip Trash: no access (give your terminal Full Disk Access){RESET}")
            except FileNotFoundError:
                trash = []
            if trash:
                plan.append(Item("Trash", trash, unit="items"))

    if t.get("docker") and shutil.which("docker"):
        if subprocess.run(["docker", "info"], capture_output=True).returncode == 0:
            plan.append(Item("Docker unused images/volumes", [], ["docker", "system", "prune", "-af", "--volumes"]))
        else:
            print(f"{DIM}skip Docker: daemon not running{RESET}")

    skip = _skip_set(cfg)
    found = _find_artifacts(roots, [key for key in ARTIFACTS if t.get(key)])
    for key, paths in found.items():
        if key == "scan_venv":   # only real virtualenvs, so a source dir named "venv" survives
            paths = [p for p in paths if os.path.exists(os.path.join(p, "pyvenv.cfg"))]
        if key == "scan_egg":    # installed package metadata lives in site-packages; only project build output goes
            paths = [p for p in paths if "site-packages" not in Path(p).parts]
        paths = [p for p in paths if not _protected(p, skip)]
        if paths:
            plan.append(Item(LABELS[key], paths, unit="items" if key == "scan_pycache" else "dirs"))

    # one path, one owner: drop repeats (overlapping roots) and paths inside another deleted path,
    # so sizes and "freed" aren't counted twice. Command items clean by their own rules and stay as they are.
    direct = {p for item in plan if not item.cmd for p in item.paths}
    seen: set[str] = set()
    for item in plan:
        if item.cmd:
            continue
        kept = []
        for p in item.paths:
            if p not in seen and not _inside(p, direct):
                seen.add(p)
                kept.append(p)
        item.paths = kept
    return [item for item in plan if item.cmd or item.paths]


def _delete(p: str) -> bool:
    if _canon_leaf(p) != p:   # a parent became a symlink after planning: don't follow it
        return False
    rp = Path(p)
    if rp.is_symlink() or rp.is_file():
        try:
            rp.unlink()
        except OSError:
            pass
    else:
        shutil.rmtree(rp, ignore_errors=True)
    return not rp.exists() and not rp.is_symlink()


def run_cleanup(dry: bool = False, force: bool = False) -> None:
    cfg = load_config()
    print("\nScanning...")
    plan = _build_plan(cfg)
    if not plan:
        print("Nothing to clean.")
        return

    # measure once; reused as the "before" size so du doesn't walk 70G twice
    sizes = [_size_bytes(i.paths) for i in plan]
    order = sorted(range(len(plan)), key=lambda i: (bool(plan[i].paths), sizes[i]), reverse=True)
    plan, sizes = [plan[i] for i in order], [sizes[i] for i in order]
    print()
    for item, size in zip(plan, sizes):
        upto = "≤" if item.cmd and item.cmd[0] == "find" else ""   # age-filtered: only part of the dir goes
        print(f"{CYAN}{item.name:<42}{RESET} {upto + _human(size) if item.paths else '?'}")
    print(f"\n{BOLD}{len(plan)} group(s), ~{_human(sum(sizes))}{RESET}")

    if dry:
        print(f"{YELLOW}Dry run, nothing deleted.{RESET}\n")
        return
    if not force:
        try:
            if input("Proceed? [y/N] ").strip().lower() not in ("y", "yes"):
                print("Aborted.")
                return
        except (KeyboardInterrupt, EOFError):
            print("\nAborted.")
            return

    print()
    total_freed = 0
    for item, before in zip(plan, sizes):
        print(f"{CYAN}{item.name:<42}{RESET} ", end="", flush=True)
        if item.cmd:
            ok = subprocess.run(item.cmd, capture_output=True).returncode == 0
        else:
            ok = all([_delete(p) for p in item.paths])
        freed = max(before - _size_bytes(item.paths), 0)
        total_freed += freed
        note = "" if ok else f"  {YELLOW}(errors: in use or no permission?){RESET}"
        print(f"{GREEN}{'freed ' + _human(freed) if item.paths else 'done'}{RESET}{note}" if ok or freed
              else f"{RED}failed{RESET}{note}")

    print(f"\n{GREEN}Total freed: {_human(total_freed)}{RESET}\n")

# ── Config TUI ────────────────────────────────────────────────────────────────

@dataclass
class CategoryRow:
    kind:   str = "category"
    cat_id: str = ""
    label:  str = ""
    enabled: bool = True


@dataclass
class TargetRow:
    kind:     str = "target"
    cat_id:   str = ""
    key:      str = ""
    label:    str = ""
    enabled:  bool = True
    original: bool = True


@dataclass
class ScanRootRow:
    kind:      str = "scan_root"
    cat_id:    str = "devprojects"
    path:      str = ""
    label:     str = ""
    enabled:   bool = True   # True = clean its projects, False = keep them all
    original:  bool = True
    is_new:    bool = False
    to_remove: bool = False
    inherited: bool = False   # kept through a parent folder in skip_projects
    partial:   bool = False   # some of its projects selected, some kept


@dataclass
class SeparatorRow:
    kind:   str = "separator"
    cat_id: str = "devprojects"
    label:  str = ""


@dataclass
class ProjectRow:
    kind:     str = "project"
    cat_id:   str = "devprojects"
    path:     str = ""     # absolute
    root:     str = ""     # canonical scan root it belongs to
    label:    str = ""     # short display name
    enabled:  bool = True  # True = clean, False = keep (protected)
    original: bool = True
    inherited: bool = False  # kept through a parent folder in skip_projects


Row = CategoryRow | TargetRow | ScanRootRow | SeparatorRow | ProjectRow


def _discover_projects(roots: list[str]) -> list[str]:
    """Top-level folders under each root that hold artifacts, from the same scan the cleanup runs,
    so every folder a cleanup can touch can also be protected."""
    canon_roots = [_canon(r) for r in roots]
    projects: set[str] = set()
    for paths in _find_artifacts(roots, list(ARTIFACTS)).values():
        for p in paths:
            root = next(r for r in canon_roots if _under(p, r))
            projects.add(os.path.join(root, os.path.relpath(p, root).split(os.sep)[0]))
    return sorted(projects)


def _root_section(roots: list[ScanRootRow], skip_projects: list[str], staged: dict[str, bool]) -> list[Row]:
    """Each scan root followed by its projects. staged carries project toggles made earlier in this session;
    a project without one follows its root (a deselected root keeps everything under it)."""
    skip = _skip_set({"skip_projects": skip_projects})
    out: list[Row] = []
    for root in roots:
        out.append(root)
        if root.to_remove:
            continue
        croot = _canon(root.path)
        root.inherited = any(s != croot and _under(croot, s) for s in skip)
        kids = []
        for p in _discover_projects([root.path]):
            if root.inherited or any(s not in (p, croot) and _under(p, s) for s in skip):
                kids.append(ProjectRow(path=p, root=croot, label=os.path.basename(p),
                                       enabled=False, original=False, inherited=True))
            else:
                saved = croot not in skip and p not in skip
                kids.append(ProjectRow(path=p, root=croot, label=os.path.basename(p),
                                       enabled=staged.get(p, root.enabled and p not in skip), original=saved))
        _sync_root(root, kids)
        out += kids
    return out


def _sync_root(root: ScanRootRow, kids: list[Row]) -> None:
    """Like a category: a root is selected when all its projects are."""
    kids = [k for k in kids if isinstance(k, ProjectRow) and not k.inherited]
    if kids and not root.inherited:
        root.enabled = all(k.enabled for k in kids)
        root.partial = not root.enabled and any(k.enabled for k in kids)


def _build_rows(cfg: dict) -> list[Row]:
    rows: list[Row] = []
    t = cfg["targets"]
    scan_roots = cfg.get("scan_roots", DEFAULT_SCAN_ROOTS)
    skip = _skip_set(cfg)

    for cat_id, cat_label, children in CATEGORIES:
        child_states = [t.get(key, default) for key, _, default in children]
        rows.append(CategoryRow(cat_id=cat_id, label=cat_label, enabled=all(child_states)))
        for key, label, default in children:
            enabled = t.get(key, default)
            rows.append(TargetRow(cat_id=cat_id, key=key, label=label,
                                  enabled=enabled, original=enabled))

        if cat_id == "devprojects":
            rows.append(SeparatorRow(label="scan roots  (◉ = clean, ◯ = keep)"))
            roots = [ScanRootRow(path=r, label=r, enabled=_canon(r) not in skip) for r in scan_roots]
            section = _root_section(roots, cfg.get("skip_projects", []), {})
            for root in roots:   # the saved state, as shown before any toggles
                root.original = root.enabled
            rows += section

    return rows


def _section_bounds(rows: list[Row]) -> tuple[int, int]:
    start = 1 + next(j for j, r in enumerate(rows) if isinstance(r, SeparatorRow) and r.label.startswith("scan roots"))
    end = start
    while end < len(rows) and isinstance(rows[end], (ScanRootRow, ProjectRow)):
        end += 1
    return start, end


def _refresh_projects(rows: list[Row], cfg: dict) -> None:
    """Re-scan the projects for the scan roots as currently staged, keeping toggles made this session."""
    start, end = _section_bounds(rows)
    roots = [r for r in rows[start:end] if isinstance(r, ScanRootRow)]
    staged = {r.path: r.enabled for r in rows[start:end] if isinstance(r, ProjectRow) and not r.inherited}
    rows[start:end] = _root_section(roots, cfg.get("skip_projects", []), staged)


def _save_projects(rows: list[Row], old: list[str]) -> list[str]:
    """New skip_projects. Entries the menu doesn't show (no artifacts right now, root offline) survive;
    a fully deselected root is saved as the root itself, so projects that appear later are kept too."""
    protect: list[str] = []
    handled: set[str] = set()
    for root in rows:
        if not isinstance(root, ScanRootRow) or root.to_remove or root.inherited:
            continue
        croot = _canon(root.path)
        kids = [r for r in rows if isinstance(r, ProjectRow) and r.root == croot and not r.inherited]
        handled |= {croot, *(k.path for k in kids)}
        if any(k.enabled for k in kids) or (not kids and root.enabled):
            protect += [k.path for k in kids if not k.enabled]
        else:
            protect.append(root.path)
    want = {_canon(p) for p in protect}
    kept = [s for s in old if _canon(s) not in handled or _canon(s) in want]   # unchanged entries keep their spelling
    have = {_canon(s) for s in kept}
    return kept + [p for p in protect if _canon(p) not in have]


def _update_category(rows: list[Row], cat_id: str) -> None:
    children = [r for r in rows if isinstance(r, TargetRow) and r.cat_id == cat_id]
    cats = [r for r in rows if isinstance(r, CategoryRow) and r.cat_id == cat_id]
    if cats and children:
        cats[0].enabled = all(c.enabled for c in children)


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
            # arrows are ESC [ A; a lone Esc has no tail, so never block waiting for one (that swallowed Ctrl-C)
            for _ in range(2):
                if not select.select([fd], [], [], 0.05)[0]:
                    break
                key += os.read(fd, 1)
        if b"\x03" in key:
            return "\x03"
        return key.decode(errors="replace") if key else "q"
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)


def _row_line(row: Row, is_cur: bool) -> str:
    cursor_mark = f"{CYAN}{ARROW}{RESET} " if is_cur else "  "

    if isinstance(row, CategoryRow):
        dot = f"{GREEN}{CHECK}{RESET}" if row.enabled else f"{DIM}{EMPTY}{RESET}"
        return f"{cursor_mark}{dot}  {BOLD}{row.label}{RESET}"

    if isinstance(row, TargetRow):
        dot   = f"{GREEN}{CHECK}{RESET}" if row.enabled else f"{DIM}{EMPTY}{RESET}"
        label = row.label if row.enabled else f"{DIM}{row.label}{RESET}"
        changed = ""
        if row.enabled != row.original:
            changed = f"  {GREEN}← will enable{RESET}" if row.enabled else f"  {RED}← will disable{RESET}"
        return f"{cursor_mark}     {dot}  {label}{changed}"

    if isinstance(row, ScanRootRow):
        if row.to_remove:
            return f"{cursor_mark}     {DIM}╌  {row.label}  ← will remove{RESET}"
        if row.inherited:
            return f"{cursor_mark}     {DIM}{EMPTY}  {row.label}  (kept by a parent folder){RESET}"
        dot = f"{GREEN}{CHECK}{RESET}" if row.enabled else f"{YELLOW}◐{RESET}" if row.partial else f"{DIM}{EMPTY}{RESET}"
        tag = f"  {GREEN}← new{RESET}" if row.is_new else _change_tag(row)
        return f"{cursor_mark}     {dot}  {row.label if row.enabled else DIM + row.label + RESET}{tag}"

    if isinstance(row, SeparatorRow):
        return f"  {DIM}     ── {row.label} ──{RESET}"

    # ProjectRow
    if row.inherited:
        return f"{cursor_mark}        {DIM}{EMPTY}  {row.label}  (kept by a parent folder){RESET}"
    if row.enabled:
        return f"{cursor_mark}        {GREEN}{CHECK}{RESET}  {row.label}{_change_tag(row)}"
    return f"{cursor_mark}        {DIM}{EMPTY}  {row.label}{RESET}{_change_tag(row) or f'  {DIM}(keep){RESET}'}"


def _change_tag(row: ScanRootRow | ProjectRow) -> str:
    if row.enabled == row.original:
        return ""
    return f"  {RED}← will clean{RESET}" if row.enabled else f"  {GREEN}← will keep{RESET}"


def _render(rows: list[Row], cursor: int, top: int, message: str | None) -> int:
    """Draw one frame that fits the terminal; returns the scroll offset that keeps the cursor visible."""
    header = [
        f"{BOLD}Freespace Config{RESET}  {DIM}({CONFIG_PATH}){RESET}",
        f"{DIM}up/down navigate  {YELLOW}·{DIM}  space toggle"
        f"  {YELLOW}·{DIM}  a add scan root"
        f"  {YELLOW}·{DIM}  d remove scan root"
        f"  {YELLOW}·{DIM}  enter save"
        f"  {YELLOW}·{DIM}  q quit{RESET}",
        "",
    ]

    target_changes  = sum(1 for r in rows if isinstance(r, TargetRow) and r.enabled != r.original)
    project_changes = sum(1 for r in rows if isinstance(r, ProjectRow) and r.enabled != r.original)
    root_changes    = sum(1 for r in rows if isinstance(r, ScanRootRow)
                          and (r.is_new or r.to_remove or r.enabled != r.original))
    if target_changes + project_changes + root_changes:
        parts = []
        if target_changes:  parts.append(f"{YELLOW}{target_changes} target change(s){RESET}")
        if project_changes: parts.append(f"{YELLOW}{project_changes} project change(s){RESET}")
        if root_changes:    parts.append(f"{YELLOW}{root_changes} scan root change(s){RESET}")
        summary = f"  {', '.join(parts)}  {DIM}— enter to save  ·  q to discard{RESET}"
    else:
        summary = f"  {DIM}No unsaved changes{RESET}"
    footer = ["", "", summary] + (["", f"  {YELLOW}{message}{RESET}"] if message else [])

    # viewport: only the rows that fit, scrolled just enough to keep the cursor on screen
    term = shutil.get_terminal_size().lines
    if term - len(header) - len(footer) < 3:   # short terminal: keep the title, scroll hint and last status line
        header, footer = header[:1], footer[:1] + footer[-1:]
    height = max(term - len(header) - len(footer), 1)
    top = min(max(top, cursor - height + 1), cursor, max(len(rows) - height, 0))
    top = max(top, 0)
    visible = [_row_line(r, i == cursor) for i, r in enumerate(rows[top:top + height], top)]
    above, below = top, max(len(rows) - top - height, 0)
    if above or below:
        footer[0] = f"  {DIM}{'↑ ' + str(above) + ' more' if above else ''}"\
                    f"{'  ·  ' if above and below else ''}{'↓ ' + str(below) + ' more' if below else ''}{RESET}"

    # one write per frame, overwrite in place (no full clear), so nothing flickers or scrolls
    lines = (header + visible + footer)[:term]   # never more lines than the screen, or it scrolls
    sys.stdout.write("\033[H" + "\n".join(l + "\033[K" for l in lines) + "\033[J")
    sys.stdout.flush()
    return top


def _prompt_inline(question: str) -> str | None:
    sys.stdout.write(f"\033[?25h\n  {question}: ")
    sys.stdout.flush()
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        line = sys.stdin.readline()
        return line.strip() or None
    except (KeyboardInterrupt, EOFError):
        return None
    finally:
        sys.stdout.write("\033[?25l")
        sys.stdout.flush()


def _interactive(cfg: dict) -> bool:
    rows = _build_rows(cfg)
    cursor = 0
    top = 0
    message: str | None = None

    # alternate screen + no autowrap: the frame owns the screen and long lines clip instead of wrapping
    sys.stdout.write("\033[?1049h\033[?7l\033[?25l")
    sys.stdout.flush()
    try:
        while True:
            top = _render(rows, cursor, top, message)
            message = None
            key = _read_key()

            if key in ("q", "\x03"):
                return False

            elif key in ("k", "\x1b[A"):
                cursor = max(0, cursor - 1)
                while cursor > 0 and isinstance(rows[cursor], SeparatorRow):
                    cursor -= 1

            elif key in ("j", "\x1b[B"):
                cursor = min(len(rows) - 1, cursor + 1)
                while cursor < len(rows) - 1 and isinstance(rows[cursor], SeparatorRow):
                    cursor += 1

            elif key in ("\r", "\n"):
                for row in rows:
                    if isinstance(row, TargetRow):
                        cfg["targets"][row.key] = row.enabled
                cfg["scan_roots"] = [
                    r.path for r in rows
                    if isinstance(r, ScanRootRow) and not r.to_remove
                ]   # may be empty: removing every root turns the project scans off
                cfg["skip_projects"] = _save_projects(rows, cfg.get("skip_projects", []))
                save_config(cfg)
                return True

            elif key == " ":
                row = rows[cursor]
                if isinstance(row, CategoryRow):
                    children = [r for r in rows if isinstance(r, TargetRow) and r.cat_id == row.cat_id]
                    new_state = not all(c.enabled for c in children)
                    for c in children:
                        c.enabled = new_state
                    _update_category(rows, row.cat_id)
                elif isinstance(row, TargetRow):
                    row.enabled = not row.enabled
                    _update_category(rows, row.cat_id)
                elif isinstance(row, (ScanRootRow, ProjectRow)) and row.inherited:
                    message = "Kept by a parent folder in skip_projects; change that entry instead."
                elif isinstance(row, ScanRootRow) and row.to_remove:
                    message = "Marked for removal; press d to keep it."
                elif isinstance(row, ScanRootRow):
                    row.enabled, row.partial = not row.enabled, False   # and every project under it, like a category
                    for kid in rows:
                        if isinstance(kid, ProjectRow) and kid.root == _canon(row.path) and not kid.inherited:
                            kid.enabled = row.enabled
                elif isinstance(row, ProjectRow):
                    row.enabled = not row.enabled
                    root = next(r for r in rows if isinstance(r, ScanRootRow) and _canon(r.path) == row.root)
                    _sync_root(root, [r for r in rows if isinstance(r, ProjectRow) and r.root == row.root])

            elif key == "a":
                # Only meaningful for Dev Projects
                row = rows[cursor]
                if getattr(row, "cat_id", "") == "devprojects" and not isinstance(row, SeparatorRow):
                    sys.stdout.write("\033[?25h")
                    sys.stdout.flush()
                    path_val = _prompt_inline("New scan root path")
                    active = [r.path for r in rows if isinstance(r, ScanRootRow) and not r.to_remove]
                    err = path_val and _root_error(path_val, active)
                    if err:
                        message = err
                    elif path_val:
                        new_row = ScanRootRow(path=path_val, label=path_val, is_new=True,
                                              enabled=_canon(path_val) not in _skip_set(cfg))
                        rows.insert(_section_bounds(rows)[1], new_row)   # end of the scan roots section
                        _refresh_projects(rows, cfg)
                        cursor = next(j for j, r in enumerate(rows) if r is new_row)
                        message = f"Added: {path_val}  (enter to save)"
                    else:
                        message = "Add cancelled."
                else:
                    message = "Navigate into Dev Projects to add scan roots."

            elif key == "d":
                row = rows[cursor]
                if isinstance(row, ScanRootRow):
                    if row.is_new:
                        rows.pop(cursor)
                    else:
                        row.to_remove = not row.to_remove
                    _refresh_projects(rows, cfg)
                    cursor = next((j for j, r in enumerate(rows) if r is row), max(0, cursor - 1))
                    message = "Scan root marked for removal  (enter to save)." if not row.is_new else None
                else:
                    message = "Move cursor to a scan root to remove it."

    finally:
        sys.stdout.write("\033[?25h\033[?7h\033[?1049l")
        sys.stdout.flush()


def run_config() -> None:
    if not (sys.stdin.isatty() and sys.stdout.isatty()):
        print("freespace config requires an interactive TTY.")
        sys.exit(1)
    cfg = load_config()
    saved = _interactive(cfg)
    if saved:
        print(f"Config saved to {CONFIG_PATH}")
    else:
        print("No changes saved.")

# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    args = sys.argv[1:]
    if args in (["config"], ["-c"], ["--config"]):
        run_config()
    elif args in (["-h"], ["--help"]):
        print(__doc__.strip())
    elif set(args) <= {"--dry-run", "-n", "--force", "-f"}:
        run_cleanup(dry=bool({"--dry-run", "-n"} & set(args)), force=bool({"--force", "-f"} & set(args)))
    else:
        # unknown flags used to fall through to a real cleanup
        sys.exit(f"unknown option: {' '.join(args)}  (try -h)")


if __name__ == "__main__":
    main()
