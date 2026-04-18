# SysSet — System Setup

**SysSet** is a project developing system setup tools (a.k.a features) that must work seamlessly on both macOS and various Linux distributions, both in containers and on bare-metal machines. These tools are distributed as both [**devcontainer features**](https://containers.dev/implementors/features/) (published to GHCR) and **standalone/bundled installers** (published to GitHub Releases). They provide users with a seamless experience for installing and configuring essential software in their environments, with rich configuration options that cater to a wide range of use cases and requirements. These tools must be robust, reliable, consistently designed, and thoroughly tested, with comprehensive documentation.

## Rules and Constraints

- When using conda, use `python` instead of `python3`; since `python3` is aliased to the system Python on some distros.

## Workspace Layout

The workspace is a git repository with following key directories and files:

- `bootstrap.sh`: A thin POSIX-compliant shim that ensures bash is available, then exec's `scripts/install.sh`. This is the canonical source for the install script's entry point, and is copied into each feature's `src/*/install.sh` by `sync-lib.sh`.
- `sync-lib.sh`: Distributes `lib/` and `bootstrap.sh` into every feature.
- `Makefile`: Developer targets: format, format-check, lint, sync.
- `.editorconfig`: shfmt style config (2-space, case-indent, etc.).
- `.shellcheckrc`: shellcheck defaults (shell=bash, external-sources=true).
- `lefthook.yml`: A lefthook pre-commit hook that runs `sync-lib.sh` and `make format` automatically.
- `.local/scratch/`: Git-ignored scratch space for temporary files that is wiped periodically; use it for short-term storage during your work.
- `lib/`: Shared library containing common functions for feature scripts (canonical source); its contents are copied into every feature's `scripts/_lib/` by `sync-lib.sh`, which are then sourced by the feature scripts.
- `src/`: Source code of all features.
  - `src/*/`: Per-feature directory, where `*` is the feature name/ID (e.g. `install-shell`).
    - `src/*/devcontainer-feature.json`: Metadata and option definitions for the feature, consumed by the devcontainer CLI to install the feature into devcontainer images.
    - `src/*/install.sh`: Auto-generated and git-ignored copy of `bootstrap.sh` for each feature; **NEVER EDIT THIS FILE DIRECTLY!** It is overwritten by `sync-lib.sh` on every run.
    - `src/*/scripts/`: Main feature scripts.
      - `src/*/scripts/_lib/`: Auto-generated and git-ignored copies of `lib/` for each feature; **NEVER EDIT THESE FILES DIRECTLY!** They are overwritten by `sync-lib.sh` on every run.
      - `src/*/scripts/install.sh`: Main installer script and entry point for the feature (bash ≥4.0); orchestrates and implement the installation using functionalities in the shared library.
      - `src/*/scripts/*.sh`: Any additional feature-specific helper scripts; sourced by the main installer.
    - `src/*/dependencies/`: Dependency manifests for the feature.
      - `src/*/dependencies/*.yaml`: Feature dependencies, i.e. lists of OS packages required by the feature, represented as platform-aware manifests that are consumed by `lib/ospkg.sh`.
      - `src/*/dependencies/base.yaml`: Manifest for always-required dependencies; all other manifests are optional and only used when specific options are set.
    - `src/*/files/`: Artifacts used by the feature (e.g. config files, templates, static assets) to generate files in the target system; these are copied as-is (or with variable substitution) into the container or target machine, and are not executed directly by the installer.
- `docs/`: Documentation.
  - `docs/dev-guide/`: Developer guide
    - `docs/dev-guide/writing-features.md` — feature anatomy, options, scripts, full library reference
    - `docs/dev-guide/testing.md` — test structure, writing scenarios, running locally
    - `docs/dev-guide/repo-structure.md` — annotated directory tree, sync mechanism
    - `docs/dev-guide/publishing.md` — versioning, release, GHCR, containers.dev index
- `test/`: Test suite for features.
  - `test/dist/`: Tests for the distributed bundled/standalone installers.
  - `test/unit/`: Tests for the shared library (`lib/`).
    - `test/unit/bats/`: Git submodule of Bats testing framework; **NEVER EDIT THESE FILES!**
    - `test/unit/helpers/`: Helper scripts for unit tests.
    - `test/unit/setup_suite.bash`: bash ≥4 guard (auto-discovered by bats)
    - `test/unit/*.bats`: Unit tests for `lib/` modules, organized by module (one file per module, e.g. `os.bats`, `shell.bats`).
  - `test/<feature>/`: One directory per feature, with test scenarios for that feature.
    - `test/<feature>/scenarios.json`: devcontainer-cli test definitions.
    - `test/<feature>/<scenario>.sh`: Per-scenario assertion scripts.
    - `test/<feature>/<scenario>/`: Per-scenario build context (if needed), e.g. Dockerfile or other files needed at build time.

## Key Commands

| Task | Command |
|------|---------|
| Sync auto-generated files | `bash sync-lib.sh` |
| Verify auto-generated files are up to date | `bash sync-lib.sh --check` |
| Format all shell files | `make format` |
| Check formatting (CI-style, no writes) | `make format-check` |
| Lint all shell files | `make lint` |
| Test one feature (scenarios + fail cases) | `bash test/run.sh feature <feature>` |
| Run lib/ unit tests (all) | `make test-unit` |
| Run lib/ unit tests (one module) | `bash test/run-unit.sh --module <name>` (e.g. `os`, `shell`, `ospkg`) |
| Release to GHCR + GitHub Release | Push a `v*` tag, or `workflow_dispatch` on `cicd.yaml` with a `tag` input |
| Publish only (skip tests) | `workflow_dispatch` on `cd.yaml` with a `tag` input |

Always run `bash sync-lib.sh` before running feature tests locally.

## Features

| Feature | Purpose |
|---|---|
| `install-shell` | Zsh/Bash, Oh My Zsh, Oh My Bash, Starship, dotfiles |
| `install-fonts` | Nerd Fonts, P10k fonts, custom font URLs |
| `install-os-pkg` | General-purpose OS package installer from a manifest |
| `install-podman` | Rootless Podman with user namespace config |
| `install-pixi` | Pixi package manager |
| `install-miniforge` | Miniforge (conda/mamba) |
| `install-conda-env` | Conda/mamba environments from files or inline specs |
| `setup-user` | Create/configure a Linux user with sudo |
| `setup-shim` | Shell shims: `code`, `devcontainer-info`, `systemctl` |

## Shared Library (`lib/`)

**Always check `lib/` before implementing something from scratch.** The library covers the most common operations feature scripts need. Prefer calling a lib function over writing inline logic — this keeps scripts shorter, consistent, and testable.

When implementing a new feature or editing an existing one, abstract any reusable logic into `lib/` rather than copy-pasting it across scripts. A function belongs in `lib/` when it is (or could be) called from more than one feature, or when it encapsulates a non-trivial detail that is easy to get wrong (e.g. SHA-256 verification, GitHub API pagination, user deduplication).


## Code Style

All shell scripts are formatted with **shfmt** and linted with **shellcheck**.

- Style is defined in `.editorconfig`: 2-space indent, `switch_case_indent = true`, `function_next_line = false` (brace on same line), `space_redirects = true`.
- `.shellcheckrc` sets `shell=bash` and `external-sources=true` globally.
- Pre-commit hook checks formatting and lints staged files (no-op when tools absent from PATH).
- CI (`lint.yaml`) enforces both strictly on every push and PR.
- Run `make format` to auto-format; `make lint` to lint.
- `*.bats` files use `shell_variant = bats` in `.editorconfig` and are formatted by shfmt.
- `--apply-ignore` excludes generated `_lib/` copies and `install.sh` stubs automatically.




## Key References

- [devcontainer CLI Repository](https://github.com/devcontainers/cli)
- [devcontainer GitHub Organization](https://github.com/devcontainers)
