# Developer Notes

## Why the VS Code user-dir symlink is an `onCreateCommand`, not part of the install

The symlink from the workspace `.copilot` directory (the `vscode_user_dir` option)
to `~/.vscode-server/data/User` cannot be created during `install.bash`, because the
two devcontainer variables it needs are never available in the same context:

- `remoteUser` is exposed to the installer as the `_REMOTE_USER` environment
  variable (see `os__is_devcontainer_build` in `lib/os.bash`), but is **not**
  available for `${...}` substitution in `devcontainer-feature.json`.
- `containerWorkspaceFolder` is the mirror image: it is **not** present in the
  installer's environment, but **is** available for substitution in
  `devcontainer-feature.json`.

So at install time the feature knows the target user but not the workspace path.
The symlink is therefore deferred to the `symlink-vscode-user-dir` `onCreateCommand`,
whose argument carries `${containerWorkspaceFolder}` — substituted by the
devcontainer CLI at lifecycle time. See the `onCreateCommand` entry in
`metadata.yaml` and `files/on-create--symlink-vscode-user-dir.sh`.

## Reference

Upstream devcontainers Copilot CLI feature (prior art for the VS Code symlink
approach): <https://github.com/devcontainers/features/tree/main/src/copilot-cli>
