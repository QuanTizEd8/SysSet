---
description: "Use when writing, editing, or creating feature installer scripts under src/**/scripts/ or shared library modules under lib/. Covers the bootstrap pattern, library sourcing, logging setup, dual-mode argument parsing, emoji conventions, and the full shared library API."
applyTo: "src/**/scripts/*.sh, lib/*.sh"
---

# Feature Installer Script Conventions

## File Header

```bash
#!/usr/bin/env bash
set -euo pipefail

_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
_BASE_DIR="$(cd "$_SELF_DIR/.." && pwd)"   # Feature root: src/<feature>/
```

## Library Sourcing

Source from `_SELF_DIR/_lib/` (the generated copy of `lib/`). **`ospkg.sh` must be sourced first** — it internally sources `os.sh` and `net.sh`, making all three available.

```bash
. "$_SELF_DIR/_lib/ospkg.sh"      # Provides ospkg::*, os::*, net::* — source first
. "$_SELF_DIR/_lib/logging.sh"    # Always include
. "$_SELF_DIR/_lib/git.sh"        # Only if git::clone is needed
. "$_SELF_DIR/_lib/shell.sh"      # Only if shell::* helpers are needed
```

## Logging Setup

Always call `logging::setup` immediately after sourcing, before any output:

```bash
logging::setup
trap 'logging::cleanup' EXIT
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
ospkg::run --manifest "${_BASE_DIR}/dependencies/base.txt" --check_installed
```

`--check_installed` skips packages already present (idempotent). Omit `--check_installed` when upgrading is desired.

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

Every function must end with an explicit `return` statement (even if it always returns 0). This applies to all functions in both `scripts/` and `lib/`.

## Guard Pattern (lib/ modules only)

All `lib/*.sh` modules must start with an idempotency guard:

```bash
[[ -n "${_LIB_MYMODULE_LOADED-}" ]] && return 0
_LIB_MYMODULE_LOADED=1
```

## Shared Library API

### `ospkg.sh`

- `ospkg::detect` — auto-detect package manager (called automatically by other ospkg functions)
- `ospkg::install <pkg>...` — install one or more packages
- `ospkg::update` — refresh package index
- `ospkg::clean` — clean package caches
- `ospkg::run [--manifest <file>] [--check_installed] [--no_clean] [--no_update] [--dry_run]` — full pipeline: update → install from manifest → clean

### `net.sh` (auto-sourced by ospkg.sh)

- `net::fetch_url_stdout <url>` — fetch URL to stdout; auto-selects curl/wget; 3 retries
- `net::fetch_url_file <url> <dest>` — fetch URL to file
- `net::fetch_with_retry <max-attempts> <cmd...>` — generic retry wrapper; 3-second pause between attempts
- `net::ensure_fetch_tool` — ensure curl or wget is available (installs curl if neither found)
- `net::ensure_ca_certs` — ensure `/etc/ssl/certs/ca-certificates.crt` is present

### `os.sh` (auto-sourced by ospkg.sh)

- `os::require_root` — exits 1 with message if current user is not root

### `logging.sh`

- `logging::setup` — tee stdout+stderr into a temp file; saves original fds as fd 3/4; sets `_LOGFILE_TMP`
- `logging::cleanup` — flushes temp log to `$LOGFILE` (if set), restores fds; call from EXIT trap only

### `git.sh`

- `git::clone --url <url> --dir <dir> [--branch <branch>]` — depth-1 clone; idempotent (skips if `<dir>/.git` exists); removes partial clone on failure

### `shell.sh`

- `shell::detect_bashrc` — returns `/etc/bash.bashrc`, `/etc/bashrc`, or `/etc/bash/bashrc`
- `shell::detect_zshdir` — returns `/etc/zsh` or `/etc`
- `shell::resolve_home <user>` — evaluates `~<user>` to absolute path
- `shell::resolve_omz_theme --theme_slug <slug> --custom_dir <dir>` — resolves Oh My Zsh theme path
- `shell::plugin_names_from_slugs <csv>` — converts comma-separated plugin slugs to plugin names

## Further Reading

- `docs/dev-guide/writing-features.md` — feature anatomy, options, scripts, full library reference
