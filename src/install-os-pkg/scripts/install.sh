#!/usr/bin/env bash
set -euo pipefail

_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
_BASE_DIR="$(cd "$_SELF_DIR/.." && pwd)"

# shellcheck source=lib/ospkg.sh
. "$_SELF_DIR/_lib/ospkg.sh"
# shellcheck source=lib/logging.sh
. "$_SELF_DIR/_lib/logging.sh"
logging__setup
echo "↪️ Script entry: OS Package Installer" >&2
# Override _cleanup_hook in the hand-written section for feature-specific
# cleanup (e.g. removing temp files). Do NOT call logging__cleanup there;
# _on_exit owns that call and guarantees it runs exactly once, last.
# shellcheck disable=SC2329
_cleanup_hook() { return; }
# shellcheck disable=SC2329
_on_exit() {
  local _rc=$?
  _cleanup_hook
  [[ "${KEEP_CACHE:-true}" != true ]] && ospkg__clean
  if [[ $_rc -eq 0 ]]; then
    echo "✅ OS Package Installer script finished successfully." >&2
  else
    echo "❌ OS Package Installer script exited with error ${_rc}." >&2
  fi
  logging__cleanup
  return
}
trap '_on_exit' EXIT

__usage__() {
  cat << 'EOF'
Usage: install.sh [OPTIONS]

Options:
  --install_self {true,false}                            Install the 'install-os-pkg' system command. (default: "false")
  --interactive {true,false}                             Run in interactive mode. (default: "false")
  --keep_repos {true,false}                              Keep added repositories after installation. (default: "false")
  --lifecycle_hook {|onCreate|updateContent|postCreate}  Defer package installation to a devcontainer lifecycle hook.
  --manifest <value>                                     Inline manifest content or path to a manifest file.
  --update {true,false}                                  Update package lists before installation. (default: "true")
  --lists_max_age <value>                                Maximum age of package lists (in seconds) before an update is considered necessary. (default: "300")
  --dry_run {true,false}                                 Print what would be installed/fetched without making any changes. (default: "false")
  --skip_installed {true,false}                          Skip packages that are already available in PATH. (default: "false")
  --prefer_linuxbrew {true,false}                        Prefer Homebrew over the native Linux package manager. (default: "false")
  --keep_cache {true,false}                              Keep the package manager cache after installation. By default, the package manager cache is removed after installation to reduce image layer size. Set this flag to true to keep the cache, which may speed up subsequent installations at the cost of larger image layers. (default: "false")
  --debug {true,false}                                   Enable debug output. This adds `set -x` to the installer script, which prints each command before executing it. (default: "false")
  --logfile <value>                                      Log all output (stdout + stderr) to this file in addition to console.
  -h, --help                                             Show this help
EOF
  return
}

