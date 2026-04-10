#!/usr/bin/env bash
# install-shell main orchestrator.
#
# Installs shells (zsh), shell frameworks (Oh My Zsh, Oh My Bash), the
# Starship prompt, Nerd Fonts, deploys system-wide shell configuration files,
# configures per-user dotfiles, and optionally sets default login shells.
#
# Can be run standalone (CLI flags) or as a devcontainer feature (env vars).
set -euo pipefail

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
_BASE_DIR="$(cd "$_SELF_DIR/.." && pwd)"
_FILES_DIR="${_BASE_DIR}/files"
_SKEL_DIR="${_FILES_DIR}/skel"

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------
# shellcheck source=_lib/ospkg.sh
. "$_SELF_DIR/_lib/ospkg.sh"
# shellcheck source=_lib/shell.sh
. "$_SELF_DIR/_lib/shell.sh"

# ---------------------------------------------------------------------------
# Cleanup / logging
# ---------------------------------------------------------------------------
. "$_SELF_DIR/_lib/logging.sh"
logging::setup
trap 'logging::cleanup' EXIT

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
__usage__() {
  cat >&2 <<'EOF'
Usage: install.sh [OPTIONS]

Shells:
  --install_zsh <bool>             Install zsh (default: true)

Frameworks:
  --install_ohmyzsh <bool>         Install Oh My Zsh (default: true)
  --install_ohmybash <bool>        Install Oh My Bash (default: true)
  --install_starship <bool>        Install Starship prompt (default: true)
  --starship_shells <string>       Comma-separated shells to activate starship in (default: zsh,bash)

Oh My Zsh options:
  --zdotdir <path>                 Zsh config directory (ZDOTDIR, default: ~/.config/zsh)
  --ohmyzsh_install_dir <path>     Installation directory
  --ohmyzsh_custom_dir <path>      ZSH_CUSTOM directory
  --ohmyzsh_branch <string>        Git branch/tag to clone
  --ohmyzsh_theme <string>         Custom theme (owner/repo slug)
  --ohmyzsh_plugins <string>       Comma-separated custom plugin slugs

Oh My Bash options:
  --ohmybash_install_dir <path>    Installation directory
  --ohmybash_custom_dir <path>     OSH_CUSTOM directory
  --ohmybash_branch <string>       Git branch/tag to clone
  --ohmybash_theme <string>        Custom theme (owner/repo slug)
  --ohmybash_plugins <string>      Comma-separated custom plugin slugs

User configuration:
  --add_current_user_config <bool> Configure current user (default: true)
  --add_container_user_config <bool>  Configure containerUser (default: true)
  --add_remote_user_config <bool>  Configure remoteUser (default: true)
  --add_user_config <string>       Comma-separated additional usernames
  --user_config_mode <string>      overwrite | augment | skip (default: overwrite)
  --set_user_shells <string>       zsh | bash | none (default: none)

General:
  --debug                          Enable debug output
  --logfile <path>                 Log file path
  -h, --help                       Show this help
EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing — dual-mode: CLI flags or env vars
# ---------------------------------------------------------------------------
if [ "$#" -gt 0 ]; then
  INSTALL_ZSH=""
  INSTALL_OHMYZSH=""
  INSTALL_OHMYBASH=""
  INSTALL_STARSHIP=""
  STARSHIP_SHELLS=""
  OHMYZSH_INSTALL_DIR=""
  ZDOTDIR=""
  OHMYZSH_CUSTOM_DIR=""
  OHMYZSH_BRANCH=""
  OHMYZSH_THEME=""
  OHMYZSH_PLUGINS=""
  OHMYBASH_INSTALL_DIR=""
  OHMYBASH_CUSTOM_DIR=""
  OHMYBASH_BRANCH=""
  OHMYBASH_THEME=""
  OHMYBASH_PLUGINS=""
  ADD_CURRENT_USER_CONFIG=""
  ADD_CONTAINER_USER_CONFIG=""
  ADD_REMOTE_USER_CONFIG=""
  ADD_USER_CONFIG=""
  USER_CONFIG_MODE=""
  SET_USER_SHELLS=""
  DEBUG=""
  LOGFILE=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      --install_zsh)                shift; INSTALL_ZSH="$1"; shift;;
      --install_ohmyzsh)            shift; INSTALL_OHMYZSH="$1"; shift;;
      --install_ohmybash)           shift; INSTALL_OHMYBASH="$1"; shift;;
      --install_starship)           shift; INSTALL_STARSHIP="$1"; shift;;
      --starship_shells)            shift; STARSHIP_SHELLS="$1"; shift;;

      --ohmyzsh_install_dir)        shift; OHMYZSH_INSTALL_DIR="$1"; shift;;
      --zdotdir)                    shift; ZDOTDIR="$1"; shift;;
      --ohmyzsh_custom_dir)         shift; OHMYZSH_CUSTOM_DIR="$1"; shift;;
      --ohmyzsh_branch)             shift; OHMYZSH_BRANCH="$1"; shift;;
      --ohmyzsh_theme)              shift; OHMYZSH_THEME="$1"; shift;;
      --ohmyzsh_plugins)            shift; OHMYZSH_PLUGINS="$1"; shift;;
      --ohmybash_install_dir)       shift; OHMYBASH_INSTALL_DIR="$1"; shift;;
      --ohmybash_custom_dir)        shift; OHMYBASH_CUSTOM_DIR="$1"; shift;;
      --ohmybash_branch)            shift; OHMYBASH_BRANCH="$1"; shift;;
      --ohmybash_theme)             shift; OHMYBASH_THEME="$1"; shift;;
      --ohmybash_plugins)           shift; OHMYBASH_PLUGINS="$1"; shift;;
      --add_current_user_config)    shift; ADD_CURRENT_USER_CONFIG="$1"; shift;;
      --add_container_user_config)  shift; ADD_CONTAINER_USER_CONFIG="$1"; shift;;
      --add_remote_user_config)     shift; ADD_REMOTE_USER_CONFIG="$1"; shift;;
      --add_user_config)            shift; ADD_USER_CONFIG="$1"; shift;;
      --user_config_mode)           shift; USER_CONFIG_MODE="$1"; shift;;
      --set_user_shells)            shift; SET_USER_SHELLS="$1"; shift;;
      --debug)                      DEBUG=true; shift;;
      --logfile)                    shift; LOGFILE="$1"; shift;;
      --help|-h)                    __usage__;;
      --*) echo "⛔ Unknown option: '${1}'" >&2; exit 1;;
      *)   echo "⛔ Unexpected argument: '${1}'" >&2; exit 1;;
    esac
  done
