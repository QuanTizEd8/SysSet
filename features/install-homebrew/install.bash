# ── Constants ────────────────────────────────────────────────────────────────
_BREW_INSTALL_BASE_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD"
_BREW_INSTALLER_URL="${_BREW_INSTALL_BASE_URL}/install.sh"
_BREW_UNINSTALLER_URL="${_BREW_INSTALL_BASE_URL}/uninstall.sh"

# ── High-level steps ──────────────────────────────────────────────────────────

install_linux_deps() {
  echo "↪️ Function entry: install_linux_deps" >&2
  echo "📦 Installing Homebrew build dependencies." >&2
  ospkg__run --manifest "${_BASE_DIR}/dependencies/base.yaml" --skip_installed
  echo "↩️ Function exit: install_linux_deps" >&2
  return 0
}

run_brew_installer() {
  echo "↪️ Function entry: run_brew_installer" >&2
  echo "📦 Running Homebrew installer as user '${RESOLVED_INSTALL_USER}'." >&2
  local -a _env_vars=("NONINTERACTIVE=1")
  [ -n "${BREW_GIT_REMOTE-}" ] && _env_vars+=("HOMEBREW_BREW_GIT_REMOTE=${BREW_GIT_REMOTE}")
  [ -n "${CORE_GIT_REMOTE-}" ] && _env_vars+=("HOMEBREW_CORE_GIT_REMOTE=${CORE_GIT_REMOTE}")
  [[ "${NO_INSTALL_FROM_API}" == true ]] && _env_vars+=("HOMEBREW_NO_INSTALL_FROM_API=1")
  [ -n "${PREFIX-}" ] && _env_vars+=("HOMEBREW_PREFIX=${PREFIX}")
  local _tmpfile
  _tmpfile="$(mktemp /tmp/brew_install.XXXXXX.sh)"
  # shellcheck disable=SC2064
  trap "rm -f '${_tmpfile}'" RETURN
  echo "📥 Downloading Homebrew installer to '${_tmpfile}'." >&2
  net__fetch_url_file "$_BREW_INSTALLER_URL" "$_tmpfile"
  chmod a+r "$_tmpfile"
  echo "ℹ️ Installing as '${RESOLVED_INSTALL_USER}'." >&2
  _brew_run_as_install_user env "${_env_vars[@]}" /bin/bash "$_tmpfile"
  echo "✅ Homebrew installer completed." >&2
  echo "↩️ Function exit: run_brew_installer" >&2
  return 0
}

uninstall_brew() {
  echo "↪️ Function entry: uninstall_brew" >&2
  echo "🗑 Uninstalling Homebrew at '${RESOLVED_PREFIX}'." >&2
  local _tmpfile
  _tmpfile="$(mktemp /tmp/brew_uninstall.XXXXXX.sh)"
  # shellcheck disable=SC2064
  trap "rm -f '${_tmpfile}'" RETURN
  net__fetch_url_file "$_BREW_UNINSTALLER_URL" "$_tmpfile"
  chmod a+r "$_tmpfile"
  _brew_run_as_install_user env NONINTERACTIVE=1 /bin/bash "$_tmpfile" --path "$RESOLVED_PREFIX"
  echo "✅ Homebrew uninstalled." >&2
  echo "↩️ Function exit: uninstall_brew" >&2
  return 0
}

export_shellenv_for_user() {
  echo "↪️ Function entry: export_shellenv_for_user" >&2
  local _user="$1"
  # shellcheck disable=SC2016  # shellcheck disable=SC2016  local _brew_content='eval "$('''${RESOLVED_PREFIX}/bin/brew''' shellenv)"'
  shell__sync_block \
    --files "$(shell__user_init_files --home "$(shell__resolve_home "$_user")")" \
    --marker "brew shellenv (install-homebrew)" \
    --content "$_brew_content"
  echo "↩️ Function exit: export_shellenv_for_user" >&2
  return 0
}

