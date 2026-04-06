#!/usr/bin/env bash
set -euo pipefail
__usage__() {
  echo "Usage:" >&2
  echo "  --branch (string): " >&2
  echo "  --configure_zshrc_for (string): " >&2
  echo "  --debug (boolean): " >&2
  echo "  --font_dir (string): " >&2
  echo "  --install_dir (string): This is the directory where Oh My Zsh will be installed." >&2
  echo "  --install_fonts (boolean): " >&2
  echo "  --logfile (string): " >&2
  echo "  --plugins (string): " >&2
  echo "  --set_default_shell_for (string): " >&2
  echo "  --theme (string): " >&2
  echo "  --zsh_custom_dir (string): This corresponds to the ZSH_CUSTOM configuration variable in Oh My Zsh." >&2
  exit 0
}

__cleanup__() {
  echo "↪️ Function entry: __cleanup__" >&2
  if [ -n "${LOGFILE-}" ]; then
    exec 1>&3 2>&4
    wait 2>/dev/null
    echo "ℹ️ Write logs to file '$LOGFILE'" >&2
    mkdir -p "$(dirname "$LOGFILE")"
    cat "$_LOGFILE_TMP" >> "$LOGFILE"
    rm -f "$_LOGFILE_TMP"
  fi
  echo "↩️ Function exit: __cleanup__" >&2
}

exit_if_not_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "⛔ This script must be run as root. Use sudo, su, or add \"USER root\" to your Dockerfile." >&2
    exit 1
  fi
}

# git_clone --url <url> --dir <dir> [--branch <branch>]
# Clones <url> into <dir> with depth=1.  If <dir>/.git already exists the
# clone is skipped (idempotent).  On failure the partially-created <dir> is
# removed so a re-run does not silently skip a broken clone.
git_clone() {
  echo "↪️ Function entry: git_clone" >&2
  local branch=""
  local dir=""
  local url=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --branch) shift; branch="$1"; echo "📩 Read argument 'branch': '${branch}'" >&2; shift;;
      --dir) shift; dir="$1"; echo "📩 Read argument 'dir': '${dir}'" >&2; shift;;
      --url) shift; url="$1"; echo "📩 Read argument 'url': '${url}'" >&2; shift;;
      --*) echo "⛔ Unknown option: '${1}'" >&2; exit 1;;
      *) echo "⛔ Unexpected argument: '${1}'" >&2; exit 1;;
    esac
  done
  [ -z "${dir-}" ] && { echo "⛔ Missing required argument 'dir'." >&2; exit 1; }
  [ -z "${url-}" ] && { echo "⛔ Missing required argument 'url'." >&2; exit 1; }
  if [ -d "${dir}/.git" ]; then
    echo "ℹ️  '${dir}' already exists — skipping clone." >&2
    echo "↩️ Function exit: git_clone" >&2
    return 0
  fi
  mkdir -p "$dir"
  local _clone_args=(--depth=1
    -c core.eol=lf
    -c core.autocrlf=false
    -c fsck.zeroPaddedFilemode=ignore
    -c fetch.fsck.zeroPaddedFilemode=ignore
    -c receive.fsck.zeroPaddedFilemode=ignore)
  [ -n "${branch-}" ] && _clone_args+=(--branch "$branch")
  if ! git clone "${_clone_args[@]}" "$url" "$dir" 2>&1; then
    rm -rf "$dir" 2>/dev/null || true
    echo "⛔ git clone of '${url}' failed." >&2
    exit 1
  fi
  echo "↩️ Function exit: git_clone" >&2
}

# _fetch_with_retry <max-attempts> <cmd...>
# Runs <cmd> up to <max-attempts> times with a 3-second pause between failures.
_fetch_with_retry() {
  local _max="$1"; shift
  local _i=1
  while [[ $_i -le $_max ]]; do
    "$@" && return 0
    [[ $_i -lt $_max ]] && echo "⚠️  Fetch attempt $_i/$_max failed — retrying in 3s..." >&2 && sleep 3
    (( _i++ ))
  done
  echo "⛔ Fetch failed after $_max attempt(s)." >&2
  return 1
}

