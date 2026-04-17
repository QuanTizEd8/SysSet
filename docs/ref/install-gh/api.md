## Usage Examples

### Basic Installation (Latest)

Install the latest GitHub CLI release using the official package repository (default behavior).

```jsonc
"features": {
  "ghcr.io/quantized8/sysset/install-gh:0": {}
}
```

Standalone installer:
```bash
curl -fsSL https://sysset.quantized8.dev/get.sh | bash -s -- install-gh
```

---

### Pin to a Specific Version (Binary method)

Install an exact version of gh using the binary download method, for reproducible container builds.

```jsonc
"features": {
  "ghcr.io/quantized8/sysset/install-gh:0": {
    "version": "2.89.0",
    "method": "binary"
  }
}
```

Standalone installer:
```bash
curl -fsSL https://sysset.quantized8.dev/get.sh | bash -s -- install-gh \
  --version 2.89.0 --method binary
```

---

### Pin to a Specific Version (apt Repo method)

Install an exact version via apt (Debian/Ubuntu only; not supported on Alpine/Arch).

```jsonc
"features": {
  "ghcr.io/quantized8/sysset/install-gh:0": {
    "version": "2.89.0",
    "method": "repos"
  }
}
```

---

### Custom Binary Install Path

Install the binary to a non-default location (e.g. a user-writable `~/.local`).

```jsonc
"features": {
  "ghcr.io/quantized8/sysset/install-gh:0": {
    "method": "binary",
    "prefix": "/home/vscode/.local"
  }
}
```

---

### Install with Extensions

Install the GitHub CLI and one or more extensions. By default extensions are installed for the devcontainer `remoteUser` and `containerUser`. To limit to a specific user only, disable the auto-resolved users and list explicitly.

```jsonc
"features": {
  "ghcr.io/quantized8/sysset/install-gh:0": {
    "extensions": "dlvhdr/gh-dash,github/gh-copilot"
  }
}
```

Install extensions for one specific user only:
```jsonc
"features": {
  "ghcr.io/quantized8/sysset/install-gh:0": {
    "extensions": "dlvhdr/gh-dash,github/gh-copilot",
    "add_current_user": false,
    "add_remote_user": false,
    "add_container_user": false,
    "add_users": "alice"
  }
}
```

---

### Skip if Already Present (default) vs Fail if Already Present

Default behavior — silently skip if gh is already installed:
```jsonc
"features": {
  "ghcr.io/quantized8/sysset/install-gh:0": {
    "if_exists": "skip"
  }
}
```

Fail loudly if gh is already present (useful to enforce a clean baseline):
```jsonc
"features": {
  "ghcr.io/quantized8/sysset/install-gh:0": {
    "if_exists": "fail"
  }
}
```

---

### Configure Git Credential Helper

Register `gh` as the git credential helper so that `git push/pull` authenticates via the gh token without prompting. Useful in CI environments or devcontainers where `GH_TOKEN` is set as a secret.

```jsonc
"features": {
  "ghcr.io/quantized8/sysset/install-gh:0": {
    "setup_git": true
  }
}
```

For GitHub Enterprise Server:
```jsonc
"features": {
  "ghcr.io/quantized8/sysset/install-gh:0": {
    "setup_git": true,
    "git_hostname": "git.corp.example.com"
  }
}
```

---

### Configure git Protocol and SSH Commit Signing

Set the default git protocol to SSH and enable SSH-based commit signing (requires the user to set `user.signingkey` pointing to their public key, e.g. via dotfiles).

```jsonc
"features": {
  "ghcr.io/quantized8/sysset/install-gh:0": {
    "git_protocol": "ssh",
    "sign_commits": "ssh"
  }
}
```

For GPG signing instead:
```jsonc
"features": {
  "ghcr.io/quantized8/sysset/install-gh:0": {
    "sign_commits": "gpg"
  }
}
```

---

### Custom Binary Install Path

Install the binary to a non-default location with a symlink at `/usr/local/bin/gh` for PATH compatibility.

```jsonc
"features": {
  "ghcr.io/quantized8/sysset/install-gh:0": {
    "method": "binary",
    "prefix": "/opt/gh",
    "symlink": true
  }
}
```

