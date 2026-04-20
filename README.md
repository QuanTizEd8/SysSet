<div align="center">

# SysSet

**Declarative system setup — as devcontainer features or standalone installers**

[![CI](https://github.com/quantized8/sysset/actions/workflows/test.yaml/badge.svg)](https://github.com/quantized8/sysset/actions/workflows/test.yaml)
[![Lint](https://github.com/quantized8/sysset/actions/workflows/lint.yaml/badge.svg)](https://github.com/quantized8/sysset/actions/workflows/lint.yaml)
[![License](https://img.shields.io/github/license/quantized8/sysset)](LICENSE)

</div>

SysSet is a collection of idempotent shell installers that configure Linux and macOS environments.
Every feature ships as both a **[Dev Container feature](https://containers.dev/features)** (published to GHCR) and a **self-contained tarball** you can run on any machine directly.

---

## Features

| Feature | Description |
|---|---|
| [`setup-user`](#setup-user) | Create / configure a user account with sudo |
| [`install-homebrew`](#install-homebrew) | Homebrew on macOS and Linux |
| [`install-os-pkg`](#install-os-pkg) | OS package manager with a YAML manifest |
| [`install-shell`](#install-shell) | Zsh/Bash · Oh My Zsh · Oh My Bash · Starship |
| [`install-miniforge`](#install-miniforge) | Miniforge (conda/mamba) |
| [`install-conda-env`](#install-conda-env) | Conda environments from YAML or inline specs |
| [`install-pixi`](#install-pixi) | Pixi package manager |
| [`install-podman`](#install-podman) | Rootless Podman with user-namespace config |
| [`install-fonts`](#install-fonts) | Nerd Fonts, P10k fonts, arbitrary URLs |
| [`setup-shim`](#setup-shim) | `code`, `devcontainer-info`, `systemctl` shims |

---

## Quick Start

### As Dev Container features

Add any feature to `.devcontainer/devcontainer.json`:

```jsonc
{
  "image": "ubuntu:24.04",
  "features": {
    "ghcr.io/quantized8/sysset/setup-user:0": {
      "username": "dev"
    },
    "ghcr.io/quantized8/sysset/install-shell:0": {
      "ohmyzsh_theme": "romkatv/powerlevel10k",
      "set_user_shells": "zsh"
    },
    "ghcr.io/quantized8/sysset/install-pixi:0": {}
  }
}
```

### As standalone installers — single feature

Download and run any feature in one line (requires `curl` or `wget`):

```sh
# Install a specific feature from the latest release
curl -fsSL https://github.com/quantized8/sysset/releases/latest/download/get.sh | \
  sh -s -- install-pixi --version 0.66.0

# Pin to a specific release
curl -fsSL https://github.com/quantized8/sysset/releases/latest/download/get.sh | \
  sh -s -- install-pixi --tag v1.0.0 --version 0.66.0
```

Or download the tarball and run offline:

```sh
curl -fsSL https://github.com/quantized8/sysset/releases/latest/download/sysset-install-pixi.tar.gz \
  | tar xz -C /tmp/sysset-pixi
bash /tmp/sysset-pixi/install.sh --version 0.66.0
```

### As standalone installers — manifest-driven

Download the all-in-one bundle and drive multiple features from a single manifest:

```sh
curl -fsSL https://github.com/quantized8/sysset/releases/latest/download/sysset-all.tar.gz \
  | tar xz -C /opt/sysset
sudo bash /opt/sysset/scripts/sysset.sh my-setup.json
```

**`my-setup.json`:**

```jsonc
{
  "features": [
    { "id": "setup-user",       "options": { "username": "dev" } },
    { "id": "install-shell",    "options": { "ohmyzsh_theme": "romkatv/powerlevel10k", "set_user_shells": "zsh" } },
    { "id": "install-miniforge","options": { "version": "latest" } },
    { "id": "install-pixi",     "options": { "version": "0.66.0" } }
  ]
}
```

Features are always installed in a safe [canonical order](#canonical-install-order) regardless of how they appear in the manifest.

---

## Feature Reference

### `setup-user`

Create and configure a system user with optional sudo access.

```jsonc
"ghcr.io/quantized8/sysset/setup-user:0": {
  "username": "dev",           // default: "vscode"
  "user_id": "1000",           // default: "1000"
  "group_id": "1000",          // default: "1000"
  "home_dir": "",              // default: /home/<username>
  "user_shell": "/bin/bash",   // default: /bin/bash
  "sudo_access": true,         // default: true — passwordless sudo
  "extra_groups": "",          // comma-separated supplementary groups
  "replace_existing": true     // remove conflicting UID/GID first
}
```

---

### `install-homebrew`

Install [Homebrew](https://brew.sh/) on macOS and Linux. Handles Xcode CLT on macOS and build dependencies on Linux. Exports `brew shellenv` to the appropriate shell startup files.

```jsonc
"ghcr.io/quantized8/sysset/install-homebrew:0": {
  "install_user": "",          // defaults to SUDO_USER or first non-system user
  "prefix": "",                // default: platform auto-detect (/opt/homebrew, /usr/local, /home/linuxbrew/.linuxbrew)
  "if_exists": "skip",         // "skip" | "fail" | "reinstall"
  "update": true,              // run brew update after install
  "export_path": "auto",       // "auto" | "" (skip) | newline-separated file paths
  "users": "",                 // extra users to receive brew shellenv
  "brew_git_remote": "",       // override for air-gapped mirrors
  "core_git_remote": "",       // override for air-gapped mirrors
  "no_install_from_api": false // force full homebrew-core clone
}
```

---

### `install-os-pkg`

Cross-distro package installer (`apt`, `dnf`, `zypper`, `pacman`, `apk`, `brew`) driven by a YAML manifest format with per-distro selectors, repo configuration, key import, and pre/post scripts.

```jsonc
"ghcr.io/quantized8/sysset/install-os-pkg:0": {
  "manifest": "dependencies/base.yaml", // file path or inline content
  "lifecycle_hook": "",                  // "" | "onCreate" | "updateContent" | "postCreate"
  "skip_installed": false,             // skip packages already in PATH
  "update": true,                       // run apt-get update / dnf check-update
  "lists_max_age": "300",               // seconds before forcing a package list refresh
  "keep_cache": false,                    // keep package manager cache
  "keep_repos": false,                  // keep added repo files
  "dry_run": false,                     // print without installing
  "install_self": true                  // write /usr/local/bin/install-os-pkg wrapper
}
```

**Manifest format** (`dependencies/base.yaml`):

```yaml
packages:
  - git
  - curl
  - wget

apt:
  packages:
    - build-essential
    - libssl-dev
  repos:
    - "deb [signed-by=/etc/apt/keyrings/my.gpg] https://example.com/repo stable main"
  keys:
    - url: https://example.com/key.asc
      dest: /etc/apt/keyrings/my.gpg

dnf:
  packages:
    - gcc
    - openssl-devel
  when: {id: [fedora, rhel]}

scripts:
  - echo "Post-install script"
```

PM-specific blocks (`apt`, `dnf`, `apk`, `brew`, `pacman`, `zypper`) scope packages, repos, keys, and scripts to a single package manager. `when` clauses filter on `/etc/os-release` fields plus synthetic `pm` and `arch`.

---

### `install-shell`

Install Bash and Zsh with [Oh My Zsh](https://ohmyz.sh/), [Oh My Bash](https://ohmybash.nntoan.com/), and [Starship](https://starship.rs/). Deploys layered system-wide and per-user config files that work across all shell invocation modes.

```jsonc
"ghcr.io/quantized8/sysset/install-shell:0": {
  "install_zsh": true,
  "install_ohmyzsh": true,
  "install_ohmybash": true,
  "install_starship": true,
  "starship_shells": "zsh",         // "zsh" | "bash" | "zsh,bash" | ""
  "ohmyzsh_plugins": "git,zsh-users/zsh-syntax-highlighting",
  "ohmyzsh_theme": "",              // e.g. "romkatv/powerlevel10k"
  "ohmybash_plugins": "git",
  "ohmybash_theme": "",
  "ohmyzsh_install_dir": "/usr/local/share/oh-my-zsh",
  "ohmybash_install_dir": "/usr/local/share/oh-my-bash",
  "zdotdir": "",                    // default: ~/.config/zsh
  "ohmyzsh_custom_dir": "",         // default: $ZDOTDIR/custom
  "set_user_shells": "zsh",         // "zsh" | "bash" | "none"
  "add_current_user": true,
  "add_remote_user": true,
  "add_container_user": true,
  "add_users": "",            // extra comma-separated usernames
  "user_config_mode": "overwrite"   // "overwrite" | "augment" | "skip"
}
```

**Powerlevel10k example:**

```jsonc
"ghcr.io/quantized8/sysset/install-shell:0": {
  "ohmyzsh_theme": "romkatv/powerlevel10k",
  "ohmyzsh_plugins": "zsh-users/zsh-syntax-highlighting,zsh-users/zsh-autosuggestions",
  "set_user_shells": "zsh"
}
```

Don't forget [`install-fonts`](#install-fonts) → `"p10k_fonts": true` for the matching Nerd Font glyphs.

---

### `install-miniforge`

Install [Miniforge](https://github.com/conda-forge/miniforge) (conda/mamba) with full control over version, installation path, user permissions, and shell activation.

```jsonc
"ghcr.io/quantized8/sysset/install-miniforge:0": {
  "version": "latest",          // conda version string, e.g. "24.7.1"
  "bin_dir": "/opt/conda",
  "if_exists": "skip",          // "skip" | "fail" | "reinstall" | "update"
  "preserve_envs": true,        // export/recreate envs when if_exists=reinstall
  "preserve_config": true,      // keep .condarc on reinstall
  "export_path": "auto",
  "symlink": true,              // create /opt/conda symlink when bin_dir differs
  "activate_env": "base",       // env to activate in rc_files
  "rc_files": "",               // shell files to append conda activation to
  "set_permissions": false,     // create conda group and set group ownership
  "group": "conda",
  "users": ""                   // users to add to the conda group
}
```

---

### `install-conda-env`

Create or update conda/mamba environments from YAML files, directory scans, or inline package lists.

```jsonc
"ghcr.io/quantized8/sysset/install-conda-env:0": {
  "env_files": "environment.yml :: ml/environment.yml",  // ' :: '-separated paths
  "env_dirs": "",                                          // scan dirs for *.yml
  "env_name": "",                                          // inline env name
  "packages": "",                                          // space-separated pkgs
  "python_version": "",                                    // e.g. "3.11"
  "channels": "conda-forge :: pytorch",
  "strict_channel_priority": false,
  "solver": "auto",                                        // "auto" | "mamba" | "conda"
  "pip_requirements_files": "requirements.txt",
  "pip_env": "",
  "post_env_script": "",                                   // called with env name
  "keep_cache": false
}
```

---

### `install-pixi`

Install the [Pixi](https://pixi.sh/) package manager binary.

```jsonc
"ghcr.io/quantized8/sysset/install-pixi:0": {
  "version": "0.66.0",           // Pixi release version
  "install_path": "/usr/local/bin"
}
```

The feature mounts a named volume at `.pixi` so the Pixi environment cache survives container rebuilds.

---

### `install-podman`

Install [rootless Podman](https://podman.io/) for running OCI containers inside a devcontainer. Uses native overlay storage on a named volume for fast copy-on-write.

```jsonc
"ghcr.io/quantized8/sysset/install-podman:0": {
  "add_current_user": true,   // configure subuid/subgid for current user
  "add_remote_user": true,    // configure for devcontainer remoteUser
  "add_container_user": true, // configure for devcontainer containerUser
  "add_users": ""              // extra comma-separated usernames
}
```

> **Note**: Requires `"privileged": true` in `devcontainer.json` (same as docker-in-docker). The feature sets this automatically.

---

### `install-fonts`

Install fonts from multiple sources: [Nerd Fonts](https://www.nerdfonts.com/) by name, direct URLs (files or archives), and GitHub release assets. Deduplicates by PostScript name to avoid re-installing existing fonts.

```jsonc
"ghcr.io/quantized8/sysset/install-fonts:0": {
  "nerd_fonts": "Meslo,JetBrainsMono",  // comma-separated Nerd Font archive names
  "font_urls": "",                        // comma-separated direct URLs (.ttf, .zip, …)
  "gh_release_fonts": "",                // comma-separated owner/repo[@tag] slugs
  "font_dir": "",                         // auto-detect: /usr/share/fonts or ~/Library/Fonts
  "p10k_fonts": false,                   // install 4 MesloLGS NF fonts from romkatv
  "overwrite": false                     // overwrite existing fonts by PostScript name
}
```

---

### `setup-shim`

Install lightweight shim scripts into `/usr/local/share/setup-shim/bin` (prepended to `PATH`) so the right tool is always invoked regardless of the host environment.

```jsonc
"ghcr.io/quantized8/sysset/setup-shim:0": {
  "code": true,                // delegates to code CLI / code-insiders
  "devcontainer-info": true,   // queries devcontainer image metadata
  "systemctl": true            // fallback message when systemd is absent
}
```

---

## Standalone Distribution

Every feature is also available as a self-contained tarball, with no Docker or devcontainer tooling required. Perfect for provisioning VMs, CI runners, WSL2, or physical machines.

### `get.sh` — single feature

```sh
# Usage
get.sh <feature> [--tag <release-tag>] [<feature-options>...]

# Examples
sh get.sh install-shell --set_user_shells zsh
sh get.sh install-pixi --version 0.66.0
sh get.sh install-fonts --nerd_fonts Meslo,FiraCode --p10k_fonts true
sh get.sh install-miniforge --version latest --bin_dir /opt/conda
```

`get.sh` is version-stamped at build time and always downloads from the same release it was bundled with. Use `--tag` to override.

### `sysset.sh` — manifest-driven

```sh
# Usage (from an extracted sysset-all.tar.gz)
sudo bash scripts/sysset.sh <manifest.json|.yaml> [OPTIONS]

Options:
  --tag <tag>       Override the release tag for all downloads
  --logfile <path>  Tee output to a file
  --debug           Enable set -x trace
```

**JSON manifest:**

```jsonc
{
  "tag": "v1.0.0",                   // optional — pin to a specific release
  "override_install_order": false,   // true to keep manifest order
  "features": [
    { "id": "setup-user",        "options": { "username": "dev" } },
    { "id": "install-homebrew",  "options": { "update": true } },
    { "id": "install-shell",     "options": { "ohmyzsh_theme": "romkatv/powerlevel10k", "set_user_shells": "zsh" } },
    { "id": "install-miniforge", "options": { "version": "latest" } },
    { "id": "install-pixi",      "options": { "version": "0.66.0" } },
    { "id": "install-fonts",     "options": { "nerd_fonts": "Meslo", "p10k_fonts": true } }
  ]
}
```

**YAML manifest** (requires `yq`; auto-installed):

```yaml
features:
  - id: setup-user
    options:
      username: dev
  - id: install-shell
    options:
      ohmyzsh_theme: romkatv/powerlevel10k
      set_user_shells: zsh
  - id: install-pixi
    options:
      version: "0.66.0"
```

### Canonical install order

Features are always installed in dependency-safe order unless `override_install_order: true`:

```
setup-user → install-homebrew → install-os-pkg → install-shell
→ install-miniforge → install-conda-env → install-pixi
→ install-podman → install-fonts → setup-shim
```

Unknown feature IDs (not in the list above) are appended at the end in manifest order.

### Offline / air-gapped use

Extract `sysset-all.tar.gz` — it contains all per-feature tarballs alongside `scripts/sysset.sh`. The orchestrator automatically prefers co-located tarballs over network downloads:

```sh
tar xzf sysset-all.tar.gz -C /opt/sysset
sudo bash /opt/sysset/scripts/sysset.sh my-setup.json  # fully offline
```

---

## Release Artifacts

Every release publishes to two registries simultaneously:

| Artifact | Location |
|---|---|
| Dev Container features | `ghcr.io/quantized8/sysset/<feature>:<version>` |
| `get.sh` | GitHub Releases → `get.sh` |
| Per-feature tarballs | GitHub Releases → `sysset-<feature>.tar.gz` |
| All-in-one bundle | GitHub Releases → `sysset-all.tar.gz` |

```sh
# Install from GHCR (devcontainer.json)
ghcr.io/quantized8/sysset/install-pixi:0

# Install standalone (latest release)
curl -fsSL https://github.com/quantized8/sysset/releases/latest/download/get.sh | \
  sh -s -- install-pixi --version 0.66.0
```

---

## Development

### Prerequisites

- Bash ≥ 4.0
- [shfmt](https://github.com/mvdan/sh) and [shellcheck](https://shellcheck.net/) (for linting)
- Docker (for feature integration tests)
- [devcontainer CLI](https://github.com/devcontainers/cli) (`npm install -g @devcontainers/cli`)
- [bats](https://github.com/bats-core/bats-core) (included as git submodule under `test/unit/bats/`)

### Common commands

```sh
# Regenerate lib/ copies in each feature (run after editing lib/ or bootstrap.sh)
bash sync-lib.sh

# Format all shell scripts
make format

# Lint all shell scripts
make lint

# Build standalone distribution artifacts
make build-dist                      # tag = "dev"
make build-dist VERSION=v1.0.0       # tag = "v1.0.0"

# Run a feature's integration tests (scenarios + fail cases)
bash test/run.sh feature install-pixi

# Run all bats unit tests
make test-unit

# Run unit tests for a single lib module
bash test/run-unit.sh --module ospkg
```

### Repository layout

```
src/<feature>/
  devcontainer-feature.json   Feature metadata and options
  install.bash                Main installer (bash ≥4.0)
  _lib/                       ← auto-generated; never edit directly
  dependencies/base.yaml      OS package manifest
  files/                      Static files copied into the container
  install.sh                  ← auto-generated bootstrap; never edit

lib/                          Shared bash library (canonical source)
  logging.sh  os.sh  ospkg.sh  net.sh  json.sh  git.sh  shell.sh  str.sh
  github.sh   checksum.sh  users.sh

build-artifacts.sh            Assembles all dist/ artifacts
get.sh                        Standalone single-feature installer (version-stamped)
sysset.sh                     Standalone manifest orchestrator (version-stamped)
sync-lib.sh                   Distributes lib/ into every feature
```

> Files under `src/*/install.sh` and `src/**/_lib/` are **auto-generated**.
> Edit `lib/` and run `bash sync-lib.sh` to propagate changes.

### Pre-commit hooks

[lefthook](https://github.com/evilmartians/lefthook) runs automatically on commit:

- **shellcheck** — lint all staged shell files
- **shfmt** — format check all staged shell files
- **sync-lib** — regenerate `_lib/` copies when `lib/` or `bootstrap.sh` change

---

## CI

| Workflow | Trigger | Purpose |
|---|---|---|
| `test.yaml` | Push/PR to `main` | Integration tests for changed features |
| `test-unit.yaml` | Push/PR touching `lib/**` | bats unit tests on `ubuntu-latest` + `macos-latest` |
| `lint.yaml` | Every push/PR | shfmt + shellcheck |
| `validate.yml` | PR | JSON schema validation of `devcontainer-feature.json` |
| `release.yaml` | Push `v*` tag / `workflow_dispatch` | Publish to GHCR + GitHub Releases |

---

## License

[MIT](LICENSE)
