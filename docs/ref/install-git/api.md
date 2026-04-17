# API Reference — install-git

<!-- START devcontainer-feature.json MARKER -->
Install Git in the development container. Two strategies controlled by 'method': 'package' uses the OS package manager (with Ubuntu git-core PPA on Ubuntu when version=latest); 'source' builds from a kernel.org tarball for full version control on any platform. Version is controlled independently by the 'version' option: 'latest', 'stable', or a specific version string.

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `method` | string (enum) | `"package"` | Installation strategy. 'package' (default) — install via the OS package manager. On Ubuntu with version=latest, activates the git-core PPA (ppa:git-core/ppa) to provide the newest upstream stable release; all other platforms and version values use their native package manager directly. On macOS, delegates to Homebrew. 'source' — build from a kernel.org source tarball. Requires a C toolchain and build dependencies (installed automatically). Version is controlled by the 'version' option. Works on all supported Linux distributions and macOS (requires Xcode CLT). |
| `version` | string (proposals) | `"latest"` | Version of git to install. 'latest' (default) — with method=package: newest available package (Ubuntu PPA on Ubuntu, native package manager elsewhere; Homebrew on macOS already tracks latest). With method=source: builds the newest tag from the GitHub Tags API, including release candidates. 'stable' — with method=package: native package manager without PPA activation, even on Ubuntu. With method=source: builds the newest stable release (release candidates excluded). A version string (e.g. '2.47.2', '2.47.0-rc1') — with method=package: passes the version to the package manager (user is responsible for availability). With method=source: builds exactly that version from the kernel.org tarball. |
| `prefix` | string | `"auto"` | Installation prefix for source builds (passed as prefix= to make install). 'auto' (default) — resolves to /usr/local when running as root, or $HOME/.local when running as a non-root user. An explicit path — used as-is; the script exits with an error if the path is not writable and cannot be created. |
| `sysconfdir` | string | `"auto"` | System configuration directory for source builds (passed as sysconfdir= to make). Git reads <sysconfdir>/gitconfig as its system-level config file. 'auto' (default) — resolves to /etc when running as root, or $HOME/.config when running as a non-root user. An explicit path — used as-is; the script exits with an error if the path is not writable and cannot be created. |
| `installer_dir` | string | `"/tmp/git-build"` | Working directory for the source build: tarball download, extraction, and compilation happen here. Removed after a successful build unless keep_installer=true. Ignored when method=package. |
| `keep_installer` | boolean | `false` | Keep the source build directory (installer_dir) after a successful install. Useful for debugging build failures or inspecting the compiled binaries. Ignored when method=package. |
| `no_flags` | string | `""` | Space-separated list of components to exclude from the source build (case-insensitive). Available values: 'perl', 'python', 'tcltk', 'gettext'. Each value maps to the corresponding NO_<FLAG>=YesPlease make variable. 'perl' — disables Perl scripts (git-svn, git-send-email, git-archimport, git-cvsimport, gitweb) and removes the Perl runtime requirement. 'python' — disables Python scripts (git-p4) and removes the Python runtime requirement. 'tcltk' — disables Tcl/Tk GUI tools (gitk, git-gui) and removes the Tcl/Tk requirement. 'gettext' — disables i18n/translation support; git output is English-only and the gettext/libintl build dependency is removed. Unknown values are logged as warnings and ignored. Silently ignored when method=package. On Alpine Linux, gettext is always disabled regardless of this option (required for a successful build). |
| `make_flags` | string | `""` | Additional flags appended verbatim last to the make invocation for source builds (space-separated KEY=VALUE pairs, e.g. 'NO_CURL=YesPlease OPENSSL_SHA256=YesPlease'). Appended after all computed flags including no_flags, so last-position values take effect. No validation — unknown flags are silently ignored by make. Silently ignored when method=package. |
| `export_path` | string | `"auto"` | Controls PATH and MANPATH export for source builds. 'auto' (default) — writes idempotent export blocks to all system-wide shell startup files: the BASH_ENV file (non-login non-interactive bash, registered in /etc/environment), /etc/profile.d/install-git.sh (login shells), the system-wide bashrc (non-login interactive bash), and <zshdir>/zshenv (all zsh). This covers login, interactive, non-interactive, Docker RUN, SSH exec, and PAM invocation scenarios. '' (empty string) — skips all PATH/MANPATH writes. A newline-separated list of absolute file paths — writes only to those files. Ignored when method=package (git lands in /usr/bin which is universally on PATH). |
| `shell_completions` | string | `"bash zsh"` | Space-separated list of shell names to install completion scripts for after a source build. Supported shells: 'bash', 'zsh'. As root: copies git-completion.bash to /etc/bash_completion.d/git and git-completion.zsh to <zshdir>/completions/_git (where <zshdir> is detected by shell__detect_zshdir). As non-root: copies to $HOME/.local/share/bash-completion/completions/git (bash) and $HOME/.zfunc/_git (zsh). The source files are taken from $PREFIX/share/git-core/contrib/completion/ which is populated by make install. Set to '' to skip all completion writes. Ignored when method=package (completions are installed by the package manager). Examples: 'bash zsh', 'bash', 'zsh', ''. |
| `if_exists` | string (enum) | `"update"` | What to do when git is already present in PATH before installation begins. If the installed version already matches the resolved target version, installation is always skipped silently regardless of this setting. 'skip' — log a notice and exit successfully without making any changes (idempotent). 'fail' — print an error and exit non-zero. 'reinstall' — detect how git is currently installed, uninstall it, then install fresh using the selected method. Detection is per-platform: dpkg (Debian/Ubuntu), apk (Alpine), rpm (RHEL/Fedora), brew (macOS). If the existing git is package-managed, it is removed via the package manager; if source-installed, all files under prefix and the equivs dummy package (Debian/Ubuntu only) are removed before reinstalling. 'update' — upgrade to the resolved target version. Detects the existing install method and compares it to the requested method. Same-method updates proceed in place (package manager re-runs natively; source rebuild overwrites binaries if the prefix matches, or removes the old prefix first if it differs). Method-switch updates (e.g. package→source or source→package) behave identically to reinstall. |
| `default_branch` | string | `"main"` | Sets init.defaultBranch in the system-level gitconfig (/etc/gitconfig as root, $HOME/.config/git/config as non-root). Applies to all newly initialised repositories. Set to '' to skip writing this setting. |
| `safe_directory` | string | `"*"` | Sets safe.directory in the system-level gitconfig. Use '*' (default) to trust all directories (useful in containers where the working directory may be owned by a different UID), a specific absolute path, or a newline-separated list of paths. Set to '' to skip writing this setting. |
| `system_gitconfig` | string | `""` | Freeform content to append to the system-level gitconfig (as root: /etc/gitconfig; as non-root: $HOME/.config/git/config). Accepts standard gitconfig format, e.g. '[core] autocrlf = input [push] default = simple'. Written after any settings from default_branch and safe_directory. Set to '' to skip. |
| `add_current_user` | boolean | `true` | Include the current user (the user running the installer, or SUDO_USER if set) in the resolved user list for per-user gitconfig writes. Root is deferred: only included as a fallback when no other non-root user is resolved. |
| `add_remote_user` | boolean | `true` | Include the devcontainer remoteUser (from the _REMOTE_USER env var) in the resolved user list for per-user gitconfig writes. Ignored when _REMOTE_USER is unset or empty. Root is excluded from this path. |
| `add_container_user` | boolean | `true` | Include the devcontainer containerUser (from the _CONTAINER_USER env var) in the resolved user list for per-user gitconfig writes. Ignored when _CONTAINER_USER is unset or empty. Root is excluded from this path. |
| `add_users` | string | `""` | Comma-separated list of additional usernames to include in the resolved user list for per-user gitconfig writes. Root is accepted here (unlike the auto-detected paths above). |
| `user_name` | string | `""` | Sets user.name in the per-user gitconfig (~/.gitconfig) for all resolved users. Set to '' to skip writing this setting. |
| `user_email` | string | `""` | Sets user.email in the per-user gitconfig (~/.gitconfig) for all resolved users. Set to '' to skip writing this setting. |
| `user_gitconfig` | string | `""` | Freeform content to append to the per-user gitconfig (~/.gitconfig) for all resolved users. Accepts standard gitconfig format. Written after user_name and user_email settings. Set to '' to skip. |
| `symlink` | boolean | `true` | Create a symlink from the canonical bin directory to $prefix/bin/git when prefix resolves to a non-default path (source builds only). Root: creates /usr/local/bin/git -> $prefix/bin/git. Non-root: creates $HOME/.local/bin/git -> $prefix/bin/git. Ensures the containerEnv PATH entries always resolve to the installed binary regardless of the chosen prefix. No-op when method=package (git is already in /usr/bin), or when prefix already resolves to the canonical path (/usr/local for root, $HOME/.local for non-root). |
| `debug` | boolean | `false` | Enable debug output (set -x). |
| `logfile` | string | `""` | Append install log to this file path. |
<!-- END devcontainer-feature.json MARKER -->

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `method` | enum | `"package"` | `"package"`: OS package manager (Ubuntu PPA when `version=latest` on Ubuntu). `"source"`: build from kernel.org tarball. |
| `version` | string | `"latest"` | `"latest"`: newest package/tag (including RCs for source). `"stable"`: distro package without PPA, or newest stable tag for source. A version string (e.g. `"2.47.2"`): specific version. |
| `prefix` | string | `"auto"` | Source-build install prefix. `"auto"`: `/usr/local` as root, `$HOME/.local` as non-root. Explicit path validated for writeability. Ignored for `method=package`. |
| `sysconfdir` | string | `"auto"` | Source-build sysconfdir. `"auto"`: `/etc` as root, `$HOME/.config` as non-root. Ignored for `method=package`. |
| `installer_dir` | string | `"/tmp/git-build"` | Source-build working directory; removed after success unless `keep_installer=true`. Ignored for `method=package`. |
| `keep_installer` | boolean | `false` | Keep `installer_dir` after a successful source build. Ignored for `method=package`. |
| `no_flags` | string | `""` | Space-separated component flags to disable in source build (`perl`, `python`, `tcltk`, `gettext`). Ignored for `method=package`. |
| `make_flags` | string | `""` | Additional `KEY=VALUE` pairs appended verbatim last to every `make` invocation for source builds. Overrides any computed flag. Ignored for `method=package`. |
| `symlink` | boolean | `true` | Create a symlink from the canonical bin directory to `${PREFIX}/bin/git` when `prefix` resolves to a non-default path (source builds only). Root: `/usr/local/bin/git → ${PREFIX}/bin/git`. Non-root: `$HOME/.local/bin/git → ${PREFIX}/bin/git`. Ensures `containerEnv` PATH always resolves correctly. |
| `shell_completions` | string | `"bash zsh"` | Space-separated list of shell names to install completions for after a source build. Supported: `"bash"`, `"zsh"`. Copies completion scripts from `$PREFIX/share/git-core/contrib/completion/` to system completion dirs (root) or user dirs (non-root). Set to `""` to skip. Ignored for `method=package`. |
| `export_path` | string | `"auto"` | PATH/MANPATH export target files after a source build. `"auto"`: all system-wide startup files. `""`: skip. Newline-separated paths: explicit targets. Ignored for `method=package`. |
| `if_exists` | enum | `"skip"` | When `git` is already in PATH: `"skip"` exits silently; `"fail"` exits non-zero; `"reinstall"` detects and tears down then reinstalls; `"update"` upgrades in place or tears down and reinstalls on a method switch. Version match always short-circuits to skip. |
| `default_branch` | string | `"main"` | Sets `init.defaultBranch` in the system-level gitconfig. Set to `""` to skip. |
| `safe_directory` | string | `""` | Sets `safe.directory` in the system-level gitconfig. `"*"` trusts all directories. Set to `""` to skip. |
| `system_gitconfig` | string | `""` | Freeform content appended to the system-level gitconfig after `default_branch`/`safe_directory`. |
| `add_current_user` | boolean | `false` | Include the current user in the resolved user list for per-user gitconfig writes. Root is deferred: only included as a fallback when no other non-root user is resolved. |
| `add_remote_user` | boolean | `false` | Include the devcontainer remoteUser (from `_REMOTE_USER`) in the resolved user list for per-user gitconfig writes. Ignored when `_REMOTE_USER` is unset or empty. Root is excluded. |
| `add_container_user` | boolean | `false` | Include the devcontainer containerUser (from `_CONTAINER_USER`) in the resolved user list for per-user gitconfig writes. Ignored when `_CONTAINER_USER` is unset or empty. Root is excluded. |
| `add_users` | string | `""` | Comma-separated list of additional usernames for the resolved user list for per-user gitconfig writes. Root is accepted here. |
| `user_name` | string | `""` | Sets `user.name` in `~/.gitconfig` for each resolved user. Set to `""` to skip. |
| `user_email` | string | `""` | Sets `user.email` in `~/.gitconfig` for each resolved user. Set to `""` to skip. |
| `user_gitconfig` | string | `""` | Freeform content appended to `~/.gitconfig` for each resolved user after `user_name`/`user_email`. |
| `debug` | boolean | `false` | Enable `set -x` debug output. |
| `logfile` | string | `""` | Append full install log to this file path. |

