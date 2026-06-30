# [@damsleth's](https://github.com/damsleth) zsh config

### new mac what dis?

My personal z-shell configuration. It used to be a single `.zshrc` file, but became
unwieldy somewhere past ~1000 LoC, so I split it into focused modules that each own one
concern. `~/.zshrc` does almost nothing — it just sets `ZSH_CONFIG_DIR` (defaulting to
`~/.config/zsh`) and sources [`_main.zsh`](_main.zsh), which loads everything else in
order and (optionally) times each file as it goes.

No framework, no Oh-My-Zsh. Just plain zsh, lazy-loading where it matters, and a pile of
[Cool And Useful Functions™️](func.zsh) collected over the years.

## Layout

| File                            | Description                                                                                  |
| ------------------------------- | -------------------------------------------------------------------------------------------- |
| [`_main.zsh`](_main.zsh)        | Entry point. Sources every other module in order, sets `DEFAULT_USER`, and times the load when `TIME_SOURCING_ENABLED=1`. Short-circuits to a minimal config inside VS Code terminals so it doesn't fight the AI integration. |
| [`extra.zsh`](extra.zsh)        | Early config: root welcome banner, and `Ctrl-X Ctrl-E` to edit the current command line in `$EDITOR`. |
| [`env.zsh`](env.zsh)            | Environment variables, locale, history, XDG dirs, cached Homebrew `shellenv`, and the canonical `PATH` (built as a deduped array). |
| [`alias.zsh`](alias.zsh)        | Aliases — navigation, git shortcuts, network/recon helpers, dark/light mode, app launchers, `updateall`, and friends. |
| [`agents.zsh`](agents.zsh)      | Coding-agent shortcuts: `clauded`/`codexd` (yolo mode), plus `codexq` for a quick non-interactive Codex answer. |
| [`func.zsh`](func.zsh)          | The big one. Shell functions — `q` (ask Codex), `serve`/`pipe` (localtunnel), `kp` (fzf kill), `mkd`, `wallpaper`, `jwt-decode`, `watt`, `binlink`, iMessage/OTP helpers, and more. |
| [`source.zsh`](source.zsh)      | Sources external tools: Starship, fzf keybindings, zsh-autosuggestions, fnm, autojump, and lazy-loaded cargo/chruby/ESP-IDF. |
| [`ghcs.zsh`](ghcs.zsh)          | GitHub Copilot CLI wrappers — `ghcs` (suggest + run a command) and `ghce` (explain a command). |
| [`comp.zsh`](comp.zsh)          | Completion setup: `compinit`, `fpath` additions, cached bun/1Password completions, and the `opinit` 1Password sign-in helper. |
| [`secrets.zsh`](secrets.zsh)    | On-demand secret retrieval from 1Password. `OP_SECRETS` maps env-var names to commit-safe `op://` references; `secret NAME` resolves one into the shell only when asked. |
| [`tmux.zsh`](tmux.zsh)          | tmux session helpers — `ta` (attach/create), `rt` (remote sessions over SSH), `t`. |
| [`starship.toml`](starship.toml) | [Starship](https://starship.rs) prompt config (loaded via `STARSHIP_CONFIG` in `source.zsh`). |

## Install

```sh
git clone https://github.com/damsleth/dotfiles ~/code/dotfiles
mkdir -p ~/.config
ln -s ~/code/dotfiles/zsh/.zsh ~/.config/zsh
ln -s ~/code/dotfiles/zsh/.zshrc ~/.zshrc
```

Set `DEFAULT_USER` at the top of [`_main.zsh`](_main.zsh) to your own username, then open
a new shell. Edit the config any time with `zshconfig` and reload with `reload`.

Optional extras the config will use if present (and silently skip if not): `starship`,
`fzf`, `fnm`, `autojump`, `eza`, `bat`, `op` (1Password CLI), and a checkout of
[zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) under
`~/.config/zsh/plugins/`.

## Benchmarking startup

The loader can time itself. In [`_main.zsh`](_main.zsh):

| Flag                       | Effect                                                              |
| -------------------------- | ------------------------------------------------------------------- |
| `TIME_SOURCING_ENABLED=1`  | Time the whole load and print the total (in rainbow) on startup.    |
| `TIME_SOURCING_VERBOSE=1`  | Also print a per-file breakdown, sorted slowest-first.              |

Timing uses zsh's `zsh/datetime` module (`$EPOCHREALTIME`) so the measurement itself is
cheap. For a wall-clock figure from outside the shell, there's the `timing` alias, which
runs `zsh -i -c exit` under `/usr/bin/time` and prints the real time.

## Notes

- **VS Code terminals** get a stripped-down config — `_main.zsh` returns early after
  loading env + aliases so it doesn't interfere with the editor's shell/AI integration.
- **Lazy loading** keeps startup snappy: cargo, rustc, rustup, chruby, and ESP-IDF only
  initialize the first time you call them.
- **Caching**: Homebrew `shellenv`, the 1Password completion script, and the `.zcompdump`
  are all cached/compiled so they don't recompute on every shell.
- **Cross-platform-ish**: `env.zsh` detects the OS (`ZSH_OS`) and locates Homebrew on
  Apple Silicon, Intel, or Linuxbrew, so most of this works on Linux too.
- `.env` (gitignored) holds machine-local secrets like SSH targets used by `tmux.zsh`.
- **Secrets stay out of the repo**: [`secrets.zsh`](secrets.zsh) commits only `op://`
  *references*, never values. `secret THINGS_AUTH_TOKEN` resolves one into the current
  shell on demand; `secret` lists them; `secret NAME -p` prints instead of exporting. For
  secrets that should never touch the interactive shell, wrap the command in `op run --`.
