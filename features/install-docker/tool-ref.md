<!--
This is the Feature Reference Document for Docker Engine installation.
It provides a structured format for documenting the underlying tool that a feature installs or sets up, including its installation methods, supported platforms and platform-specific notes, dependencies, configuration options, limitations, and other important information for implementers, auditors, and maintainers. This document serves as a comprehensive reference for developers, ensuring that they have all the necessary information to understand the tool's installation process and to implement the feature correctly.
When writing the feature reference, be sure to provide clear and detailed information, including exact commands where applicable, and accurately cite all relevant references for the information provided (use footnotes to cite each piece of information). Make sure to stay faithful to the template structure; remove all comments and placeholder text, and replace them with the actual content.
-->
# Feature Reference

Docker Engine is an open-source containerization technology that enables the packaging and running of applications in isolated environments called containers. It consists of a daemon (`dockerd`) that manages containers, images, networks, and volumes, and a client (`docker`) that provides a command-line interface for interacting with the daemon. Docker Engine also includes `containerd` for container lifecycle management, `runc` for running containers according to OCI specifications, and various plugins such as `docker-buildx` for extended build capabilities and `docker-compose-plugin` for defining and running multi-container applications. The Engine is written in Go and runs natively on Linux, with client-only binaries available for macOS and Windows.

- **Homepage**: https://www.docker.com/
- **Source Code**: https://github.com/moby/moby
- **Documentation**: https://docs.docker.com/engine/
- **Latest Release**: 29.6.1 (as of 2026-07-03)[^latest-release]

## Tool Architecture

Docker Engine follows a client-server architecture with the following main components:

- **`dockerd`** (Docker daemon): A long-running background process that manages Docker objects (containers, images, networks, volumes). It listens for Docker API requests via a Unix socket (`/var/run/docker.sock` by default) and/or a TCP port. It is a single Go binary that relies on containerd for container lifecycle operations.

- **`docker`** (Docker CLI): A command-line client that communicates with `dockerd` via the Docker API (REST). It is a separate Go binary from the daemon. It can connect to a local daemon via the Unix socket or to a remote daemon over TCP/TLS.

- **`containerd`**: An industry-standard core container runtime that manages the complete container lifecycle (image transfer, storage, and container execution/ supervision). Docker Engine bundles containerd as `containerd.io`.

- **`runc`**: A lightweight, OCI-compliant runtime for spawning and running containers. It is bundled with containerd.

- **Plugins**: Extended functionality through separate binaries:
  - `docker-buildx` (BuildKit-based builder)
  - `docker-compose-plugin` (v2 compose functionality)
  - `docker-init` (tini init process for containers)

Docker Engine is self-contained and does not require external services to function. It uses Linux kernel features such as cgroups, namespaces, and union filesystems (overlay2). It requires a 64-bit Linux kernel version 3.10 or higher (recommended 4.8+). The daemon binds to a Unix socket owned by `root` by default and uses `iptables`/`nftables` for network isolation. It supports systemd for service management on Linux hosts.[^docs-arch][^docs-install-overview]

## Installation Methods

