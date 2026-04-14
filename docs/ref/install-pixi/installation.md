# Installation Reference — install-pixi

Pixi is an open-source, cross-platform package and project manager for conda
and PyPI packages, written in Rust by prefix.dev. It ships as a single
statically-linked binary for Linux (x86_64, aarch64, riscv64gc) and macOS
(x86_64, aarch64/Apple Silicon). No system runtime is required. The canonical
installation method is a shell installer script hosted at
`https://pixi.sh/install.sh`; alternative methods include Homebrew, Winget
(Windows), Scoop (Windows), Windows MSI installer, direct binary download from
GitHub releases, and building from source with Cargo. For devcontainer features
and cross-platform standalone installers targeting Linux and macOS, the
**direct binary download from GitHub Releases** is the recommended approach: it
gives full control over architecture detection, version pinning, and checksum
verification without relying on an external installer script.


## Available Methods

### Method 1 — Official Installer Script (`pixi.sh/install.sh`)

**Supported platforms:** Linux (x86_64, aarch64, riscv64gc), macOS (x86_64,
aarch64); containers and bare-metal.

**Dependencies:** `sh`; `curl` or `wget`; `tar` (optional — falls back to
bare-binary copy if absent); `mktemp`.

**Installation steps:**

```sh
# Latest version:
curl -fsSL https://pixi.sh/install.sh | sh

# Specific version (with or without 'v' prefix — both are handled by the script):
curl -fsSL https://pixi.sh/install.sh | PIXI_VERSION=v0.67.0 sh

# Drop-in system-wide install (suppresses shell-RC modification):
curl -fsSL https://pixi.sh/install.sh | PIXI_BIN_DIR=/usr/local/bin PIXI_NO_PATH_UPDATE=1 bash
```

**Officially documented environment variables** (from
`https://pixi.prefix.dev/latest/installation/`):

| Variable | Default | Effect |
|---|---|---|
| `PIXI_VERSION` | `latest` | Version to install. Accepts `latest` or `vX.Y.Z` / `X.Y.Z`. Script strips then re-adds `v` when building URL. |
| `PIXI_HOME` | `$HOME/.pixi` | Global pixi data directory (environments, configs). Tilde-expansion applied. |
| `PIXI_BIN_DIR` | `$PIXI_HOME/bin` | Directory where the `pixi` binary is placed. |
| `PIXI_ARCH` | `uname -m` | Override detected CPU architecture. |
| `PIXI_NO_PATH_UPDATE` | *(unset)* | If set to any non-empty value, suppresses all shell-RC PATH modifications. |
| `PIXI_DOWNLOAD_URL` | GitHub releases | Override binary/archive download URL (mirrors, air-gapped). |
| `NETRC` | *(unset)* | Path to custom `.netrc` for authenticated downloads. Falls back to `~/.netrc` if present. |
| `TMPDIR` | `/tmp` | Temporary directory for the download. **Note:** the official documentation table incorrectly lists this as `TMP_DIR`, but the installer source code (v0.67.0) uses the standard POSIX `TMPDIR`. This is a confirmed discrepancy between docs and code. |

> **`PIXI_REPOURL` note:** The installer source code also reads `PIXI_REPOURL`
> (default `https://github.com/prefix-dev/pixi`) to construct the download URL.
> However, this variable is **not documented in the official installation docs**
> and should be treated as an installer-internal detail, not a stable public API.
> Our feature exposes `PIXI_DOWNLOAD_URL` (which is officially documented) for
> custom/mirror URLs instead.

**Architecture-to-triple mapping** (from installer source v0.67.0):

| `uname -s` | `uname -m` / `PIXI_ARCH` | Release triple |
|---|---|---|
| `Linux` | `x86_64` | `x86_64-unknown-linux-musl` |
| `Linux` | `aarch64` or `arm64` | `aarch64-unknown-linux-musl` |
| `Linux` | `riscv64` | `riscv64gc-unknown-linux-gnu` |
| `Darwin` | `x86_64` | `x86_64-apple-darwin` |
| `Darwin` | `arm64` or `aarch64` | `aarch64-apple-darwin` |

