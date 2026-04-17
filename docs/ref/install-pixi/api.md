## Devcontainer Integration

### `containerEnv`

The feature sets `PATH=/usr/local/bin:${PATH}` in `containerEnv`.
This ensures the devcontainer runtime always has `/usr/local/bin` on `PATH` — the
location where the pixi binary is installed by default (root) and where the `symlink`
option places the symlink when a custom `prefix` is used.

---

### `.pixi` Volume Mount

The feature automatically adds a named Docker volume mount for the `.pixi` directory:

```jsonc
// Added automatically — no configuration required:
"mounts": [
  {
    "source": "${localWorkspaceFolderBasename}-pixi",
    "target": "${containerWorkspaceFolder}/.pixi",
    "type": "volume"
  }
]
```

This is a **correctness requirement**, not just a persistence convenience: certain
conda packages contain files whose names differ only in case. On macOS and Windows
hosts, the workspace bind-mount is on a case-insensitive filesystem, which causes
those files to silently overwrite each other. The named volume is always on a
Linux (ext4) case-sensitive filesystem.

The volume is named `<workspace-basename>-pixi` (e.g. `myproject-pixi`) and
persists across container rebuilds — packages do not need to be re-downloaded
each time.

---

## Usage Examples

### Basic Installation (devcontainer)

Install the latest pixi to `/usr/local/bin` (already on PATH in all devcontainer base images):

```jsonc
// .devcontainer/devcontainer.json
{
  "features": {
    "ghcr.io/quantized8/sysset/install-pixi:1": {}
  }
}
```

Standalone equivalent:
```bash
curl -fsSL https://github.com/quantized8/sysset/releases/latest/download/install-pixi.tar.gz | tar -xz
bash install-pixi/install.sh
```

---

### Pin to a Specific Version

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-pixi:1": {
      "version": "0.67.0"
    }
  }
}
```

Standalone:
```bash
bash install-pixi/install.sh --version 0.67.0
```

---

### Custom Binary Directory with PATH Export

Install to `/opt/pixi` (requires root) and write a PATH export to all system-wide shell startup files:

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-pixi:1": {
      "prefix": "/opt/pixi",
      "export_path": "auto"
    }
  }
}
```

Standalone:
```bash
bash install-pixi/install.sh --prefix /opt/pixi --export_path auto
```

---

### `.pixi` Volume Mount and `postCreateCommand`

The feature automatically mounts a named volume at `${containerWorkspaceFolder}/.pixi`.
Because the feature installer runs as `root`, the mount is initially root-owned.
If your devcontainer runs as a non-root user (e.g. `vscode`), add a `postCreateCommand`
to fix ownership and optionally auto-install environments:

```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/quantized8/sysset/install-pixi:1": {}
  },
  "remoteUser": "vscode",
  "postCreateCommand": "sudo chown vscode ${containerWorkspaceFolder}/.pixi && pixi install"
}
```

Omit `&& pixi install` if your project has no `pixi.toml`, or if you prefer to run it manually.

---

### Persistent `PIXI_HOME` Across Rebuilds

Set `home_dir` to a stable path (e.g. a volume-backed directory) so global pixi environments survive container rebuilds:

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-pixi:1": {
      "home_dir": "/var/pixi"
    }
  }
}
```

Note: `PIXI_HOME` is read by pixi on every invocation, so it must be exported to the runtime environment to take effect. Set `export_pixi_home` to `"auto"` (the default) to have the installer write `export PIXI_HOME="/var/pixi"` to shell startup files. This ensures it is active in all future shell sessions inside the container.

---

### Shell Completion (`shell_completions`)

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-pixi:1": {
      "shell_completions": "bash zsh"
    }
  }
}
```

Standalone:
```bash
bash install-pixi/install.sh --shell_completions "bash zsh"
```

This writes the following idempotent block to each listed shell's config file:

```zsh
# >>> pixi completion >>>
eval "$(pixi completion --shell zsh)"
# <<< pixi completion <<<
```

---

### Air-Gapped / Mirror Installation

Use `download_url` to point directly to an internal mirror. Checksum verification is skipped (use a trusted mirror):

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-pixi:1": {
      "download_url": "https://mirror.internal/pixi/pixi-x86_64-unknown-linux-musl.tar.gz"
    }
  }
}
```

For authenticated mirrors, provide a `.netrc` file:

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-pixi:1": {
      "download_url": "https://mirror.internal/pixi/pixi-x86_64-unknown-linux-musl.tar.gz",
      "netrc": "/run/secrets/netrc"
    }
  }
}
```

---

### Update Pixi on Rebuild

