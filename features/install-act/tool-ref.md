# Feature Reference

`act` is an open-source command-line tool that allows developers to run [GitHub Actions](https://github.com/features/actions) workflows locally, without needing to push changes to a remote repository. It reads workflow files from `.github/workflows/`, uses the Docker Engine API to pull or build container images defined in those workflows, and executes the workflow steps in containers on the local machine. Its primary use cases are fast feedback during workflow development (avoiding the commit/push/debug cycle) and acting as a local task runner (replacing `Makefile`-style workflows with standard GitHub Actions workflows).[^readme][^docs-intro]

- **Homepage**: <https://nektosact.com/>
- **Source Code**: <https://github.com/nektos/act>
- **Documentation**: <https://nektosact.com/>
- **Latest Release**: 0.2.89 (as of 2026-07-02)

## Tool Architecture

`act` is a single, self-contained CLI binary written in [Go](https://go.dev/) (with `CGO_ENABLED=0`, producing a fully statically linked executable).[^goreleaser] It does not depend on any interpreted runtime (e.g., JVM, Node.js, Python) to function.[^goreleaser][^go-mod]

The tool is **standalone** — it does not have a client-server architecture and does not require a running daemon or background service. It communicates with a container runtime via the [Docker Engine API](https://docs.docker.com/engine/api/).[^docs-install] The container runtime (Docker Engine or any Docker Engine API-compatible host) must be available at a socket address specified by the `DOCKER_HOST` environment variable (defaults to the local Docker daemon socket).[^docs-custom-engine]

When executed, `act` performs the following operations:[^readme]

1. Reads and parses GitHub Actions workflow files from `.github/workflows/`.
2. Resolves the set of actions and their dependency graph.
3. Pulls or builds the necessary Docker images (using images like `catthehacker/ubuntu:act-latest` for `ubuntu-latest` runners, or custom images specified by the user).[^docs-runners]
4. Executes each workflow step in an ephemeral Docker container, with environment variables and filesystem configured to match GitHub's hosted runner environment.

`act` is built using Go's standard toolchain and [goreleaser](https://goreleaser.com/) for release automation.[^goreleaser] The module uses `go 1.25.0` as of the latest release.[^go-mod]

## Installation Methods

`act` can be installed via a wide variety of methods: a convenience bash script that downloads pre-built binaries, manual download from GitHub Releases, building from source with the Go toolchain, or through several operating system package managers.[^docs-install] The Bash script method is the most portable and is the primary method used by the feature.

### Bash Script (Binary Download)

The `install.sh` bash script downloads the correct pre-compiled binary and SHA256 checksums from the [GitHub Releases page](https://github.com/nektos/act/releases) and extracts it to a user-specified directory.[^docs-install][^install-sh]

#### Supported Platforms

Based on the goreleaser configuration and the install script's `get_binaries()` function, pre-built binaries are available for the following platforms:[^goreleaser][^install-sh-get-binaries]

- **Linux**: `amd64` (x86_64), `arm64` (aarch64), `i386` (x86), `armv6`, `armv7`
- **macOS**: `amd64` (x86_64), `arm64` (Apple Silicon), `i386`
- **Windows**: `amd64` (x86_64), `arm64`, `i386` (x86), `armv7`

The binaries are statically linked, so they do not require any platform-specific system libraries to execute.[^goreleaser]

> **Note**: The goreleaser configuration also lists `riscv64` in `goarch`, but the install script (`install.sh`) does not currently handle `linux/riscv64` — it would fall through to the unsupported-platform error handler.[^install-sh-get-binaries][^goreleaser]

#### Dependencies

##### Common Dependencies

- **curl** or **wget**: Required to download the binary and checksum files.[^install-sh]
- **Docker Engine**: Required at runtime to execute workflows in containers. `act` communicates with Docker via the Docker Engine API.[^docs-install] If Docker is not available, `act` can still run jobs that use `-self-hosted` runners directly on the host system (e.g., `act -P macos-latest=-self-hosted`), but this is limited to supported host platforms.[^docs-runners]

##### Platform-Specific Dependencies

- **Linux**: Standard POSIX tools (`tar`, `install`). Docker Engine must be installed separately.
- **macOS**: Standard POSIX tools. Docker Desktop for Mac must be installed separately.
- **Windows**: Only supported via the Bash script if a Unix-like environment (e.g., Git Bash, WSL) is available; otherwise, use Chocolatey, Scoop, or WinGet.

#### Installation Steps

The `install.sh` script performs the following steps:[^install-sh]

1. **Parse arguments**: Supports `-b <bindir>` for installation directory, `-d` for debug logging, `-f` for force install (skip version checks), and an optional tag argument.[^install-sh-parse-args]
2. **Determine platform**: Uses `uname -s` and `uname -m` to detect the operating system and CPU architecture, converting them to Go-style OS/ARCH values (e.g., `linux`/`amd64`).[^install-sh-uname]
3. **Get binaries**: Calls `get_binaries()` which validates the platform and sets the binary name (always `act`).
4. **Resolve version**: If no tag is specified, fetches the latest release tag from GitHub's Releases API. Otherwise, validates the specified tag exists.[^install-sh-tag]
5. **Check installed version**: If `act` is already installed and `-f` is not specified, compares the installed version with the target version and skips installation if they match.[^install-sh-check-version]
6. **Construct download URLs**: Builds the archive name using the pattern `act_<OS>_<ARCH>.tar.gz` (or `.zip` for Windows) and constructs the download URL: `https://github.com/nektos/act/releases/download/<TAG>/<ARCHIVE>`.[^install-sh-urls]
7. **Download and verify**: Downloads the archive and the `checksums.txt` file, then verifies the archive's SHA256 hash against the checksum file.[^install-sh-verify]
8. **Extract and install**: Extracts the archive to a temporary directory using `tar` (or `unzip` on Windows), then copies the `act` binary to the specified bindir using `install -d` and `install` (or the Windows equivalent).[^install-sh-extract]

The recommended command for a system-wide installation is:[^docs-install]

```shell
curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
```

To install a specific version:

```shell
curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash -s -- v0.2.64
```

To install to a custom directory (e.g., user-local `~/.local/bin`):

```shell
curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/nektos/act/master/install.sh | bash -s -- -b ~/.local/bin
```

#### Installation Verification

After installation, verify the binary is correctly installed and functional:[^docs-install]

```shell
act --version
```

Expected output format: `act version 0.2.89` (version number matching the installed release).

The SHA256 checksum of the downloaded archive is verified against the `checksums.txt` file from the same release before extraction, ensuring integrity.[^install-sh-verify] There is no GPG signature verification.

The install script also performs a version check if `act` is already in PATH: it extracts the version via `act --version | cut -d' ' -f3` and compares it with the target version. If they match and `-f` (force) is not set, the script exits early without re-downloading.[^install-sh-check-version]

#### Configuration Options

##### Version Selection

The install script accepts an optional positional argument specifying a tag (e.g., `v0.2.64`). If omitted, it defaults to the latest release.[^install-sh] Tags correspond to GitHub Releases at `https://github.com/nektos/act/releases`.

Version can also be selected by using package managers that support version pinning (e.g., Homebrew: `brew install act@<version>`, although `act` currently only has one version in Homebrew).

##### Installation Path

The installation directory can be specified with the `-b` flag. Default: `./bin` (relative to the current working directory).[^install-sh-parse-args] For system-wide installation, the recommended usage is `sudo bash install.sh` which installs to the default `./bin` — but typical practice is to pipe to `sudo bash` without `-b`, which also defaults to `./bin` in the current directory (when executing via curl pipe, the default `./bin` is relative to the invoking user's home, so `sudo` is used to write to a privileged location). The recommended approach for system-wide installation without explicit `-b` is:

```shell
sudo bash install.sh -b /usr/local/bin
```

Or simply piping to `sudo bash` places the binary in `/root/bin` when run via `sudo`, which may not be in PATH. It is recommended to always explicitly specify `-b /usr/local/bin` for system-wide installation.

##### User Targeting

- **System-wide**: Run the script with `sudo` and install to a system directory (e.g., `/usr/local/bin`).
- **User-local**: Run without `sudo` and install to a user-writable directory (e.g., `~/.local/bin` or `~/bin`). Ensure the target directory is in PATH.

##### Required Privileges

- **Root/sudo**: Required only if installing to a system-wide directory (e.g., `/usr/local/bin`). The binary itself does not require root privileges to run.
- **User-local installation**: No special privileges needed.

##### Tool-Specific Configurations

`act` supports several configuration mechanisms at runtime:[^docs-usage]

- **`.actrc` file**: A configuration file that `act` reads for default CLI flags. Located by default at `~/.actrc`. Each line should contain a CLI flag as it would be passed on the command line. Example:[^readme-actrc]
  ```
  -P ubuntu-latest=catthehacker/ubuntu:act-latest
  --container-architecture linux/amd64
  ```
- **Environment variables**:
  - `DOCKER_HOST`: Override the Docker Engine API socket. Useful for using a remote Docker host or a different container engine (e.g., `DOCKER_HOST='unix:///var/run/podman/podman.sock'`). Note that podman is not officially supported but may work.[^docs-custom-engine][^docs-install]
  - `ACT_PROGRESS_OUTPUT`: Set to a path where progress output is written (used for programmatic consumption).
  - `ACTIONS_STEP_DEBUG`: Set to `true` to enable step debug logging.
  - `GITHUB_TOKEN`: Sets the GitHub token to use for API requests (e.g., when using actions that need to authenticate to GitHub).
- **CLI flags**: See `act --help` for the full list. Key flags include:
  - `-P, --platform <platform>=<image>`: Specify the Docker image to use for a given runner platform.
  - `-W, --workflows <path>`: Path to workflow files (default `.github/workflows`).
  - `-j, --job <job-id>`: Run only a specific job.
  - `-s, --secret <key>=<value>`: Pass secrets to the workflow.
  - `--env <key>=<value>`: Pass environment variables to the workflow.
  - `--pull <boolean>`: Whether to pull the Docker image before running (default `true`).
  - `--action-offline-mode`: Use action cache without pulling.
  - `--container-options <options>`: Pass additional options to Docker when creating containers.
  - `--artifact-server-path <path>`: Path to store workflow artifacts.

The official documentation provides a full schema and documentation of all options at <https://nektosact.com/usage/schema.html>[^docs-schema]

#### Post-Installation Steps and Cleanup

##### PATH Setup

The installed binary should be placed in a directory that is in the `PATH` environment variable. Common locations:

- **System-wide**: `/usr/local/bin` (typically already in `PATH`).
- **User-local**: `~/.local/bin`, `~/bin`, or `~/.cargo/bin`.

For user-local installations, ensure the chosen directory is in `PATH` by adding to `~/.bashrc`, `~/.zshrc`, or `~/.profile`:

```shell
export PATH="${HOME}/.local/bin:${PATH}"
```

##### Configuration Files

- **`~/.actrc`**: `act` reads this file automatically if it exists. It can contain default CLI options, one per line. This file is not created by the installer and is entirely optional.
- **`.env.act`**: A dotenv file that can be referenced via `act --env-file .env.act` to inject environment variables into workflow runs.

##### Environment Variables

No environment variables need to be set persistently for `act` to work. The `DOCKER_HOST` variable is only needed if connecting to a non-default Docker daemon (e.g., remote host or podman socket).[^docs-custom-engine]

##### Activation Scripts

No activation scripts are required. `act` is a standalone binary that can be invoked directly.

##### Shell Completions

`act` does not ship shell completion files. Completions can be generated using the tool's built-in help system:[^docs-usage]

```shell
act completion bash > /etc/bash_completion.d/act
act completion zsh > "${fpath[1]}/_act"
act completion fish > ~/.config/fish/completions/act.fish
act completion powershell > act.ps1
```

These commands must be run after installation; completion files are not installed automatically.

##### Cleanup

The install script creates a temporary directory with `mktemp -d` for downloading and extracting archives. This directory is removed with `rm -rf "${tmpdir}"` at the end of the `execute()` function.[^install-sh-execute] No cleanup is required by the user.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- **Bash script**: Re-run the install script with the desired tag. The script will detect the existing version via `act --version` and update the binary if the versions differ. Use `-f` to force re-installation even if the same version is already installed.[^install-sh-check-version]
- **Manual download**: Download and extract the desired version's archive to the same installation directory, overwriting the existing binary.
- **Package managers**: Use the package manager's upgrade mechanism (e.g., `brew upgrade act`, `choco upgrade act-cli`).

##### Uninstallation

- **Bash script installation**: Remove the `act` binary from the installation directory:
  ```shell
  rm /usr/local/bin/act
  ```
- **Package managers**: Use the package manager's uninstall command (e.g., `brew uninstall act`, `choco uninstall act-cli`, `scoop uninstall act`).
- **Configuration files**: `~/.actrc` and any `.env.act` files are not removed by uninstallation and must be deleted manually if desired.

##### Idempotency

The Bash install script is idempotent: if the target version is already installed (detected via `act --version`), it exits successfully without re-downloading or re-installing. Use the `-f` flag to force re-installation.[^install-sh-check-version]

#### Details

The `install.sh` script is based on code originally generated by [godownloader](https://github.com/goreleaser/godownloader) (deprecated) and is now maintained directly in the act repository.[^install-sh] Key technical details:

**Version resolution**: When no tag is provided, the script fetches `https://github.com/nektos/act/releases/latest` with an `Accept: application/json` header, then extracts the `tag_name` field from the JSON response using `sed`.[^install-sh]

**Archive naming convention**: Archives follow the pattern `act_<OS>_<ARCH>.tar.gz` (or `.zip` for Windows). For example, `act_Linux_x86_64.tar.gz`. The OS and ARCH names are title-cased (e.g., `Linux`, `Darwin`, `Windows`, `x86_64`, `arm64`).[^install-sh-adjust][^goreleaser-checksum]

**Checksum verification**: The `checksums.txt` file is downloaded from the same release URL, and the SHA256 checksum of the downloaded archive is computed and compared against the expected value. If they do not match, the script fails with an error message.[^install-sh-verify]

**Binary directory creation**: The script uses `install -d "${BINDIR}"` to create the target directory if it does not exist, then copies the binary with `install "${srcdir}/${binexe}" "${BINDIR}/"`, which preserves executable permissions.[^install-sh-execute]

#### Notes and Best Practices

- **Docker requirement**: `act` requires a running Docker daemon (or Docker Engine API-compatible host) to execute workflow steps in containers. In devcontainer environments, the Docker socket must be mounted into the container for `act` to work. Without Docker access, `act` can only run workflows that use `-self-hosted` runners for the host platform.[^docs-install][^docs-runners]
- **Self-hosted runners**: For macOS or Windows jobs, `act` can run them directly on the host system (without Docker) by using `-P <platform>=-self-hosted`. This is useful in environments where Docker is not available or desired.[^docs-runners]
- **Podman compatibility**: `act` supports the Docker Engine API via `DOCKER_HOST`. Podman's socket is compatible with the Docker Engine API, so `export DOCKER_HOST='unix:///var/run/podman/podman.sock'` may work, but it is not officially tested or supported.[^docs-custom-engine][^docs-install]
- **Default runner images**: The default Docker images used by `act` (e.g., `catthehacker/ubuntu:act-latest`) are intentionally minimal and do not contain all tools available in GitHub's hosted runners. For a more complete environment, use `catthehacker/ubuntu:full-latest` (~18GB) or build custom images.[^docs-runners]
- **Security**: Running `curl ... | sudo bash` is a common pattern but carries inherent risks. Review the script before execution, or download and inspect it first:
  ```shell
  curl -LO https://raw.githubusercontent.com/nektos/act/master/install.sh
  less install.sh
  sudo bash install.sh
  ```

### Build from Source

Building `act` from source requires the Go toolchain.[^readme-build]

#### Supported Platforms

All platforms supported by Go. The build has been tested on Linux, macOS, and Windows.

#### Dependencies

- Go toolchain 1.20+ (the project uses `go 1.25.0` as of the latest release).[^go-mod][^readme-build]
- `git` (for cloning the repository and embedding version information).

#### Installation Steps

```shell
git clone https://github.com/nektos/act.git
cd act
make build
```

Or equivalently:

```shell
git clone https://github.com/nektos/act.git
cd act
go build -ldflags "-X main.version=$(git describe --tags --dirty --always | sed -e 's/^v//')" -o dist/local/act main.go
```

To install the binary system-wide:

```shell
make install
```

This copies the binary to `$(PREFIX)/bin/act` (default prefix: `/usr/local`), sets permissions to 755, and prints the version.[^makefile-install]

#### Installation Verification

```shell
./dist/local/act --version
```

#### Version Selection

The version is derived from the Git tag via `git describe --tags --dirty --always`. To build a specific version, check out the corresponding tag before building:

```shell
git checkout v0.2.64
make build
```

#### Required Privileges

- Source build: No special privileges.
- `make install`: Requires write permissions to the prefix directory (default `/usr/local/bin`, needs `sudo`).

#### Notes

Building from source is not the recommended installation method for users; it is primarily useful for development and testing of `act` itself.

### Package Manager Installation

`act` is available through several package managers, providing platform-native installation experiences.[^docs-install] This section provides a brief overview; refer to each package manager's documentation for detailed instructions.

#### Homebrew (Linux/macOS)

```shell
brew install act
```

For the latest unreleased version (requires compiler):
```shell
brew install act --HEAD
```

#### GitHub CLI Extension (Linux/macOS/Windows/FreeBSD)

```shell
gh extension install nektos/gh-act
gh act --version
```

#### Arch Linux (AUR)

```shell
yay -S act
```

#### Chocolatey (Windows)

```shell
choco install act-cli
```

#### COPR (Fedora/RHEL)

```shell
dnf copr enable rubemlrm/act-cli
dnf install act-cli
```

#### MacPorts (macOS)

```shell
sudo port install act
```

#### Nix/NixOS (Linux/macOS)

```shell
nix-env -iA nixpkgs.act
```

Or ephemeral:
```shell
nix-shell -p act
```

#### Scoop (Windows)

```shell
scoop install act
```

#### WinGet (Windows)

```shell
winget install nektos.act
```

## Dev Container Setup

When installing `act` in a development container (devcontainer), the following considerations apply:

1. **Docker socket mount**: `act` requires access to the Docker daemon. The Docker socket must be mounted into the container. In `.devcontainer/devcontainer.json`, this is typically configured with:
   ```json
   {
     "mounts": [
       "source=/var/run/docker.sock,target=/var/run/docker.sock,type=bind"
     ],
     "features": {
       "ghcr.io/devcontainers/features/docker-outside-of-docker:1": {}
     }
   }
   ```
   The `docker-outside-of-docker` feature ensures the Docker CLI is available and properly configured in the container.

2. **act inside a devcontainer**: When running `act` inside a devcontainer, the workflows it executes will run in sibling containers on the host (not nested inside the devcontainer). This is because `/var/run/docker.sock` is mounted from the host.[^issue-dind]

3. **Docker-in-Docker considerations**: If using `act` with actions that themselves use Docker (e.g., `devcontainers/ci`), special handling is required because `act` mounts the workspace from the host filesystem, but the workspace inside the devcontainer's Docker container is at a different path. The `--container-options --privileged` flag and starting a Docker-in-Docker daemon may be necessary.[^issue-dind]

4. **Permissions**: The container user must have permission to access the Docker socket. This is typically handled by the `docker-outside-of-docker` feature, which adds the user to the `docker` group.

5. **.actrc**: A project-level `.actrc` file can be included in the repository to configure default `act` behavior for all developers. For example:
   ```
   -P ubuntu-latest=catthehacker/ubuntu:act-latest
   --artifact-server-path /tmp/act-artifacts
   ```

## Plugins and Extensions

### GitHub Local Actions (VS Code Extension)

A Visual Studio Code extension that provides a graphical interface for running and managing `act` workflows.[^readme]

- **Website**: <https://sanjulaganepola.github.io/github-local-actions-docs/>
- **Description**: Allows users to run and manage `act` workflows directly from VS Code without using the command line.
- **Installation**: Install from the VS Code Marketplace or via `ext install sanjulaganepola.github-local-actions`.

### gh-act (GitHub CLI Extension)

A GitHub CLI extension that wraps `act` for use as a `gh` subcommand.[^gh-act]

- **Source Code**: <https://github.com/nektos/gh-act>
- **Installation**: `gh extension install nektos/gh-act`
- **Usage**: After installing, `act` can be invoked as `gh act` with all the same arguments as the standalone `act` binary.

## References

[^readme]: [nektos/act README – Overview, how it works, building from source](https://github.com/nektos/act/blob/master/README.md)
[^docs-intro]: [Official Documentation – Introduction](https://nektosact.com/introduction.html)
[^docs-install]: [Official Documentation – Installation (prerequisites, all methods)](https://nektosact.com/installation/)
[^docs-usage]: [Official Documentation – Usage Guide](https://nektosact.com/usage/)
[^docs-runners]: [Official Documentation – Runners (default images, alternative images, self-hosted)](https://nektosact.com/usage/runners.html)
[^docs-custom-engine]: [Official Documentation – Custom Container Engine (DOCKER_HOST, podman, SSH)](https://nektosact.com/usage/custom_engine.html)
[^docs-schema]: [Official Documentation – Schema (all CLI options)](https://nektosact.com/usage/schema.html)
[^install-sh]: [Install Script (install.sh) – Full source code](https://github.com/nektos/act/blob/master/install.sh)
[^install-sh-parse-args]: [Install Script – Argument parsing (bindir, debug, force, tag)](https://github.com/nektos/act/blob/master/install.sh#L19-L32)
[^install-sh-get-binaries]: [Install Script – get_binaries() supported platforms](https://github.com/nektos/act/blob/master/install.sh#L46-L64)
[^install-sh-uname]: [Install Script – OS and ARCH detection](https://github.com/nektos/act/blob/master/install.sh#L210-L240)
[^install-sh-tag]: [Install Script – tag_to_version() resolving latest release](https://github.com/nektos/act/blob/master/install.sh#L66-L76)
[^install-sh-check-version]: [Install Script – check_installed_version() idempotency logic](https://github.com/nektos/act/blob/master/install.sh#L103-L120)
[^install-sh-urls]: [Install Script – URL construction for download](https://github.com/nektos/act/blob/master/install.sh#L215-L219)
[^install-sh-verify]: [Install Script – SHA256 checksum verification](https://github.com/nektos/act/blob/master/install.sh#L258-L272)
[^install-sh-extract]: [Install Script – Extraction and installation](https://github.com/nektos/act/blob/master/install.sh#L34-L45)
[^install-sh-execute]: [Install Script – execute() function (download, verify, extract, install, cleanup)](https://github.com/nektos/act/blob/master/install.sh#L34-L45)
[^install-sh-adjust]: [Install Script – adjust_os() and adjust_arch() for archive naming](https://github.com/nektos/act/blob/master/install.sh#L79-L97)
[^goreleaser]: [GoReleaser Configuration – Build matrix, static linking, archive naming](https://github.com/nektos/act/blob/master/.goreleaser.yml)
[^goreleaser-checksum]: [GoReleaser Configuration – Checksum generation](https://github.com/nektos/act/blob/master/.goreleaser.yml#L16)
[^go-mod]: [go.mod – Go module definition with dependencies](https://github.com/nektos/act/blob/master/go.mod)
[^readme-build]: [README – Building from source (Go 1.20+)](https://github.com/nektos/act#manually-building-from-source)
[^makefile-install]: [Makefile – install target (copy binary and set permissions)](https://github.com/nektos/act/blob/master/Makefile#L55-L57)
[^readme-actrc]: [Example .actrc configuration from project-integration docs](https://github.com/happyvertical/sdk/blob/main/.devcontainer/ACT_INTEGRATION.md)
[^issue-dind]: [Issue #2095 – Docker-in-Docker considerations when using act with devcontainers/ci](https://github.com/nektos/act/issues/2095)
[^gh-act]: [nektos/gh-act – GitHub CLI Extension for act](https://github.com/nektos/gh-act)