_LOGFILE_TMP="$(mktemp)"
exec 3>&1 4>&2
exec > >(tee -a "$_LOGFILE_TMP" >&3) 2>&1
echo "↪️ Script entry: Oh My Zsh Installation Devcontainer Feature Installer" >&2
trap __cleanup__ EXIT
if [ "$#" -gt 0 ]; then
  echo "ℹ️ Script called with arguments: $@" >&2
  BRANCH=""
  CONFIGURE_ZSHRC_FOR=""
  DEBUG=""
  FONT_DIR=""
  INSTALL_DIR=""
  INSTALL_FONTS=""
  LOGFILE=""
  PLUGINS=""
  SET_DEFAULT_SHELL_FOR=""
  THEME=""
  ZSH_CUSTOM_DIR=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --branch) shift; BRANCH="$1"; echo "📩 Read argument 'branch': '${BRANCH}'" >&2; shift;;
      --configure_zshrc_for) shift; CONFIGURE_ZSHRC_FOR="$1"; echo "📩 Read argument 'configure_zshrc_for': '${CONFIGURE_ZSHRC_FOR}'" >&2; shift;;
      --debug) shift; DEBUG=true; echo "📩 Read argument 'debug': '${DEBUG}'" >&2;;
      --font_dir) shift; FONT_DIR="$1"; echo "📩 Read argument 'font_dir': '${FONT_DIR}'" >&2; shift;;
      --install_dir) shift; INSTALL_DIR="$1"; echo "📩 Read argument 'install_dir': '${INSTALL_DIR}'" >&2; shift;;
      --install_fonts|--no_install_fonts) [[ "$1" == --no_* ]] && INSTALL_FONTS=false || INSTALL_FONTS=true; echo "📩 Read argument 'install_fonts': '${INSTALL_FONTS}'" >&2; shift;;
      --logfile) shift; LOGFILE="$1"; echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2; shift;;
      --plugins) shift; PLUGINS="$1"; echo "📩 Read argument 'plugins': '${PLUGINS}'" >&2; shift;;
      --set_default_shell_for) shift; SET_DEFAULT_SHELL_FOR="$1"; echo "📩 Read argument 'set_default_shell_for': '${SET_DEFAULT_SHELL_FOR}'" >&2; shift;;
      --theme) shift; THEME="$1"; echo "📩 Read argument 'theme': '${THEME}'" >&2; shift;;
      --zsh_custom_dir) shift; ZSH_CUSTOM_DIR="$1"; echo "📩 Read argument 'zsh_custom_dir': '${ZSH_CUSTOM_DIR}'" >&2; shift;;
      --help|-h) __usage__;;
      --*) echo "⛔ Unknown option: '${1}'" >&2; exit 1;;
      *) echo "⛔ Unexpected argument: '${1}'" >&2; exit 1;;
    esac
  done
else
  echo "ℹ️ Script called with no arguments. Read environment variables." >&2
  [ "${BRANCH+defined}" ] && echo "📩 Read argument 'branch': '${BRANCH}'" >&2
  [ "${CONFIGURE_ZSHRC_FOR+defined}" ] && echo "📩 Read argument 'configure_zshrc_for': '${CONFIGURE_ZSHRC_FOR}'" >&2
  [ "${DEBUG+defined}" ] && echo "📩 Read argument 'debug': '${DEBUG}'" >&2
  [ "${FONT_DIR+defined}" ] && echo "📩 Read argument 'font_dir': '${FONT_DIR}'" >&2
  [ "${INSTALL_DIR+defined}" ] && echo "📩 Read argument 'install_dir': '${INSTALL_DIR}'" >&2
  [ "${INSTALL_FONTS+defined}" ] && echo "📩 Read argument 'install_fonts': '${INSTALL_FONTS}'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
  [ "${PLUGINS+defined}" ] && echo "📩 Read argument 'plugins': '${PLUGINS}'" >&2
  [ "${SET_DEFAULT_SHELL_FOR+defined}" ] && echo "📩 Read argument 'set_default_shell_for': '${SET_DEFAULT_SHELL_FOR}'" >&2
  [ "${THEME+defined}" ] && echo "📩 Read argument 'theme': '${THEME}'" >&2
  [ "${ZSH_CUSTOM_DIR+defined}" ] && echo "📩 Read argument 'zsh_custom_dir': '${ZSH_CUSTOM_DIR}'" >&2
