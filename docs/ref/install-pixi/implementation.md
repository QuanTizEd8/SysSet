# Implementation Reference — `install-pixi`

## Summary

The installer downloads a pre-built static binary from GitHub Releases, verifies it
against a `.tar.gz.sha256` sidecar file, extracts it to `$PREFIX/bin`, and optionally updates
shell startup files for PATH and completion. It follows the same structural patterns
as `src/install-miniforge/scripts/install.sh`.

All heavy-lifting is delegated to `lib/` functions. The installer's own functions
are pure orchestrators that handle pixi-specific logic (triple detection, version
stripping, self-update invocation) while the shared library handles downloads,
checksums, shell config writes, OS packages, and logging.

---

## Building Blocks

### `os__kernel` — Reused from `lib/os.sh`
- **Responsibility:** Returns `Linux` or `Darwin`.
- **Reuse or New:** Reused. Used by `detect_triple` to form the release triple.

### `os__arch` — Reused from `lib/os.sh`
- **Responsibility:** Returns the normalised CPU architecture string (`x86_64`, `aarch64`, `riscv64`, etc.).
- **Reuse or New:** Reused. Returns `aarch64` for Apple Silicon (`arm64` from `uname -m` is mapped internally by `os__arch`).

### `os__require_root` — Reused from `lib/os.sh`
- **Responsibility:** Exits non-zero with a clear message if the current user is not root.
- **Reuse or New:** Reused.

### `github__latest_tag` — Reused from `lib/github.sh`
- **Responsibility:** Returns the latest release tag (e.g. `v0.67.0`) for a given `owner/repo`.
- **Reuse or New:** Reused. Used by `resolve_pixi_version`.

### `net__fetch_url_file` — Reused from `lib/net.sh`
- **Responsibility:** Downloads a URL to a local file path with retries.
- **Reuse or New:** Reused. Called by `download_pixi` for both the `.tar.gz` archive and the `.tar.gz.sha256` sidecar.

### `checksum__verify_sha256_sidecar` — Reused from `lib/checksum.sh`
- **Responsibility:** Reads the expected hash from a `.tar.gz.sha256` sidecar and calls `checksum__verify_sha256`.
- **Reuse or New:** Reused. Called after both files are downloaded, before extraction.

### `shell__system_path_files` — Reused from `lib/shell.sh`
- **Responsibility:** Prints system-wide shell startup file paths for PATH injection (for root case).
- **Reuse or New:** Reused. Called by `export_path_main` when `EXPORT_PATH="auto"` and running as root.

### `shell__user_path_files` — Reused from `lib/shell.sh`
- **Responsibility:** Prints user-scoped shell startup file paths for PATH export.
- **Reuse or New:** Reused. Called by `export_path_main` when `EXPORT_PATH="auto"` and non-root.

### `shell__detect_bashrc` — Reused from `lib/shell.sh`
- **Responsibility:** Returns the distro-correct system-wide bashrc path.
- **Reuse or New:** Reused. Called by `install_completion` for bash completion (root case).

### `shell__detect_zshdir` — Reused from `lib/shell.sh`
- **Responsibility:** Returns the distro-correct system-wide zsh config directory.
- **Reuse or New:** Reused. Called by `install_completion` for zsh completion (root case).

### `shell__sync_block` — Reused from `lib/shell.sh`
- **Responsibility:** Idempotently writes or removes a named shell block in one or more files.
- **Reuse or New:** Reused. Used by `export_path_main` and `export_pixi_home_main` (multi-file targets).

### `shell__write_block` — Reused from `lib/shell.sh`
- **Responsibility:** Writes or removes a named shell block in a single file.
- **Reuse or New:** Reused. Used by `install_completion` (single-file target per shell type).

### `ospkg__run` — Reused from `lib/ospkg.sh`
- **Responsibility:** Installs OS packages from a manifest file.
- **Reuse or New:** Reused. Used at the top of the main script to install `curl` and `ca-certificates`.

