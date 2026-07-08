# AGENTS.md — dotfiles repo guidance for AI agents

This is @damsleth's personal dotfiles repo, managed with GNU Stow.

> ⚠️ **This repo is PUBLIC.** It must contain **no** secrets, real hostnames,
> IP addresses, work/personal email addresses, internal tenant names, private
> repo names, or absolute `/Users/<name>` paths. Anything personal lives in the
> **private overlay** (`./private/`, gitignored) — see "Private overlay" below.
> If you're about to add a host, IP, email, token, or tenant alias to a tracked
> file, STOP: it belongs in the overlay, not here.

## Repo structure

Every top-level directory (except `_scripts/` and `_docs/`) is a **stow package**.
Each package mirrors the home directory - e.g., `zsh/.zshrc` maps to `~/.zshrc`.

```
dotfiles/
├── <package>/        # stow package - mirrors $HOME
│   ├── .somerc       # maps to ~/.somerc
│   └── .config/      # maps to ~/.config/
│       └── <tool>/
├── _scripts/         # helper scripts (bootstrap-fresh, macos, dock, etc.)
├── _docs/            # package notes that should not be stowed
├── Brewfile          # curated install manifest for `brew bundle`
├── Brewfile.full     # full machine dump (reference, do not run as-is)
├── bootstrap.sh      # stow-only bootstrap (runs on any platform)
├── .gitignore
├── README.md
└── AGENTS.md
```

## Private overlay

Anything personal that shouldn't be public lives in `./private/` (gitignored;
track it as its own private repo if you want history). It mirrors the same stow
layout and is stowed **on top of** the public packages by `bootstrap.sh`.

```
private/
├── Brewfile                         # private Homebrew entries
├── <tool>/                         # personal tool configs (own emails/tenants)
├── ssh/.ssh/config.d/personal       # real hosts/IPs/users (Include'd by public config)
├── ssh/.ssh/{*.pub,kswon-askpass.sh}# identity material + helpers
├── zsh/.zsh/local.zsh               # host-specific / secrets-touching shell funcs
└── _scripts/{repos.txt,local-tools.txt,tools-restore.sh}
```

The public side hooks it without leaking anything: `ssh/.ssh/config` does
`Include ~/.ssh/config.d/*`, `zsh/.zsh/_main.zsh` sources `~/.config/zsh/local.zsh`
if present, and `clone-repos.sh` resolves `repos.txt` from the overlay. None of
those hooks reference real values. **Never move overlay content back into a
tracked package.**

## Critical rules

1. **Never add secrets or PII.** No `.env`, `.netrc`, `.npmrc`, SSH private keys,
   API tokens, passwords, or credentials. Also no real hostnames/IPs, no email
   addresses, no employer/tenant names, no private repo names, no embedded
   shared-secrets in shell functions, and no hardcoded `/Users/<name>` paths
   (use `$HOME`). The `.gitignore` is authoritative — if a file is gitignored,
   keep it that way. When in doubt, put it in the private overlay.

   To re-check before publishing or committing, sweep the tracked tree:
   ```bash
   git ls-files -z | xargs -0 grep -nIE \
     '([0-9]{1,3}(\.[0-9]{1,3}){3}|[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}|Bearer |shared-secret)'
   ```

2. **One package per tool.** Do not merge packages. Do not create a catch-all `home/` package.

3. **Stow packages only contain dotfiles.** No READMEs, no scripts, no metadata inside packages —
   those go in `_scripts/` or the repo root.

4. **Cross-platform awareness.** This repo is used on:
   - macOS (primary, zsh, Homebrew)
   - Ubuntu VPS (zsh, apt)
   - WSL on Windows (zsh)

   macOS-only packages: `karabiner`, `vscode`

   `zsh` package is cross-platform - use `$OSTYPE` checks in shell scripts where needed.

5. **Don't modify what you haven't read.** Always read the current state of a file before editing.

6. **Stow conventions:**
   - Run `stow <package>` from the repo root (`~/Code/dotfiles`)
   - Use `stow --simulate` to preview changes
   - Use `stow -R <package>` to restow after adding files
   - Use `stow -D <package>` to remove symlinks

## Adding a new package