fi

# ---------------------------------------------------------------------------
# Defaults (match devcontainer-feature.json)
# ---------------------------------------------------------------------------
: "${INSTALL_ZSH:=true}"
: "${INSTALL_OHMYZSH:=true}"
: "${INSTALL_OHMYBASH:=true}"
: "${INSTALL_STARSHIP:=true}"
: "${STARSHIP_SHELLS=zsh,bash}"
: "${OHMYZSH_INSTALL_DIR:=/usr/local/share/oh-my-zsh}"
: "${ZDOTDIR:=}"
: "${OHMYZSH_CUSTOM_DIR:=}"
: "${OHMYZSH_BRANCH:=master}"
: "${OHMYZSH_THEME:=}"
: "${OHMYZSH_PLUGINS=zsh-users/zsh-syntax-highlighting}"
: "${OHMYBASH_INSTALL_DIR:=/usr/local/share/oh-my-bash}"
: "${OHMYBASH_CUSTOM_DIR:=}"
: "${OHMYBASH_BRANCH:=master}"
: "${OHMYBASH_THEME:=}"
: "${OHMYBASH_PLUGINS:=}"
: "${ADD_CURRENT_USER_CONFIG:=true}"
: "${ADD_CONTAINER_USER_CONFIG:=true}"
: "${ADD_REMOTE_USER_CONFIG:=true}"
: "${ADD_USER_CONFIG:=}"
: "${USER_CONFIG_MODE:=overwrite}"
: "${SET_USER_SHELLS:=none}"
: "${DEBUG:=false}"
: "${LOGFILE:=}"

