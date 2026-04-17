# Implementation Reference — install-node

The `install-node` installer script is a pure orchestrator: it parses arguments, installs OS dependencies, dispatches to one of two code paths (`nvm` or `binary`), configures PATH, and creates symlinks. All non-trivial logic is delegated to building blocks defined below.

---

## Building Blocks

### `github__latest_tag` — Resolve nvm Release Tag

- **Module:** `lib/github.sh`
- **Reuse:** ✅ Existing function
- **Responsibility:** When `nvm_version=latest`, call `github__latest_tag nvm-sh/nvm` to retrieve the latest nvm release tag from the GitHub Releases API. The result is a tag like `v0.40.4`.

---

### `net__fetch_url_file` — Download Files

- **Module:** `lib/net.sh` (auto-sourced by `ospkg.sh`)
- **Reuse:** ✅ Existing function
- **Responsibility:** Download the nvm install script, Node.js tarball, and `SHASUMS256.txt` to `installer_dir`. Automatically selects curl/wget; retries up to 3 times on failure.

---

### `checksum__verify_sha256` — SHA-256 Verification

- **Module:** `lib/checksum.sh`
- **Reuse:** ✅ Existing function (note: `checksum__verify_sha256_sidecar` is NOT used here — `SHASUMS256.txt` has multiple entries; the correct hash must be extracted first with `grep "${TARBALL}" SHASUMS256.txt | awk '{print $1}'`, then passed to `checksum__verify_sha256`).

---

### `ospkg__run` — Install OS Dependencies

- **Module:** `lib/ospkg.sh`
- **Reuse:** ✅ Existing function
- **Responsibility:** Install OS package dependencies from manifest files. Called three times:
  1. `dependencies/base.yaml` — always (curl, ca-certificates)
  2. `dependencies/nvm.yaml` — when `method=nvm` (bash; Alpine build toolchain via `apk` block)
  3. `dependencies/binary.yaml` — when `method=binary` (tar, xz-utils/xz)

---

### `os__platform` — Alpine Detection

- **Module:** `lib/os.sh` (auto-sourced by `ospkg.sh`)
- **Reuse:** ✅ Existing function
- **Responsibility:** Returns `alpine` when running on Alpine Linux. Used to gate the Alpine check for `method=binary` (exit with error) and to switch to `nvm install -s` on Alpine.

---

### `os__arch` / `os__kernel` — CPU Architecture / OS Detection

- **Module:** `lib/os.sh`
- **Reuse:** ✅ Existing functions
- **Responsibility:** Used in the binary method to build the nodejs.org platform string (e.g. `linux-x64`, `darwin-arm64`). Called when `arch` option is empty (auto-detect mode).

---

### `_node_build_platform_string` (inline in install.sh)

- **New inline helper**
- **Responsibility:** Converts `os__kernel` + `os__arch` output (or the user-provided `arch` override) to a nodejs.org platform string.
- **Spec:**
  - Inputs: `kernel` (e.g. `Linux`, `Darwin`), `arch` (e.g. `x86_64`, `aarch64`, `arm64`, `armv7l`)
  - Output: e.g. `linux-x64`, `linux-arm64`, `linux-armv7l`, `darwin-x64`, `darwin-arm64`
  - Before the lookup, normalize: if `kernel=Darwin` and `arch=aarch64`, replace `arch` with `arm64`. This ensures that a user-provided `arch=aarch64` on macOS is accepted without error.
  - Mapping:
    - `Linux` + `x86_64` → `linux-x64`
    - `Linux` + `aarch64` → `linux-arm64`
    - `Linux` + `armv7l` → `linux-armv7l`
    - `Linux` + `ppc64le` → `linux-ppc64le`
    - `Linux` + `s390x` → `linux-s390x`
    - `Darwin` + `x86_64` → `darwin-x64`
    - `Darwin` + `arm64` → `darwin-arm64` (also accepts `aarch64` after normalization above)
  - Error: unsupported kernel/arch combination exits 1 with a clear message.

---

### `_node_resolve_binary_version` (inline in install.sh)

