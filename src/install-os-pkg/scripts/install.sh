#!/usr/bin/env bash
set -euo pipefail

_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$_SELF_DIR/_lib/ospkg.sh"
. "$_SELF_DIR/_lib/logging.sh"
logging::setup
echo "↪️ Script entry: System Package Installation" >&2
trap 'logging::cleanup' EXIT

if [ "$#" -gt 0 ]; then
  echo "ℹ️ Script called with arguments: $@" >&2
  DEBUG=""
  DIR=""
  INTERACTIVE=""
  KEEP_REPOS=""
  LIFECYCLE_HOOK=""
  LOGFILE=""
  MANIFEST=""
  NO_CLEAN=""
  NO_UPDATE=""
  LISTS_MAX_AGE=""
  DRY_RUN=""
  CHECK_INSTALLED=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --debug) shift; DEBUG=true; echo "📩 Read argument 'debug': '"$DEBUG"'" >&2;;
      --dir) shift; DIR="$1"; echo "📩 Read argument 'dir': '"$DIR"'" >&2; shift;;
      --install_self) shift; INSTALL_SELF="$1"; echo "📩 Read argument 'install_self': '"$INSTALL_SELF"'" >&2; shift;;
      --interactive) shift; INTERACTIVE=true; echo "📩 Read argument 'interactive': '"$INTERACTIVE"'" >&2;;
      --keep_repos) shift; KEEP_REPOS=true; echo "📩 Read argument 'keep_repos': '"$KEEP_REPOS"'" >&2;;
      --lifecycle_hook) shift; LIFECYCLE_HOOK="$1"; echo "📩 Read argument 'lifecycle_hook': '"$LIFECYCLE_HOOK"'" >&2; shift;;
      --logfile) shift; LOGFILE="$1"; echo "📩 Read argument 'logfile': '"$LOGFILE"'" >&2; shift;;
      --manifest) shift; MANIFEST="$1"; echo "📩 Read argument 'manifest': '"$MANIFEST"'" >&2; shift;;
      --no_clean) shift; NO_CLEAN=true; echo "📩 Read argument 'no_clean': '"$NO_CLEAN"'" >&2;;
      --no_update) shift; NO_UPDATE=true; echo "📩 Read argument 'no_update': '"$NO_UPDATE"'" >&2;;
      --lists_max_age) shift; LISTS_MAX_AGE="$1"; echo "📩 Read argument 'lists_max_age': '"$LISTS_MAX_AGE"'" >&2; shift;;
      --dry_run) shift; DRY_RUN=true; echo "📩 Read argument 'dry_run': '"$DRY_RUN"'" >&2;;
      --check_installed) shift; CHECK_INSTALLED=true; echo "📩 Read argument 'check_installed': '"$CHECK_INSTALLED"'" >&2;;
      --*) echo "⛔ Unknown option: "$1"" >&2; exit 1;;
      *) echo "⛔ Unexpected argument: "$1"" >&2; exit 1;;
    esac
  done
else
  echo "ℹ️ Script called with no arguments. Read environment variables." >&2
  [ "${DEBUG+defined}" ] && echo "📩 Read argument 'debug': '"$DEBUG"'" >&2
  [ "${INSTALL_SELF+defined}" ] && echo "📩 Read argument 'install_self': '"$INSTALL_SELF"'" >&2
  [ "${INTERACTIVE+defined}" ] && echo "📩 Read argument 'interactive': '"$INTERACTIVE"'" >&2
  [ "${KEEP_REPOS+defined}" ] && echo "📩 Read argument 'keep_repos': '"$KEEP_REPOS"'" >&2
  [ "${LIFECYCLE_HOOK+defined}" ] && echo "📩 Read argument 'lifecycle_hook': '"$LIFECYCLE_HOOK"'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '"$LOGFILE"'" >&2
  [ "${MANIFEST+defined}" ] && echo "📩 Read argument 'manifest': '"$MANIFEST"'" >&2
  [ "${NO_CLEAN+defined}" ] && echo "📩 Read argument 'no_clean': '"$NO_CLEAN"'" >&2
  [ "${NO_UPDATE+defined}" ] && echo "📩 Read argument 'no_update': '"$NO_UPDATE"'" >&2
  [ "${LISTS_MAX_AGE+defined}" ] && echo "📩 Read argument 'lists_max_age': '"$LISTS_MAX_AGE"'" >&2
  [ "${DRY_RUN+defined}" ] && echo "📩 Read argument 'dry_run': '"$DRY_RUN"'" >&2
  [ "${CHECK_INSTALLED+defined}" ] && echo "📩 Read argument 'check_installed': '"$CHECK_INSTALLED"'" >&2
fi

[[ "$DEBUG" == true ]] && set -x
: "${DEBUG:=false}"
: "${INSTALL_SELF:=true}"
: "${MANIFEST:=}"
if [[ -z "$MANIFEST" && "$INSTALL_SELF" != true ]]; then
    echo "⛔ 'MANIFEST' is required when 'install_self' is false." >&2; exit 1
fi
# Normalize: some environments (e.g. devcontainer CLI build args) serialize
# multi-line strings with literal \n rather than real newlines.  Expand them
# so inline-manifest detection works correctly.
if [[ -n "$MANIFEST" && "$MANIFEST" != *$'\n'* && "$MANIFEST" == *'\n'* ]]; then
    MANIFEST="$(printf '%b' "$MANIFEST")"
    echo "ℹ️  Expanded literal \\n escapes in MANIFEST value." >&2
