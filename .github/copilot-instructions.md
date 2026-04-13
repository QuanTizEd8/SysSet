# SysSet — System Setup

A collection of system setup scripts that declaratively install tools and configure environments.
Designed for use as both [devcontainer features](https://containers.dev/implementors/features/) published to GHCR,
and as scripts for general Linux and macOS system setup.

## Critical: Generated Files — Never Edit Directly

These files are **auto-generated** and **git-ignored**.
Any edits made to them are overwritten on the next sync run:

| Generated path | Actual source |
|---|---|
| `src/*/install.sh` | `bootstrap.sh` (repo root) |
| `src/**/scripts/_lib/` | `lib/` (repo root) |

Regenerate with: `bash sync-lib.sh`

A lefthook pre-commit hook runs `sync-lib.sh` automatically when `lib/` files or `bootstrap.sh` change.

## Repository Layout

```
src/<feature>/
  devcontainer-feature.json     Metadata, options, lifecycle commands
  scripts/install.sh            Main installer (bash ≥4.0)
  scripts/_lib/                 ← generated; never edit
  dependencies/base.yaml         ospkg manifest: OS packages pre-installed
  files/                        Static files copied into the container (optional)
  install.sh                    ← generated; never edit

lib/                            Shared bash library (canonical source)
  logging.sh  os.sh  ospkg.sh  net.sh  git.sh  shell.sh

test/<feature>/
  scenarios.json                devcontainer-cli test definitions
  <scenario>.sh                 Per-scenario assertion scripts
  <scenario>/                   Build context for that scenario (only when needed)
    Dockerfile                  Only when extra image instructions are needed
    <other files>               Any files needed at build time

test/unit/
  *.bats                        bats unit tests — one file per lib/ module
  helpers/
    common.bash                 reload_lib() helper and bats library loading
    stubs.bash                  create_fake_bin() / prepend_fake_bin_path()
  setup_suite.bash              bash ≥4 guard (auto-discovered by bats)
  bats/                         ← git submodules; never edit
    bats-core/  bats-support/  bats-assert/  bats-file/

bootstrap.sh                    Ensures bash exists, then exec's scripts/install.sh
sync-lib.sh                     Distributes lib/ and bootstrap.sh into every feature
lefthook.yml                    Pre-commit: sync-lib, shfmt format-check, shellcheck lint
Makefile                        Developer targets: format, format-check, lint, sync
.editorconfig                   shfmt style config (2-space, case-indent, etc.)
.shellcheckrc                   shellcheck defaults (shell=bash, external-sources=true)
```

Features without a `dependencies/base.yaml`: `install-os-pkg` (it IS the package installer), `setup-shim`.

## Key Commands

| Task | Command |
|---|---|
| Sync generated files | `bash sync-lib.sh` |
| Verify generated files up to date | `bash sync-lib.sh --check` |
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

| Module | Key API |
|---|---|
| `logging.sh` | `logging__setup` · `logging__cleanup` |
| `os.sh` | `os__require_root` · `os__kernel` · `os__arch` · `os__id` · `os__id_like` · `os__platform` · `os__font_dir` |
| `ospkg.sh` | `ospkg__detect` · `ospkg__install <pkg>...` · `ospkg__update` · `ospkg__clean` · `ospkg__run [--manifest <f>] [--check_installed] [--no_clean] [--no_update] [--dry_run]` |
| `net.sh` | `net__fetch_url_stdout <url>` · `net__fetch_url_file <url> <dest>` · `net__fetch_with_retry <n> <cmd...>` |
| `git.sh` | `git__clone --url <url> --dir <dir> [--branch <branch>]` |
| `shell.sh` | `shell__detect_bashrc` · `shell__detect_zshdir` · `shell__resolve_home <user>` · `shell__resolve_omz_theme` · `shell__plugin_names_from_slugs <csv>` · `shell__write_block` · `shell__remove_block` · `shell__export_path` · `shell__export_env` |
| `github.sh` | `github__fetch_release_json <owner/repo> [--tag <tag>] [--dest <file>]` · `github__latest_tag <owner/repo>` · `github__release_tags <owner/repo> [--per_page <n>]` · `github__release_asset_urls <owner/repo> [--tag <tag>] [--filter <ere>]` |
| `checksum.sh` | `checksum__verify_sha256 <file> <expected_hash>` · `checksum__verify_sha256_sidecar <file> <sha256_file>` |
| `users.sh` | `users__resolve_list` · `users__set_login_shell <shell_path> <username>...` |

`ospkg.sh` internally sources `os.sh` and `net.sh`, so sourcing `ospkg.sh` first is sufficient for most features. Source `github.sh`, `checksum.sh`, `shell.sh`, `git.sh`, and `users.sh` explicitly when needed.

## Code Style

All shell scripts are formatted with **shfmt** and linted with **shellcheck**.

- Style is defined in `.editorconfig`: 2-space indent, `switch_case_indent = true`, `function_next_line = false` (brace on same line), `space_redirects = true`.
- `.shellcheckrc` sets `shell=bash` and `external-sources=true` globally.
- Pre-commit hook checks formatting and lints staged files (no-op when tools absent from PATH).
- CI (`lint.yaml`) enforces both strictly on every push and PR.
- Run `make format` to auto-format; `make lint` to lint.
- `*.bats` files use `shell_variant = bats` in `.editorconfig` and are formatted by shfmt.
- `--apply-ignore` excludes generated `_lib/` copies and `install.sh` stubs automatically.

## CI

Three workflow files form the pipeline:

- **`cicd.yaml`** — Orchestrator. Defines all event triggers (push, tag, PR, manual). Runs a `detect` job that computes changed-file flags, then calls `ci.yaml` (reusable CI) and conditionally `cd.yaml` (reusable CD) for releases.
- **`ci.yaml`** — Reusable CI. All lint, validation, unit, feature, and dist test jobs. Also callable standalone via `workflow_dispatch`.
- **`cd.yaml`** — Reusable CD. Publishes features to GHCR and creates a GitHub Release. Callable standalone via `workflow_dispatch` with a `tag` input.

`detect` in `cicd.yaml` maps changed paths to specific jobs:

| Changed path | Jobs triggered |
|---|---|
| `*.sh`, `*.bash`, `*.bats` | `lint` |
| `src/**/devcontainer-feature.json` | `validate` |
| `lib/**`, `test/unit/**` | `unit-native`, `unit-linux` |
| `src/<f>/` or `test/<f>/` | `test-features` (matrix), `test-macos` if macOS scenarios exist |
| `install-os-pkg` in changed list | `test-os-pkg` (6-distro matrix) |
| `get.sh`, `sysset.sh`, `build-artifacts.sh`, `src/**`, `lib/**`, `test/dist/**` | `test-dist-*` |

On `workflow_dispatch` or `v*` tag push, all jobs run. CD runs only when `is_release=true` AND CI passes.

## Dev Container

`.devcontainer/devcontainer.json` uses `mcr.microsoft.com/devcontainers/javascript-node:1-20-bookworm` with docker-in-docker.
The `_src → ../src` symlink allows the devcontainer CLI (which only looks inside `.devcontainer/`) to find features during local development.

## Further Reading

- `docs/dev-guide/writing-features.md` — feature anatomy, options, scripts, full library reference
- `docs/dev-guide/testing.md` — test structure, writing scenarios, running locally
- `docs/dev-guide/repo-structure.md` — annotated directory tree, sync mechanism
- `docs/dev-guide/publishing.md` — versioning, release, GHCR, containers.dev index