- **New inline helper**
- **Responsibility:** Resolves the `version` option to an exact `v{MAJOR}.{MINOR}.{PATCH}` string for `method=binary` by querying or parsing the downloaded `nodejs.org/dist/index.json`.
- **Spec:**
  - Inputs: `version_spec` (from `VERSION` option), path to a locally downloaded `index.json`
  - **Normalise first:** if `version_spec` = `"lts"`, treat it as `"lts/*"` before any resolution. This alias is documented in the API as equivalent.
  - The index.json has one compact JSON object per line (one line per release), sorted most-recent first. Each line contains `"version":"v{X}.{Y}.{Z}"` and `"lts":"Codename"` or `"lts":false`.
  - Resolution rules:
    - `lts/*` → first line in index.json that does NOT contain `"lts":false`
    - `latest` / `node` → first line in index.json (highest version, LTS or not)
    - A bare major number `N` (no dots) → first line containing `"version":"vN.` prefix
    - Exact semver `N.M.P` or `vN.M.P` → normalize to `vN.M.P`, verify it exists in index.json, return
    - Unknown pattern → exit 1 with a message such as `nvm-style aliases (e.g. 'lts/jod') are not supported by method=binary; use method=nvm`
  - Implementation: use `grep`/`awk`/`sed` on the single-line-per-entry JSON (no external JSON parser required). If extraction fails (empty result), exit 1 with a helpful error.

---

### `_node_set_permissions` (inline in install.sh)

- **New inline function**
- **Responsibility:** Create the nvm group, configure group ownership and bits on `NVM_DIR`, add users to the group. Mirrors the `set_permissions()` pattern from `install-miniforge`.
- **Spec:**
  - Only runs when `method=nvm`, `SET_PERMISSIONS=true`, and `id -u` = 0.
  - **macOS guard:** If `os__platform` returns `macos`, emit `"ℹ️ set_permissions is not supported on macOS (groupadd/usermod are unavailable); skipping."` and `return 0`. The group-management commands (`groupadd`, `usermod`, `getent group`) are Linux-specific; macOS uses `dseditgroup`/`dscl` and is not a container target where this matters.
  - Create the group if it does not exist: `getent group "$GROUP" > /dev/null || groupadd -r "$GROUP"`
  - For each user in `_USERS_ARR`: `id -nG "$u" | grep -qw "$GROUP" || usermod -a -G "$GROUP" "$u"`
  - Transfer ownership: `chown -R "${_USERS_ARR[0]}:$GROUP" "$NVM_DIR"`
  - Set bits: `chmod g+rws "$NVM_DIR"` (group-write + setgid so newly created subdirs inherit group)
  - Log each action.

---

### `_node_install_via_nvm` (inline in install.sh)

