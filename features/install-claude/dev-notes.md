# Developer Notes

## Config directory symlink

The feature persists Claude's state by symlinking `~/.claude` to a workspace
subdirectory (the `config_dir` option) from the `symlink-config-dir`
`onCreateCommand`, rather than doing it during the main install or by exporting
`CLAUDE_CONFIG_DIR`. Two constraints drive this design:

- **Why an `onCreateCommand` instead of `install.bash`?** The symlink target is
  the workspace path *inside* the container, and `containerWorkspaceFolder` is
  only exposed for substitution in `devcontainer-feature.json` lifecycle hooks —
  it is not passed as an environment variable to `install.sh`/`install.bash`.
  Conversely, `_REMOTE_USER` is available to the install scripts but is not
  substitutable in `devcontainer-feature.json`. The lifecycle command runs as
  the remote user, so `~/.claude` in the script resolves to that user's home,
  while the workspace path is handed in explicitly as `${containerWorkspaceFolder}`
  (see the `onCreateCommand.symlink-config-dir.args` in `metadata.yaml`).

- **Why a symlink instead of `CLAUDE_CONFIG_DIR`?** The VS Code extension ignores
  the `CLAUDE_CONFIG_DIR` environment variable
  ([anthropics/claude-code#30538](https://github.com/anthropics/claude-code/issues/30538)),
  so pointing only the CLI at a workspace directory via that variable would not
  persist the extension's state. Symlinking `~/.claude` works for both the CLI
  and the extension.

## References

- [Advanced Setup](https://code.claude.com/docs/en/setup)
- [The `~/.claude` directory](https://code.claude.com/docs/en/claude-directory)
- [VS Code integration](https://code.claude.com/docs/en/vs-code)
- [Dev Containers](https://code.claude.com/docs/en/devcontainer)
- [Official Claude Code devcontainer feature](https://github.com/anthropics/devcontainer-features/tree/main/src/claude-code)
