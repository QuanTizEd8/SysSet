# OS Package Installer

Install packages from the operating system's native package manager using a
single, cross-distro manifest file.

Supports **APT** (Debian/Ubuntu), **APK** (Alpine), **DNF/YUM** (Fedora/RHEL/CentOS),
**microdnf**, **Zypper** (openSUSE), and **Pacman** (Arch Linux).

---

## Usage

### As a Dev Container feature

```jsonc
// .devcontainer/devcontainer.json
{
  "features": {
    "ghcr.io/quantized8/sysset/install-os-pkg:0": {
      "manifest": "/workspace/.devcontainer/packages.txt"
    }
  }
}
```

Inline manifests are also supported — the value is treated as inline content
when it contains a newline, and as a file path otherwise:

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-os-pkg:0": {
      "manifest": "git\ncurl\njq\n"
    }
  }
}
```

### As a standalone installer script

The script can be piped directly from the network or run from a local copy.
Pass the manifest as a file path or an inline string via `--manifest`. The
script must run as root.

```sh
# From a manifest file
curl -fsSL https://raw.githubusercontent.com/quantized8/sysset/main/src/install-os-pkg/install.sh \
  | sudo bash -s -- --manifest /path/to/packages.txt

# Inline manifest (trailing newline required for multi-line detection)
sudo bash install.sh --manifest $'git\ncurl\njq\n'
```

After the feature has been installed in a dev container (with `install_self`
left at its default `true`), a persistent wrapper is available at
`/usr/local/bin/install-os-pkg` and can be called directly by other features
or `postCreate` scripts:

```sh
install-os-pkg --manifest /workspace/.devcontainer/extra-packages.txt
```

---

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `manifest` | string | `""` | Inline manifest content or path to a manifest file. Required unless `install_self` is `true`. |
| `install_self` | boolean | `true` | Write the `install-os-pkg` wrapper to `/usr/local/bin` so other features and scripts can call it after build. Set to `false` to skip. |
| `lifecycle_hook` | string | `""` | Defer installation to a devcontainer lifecycle event (`onCreate`, `updateContent`, or `postCreate`). See [Lifecycle hook](#lifecycle-hook) below. |
| `debug` | boolean | `false` | Enable `set -x` trace output. |
| `interactive` | boolean | `false` | Allow interactive package manager prompts. Defaults to `DEBIAN_FRONTEND=noninteractive` for APT. |
| `keep_repos` | boolean | `false` | Keep any repository drop-in files written during the `repo` section after installation completes. |
| `logfile` | string | `""` | Mirror all output (stdout + stderr) to this file in addition to the console. |
| `no_clean` | boolean | `false` | Skip the package manager cache clean step after installation. |
| `no_update` | boolean | `false` | Skip the package list refresh (`apt-get update`, `apk update`, etc.) before installing. |

---

## Manifest format

A manifest is a plain-text file (or inline string) that tells the installer
what to do. It is divided into **sections** separated by header lines. The
implicit leading block — everything before the first header — is treated as a
`pkg` section.

### Section types

| Section | Purpose |
|---|---|
| `pkg` | Packages to install via the OS package manager. One package name per line. |
| `repo` | Repository configuration to add before installing. Written verbatim to the package manager's drop-in directory. |
| `prescript` | Shell script to run **before** repositories are added and packages are installed. |
| `script` | Shell script to run **after** packages are installed. |

### Section header syntax

```
--- <type> [selector [selector ...]]
```

A header with no selectors is always active. A header with one or more
selector blocks is only active when the selectors match the current
environment (see [Selectors](#selectors) below).

### Selectors

Selectors filter sections or individual package lines based on the current
OS environment. They use square-bracket syntax:

```
[key=val, key=val, ...]
```

Keys are matched against `/etc/os-release` fields (case-insensitive) plus two
synthetic keys:

| Key | Value |
|---|---|
| `pm` | Package manager prefix: `apt`, `apk`, `dnf`, `zypper`, `pacman` |
| `arch` | CPU architecture from `uname -m`, e.g. `x86_64`, `aarch64` |

**AND within a block** — all `key=val` pairs in a single block must match.

**OR across blocks** — multiple blocks on the same line pass if _any_ block
matches.

Selectors on a **section header** gate the entire section. Selectors on a
**package line** gate just that line (only applies to `pkg` sections).

### Full example

```
# Packages installed on every distro (implicit leading pkg section)
git
curl
jq

# APT-only packages
--- pkg [pm=apt]
build-essential
libssl-dev

# Alpine-only packages
--- pkg [pm=apk]
build-base
openssl-dev

# Add a third-party APT repository before installing anything
--- repo [pm=apt]
deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main

# Run a setup script before the repository is consumed (e.g. import the GPG key)
--- prescript [pm=apt]
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg

# Package that requires the repo above — APT only
--- pkg [pm=apt]
nodejs

# Post-install script: run on every distro
--- script
npm install -g pnpm
echo "Setup complete."

# Per-line selectors: install bat only on Debian/Ubuntu x86_64
--- pkg
bat [pm=apt, arch=x86_64]
ripgrep
```

### Minimal manifest

A manifest with only package names and no headers is perfectly valid:

```
git
curl
jq
ripgrep
```

### Inline manifest in devcontainer.json

Use `\n` as line endings when writing a multi-line string inline in JSON.
The installer automatically expands literal `\n` escape sequences so that
inline-manifest detection works correctly:

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-os-pkg:0": {
      "manifest": "git\ncurl\njq\n"
    }
  }
}
```

---

## Lifecycle hook

By default the feature installs packages at **image build time** (inside the
`docker build` step). Setting `lifecycle_hook` defers installation to a
devcontainer lifecycle event that runs _after_ the container is created, with
the workspace fully mounted.

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-os-pkg:0": {
      "manifest": "/workspace/.devcontainer/packages.txt",
      "lifecycle_hook": "postCreate"
    }
  }
}
```

Supported values:

| Value | When it runs |
|---|---|
| `onCreate` | Once, after the container is created and the workspace is mounted. |
| `updateContent` | Once when the workspace content changes (e.g. a new clone). |
| `postCreate` | Once, after `onCreate` and `updateContent` have completed. |

When `lifecycle_hook` is set:

- The feature writes a single executable hook script to
  `/usr/local/share/install-os-pkg/<hook-name>.sh` (e.g. `post-create.sh`).
- No packages are installed during the build step.
- If the manifest value is inline content it is saved to
  `/usr/local/share/install-os-pkg/manifest.txt` so it is accessible at
  hook runtime.

The other two hook commands are registered as safe no-ops, so they have no
effect when the files are absent.

> **Note:** `lifecycle_hook` requires a non-empty `manifest`.

---

## System paths

| Path | Purpose |
|---|---|
| `/usr/local/bin/install-os-pkg` | Wrapper script (written when `install_self=true`). |
| `/usr/local/lib/install-os-pkg/install.sh` | Library copy of the main installer. |
| `/usr/local/share/install-os-pkg/` | Hook scripts and saved manifests (only when `lifecycle_hook` is set). |

---

## Supported package managers

Detection is automatic based on which binary is present:

| Distro family | Tool detected |
|---|---|
| Debian / Ubuntu | `apt-get` |
| Alpine | `apk` |
| Fedora / RHEL / CentOS | `dnf`, `microdnf`, or `yum` |
| openSUSE | `zypper` |
| Arch Linux | `pacman` |