export_shellenv_main() {
  echo "↪️ Function entry: export_shellenv_main" >&2
  if [ "$EXPORT_PATH" = "" ]; then
    echo "ℹ️ export_path is empty; skipping shellenv export." >&2
    echo "↩️ Function exit: export_shellenv_main" >&2
    return 0
  fi
  # shellcheck disable=SC2016
  local _brew_content='eval "$('"${RESOLVED_PREFIX}/bin/brew"' shellenv)"'
  local _marker="brew shellenv (install-homebrew)"
  if [ "$EXPORT_PATH" != "auto" ]; then
    # Explicit newline-separated path list
    shell__sync_block --files "$EXPORT_PATH" --marker "$_marker" --content "$_brew_content"
    echo "↩️ Function exit: export_shellenv_main" >&2
    return 0
  fi
  # auto mode
  local _is_root=false
  [ "$(id -u)" = "0" ] && _is_root=true
  if [ "$_is_root" = true ] && [ "$(os__kernel)" != "Darwin" ]; then
    echo "ℹ️ Case A: system-wide shellenv export (root + Linux)." >&2
    shell__sync_block \
      --files "$(shell__system_path_files --profile_d "brew.sh")" \
      --marker "$_marker" \
      --content "$_brew_content"
  else
    echo "ℹ️ Case B: user-scoped shellenv export." >&2
    export_shellenv_for_user "$RESOLVED_INSTALL_USER"
  fi
  # Resolved additional users
  local _u
  while IFS= read -r _u; do
    [[ -z "$_u" ]] && continue
    echo "ℹ️ Exporting shellenv for resolved user '${_u}'." >&2
    export_shellenv_for_user "$_u"
  done < <(users__resolve_list)
  echo "↩️ Function exit: export_shellenv_main" >&2
  return 0
}

# ── Helper functions ──────────────────────────────────────────────────────────

detect_brew_prefix() {
  echo "↪️ Function entry: detect_brew_prefix" >&2
  if [ "$(os__kernel)" = "Darwin" ]; then
    if [ "$(os__arch)" = "arm64" ]; then
      echo "/opt/homebrew"
    else
      echo "/usr/local"
    fi
  else
    echo "/home/linuxbrew/.linuxbrew"
  fi
  echo "↩️ Function exit: detect_brew_prefix" >&2
  return 0
}

# Returns the path to the Homebrew/brew git repository — distinct from the
# prefix on Intel macOS and Linux, where brew lives in ${prefix}/Homebrew.
detect_brew_repository() {
  echo "↪️ Function entry: detect_brew_repository" >&2
  if [ "$(os__kernel)" = "Darwin" ] && [ "$(os__arch)" = "arm64" ]; then
    echo "${RESOLVED_PREFIX}"
  else
    echo "${RESOLVED_PREFIX}/Homebrew"
  fi
  echo "↩️ Function exit: detect_brew_repository" >&2
  return 0
}

# enforce_options — applies post-install options unconditionally:
#   • BREW_GIT_REMOTE / CORE_GIT_REMOTE: sets git remote.origin.url on the
#     brew and homebrew-core repositories, and writes env-var export blocks to
#     shell init files (so future `brew update` calls use the same remote).
#   • NO_INSTALL_FROM_API: writes / removes HOMEBREW_NO_INSTALL_FROM_API=1
#     export block in shell init files.
enforce_options() {
  echo "↪️ Function entry: enforce_options" >&2
  local _brew_repo _core_repo _marker_brew _marker_core _marker_api
  _brew_repo="$(detect_brew_repository)"
  _core_repo="${_brew_repo}/Library/Taps/homebrew/homebrew-core"
  _marker_brew="HOMEBREW_BREW_GIT_REMOTE (install-homebrew)"
  _marker_core="HOMEBREW_CORE_GIT_REMOTE (install-homebrew)"
  _marker_api="HOMEBREW_NO_INSTALL_FROM_API (install-homebrew)"

  # --- brew git remote ---
  if [ -n "${BREW_GIT_REMOTE-}" ]; then
    echo "🔧 Setting brew git remote to '${BREW_GIT_REMOTE}'." >&2
    if [ -d "${_brew_repo}/.git" ]; then
      git -C "$_brew_repo" remote set-url origin "$BREW_GIT_REMOTE"
    else
      echo "⚠️ brew repository not found at '${_brew_repo}'; skipping git remote set." >&2
    fi
  fi
  _sync_init_files "$_marker_brew" ${BREW_GIT_REMOTE:+"export HOMEBREW_BREW_GIT_REMOTE=\"${BREW_GIT_REMOTE}\""}

  # --- core git remote ---
  if [ -n "${CORE_GIT_REMOTE-}" ]; then
    echo "🔧 Setting homebrew-core git remote to '${CORE_GIT_REMOTE}'." >&2
    if [ -d "${_core_repo}/.git" ]; then
      git -C "$_core_repo" remote set-url origin "$CORE_GIT_REMOTE"
    else
      echo "ℹ️ homebrew-core tap not present at '${_core_repo}'; skipping git remote set." >&2
    fi
  fi
  _sync_init_files "$_marker_core" ${CORE_GIT_REMOTE:+"export HOMEBREW_CORE_GIT_REMOTE=\"${CORE_GIT_REMOTE}\""}

  # --- HOMEBREW_NO_INSTALL_FROM_API ---
  if [[ "${NO_INSTALL_FROM_API}" == true ]]; then
    echo "🔧 Persisting HOMEBREW_NO_INSTALL_FROM_API=1." >&2
    _sync_init_files "$_marker_api" "export HOMEBREW_NO_INSTALL_FROM_API=1"
  else
    _sync_init_files "$_marker_api"
  fi

  echo "↩️ Function exit: enforce_options" >&2
  return 0
}