Docker Engine can be installed on Linux hosts using several methods. Within a Dev Container context (see the Dev Container Setup section), Docker can be set up either as a full Docker-in-Docker (DinD) installation (running a nested daemon) or as a Docker-outside-of-Docker (DooD) installation (connecting to the host's daemon via a forwarded socket). Each method has distinct requirements, advantages, and limitations that are documented in the Dev Container Setup section below.

### OS Package Manager (apt/dnf/yum)

This is the recommended installation method for production environments, as it provides automatic security updates through the system's package management infrastructure.

#### Supported Platforms

- **Debian-based**: Ubuntu, Debian, Raspberry Pi OS (32-bit, formerly Raspbian), and derivatives[^docs-install-ubuntu][^docs-install-debian]
- **RPM-based**: Fedora, CentOS, RHEL, Rocky Linux[^docs-install-fedora][^docs-install-centos][^docs-install-rhel]
- **Architectures**: x86_64/amd64, arm64/aarch64, armhf (32-bit), ppc64le, s390x (varies by distribution)[^docs-install-overview]

#### Dependencies

##### Common Dependencies

- `ca-certificates` (for HTTPS access to repositories)
- `curl` (for downloading GPG keys)
- `gnupg` / `gpg` (for key management on Debian-based systems)
- Linux kernel 3.10+ (recommended 4.8+)
- `iptables` version 1.4+ (or `iptables-nft`)

##### Platform-Specific Dependencies

- **Debian-based**: `apt-transport-https` (for modern TLS support), `software-properties-common` (optional for repo management)
- **RPM-based (dnf)**: `dnf-plugins-core`
- **RPM-based (yum)**: `yum-utils`

#### Installation Steps

**Debian-based (Ubuntu/Debian)**[^docs-install-ubuntu][^docs-install-debian]:

```bash
# 1. Set up Docker's apt repository
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add repository (using OS release codename detection)
# For Ubuntu: use $UBUNTU_CODENAME, for Debian: use $VERSION_CODENAME
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt-get update

# 2. Install Docker packages
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

**RPM-based (Fedora)**[^docs-install-fedora]:

```bash
# 1. Set up Docker's dnf repository
sudo dnf config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo

# 2. Install Docker packages
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 3. Start Docker
sudo systemctl enable --now docker
```

**RPM-based (CentOS)**[^docs-install-centos]:

```bash
# 1. Set up Docker's repository
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# 2. Install Docker packages
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 3. Start Docker
sudo systemctl enable --now docker
```

**RPM-based (RHEL)**[^docs-install-rhel]:

```bash
# 1. Set up Docker's repository (note: uses rhel-specific repo URL)
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo

# 2. Install Docker packages
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 3. Start Docker
sudo systemctl enable --now docker
```

#### Installation Verification

After installation, verify with:
```bash
sudo docker run hello-world
```
Expected output includes a confirmation message from Docker that the installation appears to be working correctly.[^docs-install-ubuntu]

The installed binaries can be verified:
```bash
docker --version               # e.g., Docker version 29.6.1
dockerd --version              # e.g., Docker version 29.6.1
containerd --version           # e.g., containerd 2.x.x
```

#### Configuration Options

##### Version Selection

To install a specific version, first list available versions:

**Debian-based**:
```bash
apt list --all-versions docker-ce
sudo apt-get install -y docker-ce=<VERSION_STRING> docker-ce-cli=<VERSION_STRING> containerd.io docker-buildx-plugin docker-compose-plugin
```

**RPM-based**:
```bash
dnf list docker-ce --showduplicates | sort -r
sudo dnf install docker-ce-<VERSION_STRING> docker-ce-cli-<VERSION_STRING> containerd.io docker-buildx-plugin docker-compose-plugin
```

The version string for Debian-based systems follows the format `5:<docker-version>-1~ubuntu.<release>~<codename>`, while for RPM-based it follows `<epoch>:<docker-version>-1.<distro-suffix>`.[^docs-install-ubuntu][^docs-install-centos]

##### Installation Path

Installation paths are managed by the package manager:
- Binaries: `/usr/bin/docker`, `/usr/bin/dockerd`, `/usr/bin/containerd`
- Configuration: `/etc/docker/daemon.json`
- Data directory: `/var/lib/docker` (configurable via `data-root` in daemon.json)
- Containerd data: `/var/lib/containerd`

##### User Targeting

System-wide only via package managers. User-local installations are possible via Rootless mode (see below).

##### Required Privileges

All package manager installations require `root` or `sudo` privileges. The Docker daemon always runs as `root`.[^docs-postinstall]

##### Tool-Specific Configurations

Docker daemon is configured through `/etc/docker/daemon.json` (JSON format). Key configuration options include[^docs-daemon]:

```json
{
  "data-root": "/var/lib/docker",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "exec-opts": ["native.cgroupdriver=systemd"],
  "iptables": true,
  "ip6tables": false,
  "live-restore": true,
  "default-address-pools": [
    {"base": "192.168.0.0/16", "size": 24}
  ],
  "features": {
    "containerd-snapshotter": true
  },
  "group": "docker"
}
```

The configuration can be validated without restarting:
```bash
sudo dockerd --validate --config-file /etc/docker/daemon.json
```

Some options (debug, log-level, labels, live-restore) can be reloaded with SIGHUP:
```bash
sudo kill -SIGHUP $(pidof dockerd)
```

#### Post-Installation Steps and Cleanup

##### PATH Setup

Docker binaries are installed to standard system paths (`/usr/bin/`), which are already in PATH by default. No additional PATH setup is needed for system-wide installations.

##### Configuration Files

The main configuration file is `/etc/docker/daemon.json`. It is not created by default; the daemon uses built-in defaults if absent.

##### Environment Variables

The following environment variables are commonly used:
- `DOCKER_HOST`: Sets the Docker daemon socket to connect to (e.g., `unix:///var/run/docker.sock`)
- `DOCKER_CONTEXT`: Selects a Docker context
- `DOCKER_CONFIG`: Location of Docker CLI configuration files (default: `~/.docker`)

##### Activation Scripts

No activation scripts are needed for standard installations.

##### Shell Completions

Docker CLI provides shell completions for bash, zsh, and fish. They can be installed by running `docker completion bash` (or `zsh`/`fish`) or from distribution packages (e.g., `bash-completion` on Debian/Ubuntu).[^docs-docker-completion]

##### Cleanup

After installation, clean up the apt cache:
```bash
sudo apt-get clean
rm -rf /var/lib/apt/lists/*
```

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

Upgrade by repeating the installation steps with a newer version string. For package manager installations, use `apt-get install` (Debian) or `dnf install` (RPM) with the desired version. Downgrading requires explicitly specifying an older version via the same commands. Configuration files in `/etc/docker/` are preserved during package upgrades.

##### Uninstallation

**Debian-based**:
```bash
sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
sudo rm -rf /var/lib/docker /var/lib/containerd
sudo rm /etc/apt/sources.list.d/docker.sources /etc/apt/keyrings/docker.asc 2>/dev/null || true
```

**RPM-based**:
```bash
sudo dnf remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
sudo rm -rf /var/lib/docker /var/lib/containerd
```

Note that images, containers, volumes, and networks stored in `/var/lib/docker/` and `/var/lib/containerd/` are not automatically removed when uninstalling Docker packages; they must be removed manually if desired.[^docs-install-ubuntu]

##### Idempotency

Running the package manager installation multiple times is idempotent: it will upgrade packages to the latest (or specified) version if newer packages are available. The repository configuration steps (adding GPG keys and source lists) are designed to be re-run safely; existing files are overwritten. The convenience script (get.docker.com) is NOT idempotent for upgrades and its use for repeated installations is discouraged.[^docs-install-convenience]

#### Details

The official Docker convenience script at `get.docker.com` (source: https://github.com/docker/docker-install) performs the package manager installation steps automatically[^src-installer]. It is not a separate installation method — it detects the Linux distribution and configures the appropriate package repository under the hood. The script performs the following:

1. Detects the Linux distribution and version via `/etc/os-release`
2. Configures the appropriate package repository (apt or rpm) with the correct GPG key
3. Installs the required packages: `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`, `docker-ce-rootless-extras`
4. Supports `--version`, `--channel` (stable/test), `--mirror`, and `--dry-run` flags
5. Optionally starts and enables the Docker systemd service

The script supports Debian-based (Ubuntu, Debian, Raspberry Pi OS) and RPM-based (CentOS, Fedora, RHEL, Rocky) distributions.

#### Notes and Best Practices

- The convenience script (`get.docker.com`) is NOT recommended for production environments; use the package manager method instead.[^docs-install-convenience]
- Docker is licensed under Apache License 2.0, but commercial use in enterprises exceeding 250 employees or $10M annual revenue requires a paid subscription when using Docker Desktop.[^docs-install-overview]
- The Docker daemon opens port 2375 (HTTP) and 2376 (HTTPS) if TCP is enabled; secure appropriately.
- Firewall rules using `ufw` or `firewalld` may be bypassed by published container ports. Docker is only compatible with `iptables-nft` and `iptables-legacy`, not raw `nft`.[^docs-install-ubuntu]
- On Ubuntu 26.04 (Resolute) and newer kernels, prefer `iptables-nft` over `iptables-legacy` for compatibility.
- On RPM-based systems (Fedora, CentOS, RHEL), the Docker service must be explicitly started with `systemctl start docker`.
- On Debian-based systems, the Docker service starts automatically after installation.

### Static Binary Download

Docker provides statically-linked binaries for manual installation on any Linux distribution, useful for testing or air-gapped environments.

#### Supported Platforms

- **Linux**: x86_64/amd64, arm64/aarch64, armhf, ppc64le, s390x[^docs-install-binaries]
- **macOS** (client only): x86_64 (Intel), aarch64 (Apple Silicon)
- **Windows** (daemon + client): x86_64 (Windows Server only)
- Static binaries do NOT support all features of packaged installations.

#### Dependencies

- Linux kernel 3.10+ (64-bit), `iptables` 1.4+, `git` 1.7+, `procps` (for `ps`), XZ Utils 4.9+, proper cgroupfs hierarchy[^docs-install-binaries]
- For rootless: `newuidmap`/`newgidmap` (from `uidmap` package), `/etc/subuid` and `/etc/subgid` configured with subordinate ID ranges

#### Installation Steps

```bash
# 1. Download the static binary archive
#    Available at: https://download.docker.com/linux/static/stable/<ARCH>/
curl -fsSLO https://download.docker.com/linux/static/stable/x86_64/docker-29.6.1.tgz

# 2. Extract (contains: docker, dockerd, containerd, etc.)
tar xzf docker-29.6.1.tgz

# 3. Install binaries to system path
sudo cp docker/* /usr/bin/

# 4. Start the daemon
sudo dockerd &

# 5. Verify
sudo docker run hello-world
```

For client-only installation (useful for DooD setups):
```bash
curl -fsSLO https://download.docker.com/linux/static/stable/x86_64/docker-29.6.1.tgz
tar xzf docker-29.6.1.tgz
sudo cp docker/docker /usr/local/bin/   # Only copy the client binary
rm -rf docker docker-29.6.1.tgz
```

#### Installation Verification

Verify the installation by:
```bash
# Check the installed binary versions
docker --version                   # e.g., Docker version 29.6.1
dockerd --version                  # Only if daemon was installed

# Run a test container (requires running daemon)
sudo docker run hello-world

# Check that the binary is statically linked (no "not a dynamic executable" means static)
file /usr/bin/docker | grep -q "statically linked" && echo "Static binary"

# Verify the daemon is listening on the Docker socket
sudo docker info
```

#### Configuration Options

##### Version Selection

Set the version by modifying the URL. Available versions are listed at https://download.docker.com/linux/static/stable/.

##### Installation Path

Binaries can be placed in any directory on PATH. The standard locations are `/usr/bin/` or `/usr/local/bin/`.

##### User Targeting

System-wide only (requires root to copy to system paths). For user-local installation, place binaries in `~/bin/` and add to PATH.

##### Required Privileges

Copying binaries to system directories and starting the daemon require `root` or `sudo` privileges. Placing binaries in user-local directories (`~/bin/`) does not require root.

##### Tool-Specific Configurations

The same `daemon.json` configuration file at `/etc/docker/daemon.json` is used regardless of installation method. Static binary installations do not include a default config file or systemd service unit, so these must be created manually if needed. The daemon is started directly via `dockerd` with CLI flags instead of systemd.

#### Post-Installation Steps and Cleanup

##### PATH Setup

If binaries were placed in a non-standard location (e.g., `/opt/docker/bin`), add it to PATH:
```bash
export PATH="/opt/docker/bin:$PATH"
```
For persistence, add to `~/.bashrc` or `/etc/profile.d/docker.sh`.

##### Configuration Files

Create `/etc/docker/daemon.json` manually if custom configuration is needed. No config file is provided by default.

##### Environment Variables

Same environment variables as the package manager installation:
- `DOCKER_HOST`: Override the daemon socket location
- `DOCKER_CONFIG`: CLI configuration directory

##### Activation Scripts

No activation scripts are needed. For systemd integration, create a service unit file manually at `/etc/systemd/system/docker.service` with the appropriate `dockerd` command and flags.

##### Shell Completions

Install completions by generating them:
```bash
docker completion bash > /usr/share/bash-completion/completions/docker
```
Or for user-local installation:
```bash
mkdir -p ~/.local/share/bash-completion/completions
docker completion bash > ~/.local/share/bash-completion/completions/docker
```

##### Cleanup

Remove the downloaded archive and temporary extraction directory:
```bash
rm -rf docker-*.tgz docker/
```

#### Changing Versions and Uninstallation

Stop the running daemon, remove the old binaries from the installation directory, and repeat the installation steps with the new version. There is no package manager to track installed files; all files must be removed manually.

#### Idempotency

Not idempotent. Repeated installations will overwrite existing binaries. The daemon must be stopped before upgrading to avoid version mismatches between client and daemon.

#### Notes and Best Practices

- Static binaries are primarily for testing. They lack automatic security updates and may not include all functionality of packaged versions.[^docs-install-binaries]
- The macOS static binary includes only the Docker CLI (no daemon). A separate Docker Engine (via Docker Desktop or a remote daemon) is required to run containers.
- 32-bit static binary archives do not include the Docker daemon.
- For production, prefer the OS package manager method for automatic security updates.

### Rootless Mode Installation

Rootless mode allows running the Docker daemon and containers as a non-root user, mitigating potential vulnerabilities.

#### Supported Platforms

- Linux only (requires user namespaces support in the kernel)
- All distributions supported by the package manager installation
- Also available via standalone script at https://get.docker.com/rootless

#### Dependencies

- `newuidmap` and `newgidmap` (from the `uidmap` package on most distributions)[^docs-rootless]
- `/etc/subuid` and `/etc/subgid` must contain at least 65,536 subordinate UIDs/GIDs for the target user
- `iptables` or `iptables-nft`
- `ip_tables` kernel module (or `SKIP_IPTABLES=1` to skip networking)
- `systemd` --user instance for service management (recommended)
- `XDG_RUNTIME_DIR` must be set and writable
- User namespaces support: `kernel.unprivileged_userns_clone=1` (Debian), `user.max_user_namespaces=28633` (CentOS/RHEL)

#### Installation Steps

**Via package manager** (if Docker packages are already installed rootful):
```bash
# Install rootless extras
sudo apt-get install -y docker-ce-rootless-extras

# Run as non-root user
dockerd-rootless-setuptool.sh install
```

**Via standalone script**[^src-rootless-installer]:
```bash
# Run as non-root user
curl -fsSL https://get.docker.com/rootless | sh
```

The standalone script performs the following:
1. Validates system requirements (kernel, uidmap, iptables, subuid/subgid)
2. Downloads static binaries for Docker and docker-rootless-extras
3. Extracts them to `~/bin/`
4. Creates systemd user service at `~/.config/systemd/user/docker.service`
5. Sets up a Docker context named "rootless"
6. Enables linger for the user via `sudo loginctl enable-linger <user>`

#### Installation Verification

Verify rootless Docker is running:
```bash
# Check that Docker is responding (using rootless context)
docker info

# The output should show "rootless" in the Security Options
docker info | grep -i rootless

# Run a test container
docker run hello-world

# Check the Docker context
docker context ls
# Expected: "rootless" context with a DOCKER_HOST pointing to
# unix:///run/user/<UID>/docker.sock
```

#### Configuration Options

##### Version Selection

For the package-based installation, the rootless extras version matches the installed rootful Docker version. For the standalone script, a specific channel can be selected:
```bash
CHANNEL=test curl -fsSL https://get.docker.com/rootless | sh
```

##### Installation Path

Binaries are installed to `~/bin/` by default. Override with:
```bash
DOCKER_BIN=/custom/path curl -fsSL https://get.docker.com/rootless | sh
```

##### User Targeting

Always user-local. Each non-root user must install rootless Docker independently. The daemon runs under the user's systemd user instance.

##### Required Privileges

The rootless installation script itself does not require root, but certain system prerequisites (installing `uidmap`, configuring `/etc/subuid`, enabling linger) require `sudo` access.

##### Tool-Specific Configurations

Rootless Docker uses `~/.config/docker/daemon.json` (instead of `/etc/docker/daemon.json`) for daemon configuration. The daemon socket is at `unix:///run/user/$UID/docker.sock` (instead of `/var/run/docker.sock`).

#### Post-Installation Steps and Cleanup

##### PATH Setup

Add `~/bin` to PATH (the script alerts about this):
```bash
export PATH=/usr/bin:$HOME/bin:$PATH
```

##### Configuration Files

Rootless Docker uses `~/.config/docker/daemon.json`. The rootless Docker context configuration is stored in `~/.docker/contexts/meta/`.

##### Environment Variables

The following environment variables need to be set persistently (e.g., in `~/.bashrc`):
```bash
export PATH=/usr/bin:$HOME/bin:$PATH
export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock
```

##### Activation Scripts

Enable automatic startup on boot:
```bash
sudo loginctl enable-linger <username>
systemctl --user enable docker
systemctl --user start docker
```

##### Shell Completions

Same as the package manager method; completions are installed to system paths or user-local paths.

##### Cleanup

The standalone script uses a temporary directory (cleaned up automatically via `trap`). No additional cleanup is needed.

#### Changing Versions and Uninstallation

Stop the docker service (`systemctl --user stop docker`), remove the binaries from `~/bin/`, and re-run the installation script. To fully uninstall, also remove `~/.config/systemd/user/docker.service` and the rootless Docker context (`docker context rm rootless`).

#### Idempotency

The installation script detects an existing rootless installation and exits without making changes. To upgrade, the existing binaries must be manually removed first. The script has a `--force` flag (via `FORCE_ROOTLESS_INSTALL=1`) to override protections.

#### Notes and Best Practices

- Rootless mode does NOT use binaries with SETUID bits or file capabilities, except `newuidmap` and `newgidmap`.[^docs-rootless]
- Rootless mode has limitations compared to rootful Docker: it cannot bind to privileged ports (<1024), has limited network capabilities, and some storage drivers (e.g., overlay2) may not work in all configurations.
- If a rootful Docker daemon is already running, disable it before setting up rootless: `sudo systemctl disable --now docker.service docker.socket && sudo rm /var/run/docker.sock`.
- If the rootful socket is still accessible, set `FORCE_ROOTLESS_INSTALL=1` to proceed.

## Dev Container Setup

Setting up Docker in a Dev Container environment presents two distinct patterns, each with fundamentally different approaches, requirements, and trade-offs. This section documents both patterns comprehensively.

### Docker-in-Docker (DinD)

Docker-in-Docker runs a full Docker daemon inside the container, creating a completely isolated Docker environment independent from the host's Docker instance. This is the standard approach when each dev container needs its own isolated Docker daemon.

#### Overview

DinD uses the Moby project's official `hack/dind` wrapper script[^src-dind] for kernel namespace setup (cgroups, mounts, security) combined with a feature-generated init script that installs and manages the nested daemon lifecycle. The Feature installs the Docker CLI, daemon, containerd, and supporting tools inside the container, and provides an init script (`docker-init.sh`) that acts as the container entrypoint to start the nested daemon when the container launches.[^ext-feature-dind][^ext-feature-dind-install]

#### Architecture

The DinD setup consists of:
- **Installed packages**: Docker Engine (`docker-ce` or `moby-engine`), CLI (`docker-ce-cli` or `moby-cli`), containerd, Buildx, Docker Compose. For DinD installations using Docker CE, the packages are held at their installed version with `apt-mark hold` to prevent accidental upgrades that could cause compatibility issues.[^ext-feature-dind-install]
- **Init script** (`/usr/local/share/docker-init.sh`): Acts as the container entrypoint, starting the nested `dockerd` and `containerd` daemons before executing any further commands[^ext-feature-dind-install]
- **Dind wrapper logic**: The init script embeds logic derived from the Moby project's `hack/dind` script[^src-dind] for:
  - AppArmor compatibility (setting `container=docker` environment variable)
  - Security filesystem mounting (`/sys/kernel/security`)
  - Temporary filesystem mounting (`/tmp` as tmpfs)
  - Cgroup v2 nesting support
  - Shared mount propagation
- **Feature-specific startup logic** (from the devcontainers feature implementation[^ext-feature-dind-install], NOT from Moby's `hack/dind`) for:
  - PID file cleanup
  - containerd and dockerd daemon startup
  - iptables alternative configuration (legacy vs nft)
  - containerd erofs snapshotter plugin disabling
  - User command execution

#### Prerequisites and Requirements

- **Privileged mode** is REQUIRED. The container must run with `--privileged` flag (or at minimum `--cap-add SYS_ADMIN --security-opt apparmor=unconfined`) to allow the nested daemon to create cgroups, mount filesystems, and manage iptables.[^ext-feature-dind-docs]
- **Init process** is strongly recommended (`--init` flag or `init: true` in Docker Compose) to enable the tini init process, which properly handles signals and reaps zombie processes.[^ext-feature-dind-docs]
- **Host architecture matching**: The host and container must run on the same chip architecture (e.g., both amd64 or both arm64). Emulated cross-architecture containers are NOT supported for DinD.[^ext-feature-dind-docs]
- **Overlayfs on rootfs**: When the container's root filesystem is an overlayfs mount (common in Kubernetes, GitHub Codespaces, and containerd-backed Docker hosts), dedicated volumes must be mounted for `/var/lib/docker` and `/var/lib/containerd` to prevent overlay-on-overlay mount failures that cause `invalid argument` errors.[^ext-feature-dind-overlayfs]

#### Mount Configuration

Two named volumes are required to persist Docker state and prevent overlay-on-overlay filesystem issues[^ext-feature-dind-install][^ext-feature-dind-overlayfs]:

```json
{
  "mounts": [
    {
      "source": "dind-var-lib-docker-${devcontainerId}",
      "target": "/var/lib/docker",
      "type": "volume"
    },
    {
      "source": "dind-var-lib-containerd-${devcontainerId}",
      "target": "/var/lib/containerd",
      "type": "volume"
    }
  ]
}
```

The `${devcontainerId}` variable ensures each dev container gets isolated state and preserves images/snapshots across rebuilds. These volumes are not automatically removed when the dev container is deleted; manual cleanup with `docker volume rm` is required to reclaim space.

**Why separate volumes are needed**: Without the `/var/lib/containerd` volume mount, containerd's overlayfs snapshotter would write onto the container's overlay rootfs, causing `invalid argument` errors during image pull or container startup with containerd >= 2.3 (which uses erofs snapshotter). The separate volume mounts guarantee non-overlay storage for these critical state directories.[^ext-feature-dind-overlayfs]

#### Container Runtime Configuration

**devcontainer.json** (for image or Dockerfile):
```json
{
  "image": "mcr.microsoft.com/devcontainers/base:noble",
  "runArgs": ["--init", "--privileged"],
  "overrideCommand": false,
  "features": {
    "ghcr.io/devcontainers/features/docker-in-docker:4": {}
  }
}
```

**Docker Compose**:
```yaml
services:
  dev:
    image: mcr.microsoft.com/devcontainers/base:noble
    init: true
    privileged: true
    # ...
```

#### Init Script Details (`docker-init.sh`)

The init script generated by the DinD feature performs the following at container startup[^ext-feature-dind-install]. Steps 1-5 are based on the Moby project's `hack/dind` wrapper[^src-dind]; steps 6-10 are from the feature's own implementation:

1. **Set environment**: Exports `container=docker` for AppArmor detection (from Moby `hack/dind`)
2. **Mount security filesystem**: Mounts `/sys/kernel/security` if available (from Moby `hack/dind`)
3. **Mount /tmp**: Mounts `/tmp` as a writable tmpfs if not already mounted (from Moby `hack/dind`)
4. **Configure cgroup v2 nesting**: If running on cgroup v2, moves processes to an `/init` group and enables controllers in the subtree. This is necessary because writing to `cgroup.subtree_control` fails with EBUSY when processes exist in the root cgroup. (from Moby `hack/dind`)
5. **Set shared mount propagation**: Runs `mount --make-rshared /` (from Moby `hack/dind`)
6. **Clean PID files**: Removes any stale `docker*.pid` and `container*.pid` files from `/run` and `/var/run` (feature-specific)
7. **Start containerd**: Starts containerd with the configuration that disables the erofs snapshotter plugin (feature-specific)
8. **Configure iptables**: Optionally sets the iptables alternative (legacy vs nft) based on runtime detection (feature-specific)
9. **Start dockerd**: Starts the Docker daemon with the appropriate configuration (address pools, DNS auto-detection, ip6tables settings, etc.) (feature-specific)
10. **Execute user command**: Runs the command passed as arguments (typically the container's CMD) (feature-specific)

#### containerd Configuration

The DinD setup generates an initial `/etc/containerd/config.toml` if one does not exist. It disables the `io.containerd.snapshotter.v1.erofs` plugin to prevent failures when the host kernel exposes the erofs filesystem but the distro provides an older version of `erofs-utils` (versions < 1.7, as found on Debian 12 and Ubuntu 22.04). This ensures containerd always uses the overlayfs snapshotter regardless of the distro.[^ext-feature-dind-install]

#### Security Considerations

- **Privileged access**: The container requires privileged access to run a nested Docker daemon. This introduces security implications similar to running Docker directly on the host.
- **AppArmor**: The `container=docker` environment variable is set to ensure AppArmor profiles are properly applied within the DinD context.
- **User namespaces**: Adding the non-root user to the `docker` group grants effective root access within the container (equivalent to Docker's standard security model).

#### Limitations

- **Architecture constraint**: Host and container must run on the same CPU architecture. Cross-platform emulation (e.g., running an amd64 container on an Apple Silicon Mac via Rosetta) is NOT supported for DinD.[^ext-feature-dind-docs]
- **Performance**: Running a nested Docker daemon has overhead compared to using the host's daemon directly.
- **Storage**: All images and containers created within the DinD environment are isolated and not shared with the host's Docker installation. They are lost on container destroy unless persisted volumes are used.
- **Network**: The nested daemon uses its own iptables rules, which may conflict or behave unexpectedly in complex network environments.
- **Zombie processes**: Without `--init`, child processes of the nested daemon may become orphaned and accumulate as zombies.
- **Shared mounts**: Docker bind mounts from within the nested daemon refer to the container's filesystem, not the host's filesystem.

### Docker-outside-of-Docker (DooD)

Docker-outside-of-Docker connects to the host's Docker daemon by bind-mounting the Docker socket into the container. This allows Docker commands run inside the container to be executed against the host's daemon, sharing the host's images, containers, and volumes.

#### Overview

DooD installs only the Docker CLI (and optionally Buildx and Compose) inside the container, without installing a nested Docker daemon. The host's Docker socket is bind-mounted into the container, enabling the `docker` CLI to communicate directly with the host's daemon.[^ext-feature-dood][^ext-feature-dood-install]

#### Architecture

The DooD setup consists of:
- **Installed CLI**: Docker CLI (from `docker-ce-cli` or `moby-cli` packages), optional Buildx and Compose
- **Socket configuration**: The host's Docker socket is mounted into the container at a configurable path (default: `/var/run/docker-host.sock`), and optionally symlinked to `/var/run/docker.sock`
- **Group management**: The feature creates a `docker` group in the container and attempts to match the GID with the socket's group GID
- **socat proxy**: If GID matching is not possible, `socat` is used as a TCP proxy to forward the socket with appropriate permissions

#### Socket Configuration

The feature expects the Docker socket at `/var/run/docker.sock` on the host by default. This must be mounted into the container. The feature provides configurable options for the mount path:

```json
{
  "features": {
    "ghcr.io/devcontainers/features/docker-outside-of-docker:1": {}
  },
  "mounts": [
    {
      "source": "/var/run/docker.sock",
      "target": "/var/run/docker-host.sock",
      "type": "bind"
    }
  ]
}
```

The socket path inside the container is configurable via the `socketPath` option (default: `/var/run/docker-host.sock`). The feature creates a symlink from the configured source path to `/var/run/docker.sock` or forwards via socat.

#### Rootless Docker Support

For rootless host Docker setups, the socket is located at a different path (typically `/run/user/$UID/docker.sock` or `$XDG_RUNTIME_DIR/docker.sock`). The mount must be adjusted accordingly[^ext-feature-dood-docs][^ext-feature-dood-rootless-issue]:

```json
{
  "features": {
    "ghcr.io/devcontainers/features/docker-outside-of-docker:1": {}
  },
  "mounts": [
    {
      "source": "/run/user/1000/docker.sock",
      "target": "/var/run/docker-host.sock",
      "type": "bind"
    }
  ]
}
```

**Important**: With rootless Docker on the host, the socket GID will typically be the user's primary GID (1000), not a dedicated `docker` group. The feature handles this by using socat to proxy the socket when the GID cannot be matched to the container's `docker` group.

#### Group and Permission Management

The feature implements a sophisticated permission management strategy[^ext-feature-dood-install]:

1. Creates the `docker` group in the container if it does not exist
2. Retrieves the GID of the mounted socket using `stat -c '%g'`
3. If the socket GID is non-root and not already assigned to another group, changes the container's `docker` group GID to match
4. If the socket GID is root (0) or the GID is already taken by another group, falls back to using `socat` to create a proxied socket with appropriate permissions for the non-root user
5. Adds the non-root user to the `docker` group

The socat proxy runs as a background process:
```bash
socat UNIX-LISTEN:/var/run/docker.sock,fork,mode=660,user=<username>,backlog=128 \
      UNIX-CONNECT:/var/run/docker-host.sock
```

#### Init Script Details

The init script (`/usr/local/share/docker-init.sh`) handles:
1. Checking the socket permissions and GID
2. Starting the socat proxy if needed
3. Setting up the symlink from the mounted socket to the expected Docker socket location
4. Executing the container's main command

If non-root access is disabled or the user is root, a stub init script is used instead.

#### Bind Mount Resolution with DooD

A critical nuance with DooD is that **bind mounts specified with `docker run -v`** use the host's filesystem paths, not the container's paths. This is because the Docker CLI connects to the host's daemon, which resolves mount paths from its own (the host's) filesystem namespace.[^ext-feature-dood-docs]

To work around this for bind mounts within the dev container:
- Mount the workspace at the same path on both host and container:
  ```json
  {
    "workspaceFolder": "${localWorkspaceFolder}",
    "workspaceMount": "source=${localWorkspaceFolder},target=${localWorkspaceFolder},type=bind"
  }
  ```
- Or use Docker-in-Docker if host-path bind mounts are not suitable.

#### Prerequisites

- The Docker daemon must be running on the host and accessible via the mounted socket.
- The container user must have read/write access to the Docker socket. This is achieved through GID matching or socat proxying.
- For rootless Docker on the host, the socket must be explicitly mounted at the correct path and the user may need `linger` enabled.

#### Security Considerations

- **Root-equivalent access**: Access to the Docker socket grants effective root access to the host. Any user in the `docker` group can execute arbitrary commands on the host.
- **Socket sharing**: The host's daemon is shared across all containers that mount the socket — operations in one container affect the daemon globally.
- **No isolation**: Container builds, image pulls, and resource usage impact the host's Docker daemon.

#### Limitations

- **No daemon isolation**: Unlike DinD, operations in one dev container affect images, containers, and volumes used by other containers or the host.
- **Bind mount path mismatch**: File paths in Docker run commands with bind mounts must reference host paths, not container paths.
- **Requires host Docker**: The feature depends entirely on the host's Docker daemon being available and accessible.
- **Different Docker versions**: If the CLI version in the container differs significantly from the daemon version on the host, API incompatibilities may occur.
- **Rootless sockets**: Rootless Docker socket paths vary by user and require manual configuration of the mount.
- **Socket cleanup**: If the container exits unexpectedly, the socat proxy process on the host (if used) may leave stale processes.

### Comparison: DinD vs DooD

| Aspect | Docker-in-Docker (DinD) | Docker-outside-of-Docker (DooD) |
|--------|------------------------|----------------------------------|
| **Daemon** | Nested daemon inside container | Uses host's daemon |
| **Privileges** | Requires `--privileged` | No special privileges needed |
| **Isolation** | Full isolation from host | Shared with host |
| **Images** | Stored in container (volumes) | Stored on host (shared) |
| **Performance** | Some overhead from nesting | Native performance |
| **Bind mounts** | Container-relative paths | Host-relative paths |
| **Init required** | Strongly recommended (`--init`) | Not required |
| **Architecture** | Must match host | No restriction |
| **Setup complexity** | Higher (privileged, volumes, init) | Lower (socket mount only) |
| **Use case** | Full isolation, CI/CD pipelines | Quick development, shared resources |

### Feature Options Design Considerations

Based on the analysis of existing implementations[^ext-feature-dind][^ext-feature-dood], the following options should be considered for the Feature's metadata:

#### Installation Mode Options

- **`mode`**: Controls installation mode: `host`, `dind`, or `dood` (or auto-detect based on environment)
- **`moby`**: Boolean flag to install OSS Moby packages instead of Docker CE (default: `true` for dev container modes, as Moby avoids Docker's license terms)
- **`version`**: Docker/Moby version to install (default: `latest`)

#### DinD-Specific Options

- **`dockerDefaultAddressPool`**: Define default address pools for Docker networks (e.g., `base=192.168.0.0/16,size=24`)
- **`azureDnsAutoDetection`**: Automatically detect and configure DNS for Azure environments (default: `true`)
- **`disableIp6tables`**: Disable ip6tables (useful for Docker 27+ on kernels without ip6tables support)
- **`iptablesSwitchAtRuntime`**: If `true`, selects the iptables backend (legacy vs nft) at container start based on kernel detection, rather than at build time
- **`installDockerBuildx`**: Install Docker Buildx plugin (default: `true`)
- **`installDockerComposeSwitch`**: Install Compose Switch for `docker-compose` v1 command compatibility (default: `false` for DinD, `true` for DooD — the actual default varies by implementation[^ext-feature-dind-install][^ext-feature-dood-install])
- **`dockerDashComposeVersion`**: Docker Compose version to install (`v1`, `v2`, `latest`, or `none`)

#### DooD-Specific Options

- **`socketPath`**: Path where the host Docker socket is mounted inside the container (default: `/var/run/docker-host.sock`)
- **`enableNonrootDocker`**: Enable non-root user access to Docker (default: `true`)

#### Host Installation Options

- **`channel`**: Installation channel: `stable` or `test`
- **`mirror`**: Package mirror for restricted environments (e.g., `Aliyun`, `AzureChinaCloud`)

## Plugins and Extensions

Docker Engine supports several plugins and extensions that enhance its functionality. The following are relevant to the Feature:

### Docker Buildx

`docker-buildx` is a CLI plugin that extends the `docker build` command with full BuildKit capabilities, including multi-platform builds, advanced caching, and custom build drivers.

- **Homepage**: https://github.com/docker/buildx
- **Documentation**: https://docs.docker.com/build/
- **Installation**: Bundled with Docker packages as `docker-buildx-plugin` on Debian-based systems, or as part of the Docker CE RPM packages. On DinD and DooD installations, it is installed separately from GitHub releases[^ext-feature-dind-install] if the `installDockerBuildx` option is enabled (default: `true`). It is placed in `/usr/libexec/docker/cli-plugins/docker-buildx`.

### Docker Compose

`docker-compose-plugin` (v2) and `docker-compose` (v1) are tools for defining and running multi-container applications.

- **Homepage**: https://github.com/docker/compose
- **Documentation**: https://docs.docker.com/compose/
- **Installation**: 
  - **V2**: Bundled as `docker-compose-plugin` with Docker packages, or as `moby-compose` for Moby-based installations
  - **V1**: Available as a standalone binary download from GitHub releases, or installed via pip in an isolated virtualenv for architectures where pre-built binaries are unavailable[^ext-feature-dind-install]
  - **Compose Switch**: An optional utility (`compose-switch`) that maps the old `docker-compose` command to `docker compose` v2, providing backward compatibility
- In the Feature, the version is controlled by the `dockerDashComposeVersion` option. For DinD, Compose Switch defaults to `false`; for DooD, it defaults to `true`.

### Docker Init (tini)

Docker bundles `tini` (an init process for containers) as `docker-init`. It is used when `--init` is passed to `docker run`.

### VS Code Extension

The **Dev Containers** extension (`ms-azuretools.vscode-remotewsl`) and the **Docker** extension (`ms-azuretools.vscode-docker`) provide integrated Docker support in VS Code. The Docker extension can be installed in the dev container for in-editor container management.

## References

[^latest-release]: [Official Docker Engine Release Notes — Version 29](https://docs.docker.com/engine/release-notes/29/) — Official release notes for Docker Engine 29.x, with the latest stable release being 29.6.1 as of 26 June 2026.

[^docs-arch]: [Docker Engine Overview](https://docs.docker.com/engine/) — Official documentation describing Docker Engine architecture and components.

[^docs-install-overview]: [Docker Engine Installation Overview](https://docs.docker.com/engine/install/) — Official installation overview with platform matrix and release channels.

[^docs-install-ubuntu]: [Install Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/) — Official installation instructions for Ubuntu, including repository setup, package installation, version selection, and uninstallation.

[^docs-install-debian]: [Install Docker Engine on Debian](https://docs.docker.com/engine/install/debian/) — Official installation instructions for Debian.

[^docs-install-fedora]: [Install Docker Engine on Fedora](https://docs.docker.com/engine/install/fedora/) — Official installation instructions for Fedora.

[^docs-install-centos]: [Install Docker Engine on CentOS](https://docs.docker.com/engine/install/centos/) — Official installation instructions for CentOS.

[^docs-install-rhel]: [Install Docker Engine on RHEL](https://docs.docker.com/engine/install/rhel/) — Official installation instructions for RHEL.

[^docs-install-binaries]: [Install Docker Engine from Binaries](https://docs.docker.com/engine/install/binaries/) — Official documentation for static binary installation.

[^docs-install-convenience]: [Docker Convenience Script](https://docs.docker.com/engine/install/ubuntu/#install-using-the-convenience-script) — Documentation for the convenience script at get.docker.com, including limitations and recommendations.

[^docs-postinstall]: [Linux Post-Installation Steps for Docker Engine](https://docs.docker.com/engine/install/linux-postinstall/) — Official post-installation steps, including non-root user setup and systemd configuration.

[^docs-rootless]: [Run the Docker daemon as a non-root user (Rootless mode)](https://docs.docker.com/engine/security/rootless/) — Official documentation for rootless mode, including prerequisites, installation, and limitations.

[^docs-daemon]: [Docker Daemon Configuration Overview](https://docs.docker.com/engine/daemon/) — Official documentation for daemon configuration via daemon.json and CLI flags.

[^docs-docker-completion]: [Docker CLI Completion Reference](https://docs.docker.com/reference/cli/docker/completion/) — Official documentation for Docker CLI shell completion setup for bash, zsh, and fish.

[^src-installer]: [docker-install install.sh](https://github.com/docker/docker-install/blob/master/install.sh) — Source code of the official Docker installation convenience script, showing distribution detection, repository configuration, and package installation logic.

[^src-rootless-installer]: [docker-install rootless-install.sh](https://github.com/docker/docker-install/blob/master/rootless-install.sh) — Source code of the official rootless Docker installation script, including requirements checking, binary download, and systemd service setup.

[^src-dind]: [Moby project hack/dind](https://github.com/moby/moby/blob/master/hack/dind) — The official Docker-in-Docker wrapper script from the Moby project, handling cgroup v2 nesting, security filesystem mounting, and shared mount propagation for nested daemon environments.

[^ext-feature-dind]: [Devcontainers Docker-in-Docker Feature](https://github.com/devcontainers/features/tree/main/src/docker-in-docker) — Official devcontainers feature implementing Docker-in-Docker for dev containers.

[^ext-feature-dind-install]: [Devcontainers Docker-in-Docker install.sh](https://raw.githubusercontent.com/devcontainers/features/main/src/docker-in-docker/install.sh) — Source code of the official docker-in-docker feature installation script showing all configuration options, iptables handling, containerd erofs workaround, `apt-mark hold` for Docker CE packages, and container init script generation.

[^ext-feature-dind-docs]: [Devcontainers Docker-in-Docker README](https://github.com/devcontainers/features/blob/main/src/docker-in-docker/README.md) — Official documentation for the docker-in-docker feature, including requirements for privileged mode, init process, and architecture compatibility.

[^ext-feature-dind-overlayfs]: [Devcontainers Docker-in-Docker PR #1653](https://github.com/devcontainers/features/pull/1653) — Pull request adding dedicated `/var/lib/containerd` volume mount to fix overlay-on-overlay filesystem issues with containerd >= 2.3 erofs snapshotter.

[^ext-feature-dood]: [Devcontainers Docker-outside-of-Docker Feature](https://github.com/devcontainers/features/tree/main/src/docker-outside-of-docker) — Official devcontainers feature implementing Docker-outside-of-Docker for dev containers.

[^ext-feature-dood-install]: [Devcontainers Docker-outside-of-Docker install.sh](https://raw.githubusercontent.com/devcontainers/features/main/src/docker-outside-of-docker/install.sh) — Source code of the official docker-outside-of-docker feature installation script showing socket handling, GID matching, socat proxy setup, and the default value of `installDockerComposeSwitch=true`.

[^ext-feature-dood-docs]: [Devcontainers Docker-outside-of-Docker README](https://github.com/devcontainers/features/blob/main/src/docker-outside-of-docker/README.md) — Official documentation for the docker-outside-of-docker feature, including bind mount path resolution and rootless Docker configuration.

[^ext-feature-dood-rootless-issue]: [Devcontainers Issue #1536 — Rootless Docker socket path](https://github.com/devcontainers/features/issues/1536) — Issue discussing rootless Docker socket path configuration complexities and the need for configurable host socket paths.
