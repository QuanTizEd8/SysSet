# Feature Reference

`mise` (pronounced "meez", short for the French culinary term *mise-en-place*; formerly named `rtx`) is a polyglot developer-environment manager written in Rust. It combines three capabilities in a single binary: (1) a **dev-tool version manager** that installs and switches between versions of languages and CLI tools (a drop-in replacement for `asdf`, `nvm`, `pyenv`, `rbenv`, etc., and backward-compatible with `asdf` plugins and `.tool-versions` files); (2) an **environment-variable manager** that loads/unloads project-scoped environment variables when you enter a directory (comparable to `direnv`); and (3) a **task runner** (comparable to `make` or `just`).[^homepage][^repo] Tools are declared in a per-project `mise.toml` (or a legacy `.tool-versions`) file and installed on demand from a large registry of backends (asdf, aqua, ubi, vfox, cargo, npm, pipx, go, and built-in "core" tools).[^configuration]

This document concerns installing the **`mise` binary itself** (the concern of the `install-mise` feature), not the downstream tools that `mise` can subsequently manage. Once `mise` is installed, it must be **activated** in the shell (or its **shims** directory placed on `PATH`) before the tools it manages become available.[^getting-started][^shims]

- **Homepage**: https://mise.jdx.dev (the domain `https://mise.en.dev` is an alias serving the same site; the installer is served from `https://mise.run`)
- **Source Code**: https://github.com/jdx/mise
- **Documentation**: https://mise.jdx.dev
- **Latest Release**: 2026.7.7 (as of 2026-07-17)[^releases]

> **Versioning note (CalVer):** mise uses **calendar versioning** in the form `YYYY.M.PATCH` (e.g. `2026.7.7` = the 7th release of July 2026). Git tags and release artifacts are prefixed with `v` (`v2026.7.7`), but `mise version` reports the number without the `v`. There is no semantic-versioning "major/minor" contract; every release is expected to be a safe upgrade.[^releases] References to `MISE_VERSION` accept either form (`v2026.7.7` or `2026.7.7`); the installer strips the leading `v`.[^install-script]

## Tool Architecture