fi
: "${INTERACTIVE:=false}"
: "${KEEP_REPOS:=false}"
: "${LIFECYCLE_HOOK:=}"
if [[ -n "$LIFECYCLE_HOOK" ]]; then
    case "$LIFECYCLE_HOOK" in
        onCreate|updateContent|postCreate) ;;
        *) echo "⛔ Invalid lifecycle_hook value: '$LIFECYCLE_HOOK'. Must be one of: onCreate, updateContent, postCreate." >&2; exit 1;;
    esac
    if [[ -z "$MANIFEST" ]]; then
        echo "⛔ 'manifest' is required when 'lifecycle_hook' is set." >&2; exit 1
    fi
fi
: "${LOGFILE:=}"
: "${NO_CLEAN:=false}"
: "${NO_UPDATE:=false}"
: "${LISTS_MAX_AGE:=300}"
if ! [[ "$LISTS_MAX_AGE" =~ ^[0-9]+$ ]]; then
    echo "⛔ Invalid lists_max_age value: '$LISTS_MAX_AGE'. Must be a non-negative integer." >&2; exit 1
fi
: "${DRY_RUN:=false}"
: "${CHECK_INSTALLED:=false}"

# Install the system command so other features/scripts can call 'install-os-pkg'
# directly.  Done unconditionally (before lifecycle_hook early exit) so the
# library files exist when hook scripts reference the installed copy at runtime.
if [[ "$INSTALL_SELF" == true ]]; then
    _LIB_DIR="/usr/local/lib/install-os-pkg"
    _BIN="/usr/local/bin/install-os-pkg"
    if [ ! -x "$_BIN" ]; then
        mkdir -p "$_LIB_DIR"
        cp "$0" "$_LIB_DIR/install.sh"
        chmod +x "$_LIB_DIR/install.sh"
        cp -r "$_SELF_DIR/_lib" "$_LIB_DIR/"
        printf '#!/bin/sh\nexec bash "%s/install.sh" "$@"\n' "$_LIB_DIR" > "$_BIN"
        chmod +x "$_BIN"
        echo "✅ Installed system command: $_BIN" >&2
    fi
else
    echo "ℹ️ Skipping system command installation (install_self=false)." >&2
fi

# When lifecycle_hook is set, write a hook script and exit without installing.
if [[ -n "$LIFECYCLE_HOOK" ]]; then
    _HOOK_DIR="/usr/local/share/install-os-pkg"
    mkdir -p "$_HOOK_DIR"
    _MANIFEST_ARG="$MANIFEST"
    if [[ "$MANIFEST" == *$'\n'* ]]; then
        printf '%s' "$MANIFEST" > "$_HOOK_DIR/manifest.txt"
        _MANIFEST_ARG="$_HOOK_DIR/manifest.txt"
        echo "ℹ️  Saved inline manifest to '$_MANIFEST_ARG'." >&2
    fi
    _HOOK_OPTS="--manifest $(printf '%q' "$_MANIFEST_ARG")"
    [[ "$DEBUG" == true ]] && _HOOK_OPTS+=" --debug"
    [[ "$INTERACTIVE" == true ]] && _HOOK_OPTS+=" --interactive"
    [[ "$KEEP_REPOS" == true ]] && _HOOK_OPTS+=" --keep_repos"
    [[ -n "$LOGFILE" ]] && _HOOK_OPTS+=" --logfile $(printf '%q' "$LOGFILE")"
    [[ "$NO_CLEAN" == true ]] && _HOOK_OPTS+=" --no_clean"
    [[ "$NO_UPDATE" == true ]] && _HOOK_OPTS+=" --no_update"
    _HOOK_OPTS+=" --lists_max_age $LISTS_MAX_AGE"
    [[ "$DRY_RUN" == true ]] && _HOOK_OPTS+=" --dry_run"
    [[ "$CHECK_INSTALLED" == true ]] && _HOOK_OPTS+=" --check_installed"
    case "$LIFECYCLE_HOOK" in
        onCreate)       _HOOK_FILE="$_HOOK_DIR/on-create.sh" ;;
        updateContent)  _HOOK_FILE="$_HOOK_DIR/update-content.sh" ;;
        postCreate)     _HOOK_FILE="$_HOOK_DIR/post-create.sh" ;;
    esac
    printf '#!/bin/sh\nset -e\nexec bash "%s" %s\n' \
        "/usr/local/lib/install-os-pkg/install.sh" "$_HOOK_OPTS" > "$_HOOK_FILE"
    chmod +x "$_HOOK_FILE"
    echo "✅ Registered lifecycle hook '$LIFECYCLE_HOOK': $_HOOK_FILE" >&2
    exit 0
fi

_OSPKG_ARGS=()
[[ -n "$MANIFEST" ]] && _OSPKG_ARGS+=(--manifest "$MANIFEST")
[[ "$NO_UPDATE" == true ]] && _OSPKG_ARGS+=(--no_update)
[[ "$NO_CLEAN" == true ]] && _OSPKG_ARGS+=(--no_clean)
[[ "$KEEP_REPOS" == true ]] && _OSPKG_ARGS+=(--keep_repos)
_OSPKG_ARGS+=(--lists_max_age "$LISTS_MAX_AGE")
[[ "$DRY_RUN" == true ]] && _OSPKG_ARGS+=(--dry_run)
[[ "$CHECK_INSTALLED" == true ]] && _OSPKG_ARGS+=(--check_installed)
[[ "$INTERACTIVE" == true ]] && _OSPKG_ARGS+=(--interactive)
ospkg::run "${_OSPKG_ARGS[@]}"
echo "✅ Package installation complete."
echo "↩️ Script exit: System Package Installation" >&2

