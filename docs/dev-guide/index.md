# Developer Guide

SysSet is a collection of [dev container features](https://containers.dev/implementors/features/)
published to GitHub Container Registry. This guide covers everything needed
to work on the repository — understanding the structure, writing new features,
testing them, and publishing releases.

---

## Prerequisites

- **Docker** — must be running and accessible.
- **Node.js / npm** — required for the devcontainer CLI.
- **devcontainer CLI** — install once:
  ```bash
  npm install -g @devcontainers/cli
  ```
- **shfmt** — bash formatter ([mvdan/sh](https://github.com/mvdan/sh)):
  ```bash
  brew install shfmt
  ```
- **shellcheck** — bash linter:
  ```bash
  brew install shellcheck
  ```
- **Lefthook** — runs `sync-lib.sh`, shfmt, and shellcheck automatically
  on commit:
  ```bash
  brew install lefthook
  lefthook install
  ```

---

## Guide sections

| Section | Description |
|---|---|
| [Repository structure](repo-structure.md) | Directory layout, synced files, code style tooling, dev container setup, CI workflows |
| [Writing features](writing-features.md) | Feature anatomy, bootstrap pattern, argument parsing, shared library reference |
| [Testing](testing.md) | Test framework, scenario scripts, running tests locally and in CI |
| [Publishing](publishing.md) | Versioning, GHCR publication, making packages public, adding to the index |

---

## Shared library quick reference

Every feature's `scripts/install.sh` has access to a shared bash library
(sourced from `scripts/_lib/`, a synced copy of `lib/`):

| Module | Key functions |
|---|---|
| `os.sh` | `os__require_root` |
| `logging.sh` | `logging__setup`, `logging__cleanup` |
| `net.sh` | `net__fetch_url_file`, `net__fetch_url_stdout`, `net__fetch_with_retry` |
| `ospkg.sh` | `ospkg__run`, `ospkg__install`, `ospkg__clean`, `ospkg__detect` |
| `shell.sh` | `shell__detect_bashrc`, `shell__detect_zshdir`, `shell__resolve_home` |
| `git.sh` | `git__clone` |

See [Writing features — Shared library reference](writing-features.md#shared-library-reference)
for the full API.

---

## Feature reference documentation

Detailed per-feature documentation lives under `docs/ref/`:

- [install-os-pkg](../ref/install-os-pkg.md) — cross-distro OS package installer with manifest support
- [install-shell](../ref/install-shell.md) — Bash/Zsh, Oh My Zsh/Bash, Starship, Nerd Fonts
- [install-miniforge](../ref/install-miniforge.md) — Miniforge / conda
- [install-fonts](../ref/install-fonts.md) — Nerd Fonts
- [install-pixi](../ref/install-pixi.md) — Pixi package manager
- [install-podman](../ref/install-podman.md) — Podman container runtime
- [setup-shim](../ref/setup-shim.md) — command shims
- [setup-user](../ref/setup-user.md) — dev container user creation

---

## References

- [Dev Containers — Feature authoring specification](https://containers.dev/implementors/features/)
- [Dev Containers — Feature distribution specification](https://containers.dev/implementors/features-distribution/)
- [devcontainers/cli — npm package](https://www.npmjs.com/package/@devcontainers/cli)
- [devcontainers/action — GitHub Action for CI and publishing](https://github.com/devcontainers/action)
- [containers.dev — public features index](https://containers.dev/features)
- [`dev-container-features-test-lib` — source](https://github.com/devcontainers/cli/blob/main/src/test/dev-container-features-test-lib)