If pixi is already installed in the image and you want to upgrade it on each rebuild:

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-pixi:1": {
      "version": "latest",
      "if_exists": "update"
    }
  }
}
```

---

### Preserve Downloaded Archive

Keep the `.tar.gz` and `.tar.gz.sha256` sidecar in `installer_dir` after installation (useful for caching layers):

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-pixi:1": {
      "installer_dir": "/tmp/pixi-installer",
      "keep_installer": true
    }
  }
}
```

---

## Details

### `version` — Resolution Logic

1. If `version` is `"latest"`, the installer fetches the most recent tag from the GitHub Releases API (`prefix-dev/pixi`). This requires outbound HTTPS access to `api.github.com`.
2. If `version` is a string like `"0.67.0"` or `"v0.67.0"`, the `v` prefix is stripped and the version is used as-is.
3. Before downloading, the installer checks whether an existing pixi binary reports the same version. If it does, the install is **always skipped silently** regardless of `if_exists`.

### `prefix` — Empty String Behavior

When `prefix` is set to `""`, the binary is installed to `$HOME/.pixi/bin` (prefix resolves to `$HOME/.pixi`) — the same default used by the official upstream installer. This is appropriate for non-root user installs. In this case, `export_path="auto"` will write the PATH export to user-scoped shell files (`~/.bash_profile`, `~/.bashrc`, `~/.zshenv`).

When `prefix` is a system path (e.g. `/usr/local`, `/opt/pixi`, `/usr`), the installer requires root privileges.

### `if_exists` — `"update"` Caveats

- `"update"` runs `pixi self-update --version <resolved_version>`.
- This **only works for installer-managed pixi**. pixi installed via Homebrew or conda/mamba cannot self-update and will fail.
- `version` is always resolved to a concrete semver string before the update path is taken (even when `version="latest"`), so `--version` is always passed to `pixi self-update`. To always track the latest release, use `version="latest"` together with `if_exists="update"` — the resolved version is fetched from the GitHub API at install time.

### `export_path` — Scope Rules

| Condition | Files written |
|---|---|
| `"auto"` + root + system path | System-wide: `$BASH_ENV`, `/etc/profile.d/pixi_bin_path.sh`, global bashrc, global zshenv |
| `"auto"` + non-root OR user path | User-scoped: `~/.bash_profile`, `~/.bashrc`, `~/.zshenv` |
| `""` (empty) | No writes |
| Newline-separated list | Only those files |

For the default `prefix="/usr/local"` in devcontainer images, `/usr/local/bin` is already on `PATH` via the image's `/etc/environment` or `/etc/profile`, so `export_path=""` or `export_path="auto"` both work. Setting `export_path=""` is a safe micro-optimization.

### `shell_completions` — Supported Shells

| shell name | Completion file target (root) | Completion file target (non-root) |
|---|---|---|
| `bash` | global bashrc | `~/.bashrc` |
| `zsh` | global zshenv | `~/.zshenv` |
| `fish` | `~/.config/fish/config.fish` | `~/.config/fish/config.fish` |
| `nushell` | `~/.config/nushell/config.nu` | `~/.config/nushell/config.nu` |
| `elvish` | `~/.config/elvish/rc.elv` | `~/.config/elvish/rc.elv` |

For fish, nushell, and elvish, the installer writes to the user config directory regardless of whether the script runs as root, since those shells don't have a well-defined system-wide config location on all distros.

### `netrc` — Authentication

The `netrc` option is only used when downloading the pixi binary (or when a `download_url` is provided). It is passed as `--netrc-file <path>` to curl (or `--auth-no-challenge` equivalent for wget). It does **not** affect the GitHub Releases API call used for version resolution.

### macOS Specifics

On macOS, the installer downloads the `aarch64-apple-darwin` triple for Apple Silicon (`arm64`) and `x86_64-apple-darwin` for Intel. The detected architecture maps `arm64` → `aarch64` automatically.

The RISC-V (`riscv64`) triple uses GNU libc (`riscv64gc-unknown-linux-gnu`), not musl.

### `PIXI_HOME` — Runtime Configuration

`PIXI_HOME` is a **runtime** environment variable — pixi reads it on every invocation to locate global environments and configuration. Setting `home_dir` without also exporting `PIXI_HOME` to the runtime environment means the custom location is silently ignored after installation.

By default, `export_pixi_home="auto"` causes the installer to write `export PIXI_HOME="<home_dir>"` to the appropriate shell startup files (system-wide for root, user-scoped for non-root). This ensures all subsequent shell sessions inside the container see the correct value.

Set `export_pixi_home=""` only if you have another mechanism to set `PIXI_HOME` at runtime (e.g. an upstream image layer or a manually configured `containerEnv` block).
