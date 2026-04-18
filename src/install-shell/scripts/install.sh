#!/usr/bin/env bash
set -euo pipefail

_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
_BASE_DIR="$(cd "$_SELF_DIR/.." && pwd)"

# shellcheck source=lib/ospkg.sh
. "$_SELF_DIR/_lib/ospkg.sh"
# shellcheck source=lib/logging.sh
. "$_SELF_DIR/_lib/logging.sh"
logging__setup
echo "↪️ Script entry: Install Shell" >&2
# Override _cleanup_hook in the hand-written section for feature-specific
# cleanup (e.g. removing temp files). Do NOT call logging__cleanup there;
# _on_exit owns that call and guarantees it runs exactly once, last.
# shellcheck disable=SC2329
_cleanup_hook() { return; }
# shellcheck disable=SC2329
_on_exit() {
  local _rc=$?
  _cleanup_hook
  if [[ $_rc -eq 0 ]]; then
    echo "✅ Install Shell script finished successfully." >&2
  else
    echo "❌ Install Shell script exited with error ${_rc}." >&2
  fi
  logging__cleanup
  return
}
trap '_on_exit' EXIT

__usage__() {
  cat << 'EOF'
Usage: install.sh [OPTIONS]

Options:
  --install_zsh {true,false}                   Install Zsh. Bash is always installed. (default: "true")
  --install_ohmyzsh {true,false}               Install Oh My Zsh when installing Zsh. Ignored if Zsh is not available or being installed. (default: "true")
  --install_ohmybash {true,false}              Install Oh My Bash. (default: "true")
  --install_starship {true,false}              Install the Starship prompt binary to `/usr/local/bin`. (default: "true")
  --starship_shells <value>  (repeatable)      Shells to activate the Starship prompt in (`zsh`, `bash`, or both).
  --ohmyzsh_plugins <value>  (repeatable)      Oh My Zsh plugins to install, each as an `owner/repo` GitHub slug or a plain built-in name.
  --ohmybash_plugins <value>  (repeatable)     Oh My Bash plugins to install, each as an `owner/repo` GitHub slug or a plain built-in name.
  --ohmyzsh_theme <value>                      Oh My Zsh custom theme to install, as a `owner/repo` GitHub slug (e.g., 'romkatv/powerlevel10k' for the Powerlevel10k theme).
  --ohmybash_theme <value>                     Oh My Bash custom theme to install, as a `owner/repo` GitHub slug.
  --ohmyzsh_install_dir <value>                Path to the Oh My Zsh installation directory. (default: "/usr/local/share/oh-my-zsh")
  --ohmybash_install_dir <value>               Path to the Oh My Bash installation directory. (default: "/usr/local/share/oh-my-bash")
  --ohmyzsh_branch <value>                     Git branch/tag of ohmyzsh/ohmyzsh to clone. (default: "master")
  --ohmybash_branch <value>                    Git branch/tag of ohmybash/oh-my-bash to clone. (default: "master")
  --add_current_user {true,false}              Whether to add configuration for the current non-root user (`SUDO_USER` if run via `sudo`, otherwise `whoami`). No effect when the current user is root. (default: "true")
  --add_container_user {true,false}            Whether to add configuration for the `containerUser` set in the devcontainer.json file, which becomes the `_CONTAINER_USER` environment variable set by the devcontainer tooling. No effect when `_CONTAINER_USER` is not set. (default: "true")
  --add_remote_user {true,false}               Whether to add configuration for the `remoteUser` set in the devcontainer.json file, which becomes the `_REMOTE_USER` environment variable set by the devcontainer tooling. No effect when `_REMOTE_USER` is not set. (default: "true")
  --add_users <value>  (repeatable)            Usernames to add shell configuration for, in addition to the users specified by the other `add_*_user_config` options.
  --set_user_shells {zsh|bash|none}            Whether to set users' default login shell to zsh or bash via `chsh`. (default: "zsh")
  --zdotdir <value>                            Directory where Zsh looks for its per-user config files (`.zshrc`, `.zprofile`, `.zlogin`).
  --ohmyzsh_custom_dir <value>                 ZSH_CUSTOM directory for Oh My Zsh.
  --ohmybash_custom_dir <value>                OSH_CUSTOM directory for Oh My Bash.
  --user_config_mode {overwrite|augment|skip}  How to handle existing user dotfiles when configuring users. (default: "overwrite")
  --debug {true,false}                         Enable debug output. (default: "false")
  --logfile <value>                            Log all output (stdout + stderr) to this file in addition to console.
  -h, --help                                   Show this help
EOF
  return
}

