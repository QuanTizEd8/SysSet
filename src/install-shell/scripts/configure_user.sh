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
_SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$_SCRIPTS_DIR/_lib/shell.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
__usage__() {
  cat >&2 << 'EOF'
Usage: configure_user.sh [OPTIONS]

Options:
  --username <string>             Target user (required)
  --skel_dir <string>             Path to skeleton files directory
  --user_config_mode <string>     overwrite | augment | skip (default: overwrite)
  --zdotdir <string>              Zsh config directory (ZDOTDIR; default: ~/.config/zsh)
  --starship_shells <string>      Comma-separated shells to activate starship in (default: zsh,bash)
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
# resolve_custom_dir <raw_value> <user_home>
# Expands ~- and $HOME-prefixed paths to absolute paths for the given user.
# Absolute paths and other values are passed through unchanged.
# ---------------------------------------------------------------------------
resolve_custom_dir() {
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
# Argument parsing
# ---------------------------------------------------------------------------
USERNAME=""
SKEL_DIR=""
USER_CONFIG_MODE=""
ZDOTDIR=""
STARSHIP_SHELLS=""
STARSHIP_BIN_DIR=""
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
      --username)
        shift
        USERNAME="$1"
        shift
        ;;
      --skel_dir)
        shift
        SKEL_DIR="$1"
        shift
        ;;
      --user_config_mode)
        shift
        USER_CONFIG_MODE="$1"
        shift
        ;;
      --zdotdir)
        shift
        ZDOTDIR="$1"
        shift
        ;;
      --starship_shells)
        shift
        STARSHIP_SHELLS="$1"
        shift
        ;;
      --starship_bin_dir)
        shift
        STARSHIP_BIN_DIR="$1"
        shift
        ;;
      --ohmyzsh_install_dir)
        shift
        OHMYZSH_INSTALL_DIR="$1"
        shift
        ;;
      --ohmyzsh_custom_dir)
        shift
        OHMYZSH_CUSTOM_DIR="$1"
        shift
        ;;
      --ohmyzsh_theme)
        shift
        OHMYZSH_THEME="$1"
        shift
        ;;
      --ohmyzsh_plugins)
        shift
        OHMYZSH_PLUGINS="$1"
        shift
        ;;
      --ohmybash_install_dir)
        shift
        OHMYBASH_INSTALL_DIR="$1"
        shift
        ;;
      --ohmybash_custom_dir)
        shift
        OHMYBASH_CUSTOM_DIR="$1"
        shift
        ;;
      --ohmybash_theme)
        shift
        OHMYBASH_THEME="$1"
        shift
        ;;
      --ohmybash_plugins)
        shift
        OHMYBASH_PLUGINS="$1"
        shift
        ;;
      --debug)
        DEBUG=true
        shift
        ;;
      --help | -h) __usage__ ;;
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
fi

[ -z "${USERNAME}" ] && {
  echo "⛔ Missing --username" >&2
  exit 1
}
: "${SKEL_DIR:=}"
: "${USER_CONFIG_MODE:=overwrite}"
: "${STARSHIP_SHELLS=zsh,bash}"
: "${STARSHIP_BIN_DIR=/usr/local/bin}"
: "${DEBUG:=false}"

[[ "$DEBUG" == true ]] && set -x

# ---------------------------------------------------------------------------
# Resolve user's home directory and group
# ---------------------------------------------------------------------------
_HOME="$(shell::resolve_home "$USERNAME")"
_GROUP="$(id -gn "$USERNAME" 2> /dev/null || echo "$USERNAME")"

if [ ! -d "$_HOME" ]; then
  echo "⚠️  Home directory '${_HOME}' does not exist for user '${USERNAME}' — creating." >&2
  mkdir -p "$_HOME"
  chown "${USERNAME}:${_GROUP}" "$_HOME"
fi

echo "ℹ️  Configuring user '${USERNAME}' (home: ${_HOME}, mode: ${USER_CONFIG_MODE})..." >&2