---

## Behaviour Matrix

| `method` | `version` | Behaviour |
|---|---|---|
| `package` | `latest` | Ubuntu PPA (newest stable); native package manager elsewhere; Homebrew on macOS (already tracks latest) |
| `package` | `stable` | Native package manager always; no PPA activation even on Ubuntu |
| `package` | `<x.y.z>` | Native package manager with version pinning (ospkg translates to PM-native syntax automatically); user responsible for availability |
| `source` | `latest` | Resolve newest tag via GitHub Tags API (including RCs); build from kernel.org tarball |
| `source` | `stable` | Resolve newest stable tag (no `-rc*` suffix) via GitHub Tags API; build from kernel.org tarball |
| `source` | `<x.y.z>` | Build exactly that version from kernel.org tarball; no API call needed |

---

## Usage Examples

### Default Install

Installs git from the OS package manager. On Ubuntu, activates the git-core PPA for the newest upstream stable release. On macOS, uses Homebrew. Fastest option; no compiler needed.

```jsonc
// devcontainer.json
{
  "features": {
    "ghcr.io/quantized8/sysset/install-git": {}
  }
}
```

Standalone:
```bash
curl -fsSL https://github.com/quantized8/sysset/releases/latest/download/install-git.sh | bash
```

---

### Distro-Provided git (No PPA, No Source Build)

