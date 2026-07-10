# Notes

## Supported Installation Methods

The feature resolves an installation method automatically from the platform (or
you can force one with `method`):

- **`upstream-package`** — adds the official GitHub CLI package repository and
  signing key, then installs `gh` with the system package manager. Applies to
  Debian/Ubuntu (`apt`), Fedora/RHEL and derivatives (`dnf`/`yum`), and
  openSUSE (`zypper`). This is the recommended method on these platforms: the
  packages are published by the GitHub CLI team. The added repository and key
  are removed after install by default; set `keep_repos=true` to retain them so
  the package manager can pick up future updates (e.g. via `apt upgrade`).
- **`package`** — installs the `github-cli` package from the distribution's own
  standard repositories. Applies to Alpine (`apk`) and Arch (`pacman`). These
  packages are **community-maintained** — not published by the GitHub CLI team —
  so they may lag the latest upstream release.
- **`binary`** — downloads the pre-built release binary from GitHub Releases and
  verifies its SHA-256 checksum. Works on every supported platform and is the
  only method that installs into a custom `prefix`.

macOS has no package-manager method defined, so installs on macOS always use
`method=binary`.

## Version Selection

- **`method=binary`** downloads the exact requested release asset from GitHub
  Releases, so any published version can be pinned reproducibly on every
  platform. This is the method to use when an exact `gh` version matters.
- **`method=package` and `method=upstream-package`** install whatever the
  package manager's configured repositories currently offer. Exact-version
  pinning is only as reliable as the package manager and repository allow; the
  community `apk`/`pacman` packages in particular cannot be pinned to arbitrary
  upstream versions. Prefer `method=binary` when reproducible pinning is
  required.

## Git Credential Helper (`setup_git`)

`setup_git=true` runs `gh auth setup-git --force --hostname <git_hostname>` for
each resolved user during installation. `--force` is required because there is
no active `gh` login at container-build time.

This writes a credential-helper entry to the user's `~/.gitconfig`, roughly:

```gitconfig
[credential "https://github.com"]
    helper =
    helper = !gh auth git-credential
```

The empty first `helper =` line resets any inherited credential-helper chain;
the second line routes authentication through `gh`. Subsequent `git push/pull`
operations then authenticate via `gh auth git-credential`, which reads the
`GH_TOKEN` environment variable or a token stored by `gh auth login` — no
separate credential store is needed. For GitHub Enterprise Server, set
`git_hostname` to your GHES hostname so the entry targets the right host.

## Commit Signing (`sign_commits`)

`sign_commits` pre-configures commit signing but deliberately **does not set
`user.signingkey`** — the key identifier is user-specific and unknown at build
time. Each user must set it themselves (e.g. via dotfiles). For SSH signing,
commits show as **Verified** on GitHub only once the corresponding public key is
registered under *Settings → SSH and GPG keys → New SSH signing key*.

SSH signing (`sign_commits=ssh`) is the simplest option in containers: it is
silent and needs no TTY or pinentry, but the SSH agent must be forwarded into
the container. `forwardAgent` is **not** a valid `devcontainer.json` property;
forward the agent with `runArgs` and `remoteEnv` instead:

```jsonc
// macOS / Docker Desktop
"runArgs": ["--volume=/run/host-services/ssh-auth.sock:/run/host-services/ssh-auth.sock:ro"],
"remoteEnv": { "SSH_AUTH_SOCK": "/run/host-services/ssh-auth.sock" }
// Linux — substitute your host's $SSH_AUTH_SOCK path
```

GPG signing (`sign_commits=gpg`) requires a running `gpg-agent`; forwarding its
socket into a container needs additional host setup beyond the devcontainer
spec, which is why SSH signing is usually preferable in container environments.

## Extensions

Extensions listed in `extensions` are installed per-user by running
`gh extension install <entry>` as each resolved user. Installing public
extensions from GitHub repositories does **not** require a GitHub login, but it
does require network access to `github.com` at install time. An extension that
fails to install is logged as a warning and does not abort the feature (gh
itself is still installed successfully).

## User Configuration

Per-user configuration (`git_protocol`, `setup_git`, `sign_commits`) and
extension installation apply to the **same** resolved set of users. That set is
built from `add_current_user`, `add_remote_user`, `add_container_user`, and
`add_users`; duplicates are removed, and root is dropped automatically whenever
any non-root user is present. To target one specific user only, disable the
three auto-detected users and name the user explicitly:

```jsonc
"add_current_user": false,
"add_remote_user": false,
"add_container_user": false,
"add_users": "alice"
```

None of these steps run unless at least one of `extensions`, `git_protocol`,
`setup_git`, or `sign_commits` is active.

## Security

- **`method=binary`** verifies the downloaded archive's SHA-256 digest against
  the `gh_<version>_checksums.txt` file published alongside each release; a
  mismatch aborts the install.
- **`method=upstream-package`** installs from GPG-signed official repositories:
  the `apt` method places the keyring at `/etc/apt/keyrings/`, and the `rpm`
  methods import the GitHub CLI signing key (`0x23F3D4EA75716059`) from
  `keyserver.ubuntu.com`.

## Troubleshooting

- **Exact version not honoured on Alpine/Arch:** the `apk`/`pacman` packages
  cannot be pinned to an arbitrary upstream version — use `method=binary`.
- **Keyring download fails on Debian/Ubuntu:** if fetching
  `cli.github.com/packages/githubcli-archive-keyring.gpg` is blocked, use
  `method=binary` instead.
- **Extension install fails:** ensure the container has network access to
  `github.com` at install time.
- **Commits not showing as Verified with `sign_commits=ssh`:** set the user's
  `user.signingkey` (pointing at a `.pub` file, e.g. `~/.ssh/id_ed25519.pub`)
  and register that public key as an SSH signing key on GitHub.
- **`sign_commits=gpg` with no gpg-agent:** GPG signing needs a running,
  reachable `gpg-agent`; in containers this usually means forwarding the agent
  socket from the host.