if [ "$#" -gt 0 ]; then
  echo "ℹ️ Script called with arguments: $*" >&2
  INSTALL_ZSH=true
  INSTALL_OHMYZSH=true
  INSTALL_OHMYBASH=true
  INSTALL_STARSHIP=true
  STARSHIP_SHELLS=()
  OHMYZSH_PLUGINS=()
  OHMYBASH_PLUGINS=()
  OHMYZSH_THEME=""
  OHMYBASH_THEME=""
  OHMYZSH_INSTALL_DIR="/usr/local/share/oh-my-zsh"
  OHMYBASH_INSTALL_DIR="/usr/local/share/oh-my-bash"
  OHMYZSH_BRANCH="master"
  OHMYBASH_BRANCH="master"
  ADD_CURRENT_USER=true
  ADD_CONTAINER_USER=true
  ADD_REMOTE_USER=true
  ADD_USERS=()
  SET_USER_SHELLS="zsh"
  ZDOTDIR=""
  OHMYZSH_CUSTOM_DIR=""
  OHMYBASH_CUSTOM_DIR=""
  USER_CONFIG_MODE="overwrite"
  DEBUG=false
  LOGFILE=""
  while [ "$#" -gt 0 ]; do
    case $1 in
      --install_zsh)
        shift
        INSTALL_ZSH="$1"
        echo "📩 Read argument 'install_zsh': '${INSTALL_ZSH}'" >&2
        shift
        ;;
      --install_ohmyzsh)
        shift
        INSTALL_OHMYZSH="$1"
        echo "📩 Read argument 'install_ohmyzsh': '${INSTALL_OHMYZSH}'" >&2
        shift
        ;;
      --install_ohmybash)
        shift
        INSTALL_OHMYBASH="$1"
        echo "📩 Read argument 'install_ohmybash': '${INSTALL_OHMYBASH}'" >&2
        shift
        ;;
      --install_starship)
        shift
        INSTALL_STARSHIP="$1"
        echo "📩 Read argument 'install_starship': '${INSTALL_STARSHIP}'" >&2
        shift
        ;;
      --starship_shells)
        shift
        STARSHIP_SHELLS+=("$1")
        echo "📩 Read argument 'starship_shells': '$1'" >&2
        shift
        ;;
      --ohmyzsh_plugins)
        shift
        OHMYZSH_PLUGINS+=("$1")
        echo "📩 Read argument 'ohmyzsh_plugins': '$1'" >&2
        shift
        ;;
      --ohmybash_plugins)
        shift
        OHMYBASH_PLUGINS+=("$1")
        echo "📩 Read argument 'ohmybash_plugins': '$1'" >&2
        shift
        ;;
      --ohmyzsh_theme)
        shift
        OHMYZSH_THEME="$1"
        echo "📩 Read argument 'ohmyzsh_theme': '${OHMYZSH_THEME}'" >&2
        shift
        ;;
      --ohmybash_theme)
        shift
        OHMYBASH_THEME="$1"
        echo "📩 Read argument 'ohmybash_theme': '${OHMYBASH_THEME}'" >&2
        shift
        ;;
      --ohmyzsh_install_dir)
        shift
        OHMYZSH_INSTALL_DIR="$1"
        echo "📩 Read argument 'ohmyzsh_install_dir': '${OHMYZSH_INSTALL_DIR}'" >&2
        shift
        ;;
      --ohmybash_install_dir)
        shift
        OHMYBASH_INSTALL_DIR="$1"
        echo "📩 Read argument 'ohmybash_install_dir': '${OHMYBASH_INSTALL_DIR}'" >&2
        shift
        ;;
      --ohmyzsh_branch)
        shift
        OHMYZSH_BRANCH="$1"
        echo "📩 Read argument 'ohmyzsh_branch': '${OHMYZSH_BRANCH}'" >&2
        shift
        ;;
      --ohmybash_branch)
        shift
        OHMYBASH_BRANCH="$1"
        echo "📩 Read argument 'ohmybash_branch': '${OHMYBASH_BRANCH}'" >&2
        shift
        ;;
      --add_current_user)
        shift
        ADD_CURRENT_USER="$1"
        echo "📩 Read argument 'add_current_user': '${ADD_CURRENT_USER}'" >&2
        shift
        ;;
      --add_container_user)
        shift
        ADD_CONTAINER_USER="$1"
        echo "📩 Read argument 'add_container_user': '${ADD_CONTAINER_USER}'" >&2
        shift
        ;;
      --add_remote_user)
        shift
        ADD_REMOTE_USER="$1"
        echo "📩 Read argument 'add_remote_user': '${ADD_REMOTE_USER}'" >&2
        shift
        ;;
      --add_users)
        shift
        ADD_USERS+=("$1")
        echo "📩 Read argument 'add_users': '$1'" >&2
        shift
        ;;
      --set_user_shells)
        shift
        SET_USER_SHELLS="$1"
        echo "📩 Read argument 'set_user_shells': '${SET_USER_SHELLS}'" >&2
        shift
        ;;
      --zdotdir)
        shift
        ZDOTDIR="$1"
        echo "📩 Read argument 'zdotdir': '${ZDOTDIR}'" >&2
        shift
        ;;
      --ohmyzsh_custom_dir)
        shift
        OHMYZSH_CUSTOM_DIR="$1"
        echo "📩 Read argument 'ohmyzsh_custom_dir': '${OHMYZSH_CUSTOM_DIR}'" >&2
        shift
        ;;
      --ohmybash_custom_dir)
        shift
        OHMYBASH_CUSTOM_DIR="$1"
        echo "📩 Read argument 'ohmybash_custom_dir': '${OHMYBASH_CUSTOM_DIR}'" >&2
        shift
        ;;
      --user_config_mode)
        shift
        USER_CONFIG_MODE="$1"
        echo "📩 Read argument 'user_config_mode': '${USER_CONFIG_MODE}'" >&2
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
  [ "${INSTALL_ZSH+defined}" ] && echo "📩 Read argument 'install_zsh': '${INSTALL_ZSH}'" >&2
  [ "${INSTALL_OHMYZSH+defined}" ] && echo "📩 Read argument 'install_ohmyzsh': '${INSTALL_OHMYZSH}'" >&2
  [ "${INSTALL_OHMYBASH+defined}" ] && echo "📩 Read argument 'install_ohmybash': '${INSTALL_OHMYBASH}'" >&2
  [ "${INSTALL_STARSHIP+defined}" ] && echo "📩 Read argument 'install_starship': '${INSTALL_STARSHIP}'" >&2
  if [ "${STARSHIP_SHELLS+defined}" ]; then
    if [ -n "${STARSHIP_SHELLS-}" ]; then
      mapfile -t STARSHIP_SHELLS < <(printf '%s\n' "${STARSHIP_SHELLS}" | grep -v '^$')
      for _item in "${STARSHIP_SHELLS[@]}"; do
        echo "📩 Read argument 'starship_shells': '$_item'" >&2
      done
    else
      STARSHIP_SHELLS=()
    fi
  fi
  if [ "${OHMYZSH_PLUGINS+defined}" ]; then
    if [ -n "${OHMYZSH_PLUGINS-}" ]; then
      mapfile -t OHMYZSH_PLUGINS < <(printf '%s\n' "${OHMYZSH_PLUGINS}" | grep -v '^$')
      for _item in "${OHMYZSH_PLUGINS[@]}"; do
        echo "📩 Read argument 'ohmyzsh_plugins': '$_item'" >&2
      done
    else
      OHMYZSH_PLUGINS=()
    fi
  fi
  if [ "${OHMYBASH_PLUGINS+defined}" ]; then
    if [ -n "${OHMYBASH_PLUGINS-}" ]; then
      mapfile -t OHMYBASH_PLUGINS < <(printf '%s\n' "${OHMYBASH_PLUGINS}" | grep -v '^$')
      for _item in "${OHMYBASH_PLUGINS[@]}"; do
        echo "📩 Read argument 'ohmybash_plugins': '$_item'" >&2
      done
    else
      OHMYBASH_PLUGINS=()
    fi
  fi
  [ "${OHMYZSH_THEME+defined}" ] && echo "📩 Read argument 'ohmyzsh_theme': '${OHMYZSH_THEME}'" >&2
  [ "${OHMYBASH_THEME+defined}" ] && echo "📩 Read argument 'ohmybash_theme': '${OHMYBASH_THEME}'" >&2
  [ "${OHMYZSH_INSTALL_DIR+defined}" ] && echo "📩 Read argument 'ohmyzsh_install_dir': '${OHMYZSH_INSTALL_DIR}'" >&2
  [ "${OHMYBASH_INSTALL_DIR+defined}" ] && echo "📩 Read argument 'ohmybash_install_dir': '${OHMYBASH_INSTALL_DIR}'" >&2
  [ "${OHMYZSH_BRANCH+defined}" ] && echo "📩 Read argument 'ohmyzsh_branch': '${OHMYZSH_BRANCH}'" >&2
  [ "${OHMYBASH_BRANCH+defined}" ] && echo "📩 Read argument 'ohmybash_branch': '${OHMYBASH_BRANCH}'" >&2
  [ "${ADD_CURRENT_USER+defined}" ] && echo "📩 Read argument 'add_current_user': '${ADD_CURRENT_USER}'" >&2
  [ "${ADD_CONTAINER_USER+defined}" ] && echo "📩 Read argument 'add_container_user': '${ADD_CONTAINER_USER}'" >&2
  [ "${ADD_REMOTE_USER+defined}" ] && echo "📩 Read argument 'add_remote_user': '${ADD_REMOTE_USER}'" >&2
  if [ "${ADD_USERS+defined}" ]; then
    if [ -n "${ADD_USERS-}" ]; then
      mapfile -t ADD_USERS < <(printf '%s\n' "${ADD_USERS}" | grep -v '^$')
      for _item in "${ADD_USERS[@]}"; do
        echo "📩 Read argument 'add_users': '$_item'" >&2
      done
    else
      ADD_USERS=()
    fi
  fi
  [ "${SET_USER_SHELLS+defined}" ] && echo "📩 Read argument 'set_user_shells': '${SET_USER_SHELLS}'" >&2
  [ "${ZDOTDIR+defined}" ] && echo "📩 Read argument 'zdotdir': '${ZDOTDIR}'" >&2
  [ "${OHMYZSH_CUSTOM_DIR+defined}" ] && echo "📩 Read argument 'ohmyzsh_custom_dir': '${OHMYZSH_CUSTOM_DIR}'" >&2
  [ "${OHMYBASH_CUSTOM_DIR+defined}" ] && echo "📩 Read argument 'ohmybash_custom_dir': '${OHMYBASH_CUSTOM_DIR}'" >&2
  [ "${USER_CONFIG_MODE+defined}" ] && echo "📩 Read argument 'user_config_mode': '${USER_CONFIG_MODE}'" >&2
  [ "${DEBUG+defined}" ] && echo "📩 Read argument 'debug': '${DEBUG}'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
