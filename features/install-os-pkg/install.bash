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
  [[ "$INTERACTIVE" == true ]] && _HOOK_OPTS+=" --interactive true"
  [[ "$KEEP_REPOS" == true ]] && _HOOK_OPTS+=" --keep_repos true"
  [[ -n "$LOGFILE" ]] && _HOOK_OPTS+=" --logfile $(printf '%q' "$LOGFILE")"
  [[ "$UPDATE" == false ]] && _HOOK_OPTS+=" --update false"
  _HOOK_OPTS+=" --lists_max_age $LISTS_MAX_AGE"
  [[ "$DRY_RUN" == true ]] && _HOOK_OPTS+=" --dry_run true"
  [[ "$SKIP_INSTALLED" == true ]] && _HOOK_OPTS+=" --skip_installed true"
  [[ "$PREFER_LINUXBREW" == true ]] && _HOOK_OPTS+=" --prefer_linuxbrew true"
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
