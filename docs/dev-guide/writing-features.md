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
  - [`install.bash` structure](#installbash-structure)
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
2. Create `src/<feature-id>/install.bash` following the structure
   described below.
3. Run `bash sync-lib.sh` — this generates `src/<feature-id>/install.sh`
   (bootstrap) and `src/<feature-id>/_lib/`.
4. Create `test/<feature-id>/scenarios.json` and at least one `<scenario>.sh`.
5. If the feature requires OS packages before `install.bash` runs,
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

`install.sh` (at the feature root) and `_lib/` are git-ignored
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
   Then `exec bash install.bash "$@"` to hand off.
2. **`install.bash`** (bash ≥4) — the real installer with full access
   to the shared library.

`install.sh` at the feature root is generated from `bootstrap.sh` by
`sync-lib.sh`. It is identical in every feature. **Never write it manually.**

---

## `install.bash` structure

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
_BASE_DIR="$_SELF_DIR"
```

`_SELF_DIR` and `_BASE_DIR` both resolve to `src/<feature>/`. Use them to source `_lib/`,
reference `files/`, and find manifests.

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
  `install.bash --version 1.2.3 --debug` directly.

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
packages using `ospkg__run --keep_cache`, call `ospkg__clean` explicitly at the
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

```yaml
# Base dependencies for my-feature.
packages:
  - ca-certificates
  - curl
```

Call it at the start of the script with `ospkg__run`:

```bash
ospkg__run --manifest "${_BASE_DIR}/dependencies/base.yaml" --skip_installed
ospkg__clean
```

`--skip_installed` skips packages whose binary is already in `PATH`, so
repeated runs are fast.

### `ospkg__run` versus `ospkg__install`

- **`ospkg__run --manifest <file>`** — the full pipeline: detect PM, update
  package lists, install packages from the manifest, run pre/post scripts,
  clean cache. Use this for manifests.
- **`ospkg__install <pkg>...`** — installs named packages directly, with an
  idempotency check (skips already-installed packages on APT/DNF). Use this
  for individual packages installed outside a manifest.

When calling `ospkg__install` after `ospkg__run`, pass `--keep_cache` to
`ospkg__run` and call `ospkg__clean` once explicitly at the end, so that a
single cache refresh covers all installs:

```bash
ospkg__run --manifest "$_MANIFEST" --skip_installed --keep_cache
ospkg__install some-extra-package
ospkg__clean
```

---

## Shared library reference

All library files live in `lib/` and are synced to `_lib/` in each
feature. Source them from `$_SELF_DIR/_lib/<file>.sh`.

> **Always check here before implementing something from scratch.** If a
> function does what you need, use it. If you are writing logic that could
> benefit other features, add it to `lib/` instead of keeping it inline.

### `os.sh`

Auto-loaded by `ospkg.sh`. Can also be sourced standalone.

<!-- START lib-os-table MARKER -->
| Function | Signature | Description |
|---|---|---|
| `os__kernel` | `os__kernel` | Prints the kernel name (`Linux` or `Darwin`). Cached; use instead of `uname -s`. |
| `os__arch` | `os__arch` | Prints the CPU architecture (e.g. `x86_64`, `aarch64`). Cached; use instead of `uname -m`. |
| `os__id` | `os__id` | Prints the `ID` field from `/etc/os-release` (e.g. `ubuntu`, `alpine`). |
| `os__id_like` | `os__id_like` | Prints the `ID_LIKE` field from `/etc/os-release` (space-separated distro family list). |
| `os__platform` | `os__platform` | Prints a canonical platform tag: `debian` | `alpine` | `rhel` | `macos`. |
| `os__require_root` | `os__require_root` | Exits 1 with an error message if the current user is not root. |
| `os__font_dir` | `os__font_dir` | Print the font directory for the current user. |
| `os__is_container` | `os__is_container` | Returns 0 if running inside a container (Docker, Podman, Kubernetes, CI), 1 otherwise. |
| `os__codename` | `os__codename` | Prints `VERSION_CODENAME` from `/etc/os-release` (e.g. `jammy`, `bookworm`). Empty string if absent or on macOS. |
<!-- END lib-os-table MARKER -->

### `logging.sh`

<!-- START lib-logging-table MARKER -->
| Function | Signature | Description |
|---|---|---|
| `logging__setup` | `logging__setup` | Redirect stdout+stderr through `tee` into a temp log file; save original fds. |
| `logging__mask_secret` | `logging__mask_secret <value>` | Register a secret value to be redacted when `logging__cleanup` writes to `$LOGFILE`. |
| `logging__tmpdir` | `logging__tmpdir <name>` | Return (and create if needed) a named subdirectory of `_SYSSET_TMPDIR`. Lazy-initialises `_SYSSET_TMPDIR` if needed. Idempotent. |
| `logging__cleanup` | `logging__cleanup` | Restore original fds, flush the temp log to `$LOGFILE` if set, and delete `_SYSSET_TMPDIR`. |
<!-- END lib-logging-table MARKER -->

`$LOGFILE` is a user-visible option (type string, default `""`). When set,
`logging__cleanup` appends the full session log to that file.

### `net.sh`

Auto-loaded by `ospkg.sh`. Can also be sourced standalone (requires `ospkg.sh`
for `net__ensure_fetch_tool` and `net__ensure_ca_certs`).

<!-- START lib-net-table MARKER -->
| Function | Signature | Description |
|---|---|---|
| `net__fetch_with_retry` | `net__fetch_with_retry [--retries N] [--delay N] <cmd...>` | Run `<cmd>` up to N times with a delay between failures (default: 60 retries, 5s delay). |
| `net__fetch_url_stdout` | `net__fetch_url_stdout <url> [--retries N] [--delay N] [--header <H>]...` | Download `<url>` to stdout with retries. Auto-detects curl/wget. |
| `net__fetch_url_file` | `net__fetch_url_file <url> <dest> [--retries N] [--delay N] [--header <H>]...` | Download `<url>` to `<dest>` with retries. Auto-detects curl/wget. |
<!-- END lib-net-table MARKER -->

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
net__fetch_with_retry curl \
  --compressed -fsSLo /tmp/tool.bin \
  "https://example.com/tool-$(uname -m)"
```

### `ospkg.sh`

<!-- START lib-ospkg-table MARKER -->
| Function | Signature | Description |
|---|---|---|
| `ospkg__detect` | `ospkg__detect` | Detect the package manager and populate internal state. Idempotent; called automatically by all other `ospkg__*` functions. |
| `ospkg__update` | `ospkg__update [--force] [--lists_max_age N] [--repo_added]` | Refresh the package index. Skips when lists are fresh (within `--lists_max_age` seconds). |
| `ospkg__install` | `ospkg__install <pkg>...` | Install one or more packages. Skips if all are already installed (APT, DNF/YUM). |
| `ospkg__clean` | `ospkg__clean` | Remove the package manager cache to reduce image layer size. |
| `ospkg__parse_manifest_yaml` | `ospkg__parse_manifest_yaml <json-file>` | Parse a YAML manifest (pre-converted to JSON by `yq`) and emit normalised installation records to stdout. |
| `ospkg__run` | `ospkg__run [--manifest <f>] [--update <bool>] [--keep_cache] [--keep_repos] [--dry_run] [--skip_installed] [--interactive]` | Run the full installation pipeline from a manifest. |
<!-- END lib-ospkg-table MARKER -->

`ospkg__run` options:

| Option | Default | Description |
|---|---|---|
| `--manifest <file-or-inline>` | `""` | Path to a manifest file, or inline content (detected when the value contains a newline). |
| `--update false` | false | Skip the package list refresh unconditionally. |
| `--keep_cache` | false | Skip the cache clean step (useful when more installs follow). |
| `--keep_repos` | false | Keep repository drop-in files written by `repo` sections. |
| `--lists_max_age <N>` | 300 | Seconds before a package list refresh is considered necessary. |
| `--dry_run` | false | Print what would happen without making any changes. Root not required. |
| `--skip_installed` | false | Skip packages whose binary is already in `PATH`. |
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

<!-- START lib-shell-table MARKER -->
| Function | Signature | Description |
|---|---|---|
| `shell__detect_bashrc` | `shell__detect_bashrc` | Print the system-wide bashrc path for the current distro. Uses binary probing, never file-existence checks. |
| `shell__detect_zshdir` | `shell__detect_zshdir` | Print the system-wide zsh config directory (`/etc/zsh` or `/etc`). Uses binary probing, never directory-existence checks. |
| `shell__write_block` | `shell__write_block --file <f> --marker <id> --content <c>` | Idempotently write a named `# >>> <id> >>>` … `# <<< <id> <<<` block to a file. Creates the file if needed. |
| `shell__sync_block` | `shell__sync_block --files <list> --marker <id> [--content <c>]` | Write (if `--content` given) or remove the named block in each file in the newline-separated list. |
| `shell__user_login_file` | `shell__user_login_file [--home <dir>]` | Print the bash login startup file path (`~/.bash_profile`, `~/.bash_login`, or `~/.profile`). Falls back to `~/.bash_profile`. |
| `shell__system_path_files` | `shell__system_path_files [--profile_d <filename>]` | Print system-wide shell startup file paths for PATH/env injection. |
| `shell__detect_zdotdir` | `shell__detect_zdotdir [--home <dir>]` | Print the effective ZDOTDIR for a user. Probes the live environment, parses system and user zshenv, then falls back to `<home>`. |
| `shell__user_path_files` | `shell__user_path_files [--home <dir>] [--zdotdir <dir>]` | Print user startup file paths for a PATH export: bash login file, `.bashrc`, and `<zdotdir>/.zshenv`. |
| `shell__user_init_files` | `shell__user_init_files [--home <dir>] [--zdotdir <dir>]` | Print user startup file paths for a full initializer: bash login, `.bashrc`, `<zdotdir>/.zprofile`, `<zdotdir>/.zshrc`. |
| `shell__user_rc_files` | `shell__user_rc_files [--home <dir>] [--zdotdir <dir>]` | Print user-scoped interactive RC file paths (`.bashrc`, `<zdotdir>/.zshrc`). Excludes login files. |
| `shell__system_rc_files` | `shell__system_rc_files` | Print system-wide interactive RC file paths (global bashrc, `<zshdir>/zshrc`). Does not include login or PATH-export files. |
| `shell__resolve_omz_theme` | `shell__resolve_omz_theme --theme_slug <slug> --custom_dir <dir>` | Given an `owner/repo` slug and `ZSH_CUSTOM` dir, print the `ZSH_THEME` value expected by oh-my-zsh. |
| `shell__plugin_names_from_slugs` | `shell__plugin_names_from_slugs <csv-slugs>` | Extract repo names (basenames) from a comma-separated list of `owner/repo` slugs. Prints one name per line. |
| `shell__resolve_home` | `shell__resolve_home <username>` | Print the home directory for the given user. |
| `shell__ensure_bashenv` | `shell__ensure_bashenv` | Detect or create the system-wide BASH_ENV file and register it in `/etc/environment`. Print the absolute path to the file. |
| `shell__create_symlink` | `shell__create_symlink --src <s> --system-target <t> --user-target <t>` | Create a symlink, choosing system-wide or user-scoped location based on the src path. |
<!-- END lib-shell-table MARKER -->

### `git.sh`

<!-- START lib-git-table MARKER -->
| Function | Signature | Description |
|---|---|---|
| `git__clone` | `git__clone --url <url> --dir <dir> [--branch <branch>]` | Shallow clone (`--depth=1`) of `<url>` into `<dir>`. Idempotent; skips if `<dir>/.git` already exists. |
<!-- END lib-git-table MARKER -->

### `github.sh`

Source explicitly. Requires `net.sh` (and `ospkg.sh`) to have been sourced first. Respects the `GITHUB_TOKEN` environment variable for all API calls.

<!-- START lib-github-table MARKER -->
| Function | Signature | Description |
|---|---|---|
| `github__fetch_release_json` | `github__fetch_release_json <owner/repo> [--tag <tag>] [--dest <file>]` | Fetch GitHub Releases API JSON for a repository. |
| `github__latest_tag` | `github__latest_tag <owner/repo>` | Print the latest release tag name. Exits 1 if the API call fails or the tag cannot be parsed. |
| `github__release_tags` | `github__release_tags <owner/repo> [--per_page N]` | Print one release tag per line (newest first) from `/releases?per_page=N` (default 100). |
| `github__tags` | `github__tags <owner/repo> [--per_page N]` | Print one tag per line from `/tags?per_page=N` (default 100). Includes lightweight tags not associated with a release. |
| `github__release_asset_urls` | `github__release_asset_urls <owner/repo> [--tag <tag>] [--filter <ere>]` | Print `browser_download_url` values from a release. `--filter` applies an ERE grep to the URL list. |
| `github__pick_release_asset` | `github__pick_release_asset <owner/repo> [--tag <tag>] [--asset-regex <ERE>]` | Select a single release asset URL using heuristic arch/platform filters. |
<!-- END lib-github-table MARKER -->

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

<!-- START lib-checksum-table MARKER -->
| Function | Signature | Description |
|---|---|---|
| `checksum__verify_sha256` | `checksum__verify_sha256 <file> <expected_hash>` | Verify the SHA-256 digest of `<file>`. Uses `sha256sum` (Linux) or `shasum -a 256` (macOS). Returns 1 on mismatch. |
| `checksum__verify_sha256_sidecar` | `checksum__verify_sha256_sidecar <file> <sha256_file>` | Read the expected hash from the first field of `<sha256_file>` and delegate to `checksum__verify_sha256`. |
<!-- END lib-checksum-table MARKER -->

Typical pattern:

```bash
net__fetch_url_file "$DOWNLOAD_URL" /tmp/tool.bin
net__fetch_url_file "$DOWNLOAD_URL.sha256" /tmp/tool.bin.sha256
checksum__verify_sha256_sidecar /tmp/tool.bin /tmp/tool.bin.sha256
```

### `users.sh`

Source explicitly. Reads the standard devcontainer user-config env vars
(`ADD_CURRENT_USER`, `ADD_REMOTE_USER`, `ADD_CONTAINER_USER`,
`ADD_USERS`).

<!-- START lib-users-table MARKER -->
| Function | Signature | Description |
|---|---|---|
| `users__resolve_list` | `users__resolve_list` | Print one deduplicated username per line from devcontainer user-config env vars. |
| `users__set_write_permissions` | `users__set_write_permissions <prefix> <owner> <group> [<user>...]` |  |
| `users__set_login_shell` | `users__set_login_shell <shell_path> <username>...` | Register `<shell_path>` in `/etc/shells`, patch Alpine PAM if needed, then call `chsh -s` for each user. |
<!-- END lib-users-table MARKER -->

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
`install.bash` via `_FILES_DIR="${_BASE_DIR}/files"`.

```bash
_FILES_DIR="${_BASE_DIR}/files"
cp "${_FILES_DIR}/my-config.conf" /etc/my-config.conf
```

---

## Sync and pre-commit

After creating or editing `install.bash`, run:

```bash
bash sync-lib.sh
```

This generates `install.sh` (bootstrap) and `_lib/` for your new
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