fi

[[ "${DEBUG:-}" == true ]] && set -x

# Apply defaults.
[ "${INSTALL_ZSH+defined}" ] || {
  INSTALL_ZSH=true
  echo "\u2139\ufe0f Argument 'install_zsh' set to default value 'true'." >&2
}
[ "${INSTALL_OHMYZSH+defined}" ] || {
  INSTALL_OHMYZSH=true
  echo "\u2139\ufe0f Argument 'install_ohmyzsh' set to default value 'true'." >&2
}
[ "${INSTALL_OHMYBASH+defined}" ] || {
  INSTALL_OHMYBASH=true
  echo "\u2139\ufe0f Argument 'install_ohmybash' set to default value 'true'." >&2
}
[ "${INSTALL_STARSHIP+defined}" ] || {
  INSTALL_STARSHIP=true
  echo "\u2139\ufe0f Argument 'install_starship' set to default value 'true'." >&2
}
[ "${STARSHIP_SHELLS+defined}" ] || {
  mapfile -t STARSHIP_SHELLS < <(printf '%s' $'zsh' | grep -v '^$')
  echo "\u2139\ufe0f Argument 'starship_shells' set to default value 'zsh'." >&2
}
[ "${OHMYZSH_PLUGINS+defined}" ] || {
  mapfile -t OHMYZSH_PLUGINS < <(printf '%s' $'git\nzsh-users/zsh-syntax-highlighting' | grep -v '^$')
  echo "\u2139\ufe0f Argument 'ohmyzsh_plugins' set to default value 'git, zsh-users/zsh-syntax-highlighting'." >&2
}
[ "${OHMYBASH_PLUGINS+defined}" ] || {
  mapfile -t OHMYBASH_PLUGINS < <(printf '%s' $'git' | grep -v '^$')
  echo "\u2139\ufe0f Argument 'ohmybash_plugins' set to default value 'git'." >&2
}
[ "${OHMYZSH_THEME+defined}" ] || {
  OHMYZSH_THEME=""
  echo "\u2139\ufe0f Argument 'ohmyzsh_theme' set to default value ''." >&2
}
[ "${OHMYBASH_THEME+defined}" ] || {
  OHMYBASH_THEME=""
  echo "\u2139\ufe0f Argument 'ohmybash_theme' set to default value ''." >&2
}
[ "${OHMYZSH_INSTALL_DIR+defined}" ] || {
  OHMYZSH_INSTALL_DIR="/usr/local/share/oh-my-zsh"
  echo "\u2139\ufe0f Argument 'ohmyzsh_install_dir' set to default value '/usr/local/share/oh-my-zsh'." >&2
}
[ "${OHMYBASH_INSTALL_DIR+defined}" ] || {
  OHMYBASH_INSTALL_DIR="/usr/local/share/oh-my-bash"
  echo "\u2139\ufe0f Argument 'ohmybash_install_dir' set to default value '/usr/local/share/oh-my-bash'." >&2
}
[ "${OHMYZSH_BRANCH+defined}" ] || {
  OHMYZSH_BRANCH="master"
  echo "\u2139\ufe0f Argument 'ohmyzsh_branch' set to default value 'master'." >&2
}
[ "${OHMYBASH_BRANCH+defined}" ] || {
  OHMYBASH_BRANCH="master"
  echo "\u2139\ufe0f Argument 'ohmybash_branch' set to default value 'master'." >&2
}
[ "${ADD_CURRENT_USER+defined}" ] || {
  ADD_CURRENT_USER=true
  echo "\u2139\ufe0f Argument 'add_current_user' set to default value 'true'." >&2
}
[ "${ADD_CONTAINER_USER+defined}" ] || {
  ADD_CONTAINER_USER=true
  echo "\u2139\ufe0f Argument 'add_container_user' set to default value 'true'." >&2
}
[ "${ADD_REMOTE_USER+defined}" ] || {
  ADD_REMOTE_USER=true
  echo "\u2139\ufe0f Argument 'add_remote_user' set to default value 'true'." >&2
}
[ "${ADD_USERS+defined}" ] || {
  ADD_USERS=()
  echo "\u2139\ufe0f Argument 'add_users' set to default value '(empty)'." >&2
}
[ "${SET_USER_SHELLS+defined}" ] || {
  SET_USER_SHELLS="zsh"
  echo "\u2139\ufe0f Argument 'set_user_shells' set to default value 'zsh'." >&2
}
[ "${ZDOTDIR+defined}" ] || {
  ZDOTDIR=""
  echo "\u2139\ufe0f Argument 'zdotdir' set to default value ''." >&2
}
[ "${OHMYZSH_CUSTOM_DIR+defined}" ] || {
  OHMYZSH_CUSTOM_DIR=""
  echo "\u2139\ufe0f Argument 'ohmyzsh_custom_dir' set to default value ''." >&2
}
[ "${OHMYBASH_CUSTOM_DIR+defined}" ] || {
  OHMYBASH_CUSTOM_DIR=""
  echo "\u2139\ufe0f Argument 'ohmybash_custom_dir' set to default value ''." >&2
}
[ "${USER_CONFIG_MODE+defined}" ] || {
  USER_CONFIG_MODE="overwrite"
  echo "\u2139\ufe0f Argument 'user_config_mode' set to default value 'overwrite'." >&2
}
[ "${DEBUG+defined}" ] || {
  DEBUG=false
  echo "\u2139\ufe0f Argument 'debug' set to default value 'false'." >&2
}
[ "${LOGFILE+defined}" ] || {
  LOGFILE=""
  echo "\u2139\ufe0f Argument 'logfile' set to default value ''." >&2
}

