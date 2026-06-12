# Testing the Linux bootstrap in a container

`_scripts/bootstrap-fresh-linux.sh` chains apt/snap installs, language-manager
bootstraps, `stow`, and the shared restore scripts. The cheapest way to know it
still runs end-to-end on a *clean* box - without touching your host - is to run
it in a throwaway Ubuntu container. `_scripts/test-bootstrap-container.sh`
drives that and reports how long each step took.

## Requirements

- A **Linux host** (the script uses GNU `mktemp --suffix`, and the in-container
  timing relies on bash 5's `EPOCHSECONDS`, which Ubuntu 24.04 ships).
- **podman**. By default the script uses `sudo podman` (rootful) for reliable
  container networking; set `PODMAN=podman` to use rootless if you've configured
  subuid/subgid + slirp4netns.
  ```bash
  sudo apt install -y podman
  ```

## Quick start

```bash
_scripts/test-bootstrap-container.sh
```

This pulls `ubuntu:24.04` (cached after the first run), creates a non-root
`tester` user with passwordless sudo, copies the repo in, runs the orchestrator,
and prints a per-step timing table plus a post-run sanity block (fnm/node/go/
rustc reachable, only Node v26 installed).

Env knobs: `PODMAN`, `IMAGE`, `KEEP_LOG=1` (keep + print the timestamped log).

## Exercising the editable tools (`tools-restore.sh`) with a JIT SSH key

The orchestrator's `clone-repos.sh` + `tools-restore.sh` need GitHub SSH auth to
clone the private repos and editable-install the local tools. A bare container
has no auth, so those steps **warn-skip** by default - the rest of the run still
validates.

To exercise them, inject an SSH key just-in-time. The key is read into a `0600`
tempfile, mounted **read-only**, copied into the container user's `~/.ssh`, and
the container runs `--rm` so it disappears on exit. The key is **never** written
into the repo or printed to the log.

```bash
# From 1Password (op CLI signed in):
SSH_TEST_KEY_OP_REF='op://Private/GitHub deploy key/private key' \
    _scripts/test-bootstrap-container.sh

# From a key file on the host:
SSH_TEST_KEY_FILE=~/.ssh/throwaway_ed25519 \
    _scripts/test-bootstrap-container.sh
```

Security notes:
- **Prefer a dedicated read-only deploy key** over your personal key. The key
  briefly lives in a host tempfile and inside a throwaway container.
- Use an **unencrypted** key (the non-interactive clone can't answer a
  passphrase prompt), which is another reason to use a throwaway/deploy key.
- The host tempfile is `0600` and removed on exit (including on Ctrl-C, via a
  trap); the container is `--rm`.

With a working key the sanity block additionally lists the editable tools that
landed on PATH (`ledger`, `yaams`, `owa-piggy`, `owa-cal`, `owa-mail`).

## What it validates

- apt prerequisites + `bootstrap.sh` (stow, `bat`/`golang-go`/`snapd`, the
  `bat`->`batcat` symlink). `snap install` warn-skips with no systemd - the
  documented WSL caveat.
- Language managers (pipx/fnm/rustup) install; **fnm is symlinked into
  `~/.local/bin`** so it's reachable in a login shell; only **Node v26** is
  seeded (fnm `--use-on-cd` handles per-project majors on demand).
- `lang-restore.sh` (third-party pipx/npm globals), `clone-repos.sh`, and -
  with an SSH key - `tools-restore.sh` editable installs.
- `verify-restore.sh` skips the macOS-only checks on Linux.
- `owa-piggy login` is **not** invoked (intentionally removed from the orchestrator).

## Timing methodology

The in-container entrypoint prefixes every orchestrator line with elapsed
seconds since the orchestrator started. The host parses the `[boot]` step
anchors and prints the delta between consecutive anchors, plus container-prep
time and total host wall-clock.

### Baseline (arm64, cached image, no SSH key)

| Step | ~Duration |
|---|---|
| container prep (sudo+certs, useradd, copy repo) | 10s |
| apt prerequisites (git, curl, build-essential, stow…) | 16s |
| `bootstrap.sh` (stow + apt + snap attempts) | ~20s |
| install pipx (apt) | 6s |
| install fnm (+ `~/.local/bin` symlink) | <1s |
| install rustup (+ stable toolchain) | ~14s |
| `toolchains-restore` (Node v26 + corepack + GOPATH) | ~3s |
| `lang-restore` (pipx `mark` ~60s + npm globals) | ~80s |
| `clone-repos` (warn-skip without a key) | ~7s |
| `tools-restore` (warn-skip without a key) | <1s |
| `verify-restore` | ~34s |
| **orchestrator total** | **~180s** |
| **host wall** | **~195s** |

`lang-restore` dominates (registry installs: `pipx mark` and the npm globals).
With an SSH key, add the real `clone-repos` + `tools-restore` time (the editable
`pipx install` builds one venv per tool).

## Cleanup

```bash
sudo podman image rm docker.io/library/ubuntu:24.04   # drop the cached image
sudo apt remove --purge -y podman                     # if you only installed it to test
```