- **New inline function**
- **Responsibility:** Full nvm-based installation flow.
- **Spec:**
  1. Resolve `NVM_VERSION`: if `"latest"`, call `github__latest_tag nvm-sh/nvm` to get the latest tag. Otherwise, normalize to always have a leading `v`: `_nvm_tag="v${NVM_VERSION#v}"` (strip any leading `v`, then prepend `v`). This normalizes both `"0.40.4"` and `"v0.40.4"` to `"v0.40.4"` for use in the download URL.
  2. Download nvm install script: `net__fetch_url_file "https://raw.githubusercontent.com/nvm-sh/nvm/${_nvm_tag}/install.sh" "${INSTALLER_DIR}/nvm-install.sh"`
  3. Create `NVM_DIR`: `mkdir -p "$NVM_DIR"`
  4. Determine the user to run nvm as: if `SET_PERMISSIONS=true` and root, use `${_USERS_ARR[0]}` (first resolved user); otherwise use the current user.
  5. Call `_node_set_permissions` (creates group, sets bits) before running the installer.
  6. Export `NVM_SYMLINK_CURRENT=true` so nvm creates and maintains a `$NVM_DIR/current` symlink during install and `nvm use`.
  7. Run nvm installer as target user: `su "$_NVM_USER" -c "umask 0002 && PROFILE=/dev/null NVM_SYMLINK_CURRENT=true NVM_DIR='$NVM_DIR' bash '${INSTALLER_DIR}/nvm-install.sh'"`
  8. Verify nvm loaded (in root shell): `. "$NVM_DIR/nvm.sh"` then `command -v nvm` (exits 1 if missing).
  9. Normalize `version`: `"lts"` → `"lts/*"`. If `VERSION="none"`, skip steps 10–14 (no Node.js install). Leave `_NODE_VERSION` unset/empty.
  10. If Alpine (`os__platform = alpine`): run as user: `su "$_NVM_USER" -c "umask 0002 && . '$NVM_DIR/nvm.sh' && nvm install -s '${VERSION}'"`
  11. Otherwise: `su "$_NVM_USER" -c "umask 0002 && . '$NVM_DIR/nvm.sh' && nvm install '${VERSION}'"`
  12. Set default alias as user: `su "$_NVM_USER" -c "umask 0002 && . '$NVM_DIR/nvm.sh' && nvm alias default '${VERSION}'"`
  13. Restore primary version as active: `su "$_NVM_USER" -c "umask 0002 && . '$NVM_DIR/nvm.sh' && nvm use default"`
  14. Get exact installed version string: run as the nvm user to ensure the same `$NVM_DIR` context: `su "$_NVM_USER" -c "umask 0002 && . '$NVM_DIR/nvm.sh' && nvm version '$VERSION'"` → stored in `_NODE_VERSION` (e.g. `v24.11.1`). Rationale: sourcing nvm in the root shell and calling `nvm version` may refer to a different $HOME and $NVM_DIR context than the user under whom nvm was installed; reading `$NVM_DIR/alias/default` is an alternative but requires resolving alias chaining. Running as the nvm user is the safest approach.
  15. Install additional versions (if `ADDITIONAL_VERSIONS` non-empty): for each version in the comma-separated list (trim surrounding whitespace from each entry), run `su "$_NVM_USER" -c "umask 0002 && . '$NVM_DIR/nvm.sh' && nvm install '$ver'"`; then restore default with `su "$_NVM_USER" -c "umask 0002 && . '$NVM_DIR/nvm.sh' && nvm use default"`. If `METHOD=binary`, emit a warning `"⚠️ additional_versions is not supported for method=binary; skipping."` and skip silently. If `VERSION=none` and `ADDITIONAL_VERSIONS` is non-empty, emit `"⚠️ VERSION=none with additional_versions: no default alias is set — run 'nvm alias default <version>' manually inside the container."` before installing each extra version.
  16. Fix version directory permissions: `chmod -R g+rw "${NVM_DIR}/versions"` (inheriting group from setgid; needed because nvm extracts tarballs which may lack group-write).
  17. Clear nvm cache and clean installer dir: these both belong in the EXIT trap (run unconditionally on exit, success or failure), not inline — `rm -rf "$INSTALLER_DIR"` and (for nvm) `su "$_NVM_USER" -c ". '$NVM_DIR/nvm.sh' && nvm clear-cache" || true`.
  18. Return `_NODE_VERSION` to the caller (may be empty when `VERSION=none`).

---

### `_node_install_via_binary` (inline in install.sh)

- **New inline function**
- **Responsibility:** Full binary-tarball installation flow.
- **Spec:**
  1. Fail immediately if on Alpine: `[ "$(os__platform)" = "alpine" ] && echo "⛔ ..." >&2 && return 1`
  2. Build platform string: call `_node_build_platform_string`
  3. Resolve `prefix` if `"auto"`: `/usr/local` (root is guaranteed by `os__require_root` at script entry).
  4. Download index.json if not already resolved: if `$_NODE_VERSION` is already set (resolved during the pre-install check — see script structure), skip to step 6. Otherwise, download `https://nodejs.org/dist/index.json` to `${INSTALLER_DIR}/index.json`.
  5. Resolve exact version if not already set: call `_node_resolve_binary_version "${VERSION}" "${INSTALLER_DIR}/index.json"` → stored in `_NODE_VERSION` (e.g. `v24.11.1`).
  6. Build tarball filename: `node-${_NODE_VERSION}-${PLATFORM}.tar.xz`
  7. Download tarball: `net__fetch_url_file "https://nodejs.org/dist/${_NODE_VERSION}/${TARBALL}" "${INSTALLER_DIR}/${TARBALL}"`
  8. Download checksums: `net__fetch_url_file "https://nodejs.org/dist/${_NODE_VERSION}/SHASUMS256.txt" "${INSTALLER_DIR}/SHASUMS256.txt"`
  9. Extract expected hash: `_hash=$(grep "  ${TARBALL}$" "${INSTALLER_DIR}/SHASUMS256.txt" | awk '{print $1}')`; exit 1 with error if empty. Note: the format is `{sha256hex}  {filename}` — two spaces between hash and filename.
  10. Verify: `checksum__verify_sha256 "${INSTALLER_DIR}/${TARBALL}" "$_hash"`
  11. Create prefix: `mkdir -p "${PREFIX}"`
  12. Extract: `tar -xJf "${INSTALLER_DIR}/${TARBALL}" --strip-components=1 -C "${PREFIX}"`
  13. Return `_NODE_VERSION` and `PREFIX` to caller. (Cleanup of `$INSTALLER_DIR` is handled by the EXIT trap — do not clean up inline here.)