### `logging__setup` / `logging__cleanup` — Reused from `lib/logging.sh`
- **Responsibility:** Configure tee-logging to file and handle cleanup.
- **Reuse or New:** Reused. Called at script setup and in the EXIT trap.

---

## Script-Local Functions

### `__usage__`
- **Responsibility:** Prints help text listing all supported `--flag <value>` arguments and exits 0. Invoked when `--help` is passed in standalone (CLI) mode.
- **Inputs:** none.
- **Notes:** Must stay in sync with the dual-mode argument-parsing block.

### `__cleanup__`
- **Responsibility:** EXIT trap. Removes the `.tar.gz` archive and `.tar.gz.sha256` sidecar from `INSTALLER_DIR` (unless `KEEP_INSTALLER=true`). Removes `INSTALLER_DIR` if it becomes empty. Always calls `logging__cleanup`.
- **Inputs (globals):** `KEEP_INSTALLER`, `ARCHIVE` (path), `SIDECAR` (path), `INSTALLER_DIR`.

### `resolve_bin_dir`
- **Responsibility:** Resolves `PREFIX` from `"auto"` to a concrete path, storing the result back in `PREFIX`.
  - `"auto"` → `/usr/local` when `$(id -u) = 0`, or `$HOME/.pixi` when non-root.
  - `""` (empty) → `$HOME/.pixi` (upstream default, regardless of current user).
  - Any other value → used as-is.
- **Inputs (globals):** `PREFIX`.
- **Outputs (globals):** `PREFIX` (resolved absolute path).
- **Notes:** Must be called before `check_root_requirement` and before any path-based logic.

### `check_root_requirement`
- **Responsibility:** If `PREFIX` is under a system prefix (`/opt/`, `/usr/`, `/var/`, `/srv/`, `/snap/`), call `os__require_root`. Otherwise log that root is not required and proceed.
- **Inputs (globals):** `PREFIX`.

### `resolve_pixi_version`
- **Responsibility:** Resolves `VERSION` to a bare `X.Y.Z` string (no `v` prefix) stored back in `VERSION`.
  - If `VERSION="latest"`, calls `github__latest_tag prefix-dev/pixi`, strips the leading `v`.
  - Otherwise, strips any leading `v` from the user-supplied string.
- **Inputs (globals):** `VERSION`.
- **Outputs (globals):** `VERSION` (bare semver, e.g. `"0.67.0"`).

### `detect_triple`
- **Responsibility:** Builds the pixi release asset triple string and stores it in `TRIPLE`.
  - Uses `os__kernel` and (`ARCH` override OR `os__arch`).
  - Mapping:
    - `Linux` + `x86_64`  → `x86_64-unknown-linux-musl`
    - `Linux` + `aarch64` → `aarch64-unknown-linux-musl`
    - `Linux` + `riscv64` → `riscv64gc-unknown-linux-gnu` (**note: GNU libc, not musl**)
    - `Darwin` + `x86_64` → `x86_64-apple-darwin`
    - `Darwin` + `aarch64` → `aarch64-apple-darwin`
  - Exits non-zero with a clear error for unsupported combinations.
- **Inputs (globals):** `ARCH` (may be empty).
- **Outputs (globals):** `TRIPLE`.

### `resolve_installer_paths`
- **Responsibility:** Sets `ARCHIVE`, `SIDECAR`, `ARCHIVE_URL`, and `SIDECAR_URL`:
  - If `DOWNLOAD_URL` is non-empty, sets `ARCHIVE_URL="$DOWNLOAD_URL"` and `SIDECAR_URL=""` (checksum skipped).
  - Otherwise, constructs standard URLs:
    ```
    https://github.com/prefix-dev/pixi/releases/download/v${VERSION}/pixi-${TRIPLE}.tar.gz
    https://github.com/prefix-dev/pixi/releases/download/v${VERSION}/pixi-${TRIPLE}.tar.gz.sha256
    ```
  - Sets `ARCHIVE="${INSTALLER_DIR}/pixi-${TRIPLE}.tar.gz"`.
  - Sets `SIDECAR="${INSTALLER_DIR}/pixi-${TRIPLE}.tar.gz.sha256"`.
