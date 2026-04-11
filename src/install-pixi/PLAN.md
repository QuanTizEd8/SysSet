# Plan: install-pixi Feature Redesign

## Context
- Feature: `.devcontainer/src/install-pixi/`
- Key files: `devcontainer-feature.json`, `scripts/install.sh`, `install.sh` (bootstrap), `dependencies/base.txt`
- Pattern reference: `install-miniforge` (sister feature)
- Bootstrap `install.sh` delegates to `scripts/install.sh`
- Each iteration is independently shippable and testable before the next begins

### Goals

1. **Dual-mode**: works as a devcontainer feature and as a standalone installer invoked directly on any machine
2. **Cross-platform**: Linux (x86_64, aarch64) and macOS (arm64, x86_64)
3. **Robust**: `if_exists` conflict policy, idempotency, version resolution, checksum verification
4. **Composable options**: exposes all upstream installer env vars as typed, documented options

### Current state

The existing installer downloads a hardcoded Linux `unknown-linux-musl` binary via `curl` directly from GitHub releases. It only supports Linux, hardcodes a specific version (`0.66.0`), provides no conflict handling, and always requires `install-os-pkg` (fails as a standalone script on macOS or outside a devcontainer).

### Source of truth — upstream `install.sh`

The official pixi installer is at `https://pixi.sh/install.sh` (source: `install/install.sh` in the pixi repo, verified from source in v0.67.0).

**Env vars read by the upstream `install.sh`:**

| Variable | Default | Effect |
|---|---|---|
| `PIXI_VERSION` | `latest` | Version to install (e.g. `v0.67.0` or `latest`) |
| `PIXI_HOME` | `$HOME/.pixi` | Pixi home directory |
| `PIXI_BIN_DIR` | `$PIXI_HOME/bin` | Where the pixi binary is placed |
| `PIXI_ARCH` | `uname -m` | Architecture override |
| `PIXI_NO_PATH_UPDATE` | *(unset)* | If non-empty: skip shell config PATH writes |
| `PIXI_DOWNLOAD_URL` | GitHub releases | Override binary download URL (mirrors, air-gapped) |
| `PIXI_REPOURL` | `https://github.com/prefix-dev/pixi` | Override repo base URL |
| `NETRC` | *(unset)* | Path to custom `.netrc` for authenticated downloads |
| `TMPDIR` | `/tmp` | Temp directory for download (note: `TMPDIR`, not `TMP_DIR`) |

**What `PIXI_NO_PATH_UPDATE` disables:**

When **unset** (the upstream default), the installer appends a single `export PATH=...` line
to the calling user's shell config file, guarded by `grep -Fxq` (idempotent):

| Shell (via `$SHELL`) | File modified | Line appended |
|---|---|---|
| `bash` | `~/.bashrc` | `export PATH="${PIXI_BIN_DIR}:$PATH"` |
| `zsh` | `~/.zshrc` | `export PATH="${PIXI_BIN_DIR}:$PATH"` |
| `fish` | `~/.config/fish/config.fish` | `set -gx PATH "${PIXI_BIN_DIR}" $PATH` |
| `tcsh` | `~/.tcshrc` | `set path = ( ${PIXI_BIN_DIR} $path )` |
| unknown | — | warns; does nothing |

When **set to any non-empty value**: skips all of the above.

**Auto-set rule in our script:** when `BIN_DIR` is explicitly set (non-empty), we
automatically set `PIXI_NO_PATH_UPDATE=1` before invoking the upstream installer.
This matches the official drop-in pattern from the docs:
```
curl -fsSL https://pixi.sh/install.sh | PIXI_BIN_DIR=/usr/local/bin PIXI_NO_PATH_UPDATE=1 bash
```
When `BIN_DIR` is empty (standalone user install), the `no_path_update` option controls
this flag directly — defaulting to `false` so the upstream shell-config-modification
behavior is preserved.

---

## Iteration 1 — Option API cleanup and extension

**Goal:** Clean up the public option surface and add all new option stubs without altering any installation logic. Existing install behavior is fully preserved. All tests pass unchanged.

### `devcontainer-feature.json` changes

- Rename `install_path` → `bin_dir`; update description to mention `PIXI_BIN_DIR`; keep default `/usr/local/bin`
- Change `version` default: `"0.66.0"` → `"latest"`
- Add new options:

