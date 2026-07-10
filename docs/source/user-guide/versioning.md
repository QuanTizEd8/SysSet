# Versioning

Features are versioned **independently** using a [semantic versioning](https://semver.org/) scheme, i.e. `<major>.<minor>.<patch>`, e.g. `1.2.3`. Each feature is first released with the initial version `0.1.0`. For each subsequent release of that feature, its version is bumped according to the nature of the changes:

- **Major** release: If the release contains breaking changes, the major version is incremented and the minor and patch versions are reset to zero: `X.Y.Z` → `(X+1).0.0` (e.g. `1.2.3` → `2.0.0`). Breaking changes are defined as any change that alters the public API and behavior of the feature in a way that is not backwards compatible. Examples include renaming or removing options, changing default values, or modifying the behavior of existing options such that it could cause existing configurations to break or behave differently.
- **Minor** release: Otherwise (no breaking changes), if the release introduces new capabilities or significant improvements to existing functionality in a backwards-compatible manner, the minor version is incremented and the patch version is reset to zero: `X.Y.Z` → `X.(Y+1).0` (e.g. `1.2.3` → `1.3.0`). Backwards-compatible additions include new options with defaults that do not change existing behavior, additional accepted values for existing options, and support for new platforms or environments.
- **Patch** release: Otherwise (no breaking changes or significant new capabilities), if the release includes only backwards-compatible bug fixes, minor corrections, or documentation updates, the patch version is incremented: `X.Y.Z` → `X.Y.(Z+1)` (e.g. `1.2.3` → `1.2.4`). Backwards-compatible bug fixes include corrections to installation scripts, fixes for edge cases that do not alter existing behavior, and improvements to error handling that do not change the public API.


:::{admonition} Feature Version ≠ Tool Version
:class: note dropdown
:name: feature-version-tool-version

Feature versions represent the evolution of the feature's API, functionality, and behavior itself, not the versions of the underlying tools they install. For features that install versioned tools, the tool versions can be specified via feature input options, regardless of the feature's own version.
:::


## Version Pinning

Features can be pinned separately to specific versions at the desired precision level (major, minor, or patch), to balance stability and access to new updates as needed. This is done by appending a version specifier `:<version>` to the feature ID, either in the `devcontainer.json` file for Dev Container Features or on the CLI when invoking the installer:

- **Patch**: `:<major>.<minor>.<patch>` (e.g. `:1.2.3`)
- **Minor**: `:<major>.<minor>` (e.g. `:1.2`)
- **Major**: `:<major>` (e.g. `:1`)
- **Latest**: `:latest` or no specifier (e.g. `:latest`)

:::{admonition} Pinning GitHub Releases
:class: attention dropdown

When [directly downloading from GitHub Releases](installation.md#from-github-releases), you can only download a specific patch version (e.g. `0.1.0`), since GitHub Releases only supports a single tag per release. If you need to pin to a specific minor or major version or use the rolling `latest` tag, and you can only download from GitHub Releases, you can query the GitHub API to get a list of releases and their tags, find the appropriate version that matches your desired specifier, and then download that specific version from its corresponding full tag.
:::

### Patch Version

Pin to a full patch version to ensure that the exact same version of the feature is used every time, providing maximum stability and reproducibility.

:::::{tab-set}

::::{tab-item} Dev Container
```jsonc
{
  // devcontainer.json
  "features": {
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-shell:1.2.3": {}
  }
}
```
::::

::::{tab-item} SysSet
```sh
sysset feat install ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-shell:1.2.3
```
::::

::::{tab-item} GHCR
```sh
oras pull ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-shell:1.2.3
```
::::

::::{tab-item} GitHub Release
```sh
ID=setup-shell; VERSION=1.2.3; curl -fsSL \
  https://github.com/|{{github_user}}|/|{{github_repo}}|/releases/download/$ID/$VERSION/devfeats-$ID.tar.gz
```
::::

:::::


### Minor Version

Pin to a minor version (e.g. `1.2`) to receive all patch updates within that minor release, while still ensuring high stability and reproducibility.

:::::{tab-set}

::::{tab-item} Dev Container
```jsonc
{
  // devcontainer.json
  "features": {
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-shell:1.2": {}
  }
}
```
::::

::::{tab-item} SysSet
```sh
sysset feat install ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-shell:1.2
```
::::

::::{tab-item} GHCR
```sh
oras pull ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-shell:1.2
```
::::

:::::


### Major Version

Pin to a major version (e.g. `1`) to receive all minor and patch updates within that major release, while avoiding any breaking changes. This is a good option if you want to stay up-to-date with new options and improvements while maintaining a stable API.

:::::{tab-set}

::::{tab-item} Dev Container
```jsonc
{
  // devcontainer.json
  "features": {
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-shell:1": {}
  }
}
```
::::

::::{tab-item} SysSet
```sh
sysset feat install ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-shell:1
```
::::

::::{tab-item} GHCR
```sh
oras pull ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-shell:1
```
::::

:::::

### Latest Version

No version specifier (or `latest`) means the feature will always resolve to the latest available version, regardless of major, minor, or patch. This is not recommended for production use, as it can lead to unexpected breaking changes and instability.

:::::{tab-set}

::::{tab-item} Dev Container
```jsonc
{
  // devcontainer.json
  "features": {
    // with `:latest` tag
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-shell:latest": {},

    // or no tag (same as `:latest`)
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-git": {}
  }
}
```
::::
::::{tab-item} SysSet
```sh
# with `:latest` tag
sysset feat install ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-shell:latest

# or no tag (same as `:latest`)
sysset feat install ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-git
```
::::

::::{tab-item} GHCR
```sh
oras pull ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-shell:latest
```
::::

:::::
