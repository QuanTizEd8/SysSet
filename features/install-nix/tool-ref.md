# Feature Reference

Nix is a purely functional package manager that treats packages like values in a purely functional programming language — packages are built by functions that don't have side-effects, and they never change after they have been built[^intro]. It enables reproducible, declarative, and reliable package management across Linux, macOS, and WSL2 systems. Nix stores packages in the Nix store (usually `/nix/store`), where each package has its own unique subdirectory identified by a cryptographic hash of all its build inputs, enabling multiple versions of the same package to coexist without conflict[^how-nix-works]. Nix also provides the Nix Packages collection (Nixpkgs), which offers over 140,000 packages[^nixos-org].

- **Homepage**: https://nixos.org/
- **Source Code**: https://github.com/NixOS/nix
- **Documentation**: https://nix.dev/
- **Latest Release**: 2.35.1 (as of 2026-07-16)

> **Distribution note**: Nix does **not** publish GitHub Releases with attached assets. The `NixOS/nix` repository is tagged with bare semver tags (e.g. `2.35.1`), and `https://api.github.com/repos/NixOS/nix/releases/latest` returns `404`. Pre-built binaries and the installer scripts are distributed exclusively via `https://releases.nixos.org/`. Version resolution for a feature must therefore query **git tags** (not the Releases API), and download artifacts from `releases.nixos.org`, not from GitHub.

## Tool Architecture

Nix consists of hierarchical layers[^architecture]:

1. **Command Line Interface** – The top-level user-facing layer that drives underlying components. Includes both the legacy interface (`nix-env`, `nix-build`, `nix-shell`, `nix-store`, `nix-channel`) and the new unified CLI (`nix` with subcommands like `nix build`, `nix run`, `nix profile`, `nix develop`, etc.).

2. **Nix Language Evaluator** – Transforms Nix expressions (a pure, lazy, functional language) into self-contained build plans called *store derivations*. The Nix language itself has no notion of packages or configurations; it only describes build inputs and outputs[^architecture].

3. **Nix Store** – A mechanism to keep track of build plans, data, and references between them. The store can also execute build plans to produce new data, which are made available to the operating system as files[^architecture]. The store is physically located at `/nix/store` by default and is read-only after content is written. Build tasks in Nix are called *store derivations*.

4. **Nix Daemon** – In multi-user installations, the Nix daemon (`nix-daemon`) performs store operations on behalf of non-root clients, providing build isolation, caching, and access control. It is managed by `systemd` on Linux and `launchd` on macOS[^daemon].

Key architectural characteristics:

- **Purely functional**: Packages are built by functions without side-effects and never change after being built. Building the same Nix expression twice always yields the same result[^intro].
- **Immutable store**: The Nix store is content-addressed using cryptographic hashes of all build inputs. Packages are never overwritten; instead, new versions are stored in different store paths.
- **Binary cache**: Nix can automatically skip building from source and use a binary cache (https://cache.nixos.org) for pre-built binaries, falling back to source builds when needed[^intro].
- **Sandboxed builds**: On Linux with sandboxing enabled (default), Nix sets up an isolated environment for each build process, blocking network access (outside `fetch*` functions) and files outside the Nix store[^nixos-wiki].
- **Multi-user support**: The daemon-based multi-user installation creates system users (`nixbld1` through `nixbld32` by default) and a shared build group (`nixbld`) to run builds in isolated environments, with proper access control via the Nix daemon[^install-binary].
- **Profiles and generations**: Nix uses *profiles* (symlink chains to user environments) to enable atomic upgrades and rollbacks. Each `nix-env` or `nix profile` operation creates a new *generation* that can be switched to or rolled back[^profiles].
- **Written in C++**: The Nix package manager is primarily written in C++ (C++23 standard), using libraries such as Boost, SQLite, libcurl, and libseccomp[^prerequisites-source].
- **Self-contained**: Nix does not rely on any external runtime environment (like JVM, Node.js, or Python) to function after installation. It includes its own SSL certificate bundle (`ca-bundle.crt`) for HTTPS downloads[^env-vars].

## Installation Methods

Nix provides several installation approaches. The official installer script (`curl https://nixos.org/nix/install | sh`) is the primary method and is most relevant for feature implementation. The binary tarball method and native distribution packages are also available. A Rust-based community installer (`nix-installer`) is maintained by the NixOS community as an alternative[^nix-installer].

### Official Installer Script

This is the recommended and most common installation method. It uses a two-stage process: a thin shell script downloads a binary tarball containing a complete, pre-built Nix installation, then invokes a second-stage installer script from within that tarball to perform the actual installation[^install-script-source].

#### Supported Platforms

- **Linux**: x86_64, i686, aarch64, armv6l, armv7l, riscv64
- **macOS**: x86_64 (Intel), aarch64 (Apple Silicon) — requires macOS **14.0 or higher** (the installer exits with an error on older versions)[^install-script-source]
- **FreeBSD**: x86_64 (the tarball installer includes a FreeBSD multi-user path; not a primary DevFeats target)[^install-script-source]
- **Windows**: via WSL2
- Multi-user (daemon) installation is supported on Linux (requires systemd to install and manage the daemon service) and macOS
- Single-user (`--no-daemon`) installation is supported on Linux (and FreeBSD); it does not require systemd or a daemon
- Single-user is **not** supported on macOS — the tarball installer explicitly refuses `--no-daemon` on Darwin ("`--no-daemon installs are no-longer supported on Darwin/macOS!`")[^install-script-source]

> **Default mode (shell installer)**: Contrary to a common misconception, the official **shell** installer does **not** auto-detect systemd/SELinux to pick a mode. Its default is purely OS-based: `INSTALL_MODE=daemon` on Darwin, `INSTALL_MODE=no-daemon` on everything else (Linux/FreeBSD). On Linux it only prints "*a multi-user installation is possible*" as a hint and otherwise performs a **single-user** install unless `--daemon` is passed explicitly. The systemd/SELinux-aware auto-detection described in some docs is a property of the Rust `nix-installer`, not this script.[^install-script-source]

#### Dependencies

##### Common Dependencies

- `curl` or `wget` – for downloading the binary tarball
- `tar` – for extracting the binary tarball
- `xz` – for decompressing the `.tar.xz` tarball (not required on macOS)
- `sha256sum`, `shasum`, or `openssl` – for verifying the SHA-256 hash of the downloaded tarball
- `sudo` – for creating `/nix` and performing privileged operations (unless running as root)

##### Platform-Specific Dependencies

- **Linux with systemd**: systemd must be running (`/run/systemd/system` must exist) for multi-user installation; otherwise, daemon management must be done manually[^install-binary]
- **macOS**: No additional dependencies beyond those listed above
- **Linux without systemd**: Manual configuration of the init system is required for the Nix daemon[^install-binary]

#### Installation Steps

The installer script performs the following steps[^install-script-source]:

1. **Platform detection**: Determines the system type from `uname -s` and `uname -m` and selects the appropriate binary tarball URL and expected SHA-256 hash.

2. **Tarball download**: Downloads the binary tarball from `https://releases.nixos.org/nix/nix-<VERSION>/nix-<VERSION>-<SYSTEM>.tar.xz` to a temporary directory[^install-script-source].

3. **Hash verification**: Verifies the downloaded tarball's SHA-256 hash against the expected value embedded in the script.

4. **Extraction**: Extracts the tarball and locates the second-stage installer script (`install`) within the extracted directory.

5. **Installation modes** (second-stage):

   **Multi-user installation** (`--daemon`):
   - Creates the build group (`nixbld` with configurable GID)
   - Creates build users (`nixbld1` through `nixbld32` by default, with configurable UIDs and count)
   - Sets up directory structure under `/nix` (store, database, profiles, daemon socket, logs, GC roots, temp roots, user pool)
   - Copies the pre-built Nix store contents from the tarball to `/nix/store`
   - Loads the Nix database from the included `.reginfo` file
   - Installs Nix into the default profile using `nix-env -i`
   - Installs SSL certificates
   - Creates `/etc/nix/nix.conf` with the `build-users-group` setting
   - Sets up the nixpkgs channel
   - Configures profile files (`/etc/bashrc`, `/etc/zshrc`, `/etc/bash.bashrc`, `/etc/fish/conf.d/nix.fish`) to source `nix-daemon.sh`
   - Starts the Nix daemon service (systemd on Linux, launchd on macOS)[^install-multi-user-source]

   **Single-user installation** (`--no-daemon`):
   - Takes ownership of `/nix` for the invoking user
   - Sets up the directory structure
   - Copies store contents and loads the database
   - Installs Nix into the default profile
   - Sets up the nixpkgs channel
   - Does **not** create system users, groups, or daemon service
    - Modifies `~/.profile` of the installing user to source the Nix initialization script (unless `--no-modify-profile` is passed)[^install-binary]

6. **Default behavior**: When no `--daemon`/`--no-daemon` flag is given, the shell installer picks the mode by OS only (see the "Default mode" note above):
   - `daemon` (multi-user) on macOS (Darwin) — and `--no-daemon` is refused there
   - `no-daemon` (single-user) on Linux and FreeBSD[^install-script-source]

   It does **not** probe for systemd or SELinux. A feature that wants a specific mode must pass the flag explicitly.

To install a specific version:

```bash
export VERSION=2.19.2
curl -L https://releases.nixos.org/nix/nix-$VERSION/install | sh
```

#### Installation Verification

Successful installation can be verified by:

```bash
nix-env --version
# Expected output: nix-env (Nix) 2.35.1

# Verify Nix can install and run a package
nix-env -iA nixpkgs.hello
hello
```

The installer also performs hash verification of the downloaded tarball automatically[^install-script-source].

#### Configuration Options

##### Version Selection

- **Latest version**: Use the default URL `https://nixos.org/nix/install`
- **Specific version**: Use the URL `https://releases.nixos.org/nix/nix-$VERSION/install` where `$VERSION` is any Nix version since 1.11.16[^install-binary]
- Version-specific directories include SHA-256 hashes for verification at https://releases.nixos.org/?prefix=nix/

##### Installation Path

- The Nix store is always installed at `/nix` (hardcoded in the installer as `readonly NIX_ROOT="/nix"`)[^install-multi-user-source]
- On macOS, the installer creates a dedicated APFS volume for the Nix store and configures `/etc/synthetic.conf` and `/etc/fstab` for mounting[^install-binary]
- The installation path is not configurable as the Nix community explicitly does not support alternative locations[^install-multi-user-source]

##### User Targeting

- **Multi-user installation** (`--daemon`): System-wide. Nix can be used by any user. Requires `sudo` for installation and daemon management. The Nix daemon runs as `root` and handles builds on behalf of unprivileged users[^install-binary].
- **Single-user installation** (`--no-daemon`): User-local. `/nix` is owned by the installing user. Only that user (and root) can use Nix. This mode is suitable for single-user systems, containers, and WSL without systemd[^install-binary].
- Root installation: The installer can be run as `root` directly. In multi-user mode, it skips `sudo` calls[^install-multi-user-source].
- Not supported: Installing to a user home directory or non-`/nix` prefix.

##### Required Privileges

- Multi-user installation requires `sudo` (or running as root) for:
  - Creating `/nix` directory
  - Creating system users and groups
  - Installing/starting the systemd or launchd service
  - Modifying system shell profile files
- Single-user installation requires `sudo` (or running as root) only for creating `/nix` if it doesn't exist[^install-binary]

##### Tool-Specific Configurations

The installer supports the following environment variables and flags (second-stage installer `install-multi-user.sh`)[^install-multi-user-source]:

| Variable / Flag | Description | Default |
|---|---|---|
| `NIX_USER_COUNT` | Number of build users to create (equivalent to the `--daemon-user-count` flag) | `32` |
| `NIX_BUILD_GROUP_NAME` | Name of the Nix build group | `nixbld` — **hardcoded** (`readonly NIX_BUILD_GROUP_NAME="nixbld"` in the current `install-multi-user.sh`; not overridable by env) |
| `NIX_FIRST_BUILD_UID` | Starting UID for build users (platform-specific) | `30000` (Linux), `350` (macOS) |
| `NIX_BUILD_GROUP_ID` | GID for the build group (platform-specific) | `30000` (Linux), `350` (macOS) |
| `NIX_BUILD_USER_NAME_TEMPLATE` | Template for build user names | `nixbld%d` (Linux), `_nixbld%d` (macOS) |
| `NIX_EXTRA_CONF` | Extra configuration lines for `/etc/nix/nix.conf` | (empty) |
| `NIX_INSTALLER_NO_CHANNEL_ADD` | Skip setting up the nixpkgs channel | (unset) |
| `NIX_SSL_CERT_FILE` | Path to SSL certificate bundle | Auto-detected |
| `--daemon` / `--no-daemon` | Select installation mode | Auto-detected |
| `--no-modify-profile` | Skip modification of shell profile files | (profiles are modified) |
| `--no-start-daemon` | Do not start the Nix daemon after installation (official installer does not support this flag; use the community `nix-installer` if needed) | N/A for official installer |

The Nix configuration file (`/etc/nix/nix.conf`) can be customized with settings such as[^nix-conf]:
- `build-users-group`: The group for build users (set automatically by the installer)
- `sandbox`: Enable/disable build sandboxing (default: `true` on Linux)
- `substituters`: URLs of binary caches (default: `https://cache.nixos.org`)
- `trusted-public-keys`: Public keys for verifying binary cache signatures
- `ssl-cert-file`: Path to custom CA certificate bundle
- `extra-experimental-features`: Enable experimental features like `nix-command` and `flakes`
- `max-jobs`: Maximum number of build jobs (default: `auto`)
- `nix-path`: Search paths for `<nixpkgs>` lookup paths

#### Post-Installation Steps and Cleanup

##### PATH Setup

The installer modifies system shell profiles to source the Nix daemon initialization script. For multi-user installations, it appends sourcing of `/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh` to the following files[^install-multi-user-source]:

- `/etc/bashrc` (or `/etc/bash.bashrc` on some systems)
- `/etc/zshrc`
- Fish shell: creates `/etc/fish/conf.d/nix.fish` (or in other common fish config directories)

This initialization script sets up:
- `PATH` to include `~/.nix-profile/bin` and the Nix tools directory
- `NIX_PATH` for Nix expression search paths
- `NIX_SSL_CERT_FILE` if a Nix-provided certificate bundle is available
- Various Nix-related shell functions and completions

For single-user installations (when `--no-modify-profile` is not used), the installer modifies `~/.profile` of the installing user[^install-binary].

If profiles were not modified (e.g., using `--no-modify-profile`), users must manually add:
```bash
. "$HOME/.nix-profile/etc/profile.d/nix.sh"
# or for multi-user:
. "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
```

##### Configuration Files

The installer creates or modifies the following configuration files[^install-multi-user-source]:

- `/etc/nix/nix.conf` – System-wide Nix configuration (created with `build-users-group = nixbld` and any `NIX_EXTRA_CONF` content)
- `/etc/bashrc` (or `/etc/bash.bashrc`) – Modified to source nix-daemon.sh
- `/etc/zshrc` – Modified to source nix-daemon.sh
- `/etc/fish/conf.d/nix.fish` – Created for Fish shell integration
- `/etc/synthetic.conf` (macOS) – Contains `nix` entry for APFS volume mount point
- `/etc/fstab` (macOS) – Contains mount entry for the Nix Store APFS volume

The installer also creates backup files (`.backup-before-nix`) of modified shell profiles before changing them[^install-multi-user-source].

##### Environment Variables

Persistent environment variables that need to be set for correct Nix operation[^env-vars]:

- `PATH` – Should include `~/.nix-profile/bin` and the Nix tools directory (e.g., `/nix/var/nix/profiles/default/bin`)
- `NIX_PATH` – Colon-separated list of search paths for Nix expressions (e.g., `nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixpkgs`)
- `NIX_SSL_CERT_FILE` – Path to SSL certificate bundle (if custom bundle is needed)

Optional environment variables[^common-env-vars]:
- `NIX_CONFIG` – Additional configuration settings applied from the environment
- `NIX_CONF_DIR` – Override the system Nix configuration directory (default: `/etc/nix`)
- `NIX_USER_CONF_FILES` – Override the location of user configuration files
- `XDG_CONFIG_HOME` / `XDG_STATE_HOME` / `XDG_CACHE_HOME` – XDG base directories for Nix state (when `use-xdg-base-directories` is enabled)
- `http_proxy` / `https_proxy` / `ftp_proxy` / `all_proxy` / `no_proxy` – Proxy settings (on Linux with systemd, the installer will create an override at `/etc/systemd/system/nix-daemon.service.d/override.conf` so the daemon uses them; on other platforms the daemon must be configured manually)[^env-vars]

##### Activation Scripts

The Nix environment is activated by sourcing the appropriate profile script[^env-vars]:

- **Multi-user**: `. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`
- **Single-user**: `. $HOME/.nix-profile/etc/profile.d/nix.sh`

These scripts are automatically sourced when a new shell is started after the installer has modified the shell profile files. There are no additional activation or deactivation scripts (like Python virtualenv) needed.

##### Shell Completions

Nix provides shell completions for Bash and Zsh. These are installed as part of the Nix package and are automatically loaded when the profile script is sourced. Zsh completions are also provided by the `nix-zsh-completions` package on some distributions[^arch-wiki].

##### Cleanup

The installer performs cleanup automatically:
- Downloads and extracts files to a temporary directory, which is deleted after installation completes (using `trap cleanup EXIT INT QUIT TERM`)[^install-script-source]
- If the installation fails, the `finish_fail` trap handler displays an error message and cleans up temporary files[^install-multi-user-source]

No additional manual cleanup is required after a successful installation.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

Nix can be upgraded using the built-in command (requires the `nix-command` experimental feature to be enabled in `/etc/nix/nix.conf`):

```bash
nix upgrade-nix
```

This command replaces the currently running Nix with the latest stable version declared in Nixpkgs. It may not always be the latest tagged release[^upgrade-nix].

Alternatively, the legacy `nix-env` approach can be used:
```bash
nix-env -f '<nixpkgs>' -iA nix cacert
```

To downgrade or install a specific version, the recommended approach is to use the version-specific installer URL:

```bash
curl -L https://releases.nixos.org/nix/nix-$VERSION/install | sh
```

Alternatively, the user can [uninstall](#uninstallation) and reinstall the desired version.

When using `nix upgrade-nix`, the Nix daemon will be restarted after the upgrade completes.

##### Uninstallation

Uninstallation steps vary by platform and installation type[^uninstall]:

**Linux (systemd)**:
```bash
# Stop and disable the Nix daemon
sudo systemctl stop nix-daemon.service
sudo systemctl disable nix-daemon.socket nix-daemon.service
sudo systemctl daemon-reload

# Remove Nix build users and group
for i in $(seq 1 32); do sudo userdel nixbld$i 2>/dev/null; done
sudo groupdel nixbld 2>/dev/null || true

# Remove Nix files, directories, and configuration
sudo rm -rf /etc/nix /etc/profile.d/nix.sh /etc/tmpfiles.d/nix-daemon.conf /nix \
  ~/.nix-profile ~/.nix-defexpr ~/.nix-channels ~/.local/share/nix ~/.local/state/nix ~/.cache/nix \
  ~root/.nix-profile ~root/.nix-defexpr ~root/.nix-channels ~root/.cache/nix
```

**macOS**:
```bash
# Stop and remove Nix daemon services
sudo launchctl unload /Library/LaunchDaemons/org.nixos.nix-daemon.plist
sudo rm /Library/LaunchDaemons/org.nixos.nix-daemon.plist
sudo launchctl unload /Library/LaunchDaemons/org.nixos.darwin-store.plist
sudo rm /Library/LaunchDaemons/org.nixos.darwin-store.plist

# Edit fstab to remove APFS mount entry (use `sudo vifs`)
# Edit /etc/synthetic.conf to remove the nix line

# Remove Nix build users and group
sudo dscl . -delete /Groups/nixbld 2>/dev/null || true
for u in $(sudo dscl . -list /Users | grep _nixbld); do sudo dscl . -delete /Users/$u; done

# Remove APFS volume
sudo diskutil apfs deleteVolume /nix 2>/dev/null || echo "Nix Store volume may have already been removed"

# Clean up remaining files
sudo rm -rf /etc/nix /var/root/.nix-profile /var/root/.nix-defexpr /var/root/.nix-channels \
  ~/.nix-profile ~/.nix-defexpr ~/.nix-channels ~/.local/share/nix ~/.local/state/nix ~/.cache/nix
```

Shell profile modifications must also be reverted by restoring backup files (e.g., `/etc/bashrc.backup-before-nix`) or manually removing the Nix sourcing lines.

If Nix was installed via the community `nix-installer`, uninstallation can be done with a single command:
```bash
/nix/nix-installer uninstall
```
This uses the installation receipt stored at `/nix/receipt.json` to perform a clean uninstallation[^nix-installer].

##### Idempotency

- Running the installer on a system where Nix is already installed will detect the existing installation and warn the user[^install-multi-user-source]
- The installer checks for the `nix-env` command and existing artifacts to detect prior installations
- If artifacts of a previous installation are found (e.g., backup profiles), the installer will refuse to proceed until they are resolved
- The built-in `nix upgrade-nix` command is idempotent and safe to run multiple times
- The community `nix-installer` provides a `--force` flag to override existing installation detection[^nix-installer]

#### Details

The official installer script (`https://nixos.org/nix/install`) is a POSIX shell script with the following key design[^install-script-source]:

1. It wraps the entire script body in a `{ ... }` block to prevent execution if only partially downloaded.
2. It detects the platform from `uname -s` and `uname -m`, mapping to specific system types like `x86_64-linux`, `aarch64-darwin`, etc.
3. For each platform, it has hardcoded the expected SHA-256 hash of the binary tarball and the Cachix-accessible path.
4. It constructs the tarball URL as `https://releases.nixos.org/nix/nix-2.35.1/nix-2.35.1-$system.tar.xz` (with version baked into the script).
5. It supports a `--tarball-url-prefix` argument for using alternative tarball mirrors.
6. It verifies integrity by computing the SHA-256 hash of the downloaded file and comparing it against the embedded expected hash.
7. It then extracts the tarball and delegates to the second-stage `install` script with the `INVOKED_FROM_INSTALL_IN=1` environment variable.

The second-stage installer (`install-multi-user.sh`) is a ~1100-line Bash script that implements the actual installation logic[^install-multi-user-source]:

- It handles OS-specific operations through polymorphic functions (e.g., `poly_create_build_user`, `poly_service_setup`) that are defined separately for Linux, macOS, and FreeBSD (FreeBSD support is included in the installer but is not a primary target for the DevFeats `install-nix` feature)
- It uses `sudo` for privileged operations unless running as root
- It tracks reminders and completion status through a structured output system
- It creates build users sequentially (default 32) with specific UIDs, home directories (`/var/empty`), shells (`/sbin/nologin`), and group membership
- It copies the pre-built Nix store content using `cp -RPp` (or `cp -RP --preserve=ownership,timestamps` on Linux) and then sets the store directory to read-only (`chmod -R ugo-w`)
- It loads initial Nix database entries from a `.reginfo` file inside the tarball
- It configures the nixpkgs channel by creating `~root/.nix-channels` pointing to `https://channels.nixos.org/nixpkgs-unstable`
- It backs up and modifies shell profile files, restoring from backup if installation fails

#### Notes and Best Practices

- The installer script must be fetched over HTTPS to ensure integrity during download. The SHA-256 hash verification provides an additional layer of protection against corruption or tampering[^install-script-source].
- On macOS Catalina and later, the installer creates a dedicated APFS volume for `/nix` due to the read-only system volume, configuring `/etc/synthetic.conf` and `/etc/fstab` appropriately[^install-binary].
- If macOS is updated to version 15 (Sequoia), a known issue can occur where the `_nixbld*` users are lost. Refer to issue NixOS/nix#10892 for recovery instructions[^install-binary].
- Single-user installation is significantly simpler and is the preferred mode for container environments where the daemon is unnecessary[^install-binary].
- The installer does **not** support installing to a non-default path. The Nix store must be at `/nix`[^install-multi-user-source].
- In container environments, the `--no-daemon` (single-user) mode is recommended since systemd is typically not available. The community `nix-installer` also supports `--init none` for such scenarios[^nix-installer].

### Binary Tarball

The binary tarball is an alternative installation method that downloads and unpacks the Nix distribution manually before running the installer[^install-binary].

#### Supported Platforms

Same as the official installer script (all platforms for which pre-built binaries are distributed).

#### Dependencies

- `curl` or `wget` for downloading the tarball
- `tar` with xz support for decompression
- `sudo` for privileged operations

#### Installation Steps

```bash
pushd $(mktemp -d)
export VERSION=2.19.2
export SYSTEM=x86_64-linux
curl -LO https://releases.nixos.org/nix/nix-$VERSION/nix-$VERSION-$SYSTEM.tar.xz
tar -xJf nix-$VERSION-$SYSTEM.tar.xz
cd nix-$VERSION-$SYSTEM
./install
popd
```

> **Note on the `tar` command**: The official binary installation documentation[^install-binary] shows `tar xfj` (lowercase `-j` flag for bzip2), but the Nix binary tarballs use `.tar.xz` (LZMA/xz) compression. The correct flag is `-xJf` (uppercase `-J` for xz), as used in the first-stage installer script itself[^install-script-source]. Modern GNU tar auto-detects compression, but the explicit flag `-J` is used here for correctness.

The `install` script within the tarball is the same second-stage installer used by the official script, supporting the same flags (`--daemon`, `--no-daemon`) and environment variables.

#### Installation Verification

Same as the official installer script.

#### Configuration Options

Same as the official installer script. The installer can be customized with the environment variables declared in the `install-multi-user` file within the tarball.

#### Details

The binary tarball method bypasses the first-stage installer script and directly invokes the second-stage installer. The tarball contains[^install-binary]:
- A complete, pre-built Nix store directory tree (`store/`) with all required dependencies
- A `.reginfo` file containing the initial Nix store database entries
- The `install` script (same as `install-multi-user.sh`)
- An `install-multi-user` file documenting customization environment variables

This method is useful when:
- The official installer script is inaccessible or when pinning to a specific version is required
- Inspection of the installer script before execution is desired
- Installing Nix on air-gapped systems (by downloading the tarball on a different machine)

### Native Packages for Linux Distributions

The Nix community maintains native packages for several Linux distributions[^distributions].

#### Supported Platforms

Various Linux distributions with native packaging formats[^nix-community-installers]:
- Debian/Ubuntu and derivatives (via `.deb` packages)
- Fedora/RHEL/CentOS and derivatives (via `.rpm` packages)
- Arch Linux and derivatives (via `.pkg.tar.zst` packages via `pacman`)

The community-maintained native installers can be found at https://nix-community.github.io/nix-installers/ and the source repository at https://github.com/nix-community/nix-installers.

#### Dependencies

Depends on the specific distribution's package management system but generally uses the distribution's native packaging format with bundled Nix dependencies.

#### Notes and Best Practices

- These are community-maintained and may lag behind the latest Nix release
- The official installer script is the recommended installation method across all platforms[^install-binary]

### Nix Installer (Rust-based)

An alternative installer written in Rust, distributed as a single static binary. It offers better container/no-systemd support (`--init none`), an installation receipt for clean uninstall, and non-interactive operation (`--no-confirm`).

> **Important — two forks, and the "Determinate Nix" distinction (verified 2026-07-16):** the Rust installer now exists as **two divergent forks**, and they install *different things*:
>
> | Fork | Primary URL | What it installs by default | Notes |
> |---|---|---|---|
> | **`NixOS/nix-installer`** (NixOS-foundation fork, via the Nix Installer Working Group) | `https://artifacts.nixos.org/nix-installer` | **Upstream Nix** | Currently **beta**; LGPL-2.1; the neutral community option[^nix-installer] |
> | **`DeterminateSystems/nix-installer`** (the original) | `https://install.determinate.systems/nix` | **Determinate Nix** — a *downstream, opinionated distribution* by Determinate Systems (flakes enabled by default) | The `--prefer-upstream-nix` opt-out is being sunset (documented as available only "until January 1, 2026"); GitHub Action equivalent is `determinate: false`[^determinate-installer] |
>
> For a **neutral** DevFeats feature that installs standard upstream Nix, only `NixOS/nix-installer` (or the official shell installer) is appropriate. The Determinate Systems endpoint installs a different product and should not be used as a drop-in "install Nix" method. Earlier revisions of this document conflated the two.

#### Supported Platforms

| Platform | Multi-user | Root-only | Maturity |
|---|---|---|---|
| Linux (`x86_64` and `aarch64`) | Yes (via systemd) | Yes | Stable |
| macOS (`x86_64` and `aarch64`) | Yes | - | Stable (see note) |
| Valve Steam Deck (SteamOS) | Yes | - | Stable |
| WSL2 (`x86_64` and `aarch64`) | Yes (via systemd) | Yes | Stable |
| Podman Linux containers | Yes (via systemd) | Yes | Stable |
| Docker containers | - | Yes | Stable |

#### Dependencies

- OpenSSL
- Standard system tools (`useradd`, etc.) for user/group management
- For containers without systemd: no additional dependencies (uses `--init none`)[^nix-installer]

#### Installation Steps

One-liner:
```bash
curl -sSfL https://artifacts.nixos.org/nix-installer | sh -s -- install
```

With Nix flakes enabled:
```bash
curl -sSfL https://artifacts.nixos.org/nix-installer | sh -s -- install --enable-flakes
```

Direct binary download:
```bash
curl -sL -o nix-installer https://artifacts.nixos.org/nix-installer/nix-installer-x86_64-linux
chmod +x nix-installer
./nix-installer install --no-confirm
```

#### Configuration Options

Key flags include[^nix-installer]:
- `--enable-flakes`: Enable flakes and nix-command experimental features
- `--init`: Init system to configure (`systemd`, `launchd`, `none`)
- `--extra-conf`: Extra configuration lines for `/etc/nix/nix.conf`
- `--nix-build-group-id` / `--nix-build-group-name`: Build group configuration
- `--nix-build-user-count` / `--nix-build-user-id-base`: Build user configuration
- `--no-confirm`: Skip interactive confirmation
- `--no-modify-profile`: Skip profile modification
- `--no-start-daemon`: Do not start the daemon after installation
- `--proxy`: Proxy configuration
- `--ssl-cert-file`: Custom SSL certificate file

#### Notes and Best Practices

- Note on macOS: The Nix installer is stable on macOS but may require attention after macOS upgrades, which can sometimes disrupt the Nix build users (`_nixbld*`) or the Nix Store APFS volume configuration. Refer to GitHub issue NixOS/nix#10892 for known macOS 15 Sequoia issues.
- Stores an installation receipt at `/nix/receipt.json` for easy uninstallation using `nix-installer uninstall`
- Supports SELinux and OSTree-based distributions
- Supports a "curing" mode for compatibility with existing Nix installations
- Designed for use in CI/CD pipelines (GitHub Actions, GitLab CI)
- In Docker/Podman containers or WSL2 without systemd, pass `--init none`[^nix-installer]

## Dev Container Setup

Setting up Nix in a devcontainer environment requires special consideration due to Nix's need for `/nix` directory creation, user/group management, and daemon configuration. The existing `ghcr.io/devcontainers/features/nix` feature provides a reference implementation[^devcontainer-nix-feature].

Key considerations for a devcontainer feature:

1. **Installation mode selection**: Multi-user (`--daemon`) is the default but requires either running as root or having passwordless `sudo` with `remoteUser` configured. Single-user (`--no-daemon`) is simpler but tied to a specific UID, which can break when `remoteUser` UID/GID is synced to the local user on Linux.[^devcontainer-nix-feature]

2. **Multi-user installation in containers**:
   - Works with Nix 2.11+ due to installer requirements
   - Container must run as root (but `remoteUser` can be non-root) or include `sudo` with the `remoteUser` configured to use it
   - Automated daemon startup requires passwordless `sudo` if the container itself (e.g., `containerUser`) is not running as root
   - Manual daemon startup: `sudo /usr/local/share/nix-entrypoint.sh`

3. **Single-user installation in containers**:
   - Does not require root or `sudo`
   - User specified by the feature is the Nix owner
   - Limitation: If the user's UID/GID is updated (e.g., UID sync in Linux), that user will no longer be able to work with Nix without `chown` on `/nix`

4. **Entrypoint script**: A wrapper script (e.g., `/usr/local/share/nix-entrypoint.sh`) that starts the Nix daemon and then executes the provided command is needed for multi-user installations to work properly with container lifecycle hooks[^devcontainer-nix-feature].

5. **Post-installation steps**:
   - Source the appropriate profile script before running Nix commands:
     - Multi-user: `. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`
     - Single-user: `. $HOME/.nix-profile/etc/profile.d/nix.sh`
   - Install additional packages or flakes as specified in feature options
   - Run `nix-collect-garbage --delete-old` and `nix-store --optimise` to clean up after installation

6. **Base image compatibility**: The feature should work on Debian/Ubuntu, RHEL-based, and Alpine-based images. `bash` is required to execute the installation script[^devcontainer-nix-feature].

7. **Nix configuration**: The `/etc/nix/nix.conf` file can be customized with options like:
   ```nix
   extra-experimental-features = nix-command flakes
   sandbox = false
   ```

8. **Packages and Flakes**: Feature options should support installing packages and flakes:
   - `packages`: Optional comma-separated list of Nix packages to install (using `nix-env -iA nixpkgs.<pkg>`)
   - `flakeUri`: Optional URI to a Nix flake to install (using `nix profile install`)
   - Note: Local flake files (`../flake.nix`) are not directly supported because the feature is installed before the workspace is mounted; remote URIs (e.g., `github:nixos/nixpkgs/nixpkgs-unstable#hello`) work best[^devcontainer-nix-issue-1518]

9. **PATH issues**: A known issue with the existing feature is that packages installed via the `packages` option may not be on the `PATH` after installation. Using `onCreateCommand` with `nix-env -iA nixpkgs.<pkg>` works around this[^devcontainer-nix-issue-1573].

10. **Memory considerations**: Installing packages during container build can be memory-intensive. The `useAttributePath` option (using `nix-env -iA` instead of `nix-env --install`) is recommended to avoid ambiguity and potential OOM issues[^devcontainer-nix-issue-1093].

## Plugins and Extensions

Nix itself is a package manager and does not support plugins or extensions in the traditional sense. However, the Nix ecosystem includes several complementary tools:

- **Nixpkgs**: The main package collection, containing over 140,000 packages for Nix. Source at https://github.com/NixOS/nixpkgs.
- **nix-darwin**: Nix modules for macOS system configuration. https://github.com/LnL7/nix-darwin
- **home-manager**: A system for managing user environments declaratively with Nix. https://github.com/nix-community/home-manager
- **devenv**: Fast, declarative, reproducible dev environments using Nix. https://devenv.sh/
- **nix-flake**: An experimental feature (enabled via `extra-experimental-features = nix-command flakes`) that provides a more structured approach to managing Nix expressions and dependencies[^nix-installer].

## References

[^intro]: [Nix Reference Manual – Introduction](https://nix.dev/manual/nix/2.34/introduction.html). Official documentation describing Nix as a purely functional package manager.

[^how-nix-works]: [Nix & NixOS – How Nix Works](https://nixos.org/guides/how-nix-works/). Guide explaining Nix's fundamental concepts, including the store, derivations, and binary caches.

[^nixos-org]: [NixOS Homepage](https://nixos.org/). Official website with general information about Nix and the NixOS ecosystem.

[^architecture]: [Nix Reference Manual – Architecture](https://nix.dev/manual/nix/2.34/architecture/architecture). Official architecture documentation covering the CLI, Nix language evaluator, store, and daemon layers.

[^daemon]: [Nix Reference Manual – nix daemon](https://nix.dev/manual/nix/2.34/command-ref/new-cli/nix3-daemon.html). Documentation for the Nix daemon command.

[^install-binary]: [Nix Reference Manual – Installing a Binary Distribution](https://nix.dev/manual/nix/2.34/installation/installing-binary.html). Official installation documentation for binary distribution.

[^install-script-source]: [Nix Installer Script Source Code](https://nixos.org/nix/install). The first-stage installer shell script that downloads the binary tarball, verifies its hash, and invokes the second-stage installer.

[^install-multi-user-source]: [NixOS/nix – scripts/install-multi-user.sh](https://github.com/NixOS/nix/blob/master/scripts/install-multi-user.sh). The second-stage multi-user installer script (~1100 lines) that performs the actual Nix installation.

[^nix-installer]: [NixOS/nix-installer – README](https://github.com/NixOS/nix-installer/blob/main/README.md). NixOS-foundation fork of the Rust-based Nix installer (a fork of the Determinate Nix Installer), maintained by the Nix Installer Working Group; installs upstream Nix; currently beta. Distributed via `https://artifacts.nixos.org/nix-installer`.

[^determinate-installer]: [DeterminateSystems/nix-installer – README](https://github.com/DeterminateSystems/nix-installer). The original Rust-based installer by Determinate Systems, served at `https://install.determinate.systems/nix`. By default it installs **Determinate Nix** (a downstream distribution with flakes enabled), not upstream Nix; the `--prefer-upstream-nix` opt-out is documented as available only until 2026-01-01.

[^env-vars]: [Nix Reference Manual – Environment Variables](https://nix.dev/manual/nix/2.34/installation/env-variables). Official documentation for required and optional Nix environment variables.

[^common-env-vars]: [Nix Reference Manual – Common Environment Variables](https://nix.dev/manual/nix/2.34/command-ref/env-common.html). Official documentation for common Nix environment variables including NIX_PATH, NIX_CONF_DIR, and NIX_CONFIG.

[^nix-conf]: [Nix Reference Manual – nix.conf](https://nix.dev/manual/nix/2.34/command-ref/conf-file). Official documentation for Nix configuration file settings.

[^profiles]: [Nix Reference Manual – Profiles](https://nix.dev/manual/nix/2.34/package-management/profiles). Official documentation for Nix profiles, user environments, and generations.

[^nixos-wiki]: [NixOS Wiki – Nix (package manager)](https://wiki.nixos.org/wiki/Nix_(package_manager)). Community wiki with detailed information about Nix features including sandboxing.

[^uninstall]: [Nix Reference Manual – Uninstalling Nix](https://nix.dev/manual/nix/2.34/installation/uninstall.html). Official uninstallation instructions for all supported platforms.

[^upgrade-nix]: [Nix Reference Manual – nix upgrade-nix](https://nix.dev/manual/nix/2.34/command-ref/new-cli/nix3-upgrade-nix.html). Official documentation for the Nix upgrade command. Note that this command is experimental and requires the `nix-command` experimental feature.

[^nix-community-installers]: [nix-community/nix-installers](https://nix-community.github.io/nix-installers/). Community-maintained native packaging (deb/rpm/pacman) for Nix on legacy Linux distributions.

[^distributions]: [Nix Reference Manual – Native Packages for Linux Distributions](https://nix.dev/manual/nix/2.34/installation/installing-binary.html#native-packages-for-linux-distributions). Official documentation for distribution-specific Nix packages.

[^arch-wiki]: [ArchWiki – Nix](https://wiki.archlinux.org/title/Nix). Community documentation for Nix on Arch Linux, including shell completions and configuration tips.

[^prerequisites-source]: [Nix Reference Manual – Prerequisites (Source)](https://nix.dev/manual/nix/2.34/installation/prerequisites-source). Official build prerequisites for compiling Nix from source.

[^devcontainer-nix-feature]: [devcontainers/features – src/nix](https://github.com/devcontainers/features/tree/main/src/nix). The official devcontainer feature for Nix package manager, including install.sh, post-install-steps, and documentation on multi-user vs single-user considerations.

[^devcontainer-nix-issue-1518]: [devcontainers/features – Issue #1518](https://github.com/devcontainers/features/issues/1518). Discussion of limitations with local flake files in the Nix devcontainer feature.

[^devcontainer-nix-issue-1573]: [devcontainers/features – Issue #1573](https://github.com/devcontainers/features/issues/1573). Report of PATH issues with packages installed via the Nix devcontainer feature.

[^devcontainer-nix-issue-1093]: [devcontainers/features – Issue #1093](https://github.com/devcontainers/features/issues/1093). Report of OOM/memory issues and recommendation to use `useAttributePath` option.