The fast path is `_scripts/import-config.sh`, which moves the live dir into a
new package and stows it in one shot:

```bash
_scripts/import-config.sh <tool>            # ~/.config/<tool>  -> <tool> pkg
_scripts/import-config.sh --home <name>     # ~/.<name>         -> <name> pkg
_scripts/import-config.sh --dry-run <tool>  # preview
```

After it runs: review the package for secrets/caches, optionally add the name
to `COMMON_PACKAGES` in `bootstrap.sh`, then commit.

Manual equivalent:

```bash
mkdir -p ~/Code/dotfiles/<package>
mv ~/.<tool>rc ~/Code/dotfiles/<package>/.<tool>rc
# or for .config/:
mkdir -p ~/Code/dotfiles/<package>/.config/<tool>
mv ~/.config/<tool> ~/Code/dotfiles/<package>/.config/<tool>
cd ~/Code/dotfiles && stow <package>
git add <package> && git commit -m "feat: add <package> package"
```

## ~/.ssh handling

The `ssh` package is **deny-by-default** in `.gitignore`. The tracked
`ssh/.ssh/config` is a **generic template** — it carries no real hosts, IPs,
users, or keys; it just `Include`s `~/.ssh/config.d/*` and sets the 1Password
agent. Real hosts live in the private overlay (`private/ssh/.ssh/config.d/
personal`) or any file you drop in `~/.ssh/config.d/`. Private keys, public
keys, `known_hosts`, `authorized_keys`, and controlmaster sockets are never
committed to this public repo.

Restore flow on a fresh machine:

1. `stow ssh` links `~/.ssh/config` and public keys back into place.
2. Generate or copy private keys onto the box out-of-band (1Password,
   USB, or `ssh-keygen` + re-upload pubkey to GitHub/servers).
3. `chmod 600 ~/.ssh/id_*` and `chmod 644 ~/.ssh/*.pub`.
4. SSH agent integration goes through 1Password (`IdentityAgent` line
   in `ssh/.ssh/config`) — install 1Password first.

## Zsh config layout

The `zsh` package manages:
- `~/.zshrc` — entry point, sets `ZSH_CONFIG_DIR` and sources `_main.zsh`
- `~/.config/zsh/` — all modular zsh config files (Homebrew PATH is initialized from `env.zsh`):
  - `_main.zsh` — loader/orchestrator
  - `alias.zsh` — aliases
  - `env.zsh` — environment variables and PATH
  - `func.zsh` — shell functions
  - `source.zsh` — external tool integrations (starship, cargo, etc.)
  - `comp.zsh` — completions
  - `agents.zsh` — AI agent aliases
  - `ghcs.zsh` — GitHub Copilot CLI
  - `extra.zsh` — early/misc config
  - `tmux.zsh` — tmux config
  - `dtop.zsh` — dtop (minimal process viewer)

Note: `~/.config/zsh/.env` is gitignored — it contains machine-local environment secrets.

## bootstrap.sh

`bootstrap.sh` is the **stow** entrypoint - it links dotfiles into `$HOME`.
On a bare interactive run it opens the **Dotfiles** tab of
`_scripts/dotfiles-wizard.sh` (via `--tab dotfiles --emit`) so the user chooses
which packages to install; flags skip the prompt: `--preset min|rec|all`,
`--all`, `--no-wizard`, plus `--dry-run` to preview. After the public packages,
it stows the private overlay's packages if present.
Platform detection: `uname -s` -> `Darwin` for macOS, `Linux` for Ubuntu/WSL.

Two extra hooks tie the layers together:
- `--full` execs the multi-tab wizard (Homebrew + macOS + npm/pipx, not just
  dotfiles), which drives the whole machine setup.
- `DOTFILES_PRESELECTED="zsh vim …"` (env) skips the picker and stows exactly
  those packages. This is how the full wizard delegates the stow step back to
  `bootstrap.sh` without re-entering the picker (no recursion).

