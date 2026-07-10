# Notes

## Install user

Homebrew refuses to run as `root`, so the feature always installs and runs
`brew` as a non-root user. That user (also the owner of the installation
prefix) is resolved in this order:

1. **`install_user` option** — used verbatim when set. A non-root caller may
   only install for itself; only `root` can install on behalf of another user.
2. **Non-root caller** — the current user installs Homebrew into their own
   prefix (`${HOME}/.linuxbrew` on Linux, the standard prefix on macOS).
3. **Linux as `root`** — a dedicated `linuxbrew` system account is created (if
   absent) and owns the canonical `/home/linuxbrew/.linuxbrew` prefix. This
   account is used even when `SUDO_USER`/`_REMOTE_USER` is set, so the install
   is treated as system-scoped.
4. **macOS as `root`** — the invoking user is resolved via `SUDO_USER` /
   `_REMOTE_USER`; if that still resolves to `root`, the first non-system
   account from `dscl . list /Users` (excluding `_*`, `daemon`, `nobody`,
   `root`, `Guest`) is used. If no such account exists the feature aborts —
   set `install_user` explicitly.

Because installing the OS build dependencies needs `root`, a standalone
(non-devcontainer) run on Linux should be invoked as `root` (or via `sudo`).
On macOS it can run as a regular user.

## Shell activation

The `eval "$(brew shellenv)"` block that puts `brew` on `PATH` is written by the
standard prefix-discovery machinery (see the `prefix_discovery`,
`prefix_exports`, and `prefix_discovery_snippet_*` options). Its scope depends
on the install:

- **Linux as `root`** — written system-wide (under `/etc/profile.d` and the
  global bash/zsh init files) so every user gets Homebrew on login.
- **macOS, or any non-root install** — written to the install user's personal
  startup files. On macOS the prefix (`/opt/homebrew`, `/usr/local`) lives
  outside `$HOME` but is user-owned, so activation is always user-scoped.

## Air-gapped and mirror setups

For environments without access to the public Homebrew endpoints, combine the
network options: point `brew_git_remote` and `core_git_remote` at internal
mirrors and set `no_install_from_api: true` so `homebrew-core` is cloned as a
full git repository instead of using the JSON API.

```jsonc
{
  "brew_git_remote": "https://my-mirror.example.com/Homebrew/brew",
  "core_git_remote": "https://my-mirror.example.com/Homebrew/homebrew-core",
  "no_install_from_api": true
}
```

## Troubleshooting

### `Running as root on macOS but no non-root user found`

Homebrew cannot run as `root` on macOS and the feature could not find a
non-system account to install for. Set `install_user` to a non-root account:

```jsonc
{ "install_user": "myuser" }
```

### `No 'Command Line Tools' package found in softwareupdate -l`

On macOS the feature installs the Xcode Command Line Tools headlessly via
`softwareupdate`. In some restricted environments `softwareupdate -l` returns
no CLT package; install them manually and re-run:

```sh
xcode-select --install
```

### `brew doctor` warnings

`brew doctor` runs only as a post-install diagnostic and its exit code is
ignored. Warnings are expected in fresh containers (unowned `/usr/local`, a
sparse `PATH`, etc.) and do not indicate a broken installation.

## References

- [Homebrew documentation](https://docs.brew.sh/)
- [Homebrew on Linux](https://docs.brew.sh/Homebrew-on-Linux)
- [Official install script](https://github.com/Homebrew/install/blob/HEAD/install.sh)