> **Important:** Linux uses MUSL (statically linked) for x86_64 and aarch64.
> RISC-V Linux uses GNU libc (`riscv64gc-unknown-linux-gnu`), **not** MUSL.
> macOS uses `arm64`/`aarch64` interchangeably — the installer normalizes both to `aarch64`.

**Archive format:** `.tar.gz` (preferred); falls back to bare binary if `tar`
is not available. The installer extracts the `pixi` binary from the archive and
places it into `$PIXI_BIN_DIR`.

**PATH updates made by the installer** when `PIXI_NO_PATH_UPDATE` is unset:

| Calling shell (`$SHELL`) | File modified | Line appended |
|---|---|---|
| `bash` | `~/.bashrc` | `export PATH="${PIXI_BIN_DIR}:$PATH"` |
| `zsh` | `~/.zshrc` | `export PATH="${PIXI_BIN_DIR}:$PATH"` |
| `fish` | `~/.config/fish/config.fish` | `set -gx PATH "${PIXI_BIN_DIR}" $PATH` |
| `tcsh` | `~/.tcshrc` | `set path = ( ${PIXI_BIN_DIR} $path )` |
| unknown | — | warns only |

Guard: `grep -Fxq` — no duplicate line added on re-run.

**Cleanup:** Upstream script uses `mktemp` and removes the temp file in an EXIT
trap. No installer artifact is left behind.

**Idempotency:** Unconditionally overwrites the binary. For idempotency control,
our feature implements an `if_exists` guard.

**Limitation:** The upstream installer does not perform checksum verification.

---

### Method 2 — Direct Binary Download from GitHub Releases (Recommended for this Feature)

**Supported platforms:** same as Method 1.

**Dependencies:** `curl` or `wget`; `tar`; `chmod`; `mktemp`.

**Release assets per version** (`https://github.com/prefix-dev/pixi/releases/tag/vX.Y.Z`):

| Asset | Platform |
|---|---|
| `pixi-x86_64-unknown-linux-musl.tar.gz` | Linux x86_64 |
| `pixi-aarch64-unknown-linux-musl.tar.gz` | Linux ARM64 |
| `pixi-riscv64gc-unknown-linux-gnu.tar.gz` | Linux RISC-V |
| `pixi-x86_64-apple-darwin.tar.gz` | Intel macOS |
| `pixi-aarch64-apple-darwin.tar.gz` | Apple Silicon macOS |
| `pixi-${TRIPLE}.sha256` | SHA-256 checksum **of the `.tar.gz` archive** |

> **Checksum clarity:** The `.sha256` sidecar file contains the SHA-256 hash of
> the corresponding `.tar.gz` archive (not of the extracted binary). Verification
> must happen on the archive *before* extraction.

**Steps:**

```sh
VERSION=0.67.0   # no 'v' prefix used here; it is prepended when building the URL
TRIPLE=x86_64-unknown-linux-musl
TMP_DIR="$(mktemp -d)"
ARCHIVE="$TMP_DIR/pixi.tar.gz"

# 1. Download archive + checksum sidecar
curl -fsSL -o "$ARCHIVE" \
  "https://github.com/prefix-dev/pixi/releases/download/v${VERSION}/pixi-${TRIPLE}.tar.gz"
curl -fsSL -o "$TMP_DIR/pixi.sha256" \
  "https://github.com/prefix-dev/pixi/releases/download/v${VERSION}/pixi-${TRIPLE}.sha256"

# 2. Verify archive checksum BEFORE extraction
# (use lib/checksum.sh in the actual installer — example shows Linux variant only)
sha256sum --check <(echo "$(awk '{print $1}' "$TMP_DIR/pixi.sha256")  $ARCHIVE")

# 3. Extract binary from archive
tar -xzf "$ARCHIVE" -C "$TMP_DIR"
mv "$TMP_DIR/pixi" /usr/local/bin/pixi
chmod +x /usr/local/bin/pixi
rm -rf "$TMP_DIR"
```

**Idempotency:** No built-in conflict detection; caller must implement `if_exists` guard.

---

### Method 3 — Homebrew (macOS and Linux)

```sh
brew install pixi       # install
brew upgrade pixi       # update
```

