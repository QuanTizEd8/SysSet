# Developer Notes

This feature is almost entirely template-driven. Installation method dispatch,
version resolution, GitHub-release download and checksum verification, shell
completion generation, and prefix/PATH handling all come from the shared
`install.tmpl.bash` flow driven by the `_options` block in `metadata.yaml`
(`version.resolution=github_release`, the `binary`/`package`/`upstream-package`
methods, `completions.subcmd="completion -s"`, and `prefix.bins=[gh]`). There is
no bespoke installer code for any of that.

The only feature-local code lives in `install.bash` as two post-install hooks,
dispatched by `__install_finish_post` after the framework has installed `gh`,
its completions, and its prefix symlinks/exports:

- `_configure_user` — applies `git_protocol`, `setup_git`, and `sign_commits`.
- `_install_extensions` — installs the `extensions` entries.

`__install_finish_post` only calls each hook when its inputs are non-default
(`git_protocol`/`setup_git`/`sign_commits` for the first, a non-empty
`extensions` for the second).

## Per-user execution model

Both hooks resolve their target users the same way: they translate the
`ADD_CURRENT_USER`/`ADD_REMOTE_USER`/`ADD_CONTAINER_USER`/`ADD_USERS` options
into `--current`/`--remote`/`--container`/`--user` flags for
`users__resolve_list`, which deduplicates and drops root when other non-root
users are present.

For each resolved user, execution splits on whether the user is the current
(installing) user:

- **Current user:** run `gh`/`git` directly with per-invocation env overrides
  (`GH_CONFIG_DIR`, `HOME`, `GIT_CONFIG_GLOBAL`) pointing at that user's home,
  avoiding an unnecessary `su`.
- **Any other user:** run the command through `users__run_as <user>` so it
  executes with the target user's identity and environment.

## Implementation caveats

- **`setup_git`** runs `gh auth setup-git --force`; `--force` is required
  because there is no active `gh` login at build time. Afterwards the user's
  `~/.gitconfig` is `chown`ed back to the user (best-effort) in case `gh` created
  it as root.
- **`sign_commits=gpg`** clears any inherited `gpg.format` with
  `git config --global --unset-all gpg.format || true`; `git config --unset-all`
  exits 5 when the key is absent, so the `|| true` prevents an abort under
  `set -e`.
- **Extensions are best-effort:** a failed `gh extension install` is logged as a
  warning and does not fail the install — the feature's contract is to install
  `gh`, and extension availability depends on external network/repo state.
  Each entry is whitespace-trimmed before use.