- `_scripts/dotfiles-wizard.sh` - the multi-tab picker (renamed from
  `wizard.sh`). Pure bash (runs on macOS bash 3.2), zero deps, safe over SSH.
  Tabs: **Dotfiles** (per-package, from the `PACKAGES` array near the top — add
  new packages there with category/platform/preset), **Homebrew** (per-category,
  parsed live from the `Brewfile` `# ===` headers), **macOS** (per-category, from
  `macos.sh --list-categories`), **npm**/**pipx** (per-item, from the manifests).
  Homebrew + macOS tabs only appear on macOS. `Tab`/`←→` switch tabs; `Enter`
  applies. On apply it delegates to each domain's script (`brew bundle` on a
  filtered temp Brewfile, `bootstrap.sh` for stow, `macos.sh --only`,
  `lang-restore.sh` with temp manifests). Single-tab/non-interactive modes for
  back-compat: `--tab dotfiles --emit`, `--preset NAME`, `--list`. Chosen keys
  go to stdout, all UI to stderr.

## _scripts/

Helper scripts (executable, not stow packages):

- `_scripts/bootstrap-fresh.sh` - **macOS-only** first-boot orchestrator.
  Sets hostname, installs Xcode CLT + Homebrew, enables TouchID sudo, ensures
  App Store sign-in for `mas`, then chains: `brew bundle` -> `bootstrap.sh` ->
  `macos.sh` -> `secrets-restore.sh` -> `clone-repos.sh` ->
  `toolchains-restore.sh` -> `lang-restore.sh` -> `tools-restore.sh` ->
  `dock.sh` -> `verify-restore.sh` -> `permissions-checklist.sh`. Idempotent.
  Run after the private repo is cloned. Short-lived local-tool auth is intentionally
  not run; auth manually after bootstrap.

- `_scripts/bootstrap-fresh-linux.sh` - **Debian/Ubuntu/WSL** first-boot
  orchestrator and counterpart to `bootstrap-fresh.sh`. Installs apt
  prerequisites, runs `bootstrap.sh` (stow + the apt/snap packages), installs
  the language managers `brew bundle` provides on mac (fnm/rustup/pipx), then
  reuses the shared restore scripts: `toolchains-restore.sh` ->
  `lang-restore.sh` -> `secrets-restore.sh` -> `clone-repos.sh` ->
  `tools-restore.sh` -> `verify-restore.sh`. Clones over HTTPS. Idempotent.

- `_scripts/public-bootstrap-gist.sh` - public-safe gist bootstrap. Installs
  Xcode CLT, Homebrew, `git`, `gh`, `stow`, and `1password-cli`; authenticates
  GitHub over HTTPS; clones the private repo via `gh repo clone`; then runs
  `_scripts/bootstrap-fresh.sh`. Copy this file into the public gist.

- `_scripts/macos.sh` - opinionated `defaults write` for Finder, Dock,
  keyboard, screenshots, etc. Idempotent. Organized into named categories;
  `--list-categories` prints them, `--only finder,dock` runs a subset (the
  macOS wizard tab drives this), `--dry-run` previews without writing.

- `_scripts/dock.sh` - rebuilds the Dock layout via `dockutil`. Idempotent.

- `_scripts/vscode-restore.sh` - installs extensions from
  `_scripts/vscode-extensions.txt`. Supports `--dump` to refresh the list and
  `--yes` to skip the confirmation prompt. Not part of the default fresh
  bootstrap because VS Code Settings Sync owns settings/extensions.

- `_scripts/vscode-extensions.txt` - canonical extension list. Refresh via
  `./_scripts/vscode-restore.sh --dump`.

- `_scripts/clone-repos.sh` - clones repos into `~/code/<name>`. The repo list
  is personal, so it's NOT tracked here: `clone-repos.sh` resolves `repos.txt`
  from `$DOTFILES_PRIVATE/_scripts/` (the overlay), `$REPOS_FILE`, or a local
  `_scripts/repos.txt`, and no-ops if none exist. See `_scripts/repos.txt.example`
  for the format. Supports `--pull` and `--dry-run`. Requires working SSH agent.

- `_scripts/binlink.sh` - interactive picker for symlinking an executable
  from a `~/code` repo into `~/.local/bin`. Supports link / unlink / list.
  This is the manual counterpart to the per-project venv + binlink pattern
  used by private local tools. Itself symlinked to
  `~/.local/bin/binlink`.

- `_scripts/pull-all.sh` - parallel `git pull --ff-only` across every repo
  under `~/code`. Skips non-git dirs, detached HEAD, missing upstream, and
  dirty worktrees instead of erroring. `-j N` controls fan-out (default 6).
  Itself symlinked to `~/.local/bin/pull-all`.

- `_scripts/lang-restore.sh` + `_scripts/{pipx-packages,npm-globals}.txt` -
  reinstall third-party pipx + npm global packages (from PyPI/npm) from
  snapshot lists. Refresh with `lang-restore.sh --dump` (then prune the
  editable local tools back out of `pipx-packages.txt` before committing).

- `_scripts/tools-restore.sh` + `_scripts/local-tools.txt` - **in the private
  overlay** (`private/_scripts/`), since the tool/repo names are personal.
  Editable-installs the self-written Python tools from their `~/code` clones via
  `pipx install --editable`. The orchestrators call it only if present, so the
  public bootstrap skips it cleanly.

- `_scripts/toolchains-restore.sh` - install language toolchains that brew
  alone doesn't cover: fnm LTS Node + corepack, rustup (default stable,
  no PATH edits), and `~/go/bin`. Idempotent. Skips items already present.

- `_scripts/secrets-restore.sh` - restores machine-local secret files from
  1Password CLI (`~/.config/zsh/.env`, SSH private keys) only from refs supplied
  by `ZSH_ENV_OP_REF` and `SSH_PRIVATE_KEY_OP_REFS`; never hard-code actual
  secret values or private 1Password paths in the public repo.

- `_scripts/permissions-checklist.sh` - prints the macOS approvals that cannot
  be reliably granted from shell: system extensions, Accessibility,
  Full Disk Access, Developer Tools, Login Items, VPN, and 1Password SSH Agent.

- `_scripts/verify-restore.sh` - post-bootstrap sanity checker. Verifies
  core CLIs on PATH, `~/.config/zsh/.env`, SSH auth, pipx/npm globals installed,
  and private repos from the overlay manifest when present. macOS-only checks
  (brew bundle clean, App Store sign-in, the macOS 1Password SSH agent socket)
  are skipped on Linux. Exits non-zero if anything fails. Re-runnable.

- `_scripts/audit-public.sh` - public-safety and restore-contract audit. Checks
  shell syntax, public leak patterns, SSH config, package catalog drift, Stow
  simulation, and ShellCheck when available. Run before publishing.

- `_scripts/import-config.sh` - migrate a `~/.config/<tool>` (or `~/.<name>`)
  dir into a new stow package. See "Adding a new package" below.

- `_scripts/test-bootstrap-container.sh` + `_scripts/TESTING.md` - run
  `bootstrap-fresh-linux.sh` end-to-end in a throwaway Ubuntu container (podman)
  with per-step timing. Optionally JIT-inject an SSH key (`SSH_TEST_KEY_OP_REF`
  from 1Password, or `SSH_TEST_KEY_FILE`) so the private clones + editable
  `tools-restore` actually run; the key is mounted read-only from a 0600
  tempfile and never committed/logged, container is `--rm`. See TESTING.md for
  the methodology, knobs, and baseline timings.

## _scripts/windows/

Windows-only (PowerShell) utilities. Self-contained collection; not part of any
`uname`-gated bootstrap. Each util lives in its own subfolder with a README; run
its `Install.ps1` (uses `$PSScriptRoot`, so it registers against this checkout).
Generated runtime artifacts are gitignored per-util.

- `_scripts/windows/info-wallpaper/` - dynamic desktop wallpaper showing host /
  session / RDP source IP / local + external IP / Tailscale + WSL status.
  Refreshes at logon, on RDP (re)connect (scheduled tasks), and on demand.

## Brewfile

`Brewfile` at the repo root is the **curated** install manifest. Run with
`brew bundle --file=~/Code/dotfiles/Brewfile`. The file is organised by
category with `REVIEW` blocks of previously-installed-but-suspect items
commented out - uncomment to keep, delete to drop.

`Brewfile.full` is the unmodified `brew bundle dump` from the previous machine,
kept as a reference. Do not run it directly on a fresh machine - it will
faithfully recreate years of accumulated cruft.

When adding tools, add to `Brewfile` (not `Brewfile.full`) and commit.
