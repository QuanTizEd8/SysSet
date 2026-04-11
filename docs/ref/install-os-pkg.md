# OS Package Installer

Install packages from the operating system's native package manager using a
single, cross-platform YAML or JSON manifest file.

Supports **APT** (Debian/Ubuntu), **APK** (Alpine), **DNF/YUM**
(Fedora/RHEL/CentOS), **microdnf**, **Zypper** (openSUSE), **Pacman** (Arch
Linux), and **Homebrew** (macOS, Linuxbrew).

---

## Usage

### As a Dev Container feature

```jsonc
// .devcontainer/devcontainer.json
{
  "features": {
    "ghcr.io/quantized8/sysset/install-os-pkg:0": {
      "manifest": "/existing/path/packages.yaml"
      // or:   "/nonexistent/path/packages.json"
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
      "manifest": "packages: [git, curl, jq]\n"
      // or: "{\"packages\": [\"git\", \"curl\", \"jq\"]}\n"
    }
  }
}
```

>[!NOTE]
> One-line inline manifests must end with a newline character for proper detection.

### As a standalone installer script

The script can be piped directly from the network or run from a local copy.
Pass the manifest as a file path or an inline string via `--manifest`.
The script must run as root on Linux.
On macOS it may run as a regular user or with `sudo`.

```sh
# From a manifest file
curl -fsSL https://raw.githubusercontent.com/quantized8/sysset/main/src/install-os-pkg/install.sh \
  | sudo bash -s -- --manifest /path/to/packages.yaml

# Inline manifest (trailing newline required for inline detection)
sudo bash install.sh --manifest $'packages:\n  - git\n  - curl\n  - jq\n'
```

After the feature has been installed (with `install_self` set to `true`),
a persistent wrapper is available at `/usr/local/bin/install-os-pkg`
and can be called directly by other features or lifecycle hook scripts (e.g., `postCreateCommand`):

```sh
install-os-pkg --manifest /workspace/.devcontainer/extra-packages.yaml
```

### As a dependency for another devcontainer feature

Other features can declare `install-os-pkg` as a dependency and call the
installer directly in their own `install.sh` to set up packages as part of
their own setup process:

```jsonc
// devcontainer-feature.json of another feature
{
  "dependsOn": {
    "ghcr.io/quantized8/sysset/install-os-pkg:0": {
        "install_self": true
    }
  }
}
```

```sh
# install.sh of another feature
install-os-pkg --manifest $'packages:\n  - git\n  - curl\n'
```