# _sync_init_files <marker> [content]
# Calls shell__sync_block for the relevant init files for RESOLVED_INSTALL_USER
# (and any resolved users) plus system-wide files when running as root on Linux.
# If content is given, writes/updates the block; if absent, removes it.
_sync_init_files() {
  local _marker="$1"
  local _content="${2-}"
  local _has_content=false
  [ $# -ge 2 ] && _has_content=true
  local _files _slug _is_root=false
  [ "$(id -u)" = "0" ] && _is_root=true

  if [ "$_is_root" = true ] && [ "$(os__kernel)" != "Darwin" ]; then
    _slug="$(echo "$_marker" | tr ' ()' '_' | tr -s '_' | tr '[:upper:]' '[:lower:]')"
    _files="$(shell__system_path_files --profile_d "${_slug}.sh")"
  else
    _files="$(shell__user_init_files --home "$(shell__resolve_home "$RESOLVED_INSTALL_USER")")"
  fi
  if [ "$_has_content" = true ]; then
    shell__sync_block --files "$_files" --marker "$_marker" --content "$_content"
  else
    shell__sync_block --files "$_files" --marker "$_marker"
  fi

  local _u
  while IFS= read -r _u; do
    [[ -z "$_u" ]] && continue
    _files="$(shell__user_init_files --home "$(shell__resolve_home "$_u")")"
    if [ "$_has_content" = true ]; then
      shell__sync_block --files "$_files" --marker "$_marker" --content "$_content"
    else
      shell__sync_block --files "$_files" --marker "$_marker"
    fi
  done < <(users__resolve_list)
  return 0
}

# _brew_run_as_install_user <cmd> [args...]
# Run a command as RESOLVED_INSTALL_USER when the current process is root and
# the install user is not root. Uses runuser(1) on Linux (no sudo config
# needed for root) and sudo on macOS (runuser is absent there).
_brew_run_as_install_user() {
  echo "↪️ Function entry: _brew_run_as_install_user" >&2
  if [ "$(id -u)" != "0" ] || [ "${RESOLVED_INSTALL_USER}" = "root" ]; then
    "$@"
  elif [ "$(os__kernel)" = "Darwin" ]; then
    sudo -u "${RESOLVED_INSTALL_USER}" "$@"
  else
    runuser -u "${RESOLVED_INSTALL_USER}" -- "$@"
  fi
  echo "↩️ Function exit: _brew_run_as_install_user" >&2
  return 0
}

detect_install_user() {
  echo "↪️ Function entry: detect_install_user" >&2
  if [ -n "${INSTALL_USER-}" ]; then
    echo "ℹ️ Using specified install_user: '${INSTALL_USER}'." >&2
    echo "$INSTALL_USER"
    echo "↩️ Function exit: detect_install_user" >&2
    return 0
  fi
  if [ "$(id -u)" != "0" ]; then
    id -nu
    echo "↩️ Function exit: detect_install_user" >&2
    return 0
  fi
  # Running as root.
  if [ "$(os__kernel)" = "Darwin" ]; then
    # The official Homebrew installer refuses to run as root on macOS.
    # We must find a non-root user to install as.
    if [ -n "${SUDO_USER-}" ] && [ "$SUDO_USER" != "root" ]; then
      echo "ℹ️ macOS root: using SUDO_USER='${SUDO_USER}' as install_user." >&2
      echo "$SUDO_USER"
    else
      local _u
      _u="$(dscl . list /Users 2> /dev/null |
        grep -v -E '^(_|daemon|nobody|root|Guest)' |
        head -1)" || true
      if [ -n "$_u" ]; then
        echo "ℹ️ macOS root: using first non-system user '${_u}' as install_user." >&2
        echo "$_u"
      else
        echo "⛔ Running as root on macOS but no non-root user found." >&2
        echo "   Set the 'install_user' option to a non-root user account." >&2
        exit 1
      fi
    fi
  else
    # Linux: Homebrew's installer refuses root in container environments where
    # /.dockerenv is absent (Docker BuildKit + cgroup v2 on modern GHA runners).
    # Prefer an existing non-root user; fall back to creating a dedicated
    # 'linuxbrew' user only when no real user is available.
    if [ -n "${SUDO_USER-}" ] && [ "$SUDO_USER" != "root" ]; then
      echo "ℹ️ Linux root: using SUDO_USER='${SUDO_USER}' as install_user." >&2
      echo "$SUDO_USER"
    elif [ -n "${_REMOTE_USER-}" ] && [ "$_REMOTE_USER" != "root" ]; then
      echo "ℹ️ Linux root: using _REMOTE_USER='${_REMOTE_USER}' as install_user." >&2
      echo "$_REMOTE_USER"
    else
      if ! id linuxbrew &> /dev/null; then
        echo "ℹ️ Linux root: creating 'linuxbrew' user for Homebrew installation." >&2
        useradd --create-home --shell /bin/bash linuxbrew
        # Ubuntu 22.04+ creates home directories with mode 750; make it
        # world-traversable so other users can access the brew binary.
        chmod 755 /home/linuxbrew
      else
        echo "ℹ️ Linux root: 'linuxbrew' user already exists." >&2
      fi
      echo "linuxbrew"
    fi
  fi
  echo "↩️ Function exit: detect_install_user" >&2
  return 0
}