---

### Keep Installer Artifacts for Debugging

```jsonc
"features": {
  "ghcr.io/quantized8/sysset/install-gh:0": {
    "method": "binary",
    "keep_installer": true,
    "installer_dir": "/tmp/gh-debug"
  }
}
```

---

## Details

### `method=repos` Behavior by Platform

| Platform | Package manager | Package name | Source | Version pinning |
|---|---|---|---|---|
| Debian / Ubuntu | `apt` | `gh` | Official GitHub CLI apt repo | `gh=<version>` via apt |
| RHEL / Fedora / CentOS | `dnf` or `yum` | `gh` | Official GitHub CLI rpm repo | Not supported by this feature (use `method=binary`) |
| SUSE / openSUSE | `zypper` | `gh` | Official GitHub CLI rpm repo | Not supported by this feature (use `method=binary`) |
| Alpine Linux | `apk` | `github-cli` | Community (Alpine aports) | Not supported by apk |
| Arch Linux | `pacman` | `github-cli` | Community (Arch extra repo) | Not supported by pacman |
| macOS | `brew` | `gh` | Official Homebrew formula | Not available via formula |

**Note on Alpine and Arch:** The packages on these distros are community-maintained and not officially supported by the GitHub CLI team. Version pinning is not possible with `apk` or `pacman`. When `version` is set to a specific value other than `latest` on Alpine or Arch, the feature logs a warning and installs the latest available community package.

**Note on RHEL/SUSE version pinning:** The official GitHub CLI rpm docs only document un-versioned `dnf install gh`. If you need an exact version on RHEL, use `method=binary`.

### `method=binary` Architecture Mapping

The feature maps `uname -m` output to the GitHub Release asset architecture name:

| `uname -m` | Asset arch |
|---|---|
| `x86_64` | `amd64` |
| `aarch64`, `arm64` | `arm64` |
| `i386`, `i686` | `386` |
| `armv6l`, `armv7l` | `armv6` |

macOS binaries use `macOS` (mixed-case) in the asset filename — not `darwin`.

### `method=binary` Static Linking (Alpine Compatibility)

