#!/usr/bin/env bash
# configure_user.sh — Set up per-user shell configuration files.
#
# Copies skeleton files into the user's HOME directory and injects Oh My Zsh
# and/or Oh My Bash configuration blocks into ~/.zshrc / ~/.bashrc using
# guarded BEGIN/END markers.
#
# Called once per user by the main install-shell orchestrator.
set -euo pipefail

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------
# shellcheck source=helpers.sh
_SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$_SCRIPTS_DIR/helpers.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
__usage__() {
  cat >&2 <<'EOF'
Usage: configure_user.sh [OPTIONS]

Options:
  --username <string>             Target user (required)
  --skel_dir <string>             Path to skeleton files directory
  --user_config_mode <string>     overwrite | augment | skip (default: overwrite)
  --ohmyzsh_install_dir <string>  Oh My Zsh install dir (empty = not installed)
  --ohmyzsh_custom_dir <string>   ZSH_CUSTOM directory
  --ohmyzsh_theme <string>        Theme slug (owner/repo) or empty
  --ohmyzsh_plugins <string>      Comma-separated plugin slugs
  --ohmybash_install_dir <string> Oh My Bash install dir (empty = not installed)
  --ohmybash_custom_dir <string>  OSH_CUSTOM directory
  --ohmybash_theme <string>       Theme slug (owner/repo) or empty
  --ohmybash_plugins <string>     Comma-separated plugin slugs
  --debug                         Enable debug output (set -x)
  -h, --help                      Show this help
EOF
  exit 0
}

# ---------------------------------------------------------------------------
# inject_guarded_block <file> <marker> <content>
# Removes any existing block between "# BEGIN <marker>" and "# END <marker>",
# then appends a new block with the given content.
# ---------------------------------------------------------------------------
inject_guarded_block() {
  local _file="$1" _marker="$2" _content="$3"
  local _tmp
  _tmp="$(mktemp)"

  if [ -f "$_file" ]; then
    sed "/# BEGIN ${_marker}/,/# END ${_marker}/d" "$_file" > "$_tmp"
    mv "$_tmp" "$_file"
  fi

  {
    printf '# BEGIN %s\n' "$_marker"
    printf '%s\n' "$_content"
    printf '# END %s\n' "$_marker"
  } >> "$_file"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
USERNAME=""
SKEL_DIR=""
USER_CONFIG_MODE=""
OHMYZSH_INSTALL_DIR=""
OHMYZSH_CUSTOM_DIR=""
OHMYZSH_THEME=""
OHMYZSH_PLUGINS=""
OHMYBASH_INSTALL_DIR=""
OHMYBASH_CUSTOM_DIR=""
OHMYBASH_THEME=""
OHMYBASH_PLUGINS=""
DEBUG=""

if [ "$#" -gt 0 ]; then
  while [[ $# -gt 0 ]]; do
    case $1 in
      --username) shift; USERNAME="$1"; shift;;
      --skel_dir) shift; SKEL_DIR="$1"; shift;;
      --user_config_mode) shift; USER_CONFIG_MODE="$1"; shift;;
      --ohmyzsh_install_dir) shift; OHMYZSH_INSTALL_DIR="$1"; shift;;
      --ohmyzsh_custom_dir) shift; OHMYZSH_CUSTOM_DIR="$1"; shift;;
      --ohmyzsh_theme) shift; OHMYZSH_THEME="$1"; shift;;
      --ohmyzsh_plugins) shift; OHMYZSH_PLUGINS="$1"; shift;;
      --ohmybash_install_dir) shift; OHMYBASH_INSTALL_DIR="$1"; shift;;
      --ohmybash_custom_dir) shift; OHMYBASH_CUSTOM_DIR="$1"; shift;;
      --ohmybash_theme) shift; OHMYBASH_THEME="$1"; shift;;
      --ohmybash_plugins) shift; OHMYBASH_PLUGINS="$1"; shift;;
      --debug) DEBUG=true; shift;;
      --help|-h) __usage__;;
      --*) echo "⛔ Unknown option: '${1}'" >&2; exit 1;;
      *) echo "⛔ Unexpected argument: '${1}'" >&2; exit 1;;
    esac
  done
fi

[ -z "${USERNAME}" ]          && { echo "⛔ Missing --username" >&2; exit 1; }
[ -z "${SKEL_DIR-}" ]         && SKEL_DIR=""
[ -z "${USER_CONFIG_MODE-}" ] && USER_CONFIG_MODE="overwrite"
[ -z "${DEBUG-}" ]             && DEBUG=false

[[ "$DEBUG" == true ]] && set -x

# ---------------------------------------------------------------------------
# Resolve user's home directory and group
# ---------------------------------------------------------------------------
_HOME="$(resolve_home "$USERNAME")"
_GROUP="$(id -gn "$USERNAME" 2>/dev/null || echo "$USERNAME")"