[[ "$DEBUG" == true ]] && set -x

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------
os::require_root

echo "========================================" >&2
echo "  install-shell" >&2
echo "========================================" >&2

# ===================================================================
# Step 1: Install dependencies
# ===================================================================
_PKG_MANIFEST="${_BASE_DIR}/dependencies/base.txt"
ospkg::run --manifest "$_PKG_MANIFEST" --check_installed --no_clean

if [[ "$INSTALL_ZSH" == true ]]; then
  if command -v zsh > /dev/null 2>&1; then
    echo "ℹ️  Zsh already installed — skipping." >&2
  else
    echo "📦 Installing Zsh..." >&2
    ospkg::install zsh
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
      --plugins "$OHMYZSH_PLUGINS"
    )
    # Pass an explicit system-path custom dir to the install script so themes
    # and plugins are cloned there.  Per-user paths (~/$HOME-prefixed) and
    # the empty default are handled at configure-user time via symlinks.
    if [ -n "$OHMYZSH_CUSTOM_DIR" ] && \
       [[ "$OHMYZSH_CUSTOM_DIR" != '~'* ]] && \
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
    --plugins "$OHMYBASH_PLUGINS"
  )
  if [ -n "$OHMYBASH_CUSTOM_DIR" ] && \
     [[ "$OHMYBASH_CUSTOM_DIR" != '~'* ]] && \
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
  bash "$_SELF_DIR/install_starship.sh" \
    $( [[ "$DEBUG" == true ]] && echo "--debug" )
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
_SYS_BASHRC="$(shell::detect_bashrc)"
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
  [[ "$_SYS_BASHRC" == "/etc/bashrc" ]]      && _bashenv_dest="/etc/bashenv"
  cp -f "$_src" "$_bashenv_dest"
  chmod 644 "$_bashenv_dest"
  echo "  ✅ ${_bashenv_dest}" >&2

  # Ensure BASH_ENV is set system-wide so non-interactive non-login bash
  # sessions (VS Code tasks, devcontainer exec, CI runners) source it.
  if ! grep -qxF "BASH_ENV=${_bashenv_dest}" /etc/environment 2>/dev/null; then
    # Remove any stale BASH_ENV line first, then append the correct one.
    sed -i '/^BASH_ENV=/d' /etc/environment 2>/dev/null || true
    echo "BASH_ENV=${_bashenv_dest}" >> /etc/environment
    echo "  ✅ BASH_ENV=${_bashenv_dest} → /etc/environment" >&2
  fi
fi

# --- Zsh system-wide files ---
if command -v zsh > /dev/null 2>&1; then
  _ZSH_ETC="$(shell::detect_zshdir)"
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
declare -A _USERS_MAP  # associative array for deduplication

if [[ "$ADD_CURRENT_USER_CONFIG" == true ]]; then
  _CURRENT_USER="${SUDO_USER:-$(whoami)}"
  if [ -n "$_CURRENT_USER" ] && [ "$_CURRENT_USER" != "root" ]; then
    _USERS_MAP["$_CURRENT_USER"]=1
  fi
fi

if [[ "$ADD_CONTAINER_USER_CONFIG" == true ]]; then
  if [ -n "${_CONTAINER_USER:-}" ]; then
    _USERS_MAP["$_CONTAINER_USER"]=1
  fi
fi

if [[ "$ADD_REMOTE_USER_CONFIG" == true ]]; then
  if [ -n "${_REMOTE_USER:-}" ]; then
    _USERS_MAP["$_REMOTE_USER"]=1
  fi
fi

if [ -n "$ADD_USER_CONFIG" ]; then
  IFS=',' read -r -a _EXTRA_USERS <<< "$ADD_USER_CONFIG"
  for _u in "${_EXTRA_USERS[@]}"; do
    _u="${_u// /}"
    [ -n "$_u" ] && _USERS_MAP["$_u"]=1
  done