# Validate enum options.
case "${SET_USER_SHELLS}" in
  zsh | bash | none) ;;
  *)
    echo "⛔ Invalid value for 'set_user_shells': '${SET_USER_SHELLS}' (expected: zsh, bash, none)" >&2
    exit 1
    ;;
esac
case "${USER_CONFIG_MODE}" in
  overwrite | augment | skip) ;;
  *)
    echo "⛔ Invalid value for 'user_config_mode': '${USER_CONFIG_MODE}' (expected: overwrite, augment, skip)" >&2
    exit 1
    ;;
esac

ospkg__run --manifest "${_BASE_DIR}/dependencies/base.yaml" --skip_installed

# END OF AUTOGENERATED BLOCK

# shellcheck source=lib/shell.sh
. "$_SELF_DIR/_lib/shell.sh"
# shellcheck source=lib/users.sh
. "$_SELF_DIR/_lib/users.sh"

_FILES_DIR="${_BASE_DIR}/files"
_SKEL_DIR="${_FILES_DIR}/skel"

os__require_root

if [[ "$INSTALL_ZSH" == true ]]; then
  if command -v zsh > /dev/null 2>&1; then
    echo "ℹ️  Zsh already installed — skipping." >&2
  else
    echo "📦 Installing Zsh..." >&2
    ospkg__install zsh
  fi