| Option | Type | Default | Maps to / purpose |
|---|---|---|---|
| `if_exists` | string enum | `"skip"` | Conflict policy when pixi is already installed |
| `installer_dir` | string | `"/tmp/pixi-installer"` | Directory to download `install.sh` into before execution |
| `arch` | string | `""` | `PIXI_ARCH` — override CPU arch (e.g. `x86_64`) |
| `home_dir` | string | `""` | `PIXI_HOME` — pixi global data dir |
| `tmp_dir` | string | `""` | `TMPDIR` — temp dir used by the upstream installer |
| `download_url` | string | `""` | `PIXI_DOWNLOAD_URL` — override binary source URL |
| `netrc` | string | `""` | `NETRC` — path to `.netrc` for private repo auth |
| `no_path_update` | boolean | `false` | `PIXI_NO_PATH_UPDATE` — suppress upstream shell config writes |
| `shell_completion` | boolean | `false` | Post-install: append `pixi completion` eval to shell config |
| `shell` | string | `"bash"` | Shell for `pixi completion --shell` (`bash`/`zsh`/`fish`/`nushell`/`elvish`) |

`if_exists` enum values: `["skip", "fail", "uninstall", "update"]`

### `scripts/install.sh` changes

- Add `__usage__()` function documenting all options (same pattern as `install-miniforge`)
- Rename `INSTALL_PATH` / `--install_path` → `BIN_DIR` / `--bin_dir` in the CLI parser,
  env-var reader, defaults block, and all downstream references to the variable
- Change `VERSION` default: `"0.66.0"` → `"latest"`
- Extend the CLI parser (`while [[ $# -gt 0 ]]`) and the env-var reader to include all new
  options with their defaults (parse-and-default only; no functional change to install logic)
- Add validation after defaults: assert `IF_EXISTS` is one of `skip|fail|uninstall|update`;
  exit 1 with a descriptive error if not
- Add validation: assert `SHELL_TYPE` is one of `bash|zsh|fish|nushell|elvish` (when
  `SHELL_COMPLETION=true`); exit 1 if not

### Verification

- `bash -n scripts/install.sh` — syntax check passes
- Run with `--bin_dir /tmp/pixi-test-bin --version 0.66.0` — existing install behavior
  identical (same curl download, same chmod)
- Run with `--if_exists fail` — option parsed and logged; no other change to behavior
- Run with `--if_exists bogus` — exits 1 with clear validation error message
- Run with `--shell_completion true --shell powershell` — exits 1 with shell validation error
- `devcontainer-feature.json` validates against the DevContainer feature schema

---

## Iteration 2 — Bootstrap standalone support

**Goal:** Make `install.sh` (the bootstrap entrypoint) work without `install-os-pkg` so
the feature can be invoked directly on macOS or Linux systems without a devcontainer
toolchain.

### `install.sh` changes

Replace the unconditional `install-os-pkg` call with a guarded variant:

```sh
if command -v install-os-pkg >/dev/null 2>&1; then
    # Devcontainer mode: install dependencies via the feature toolchain.
    install-os-pkg --manifest "$_SELF_DIR/dependencies/base.txt" --check_installed
else
    # Standalone mode: verify required tools exist and print a friendly error if not.
    _missing=""
    for _cmd in curl bash; do
        command -v "$_cmd" >/dev/null 2>&1 || _missing="$_missing $_cmd"
    done
    if [ -n "$_missing" ]; then
        echo "⛔ Missing required tools:$_missing" >&2
        echo "   Install them via your system package manager and retry." >&2
        exit 1
    fi
fi
```

### Verification

- Run `install.sh` directly on macOS (no `install-os-pkg` in PATH) — proceeds to
  `scripts/install.sh` instead of failing with "command not found"
- Run `install.sh` directly on Linux without devcontainer toolchain — same result
- Run inside devcontainer — `install-os-pkg` is still called as before (no regression)
- `bash -n install.sh` — syntax check passes
- Run without `curl` in PATH (standalone mode) — exits 1 with "Missing required tools: curl"

---

## Iteration 3 — Core installer rewrite: official script delegation, version resolution, `if_exists`

**Goal:** Replace the hardcoded Linux-only `curl` binary download with delegation to the
official `https://pixi.sh/install.sh`. Gain macOS support, `"latest"` version resolution,
`if_exists` dispatch, and all env-var passthrough options wired up.

### Version resolution

Add `resolve_pixi_version()`:

- `VERSION="" or "latest"` → `curl -fsSL https://api.github.com/repos/prefix-dev/pixi/releases/latest`;
  extract `tag_name` with `grep`/`sed` (no `jq` dependency); strip leading `v`; store as
  `RESOLVED_VERSION`
  ```sh
  RESOLVED_VERSION=$(curl -fsSL https://api.github.com/repos/prefix-dev/pixi/releases/latest \
    | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
  ```
- Specific version → strip any leading `v`; store as `RESOLVED_VERSION`
- On API or network failure → print a clear error and exit 1

