# Devcontainer Bash Lib Modularization Plan

## Background

The devcontainer spec requires every file needed by a feature at install time to reside inside
that feature's own directory (co-located with `devcontainer-feature.json`), because the CLI
packages only that directory into an OCI artifact. Symlinks are not followed (the CLI uses
`ncp` without `dereference: true` and `node-tar` without `follow: true`). The spec's proposed
`include` property in `devcontainer-feature.json` was merged as a spec document in April 2023
but has never been implemented in the CLI (tracking: devcontainers/spec#129, Backlog).

**Solution:** a canonical source directory (`.devcontainer/lib/`) plus a sync script and a
lefthook pre-commit hook that copies `lib/` into every feature's `scripts/_lib/` directory.
Copies are committed to the repo. The hook keeps them in sync automatically.

---

## Decisions

| # | Decision |
|---|---|
| 1 | `helpers.sh` files migrate now (clean break — no parallel naming period) |
| 2 | `sync-lib.sh --check` mode provides CI enforcement |
| 3 | Hook distribution: **lefthook** (`lefthook.yml` committed to repo) |
| 4 | Namespacing convention: `module_name::function_name` for all lib functions |
| 5 | `_lib/` destination: `src/<feature>/scripts/_lib/` (not the feature root) |

---

## Repo Structure After Completion

```
.devcontainer/
  lib/                          ← source of truth (never sourced directly at runtime)
    logging.sh
    os.sh
    ospkg.sh
    net.sh
    git.sh
    shell.sh
  sync-lib.sh                   ← discovers features, copies lib/ → scripts/_lib/
  src/
    <feature>/
      install.sh                ← #!/bin/sh bootstrap (must NEVER source _lib/)
      scripts/
        install.sh              ← #!/usr/bin/env bash main script
        _lib/                   ← generated copy; committed; do not edit here
          logging.sh
          os.sh
          ...
lefthook.yml                    ← at repo root
```

---

## Module Catalog

Each module file begins with:
```bash
# This file must be sourced from bash (>=4.0), not sh.
# Guard against double-sourcing.
[[ -n "${_LIB_<MODULENAME>_LOADED-}" ]] && return 0
_LIB_<MODULENAME>_LOADED=1
```

### `lib/logging.sh` — guard: `_LIB_LOGGING_LOADED`

| Function | Signature | Description |
|---|---|---|
| `logging__setup` | `logging__setup` | Creates `$_LOGFILE_TMP` (mktemp), saves original fds (`exec 3>&1 4>&2`), starts tee pipe. Does NOT install trap — caller does. |
| `logging__cleanup` | `logging__cleanup` | Restores fds, waits for tee, writes `$_LOGFILE_TMP` to `$LOGFILE` (if set), removes tmp file. |

Caller pattern:
```bash
. "$_SELF_DIR/_lib/logging.sh"
logging__setup
trap 'logging__cleanup' EXIT
# ...or for features with extra teardown:
__cleanup__() {
  logging__cleanup
  # feature-specific cleanup here
}
trap '__cleanup__' EXIT
```

### `lib/os.sh` — guard: `_LIB_OS_LOADED`

| Function | Signature | Description |
|---|---|---|
| `os__require_root` | `os__require_root` | Exits 1 with message if `$(id -u) != 0`. |

### `lib/ospkg.sh` — guard: `_LIB_OSPKG_LOADED`

Sources `_lib/os.sh` internally.

| Function | Signature | Description |
|---|---|---|
| `ospkg__detect` | `ospkg__detect` | Detects `PKG_MNGR`, builds `INSTALL[]` array, sets `PKG_PREFIX`, loads `OS_RELEASE[]` associative array. **Idempotent** — no-op if `PKG_MNGR` already set. Sets global state in caller scope. |
| `ospkg__update` | `ospkg__update` | Runs package list update for detected pkg manager. |
| `ospkg__install` | `ospkg__install <pkg>...` | Idempotent install: checks if packages are already installed before running the install command. |
| `ospkg__clean` | `ospkg__clean` | Dispatches to the appropriate `clean_apk`/`clean_apt`/`clean_dnf`/`clean_pacman`/`clean_zypper`. |
| `ospkg__eval_selector_block` | `ospkg__eval_selector_block <block>` | Returns 0 if all `key=val` conditions in the block match `OS_RELEASE[]`. |
| `ospkg__pkg_matches_selectors` | `ospkg__pkg_matches_selectors <line>` | Returns 0 if a manifest line has no selector blocks or any block passes. |
| `ospkg__parse_manifest` | `ospkg__parse_manifest <content>` | Parses manifest content into caller-scope vars: `_M_PRESCRIPT`, `_M_REPO`, `_M_KEY`, `_M_PKG`, `_M_SCRIPT`. |

**Note on global state:** `ospkg__detect` writes `PKG_MNGR`, `INSTALL`, `PKG_PREFIX`, and `OS_RELEASE` into the caller's global scope. This is intentional and unavoidable without subshells. Document at every call site.

### `lib/net.sh` — guard: `_LIB_NET_LOADED`

**Precondition:** `net__ensure_fetch_tool` and `net__ensure_ca_certs` require `ospkg__detect` to have been called first (they call `ospkg__install` internally if curl/wget or ca-certificates are missing). A runtime guard enforces this: `[[ -n "${_LIB_OSPKG_LOADED-}" ]] || { echo "⛔ net.sh: ospkg.sh must be sourced first" >&2; return 1; }`.

| Function | Signature | Description |
|---|---|---|
| `net__fetch_with_retry` | `net__fetch_with_retry <max-attempts> <cmd>...` | Runs `<cmd>` up to `max-attempts` times, 3-second pause between failures. |
| `net__ensure_fetch_tool` | `net__ensure_fetch_tool` | Sets `_FETCH_TOOL` to `curl` or `wget`; installs curl via `ospkg__install` if neither found. |
| `net__ensure_ca_certs` | `net__ensure_ca_certs` | Ensures `/etc/ssl/certs/ca-certificates.crt` exists; installs `ca-certificates` if not. |
| `net__fetch_url_stdout` | `net__fetch_url_stdout <url>` | Writes URL response to stdout using `_FETCH_TOOL`, with retries. |
| `net__fetch_url_file` | `net__fetch_url_file <url> <dest>` | Writes URL response to file using `_FETCH_TOOL`, with retries. |

### `lib/git.sh` — guard: `_LIB_GIT_LOADED`

| Function | Signature | Description |
|---|---|---|
| `git__clone` | `git__clone --url <url> --dir <dir> [--branch <branch>]` | Idempotent clone (no-op if dir already exists). Cleans up partial clone on failure. Migrated from `install-shell/scripts/helpers.sh`. |

### `lib/shell.sh` — guard: `_LIB_SHELL_LOADED`

| Function | Signature | Description |
|---|---|---|
| `shell__detect_bashrc` | `shell__detect_bashrc` | Probes `/etc/bash.bashrc`, `/etc/bashrc`, `/etc/bash/bashrc`; falls back to `strings` binary scan. Migrated from `install-shell/scripts/helpers.sh`. |
| `shell__detect_zshdir` | `shell__detect_zshdir` | Detects zsh etc dir. Migrated from `install-shell/scripts/helpers.sh`. |
| `shell__resolve_omz_theme` | `shell__resolve_omz_theme <value>` | Resolves Oh My Zsh theme name. Migrated from `install-shell/scripts/helpers.sh`. |

---

## Function Audit: Current State → Destination

| Function / Pattern | Currently in | Also duplicated in | Moves to |
|---|---|---|---|
| `__cleanup__` + logfile tee setup + `trap` | ALL 8 features, inline | — | `logging.sh` |
| `exit_if_not_root` | install-os-pkg, setup-user, install-miniforge | — | `os.sh` |
| `clean_apk/apt/dnf/pacman/zypper` | install-os-pkg/scripts/install.sh | — | `ospkg.sh` |
| Pkg manager detection (`PKG_MNGR`, `INSTALL[]`, `PKG_PREFIX`) | install-os-pkg/scripts/install.sh (main body) | install-shell/install.sh (bootstrap), install-pixi/install.sh (via CLI call) | `ospkg.sh` |
| `install()` — idempotent install | install-os-pkg/scripts/install.sh | — | `ospkg.sh` |
| `OS_RELEASE[]` loading | install-os-pkg/scripts/install.sh (main body) | — | `ospkg.sh` |
| `eval_selector_block` | install-os-pkg/scripts/install.sh | — | `ospkg.sh` |
| `pkg_matches_selectors` | install-os-pkg/scripts/install.sh | — | `ospkg.sh` |
| `parse_manifest` | install-os-pkg/scripts/install.sh | — | `ospkg.sh` |
| `_fetch_with_retry` / `_fetch_url_stdout` / `_fetch_url_file` | install-os-pkg/scripts/install.sh (prefixed `_`) | install-shell/scripts/helpers.sh (as `fetch_with_retry`), install-fonts/scripts/helpers.sh | `net.sh` |
| `_ensure_fetch_tool` / `_ensure_ca_certs` | install-os-pkg/scripts/install.sh | — | `net.sh` |
| `git_clone` | install-shell/scripts/helpers.sh | — | `git.sh` (as `git__clone`) |
| `detect_sys_bashrc` / `detect_zsh_etcdir` / `resolve_omz_theme_value` | install-shell/scripts/helpers.sh | — | `shell.sh` (renamed `shell::*`) |
| `fetch_with_retry` | install-fonts/scripts/helpers.sh | — | `net.sh` (share with install-shell) |

---

## `dependsOn: install-os-pkg` Impact

Six features currently declare a dependency on install-os-pkg in `devcontainer-feature.json`.
Several of these use install-os-pkg only for prerequisite installation — once `ospkg.sh` is
available as a lib module, they can self-install prerequisites and drop the dependency.

### Bootstrap patterns observed

Three patterns exist in feature `install.sh` bootstrap files:

**Pattern A — bash-ensuring bootstrap** (install-os-pkg, install-shell):
```sh
#!/bin/sh
# Ensures bash exists, installs it if not, then delegates
if ! command -v bash > /dev/null 2>&1; then
    ...series of pkg manager if/elif blocks...
fi
exec bash "$_SELF_DIR/scripts/install.sh" "$@"
```

**Pattern B — install-os-pkg CLI bootstrap** (install-miniforge, install-conda-env, install-fonts):
```sh
#!/bin/sh
install-os-pkg --manifest "$_SELF_DIR/dependencies/base.txt" --check_installed
exec bash "$_SELF_DIR/scripts/install.sh" "$@"
```
These assume install-os-pkg is already on PATH (installed as a prior feature or explicit dependency).

**Pattern C — inline main script** (setup-shim):
```sh
#!/bin/bash
# install.sh is the main script here, no scripts/ subdirectory
```

### Per-feature `dependsOn` decision

| Feature | Currently declares `dependsOn` | Bootstrap pattern | Decision |
|---|---|---|---|
| install-shell | Yes | A (bash-ensuring) | Drop `dependsOn`; source `_lib/ospkg.sh` from `scripts/install.sh`; change bootstrap from pattern A to a minimal bash-only check |
| install-fonts | Yes | B (install-os-pkg CLI) | Drop `dependsOn`; change bootstrap to pattern A; call `ospkg__install` from `scripts/install.sh` |
| setup-user | Yes | n/a (delegates to scripts/ only) | Drop `dependsOn`; source `_lib/ospkg.sh` from `scripts/install.sh` |
| install-miniforge | Yes | B (install-os-pkg CLI) | Drop `dependsOn`; change bootstrap to pattern A; call `ospkg__install` from `scripts/install.sh` |
| install-conda-env | Yes | B (install-os-pkg CLI) | Drop `dependsOn`; change bootstrap to pattern A; call `ospkg__install` from `scripts/install.sh` |
| install-podman | Yes | (read scripts before deciding) | **Defer to Phase 2** — likely needs GPG key + apt repo management |
| install-pixi | No | Calls install-os-pkg CLI in bootstrap (`install-os-pkg --manifest ...`) but doesn't declare `dependsOn` | Fix bootstrap to pattern A; source `_lib/ospkg.sh` from `scripts/install.sh` for any install calls |

**Important:** `install-os-pkg` itself does not go away. It remains a standalone feature and
provides the `/usr/local/bin/install-os-pkg` CLI command for runtime use (postCreate hooks,
lifecycle scripts, manual invocation). The `ospkg.sh` module exposes the same underlying
functions for sourcing — it is not a replacement for the feature, only for its internals.

---

## Infrastructure Files

### `.devcontainer/sync-lib.sh`

```
Usage: sync-lib.sh [--check]

Without --check: copies .devcontainer/lib/ into each feature's scripts/_lib/.
With --check:    compares lib/ against all _lib/ copies; exits non-zero and
                 reports which features are stale. Does not modify files.

Feature auto-discovery (never hard-coded):
  find .devcontainer/src -maxdepth 2 -name devcontainer-feature.json -printf '%h\n'
```

### `lefthook.yml` (repo root)

```yaml
pre-commit:
  commands:
    sync-lib:
      glob: ".devcontainer/lib/*"
      run: bash .devcontainer/sync-lib.sh && git add .devcontainer/src/*/scripts/_lib/
```

The `glob:` filter ensures the sync only runs when `lib/` files are actually staged. The
`git add` at the end stages the updated `_lib/` copies so they are included in the same commit.

### CI Step

Add a step (GitHub Actions or equivalent):
```yaml
- name: Verify lib sync
  run: bash .devcontainer/sync-lib.sh --check
```

---

## Phases

Each phase is independently shippable and testable. Complete all verification steps before
moving to the next phase.

---

### Phase 0 — Infrastructure

**Goal:** Set up the sync machinery without changing any feature script. Create stub module
files so the sync pipeline can be validated end-to-end before any real refactoring begins.

**Files created:**
- `.devcontainer/lib/logging.sh` (stub: shebang + guard + comment only)
- `.devcontainer/lib/os.sh` (stub)
- `.devcontainer/lib/ospkg.sh` (stub)
- `.devcontainer/lib/net.sh` (stub)
- `.devcontainer/lib/git.sh` (stub)
- `.devcontainer/lib/shell.sh` (stub)
- `.devcontainer/sync-lib.sh` (full implementation)
- `lefthook.yml` (repo root)

**Steps:**
1. Create all stub module files
2. Write `sync-lib.sh` with auto-discovery and `--check` mode
3. Write `lefthook.yml`
4. Run `bash .devcontainer/sync-lib.sh` — creates all `scripts/_lib/` directories
5. `git add .devcontainer/lib/ .devcontainer/sync-lib.sh lefthook.yml .devcontainer/src/*/scripts/_lib/`
6. Run `lefthook install`
7. Add CI step

**Verification:**
- `bash .devcontainer/sync-lib.sh` exits 0; all `scripts/_lib/` directories contain the stub files
- `bash .devcontainer/sync-lib.sh --check` exits 0 (copies match source)
- Trigger hook test: modify a stub file, `git add` it, run `git commit --dry-run` — hook fires and stages `_lib/` copies
- POSIX check: `grep -rl '\. .*_lib/' .devcontainer/src/*/install.sh` → zero matches (no sh bootstrap sources lib)

---

### Phase 1 — `logging.sh`

**Goal:** Eliminate the `__cleanup__` + logfile tee + `trap` boilerplate duplicated across all
8 features. Highest ROI — pure boilerplate reduction with no semantic changes.

**Files modified:**
- `.devcontainer/lib/logging.sh` (implement `logging__setup`, `logging__cleanup`)
- `src/install-shell/scripts/install.sh`
- `src/install-fonts/scripts/install.sh`
- `src/install-pixi/scripts/install.sh`
- `src/setup-user/scripts/install.sh`
- `src/install-os-pkg/scripts/install.sh`
- `src/install-miniforge/scripts/install.sh`
- `src/install-conda-env/scripts/install.sh`
- `src/setup-shim/install.sh` (this is the main script — no scripts/ subdirectory)

**Before (each feature, inline):**
```bash
__cleanup__() {
  if [ -n "${LOGFILE-}" ]; then
    exec 1>&3 2>&4; wait 2>/dev/null
    mkdir -p "$(dirname "$LOGFILE")"
    cat "$_LOGFILE_TMP" >> "$LOGFILE"; rm -f "$_LOGFILE_TMP"
  fi
}
_LOGFILE_TMP="$(mktemp)"
exec 3>&1 4>&2
exec > >(tee -a "$_LOGFILE_TMP" >&3) 2>&1
trap __cleanup__ EXIT
```

**After (features with no extra teardown):**
```bash
. "$_SELF_DIR/_lib/logging.sh"
logging__setup
trap 'logging__cleanup' EXIT
```

**Special cases:**

`install-miniforge/scripts/install.sh` has feature-specific teardown (removes installer files,
`.a` and `.pyc` files). Keep a local `__cleanup__` that calls `logging__cleanup` first:
```bash
. "$_SELF_DIR/_lib/logging.sh"
logging__setup
__cleanup__() {
  logging__cleanup
  # installer teardown: rm installer, checksum, .a/.pyc files...
}
trap '__cleanup__' EXIT
```

`setup-shim/install.sh` uses a simpler one-line log append (no tee, no temp file). Apply the
full `logging__setup` + `logging__cleanup` pattern to bring it in line with the others.

**Steps:**
1. Implement `logging.sh` functions
2. Run `sync-lib.sh`
3. Apply refactoring to each feature (one at a time, verify after each)

**Verification:**
- Run each feature's `scripts/install.sh --help` (or `--debug` / `--dry_run`) — output unchanged
- Manually source a `_lib/logging.sh` twice in a test script → no error, no duplicate output (guard works)
- `sync-lib.sh --check` exits 0

---

### Phase 2 — `os.sh` + `ospkg.sh`

**Goal:** Extract all package-management primitives from `install-os-pkg/scripts/install.sh`
into `ospkg.sh`. Refactor feature bootstraps that currently call the `install-os-pkg` CLI
into self-contained bash scripts. Remove `dependsOn: install-os-pkg` from features that
only needed it for simple prerequisite installation.

This is the largest structural change in the plan.

**Scope of install-os-pkg refactor:**

Functions extracted to `ospkg.sh` (currently inlined in `scripts/install.sh`, ~140 lines total):
- `clean_apk`, `clean_apt`, `clean_dnf`, `clean_pacman`, `clean_zypper`
- `exit_if_not_root` (moves to `os.sh`)
- `install` → `ospkg__install`
- `eval_selector_block`, `pkg_matches_selectors`, `parse_manifest`
- pkg manager detection block (currently in main body before arg parsing)
- `OS_RELEASE[]` loading (currently in main body)

After extraction, `install-os-pkg/scripts/install.sh` sources `_lib/ospkg.sh` and calls the
`ospkg::` namespace functions.

**Bootstrap changes for pattern B features:**

Features whose `install.sh` currently calls the `install-os-pkg` CLI (install-miniforge,
install-conda-env, install-fonts) change to pattern A:
```sh
#!/bin/sh
# Ensures bash, then delegates.
set -e
if ! command -v bash > /dev/null 2>&1; then
    # ... pkg manager if/elif blocks to install bash ...
fi
_SELF_DIR="$(dirname "$0")"
exec bash "$_SELF_DIR/scripts/install.sh" "$@"
```
Their `scripts/install.sh` then sources `_lib/ospkg.sh`, calls `ospkg__detect`, and calls
`ospkg__install` for prerequisites instead of shelling out to `install-os-pkg`.

**Files modified:**
- `.devcontainer/lib/os.sh` (implement `os__require_root`)
- `.devcontainer/lib/ospkg.sh` (implement full module)
- `src/install-os-pkg/scripts/install.sh` (replace ~140 lines of inlined functions with `. _lib/ospkg.sh`)
- `src/install-miniforge/install.sh` (pattern B → pattern A)
- `src/install-miniforge/scripts/install.sh` (add `ospkg__detect`, replace `install-os-pkg` CLI calls)
- `src/install-conda-env/install.sh` (pattern B → pattern A)
- `src/install-conda-env/scripts/install.sh` (add `ospkg__detect`)
- `src/install-fonts/install.sh` (pattern B → pattern A)
- `src/install-fonts/scripts/install.sh` (add `ospkg__detect`, `ospkg__install`)
- `src/install-shell/scripts/install.sh` (add `ospkg__detect` — bootstrap already is pattern A)
- `src/setup-user/scripts/install.sh` (add `ospkg__detect`, `ospkg__install`)
- `src/install-pixi/scripts/install.sh` (add `ospkg__detect` — pixi uses curl which is its prerequisite)
- `src/install-miniforge/devcontainer-feature.json` (remove `dependsOn: install-os-pkg`)
- `src/install-conda-env/devcontainer-feature.json` (remove `dependsOn`)
- `src/install-fonts/devcontainer-feature.json` (remove `dependsOn`)
- `src/install-shell/devcontainer-feature.json` (remove `dependsOn`)
- `src/setup-user/devcontainer-feature.json` (remove `dependsOn`)
- `src/install-podman/` — **read `scripts/install.sh` before deciding**; likely retains `dependsOn`

**Steps:**
1. Implement `os.sh` and `ospkg.sh`
2. Run `sync-lib.sh`
3. Refactor `install-os-pkg/scripts/install.sh` first — it is the primary consumer and defines the expected API
4. Refactor each other feature, one at a time
5. Update `devcontainer-feature.json` for confirmed `dependsOn` removals
6. Run `sync-lib.sh --check` after each feature

**Verification:**
- `install-os-pkg/scripts/install.sh --dry_run --manifest <file>` → output identical to pre-refactor
- `install-os-pkg/scripts/install.sh --check_installed --manifest <file>` → exits 0 when packages already present
- Run each refactored feature in a test container (or CI) — prerequisite packages install correctly
- For dropped `dependsOn`: remove install-os-pkg from devcontainer.json test configuration, rebuild → feature still works

---

### Phase 3 — `net.sh`

**Goal:** Consolidate the three copies of `fetch_with_retry` and the `_fetch_*` / `_ensure_*`
helpers into a single `net.sh` module.

**Files modified:**
- `.devcontainer/lib/net.sh` (implement full module)
- `src/install-os-pkg/scripts/install.sh` (remove `_fetch_with_retry`, `_fetch_url_stdout`, `_fetch_url_file`, `_ensure_fetch_tool`, `_ensure_ca_certs`; add `. _lib/net.sh`; replace `_fetch_*` / `_ensure_*` calls with `net::*`)
- `src/install-shell/scripts/helpers.sh` (remove `fetch_with_retry`; add `. _lib/net.sh` if not already sourced via another module; update all call sites to `net__fetch_with_retry`)
- `src/install-fonts/scripts/helpers.sh` (remove `fetch_with_retry` — this file may become empty or be deleted early if only `fetch_with_retry` was in it)
- `src/install-fonts/scripts/install.sh` (update call sites)
- `src/install-miniforge/scripts/install.sh` (uses `curl` directly; add `net__ensure_fetch_tool` before curl calls if appropriate)

**Note:** After removing `fetch_with_retry` from `install-fonts/scripts/helpers.sh`, that file
may be empty. If so, delete it and remove its `source` call from `install.sh`.

**Verification:**
- `install-miniforge/scripts/install.sh` downloads installer → succeeds
- `install-fonts/scripts/install.sh` downloads fonts → succeeds
- `install-shell/scripts/install.sh` (starship, OMZ downloads) → succeeds
- `sync-lib.sh --check` exits 0

---

### Phase 4 — `git.sh` + `shell.sh` + delete `helpers.sh` files

**Goal:** Complete the migration of `install-shell/scripts/helpers.sh`. Retire both
`helpers.sh` files permanently.

**Files modified:**
- `.devcontainer/lib/git.sh` (implement `git__clone` — migrated from helpers.sh)
- `.devcontainer/lib/shell.sh` (implement `shell__detect_bashrc`, `shell__detect_zshdir`, `shell__resolve_omz_theme` — migrated from helpers.sh)
- `src/install-shell/scripts/install.sh`:
  - Replace `. "$_SELF_DIR/helpers.sh"` with `. "$_SELF_DIR/_lib/git.sh"` and `. "$_SELF_DIR/_lib/shell.sh"`
  - Replace all `git_clone` calls with `git__clone`
  - Replace `detect_sys_bashrc` → `shell__detect_bashrc`, `detect_zsh_etcdir` → `shell__detect_zshdir`, `resolve_omz_theme_value` → `shell__resolve_omz_theme`

**Files deleted:**
- `src/install-shell/scripts/helpers.sh`
- `src/install-fonts/scripts/helpers.sh` (if not already deleted in Phase 3)

**Steps:**
1. Implement `git.sh` and `shell.sh`
2. Run `sync-lib.sh`
3. Update `install-shell/scripts/install.sh`
4. Delete `helpers.sh` files
5. Run `sync-lib.sh --check`
6. `git add` all changes; commit

**Verification:**
- `install-shell/scripts/install.sh --debug` → all `git__clone`, `shell__detect_bashrc`, etc. paths exercised
- `shellcheck` on `install-shell/scripts/install.sh` passes (no source-not-found warnings — update `# shellcheck source=` directives)
- No remaining references to `helpers.sh` in any file: `grep -r 'helpers\.sh' .devcontainer/src/` → zero matches

---

### Phase 5 — Final Validation

**Goal:** End-to-end validation across all features and CI gate confirmation.

**Steps:**
1. Run `bash .devcontainer/sync-lib.sh` (final clean sync)
2. `git add .devcontainer/src/*/scripts/_lib/` and commit
3. Hook smoke test: modify one line in `lib/logging.sh`, stage it, attempt commit → `_lib/` copies are auto-staged
4. Hook skip test: modify a non-lib file, commit → hook does not run
5. CI drift test: manually corrupt one `_lib/` file (do not stage+commit), run `sync-lib.sh --check` → exits non-zero with report
6. Full rebuild test: use each feature standalone via CLI (`scripts/install.sh --help`, dry-run modes)
7. POSIX source guard: `grep -rn '\. .*_lib/' .devcontainer/src/*/install.sh` → zero matches (no `#!/bin/sh` bootstrap sources lib)
8. Double-source guard: write a test script that sources every lib module twice → no error output, no duplicate function definitions

---

## Constraints and Rules

**POSIX / bash boundary:** `_lib/` modules use `declare -A`, `[[ ]]`, and `::` in function
names. All are bash-specific. Modules may only be sourced from `#!/usr/bin/env bash` scripts
(`scripts/install.sh`). The `#!/bin/sh` bootstrap `install.sh` at the feature root MUST NEVER
source any `_lib/` file. This is enforced by the Phase 5 grep check.

**Double-source guards:** Every module file MUST have a guard as its first executable line.
Convention: `[[ -n "${_LIB_<UPPER_MODULENAME>_LOADED-}" ]] && return 0` followed by
`_LIB_<UPPER_MODULENAME>_LOADED=1`.

**Do not edit `_lib/` files directly:** They are generated by `sync-lib.sh`. Edit only
`.devcontainer/lib/` sources. The pre-commit hook keeps copies in sync.

**`install-os-pkg` feature is not removed:** It remains a published devcontainer feature
and provides the `/usr/local/bin/install-os-pkg` CLI. The `ospkg.sh` module exposes the same
logic for features that want to source it directly instead of declaring a runtime dependency.

**`sync-lib.sh` always auto-discovers features:** Never hard-code the feature list. Use:
```bash
find .devcontainer/src -maxdepth 2 -name devcontainer-feature.json -printf '%h\n'
```