if [ ! -d "$_HOME" ]; then
  echo "⚠️  Home directory '${_HOME}' does not exist for user '${USERNAME}' — creating." >&2
  mkdir -p "$_HOME"
  chown "${USERNAME}:${_GROUP}" "$_HOME"
fi

echo "ℹ️  Configuring user '${USERNAME}' (home: ${_HOME}, mode: ${USER_CONFIG_MODE})..." >&2

# ---------------------------------------------------------------------------
# Mode: skip — bail out if any dotfile already exists
# ---------------------------------------------------------------------------
if [[ "$USER_CONFIG_MODE" == "skip" ]]; then
  if [ -f "${_HOME}/.zshrc" ] || [ -f "${_HOME}/.bashrc" ]; then
    echo "ℹ️  User '${USERNAME}' already has dotfiles — skipping (mode=skip)." >&2
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Copy skeleton files
# ---------------------------------------------------------------------------
if [ -n "$SKEL_DIR" ] && [ -d "$SKEL_DIR" ]; then
  # Collect skel files (excluding p10k.zsh which is handled separately).
  while IFS= read -r -d '' _skel_file; do
    _rel="${_skel_file#${SKEL_DIR}/}"
    _dest="${_HOME}/${_rel}"

    # Skip p10k.zsh — it's copied only when p10k theme is selected.
    [[ "$_rel" == "p10k.zsh" ]] && continue

    case "$USER_CONFIG_MODE" in
      overwrite)
        mkdir -p "$(dirname "$_dest")"
        cp -f "$_skel_file" "$_dest"
        ;;
      augment)
        if [ ! -f "$_dest" ]; then
          mkdir -p "$(dirname "$_dest")"
          cp "$_skel_file" "$_dest"
        fi
        ;;
    esac
  done < <(find "$SKEL_DIR" -maxdepth 1 -type f -print0)
fi

# ---------------------------------------------------------------------------
# Oh My Zsh configuration block
# ---------------------------------------------------------------------------
if [ -n "$OHMYZSH_INSTALL_DIR" ] && [ -d "$OHMYZSH_INSTALL_DIR" ]; then
  _ZSHRC="${_HOME}/.zshrc"

  # Ensure the file exists (it should, from skel copy — but be safe).
  [ -f "$_ZSHRC" ] || touch "$_ZSHRC"

  # Resolve the ZSH_THEME value (e.g. "powerlevel10k/powerlevel10k").
  _OMZ_THEME_VALUE=""
  if [ -n "$OHMYZSH_THEME" ]; then
    _OMZ_THEME_VALUE="$(resolve_omz_theme_value \
      --theme_slug "$OHMYZSH_THEME" \
      --custom_dir "$OHMYZSH_CUSTOM_DIR")"
  fi

  # Build plugin names list from slugs.
  _OMZ_PLUGIN_NAMES=""
  if [ -n "$OHMYZSH_PLUGINS" ]; then
    _OMZ_PLUGIN_NAMES="$(plugin_names_from_slugs "$OHMYZSH_PLUGINS" | tr '\n' ' ')"
    _OMZ_PLUGIN_NAMES="${_OMZ_PLUGIN_NAMES% }"  # trim trailing space
  fi

  # Determine if we're using p10k.
  _IS_P10K=false
  [[ "$OHMYZSH_THEME" == *powerlevel10k* ]] && _IS_P10K=true

  # Build the OMZ block content.
  _OMZ_BLOCK=""
  _OMZ_BLOCK+="export ZSH=\"${OHMYZSH_INSTALL_DIR}\""$'\n'
  _OMZ_BLOCK+='ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-zsh"'$'\n'
  _OMZ_BLOCK+='[ -d "$ZSH_CACHE_DIR" ] || mkdir -p "$ZSH_CACHE_DIR"'$'\n'
  _OMZ_BLOCK+='ZSH_COMPDUMP="${ZSH_CACHE_DIR}/.zcompdump-${SHORT_HOST}-${ZSH_VERSION}"'$'\n'
  _OMZ_BLOCK+="ZSH_CUSTOM=\"\$HOME/.oh-my-zsh-custom\""$'\n'

  if [ -n "$_OMZ_THEME_VALUE" ]; then
    _OMZ_BLOCK+="ZSH_THEME=\"${_OMZ_THEME_VALUE}\""$'\n'
  else
    _OMZ_BLOCK+='ZSH_THEME=""'$'\n'
  fi

  if [ -n "$_OMZ_PLUGIN_NAMES" ]; then
    _OMZ_BLOCK+="plugins=(${_OMZ_PLUGIN_NAMES})"$'\n'
  else
    _OMZ_BLOCK+='plugins=()'$'\n'
  fi

  _OMZ_BLOCK+="zstyle ':omz:update' mode disabled"$'\n'

  if [[ "$_IS_P10K" == true ]]; then
    _OMZ_BLOCK+='POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true'$'\n'
  fi

  _OMZ_BLOCK+='[ -f "$ZSH/oh-my-zsh.sh" ] && source "$ZSH/oh-my-zsh.sh"'$'\n'

  if [[ "$_IS_P10K" == true ]]; then
    _OMZ_BLOCK+='[[ ! -f "${HOME}/.p10k.zsh" ]] || source "${HOME}/.p10k.zsh"'
  fi

  inject_guarded_block "$_ZSHRC" "install-shell-ohmyzsh" "$_OMZ_BLOCK"

  # Create per-user custom directory.
  _USER_ZSH_CUSTOM="${_HOME}/.oh-my-zsh-custom"
  mkdir -p "${_USER_ZSH_CUSTOM}/themes" "${_USER_ZSH_CUSTOM}/plugins"

  # Copy p10k config if p10k theme is selected.
  if [[ "$_IS_P10K" == true ]] && [ -n "$SKEL_DIR" ] && [ -f "${SKEL_DIR}/p10k.zsh" ]; then
    case "$USER_CONFIG_MODE" in
      overwrite)
        cp -f "${SKEL_DIR}/p10k.zsh" "${_HOME}/.p10k.zsh"
        ;;
      augment)
        [ ! -f "${_HOME}/.p10k.zsh" ] && cp "${SKEL_DIR}/p10k.zsh" "${_HOME}/.p10k.zsh"
        ;;
    esac
  fi

  echo "ℹ️  Injected Oh My Zsh config into '${_ZSHRC}'." >&2