fi
[[ "$DEBUG" == true ]] && set -x
[ -z "${BRANCH-}" ] && { echo "ℹ️ Argument 'BRANCH' set to default value 'master'." >&2; BRANCH="master"; }
[ -z "${CONFIGURE_ZSHRC_FOR-}" ] && { echo "ℹ️ Argument 'CONFIGURE_ZSHRC_FOR' set to default value ''." >&2; CONFIGURE_ZSHRC_FOR=""; }
[ -z "${DEBUG-}" ] && { echo "ℹ️ Argument 'DEBUG' set to default value 'false'." >&2; DEBUG=false; }
[ -z "${FONT_DIR-}" ] && { echo "ℹ️ Argument 'FONT_DIR' set to default value '/usr/share/fonts/MesloLGS'." >&2; FONT_DIR="/usr/share/fonts/MesloLGS"; }
[ -z "${INSTALL_DIR-}" ] && { echo "ℹ️ Argument 'INSTALL_DIR' set to default value '/usr/local/share/oh-my-zsh'." >&2; INSTALL_DIR="/usr/local/share/oh-my-zsh"; }
[ -z "${INSTALL_FONTS-}" ] && { echo "ℹ️ Argument 'INSTALL_FONTS' set to default value 'true'." >&2; INSTALL_FONTS=true; }
[ -z "${LOGFILE-}" ] && { echo "ℹ️ Argument 'LOGFILE' set to default value ''." >&2; LOGFILE=""; }
[ -z "${PLUGINS-}" ] && { echo "ℹ️ Argument 'PLUGINS' set to default value 'zsh-users/zsh-syntax-highlighting'." >&2; PLUGINS="zsh-users/zsh-syntax-highlighting"; }
[ -z "${SET_DEFAULT_SHELL_FOR-}" ] && { echo "ℹ️ Argument 'SET_DEFAULT_SHELL_FOR' set to default value ''." >&2; SET_DEFAULT_SHELL_FOR=""; }
[ -z "${THEME-}" ] && { echo "ℹ️ Argument 'THEME' set to default value 'romkatv/powerlevel10k'." >&2; THEME="romkatv/powerlevel10k"; }
[ -z "${ZSH_CUSTOM_DIR-}" ] && { ZSH_CUSTOM_DIR="${INSTALL_DIR}/custom"; echo "ℹ️ Argument 'ZSH_CUSTOM_DIR' set to default value '${ZSH_CUSTOM_DIR}'." >&2; }
exit_if_not_root
# Install runtime dependencies (git, curl, zsh, fontconfig) via install-os-pkg.
_PACKAGES_MANIFEST="$(dirname "$0")/packages.txt"
install-os-pkg --manifest "$_PACKAGES_MANIFEST" --check_installed
umask g-w,o-w
git_clone --url "https://github.com/ohmyzsh/ohmyzsh" --dir "$INSTALL_DIR" --branch "$BRANCH"
# Set oh-my-zsh update metadata so 'omz update' knows which remote and branch to use.
git -C "$INSTALL_DIR" config oh-my-zsh.remote origin
git -C "$INSTALL_DIR" config oh-my-zsh.branch "$BRANCH"
# Ensure ZSH_CUSTOM scaffold directories exist regardless of theme/plugin selections.
mkdir -p "${ZSH_CUSTOM_DIR}/themes" "${ZSH_CUSTOM_DIR}/plugins"
# --- Theme ---
if [ -n "${THEME-}" ]; then
  _THEME_REPO_NAME="$(basename "$THEME")"
  git_clone \
    --url "https://github.com/${THEME}" \
    --dir "${ZSH_CUSTOM_DIR}/themes/${_THEME_REPO_NAME}"
fi
# --- Plugins ---
if [ -n "${PLUGINS-}" ]; then
  IFS=',' read -r -a _PLUGIN_SLUGS <<< "$PLUGINS"
  for _slug in "${_PLUGIN_SLUGS[@]}"; do
    _slug="${_slug// /}"
    [ -z "$_slug" ] && continue
    _PLUGIN_NAME="$(basename "$_slug")"
    git_clone \
      --url "https://github.com/${_slug}" \
      --dir "${ZSH_CUSTOM_DIR}/plugins/${_PLUGIN_NAME}"
  done