- **Inputs (globals):** `VERSION`, `TRIPLE`, `DOWNLOAD_URL`, `INSTALLER_DIR`.
- **Outputs (globals):** `ARCHIVE`, `SIDECAR`, `ARCHIVE_URL`, `SIDECAR_URL`.

### `download_pixi`
- **Responsibility:** Creates `INSTALLER_DIR`, then downloads the archive (and sidecar if `SIDECAR_URL` is non-empty).
  - When `NETRC` is non-empty, delegates to a local `curl`/`wget` call with `--netrc-file` or equivalent instead of `net__fetch_url_file`, to pass the credential file.
  - When `NETRC` is empty, uses `net__fetch_url_file` directly.
- **Inputs (globals):** `INSTALLER_DIR`, `ARCHIVE`, `SIDECAR`, `ARCHIVE_URL`, `SIDECAR_URL`, `NETRC`.

### `verify_pixi`
- **Responsibility:** Calls `checksum__verify_sha256_sidecar "$ARCHIVE" "$SIDECAR"`.
  - Skipped when `SIDECAR_URL` is empty (i.e. when `download_url` was set) — logs a warning instead.
- **Inputs (globals):** `ARCHIVE`, `SIDECAR`, `SIDECAR_URL`.

### `get_installed_version`
- **Responsibility:** Prints the currently installed pixi version as a bare semver string, or empty string if not found.
  - Runs `"$PREFIX/bin/pixi" --version 2>/dev/null` and extracts the `X.Y.Z` portion with `awk`/`sed`.
  - Falls back to `command -v pixi` if `$PREFIX/bin/pixi` is absent.
- **Inputs (globals):** `PREFIX`.
- **Outputs:** echoes version string to stdout.

### `handle_if_exists`
- **Responsibility:** Implements the `IF_EXISTS` policy when a pixi binary already exists at `$PREFIX/bin/pixi`.
  - `skip`      — logs warning, sets `_SKIP_INSTALL=true`, continues to post-install.
  - `fail`      — prints error, exits 1.
  - `uninstall` — removes `$PREFIX/bin/pixi`, then proceeds to download + install.
  - `update`    — runs `update_pixi`, sets `_SKIP_INSTALL=true`, continues to post-install.
  - Version-match idempotency is implemented in `main` **before** calling `handle_if_exists`: if the installed version already matches `VERSION`, the install is skipped entirely without entering `handle_if_exists`.
- **Inputs (globals):** `PREFIX`, `IF_EXISTS`, `VERSION`.
- **Outputs (globals):** `_SKIP_INSTALL` (boolean string `true`/`false`).

### `update_pixi`
- **Responsibility:** Runs `pixi self-update --version "$VERSION"` (no `v` prefix — confirmed from CLI docs).
  - Finds the pixi binary from `$PREFIX/bin/pixi` or, if absent, from PATH.
  - Exits non-zero if no pixi binary is found.
- **Inputs (globals):** `PREFIX`, `VERSION`.

### `install_pixi_binary`
- **Responsibility:** Extracts the archive and places the binary.
  1. Creates a temporary extraction directory under `INSTALLER_DIR`.
  2. Runs `tar -xzf "$ARCHIVE" -C "$_tmpdir"`.
  3. Moves `"$_tmpdir/pixi"` to `"$PREFIX/bin/pixi"`.
  4. Sets executable permissions: `chmod 0755 "$PREFIX/bin/pixi"`.
  5. Removes the temp extraction directory.
- **Inputs (globals):** `ARCHIVE`, `PREFIX`.

### `create_symlink`
- **Responsibility:** Creates a file symlink `/usr/local/bin/pixi → $PREFIX/bin/pixi` when all conditions are met:
  - `SYMLINK=true`
  - Running as root (`$(id -u) = 0`)
  - `PREFIX ≠ /usr/local`
  Uses `ln -sf` (force, so it is idempotent). Logs a no-op notice when any condition is not met.
- **Inputs (globals):** `SYMLINK`, `PREFIX`.