# ---------------------------------------------------------------------------
# Resolve per-user XDG and Zsh config paths
# ---------------------------------------------------------------------------
_XDG_CONFIG_HOME="${_HOME}/.config"

# Expand ZDOTDIR option (may be ~-prefixed, $HOME-prefixed, or absolute).
# shellcheck disable=SC2016
if [ -z "${ZDOTDIR-}" ]; then
  _ZDOTDIR="${_XDG_CONFIG_HOME}/zsh"
elif [[ "$ZDOTDIR" == '~'* ]]; then
  _ZDOTDIR="${_HOME}${ZDOTDIR#\~}"
elif [[ "$ZDOTDIR" == '$HOME'* ]]; then
  _ZDOTDIR="${_HOME}${ZDOTDIR#'$HOME'}"
else
  _ZDOTDIR="$ZDOTDIR"
fi

# Apply defaults for custom dirs if not explicitly provided.
[ -z "${OHMYZSH_CUSTOM_DIR-}" ] && OHMYZSH_CUSTOM_DIR="${_ZDOTDIR}/custom"
[ -z "${OHMYBASH_CUSTOM_DIR-}" ] && OHMYBASH_CUSTOM_DIR="${_XDG_CONFIG_HOME}/bash/custom"

# ---------------------------------------------------------------------------
# Mode: skip — bail out if any dotfile already exists
# ---------------------------------------------------------------------------
if [[ "$USER_CONFIG_MODE" == "skip" ]]; then
  if [ -f "${_ZDOTDIR}/.zshrc" ] || [ -f "${_HOME}/.bashrc" ]; then
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
    _rel="${_skel_file#"${SKEL_DIR}"/}"

    # Skip p10k.zsh — it's copied only when p10k theme is selected.
    [[ "$_rel" == "p10k.zsh" ]] && continue

    # .zshenv always lives in HOME so zsh finds it before ZDOTDIR is set.
    # All other zsh config files go into ZDOTDIR.
    case "$_rel" in
      .zshenv)
        _dest="${_HOME}/${_rel}"
        ;;
      .zshrc | .zprofile | .zlogin)
        _dest="${_ZDOTDIR}/${_rel}"
        ;;
      *)
        _dest="${_HOME}/${_rel}"
        ;;
    esac

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
# Inject ZDOTDIR into ~/.zshenv
# ---------------------------------------------------------------------------
_ZSHENV="${_HOME}/.zshenv"
[ -f "$_ZSHENV" ] || touch "$_ZSHENV"
mkdir -p "$_ZDOTDIR"
inject_guarded_block "$_ZSHENV" "install-shell-zdotdir" "ZDOTDIR=\"${_ZDOTDIR}\""

# ---------------------------------------------------------------------------
# Zsh theme file ($ZDOTDIR/zshtheme)
# ---------------------------------------------------------------------------
_ZSHTHEME="${_ZDOTDIR}/zshtheme"
_ZSHTHEME_CONTENT=""

