# `install.bash`

`features/<feature-id>/install.bash` is the feature-specific body of the installer. It contains **only** the hooks and data overrides that define the feature's custom behavior — no shebang, no header, no argument parsing.

The full installer is assembled by `just sync-src`: the template (`features/install.tmpl.bash`) provides the entire framework (argument parsing, library sourcing, version/method resolution, binary installation, PATH export, shell completions, lifecycle hooks), and the feature's `install.bash` is **injected after all template function definitions** (immediately before the single `__main__ "$@"` dispatch call at the end of the file). Any function a feature defines therefore overrides the corresponding template function.

---

## What the Framework Auto-Implements

For most features, declaring `_options` in `metadata.yaml` is sufficient — `install.bash` needs little or no code. The framework handles:

| Declared in `_options` | Auto-implemented in install.bash |
|------------------------|----------------------------------|
| `version.resolution: github_release` | Full `__resolve_version` (queries GitHub API, handles stable/latest/semver) |
| `method.binary` with `asset_uri` | Full `__install_run_binary__` (fetch, checksum, extract, install) |
| `method.package` | Full `__install_run_package__` (ospkg install from manifest) |
| `method.upstream-package` | Full `__install_run_upstream_package__` (adds package-source config, installs) |
| `method.script` with `asset_uri` | Full `__install_run_script__` (fetch, verify, execute) |
| `method.cargo` with `crate` | Full `__install_run_cargo__` (cargo install / cargo-binstall) |
| `method.npm` with `package` | Full `__install_run_npm__` (npm install -g) |
| `method.npm-bundled` | Full `__install_run_npm_bundled__` (bundled Node.js runtime) |
| `method.source` with `build_system` | Full `__install_run_source__` (fetch, configure, make) |
| `method.git-clone` | Full `__install_run_git_clone__` (clone, checkout VERSION) |
| `prefix.bins` | Symlinks / PATH export / activation in `__install_finish__` |
| `completions.subcmd` or `source_files` | Shell completion installation in `__install_finish__` |
| `verify.cmd` | Post-install binary verification in `__install_finish__` |
| Two or more methods declared | Shared `method=auto` resolution from declared methods and `when` blocks |

**Minimum `install.bash` for a feature with a GitHub binary release:**

```bash
# Typically empty.
```

Everything else — download URL expansion, fetch, SHA256 verification, extraction, binary placement, PATH export, completions — is handled by the framework when `_options.method.binary` declares the `asset_uri`.

---

## Template Architecture

The template drives execution via `__main__()`, which calls hooks in a fixed order:

```
__main__
  ├── __init__                      # env setup, library sourcing, arg parsing
  │     ├── [__init_pre]            # user hook (optional)
  │     ├── __init_env__            # sets _FEAT_DIR, _FEAT_FILES_DIR, metadata env vars
  │     ├── __init_lib__            # sources lib/__init__.bash (all library modules)
  │     ├── __init_script__         # sets up logging, exit trap, session scratch
  │     ├── __init_args__           # parses CLI flags → env vars; validates _path / _uri options
  │     └── [__init_post]           # user hook (optional)
  │
  └── [if_exists branch or direct install]
        └── __install__
              ├── [__install_pre]                     # user hook: runs before everything
              ├── __install_init__
              │     ├── [__install_init_pre]          # user hook
              │     ├── __resolve_input_method__      # shared auto-resolver; optional __resolve_method escape hatch
              │     ├── __resolve_input_version__     # calls __resolve_version or auto-impl
              │     ├── __resolve_input_prefixes__    # resolves PREFIX from options + platform
              │     ├── __dep_install_base__          # OSPKG_MANIFEST_BASE_{RUN,BUILD}
              │     └── [__install_init_post]         # user hook
              ├── __install_run__                     # dispatches to method-specific runner
              │     ├── [__install_run_pre]           # user hook: before method dispatch
              │     ├── __dep_install_option_bound__  # boolean option-* manifests (all features)
              │     ├── __dep_install_for_method__    # active METHOD manifest env vars
              │     ├── [__install_run_<method>_pre]  # user hook: before specific method
              │     ├── __install_run_<method>__      # auto-implementation (or user override)
              │     ├── [__install_run_<method>_post] # user hook: after specific method
              │     └── [__install_run_post]          # user hook: after method dispatch
              ├── __install_finish__                  # completions, PATH export, lifecycle, verify
              └── [__install_post]                    # user hook: runs after everything
```

