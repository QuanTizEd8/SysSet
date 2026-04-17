# SysSet

**Declarative system setup — as devcontainer features or standalone installers**

SysSet is a collection of idempotent shell installers that configure Linux and
macOS environments. Every feature ships as both a
[Dev Container feature](https://containers.dev/features) published to GHCR and
a self-contained tarball you can run on any machine directly.

---

## Features

::::{grid} 2
:gutter: 3

:::{grid-item-card} install-shell
:link: ref/install-shell
:link-type: doc
Zsh/Bash · Oh My Zsh · Oh My Bash · Starship prompt
:::

:::{grid-item-card} install-fonts
:link: ref/install-fonts
:link-type: doc
Nerd Fonts, P10k fonts, arbitrary download URLs
:::

:::{grid-item-card} install-os-pkg
:link: ref/install-os-pkg
:link-type: doc
Cross-platform OS package install from a YAML manifest
:::

:::{grid-item-card} install-podman
:link: ref/install-podman
:link-type: doc
Rootless Podman with user-namespace config
:::

:::{grid-item-card} install-homebrew
:link: ref/install-homebrew
:link-type: doc
Homebrew on macOS and Linux
:::

:::{grid-item-card} install-pixi
:link: ref/install-pixi/installation
:link-type: doc
Pixi package manager (conda + PyPI)
:::

:::{grid-item-card} install-node
:link: ref/install-node/installation
:link-type: doc
Node.js and npm
:::

:::{grid-item-card} install-gh
:link: ref/install-gh/installation
:link-type: doc
GitHub CLI (`gh`)
:::

:::{grid-item-card} install-git
:link: ref/install-git/installation
:link-type: doc
Git — package or from source
:::

:::{grid-item-card} setup-user
:link: ref/setup-user
:link-type: doc
Create / configure a user account with sudo
:::

:::{grid-item-card} setup-shim
:link: ref/setup-shim
:link-type: doc
Shell shims: `code`, `devcontainer-info`, `systemctl`
:::

::::

---

