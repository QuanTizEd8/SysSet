# Features

Features are self-contained installers for developer tools and environment configurations. Each feature publishes as a [Dev Container Feature](https://containers.dev/implementors/features/) and can also be installed standalone on any POSIX system.

::::{grid} 1
:gutter: 3

:::{grid-item-card} Quickstart
:class-title: sd-text-center
:link: features/quickstart
:link-type: doc

Feature anatomy, directory layout, the checklist for creating a new feature, and how the sync pipeline assembles `src/`.
:::

:::{grid-item-card} `metadata.yaml`
:class-title: sd-text-center
:link: features/metadata.yaml
:link-type: doc

Full reference for feature metadata: options, dependencies, shared metadata, versioning, and code-generation keys.
:::

:::{grid-item-card} `install.bash`
:class-title: sd-text-center
:link: features/install.bash
:link-type: doc

How the generated installer works: the template, hook functions, dispatch order, and how to add custom logic.
:::

:::{grid-item-card} `install.sh` (Bootstrap)
:class-title: sd-text-center
:link: features/install.sh
:link-type: doc

The POSIX shim that bootstraps bash ≥4.4 and hands off to `install.bash`.
:::

:::{grid-item-card} Shared Library
:class-title: sd-text-center
:link: features/lib
:link-type: doc

The shared bash library available to every feature installer. Read this before writing any logic from scratch.
:::

:::{grid-item-card} Generated `src/`
:class-title: sd-text-center
:link: features/src
:link-type: doc

What `just sync-src` produces, how the sync pipeline works, and what each generated file contains.
:::

:::{grid-item-card} Condition Context
:class-title: sd-text-center
:link: features/context
:link-type: doc

The unified `os.*` / `plat.*` / `feat.*` context registry behind `when` conditions and URI/manifest pattern tokens.
:::

::::