### `if_exists` dispatch

After version resolution, locate the pixi binary: `${BIN_DIR}/pixi` if `BIN_DIR` is set,
otherwise `$(command -v pixi 2>/dev/null)`.

```
if pixi binary found:
    installed_ver=$(pixi --version | awk '{print $2}')
    if installed_ver == RESOLVED_VERSION:
        → skip silently (version match always wins, regardless of if_exists)
    else:
        if_exists == "skip"      → warn, skip install, continue to post-install steps
        if_exists == "fail"      → print error, exit 1
        if_exists == "uninstall" → rm existing binary, then install
        if_exists == "update"    → pixi self-update --version "$RESOLVED_VERSION"
else:
    install
```

Note on `if_exists: "update"`: runs `pixi self-update --version "$RESOLVED_VERSION"`,
which works because pixi already exists. This is a thin wrapper — no uninstall/reinstall
needed.

### Installation via official script

1. `mkdir -p "$INSTALLER_DIR"` (default `/tmp/pixi-installer`)
2. `curl -fsSL -o "$INSTALLER_DIR/install.sh" https://pixi.sh/install.sh`
3. Build env var string for subprocess — only include each var when its value is non-empty:
   - `PIXI_VERSION="v${RESOLVED_VERSION}"` (upstream expects a `v` prefix)
   - `PIXI_BIN_DIR="$BIN_DIR"` — when `BIN_DIR` non-empty
   - `PIXI_HOME="$HOME_DIR"` — when `HOME_DIR` non-empty
   - `TMPDIR="$TMP_DIR"` — when `TMP_DIR` non-empty (note: `TMPDIR`, **not** `TMP_DIR`)
   - `PIXI_ARCH="$ARCH"` — when `ARCH` non-empty
   - `PIXI_DOWNLOAD_URL="$DOWNLOAD_URL"` — when `DOWNLOAD_URL` non-empty
   - `NETRC="$NETRC"` — when `NETRC` non-empty
   - `PIXI_NO_PATH_UPDATE=1` — when `BIN_DIR` non-empty **or** `NO_PATH_UPDATE=true`
4. `env [...] bash "$INSTALLER_DIR/install.sh"`
5. `rm -f "$INSTALLER_DIR/install.sh"`

### Verification

- **Version resolution — `latest`**: run without `--version`; assert resolved version logged,
  correct binary installed
- **Version resolution — pinned**: `--version 0.65.0`; assert that exact version installed
- **Version resolution — `latest` with `v` prefix**: `--version v0.65.0`; same as pinned
- **API failure**: block `api.github.com` (via `/etc/hosts`); assert clean error exit, not a
  bash error traceback
- **`if_exists: skip`**: pre-install pixi at a different version; assert skip warning emitted,
  binary version unchanged, exit 0
- **`if_exists: fail`**: same setup; assert non-zero exit with error message
- **`if_exists: uninstall`**: pre-install pixi; assert binary removed and reinstalled fresh
- **`if_exists: update`**: pre-install older version; assert `pixi --version` reports new version
- **Version match skip**: pre-install exact matching version; assert "already installed" message
  emitted regardless of `if_exists` value, exit 0
- **macOS `latest`**: correct `aarch64-apple-darwin` or `x86_64-apple-darwin` binary installed
- **Linux `latest`**: correct `x86_64-unknown-linux-musl` or `aarch64-unknown-linux-musl`
- **`bin_dir` set**: binary placed at custom path; `PIXI_NO_PATH_UPDATE` auto-applied;
  shell config NOT modified
- **`bin_dir` unset (standalone)**: binary placed at `~/.pixi/bin`; shell config modified
  (assuming `no_path_update: false`)
- **`no_path_update: true` + `bin_dir` unset**: explicit flag respected; shell config not touched
- **`arch` override**: `PIXI_ARCH` passed through to upstream installer
- **`download_url` override**: custom URL used; connection to GitHub releases not made
- **`tmp_dir` set**: temp file created under `TMPDIR=<value>`, not default `/tmp`
- **`home_dir` set**: `PIXI_HOME` passed through; binary lands under `<home_dir>/bin`

---

## Iteration 4 — Post-install checksum verification

**Goal:** Independently verify the installed binary against the SHA-256 hash published on
the GitHub release, exiting non-zero if verification fails. Guards against download
corruption or MITM (especially relevant when `download_url` is overridden with an
unofficial mirror).

### Implementation

Add `verify_checksum()` called immediately after the upstream installer completes.

