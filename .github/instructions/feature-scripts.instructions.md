---
description: "Use when writing, editing, or creating feature installer scripts under features/**/*.bash or shared library modules under lib/. Covers the bootstrap pattern, library sourcing, logging setup, dual-mode argument parsing, emoji conventions, and the full shared library API."
applyTo: "features/**/*.bash, lib/*.sh"
---

# Feature Installer Script Conventions

## File Header

```bash
#!/usr/bin/env bash
set -euo pipefail

_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
_BASE_DIR="$(cd "$_SELF_DIR/.." && pwd)"   # Feature root: src/<feature>/ (assembled by sync-lib.sh)
```

## Library-First Principle

**Always check `lib/` before writing inline logic.** If a function already exists in the shared library, use it — do not reimplement it. Common mistakes to avoid:

- Calling `uname -s` / `uname -m` directly → use `os__kernel` / `os__arch` instead.
- Detecting the font directory with an if/elif block → use `os__font_dir`.
- Hand-rolling a GitHub API call with curl → use `github__fetch_release_json`, `github__latest_tag`, or `github__release_tags`.
- Implementing SHA-256 verification inline → use `checksum__verify_sha256` or `checksum__verify_sha256_sidecar`.
- Resolving devcontainer user lists with a local associative array → use `users__resolve_list`.
- Calling `chsh` manually for a list of users → use `users__set_login_shell`.

**When adding new logic**, ask: could this be useful in more than one feature, or does it encapsulate a detail that is easy to get wrong? If yes, add it to `lib/` rather than keeping it inline. After adding to `lib/`, run `bash sync-lib.sh` to propagate it to all features.

## Library Sourcing

Source from `_SELF_DIR/_lib/` (the generated copy of `lib/`). **`ospkg.sh` must be sourced first** — it internally sources `os.sh` and `net.sh`, making all three available. Source additional modules explicitly when their functions are needed.

```bash
. "$_SELF_DIR/_lib/ospkg.sh"      # Provides ospkg::*, os::*, net::* — source first
. "$_SELF_DIR/_lib/logging.sh"    # Always include
. "$_SELF_DIR/_lib/json.sh"       # Only if json::* helpers are needed without github (github.sh loads json.sh itself)
. "$_SELF_DIR/_lib/github.sh"     # Only if github::* helpers are needed
. "$_SELF_DIR/_lib/checksum.sh"   # Only if checksum::* helpers are needed
. "$_SELF_DIR/_lib/users.sh"      # Only if users::* helpers are needed
. "$_SELF_DIR/_lib/shell.sh"      # Only if shell::* helpers are needed
. "$_SELF_DIR/_lib/git.sh"        # Only if git__clone is needed
```

## Logging Setup

Always call `logging__setup` immediately after sourcing, before any output:

```bash
logging__setup
trap 'logging__cleanup' EXIT
```

## Dual-Mode Argument Parsing

The devcontainer CLI passes options as environment variables,
whereas direct script invocation uses CLI flags.
Support both:

```bash
if [[ "$#" -gt 0 ]]; then
  OPTNAME=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --optname) shift; OPTNAME="$1"; shift;;
      --debug)   shift; DEBUG="$1";   shift;;
      --logfile) shift; LOGFILE="$1"; shift;;
      --*) echo "⛔ Unknown option: '${1}'" >&2; exit 1;;
      *)   echo "⛔ Unexpected argument: '${1}'" >&2; exit 1;;
    esac
  done
else
  [ "${OPTNAME+defined}" ] && echo "📩 Read argument 'optname': '${OPTNAME}'" >&2
  [ "${DEBUG+defined}"   ] && echo "📩 Read argument 'debug': '${DEBUG}'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
fi

[[ "$DEBUG" == true ]] && set -x

# Apply defaults AFTER parsing
[ -z "${OPTNAME-}" ] && OPTNAME="default_value"
[ -z "${DEBUG-}"   ] && DEBUG=false
[ -z "${LOGFILE-}" ] && LOGFILE=""
```

## OS Package Dependencies

```bash
ospkg__run --manifest "${_BASE_DIR}/dependencies/base.yaml" --skip_installed
```

`--skip_installed` skips packages already present (idempotent). Omit `--skip_installed` when upgrading is desired.

## Emoji Log Conventions

| Emoji | Meaning |
|-------|---------|
| ⛔ | Error / fatal |
| ⚠️ | Warning |
| ℹ️ | Informational |
| ✅ | Success |
| 📩 | Variable read from environment |
| ↪️ | Script entry |
| ↩️ | Script exit |

## Return Statements

Every function must end with an explicit `return` statement (even if it always returns 0). This applies to all functions in both `install.bash` and `lib/`.

## Guard Pattern (lib/ modules only)

All `lib/*.sh` modules must start with an idempotency guard:

```bash
[[ -n "${_LIB_MYMODULE_LOADED-}" ]] && return 0
_LIB_MYMODULE_LOADED=1
```

## Shared Library API

### `ospkg.sh`

- `ospkg__detect` — auto-detect package manager (called automatically by other ospkg functions)
- `ospkg__install <pkg>...` — install one or more packages
- `ospkg__update` — refresh package index
- `ospkg__clean` — clean package caches
- `ospkg__run [--manifest <file>] [--skip_installed] [--keep_cache] [--update false] [--dry_run]` — full pipeline: update → install from manifest → clean

