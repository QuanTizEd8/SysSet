# Notes

## Project `.pixi` Volume Mount

This feature always adds a named Docker volume mount for the project's `.pixi`
directory (`${containerWorkspaceFolder}/.pixi`, where `pixi install` materializes
per-project environments) together with an entrypoint that fixes the volume's
ownership so the remote user can write to it. No configuration is required, and
no `postCreateCommand` of your own is needed for the ownership fix.

The named volume serves two purposes:

- **Persistence.** Installed packages survive container rebuilds, so `pixi
  install` does not re-download and re-link everything each time.
- **Filesystem correctness.** Some conda packages ship files whose names differ
  only in case. When the workspace is bind-mounted from a macOS or Windows host,
  `.pixi` would land on a case-insensitive filesystem, where those files silently
  overwrite each other. A named Docker volume always lives on the container's
  case-sensitive Linux filesystem, avoiding the corruption.

The volume is named `<workspace-basename>-pixi` (e.g. `myproject-pixi`).

This project-local `.pixi` directory is distinct from `PIXI_HOME` — the global
environment and configuration directory set by `home_dir` (default
`$HOME/.pixi`), which stores `pixi global install` tools and is not backed by
this volume.

## Updating an Existing Pixi (`if_exists=update`)

When `if_exists=update` finds an existing pixi, this feature updates it with
`pixi self-update --version <resolved-version>` rather than the generic
reinstall-based update path. `version` is always resolved to a concrete version
first, so `--version` is always passed; use `version=latest` to track the newest
release on each rebuild.

Because `self-update` only works for a pixi that manages its own binary, an
`update` run against a pixi provided some other way (for example Homebrew or
conda) can fail — and, unlike the generic `update` contract, this feature does
not fall back to a reinstall when `self-update` fails.