if [ -n "$OHMYZSH_INSTALL_DIR" ] && [ -d "$OHMYZSH_INSTALL_DIR" ]; then
  # Resolve effective ZSH_CUSTOM path for this user (expand ~/$HOME if explicit).
  _OMZ_CUSTOM_DIR="$(resolve_custom_dir "$OHMYZSH_CUSTOM_DIR" "$_HOME")"
  _OMZ_IS_PER_USER=false
  [[ "$_OMZ_CUSTOM_DIR" == "$_HOME"* ]] && _OMZ_IS_PER_USER=true

  # Resolve the ZSH_THEME value (e.g. "powerlevel10k/powerlevel10k").
  _OMZ_THEME_VALUE=""
  if [ -n "$OHMYZSH_THEME" ]; then
    _OMZ_THEME_VALUE="$(shell::resolve_omz_theme \
      --theme_slug "$OHMYZSH_THEME" \
      --custom_dir "${OHMYZSH_INSTALL_DIR}/custom")"
  fi

  # Build plugin names list from slugs.
  _OMZ_PLUGIN_NAMES=""
  if [ -n "$OHMYZSH_PLUGINS" ]; then
    _OMZ_PLUGIN_NAMES="$(shell::plugin_names_from_slugs "$OHMYZSH_PLUGINS" | tr '\n' ' ')"
    _OMZ_PLUGIN_NAMES="${_OMZ_PLUGIN_NAMES% }"
  fi

  # Determine if we're using p10k.
  _IS_P10K=false
  [[ "$OHMYZSH_THEME" == *powerlevel10k* ]] && _IS_P10K=true

  # Detect starship/OMZ theme conflict.
  _ZSH_USE_STARSHIP=false
  if [[ "$STARSHIP_SHELLS" == *zsh* ]]; then
    _ZSH_USE_STARSHIP=true
    if [ -n "$OHMYZSH_THEME" ]; then
      echo "⚠️  ohmyzsh_theme='${OHMYZSH_THEME}' is set but starship_shells includes 'zsh' — theme ignored, Starship will own the prompt." >&2
    fi
  fi

  # Build Oh My Zsh theme file content.
  # shellcheck disable=SC2016
  _ZSHTHEME_CONTENT+="export ZSH=\"${OHMYZSH_INSTALL_DIR}\""$'\n'
  # shellcheck disable=SC2016
  _ZSHTHEME_CONTENT+='ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-zsh"'$'\n'
  # shellcheck disable=SC2016
  _ZSHTHEME_CONTENT+='[ -d "$ZSH_CACHE_DIR" ] || mkdir -p "$ZSH_CACHE_DIR"'$'\n'
  # shellcheck disable=SC2016
  _ZSHTHEME_CONTENT+='ZSH_COMPDUMP="${ZSH_CACHE_DIR}/.zcompdump-${SHORT_HOST}-${ZSH_VERSION}"'$'\n'
  _ZSHTHEME_CONTENT+="ZSH_CUSTOM=\"${_OMZ_CUSTOM_DIR}\""$'\n'

  if [[ "$_ZSH_USE_STARSHIP" == true ]]; then
    _ZSHTHEME_CONTENT+='ZSH_THEME=""'$'\n'
  elif [ -n "$_OMZ_THEME_VALUE" ]; then
    _ZSHTHEME_CONTENT+="ZSH_THEME=\"${_OMZ_THEME_VALUE}\""$'\n'
  else
    _ZSHTHEME_CONTENT+='ZSH_THEME=""'$'\n'
  fi

  if [ -n "$_OMZ_PLUGIN_NAMES" ]; then
    _ZSHTHEME_CONTENT+="plugins=(${_OMZ_PLUGIN_NAMES})"$'\n'
  else
    _ZSHTHEME_CONTENT+='plugins=()'$'\n'
  fi

  _ZSHTHEME_CONTENT+="zstyle ':omz:update' mode disabled"$'\n'

  if [[ "$_IS_P10K" == true ]] && [[ "$_ZSH_USE_STARSHIP" != true ]]; then
    _ZSHTHEME_CONTENT+='POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true'$'\n'
  fi

  # shellcheck disable=SC2016
  _ZSHTHEME_CONTENT+='[ -f "$ZSH/oh-my-zsh.sh" ] && source "$ZSH/oh-my-zsh.sh"'$'\n'

  if [[ "$_IS_P10K" == true ]] && [[ "$_ZSH_USE_STARSHIP" != true ]]; then
    # shellcheck disable=SC2016
    _ZSHTHEME_CONTENT+='[[ ! -f "${HOME}/.p10k.zsh" ]] || source "${HOME}/.p10k.zsh"'$'\n'
  fi

  # Create custom directory and symlink installer-managed items if per-user.
  mkdir -p "${_OMZ_CUSTOM_DIR}/themes" "${_OMZ_CUSTOM_DIR}/plugins"
  if [[ "$_OMZ_IS_PER_USER" == true ]]; then
    _link_custom_items \
      "${OHMYZSH_INSTALL_DIR}/custom" \
      "$_OMZ_CUSTOM_DIR" \
      "$OHMYZSH_THEME" \
      "$OHMYZSH_PLUGINS" \
      "$USER_CONFIG_MODE"
  fi

  # Copy p10k config if p10k theme is selected (and not using starship).
  if [[ "$_IS_P10K" == true ]] && [[ "$_ZSH_USE_STARSHIP" != true ]] &&
    [ -n "$SKEL_DIR" ] && [ -f "${SKEL_DIR}/p10k.zsh" ]; then
    case "$USER_CONFIG_MODE" in
      overwrite)
        cp -f "${SKEL_DIR}/p10k.zsh" "${_HOME}/.p10k.zsh"
        ;;
      augment)
        [ ! -f "${_HOME}/.p10k.zsh" ] && cp "${SKEL_DIR}/p10k.zsh" "${_HOME}/.p10k.zsh"
        ;;
    esac
  fi