---

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `manifest` | string | `""` | Inline manifest content (YAML/JSON) or path to a manifest file. Required unless `install_self` is `true`. When the value contains a newline it is treated as inline content; otherwise as a file path. |
| `install_self` | boolean | `false` | Write the `install-os-pkg` wrapper to `/usr/local/bin`. Enable when you want the installer accessible to other features or lifecycle hook scripts after the build step. |
| `lifecycle_hook` | enum | `""` | Defer installation to a devcontainer lifecycle event (`onCreate`, `updateContent`, or `postCreate`). See [Lifecycle hook](#lifecycle-hook). |
| `interactive` | boolean | `false` | Allow interactive package manager prompts. Defaults to `DEBIAN_FRONTEND=noninteractive` for APT. |
| `prefer_linuxbrew` | boolean | `false` | On Linux, prefer Homebrew (Linuxbrew) over the native package manager when both are available. By default the native PM always takes priority. |
| `update` | boolean | `true` | Refresh package lists before installing. Auto-skipped when lists were refreshed within `lists_max_age` seconds, unless a new repository was added by the manifest. |
| `lists_max_age` | string | `"300"` | Maximum age of the package lists (in seconds) before a refresh is considered necessary. Set to `0` to always update. Ignored when `update` is `false` or when a new repository was added by the manifest. |
| `keep_repos` | boolean | `false` | Keep repository drop-in files written during installation. By default they are removed after packages are installed. Homebrew taps are always kept regardless of this setting. |
| `keep_cache` | boolean | `false` | Keep the package manager's download cache after installation. By default the cache is cleaned to reduce image size. |
| `skip_installed` | boolean | `false` | Skip packages whose binary is already present in `PATH` (checked via `command -v`). Useful when a dependency may have been installed outside the system package manager. |
| `dry_run` | boolean | `false` | Print what would be installed/fetched without making any changes. No packages are installed, no files are written, and no scripts are executed. Root privilege is not required. See [Dry run](#dry-run). |
| `debug` | boolean | `false` | Enable `set -x` trace output. |
| `logfile` | string | `""` | Mirror all output (stdout + stderr) to this file in addition to the console. |

---

## Manifest format

A manifest is a YAML (or JSON) document that declaratively describes what to
install and how. A formal JSON Schema is available at
[`src/install-os-pkg/manifest.schema.json`](../../src/install-os-pkg/manifest.schema.json)
and can be referenced in editors for autocompletion and validation:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/QuanTizEd8/SysSet/main/src/install-os-pkg/manifest.schema.json
```

### Top-level structure

```yaml
# Packages to install
packages:
  - curl
  - git
  - jq

# Global scripts
prescripts: mkdir -p /opt/tools
scripts: echo "Done."

# PM-specific setup (only the active PM's block is evaluated)
apt:
  ppas: [ppa:deadsnakes/ppa]
brew:
  taps: [homebrew/cask-fonts]
```

All top-level keys are optional. A manifest with only `packages` is valid. A
manifest with only PM blocks (e.g. only `brew:` for cask installation) is
also valid. An empty manifest is valid but does nothing.

The full set of top-level keys:

| Key | Type | Description |
|---|---|---|
| `packages` | packageEntry[] | Packages to install. See [Package entries](#package-entries). |
| `prescripts` | script | Shell commands run before any PM operations. |
| `scripts` | script | Shell commands run after all packages are installed. |
| `apt` | object | APT-specific setup. See [PM blocks](#pm-blocks). |
| `apk` | object | APK-specific setup. |
| `brew` | object | Homebrew-specific setup. |
| `dnf` | object | DNF-specific setup. |
| `yum` | object | YUM-specific setup. |
| `pacman` | object | Pacman-specific setup. |
| `zypper` | object | Zypper-specific setup. |

### Package entries

The `packages` array accepts three entry types.

#### Bare strings

A bare string is a package name installed via the detected package manager:

```yaml
packages:
  - git
  - curl
  - jq
```

This is the simplest and most common form. A manifest containing nothing but
bare strings covers the vast majority of use cases.

#### Package objects

A package object provides PM-specific name overrides, version constraints,
conditions, flags, and inline setup. The required `name` field is the default
package name:

```yaml
packages:
  - name: ssl
    apt: libssl-dev
    apk: openssl-dev
    brew: openssl
    dnf: openssl-devel
    pacman: openssl
    zypper: libopenssl-devel
```

When the active PM has an explicit override key (e.g. `apt: libssl-dev`),
that override is used instead of `name`. If every target PM has an override,
`name` serves as a human-readable label — it is never passed to any PM.

Package object properties:

| Property | Type | Description |
|---|---|---|
| `name` | string | **Required.** Default package name or label. |
| `when` | condition | Condition filter. Package is skipped when the condition does not match. See [`when` clause](#when-clause). |
| `flags` | string \| string[] | Extra flags passed verbatim to the PM's install command (e.g. `--no-install-recommends`). |
| `version` | string | Version constraint in the active PM's native syntax (e.g. `=1.2.3-1` for apt, `>=1.2` for brew). |
| `prescript` | script | Shell commands collected and run in the prescript phase. |
| `script` | script | Shell commands collected and run in the script phase. |
| `keys` | keyEntry[] | Signing keys collected and fetched in the key phase. See [Signing keys](#signing-keys). |
| `repos` | string[] | Repository definitions collected and added in the repo phase. |
| `apt`, `apk`, `brew`, `dnf`, `yum`, `pacman`, `zypper` | string | PM-specific package name override. |

#### Group objects

A group shares conditions, flags, and inline setup across multiple packages.
The required `packages` field distinguishes groups from package objects:

```yaml
packages:
  - label: Build tools
    when: { pm: apt }
    flags: --no-install-recommends
    packages:
      - build-essential
      - pkg-config
      - cmake
```

Groups can nest — a group's `packages` array can contain bare strings,
package objects, or further groups:

```yaml
packages:
  - label: Platform tools
    when: { kernel: linux }
    packages:
      - label: Debian family
        when: { id_like: debian }
        packages: [apt-transport-https, ca-certificates]
      - strace
```

A group's `when` condition ANDs with its children's `when` conditions. In the
example above, `apt-transport-https` requires both `kernel: linux` AND
`id_like: debian` to match. Nested groups stack: the effective condition is
the AND of all ancestor `when` clauses plus the entry's own.

A group's `flags` merge with per-package flags — group flags come first in
the argument list.

Group object properties:

| Property | Type | Description |
|---|---|---|
| `packages` | packageEntry[] | **Required.** The packages in this group. |
| `label` | string | Human-readable label shown in log output. |
| `when` | condition | Condition filter applied (AND'd) to all children. |
| `flags` | string \| string[] | Extra flags applied to all packages in the group. |
| `prescript` | script | Shell commands collected and run in the prescript phase. |
| `script` | script | Shell commands collected and run in the script phase. |
| `keys` | keyEntry[] | Signing keys collected and fetched in the key phase. |
| `repos` | string[] | Repository definitions collected and added in the repo phase. |

### `when` clause

The `when` clause is a condition filter that controls whether a package,
group, or PM block entry is evaluated. It supports two forms:

**Dictionary form** — keys within a dict are AND'd; array values within a
single key are OR'd:

```yaml
# pm must be apt AND arch must be x86_64
when: { pm: apt, arch: x86_64 }

# pm must be apt OR dnf (array values are OR'd within a key)
when: { pm: [apt, dnf] }
```

**List-of-dicts form** — each dict is a compound AND condition; the list is
OR'd:

```yaml
# (apt AND ubuntu) OR (dnf AND fedora)
when:
  - { pm: apt, id: ubuntu }
  - { pm: dnf, id: fedora }
```

#### Condition keys

| Key | Source | Example values |
|---|---|---|
| `pm` | Detected package manager | `apt`, `apk`, `brew`, `dnf`, `yum`, `pacman`, `zypper` |
| `arch` | `uname -m` | `x86_64`, `aarch64`, `armv7l`, `i686`, `arm64` |
| `kernel` | `uname -s` (lowercased) | `linux`, `darwin` |
| `id` | `ID` from `/etc/os-release` (or `macos` on macOS) | `ubuntu`, `debian`, `alpine`, `fedora`, `arch`, `rhel`, `macos` |
| `id_like` | `ID_LIKE` from `/etc/os-release` (or `macos`) | `debian`, `rhel`, `arch`, `suse`, `macos` |
| `version_id` | `VERSION_ID` from `/etc/os-release` (or `sw_vers` on macOS) | `22.04`, `39`, `3.19`, `15.6`, `15.2` |

All condition values are matched case-insensitively.

On macOS, where `/etc/os-release` does not exist, the condition keys are
populated synthetically — see [macOS support](#macos-support).

#### Evaluation rules

1. **Absent `when`** → the entry always matches.
2. **Single dict** → AND of all keys. Each key's value is a string or an
   array of strings (OR'd within the key). All keys must match.
3. **Array of dicts** → OR of compounds. Each element is evaluated as in (2).
   The entry matches if any element matches.
4. **Group stacking** → a group's `when` ANDs with each child's `when`.
   Nested groups stack: the effective condition is the AND of all ancestor
   conditions plus the entry's own.

### PM blocks

PM blocks are top-level keys named after a package manager. They contain
setup operations that are inherently PM-specific — signing keys, repositories,
taps, casks, modules, etc. Only the block matching the detected PM is
evaluated; all others are silently ignored.

```yaml
apt:
  ppas: [ppa:deadsnakes/ppa]
  keys:
    - url: https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key
      dest: /usr/share/keyrings/nodesource.gpg
  repos:
    - "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main"

brew:
  taps: [homebrew/cask-fonts]
  casks: [iterm2, visual-studio-code]

dnf:
  copr: [user/project]
  modules: ["nodejs:18/common"]
  groups: [development-tools]
```

#### Available keys per PM

| PM | Available keys |
|---|---|
| `apt` | `ppas`, `keys`, `repos`, `scripts` |
| `apk` | `repos`, `scripts` |
| `brew` | `taps`, `casks`, `scripts` |
| `dnf` | `copr`, `repos`, `modules`, `groups`, `keys`, `scripts` |
| `yum` | `repos`, `groups`, `keys`, `scripts` |
| `pacman` | `repos`, `keys`, `scripts` |
| `zypper` | `repos`, `keys`, `scripts` |

#### `ppas` (APT only)

Ubuntu PPAs added via `add-apt-repository` before the package list refresh:

```yaml
apt:
  ppas: [ppa:deadsnakes/ppa, ppa:ubuntu-toolchain-r/test]
```

#### `taps` (Homebrew only)

Homebrew taps — third-party formula repositories cloned via `brew tap`.
Entries can be simple strings or objects with a custom URL:

```yaml
brew:
  taps:
    - homebrew/cask-fonts           # short name
    - name: user/repo              # object form with custom URL
      url: https://git.example.com/user/homebrew-repo.git
```

Taps are **not cleaned up** after installation — they persist in the Homebrew
prefix. The `keep_repos` option does not affect taps.

#### `casks` (Homebrew only)

macOS GUI applications installed via `brew install --cask`. No Linux
equivalent — cask entries are silently skipped on Linuxbrew.

```yaml
brew:
  casks: [iterm2, visual-studio-code, firefox]
```

#### `copr` (DNF only)

Fedora COPR repositories enabled via `dnf copr enable`:

```yaml
dnf:
  copr: [user/project]
```

#### `modules` (DNF only)

DNF module streams enabled via `dnf module enable`. Format:
`module:stream` or `module:stream/profile`:

```yaml
dnf:
  modules: ["nodejs:18/common", "php:8.2"]
```

#### `groups` (DNF/YUM only)

Package groups installed via `dnf groupinstall` or `yum groupinstall`:

```yaml
dnf:
  groups: [development-tools, "RPM Development Tools"]
```

#### `repos`

Repository definitions in the active PM's native format. Each entry is a
string written to the PM's drop-in configuration path (see
[Repository drop-in paths](#repository-drop-in-paths)):

```yaml
apt:
  repos:
    - "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main"

dnf:
  repos:
    - |
      [docker-ce]
      name=Docker CE Stable
      baseurl=https://download.docker.com/linux/fedora/$releasever/$basearch/stable
      enabled=1
      gpgcheck=1
      gpgkey=https://download.docker.com/linux/fedora/gpg
```

#### `keys` (PM block)

Signing keys fetched before repositories are added. Same format as inline
keys — see [Signing keys](#signing-keys).

#### `scripts` (PM block)

Shell commands that run only when the corresponding PM is active. PM block
scripts run _after_ all packages and casks are installed, in the script phase
of the [pipeline](#pipeline-execution-order):

```yaml
apt:
  scripts: apt-get autoremove -y
brew:
  scripts: brew cleanup --prune=all
```

### Inline setup

Package objects and group objects can carry `keys`, `repos`, `script`, and
`prescript` inline, keeping all setup for a third-party package in one place:

```yaml
packages:
  - name: docker
    apt: docker-ce
    when: { pm: apt }
    keys:
      - url: https://download.docker.com/linux/ubuntu/gpg
        dest: /etc/apt/keyrings/docker.gpg
    repos:
      - "deb [signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable"
    script: systemctl enable docker
```

Inline keys, repos, and scripts are **collected** and executed in the
standard [pipeline order](#pipeline-execution-order) — not inline at the
point of definition. This structural co-location is for authoring
convenience; it does not change execution semantics. See
[Collected ordering](#collected-ordering) in the Developer Notes for merge
details.

### Signing keys

Keys are signing key entries fetched before any repository is added. Each
entry requires a `url` and `dest`:

```yaml
apt:
  keys:
    - url: https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key
      dest: /usr/share/keyrings/nodesource.gpg
```

Key entry properties:

| Property | Type | Description |
|---|---|---|
| `url` | string (URI) | **Required.** URL to download the signing key from. |
| `dest` | string | **Required.** Destination file path for the key. |
| `dearmor` | boolean | Explicitly control dearmoring. When omitted, auto-detected from `dest` extension. |

Behaviour:

- If `dest` ends in `.gpg`, the key is automatically dearmored via
  `gpg --dearmor` (ASCII-armored PGP → binary keyring format required by
  modern APT `signed-by=` references). Set `dearmor: false` to override.
- `curl` (preferred) or `wget` is used for downloading. `gnupg` is used for
  dearmoring. Missing tools are **auto-installed** via the detected PM before
  proceeding.
- The fetch is retried up to three times with a 3-second pause to handle
  transient network failures.
- GPG operations run in an isolated temporary `GNUPGHOME` directory that is
  removed after all keys are installed, so no trust-database artefacts
  pollute the container image layer.

Keys can appear in PM blocks or inline on package/group objects. All are
collected and processed together during the key phase of the
[pipeline](#pipeline-execution-order).

### Scripts

Scripts are shell commands run at two points in the pipeline:

- **`prescripts`** (top-level) / **`prescript`** (inline on packages/groups):
  Run before any PM operations (keys, repos, update, install).
- **`scripts`** (top-level, PM blocks) / **`script`** (inline on
  packages/groups): Run after all packages are installed, before repo cleanup
  and cache clean.

A script value can be a single string or an array of strings (joined with
newlines before execution):

```yaml
prescripts: mkdir -p /opt/tools

scripts:
  - ldconfig
  - echo "Installation complete"

packages:
  - name: docker
    apt: docker-ce
    script: systemctl enable docker

apt:
  scripts: apt-get autoremove -y
```

### Flags

The `flags` property passes extra arguments verbatim to the PM's install
command. It can be a string (split on whitespace) or an array of strings:

```yaml
packages:
  - name: vim
    flags: --no-install-recommends
    when: { pm: apt }

  - label: Minimal installs
    flags: [--no-install-recommends, --no-install-suggests]
    when: { pm: apt }
    packages: [git, curl]
```

Group flags are prepended to per-package flags when both are present.

---

## Supported package managers

Detection is automatic based on which binary is present. The first match
wins:

| Priority | Tool | Distro family |
|---|---|---|
| 1 | `apt-get` | Debian, Ubuntu |
| 2 | `apk` | Alpine |
| 3 | `dnf` | Fedora, RHEL 8+, CentOS Stream |
| 4 | `microdnf` | Minimal RHEL/UBI containers |
| 5 | `yum` | RHEL 7, CentOS 7, Amazon Linux |
| 6 | `zypper` | openSUSE, SLES |
| 7 | `pacman` | Arch Linux, Manjaro |
| 8 | `brew` | macOS, Linuxbrew |

On macOS (Darwin), `brew` is the **only** candidate — native package managers
do not exist. If `brew` is not found on macOS, the installer fails with an
actionable error message directing the user to install Homebrew first (via the
`install-homebrew` feature or the official Homebrew installer at
<https://brew.sh>).

On Linux, native package managers always take priority over `brew`. Homebrew
(Linuxbrew) is only used on Linux when no native PM is found. Set
`prefer_linuxbrew: true` to invert this — `brew` is then checked before the
native PM chain and will be selected if present, even alongside `apt-get` or
another native PM.

### macOS support

On macOS, Homebrew replaces the system package manager. The installer handles
macOS-specific concerns transparently:

**Condition keys** — Since `/etc/os-release` does not exist on macOS, the
`when` condition keys are populated synthetically:

| Key | Value | Source |
|---|---|---|
| `pm` | `brew` | Detection |
| `arch` | `arm64` or `x86_64` | `uname -m` |
| `kernel` | `darwin` | `uname -s` (lowercased) |
| `id` | `macos` | Synthetic |
| `id_like` | `macos` | Synthetic |
| `version_id` | e.g. `15.2` | `sw_vers -productVersion` |

This means `when: { pm: brew }` and `when: { id: macos }` are both valid
ways to target macOS in a manifest. Both work; the choice is a matter of
intent (`pm: brew` also matches Linuxbrew; `id: macos` targets macOS
specifically).

**Linuxbrew context** — When `prefer_linuxbrew: true` selects Homebrew on a
Linux host, `pm` is `brew` but the remaining keys (`id`, `id_like`,
`version_id`) still reflect the real Linux distro values from
`/etc/os-release`. This means:

- `when: { pm: brew }` matches both macOS brew and Linuxbrew.
- `when: { id: macos }` does **not** match Linuxbrew on Linux — use it when
  you need to target macOS exclusively.
- `when: { pm: brew, id: macos }` also targets macOS only.
- `when: { pm: brew, kernel: linux }` targets Linuxbrew on Linux only.

**Root privilege** — On Linux, the installer requires root for native PM
operations. On macOS, `brew` must run as a non-root user; the
`os::require_root` check is skipped when the detected PM is `brew`. The
`dry_run` option also skips the root check on all platforms.

**Brew user handling** — When the installer runs as root (as it always does
inside a devcontainer feature's `install.sh`), it handles brew's root
restriction transparently:

| Context | Action |
|---|---|
| Root in a container (Docker, Podman, K8s, CI) | Run brew directly — [brew allows root in containers](#brew-root-handling) |
| Root on bare metal | `su` to the owner of `$(brew --prefix)` |
| Non-root | Run brew directly |

No user-facing `brew_user` option is needed. See the
[Developer Notes](#brew-user-handling) for the full rationale and brew's
source code.

---

## Pipeline execution order

When processing a manifest, the installer executes phases in this fixed
order:

1. **Prescripts** — top-level `prescripts` + collected from packages/groups.
2. **Keys** — PM block `keys` + collected from packages/groups.
3. **Repos** — PM block `repos` + collected from packages/groups.
4. **PM-specific setup** — PPAs (apt), taps (brew), COPR (dnf).
5. **Update** — `apt-get update` / `brew update` / `apk update` / etc.
   Skipped when `update` is `false`, or when lists are fresh per
   `lists_max_age`, unless a new repo was just added.
6. **Modules** — `dnf module enable` (DNF only).
7. **Groups** — `dnf groupinstall` / `yum groupinstall` (DNF/YUM only).
8. **Packages** — `packages` array, resolved per active PM.
9. **Casks** — `brew install --cask` (Homebrew only).
10. **Scripts** — PM block `scripts` + top-level `scripts` + collected from
    packages/groups.
11. **Repo cleanup** — remove drop-in repo files (unless `keep_repos`).
12. **Cache clean** — `apt-get clean` / `brew cleanup` / etc. (unless
    `keep_cache`).

Inline keys, repos, and scripts from packages and groups are merged with
their corresponding PM block and top-level entries before execution. Within
each phase, collected items are processed in manifest declaration order. See
[Collected ordering](#collected-ordering) in the Developer Notes for details.

---

## Dry run

Set `dry_run: true` in `devcontainer.json`, pass `--dry_run` on the CLI, or
set `DRY_RUN=true` as an environment variable to print what the installer
would do without making any changes. No packages are installed, no files are
written, and no scripts are executed. Root privilege is not required.

```sh
install-os-pkg --manifest /path/to/packages.yaml --dry_run
```

Example output:

```
🔍 Dry-run mode enabled — no changes will be made.
🔍 [dry-run] key: 1 entry/entries — would fetch:
    https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key → /usr/share/keyrings/nodesource.gpg
🔍 [dry-run] repo: 1 line(s) — would add to package manager repos.
🔍 [dry-run] update: would run: apt-get update
🔍 [dry-run] packages (2): nodejs curl
🔍 [dry-run] cache clean: would run clean_apt
```

> **Note:** When used as a devcontainer feature, the build step succeeds
> without installing anything, which is useful for manifest auditing or
> debugging selector logic in CI.

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
      "manifest": "/workspace/.devcontainer/packages.yaml",
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

- The feature writes a hook script to
  `/usr/local/share/install-os-pkg/<hook-name>.sh` (e.g. `post-create.sh`).
- No packages are installed during the build step.
- If the manifest value is inline content it is saved to
  `/usr/local/share/install-os-pkg/manifest.yaml` so it is accessible at
  hook runtime.
- All other options (`debug`, `keep_repos`, `logfile`, etc.) are forwarded
  into the hook script automatically.
- The other two lifecycle commands are registered as safe no-ops (the files
  for those hooks are absent, so the conditional test in the lifecycle
  command is a no-op).

> **Note:** `lifecycle_hook` requires a non-empty `manifest`.

---

## System paths

| Path | Purpose |
|---|---|
| `/usr/local/bin/install-os-pkg` | Wrapper script (written when `install_self=true`). |
| `/usr/local/lib/install-os-pkg/install.sh` | Library copy of the main installer. |
| `/usr/local/share/install-os-pkg/` | Hook scripts and saved manifests (only when `lifecycle_hook` is set). |

---

## Repository drop-in paths

When a manifest adds repositories (via `repos` in PM blocks or inline on
packages/groups), the installer writes content to a PM-specific drop-in
location before the update and install steps. Unless `keep_repos` is `true`,
the files are deleted after installation so they do not persist in the image.

| Package manager | Drop-in location |
|---|---|
| APT | `/etc/apt/sources.list.d/syspkg-installer.list` |
| APK | Lines appended to `/etc/apk/repositories` (reversed on cleanup) |
| DNF / YUM | `/etc/yum.repos.d/syspkg-installer.repo` |
| Zypper | `/etc/zypp/repos.d/syspkg-installer.repo` |
| Pacman | `/etc/pacman.d/syspkg-installer.conf` + `Include` line in `/etc/pacman.conf` |
| Homebrew | N/A — taps are Git clones into the Homebrew prefix, not drop-in files. They are always kept. |

---

## Full examples

### Minimal manifest

A manifest with only package names and no extra configuration:

```yaml
packages:
  - git
  - curl
  - jq
  - ripgrep
```

### Cross-platform development tools

```yaml
packages:
  - git
  - curl
  - jq

  - name: ssl
    apt: libssl-dev
    apk: openssl-dev
    brew: openssl
    dnf: openssl-devel
    yum: openssl-devel
    pacman: openssl
    zypper: libopenssl-devel

  - label: Build essentials (Debian)
    when: { pm: apt }
    flags: --no-install-recommends
    packages: [build-essential, pkg-config, cmake]

  - label: Build essentials (Alpine)
    when: { pm: apk }
    packages: [build-base, pkgconf, cmake]

  - label: Build essentials (Fedora)
    when: { pm: dnf }
    packages: [gcc, gcc-c++, make, pkgconf-pkg-config, cmake]
```

### Third-party APT repository (Node.js)

```yaml
apt:
  keys:
    - url: https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key
      dest: /usr/share/keyrings/nodesource.gpg
  repos:
    - "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main"

packages:
  - name: nodejs
    when: { pm: apt }
```

### Docker CE with inline setup

All signing key, repository, and post-install configuration co-located with
the package entry:

```yaml
packages:
  - name: docker
    apt: docker-ce
    when: { pm: apt }
    keys:
      - url: https://download.docker.com/linux/ubuntu/gpg
        dest: /etc/apt/keyrings/docker.gpg
    repos:
      - "deb [signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable"
    script: systemctl enable docker
```

### Homebrew with taps and casks

```yaml
brew:
  taps:
    - homebrew/cask-fonts
    - name: user/tools
      url: https://git.example.com/user/homebrew-tools.git
  casks:
    - iterm2
    - visual-studio-code
    - firefox

packages:
  - name: terminal-tools
    brew: bat
  - name: search
    brew: ripgrep
  - name: shell
    brew: fish
```

### Architecture-conditional packages

```yaml
packages:
  - label: Performance tools
    when: { kernel: linux, arch: x86_64 }
    packages: [linux-perf, valgrind]

  - label: Cross-compile tools
    when:
      - { pm: apt, arch: aarch64 }
      - { pm: dnf, arch: aarch64 }
    packages: [gcc-x86-64-linux-gnu]
```

### Mixed Linux and macOS

```yaml
packages:
  - git
  - curl
  - name: ssl
    apt: libssl-dev
    brew: openssl

  - label: macOS development
    when: { id: macos }
    packages:
      - name: compiler
        brew: llvm

brew:
  casks: [iterm2, rectangle]

apt:
  ppas: [ppa:deadsnakes/ppa]

scripts: echo "Setup complete on $(uname -s)"
```

---

## Troubleshooting

### No supported package manager found (macOS)

If the installer fails with "No supported package manager found" on macOS,
Homebrew needs to be installed first. Use the `install-homebrew` feature
(which is automatically ordered before `install-os-pkg` when both are
present via `installsAfter`) or install Homebrew manually from
<https://brew.sh>.

### YAML parse error

Ensure the manifest is valid YAML. Common issues:

- Unquoted strings containing special characters (`:`, `@`, `#`, `[`, `]`).
  Repository lines almost always need quoting:
  `"deb [signed-by=...] https://..."`.
- Indentation errors — YAML uses spaces, not tabs.
- Missing quotes around version constraints containing `=` or `>`.

Add the JSON Schema reference to the top of your manifest file to enable IDE
validation and autocompletion:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/QuanTizEd8/SysSet/main/src/install-os-pkg/manifest.schema.json
```

### Packages not found after adding a repository

Check that `update` is not set to `false`. When a manifest adds
repositories, the package list update must run before installation. The
installer automatically forces an update when a new repo is added, unless
`update: false` overrides this behaviour.

### Brew refuses to run as root

This should not occur inside containers — brew explicitly allows root in
Docker, Podman, Kubernetes, and CI environments. If it does occur, the
container environment may not be detectable (missing `/.dockerenv` or
`/run/.containerenv`, no matching cgroup entries). As a workaround, ensure
the Homebrew prefix exists and is owned by a non-root user, or run the
installer as that user directly.

---

## References

- [devcontainer features specification](https://containers.dev/implementors/features/)
- [devcontainer lifecycle hooks](https://containers.dev/implementors/spec/#lifecycle)
- [APT documentation](https://manpages.debian.org/stable/apt/apt-get.8.en.html)
- [APK wiki](https://wiki.alpinelinux.org/wiki/Alpine_Package_Keeper)
- [Homebrew documentation](https://docs.brew.sh/)
- [Homebrew on Linux](https://docs.brew.sh/Homebrew-on-Linux)
- [Homebrew FAQ — running as root](https://docs.brew.sh/FAQ)
- [DNF documentation](https://dnf.readthedocs.io/)
- [YUM man page](https://man7.org/linux/man-pages/man8/yum.8.html)
- [Pacman wiki](https://wiki.archlinux.org/title/Pacman)
- [Zypper manual](https://en.opensuse.org/SDB:Zypper_manual)
- [os-release specification (FreeDesktop)](https://www.freedesktop.org/software/systemd/man/latest/os-release.html)
- [JSON Schema 2020-12](https://json-schema.org/draft/2020-12/json-schema-core)
- [`manifest.schema.json`](../../src/install-os-pkg/manifest.schema.json) — formal JSON Schema for YAML/JSON manifests

---

## Developer Notes

> This section is an internal reference for contributors. It documents the
> design rationale, architectural decisions, and implementation details behind
> the YAML manifest format and Homebrew integration. It complements the
> user-facing sections above with the _why_ behind every design choice.

### Design rationale: why YAML

The original text DSL used custom section headers (`--- type [selectors]`)
and per-line selector syntax (`package [key=val]`). This worked for basic
cases but had fundamental limitations that motivated the move to YAML:

1. **No tooling support.** The custom syntax is unrecognizable by linters,
   formatters, language servers, and IDEs. Users get zero autocompletion,
   zero validation, and unhelpful error messages when the format is wrong.

2. **Flat structure.** Package-specific setup (keys, repos, scripts) had to
   live in separate sections scattered across the file. There was no way to
   co-locate all setup for a single third-party package (e.g. Docker CE
   needs a signing key + repo + package + post-install script — that was four
   separate sections in the text DSL).

3. **Homebrew complexity.** Brew introduces concepts (taps, casks, formulae,
   `--cask` flag) that don't map cleanly to the text DSL's `pkg`/`repo`/`key`
   section model. Taps are not repos (they're Git clones), casks are not
   regular packages, and brew has no signing keys.

4. **Extensibility ceiling.** Adding per-PM blocks (PPAs, COPR, modules,
   groups) to a line-oriented format would require increasingly complex
   header/selector syntax, creating a bespoke DSL that is harder to learn
   than a structured data format users already know.

YAML was chosen over other structured formats because:

- **`sysset.sh` already has a proven YAML pipeline** — `yq` auto-download +
  YAML→JSON→`jq` processing. The same infrastructure is reused in
  `lib/ospkg.sh` via `_ospkg_ensure_yq()`.
- **JSON Schema provides machine-verifiable contracts** — one schema file
  serves as an authoritative specification, validation source, documentation
  generator, and IDE autocompletion backend. There is no ambiguity about
  what constitutes a valid manifest.
- **YAML is natively commentable** — unlike JSON, YAML supports line
  comments (`#`), which matters for manifests that users maintain by hand.
- **One file replaces many** — a single YAML manifest replaces the
  per-platform `.txt` files that features previously maintained in their
  `dependencies/` directories.

JSON manifests are equally valid (JSON is a strict subset of YAML), so
users who prefer JSON or generate manifests programmatically can use `.json`
files directly. The parser uses `yq`, which auto-detects the format — no
extension convention or explicit flag is required.

### Schema design

#### Evaluated candidates

23+ schema structures were evaluated during the design phase. The major
categories were:

- **Flat package list** with per-entry PM overrides — every package becomes
  an object, making simple manifests unnecessarily verbose.
- **PM-first grouping** (`apt: {packages: [...]}`, `brew: {packages: [...]}`
  ) — clean for PM-specific packages but forces duplication for cross-
  platform packages. Cannot express "install `curl` on every platform"
  without repeating it in every PM block.
- **Separate `overrides` section** — moves PM name mappings to a dedicated
  top-level block, keeping `packages` clean but splitting logically related
  information across distant parts of the file.
- **Brewfile-inspired DSL** — Ruby-like entries (`brew "bat"`,
  `cask "iterm2"`) embedded in YAML strings — foreign syntax that defeats
  the purpose of using a structured format.
- **Conda `meta.yaml` style** — per-line comment selectors (`# [osx]`,
  `# [linux and x86_64]`) — clever but fragile, invisible to YAML parsers,
  and unvalidatable by JSON Schema.

#### Selected: Schema #1 — Unified `packages` + PM-scoped blocks

Schema #1 was selected as the best balance of simplicity, expressiveness, and
cross-PM coverage:

- **`packages`** is the primary, PM-agnostic array. Most entries are bare
  strings that work on any platform. The 95% common case — a list of package
  names — is a simple YAML list with no objects, no nesting, and no
  boilerplate.
- **Package objects** add PM-specific name overrides inline, right where the
  package is defined. No indirection, no cross-referencing with a separate
  overrides section.
- **PM blocks** (top-level `apt:`, `brew:`, etc.) encapsulate inherently
  PM-specific operations that have no cross-platform equivalent (PPAs, taps,
  casks, COPR, modules). They are concise, scannable, and naturally
  exclusive — only the active PM's block runs.
- **Groups** allow shared `when`/`flags` without repeating conditions on
  every entry.

This layered design scales from minimal manifests (3 lines) to complex
cross-platform configurations (50+ lines) without syntactic overhead in
either case.

#### Three refinements to the base schema

The base schema was refined with three additions based on real-world use case
analysis:

1. **`when` as dict OR list-of-dicts.** The original proposal only supported
   a single dict (AND of keys). Real-world manifests need OR across
   different key combinations — e.g. "install this package on (Ubuntu AND
   apt) OR (Fedora AND dnf)." The list-of-dicts form (`when: [{...}, {...}]`)
   provides this without adding a new keyword, a boolean expression parser,
   or a `not`/`or` operator.

2. **Group objects.** When many packages share the same condition or flags
   (e.g. `--no-install-recommends` for all apt packages), repeating the
   condition or flags on every entry is noisy and error-prone. Groups factor
   out shared properties. They also support nesting for hierarchical
   conditions (e.g. `kernel: linux` > `id_like: debian` > specific packages).

3. **Inline setup on packages/groups.** Third-party packages often need a
   signing key, a repository entry, and a post-install script. In the text
   DSL, these had to live in separate `--- key`, `--- repo`, and
   `--- script` sections scattered across the file. The inline `keys`/
   `repos`/`script`/`prescript` properties allow all setup for one logical
   package to live together. This improves readability and maintainability.
   The execution order is unchanged — inline items are collected and merged
   into the standard pipeline phases.

### Selector vocabulary comparison

Every package management ecosystem has its own conditional/selector
mechanism. The `when` clause was designed after studying all of them:

| System | Mechanism | Syntax | Scope |
|---|---|---|---|
| Homebrew Brewfile | Ruby conditionals | `if OS.mac?`, `unless ...` | Per-entry, arbitrary Ruby |
| conda `meta.yaml` | Jinja2 selectors | `# [osx]`, `# [linux and x86_64]` | Per-line comment suffix |
| rattler-build `recipe.yaml` | `if/then` YAML keys | `if: osx`, `then: ...` | Per-section |
| APT `sources.list` | `[arch=amd64]` | Square-bracket options | Per-repo line |
| Our text DSL (old) | `[key=val, key=val]` | Square-bracket blocks | Per-section or per-line |
| **YAML `when` clause** | **Dict / list-of-dicts** | **`when: { key: val }`** | **Per-entry, per-group** |

Design choices informed by this comparison:

- **Declarative over procedural.** Brewfile uses arbitrary Ruby; conda uses
  Jinja2. Both are powerful but require familiarity with the host language
  and are impossible to validate statically. `when` clauses are pure data —
  no language runtime needed, and they are fully validatable via JSON Schema.

- **Explicit key vocabulary.** Rather than free-form predicates, the `when`
  clause uses a fixed set of 6 keys (`pm`, `arch`, `kernel`, `id`,
  `id_like`, `version_id`) that map directly to detectable system facts.
  This avoids the ambiguity of conda's `osx` vs `unix` vs `linux` vs `win`
  (platform identifiers with overlapping semantics). The `version_codename`
  key from the old text DSL was deliberately dropped — codenames are
  Debian/Ubuntu-specific and not available on other distros.

- **AND/OR composability.** conda selectors use `and`/`or`/`not` keywords
  in comment strings. rattler-build uses boolean expressions. The
  dict/list-of-dicts approach provides equivalent composability with
  standard YAML syntax, no expression parser, and a clear mental model:
  _dict = AND, list = OR_.

- **No negation.** The `when` clause does not support `not`. Negation
  creates fragile manifests that break when new platforms are added (e.g.
  `not: { pm: apt }` silently includes every future PM). Positive assertions
  are explicit and forward-compatible. If negation becomes necessary in the
  future, it can be added as a `not` key inside a condition object without
  breaking the existing schema.

### `when` evaluation algorithm

The `when` clause is evaluated by `ospkg.sh` as follows:

1. **Absent `when`** → the entry always matches (unconditional).
2. **Single condition object** (dict) → evaluate as AND:
   - For each key in the object (e.g. `pm`, `arch`), compare its value(s)
     against the corresponding system fact.
   - If the value is a string → must match the system fact
     (case-insensitive string comparison).
   - If the value is an array → at least one element must match (OR within
     a key).
   - All keys in the object must match for the condition to pass (AND
     across keys).
3. **Array of condition objects** (list-of-dicts) → evaluate as OR:
   - Each element is evaluated as in step 2.
   - The entry matches if **any** element matches.
4. **Group stacking** → a group's `when` ANDs with each child's `when`:
   - A group with `when: A` containing a package with `when: B` requires
     both A AND B to match independently.
   - Nested groups stack: the effective condition is the AND of all ancestor
     `when` clauses plus the entry's own.
   - If any ancestor's `when` fails, the entire subtree is skipped — child
     conditions are not even evaluated.

### PM detection chain

The installer walks a fixed detection chain and selects the first PM binary
found in `PATH`. The chain order was chosen to match the relative prevalence
of distro families in containerised environments:

```
apt-get → apk → dnf → microdnf → yum → zypper → pacman → brew
```

`brew` is last because:

- On Linux, native PMs should always be preferred — they are faster, better
  integrated, and produce smaller container images than Linuxbrew.
- A Linux system with both `apt-get` and `brew` present is almost certainly
  a developer workstation where the user installed Linuxbrew on top of a
  Debian/Ubuntu base. Defaulting to the native PM is the right choice for
  99% of those cases. Set `prefer_linuxbrew: true` to opt in to the
  Linuxbrew-first behaviour.

On macOS, no native PM exists and `brew` is checked unconditionally (the
linear chain is not used). If `brew` is absent, the installer exits with an
actionable error rather than silently succeeding with nothing installed.

The `microdnf` entry exists because RHEL/UBI minimal images (`ubi8-minimal`,
`ubi9-minimal`) ship `microdnf` but not `dnf`. It is detected only when `dnf`
is absent, so standard RHEL images continue to use `dnf`.

### Brew root handling

Homebrew refuses to run as root on bare-metal systems to prevent accidental
damage to system files. However, it **explicitly allows root in containers**.

From brew's source code (`Library/Homebrew/brew.sh`,
`check-run-command-as-root()`):

