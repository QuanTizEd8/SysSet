# Developer Notes

The feature is almost entirely declarative — version resolution, downloads,
sidecar (`sha256sums.asc`) verification, the OS-package and PPA
(`upstream-package`) installs, `method=auto` resolution, shell completions,
PATH export, the idempotency/`if_exists` logic, and the dummy-package
registration on source builds are all provided by the shared template from the
`_options` and `_dependencies` blocks in `metadata.yaml`. Only the pieces below
need feature-specific hooks in `install.bash`.

## Source tarball URI (`__install_run_source_pre`)

The stable-release tarball URI is declared in `_options.method.source.asset_uri`
(kernel.org). GitHub RC tags use `-rcN` (e.g. `v2.55.0-rc0`) but the matching
kernel.org tarball uses `.rcN` (`git-2.55.0.rc0.tar.gz`) and lives under a
separate `testing/` directory with its own `sha256sums.asc`. For an RC
`VERSION`, the hook rewrites `SOURCE_ASSET_URI`/`SOURCE_SIDECAR_URI` to the
`testing/` paths. The hook also creates and writeability-checks the resolved
prefix before the download starts.

## `sysconfdir` (`__resolve_input_prefixes_post`)

`SYSCONFDIR=auto` resolves after the prefix is known: `<owner-home>/.config`
for a user-owned prefix, otherwise `/etc`. It is passed to `make` as
`sysconfdir=` (so Git reads `<sysconfdir>/gitconfig` as its system config) and
reused by `_write_gitconfig` to locate the target file.

## Source build (`__install_run_source_build`)

Overrides the framework auto-build. Base make flags are
`prefix=… sysconfdir=… USE_LIBPCRE2=YesPlease`. On Alpine (musl),
`NO_GETTEXT NO_REGEX NO_SVN_TESTS NO_SYS_POLL_H` are added unconditionally.
`NO_FLAGS` tokens (comma- or space-separated) are upper-cased and mapped to
`NO_<TOKEN>=YesPlease`, deduplicated against flags already present — there is no
allow-list, so any token is accepted verbatim. `SOURCE_MAKE_FLAGS` is appended
last on both the `all` and `install` invocations, so it can override any
computed flag.

`make install` does not install the contrib completion scripts, so the hook
copies `contrib/completion/*.{bash,zsh}` into
`${PREFIX}/share/git-core/contrib/completion/`. The shared
`__install_shell_completions__` then reads them from there via the paths
declared in `_options.completions.source_files`.

## gitconfig (`_write_gitconfig`)

Writes `default_branch`, `safe_directory`, `user_name`, `user_email`, and the
freeform `gitconfig` block to one file: `<sysconfdir>/gitconfig` for a
system-scope install, or `<owner-home>/.config/git/config` for a user-scope one.
The freeform block is emitted first and the named options after it, so the named
options win on conflict (Git applies last value). A `gitconfig` value with no
newline is treated as a URI/path and fetched via `uri__resolve` (forwarding
`FETCH_HEADERS`/`FETCH_NETRC`); literal `\n` escapes — as some devcontainer CLI
environments serialize multi-line values — are expanded to real newlines first,
so such a value is still recognized as inline content. The result is written as
an idempotent `shell__sync_block` marker block.

## MANPATH export (`_export_git_manpath`)

Git's own `${PREFIX}/bin` PATH export is handled by the shared prefix machinery.
For source builds under a non-standard prefix (not `/usr/local` or
`~/.local`), the man pages also need to be discoverable, so this hook writes an
`export MANPATH="${PREFIX}/share/man:${MANPATH}"` block to the target shells.
It is skipped for non-source methods, standard prefixes, and
`PREFIX_DISCOVERY` of `none`/`symlink`. The metadata advertises this via
`_options.prefix.exports.description`.

## Uninstall cleanup (`__uninstall_run_prefix_post`, `__uninstall_finish_post`)

The shared prefix uninstall removes only the primary `git` binary. A source
build also scatters `git-*` helper binaries, `lib/git-core/`, `share/git-core/`,
and `man1/5/7` pages, which `__uninstall_run_prefix_post` removes under the
derived prefix. `__uninstall_finish_post` additionally removes the MANPATH
export block and the `gitconfig (install-git)` marker block.
