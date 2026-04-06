#!/usr/bin/env bash
set -euo pipefail
__usage__() {
  echo "Usage:" >&2
  echo "  --debug (boolean): " >&2
  echo "  --font_dir (string): " >&2
  echo "  --install_dir (string): This is the directory where Oh My Zsh will be installed.
  It corresponds to the [`ZSH`](https://github.com/ohmyzsh/ohmyzsh/wiki/Settings#zsh_custom)
  configuration variable in Oh My Zsh.
  " >&2
  echo "  --logfile (string): " >&2
  echo "  --zsh_custom_dir (string): This corresponds to the [`ZSH_CUSTOM`](https://github.com/ohmyzsh/ohmyzsh/wiki/Settings#zsh_custom)
  configuration variable in Oh My Zsh.
  " >&2
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

git_clone() {
  echo "↪️ Function entry: git_clone" >&2
  local dir=""
  local url=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --dir) shift; dir="$1"; echo "📩 Read argument 'dir': '${dir}'" >&2; shift;;
      --url) shift; url="$1"; echo "📩 Read argument 'url': '${url}'" >&2; shift;;
      --*) echo "⛔ Unknown option: '${1}'" >&2; exit 1;;
      *) echo "⛔ Unexpected argument: '${1}'" >&2; exit 1;;
    esac
  done
  [ -z "${dir-}" ] && { echo "⛔ Missing required argument 'dir'." >&2; exit 1; }
  [ -n "${dir-}" ] && [ -d "${dir}" ] && { echo "⛔ Directory argument to parameter 'dir' already exists: '${dir}'" >&2; exit 1; }
  [ -z "${url-}" ] && { echo "⛔ Missing required argument 'url'." >&2; exit 1; }
  mkdir -p "$dir"
  git clone --depth=1 \
      -c core.eol=lf \
      -c core.autocrlf=false \
      -c fsck.zeroPaddedFilemode=ignore \
      -c fetch.fsck.zeroPaddedFilemode=ignore \
      -c receive.fsck.zeroPaddedFilemode=ignore \
      "$url" \
      "$dir" 2>&1
  (cd "$dir" && git repack -a -d -f --depth=1 --window=1)
  echo "↩️ Function exit: git_clone" >&2
}

_LOGFILE_TMP="$(mktemp)"
exec 3>&1 4>&2
exec > >(tee -a "$_LOGFILE_TMP" >&3) 2>&1
echo "↪️ Script entry: Oh My Zsh Installation Devcontainer Feature Installer" >&2
trap __cleanup__ EXIT
if [ "$#" -gt 0 ]; then
  echo "ℹ️ Script called with arguments: $@" >&2
  DEBUG=""
  FONT_DIR=""
  INSTALL_DIR=""
  LOGFILE=""
  ZSH_CUSTOM_DIR=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --debug) shift; DEBUG=true; echo "📩 Read argument 'debug': '${DEBUG}'" >&2;;
      --font_dir) shift; FONT_DIR="$1"; echo "📩 Read argument 'font_dir': '${FONT_DIR}'" >&2; shift;;
      --install_dir) shift; INSTALL_DIR="$1"; echo "📩 Read argument 'install_dir': '${INSTALL_DIR}'" >&2; shift;;
      --logfile) shift; LOGFILE="$1"; echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2; shift;;
      --zsh_custom_dir) shift; ZSH_CUSTOM_DIR="$1"; echo "📩 Read argument 'zsh_custom_dir': '${ZSH_CUSTOM_DIR}'" >&2; shift;;
      --help|-h) __usage__;;
      --*) echo "⛔ Unknown option: '${1}'" >&2; exit 1;;
      *) echo "⛔ Unexpected argument: '${1}'" >&2; exit 1;;
    esac
  done
else
  echo "ℹ️ Script called with no arguments. Read environment variables." >&2
  [ "${DEBUG+defined}" ] && echo "📩 Read argument 'debug': '${DEBUG}'" >&2
  [ "${FONT_DIR+defined}" ] && echo "📩 Read argument 'font_dir': '${FONT_DIR}'" >&2
  [ "${INSTALL_DIR+defined}" ] && echo "📩 Read argument 'install_dir': '${INSTALL_DIR}'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
  [ "${ZSH_CUSTOM_DIR+defined}" ] && echo "📩 Read argument 'zsh_custom_dir': '${ZSH_CUSTOM_DIR}'" >&2
fi
[[ "$DEBUG" == true ]] && set -x
[ -z "${DEBUG-}" ] && { echo "ℹ️ Argument 'DEBUG' set to default value 'false'." >&2; DEBUG=false; }
[ -z "${FONT_DIR-}" ] && { echo "ℹ️ Argument 'FONT_DIR' set to default value '/usr/share/fonts/MesloLGS'." >&2; FONT_DIR="/usr/share/fonts/MesloLGS"; }
[ -z "${INSTALL_DIR-}" ] && { echo "ℹ️ Argument 'INSTALL_DIR' set to default value '/usr/local/share/oh-my-zsh'." >&2; INSTALL_DIR="/usr/local/share/oh-my-zsh"; }
[ -z "${LOGFILE-}" ] && { echo "ℹ️ Argument 'LOGFILE' set to default value ''." >&2; LOGFILE=""; }
[ -z "${ZSH_CUSTOM_DIR-}" ] && { echo "ℹ️ Argument 'ZSH_CUSTOM_DIR' set to default value '/usr/local/share/oh-my-zsh/custom'." >&2; ZSH_CUSTOM_DIR="/usr/local/share/oh-my-zsh/custom"; }
# Install runtime dependencies (git, curl, zsh) via install-os-pkg.
_PACKAGES_MANIFEST="$(dirname "$0")/packages.txt"
install-os-pkg --manifest "$_PACKAGES_MANIFEST" --check_installed
umask g-w,o-w
git_clone --url "https://github.com/ohmyzsh/ohmyzsh" --dir "$INSTALL_DIR"
mkdir -p "$FONT_DIR"
BASE_URL="https://github.com/romkatv/powerlevel10k-media/raw/master"
FONT_FILES="
MesloLGS%20NF%20Regular.ttf
MesloLGS%20NF%20Bold.ttf
MesloLGS%20NF%20Italic.ttf
MesloLGS%20NF%20Bold%20Italic.ttf
"
echo "Installing MesloLGS Nerd Fonts to $FONT_DIR..."
for FONT in $FONT_FILES; do
  LOCAL_NAME=$(printf '%b' "${FONT//%/\\x}")
  echo "Downloading $LOCAL_NAME..."
  curl -fsSL "$BASE_URL/$FONT" -o "$FONT_DIR/$LOCAL_NAME"
done
chmod 644 "$FONT_DIR"/*.ttf
echo "Fonts installed."
git_clone \
  --url "https://github.com/romkatv/powerlevel10k" \
  --dir "$ZSH_CUSTOM_DIR/themes/powerlevel10k"
git_clone \
  --url "https://github.com/zsh-users/zsh-syntax-highlighting" \
  --dir "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting"
echo "↩️ Script exit: Oh My Zsh Installation Devcontainer Feature Installer" >&2
