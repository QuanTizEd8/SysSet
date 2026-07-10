# Operations

## Feature Discoverability

By default, packages pushed to GHCR are **private**. Private packages incur
storage costs and are not visible to consumers who do not have credentials.
To stay within the free tier and allow anyone to use a feature, mark each
package as public:

1. Navigate to the package settings URL:
   ```
   https://github.com/users/|{{github_user}}|/packages/container/devfeats%2F<feature-id>/settings
   ```
   For example, for `setup-shell`:
   ```
   https://github.com/users/|{{github_user}}|/packages/container/devfeats%2Fsetup-shell/settings
   ```
2. Under **Danger Zone**, set the visibility to **Public**.

This must be done once per feature after its first publication.

---

## Feature Findability

To make features discoverable in tools such as VS Code Dev Containers and
GitHub Codespaces, submit a PR to the
[devcontainers/devcontainers.github.io](https://github.com/devcontainers/devcontainers.github.io)
repository to add an entry to the
[`_data/collection-index.yml`](https://github.com/devcontainers/devcontainers.github.io/blob/gh-pages/_data/collection-index.yml)
file.

The index entry registers the feature collection namespace
(`ghcr.io/|{{github_user}}|/devfeats`) so that supporting tools can surface all
features from this repository in their dev container creation UI.

---

## Feature Accessibility

To allow users to readily try out features, the repository's `.devcontainer/` directory includes a set of "try-<feature-id>" demo containers that showcase each feature in a curated environment. These containers are referenced in the documentation and linked from the feature catalog. Users can open these containers in GitHub Codespaces or VS Code Dev Containers to interactively explore the features without needing to set up their own devcontainer.json.


## Private Features

If a feature is kept private in GHCR, consumers using GitHub Codespaces must
grant the token additional permissions, because Codespaces uses repo-scoped
tokens that do not automatically include package read access.

Add a `customizations.codespaces.repositories` block to the consuming
`devcontainer.json`:

```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-shell:0": {}
  },
  "customizations": {
    "codespaces": {
      "repositories": {
        "|{{github_user}}|/devfeats": {
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
For more information, see [GitHub Container Registry — managing package visibility](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility).
