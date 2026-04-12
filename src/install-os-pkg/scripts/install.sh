#!/usr/bin/env bash
set -euo pipefail

_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/ospkg.sh
. "$_SELF_DIR/_lib/ospkg.sh"
# shellcheck source=lib/logging.sh
. "$_SELF_DIR/_lib/logging.sh"
logging::setup
echo "↪️ Script entry: System Package Installation" >&2
trap 'logging::cleanup' EXIT

if [ "$#" -gt 0 ]; then
  echo "ℹ️ Script called with arguments: $*" >&2
  DEBUG=""
  INTERACTIVE=""
  KEEP_REPOS=""
  LIFECYCLE_HOOK=""
  LOGFILE=""
  MANIFEST=""
  KEEP_CACHE=""
  UPDATE=""
  LISTS_MAX_AGE=""
  DRY_RUN=""
  SKIP_INSTALLED=""
  PREFER_LINUXBREW=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --debug)
        shift
        DEBUG=true
        echo "📩 Read argument 'debug': '${DEBUG}'" >&2
        ;;
      --install_self)
        shift
        INSTALL_SELF="$1"
        echo "📩 Read argument 'install_self': '${INSTALL_SELF}'" >&2
        shift
        ;;
      --interactive)
        shift
        INTERACTIVE=true
        echo "📩 Read argument 'interactive': '${INTERACTIVE}'" >&2
        ;;
      --keep_repos)
        shift
        KEEP_REPOS=true
        echo "📩 Read argument 'keep_repos': '${KEEP_REPOS}'" >&2
        ;;
      --lifecycle_hook)
        shift
        LIFECYCLE_HOOK="$1"
        echo "📩 Read argument 'lifecycle_hook': '${LIFECYCLE_HOOK}'" >&2
        shift
        ;;
      --logfile)
        shift
        LOGFILE="$1"
        echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
        shift
        ;;
      --manifest)
        shift
        MANIFEST="$1"
        echo "📩 Read argument 'manifest': '${MANIFEST}'" >&2
        shift
        ;;
      --keep_cache | --no_clean)
        shift
        KEEP_CACHE=true
        echo "📩 Read argument 'keep_cache': '${KEEP_CACHE}'" >&2
        ;;
      --update)
        shift
        UPDATE="$1"
        echo "📩 Read argument 'update': '${UPDATE}'" >&2
        shift
        ;;
      --no_update)
        shift
        UPDATE=false
        echo "📩 Read argument 'no_update' (alias for update=false): 'false'" >&2
        ;;
      --lists_max_age)
        shift
        LISTS_MAX_AGE="$1"
        echo "📩 Read argument 'lists_max_age': '${LISTS_MAX_AGE}'" >&2
        shift
        ;;
      --dry_run)
        shift
        DRY_RUN=true
        echo "📩 Read argument 'dry_run': '${DRY_RUN}'" >&2
        ;;
      --skip_installed | --check_installed)
        shift
        SKIP_INSTALLED=true
        echo "📩 Read argument 'skip_installed': '${SKIP_INSTALLED}'" >&2
        ;;
      --prefer_linuxbrew)
        shift
        PREFER_LINUXBREW=true
        echo "📩 Read argument 'prefer_linuxbrew': '${PREFER_LINUXBREW}'" >&2
        ;;
      --*)
        echo "⛔ Unknown option: '${1}'" >&2
        exit 1
        ;;
      *)
        echo "⛔ Unexpected argument: '${1}'" >&2
        exit 1
        ;;
    esac
  done