### `verify_installed_binary`
- **Responsibility:** Confirms the pixi binary is callable after installation (or after `if_exists=skip/update`). Avoids a hard failure when pixi was found at a path other than `$PREFIX/bin`.
  1. Tries `"$PREFIX/bin/pixi" --version 2>/dev/null` first.
  2. Falls back to `command -v pixi` and runs `pixi --version` if step 1 fails.
  3. Exits non-zero with a clear error if both fail.
  Prints the verified version string.
- **Inputs (globals):** `PREFIX`.

### `export_path_main`
- **Responsibility:** Writes the PATH export block to shell startup files, mirroring `install-miniforge`'s implementation.
  - Content: `export PATH="${PREFIX}/bin:${PATH}"`
  - Marker: `"pixi PATH (install-pixi)"`
  - When `EXPORT_PATH=""`: skips with a log message.
  - When `EXPORT_PATH="auto"` **and** `PREFIX="/usr/local"`: skips with an informational message (`/usr/local/bin is already on PATH; skipping PATH write`).
  - When `EXPORT_PATH="auto"` and `PREFIX≠"/usr/local"`:
    - Root → `shell__system_path_files --profile_d pixi_bin_path.sh`
    - Non-root → `shell__user_path_files`
  - Otherwise (explicit file list): uses `EXPORT_PATH` as the newline-separated file list regardless of `PREFIX`.
  - Calls `shell__sync_block --files "$_target_files" --marker "..." --content ".."`.
- **Inputs (globals):** `EXPORT_PATH`, `PREFIX`.
### `export_pixi_home_main`
- **Responsibility:** Writes `export PIXI_HOME="$HOME_DIR"` to shell startup files when `HOME_DIR` is non-empty.
  - No-op (with log message) when `HOME_DIR` is empty.
  - Content: `export PIXI_HOME="${HOME_DIR}"`
  - Marker: `"pixi PIXI_HOME (install-pixi)"`
  - When `EXPORT_PIXI_HOME=""`: skips with a log message.
  - When `EXPORT_PIXI_HOME="auto"`:
    - Root → `shell__system_path_files --profile_d pixi_home.sh`
    - Non-root → `shell__user_path_files`
  - Otherwise (explicit file list): uses `EXPORT_PIXI_HOME` as the newline-separated file list.
  - Calls `shell__sync_block --files "$_target_files" --marker "..." --content ".."`.
- **Inputs (globals):** `EXPORT_PIXI_HOME`, `HOME_DIR`.
### `install_completion`
- **Responsibility:** Iterates over each shell name in `SHELL_COMPLETIONS` and writes an idempotent `eval "$(pixi completion --shell <shell>)"` block. No-op when `SHELL_COMPLETIONS` is empty.
  - Content (per shell): `eval "$(pixi completion --shell ${_shell})"`
  - Marker: `"pixi completion (install-pixi)"`
  - Target file selection per shell:
    - `bash`: root → `shell__detect_bashrc`; non-root → `~/.bashrc`
    - `zsh`: root → `"$(shell__detect_zshdir)/zshenv"`; non-root → `~/.zshenv`
    - `fish`, `nushell`, `elvish`: always `~/.config/<shell>/config.<ext>` (no standard system-wide location)
  - Calls `shell__write_block` for each shell.
- **Inputs (globals):** `SHELL_COMPLETIONS`, `PREFIX`.

---

## Details

### Execution Flow