fi

# Verify prerequisites are available.
for _cmd in git curl; do
  if ! command -v "$_cmd" > /dev/null 2>&1; then
    echo "⛔ Required command '${_cmd}' not found. Install it first." >&2
    exit 1
  fi
done

# ===================================================================
# Step 2: Install Oh My Zsh
# ===================================================================
_OMZ_INSTALLED=false
if [[ "$INSTALL_OHMYZSH" == true ]]; then
  if ! command -v zsh > /dev/null 2>&1; then
    echo "⚠️  Zsh not available — skipping Oh My Zsh installation." >&2
  else
    _OMZ_INSTALL_ARGS=(
      --branch "$OHMYZSH_BRANCH"
      --install_dir "$OHMYZSH_INSTALL_DIR"
      --theme "$OHMYZSH_THEME"
      --plugins "${OHMYZSH_PLUGINS[*]}"
    )
    # Pass an explicit system-path custom dir to the install script so themes
    # and plugins are cloned there.  Per-user paths (~/$HOME-prefixed) and
    # the empty default are handled at configure-user time via symlinks.
    # shellcheck disable=SC2016
    if [ -n "$OHMYZSH_CUSTOM_DIR" ] &&
      [[ "$OHMYZSH_CUSTOM_DIR" != '~'* ]] &&
      [[ "$OHMYZSH_CUSTOM_DIR" != '$HOME'* ]]; then
      _OMZ_INSTALL_ARGS+=(--zsh_custom_dir "$OHMYZSH_CUSTOM_DIR")
    fi
    [[ "$DEBUG" == true ]] && _OMZ_INSTALL_ARGS+=(--debug)
    bash "$_SELF_DIR/install_ohmyzsh.sh" "${_OMZ_INSTALL_ARGS[@]}"
    _OMZ_INSTALLED=true
  fi