else
  echo "ℹ️ Script called with no arguments. Read environment variables." >&2
  [ "${DEBUG+defined}" ] && echo "📩 Read argument 'debug': '${DEBUG}'" >&2
  [ "${INSTALL_SELF+defined}" ] && echo "📩 Read argument 'install_self': '${INSTALL_SELF}'" >&2
  [ "${INTERACTIVE+defined}" ] && echo "📩 Read argument 'interactive': '${INTERACTIVE}'" >&2
  [ "${KEEP_REPOS+defined}" ] && echo "📩 Read argument 'keep_repos': '${KEEP_REPOS}'" >&2
  [ "${LIFECYCLE_HOOK+defined}" ] && echo "📩 Read argument 'lifecycle_hook': '${LIFECYCLE_HOOK}'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
  [ "${MANIFEST+defined}" ] && echo "📩 Read argument 'manifest': '${MANIFEST}'" >&2
  [ "${KEEP_CACHE+defined}" ] && echo "📩 Read argument 'keep_cache': '${KEEP_CACHE}'" >&2
  # Back-compat: honour NO_CLEAN env var (old name).
  if [ "${NO_CLEAN+defined}" ] && [ -z "${KEEP_CACHE:-}" ]; then
    KEEP_CACHE="${NO_CLEAN:-}"
    echo "📩 Read argument 'no_clean' (env alias): '${KEEP_CACHE}'" >&2
  fi
  [ "${UPDATE+defined}" ] && echo "📩 Read argument 'update': '${UPDATE}'" >&2
  # Back-compat: honour NO_UPDATE env var (old name, inverted).
  if [ "${NO_UPDATE+defined}" ] && [ -z "${UPDATE:-}" ]; then
    if [ "${NO_UPDATE:-}" = "true" ]; then UPDATE=false; else UPDATE=true; fi
    echo "📩 Read argument 'no_update' (env alias): mapping to update='${UPDATE}'" >&2
  fi
  [ "${LISTS_MAX_AGE+defined}" ] && echo "📩 Read argument 'lists_max_age': '${LISTS_MAX_AGE}'" >&2
  [ "${DRY_RUN+defined}" ] && echo "📩 Read argument 'dry_run': '${DRY_RUN}'" >&2
  [ "${SKIP_INSTALLED+defined}" ] && echo "📩 Read argument 'skip_installed': '${SKIP_INSTALLED}'" >&2
  # Back-compat: honour CHECK_INSTALLED env var (old name).
  if [ "${CHECK_INSTALLED+defined}" ] && [ -z "${SKIP_INSTALLED:-}" ]; then
    SKIP_INSTALLED="${CHECK_INSTALLED:-}"
    echo "📩 Read argument 'check_installed' (env alias): '${SKIP_INSTALLED}'" >&2
  fi
  [ "${PREFER_LINUXBREW+defined}" ] && echo "📩 Read argument 'prefer_linuxbrew': '${PREFER_LINUXBREW}'" >&2
fi

[[ "${DEBUG:-}" == true ]] && set -x
: "${DEBUG:=false}"
: "${INSTALL_SELF:=false}"
: "${MANIFEST:=}"
if [[ -z "$MANIFEST" && "$INSTALL_SELF" != true ]]; then
  echo "⛔ 'MANIFEST' is required when 'install_self' is false." >&2
  exit 1
fi
# Normalize: some environments (e.g. devcontainer CLI build args) serialize
# multi-line strings with literal \n rather than real newlines.  Expand them
# so inline-manifest detection works correctly.
if [[ -n "$MANIFEST" && "$MANIFEST" != *$'\n'* && "$MANIFEST" == *'\n'* ]]; then
  MANIFEST="$(printf '%b' "$MANIFEST")"
  printf 'ℹ️  Expanded literal \\n escapes in MANIFEST value.\n' >&2
fi
: "${INTERACTIVE:=false}"
: "${KEEP_REPOS:=false}"
: "${LIFECYCLE_HOOK:=}"
if [[ -n "$LIFECYCLE_HOOK" ]]; then
  case "$LIFECYCLE_HOOK" in
    onCreate | updateContent | postCreate) ;;
    *)
      echo "⛔ Invalid lifecycle_hook value: '$LIFECYCLE_HOOK'. Must be one of: onCreate, updateContent, postCreate." >&2
      exit 1
      ;;
  esac
  if [[ -z "$MANIFEST" ]]; then
    echo "⛔ 'manifest' is required when 'lifecycle_hook' is set." >&2
    exit 1
  fi
