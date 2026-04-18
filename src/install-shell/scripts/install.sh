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
  [[ "${KEEP_CACHE:-true}" != true ]] && ospkg__clean
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
  --install_starship {true,false}              Install the Starship prompt binary. (default: "true")
  --starship_prefix <value>                    Installation prefix for Starship. The binary is placed at `$starship_prefix/bin/starship`. (default: "/usr/local")
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
  --keep_cache {true,false}                    Keep the package manager cache after installation. By default, the package manager cache is removed after installation to reduce image layer size. Set this flag to true to keep the cache, which may speed up subsequent installations at the cost of larger image layers. (default: "false")
  --debug {true,false}                         Enable debug output. This adds `set -x` to the installer script, which prints each command before executing it. (default: "false")
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
  STARSHIP_PREFIX="/usr/local"
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
  KEEP_CACHE=false
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
      --starship_prefix)
        shift
        STARSHIP_PREFIX="$1"
        echo "📩 Read argument 'starship_prefix': '${STARSHIP_PREFIX}'" >&2
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
  [ "${INSTALL_ZSH+defined}" ] && echo "📩 Read argument 'install_zsh': '${INSTALL_ZSH}'" >&2
  [ "${INSTALL_OHMYZSH+defined}" ] && echo "📩 Read argument 'install_ohmyzsh': '${INSTALL_OHMYZSH}'" >&2
  [ "${INSTALL_OHMYBASH+defined}" ] && echo "📩 Read argument 'install_ohmybash': '${INSTALL_OHMYBASH}'" >&2
  [ "${INSTALL_STARSHIP+defined}" ] && echo "📩 Read argument 'install_starship': '${INSTALL_STARSHIP}'" >&2
  [ "${STARSHIP_PREFIX+defined}" ] && echo "📩 Read argument 'starship_prefix': '${STARSHIP_PREFIX}'" >&2
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
  [ "${KEEP_CACHE+defined}" ] && echo "📩 Read argument 'keep_cache': '${KEEP_CACHE}'" >&2
  [ "${DEBUG+defined}" ] && echo "📩 Read argument 'debug': '${DEBUG}'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
fi

[[ "${DEBUG:-}" == true ]] && set -x