fi

# ===================================================================
# Step 3: Install Oh My Bash
# ===================================================================
_OMB_INSTALLED=false
if [[ "$INSTALL_OHMYBASH" == true ]]; then
  _OMB_INSTALL_ARGS=(
    --branch "$OHMYBASH_BRANCH"
    --install_dir "$OHMYBASH_INSTALL_DIR"
    --theme "$OHMYBASH_THEME"
    --plugins "${OHMYBASH_PLUGINS[*]}"
  )
  # shellcheck disable=SC2016
  if [ -n "$OHMYBASH_CUSTOM_DIR" ] &&
    [[ "$OHMYBASH_CUSTOM_DIR" != '~'* ]] &&
    [[ "$OHMYBASH_CUSTOM_DIR" != '$HOME'* ]]; then
    _OMB_INSTALL_ARGS+=(--osh_custom_dir "$OHMYBASH_CUSTOM_DIR")
  fi
  [[ "$DEBUG" == true ]] && _OMB_INSTALL_ARGS+=(--debug)
  bash "$_SELF_DIR/install_ohmybash.sh" "${_OMB_INSTALL_ARGS[@]}"
  _OMB_INSTALLED=true
fi

# ===================================================================
# Step 4: Install Starship
# ===================================================================
if [[ "$INSTALL_STARSHIP" == true ]]; then
  _starship_args=()
  [[ "$DEBUG" == true ]] && _starship_args+=(--debug)
  bash "$_SELF_DIR/install_starship.sh" "${_starship_args[@]}"