---

### `_node_create_symlinks` (inline in install.sh)

- **New inline function**
- **Responsibility:** Create symlinks that keep the `containerEnv`-declared paths valid regardless of where nvm or Node.js was actually installed.
- **Spec:**
  - Only runs when running as root (`id -u` = 0) and `SYMLINK=true`.
  - **`method=nvm` — `current` symlink:** nvm creates and maintains `$NVM_DIR/current -> $NVM_DIR/versions/node/$_NODE_VERSION` automatically when `NVM_SYMLINK_CURRENT=true` is exported before install. The installer does NOT create per-binary symlinks to `/usr/local/bin` for the primary version — `containerEnv.PATH` references `$NVM_DIR/current/bin` directly.
  - **`method=nvm` — NVM_DIR bridge symlink:** If `NVM_DIR` (the actual install dir) differs from `/usr/local/share/nvm` (the `containerEnv.NVM_DIR` value), create: `ln -sf "$NVM_DIR" /usr/local/share/nvm`. This makes `containerEnv.NVM_DIR` and `containerEnv.PATH=/usr/local/share/nvm/current/bin:...` always resolve to the real nvm directory.
  - **`method=binary` with `PREFIX=/usr/local`:** no-op for binary symlinks (binaries already in `/usr/local/bin`).
  - **`method=binary` with other prefix:** Source directory is `$PREFIX/bin/`. For each binary in `node npm npx corepack`: if the source file exists, create `ln -sf <src> /usr/local/bin/<binary>`.
  - Log each symlink created.

---

### `_node_configure_path` (inline in install.sh)

- **New inline function**
- **Responsibility:** Write PATH and shell-initialisation exports to startup files, using the correct strategy per method.
- **Spec:**
  - If `EXPORT_PATH=""`: skip all writes immediately (`return 0`).
  - **`method=nvm`:** Call `_node_write_nvm_rc` (see below). Do NOT write a hardcoded versioned bin path — the nvm init snippet (which sources `$NVM_DIR/nvm.sh` and sets `NVM_SYMLINK_CURRENT=true`) is the only correct approach, because version-specific paths become stale after `nvm use`.
  - **`method=binary` + `PREFIX=/usr/local`:** Skip (binaries already land in `/usr/local/bin`, which is universally on PATH; `containerEnv.PATH` covers container processes).
  - **`method=binary` + other prefix:** Write `export PATH="${PREFIX}/bin:${PATH}"` using:
    - Determine target file list:
      - If `EXPORT_PATH != "auto"`: use `EXPORT_PATH` directly as the file list.
      - Otherwise: `_files="$(shell__system_path_files --profile_d 'node_path.sh')"`. This automatically includes the BASH_ENV file (covers non-interactive Docker `RUN` steps via `/etc/environment`), `/etc/profile.d/node_path.sh` (login shells), system bashrc (non-login interactive bash), and `<zshdir>/zshenv` (all zsh sessions). Root is guaranteed by `os__require_root` at script entry.
    - Call `shell__sync_block --files "$_files" --marker "node PATH (install-node)" --content 'export PATH="<PREFIX>/bin:${PATH}"'`.
  - **Per-user writes (both methods):** After system-wide writes, if `_USERS_ARR` is non-empty (resolved earlier in the script), for each user obtain their home directory via `shell__resolve_home "$u"`. Per-user writes always run regardless of whether `EXPORT_PATH` is `"auto"` or an explicit file list (as long as `EXPORT_PATH ≠ ""`). Then:
    - For `method=nvm`: call `_node_write_nvm_rc` for each user's home directory (writes per-user nvm init snippet).
    - For `method=binary` with non-`/usr/local` prefix: call `shell__sync_block --files "$(shell__user_path_files --home "$_home")" --marker "node PATH (install-node)" --content 'export PATH="<PREFIX>/bin:${PATH}"'` for each user.
  - **`VERSION=none` guard:** when `VERSION=none`, `_NODE_VERSION` is empty. For `method=nvm`, `_node_write_nvm_rc` should still write the nvm init snippet (so that `nvm` is available to users for subsequent `nvm install` calls even when no version was installed now).

---

### `_node_write_nvm_rc` (inline in install.sh)

