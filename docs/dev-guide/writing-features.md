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
    - [`dependencies/base.yaml`](#dependenciesbaseyaml)
    - [`ospkg__run` versus `ospkg__install`](#ospkgrun-versus-ospkginstall)
  - [Shared library reference](#shared-library-reference)
    - [`os.sh`](#ossh)
    - [`logging.sh`](#loggingsh)
    - [`net.sh`](#netsh)
    - [`ospkg.sh`](#ospkgsh)
      - [Manifest format overview](#manifest-format-overview)
    - [`shell.sh`](#shellsh)
    - [`git.sh`](#gitsh)
    - [`github.sh`](#githubsh)
    - [`checksum.sh`](#checksumsh)
    - [`users.sh`](#userssh)
  - [Static files](#static-files)
  - [Sync and pre-commit](#sync-and-pre-commit)
  - [References](#references)

---

## Quick-start checklist

1. **Before writing any logic** — read [Shared library reference](#shared-library-reference)
   below. Many common operations (kernel/arch detection, GitHub API calls,
   checksum verification, user resolution, shell changes) are already
   implemented. Use library functions instead of reinventing them.
2. Create `src/<feature-id>/devcontainer-feature.json` with `"id"` matching
   the directory name.
2. Create `src/<feature-id>/scripts/install.sh` following the structure
   described below.
3. Run `bash sync-lib.sh` — this generates `src/<feature-id>/install.sh`
   (bootstrap) and `src/<feature-id>/scripts/_lib/`.
4. Create `test/<feature-id>/scenarios.json` and at least one `<scenario>.sh`.
5. If the feature requires OS packages before `scripts/install.sh` runs,
   add `src/<feature-id>/dependencies/base.yaml`.

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
│   └── base.yaml                ← OS packages needed before install.sh
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

Supported types: `"string"`, `"boolean"`.

For string options, two properties control how supporting tools (VS Code,
Codespaces) present the allowed values to users:

| Property | Behaviour |
|---|---|
| `"enum"` | **Strict** — the user must choose one of the listed values. Any other value is rejected by the tooling. Use when the script only handles a closed set of values. |
| `"proposals"` | **Suggestive** — the listed values appear as suggestions in the UI, but the user is free to type any value. Use when the script can handle arbitrary input and you only want to provide convenient defaults. |

```jsonc
// Closed set — only these three values are accepted
"mode": {
  "type": "string",
  "default": "fast",
  "enum": ["fast", "safe", "dry_run"],
  "description": "Operating mode."
}

// Open set — suggests common versions, but any semver is valid
"version": {
  "type": "string",
  "default": "latest",
  "proposals": ["latest", "3.12", "3.11", "3.10"],
  "description": "Version to install."
}
```

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
# ospkg.sh pulls in os.sh and net.sh automatically.
# shellcheck source=_lib/ospkg.sh
. "$_SELF_DIR/_lib/ospkg.sh"
# shellcheck source=_lib/logging.sh
. "$_SELF_DIR/_lib/logging.sh"

# Source additional modules only when their functions are needed:
# shellcheck source=_lib/github.sh
. "$_SELF_DIR/_lib/github.sh"    # github__fetch_release_json, __latest_tag, etc.
# shellcheck source=_lib/checksum.sh
. "$_SELF_DIR/_lib/checksum.sh"  # checksum__verify_sha256, __verify_sha256_sidecar
# shellcheck source=_lib/users.sh
. "$_SELF_DIR/_lib/users.sh"     # users__resolve_list, __set_login_shell
# shellcheck source=_lib/shell.sh
. "$_SELF_DIR/_lib/shell.sh"     # shell__write_block, __export_path, etc.
# shellcheck source=_lib/git.sh
. "$_SELF_DIR/_lib/git.sh"       # git__clone
```

> **Check the library first.** Before writing inline logic for any of the
> common operations below, confirm there is not already a lib function for it:
> `os__kernel` / `os__arch` instead of `uname -s` / `uname -m`;
> `os__font_dir` instead of manual platform detection;
> `github__latest_tag` instead of a hand-rolled API call;
> `checksum__verify_sha256_sidecar` instead of inline sha256sum/shasum logic;
> `users__resolve_list` + `users__set_login_shell` instead of a local
> deduplication loop and manual `chsh` calls.

### Logging setup and the EXIT trap

Always set up logging immediately after sourcing the library and before
any other work, with the EXIT trap to ensure cleanup runs even on error:

```bash
logging__setup
echo "↪️ Script entry: My Feature" >&2
trap 'logging__cleanup' EXIT
```

`logging__setup` redirects stdout and stderr through `tee` into a temp file.
`logging__cleanup` (called on EXIT) flushes the captured output to `$LOGFILE`
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
os__require_root

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$|^latest$ ]]; then
  echo "⛔ Invalid version: '${VERSION}'" >&2
  exit 1
fi
```

Always call `os__require_root` near the top of any script that installs
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
installation, cloning, GitHub API calls, checksum verification, user
resolution, shell changes) — see [Shared library reference](#shared-library-reference)
below.

When writing new logic, ask: could this be useful in more than one feature,
or does it encapsulate a non-trivial detail easy to get wrong? If yes, add it
to `lib/` rather than keeping it inline, then run `bash sync-lib.sh` to
propagate it. See [Sync and pre-commit](#sync-and-pre-commit).

End the script with a clear success message:

```bash
echo "✅ my-feature setup complete." >&2
```

### Cleanup

The `logging__cleanup` trap handles log flushing. If the feature installs OS
packages using `ospkg__run --no_clean`, call `ospkg__clean` explicitly at the
end before the success message, so the cache is cleared regardless of whether
earlier steps succeeded:

```bash
# (at the very end, before the success echo)
ospkg__clean
echo "✅ my-feature setup complete." >&2
```

---

## OS package dependencies

### `dependencies/base.yaml`

Create `src/<feature>/dependencies/base.yaml` when the installer needs tools
(e.g. `curl`, `ca-certificates`) to be present before any other work begins.
The file is a YAML ospkg manifest (see
[`install-os-pkg` reference](../ref/install-os-pkg.md) for the full format).

Example — the minimum set needed before downloading a binary:

```
# Base dependencies for my-feature.
ca-certificates
curl
```

Call it at the start of the script with `ospkg__run`:

```bash
ospkg__run --manifest "${_BASE_DIR}/dependencies/base.yaml" --check_installed
ospkg__clean
```

`--check_installed` skips packages whose binary is already in `PATH`, so
repeated runs are fast.

### `ospkg__run` versus `ospkg__install`

- **`ospkg__run --manifest <file>`** — the full pipeline: detect PM, update
  package lists, install packages from the manifest, run pre/post scripts,
  clean cache. Use this for manifests.
- **`ospkg__install <pkg>...`** — installs named packages directly, with an
  idempotency check (skips already-installed packages on APT/DNF). Use this
  for individual packages installed outside a manifest.

When calling `ospkg__install` after `ospkg__run`, pass `--no_clean` to
`ospkg__run` and call `ospkg__clean` once explicitly at the end, so that a
single cache refresh covers all installs:

```bash
ospkg__run --manifest "$_MANIFEST" --check_installed --no_clean
ospkg__install some-extra-package
ospkg__clean
```

---

## Shared library reference

All library files live in `lib/` and are synced to `scripts/_lib/` in each
feature. Source them from `$_SELF_DIR/_lib/<file>.sh`.

> **Always check here before implementing something from scratch.** If a
> function does what you need, use it. If you are writing logic that could
> benefit other features, add it to `lib/` instead of keeping it inline.

### `os.sh`

Auto-loaded by `ospkg.sh`. Can also be sourced standalone.

| Function | Signature | Description |
|---|---|---|
| `os__require_root` | `os__require_root` | Exits 1 with a message if the current user is not root. |
| `os__kernel` | `os__kernel` | Prints the kernel name (`Linux` or `Darwin`). Cached after first call. Use instead of `uname -s`. |
| `os__arch` | `os__arch` | Prints the CPU architecture (e.g. `x86_64`, `aarch64`, `arm64`). Cached after first call. Use instead of `uname -m`. |
| `os__id` | `os__id` | Prints the `ID` field from `/etc/os-release` (e.g. `ubuntu`, `alpine`). |
| `os__id_like` | `os__id_like` | Prints the `ID_LIKE` field from `/etc/os-release`. |
| `os__platform` | `os__platform` | Prints a canonical platform tag: `debian` \| `alpine` \| `rhel` \| `macos`. |
| `os__font_dir` | `os__font_dir` | Prints the appropriate font directory for the current user: `/usr/share/fonts` (root), `~/Library/Fonts` (macOS non-root), `${XDG_DATA_HOME:-~/.local/share}/fonts` (Linux non-root). |

### `logging.sh`

| Function | Signature | Description |
|---|---|---|
| `logging__setup` | `logging__setup` | Redirects stdout+stderr through `tee` into a temp file. Sets the global `_LOGFILE_TMP`. Saves original stdout as fd 3, stderr as fd 4. Does **not** install an EXIT trap — caller is responsible. |
| `logging__cleanup` | `logging__cleanup` | Restores original fds, flushes the temp log to `$LOGFILE` (if set), and deletes the temp file. No-op if `logging__setup` was never called. |

`$LOGFILE` is a user-visible option (type string, default `""`). When set,
`logging__cleanup` appends the full session log to that file.

### `net.sh`

Auto-loaded by `ospkg.sh`. Can also be sourced standalone (requires `ospkg.sh`
for `net__ensure_fetch_tool` and `net__ensure_ca_certs`).

| Function | Signature | Description |
|---|---|---|
| `net__fetch_with_retry` | `net__fetch_with_retry <max-attempts> <cmd...>` | Runs `<cmd>` up to `<max-attempts>` times with a 3-second pause between failures. Does **not** require `ospkg.sh`. |
| `net__ensure_ca_certs` | `net__ensure_ca_certs` | Ensures CA certificates are present; installs `ca-certificates` via `ospkg__install` if not. Idempotent. |
| `net__ensure_fetch_tool` | `net__ensure_fetch_tool` | Sets `_NET_FETCH_TOOL` to `curl` or `wget`; installs `curl` if neither is found. Calls `net__ensure_ca_certs` automatically. Idempotent. |
| `net__fetch_url_stdout` | `net__fetch_url_stdout <url>` | Downloads `<url>` to stdout with retries. Calls `net__ensure_fetch_tool` automatically. |
| `net__fetch_url_file` | `net__fetch_url_file <url> <dest>` | Downloads `<url>` to a file with retries. Calls `net__ensure_fetch_tool` automatically. |

Typical download pattern:

```bash
net__fetch_url_file \
  "https://example.com/tool-$(uname -m).tar.gz" \
  /tmp/tool.tar.gz
```

When you need to pass extra flags (e.g. `--compressed`), use `net__ensure_fetch_tool`
directly and call the tool yourself inside `net__fetch_with_retry`:

```bash
net__ensure_fetch_tool
net__fetch_with_retry 3 curl \
  --compressed -fsSLo /tmp/tool.bin \
  "https://example.com/tool-$(uname -m)"
```

### `ospkg.sh`

| Function | Signature | Description |
|---|---|---|
| `ospkg__detect` | `ospkg__detect` | Detects the package manager and populates internal state. Idempotent. Called automatically by all other `ospkg::*` functions. |
| `ospkg__update` | `ospkg__update [--force] [--lists_max_age N] [--repo_added]` | Refreshes the package index. Skips when lists are fresh (within `<N>` seconds). `--repo_added` forces a refresh unconditionally. |
| `ospkg__install` | `ospkg__install <pkg>...` | Installs packages with an idempotency check on APT and DNF. |
| `ospkg__clean` | `ospkg__clean` | Removes the package manager cache to reduce image layer size. |
| `ospkg__run` | `ospkg__run [options]` | Full pipeline: detect → root check → parse manifest → prescript → keys → repos → update → install → script → remove repos → clean. See options below. |
| `ospkg__parse_manifest_yaml` | `ospkg__parse_manifest_yaml <json-file>` | Parses a YAML/JSON manifest (pre-converted to JSON by `yq`) and emits normalized records for the pipeline. |

`ospkg__run` options:

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

**Note:** The manifest format has moved to YAML. The above table describes a legacy
text DSL that has been removed. See the install-os-pkg reference doc for the current
YAML manifest schema, `when` clause syntax, and PM-specific blocks.

See [install-os-pkg reference](../ref/install-os-pkg.md) for the complete
manifest format, all selector keys, and examples.

### `shell.sh`

| Function | Signature | Description |
|---|---|---|
| `shell__detect_bashrc` | `shell__detect_bashrc` | Prints the system-wide bashrc path for the current distro (`/etc/bash.bashrc`, `/etc/bashrc`, or `/etc/bash/bashrc`). |
| `shell__detect_zshdir` | `shell__detect_zshdir` | Prints the system-wide zsh config directory (`/etc/zsh` or `/etc`). |
| `shell__resolve_home` | `shell__resolve_home <username>` | Prints the home directory for a user via `eval echo "~<user>"`. |
| `shell__resolve_omz_theme` | `shell__resolve_omz_theme --theme_slug <slug> --custom_dir <dir>` | Given an `owner/repo` slug and `ZSH_CUSTOM`, prints the `ZSH_THEME` value for oh-my-zsh. |
| `shell__plugin_names_from_slugs` | `shell__plugin_names_from_slugs <csv-slugs>` | Extracts repository names (basenames) from a comma-separated list of `owner/repo` slugs. |
| `shell__write_block` | `shell__write_block --file <f> --marker <m> --content <c>` | Writes a fenced `# BEGIN <m>` … `# END <m>` block into a file. Idempotent: replaces any existing block with the same marker. |
| `shell__remove_block` | `shell__remove_block --file <f> --marker <m>` | Removes a fenced block (by marker) from a file. |
| `shell__export_path` | `shell__export_path --users <list> --path <dir> [--marker <m>] [--rc_files <list>]` | Appends a `PATH` export block to each user's shell RC files. |
| `shell__export_env` | `shell__export_env --users <list> --name <VAR> --value <val> [--marker <m>] [--rc_files <list>]` | Appends an `export VAR=val` block to each user's shell RC files. |

### `git.sh`

| Function | Signature | Description |
|---|---|---|
| `git__clone` | `git__clone --url <url> --dir <dir> [--branch <branch>]` | Shallow clone (`--depth=1`) of `<url>` into `<dir>`. Idempotent: skips if `<dir>/.git` already exists. On failure, removes the partial clone so re-runs do not silently skip a broken directory. |

### `github.sh`

Source explicitly. Requires `net.sh` (and `ospkg.sh`) to have been sourced first. Respects the `GITHUB_TOKEN` environment variable for all API calls.

| Function | Signature | Description |
|---|---|---|
| `github__fetch_release_json` | `github__fetch_release_json <owner/repo> [--tag <tag>] [--dest <file>]` | Fetches GitHub Releases API JSON. Without `--tag`: `/releases/latest`. Without `--dest`: writes to stdout. |
| `github__latest_tag` | `github__latest_tag <owner/repo>` | Prints the latest release tag name. Exits 1 if the API call fails or the tag cannot be parsed. |
| `github__release_tags` | `github__release_tags <owner/repo> [--per_page <n>]` | Prints one tag per line (newest first) from `/releases?per_page=<n>` (default 100). Useful for version matching. |
| `github__release_asset_urls` | `github__release_asset_urls <owner/repo> [--tag <tag>] [--filter <ere>]` | Prints `browser_download_url` values from a release. `--filter` applies an extended-regex grep to the URL list. |

Typical patterns:

```bash
# Resolve "latest" to a concrete tag:
if [[ "$VERSION" == "latest" ]]; then
  VERSION="$(github__latest_tag owner/repo)" || { echo "⛔ Failed to resolve version." >&2; exit 1; }
fi

# Pick a release tag matching a partial version string:
releases="$(github__release_tags owner/repo)"
tag="$(printf '%s\n' "$releases" | grep "^${VERSION//./\\.}" | head -1)"

# Fetch release JSON to a temp file, then parse it yourself:
json="$(mktemp)"
github__fetch_release_json owner/repo --tag "$tag" --dest "$json"
```

### `checksum.sh`

Source explicitly. Works transparently with `sha256sum` (Linux) or `shasum` (macOS).

| Function | Signature | Description |
|---|---|---|
| `checksum__verify_sha256` | `checksum__verify_sha256 <file> <expected_hash>` | Verifies the SHA-256 digest of `<file>` against `<expected_hash>`. Exits 1 on mismatch. |
| `checksum__verify_sha256_sidecar` | `checksum__verify_sha256_sidecar <file> <sha256_file>` | Reads the expected hash from the first whitespace-separated field of `<sha256_file>` then delegates to `checksum__verify_sha256`. Use for `.sha256` sidecar files. |

Typical pattern:

```bash
net__fetch_url_file "$DOWNLOAD_URL" /tmp/tool.bin
net__fetch_url_file "$DOWNLOAD_URL.sha256" /tmp/tool.bin.sha256
checksum__verify_sha256_sidecar /tmp/tool.bin /tmp/tool.bin.sha256
```

### `users.sh`

Source explicitly. Reads the standard devcontainer user-config env vars
(`ADD_CURRENT_USER_CONFIG`, `ADD_REMOTE_USER_CONFIG`, `ADD_CONTAINER_USER_CONFIG`,
`ADD_USER_CONFIG`).

| Function | Signature | Description |
|---|---|---|
| `users__resolve_list` | `users__resolve_list` | Prints one deduplicated username per line to stdout. Root is excluded from auto-detected paths (CURRENT, REMOTE, CONTAINER user) but **allowed** when explicitly listed in `ADD_USER_CONFIG`. |
| `users__set_login_shell` | `users__set_login_shell <shell_path> <username>...` | Registers `<shell_path>` in `/etc/shells`, patches Alpine PAM if needed, then calls `chsh -s` for each user. Skips users already on that shell; warns (does not abort) on `chsh` failure. |

Typical bash caller pattern:

```bash
mapfile -t _RESOLVED_USERS < <(users__resolve_list)
if [ ${#_RESOLVED_USERS[@]} -eq 0 ]; then
  echo "ℹ️  No users to configure." >&2
fi
for _username in "${_RESOLVED_USERS[@]}"; do
  # ... per-user configuration ...
done
users__set_login_shell "$_TARGET_SHELL" "${_RESOLVED_USERS[@]}"
```

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