if [ "$#" -gt 0 ]; then
  echo "ℹ️ Script called with arguments: $*" >&2
  INSTALL_SELF=false
  INTERACTIVE=false
  KEEP_REPOS=false
  LIFECYCLE_HOOK=""
  MANIFEST=""
  UPDATE=true
  LISTS_MAX_AGE="300"
  DRY_RUN=false
  SKIP_INSTALLED=false
  PREFER_LINUXBREW=false
  KEEP_CACHE=false
  DEBUG=false
  LOGFILE=""
  while [ "$#" -gt 0 ]; do
    case $1 in
      --install_self)
        shift
        INSTALL_SELF="$1"
        echo "📩 Read argument 'install_self': '${INSTALL_SELF}'" >&2
        shift
        ;;
      --interactive)
        shift
        INTERACTIVE="$1"
        echo "📩 Read argument 'interactive': '${INTERACTIVE}'" >&2
        shift
        ;;
      --keep_repos)
        shift
        KEEP_REPOS="$1"
        echo "📩 Read argument 'keep_repos': '${KEEP_REPOS}'" >&2
        shift
        ;;
      --lifecycle_hook)
        shift
        LIFECYCLE_HOOK="$1"
        echo "📩 Read argument 'lifecycle_hook': '${LIFECYCLE_HOOK}'" >&2
        shift
        ;;
      --manifest)
        shift
        MANIFEST="$1"
        echo "📩 Read argument 'manifest': '${MANIFEST}'" >&2
        shift
        ;;
      --update)
        shift
        UPDATE="$1"
        echo "📩 Read argument 'update': '${UPDATE}'" >&2
        shift
        ;;
      --lists_max_age)
        shift
        LISTS_MAX_AGE="$1"
        echo "📩 Read argument 'lists_max_age': '${LISTS_MAX_AGE}'" >&2
        shift
        ;;
      --dry_run)
        shift
        DRY_RUN="$1"
        echo "📩 Read argument 'dry_run': '${DRY_RUN}'" >&2
        shift
        ;;
      --skip_installed)
        shift
        SKIP_INSTALLED="$1"
        echo "📩 Read argument 'skip_installed': '${SKIP_INSTALLED}'" >&2
        shift
        ;;
      --prefer_linuxbrew)
        shift
        PREFER_LINUXBREW="$1"
        echo "📩 Read argument 'prefer_linuxbrew': '${PREFER_LINUXBREW}'" >&2
        shift
        ;;
      --keep_cache)
        shift
        KEEP_CACHE="$1"
        echo "📩 Read argument 'keep_cache': '${KEEP_CACHE}'" >&2
        shift
        ;;
      --debug)
        shift
        DEBUG="$1"
        echo "📩 Read argument 'debug': '${DEBUG}'" >&2
        shift
        ;;
      --logfile)
        shift
        LOGFILE="$1"
        echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
        shift
        ;;
      -h | --help)
        __usage__
        exit 0
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
  [ "${INSTALL_SELF+defined}" ] && echo "📩 Read argument 'install_self': '${INSTALL_SELF}'" >&2
  [ "${INTERACTIVE+defined}" ] && echo "📩 Read argument 'interactive': '${INTERACTIVE}'" >&2
  [ "${KEEP_REPOS+defined}" ] && echo "📩 Read argument 'keep_repos': '${KEEP_REPOS}'" >&2
  [ "${LIFECYCLE_HOOK+defined}" ] && echo "📩 Read argument 'lifecycle_hook': '${LIFECYCLE_HOOK}'" >&2
  [ "${MANIFEST+defined}" ] && echo "📩 Read argument 'manifest': '${MANIFEST}'" >&2
  [ "${UPDATE+defined}" ] && echo "📩 Read argument 'update': '${UPDATE}'" >&2
  [ "${LISTS_MAX_AGE+defined}" ] && echo "📩 Read argument 'lists_max_age': '${LISTS_MAX_AGE}'" >&2
  [ "${DRY_RUN+defined}" ] && echo "📩 Read argument 'dry_run': '${DRY_RUN}'" >&2
  [ "${SKIP_INSTALLED+defined}" ] && echo "📩 Read argument 'skip_installed': '${SKIP_INSTALLED}'" >&2
  [ "${PREFER_LINUXBREW+defined}" ] && echo "📩 Read argument 'prefer_linuxbrew': '${PREFER_LINUXBREW}'" >&2
  [ "${KEEP_CACHE+defined}" ] && echo "📩 Read argument 'keep_cache': '${KEEP_CACHE}'" >&2
  [ "${DEBUG+defined}" ] && echo "📩 Read argument 'debug': '${DEBUG}'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
fi

[[ "${DEBUG:-}" == true ]] && set -x