```
1.  Source _lib/ospkg.sh, _lib/logging.sh, _lib/shell.sh, _lib/github.sh, _lib/checksum.sh
2.  logging__setup                  — tee to LOGFILE if set
3.  trap '__cleanup__' EXIT
4.  ospkg__run --manifest base.yaml --skip_installed
5.  Parse CLI args OR read env vars (dual-mode)
6.  Apply defaults
7.  [[ DEBUG == true ]] && set -x
8.  resolve_bin_dir                 — resolve "auto" / "" to concrete path
9.  check_root_requirement
10. resolve_pixi_version             — normalise VERSION to bare semver
11. get_installed_version → _INSTALLED_VER (only when PREFIX/bin/pixi exists)
12. If _INSTALLED_VER == VERSION:
      → log "already installed, skipping" and jump to step 18 (post-install)
13. If PREFIX/bin/pixi exists:
      → handle_if_exists             — may exit, set _SKIP_INSTALL, or remove binary
14. If _SKIP_INSTALL != true:
      a. detect_triple
      b. resolve_installer_paths
      c. download_pixi
      d. verify_pixi (or warn if skipped)
      e. install_pixi_binary
15. verify_installed_binary      — try $PREFIX/bin/pixi, fall back to PATH; exit on failure
16. create_symlink
17. export_path_main             — no-op when EXPORT_PATH="auto" and PREFIX=/usr/local
18. export_pixi_home_main        — no-op when HOME_DIR is empty
19. install_completion
20. echo "✅ Pixi ${VERSION} installed."
```

### Argument Parsing (Dual-Mode)

The script uses the same `if [ "$#" -gt 0 ]; then ... else ... fi` pattern as
`install-miniforge`. When invoked with CLI arguments (standalone mode), all
options are read from `--flag value` pairs. When invoked with no arguments
(devcontainer feature mode), options are read from identically-named environment
variables set by the devcontainer CLI from `devcontainer-feature.json`.

Boolean CLI flags (`--debug`, `--keep_installer`) require
an explicit value of `true` or `false` (e.g. `--debug true`). Omitting the flag
is equivalent to the default value (`false` for both).

String flags such as `--shell_completions` accept a space-separated list of shell names
(e.g. `--shell_completions "bash zsh"`) or an empty string to skip all completions.

### Default Value Logic

Defaults are applied *after* the argument-parsing block, using the same
`[ -z "${VAR-}" ] && { echo "ℹ️ ..."; VAR=default; }` idiom.

Special case for `EXPORT_PATH`: because empty string is a valid user-supplied value
("skip all PATH writes"), the default test must use `[ -z "${EXPORT_PATH+x}" ]`
(i.e. test for *unset*, not empty).

### NETRC Download Handling

When `NETRC` is non-empty, the installer cannot use `net__fetch_url_file` directly
(which has no netrc support). Instead, `download_pixi` falls back to an inline
`curl --netrc-file "$NETRC"` (or `wget --netrc-file "$NETRC"`) call for
the archive download. The sidecar (`.tar.gz.sha256`) does not contain secrets and is
fetched with `net__fetch_url_file` even when `NETRC` is set, unless a netrc-protected
mirror delivers both.

Implementation detail: detect preferred tool via `command -v curl` / `command -v wget`
—same logic used in `net.sh`—so we don't duplicate tool detection.

### Version-Match Idempotency

The version-match short-circuit check is performed **before** any download attempt:

```bash
_installed_ver="$(get_installed_version)"
if [[ -n "$_installed_ver" && "$_installed_ver" == "$VERSION" ]]; then
  echo "ℹ️ Installed pixi version '${_installed_ver}' matches '${VERSION}'. Skipping install."
  _SKIP_INSTALL=true
fi
```

This is intentionally placed before the `handle_if_exists` call to avoid
unnecessary downloads.

### riscv64 Triple

Linux RISC-V uses `riscv64gc-unknown-linux-gnu` (GNU libc), **not** musl. This is
the only Linux triple that uses GNU libc; all others use musl. The `detect_triple`
function must explicitly handle this case by matching `riscv64` from `uname -m`.

### PREFIX Auto-Resolution and root vs non-root

`resolve_bin_dir` runs immediately after argument defaults are applied and before any
other path-based logic:

```bash
if [ "${PREFIX}" = "auto" ]; then
  [ "$(id -u)" = "0" ] && PREFIX="/usr/local" || PREFIX="${HOME}/.pixi"
elif [ -z "${PREFIX}" ]; then
  PREFIX="${HOME}/.pixi"
fi
```

This mirrors the `prefix="auto"` pattern in `install-git`. The resolved value feeds
`check_root_requirement`, `handle_if_exists`, the symlink logic, and `export_path_main`.

### Post-Install Verification