fi

_RESOLVED_USERS=("${!_USERS_MAP[@]}")

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
    --starship_shells "$STARSHIP_SHELLS"
  )

  if [[ "$_OMZ_INSTALLED" == true ]]; then
    _CONFIGURE_ARGS+=(
      --ohmyzsh_install_dir "$OHMYZSH_INSTALL_DIR"
      --ohmyzsh_custom_dir "$OHMYZSH_CUSTOM_DIR"
      --ohmyzsh_theme "$OHMYZSH_THEME"
      --ohmyzsh_plugins "$OHMYZSH_PLUGINS"
    )
  fi

  if [[ "$_OMB_INSTALLED" == true ]]; then
    _CONFIGURE_ARGS+=(
      --ohmybash_install_dir "$OHMYBASH_INSTALL_DIR"
      --ohmybash_custom_dir "$OHMYBASH_CUSTOM_DIR"
      --ohmybash_theme "$OHMYBASH_THEME"
      --ohmybash_plugins "$OHMYBASH_PLUGINS"
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
      _TARGET_SHELL="$(command -v zsh 2>/dev/null || true)"
      if [ -z "$_TARGET_SHELL" ]; then
        echo "⛔ set_user_shells=zsh but zsh is not installed." >&2
        exit 1
      fi
      ;;
    bash)
      _TARGET_SHELL="$(command -v bash 2>/dev/null || true)"
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

  if ! command -v chsh > /dev/null 2>&1; then
    echo "⚠️  chsh not found — skipping shell change. Install the 'passwd' package." >&2
  else
    # Ensure the target shell is in /etc/shells.
    _SHELLS_FILE=/etc/shells
    [ -f /usr/share/defaults/etc/shells ] && _SHELLS_FILE=/usr/share/defaults/etc/shells
    if [ -f "$_SHELLS_FILE" ] && ! grep -qx "$_TARGET_SHELL" "$_SHELLS_FILE" 2>/dev/null; then
      echo "$_TARGET_SHELL" >> "$_SHELLS_FILE"
      echo "ℹ️  Added '${_TARGET_SHELL}' to '${_SHELLS_FILE}'." >&2
    fi

    # On Alpine, PAM may require a password for chsh even when run as root.
    if [ -f /etc/pam.d/chsh ]; then
      if ! grep -Eq '^auth[[:blank:]]+sufficient[[:blank:]]+pam_rootok\.so' /etc/pam.d/chsh 2>/dev/null; then
        if grep -Eq '^auth(.*)pam_rootok\.so' /etc/pam.d/chsh 2>/dev/null; then
          awk '/^auth(.*)pam_rootok\.so$/ { $2 = "sufficient" } { print }' \
            /etc/pam.d/chsh > /tmp/_chsh.tmp && mv /tmp/_chsh.tmp /etc/pam.d/chsh
        else
          printf 'auth sufficient pam_rootok.so\n' >> /etc/pam.d/chsh
        fi
        echo "ℹ️  Fixed pam_rootok.so in /etc/pam.d/chsh." >&2
      fi
    fi

    for _username in "${_RESOLVED_USERS[@]}"; do
      _current_shell="$(getent passwd "$_username" 2>/dev/null | cut -d: -f7 || true)"
      if [ "$_current_shell" = "$_TARGET_SHELL" ]; then
        echo "ℹ️  Shell for '${_username}' already set to '${_TARGET_SHELL}'." >&2
        continue
      fi
      if chsh -s "$_TARGET_SHELL" "$_username" 2>/dev/null; then
        echo "✅ Shell for '${_username}' set to '${_TARGET_SHELL}'." >&2
      else
        echo "⚠️  chsh failed for '${_username}'." >&2
      fi
    done
  fi
fi

ospkg::clean

echo "========================================" >&2
echo "  install-shell complete" >&2
echo "========================================" >&2
