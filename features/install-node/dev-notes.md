# Developer Notes

Almost the entire installation flow — argument parsing, dependency install,
`if_exists` handling, prefix/symlink/PATH configuration, and verification — is
provided by the shared `install.tmpl.bash` template and `lib/`. The
feature-specific `install.bash` only implements the three hooks the generic
binary flow cannot infer for Node.js.

## `__resolve_version` — custom version resolver

The feature declares `version.resolution: none` because the nodejs.org release
index is not one of the framework's built-in resolvers (`github_release`,
`github_tag`, `npm`, `cargo`, `sidecar`). When `__resolve_version` is defined,
the template calls it and uses its stdout as the resolved version. The hook
downloads `https://nodejs.org/dist/index.json` into `$INSTALLER_DIR` and
delegates to `npm__resolve_node_version` (`lib/npm.bash`), which maps a spec
(`stable`, `lts`/`lts/*`, `latest`/`node`, `<major>`, `<major>.<minor>`, or an
exact `vX.Y.Z`) to a concrete `vX.Y.Z` validated against the index. The result
becomes `VERSION` and is substituted into the asset/sidecar URIs as
`{feat.version}`.

## Full-tree install via `__install_run_binary_post`

The upstream tarball extracts to a single top-level directory,
`node-<version>-<platform>/`, containing the complete distribution (`bin/`,
`lib/`, `include/`, `share/`). The generic binary installer copies only the
declared `binary_src` (`bin/node`) into `${PREFIX}/bin/`, but Node.js needs its
full tree — `npm`, `npx`, and `corepack` in `bin/` resolve into
`lib/node_modules`. So:

- `binary_src: [bin/node]` identifies `node` as the primary binary for the
  framework (download/verify/extract, primary-bin bookkeeping, verification
  script).
- `__install_run_binary_pre` computes the platform triple with
  `npm__node_platform` and stores the extracted directory name in
  `_NODE_DIST_DIR` (`node-${VERSION}-${platform}`).
- `__install_run_binary_post` copies the entire
  `${INSTALLER_DIR}/asset/${_NODE_DIST_DIR}/.` tree (extracted verbatim by the
  framework) into `${_RESOLVED_PREFIX}/`, yielding `${PREFIX}/{bin,lib,include,share}`
  and the four binaries declared in `prefix.bins` (`node`, `npm`, `npx`, `corepack`).

## Alpine guard and macOS Xcode bootstrap

`__install_run_binary_pre` also:

- Aborts on Alpine (glibc-only binaries) with a pointer to `install-nvm`.
- Calls `bootstrap__xcode` (`lib/bootstrap.bash`) when `node_gyp_deps=true` on
  macOS, since node-gyp needs the Xcode Command Line Tools — the brew dependency
  block cannot provide the compilers.