```bash
check-run-command-as-root() {
  [[ "${EUID}" == 0 || "${UID}" == 0 ]] || return
  # Allow containers and CI:
  [[ -f /.dockerenv ]] && return
  [[ -f /run/.containerenv ]] && return
  [[ -f /proc/1/cgroup ]] && grep -E \
    "azpl_job|actions_job|docker|garden|kubepods" -q /proc/1/cgroup && return
  # Allow brew services (needs sudo):
  [[ "${HOMEBREW_COMMAND}" == "services" ]] && return
  # Allow read-only --prefix:
  [[ "${HOMEBREW_COMMAND}" == "--prefix" ]] && return
  odie "Running Homebrew as root is extremely dangerous..."
}
```

This is relevant because devcontainer features' `install.sh` **always runs
as root** (per the [devcontainer spec](https://containers.dev/implementors/features/)).
The installer leverages brew's own container detection to run `brew install`
directly as root inside containers — no user switching needed.

The devcontainer spec provides `_REMOTE_USER` and `_CONTAINER_USER`
environment variables at feature install time, but neither is needed for brew
operations. The brew prefix owner (obtained via `stat $(brew --prefix)`) is
the only identity that matters, and only on bare-metal systems where root
invocations must `su` to that owner.

### Brew user handling

The installer determines who should run `brew` commands based on three
factors: effective UID, container status, and brew prefix ownership.

| Context | EUID | Container? | Action |
|---|---|---|---|
| Devcontainer feature | 0 | Yes | Run brew directly (allowed by brew) |
| Standalone on bare metal | 0 (sudo) | No | `su` to owner of `$(brew --prefix)` |
| Normal user | ≠ 0 | — | Run brew directly |

This is handled internally by `ospkg.sh` — no user-facing `brew_user` option
is exposed. The rationale:

- **There is no ambiguity.** The brew prefix owner is deterministic. In
  containers, root is allowed. On bare metal with sudo, the prefix owner is
  the user who installed brew — obtainable via `stat`.
- **Exposing a `brew_user` option would be error-prone.** Users would need to
  know the brew prefix owner — information the installer can determine
  automatically.
- **Existing feature patterns vary unnecessarily.** `install-shell` uses
  per-user config booleans (4 options); `install-miniforge` uses group
  permissions. Brew's single-user ownership model is simpler than both and
  doesn't warrant a user-facing option.

Container detection is implemented via `os::is_container()` in `lib/os.sh`,
reusing the same indicators brew checks: `/.dockerenv` (Docker),
`/run/.containerenv` (Podman), and cgroup inspection for `docker`,
`kubepods`, `garden`, `azpl_job`, `actions_job` (Kubernetes, Cloud Foundry,
Azure Pipelines, GitHub Actions).

### YAML parser infrastructure

The manifest parser uses a `yq` + `jq` pipeline:

1. **`yq`** (mikefarah/yq) reads the manifest and outputs it as JSON.
   `yq` auto-detects the input format — YAML and JSON are both accepted
   transparently. Since JSON is valid YAML, no explicit format detection is
   needed: the same code path handles both.
2. **`jq`** processes the JSON to extract packages, conditions, PM blocks,
   etc. into a normalized intermediate form consumable by bash.

`yq` is auto-downloaded if not present, using the same pattern as
`sysset.sh`:

- Binary is fetched from [mikefarah/yq GitHub Releases](https://github.com/mikefarah/yq/releases)
  for the current platform (`linux`/`darwin`) and architecture
  (`amd64`/`arm64`).
- The download is checksum-verified (SHA-256) against the published checksums
  file.
- The binary is placed in a cache or temporary directory — no system
  installation, no `PATH` modification, no package manager dependency.

This is implemented via an `_ospkg_ensure_yq()` helper in `lib/ospkg.sh`
that is called once at the start of manifest parsing. The helper is idempotent
— if `yq` is already present (either system-installed or previously
downloaded), it is reused without re-downloading.

### Collected ordering

When inline keys, repos, and scripts from multiple packages and groups are
collected into their respective pipeline phases, they are merged in
**manifest declaration order** — the order in which items appear in the YAML
file.

Within each phase, the merge order is:

1. **PM block entries** (if present for the active PM).
2. **Top-level entries** (`prescripts`, `scripts`).
3. **Collected inline entries** from the `packages` array, in declaration
   order (depth-first traversal of nested groups).

This means:

- A PM block's keys are fetched before inline keys from packages.
- A PM block's scripts run before top-level `scripts`, which run before
  inline scripts.
- Within the `packages` array, items are processed in the order written.
  A key on package A (listed first) is fetched before a key on package B
  (listed second).

### Backward compatibility

The text DSL parser is removed entirely — this is a **clean break**. There is
no transition period, backward-compatibility layer, or automatic format
detection/migration.

Rationale:

- **The text DSL has no external users.** The feature has not had a stable
  release. The text DSL was never documented outside this repository and was
  never published to a package registry.
- **All in-repo manifests will be migrated.** The feature-level
  `dependencies/base.txt` files used by other features (which also consume
  `ospkg::run()`) will be converted to YAML as part of the implementation.
- **A backward-compatible approach would be costly.** Supporting two formats
  means maintaining two parsers, producing confusing error messages when the
  wrong format is used (or worse, silently misinterpreting one format as the
  other), and carrying documentation burden for a deprecated syntax
  indefinitely.
- **Clean breaks are cheaper at this stage.** Before a stable release, the
  cost of breaking changes is near zero. After the YAML format ships, the
  JSON Schema provides a versioned contract that protects against future
  breakage.

### Cross-PM feature mapping

Not all PM concepts have equivalents across package managers. This table maps
manifest features to their PM-level implementations:

| Manifest concept | apt | apk | brew | dnf | yum | pacman | zypper |
|---|---|---|---|---|---|---|---|
| Regular packages | `apt-get install` | `apk add` | `brew install` | `dnf install` | `yum install` | `pacman -S` | `zypper install` |
| GUI apps (casks) | — | — | `brew install --cask` | — | — | — | — |
| Third-party repos | `sources.list.d/` | `/etc/apk/repositories` | `brew tap` | `yum.repos.d/` | `yum.repos.d/` | `pacman.conf` | `zypper addrepo` |
| PPAs | `add-apt-repository` | — | — | — | — | — | — |
| COPR | — | — | — | `dnf copr enable` | — | — | — |
| Module streams | — | — | — | `dnf module enable` | — | — | — |
| Package groups | — | — | — | `dnf groupinstall` | `yum groupinstall` | — | `zypper install -t pattern` |
| Signing keys | `gpg --dearmor` | — | — | `rpm --import` | `rpm --import` | `pacman-key` | `rpm --import` |
| Cache clean | `apt-get clean` | `apk cache clean` | `brew cleanup` | `dnf clean all` | `yum clean all` | `pacman -Scc` | `zypper clean` |
| List update | `apt-get update` | `apk update` | `brew update` | `dnf makecache` | `yum makecache` | `pacman -Sy` | `zypper refresh` |

Entries marked "—" indicate the concept does not exist or is not applicable
for that PM. Manifest entries targeting unsupported PM features are silently
skipped.