Always uses the native package manager, even on Ubuntu. Installs whatever version the distro currently packages.

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-git": {
      "version": "stable"
    }
  }
}
```

---

### Pinned Package Version

Installs a specific version via the package manager. The version must exist in the distro's current repositories. Not supported on macOS (Homebrew does not support arbitrary git version pinning via formula arguments).

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-git": {
      "version": "2.34.1"
    }
  }
}
```

---

### Latest Stable from Source

Resolves the current stable release via the GitHub Tags API and builds from a kernel.org tarball. Useful on Debian or RHEL where base packages are old and there is no PPA equivalent. Takes 3–5 minutes.

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-git": {
      "method": "source",
      "version": "stable"
    }
  }
}
```

Standalone:
```bash
curl -fsSL https://github.com/quantized8/sysset/releases/latest/download/install-git.sh | bash -s -- --method source --version stable
```

---

### Latest Tag from Source (Including Release Candidates)

Resolves the absolute newest git tag (RCs included) and builds from source. Use when you want to track the bleeding edge.

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-git": {
      "method": "source"
    }
  }
}
```

---

### Pinned Version from Source

Builds exactly `2.47.2` from the kernel.org tarball. Works on all supported Linux distros and macOS (requires Xcode CLT).

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-git": {
      "method": "source",
      "version": "2.47.2"
    }
  }
}
```

Standalone:
```bash
curl -fsSL https://github.com/quantized8/sysset/releases/latest/download/install-git.sh | bash -s -- --method source --version 2.47.2
```

---

### Pinned Version from Source with Custom Prefix

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-git": {
      "method": "source",
      "version": "2.47.2",
      "prefix": "/opt/git"
    }
  }
}
```

