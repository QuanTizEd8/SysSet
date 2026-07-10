# Developer Notes

Pixi is installed by the shared `install.tmpl.bash` flow using the `binary`
method (GitHub release tarball + `.sha256` sidecar, `binary_src: pixi`). The
feature-specific `install.bash` adds only three hooks; everything else
(download, checksum, prefix/symlink/PATH handling, `if_exists`, cleanup,
completions, verification) comes from the template and `lib/`. Keep custom logic
confined to these hooks and push anything reusable upstream into the template or
library.

## `__update_run__` — self-update override

The default template update path is replaced so that `if_exists=update` upgrades
via pixi's own `pixi self-update --version "${VERSION}"`, which is the correct
mechanism for a binary that manages itself. `__update_predispatch__` (template)
still handles the method/prefix/version routing and only invokes this hook when
an in-place version bump is actually needed, so the hook can assume the target
version differs from the installed one.

On failure the hook logs an error and returns non-zero. Note this diverges from
the generic `update` contract: there is no reinstall fallback here, so a pixi
that cannot self-update (e.g. a Homebrew- or conda-provided binary) makes the
update fail rather than silently reinstalling.

## `__install_finish_post` — global manifest and global installs

Runs after the binary is in place, only when `global_manifest` or
`global_installs` is set. It:

1. Resolves the pixi binary, preferring the just-installed `_RESOLVED_PREFIX`
   over whatever is on `PATH`.
2. Resolves the target user devcontainer-aware (`users__get_current` →
   `users__resolve_home`) — the same resolution the prefix activation snippet
   uses, so global tools land in the home of whoever will actually run pixi.
3. Computes a **literal** `PIXI_HOME` for that user: `home_dir` when set (with a
   leading `~` expanded against the *resolved user's* home, not the install
   process's `$HOME`, which may be root's), otherwise `<user-home>/.pixi`.
4. Writes the manifest to `${PIXI_HOME}/manifests/pixi-global.toml`, then runs
   `pixi global sync` and any `pixi global install` commands **as the target
   user** with `PIXI_HOME` exported into the environment.

`GLOBAL_MANIFEST` arrives as an already-resolved local file path — the
`_content_or_uri` argparse step materializes inline content or fetches remote
URIs (honoring `fetch_headers`/`fetch_netrc`) before this hook runs. When the
install process runs as a different user than the target (root during a
devcontainer build), ownership of `${PIXI_HOME}` and its `manifests/` subtree is
fixed so the target user can modify them at runtime.

## `__prefix_activation_snippet` — `PIXI_HOME` export

Emits the `export PIXI_HOME="…"` line written to bash/zsh startup files by the
generated prefix-activation system (`prefix.activation.shells: [bash, zsh]`).

Unlike `__install_finish_post`, this snippet is evaluated by the target user at
runtime, so it must use a literal `${HOME}` rather than a resolved absolute path:
with no `home_dir` it emits `${HOME}/.pixi`, and a leading `~` in `home_dir` is
rewritten to `${HOME}` (bare tilde is not expanded inside a double-quoted shell
string). This keeps the exported value correct regardless of which user's shell
sources the file.