When `if_exists` is set, `__main__` first calls `__detect_existing__` and branches to skip/fail/reinstall/uninstall/update logic before entering `__install__`.

---

## Available Environment Variables

All variables below are set before any user hook runs.

### Metadata-derived (always available)

```bash
_FEAT_ID                    # Feature ID (directory name)
_FEAT_VERSION               # Feature version from metadata.yaml
_FEAT_NAME                  # Feature display name
_FEAT_DIR                   # Absolute path to src/<feature-id>/ at runtime
_FEAT_FILES_DIR             # ${_FEAT_DIR}/files
_FEAT_SHARE_DIR_ROOT        # /usr/local/share/<namespace>/<id>
_FEAT_SHARE_DIR_NONROOT     # ${HOME}/.local/share/<namespace>/<id>
_FEAT_LIFECYCLE_DIR         # Lifecycle hook directory
_FEAT_PROFILE_D_FILE        # Shell profile snippet filename
```

### User options (from CLI args or devcontainer features config)

```bash
VERSION                     # Resolved version (e.g., "1.7.1")
METHOD                      # Resolved install method (binary, package, source, ...)
LOG_LEVEL                   # Console verbosity (silent|error|warn|info|debug|trace)
LOG_FILE                    # Path to session log file (empty = no file)
LOG_FILE_LEVEL              # File verbosity (default: trace)
IF_EXISTS                   # Behavior when tool exists: skip|fail|reinstall|update|uninstall
PREFIX                      # Raw prefix option (may be an array with root/non-root/platform variants)
_RESOLVED_PREFIX            # Resolved, writable install prefix — use THIS in build/install hooks
PREFIX_SCOPE                # "system" (root) or "user" (non-root)
RUNTIME_PATH                # PATH used to decide whether the prefix is already reachable
SHELL_COMPLETIONS           # Array of shells for completions
INSTALLER_DIR               # Working dir for downloads (set when _options.installer_dir true)
```

### Version resolution (set by `__resolve_input_version__`)

```bash
VERSION_URI                 # Metadata endpoint (GitHub API URL, npm registry URL, etc.)
VERSION_RESOLUTION          # Resolution type: github_release, github_tag, npm, cargo, sidecar, git_ref, none
VERSION_FLAG                # CLI flag for version queries (default: --version)
VERSION_TAG_PREFIX          # Tag prefix used to filter releases/tags (e.g. "v")
_FEAT_RESOLVED_TAG          # Full VCS tag (e.g., "v1.7.1"); empty for non-VCS resolution
_FEAT_RESOLVED_GIT_SHA      # SHA when using git_ref resolution
```

### Method-specific (set from _options or user overrides)

```bash
# binary method
BINARY_ASSET_URI            # Expanded download URL
BINARY_SIDECAR_URI          # Checksum file URL
BINARY_SRC                  # Filename inside archive
BINARY_COMPANION_BINS       # Additional binaries to symlink alongside the primary one
BINARY_SHA256               # Pre-computed SHA256 (optional)

# script method
SCRIPT_ASSET_URI            # Installer script URL
SCRIPT_ARGS                 # Static arguments to script

# cargo method
CARGO_CRATE                 # Crate name

# npm / npm-bundled
NPM_PACKAGE                 # Package name
NPM_REGISTRY                # npm registry URL (optional)
NPM_CMD                     # Command name to expose (npm-bundled)
NODE_VERSION                # Node.js version (npm-bundled only)

# package / upstream-package method
REGISTER_PACKAGE_NAME       # OS package name registered for version checks / dummy package

# source method
SOURCE_ASSET_URI            # Source tarball URL
SOURCE_FALLBACK_ASSET_URI   # Alternate source URL if the primary fetch fails
SOURCE_BUILD_SYSTEM         # autotools | make | cmake
SOURCE_CONFIGURE_ARGS       # Array of ./configure arguments
SOURCE_CMAKE_ARGS           # Array of cmake arguments (build_system: cmake)
SOURCE_BUILD_ENV            # Array of NAME=value env overrides injected into source auto-builds
SOURCE_MAKE_FLAGS           # Array of make variable assignments
SOURCE_MAKE_TARGETS         # Array of make targets
SOURCE_INSTALL_BINS         # Array of built binary paths copied to ${_RESOLVED_PREFIX}/bin/

# git-clone method
GIT_CLONE_URI               # Repository URL
GIT_CLONE_CONFIG            # Array of "key=value" git config pairs
```

