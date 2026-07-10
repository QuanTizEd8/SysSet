# Notes

This feature installs packages described by a declarative **manifest** — a
single YAML or JSON document that works across every supported package
manager. The `manifest` option (see the options table above) accepts inline
content, a file path, or a URI; this page documents the manifest format
itself, which has no home in the option descriptions.

## Manifest format

A manifest is a YAML (or JSON — JSON is a subset of YAML) document describing
what to install and how. The authoritative contract is the `manifest.schema.json`
bundled with the feature, also published at
`https://quantized8.github.io/devfeats/schema/manifest.json`. The feature
validates every manifest against this schema before installing anything, so a
malformed manifest fails fast with a schema error. Reference the schema at the
top of a manifest file for editor autocompletion and validation:

```yaml
# yaml-language-server: $schema=https://quantized8.github.io/devfeats/schema/manifest.json
```

The document is either a bare non-empty **array** (shorthand for a top-level
`packages` list) or an **object** with any of the keys below. All keys are
optional; a manifest with only `packages` is valid, a manifest with only a PM
block (e.g. only `brew:` for casks) is valid, and an empty manifest is valid
but does nothing.

### Top-level keys

| Key | Type | Description |
|---|---|---|
| `id` | string | Optional identifier for logging/debugging. |
| `description` | string | Optional description for logging/debugging. |
| `when` | condition | Global gate — if it does not match the active context, the **entire** manifest is skipped. See [`when` conditions](#when-conditions). |
| `packages` | packageEntry[] | Packages to install. See [Package entries](#package-entries). |
| `keys` | keyEntry[] | Signing keys fetched before repos/packages. See [Signing keys](#signing-keys). |
| `repos` | string[] | Repository definitions in the active PM's native format. See [Repositories](#repositories-and-variable-substitution). |
| `ppas` | string[] | APT PPA identifiers (`add-apt-repository`). Effective only when the active PM is `apt`. |
| `taps` | tapEntry[] | Homebrew taps. Effective only when the active PM is `brew`. |
| `copr` | string[] | DNF COPR repo names (e.g. `user/repo`). Applied only when the detected PM is `dnf`/`microdnf`; ignored under plain `yum`. |
| `modules` | string[] | DNF module streams (e.g. `nodejs:18`). Same DNF-only restriction as `copr`. |
| `groups` | (string \| {name, when})[] | Distro package-group names (`dnf group install` / `zypper` pattern / `pacman` group). Each entry may carry its own `when`. |
| `casks` | string[] | Homebrew cask names. Effective only when the active PM is `brew` on macOS. |
| `prescripts` | script | Shell commands run before any PM operation. |
| `scripts` | script | Shell commands run after all packages are installed. |
| `apt`, `apk`, `brew`, `dnf`, `yum`, `pacman`, `zypper` | object | PM-specific blocks. Only the block matching the detected PM is evaluated. See [PM blocks](#pm-blocks). |

The top-level `keys`, `repos`, `ppas`, `taps`, `copr`, `modules`, `groups`,
and `casks` collectors mirror the same keys inside PM blocks — use the
top-level form for PM-agnostic authoring, and the PM-block form to scope setup
to a single package manager. Both funnel into the same [execution
phases](#execution-order).

### Package entries

The `packages` array accepts three entry kinds.

**Bare strings** — a package name installed via the detected PM. This is the
common case; a manifest of nothing but bare strings covers most needs:

```yaml
packages:
  - git
  - curl
  - jq
```

**Package objects** — an object with a required `name`. PM override keys
replace `name` when that PM is active; if every target PM has an override,
`name` is only a label (never passed to any PM):

| Property | Type | Description |
|---|---|---|
| `name` | string | **Required.** Default package name, or a label when all target PMs have overrides. |
| `apt`, `apk`, `brew`, `dnf`, `yum`, `pacman`, `zypper` | string | Package-name override for that PM. |
| `when` | condition | The package is skipped when the condition does not match. |
| `flags` | string \| string[] | Extra flags passed verbatim to the install command. |
| `version` | string | Plain version spec — see [Versions](#versions). |
| `prescript` / `script` | script | Shell commands collected into the prescript / script phase. |
| `keys` | keyEntry[] | Signing keys collected into the key phase. |
| `repos` | string[] | Repository definitions collected into the repo phase. |

```yaml
packages:
  - name: ssl            # label only — every target PM has an override
    apt: libssl-dev
    apk: openssl-dev
    brew: openssl
    dnf: openssl-devel
    yum: openssl-devel
    pacman: openssl
    zypper: libopenssl-devel
```

**Group objects** — an object **without** a `name` (a `name` makes it a
package object). A group shares its `when`, `flags`, `keys`, `repos`,
`prescript`, and `script` across all its members:

| Property | Type | Description |
|---|---|---|
| `packages` | packageEntry[] | Members (strings, package objects, or nested groups). Optional — omit it to use the group purely as conditional setup for `keys`/`repos`/`scripts`. |
| `label` | string | Human-readable label for log output only. |
| `when` | condition | Applied (AND'd) to every member and nested group. |
| `flags` | string \| string[] | Prepended to each member's own flags. |
| `keys`, `repos`, `prescript`, `script` | — | Collected like the package-object equivalents. |

```yaml
packages:
  - label: Build tools (Debian)
    when: { plat.pm: apt }
    flags: --no-install-recommends
    packages: [build-essential, pkg-config, cmake]
```

Groups nest, and their `when` clauses stack: the effective condition of any
entry is the AND of all ancestor `when` clauses plus its own.

### Versions

A package object's `version` is a **plain** version spec (a prefix such as
`5.9`, or an exact version such as `5.9.1`) — not PM-native syntax. The
installer queries the repository, resolves the spec to the exact available
version, and builds the PM-native pin itself: `pkg=ver` on apt/apk/pacman/
zypper, `pkg-ver` on dnf/yum, and `pkg@ver` on brew. A spec that no repository
satisfies fails with a clear error. The values `stable`, `latest`, and empty
mean "whatever the PM provides" (unversioned). `version` may contain
`{feat.pm_version}` or other context tokens, expanded before install when the
manifest is generated from feature metadata.

### `when` conditions

A `when` clause gates a manifest, package, group, group member, or `groups`
entry. Condition keys are **qualified** and must match
`^(os|plat|feat)\.[a-z0-9_]+$` — legacy flat keys (`pm`, `arch`, `id`, ...)
are rejected by the schema.

| Key | Source | Example values |
|---|---|---|
| `plat.pm` | Detected package manager | `apt`, `apk`, `brew`, `dnf`, `yum`, `pacman`, `zypper` |
| `plat.kernel` | `uname -s` | `Linux`, `Darwin` |
| `plat.machine` | Raw `uname -m` | `x86_64`, `aarch64`, `arm64` |
| `plat.machine_release` | Normalized release arch | `amd64`, `arm64` |
| `plat.deb_arch` | `dpkg --print-architecture` (apt only) | `amd64`, `arm64`, `armhf` |
| `os.id` | `/etc/os-release` `ID` (or `macos`) | `ubuntu`, `debian`, `alpine`, `fedora`, `arch` |
| `os.id_like` | `ID_LIKE` — a whitespace token list | `debian`, `rhel`, `suse`, `arch` |
| `os.version_id` | `VERSION_ID` | `22.04`, `39`, `3.19` |
| `os.version_codename` | `VERSION_CODENAME` | `jammy`, `bookworm`, `noble` |
| `feat.*` | Install context (`feat.version`, `feat.method`, `feat.pm_version`) | mainly for feature-generated manifests |

Any other `os.<field>` present in `/etc/os-release` is also available; an
absent key evaluates as empty string. Matches are case-insensitive, and
`os.id_like` matches by **token membership** (`eq: rhel` matches
`ID_LIKE="rhel centos"`).

Each key's value is one of:

- a **string** — shorthand for `eq` (equal, case-insensitive);
- a non-empty **array** of strings — shorthand for `eq` with OR across values;
- an **operator object** with any of `eq`, `ne`, `lt`, `lte`, `gt`, `gte`
  (all present operators are AND'd). `eq`/`ne` accept a string or array;
  `lt`/`lte`/`gt`/`gte` are semver comparisons and take a single string. On
  version-like fields (`feat.version`, `os.version_id`) ordering operators
  order by semver; on `os.id_like` they always fail (fail-closed).

A `when` value is either a **single object** (AND of its keys) or a
**non-empty array of objects** (OR of the AND-groups):

```yaml
when: { plat.pm: apt, plat.machine: x86_64 }   # apt AND x86_64
when: { plat.pm: [apt, dnf] }                   # apt OR dnf
when:                                           # (apt AND ubuntu) OR (dnf AND fedora)
  - { plat.pm: apt, os.id: ubuntu }
  - { plat.pm: dnf, os.id: fedora }
when: { feat.version: { gte: "1.0", lt: "2.0" } }  # 1.0 <= version < 2.0
```

Evaluation is performed by the shared `ctx__match_when` / `ctx-match.jq`
context layer, the same engine used for feature `when` blocks.

### PM blocks

Top-level keys named after a package manager hold operations that are
inherently PM-specific. Only the block matching the detected PM runs; the
rest are silently ignored.

| PM | Available keys |
|---|---|
| `apt` | `packages`, `ppas`, `keys`, `repos`, `scripts` |
| `apk` | `packages`, `keys`, `repos`, `scripts` |
| `brew` | `packages`, `taps`, `casks`, `scripts` |
| `dnf` | `packages`, `copr`, `repos`, `modules`, `groups`, `keys`, `scripts` |
| `yum` | `packages`, `repos`, `groups`, `keys`, `scripts` |
| `pacman` | `packages`, `repos`, `keys`, `groups`, `scripts` |
| `zypper` | `packages`, `repos`, `keys`, `groups`, `scripts` |

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

Notes on individual keys:

- **`ppas`** (apt) are added via `add-apt-repository` before the list refresh.
- **`taps`** (brew) are Git clones into the Homebrew prefix. They are **never**
  cleaned up — `keep_repos` does not affect them.
- **`casks`** (brew) are macOS GUI apps; they are silently skipped on
  Linuxbrew.
- **`copr`** and **`modules`** require full `dnf`; under `microdnf` or `yum`
  they are skipped with a warning.
- **`groups`** map to `dnf group install` / `yum groupinstall` /
  `zypper install -t pattern` / `pacman -S <group>` depending on the PM.
- **`scripts`** run only when that PM is active, during the script phase
  (after packages, before cleanup).

### Signing keys

A `keyEntry` fetches a signing key before repositories are added. `dest` is
required, and at least one of `url` or `fingerprint` must be present:

| Property | Type | Description |
|---|---|---|
| `url` | string (URI) | Download the key from this URL. |
| `fingerprint` | string | 40-char hex GPG fingerprint. Without `url`, the key is fetched from a keyserver (Ubuntu HTTPS, then HKP fallbacks). |
| `dest` | string | **Required.** Destination path. If it ends in `.gpg`, the key is dearmored (`gpg --dearmor`) by default. |
| `dearmor` | boolean | Force dearmoring on/off. When omitted, it is auto-detected from a `.gpg` suffix. |

```yaml
apt:
  keys:
    - url: https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key
      dest: /usr/share/keyrings/nodesource.gpg
    - fingerprint: "F911AB184317630C59970973E363C90F8F1B6217"
      dest: /usr/share/keyrings/git-core-ppa.gpg
```

`curl` (or `wget`) and `gnupg` are auto-installed if missing. URL fetches are
retried on transient failure, and GPG operations run in an isolated temporary
`GNUPGHOME` so no trust-database artefacts leak into the image layer.

### Repositories and variable substitution

Each `repos` entry is a **string** in the active PM's native format, written
to the PM's drop-in path (see [Repository drop-in paths](#repository-drop-in-paths))
before the update and install steps:

```text
apt:     "deb [signed-by=/usr/share/keyrings/foo.gpg] https://repo.example.com bookworm main"
apk:     "@community https://dl-cdn.alpinelinux.org/alpine/edge/community"
dnf/yum: .repo file content or a baseurl string
pacman:  an INI section for /etc/pacman.conf
zypper:  zypper addrepo arguments
```

Repo strings and key `url`/`dest` values support `{namespace.key}` token
substitution at runtime, drawing from the same context registry as `when`
keys. `{plat.deb_arch}` is especially useful for APT `[arch=...]` options so a
manifest need not hardcode `amd64`/`arm64`:

```yaml
apt:
  repos:
    - "deb [arch={plat.deb_arch} signed-by=/usr/share/keyrings/myppa.gpg] https://ppa.launchpadcontent.net/foo/ppa/ubuntu {os.version_codename} main"
```

Tokens are expanded at the point of repo write / key fetch (a runtime
expansion, not a YAML preprocessor); unknown tokens are left unchanged.

### Scripts and flags

`prescripts`/`prescript` run before any PM operation; `scripts`/`script` run
after all packages are installed, before repo cleanup and cache clean. A
script value is a string, or an array of strings joined with newlines:

```yaml
prescripts: mkdir -p /opt/tools
scripts:
  - ldconfig
  - echo "done"
```

`flags` passes extra arguments verbatim to the PM install command — a string
(split on whitespace) or an array. Group `flags` are prepended to a member's
own flags.

## Execution order

When processing a manifest, the installer runs these phases in a fixed order.
Top-level, PM-block, and inline (package/group) entries of each kind are
collected together and processed in manifest declaration order within the
phase:

1. **Prescripts.**
2. **Keys** — fetch signing keys.
3. **Repos** — write repository drop-ins.
4. **PM setup** — PPAs (apt), taps (brew), COPR (dnf), then DNF module
   streams and distro package `groups`.
5. **Update** — refresh the package index. Deferred and run lazily just
   before the first package that needs installing. Skipped when `update` is
   false or when the lists are fresh per `lists_max_age`, but forced when a
   new repo was added.
6. **Packages** — install the `packages` array, resolved per active PM.
7. **Casks** — `brew install --cask` (Homebrew on macOS only).
8. **Scripts** — PM-block `scripts`, top-level `scripts`, and inline `script`s.
9. **Repo cleanup** — remove the repo drop-ins unless `keep_repos` is set.
10. **Cache clean** — `apt-get clean` / `brew cleanup` / etc., unless
    `keep_cache` is set.

Structural co-location of inline `keys`/`repos`/`scripts` on a package is for
authoring convenience only; it does not change the phase in which they run.

## Package-manager detection

Detection is automatic — the first binary found wins:

| Priority | Tool | Distro family |
|---|---|---|
| 1 | `apt-get` | Debian, Ubuntu |
| 2 | `apk` | Alpine |
| 3 | `dnf` | Fedora, RHEL 8+, CentOS Stream |
| 4 | `microdnf` | Minimal RHEL/UBI containers |
| 5 | `yum` | RHEL 7, CentOS 7, Amazon Linux |
| 6 | `zypper` | openSUSE, SLES |
| 7 | `pacman` | Arch, Manjaro |
| 8 | `brew` | macOS, Linuxbrew |

On Linux, native PMs always take priority over `brew`; Linuxbrew is used only
when no native PM is present. Set `prefer_linuxbrew: true` to check `brew`
first and select it even alongside a native PM.

On macOS `brew` is the **only** candidate. If it is missing the installer
fails with an actionable error rather than silently succeeding — install
Homebrew first (via the `install-homebrew` feature or <https://brew.sh>).

### macOS support

`/etc/os-release` does not exist on macOS, so the context keys are populated
synthetically: `plat.pm=brew`, `plat.kernel=Darwin`, `os.id=macos`,
`os.id_like=macos`, `os.version_id` from `sw_vers`, and `plat.machine` from
`uname -m`. Both `when: { plat.pm: brew }` and `when: { os.id: macos }` target
macOS — but `plat.pm: brew` also matches Linuxbrew, whereas `os.id: macos`
does not (on a Linuxbrew host the `os.*` keys still reflect the real Linux
distro). Use `os.id: macos` (or `plat.pm: brew, plat.kernel: Darwin`) to
target macOS exclusively.

Homebrew must not run as root on bare metal but explicitly allows it inside
containers (Docker/Podman/K8s/CI). Because a devcontainer feature's install
script always runs as root, the installer relies on brew's own container
detection: it runs `brew` directly in containers, and `su`s to the brew-prefix
owner only on bare-metal root invocations. No user-facing `brew_user` option
is needed. The root check is also skipped for `dry_run`.

## Repository drop-in paths

When a manifest adds repositories, the installer writes to a PM-specific
drop-in location before update/install, then deletes it afterward unless
`keep_repos` is set:

| Package manager | Drop-in location |
|---|---|
| APT | `/etc/apt/sources.list.d/syspkg-installer.list` |
| APK | lines appended to `/etc/apk/repositories` (reversed on cleanup) |
| DNF / YUM | `/etc/yum.repos.d/syspkg-installer.repo` |
| Zypper | `/etc/zypp/repos.d/syspkg-installer.repo` |
| Pacman | `/etc/pacman.d/syspkg-installer.conf` + an `Include` line in `/etc/pacman.conf` |
| Homebrew | N/A — taps are Git clones into the Homebrew prefix and are always kept. |

## System paths

| Path | Purpose |
|---|---|
| `/usr/local/bin/install-os-pkg` | User-facing wrapper command, written only when `install_self=true`. |
| `/usr/local/share/<namespace>/install-os-pkg/install.sh` | Persistent self-copy of the installer, always deployed so lifecycle hooks and other features can call back into a full copy. |
| `/usr/local/share/<namespace>/install-os-pkg/lifecycle-hooks/` | Lifecycle hook scripts (`on-create--install.sh`, `update-content--install.sh`, `post-create--install.sh`) and the saved `manifest.yaml`, written only when `lifecycle_hook` is set. |

`<namespace>` is the feature's OCI namespace (`quantized8/devfeats`).

## Examples

Cross-platform names, a Debian-only group, and inline third-party setup:

```yaml
packages:
  - git
  - curl
  - name: ssl
    apt: libssl-dev
    apk: openssl-dev
    brew: openssl
    dnf: openssl-devel
    pacman: openssl
    zypper: libopenssl-devel

  - label: Build essentials (Debian)
    when: { plat.pm: apt }
    flags: --no-install-recommends
    packages: [build-essential, pkg-config, cmake]

  # Docker CE with its signing key, repo, and post-install script co-located.
  - name: docker
    apt: docker-ce
    when: { plat.pm: apt }
    keys:
      - url: https://download.docker.com/linux/ubuntu/gpg
        dest: /etc/apt/keyrings/docker.gpg
    repos:
      - "deb [arch={plat.deb_arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu {os.version_codename} stable"
    script: systemctl enable docker

brew:
  casks: [iterm2, rectangle]
```

## Troubleshooting

**No supported package manager found (macOS).** Homebrew is not installed.
Add the `install-homebrew` feature (ordered before this one) or install
Homebrew from <https://brew.sh>.

**YAML parse / schema error.** Quote repository lines and version specs that
contain `:`, `@`, `#`, `[`, `]`, `=`, or `>`, and use spaces (not tabs) for
indentation. Add the `# yaml-language-server` schema hint (above) for
in-editor validation.

**Packages not found after adding a repository.** Make sure `update` is not
`false`. The installer forces an index refresh when a repo is added, but
`update: false` overrides that and the new packages may be invisible.

**Brew refuses to run as root.** This should not happen in containers, where
brew allows root. If it does, the container is undetectable (missing
`/.dockerenv` / `/run/.containerenv` and no matching cgroup); ensure the
Homebrew prefix is owned by a non-root user and run the installer as that user.