The GitHub CLI Linux release binaries are built with `CGO_ENABLED=0` ([confirmed in `.goreleaser.yml`](https://github.com/cli/cli/blob/trunk/.goreleaser.yml)), producing fully static Go executables. They run on any Linux distribution, including Alpine/musl, without any glibc compatibility shim. No special handling is required on Alpine.

### SHA-256 Checksum Verification

For `method=binary`, the installer downloads `gh_<version>_checksums.txt` alongside the archive and verifies the SHA-256 digest before installation. If the checksum does not match, the installer exits non-zero.

### Shell Completions (`shell_completions`)

When `shell_completions` is non-empty (default: `"bash zsh"`), shell completions are installed for the listed shells:

- **`method=binary`:** Completion files are read from the release archive (`share/bash-completion/completions/gh` and `share/zsh/site-functions/_gh`), which are bundled in every GitHub Releases archive.
- **`method=repos`:** Completions are generated on the fly via `gh completion -s bash` and `gh completion -s zsh`. This is necessary for Alpine and Arch, where the community package may not install completions, and ensures they land in the feature-controlled paths on all platforms.

Installation paths:
- **As root:** Bash → `/etc/bash_completion.d/gh`; Zsh → `<zshdir>/completions/_gh` (where `<zshdir>` is detected by `shell__detect_zshdir`)
- **As non-root:** Bash → `$HOME/.local/share/bash-completion/completions/gh`; Zsh → `$HOME/.zfunc/_gh`

### Extensions

Extensions require the `gh` CLI binary to be installed and accessible. They are installed per-user by running `gh extension install <extension>` as each target user. This does **not** require GitHub authentication when installing public extensions from GitHub repositories.

The users who receive extensions are resolved from the four `add_*_user_config` / `add_users` options via `users__resolve_list`, which auto-deduplicates and excludes root when non-root users are also targeted. The same user set also receives any per-user configuration from `git_protocol`, `setup_git`, and `sign_commits`.

### `setup_git` and `git_hostname`

`setup_git=true` runs `gh auth setup-git --force --hostname <git_hostname>` for each resolved user at container build time. `--force` is required because there is no active `gh` login during the feature install step. This writes two entries to `~/.gitconfig`:

```gitconfig
[credential "https://github.com"]
    helper =
    helper = !gh auth git-credential
```

The empty first `helper =` line severs any pre-existing credential helper chain. Subsequent `git push/pull` operations authenticate via `gh auth git-credential`, which reads the `GH_TOKEN` environment variable or a stored token from `gh auth login`.

For GitHub Enterprise Server, set `git_hostname` to your GHES hostname (e.g. `git.corp.example.com`).

### `sign_commits`

`sign_commits` pre-configures commit signing in each resolved user's `~/.gitconfig`:

| Value | git config written | Notes |
|---|---|---|
| `"ssh"` | `gpg.format = ssh`, `commit.gpgsign = true` | Requires git ≥ 2.34. Best for devcontainers: silent, no TTY/pinentry. Requires SSH agent forwarding via `runArgs`/`remoteEnv`. |
| `"gpg"` | `commit.gpgsign = true` (gpg.format unset → git default GPG) | Requires gpg-agent; socket forwarding into containers needs extra host setup. |
| `""` | (nothing written) | Default. |

**`user.signingkey` is intentionally not set** by this feature — the key identifier is user-specific and unknown at build time. Users must set it themselves (e.g. via dotfiles).

For SSH signing to show commits as **Verified** on GitHub, the user's public key must be added to [GitHub Settings → SSH and GPG keys → New SSH signing key](https://github.com/settings/keys).

**SSH agent forwarding:** `forwardAgent` is not a valid `devcontainer.json` property. To forward the SSH agent into the container, use `runArgs` and `remoteEnv`:

```jsonc
// macOS / Docker Desktop
"runArgs": ["--volume=/run/host-services/ssh-auth.sock:/run/host-services/ssh-auth.sock:ro"],
"remoteEnv": { "SSH_AUTH_SOCK": "/run/host-services/ssh-auth.sock" }

// Linux — substitute your host $SSH_AUTH_SOCK path, e.g. via a Docker Compose file
```

### Security Considerations

- `method=repos`: Uses GPG-signed package metadata for Debian/Ubuntu and RHEL/Fedora. The apt keyring is downloaded and placed in `/etc/apt/keyrings/` (modern, non-deprecated approach). The GPG fingerprints published by the GitHub CLI team are `2C6106201985B60E6C7AC87323F3D4EA75716059` and `7F38BBB59D064DBCB3D84D725612B36462313325`.
- `method=binary`: Verifies SHA-256 of the downloaded archive against the `checksums.txt` file published with each release. Both the archive and checksums file are fetched from the same `github.com/cli/cli/releases/download/...` base URL over HTTPS.

### Troubleshooting

- **`gh` not found after install with `method=binary`:** Ensure `$prefix/bin` is on `$PATH`. The `containerEnv.PATH` entry in the feature adds `/usr/local/bin` automatically; if using a custom `prefix`, either use `/usr/local` (default) or enable `symlink=true` so `/usr/local/bin/gh` points to the binary.
- **Version not found with `method=repos` on Alpine/Arch:** Version pinning is not supported via `apk`/`pacman`. Use `method=binary` for an exact version on these platforms.
- **GPG key issues on Debian/Ubuntu:** If the apt keyring download (`cli.github.com/packages/githubcli-archive-keyring.gpg`) fails due to network restrictions, use `method=binary` instead.
- **Extension install fails:** `gh extension install` requires network access to `github.com`. Ensure the container has internet access at feature install time.
- **Commits not showing as Verified with `sign_commits=ssh`:** Ensure the user's `user.signingkey` is set (pointing to a `.pub` file, e.g. `~/.ssh/id_ed25519.pub`) and the corresponding public key is registered as an SSH signing key on GitHub.
- **`sign_commits=gpg` with no gpg-agent:** GPG signing requires `gpg-agent` to be running and accessible. In containers this typically requires socket forwarding from the host — significantly more setup than SSH signing.