---

## Hook Reference

Define only the hooks your feature needs. Every hook is optional — template defaults apply when the hook is absent.

### `__resolve_method` — optional `method: auto` escape hatch

Called by `__resolve_input_method__` before the shared auto resolver when `METHOD=auto`. Must print exactly one method name to stdout:

```bash
__resolve_method() {
  if [[ "$(os__platform)" == "macos" ]]; then
    printf 'package\n'
  else
    printf 'binary\n'
  fi
}
```

**When you need this:** Only when the shared auto resolver cannot express the feature's selection rules from the declared methods and their `when` conditions. Most features should omit this hook entirely.

### `__resolve_version` — optional override

Prints the resolved bare version string to stdout. The auto-implementation handles `github_release`, `github_tag`, `npm`, `cargo`, and `git_ref` resolution automatically when `_options.version.resolution` is set. Only write this hook when custom resolution logic is needed.

```bash
__resolve_version() {
  # Custom version lookup — must print a bare version string
  printf '%s\n' "$(curl -sf https://api.example.com/latest | jq -r .version)"
}
```

May also set `_FEAT_RESOLVED_TAG` via `declare -g` for access to the full VCS tag in URL patterns.

### `__install_pre` / `__install_post`

Run before and after the **entire** install sequence (init + method dispatch + finish).

```bash
__install_pre() {
  logging__info "Checking prerequisites"
  ospkg__install build-essential
}

__install_post() {
  # Runs after __install_finish__ (completions, PATH, lifecycle already done)
  tool config --global some-setting value
}
```

### `__install_init_pre` / `__install_init_post`

Run before/after `__install_init__` — at the point when VERSION, METHOD, and PREFIX have just been resolved and `_dependencies.run.base` has just been installed.

The install template mirrors resolved globals into the context registry via `__ctx_sync_version__`, `__ctx_sync_pm_version__`, `__ctx_sync_method__`, and `__ctx_sync_prefix__` (or `__ctx_sync__` for version, method, and prefix only). Feature hooks that change `VERSION`, `METHOD`, or prefix-related globals must call the matching sync helper so when blocks and URI patterns see up-to-date `feat.*` keys. See [Unified condition context](context.md).

`VERSION_INPUT` is captured once at the end of `__init_args__` (after `__init_args_post`) via `__feat_capture_version_input__` when the feature has a `version` option. It holds the user's channel/spec input and is not rewritten during `__resolve_input_version__`.

### PM version vs upstream version

Upstream version resolution (`feat.version`) and PM install pinning (`feat.pm_version`) are separate:

- **Upstream** (`github_release`, `npm`, `sidecar`, …) resolves the user's spec for artifacts and method `when` blocks. Runs before `METHOD=auto` selection.
- **PM** (`feat.pm_version`) is derived after method resolution for `method-package` / `method-upstream-package` manifests. Channel specs (`stable`/`latest`) produce an empty PM spec (unversioned distro install); numeric semver prefixes are passed to ospkg for distro resolution; registry dist-tags use the resolved semver when available. `git_ref` and unresolvable opaque specs yield an empty PM spec (unversioned).

Use `{feat.pm_version}` in OS package manifest `version:` fields — not `{feat.version}` or `{feat.version_input}` (except channel patterns in upstream-package repo URLs). See `__feat_pm_version_spec__` in the install template.

```bash
__install_init_post() {
  # VERSION and METHOD are resolved here; PREFIX is set
  logging__info "Installing ${METHOD} method for version ${VERSION} at ${PREFIX}"
}
```

### `__install_run_pre` / `__install_run_post`

Run before/after the method dispatcher, wrapping all method-specific logic.

When a feature fully overrides `__install_run__` (e.g. `setup-user`), call `__dep_install_option_bound__` once at the top so boolean option-bound manifests still install. Do not call `__dep_install_option__` for options already covered by trigger specs.

### `__install_run_<method>_pre` / `__install_run_<method>_post`

Run before/after a specific method. Use `_pre` to set data variables:

```bash
# Override the binary download URL dynamically
__install_run_binary_pre() {
  # Set BINARY_ASSET_URI directly (overrides the metadata asset_uri).
  local arch
  arch="$(ctx__get plat.machine_release)"
  case "$(os__platform)" in
    alpine) BINARY_ASSET_URI="https://example.com/tool-${VERSION}-linux-musl-${arch}.tar.gz" ;;
    *)      BINARY_ASSET_URI="https://example.com/tool-${VERSION}-linux-${arch}.tar.gz" ;;
  esac
  # You may also set BINARY_SIDECAR_URI (checksum file) or BINARY_SHA256 here.
}
```

```bash
# Run after binary installation — do further configuration
__install_run_binary_post() {
  tool init --system
}
```

### `__install_run_source_build <src_dir>` — custom source build

Override the entire build step for `METHOD=source`. Receives the extracted source directory as `$1`. Use when `build_system: autotools/make` is insufficient.

```bash
__install_run_source_build() {
  local src_dir="$1"
  make -C "${src_dir}" \
    USE_LIBPCRE2=YesPlease \
    INSTALL_SYMLINKS=1 \
    prefix="${_RESOLVED_PREFIX}" \
    install
}
```

Use `${_RESOLVED_PREFIX}` — the resolved, writable install path — in build and install hooks, **not** the raw `PREFIX` option (which may be an array with root/non-root/platform variants).

### `__install_run_script_run <script_path>` — custom script invocation

Override how the installer script is called. Receives the fetched script path as `$1`.

```bash
__install_run_script_run() {
  local script_path="$1"
  bash "${script_path}" --prefix="${PREFIX}" --yes
}
```

### `__configure_user <username>` — per-user configuration

Called for each resolved user by `__feat_do_configure_users__`. Declare `_options.configure_users: true` in `metadata.yaml` to:

1. Auto-inject the four user-resolution options (`add_current_user`, `add_remote_user`, `add_container_user`, `add_users`) so the user controls which accounts are configured.
2. Auto-call `__feat_do_configure_users__` at the end of `__install_finish__` and in the `if_exists=skip` branch — no manual hook needed.

Just implement `__configure_user`:

```bash
__configure_user() {
  local username="$1"
  local home
  home="$(users__home "${username}")"
  # Write per-user config
  users__write_file "${username}" "${home}/.config/tool/config.toml" "$(cat "${_FEAT_FILES_DIR}/config.toml")"
  # Or add shell init snippet
  shell__add_block "${username}" "tool-init" "eval \"\$(tool init shell)\""
}
```

`_FEAT_CONFIGURE_USERS` (array of resolved usernames) is set by `__feat_do_configure_users__` before `__install_finish_post` runs, so any additional per-user logic in that hook can use it directly.

**Who gets configured** is controlled by the four injected options: `add_current_user` (default: true), `add_remote_user` (default: true), `add_container_user` (default: true), and `add_users` (extra explicit usernames).

### `__detect_existing__` — probe for existing installation

Called when `IF_EXISTS` is set. Sets `_FEAT_EXISTING_PATH` (path to existing binary, or `""`) and optionally `_FEAT_EXISTING_METHOD` (how it was installed):

```bash
__detect_existing__() {
  _FEAT_EXISTING_PATH="$(command -v tool 2>/dev/null || true)"
  # _FEAT_EXISTING_METHOD is auto-detected when empty (checks ospkg, npm, prefix, etc.)
}
```

The auto-implementation (`__detect_existing_path__` + `__detect_existing_method__`) handles common cases — only override when the tool isn't on PATH or requires non-standard detection.

### `__installed_version <path>` — read installed version

Called during update checks to compare installed vs requested version. Auto-impl runs `"${path}" "${VERSION_FLAG}"` and extracts the version via `ver__extract_version`. Override when the version output is non-standard:

```bash
__installed_version() {
  local path="$1"
  "${path}" version --json 2>/dev/null | jq -r '.version'
}
```

### `__get_completion_content__ <shell>` — custom completion generation

Called by `__install_shell_completions__` when neither `shell_completions_cmd` nor `shell_completions_files` covers a requested shell. Return non-zero to skip that shell.

```bash
__get_completion_content__() {
  local shell="$1"
  case "${shell}" in
    bash) tool completion bash ;;
    zsh)  tool completion zsh ;;
    *)    return 1 ;;   # skip unsupported shells
  esac
}
```

The auto-implementation handles this when `_options.completions.subcmd` is declared in metadata.

### Other lifecycle hooks