fi

# ===================================================================
# Step 5: Deploy system-wide shell configuration files
# ===================================================================
echo "📄 Deploying system-wide shell configuration files..." >&2

# --- Shared (shell-agnostic) files ---
for _name in shellenv shellrc shellaliases; do
  _src="${_FILES_DIR}/shell/${_name}"
  _dest="/etc/${_name}"
  if [ -f "$_src" ]; then
    cp -f "$_src" "$_dest"
    chmod 644 "$_dest"
    echo "  ✅ ${_dest}" >&2
  fi
done

# --- /etc/profile ---
_src="${_FILES_DIR}/profile"
if [ -f "$_src" ]; then
  cp -f "$_src" "/etc/profile"
  chmod 644 "/etc/profile"
  echo "  ✅ /etc/profile" >&2
fi

# --- Bash system-wide bashrc ---
_SYS_BASHRC="$(shell__detect_bashrc)"
_src="${_FILES_DIR}/bash/bashrc"
if [ -f "$_src" ]; then
  mkdir -p "$(dirname "$_SYS_BASHRC")"
  cp -f "$_src" "$_SYS_BASHRC"
  chmod 644 "$_SYS_BASHRC"
  echo "  ✅ ${_SYS_BASHRC}" >&2
fi

# --- Bash bashenv (if present in files/) ---
_src="${_FILES_DIR}/bash/bashenv"
if [ -f "$_src" ]; then
  # Place bashenv next to bashrc: /etc/bash/bashenv, /etc/bashenv, etc.
  _bashenv_dest="$(dirname "$_SYS_BASHRC")/bashenv"
  # If bashrc is at /etc/bashrc or /etc/bash.bashrc, put bashenv at /etc/bashenv.
  [[ "$_SYS_BASHRC" == "/etc/bash.bashrc" ]] && _bashenv_dest="/etc/bashenv"
  [[ "$_SYS_BASHRC" == "/etc/bashrc" ]] && _bashenv_dest="/etc/bashenv"
  cp -f "$_src" "$_bashenv_dest"
  chmod 644 "$_bashenv_dest"
  echo "  ✅ ${_bashenv_dest}" >&2

  # Ensure BASH_ENV is set system-wide so non-interactive non-login bash
  # sessions (VS Code tasks, devcontainer exec, CI runners) source it.
  if ! grep -qxF "BASH_ENV=${_bashenv_dest}" /etc/environment 2> /dev/null; then
    # Remove any stale BASH_ENV line first, then append the correct one.
    sed -i '/^BASH_ENV=/d' /etc/environment 2> /dev/null || true
    echo "BASH_ENV=${_bashenv_dest}" >> /etc/environment
    echo "  ✅ BASH_ENV=${_bashenv_dest} → /etc/environment" >&2
  fi
