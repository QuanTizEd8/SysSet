#!/bin/sh

symlink_data_dir() {
  # $1 is the containerWorkspaceFolder variable,
  # passed directly by the devcontainer CLI — see metadata.yaml.
  _container_workspace_folder="${1}"

  # When data_dir was set to empty, skip the symlink.
  if [ -z "${DATA_DIR:-}" ]; then
    warn "data_dir not specified; skipping ~/.local/share/opencode symlink."
    return 0
  fi

  _data_dir_fullpath="${_container_workspace_folder}/${DATA_DIR}"

  rm -rf ~/.local/share/opencode
  mkdir -p "$_data_dir_fullpath"
  mkdir -p "$(dirname ~/.local/share/opencode)"
  ln -s "$_data_dir_fullpath" ~/.local/share/opencode
}

symlink_data_dir "$1"