# Apply defaults.
[ "${INSTALL_ZSH+defined}" ] || {
  INSTALL_ZSH=true
  echo "ℹ️ Argument 'install_zsh' set to default value 'true'." >&2
}
[ "${INSTALL_OHMYZSH+defined}" ] || {
  INSTALL_OHMYZSH=true
  echo "ℹ️ Argument 'install_ohmyzsh' set to default value 'true'." >&2
}
[ "${INSTALL_OHMYBASH+defined}" ] || {
  INSTALL_OHMYBASH=true
  echo "ℹ️ Argument 'install_ohmybash' set to default value 'true'." >&2
}
[ "${INSTALL_STARSHIP+defined}" ] || {
  INSTALL_STARSHIP=true
  echo "ℹ️ Argument 'install_starship' set to default value 'true'." >&2
}
[ "${STARSHIP_PREFIX+defined}" ] || {
  STARSHIP_PREFIX="/usr/local"
  echo "ℹ️ Argument 'starship_prefix' set to default value '/usr/local'." >&2
}
[ "${STARSHIP_SHELLS+defined}" ] || {
  mapfile -t STARSHIP_SHELLS < <(printf '%s' $'zsh' | grep -v '^$')
  echo "ℹ️ Argument 'starship_shells' set to default value 'zsh'." >&2
}
[ "${OHMYZSH_PLUGINS+defined}" ] || {
  mapfile -t OHMYZSH_PLUGINS < <(printf '%s' $'git\nzsh-users/zsh-syntax-highlighting' | grep -v '^$')
  echo "ℹ️ Argument 'ohmyzsh_plugins' set to default value 'git, zsh-users/zsh-syntax-highlighting'." >&2
}
[ "${OHMYBASH_PLUGINS+defined}" ] || {
  mapfile -t OHMYBASH_PLUGINS < <(printf '%s' $'git' | grep -v '^$')
  echo "ℹ️ Argument 'ohmybash_plugins' set to default value 'git'." >&2
}
[ "${OHMYZSH_THEME+defined}" ] || {
  OHMYZSH_THEME=""
  echo "ℹ️ Argument 'ohmyzsh_theme' set to default value ''." >&2
}
[ "${OHMYBASH_THEME+defined}" ] || {
  OHMYBASH_THEME=""
  echo "ℹ️ Argument 'ohmybash_theme' set to default value ''." >&2
}
[ "${OHMYZSH_INSTALL_DIR+defined}" ] || {
  OHMYZSH_INSTALL_DIR="/usr/local/share/oh-my-zsh"
  echo "ℹ️ Argument 'ohmyzsh_install_dir' set to default value '/usr/local/share/oh-my-zsh'." >&2
}
[ "${OHMYBASH_INSTALL_DIR+defined}" ] || {
  OHMYBASH_INSTALL_DIR="/usr/local/share/oh-my-bash"
  echo "ℹ️ Argument 'ohmybash_install_dir' set to default value '/usr/local/share/oh-my-bash'." >&2
}
[ "${OHMYZSH_BRANCH+defined}" ] || {
  OHMYZSH_BRANCH="master"
  echo "ℹ️ Argument 'ohmyzsh_branch' set to default value 'master'." >&2
}
[ "${OHMYBASH_BRANCH+defined}" ] || {
  OHMYBASH_BRANCH="master"
  echo "ℹ️ Argument 'ohmybash_branch' set to default value 'master'." >&2
}
[ "${ADD_CURRENT_USER+defined}" ] || {
  ADD_CURRENT_USER=true
  echo "ℹ️ Argument 'add_current_user' set to default value 'true'." >&2
}
[ "${ADD_CONTAINER_USER+defined}" ] || {
  ADD_CONTAINER_USER=true
  echo "ℹ️ Argument 'add_container_user' set to default value 'true'." >&2
}
[ "${ADD_REMOTE_USER+defined}" ] || {
  ADD_REMOTE_USER=true
  echo "ℹ️ Argument 'add_remote_user' set to default value 'true'." >&2
}
[ "${ADD_USERS+defined}" ] || {
  ADD_USERS=()
  echo "ℹ️ Argument 'add_users' set to default value '(empty)'." >&2
}
[ "${SET_USER_SHELLS+defined}" ] || {
  SET_USER_SHELLS="zsh"
  echo "ℹ️ Argument 'set_user_shells' set to default value 'zsh'." >&2
}
[ "${ZDOTDIR+defined}" ] || {
  ZDOTDIR=""
  echo "ℹ️ Argument 'zdotdir' set to default value ''." >&2
}
[ "${OHMYZSH_CUSTOM_DIR+defined}" ] || {
  OHMYZSH_CUSTOM_DIR=""
  echo "ℹ️ Argument 'ohmyzsh_custom_dir' set to default value ''." >&2
}
[ "${OHMYBASH_CUSTOM_DIR+defined}" ] || {
  OHMYBASH_CUSTOM_DIR=""
  echo "ℹ️ Argument 'ohmybash_custom_dir' set to default value ''." >&2
}
[ "${USER_CONFIG_MODE+defined}" ] || {
  USER_CONFIG_MODE="overwrite"
  echo "ℹ️ Argument 'user_config_mode' set to default value 'overwrite'." >&2
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
# shellcheck source=lib/git.sh
. "$_SELF_DIR/_lib/git.sh"
# shellcheck source=lib/net.sh
. "$_SELF_DIR/_lib/net.sh"

_GITHUB_BASE_URL="https://github.com"
_OHMYZSH_REPO_URL="${_GITHUB_BASE_URL}/ohmyzsh/ohmyzsh"
_OHMYBASH_REPO_URL="${_GITHUB_BASE_URL}/ohmybash/oh-my-bash"
_STARSHIP_INSTALLER_URL="https://starship.rs/install.sh"

# ---------------------------------------------------------------------------
# install_ohmyzsh — Clone OMZ, scaffold ZSH_CUSTOM, clone custom theme/plugins.
# Uses: OHMYZSH_INSTALL_DIR, OHMYZSH_BRANCH, OHMYZSH_THEME, OHMYZSH_CUSTOM_DIR,
#       OHMYZSH_PLUGINS (array).
# ---------------------------------------------------------------------------
install_ohmyzsh() {
  local _install_dir="$OHMYZSH_INSTALL_DIR"
  local _branch="$OHMYZSH_BRANCH"
  local _theme="$OHMYZSH_THEME"
  # Use an explicit system-path custom dir if given; per-user paths (~/$HOME-prefixed)
  # and the empty default are handled at configure-user time via symlinks.
  local _custom_dir
  # shellcheck disable=SC2016
  if [ -n "$OHMYZSH_CUSTOM_DIR" ] &&
    [[ "$OHMYZSH_CUSTOM_DIR" != '~'* ]] &&
    [[ "$OHMYZSH_CUSTOM_DIR" != '$HOME'* ]]; then
    _custom_dir="$OHMYZSH_CUSTOM_DIR"
  else
    _custom_dir="${_install_dir}/custom"
  fi

  echo "ℹ️  Installing Oh My Zsh to '${_install_dir}' (branch: ${_branch})..." >&2
  local _prev_umask
  _prev_umask="$(umask)"
  umask g-w,o-w
  git__clone --url "$_OHMYZSH_REPO_URL" --dir "$_install_dir" --branch "$_branch"
  umask "$_prev_umask"

  # Set oh-my-zsh update metadata so 'omz update' knows which remote/branch.
  git -C "$_install_dir" config oh-my-zsh.remote origin
  git -C "$_install_dir" config oh-my-zsh.branch "$_branch"

  mkdir -p "${_custom_dir}/themes" "${_custom_dir}/plugins"

  if [ -n "$_theme" ]; then
    local _theme_repo_name
    _theme_repo_name="$(basename "$_theme")"
    git__clone --url "${_GITHUB_BASE_URL}/${_theme}" --dir "${_custom_dir}/themes/${_theme_repo_name}"
    echo "ℹ️  Installed custom theme '${_theme}'." >&2
  fi

  local _slug
  for _slug in "${OHMYZSH_PLUGINS[@]}"; do
    _slug="${_slug// /}"
    [ -z "$_slug" ] && continue
    if [[ "$_slug" != */* ]]; then
      echo "ℹ️  '${_slug}' is a built-in plugin — skipping clone." >&2
      continue
    fi
    local _plugin_name
    _plugin_name="$(basename "$_slug")"
    git__clone --url "${_GITHUB_BASE_URL}/${_slug}" --dir "${_custom_dir}/plugins/${_plugin_name}"
    echo "ℹ️  Installed custom plugin '${_slug}'." >&2
  done

  echo "✅ Oh My Zsh installation complete." >&2
  return 0
}

# ---------------------------------------------------------------------------
# install_ohmybash — Clone OMB, scaffold OSH_CUSTOM, clone custom theme/plugins.
# Uses: OHMYBASH_INSTALL_DIR, OHMYBASH_BRANCH, OHMYBASH_THEME, OHMYBASH_CUSTOM_DIR,
#       OHMYBASH_PLUGINS (array).
# ---------------------------------------------------------------------------
install_ohmybash() {
  local _install_dir="$OHMYBASH_INSTALL_DIR"
  local _branch="$OHMYBASH_BRANCH"
  local _theme="$OHMYBASH_THEME"
  local _custom_dir
  # shellcheck disable=SC2016
  if [ -n "$OHMYBASH_CUSTOM_DIR" ] &&
    [[ "$OHMYBASH_CUSTOM_DIR" != '~'* ]] &&
    [[ "$OHMYBASH_CUSTOM_DIR" != '$HOME'* ]]; then
    _custom_dir="$OHMYBASH_CUSTOM_DIR"
  else
    _custom_dir="${_install_dir}/custom"
  fi

  echo "ℹ️  Installing Oh My Bash to '${_install_dir}' (branch: ${_branch})..." >&2
  local _prev_umask
  _prev_umask="$(umask)"
  umask g-w,o-w
  git__clone --url "$_OHMYBASH_REPO_URL" --dir "$_install_dir" --branch "$_branch"
  umask "$_prev_umask"

  # Set update metadata so 'omb update' knows which remote/branch.
  git -C "$_install_dir" config oh-my-bash.remote origin
  git -C "$_install_dir" config oh-my-bash.branch "$_branch"

  mkdir -p "${_custom_dir}/themes" "${_custom_dir}/plugins"

  if [ -n "$_theme" ]; then
    local _theme_repo_name
    _theme_repo_name="$(basename "$_theme")"
    git__clone --url "${_GITHUB_BASE_URL}/${_theme}" --dir "${_custom_dir}/themes/${_theme_repo_name}"
    echo "ℹ️  Installed custom theme '${_theme}'." >&2
  fi

  local _slug
  for _slug in "${OHMYBASH_PLUGINS[@]}"; do
    _slug="${_slug// /}"
    [ -z "$_slug" ] && continue
    if [[ "$_slug" != */* ]]; then
      echo "ℹ️  '${_slug}' is a built-in plugin — skipping clone." >&2
      continue
    fi
    local _plugin_name
    _plugin_name="$(basename "$_slug")"
    git__clone --url "${_GITHUB_BASE_URL}/${_slug}" --dir "${_custom_dir}/plugins/${_plugin_name}"
    echo "ℹ️  Installed custom plugin '${_slug}'." >&2
  done

  echo "✅ Oh My Bash installation complete." >&2
  return 0
}

# ---------------------------------------------------------------------------
# install_starship — Download and run the official Starship installer.
# ---------------------------------------------------------------------------
install_starship() {
  local _bin_dir="${STARSHIP_PREFIX}/bin"

  if [ -x "${_bin_dir}/starship" ]; then
    echo "ℹ️  Starship already installed at '${_bin_dir}/starship' — skipping." >&2
    return 0
  fi

  echo "ℹ️  Installing Starship to '${_bin_dir}'..." >&2
  local _installer_script
  _installer_script="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '${_installer_script}'" RETURN

  net__fetch_url_file "$_STARSHIP_INSTALLER_URL" "$_installer_script"
  chmod +x "$_installer_script"
  sh "$_installer_script" --yes --bin-dir "$_bin_dir" >&2

  if [ -x "${_bin_dir}/starship" ]; then
    echo "✅ Starship installed to '${_bin_dir}/starship'." >&2
  else
    echo "⛔ Starship installation failed." >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# _resolve_custom_dir <raw_value> <user_home>
# Expands ~- and $HOME-prefixed paths to absolute paths for the given user.
# Absolute paths and other values are passed through unchanged.
# ---------------------------------------------------------------------------
_resolve_custom_dir() {
  local _raw="$1" _home="$2"
  # shellcheck disable=SC2016
  if [[ "$_raw" == '~'* ]]; then
    printf '%s%s' "$_home" "${_raw#\~}"
  elif [[ "$_raw" == '$HOME'* ]]; then
    printf '%s%s' "$_home" "${_raw#'$HOME'}"
  else
    printf '%s' "$_raw"
  fi
}

# _link_custom_items <src_custom_dir> <dest_custom_dir> <theme_slug> <plugins_csv> <mode>
# Creates symlinks in dest for exactly the named items declared in theme_slug + plugins_csv.
#   overwrite: removes existing symlink for that name, creates fresh one (skips real dirs)
#   augment:   creates symlink only if name not already present (symlink or real dir)
# User-added real dirs (non-symlinks) are never removed.
_link_custom_items() {
  local _src="$1" _dest="$2" _theme_slug="$3" _plugins_csv="$4" _mode="$5"
  mkdir -p "${_dest}/themes" "${_dest}/plugins"

  local -a _items=()
  if [ -n "$_theme_slug" ]; then
    _items+=("themes/$(basename "$_theme_slug")")
  fi
  if [ -n "$_plugins_csv" ]; then
    local _slug
    local -a _slugs=()
    IFS=',' read -r -a _slugs <<< "$_plugins_csv"
    for _slug in "${_slugs[@]}"; do
      _slug="${_slug// /}"
      [ -z "$_slug" ] && continue
      [[ "$_slug" != */* ]] && continue # built-in plugin, no clone
      _items+=("plugins/$(basename "$_slug")")
    done
  fi

  local _item _src_path _dest_path
  for _item in "${_items[@]}"; do
    _src_path="${_src}/${_item}"
    _dest_path="${_dest}/${_item}"
    [ -d "$_src_path" ] || continue # not cloned, skip
    if [[ "$_mode" == "overwrite" ]]; then
      [ -L "$_dest_path" ] && rm "$_dest_path"
      [ ! -e "$_dest_path" ] && ln -sf "$_src_path" "$_dest_path"
    else
      [ ! -e "$_dest_path" ] && ln -sf "$_src_path" "$_dest_path"
    fi
  done
}

# ---------------------------------------------------------------------------
# configure_user <username>
# Set up per-user shell configuration files.
# Reads OMZ, OMB, Starship, and other settings from outer-scope variables.
# ---------------------------------------------------------------------------
configure_user() {
  local _cu_username="$1"
  # Flatten array options to space-separated strings (matches the arg-passing
  # convention previously used when invoking the standalone script).
  local _cu_starship_shells="${STARSHIP_SHELLS[*]}"
  local _cu_omz_plugins="${OHMYZSH_PLUGINS[*]}"
  local _cu_omb_plugins="${OHMYBASH_PLUGINS[*]}"
  local _cu_bin_dir="${STARSHIP_PREFIX}/bin"

  # Resolve user's home directory and group.
  local _cu_home
  _cu_home="$(shell__resolve_home "$_cu_username")"
  local _cu_group
  _cu_group="$(id -gn "$_cu_username" 2> /dev/null || echo "$_cu_username")"

  if [ ! -d "$_cu_home" ]; then
    echo "⚠️  Home directory '${_cu_home}' does not exist for user '${_cu_username}' — creating." >&2
    mkdir -p "$_cu_home"
    chown "${_cu_username}:${_cu_group}" "$_cu_home"
  fi

  echo "ℹ️  Configuring user '${_cu_username}' (home: ${_cu_home}, mode: ${USER_CONFIG_MODE})..." >&2

  # Resolve per-user XDG and Zsh config paths.
  local _cu_xdg_config_home="${_cu_home}/.config"
  # Expand ZDOTDIR option (may be ~-prefixed, $HOME-prefixed, or absolute).
  local _cu_zdotdir
  # shellcheck disable=SC2016
  if [ -z "${ZDOTDIR-}" ]; then
    _cu_zdotdir="${_cu_xdg_config_home}/zsh"
  elif [[ "$ZDOTDIR" == '~'* ]]; then
    _cu_zdotdir="${_cu_home}${ZDOTDIR#\~}"
  elif [[ "$ZDOTDIR" == '$HOME'* ]]; then
    _cu_zdotdir="${_cu_home}${ZDOTDIR#'$HOME'}"
  else
    _cu_zdotdir="$ZDOTDIR"
  fi

  # Apply defaults for custom dirs if not explicitly provided.
  local _cu_omz_custom_dir="${OHMYZSH_CUSTOM_DIR:-}"
  [ -z "$_cu_omz_custom_dir" ] && _cu_omz_custom_dir="${_cu_zdotdir}/custom"
  local _cu_omb_custom_dir="${OHMYBASH_CUSTOM_DIR:-}"
  [ -z "$_cu_omb_custom_dir" ] && _cu_omb_custom_dir="${_cu_xdg_config_home}/bash/custom"

  # Mode: skip — bail out if any dotfile already exists.
  if [[ "$USER_CONFIG_MODE" == "skip" ]]; then
    if [ -f "${_cu_zdotdir}/.zshrc" ] || [ -f "${_cu_home}/.bashrc" ]; then
      echo "ℹ️  User '${_cu_username}' already has dotfiles — skipping (mode=skip)." >&2
      return 0
    fi
  fi

  # Copy skeleton files.
  if [ -n "$_SKEL_DIR" ] && [ -d "$_SKEL_DIR" ]; then
    local _cu_skel_file _cu_rel _cu_dest
    while IFS= read -r -d '' _cu_skel_file; do
      _cu_rel="${_cu_skel_file#"${_SKEL_DIR}"/}"
      [[ "$_cu_rel" == "p10k.zsh" ]] && continue
      # .zshenv always lives in HOME so zsh finds it before ZDOTDIR is set.
      # All other zsh config files go into ZDOTDIR.
      case "$_cu_rel" in
        .zshenv) _cu_dest="${_cu_home}/${_cu_rel}" ;;
        .zshrc | .zprofile | .zlogin) _cu_dest="${_cu_zdotdir}/${_cu_rel}" ;;
        *) _cu_dest="${_cu_home}/${_cu_rel}" ;;
      esac
      case "$USER_CONFIG_MODE" in
        overwrite)
          mkdir -p "$(dirname "$_cu_dest")"
          cp -f "$_cu_skel_file" "$_cu_dest"
          ;;
        augment)
          if [ ! -f "$_cu_dest" ]; then
            mkdir -p "$(dirname "$_cu_dest")"
            cp "$_cu_skel_file" "$_cu_dest"
          fi
          ;;
      esac
    done < <(find "$_SKEL_DIR" -maxdepth 1 -type f -print0)
  fi

  # Inject ZDOTDIR into ~/.zshenv.
  local _cu_zshenv="${_cu_home}/.zshenv"
  mkdir -p "$_cu_zdotdir"
  shell__write_block --file "$_cu_zshenv" --marker "install-shell-zdotdir" --content "ZDOTDIR=\"${_cu_zdotdir}\""

  # ---------------------------------------------------------------------------
  # Zsh theme file ($ZDOTDIR/zshtheme)
  # ---------------------------------------------------------------------------
  local _cu_zshtheme="${_cu_zdotdir}/zshtheme"
  local _cu_zshtheme_content=""

  if [[ "$_OMZ_INSTALLED" == true ]]; then
    local _cu_omz_effective_custom_dir
    _cu_omz_effective_custom_dir="$(_resolve_custom_dir "$_cu_omz_custom_dir" "$_cu_home")"
    local _cu_omz_is_per_user=false
    [[ "$_cu_omz_effective_custom_dir" == "$_cu_home"* ]] && _cu_omz_is_per_user=true

    local _cu_omz_theme_value=""
    if [ -n "$OHMYZSH_THEME" ]; then
      _cu_omz_theme_value="$(shell__resolve_omz_theme \
        --theme_slug "$OHMYZSH_THEME" \
        --custom_dir "${OHMYZSH_INSTALL_DIR}/custom")"
    fi

    local _cu_omz_plugin_names=""
    if [ -n "$_cu_omz_plugins" ]; then
      _cu_omz_plugin_names="$(shell__plugin_names_from_slugs "$_cu_omz_plugins" | tr '\n' ' ')"
      _cu_omz_plugin_names="${_cu_omz_plugin_names% }"
    fi

    local _cu_is_p10k=false
    [[ "$OHMYZSH_THEME" == *powerlevel10k* ]] && _cu_is_p10k=true

    local _cu_zsh_use_starship=false
    if [[ "$_cu_starship_shells" == *zsh* ]]; then
      _cu_zsh_use_starship=true
      if [ -n "$OHMYZSH_THEME" ]; then
        echo "⚠️  ohmyzsh_theme='${OHMYZSH_THEME}' is set but starship_shells includes 'zsh' — theme ignored, Starship will own the prompt." >&2
      fi
    fi

    # shellcheck disable=SC2016
    _cu_zshtheme_content+="export ZSH=\"${OHMYZSH_INSTALL_DIR}\""$'\n'
    # shellcheck disable=SC2016
    _cu_zshtheme_content+='ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-zsh"'$'\n'
    # shellcheck disable=SC2016
    _cu_zshtheme_content+='[ -d "$ZSH_CACHE_DIR" ] || mkdir -p "$ZSH_CACHE_DIR"'$'\n'
    # shellcheck disable=SC2016
    _cu_zshtheme_content+='ZSH_COMPDUMP="${ZSH_CACHE_DIR}/.zcompdump-${SHORT_HOST}-${ZSH_VERSION}"'$'\n'
    _cu_zshtheme_content+="ZSH_CUSTOM=\"${_cu_omz_effective_custom_dir}\""$'\n'

    if [[ "$_cu_zsh_use_starship" == true ]]; then
      _cu_zshtheme_content+='ZSH_THEME=""'$'\n'
    elif [ -n "$_cu_omz_theme_value" ]; then
      _cu_zshtheme_content+="ZSH_THEME=\"${_cu_omz_theme_value}\""$'\n'
    else
      _cu_zshtheme_content+='ZSH_THEME=""'$'\n'
    fi

    if [ -n "$_cu_omz_plugin_names" ]; then
      _cu_zshtheme_content+="plugins=(${_cu_omz_plugin_names})"$'\n'
    else
      _cu_zshtheme_content+='plugins=()'$'\n'
    fi

    _cu_zshtheme_content+="zstyle ':omz:update' mode disabled"$'\n'

    if [[ "$_cu_is_p10k" == true ]] && [[ "$_cu_zsh_use_starship" != true ]]; then
      _cu_zshtheme_content+='POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true'$'\n'
    fi

    # shellcheck disable=SC2016
    _cu_zshtheme_content+='[ -f "$ZSH/oh-my-zsh.sh" ] && source "$ZSH/oh-my-zsh.sh"'$'\n'

    if [[ "$_cu_is_p10k" == true ]] && [[ "$_cu_zsh_use_starship" != true ]]; then
      # shellcheck disable=SC2016
      _cu_zshtheme_content+='[[ ! -f "${HOME}/.p10k.zsh" ]] || source "${HOME}/.p10k.zsh"'$'\n'
    fi

    mkdir -p "${_cu_omz_effective_custom_dir}/themes" "${_cu_omz_effective_custom_dir}/plugins"
    if [[ "$_cu_omz_is_per_user" == true ]]; then
      _link_custom_items \
        "${OHMYZSH_INSTALL_DIR}/custom" \
        "$_cu_omz_effective_custom_dir" \
        "$OHMYZSH_THEME" \
        "$_cu_omz_plugins" \
        "$USER_CONFIG_MODE"
    fi

    if [[ "$_cu_is_p10k" == true ]] && [[ "$_cu_zsh_use_starship" != true ]] &&
      [ -n "$_SKEL_DIR" ] && [ -f "${_SKEL_DIR}/p10k.zsh" ]; then
      case "$USER_CONFIG_MODE" in
        overwrite)
          cp -f "${_SKEL_DIR}/p10k.zsh" "${_cu_home}/.p10k.zsh"
          ;;
        augment)
          [ ! -f "${_cu_home}/.p10k.zsh" ] && cp "${_SKEL_DIR}/p10k.zsh" "${_cu_home}/.p10k.zsh"
          ;;
      esac
    fi
  fi

  # Append Starship integration for zsh.
  if [[ "$_cu_starship_shells" == *zsh* ]]; then
    if ! command -v starship > /dev/null 2>&1 && [ ! -x "${_cu_bin_dir}/starship" ]; then
      echo "⚠️  starship_shells includes 'zsh' but starship is not on PATH — integration injected anyway." >&2
    fi
    # shellcheck disable=SC2016
    _cu_zshtheme_content+='command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"'$'\n'
  fi

  # Write zshtheme file.
  if [ -n "$_cu_zshtheme_content" ]; then
    mkdir -p "$_cu_zdotdir"
    case "$USER_CONFIG_MODE" in
      overwrite)
        printf '%s' "$_cu_zshtheme_content" > "$_cu_zshtheme"
        echo "ℹ️  Written zsh theme file '${_cu_zshtheme}'." >&2
        ;;
      augment)
        if [ ! -f "$_cu_zshtheme" ]; then
          printf '%s' "$_cu_zshtheme_content" > "$_cu_zshtheme"
          echo "ℹ️  Written zsh theme file '${_cu_zshtheme}'." >&2
        fi
        ;;
    esac
  fi

  # ---------------------------------------------------------------------------
  # Bash theme file (~/.config/bash/bashtheme)
  # ---------------------------------------------------------------------------
  local _cu_bashtheme="${_cu_xdg_config_home}/bash/bashtheme"
  local _cu_bashtheme_content=""

  if [[ "$_OMB_INSTALLED" == true ]]; then
    local _cu_omb_effective_custom_dir
    _cu_omb_effective_custom_dir="$(_resolve_custom_dir "$_cu_omb_custom_dir" "$_cu_home")"
    local _cu_omb_is_per_user=false
    [[ "$_cu_omb_effective_custom_dir" == "$_cu_home"* ]] && _cu_omb_is_per_user=true

    local _cu_omb_theme_value=""
    if [ -n "$OHMYBASH_THEME" ]; then
      _cu_omb_theme_value="$(basename "$OHMYBASH_THEME")"
    fi

    local _cu_omb_plugin_names=""
    if [ -n "$_cu_omb_plugins" ]; then
      _cu_omb_plugin_names="$(shell__plugin_names_from_slugs "$_cu_omb_plugins" | tr '\n' ' ')"
      _cu_omb_plugin_names="${_cu_omb_plugin_names% }"
    fi

    local _cu_bash_use_starship=false
    if [[ "$_cu_starship_shells" == *bash* ]]; then
      _cu_bash_use_starship=true
      if [ -n "$OHMYBASH_THEME" ]; then
        echo "⚠️  ohmybash_theme='${OHMYBASH_THEME}' is set but starship_shells includes 'bash' — theme ignored, Starship will own the prompt." >&2
      fi
    fi

    _cu_bashtheme_content+="export OSH=\"${OHMYBASH_INSTALL_DIR}\""$'\n'
    # shellcheck disable=SC2016
    _cu_bashtheme_content+='OSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-bash"'$'\n'
    # shellcheck disable=SC2016
    _cu_bashtheme_content+='[ -d "$OSH_CACHE_DIR" ] || mkdir -p "$OSH_CACHE_DIR"'$'\n'
    _cu_bashtheme_content+="OSH_CUSTOM=\"${_cu_omb_effective_custom_dir}\""$'\n'

    if [[ "$_cu_bash_use_starship" == true ]]; then
      _cu_bashtheme_content+='OSH_THEME=""'$'\n'
    elif [ -n "$_cu_omb_theme_value" ]; then
      _cu_bashtheme_content+="OSH_THEME=\"${_cu_omb_theme_value}\""$'\n'
    else
      _cu_bashtheme_content+='OSH_THEME=""'$'\n'
    fi

    if [ -n "$_cu_omb_plugin_names" ]; then
      _cu_bashtheme_content+="plugins=(${_cu_omb_plugin_names})"$'\n'
    else
      _cu_bashtheme_content+='plugins=()'$'\n'
    fi

    # shellcheck disable=SC2016
    _cu_bashtheme_content+='[ -f "$OSH/oh-my-bash.sh" ] && source "$OSH/oh-my-bash.sh"'$'\n'

    mkdir -p "${_cu_omb_effective_custom_dir}/themes" "${_cu_omb_effective_custom_dir}/plugins"
    if [[ "$_cu_omb_is_per_user" == true ]]; then
      _link_custom_items \
        "${OHMYBASH_INSTALL_DIR}/custom" \
        "$_cu_omb_effective_custom_dir" \
        "$OHMYBASH_THEME" \
        "$_cu_omb_plugins" \
        "$USER_CONFIG_MODE"
    fi
  fi

  # Append Starship integration for bash.
  if [[ "$_cu_starship_shells" == *bash* ]]; then
    if ! command -v starship > /dev/null 2>&1 && [ ! -x "${_cu_bin_dir}/starship" ]; then
      echo "⚠️  starship_shells includes 'bash' but starship is not on PATH — integration injected anyway." >&2
    fi
    # shellcheck disable=SC2016
    _cu_bashtheme_content+='command -v starship >/dev/null 2>&1 && eval "$(starship init bash)"'$'\n'
  fi

  # Write bashtheme file.
  if [ -n "$_cu_bashtheme_content" ]; then
    mkdir -p "${_cu_xdg_config_home}/bash"
    case "$USER_CONFIG_MODE" in
      overwrite)
        printf '%s' "$_cu_bashtheme_content" > "$_cu_bashtheme"
        echo "ℹ️  Written bash theme file '${_cu_bashtheme}'." >&2
        ;;
      augment)
        if [ ! -f "$_cu_bashtheme" ]; then
          printf '%s' "$_cu_bashtheme_content" > "$_cu_bashtheme"
          echo "ℹ️  Written bash theme file '${_cu_bashtheme}'." >&2
        fi
        ;;
    esac
  fi

  # Fix ownership — give the user full ownership of their entire home directory.
  chown -R "${_cu_username}:${_cu_group}" "$_cu_home"

  echo "✅ User '${_cu_username}' configuration complete." >&2
  return 0
}

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
    install_ohmyzsh
    _OMZ_INSTALLED=true
  fi
fi

# ===================================================================
# Step 3: Install Oh My Bash
# ===================================================================
_OMB_INSTALLED=false
if [[ "$INSTALL_OHMYBASH" == true ]]; then
  install_ohmybash
  _OMB_INSTALLED=true
fi

# ===================================================================
# Step 4: Install Starship
# ===================================================================
if [[ "$INSTALL_STARSHIP" == true ]]; then
  install_starship
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

  configure_user "$_username"
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
