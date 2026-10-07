# zsh package

This file shows how the zsh config gets from the repos into `$HOME`.
For what each module does, see [`_docs/zsh.md`](../_docs/zsh.md).

Two repos supply the files. Stow links them into `$HOME` with `--no-folding`, so
`~/.config/zsh/` is a real directory that holds one symlink per file.

- `~/code/dotfiles` is the public repo. It holds the `zsh` package.
- `~/code/dotfiles-private` is the private overlay. `~/code/dotfiles/private` is a
  symlink to it. Its `zsh` package adds `local.zsh` and `secrets.zsh`.

## How the files connect

| Path in `$HOME` | Links to | Repo | Read by | Role |
| --- | --- | --- | --- | --- |
| `~/.zshenv` | `zsh/.zshenv` | dotfiles | every zsh, also non-interactive shells | Points `SSH_AUTH_SOCK` at the 1Password agent. Loads `~/.config/zsh/.env`. |
| `~/.zshrc` | `zsh/.zshrc` | dotfiles | interactive zsh | Sets `ZSH_CONFIG_DIR` (default `~/.config/zsh`). Sources `_main.zsh`, then `late.zsh`. |
| `~/.config/zsh/_main.zsh` | `zsh/.config/zsh/_main.zsh` | dotfiles | `~/.zshrc` | Entry point. Sources the modules in order. |
| `~/.config/zsh/{extra,env,alias,agents,func,source,ghcs,comp,tmux}.zsh` | `zsh/.config/zsh/` | dotfiles | `_main.zsh` | The modules. |
| `~/.config/zsh/starship.toml` | `zsh/.config/zsh/starship.toml` | dotfiles | Starship, via `STARSHIP_CONFIG` | Prompt config. |
| `~/.config/zsh/secrets.zsh` | `zsh/.config/zsh/secrets.zsh` | dotfiles-private | `_main.zsh`, if present | Defines `OP_SECRETS` and `secret NAME`, which resolves a 1Password reference on demand. |
| `~/.config/zsh/local.zsh` | `zsh/.config/zsh/local.zsh` | dotfiles-private | `_main.zsh`, if present | Host-specific functions that must not be public. |
| `~/.config/zsh/late.zsh` | `zsh/.config/zsh/late.zsh` | dotfiles | `~/.zshrc`, after `_main.zsh` | iTerm2 integration and the PATH safety net. |
| `~/.config/zsh/.env` | `zsh/.config/zsh/.env` | dotfiles, gitignored | `~/.zshenv` | Machine-local tokens as `KEY=value` lines. `_scripts/secrets-restore.sh` writes it from 1Password. |
| `~/.zprofile` | none, a real file | none | login zsh | Not managed. Installers append to it. `env.zsh` already sets `PATH`. |

The public `zsh` package can hold gitignored copies of `local.zsh` and
`secrets.zsh`. `bootstrap.sh` ignores them for the public package, so only the
private overlay links them.

## Install

Run `bootstrap.sh`. It stows the public packages first and the private overlay
after them.

To stow only zsh by hand:

```sh
stow --no-folding --dir="$HOME/code/dotfiles" --target="$HOME" \
  --ignore='^\.config/zsh/local\.zsh$' --ignore='^\.config/zsh/secrets\.zsh$' zsh
stow --no-folding --dir="$HOME/code/dotfiles-private" --target="$HOME" zsh
```

## Old paths

Earlier layouts used `~/.zsh/` and `~/code/.zsh/`. No file sources them.
If one of these directories comes back, a stow command ran with the wrong
`--target`. Remove the directory and stow again with `--target="$HOME"`.