# shellcheck source=lib/shell.sh
. "$_SELF_DIR/_lib/shell.sh"
# shellcheck source=lib/users.sh
. "$_SELF_DIR/_lib/users.sh"

# ── Resolve prefix and install user ──────────────────────────────────────────
if [ -n "$PREFIX" ]; then
  RESOLVED_PREFIX="$PREFIX"
  echo "ℹ️ Using explicit prefix: '${RESOLVED_PREFIX}'." >&2
elif command -v brew > /dev/null 2>&1; then
  RESOLVED_PREFIX="$(brew --prefix)"
  echo "ℹ️ Detected existing brew prefix: '${RESOLVED_PREFIX}'." >&2
else
  RESOLVED_PREFIX="$(detect_brew_prefix)"
  echo "ℹ️ Using platform-default prefix: '${RESOLVED_PREFIX}'." >&2
fi

RESOLVED_INSTALL_USER="$(detect_install_user)"
echo "ℹ️ Install user: '${RESOLVED_INSTALL_USER}'." >&2

# ── Step 1: Linux build dependencies ─────────────────────────────────────────
if [ "$(os__kernel)" != "Darwin" ]; then
  install_linux_deps
fi

# ── Step 2: Install / skip / reinstall Homebrew ───────────────────────────────
_BREW_EXEC="${RESOLVED_PREFIX}/bin/brew"
if [ -f "$_BREW_EXEC" ]; then
  echo "⚠️ Homebrew found at '${_BREW_EXEC}'." >&2
  case "$IF_EXISTS" in
    skip)
      echo "⏭️ if_exists=skip: existing Homebrew detected; skipping installer and continuing to post-install steps." >&2
      ;;
    fail)
      echo "⛔ if_exists=fail: Homebrew already installed at '${RESOLVED_PREFIX}'." >&2
      echo "   Remove it first or set if_exists=skip or if_exists=reinstall." >&2
      exit 1
      ;;
    reinstall)
      echo "ℹ️ if_exists=reinstall: uninstalling then reinstalling Homebrew." >&2
      uninstall_brew
      run_brew_installer
      ;;
    *)
      echo "⛔ Invalid value for 'if_exists': '${IF_EXISTS}'. Use 'skip', 'fail', or 'reinstall'." >&2
      exit 1
      ;;
  esac
else
  run_brew_installer
fi

# ── Step 3: Verify brew executable ───────────────────────────────────────────
if [ ! -f "$_BREW_EXEC" ]; then
  echo "⛔ Homebrew executable not found at '${_BREW_EXEC}' after installation." >&2
  exit 1
fi
echo "✅ Homebrew $("$_BREW_EXEC" --version | head -1) is available at '${_BREW_EXEC}'." >&2

# ── Step 3.5: Enforce options (git remotes, NO_INSTALL_FROM_API) ──────────────
# Runs unconditionally so options are applied even when if_exists=skip.
enforce_options

# ── Step 4: brew update ───────────────────────────────────────────────────────
if [[ "$UPDATE" == true ]]; then
  echo "🔄 Running 'brew update'." >&2
  _brew_run_as_install_user "$_BREW_EXEC" update
  echo "✅ brew update completed." >&2
fi

# ── Step 5: Export shellenv ───────────────────────────────────────────────────
export_shellenv_main

# ── Step 6: brew doctor (warn only) ──────────────────────────────────────────
echo "ℹ️ Running 'brew doctor' (warnings only)." >&2
_brew_run_as_install_user "$_BREW_EXEC" doctor 2>&1 || true

# ── Step 7: Write-permission group ───────────────────────────────────────────
if [[ -n "${WRITE_GROUP:-}" ]] && [[ "$(os__kernel)" = "Linux" ]]; then
  export ADD_CURRENT_USER ADD_REMOTE_USER ADD_CONTAINER_USER ADD_USERS
  mapfile -t _write_users < <(users__resolve_list)
  users__set_write_permissions "$RESOLVED_PREFIX" "$RESOLVED_INSTALL_USER" "$WRITE_GROUP" "${_write_users[@]}"
fi
