## Usage

### As a Dev Container feature

```jsonc
// .devcontainer/devcontainer.json
{
  "features": {
    "ghcr.io/quantized8/sysset/install-homebrew:0": {}
  }
}
```

Install and make a couple of tools available at build time:

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-homebrew:0": {}
  },
  "postCreateCommand": "brew install bat ripgrep"
}
```

### As a standalone script

The script can be piped directly from the network or run from a local copy.
It must run as root on Linux (to install system build dependencies). On macOS
it may run as a regular user or as root — see [Install user](#install-user)
below.

```sh
# Linux (run as root or with sudo)
curl -fsSL https://raw.githubusercontent.com/quantized8/sysset/main/src/install-homebrew/install.sh \
  | sudo bash

# macOS (run as your regular user, or with sudo for system-wide shellenv)
curl -fsSL https://raw.githubusercontent.com/quantized8/sysset/main/src/install-homebrew/install.sh \
  | bash
```

Pass options as CLI flags when using the standalone mode:

```sh
sudo bash install.sh --if_exists skip --export_path /etc/profile.d/brew.sh
```

### Bootstrap behaviour

`install.sh` at the repository root is a lightweight POSIX sh bootstrap.
On macOS it installs Homebrew first (if neither `brew` nor MacPorts is
present) to obtain bash ≥ 4, then hands off to `install.bash`.
On Linux it uses whatever package manager is available to obtain bash ≥ 4.
Feature callers never need to invoke the bootstrap directly — the devcontainer
framework calls `install.sh` automatically.

---

## How it works

### Platform behaviour

| Platform | Prefix default | Installer runs as | Build deps |
|---|---|---|---|
| macOS (Apple Silicon) | `/opt/homebrew` | non-root user (see [Install user](#install-user)) | Xcode CLT |
| macOS (Intel) | `/usr/local` | non-root user | Xcode CLT |
| Linux | `/home/linuxbrew/.linuxbrew` | root (or current user) | OS packages via `ospkg` |

The official Homebrew installer refuses to run as root on macOS. The feature
always delegates to a non-root user on macOS (see [Install user](#install-user)).
Root installs are explicitly supported on Linux.

### Install user

The user that owns the Homebrew installation is determined in this order:

1. **`install_user` option** — if set, always used.
2. **Non-root caller** — if the script is not running as root, the current
   user installs Homebrew.
3. **`SUDO_USER` (macOS and Linux)** — if running as root and `SUDO_USER` is
   set (i.e. the script was launched via `sudo`), that user is used.
4. **macOS root fallback** — `dscl . list /Users` is queried for the first
   non-system user (excludes accounts starting with `_`, plus `daemon`,
   `nobody`, `root`, `Guest`). If none is found the feature exits with an
   error — the `install_user` option must be set explicitly.
5. **Linux root** — installing as `root` is allowed. The feature prints an
   informational message and proceeds.

### Build dependencies (Linux)

Before running the Homebrew installer, the feature installs the packages
required to build formulae from source:

| Package | Package manager |
|---|---|
| `git` | all |
| `curl` | all |
| `file` | all |
| `build-essential` | APT (Debian/Ubuntu) |
| `procps` | APT, Zypper |
| `procps-ng` | DNF, Pacman |
| `development-tools` group | DNF |
| `base-devel` group | Pacman |
| `devel_basis` pattern | Zypper |

Packages already present on `PATH` (`--skip_installed`) are skipped.

### Xcode Command Line Tools (macOS)

If `xcode-select -p` does not return a valid path the feature installs the
CLT headlessly using the `softwareupdate` sentinel-file technique:

```sh
touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
softwareupdate -i "<package from softwareupdate -l>"
rm  /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
```

If no CLT package is found in `softwareupdate -l` the feature exits with an
error and instructs the user to run `xcode-select --install` manually.

### If already installed

The `if_exists` option controls behaviour when a brew binary already exists
at the resolved prefix:

| Value | Behaviour |
|---|---|
| `skip` (default) | Skip the installer and continue to post-install steps (shellenv export, `brew update`, `brew doctor`). |
| `fail` | Print an error message and exit non-zero immediately. |
| `reinstall` | Run the official uninstaller, then re-run the installer from scratch. |

### shellenv export

`eval "$(brew shellenv)"` makes `brew` and all Homebrew-installed tools
available in interactive shells. The export mode is controlled by
`export_path`:

#### `auto` (default)

**Case A — root caller on Linux**: writes system-wide blocks to three files,
ensuring all user sessions (login, interactive, and Zsh) pick up the
Homebrew prefix on every login:

| File | Shell / session type |
|---|---|
| `/etc/profile.d/brew.sh` | Login shells (bash and POSIX sh sourcing profile.d) |
| `/etc/bash.bashrc` or `/etc/bashrc` | Non-login interactive bash |
| `/etc/zsh/zshenv` or `/etc/zshenv` | All Zsh sessions (login and non-login) |

The exact paths for the global bashrc and zshenv are chosen based on the
detected OS family (Debian/Ubuntu → `/etc/bash.bashrc` and `/etc/zsh/zshenv`;
Alpine → `/etc/bash/bashrc`; RHEL/Fedora/macOS → `/etc/bashrc` and
`/etc/zshenv`).

**Case B — macOS or non-root caller**: writes user-scoped blocks to the
install user's personal startup files:

| File | Shell / session type |
|---|---|
| `~/.bash_profile` (or existing `~/.bash_login` / `~/.profile`) | Login bash |
| `~/.bashrc` | Non-login interactive bash |
| `~/.zprofile` | Login Zsh |
| `~/.zshrc` | Interactive Zsh |

#### `""` (empty string) — disable

No startup files are modified. This is useful when the caller manages shell
configuration separately.

#### Newline-separated path list

When `export_path` contains one or more newline-separated absolute paths the
shellenv block is written only to those files (one per line). System-wide and
per-user defaults are not touched.

```jsonc
{
  "export_path": "/etc/profile.d/brew.sh\n/etc/bash.bashrc"
}
```

#### Additional users

Set `users` to a comma-separated list of usernames to also write the shellenv
block into their personal startup files (same four files as Case B). The
`export_path` option must not be `""` for this to take effect.

```jsonc
{
  "users": "alice,bob"
}
```

### Shellenv marker format

All writes use idempotent marked blocks:

```
# >>> brew shellenv (install-homebrew) >>>
eval "$(/path/to/brew shellenv)"
# <<< brew shellenv (install-homebrew) <<<
```

If the begin marker already exists in a file the block is **updated in
place** — the content between the markers is rewritten without appending a
second copy. This makes re-running the feature safe.

### Post-install steps

After the installer completes (or is skipped when `if_exists=skip`):

1. **Verify** — check that `${prefix}/bin/brew` exists and print its version.
2. **`brew update`** — fetch the latest formula index (skipped when
   `update=false`).
3. **shellenv export** — write the `eval "$(brew shellenv)"` block to the
   configured startup files.
4. **`brew doctor`** — run diagnostics; any warnings are printed but do not
   fail the install.

---

## System paths written

| Path | Condition | Content |
|---|---|---|
| `/etc/profile.d/brew.sh` | Case A (root+Linux), `export_path=auto` | shellenv block |
| `/etc/bash.bashrc` (or `/etc/bashrc`) | Case A (root+Linux), `export_path=auto` | shellenv block |
| `/etc/zsh/zshenv` (or `/etc/zshenv`) | Case A (root+Linux), `export_path=auto` | shellenv block |
| `~/.bash_profile` (or `~/.bash_login` / `~/.profile`) | Case B (macOS/non-root), `export_path=auto` | shellenv block |
| `~/.bashrc` | Case B (macOS/non-root), `export_path=auto` | shellenv block |
| `~/.zprofile` | Case B (macOS/non-root), `export_path=auto` | shellenv block |
| `~/.zshrc` | Case B (macOS/non-root), `export_path=auto` | shellenv block |
| Custom path(s) | `export_path` is a path list | shellenv block |
| `${logfile}` | `logfile` option set | full install log |

---

## Troubleshooting

### `Running as root on macOS but no non-root user found`

The official Homebrew installer refuses to run as root on macOS. Set
`install_user` to a non-root account, or ensure the macOS system has at least
one non-system user account:

```jsonc
{ "install_user": "myuser" }
```

### `No 'Command Line Tools' package found in softwareupdate -l`

The headless CLT install relies on `softwareupdate -l` returning a result.
This can fail in some restricted macOS environments. Install manually and
re-run:

```sh
xcode-select --install
```

### `if_exists=fail: Homebrew already installed at ...`

`if_exists` defaults to `skip`. Set it to `reinstall` to do a clean
reinstall, or to `skip` to reuse the existing installation:

```jsonc
{ "if_exists": "reinstall" }
```

### `brew doctor` warnings

`brew doctor` is run as a diagnostic step only; its exit code is ignored.
Warnings are expected in fresh containers (missing `/usr/local` ownership,
empty `PATH`, etc.) and do not indicate a broken installation.

### Network-isolated environments

Use `brew_git_remote` and `core_git_remote` to point at internal mirrors, and
set `no_install_from_api: true` to clone homebrew-core as a git repository
rather than fetching from the JSON API:

```jsonc
{
  "brew_git_remote": "https://my-mirror.example.com/Homebrew/brew",
  "core_git_remote": "https://my-mirror.example.com/Homebrew/homebrew-core",
  "no_install_from_api": true
}
```

---

## References

- [Homebrew Documentation](https://docs.brew.sh/)
- [Homebrew Linux installation](https://docs.brew.sh/Homebrew-on-Linux)
- [Official install script](https://github.com/Homebrew/install/blob/HEAD/install.sh)