### `net.sh` (auto-sourced by ospkg.sh)

- `net__fetch_url_stdout <url>` — fetch URL to stdout; auto-selects curl/wget; 3 retries
- `net__fetch_url_file <url> <dest>` — fetch URL to file
- `net__fetch_with_retry [--retries N] [--delay N] <cmd...>` — generic retry wrapper; defaults to 60 retries × 5s delay

### `os.sh` (auto-sourced by ospkg.sh)

- `os__require_root` — exits 1 with message if current user is not root
- `os__kernel` — prints `uname -s` result (cached); use instead of calling `uname -s` directly
- `os__arch` — prints `uname -m` result (cached); use instead of calling `uname -m` directly
- `os__id` — prints the `ID` field from `/etc/os-release` (e.g. `ubuntu`, `alpine`)
- `os__id_like` — prints the `ID_LIKE` field from `/etc/os-release`
- `os__platform` — prints a canonical tag: `debian` | `alpine` | `rhel` | `macos`
- `os__font_dir` — prints the appropriate font directory for the current user (`/usr/share/fonts` when root; `~/Library/Fonts` on macOS; `${XDG_DATA_HOME:-~/.local/share}/fonts` otherwise)

### `logging.sh`

- `logging__setup` — tee stdout+stderr into a temp file; saves original fds as fd 3/4; sets `_LOGFILE_TMP`
- `logging__cleanup` — flushes temp log to `$LOGFILE` (if set), restores fds; call from EXIT trap only

### `git.sh`

- `git__clone --url <url> --dir <dir> [--branch <branch>]` — depth-1 clone; idempotent (skips if `<dir>/.git` exists); removes partial clone on failure

### `shell.sh`

- `shell__detect_bashrc` — returns `/etc/bash.bashrc`, `/etc/bashrc`, or `/etc/bash/bashrc`
- `shell__detect_zshdir` — returns `/etc/zsh` or `/etc`
- `shell__resolve_home <user>` — evaluates `~<user>` to absolute path
- `shell__resolve_omz_theme --theme_slug <slug> --custom_dir <dir>` — resolves Oh My Zsh theme path
- `shell__plugin_names_from_slugs <csv>` — converts comma-separated plugin slugs to plugin names
- `shell__write_block --file <f> --marker <m> --content <c>` — writes a fenced block into a file; idempotent (replaces existing block with same marker)
- `shell__remove_block --file <f> --marker <m>` — removes a fenced block from a file
- `shell__export_path --users <list> --path <dir> [--marker <m>] [--rc_files <list>]` — appends a `PATH` export block to each user's shell RC files
- `shell__export_env --users <list> --name <VAR> --value <val> [--marker <m>] [--rc_files <list>]` — appends an `export VAR=val` block to each user's shell RC files

### `github.sh`

Source explicitly: `. "$_SELF_DIR/_lib/github.sh"`. Respects `GITHUB_TOKEN` for all API calls.

- `github__fetch_release_json <owner/repo> [--tag <tag>] [--dest <file>]` — fetches GitHub Releases API JSON; without `--tag` fetches `/releases/latest`; without `--dest` writes to stdout
- `github__latest_tag <owner/repo>` — prints the latest release tag name; exits 1 on failure
- `github__release_tags <owner/repo> [--per_page <n>]` — prints one tag per line (newest first) from `/releases?per_page=<n>` (default 100)
- `github__release_asset_urls <owner/repo> [--tag <tag>] [--filter <ere>]` — prints `browser_download_url` values from a release, optionally filtered by extended-regex pattern

### `checksum.sh`

Source explicitly: `. "$_SELF_DIR/_lib/checksum.sh"`. Works with `sha256sum` (Linux) or `shasum` (macOS) transparently.

- `checksum__verify_sha256 <file> <expected_hash>` — verifies the SHA-256 digest of a file; exits 1 on mismatch
- `checksum__verify_sha256_sidecar <file> <sha256_file>` — reads the expected hash from the first field of `<sha256_file>` then delegates to `checksum__verify_sha256`; use for `.sha256` sidecar files

### `users.sh`

Source explicitly: `. "$_SELF_DIR/_lib/users.sh"`. Reads the standard devcontainer user env vars (`ADD_CURRENT_USER`, `ADD_REMOTE_USER`, `ADD_CONTAINER_USER`, `ADD_USERS`).

- `users__resolve_list` — prints one deduplicated username per line; root is excluded from auto-detected paths (CURRENT, REMOTE, CONTAINER) but **allowed** when explicitly listed in `ADD_USERS`; collect with `mapfile -t _USERS < <(users__resolve_list)` in bash or iterate with a `while read` loop in sh
- `users__set_login_shell <shell_path> <username>...` — registers `<shell_path>` in `/etc/shells`, patches Alpine PAM if needed, and calls `chsh -s` for each user; skips users already on that shell; warns (does not abort) on `chsh` failure

## Further Reading

- `docs/dev-guide/writing-features.md` — feature anatomy, options, scripts, full library reference
