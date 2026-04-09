# Plan: install-miniforge Feature Redesign

## Context
- Feature: `.devcontainer/src/install-miniforge/`
- Key files: `devcontainer-feature.json`, `scripts/install.sh`, `install.sh` (bootstrap), `test/install-miniforge/`
- Sister feature: `install-conda-env` that depends on this one
- Bootstrap `install.sh` delegates to `scripts/install.sh`

## Phase 1: API Redesign

### 1.1 Replace `download` + `install` + `reinstall` → `action` enum
Current: users must set `download: true, install: true` to install. `reinstall` also requires `download: true`. Code behavior mismatches description (says "raises error if exists" but actually skips).

New `action` string option (default: `"install"`):
- `"install"` — download + install; skip silently if conda already present
- `"reinstall"` — download + uninstall existing + install
- `"download_only"` — fetch installer and verify checksum; do not install
- `"none"` — skip all download/install; run post-install steps only

- `devcontainer-feature.json`: remove `download`, `install`, `reinstall`, add `action`
- `scripts/install.sh`: replace ACTION logic in main flow

### 1.2 Rename `activates` → `init_rc_files`
`activates` conflates "add init script to shell config" with "activate env".
New name `init_rc_files` clearly means "shell RC files to add conda initialization to".
`active_env` → rename to `activate_env` and clarify only takes effect when `init_rc_files` is set.

### 1.3 Remove `conda_activation_script_path` + `mamba_activation_script_path` from API
These are Miniforge-internal constants. Extract to top of `scripts/install.sh` as:
```bash
readonly _CONDA_INIT_SCRIPT_RELPATH="etc/profile.d/conda.sh"
readonly _MAMBA_INIT_SCRIPT_RELPATH="etc/profile.d/mamba.sh"
```
If users have a pathological need, they can still override in standalone mode via env-vars.

### 1.4 Rename `no_clean` → `keep_installer`
Positive naming: `keep_installer: false` (default, clean up) vs `no_clean: false`.

### 1.5 Rename `set_permission` → `set_permissions` (plural), group with `user` and `group`
In descriptions, explicitly cross-reference: `user` and `group` only apply when `set_permissions: true`.

### 1.6 Rename `USER` bash variable → `CONDA_USER`
`USER` is a bash built-in; shadowing it is fragile. Use `CONDA_USER` internally.

### 1.7 Stabilize `require_root`
Keep as-is (good escape hatch). Improve description only.

---

## Phase 2: Dual-mode Consistency

### 2.1 Env-var array separator for `init_rc_files`
Keep ` :: ` separator (idiomatic for this codebase). Document clearly in `--help` and `devcontainer-feature.json` description.

### 2.2 Verify CLI ↔ env-var parity
- Add `action` to both CLI arg parser and env-var reader
- Remove removed options from both parsers
- Update `__usage__()` to reflect new API exactly

### 2.3 Bootstrap `install.sh` passes `$@` transparently
Already correct. No changes needed.

---

## Phase 3: Environment Variable Persistence

### 3.1 `containerEnv` — spec limitation, keep hardcoded
`${options.conda_dir}` in `containerEnv` is NOT supported by the devcontainer spec. This is open spec proposal [devcontainers/spec#164](https://github.com/devcontainers/spec/issues/164), in Backlog since Dec 2022 with no implementation. The official `devcontainers/features/conda` feature also hardcodes `/opt/conda` for the same reason.

`containerEnv` injects a Docker `ENV` instruction and is the only mechanism covering ALL shell types (including non-login/non-interactive `docker exec`). Since it cannot be made dynamic, keep it hardcoded to the default `/opt/conda`. Users who set a custom `conda_dir` must add the matching env var to their own `devcontainer.json` via `containerEnv` or `remoteEnv`. Document this prominently.

### 3.2 Write env-var files in the install script (login + PAM session coverage)
When `update_path: true`, add two files alongside the existing `conda_path.sh`:

1. `/etc/profile.d/conda_env.sh` — `export CONDA_DIR="$CONDA_DIR"` — covers login + interactive shells
2. `/etc/environment` — `CONDA_DIR=...` — covers PAM sessions (SSH, sudo, TTY login); use `sed -i` to update if line exists, append otherwise

For non-root installs (CONDA_DIR not under `/opt|/usr|/var`): write `~/.profile` instead of `/etc/` paths.

Coverage matrix:
| Context | Mechanism |
|---|---|
| All shell types (devcontainer, default path) | `containerEnv` hardcoded to `/opt/conda` → Docker `ENV` |
| All shell types (devcontainer, custom path) | User adds `containerEnv`/`remoteEnv` to their devcontainer.json |
| All shell types (standalone, custom path) | User sets `ENV` before `RUN` in their Dockerfile |
| Login / interactive shells | `/etc/profile.d/conda_env.sh` |
| PAM sessions (SSH, sudo, TTY login) | `/etc/environment` |
| Non-login non-interactive (`docker exec`) | Not coverable without `containerEnv` (spec limitation) |

### 3.3 `update_path` semantics expansion
`update_path: true` will now write all three files: `conda_path.sh` (PATH), `conda_env.sh` (CONDA_DIR profile.d), and update `/etc/environment` (CONDA_DIR). No new API surface needed.

---

## Phase 4: Bug Fixes

### 4.1 `install` description mismatches code
Description says "Raises an error if conda is already installed" but code skips. Resolved by Phase 1 (action enum replaces these).

### 4.2 `DOWNLOAD=true` without `INSTALL` exposes partial check path
Currently if `download: true, install: false`, the checksum verify runs if CHECKSUM exists but nothing is installed. The `action: "download_only"` consolidates this cleanly.

---

## Files to Modify

- `.devcontainer/src/install-miniforge/devcontainer-feature.json`
- `.devcontainer/src/install-miniforge/scripts/install.sh`
- `.devcontainer/test/install-miniforge/scenarios.json` (update all option names)
- All `.devcontainer/test/install-miniforge/*.sh` scenario assertion files

## Verification

1. Run `devcontainer features test` for each scenario (or `--skip-autogenerated`)
2. Verify `custom_conda_dir` scenario sets `CONDA_DIR` correctly via `/etc/profile.d/conda_env.sh` + `/etc/environment`
3. Verify `containerEnv` hardcoded `/opt/conda` is still present and correct for default install
4. Standalone: `CONDA_DIR=/custom bash install.sh` sets env-var files correctly
5. Test `action: "none"` runs post-install steps (permissions, rc-file activation) without installing

## Decisions / Scope

- **In scope**: API options redesign, env-var persistence, dual-mode parity, bug fix for description mismatch
- **Out of scope**: Test scenario content rewrites, install-conda-env feature changes
- `interactive` option: kept as-is (valid escape hatch for developers)
- `installer_dir`, `logfile`, `debug`, `miniforge_name`, `miniforge_version`: no changes