Every template function `foo()` runs an optional `__foo_pre` on entry and `__foo_post` on exit, so you can hook **any** stage of the lifecycle — for example `__resolve_input_prefixes_post` (compute sibling directories once the prefix is resolved), `__install_run_source_pre` / `__install_run_source_post`, or `__detect_existing_path_post`. The full, authoritative list is in the contract comment at the end of `features/install.tmpl.bash`.

Uninstall / reinstall / update flows can also be customized:

- `__uninstall_run__` — full override of how the tool is removed.
- `__uninstall_run_prefix_post`, `__uninstall_finish_post` — clean up feature-specific artifacts.
- `__prefix_activation_snippet <shell>`, `__prefix_discovery_snippet__ <shell>` — emit custom activation / PATH-discovery snippets per shell.

---

## Data Variable Overrides

Set these in `_pre` hooks to control method behavior without overriding the full function:

| Variable | Type | Set in hook | Effect |
|----------|------|-------------|--------|
| `BINARY_ASSET_URI` | string | `__install_run_binary_pre` | Override the binary download URL |
| `BINARY_SIDECAR_URI` | string | `__install_run_binary_pre` | Override the checksum/sidecar URL |
| `BINARY_SHA256` | string | `__install_run_binary_pre` | Provide a pre-computed SHA256 (skips sidecar lookup) |
| `_FEAT_INSTALL_SCRIPT_ARGS` | array | `__install_run_script_pre` | Extra args to installer script |
| `_FEAT_CARGO_COMMAND` | array | `__install_run_cargo_pre` | Override cargo command (e.g., `(cargo binstall --no-confirm)`) |
| `_FEAT_CARGO_INSTALL_ARGS` | array | `__install_run_cargo_pre` | Extra args to cargo install |

---

## Contract Globals (Read-Only in Hooks)

Set by the framework; read-only in user hooks unless noted:

| Variable | Set by | Meaning |
|----------|--------|---------|
| `_FEAT_EXISTING_PATH` | `__detect_existing__` | Path to existing binary, or `""` |
| `_FEAT_EXISTING_METHOD` | `__detect_existing__` | How it was installed, or `""` |
| `_FEAT_INSTALLED_VER` | `__feat_check_version_match__` | Installed version string |
| `_FEAT_RESOLVED_TAG` | `__resolve_input_version__` | Full VCS tag (e.g. `v1.7.1`); settable by `__resolve_version` via `declare -g` |
| `_FEAT_RESOLVED_GIT_SHA` | `__resolve_input_version__` | Git SHA for `git_ref` resolution |
| `_FEAT_CONFIGURE_USERS` | `__feat_do_configure_users__` | Array of resolved usernames |

---

## Sourcing the Library

Library modules are sourced via `lib/__init__.bash` before any hook runs — all `lib/` functions are available in `install.bash` without any explicit `source` call.

To source a specific module in isolation (e.g. in tests):

```bash
source "${_FEAT_DIR}/lib/os.bash"
```

See {doc}`lib` for the full API reference.

---

## Build-Dependency Cleanup and Concurrency

Features often install transient OS packages needed only while building (compilers, headers, `curl`, `git`). These are installed with `ospkg__install_tracked <sub-id> <pkg>...` (or `ospkg__run --build-group <id>`), which records them in a per-invocation sidecar and marks them removable via PM-native mechanisms (`apt-mark auto`, `pacman --asdeps`, apk virtual groups, …). At `__exit__`, unless `KEEP_BUILD_DEPS=true`, the framework removes them with `ospkg__cleanup_all_build_groups` and purges the PM cache with `ospkg__clean` (unless `KEEP_CACHE=true`).

The removal step mutates **machine-global** package state (`apt-get --purge autoremove`, `dnf autoremove`, `pacman -Rns`, `apk del`, plus the global auto/dep mark snapshot and PM cache). Two coordination layers make this safe when multiple installers touch the same machine.

### 1. SYSSET session co-ownership (frozen public contract)

An external orchestrator (`syspkg-installer`) may run several features as one **session** so a build dep pulled in by feature A is not reaped while feature B still needs it. The contract is a set of environment variables plus one coordinator function, and must not change:

| Name | Role |
|------|------|
| `_SYSSET_BUILD_CONTEXT` | Context prefix for group IDs (`feature::<id>`, `install-bash`); set by the template. |
| `_SYSSET_SESSION_TRACK_DIR` | Shared directory where each child mirrors its tracked packages. When set, children **skip their own** `__exit__` build-dep cleanup. |
| `_SYSSET_INITIAL_SNAPSHOT` | Baseline package list (`ospkg__take_initial_snapshot`); pre-existing packages are never cleaned. |
| `ospkg__cleanup_session_build_groups <install-bash-keep>` | Called once by the orchestrator at session end. Applies **keep-wins** across all co-owners (any co-owner with `keep_build_deps: true`, read from `_OPT_OF`, protects the package) and removes only packages no co-owner keeps. |