fi
: "${LOGFILE:=}"
: "${KEEP_CACHE:=false}"
: "${UPDATE:=true}"
: "${LISTS_MAX_AGE:=300}"
if ! [[ "$LISTS_MAX_AGE" =~ ^[0-9]+$ ]]; then
  echo "⛔ Invalid lists_max_age value: '$LISTS_MAX_AGE'. Must be a non-negative integer." >&2
  exit 1
fi
: "${DRY_RUN:=false}"
: "${SKIP_INSTALLED:=false}"
: "${PREFER_LINUXBREW:=false}"

# Always install the backing library so lifecycle hook scripts can reference it.
# The user-visible wrapper script (/usr/local/bin/install-os-pkg) is optional
# and only written when install_self=true.
_LIB_DIR="/usr/local/lib/install-os-pkg"
if [ ! -d "$_LIB_DIR" ]; then
  mkdir -p "$_LIB_DIR"
  cp "$0" "$_LIB_DIR/install.sh"
  chmod +x "$_LIB_DIR/install.sh"
  cp -r "$_SELF_DIR/_lib" "$_LIB_DIR/"
fi

if [[ "$INSTALL_SELF" == true ]]; then
  _BIN="/usr/local/bin/install-os-pkg"
  if [ ! -x "$_BIN" ]; then
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
  [[ "$KEEP_CACHE" == true ]] && _HOOK_OPTS+=" --keep_cache"
  [[ "$UPDATE" == false ]] && _HOOK_OPTS+=" --no_update"
  _HOOK_OPTS+=" --lists_max_age $LISTS_MAX_AGE"
  [[ "$DRY_RUN" == true ]] && _HOOK_OPTS+=" --dry_run"
  [[ "$SKIP_INSTALLED" == true ]] && _HOOK_OPTS+=" --skip_installed"
  [[ "$PREFER_LINUXBREW" == true ]] && _HOOK_OPTS+=" --prefer_linuxbrew"
  case "$LIFECYCLE_HOOK" in
    onCreate) _HOOK_FILE="$_HOOK_DIR/on-create.sh" ;;
    updateContent) _HOOK_FILE="$_HOOK_DIR/update-content.sh" ;;
    postCreate) _HOOK_FILE="$_HOOK_DIR/post-create.sh" ;;
  esac
  printf '#!/bin/sh\nset -e\nexec bash "%s" %s\n' \
    "/usr/local/lib/install-os-pkg/install.sh" "$_HOOK_OPTS" > "$_HOOK_FILE"
  chmod +x "$_HOOK_FILE"
  echo "✅ Registered lifecycle hook '$LIFECYCLE_HOOK': $_HOOK_FILE" >&2
  exit 0
fi

_OSPKG_ARGS=()
[[ -n "$MANIFEST" ]] && _OSPKG_ARGS+=(--manifest "$MANIFEST")
[[ "$UPDATE" == false ]] && _OSPKG_ARGS+=(--no_update)
[[ "$KEEP_CACHE" == true ]] && _OSPKG_ARGS+=(--keep_cache)
[[ "$KEEP_REPOS" == true ]] && _OSPKG_ARGS+=(--keep_repos)
_OSPKG_ARGS+=(--lists_max_age "$LISTS_MAX_AGE")
[[ "$DRY_RUN" == true ]] && _OSPKG_ARGS+=(--dry_run)
[[ "$SKIP_INSTALLED" == true ]] && _OSPKG_ARGS+=(--skip_installed)
[[ "$PREFER_LINUXBREW" == true ]] && _OSPKG_ARGS+=(--prefer_linuxbrew)
[[ "$INTERACTIVE" == true ]] && _OSPKG_ARGS+=(--interactive)
ospkg::run "${_OSPKG_ARGS[@]}"
echo "✅ Package installation complete."
echo "↩️ Script exit: System Package Installation" >&2
