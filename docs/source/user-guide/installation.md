# Installation Guide

Features are packaged as self-contained tarballs compliant with the [Dev Container Features Specification](https://containers.dev/implementors/features/), [versioned](versioning.md) according to Semantic Versioning, and [released](technical.md/#releases) as immutable artifacts to both [GitHub Container Registry](https://github.com/|{{github_user}}|?tab=packages&repo_name=|{{github_repo}}|) (GHCR) and [GitHub Releases](https://github.com/|{{github_user}}|/|{{github_repo}}|/releases). They can be downloaded and installed in any POSIX-compliant environment, including physical machines (e.g. to set up a new laptop or update a PC), virtual machines (e.g. to set up a cloud VM such as a GitHub Actions runner), containers (e.g. as a RUN instruction in a Dockerfile or executed inside a running container), and Dev Containers — with the same behavior across all platforms and installation methods.

## Dev Container Installation

Features are published to GHCR under `ghcr.io/|{{github_user}}|/|{{github_repo}}|/<feature-id>`, with tags for major, minor, and patch versions (and a rolling `latest` tag). To install features in a Dev Container, simply add their OCI registry references to the `features` object in your [`devcontainer.json`](https://containers.dev/implementors/json_reference/) file (with optional [version tag](versioning.md) and [options](options.md)). For example:

```jsonc
// devcontainer.json
{
  "features": {

    // latest version (no tag) with default options
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-user": {},

    // latest version ('latest' tag) with overridden options
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-shell:latest": {
      "if_exists_sys": "reinstall"
    },
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-zsh:latest": {
      "set_login_shell": true
    },

    // specific major version with default options
     "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-git:0": {},

    // specific minor version with overridden options
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-gh:0.1": {
      "version": "2.89.0"
    },

    // specific patch version with default options
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-miniforge:0.1.0": {}
  },
  // other properties...
}
```

Features are then downloaded, ordered according to their dependency graph, and installed automatically when the container is built by [VS Code](https://code.visualstudio.com/docs/devcontainers/containers), [GitHub Codespaces](https://docs.github.com/en/codespaces/setting-up-your-project-for-codespaces/adding-a-dev-container-configuration/introduction-to-dev-containers), [Dev Container CLI](https://github.com/devcontainers/cli), or any other [supporting tools](https://containers.dev/supporting).


## Universal Installation

Outside Dev Containers, features can be installed either using SysSet, or directly from their release artifacts.
**Re-runs are idempotent** — installers check for already-done work and skip it, so you can rerun after fixing an environment issue without uninstalling first.


### SysSet Installation

This is the recommended method for installing features outside Dev Containers. [SysSet](https://github.com/repodynamics/sysset) is a Dev Container supporting tool that can install any Dev Container Feature on any compatible platform, with the same behavior as if it were running inside a container. It provides a convenient CLI interface, handles all the plumbing around downloading and invoking features, and correctly handles all Dev Container specific configurations such as dependency resolution, installation order, and lifecycle hooks. It can be used to install features one at a time:

```sh
sysset feat install ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-gh:0.1 --version 2.89.0
```

or even whole environments defined by `devcontainer.json` files:

```sh
sysset env install /path/to/devcontainer.json
```

### Direct Installation

Features can also be installed directly from their release artifacts. This involves:

1. downloading the corresponding asset from GHCR or GitHub Releases,
2. extracting the tarball,
3. executing the included script with the desired feature options,
4. and optionally running the feature's lifecycle hooks and applying other Dev Container specific configurations.

This is effectively the same process as what happens under the hood when a Dev Container supporting tool installs a feature during container build.
For example, the same installation process for the following `devcontainer.json` entry

```jsonc
{
  "features": {
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-gh:0.1.0": {
      "version": "2.89.0"
    }
  }
}
```

can be performed directly on the command line (paste into a terminal and run):

```sh
( # set feature OCI reference
  FEAT_REF=ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-gh:0.1.0
  # create a temporary directory and move into it to perform the installation
  TMP_DIR=$(mktemp -d) && cd "$TMP_DIR"
  # make sure the temporary directory is removed on exit
  set -e && trap 'rm -rf "$TMP_DIR"' EXIT
  # pull the feature content from GHCR and save it to the temporary directory
  oras pull $FEAT_REF
  # extract the single feature tarball file into the temporary directory
  tar -xf *
  # execute the feature's install.sh script with the desired options
  sudo sh install.sh --version 2.89.0 )
```

:::{caution}

In the above example, there are two aspects where the Dev Container experience differs:

1. **Installation order.** Some features are better installed before others (e.g. a feature that sets up a user should generally run before a feature that installs packages for that user). Dev Container features can declare hard and soft dependencies on other features (as [`dependsOn`](https://containers.dev/implementors/features/#dependsOn) and [`installsAfter`](https://containers.dev/implementors/features/#installsAfter) properties in the `devcontainer-feature.json` file), which are used by supporting tools to determine the correct installation order. When installing features one by one, you need to ensure that you install them in the correct order yourself. You can check the documentation of each feature for any hard or soft dependencies it may have.
2. **Dev Container specific configurations.** Dev Container features can declare specific settings in their [`devcontainer-feature.json`](https://containers.dev/implementors/features/#devcontainer-feature-json-properties) metadata file, which are used by supporting tools to configure different aspects of the container (e.g. adding mount points, setting privileges, or running commands at specific points during the container lifecycle). When installing features directly using their `install.sh` script, you are responsible for applying any relevant Dev Container specific configurations yourself. However, this is a minor concern for most features, as the majority of their functionality is implemented in the installer script and does not rely on Dev Container specific configurations. Additionally, most Dev Container specific configurations are irrelevant outside of containers.
:::

While we recommend using SysSet, which handles both of the above concerns, below are the instructions for performing each of the above steps manually if you choose to go with direct installation.

#### Downloading

##### From GHCR

Features are published to GHCR under `ghcr.io/|{{github_user}}|/|{{github_repo}}|/<feature-id>`, with tags for major, minor, and patch versions (and a rolling `latest` tag). To download a feature from GHCR, the best way is to use a networking tool that recognizes the [OCI Artifact Distribution Specification](https://github.com/opencontainers/distribution-spec), such as [`oras`](https://github.com/oras-project/oras). For example:

```sh
# download latest 'install-git'
oras pull ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-git:latest

# download latest 0.1.x version of 'install-miniforge'
oras pull ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-miniforge:0.1

# download 'install-gh' version '0.1.0'
oras pull ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-gh:0.1.0

# download to a directory (default is current directory)
oras pull ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-gh:0.1.0 -o ./install-gh
```

##### From GitHub Releases

Features are published to GitHub Releases under `<base>/<feature-id>/<version>/devfeats-<feature-id>-<version>.tar.gz`, where `<base>` is `https://github.com/|{{github_user}}|/|{{github_repo}}|/releases/download`. To download a feature from GitHub Releases, you can use any networking tool (e.g. `curl` or `wget`) to download the corresponding asset. For example:

```sh
# use curl to download 'install-gh' version '0.1.0' and save as './feature.tgz'
ID=install-gh; VERSION=0.1.0; curl -fsSL \
  https://github.com/|{{github_user}}|/|{{github_repo}}|/releases/download/$ID/$VERSION/devfeats-$ID-$VERSION.tar.gz \
  -o ./feature.tgz

# use wget to download 'install-git' version '0.1.0' and save as 'install-git/feature.tgz'
ID=install-git; VERSION=0.1.0; wget -q \
  https://github.com/|{{github_user}}|/|{{github_repo}}|/releases/download/$ID/$VERSION/devfeats-$ID-$VERSION.tar.gz \
  -O $ID/feature.tgz
```

:::{caution}

GitHub Releases only supports a single tag per release, so you can only download a specific version (e.g. `0.1.0`), while GHCR supports multiple tags per release, allowing you [pin the version](versioning.md) to a specific major (e.g. `0`) or minor version (e.g. `0.1`) or even use the rolling `latest` tag.
:::

#### Extraction

After downloading the feature's tarball, you need to extract it with a tarball extraction tool (e.g. `tar`):

```sh
# extract tarball in current directory into the current directory
tar -xf feature.tgz

# extract tarball in 'install-git/feature.tgz' into 'install-git/' directory
tar -xf install-git/feature.tgz -C install-git/
```

:::{note}

When using `ghcr.io` references with `oras`, you can only specify the output directory with the `-o` flag, since OCI artifacts may contain multiple files. However, Dev Container Features packaged as OCI artifacts always only contain a single tarball file. The naming convention used by the [Dev Container CLI](https://github.com/devcontainers/cli) (which we use for publishing features to GHCR) to create the tarball file is `devcontainer-feature-<feature-id>.tgz`, e.g. `devcontainer-feature-install-gh.tgz`, but this is out of our control and may change in the future. Therefore, we recommend pulling the feature into an empty (temporary) directory, and then extracting the content of the only available file in that directory:

```sh
# assuming you are in the directory containing the pulled artifact
tar -xf *
```
:::

#### Execution

After extracting the tarball, you can use a POSIX-compliant shell (e.g. `sh` or `bash`) to run the included `install.sh` script with the desired options passed as [CLI flags](options.md):

```sh
# assuming you are in the directory containing the extracted content
sudo sh install.sh --version 2.89.0
```

:::{note}

`sudo` is required when a feature writes to system directories (almost all of them do). Dev container tooling already runs feature installs as root; in direct installations you need to supply the privilege yourself.
:::

#### Dev Container Specific Configurations

Configurations only included in the `devcontainer-feature.json` metadata file are `containerEnv`, `privileged`, `init`, `capAdd`, `securityOpt`, `entrypoint`, `customizations`, `mounts`, and the `onCreateCommand`, `updateContentCommand`, `postCreateCommand`, `postStartCommand`, and `postAttachCommand` [lifecycle hooks](https://containers.dev/implementors/features/#lifecycle-hooks). From these, only `containerEnv`, `customizations`, and the lifecycle hooks can be relevant outside of containers. Since these configurations are not included in the installer script, you need to apply them yourself. You can either inspect the `devcontainer-feature.json` file in the extracted directory and apply the corresponding configurations manually, or use a JSON processor (e.g. `jq`) to parse the file and apply the configurations programmatically.

##### Environment Variables

The `containerEnv` property specifies environment variables to set (or override if existing) in the container. It is an object where keys are the names of environment variables and values are their corresponding values. For Dev Container features, they are added during container build by the Dev Container tooling as `ENV` commands in the Dockerfile before the feature is executed. If a feature has any relevant environment variables declared, you can set them in your shell profile, for example:

```sh
# write to system-wide profile (requires sudo)
jq -r '(.containerEnv // empty) | to_entries[] | "export \(.key)=\"\(.value)\""' \
  devcontainer-feature.json | sudo tee /etc/profile.d/devcontainer-feature-env-vars.sh > /dev/null

# or write to user-specific bash profile
jq -r '(.containerEnv // empty) | to_entries[] | "export \(.key)=\"\(.value)\""' \
  devcontainer-feature.json >> ~/.bash_profile
```

##### Lifecycle Hooks

[Lifecycle hooks](https://containers.dev/implementors/json_reference/#lifecycle-scripts) are commands that are executed from the workspace folder at specific points during the container lifecycle. They can be used to perform additional setup or configuration that is not possible to include in the installer script (e.g. because it needs access to the container environment or workspace content). According to the Dev Container Features Specification, each lifecycle hook property can be either:

- a string, which goes through a shell (it needs to be parsed into command and arguments),
- an array of strings, which is passed to the OS for execution without going through a shell (the first element is the command and the rest are arguments),
- or an object containing any number of strings/arrays, which are executed in parallel.

For consistency, |{{project_name}}| features always use the object format for all lifecycle hooks (if any), with keys representing the name of the parallel process, and values (either strings or arrays) representing the command to execute for that process. For example:

```jsonc
{
  "postCreateCommand": {
    "some-shell-command": "echo Hello from postCreate! && echo This goes through a shell, so you can use shell features like && and ||",
    "some-direct-command": ["echo", "Hello from postCreate!"]
  }
}
```

To execute all available lifecycle hooks in the intended order, you can run:

```sh
for hook in onCreateCommand updateContentCommand postCreateCommand postStartCommand postAttachCommand; do
  jq -r --arg hook "$hook" \
    '.[$hook] // empty | to_entries[] | .value | if type == "string" then . else @sh end' \
    devcontainer-feature.json | \
  while IFS= read -r cmd; do eval "$cmd"; done
done
```

You can check the documentation of each feature to see if it has any lifecycle hooks and what they do.

##### Customizations

The `customizations` property is an object where each supporting tool can declare its own custom configurations under a specific key (e.g. `vscode` for VS Code specific customizations). For example, a feature can declare VS Code specific [extensions](https://containers.dev/supporting#visual-studio-code) to be installed in the container:

```jsonc
{
  "customizations": {
    "vscode": {
      "extensions": [
        "ms-python.python",
        "ms-toolsai.jupyter"
      ]
    }
  }
}
```

To install the above extensions, you can use the [VS Code CLI](https://code.visualstudio.com/docs/editor/command-line#_extension-management) to install them directly from the command line:

```sh
jq -r '(.customizations.vscode.extensions // [])[]' devcontainer-feature.json \
  | while IFS= read -r ext; do code --install-extension "$ext"; done
```
