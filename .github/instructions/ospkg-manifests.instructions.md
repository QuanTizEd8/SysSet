---
description: "Use when writing or editing ospkg manifest files (YAML/JSON). Covers YAML schema, when clauses, PM-specific blocks, inline setup, package objects, groups, casks."
applyTo: "src/**/dependencies/*.yaml"
---

# ospkg Manifest Format

Manifests are consumed by `ospkg__run --manifest <file-or-inline>`.
Manifests are written in **YAML** (or **JSON**) format.

---

## YAML / JSON Manifest

### Top-level structure

```yaml
# Optional global condition — skips the entire manifest if false.
when: {pm: apt}

# Signing keys fetched before repos/packages.
keys:
  - url: https://example.com/key.gpg
    dest: /usr/share/keyrings/example.gpg   # ends in .gpg → auto-dearmored
  - url: https://example.com/key.asc
    dest: /etc/apt/trusted.gpg.d/example.gpg
    dearmor: true                           # explicit

# Repository lines to add (PM-native format).
repos:
  - content: "deb [signed-by=...] https://repo.example.com stable main"

# APT PPAs (apt-add-repository).
ppas:
  - "ppa:git-core/ppa"

# Homebrew taps (brew only).
taps:
  - homebrew/core
  - name: my-org/tap
    url: https://github.com/my-org/homebrew-tap

# DNF COPR repos.
copr:
  - "user/reponame"

# DNF module streams.
modules:
  - "nodejs:18"

# Package groups (dnf group install / zypper pattern / pacman group).
groups:
  - "@development-tools"

# Shell commands run before package installation.
prescripts: |
  install -d /opt/myapp

# Unconditional packages (all PMs).
packages:
  - git
  - name: curl
    when: {pm: apt}
  - name: htop
    version: "3.2.1"          # becomes htop=3.2.1 on apt/apk/pacman/zypper, htop-3.2.1 on dnf/yum, htop@3.2.1 on brew
  - name: some-pkg
    flags: "--allow-unauthenticated"   # appended to the install command

# Per-PM package lists (override or supplement `packages`).
apt:
  packages:
    - build-essential
    - libssl-dev
brew:
  packages:
    - gnu-sed
  casks:
    - visual-studio-code

# macOS Homebrew casks (top-level shorthand).
casks:
  - iterm2

# Shell commands run after package installation.
scripts: |
  ldconfig
```

### Per-PM blocks

Any of the following top-level keys are evaluated only when the active PM matches:
`apt`, `brew`, `dnf`, `apk`, `yum`, `zypper`, `pacman`.

Each accepts a `packages` list. `brew` also accepts `casks` and `taps`.

```yaml
apt:
  packages:
    - libssl-dev
brew:
  taps:
    - homebrew/cask-fonts
  packages:
    - gnu-sed
  casks:
    - font-hack-nerd-font
```

### `when` clause

A `when` expression is supported at:
- Manifest top level (skips entire manifest if false)
- Individual package objects
- Group objects

`when` accepts a **mapping** (AND of all keys) or a **list of mappings** (OR of ANDs):
```yaml
when: { pm: apt }                   # pm == apt
when: { pm: [apt, apk] }            # pm == apt OR pm == apk
when: [{ pm: apt }, { pm: apk }]    # same — OR across objects
when: { pm: apt, id: debian }       # pm == apt AND id == debian
```

`when` values are matched case-insensitively. A key absent from the context evaluates as empty string.

Available condition keys — all `/etc/os-release` fields plus three synthetics:

| Field | Source |
|-------|--------|
| `pm` | Detected package manager: `apt`, `brew`, `dnf`, `apk`, `yum`, `zypper`, `pacman` |
| `kernel` | `linux` or `darwin` (synthetic) |
| `arch` | CPU architecture: `x86_64`, `aarch64`, `arm64`, etc. (synthetic) |
| `id` | `/etc/os-release` `ID` (or `macos` on macOS) |
| `id_like` | `/etc/os-release` `ID_LIKE` |
| `version_id` | `/etc/os-release` `VERSION_ID` |
| `version_codename` | `/etc/os-release` `VERSION_CODENAME` (e.g. `jammy`, `bookworm`) |
| _(any other key)_ | Any other field present in `/etc/os-release` on the target system |

### Package objects

Packages may be plain strings or objects:

```yaml
packages:
  - git                          # plain string
  - name: curl                   # object — supports all fields below
    when: { pm: [apt, brew] }
    version: "8.0.1"
    flags: "--no-install-recommends"
```

| Field | Description |
|-------|-------------|
| `name` | Package name (required) |
| `when` | Condition (same syntax as top-level `when`) |
| `version` | Plain version number (e.g. `1.2.3`). The installer builds PM-native syntax automatically (`pkg=ver` apt/apk/pacman/zypper, `pkg-ver` dnf/yum, `pkg@ver` brew). |
| `flags` | Extra flags appended to the install command |

### JSON manifest

JSON is also accepted (and produced by `yq -o=json`). The same schema applies.

---

## `ospkg__run` / Feature Option Reference

| ospkg__run flag | Feature option | Default | Effect |
|-----------------|---------------|---------|--------|
| `--manifest <val>` | `manifest` | `""` | Path or inline manifest content |
| `--update false` | `update=false` | `true` | Skip package list refresh |
| `--keep_cache` | `keep_cache` | `false` | Preserve PM cache after install |
| `--keep_repos` | `keep_repos` | `false` | Keep added repo files |
| `--skip_installed` | `skip_installed` | `false` | Skip packages already in PATH |
| `--prefer_linuxbrew` | `prefer_linuxbrew` | `false` | Use brew on Linux when available |
| `--dry_run` | `dry_run` | `false` | Simulate without making changes |
| `--lists_max_age <n>` | `lists_max_age` | `300` | Age threshold (s) for update skip |

## Further Reading

- `docs/ref/install-os-pkg.md` — full `install-os-pkg` feature reference