fi

# Append Starship integration for zsh.
if [[ "$STARSHIP_SHELLS" == *zsh* ]]; then
  if ! command -v starship > /dev/null 2>&1 && [ ! -x "${STARSHIP_BIN_DIR}/starship" ]; then
    echo "⚠️  starship_shells includes 'zsh' but starship is not on PATH — integration injected anyway." >&2
  fi
  # shellcheck disable=SC2016
  _ZSHTHEME_CONTENT+='command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"'$'\n'
fi

# Write zshtheme file.
if [ -n "$_ZSHTHEME_CONTENT" ]; then
  mkdir -p "$_ZDOTDIR"
  case "$USER_CONFIG_MODE" in
    overwrite)
      printf '%s' "$_ZSHTHEME_CONTENT" > "$_ZSHTHEME"
      echo "ℹ️  Written zsh theme file '${_ZSHTHEME}'." >&2
      ;;
    augment)
      if [ ! -f "$_ZSHTHEME" ]; then
        printf '%s' "$_ZSHTHEME_CONTENT" > "$_ZSHTHEME"
        echo "ℹ️  Written zsh theme file '${_ZSHTHEME}'." >&2
      fi
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# Bash theme file (~/.config/bash/bashtheme)
# ---------------------------------------------------------------------------
_BASHTHEME="${_XDG_CONFIG_HOME}/bash/bashtheme"
_BASHTHEME_CONTENT=""