- **Cannot use `pixi self-update`** for Homebrew-managed installations.
- Not suitable for containers without Homebrew pre-installed; not used in this feature.

---

### Method 4 — Windows-Only Methods (out of scope)

The following official Windows-only installation methods exist but are **out of
scope** for this feature (Linux/macOS only):

- Windows MSI installer (from GitHub releases)
- `winget install prefix-dev.pixi`
- `scoop install main/pixi`

---

### Method 5 — Self-Update (upgrade path)

For pixi installed via the installer script or direct binary download:

```sh
# Update to latest:
pixi self-update

# Update to specific version — NO 'v' prefix (per official CLI reference):
pixi self-update --version 0.67.0
```

Source: [Official CLI — `pixi self-update`](https://pixi.prefix.dev/latest/reference/cli/pixi/self-update/)

> **Constraint:** `pixi self-update` does **not** work for pixi installed via
> Homebrew, conda, mamba, paru, or other package managers.

---

### Method 6 — Shell Completion Setup

Pixi provides zero-dependency completion generation via `pixi completion --shell <type>`.
Supported shells on Linux/macOS (PowerShell is supported by pixi but is Windows-focused
and out of scope for this feature):

```sh
# Bash (add to ~/.bashrc or system-wide bashrc):
eval "$(pixi completion --shell bash)"

# Zsh (add to ~/.zshrc or system-wide zshrc):
eval "$(pixi completion --shell zsh)"

# Fish (source in fish config or conf.d):
pixi completion --shell fish | source

# Nushell (append to config.nu; no eval wrapper):
pixi completion --shell nushell

# Elvish (add to rc.elv):
eval (pixi completion --shell elvish)
```

The `eval` pattern is idempotent (re-evaluated on each shell start). For
persistent installation, use `shell__write_block` to write an idempotent
marker-fenced block to the target file.

---

### Method 7 — Checksum Verification Detail

Pixi publishes `.sha256` sidecar files alongside each release archive. The
content format is `<sha256hex>  <filename>` (standard `sha256sum` output).

**URL format:**
```
https://github.com/prefix-dev/pixi/releases/download/v${VERSION}/pixi-${TRIPLE}.sha256
```

**Implementation using `lib/checksum.sh`:**

```bash
checksum__verify_sha256_sidecar "$ARCHIVE" "$SHA256_FILE"
```

This function reads the first whitespace-separated field from `$SHA256_FILE`
and calls `checksum__verify_sha256` which uses `sha256sum` (Linux) or
`shasum --algorithm 256` (macOS) transparently.

**Skip condition:** When `download_url` is set to a custom URL (mirror or
air-gapped), skip checksum verification and emit a `⚠️ warning`.


## Results

**Recommended installation method: Direct binary download (Method 2).**

The official installer script (Method 1) is not used as the primary method for
the following reasons:

1. **Checksum verification requires the archive.** The `.sha256` sidecar hashes
   the `.tar.gz` archive; verification must happen before extraction. We must
   download the archive ourselves anyway, so there is no advantage to also
   delegating the download to the upstream script.

2. **We already provide all the logic the upstream script offers.** Version
   resolution (`github__latest_tag`), arch/kernel detection (`os__arch`,
   `os__kernel`), PATH management (`shell__export_path`), and completion setup
   (`shell__write_block`) are in our shared library. The upstream script's
   remaining contribution — download + extraction — is trivial to implement.

3. **Simpler, auditable install payload.** No external script is fetched at install
   time; all code lives in version control. Note: version resolution for `latest`
   still calls the GitHub API via `github__latest_tag` (not version-pinned).

**Key implementation decisions:**

1. **Triple detection:** Map `os__kernel` + `os__arch` to the release triple.
   Special cases: `riscv64` arch → `riscv64gc`; RISC-V platform suffix is
   `unknown-linux-gnu` (not `musl`); macOS `arm64` → `aarch64`.

2. **Devcontainer mode (root):** Default `bin_dir=/usr/local/bin`. Always skip
   upstream shell-RC modifications (PATH managed by our feature via `containerEnv`
   or `shell__export_path`).

3. **Standalone mode (non-root/user install):** Default `bin_dir=""` maps to
   `$HOME/.pixi/bin` by convention. The `no_path_update` option controls
   whether a PATH block is written to shell RC files.

4. **Auto no-path-update:** When `bin_dir` is explicitly non-empty, do not
   write shell RC modifications (the user chose an explicit path).

5. **`if_exists` handling:** `skip` (warn + continue), `fail` (exit 1),
   `uninstall` (remove binary + reinstall), `update` (`pixi self-update
   --version X.Y.Z` without `v` prefix per CLI docs).

6. **Version match skip:** If the installed version already matches the resolved
   target version, silently skip regardless of `if_exists` value.

7. **Shell completion:** Use `shell__write_block` with a consistent marker for
   idempotent writes; detect system-wide vs user-scoped target files based on
   whether the caller is root.

**Limitations:**
- `pixi self-update` (`if_exists=update`) only works for installer-/binary-managed
  pixi. Document this clearly; no autodetection of Homebrew-managed pixi.
- Checksum verification is skipped when `download_url` is overridden; warn clearly.
- `github__latest_tag` hits the GitHub API; rate-limiting applies for
  unauthenticated requests (60 req/hour). `GITHUB_TOKEN` is respected.


## Devcontainer Usage

### `.pixi` Volume Mount (Case-Sensitivity Requirement)

#### Why the mount is needed

When using pixi inside a devcontainer running on a macOS or Windows host, the
workspace directory is bind-mounted from the host filesystem, which is
**case-insensitive** by default (APFS on macOS, NTFS on Windows). Certain conda
packages distribute files whose names differ only in case (e.g. `License` vs
`LICENSE`). Extracting such packages into a case-insensitive filesystem causes
one file to silently overwrite the other, producing broken environments.

This affects only directories that reside on the workspace bind-mount.
`PIXI_HOME` (default `~/.pixi`) lives inside the container's own overlay
filesystem (ext4, always case-sensitive) because the container's `$HOME` is
never bind-mounted from the host — so `PIXI_HOME` does not need a volume mount.

#### Why the mount target is fixed

Pixi always reads and writes its workspace state under `<workspace>/.pixi`,
relative to the directory containing `pixi.toml`. There is no env var or CLI
flag that redirects the `.pixi` directory itself to an arbitrary path. (The
`detached-environments` config option can redirect only the `envs/`
subdirectory; pixi still creates and reads config and metadata under
`<workspace>/.pixi` regardless.) The mount target is therefore necessarily
`${containerWorkspaceFolder}/.pixi` — anything else would be ignored by pixi.

Source: [workspace environment docs](https://pixi.prefix.dev/latest/workspace/environment/) — *"All Pixi environments are by default located in the `.pixi/envs` directory of the workspace."*; [configuration docs](https://pixi.prefix.dev/latest/reference/pixi_configuration/) — config priority table lists `your_project/.pixi/config.toml` as the highest-priority config file location.

#### The mount

The fix is to mount a Docker **named volume** at `${containerWorkspaceFolder}/.pixi`.
Named volumes are always on a Linux (ext4) filesystem regardless of host OS —
and therefore case-sensitive. The `install-pixi` feature automatically adds
this mount:

```jsonc
// Automatically added by the feature:
"mounts": [
  {
    "source": "${localWorkspaceFolderBasename}-pixi",
    "target": "${containerWorkspaceFolder}/.pixi",
    "type": "volume"
  }
]
```

This creates a named Docker volume (e.g. `sysset-pixi` for a workspace folder
named `sysset`) and mounts it at `<workspace>/.pixi` inside the container.
The volume persists across container rebuilds, so environments do not need to
be reinstalled on every rebuild.

Source: [pixi VSCode Devcontainer Docs](https://pixi.prefix.dev/latest/integration/editor/vscode/#devcontainer-extension)

#### `PIXI_HOME` and `PIXI_BIN_DIR` are independent of the mount

`PIXI_HOME` and `PIXI_BIN_DIR` are separate from the volume mount and from each
other:

- **`PIXI_HOME`** (default `$HOME/.pixi`) — where pixi stores global
  environments (`pixi global install`), global config, and shell completions for
  globally installed tools. Controlled by the `home_dir` option. Lives on the
  container filesystem; not on the workspace bind-mount; does not require a
  volume mount.
- **`PIXI_BIN_DIR`** (default `$PIXI_HOME/bin`) — where the pixi binary is
  placed by the upstream installer. Controlled by the `bin_dir` option. In this
  feature the default is `/usr/local/bin` (explicitly set), so it is independent
  of `PIXI_HOME` in practice.
- **`<workspace>/.pixi`** — workspace environments and project-level config.
  Not configurable via any env var; always relative to `pixi.toml`. This is what
  the volume mount addresses.

`PIXI_BIN_DIR` defaults to `$PIXI_HOME/bin`, so if only `PIXI_HOME` is
changed without explicitly setting `PIXI_BIN_DIR`, the bin directory follows.
They are fully independent only when both are set explicitly.

Source: [Official Env Var Reference](https://pixi.prefix.dev/latest/reference/environment_variables/) — documents `PIXI_HOME` and `PIXI_BIN_DIR` defaults.

### `postCreateCommand` — Environment Ownership

Because the feature installer runs as `root`, the `.pixi` volume mount is
initially owned by `root`. If the devcontainer runs as a non-root user (e.g.
`vscode`), the user cannot write to `.pixi` without a chown fix. Add to
`devcontainer.json`:

```jsonc
"postCreateCommand": "sudo chown ${localEnv:USER} .pixi && pixi install"
```

Or, more robustly using the devcontainer remote user variable:

```jsonc
"postCreateCommand": "sudo chown ${containerEnv:_REMOTE_USER} ${containerWorkspaceFolder}/.pixi"
```

The `pixi install` call (from the official docs example) auto-installs
environments declared in `pixi.toml`. Omit it if your project doesn't have a
`pixi.toml`, or if you prefer to run `pixi install` manually.

## References

- [Official Installation Docs](https://pixi.prefix.dev/latest/installation/) —
  Primary reference for documented installation methods, env vars, PATH update
  behavior, autocompletion setup, and update instructions.
- [Upstream installer source v0.67.0](https://raw.githubusercontent.com/prefix-dev/pixi/main/install/install.sh) —
  Confirms `TMPDIR` (not `TMP_DIR`) and `PIXI_REPOURL` as installer-internal.
  Authoritative for triple detection and archive extraction logic.
- [Official `pixi self-update` CLI Docs](https://pixi.prefix.dev/latest/reference/cli/pixi/self-update/) —
  Confirms `--version x.y.z` syntax without `v` prefix (example: `pixi self-update --version 0.46.0`).
- [GitHub releases — v0.67.0](https://github.com/prefix-dev/pixi/releases/tag/v0.67.0) —
  Confirmed release asset naming: `pixi-${TRIPLE}.tar.gz` and
  `pixi-${TRIPLE}.sha256` (hash of archive).
- [Official Env Var Reference](https://pixi.prefix.dev/latest/reference/environment_variables/) —
  Documents `PIXI_HOME` (global data dir), `PIXI_BIN_DIR` (binary location, defaults to `$PIXI_HOME/bin`), `PIXI_CACHE_DIR`, `RATTLER_AUTH_FILE`.
- [Official Configuration Reference](https://pixi.prefix.dev/latest/reference/pixi_configuration/) —
  Documents `detached-environments` (redirects `envs/` subdirectory only, not `.pixi` itself); confirms `<workspace>/.pixi/config.toml` as the highest-priority config location (priority 6).
- [install-miniforge feature](../../src/install-miniforge/) — Sister feature;
  reference for `if_exists`, dual-mode parsing, `shell__export_path`, and
  `ospkg__run` patterns.
- [lib/checksum.sh](../../lib/checksum.sh) — `checksum__verify_sha256_sidecar`
  for cross-platform archive verification.
- [lib/shell.sh](../../lib/shell.sh) — `shell__write_block` for completion setup;
  `shell__export_path` for PATH management.
- [lib/github.sh](../../lib/github.sh) — `github__latest_tag` for latest version
  resolution.
- [pixi VSCode Devcontainer Docs](https://pixi.prefix.dev/latest/integration/editor/vscode/#devcontainer-extension) —
  Official pixi devcontainer guide; source for the `.pixi` volume mount
  pattern and `postCreateCommand` chown requirement.
