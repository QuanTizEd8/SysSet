# Technical Details

## Releases

Features are packaged as self-contained tarballs, versioned according to Semantic Versioning, and released as immutable artifacts to both [GitHub Container Registry](https://github.com/|{{github_user}}|?tab=packages&repo_name=|{{github_repo}}|) (GHCR) and [GitHub Releases](https://github.com/|{{github_user}}|/|{{github_repo}}|/releases). Both distribution channels pull from the same source and have identical content on every release.

Every feature is released under its own version, with a dedicated Git tag, GitHub release, and OCI tags for the major, minor, and patch versions (and a rolling `latest` tag):

- **Git tag:** `<feature-id>/<version>` (e.g. `install-pixi/1.2.3`)
- **GitHub release:** per-tag, with a single asset `devfeats-<feature-id>.tar.gz` (e.g. `devfeats-install-pixi.tar.gz`). The version is carried by the release tag and download URL, **not** the filename.
- **OCI tags:** `ghcr.io/|{{github_user}}|/|{{github_repo}}|/<feature-id>:<version>`, where `<version>` can be `latest` (e.g. `ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-pixi:latest`), `<major>` (e.g. `ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-pixi:1`), `<major>.<minor>` (e.g. `ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-pixi:1.2`), or `<major>.<minor>.<patch>` (e.g. `ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-pixi:1.2.3`).

### Release Artifacts

Feature tarballs follow a consistent structure:

```text
devfeats-<feature-id>.tar.gz
├── devcontainer-feature.json
├── install.sh
├── install.bash
├── lib/
└── files/
```
- [`devcontainer-feature.json`](https://containers.dev/implementors/features/#devcontainer-feature-json-properties) is the metadata file consumed by dev container tooling, defining the feature's identifiers, options, dependencies, and container-specific configuration.
- [`install.sh`](https://containers.dev/implementors/features/#invoking-installsh) is the main entry point for the installer. It is a POSIX sh script that is identical for all features. Its sole purpose is to bootstrap the main `install.bash` installer by ensuring a compatible version (≥ 4.4) of bash is available before executing it. This indirection allows the installer to use modern bash features while maintaining compatibility with environments where only older shells are available by default (e.g. Alpine Linux with busybox sh).
- `install.bash` is the main installer script that performs the installation logic.
- `lib/` contains the installer's internal library code (a collection of sourceable bash files), which is shared across all features and handles common tasks such as networking, API interactions, package management, and more.
- `files/` contains any static files the installer needs to copy to the system (e.g. shell snippets, configuration templates, helper scripts).

## Dev Container Specific Configurations

Some feature configurations are only defined in the `devcontainer-feature.json` file, meant to be consumed by dev container tooling and not the installer itself. These are mostly container-specific configurations such as mounts, security privileges, lifecycle hooks, and customizations for dev container supporting tools such as VS Code and GitHub Codespaces. Features that have any of these configurations document them on their reference page. They include:


### Lifecycle Hooks

These are commands that run at specific points in the container lifecycle, such as on container creation (`postCreateCommand`) or start (`postStartCommand`). They are useful for features that need to perform setup steps that cannot be done at build time (e.g. because they depend on runtime information or need access to workspace files).


### Feature Dependencies

Features can declare soft and hard dependencies on other features in their `devcontainer-feature.json` file, using the `installsAfter` and `dependsOn` properties, respectively. These properties are only consumed by dev container tooling to determine installation order; the features' install script does not read them or enforce them in any way. The order is determined by a **round-based topological sort** over a combined dependency graph:

1. **Hard edges** — from each feature's `dependsOn` in its generated `devcontainer-feature.json`. A feature cannot run until every hard dependency has completed.
2. **Soft edges** — from each feature's `installsAfter`. Honored whenever possible, but dropped if they would create a cycle.
3. **Priority** — `overrideFeatureInstallOrder` in the manifest. Earlier entries get higher priority *within the same round*; this is a tie-break, **not** an override of true dependency edges.
