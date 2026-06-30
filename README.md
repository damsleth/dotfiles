# dotfiles

Cross-platform dotfiles by [@damsleth](https://github.com/damsleth), managed
with [GNU Stow](https://www.gnu.org/software/stow/). Zsh + Starship (no
oh-my-zsh), Neovim, modern terminals, and a batteries-included CLI toolbox.

Works across macOS (zsh), Ubuntu (zsh), and WSL. Packages come from
**Homebrew + mas** on macOS and **apt + snap** on Debian/Ubuntu/WSL.

**New here?** Clone it, run `./bootstrap.sh`, and pick what you want from the
checkbox wizard — start with the **Minimal** or **Recommended** preset and toggle
from there. Nothing personal to me ships in this repo (see *Privacy* below).

## TL;DR

The opinionated path — installs everything except the macOS-only/opt-in bits
(`karabiner`, `skhd`, `vscode`):

```bash
brew install stow                 # macOS  (Linux/WSL: sudo apt install -y stow)
git clone https://github.com/damsleth/dotfiles.git ~/Code/dotfiles
cd ~/Code/dotfiles && ./bootstrap.sh --no-wizard
```

Then restart your shell. Want to choose packages yourself? Drop `--no-wizard`
for the interactive picker. Want the full machine (Homebrew + toolchains)? See
*Full machine restore* below.

## Structure

Each top-level directory is a **stow package** — its contents mirror the home directory structure.

```
dotfiles/
├── zsh/          → ~/.zshrc, ~/.config/zsh/         (Starship prompt, aliases, functions)
├── vim/          → ~/.vimrc
├── nvim/         → ~/.config/nvim/                  (LazyVim-based)
├── btop/         → ~/.config/btop/
├── ghostty/      → ~/.config/ghostty/
├── kitty/        → ~/.config/kitty/
├── glow/         → ~/.config/glow/
├── lf/           → ~/.config/lf/
├── trippy/       → ~/.trippy.toml
├── karabiner/    → ~/.config/karabiner/     (macOS)
├── skhd/         → ~/.config/skhd/          (macOS)
├── vscode/       → ~/Library/.../Code/User/ (macOS, opt-in)
├── ssh/          → ~/.ssh/config            (generic template, no keys/hosts)
└── hushlogin/    → ~/.hushlogin
```

Personal packages (my own tooling/configs) are **not** in this repo — they live
in a separate private overlay. See *Privacy & the private overlay* below.

## Prerequisites

```bash
# macOS
brew install stow

# Ubuntu / Debian / WSL
sudo apt install stow
```

## Quick start (just the dotfiles)

```bash
git clone https://github.com/damsleth/dotfiles.git ~/Code/dotfiles
cd ~/Code/dotfiles
./bootstrap.sh            # opens the dotfiles package wizard
```

The wizard is a zero-dependency checkbox picker (arrow keys / `j k` to move,
`space` to toggle, `Enter` to install). Toggle packages, or pick a preset and
tweak it:

```bash
./bootstrap.sh --preset min    # bare essentials: zsh, vim, ssh, hushlogin
./bootstrap.sh --preset rec     # recommended: + nvim, terminals, btop, lf, glow, trippy
./bootstrap.sh --all            # everything available on this platform
./bootstrap.sh --no-wizard      # recommended set, no prompt (good for CI/headless)
./bootstrap.sh --dry-run --all  # preview without changing anything
```

### The full wizard (more than just dotfiles)

`./bootstrap.sh` only links dotfiles. For a one-screen setup of the whole
machine, run the multi-tab wizard:

```bash
./bootstrap.sh --full              # or: ./_scripts/dotfiles-wizard.sh
./bootstrap.sh --full --dry-run    # preview every layer, change nothing
```

`Tab` / `←→` switches between checklists — **Dotfiles**, **Homebrew** (Brewfile
categories), **macOS** (system defaults by category), **npm** and **pipx**
globals (Homebrew + macOS tabs are macOS-only). Toggle what you want in each tab,
press `Enter`, and it applies them in order: `brew bundle` (filtered to your
selected categories) → stow → `macos.sh` → npm/pipx. Each layer is idempotent and
just drives the same underlying scripts you can also run on their own
(`_scripts/macos.sh --only finder,dock`, etc.).

On Linux, `bootstrap.sh` also apt-installs `bat`, `golang-go`, `snapd` then
`snap install`s `core`/`msedit` (the `bat` binary is symlinked from `batcat`).
Restart your shell (or `source ~/.zshrc`) when it finishes.

> **Coming from iTerm2 + oh-my-zsh?** This uses Starship instead of oh-my-zsh and
> is terminal-agnostic. The `zsh` package is self-contained — `stow zsh` (or the
> Minimal preset) is enough to try the prompt/aliases/functions without adopting
> anything else.

## Full machine restore (my setup — optional)

These orchestrators install Homebrew/apt, toolchains, and run the whole flow.
They're how *I* rebuild a machine; you can run them too, but the Minimal/
Recommended presets above are the friendlier starting point.

```bash
# macOS — one shot from a fresh Mac (installs git/gh/stow, clones, hands off):
curl -fsSL https://gist.githubusercontent.com/damsleth/b773ac8fa887e0ed0f08154ca9a725af/raw/public-bootstrap-gist.sh | bash

# Debian / Ubuntu / WSL:
git clone https://github.com/damsleth/dotfiles.git ~/Code/dotfiles
~/Code/dotfiles/_scripts/bootstrap-fresh-linux.sh
```

Steps that need my private overlay (cloning my repos, editable-installing my
own tools) skip cleanly when the overlay isn't present. After the script
finishes, see the printed checklist for manual follow-ups (macOS permission
grants, 1Password SSH Agent, VS Code Settings Sync).

### What gets installed where

Package managers: **Homebrew + mas** on macOS, **apt + snap** on Debian/Ubuntu/WSL.

- `Brewfile` -> macOS formulae, casks, fonts, mas (App Store) apps. Run with `brew bundle --file=Brewfile`.
- `bootstrap.sh` -> symlinks dotfile packages into `$HOME` via stow; on Linux also runs the apt/snap installs.
- `_scripts/bootstrap-fresh.sh` -> macOS first-boot orchestrator (Homebrew, brew bundle, toolchains, secrets, ...).
- `_scripts/bootstrap-fresh-linux.sh` -> Debian/Ubuntu first-boot orchestrator (apt/snap, language managers, toolchains, ...).
- `_scripts/macos.sh` -> `defaults write` for Finder, Dock, keyboard, screenshots (macOS).
- `_scripts/dock.sh` -> rebuilds Dock layout via dockutil (macOS).
- `_scripts/secrets-restore.sh` -> restores `~/.config/zsh/.env` and SSH private keys from 1Password.
- `_scripts/permissions-checklist.sh` -> prints macOS permission/system-extension follow-ups.
- VS Code settings/extensions -> restored by VS Code Settings Sync after sign-in.

The `Brewfile.full` is the raw dump from the previous machine - reference only,
not meant to be run directly. The curated `Brewfile` is the source of truth.

## Testing the Linux bootstrap

Run the whole `bootstrap-fresh-linux.sh` flow end-to-end in a throwaway Ubuntu
container (podman) - without touching your host - and get a per-step timing
report. Linux host only.

```bash
sudo apt install -y podman
_scripts/test-bootstrap-container.sh
```

The private-repo clones and the editable `tools-restore` step need GitHub SSH
auth, so they warn-skip by default. To exercise them, inject a key just-in-time
(mounted read-only from a 0600 tempfile, never committed or logged, container
`--rm`) - prefer a dedicated unencrypted deploy key:

```bash
SSH_TEST_KEY_OP_REF='op://Private/GitHub deploy key/private key' \
    _scripts/test-bootstrap-container.sh     # from 1Password
SSH_TEST_KEY_FILE=~/.ssh/throwaway_ed25519 \
    _scripts/test-bootstrap-container.sh     # from a key file
```

See [`_scripts/TESTING.md`](_scripts/TESTING.md) for the methodology, env knobs
(`PODMAN`, `IMAGE`, `KEEP_LOG`), security notes, and baseline timings.

## Managing packages

```bash
cd ~/Code/dotfiles

# Stow a single package
stow zsh

# Unstow (remove symlinks)
stow -D zsh

# Re-stow (restow, useful after adding files to a package)
stow -R zsh

# Dry run — preview what would happen
stow --simulate zsh
stow --simulate -D zsh
```

## Adding a new dotfile to an existing package

```bash
# Move the file into the correct package directory
mv ~/.config/foo/bar.conf ~/Code/dotfiles/foo/.config/foo/bar.conf

# Re-stow to create the new symlink
cd ~/Code/dotfiles && stow -R foo
```

## Adding a new package

```bash
# Create the package mirror structure
mkdir -p ~/Code/dotfiles/newtool
mv ~/.config/newtool ~/Code/dotfiles/newtool/.config/newtool
# OR for home-level dotfiles:
mv ~/.newtoolrc ~/Code/dotfiles/newtool/.newtoolrc

# Stow it
cd ~/Code/dotfiles && stow newtool

# Commit
git add newtool && git commit -m "feat: add newtool package"
```

## Platform notes

Some packages are macOS-only (`karabiner`, `vscode`).
On Linux/WSL, skip those packages in `bootstrap.sh` or just don't stow them.

`vscode` is intentionally **not** auto-stowed by `bootstrap.sh`. VS Code
Settings Sync is the canonical restore path for settings and extensions.

The `zsh` package is cross-platform - shell config uses `$OSTYPE` checks internally where needed.

## Refreshing captured state

```bash
# After installing/removing tools, refresh the curated manifest:
brew bundle dump --force --describe --file=Brewfile.full
# Then hand-edit Brewfile to add/remove from the curated list.

# After tweaking VS Code extensions:
./_scripts/vscode-restore.sh --dump
```

## Privacy & the private overlay

This is a **public** repo, so it contains no secrets and nothing personal:
secrets are stored as 1Password (`op://`) references resolved at runtime, the
SSH config is a generic template (no real hosts/IPs/keys), and my own tooling
configs aren't here.

Anything personal lives in a **private overlay** — a sibling directory with the
same stow layout that's gitignored here (`./private/`, or `$DOTFILES_PRIVATE`).
If present, `bootstrap.sh` stows it *on top of* the public packages. The public
side hooks it cleanly: `ssh/.ssh/config` does `Include ~/.ssh/config.d/*`,
`zsh/.zsh/_main.zsh` sources `~/.config/zsh/local.zsh` if it exists, and
`clone-repos.sh` reads its repo list from the overlay. You don't need the
overlay to use these dotfiles — it's just where my private bits go.

To make your own private layer: create `private/<package>/...` mirroring the
stow layout (e.g. `private/ssh/.ssh/config.d/personal`), and optionally
`git init` it as a private repo.

## What's NOT in this repo

- SSH private keys, public keys, and real hosts (`~/.ssh/config` is a template)
- Credentials / tokens (`.env`, `.netrc`, `.npmrc`) — secrets are `op://` refs
- My personal tool configs and repo lists (they're in the private overlay)
- Oh-my-zsh (using [Starship](https://starship.rs) instead)
- Tool-generated caches, history files, and state
- Mac App Store sign-in (`mas` is installed; run `mas list` once signed in)