- **Single self-contained binary.** `mise` is distributed as one statically-linkable executable named `mise`, written in **Rust** and licensed **MIT**.[^repo] It has **no external runtime dependencies** — it does not require a JVM, Node.js, Python, or any interpreter to run. There is no client/server or daemon component; `mise` is a standalone CLI that runs to completion on each invocation. (This is a fundamental contrast with tools like Nix: there are no system users, no groups, and no background service to install or manage.)
- **Prebuilt binaries for glibc and musl.** For Linux, mise publishes both glibc-linked (`mise-<ver>-linux-<arch>.tar.gz`) and musl-linked (`...-<arch>-musl.tar.gz`) builds; the installer auto-selects `-musl` when it detects a musl libc.[^install-script][^releases] The Linux binaries are otherwise self-contained. macOS builds are provided for x64 and arm64. Windows builds (`.zip`/`.exe`) are also published but are out of scope for a POSIX-focused feature.[^releases]
- **Two integration models.** After the binary is installed, mise integrates with the shell in one of two mutually-exclusive ways:[^getting-started][^shims]
  1. **PATH activation** — a shell hook installed via `eval "$(mise activate <shell>)"` re-computes `PATH` and environment variables on every prompt. This is the recommended mode for interactive shells and supports all mise features (env vars, hooks, `mise x`).
  2. **Shims** — small launcher executables placed in a shims directory (`~/.local/share/mise/shims`) that is added to `PATH`. Shims work without a per-prompt hook (better for non-interactive IDEs, CI, and scripts) but do **not** support all features (e.g. mise-defined env vars are only visible to mise-managed tools, most hooks don't fire, and `which` resolves to the shim rather than the real binary).[^shims]
- **Configuration is TOML-based, hierarchical, and trust-gated.** Tool/version/env declarations live in `mise.toml` files discovered by walking up the directory tree, merged with a global `~/.config/mise/config.toml` and an optional system `/etc/mise/config.toml`.[^configuration] Config files that could execute code are subject to a **trust** check before mise will parse them.[^trust]
- **XDG-compliant directory layout.** State is split across data, config, cache, and state directories following the XDG Base Directory spec, each overridable by an environment variable (see [Environment Variables](#environment-variables)).[^directories]
- **Extensible backends.** mise installs downstream tools through pluggable backends (asdf plugins, aqua, ubi, vfox, and language ecosystems). These are exercised at tool-install time, not when installing mise itself, but they influence some runtime dependencies (e.g. `git` for asdf plugins).[^configuration]

## Installation Methods

mise offers many installation channels. For a portable, cross-distro feature the two most relevant are the **installer script** (`https://mise.run`) and the **standalone binary download** from GitHub Releases, because both install a single self-contained binary with no root requirement and no system integration. A third, closely related option — the **bootstrap script** (`mise generate bootstrap`) — is the official mechanism for a vendored, version-pinned `./bin/mise`. Native OS package managers (apt, dnf/yum, zypper, apk, pacman, Homebrew, snap, MacPorts, Nix) and language package managers (Cargo, npm) are also fully supported and documented below.[^install-docs]

The installer script, bootstrap script, and binary download are functionally equivalent — they all place a single self-contained binary and differ only in automation and pinning. Package-manager installs additionally wire up system paths and enable the OS updater, but disable mise's built-in `self-update`.[^self-update]

### Installer Script (`mise.run`)

This is the recommended and most portable method. `curl https://mise.run | sh` downloads a POSIX `sh` script that detects the OS/arch/libc, downloads the matching release tarball, verifies its SHA-256 checksum, extracts the `mise` binary, and installs it to `~/.local/bin/mise` (by default). It requires **no root** for a user-local install.[^install-docs][^install-script]

The script is served identically from `https://mise.run` and `https://mise.jdx.dev/install.sh` (byte-for-byte identical, verified 2026-07-17). In addition, **shell-specific endpoints** `https://mise.run/{bash,zsh,fish}` run the same install **and then idempotently append an activation line** to the corresponding rc file (see [Activation Scripts](#activation-scripts)).[^install-docs][^run-shell-endpoints]

#### Supported Platforms

Determined by the installer's `get_os`/`get_arch` functions and the set of published release assets:[^install-script][^releases]

- **macOS** (`Darwin`): x86_64 (Intel) and arm64 (Apple Silicon).
- **Linux**: x86_64 (`x64`), aarch64/arm64 (`arm64`), and armv7l (`armv7`) — each available in both **glibc** and **musl** variants. musl is auto-detected via `ldd` (so **Alpine is supported**). See the musl override note below for how to force musl.
- **Android/Termux**: detected via `uname -o = Android`; always uses the musl build (also gated on `ldd` being present).
- Any other OS (`uname -s` not `Darwin`/`Linux`) → the script exits with `unsupported OS`. Any other architecture → `unsupported architecture`, with a suggestion to build from source via `cargo install --locked mise`.

> **Architecture caveat — armv6 is not built for current releases.** The interactive install page lists `linux-armv6`/`linux-armv6-musl` among architectures,[^install-docs] but the installer script's `get_arch` maps only `x86_64`, `aarch64`/`arm64`, and `armv7l`, and the `v2026.7.7` release publishes **no `armv6` assets** (only `x64`, `arm64`, `armv7`, each ± `-musl`).[^install-script][^releases] Treat armv6 as **unsupported** by the binary/script path for current releases; such systems must build from source with Cargo.

> **musl override precondition (verified against the script).** The `MISE_INSTALL_MUSL=1` override is evaluated **inside** the `if type ldd` guard in `get_arch` (lines 57–82). Therefore it only takes effect when an `ldd` binary is present. On a **linker-less minimal image** (scratch/distroless/BusyBox-without-`ldd`) `MISE_INSTALL_MUSL` is **silently ignored** and the glibc build is chosen — which cannot run on a musl-only system. The reliable override that works with or without `ldd` is `MISE_INSTALL_ARCH=<arch>-musl` (e.g. `x64-musl`), because `arch="${MISE_INSTALL_ARCH:-$(get_arch)}"` (line 280) bypasses `get_arch` entirely. Note that `MISE_LIBC`/`libc` is a **runtime** setting read by the *installed* mise binary when it installs downstream tools; the **installer script does not read `MISE_LIBC` at all** (it reads only `MISE_INSTALL_MUSL` and `MISE_INSTALL_ARCH`).[^install-script][^docker]

#### Dependencies

##### Common Dependencies

- **`sh`** (POSIX shell) — to run the installer.[^install-script]
- **`curl` or `wget`** — to download the tarball (and, for non-current versions, to fetch `SHASUMS256.txt`). The script prefers `curl`; falls back to `wget`.[^install-script]
- **`tar`** — to extract the tarball.[^install-script]
- **`shasum` or `sha256sum`** — for checksum verification. If neither exists the script aborts with an error.[^install-script]
- **`ldd`** — used (if present) to detect musl vs glibc by inspecting `/bin/ls`. If `ldd` is absent, libc is not detected and the glibc build is chosen (and `MISE_INSTALL_MUSL` is ignored — see the override note above).[^install-script]

##### Platform-Specific Dependencies

- **When downloading a `.tar.zst` tarball** (the default when supported): a **`zstd`** binary. The script uses `.tar.zst` only when `tar_supports_zstd` is true — i.e. `zstd` is installed **and** `tar` is either `bsdtar` or GNU `tar ≥ 1.31` (BusyBox `tar` is explicitly excluded). Otherwise it falls back to `.tar.gz`, which needs only a standard `tar` + `gzip`. If `.tar.zst` is selected but `tar` can't decompress it, the script pipes through `zstd -d -c`.[^install-script] **Implication:** on a minimal image with only BusyBox `tar` and no `zstd`, the script correctly downloads `.tar.gz`; no extra dependency is required.
- **musl images (e.g. Alpine):** no additional dependency; the `-musl` build is self-contained.

#### Installation Steps

The one-liner:

```sh
curl https://mise.run | sh
```

Behind that, the script performs (in `install_mise`):[^install-script]

1. **Resolve version.** `version = ${MISE_VERSION:-<baked-in current version>}` (leading `v` stripped). The CDN always serves a script whose baked-in version is the latest release, so an unset `MISE_VERSION` installs the latest.
2. **Detect OS/arch/ext.** `os` via `uname -s`; `arch` via `uname -m` + musl detection; `ext` = `tar.zst` if supported else `tar.gz` (forced to `tar.gz` for `v2024*`).
3. **Choose download URL.**
   - If `MISE_VERSION` ≠ the script's current version, **or** `MISE_INSTALL_FROM_GITHUB=1`: download from GitHub Releases — `https://github.com/jdx/mise/releases/download/v${version}/mise-v${version}-${os}-${arch}.${ext}`.
   - Else if `MISE_TARBALL_URL` is set: use it verbatim.
   - Else: download from the CDN — `https://mise.jdx.dev/v${version}/mise-v${version}-${os}-${arch}.${ext}`.
4. **Download** to a `mktemp -d` directory (progress bar via `curl -#fLo`).
5. **Verify checksum.** For the current version, checksums are **hard-coded** in the script; for any other version, the script downloads `SHASUMS256.txt` from the GitHub release. Verification runs `<checksum-line> | shasum -c` (or `sha256sum -c`). A mismatch aborts (the pipeline runs under `set -e`).
6. **Extract.** Into another `mktemp -d`; `tar --no-same-owner -xf` (or `zstd -d -c | tar -xf -` when needed). The tarball contains `mise/bin/mise`.
7. **Place the binary.** `mkdir -p "$install_dir"`, `rm -f "$install_path"`, then `mv mise/bin/mise "$install_path"`. If run as **root**, it first `chown 0:0` + `chmod 755` the binary. Default `install_path` = `$HOME/.local/bin/mise`.
8. **Clean up** the temp directories.
9. **Print activation help** for the detected `$SHELL` (unless `MISE_INSTALL_HELP=0`). **The base `mise.run` script does not modify any rc file or `PATH` itself** — it only prints the command the user should run. (The shell-specific `mise.run/{bash,zsh,fish}` endpoints are the exception: they *do* append an activation line — see [Activation Scripts](#activation-scripts).)[^install-script][^run-shell-endpoints]

To pin a specific version (recommended for reproducible/feature use):

```sh
curl https://mise.run | MISE_VERSION=v2026.7.7 sh
```

To install system-wide (requires write access to the target dir, i.e. root):

```sh
curl https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh
```

#### Installation Verification

```sh
# The binary reports its version (CalVer, os-arch, and build date):
~/.local/bin/mise version
# e.g. 2026.7.7 linux-x64 (2026-07-15)

mise --version        # equivalent

# Full environment self-check (activation, shims, PATH, config):
mise doctor           # alias: mise dr
```

`mise doctor` diagnoses whether activation/shims and `PATH` are wired correctly and reports the resolved directories and config.[^getting-started] The installer additionally performs SHA-256 verification automatically as part of installation (see step 5).[^install-script] Signature verification is available but **not** performed by the script (see [Notes and Best Practices](#notes-and-best-practices-installer-script)).

#### Configuration Options

##### Version Selection

- **Latest:** leave `MISE_VERSION` unset and fetch the script fresh from `https://mise.run` (its baked-in version is the latest release).[^install-script]
- **Pinned:** set `MISE_VERSION=v2026.7.7` (or without the `v`). Any value other than the script's baked-in current version switches the download source to GitHub Releases and verifies against that release's `SHASUMS256.txt`. **A feature that vendors/caches the script but wants a specific version must set `MISE_VERSION` explicitly**, otherwise it silently gets whatever version was baked into the cached script.[^install-script]
- The version string must correspond to a real release tag (`https://github.com/jdx/mise/releases`).[^releases]

##### Installation Path

- `MISE_INSTALL_PATH` selects the **full binary path** (not a directory). Default: `$HOME/.local/bin/mise`. If the path is an existing directory the script errors and asks for a file path.[^install-script]
- Related overrides: `MISE_INSTALL_OS`, `MISE_INSTALL_ARCH`, `MISE_INSTALL_EXT` override the detected values (useful for cross/edge environments; `MISE_INSTALL_ARCH=<arch>-musl` is also the reliable musl override — see above).[^install-script]

##### User Targeting

- **User-local (default):** installs to `$HOME/.local/bin/mise`; no root needed. Each user gets their own binary and their own data/config under `$HOME`.[^install-script][^directories]
- **System-wide:** set `MISE_INSTALL_PATH=/usr/local/bin/mise` (or another root-owned dir). Only the binary is shared; each user still has their own `~/.local/share/mise` data unless `MISE_DATA_DIR`/`MISE_SYSTEM_DATA_DIR` are configured. There are **no system users/groups/daemon** to create.[^docker]

##### Required Privileges

- **None** for the default user-local install (writes only under `$HOME/.local/bin`).[^install-script]
- **Root** only when `MISE_INSTALL_PATH` points to a root-owned location (e.g. `/usr/local/bin`). When run as root, the script sets `chown 0:0` + `chmod 755` on the binary.[^install-script]

##### Tool-Specific Configurations

Environment variables understood by the **installer script**:[^install-script]

| Variable | Purpose | Default |
|---|---|---|
| `MISE_VERSION` | Version to install (`v2026.7.7` or `2026.7.7`) | baked-in current (latest) |
| `MISE_INSTALL_PATH` | Full path for the installed binary | `$HOME/.local/bin/mise` |
| `MISE_INSTALL_OS` | Override detected OS token (`linux`/`macos`) | auto (`uname -s`) |
| `MISE_INSTALL_ARCH` | Override detected arch token (`x64`, `arm64`, `armv7`, ±`-musl`); bypasses `get_arch` | auto (`uname -m`) |
| `MISE_INSTALL_EXT` | Override tarball extension (`tar.zst`/`tar.gz`) | auto |
| `MISE_INSTALL_MUSL` | Force musl build (`1`/`true`) — **only honored when `ldd` is present** | auto-detected |
| `MISE_INSTALL_FROM_GITHUB` | Force download from GitHub Releases instead of CDN (`1`/`true`) | unset (CDN for current version) |
| `MISE_TARBALL_URL` | Fully custom tarball URL (used only for the current version and when `FROM_GITHUB` is unset) | unset |
| `MISE_INSTALL_SKIP_IF_EXISTS` | Skip install if the binary at `MISE_INSTALL_PATH` is already the requested version (`1`/`true`) | unset |
| `MISE_INSTALL_HELP` | Set to `0` to suppress the post-install activation hint | printed |
| `MISE_DEBUG` | Verbose debug logging (`1`/`true`) | off |
| `MISE_QUIET` | Suppress non-error output (`1`/`true`) | off |

> Note: these govern the **installer**. Runtime `mise` behavior (directories, trust, libc-for-tools, auto-install, etc.) is governed by a separate, larger set of `MISE_*` variables and `settings` — see [Environment Variables](#environment-variables) and [Configuration Files](#configuration-files).

#### Post-Installation Steps and Cleanup

##### PATH Setup

The base installer **does not** touch `PATH` or any rc file. Two things must be arranged post-install:[^getting-started][^install-script]

1. **Make the `mise` binary reachable.** With shell activation this is unnecessary — `mise activate` prepends the binary's own directory to `PATH`. Otherwise (e.g. non-interactive), either invoke it by full path (`~/.local/bin/mise`) or add `~/.local/bin` to `PATH`.[^getting-started]
2. **Choose an integration model** (activation *or* shims), below.

##### Configuration Files

mise reads (highest precedence first, discovered by walking up from the CWD, then global, then system):[^configuration]

- Project: `mise.local.toml`, `mise.toml`, `mise/config.toml`, `.mise/config.toml`, `.config/mise.toml`, `.config/mise/config.toml`, `.config/mise/conf.d/*.toml`, and asdf-compat `.tool-versions`. Environment/OS variants like `mise.<env>.toml` / `mise.windows.toml` are supported.
- Global: `~/.config/mise/config.toml` (i.e. `$MISE_CONFIG_DIR/config.toml`).
- System: `/etc/mise/config.toml`.

Key sections: `[tools]` (tool→version), `[env]` (project env vars), `[settings]` (mise behavior), `[tasks.*]`, `[plugins]`, `[alias]`.[^configuration] Installing the **mise binary** creates none of these; they are authored by the user/project. A feature that pre-declares tools would write `[tools]`/`[settings]` into the global or system config.

**Trust model (important for automation).** Before parsing a `mise.toml` that could execute code, mise checks whether the file is **trusted**. "Safe" configs — only `min_version`, `[tools]` with plain version strings, and `[tasks]` without templates/tool-options — load without prompting. Otherwise mise may prompt, skip the config, or fail with an untrusted-config error when it cannot prompt; **in detected CI it assumes trust unless paranoid mode is enabled.** Trust is granted with `mise trust [path]` (or `mise trust --all`), or by listing paths in `MISE_TRUSTED_CONFIG_PATHS`.[^trust]

##### Environment Variables

Persistent runtime directories (XDG-based), each overridable:[^directories][^docker]

| Directory | Env var | Default (Linux) |
|---|---|---|
| Config | `MISE_CONFIG_DIR` | `${XDG_CONFIG_HOME:-~/.config}/mise` |
| Data (tools, plugins, shims, installs) | `MISE_DATA_DIR` | `${XDG_DATA_HOME:-~/.local/share}/mise` |
| Cache | `MISE_CACHE_DIR` | `${XDG_CACHE_HOME:-~/.cache}/mise` (macOS: `~/Library/Caches/mise`) |
| State | `MISE_STATE_DIR` | `${XDG_STATE_HOME:-~/.local/state}/mise` |
| System data (for `mise install --system`) | `MISE_SYSTEM_DATA_DIR` | `/usr/local/share/mise` |
| Extra shared install dirs | `MISE_SHARED_INSTALL_DIRS` | unset (`:`-separated) |

Other frequently-relevant runtime variables: `MISE_TRUSTED_CONFIG_PATHS` (auto-trust), `MISE_YES` (assume "yes" to prompts — e.g. makes `mise implode` non-interactive), `MISE_LIBC`/`libc` (**runtime** setting; forces `musl`/`glibc`/`gnu` when the *installed* mise can't detect the linker while installing **downstream tools** — it does **not** influence the installer script's own binary selection), `MISE_ENV`/`MISE_ENV_FILE`, `MISE_LOG_LEVEL`, `MISE_<TOOL>_VERSION`.[^docker][^configuration][^directories]

##### Activation Scripts

The runtime shell hook is generated by `mise activate <shell>` and installed into the shell rc file. Add exactly one of these per shell (using the binary's path if it isn't yet on `PATH`):[^getting-started]

```sh
# bash — append to ~/.bashrc
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc

# zsh — append to ${ZDOTDIR:-~}/.zshrc
echo 'eval "$(~/.local/bin/mise activate zsh)"' >> "${ZDOTDIR-$HOME}/.zshrc"

# fish — append to ~/.config/fish/config.fish
echo '~/.local/bin/mise activate fish | source' >> ~/.config/fish/config.fish
```

The hook re-evaluates `PATH`/env on each prompt. As a convenience, the shell endpoints `https://mise.run/{bash,zsh,fish}` install mise **and** perform this rc edit automatically: e.g. `mise.run/bash` appends `eval "$(<install_path> activate bash)" # added by https://mise.run/bash` to `~/.bashrc` (creating it if missing), guarded by a `grep -qF "# added by https://mise.run/bash"` marker so re-runs are idempotent.[^run-shell-endpoints]

For **non-interactive** contexts (CI, IDEs, Dockerfiles) prefer **shims** or `mise exec`/`mise x` instead of activation:[^ci][^shims]

```sh
# shims: add the shims dir to PATH (no per-prompt hook)
echo 'eval "$(mise activate bash --shims)"' >> ~/.bash_profile
# or manually:
export PATH="$HOME/.local/share/mise/shims:$PATH"
```

Shims are regenerated automatically on tool install/update/remove; `mise reshim` forces a rebuild.[^shims]

##### Shell Completions

Completions are **not** installed by `mise activate`; generate and place them explicitly. **`mise completion` requires the `usage` CLI to be present** — install it first with `mise use -g usage` if missing:[^completion][^install-docs]

```sh
mise use -g usage   # prerequisite for `mise completion`

# bash (requires the bash-completion package; create the dir first):
mkdir -p ~/.local/share/bash-completion/completions/
mise completion bash --include-bash-completion-lib > ~/.local/share/bash-completion/completions/mise
# zsh:
mise completion zsh  > /usr/local/share/zsh/site-functions/_mise
# fish:
mise completion fish > ~/.config/fish/completions/mise.fish
# powershell:
mise completion powershell >> $PROFILE
```

Supported shells: `bash`, `zsh`, `fish`, `powershell`. For bash, `--include-bash-completion-lib` is required for completions to work (otherwise the bash-completion library must be sourced separately). Some package-manager installs ship completion scripts automatically.[^completion][^install-docs]

##### Cleanup

The installer removes its temporary download/extract directories automatically; no manual cleanup is needed after a successful install.[^install-script]

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- **Self-managed installs (script / bootstrap / binary download):** `mise self-update` updates the binary in place by fetching the latest GitHub release; `mise self-update <VERSION>` targets a specific version; `--yes/-y` skips confirmation, `--force/-f` re-installs even if current, `--no-plugins` skips plugin updates. Alternatively re-run the installer with a new `MISE_VERSION`.[^self-update]
- Because the binary is a single file, downgrading is just installing an older version over the current one (no migration needed).

##### Uninstallation

`mise implode` is the built-in uninstaller. Per its source it removes, with confirmation (or unconditionally under `MISE_YES`/`settings.yes`): the **state**, **data**, and **cache** directories, the **mise binary** itself (`MISE_BIN`), and the **system data dir** (`/usr/local/share/mise`). The **config dir is skipped by default** and only removed with `--config`. `--dry-run`/`-n` previews the removals. It does **not** revert rc-file activation/shims lines or completion files — those must be removed manually.[^implode]

```sh
mise implode --dry-run     # preview
mise implode               # remove data/state/cache + binary + system data
mise implode --config      # also remove ~/.config/mise
```

##### Idempotency

- Re-running the installer **overwrites** the binary by default (`rm -f "$install_path"` then `mv`), so a repeat run reinstalls the requested version. Setting `MISE_INSTALL_SKIP_IF_EXISTS=1` makes it **skip** the download/extract when the binary already at `MISE_INSTALL_PATH` reports the requested version — the recommended flag for idempotent feature runs.[^install-script]
- The base install is otherwise stateless: no partial-install detection or lockfiles; it does not modify rc files, so repeated runs cannot accumulate duplicate activation lines (the feature, not the base script, owns that; the `mise.run/{bash,zsh,fish}` endpoints have their own marker-based idempotency).[^install-script][^run-shell-endpoints]

#### Details

The installer is a ~370-line POSIX `sh` script (`set -eu`).[^install-script] Salient implementation points a re-implementation must preserve:

- **libc detection:** `type ldd` present → then check `MISE_INSTALL_MUSL`, else Android (`uname -o = Android`) → musl, else `ldd /bin/ls | grep musl`. **If `ldd` is absent the entire block is skipped** (glibc build, `MISE_INSTALL_MUSL` ignored). Use `MISE_INSTALL_ARCH=<arch>-musl` to force musl regardless of `ldd`.
- **arch mapping:** `x86_64→x64`, `aarch64|arm64→arm64`, `armv7l→armv7`, each suffixed `-musl` when applicable; anything else → `unsupported_arch` (suggests `cargo install --locked mise`).
- **zstd gating:** `.tar.zst` only when `zstd` exists and `tar` is bsdtar or GNU ≥ 1.31, excluding BusyBox; else `.tar.gz`. When a `.tar.zst` is fetched but `tar` can't read it, it pipes `zstd -d -c "$file" | tar --no-same-owner -xf -`.
- **checksums:** static/embedded for the current release; fetched from `SHASUMS256.txt` for others. A `# TODO: verify with minisign or gpg if available` comment marks that **only SHA-256 is checked** — there is no signature verification in the script.
- **download source precedence:** current-version → CDN `mise.jdx.dev/v<ver>/...`; non-current or `MISE_INSTALL_FROM_GITHUB` → GitHub Releases; `MISE_TARBALL_URL` overrides the CDN case only.
- **tarball layout:** contains `mise/bin/mise`; installed via `mv mise/bin/mise "$install_path"`.
- **root handling:** as root, `chown 0:0` + `chmod 755` before moving.
- **help printer:** `after_finish_help` only *prints* the shell-specific `mise activate` snippet; suppress with `MISE_INSTALL_HELP=0`.

#### Notes and Best Practices (Installer Script)

- **Always pipe over HTTPS and pin `MISE_VERSION` for reproducibility.** The script self-verifies SHA-256 but performs **no signature check**. For higher assurance, verify the release artifacts out-of-band using mise's **minisign** public key `RWTC3g8W3z4RZK3V3qv7fa1QY4JEWyBtqIHW+85QlJpZc5yG+uNYNBSZ` (key id `64113EDF160FDEC2`) against `SHASUMS256.txt.minisig`, or the **GPG** release key (RSA-4096 fingerprint `24853EC9F655CE80B48E6C3A8B81C9D17413A06D`, `mise releases <release@mise.jdx.dev>`, valid 2024-01-02 → 2028-01-02) against `SHASUMS256.asc`/`install.sh.sig`. The same GPG key signs the apt/rpm repositories.[^install-script][^gpg-key][^minisign][^install-docs]
- **musl on linker-less images:** do **not** rely on `MISE_INSTALL_MUSL` on scratch/distroless/busybox-without-`ldd` bases — it is gated on `ldd`. Use `MISE_INSTALL_ARCH=<arch>-musl` at install time. `MISE_LIBC=musl` addresses a different, later problem (which libc the *installed* mise assumes when installing downstream tools).[^install-script][^docker]
- **Activation is the feature's responsibility.** Since the base script never edits rc files, the feature must install the chosen integration (activation line or shims-on-PATH). The `mise.run/{bash,zsh,fish}` endpoints are one ready-made option for the activation edit.
- Package-manager installs **disable `self-update`**; the script/bootstrap/binary installs enable it.[^self-update]

### Bootstrap Script (`mise generate bootstrap`)

`mise generate bootstrap` emits a self-contained script that **downloads and executes a pinned mise** on first use — designed for projects whose contributors may not have mise installed. It is the officially recommended way to vendor a version-pinned `./bin/mise` into a repo (and is referenced by the CI guide).[^bootstrap][^ci]

#### Supported Platforms

Same matrix as the Installer Script (it downloads the same release artifacts).[^bootstrap]

#### Dependencies

Requires an existing `mise` binary to *generate* the script; the generated script itself needs the same runtime deps as the installer (`sh`, `curl`/`wget`, `tar`, `shasum`/`sha256sum`).[^bootstrap][^install-script]

#### Installation Steps

```sh
mise generate bootstrap --version v2026.7.7 --write ./bin/mise
chmod +x ./bin/mise
./bin/mise install     # downloads the pinned mise into the data dir if absent, then runs
```

Flags: `-V/--version <VERSION>` (pin the mise version), `-w/--write <FILE>` (write + chmod +x instead of stdout), `-l/--localize` (sandbox `MISE_DATA_DIR`/`MISE_CACHE_DIR` into a project `.mise` dir), `--localized-dir <DIR>` (default `.mise`).[^bootstrap]

#### Installation Verification

`./bin/mise version` / `./bin/mise doctor`, same as the Installer Script.[^getting-started]

#### Configuration Options

- **Version Selection:** `-V/--version`. **Installation Path:** the generated wrapper path (`-w`); the actual binary lands in the data dir (or the localized `.mise` dir). **User Targeting / Required Privileges:** user-local; no root. **Tool-Specific Configurations:** honors the same runtime `MISE_*` variables as any mise install; `--localize` isolates data/cache per-project.[^bootstrap]

#### Post-Installation Steps and Cleanup

Same activation/shims/completions/config considerations as the Installer Script; the wrapper is committed to the repo, so there is nothing to clean up.[^getting-started]

#### Changing Versions and Uninstallation

Re-generate with a new `--version`, or edit the pinned version in the committed wrapper. Remove the wrapper (and, if `--localize` was used, the `.mise` dir) to uninstall.[^bootstrap]

#### Idempotency

The generated wrapper is a no-op once the pinned mise is present; `./bin/mise install` only downloads when the binary is absent.[^bootstrap]

#### Notes and Best Practices

Best for reproducible, contributor-friendly project setups where mise itself should be pinned alongside the toolset. Not primarily a system-install mechanism.[^bootstrap][^ci]

### Standalone Binary Download (GitHub Releases)

Downloading the release binary directly is the lowest-level method and is exactly what the existing `devcontainers-extra/features/mise` feature does (it delegates to the generic `gh-release` feature, downloading the `.tar.gz` asset and placing the `mise` binary on `PATH`).[^dc-extra-feature][^install-docs]

#### Supported Platforms

Same matrix as the installer script (the assets are the same files). Two asset shapes are published per target: a **bare executable** (`mise-v<ver>-<os>-<arch>`) and **archives** (`.tar.gz`, `.tar.xz`, `.tar.zst`). Archives unpack to `mise/bin/mise`.[^releases]

#### Dependencies

##### Common Dependencies

- `curl`/`wget` to download; nothing beyond a downloader if grabbing the bare executable.[^releases]

##### Platform-Specific Dependencies

- If using an archive: `tar` plus the matching decompressor (`gzip` for `.tar.gz`, `xz` for `.tar.xz`, `zstd` for `.tar.zst`).[^releases]

#### Installation Steps

```sh
# Bare executable (simplest, no tar/zstd needed):
curl -fL https://github.com/jdx/mise/releases/download/v2026.7.7/mise-v2026.7.7-linux-x64 \
  -o /usr/local/bin/mise
chmod +x /usr/local/bin/mise

# Or an archive:
curl -fLO https://github.com/jdx/mise/releases/download/v2026.7.7/mise-v2026.7.7-linux-x64.tar.gz
tar -xzf mise-v2026.7.7-linux-x64.tar.gz      # -> mise/bin/mise
install -m 0755 mise/bin/mise /usr/local/bin/mise
```

Pick `-musl` assets for musl systems (`mise-v2026.7.7-linux-x64-musl...`).

#### Installation Verification

Same as the installer script (`mise version`, `mise doctor`). To verify integrity manually, download `SHASUMS256.txt` from the same release and check, then optionally verify `SHASUMS256.txt.minisig`/`.asc` signatures with the keys in the Installer Script notes.[^releases][^minisign][^gpg-key]

#### Configuration Options

##### Version Selection

Choose the release tag in the download URL.[^releases]

##### Installation Path

Wherever you have write access (user-local `~/.local/bin` needs no root; `/usr/local/bin` needs root).

##### User Targeting

User-local or system-wide, decided by the chosen path.

##### Required Privileges

None for user-local; root for system paths.

##### Tool-Specific Configurations

None at download time; runtime config (directories, trust, env vars, `MISE_LIBC`) is identical to any other install — see the Installer Script's [Environment Variables](#environment-variables) and [Configuration Files](#configuration-files).

#### Post-Installation Steps and Cleanup

##### PATH Setup / Activation Scripts / Shims / Shell Completions

Identical to the Installer Script — arrange PATH/activation or shims yourself and install completions with `mise completion` (needing `usage`).[^getting-started][^completion]

##### Configuration Files / Environment Variables

Identical to the Installer Script.[^configuration][^directories]

##### Cleanup

Remove the downloaded archive after extracting.

#### Changing Versions and Uninstallation

`mise self-update` works (this is a self-managed install). Uninstall with `mise implode` plus manual removal of the binary if it lives outside the data dir, and manual removal of rc/shim lines.[^self-update][^implode]

#### Idempotency

Re-downloading overwrites the binary. There is no built-in skip; a feature must compare `mise version` to the desired version to short-circuit.

#### Details

The tarball layout (`mise/bin/mise`) and per-target asset naming mirror what the installer script consumes; this method simply removes the detection/checksum automation.[^releases][^install-script]

#### Notes and Best Practices

- The bare executable avoids any `tar`/`zstd` dependency and is the most robust choice for minimal images.
- The `gh-release`-based devcontainers-extra feature offers only a `version` option and performs **no activation, no shims, and no version pinning beyond the tag** — a DevFeats feature should improve on this by owning activation, completions, and idempotency.[^dc-extra-feature]

### OS Native Package Managers

mise is packaged natively for most platforms. These installs are **system-wide** (require root), place the binary on the system `PATH` (e.g. `/usr/bin/mise`), and are updated by the OS package manager — but **`mise self-update` is disabled** for them.[^install-docs][^self-update] Runtime activation/shims/completion/config behavior is identical to the script install.

#### Supported Platforms

Debian/Ubuntu (apt), Fedora/RHEL/CentOS/Amazon Linux (dnf/yum), openSUSE/SLES (zypper), Alpine (apk), Arch (pacman), macOS/Linux (Homebrew), Linux (snap), macOS (MacPorts), and Nix.[^install-docs]

#### Dependencies

Whatever the distro's package manager requires; the manual apt-repo method additionally needs `gpg`/`wget`/`ca-certificates` to add the key and repo.[^install-docs]

#### Installation Steps

The official installation page currently documents these commands (apt shows the PPA and extrepo paths; the manual keyring repo below is reconstructed from the still-live signed repository and is **not** listed on the current page):[^install-docs]

- **Debian/Ubuntu (apt):**
  - PPA (Ubuntu 26.04+): `sudo add-apt-repository -y ppa:jdxcode/mise && sudo apt update && sudo apt install -y mise`.[^install-docs]
  - `extrepo` (Debian 11+/Ubuntu 22.04+): `sudo apt install -y extrepo && sudo extrepo enable mise && sudo apt update && sudo apt install -y mise`. **Caveat:** with extrepo you cannot pin `MISE_VERSION` or `MISE_INSTALL_PATH`.[^install-docs][^docker]
  - Manual signed apt repository (reconstructed — the repo `https://mise.jdx.dev/deb stable main` is live for `amd64`/`arm64`, GPG-signed by the release key):[^deb-repo][^gpg-key]
    ```sh
    apt update && apt install -y gpg sudo wget curl ca-certificates
    install -dm 755 /etc/apt/keyrings
    wget -qO - https://mise.jdx.dev/gpg-key.pub | gpg --dearmor | tee /etc/apt/keyrings/mise-archive-keyring.gpg >/dev/null
    echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.gpg arch=$(dpkg --print-architecture)] https://mise.jdx.dev/deb stable main" \
      | tee /etc/apt/sources.list.d/mise.list
    apt update && apt install -y mise
    ```
- **Fedora/RHEL/CentOS (dnf):** COPR (Fedora 41+, CentOS Stream 9+, RHEL 10+): `dnf copr enable jdxcode/mise && dnf install mise` (RHEL/Alma/Rocky 9 use `dnf copr enable jdxcode/mise centos-stream+epel-next-9`).[^install-docs]
- **RHEL 8 / CentOS Stream 8 / Amazon Linux 2 (yum):** `yum install -y yum-utils && yum-config-manager --add-repo https://mise.jdx.dev/rpm/mise.repo && yum install -y mise` (repo `baseurl=https://mise.jdx.dev/rpm`, `gpgcheck=1`, gpgkey `https://mise.jdx.dev/gpg-key.pub`).[^install-docs][^rpm-repo]
- **openSUSE/SLES (zypper):** `sudo wget https://mise.jdx.dev/rpm/mise.repo -O /etc/zypp/repos.d/mise.repo && sudo zypper refresh && sudo zypper install mise`.[^install-docs][^rpm-repo]
- **Alpine (apk):** `apk add mise` (Alpine community repository must be enabled).[^install-docs]
- **Arch (pacman):** `sudo pacman -S mise` (official `extra` repository).[^install-docs]
- **Homebrew (macOS/Linux):** `brew install mise` (formula `mise`).[^install-docs][^brew]
- **snap:** `sudo snap install mise --classic`.[^install-docs]
- **MacPorts:** `sudo port install mise`.[^install-docs]
- **Nix:** `nix-env -iA mise` (nixpkgs 24.05+), or import `mise-flake.packages.${system}.mise`. **NixOS compiles mise from source by default**; for precompiled binaries, enable [`nix-ld`](https://github.com/Mic92/nix-ld) and disable the `all_compile` setting.[^install-docs]

#### Installation Verification

`mise version` / `mise doctor`, identical to the script install.[^getting-started]

#### Configuration Options

##### Version Selection

Generally **not pinnable** — the repos serve the latest build (this is why package installs are less suitable for reproducible feature builds than the script with `MISE_VERSION`).

##### Installation Path

System paths (e.g. `/usr/bin/mise`), fixed by the package.

##### User Targeting

System-wide (all users).

##### Required Privileges

Root (package installation).

##### Tool-Specific Configurations

None at install time; runtime configuration identical to other installs.

#### Post-Installation Steps and Cleanup

Activation/shims/completions/config are identical to the Installer Script; some packages install completion scripts automatically.[^getting-started][^completion] No temp cleanup is required (handled by the package manager).

#### Changing Versions and Uninstallation

- **Upgrade:** the system package manager (`apt upgrade`, `dnf update`, etc.). `mise self-update` is unavailable.[^self-update]
- **Uninstall:** via the package manager (`apt remove mise`, `dnf remove mise`, `pacman -Rns mise`, `brew uninstall mise`, `snap remove mise`, `apk del mise`, `port uninstall mise`, `nix-env -e mise`). Note that running `mise implode` afterward will also delete the **binary** (`MISE_BIN`) even though it is package-manager-owned, leaving the package database inconsistent — prefer the package manager for the binary and use `mise implode` only if you also want the data/state/cache gone.[^implode]

#### Idempotency

The package manager no-ops if the latest is already installed.

#### Details

The apt repo (`deb stable main`, `amd64`/`arm64`) and the rpm repo (`gpgcheck=1`) are both signed by the release GPG key `24853EC9F655CE80B48E6C3A8B81C9D17413A06D`.[^deb-repo][^rpm-repo][^gpg-key]

#### Notes and Best Practices

Package installs auto-update with the system and are convenient, but **cannot pin an exact version** and **disable `self-update`** — prefer the script/bootstrap/binary method when reproducibility matters.[^self-update][^install-docs]

### Language Package Managers (Cargo, npm)

#### Supported Platforms

- **Cargo:** anywhere a Rust toolchain runs — the documented fallback for architectures without prebuilt binaries (e.g. armv6, riscv64).[^install-docs][^install-script]
- **npm:** anywhere Node.js/npm runs and a prebuilt mise binary exists for the platform.[^install-docs]

#### Dependencies

- **Cargo:** a Rust toolchain (`cargo`, `rustc`) and a C toolchain/OpenSSL for the native build — unless using `cargo binstall`, which downloads a prebuilt binary.[^install-docs]
- **npm:** Node.js and npm.[^install-docs]

#### Installation Steps

```sh
# Cargo (build from source):
cargo install --locked mise
# Faster, prebuilt via cargo-binstall:
cargo install cargo-binstall && cargo binstall mise
# Bleeding edge:
cargo install mise --git https://github.com/jdx/mise --branch main

# npm (installs a prebuilt mise binary via a wrapper package):
npm install -g mise
npx mise exec python@3.11 -- python script.py   # try without a global install
```

The npm package `mise` ships a **precompiled binary**, not a Node.js library (legacy package name: `@jdxcode/mise`).[^install-docs]

#### Installation Verification

`mise version` / `mise doctor`.[^getting-started]

#### Configuration Options

##### Version Selection

`cargo install --locked mise@<version>` (or `--version`); `npm install -g mise@<version>`.

##### Installation Path / User Targeting / Required Privileges

Cargo installs to `~/.cargo/bin` (user-local, no root); npm global installs to the npm prefix (root only if the prefix is root-owned).

##### Tool-Specific Configurations

None at install time; runtime configuration identical to other installs.

#### Post-Installation Steps and Cleanup

Activation/shims/completions/config identical to the Installer Script.[^getting-started][^completion]

#### Changing Versions and Uninstallation

Re-run `cargo install`/`npm install -g` for a new version (not `mise self-update`); uninstall with `cargo uninstall mise` / `npm uninstall -g mise`, plus `mise implode` for data/state/cache.[^implode]

#### Idempotency

`cargo install` rebuilds/replaces; `npm install -g` replaces. Neither skips by default.

#### Notes and Best Practices

Cargo is the canonical route for unsupported architectures; `cargo binstall` avoids a full source build. npm is convenient inside Node projects but adds a Node.js dependency for a tool that otherwise has none.[^install-docs]

## Dev Container Setup

mise is well-suited to containers/devcontainers, but the integration model matters. Guidance distilled from mise's own Docker/CI cookbooks:[^docker][^ci]

1. **Install the binary system-wide and expose shims on `PATH`.** The canonical Dockerfile:[^docker]
   ```dockerfile
   FROM debian:13-slim
   RUN apt-get update \
     && apt-get -y --no-install-recommends install sudo curl git ca-certificates build-essential \
     && rm -rf /var/lib/apt/lists/*
   SHELL ["/bin/bash", "-o", "pipefail", "-c"]
   ENV MISE_DATA_DIR="/mise"
   ENV MISE_CONFIG_DIR="/mise"
   ENV MISE_CACHE_DIR="/mise/cache"
   ENV MISE_INSTALL_PATH="/usr/local/bin/mise"
   ENV PATH="/mise/shims:$PATH"
   RUN curl https://mise.run | sh
   ```
   Here `PATH="$MISE_DATA_DIR/shims:$PATH"` gives every (including non-interactive) shell access to managed tools without an rc hook.

2. **Pre-install tools so they survive a mounted home directory.** Devcontainers frequently bind-mount the user's home, which would *shadow* tools installed to `~/.local/share/mise/installs` during the image build. Install them to the **system** dir instead — `mise install --system node@26 python@3.15` writes to `/usr/local/share/mise/installs` (outside `$HOME`), and every user's mise picks them up automatically; user-installed versions still take priority.[^docker]

3. **Trust in CI/containers.** mise assumes trust for configs when it detects CI (unless paranoid mode). Otherwise pre-authorize project configs with `mise trust`/`mise trust --all` or `MISE_TRUSTED_CONFIG_PATHS` so `mise install`/`mise x` don't stall on an untrusted-config prompt.[^trust][^ci]

4. **Prefer `mise exec`/`mise x` (or shims) over `mise activate` for build/CI steps**; activation's per-prompt hook is designed for interactive shells. Run `mise install` to provision the toolset declared in config, then `mise x -- <cmd>`.[^ci]

5. **libc on minimal bases.** On distroless/busybox/scratch bases, `MISE_INSTALL_MUSL=1` only works if `ldd` is present; otherwise set `MISE_INSTALL_ARCH=<arch>-musl` at install time so the installer selects the musl binary. Separately, `MISE_LIBC=musl` (runtime) tells the installed mise which libc to assume when it installs **downstream tools**.[^install-script][^docker]

6. **extrepo caveat.** The `extrepo enable mise` path is clean for Debian/Ubuntu images but forfeits `MISE_VERSION`/`MISE_INSTALL_PATH` control.[^docker]

7. **Existing feature precedent.** `ghcr.io/devcontainers-extra/features/mise` installs mise by delegating to the `gh-release` feature (binary onto `PATH`, single `version` option, `installsAfter` gh-release) — it does **not** set up activation, shims, completions, or data-dir strategy. The official `devcontainers/features` collection has **no** mise feature.[^dc-extra-feature]

## Plugins and Extensions

mise is itself an extensibility platform; "plugins/extensions" here means the **backends and plugins mise uses to install downstream tools**, plus editor integrations. These are runtime concerns and do not affect installing the mise binary, but they inform dependencies and options a feature may surface:[^configuration]

- **Backends / plugins:** core (built-in) tools, **asdf** plugins (git-based; require `git`), **aqua**, **ubi**, **vfox**, and language ecosystems (`cargo:`, `npm:`, `pipx:`, `go:`, `gem:`, etc.). Plugin/tool metadata is fetched from a registry; installing tools reaches out to many external registries/hosts.[^configuration]
- **Software verification for tools:** for `aqua` tools, mise natively verifies Cosign/Minisign signatures, SLSA provenance, and GitHub attestations (toggle with `MISE_AQUA_COSIGN`, `MISE_AQUA_SLSA`, `MISE_AQUA_GITHUB_ATTESTATIONS`, `MISE_AQUA_MINISIGN`). A `minimum_release_age` setting can quarantine brand-new versions to reduce supply-chain risk.[^security]
- **Editor/IDE integration:** mise documents IDE integration and there is a community VS Code extension; because IDEs often don't run the activation hook, the **shims** directory is the recommended `PATH` entry for editors.[^ide][^shims]

## References

[^homepage]: [mise — Homepage & Overview](https://mise.jdx.dev). Official site describing mise as "dev tools, env vars, task runner" and its asdf/direnv/make-replacement positioning.

[^repo]: [jdx/mise — GitHub Repository](https://github.com/jdx/mise). Source of truth for the project; confirms Rust implementation, MIT license, and the `mise`/former-`rtx` identity. Repo metadata (language `Rust`, license `MIT`, description "dev tools, env vars, task runner") retrieved via the GitHub API on 2026-07-17.

[^releases]: [jdx/mise — Releases / GitHub Releases API](https://github.com/jdx/mise/releases). Latest release `v2026.7.7` (published 2026-07-15), retrieved via `api.github.com/repos/jdx/mise/releases/latest` on 2026-07-17. Asset list confirms per-target archives (`.tar.gz`/`.tar.xz`/`.tar.zst`), bare executables, `SHASUMS256.txt(.asc/.minisig)`, and CalVer tagging; confirms **no armv6 assets** for the current release.

[^install-docs]: [mise — Installing mise](https://mise.jdx.dev/installing-mise.html). Official installation matrix: the `mise.run` script, apt (PPA + extrepo), dnf/yum (COPR/rpm repo), zypper, apk, pacman, Homebrew, snap, MacPorts, Nix, Cargo, npm, and Windows methods, plus shell-activation snippets, the architecture list, and the Autocompletion section (which states `mise completion` requires `usage`, installable via `mise use -g usage`).

[^install-script]: [mise — Installer Script Source](https://mise.run) (identical to https://mise.jdx.dev/install.sh; downloaded and read in full 2026-07-17). ~370-line POSIX `sh` script; source of every claim about OS/arch/libc detection (incl. the `MISE_INSTALL_MUSL` gating inside `if type ldd` at lines 57–82 and `MISE_INSTALL_ARCH` bypass at line 280), zstd gating, download-source precedence, SHA-256-only verification, `MISE_*` installer variables, default install path `$HOME/.local/bin/mise`, root chown/chmod, and the print-only activation help.

[^run-shell-endpoints]: [mise — `https://mise.run/bash` (and `/zsh`, `/fish`)](https://mise.run/bash) (fetched and read 2026-07-17). These endpoints run the standard install and then call `setup_bash_activation`, which appends `eval "$(<install_path> activate bash)" # added by https://mise.run/bash` to `~/.bashrc` (creating it if absent), guarded by a `grep -qF "# added by https://mise.run/bash"` idempotency marker.

[^bootstrap]: [mise — `mise generate bootstrap` (CLI)](https://mise.jdx.dev/cli/generate/bootstrap.html) (raw: `docs/cli/generate/bootstrap.md`, read 2026-07-17). Generates a script that downloads+executes a pinned mise; flags `-l/--localize`, `-V/--version`, `-w/--write`, `--localized-dir` (default `.mise`); canonical usage `mise generate bootstrap >./bin/mise && chmod +x ./bin/mise && ./bin/mise install`.

[^getting-started]: [mise — Getting Started](https://mise.jdx.dev/getting-started.html). Shell-activation lines for bash/zsh/fish, the fact that `~/.local/bin` need not be on `PATH` (activation self-adds it), and verification via `mise --version` / `mise doctor`.

[^directories]: [mise — Directory Structure](https://mise.jdx.dev/directories.html). Default paths and controlling env vars for config/data/cache/state directories and the XDG fallbacks (incl. macOS cache under `~/Library/Caches/mise`); shims/installs/plugins live under the data dir.

[^shims]: [mise — Shims](https://mise.jdx.dev/dev-tools/shims.html). Default shims dir `~/.local/share/mise/shims` (Windows `%LOCALAPPDATA%\mise\shims`), `mise activate <shell> --shims`, manual `PATH` export, `mise reshim`, and shims' limitations vs PATH activation.

[^configuration]: [mise — Configuration](https://mise.jdx.dev/configuration.html). Config-file names/precedence and discovery, global `~/.config/mise/config.toml` and system `/etc/mise/config.toml`, `[tools]`/`[env]`/`[settings]` sections, and backend/registry model.

[^trust]: [mise — `mise trust` (CLI)](https://mise.jdx.dev/cli/trust.html) (raw: `docs/cli/trust.md`, read 2026-07-17). Trust model: which configs are "safe" and load without prompting, CI-assumes-trust behavior, paranoid mode, `mise trust`/`--all`/`--untrust`/`--ignore`, and `MISE_TRUSTED_CONFIG_PATHS`.

[^completion]: [mise — `mise completion` (CLI)](https://mise.jdx.dev/cli/completion.html) (raw: `docs/cli/completion.md`, read 2026-07-17) and the installing-mise "Autocompletion" section.[^install-docs] Shells `bash|zsh|fish|powershell`, the `usage` prerequisite (`mise use -g usage`), the `--include-bash-completion-lib` requirement (and bash-completion package) for bash, and canonical install paths.

[^self-update]: [mise — `mise self-update` (CLI)](https://mise.jdx.dev/cli/self-update.html). Updates the binary from GitHub Releases; explicitly **not available when installed via a package manager**; flags `--yes`, `--force`, `--no-plugins`, and optional `[VERSION]`.

[^implode]: [mise — `mise implode` (CLI)](https://mise.jdx.dev/cli/implode.html) and [`src/cli/implode.rs`](https://github.com/jdx/mise/blob/main/src/cli/implode.rs) (both read 2026-07-17). Source confirms removal of `STATE`, `DATA`, `CACHE` dirs, the `MISE_BIN` binary, and the system data dir, with config skipped unless `--config`; `--dry-run` previews; prompts unless `settings.yes`/`MISE_YES`.

[^ci]: [mise — Continuous Integration](https://mise.jdx.dev/continuous-integration.html). CI guidance: install via `mise.run` or `mise generate bootstrap`, run `mise install`, prefer `mise exec`/`mise x` (or shims) over `mise activate`.

[^docker]: [mise — Cookbook: Docker](https://mise.jdx.dev/mise-cookbook/docker.html) (raw: `docs/mise-cookbook/docker.md`, read 2026-07-17). Canonical container Dockerfile (system-wide install, `MISE_DATA_DIR`/`CONFIG`/`CACHE`, `MISE_INSTALL_PATH=/usr/local/bin/mise`, shims on `PATH`), `mise install --system` → `/usr/local/share/mise/installs` surviving home-dir mounts, `MISE_SYSTEM_DATA_DIR`/`MISE_SHARED_INSTALL_DIRS`, the `MISE_LIBC` runtime override for tool installs, and the extrepo caveat.

[^rpm-repo]: [mise — RPM repo definition](https://mise.jdx.dev/rpm/mise.repo) (fetched 2026-07-17). `[mise-repo]` with `baseurl=https://mise.jdx.dev/rpm`, `enabled=1`, `gpgcheck=1`, `gpgkey=https://mise.jdx.dev/gpg-key.pub`.

[^deb-repo]: [mise — APT repo `Release` metadata](https://mise.jdx.dev/deb/dists/stable/Release) (fetched 2026-07-17). Confirms the `deb https://mise.jdx.dev/deb stable main` repository is live, `Architectures: amd64 arm64`, `Components: main`, dated 2026-07-15 (directory listing is disabled, but repo metadata resolves). Note: the manual keyring commands in this document are reconstructed from this live repo; the current installing-mise page documents only the PPA and extrepo apt paths.

[^gpg-key]: [mise — Release GPG public key](https://mise.jdx.dev/gpg-key.pub) (fetched & inspected with `gpg --show-keys` 2026-07-17). RSA-4096, fingerprint `24853EC9F655CE80B48E6C3A8B81C9D17413A06D`, uid `mise releases <release@mise.jdx.dev>`, created 2024-01-02, expires 2028-01-02; signs the apt/rpm repos and `install.sh.sig`.

[^minisign]: [jdx/mise — `minisign.pub`](https://github.com/jdx/mise/blob/main/minisign.pub) (fetched 2026-07-17). mise's release minisign public key `RWTC3g8W3z4RZK3V3qv7fa1QY4JEWyBtqIHW+85QlJpZc5yG+uNYNBSZ` (key id `64113EDF160FDEC2`), used to verify `SHASUMS256.txt.minisig`/`install.sh.minisig`.

[^security]: [mise — Security](https://mise.jdx.dev/security.html) (raw: `docs/security.md`, read 2026-07-17). Native aqua-tool verification (Cosign/Minisign/SLSA/GitHub attestations) with `MISE_AQUA_*` toggles, and the `minimum_release_age` supply-chain setting.

[^brew]: [Homebrew — `mise` formula](https://formulae.brew.sh/formula/mise). Confirms the Homebrew formula name `mise` for macOS/Linux.

[^ide]: [mise — IDE Integration](https://mise.jdx.dev/ide-integration.html). Editor/IDE integration guidance; because IDEs typically don't run the activation hook, the shims directory is the recommended `PATH` entry.

[^dc-extra-feature]: [devcontainers-extra/features — `src/mise`](https://github.com/devcontainers-extra/features/tree/main/src/mise) (`devcontainer-feature.json` + `install.sh` read 2026-07-17). Minimal precedent: delegates to `ghcr.io/devcontainers-extra/features/gh-release` (repo `jdx/mise`, `binaryNames=mise`, `assetRegex='.tar.gz$'`), exposes only a `version` option, `installsAfter` gh-release, and does not configure activation/shims/completions. The official `devcontainers/features` collection has no mise feature.