`verify_installed_binary` runs after both the install path and the `if_exists=skip/update`
pass-through paths. It uses a two-step fallback to avoid spurious failures when pixi is
recognised by PATH but sits at a different location than the resolved `$PREFIX`:

```bash
if "${PREFIX}/bin/pixi" --version > /dev/null 2>&1; then
  "${PREFIX}/bin/pixi" --version
elif command -v pixi > /dev/null 2>&1; then
  pixi --version
else
  echo "⛔ pixi not found at '${PREFIX}/bin/pixi' and not on PATH." >&2
  exit 1
fi
```

This matches `set_executable_paths --verify` in `install-miniforge`.

### PIXI_HOME Export

`export_pixi_home_main` runs unconditionally but is a fast no-op when `HOME_DIR` is empty (the default). When `home_dir` is set, pixi reads `PIXI_HOME` on every invocation to locate global environments and config; skipping the export means a custom `home_dir` is silently ignored at runtime.

The file targeting follows the same root/non-root split as `export_path_main`, using a separate `profile_d` stub (`pixi_home.sh`) so both stubs coexist cleanly under `/etc/profile.d/`.

### PATH Export: skip when PREFIX is already on PATH

When `EXPORT_PATH="auto"` and `PREFIX="/usr/local"`, `export_path_main` skips
all writes and logs:

```
ℹ️ PREFIX is /usr/local; /usr/local/bin is already on PATH in all container images; skipping PATH write.
```

This avoids modifying `/etc/profile.d/` and system bashrc/zshenv for a no-op. If the
user explicitly supplies a file list (non-`auto` value), the write happens regardless —
they are asking for it explicitly.

### Symlink: root-only, non-standard prefix only

`create_symlink` creates `/usr/local/bin/pixi → $PREFIX/bin/pixi` with `ln -sf` only when:

```bash
if [ "${SYMLINK}" = "true" ] && [ "$(id -u)" = "0" ] && [ "${PREFIX}" != "/usr/local" ]; then
  ln -sf "${PREFIX}/bin/pixi" /usr/local/bin/pixi
fi
```

This is directly analogous to install-git's step 8. It is a no-op for the default case
(`prefix=auto` → root → `/usr/local`) since that is the standard prefix. It is also a
no-op for non-root installs since they cannot write to `/usr/local/bin`.

### Cleanup Safety

The `__cleanup__` EXIT trap always runs `logging__cleanup`. The installer files
(`ARCHIVE`, `SIDECAR`) are removed only when `KEEP_INSTALLER=false`. The
`INSTALLER_DIR` is removed only when empty after file deletion. This ensures that if
`keep_installer=true`, the directory and its contents are preserved correctly.

---

## References

- [Installation Reference](./installation.md) — research output; installation methods and decision.
- [API Reference](./api.md) — feature option design.
- [install-miniforge/scripts/install.sh](../../src/install-miniforge/scripts/install.sh) — reference pattern for dual-mode parsing, export_path_main, cleanup, if_exists logic.
- [install-git/scripts/install.sh](../../src/install-git/scripts/install.sh) — reference pattern for `prefix="auto"` root/non-root resolution and `create_symlink` (steps 1 and 8).
- [lib/shell.sh](../../lib/shell.sh) — `shell__sync_block`, `shell__system_path_files`, `shell__user_path_files`, `shell__detect_bashrc`, `shell__detect_zshdir`.
- [lib/checksum.sh](../../lib/checksum.sh) — `checksum__verify_sha256_sidecar`.
- [lib/github.sh](../../lib/github.sh) — `github__latest_tag`.
- [lib/net.sh](../../lib/net.sh) — `net__fetch_url_file`.
- [lib/os.sh](../../lib/os.sh) — `os__kernel`, `os__arch`, `os__require_root`.
- [Pixi Installation Reference Docs](https://pixi.prefix.dev/latest/installation/) — official env var list.
- [Pixi self-update CLI Docs](https://pixi.prefix.dev/latest/reference/cli/self-update/) — `pixi self-update --version X.Y.Z` (no `v` prefix).
