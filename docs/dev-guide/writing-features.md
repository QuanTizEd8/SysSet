# Writing Features

This guide covers how to create a new devcontainer feature in this repository:
the required files, the conventions used by existing features, and the shared
library available to every script.

---

## Contents

- [Writing Features](#writing-features)
  - [Contents](#contents)
  - [Quick-start checklist](#quick-start-checklist)
  - [Feature anatomy](#feature-anatomy)
  - [`devcontainer-feature.json`](#devcontainer-featurejson)
    - [Options](#options)
    - [Dependencies on other features](#dependencies-on-other-features)
  - [The bootstrap pattern](#the-bootstrap-pattern)
  - [`scripts/install.sh` structure](#scriptsinstallsh-structure)
    - [Shebang and error settings](#shebang-and-error-settings)
    - [Paths](#paths)
    - [Library sourcing](#library-sourcing)
    - [Logging setup and the EXIT trap](#logging-setup-and-the-exit-trap)
    - [Dual-mode argument parsing](#dual-mode-argument-parsing)
    - [Applying defaults](#applying-defaults)
    - [Validation](#validation)
    - [Main logic](#main-logic)
    - [Cleanup](#cleanup)
  - [OS package dependencies](#os-package-dependencies)
    - [`dependencies/base.txt`](#dependenciesbasetxt)
    - [`ospkg::run` versus `ospkg::install`](#ospkgrun-versus-ospkginstall)
  - [Shared library reference](#shared-library-reference)
    - [`os.sh`](#ossh)
    - [`logging.sh`](#loggingsh)
    - [`net.sh`](#netsh)
    - [`ospkg.sh`](#ospkgsh)
      - [Manifest format overview](#manifest-format-overview)
    - [`shell.sh`](#shellsh)
    - [`git.sh`](#gitsh)
  - [Static files](#static-files)
  - [Sync and pre-commit](#sync-and-pre-commit)
  - [References](#references)

---

## Quick-start checklist

1. Create `src/<feature-id>/devcontainer-feature.json` with `"id"` matching
   the directory name.
2. Create `src/<feature-id>/scripts/install.sh` following the structure
   described below.
3. Run `bash sync-lib.sh` — this generates `src/<feature-id>/install.sh`
   (bootstrap) and `src/<feature-id>/scripts/_lib/`.
4. Create `test/<feature-id>/scenarios.json` and at least one `<scenario>.sh`.
5. Add `test/<feature-id>/test.sh` (stub — see [Testing](testing.md)).
6. If the feature requires OS packages before `scripts/install.sh` runs,
   add `src/<feature-id>/dependencies/base.txt`.

---

## Feature anatomy

```
src/<feature-id>/
├── devcontainer-feature.json   ← Metadata, options, dependencies
├── install.sh                  ← Generated bootstrap (DO NOT EDIT)
├── scripts/
│   ├── install.sh              ← The real installer (edit this)
│   ├── _lib/                   ← Synced library copy (DO NOT EDIT)
│   └── <helper>.sh             ← Optional helpers sourced by install.sh
├── dependencies/
│   └── base.txt                ← OS packages needed before install.sh
└── files/                      ← Optional static files
```

`install.sh` (at the feature root) and `scripts/_lib/` are git-ignored
generated artefacts — they are created by `bash sync-lib.sh`. Never edit
them directly.

---

## `devcontainer-feature.json`

```jsonc
{
  "id": "my-feature",          // Must match the directory name under src/
  "version": "0.1.0",          // Semver — bump for every published change
  "name": "My Feature",
  "description": "One-sentence description.",
  "options": {
    // ... (see below)
  }
}
```

### Options

Each option becomes both a CLI flag (`--<option_name>`) and an environment
variable (`<OPTION_NAME>`) injected by the devcontainer tooling at build time.
Option names use snake_case; the CLI flag uses double-dashes
(`--option_name`).

```jsonc
"options": {
  "version": {
    "type": "string",
    "default": "latest",
    "description": "Version to install."
  },
  "debug": {
    "type": "boolean",
    "default": false,
    "description": "Enable debug output."
  },
  "mode": {
    "type": "string",
    "default": "fast",
    "enum": ["fast", "safe", "dry_run"],
    "description": "Operating mode."
  }
}
```

Supported types: `"string"`, `"boolean"`. Use `"enum"` to restrict string
values to a fixed set.

Always include a `"debug"` option (boolean, default false) and a `"logfile"`
option (string, default `""`) — they follow the standard from all existing
features and are expected by the logging pattern.

### Dependencies on other features

If your feature needs another feature to have already run at build time
(e.g. it calls `install-os-pkg`), declare it with `"dependsOn"`:

```jsonc
{
  "id": "my-feature",
  ...
  "dependsOn": {
    "ghcr.io/quantized8/sysset/install-os-pkg:0": {}
  }
}
```

The devcontainer CLI resolves the installation order automatically.

---

## The bootstrap pattern

The devcontainer spec guarantees only POSIX `sh` when `install.sh` runs —
bash is not guaranteed. The library and installer scripts require bash ≥4.
The bootstrap resolves this two-step:

1. **`install.sh`** (POSIX sh) — checks whether `bash` is present; if not,
   installs it via the system package manager (`apk`, `apt-get`, `dnf`, etc.).
   Then `exec bash scripts/install.sh "$@"` to hand off.
2. **`scripts/install.sh`** (bash ≥4) — the real installer with full access
   to the shared library.

`install.sh` at the feature root is generated from `bootstrap.sh` by
`sync-lib.sh`. It is identical in every feature. **Never write it manually.**

---

## `scripts/install.sh` structure

Follow this structure for every new installer:

### Shebang and error settings

```bash
#!/usr/bin/env bash
set -euo pipefail
```

`-e`: exit on error. `-u`: treat unset variables as errors.
`-o pipefail`: catch failures in pipelines.

### Paths

```bash
_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
_BASE_DIR="$(cd "$_SELF_DIR/.." && pwd)"   # Only needed when referencing files/
```

`_SELF_DIR` resolves to `src/<feature>/scripts/`. Use it to source `_lib/`
and find manifests. `_BASE_DIR` resolves to `src/<feature>/` — use it to
reference `files/` or `dependencies/`.

### Library sourcing

Source only the libraries you need. Order matters: `ospkg.sh` sources `os.sh`
and `net.sh` automatically, but `logging.sh` and others must be sourced
explicitly.

```bash
# ospkg.sh is almost always needed; it pulls in os.sh and net.sh automatically.
# shellcheck source=_lib/ospkg.sh
. "$_SELF_DIR/_lib/ospkg.sh"

# Source others as needed:
# shellcheck source=_lib/logging.sh
. "$_SELF_DIR/_lib/logging.sh"
# shellcheck source=_lib/shell.sh
. "$_SELF_DIR/_lib/shell.sh"
# shellcheck source=_lib/git.sh
. "$_SELF_DIR/_lib/git.sh"
```

### Logging setup and the EXIT trap

Always set up logging immediately after sourcing the library and before
any other work, with the EXIT trap to ensure cleanup runs even on error:

```bash
logging::setup
echo "↪️ Script entry: My Feature" >&2
trap 'logging::cleanup' EXIT
```

`logging::setup` redirects stdout and stderr through `tee` into a temp file.
`logging::cleanup` (called on EXIT) flushes the captured output to `$LOGFILE`
if that variable is set. Enabling debug tracing must come after setting up
logging so that the trace output is also captured:

```bash
[[ "$DEBUG" == true ]] && set -x
```

### Dual-mode argument parsing

Every feature must work in two modes:

- **Devcontainer mode** (no CLI arguments): the devcontainer tooling injects
  options as environment variables (`VERSION`, `DEBUG`, `LOGFILE`, etc.).
- **CLI mode** (arguments present): a human or another script calls
  `scripts/install.sh --version 1.2.3 --debug` directly.

The standard pattern:

```bash
if [ "$#" -gt 0 ]; then
  # Reset all variables before parsing to avoid inheriting env from the caller.
  VERSION=""
  DEBUG=""
  LOGFILE=""
  # ... reset all others ...

  while [[ $# -gt 0 ]]; do
    case $1 in
      --version)  shift; VERSION="$1"; shift ;;
      --debug)    DEBUG=true; shift ;;
      --logfile)  shift; LOGFILE="$1"; shift ;;
      --help|-h)  __usage__; exit 0 ;;
      --*)        echo "⛔ Unknown option: '${1}'" >&2; exit 1 ;;
      *)          echo "⛔ Unexpected argument: '${1}'" >&2; exit 1 ;;
    esac
  done
else
  echo "ℹ️ Script called with no arguments — reading environment variables." >&2
  # Optional: echo each expected var when present, for debug transparency:
  [ "${VERSION+defined}" ] && echo "📩 Read argument 'version': '${VERSION}'" >&2
fi
```

The `[ "${VAR+defined}" ]` pattern (without `-z`) checks whether the
environment variable was **set** by the caller, even if set to an empty string
— distinguishing "caller set it empty" from "caller did not set it at all".

Include a `__usage__()` function that prints the full option list to stderr
and exits. Use it for `--help`.

### Applying defaults

Apply defaults after argument parsing using the `:-` expansion, which only
substitutes when the variable is unset **or empty**:

```bash
: "${VERSION:=latest}"
: "${DEBUG:=false}"
: "${LOGFILE:=}"
```

This works correctly in both modes — devcontainer mode sets the variables via
the environment, CLI mode may have left some unset.

Enable debug tracing **after** applying defaults (so `$DEBUG` is reliably
set):

```bash
[[ "$DEBUG" == true ]] && set -x
```

### Validation

Validate early and exit with a clear message:

```bash
os::require_root

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$|^latest$ ]]; then
  echo "⛔ Invalid version: '${VERSION}'" >&2
  exit 1
fi
```

Always call `os::require_root` near the top of any script that installs
system packages or writes to system directories.

### Main logic

Write idempotent logic wherever possible. Check whether work has already been
done before doing it:

```bash
if command -v mytool > /dev/null 2>&1; then
  echo "ℹ️  mytool already installed — skipping." >&2
else
  echo "📦 Installing mytool..." >&2
  # ... installation steps ...
fi
```

Use the library functions for common operations (downloading, package
installation, cloning) — see [Shared library reference](#shared-library-reference) below.

End the script with a clear success message:

```bash
echo "✅ my-feature setup complete." >&2
```

### Cleanup

The `logging::cleanup` trap handles log flushing. If the feature installs OS
packages using `ospkg::run --no_clean`, call `ospkg::clean` explicitly at the
end before the success message, so the cache is cleared regardless of whether
earlier steps succeeded:

```bash
# (at the very end, before the success echo)
ospkg::clean
echo "✅ my-feature setup complete." >&2
```

---

## OS package dependencies

### `dependencies/base.txt`

Create `src/<feature>/dependencies/base.txt` when the installer needs tools
(e.g. `curl`, `ca-certificates`) to be present before any other work begins.
The file is a plain-text ospkg manifest (see
[`install-os-pkg` reference](../ref/install-os-pkg.md) for the full format).

Example — the minimum set needed before downloading a binary:

```
# Base dependencies for my-feature.
ca-certificates
curl
```

Call it at the start of the script with `ospkg::run`:

```bash
ospkg::run --manifest "${_BASE_DIR}/dependencies/base.txt" --check_installed
ospkg::clean
```

`--check_installed` skips packages whose binary is already in `PATH`, so
repeated runs are fast.

### `ospkg::run` versus `ospkg::install`

- **`ospkg::run --manifest <file>`** — the full pipeline: detect PM, update
  package lists, install packages from the manifest, run pre/post scripts,
  clean cache. Use this for manifests.
- **`ospkg::install <pkg>...`** — installs named packages directly, with an
  idempotency check (skips already-installed packages on APT/DNF). Use this
  for individual packages installed outside a manifest.

When calling `ospkg::install` after `ospkg::run`, pass `--no_clean` to
`ospkg::run` and call `ospkg::clean` once explicitly at the end, so that a
single cache refresh covers all installs:

```bash
ospkg::run --manifest "$_MANIFEST" --check_installed --no_clean
ospkg::install some-extra-package
ospkg::clean
```

---

## Shared library reference

All library files live in `lib/` and are synced to `scripts/_lib/` in each
feature. Source them from `$_SELF_DIR/_lib/<file>.sh`.

### `os.sh`

Auto-loaded by `ospkg.sh`. Can also be sourced standalone.

| Function | Signature | Description |
|---|---|---|
| `os::require_root` | `os::require_root` | Exits 1 with a message if the current user is not root. |

### `logging.sh`

| Function | Signature | Description |
|---|---|---|
| `logging::setup` | `logging::setup` | Redirects stdout+stderr through `tee` into a temp file. Sets the global `_LOGFILE_TMP`. Saves original stdout as fd 3, stderr as fd 4. Does **not** install an EXIT trap — caller is responsible. |
| `logging::cleanup` | `logging::cleanup` | Restores original fds, flushes the temp log to `$LOGFILE` (if set), and deletes the temp file. No-op if `logging::setup` was never called. |

`$LOGFILE` is a user-visible option (type string, default `""`). When set,
`logging::cleanup` appends the full session log to that file.

### `net.sh`

Auto-loaded by `ospkg.sh`. Can also be sourced standalone (requires `ospkg.sh`
for `net::ensure_fetch_tool` and `net::ensure_ca_certs`).

| Function | Signature | Description |
|---|---|---|
| `net::fetch_with_retry` | `net::fetch_with_retry <max-attempts> <cmd...>` | Runs `<cmd>` up to `<max-attempts>` times with a 3-second pause between failures. Does **not** require `ospkg.sh`. |
| `net::ensure_ca_certs` | `net::ensure_ca_certs` | Ensures CA certificates are present; installs `ca-certificates` via `ospkg::install` if not. Idempotent. |
| `net::ensure_fetch_tool` | `net::ensure_fetch_tool` | Sets `_NET_FETCH_TOOL` to `curl` or `wget`; installs `curl` if neither is found. Calls `net::ensure_ca_certs` automatically. Idempotent. |
| `net::fetch_url_stdout` | `net::fetch_url_stdout <url>` | Downloads `<url>` to stdout with retries. Calls `net::ensure_fetch_tool` automatically. |
| `net::fetch_url_file` | `net::fetch_url_file <url> <dest>` | Downloads `<url>` to a file with retries. Calls `net::ensure_fetch_tool` automatically. |

Typical download pattern:

```bash
net::fetch_url_file \
  "https://example.com/tool-$(uname -m).tar.gz" \
  /tmp/tool.tar.gz
```

When you need to pass extra flags (e.g. `--compressed`), use `net::ensure_fetch_tool`
directly and call the tool yourself inside `net::fetch_with_retry`:

```bash
net::ensure_fetch_tool
net::fetch_with_retry 3 curl \
  --compressed -fsSLo /tmp/tool.bin \
  "https://example.com/tool-$(uname -m)"
```

### `ospkg.sh`

| Function | Signature | Description |
|---|---|---|
| `ospkg::detect` | `ospkg::detect` | Detects the package manager and populates internal state. Idempotent. Called automatically by all other `ospkg::*` functions. |
| `ospkg::update` | `ospkg::update [--force] [--lists_max_age N] [--repo_added]` | Refreshes the package index. Skips when lists are fresh (within `<N>` seconds). `--repo_added` forces a refresh unconditionally. |
| `ospkg::install` | `ospkg::install <pkg>...` | Installs packages with an idempotency check on APT and DNF. |
| `ospkg::clean` | `ospkg::clean` | Removes the package manager cache to reduce image layer size. |
| `ospkg::run` | `ospkg::run [options]` | Full pipeline: detect → root check → parse manifest → prescript → keys → repos → update → install → script → remove repos → clean. See options below. |
| `ospkg::eval_selector_block` | `ospkg::eval_selector_block <block>` | Returns 0 if all `key=val` conditions in a selector block match the current environment. |
| `ospkg::pkg_matches_selectors` | `ospkg::pkg_matches_selectors <line>` | Returns 0 if a package line has no selectors, or if any selector block matches. |
| `ospkg::parse_manifest` | `ospkg::parse_manifest <content>` | Parses manifest content into `_M_KEY`, `_M_PRESCRIPT`, `_M_REPO`, `_M_PKG`, `_M_SCRIPT` in the caller's scope. |

`ospkg::run` options:

| Option | Default | Description |
|---|---|---|
| `--manifest <file-or-inline>` | `""` | Path to a manifest file, or inline content (detected when the value contains a newline). |
| `--no_update` | false | Skip the package list refresh unconditionally. |
| `--no_clean` | false | Skip the cache clean step (useful when more installs follow). |
| `--keep_repos` | false | Keep repository drop-in files written by `repo` sections. |
| `--lists_max_age <N>` | 300 | Seconds before a package list refresh is considered necessary. |
| `--dry_run` | false | Print what would happen without making any changes. Root not required. |
| `--check_installed` | false | Skip packages whose binary is already in `PATH`. |
| `--interactive` | false | Allow interactive package manager prompts (disables `DEBIAN_FRONTEND=noninteractive`). |

#### Manifest format overview

A manifest is a plain-text file with sections separated by `--- <type> [selectors]` headers:

| Section | Purpose |
|---|---|
| `pkg` (default) | Packages to install via the OS package manager, one per line. |
| `key` | Signing keys to fetch: one `<url> <dest-path>` entry per line. |
| `repo` | Repository config to write verbatim to the PM's drop-in directory. |
| `prescript` | Shell script to run **before** repos and packages. |
| `script` | Shell script to run **after** packages. |

Selectors filter sections or individual package lines:
`[pm=apt]`, `[arch=x86_64]`, `[id=ubuntu]`, `[version_codename=bookworm]`.
Multiple selector blocks on the same header are OR-ed; multiple key-value
pairs within a block are AND-ed.

See [install-os-pkg reference](../ref/install-os-pkg.md) for the complete
manifest format, all selector keys, and examples.

### `shell.sh`

| Function | Signature | Description |
|---|---|---|
| `shell::detect_bashrc` | `shell::detect_bashrc` | Prints the system-wide bashrc path for the current distro (`/etc/bash.bashrc`, `/etc/bashrc`, or `/etc/bash/bashrc`). |
| `shell::detect_zshdir` | `shell::detect_zshdir` | Prints the system-wide zsh config directory (`/etc/zsh` or `/etc`). |
| `shell::resolve_home` | `shell::resolve_home <username>` | Prints the home directory for a user via `eval echo "~<user>"`. |
| `shell::resolve_omz_theme` | `shell::resolve_omz_theme --theme_slug <slug> --custom_dir <dir>` | Given an `owner/repo` slug and `ZSH_CUSTOM`, prints the `ZSH_THEME` value for oh-my-zsh. |
| `shell::plugin_names_from_slugs` | `shell::plugin_names_from_slugs <csv-slugs>` | Extracts repository names (basenames) from a comma-separated list of `owner/repo` slugs. |

### `git.sh`

| Function | Signature | Description |
|---|---|---|
| `git::clone` | `git::clone --url <url> --dir <dir> [--branch <branch>]` | Shallow clone (`--depth=1`) of `<url>` into `<dir>`. Idempotent: skips if `<dir>/.git` already exists. On failure, removes the partial clone so re-runs do not silently skip a broken directory. |

---

## Static files

If a feature deploys configuration files, templates, or scripts into the
container, place them under `src/<feature>/files/`. Reference them in
`scripts/install.sh` via `_FILES_DIR="${_BASE_DIR}/files"`.

```bash
_FILES_DIR="${_BASE_DIR}/files"
cp "${_FILES_DIR}/my-config.conf" /etc/my-config.conf
```

---

## Sync and pre-commit

After creating or editing `scripts/install.sh`, run:

```bash
bash sync-lib.sh
```

This generates `install.sh` (bootstrap) and `scripts/_lib/` for your new
feature. Both are git-ignored — never commit them.

If you have [Lefthook](https://github.com/evilmartians/lefthook) installed and
the pre-commit hook is active (`lefthook install`), any staged change to
`lib/*` or `bootstrap.sh` will trigger `sync-lib.sh` automatically.

Verify the sync is up to date before pushing:

```bash
bash sync-lib.sh --check
```

---

## References

- [Dev Containers — Feature authoring specification](https://containers.dev/implementors/features/)
- [Dev Containers — `devcontainer-feature.json` properties](https://containers.dev/implementors/features/#devcontainer-feature-json-properties)
- [Dev Containers — Option resolution](https://containers.dev/implementors/features/#option-resolution)
- [install-os-pkg reference](../ref/install-os-pkg.md) — full manifest format
- [Repository structure](repo-structure.md) — how sync-lib.sh and bootstrap.sh work
- [Testing](testing.md) — how to write and run tests for your feature