fi

# --- Zsh system-wide files ---
if command -v zsh > /dev/null 2>&1; then
  _ZSH_ETC="$(shell__detect_zshdir)"
  mkdir -p "$_ZSH_ETC"

  for _name in zshenv zprofile zshrc; do
    _src="${_FILES_DIR}/zsh/${_name}"
    _dest="${_ZSH_ETC}/${_name}"
    if [ -f "$_src" ]; then
      cp -f "$_src" "$_dest"
      chmod 644 "$_dest"
      echo "  ✅ ${_dest}" >&2
    fi
  done
fi

# ===================================================================
# Step 6: Resolve user list
# ===================================================================
mapfile -t _RESOLVED_USERS < <(users__resolve_list)

if [ ${#_RESOLVED_USERS[@]} -eq 0 ]; then
  echo "ℹ️  No users to configure." >&2
else
  echo "👤 Users to configure: ${_RESOLVED_USERS[*]}" >&2
fi

# ===================================================================
# Step 7: Per-user configuration
# ===================================================================
for _username in "${_RESOLVED_USERS[@]}"; do
  # Verify the user exists.
  if ! id "$_username" > /dev/null 2>&1; then
    echo "⚠️  User '${_username}' does not exist — skipping." >&2
    continue
  fi

  _CONFIGURE_ARGS=(
    --username "$_username"
    --skel_dir "$_SKEL_DIR"
    --user_config_mode "$USER_CONFIG_MODE"
    --zdotdir "$ZDOTDIR"
    --starship_shells "${STARSHIP_SHELLS[*]}"
  )

  if [[ "$_OMZ_INSTALLED" == true ]]; then
    _CONFIGURE_ARGS+=(
      --ohmyzsh_install_dir "$OHMYZSH_INSTALL_DIR"
      --ohmyzsh_custom_dir "$OHMYZSH_CUSTOM_DIR"
      --ohmyzsh_theme "$OHMYZSH_THEME"
      --ohmyzsh_plugins "${OHMYZSH_PLUGINS[*]}"
    )
  fi

  if [[ "$_OMB_INSTALLED" == true ]]; then
    _CONFIGURE_ARGS+=(
      --ohmybash_install_dir "$OHMYBASH_INSTALL_DIR"
      --ohmybash_custom_dir "$OHMYBASH_CUSTOM_DIR"
      --ohmybash_theme "$OHMYBASH_THEME"
      --ohmybash_plugins "${OHMYBASH_PLUGINS[*]}"
    )
  fi

  [[ "$DEBUG" == true ]] && _CONFIGURE_ARGS+=(--debug)

  bash "$_SELF_DIR/configure_user.sh" "${_CONFIGURE_ARGS[@]}"
done

# ===================================================================
# Step 8: Set default shells
# ===================================================================
if [[ "$SET_USER_SHELLS" != "none" ]] && [ ${#_RESOLVED_USERS[@]} -gt 0 ]; then
  _TARGET_SHELL=""
  case "$SET_USER_SHELLS" in
    zsh)
      _TARGET_SHELL="$(command -v zsh 2> /dev/null || true)"
      if [ -z "$_TARGET_SHELL" ]; then
        echo "⛔ set_user_shells=zsh but zsh is not installed." >&2
        exit 1
      fi
      ;;
    bash)
      _TARGET_SHELL="$(command -v bash 2> /dev/null || true)"
      if [ -z "$_TARGET_SHELL" ]; then
        echo "⛔ set_user_shells=bash but bash is not installed." >&2
        exit 1
      fi
      ;;
    *)
      echo "⛔ Invalid set_user_shells value: '${SET_USER_SHELLS}' (expected: zsh, bash, none)." >&2
      exit 1
      ;;
  esac

  users__set_login_shell "$_TARGET_SHELL" "${_RESOLVED_USERS[@]}"
fi

ospkg__clean