# Apply defaults.
[ "${INSTALL_SELF+defined}" ] || {
  INSTALL_SELF=false
  echo "ℹ️ Argument 'install_self' set to default value 'false'." >&2
}
[ "${INTERACTIVE+defined}" ] || {
  INTERACTIVE=false
  echo "ℹ️ Argument 'interactive' set to default value 'false'." >&2
}
[ "${KEEP_REPOS+defined}" ] || {
  KEEP_REPOS=false
  echo "ℹ️ Argument 'keep_repos' set to default value 'false'." >&2
}
[ "${LIFECYCLE_HOOK+defined}" ] || {
  LIFECYCLE_HOOK=""
  echo "ℹ️ Argument 'lifecycle_hook' set to default value ''." >&2
}
[ "${MANIFEST+defined}" ] || {
  MANIFEST=""
  echo "ℹ️ Argument 'manifest' set to default value ''." >&2
}
[ "${UPDATE+defined}" ] || {
  UPDATE=true
  echo "ℹ️ Argument 'update' set to default value 'true'." >&2
}
[ "${LISTS_MAX_AGE+defined}" ] || {
  LISTS_MAX_AGE="300"
  echo "ℹ️ Argument 'lists_max_age' set to default value '300'." >&2
}
[ "${DRY_RUN+defined}" ] || {
  DRY_RUN=false
  echo "ℹ️ Argument 'dry_run' set to default value 'false'." >&2
}
[ "${SKIP_INSTALLED+defined}" ] || {
  SKIP_INSTALLED=false
  echo "ℹ️ Argument 'skip_installed' set to default value 'false'." >&2
}
[ "${PREFER_LINUXBREW+defined}" ] || {
  PREFER_LINUXBREW=false
  echo "ℹ️ Argument 'prefer_linuxbrew' set to default value 'false'." >&2
}
[ "${KEEP_CACHE+defined}" ] || {
  KEEP_CACHE=false
  echo "ℹ️ Argument 'keep_cache' set to default value 'false'." >&2
}
[ "${DEBUG+defined}" ] || {
  DEBUG=false
  echo "ℹ️ Argument 'debug' set to default value 'false'." >&2
}
[ "${LOGFILE+defined}" ] || {
  LOGFILE=""
  echo "ℹ️ Argument 'logfile' set to default value ''." >&2
}

# Validate enum options.
case "${LIFECYCLE_HOOK}" in
  '' | onCreate | updateContent | postCreate) ;;
  *)
    echo "⛔ Invalid value for 'lifecycle_hook': '${LIFECYCLE_HOOK}' (expected: '', onCreate, updateContent, postCreate)" >&2
    exit 1
    ;;
esac

# END OF AUTOGENERATED BLOCK

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

if [[ -n "$LIFECYCLE_HOOK" ]]; then
  if [[ -z "$MANIFEST" ]]; then
    echo "⛔ 'manifest' is required when 'lifecycle_hook' is set." >&2
    exit 1
  fi
fi

if ! [[ "$LISTS_MAX_AGE" =~ ^[0-9]+$ ]]; then
  echo "⛔ Invalid lists_max_age value: '$LISTS_MAX_AGE'. Must be a non-negative integer." >&2
  exit 1
fi

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
    printf '%s' "$MANIFEST" > "$_HOOK_DIR/manifest.yaml"
    _MANIFEST_ARG="$_HOOK_DIR/manifest.yaml"
    echo "ℹ️  Saved inline manifest to '$_MANIFEST_ARG'." >&2
  fi
  _HOOK_OPTS="--manifest $(printf '%q' "$_MANIFEST_ARG")"
  [[ "$DEBUG" == true ]] && _HOOK_OPTS+=" --debug true"
  [[ "$INTERACTIVE" == true ]] && _HOOK_OPTS+=" --interactive"
  [[ "$KEEP_REPOS" == true ]] && _HOOK_OPTS+=" --keep_repos"
  [[ -n "$LOGFILE" ]] && _HOOK_OPTS+=" --logfile $(printf '%q' "$LOGFILE")"
  [[ "$UPDATE" == false ]] && _HOOK_OPTS+=" --update false"
  _HOOK_OPTS+=" --lists_max_age $LISTS_MAX_AGE"
  [[ "$DRY_RUN" == true ]] && _HOOK_OPTS+=" --dry_run"
  [[ "$SKIP_INSTALLED" == true ]] && _HOOK_OPTS+=" --skip_installed"
  [[ "$PREFER_LINUXBREW" == true ]] && _HOOK_OPTS+=" --prefer_linuxbrew"
  _HOOK_OPTS+=" --keep_cache $KEEP_CACHE"
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
[[ "$UPDATE" == false ]] && _OSPKG_ARGS+=(--update false)

[[ "$KEEP_REPOS" == true ]] && _OSPKG_ARGS+=(--keep_repos)
_OSPKG_ARGS+=(--lists_max_age "$LISTS_MAX_AGE")
[[ "$DRY_RUN" == true ]] && _OSPKG_ARGS+=(--dry_run)
[[ "$SKIP_INSTALLED" == true ]] && _OSPKG_ARGS+=(--skip_installed)
[[ "$PREFER_LINUXBREW" == true ]] && _OSPKG_ARGS+=(--prefer_linuxbrew)
[[ "$INTERACTIVE" == true ]] && _OSPKG_ARGS+=(--interactive)
ospkg__run "${_OSPKG_ARGS[@]}"
