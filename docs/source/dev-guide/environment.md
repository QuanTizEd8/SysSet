# Development Environment

## Dev Container

The project ships a fully-configured Dev Container at `.devcontainer/.dev/`. Opening the repository in this container gives you every tool needed for development, testing, and documentation — with consistent versions across machines.

**Supporting tools:** [VS Code Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers), [GitHub Codespaces](https://docs.github.com/en/codespaces), or any [spec-compliant client](https://containers.dev/supporting) that adheres to the [Development Container Specification](https://containers.dev/implementors/spec/).

### What's Installed

The dev container is based on **`ubuntu:24.04`** and runs as the non-root user **`devfeats-dev`**. It provisions its own toolchain using DevFeats' features — built from the local `src/` via the `.devcontainer/.src` symlink — plus upstream Docker-in-Docker. The authoritative list (and any version pins) lives in [`.devcontainer/.dev/devcontainer.json`](https://github.com/|{{github_user}}|/|{{github_repo}}|/blob/main/.devcontainer/.dev/devcontainer.json); at the time of writing it installs:

| Category | Tools |
|----------|-------|
| User & shell | `setup-user`, `install-bash`, `install-zsh`, `setup-shell` |
| Git & CLI | `install-git`, `install-gh`, `install-jq`, `install-yq`, `install-just` |
| Shell tooling | `install-shfmt`, `install-shellcheck` |
| Python / envs | `install-miniforge`, `install-pixi` |
| Node | `install-nvm` |
| Packaging / OCI | `install-devcontainer-cli`, `install-oras` |
| Git hooks | `install-lefthook` |
| OS packages | `install-os-pkg-bundle` (bundled CLI tools) |
| AI tooling | `install-claude`, `install-codex`, `install-copilot` |
| CI infra | Docker-in-Docker (upstream `devcontainers/features/docker-in-docker`) |

A few tools are version-pinned in the devcontainer definition (e.g. `install-just`, `install-shellcheck`, `install-shfmt`); consult that file for the current pins rather than relying on this table.

### Post-Start Setup

Three commands run automatically on every container start (`postStartCommand` in `.devcontainer/.dev/devcontainer.json`):

```bash
git submodule update --init --recursive   # init BATS test framework submodules
pixi install --all                        # install all pixi environments
just sync-src                             # generate src/ from features/ + lib/
```

These are idempotent — safe to re-run at any time. Running on every start ensures the environment is always consistent after container restarts.

### VS Code Customizations

The dev container configures VS Code automatically:

- **Extensions:** Bash IDE, EditorConfig, YAML support, Even Better TOML, Python (Pylance), Ruff, Docker, Markdown, Claude Code, PDF viewer, Copilot, Copilot Chat
- **YAML schema:** `features/metadata.schema.json` is registered for `features/*/metadata.yaml` files, enabling validation and autocompletion in the editor
- **JSON schema:** `devcontainer-feature.json` schema is registered for generated feature output files
- **Search/watcher excludes:** `.git/`, `__pycache__/`, `.pixi/`, `miniforge3/`, `*.egg-info/` are excluded to keep VS Code responsive
- **Docker credential helper disabled:** `dev.containers.dockerCredentialHelper` is set to `false` (see below)

### Docker-in-Docker

The dev container includes [Docker-in-Docker](https://github.com/devcontainers/features/tree/main/src/docker-in-docker): a Moby/Docker daemon runs **inside** the container, separate from the host. Feature tests and local workflows use this daemon via `docker run` / `docker build` (for example, `just test-feats` in standalone mode).

By default, VS Code and Cursor Dev Containers inject a host credential bridge into `~/.docker/config.json`:

```json
{ "credsStore": "dev-containers-<uuid>" }
```

That helper talks to the IDE over IPC (`REMOTE_CONTAINERS_IPC`) and a temporary script under `/tmp`. It works in the IDE-attached terminal, but breaks in agent shells, background jobs, SSH, and after `/tmp` cleanup — producing errors like `error getting credentials` or `Cannot find module '/tmp/vscode-remote-containers-....js'` when pulling images.

Host credential forwarding is also a poor fit for Docker-in-Docker: the inner daemon should authenticate on its own, not proxy the host's Docker login. The dev container therefore disables the bridge explicitly:

```json
"dev.containers.dockerCredentialHelper": false
```

This is the [official VS Code setting](https://github.com/microsoft/vscode-remote-release/issues/7982) for projects that manage registry auth inside the container.

**Pulling public images** (Debian, Ubuntu, etc.) works without any extra setup.

**Private registries** (for example GHCR) require a login inside the container against the inner daemon, for example:

```bash
echo "$GITHUB_TOKEN" | docker login ghcr.io -u USERNAME --password-stdin
```

After changing `.devcontainer/.dev/devcontainer.json`, rebuild the container so the setting takes effect and any stale `credsStore` entry is not re-injected.

**Already in a running container?** You do not need a full rebuild. Run:

```bash
bash .dev/scripts/devcontainer/strip-docker-credential-helper.sh
```

That removes a stale `dev-containers-*` `credsStore` immediately. A **Reload Window** or reconnect is enough for `postAttachCommand` (which runs the same script) to keep it clean on future attaches — no image rebuild required.

## Rebuilding the Container

When `.devcontainer/.dev/devcontainer.json` or the feature definitions it uses change, rebuild the container via VS Code's **Dev Containers: Rebuild Container** command or from Codespaces settings.

The CI devcontainer image is a pre-built multi-arch (amd64/arm64) image published to GHCR and used as the CI execution environment. See {doc}`/dev-guide/devops/ci` for how and when it is rebuilt.