fi

# ---------------------------------------------------------------------------
# Oh My Bash configuration block
# ---------------------------------------------------------------------------
if [ -n "$OHMYBASH_INSTALL_DIR" ] && [ -d "$OHMYBASH_INSTALL_DIR" ]; then
  _BASHRC="${_HOME}/.bashrc"

  # Ensure the file exists.
  [ -f "$_BASHRC" ] || touch "$_BASHRC"

  # Resolve the OSH_THEME value.
  _OMB_THEME_VALUE=""
  if [ -n "$OHMYBASH_THEME" ]; then
    _OMB_THEME_VALUE="$(basename "$OHMYBASH_THEME")"
  fi

  # Build plugin names list from slugs.
  _OMB_PLUGIN_NAMES=""
  if [ -n "$OHMYBASH_PLUGINS" ]; then
    _OMB_PLUGIN_NAMES="$(plugin_names_from_slugs "$OHMYBASH_PLUGINS" | tr '\n' ' ')"
    _OMB_PLUGIN_NAMES="${_OMB_PLUGIN_NAMES% }"
  fi

  # Build the OMB block content.
  _OMB_BLOCK=""
  _OMB_BLOCK+="export OSH=\"${OHMYBASH_INSTALL_DIR}\""$'\n'
  _OMB_BLOCK+='OSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-bash"'$'\n'
  _OMB_BLOCK+='[ -d "$OSH_CACHE_DIR" ] || mkdir -p "$OSH_CACHE_DIR"'$'\n'
  _OMB_BLOCK+="OSH_CUSTOM=\"\$HOME/.oh-my-bash-custom\""$'\n'

  if [ -n "$_OMB_THEME_VALUE" ]; then
    _OMB_BLOCK+="OSH_THEME=\"${_OMB_THEME_VALUE}\""$'\n'
  else
    _OMB_BLOCK+='OSH_THEME=""'$'\n'
  fi

  if [ -n "$_OMB_PLUGIN_NAMES" ]; then
    _OMB_BLOCK+="plugins=(${_OMB_PLUGIN_NAMES})"$'\n'
  else
    _OMB_BLOCK+='plugins=()'$'\n'
  fi

  _OMB_BLOCK+='[ -f "$OSH/oh-my-bash.sh" ] && source "$OSH/oh-my-bash.sh"'

  inject_guarded_block "$_BASHRC" "install-shell-ohmybash" "$_OMB_BLOCK"

  # Create per-user custom directory.
  _USER_OSH_CUSTOM="${_HOME}/.oh-my-bash-custom"
  mkdir -p "${_USER_OSH_CUSTOM}/themes" "${_USER_OSH_CUSTOM}/plugins"

  echo "ℹ️  Injected Oh My Bash config into '${_BASHRC}'." >&2
fi

# ---------------------------------------------------------------------------
# Fix ownership — everything we touched belongs to the user
# ---------------------------------------------------------------------------
_FILES_TO_OWN=()
for _f in .shellenv .shellrc .bash_profile .bashrc .zshenv .zprofile .zshrc .zlogin .p10k.zsh; do
  [ -f "${_HOME}/${_f}" ] && _FILES_TO_OWN+=("${_HOME}/${_f}")
done
for _d in .oh-my-zsh-custom .oh-my-bash-custom; do
  [ -d "${_HOME}/${_d}" ] && _FILES_TO_OWN+=("${_HOME}/${_d}")
done

if [ ${#_FILES_TO_OWN[@]} -gt 0 ]; then
  chown -R "${USERNAME}:${_GROUP}" "${_FILES_TO_OWN[@]}"
fi

echo "✅ User '${USERNAME}' configuration complete." >&2
