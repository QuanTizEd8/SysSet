#!/bin/sh

symlink_config_dir() {
  # $1 is the containerWorkspaceFolder variable,
  # passed directly by the devcontainer CLI — see metadata.yaml.
  _container_workspace_folder="${1}"

  # When config_dir was set to empty, skip the symlink.
  if [ -z "${CONFIG_DIR:-}" ]; then
    warn "config_dir not specified; skipping ~/.config/opencode symlink."
    return 0
  fi

  _config_dir_fullpath="${_container_workspace_folder}/${CONFIG_DIR}"

  rm -rf ~/.config/opencode
  mkdir -p "$(dirname "$_config_dir_fullpath")"
  mkdir -p "$(dirname ~/.config/opencode)"
  ln -s "$_config_dir_fullpath" ~/.config/opencode
}

symlink_config_dir "$1"
