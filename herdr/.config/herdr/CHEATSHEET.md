# herdr cheatsheet

Terminal workspace manager for coding agents — <https://herdr.dev>.
A background **server** owns the real terminal processes; **clients** attach to
render them. Close the lid, the work keeps running.

Stowed to `~/.config/herdr/CHEATSHEET.md`, next to `config.toml`.
Read it anywhere with `glow ~/.config/herdr/CHEATSHEET.md`.

## Model

    session    persistent server namespace (default: "default")
     └ workspace   one per repo/task
        └ tab         a layout
           └ pane        a real terminal
              └ agent       recognised process, reports its state

Agent states: `working` · `blocked` · `done` · `idle` · `unknown`.
**`blocked` is the point** — it's how you spot which agent is sitting on a
permission prompt while a dozen others churn.

## Keys

Prefix is `ctrl+b` (same as tmux). `prefix+?` lists every binding in-app.

| Key | Action |
| --- | --- |
| `prefix+q` | detach (server keeps running) |
| `prefix+w` | workspace picker — main navigation |
| `prefix+g` | goto / navigate mode |
| `prefix+shift+n` | new workspace |
| `prefix+shift+g` | new git-worktree workspace |
| `prefix+shift+w` / `prefix+shift+d` | rename / close workspace |
| `prefix+c` | new tab |
| `prefix+n` / `prefix+p` / `prefix+1..9` | next / prev / jump to tab |
| `prefix+shift+t` / `prefix+shift+x` | rename / close tab |
| `prefix+v` / `prefix+minus` | split right / split down |
| `prefix+h` `j` `k` `l` | focus pane left/down/up/right |
| `prefix+tab` / `prefix+shift+tab` | cycle panes |
| `prefix+z` | zoom pane |
| `prefix+r` | resize mode |
| `prefix+x` / `prefix+shift+p` | close / rename pane |
| `prefix+b` | toggle sidebar |
| `prefix+e` | edit scrollback in `$EDITOR` |
| `prefix+s` | settings |
| `prefix+shift+r` | reload `config.toml` |
| `prefix+o` | open notification target |

Mouse-first, unlike tmux: click panes and tabs, drag borders, right-click for a
context menu. Set `ui.mouse_capture = false` if you'd rather the outer terminal
keep clicks.

## CLI

    herdr                          launch or attach (cwd becomes the workspace)
    herdr --session <name>         use/create a named session
    herdr --no-session             monolithic, no server — escape hatch
    herdr status [server|client]   runtime status
    herdr server stop              stop everything
    herdr server reload-config     re-read config.toml in place
    herdr update [--handoff]       self-update; --handoff keeps the session live
    herdr completion zsh           shell completions (wired up in zsh/comp.zsh)

Socket-API helpers, all JSON — the basis for any fleet tooling:

    herdr workspace list
    herdr agent list
    herdr pane <subcommand>
    herdr tab <subcommand>
    herdr worktree <subcommand>
    herdr api <subcommand>

## Remote

    herdr --remote <ssh-host>                     attach to that host's server
    herdr --remote <ssh-host> --session <name>
    herdr --remote <ssh-host> --remote-keybindings server

Runs ssh through a generated config that includes `~/.ssh/config` first, then
adds `ServerAliveInterval`/`ServerAliveCountMax` as fallbacks (your own values
still win) and reuses one authenticated connection over a private control
socket — so it survives idle NAT timeouts. Disable that management with
`[remote] manage_ssh_config = false`.

## Integrations

State reporting is per-agent and **opt-in** — without it the sidebar shows
`unknown` for everything.

    herdr integration status
    herdr integration install <agent>
    herdr integration uninstall <agent>

Recognised: `claude` `codex` `copilot` `pi` `omp` `gemini` `cursor` `devin`
`cline` `opencode` `kimi` `kiro` `droid` `amp` `grok` `hermes` `kilo` `qwen`
`qoder` `maki` `antigravity-cli` `mastracode`.

Installing writes a hook into that agent's own config dir — e.g. `claude` adds a
`SessionStart` entry to `~/.claude/settings.json` alongside whatever is already
there. **Run this on every machine**; it's local state, not stowed.

## Config

`~/.config/herdr/config.toml` → stowed from `herdr/.config/herdr/config.toml`.
Everything else in that directory (sockets, logs, `session.json`) is runtime
state and stays untracked.

    herdr --default-config     print the full annotated default
    herdr config reset-keys    back up and drop custom keybindings

Worth knowing:

| Setting | Why |
| --- | --- |
| `[session] resume_agents_on_restore` | restores agent panes into their *native* conversation sessions after a server restart; needs the integrations above |
| `[ui] agent_panel_sort = "priority"` | sidebar as an attention queue instead of grouped by workspace |
| `[ui] status_indicators = "symbols"` | distinct glyphs per state instead of colour dots |
| `[ui.toast] delivery` | `off` · `herdr` · `terminal` · `system` |
| `[ui.sound] enabled` | audible ping on state change in background workspaces |
| `[worktrees] directory` | defaults to `~/.herdr/worktrees` |
| `[theme] auto_switch` | follows the host terminal's light/dark, like the kitty/ghostty switchers |

`[[keys.command]]` binds custom commands — `type = "popup"` gets you a modal
terminal without disturbing the layout:

    [[keys.command]]
    key = "prefix+alt+g"
    type = "popup"
    command = "lazygit"
    width = "80%"
    height = "80%"

## Troubleshooting

    herdr agent list                      what herdr thinks is running
    herdr agent explain <target> --json   why a pane did or didn't match
    herdr integration status              hooks installed and current?
    herdr status                          client/server version + protocol

Logs sit beside the config: `herdr.log`, `herdr-client.log`, `herdr-server.log`.
Nesting herdr inside a herdr pane is off unless
`[experimental] allow_nested = true`.