fi
# --- Fonts ---
if [[ "$INSTALL_FONTS" == true ]]; then
  mkdir -p "$FONT_DIR"
  _BASE_URL="https://github.com/romkatv/powerlevel10k-media/raw/master"
  _FONT_FILES=(
    "MesloLGS%20NF%20Regular.ttf"
    "MesloLGS%20NF%20Bold.ttf"
    "MesloLGS%20NF%20Italic.ttf"
    "MesloLGS%20NF%20Bold%20Italic.ttf"
  )
  echo "Installing MesloLGS Nerd Fonts to ${FONT_DIR}..."
  for _FONT in "${_FONT_FILES[@]}"; do
    _LOCAL_NAME="$(printf '%b' "${_FONT//%/\\x}")"
    echo "Downloading ${_LOCAL_NAME}..."
    _fetch_with_retry 3 curl -fsSL "${_BASE_URL}/${_FONT}" -o "${FONT_DIR}/${_LOCAL_NAME}"
  done
  chmod 755 "$FONT_DIR"
  chmod 644 "$FONT_DIR"/*.ttf
  fc-cache -f "$FONT_DIR"
  echo "Fonts installed."
fi
# --- Configure ~/.zshrc ---
if [ -n "${CONFIGURE_ZSHRC_FOR-}" ]; then
  # Determine the ZSH_THEME value: custom themes are cloned into a subdir, so
  # oh-my-zsh needs "dirname/theme-file" (without .zsh-theme extension).
  _THEME_ZSH_VALUE=""
  if [ -n "${THEME-}" ]; then
    _THEME_REPO_NAME_FOR_ZSHRC="$(basename "$THEME")"
    _THEME_DIR="${ZSH_CUSTOM_DIR}/themes/${_THEME_REPO_NAME_FOR_ZSHRC}"
    _THEME_FILE="$(find "$_THEME_DIR" -maxdepth 1 -name '*.zsh-theme' 2>/dev/null | head -1)"
    if [ -n "$_THEME_FILE" ]; then
      _THEME_FILE_STEM="$(basename "${_THEME_FILE%.zsh-theme}")"
      _THEME_ZSH_VALUE="${_THEME_REPO_NAME_FOR_ZSHRC}/${_THEME_FILE_STEM}"
    else
      _THEME_ZSH_VALUE="$_THEME_REPO_NAME_FOR_ZSHRC"
    fi
  fi
  _PLUGIN_NAMES=()
  if [ -n "${PLUGINS-}" ]; then
    IFS=',' read -r -a _PS <<< "$PLUGINS"
    for _p in "${_PS[@]}"; do
      _p="${_p// /}"
      [ -n "$_p" ] && _PLUGIN_NAMES+=("$(basename "$_p")")
    done
  fi
  IFS=',' read -r -a _ZSHRC_USERS <<< "$CONFIGURE_ZSHRC_FOR"
  for _username in "${_ZSHRC_USERS[@]}"; do
    _username="${_username// /}"
    [ -z "$_username" ] && continue
    if [ "$_username" = "root" ]; then
      _home="/root"
    else
      _home="$(getent passwd "$_username" 2>/dev/null | cut -d: -f6)"
    fi
    if [ -z "${_home-}" ] || [ ! -d "$_home" ]; then
      echo "⚠️  Home directory not found for user '${_username}' — skipping .zshrc configuration." >&2
      continue
    fi
    _zshrc="${_home}/.zshrc"
    touch "$_zshrc"
    # Remove any existing guarded block
    _ZSHRC_TMP="$(mktemp)"
    sed '/# BEGIN install-ohmyzsh/,/# END install-ohmyzsh/d' "$_zshrc" > "$_ZSHRC_TMP"
    mv "$_ZSHRC_TMP" "$_zshrc"
    # Append new guarded block
    {
      printf '\n# BEGIN install-ohmyzsh\n'
      printf 'export ZSH="%s"\n' "$INSTALL_DIR"
      printf 'export ZSH_CUSTOM="%s"\n' "$ZSH_CUSTOM_DIR"
      [ -n "$_THEME_ZSH_VALUE" ] && printf 'ZSH_THEME="%s"\n' "$_THEME_ZSH_VALUE"
      [ ${#_PLUGIN_NAMES[@]} -gt 0 ] && printf 'plugins=(%s)\n' "${_PLUGIN_NAMES[*]}"
      printf '%s\n' '[ -f "$ZSH/oh-my-zsh.sh" ] && source "$ZSH/oh-my-zsh.sh"'
      printf '%s\n' "zstyle ':omz:update' mode disabled"
      # Source per-user p10k config if present (e.g. powerlevel10k configuration).
      printf '%s\n' '[[ ! -f "${HOME}/.p10k.zsh" ]] || source "${HOME}/.p10k.zsh"'
      printf '# END install-ohmyzsh\n'
    } >> "$_zshrc"
    [ "$_username" != "root" ] && chown "$_username" "$_zshrc" 2>/dev/null || true
    echo "ℹ️  Configured oh-my-zsh block in '${_zshrc}'." >&2
    # Create ~/.zprofile that sources ~/.profile so zsh login shells inherit
    # the same PATH and environment set up by ~/.profile (nvm, pyenv, etc.).
    _zprofile="${_home}/.zprofile"
    if [ ! -f "$_zprofile" ] || ! grep -qF 'source $HOME/.profile' "$_zprofile"; then
      printf '\n# Source ~/.profile so zsh login shells inherit PATH set up there.\n' >> "$_zprofile"
      printf '%s\n' '[ -f "$HOME/.profile" ] && source "$HOME/.profile"' >> "$_zprofile"
      [ "$_username" != "root" ] && chown "$_username" "$_zprofile" 2>/dev/null || true
      echo "ℹ️  Configured '${_zprofile}' to source ~/.profile." >&2
    fi
  done
fi
# --- Set default shell ---
if [ -n "${SET_DEFAULT_SHELL_FOR-}" ]; then
  if ! command -v chsh > /dev/null 2>&1; then
    echo "⚠️  chsh not found — skipping default shell configuration. Install the 'passwd' package to enable this feature." >&2
  else
    _ZSH_PATH="$(command -v zsh 2>/dev/null || true)"
    if [ -z "$_ZSH_PATH" ]; then
      echo "⚠️  zsh not found in PATH — skipping default shell configuration." >&2
    else
      # chsh requires the shell to be listed in /etc/shells; add it if missing.
      _SHELLS_FILE=/etc/shells
      [ -f /usr/share/defaults/etc/shells ] && _SHELLS_FILE=/usr/share/defaults/etc/shells
      if [ -f "$_SHELLS_FILE" ] && ! grep -qx "$_ZSH_PATH" "$_SHELLS_FILE"; then
        echo "$_ZSH_PATH" >> "$_SHELLS_FILE"
        echo "ℹ️  Added '${_ZSH_PATH}' to '${_SHELLS_FILE}'." >&2
      fi
      # On Alpine, PAM may require a password for chsh even when run as root.
      # Ensure pam_rootok.so is marked 'sufficient' in /etc/pam.d/chsh.
      if [ -f /etc/pam.d/chsh ]; then
        if ! grep -Eq '^auth[[:blank:]]+sufficient[[:blank:]]+pam_rootok\.so' /etc/pam.d/chsh; then
          if grep -Eq '^auth(.*)pam_rootok\.so' /etc/pam.d/chsh; then
            awk '/^auth(.*)pam_rootok\.so$/ { $2 = "sufficient" } { print }' /etc/pam.d/chsh > /tmp/_chsh.tmp && mv /tmp/_chsh.tmp /etc/pam.d/chsh
            echo "ℹ️  Updated /etc/pam.d/chsh: pam_rootok.so set to sufficient." >&2
          else
            printf 'auth sufficient pam_rootok.so\n' >> /etc/pam.d/chsh
            echo "ℹ️  Added 'auth sufficient pam_rootok.so' to /etc/pam.d/chsh." >&2
          fi
        fi
      fi
      IFS=',' read -r -a _CHSH_USERS <<< "$SET_DEFAULT_SHELL_FOR"
      for _username in "${_CHSH_USERS[@]}"; do
        _username="${_username// /}"
        [ -z "$_username" ] && continue
        _current_shell="$(getent passwd "$_username" 2>/dev/null | cut -d: -f7 || true)"
        if [ "$_current_shell" = "$_ZSH_PATH" ]; then
          echo "ℹ️  Default shell for '${_username}' is already '${_ZSH_PATH}' — skipping." >&2
          continue
        fi
        if ! chsh -s "$_ZSH_PATH" "$_username" 2>/dev/null; then
          echo "⚠️  chsh failed for '${_username}' — skipping." >&2
          continue
        fi
        echo "ℹ️  Default shell for '${_username}' set to '${_ZSH_PATH}'." >&2
      done
    fi
  fi
fi
echo "↩️ Script exit: Oh My Zsh Installation Devcontainer Feature Installer" >&2