1. Locate the installed binary: `${BIN_DIR}/pixi` if `BIN_DIR` set, else `$(command -v pixi)`
2. Detect OS triple from `uname -s` and `uname -m` (or `ARCH` when explicitly set):

   | `uname -s` | `uname -m` (or `ARCH`) | Triple |
   |---|---|---|
   | `Linux` | `x86_64` | `x86_64-unknown-linux-musl` |
   | `Linux` | `aarch64` | `aarch64-unknown-linux-musl` |
   | `Darwin` | `arm64` / `aarch64` | `aarch64-apple-darwin` |
   | `Darwin` | `x86_64` | `x86_64-apple-darwin` |

3. Download SHA-256 file:
   `https://github.com/prefix-dev/pixi/releases/download/v${RESOLVED_VERSION}/pixi-${TRIPLE}.sha256`
4. Extract expected hash: `awk '{print $1}'`
   (the `.sha256` file may contain filename after hash)
5. Compute actual hash:
   - Linux: `sha256sum "$pixi_bin" | awk '{print $1}'`
   - macOS: `shasum -a 256 "$pixi_bin" | awk '{print $1}'`
6. Compare; on mismatch: print expected vs actual hashes and exit 1

**Skip condition:** when `DOWNLOAD_URL` is set (custom/mirror URL), the corresponding
`.sha256` may not exist on GitHub; skip verification and emit a warning.

### Verification

- **Happy path**: fresh install; checksum passes; no output beyond the "verified" log line
- **Corrupted binary**: overwrite first byte of installed binary; rerun checksum; assert
  exit 1 with "checksum mismatch" message showing expected and actual hashes
- **Custom `download_url`**: checksum step skipped; install completes cleanly
- **macOS**: correct `aarch64-apple-darwin` or `x86_64-apple-darwin` triple selected
- **Linux aarch64**: correct `aarch64-unknown-linux-musl` triple selected
- **`arch` override active**: triple built using the overridden arch, not `uname -m`
- **`.sha256` download failure** (e.g. unknown version string): clean error, not a bash error

---

## Iteration 5 — Shell completion setup

**Goal:** Wire up the `shell_completion` and `shell` options added in Iteration 1 to
post-install `pixi completion` output, appended to the appropriate shell config file
using an idempotent marked block.

### Implementation

Add `setup_shell_completion()`, called after install (and checksum) when `SHELL_COMPLETION=true`.

**Config file selection** based on `SHELL_TYPE` and current user:

| `SHELL_TYPE` | Root (devcontainer) | Non-root (standalone) |
|---|---|---|
| `bash` | Platform global bashrc¹ | `~/.bashrc` |
| `zsh` | Platform global zshrc² | `~/.zshrc` |
| `fish` | `/etc/fish/conf.d/pixi_completion.fish` | `~/.config/fish/conf.d/pixi_completion.fish` |
| `nushell` | `/etc/nushell/config.nu` | `~/.config/nushell/config.nu` |
| `elvish` | `/etc/elvish/rc.elv` | `~/.config/elvish/rc.elv` |

¹ Debian/Alpine: `/etc/bash.bashrc`; RHEL/macOS: `/etc/bashrc`
² Debian/Alpine: `/etc/zsh/zshrc`; RHEL/macOS: `/etc/zshrc`

Platform detection uses the same `detect_platform()` logic as `install-os-pkg/scripts/install.sh`
(reads `ID`/`ID_LIKE` from `/etc/os-release`; falls back to `uname -s` for macOS).

**Write a marked block** (create file if absent, replace block if already present):

```sh
# >>> pixi completion >>>
eval "$(pixi completion --shell bash)"
# <<< pixi completion <<<
```

Shell-specific completion line:
- `bash` / `zsh`: `eval "$(pixi completion --shell ${SHELL_TYPE})"`
- `fish`: `pixi completion --shell fish | source`
- `nushell`: `pixi completion --shell nushell` (no eval wrapper)
- `elvish`: `eval (pixi completion --shell elvish)`

Guard: grep for the opening marker before writing (idempotent re-runs).

### Verification

- `shell_completion: false` (default): no shell config files modified
- `shell_completion: true, shell: bash`, root: completion block appended to correct
  platform-specific global bashrc
- `shell_completion: true, shell: bash`, non-root: block appended to `~/.bashrc`
- `shell_completion: true, shell: zsh`: correct zshrc appended
- `shell_completion: true, shell: fish`: fish conf.d file created and sourced correctly
- **Re-run idempotency**: run twice; assert block not duplicated (single block present)
- **Changed pixi binary path**: re-run after moving binary; assert block replaced (not
  appended again) with updated path
- **Already partially present marker**: corrupt existing block, rerun; assert clean
  replacement