- **New inline helper** (called from `_node_configure_path`)
- **Responsibility:** Write the nvm shell-initialisation snippet to startup files so that `nvm` is available as a command in interactive login and non-login shells on bare-metal and in any shell session that does not inherit `containerEnv`. This is distinct from `_node_configure_path`'s PATH-export logic: instead of adding a hardcoded bin path, the snippet sources `$NVM_DIR/nvm.sh`, which activates nvm and dynamically populates `PATH` with the bin directory of whichever version is currently active (respecting the `current` symlink set by `NVM_SYMLINK_CURRENT`).
- **Spec:**
  - Inputs: `_home` (optional; if passed, write to this user's home dir files; if absent, write to system-wide files).
  - Content of the snippet:
    ```bash
    export NVM_SYMLINK_CURRENT=true
    export NVM_DIR="<NVM_DIR>"
    # shellcheck disable=SC1090
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
    ```
  - Marker: `"nvm init (install-node)"`.
  - File targets (system-wide, run as root):
    - Determine file list: `_files="$(shell__system_path_files --profile_d 'nvm_init.sh')"`. This covers:
      - BASH_ENV file (non-interactive Docker `RUN` steps, via `/etc/environment`)
      - `/etc/profile.d/nvm_init.sh` (login shells)
      - System-wide bashrc (non-login interactive bash)
      - `<zshdir>/zshenv` (all zsh sessions)
    - Call: `shell__sync_block --files "$_files" --marker "nvm init (install-node)" --content "$_content"`.
  - File targets (per-user, when `_home` is passed):
    - Determine file list: `_files="$(shell__user_init_files --home "$_home")"`. This covers the login file (`.bash_profile` / `.bash_login` / `.profile`), `~/.bashrc`, `~/.zprofile`, and `~/.zshrc`. `shell__user_init_files` (not `shell__user_path_files`) is correct here because the nvm init snippet sources `$NVM_DIR/nvm.sh`, which must NOT run in non-interactive zsh scripts. `~/.zshenv` is intentionally excluded — it is sourced for all zsh processes including non-interactive ones.
    - Call: `shell__sync_block --files "$_files" --marker "nvm init (install-node)" --content "$_content"`.
  - Note: If `EXPORT_PATH=""`, `_node_configure_path` already returns early — this function is never called.

---

### `_node_install_pnpm` (inline in install.sh)

- **New inline function**
- **Responsibility:** Install pnpm globally after Node.js is installed.
- **Spec:**
  - No-op if `PNPM_VERSION="none"`.
  - No-op if `VERSION="none"` (no Node.js was installed; emit `"⚠️ Skipping pnpm install: no Node.js version was installed (version=none)."`).
  - Requires npm to be available: `command -v npm >/dev/null || { echo "⛔ npm not found" >&2; return 1; }`
  - **Branching by method:**
    - `method=nvm`: source nvm and run as the nvm user: `su "$_NVM_USER" -c ". '$NVM_DIR/nvm.sh' && npm install -g 'pnpm@${PNPM_VERSION}'"`.
    - `method=binary`: npm is already on `PATH` (in `$PREFIX/bin` or `/usr/local/bin`); run directly: `npm install -g "pnpm@${PNPM_VERSION}"`.
  - Verify: `pnpm --version`.

---

### `_node_install_yarn` (inline in install.sh)

- **New inline function**
- **Responsibility:** Install Yarn globally after Node.js is installed.
- **Spec:**
  - No-op if `YARN_VERSION="none"`.
  - No-op if `VERSION="none"` (emit `"⚠️ Skipping yarn install: no Node.js version was installed (version=none)."`).
  - Requires npm to be available.
  - If `YARN_VERSION="latest"`:
    - Try `corepack enable` (preferred, ships with Node.js 16+).
    - If corepack unavailable, fall back to `npm install -g yarn`.
  - If explicit version (e.g. `"1.22.22"`): `npm install -g "yarn@${YARN_VERSION}"`.
  - **Branching by method:**
    - `method=nvm`: source nvm and run as the nvm user (same pattern as `_node_install_pnpm`).
    - `method=binary`: run npm and/or corepack directly.
  - Verify: `yarn --version`.

---

### `_node_check_if_exists` (inline in install.sh)

- **New inline function**
- **Responsibility:** Pre-installation check for existing node binary. Implements `if_exists` option.
- **Spec:**
  - If `command -v node 2>/dev/null` returns empty: return 0 (not found, proceed).
  - Get existing version: `node --version` (e.g. `v22.15.1`)
  - Compare with the target version (for `method=binary`: use `$_NODE_VERSION` resolved in the pre-install setup step — see script structure; for `method=nvm`: skip comparison since nvm manages version resolution internally)
  - If versions match exactly: log silent skip, `exit 0`
  - If `IF_EXISTS=skip`: log notice, `exit 0`
  - If `IF_EXISTS=fail`: log error, `exit 1`
  - If `IF_EXISTS=reinstall`: log info, remove existing binary (method-specific), proceed
  - For `method=binary` reinstall: `rm -f "$(command -v node)" "$(command -v npm)" "$(command -v npx)" "$(command -v corepack)"`
  - For `method=nvm` reinstall: check if `$NVM_DIR/nvm.sh` exists. If it does, source it and run `nvm uninstall "${VERSION}"`. If it does not exist (node was installed outside nvm, e.g. from apt), skip the uninstall step — the nvm installer will create a fresh environment regardless.

---

## Details

### Dependency Manifest Files

#### `dependencies/base.yaml` — always installed

```yaml
# Common prerequisites for both installation methods.
packages:
  - curl
  - ca-certificates
```

#### `dependencies/nvm.yaml` — method=nvm

```yaml
# nvm prerequisites + Alpine Linux build toolchain for source compilation.
packages:
  - bash

apk:
  packages:
    - curl
    - bash
    - ca-certificates
    - openssl
    - ncurses
    - coreutils
    - python3
    - make
    - gcc
    - g++
    - libgcc
    - linux-headers
    - grep
    - util-linux
    - binutils
    - findutils
```

> The `apk` block installs ALL required Alpine build dependencies. On non-Alpine distros, only `bash` is installed (curl/ca-certificates are covered by `base.yaml`).

#### `dependencies/binary.yaml` — method=binary

```yaml
# Dependencies for extracting .tar.xz archives.
packages:
  - tar

apt:
  packages:
    - xz-utils
apk:
  packages:
    - xz
dnf:
  packages:
    - xz
brew:
  packages: []  # tar and xz are pre-installed on macOS
```

#### `dependencies/node-gyp.yaml` — `node_gyp_deps=true` (non-Alpine systems)

```yaml
# Build tools for compiling native Node.js modules (node-gyp).
# On Alpine with method=nvm these are already present from nvm.yaml.
packages:
  - make

apt:
  packages:
    - gcc
    - g++
    - python3-minimal

apk:
  packages: []  # already provided by nvm.yaml apk block

dnf:
  packages:
    - gcc
    - gcc-c++
    - python3

brew:
  packages: []  # Xcode Command Line Tools provide these on macOS
```

---

### Installer Script Structure

```
scripts/install.sh
  ├── Header: set -euo pipefail, _SELF_DIR, _BASE_DIR
  ├── Source: ospkg.sh, logging.sh, github.sh, checksum.sh, shell.sh, users.sh
  ├── logging__setup + EXIT trap (includes: rm -rf "$INSTALLER_DIR"; for nvm also: cleanup nvm cache on error)
  ├── Script entry echo
  ├── os__require_root
  ├── === Argument parsing (dual-mode) ===
  │   ├── if [ "$#" -gt 0 ]: parse --flag <value> pairs
  │   └── else: read env vars (METHOD, VERSION, NVM_VERSION, NVM_DIR, ...)
  ├── Apply defaults
  │   ├── [ "${METHOD+defined}" ] || METHOD="nvm"
  │   ├── [ "${VERSION+defined}" ] || VERSION="lts/*"
  │   ├── [ "${EXPORT_PATH+defined}" ] || EXPORT_PATH="auto"   ← +defined, not -z, so ""  is respected
  │   ├── [ "${IF_EXISTS+defined}" ] || IF_EXISTS="skip"
  │   ├── ... (all other options)
  │   └── if SET_PERMISSIONS=true and USERS="": USERS="$(id -nu)"  ← default to current user
  ├── Early enum validation (fail-fast, before any installs)
  │   ├── case "$METHOD" in nvm|binary) ;; *) echo "⛔ Unknown method: '$METHOD'"; exit 1 ;; esac
  │   └── case "$IF_EXISTS" in skip|fail|reinstall) ;; *) echo "⛔ Unknown if_exists: '$IF_EXISTS'"; exit 1 ;; esac
  ├── Resolve user list
  │   ├── ADD_USERS="$USERS"
  │   ├── users__resolve_list  → sets _USERS_ARR
  │   └── (strips duplicates and normalizes usernames)
  ├── === Helper function definitions ===  ← ALL functions defined here, before any calls
  │   ├── _node_build_platform_string
  │   ├── _node_resolve_binary_version  (normalises "lts" → "lts/*" before resolution)
  │   ├── _node_check_if_exists
  │   ├── _node_set_permissions           (no-op on macOS: guarded by [ "$(os__platform)" = "macos" ])
  │   ├── _node_install_via_nvm
  │   ├── _node_install_via_binary
  │   ├── _node_create_symlinks
  │   ├── _node_write_nvm_rc
  │   ├── _node_configure_path
  │   ├── _node_install_pnpm
  │   └── _node_install_yarn
  ├── === OS base dependencies ===  ← always installed first; ensures curl is available
  │   └── ospkg__run --manifest base.yaml
  ├── === Pre-install check ===  ← AFTER base.yaml (curl now available for binary version resolution)
  │   ├── if binary: net__fetch_url_file index.json → call _node_resolve_binary_version → sets $_NODE_VERSION
  │   └── _node_check_if_exists  (binary: uses pre-resolved $_NODE_VERSION; nvm: exact semver compare only)
  ├── === Method-specific OS dependencies ===
  │   ├── if nvm: ospkg__run --manifest nvm.yaml
  │   ├── if NODE_GYP_DEPS=true AND NOT (method=nvm AND platform=alpine): ospkg__run --manifest node-gyp.yaml
  │   │   └── (on macOS: emit diagnostic "ℹ️ node-gyp build dependencies on macOS require Xcode Command Line Tools. Install them with: xcode-select --install")
  │   └── if binary: alpine guard (exit 1 with actionable message) + ospkg__run --manifest binary.yaml
  ├── === Main logic ===
  │   ├── if nvm: _node_install_via_nvm → captures _NODE_VERSION
  │   ├── if binary: _node_install_via_binary → captures _NODE_VERSION (skips index.json re-download if already set)
  │   ├── _node_create_symlinks
  │   ├── _node_configure_path  (for nvm: calls _node_write_nvm_rc for system + per-user writes)
  │   ├── if PNPM_VERSION != "none" and VERSION != "none": _node_install_pnpm
  │   ├── if YARN_VERSION != "none" and VERSION != "none": _node_install_yarn
  │   └── Verify: node --version, npm --version (skipped when VERSION=none)
  └── Script exit echo
```

---

### Key Edge Cases and Implementation Notes

**nvm shell function sourcing:** nvm is a shell function, not a binary. Within `scripts/install.sh` (which runs as bash), nvm must be sourced with `. "$NVM_DIR/nvm.sh"`. Any subshell invocation (e.g. `bash -c "..."`) must re-source it. The `nvm install` and `nvm version` calls in `_node_install_via_nvm` are made in the same shell after sourcing.

**`lts/*` quoting:** The `VERSION` variable may contain `lts/*`. To prevent glob expansion, all nvm invocations must pass `"$VERSION"` (double-quoted) which suppresses glob expansion in bash.

**Version resolution for if_exists check (binary method):** For `method=binary`, the exact target version must be resolved BEFORE checking if_exists, so the version comparison is available. For `method=nvm`, this pre-resolution is not performed (nvm handles version resolution internally); the if_exists check for nvm simply compares the existing `node --version` output textually against the version spec if possible (i.e., only for exact semver specs), or skips the version comparison for aliases like `lts/*`.

**`nvm version` after install (nvm method):** After `nvm install "$VERSION"` completes, get the exact installed version with `nvm version "$VERSION"` (returns e.g. `v24.11.1`). This is needed for the symlink target path. If the version spec was `lts/*`, `nvm version 'lts/*'` returns the concrete version.

**`nvm alias default` and future shells:** Setting `nvm alias default "$VERSION"` writes the alias to `$NVM_DIR/alias/default` (a plain text file). This ensures that future shells that source `$NVM_DIR/nvm.sh` will have the named default version active via `nvm use default`.

**PATH strategy for nvm:** Since `NVM_SYMLINK_CURRENT=true` is used, nvm maintains `$NVM_DIR/current -> $NVM_DIR/versions/node/$_ACTIVE_VERSION`. The `containerEnv.PATH` entry `/usr/local/share/nvm/current/bin` resolves through this symlink, making binaries available to all container processes without manual per-binary symlinks. When `nvm use <version>` is called inside the container, the `current` symlink is updated and the new version is immediately active for all new processes. For bare-metal and login shell support (without `containerEnv`), `_node_write_nvm_rc` writes an nvm init snippet to system-wide and/or per-user shell startup files. The snippet sources `$NVM_DIR/nvm.sh`, which activates nvm and sets `PATH` to the active version's bin directory dynamically — it does NOT write a hardcoded versioned path (which would become stale after `nvm use`). The `NVM_SYMLINK_CURRENT=true` export in the init snippet ensures the `current` symlink behavior is preserved in all shell sessions, not just in the container runtime.

**BASH_ENV coverage (Docker RUN steps):** `shell__system_path_files` automatically includes a BASH_ENV file via `shell__ensure_bashenv`, which registers a `BASH_ENV=<path>` entry in `/etc/environment`. This covers non-interactive bash invocations (Docker `RUN` steps, CI runners) that do not source `/etc/profile.d/`. The implementation does not need to handle this special case manually — using `shell__system_path_files` is sufficient.

**Cleanup trap:** Both `rm -rf "$INSTALLER_DIR"` and `nvm clear-cache` (for nvm method) should be registered in the EXIT trap, not called inline. This ensures cleanup happens even if the installer exits with an error. The pattern from other features is: `trap '__cleanup__' EXIT` where `__cleanup__` removes the installer dir and performs method-specific cleanup. `nvm clear-cache` should be guarded with `|| true` since it is non-critical.

**`additional_versions` for `method=binary`:** The binary install method does not support installing multiple Node.js versions side-by-side (there is only one `$PREFIX`). If `ADDITIONAL_VERSIONS` is non-empty and `METHOD=binary`, `_node_install_via_nvm` step 15 emits a warning and skips. The guard should also appear in the script structure's main logic section by only calling the additional_versions logic when `METHOD=nvm`.

**Alpine version constraints:** The nvm README notes version upper bounds per Alpine version (e.g., Alpine 3.5 supports up to Node v6.9.5). The installer does NOT enforce these limits; if `method=nvm` on Alpine results in a build failure for too-new a version, the user will see the nvm compilation error. A warning can be emitted suggesting the user upgrade their Alpine base image.

**SHASUMS256.txt line format:** Each line is `{sha256hex}  {filename}` (two spaces between hash and filename). The grep pattern `"  ${TARBALL}$"` (two spaces) ensures an exact suffix match on the filename column.

**macOS `xz` availability:** macOS Catalina+ includes `xz` via the system. `brew` is not strictly required for `tar -xJ`. The `binary.yaml` manifest's `brew` block is intentionally empty.

**corepack availability:** `corepack` is included in Node.js since v16.10.0. For older Node.js versions (v14, v12), the symlink creation for `corepack` will be skipped if the binary does not exist.

**`node_gyp_deps` on macOS:** The `node-gyp.yaml` manifest has an empty `brew.packages` block because Xcode Command Line Tools provide `make`, `gcc`/`clang`, and `python3`. However, the installer must still emit a diagnostic message on macOS when `NODE_GYP_DEPS=true`: `"ℹ️ node-gyp build dependencies on macOS require Xcode Command Line Tools. Install them with: xcode-select --install"`. This guidance is important for bare-metal macOS users who may not have the CLT installed. The manifest install step is still run (it simply installs nothing via brew) so the log output confirms the step was executed.

---

## References

- [Installation Reference](./installation.md) — Research findings and method decisions
- [API Reference](./api.md) — Full options specification and usage examples
- [nvm README v0.40.4 — Alpine Linux](https://github.com/nvm-sh/nvm/blob/v0.40.4/README.md#installing-nvm-on-alpine-linux) — Exact package list and `-s` flag requirement
- [nvm README v0.40.4 — Docker](https://github.com/nvm-sh/nvm/blob/v0.40.4/README.md#installing-in-docker) — `PROFILE=/dev/null` and nvm sourcing in Docker `RUN` steps
- [nodejs.org/dist/index.json](https://nodejs.org/dist/index.json) — Release index format (`version`, `lts`, `npm`)
- [devcontainers/features node install.sh](https://raw.githubusercontent.com/devcontainers/features/main/src/node/install.sh) — Reference implementation for nvm + Alpine patterns
- [lib/github.sh](../../../lib/github.sh) — `github__latest_tag`
- [lib/checksum.sh](../../../lib/checksum.sh) — `checksum__verify_sha256`
- [lib/shell.sh](../../../lib/shell.sh) — `shell__system_path_files`, `shell__user_path_files`, `shell__sync_block` for PATH and shell configuration
- [lib/users.sh](../../../lib/users.sh) — `users__resolve_list`
- [lib/os.sh](../../../lib/os.sh) — `os__platform`, `os__arch`, `os__kernel`