if [ -n "$OHMYBASH_INSTALL_DIR" ] && [ -d "$OHMYBASH_INSTALL_DIR" ]; then
  # Resolve effective OSH_CUSTOM path for this user (expand ~/$HOME if explicit).
  _OMB_CUSTOM_DIR="$(resolve_custom_dir "$OHMYBASH_CUSTOM_DIR" "$_HOME")"
  _OMB_IS_PER_USER=false
  [[ "$_OMB_CUSTOM_DIR" == "$_HOME"* ]] && _OMB_IS_PER_USER=true

  # Resolve the OSH_THEME value.
  _OMB_THEME_VALUE=""
  if [ -n "$OHMYBASH_THEME" ]; then
    _OMB_THEME_VALUE="$(basename "$OHMYBASH_THEME")"
  fi

  # Build plugin names list from slugs.
  _OMB_PLUGIN_NAMES=""
  if [ -n "$OHMYBASH_PLUGINS" ]; then
    _OMB_PLUGIN_NAMES="$(shell::plugin_names_from_slugs "$OHMYBASH_PLUGINS" | tr '\n' ' ')"
    _OMB_PLUGIN_NAMES="${_OMB_PLUGIN_NAMES% }"
  fi

  # Detect starship/OMB theme conflict.
  _BASH_USE_STARSHIP=false
  if [[ "$STARSHIP_SHELLS" == *bash* ]]; then
    _BASH_USE_STARSHIP=true
    if [ -n "$OHMYBASH_THEME" ]; then
      echo "⚠️  ohmybash_theme='${OHMYBASH_THEME}' is set but starship_shells includes 'bash' — theme ignored, Starship will own the prompt." >&2
    fi
  fi

  # Build Oh My Bash theme file content.
  _BASHTHEME_CONTENT+="export OSH=\"${OHMYBASH_INSTALL_DIR}\""$'\n'
  # shellcheck disable=SC2016
  _BASHTHEME_CONTENT+='OSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-bash"'$'\n'
  # shellcheck disable=SC2016
  _BASHTHEME_CONTENT+='[ -d "$OSH_CACHE_DIR" ] || mkdir -p "$OSH_CACHE_DIR"'$'\n'
  _BASHTHEME_CONTENT+="OSH_CUSTOM=\"${_OMB_CUSTOM_DIR}\""$'\n'

  if [[ "$_BASH_USE_STARSHIP" == true ]]; then
    _BASHTHEME_CONTENT+='OSH_THEME=""'$'\n'
  elif [ -n "$_OMB_THEME_VALUE" ]; then
    _BASHTHEME_CONTENT+="OSH_THEME=\"${_OMB_THEME_VALUE}\""$'\n'
  else
    _BASHTHEME_CONTENT+='OSH_THEME=""'$'\n'
  fi

  if [ -n "$_OMB_PLUGIN_NAMES" ]; then
    _BASHTHEME_CONTENT+="plugins=(${_OMB_PLUGIN_NAMES})"$'\n'
  else
    _BASHTHEME_CONTENT+='plugins=()'$'\n'
  fi

  # shellcheck disable=SC2016
  _BASHTHEME_CONTENT+='[ -f "$OSH/oh-my-bash.sh" ] && source "$OSH/oh-my-bash.sh"'$'\n'

  # Create custom directory and symlink installer-managed items if per-user.
  mkdir -p "${_OMB_CUSTOM_DIR}/themes" "${_OMB_CUSTOM_DIR}/plugins"
  if [[ "$_OMB_IS_PER_USER" == true ]]; then
    _link_custom_items \
      "${OHMYBASH_INSTALL_DIR}/custom" \
      "$_OMB_CUSTOM_DIR" \
      "$OHMYBASH_THEME" \
      "$OHMYBASH_PLUGINS" \
      "$USER_CONFIG_MODE"
  fi
fi

# Append Starship integration for bash.
if [[ "$STARSHIP_SHELLS" == *bash* ]]; then
  if ! command -v starship > /dev/null 2>&1 && [ ! -x "${STARSHIP_BIN_DIR}/starship" ]; then
    echo "⚠️  starship_shells includes 'bash' but starship is not on PATH — integration injected anyway." >&2
  fi
  # shellcheck disable=SC2016
  _BASHTHEME_CONTENT+='command -v starship >/dev/null 2>&1 && eval "$(starship init bash)"'$'\n'
fi

# Write bashtheme file.
if [ -n "$_BASHTHEME_CONTENT" ]; then
  mkdir -p "${_XDG_CONFIG_HOME}/bash"
  case "$USER_CONFIG_MODE" in
    overwrite)
      printf '%s' "$_BASHTHEME_CONTENT" > "$_BASHTHEME"
      echo "ℹ️  Written bash theme file '${_BASHTHEME}'." >&2
      ;;
    augment)
      if [ ! -f "$_BASHTHEME" ]; then
        printf '%s' "$_BASHTHEME_CONTENT" > "$_BASHTHEME"
        echo "ℹ️  Written bash theme file '${_BASHTHEME}'." >&2
      fi
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# Fix ownership — give the user full ownership of their entire home directory
# ---------------------------------------------------------------------------
chown -R "${USERNAME}:${_GROUP}" "$_HOME"

echo "✅ User '${USERNAME}' configuration complete." >&2