The caller is responsible for adding `/opt/git/bin` to PATH.

---

### Fail If Git Already Present

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-git": {
      "if_exists": "fail"
    }
  }
}
```

---

### Gitconfig — Container Setup

Trusts all directories (essential when the UID inside the container differs from the file owner), sets the default branch, and writes identity for the devcontainer `remoteUser`. Works with any `method`.

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-git": {
      "safe_directory": "*",
      "default_branch": "main",
      "add_remote_user": true,
      "user_name": "Dev User",
      "user_email": "dev@example.com"
    }
  }
}
```

Standalone (non-root, writes to `~/.config/git/config` and `~/.gitconfig`):
```bash
curl -fsSL https://github.com/quantized8/sysset/releases/latest/download/install-git.sh | \
  bash -s -- --safe_directory '*' --default_branch main --user_name 'Dev User' --user_email dev@example.com
```

---

### Gitconfig — System-wide Custom Settings

Appends freeform gitconfig content to `/etc/gitconfig` (system-level). Useful for organisation-wide defaults.

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-git": {
      "system_gitconfig": "[core]\n  autocrlf = input\n[push]\n  default = simple"
    }
  }
}
```

---

## Details

### Ubuntu PPA (`package + latest`)

On Ubuntu, `version=latest` activates `ppa:git-core/ppa`, which provides the most recently backported upstream stable release for Ubuntu LTS codenames. The installer:

1. Verifies the running `$VERSION_CODENAME` is supported by the PPA.
2. Imports the GPG signing key (`F911AB184317630C59970973E363C90F8F1B6217`) from `keyserver.ubuntu.com` HTTPS endpoint with fallback to alternative keyservers.
3. Writes a signed `sources.list.d` entry (no `software-properties-common` or Python needed).
4. Runs `apt-get update && apt-get install git`.

If the running Ubuntu codename is not yet in the PPA (e.g. a brand-new Ubuntu release), the installer falls back to the distro's base `apt` repository with a warning.

The PPA is **not activated on Debian**, even though Debian uses `apt`. The PPA packages are Ubuntu-specific. On Debian, use `version=stable` (base repo) or `method=source`.

### Package Version Pinning (`package + <x.y.z>`)

The version string is passed to `ospkg__run` via a version-pinned package manifest object. The ospkg library translates it to the PM-native syntax automatically:

| Package manager | Generated install argument |
|---|---|
| apt / apk / pacman / zypper | `git=<version>` |
| dnf / yum | `git-<version>` |
| brew | `git@<version>` |

Supply a plain upstream version string (e.g. `"2.34.1"`) — do not add PM-specific suffixes yourself.

The specified version must exist in the currently configured repositories. On macOS (Homebrew), the `git` formula does not support installing arbitrary past versions this way; use `method=source` with a specific version string for version pinning on macOS.

### Source Build Component Flags (`no_flags`)

`no_flags` accepts a space-separated list of component names (case-insensitive) to exclude from the source build. Each name maps to a `NO_<FLAG>=YesPlease` make variable:

| Value | Make variable | What it disables |
|---|---|---|
| `perl` | `NO_PERL=YesPlease` | `git-svn`, `git-send-email`, `git-archimport`, `git-cvsimport`, gitweb; removes Perl runtime requirement |
| `python` | `NO_PYTHON=YesPlease` | `git-p4`; removes Python runtime requirement |
| `tcltk` | `NO_TCLTK=YesPlease` | `gitk`, `git-gui`; removes Tcl/Tk requirement |
| `gettext` | `NO_GETTEXT=YesPlease` | i18n/translations; removes `gettext`/`libintl` build dependency; output is English-only |

Multiple values can be combined: `"no_flags": "perl tcltk"`. Unknown values are logged as warnings and ignored.

**Alpine note:** `NO_GETTEXT=YesPlease` is always set on Alpine regardless of `no_flags`, because Alpine's musl libc doesn't include a full gettext implementation. Specifying `gettext` in `no_flags` on Alpine is harmless (deduplicated automatically).

`no_flags` is silently ignored when `method=package`.

### Make Flags Passthrough (`make_flags`)

`make_flags` accepts a space-separated list of `KEY=VALUE` pairs that are appended verbatim as the **last arguments** on every `make` invocation for source builds. Because they appear after all computed flags (including those generated by `no_flags`), they can override any computed flag or set additional make variables not otherwise covered by the API.

Example — disable curl and force OpenSSL for SHA256:
```jsonc
"make_flags": "NO_CURL=YesPlease OPENSSL_SHA256=YesPlease"
```

- No validation is performed; unknown keys are silently ignored by make.
- Word-splitting by the shell separates the pairs; no quoting within the value is supported.
- Silently ignored when `method=package`.

### Source Build Tag Resolution

For `source + latest`: fetches up to 100 tags from the GitHub Tags API, sorts by version numerically, and selects the highest — including release candidates (e.g. `2.48.0-rc1`).

For `source + stable`: same fetch, but filters to tags matching `^v[0-9]+\.[0-9]+\.[0-9]+$` before sorting, which excludes all `-rc*` and other pre-release suffixes.

For `source + <x.y.z>`: no API call; the tarball URL is constructed directly from the `version` string.

### Source Build — Package Manager Registration (Debian/Ubuntu)

After a successful source build, the installer registers git with the OS package manager by creating and installing a minimal `equivs` dummy `.deb` package named `git` at the source-built version. This means that a later `apt install foo` — where `foo` declares a `Depends: git` — will see git as already satisfied and will not pull in a second, older distro git to `/usr/bin/git`.

The dummy package places no binary on disk; the source-built `$PREFIX/bin/git` (default `/usr/local/bin/git`) remains the only git binary. The `equivs` tool is removed after the dummy package is installed.

This step is intentionally non-fatal: if the registration fails for any reason, a warning is logged and installation continues. PATH ordering (`/usr/local/bin` before `/usr/bin`) still guarantees the correct binary is used in normal usage.

On non-Debian/Ubuntu platforms (Alpine, RHEL, macOS) no equivalent mechanism exists; PATH ordering is the sole guarantee there.

### Source Build on macOS

Source builds on macOS are fully supported. `method=source` is always explicit with this API design, so there are no surprises. Requirements:

- Xcode CLT must be installed (`xcode-select --install`). The installer checks for CLT and exits with a clear error if absent.
- Additional Homebrew packages (`make`, `openssl`, `pcre2`, `gettext`) are declared in `dependencies/source-build.yaml` and installed automatically.

### `if_exists` Behaviour

The check runs against any `git` in PATH before any package manager operations.

**Version short-circuit:** if `git --version` reports a version matching the resolved target version, installation is skipped silently and exits 0, regardless of the `if_exists` setting. This prevents unnecessary reinstalls when the correct version is already present.

**Policy values (applied only when versions differ or git is found with no version match):**

| Value | Behaviour |
|---|---|
| `skip` (default) | Log a notice and exit 0. Re-running this feature on a container where the correct git version is already installed is always a no-op. |
| `fail` | Log an error and exit non-zero. |
| `reinstall` | Detect how git is currently installed, remove it, then install fresh using the requested `method`. |
| `update` | Upgrade to the resolved target version. Detects the existing install method and compares it to the requested `method`; see **`update` behaviour** below. |

**`reinstall` detection logic:** the installer queries the native package manager to determine whether the found `git` binary is package-managed:

| Platform | Detection command |
|---|---|
| Debian/Ubuntu | `dpkg -S "$(command -v git)"` |
| Alpine | `apk info --who-owns "$(command -v git)"` |
| RHEL/Fedora | `rpm -qf "$(command -v git)"` |
| macOS | `brew list git 2>/dev/null` |

If the existing git is **package-managed**: it is removed via the package manager (`apt-get remove git`, `apk del git`, `dnf remove git`, `brew remove git`).

If the existing git is **source-installed** (detection returns nothing): all installed files under `$PREFIX` are removed (`$PREFIX/bin/git*`, `$PREFIX/share/git-core`, `$PREFIX/share/man/man?/git*`, `$PREFIX/lib/git-core`), and the equivs dummy package is purged on Debian/Ubuntu if registered.

After removal, the normal installation flow proceeds with the selected `method`.

**`update` behaviour:**

| Existing method | Requested `method` | Action |
|---|---|---|
| package | package | Re-run `_git__install_package` — the package manager upgrades or downgrades in place. No removal needed. |
| source | source | Rebuild and `make install`. If `$PREFIX` matches the old prefix, binaries are overwritten in place. If `$PREFIX` differs, the old prefix is removed first (same teardown as `reinstall`), then the build installs to the new prefix. |
| package | source | Remove via package manager, then build from source (identical to `reinstall`). |
| source | package | Remove source-installed files and equivs dummy, then install via package manager (identical to `reinstall`). |

The old prefix is derived as `dirname(dirname(command -v git))` — e.g. `/usr/local/bin/git` → `/usr/local`.

### Source-Only Options

`prefix`, `sysconfdir`, `installer_dir`, `keep_installer`, `no_flags`, `make_flags`, `shell_completions`, and `export_path` are silently ignored when `method=package`. `symlink` is also ignored for `method=package` (git lands in `/usr/bin` which is universally on PATH).

- `prefix="auto"` — resolves to `/usr/local` (root) or `$HOME/.local` (non-root). Explicit paths are validated for writeability; the script exits with a clear error if the path cannot be created.
- `sysconfdir="auto"` — resolves to `/etc` (root) or `$HOME/.config` (non-root). Controls where git reads its system-level `gitconfig`.
- `installer_dir` — cleaned after a successful build; set `keep_installer=true` to preserve for debugging.

### Non-root Source Builds

Running `method=source` as a non-root user is fully supported. With `prefix=auto` and `sysconfdir=auto`, all paths resolve to user-writable locations:

| Component | Root | Non-root |
|---|---|---|
| `prefix` | `/usr/local` | `$HOME/.local` |
| `sysconfdir` | `/etc` | `$HOME/.config` |
| completions (bash) | `/etc/bash_completion.d/` | `$HOME/.local/share/bash-completion/completions/` |
| completions (zsh) | `<zshdir>/completions/` | `$HOME/.zfunc/` |
| PATH export (`auto`) | `shell__system_path_files` | `shell__user_path_files` |
| `symlink` | `/usr/local/bin/git → ${PREFIX}/bin/git` | skipped (cannot write `/usr/local/bin`) |
| system gitconfig | `/etc/gitconfig` | `$HOME/.config/git/config` |
| user gitconfig | targeted users | only `$USER` |

`method=package` on Linux always requires root (package managers require it); on macOS with Homebrew it works as the current user.

### `containerEnv` and `symlink`

The feature sets `containerEnv: { "PATH": "/usr/local/bin:${PATH}" }` so that git is available in all build steps and any non-shell invocation (e.g. `RUN git clone ...`) without relying on shell startup files.

For `method=package`, git lands in `/usr/bin` which is always on PATH — the `containerEnv` entry is harmless.

For `method=source` with the default `prefix=auto`, git is installed to `/usr/local/bin` as root — already covered by `containerEnv`.

For `method=source` with a **custom prefix** (e.g. `prefix=/opt/git`), the binary is at `/opt/git/bin/git`, which is not on the hardcoded `containerEnv` path. With `symlink=true` (the default), the installer creates `/usr/local/bin/git → /opt/git/bin/git` so the `containerEnv` entry still resolves correctly.

`symlink` is silently skipped when:
- `method=package`
- `prefix` resolves to the canonical path (`/usr/local` for root, `$HOME/.local` for non-root)

### Shell Completions (`shell_completions`)

For `method=source`, `git make install` places bash and zsh completion scripts under `$PREFIX/share/git-core/contrib/completion/` but does not install them to the system completion directories. With `shell_completions="bash zsh"` (the default), the installer copies each listed shell's completion file:

| Shell | Source | Root destination | Non-root destination |
|---|---|---|---|
| bash | `$PREFIX/share/git-core/contrib/completion/git-completion.bash` | `/etc/bash_completion.d/git` | `$HOME/.local/share/bash-completion/completions/git` |
| zsh | `$PREFIX/share/git-core/contrib/completion/git-completion.zsh` | `<zshdir>/completions/_git` | `$HOME/.zfunc/_git` |

`<zshdir>` is detected by `shell__detect_zshdir`: `/etc/zsh` on Debian/Ubuntu/Alpine, `/etc` on RHEL/Fedora/macOS. The `completions/` subdirectory is in zsh's `$fpath` on all supported platforms, so `_git` is picked up automatically by `compinit`.

Set `shell_completions=""` to skip this step (e.g. in minimal containers where neither bash-completion nor zsh is present).

Ignored when `method=package` — the package manager installs completions alongside the binary.

### PATH Export (`export_path`)

For `method=source`, `export_path` controls which shell startup files receive `export PATH="$PREFIX/bin:$PATH"` and (when `$PREFIX` is non-standard) `export MANPATH="$PREFIX/share/man:$MANPATH"` blocks.

| Value | Behaviour |
|---|---|
| `"auto"` (default) | Writes to all four system-wide targets via `shell__system_path_files --profile_d install-git.sh`: the `$BASH_ENV` file, `/etc/profile.d/install-git.sh`, the system-wide bashrc, and `<zshdir>/zshenv`. |
| `""` (empty) | Skips all PATH/MANPATH writes entirely. |
| Newline-separated absolute paths | Writes only to the specified files. |

**Coverage by invocation scenario (`auto`):**

| Scenario | Covered by |
|---|---|
| Login interactive (bash/sh/zsh) | `/etc/profile.d/install-git.sh` |
| Non-login interactive bash | System-wide bashrc (`/etc/bash.bashrc` etc.) |
| Non-login interactive zsh | `<zshdir>/zshenv` |
| Docker `RUN` / SSH exec / non-interactive bash | `$BASH_ENV` file (registered in `/etc/environment`) |
| PAM sessions | `/etc/environment` (via `BASH_ENV` registration) |

When `$PREFIX` is `/usr/local`, MANPATH is not written (this prefix is included in the default man path on all supported platforms). For any other prefix, a `MANPATH` export block is appended to the same files.

The export blocks are idempotent — re-running the installer updates the block in place rather than appending duplicates (`shell__sync_block` marker pattern).

### Gitconfig (`default_branch`, `safe_directory`, `system_gitconfig`, `add_*_user_config`, `user_name`, `user_email`, `user_gitconfig`)

The installer writes gitconfig settings after installation is complete. All gitconfig options are independent of `method` — they work the same whether git was installed from a package or built from source.

#### System-level gitconfig

Written to `/etc/gitconfig` (as root) or `$HOME/.config/git/config` (as non-root). The file is created or updated using `git config --file <target_file>` for each key/value, then the freeform `system_gitconfig` block is appended (if non-empty).

| Option | gitconfig key | Notes |
|---|---|---|
| `default_branch` | `init.defaultBranch` | Set to `""` to skip. Default: `"main"`. |
| `safe_directory` | `safe.directory` | Newline-separated for multiple paths. `"*"` trusts all directories (container-friendly). Set to `""` to skip. |
| `system_gitconfig` | (raw block) | Appended verbatim after all other system-level settings. Standard gitconfig section/key/value format. |

**Root note:** As root, these go to `/etc/gitconfig` (or `${SYSCONFDIR}/gitconfig` when `sysconfdir` is set explicitly). As non-root, they go to `$HOME/.config/git/config` — the user-level XDG config path, which git reads in addition to `~/.gitconfig`.

#### Per-user gitconfig

Written to `~/.gitconfig` for each resolved user. The user list is built from the four `add_*_user_config` options: `add_current_user`, `add_remote_user`, `add_container_user` (booleans), and `add_users` (comma-separated explicit usernames). As non-root, only the current user is ever written to; any extra names are ignored with a warning.

Per-user settings are only written when at least one of `user_name`, `user_email`, or `user_gitconfig` is non-empty, **and** at least one of the user-config options resolves to a user.

| Option | gitconfig key | Notes |
|---|---|---|
| `user_name` | `user.name` | Written via `git config --file <~/.gitconfig>`. Set to `""` to skip. |
| `user_email` | `user.email` | As above. Set to `""` to skip. |
| `user_gitconfig` | (raw block) | Appended verbatim after `user_name`/`user_email`. |

#### Container pattern

For a typical devcontainer with `remoteUser: "vscode"` that needs all repositories trusted and a default branch:

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-git": {
      "safe_directory": "*",
      "default_branch": "main",
      "add_remote_user": true,
      "user_name": "Dev User",
      "user_email": "dev@example.com"
    }
  }
}
```

### Platform Summary

| Platform | `package + latest` | `package + stable` | `source` |
|---|---|---|---|
| Ubuntu LTS | PPA | apt (base repo) | kernel.org tarball |
| Debian | apt | apt | kernel.org tarball |
| RHEL / Fedora | dnf | dnf | kernel.org tarball |
| Alpine | apk | apk | kernel.org tarball |
| macOS | Homebrew (latest) | Homebrew | kernel.org tarball + Xcode CLT |
| Arch / Manjaro | pacman (rolling) | pacman | kernel.org tarball |




