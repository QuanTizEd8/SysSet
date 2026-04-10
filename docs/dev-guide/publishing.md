# Publishing Features

This guide covers how to version, publish, and make features discoverable
once they are ready for release.

---

## Contents

- [Publishing Features](#publishing-features)
  - [Contents](#contents)
  - [Versioning](#versioning)
  - [Publishing via GitHub Actions](#publishing-via-github-actions)
    - [Required repository settings](#required-repository-settings)
    - [Trigger the release workflow](#trigger-the-release-workflow)
  - [Making GHCR packages public](#making-ghcr-packages-public)
  - [Adding features to the containers.dev index](#adding-features-to-the-containersdev-index)
  - [Using private features in Codespaces](#using-private-features-in-codespaces)
  - [References](#references)

---

## Versioning

Each feature is versioned independently via the `"version"` field in its
`devcontainer-feature.json`. Versions follow [semver](https://semver.org):

```jsonc
{
  "id": "install-shell",
  "version": "0.1.0",
  ...
}
```

When making a change:

- **Patch** (`0.1.x`) — bug fixes and minor corrections with no behaviour change.
- **Minor** (`0.x.0`) — new options or capabilities, backwards-compatible.
- **Major** (`x.0.0`) — breaking changes to option names, defaults, or behaviour.

A published feature is usually pinned by major version in consumers' `devcontainer.json`:

```jsonc
"ghcr.io/quantized8/sysset/install-shell:0": {}
```

The `:0` tag always resolves to the latest `0.x.y` release.

---

## Publishing via GitHub Actions

Features are published automatically to [GitHub Container Registry (GHCR)](https://ghcr.io)
by the `.github/workflows/release.yaml` workflow. The workflow:

1. Runs `bash sync-lib.sh` to ensure every feature has up-to-date `_lib/`
   copies and `install.sh` before packaging.
2. Calls [`devcontainers/action`](https://github.com/devcontainers/action)
   with `publish-features: "true"` and `base-path-to-features: "./src"`.
3. For each feature whose `version` in `devcontainer-feature.json` has not
   yet been published as a GHCR tag, the action pushes the OCI artefact to
   `ghcr.io/quantized8/sysset/<feature-id>:<major>`, `:<major.minor>`, and
   `:<major.minor.patch>`.
4. Generates per-feature `README.md` documentation and opens a pull request
   to commit it.

> The workflow is `workflow_dispatch` only — it never runs automatically on
> push or PR. Trigger it manually when you are ready to cut a release.

### Required repository settings

In **Settings → Actions → General → Workflow permissions**:

- Enable **"Allow GitHub Actions to create and approve pull requests"** — this
  allows the action to open the documentation PR automatically.
- Grant the workflow **read and write permissions** so it can push OCI
  artefacts to GHCR.

### Trigger the release workflow

```bash
gh workflow run "Release dev container features & Generate Documentation"
```

Or open the **Actions** tab in GitHub, select the workflow, and click
**Run workflow**.

---

## Making GHCR packages public

By default, packages pushed to GHCR are **private**. Private packages incur
storage costs and are not visible to consumers who do not have credentials.
To stay within the free tier and allow anyone to use a feature, mark each
package as public:

1. Navigate to the package settings URL:
   ```
   https://github.com/users/quantized8/packages/container/sysset%2F<feature-id>/settings
   ```
   For example, for `install-shell`:
   ```
   https://github.com/users/quantized8/packages/container/sysset%2Finstall-shell/settings
   ```
2. Under **Danger Zone**, set the visibility to **Public**.

This must be done once per feature after its first publication.

---

## Adding features to the containers.dev index

To make features discoverable in tools such as VS Code Dev Containers and
GitHub Codespaces, submit a PR to the
[devcontainers/devcontainers.github.io](https://github.com/devcontainers/devcontainers.github.io)
repository to add an entry to the
[`_data/collection-index.yml`](https://github.com/devcontainers/devcontainers.github.io/blob/gh-pages/_data/collection-index.yml)
file.

The index entry registers the feature collection namespace
(`ghcr.io/quantized8/sysset`) so that supporting tools can surface all
features from this repository in their dev container creation UI.

---

## Using private features in Codespaces

If a feature is kept private in GHCR, consumers using GitHub Codespaces must
grant the token additional permissions, because Codespaces uses repo-scoped
tokens that do not automatically include package read access.

Add a `customizations.codespaces.repositories` block to the consuming
`devcontainer.json`:

```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/quantized8/sysset/install-shell:0": {}
  },
  "customizations": {
    "codespaces": {
      "repositories": {
        "quantized8/sysset": {
          "permissions": {
            "packages": "read",
            "contents": "read"
          }
        }
      }
    }
  }
}
```

Most other implementing tools (e.g. VS Code Dev Containers, the devcontainer
CLI) use a broadly-scoped token and work without this configuration.

---

## References

- [Dev Containers — Feature distribution specification](https://containers.dev/implementors/features-distribution/)
- [devcontainers/action — GitHub Action for publishing](https://github.com/devcontainers/action)
- [containers.dev — public features index](https://containers.dev/features)
- [devcontainers/devcontainers.github.io — collection-index.yml](https://github.com/devcontainers/devcontainers.github.io/blob/gh-pages/_data/collection-index.yml)
- [Dev Containers — Feature versioning](https://containers.dev/implementors/features/#versioning)
- [GitHub Container Registry — managing package visibility](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility)