### 2. The `.ospkg-live` registry (concurrency-safe last-out)

Independent, possibly concurrent invocations (devcontainer entrypoints run in parallel with lifecycle hooks; same-stage hooks run under `Promise.allSettled`) are coordinated by a machine-visible **live registry**, co-located with the guarded state:

- **Location** — system PMs: `$(dirname "$_FEAT_SHARE_DIR_ROOT")/.ospkg-live` (the namespace parent, shared by all features); brew: `$(dirname "$_FEAT_SHARE_DIR_NONROOT")/.ospkg-live`. All registry filesystem ops for system PMs go through `users__run_privileged` (the same channel tracked installs already require); brew is user-owned and runs direct. Tests override the root verbatim with `_OSPKG__REGISTRY_ROOT`.
- **Layout** — `registrants/<pid>.<token>` (one per live invocation; `token` is the process start time, guarding PID reuse), `groups/<context>::<sub-id>` (co-ownership sidecars promoted from the temp session root, with `.keep` and, for apk, `.apkvirts`), and `.global_auto_before` (the shared auto/dep-mark snapshot). A portable `mutex/` directory (`mkdir`-atomic, with stale takeover by PID liveness or a 900 s backstop) guards registration and the last-out critical section — never the installs themselves, so parallelism is preserved.
- **Last-out semantics** — each invocation registers lazily at its first tracked install; the first registrant takes the global-auto snapshot. At cleanup an invocation deregisters, prunes dead registrants, and:
  - if any **live** registrant remains, it **parks** — skipping the autoremove, global-auto restore, `ospkg__clean`, and bootstrap-bash removal so it cannot reap a sibling's in-use dep;
  - if it is the **last out**, it unions all `groups/` sidecars, applies per-group `.keep` keep-wins, removes the survivors via the normal per-PM path, restores the global-auto state, and clears the registry.

  `ospkg__is_last_out` reports the decision; the template gates `ospkg__clean` and bootstrap-bash removal on it. A live SYSSET session participates as **one** registrant, so a session and a concurrent bare invocation cannot reap each other's deps.
- **Degradation** — a nonroot-without-sudo invocation cannot do tracked installs at all, so the registry no-ops and cleanup falls back to the exact single-invocation behavior. The same byte-compatible fallback applies when the registry is otherwise unavailable.

---

## Decision Guide: What to Write

| Feature characteristic | What to write in `install.bash` |
|------------------------|----------------------------------|
| GitHub binary release, standard URL pattern | Nothing — declare `_options.method.binary.asset_uri` in metadata |
| GitHub binary release, OS-specific URL | `__install_run_binary_pre` to set `BINARY_ASSET_URI` |
| OS package manager | Nothing — declare `_options.method.package` and `_dependencies.run.method-package` (generates `ospkg_manifest_method_package_run`) |
| Multiple methods, auto-select by platform | Nothing when `when` blocks are sufficient; otherwise `__resolve_method` |
| Custom version lookup (not GitHub/npm/cargo) | `__resolve_version` |
| Pre-install OS packages not in `_dependencies` | `__install_pre` with `ospkg__install` |
| Post-install configuration (system-wide) | `__install_run_<method>_post` or `__install_post` |
| Per-user dotfiles / shell config | `_options.configure_users: true` in metadata + `__configure_user` in `install.bash` |
| Build from source, standard `./configure` + `make` | Nothing — declare `_options.method.source.build_system: autotools` |
| Build from source, bare `make` plus copy built binary | Nothing — declare `_options.method.source.build_system: make` and `_options.method.source.install_bins` |
| Build from source, framework auto-build plus exported env vars | Nothing — declare `_options.method.source.build_env` |
| Build from source, custom build logic | `__install_run_source_build <src_dir>` |
| Handle existing installations (`if_exists`) | `__detect_existing__` (if tool not on PATH) |
| Shell completions, standard subcommand | Nothing — declare `_options.completions.subcmd` in metadata |
| Shell completions, custom generation | `__get_completion_content__ <shell>` |
