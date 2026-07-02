<!--
This document serves as the comprehensive Feature Reference for zsh-completions,
the underlying tool that the install-zsh-completion feature installs and sets up.
It provides detailed information about the tool's architecture, installation methods,
supported platforms, dependencies, configuration options, and post-installation setup
for implementers, auditors, and maintainers.
-->

# Feature Reference

zsh-completions is a community-maintained project that provides additional completion
definitions for the Zsh shell that are not yet available in the core Zsh distribution.
It aims at gathering and developing new completion scripts, which may be contributed
to the upstream Zsh project when they become stable enough. The project is maintained
by the zsh-users organization on GitHub and includes completion functions for hundreds
of command-line tools spanning development tools, system administration utilities,
web development frameworks, database tools, and more.[^readme]

- **Homepage**: <https://github.com/zsh-users/zsh-completions>
- **Source Code**: <https://github.com/zsh-users/zsh-completions>
- **Documentation**: <https://github.com/zsh-users/zsh-completions/blob/master/README.md>
- **Latest Release**: 0.36.0 (as of 2026-07-02)[^release-0360]

## Tool Architecture

zsh-completions is a **collection of Zsh shell scripts** — completion function files
that are loaded into the Zsh completion system (`compsys`) via the `fpath` mechanism
and `compinit` initialization. It is not a compiled binary, daemon, or library in the
traditional sense; it is entirely interpreter-based (Zsh).

**Main components:**

- **`src/`** — The directory containing individual completion function files. Each
  file is named `_<command>` (e.g., `_git`, `_docker`, `_kubectl`, `_systemctl`)
  and implements the completion logic for that command. These are the files that
  must be placed in a directory listed in Zsh's `fpath` to be autoloaded by
  `compinit`.[^readme-manual]

- **`zsh-completions.plugin.zsh`** — A one-line plugin script (`fpath+="${0:A:h}/src"`)
  provided for compatibility with Zsh plugin managers (antigen, zinit, oh-my-zsh).
  It prepends the `src/` directory to `fpath`.[^plugin-zsh]

- **`zsh-completions-howto.org`** — An Emacs Org-mode document providing a guide to
  writing Zsh completion functions.[^howto]

- **`CONTRIBUTING.md`** — Contribution guidelines for the project.[^contributing]

**Key architectural characteristics:**

- **Single-binary/library/script type**: Collection of shell scripts; entirely
  interpreter-based (Zsh).
- **Self-contained**: No external services or daemons required. Completion functions
  operate entirely within the Zsh shell process (as autoloaded functions).
- **Client-server?**: None. Completion functions are loaded and run inline in the
  Zsh process.
- **Runtime dependencies**: Requires **Zsh** (any modern version that supports
  `compinit`). The scripts are pure Zsh functions; no other language runtime is
  needed.
- **Build system**: None. The project is purely a collection of scripts with no
  compilation step. Releases are Git tags with no build artifacts.
- **Programming language**: Shell (Zsh/Bash). The test script format shown in the
  Homebrew formula uses Zsh for verification.
- **License**: Mixed; primarily MIT-Modern-Variant (same as Zsh) and BSD-3-Clause,
  with some MIT, Apache-2.0, ISC, and NCSA licensed files.[^brew-formula-code]

**How the Zsh completion system works:**

1. Zsh's `fpath` parameter lists directories where autoloadable functions are stored.
2. `compinit` scans all files in `fpath` directories, reads the first line of each
   file for `#compdef` directives, and builds a mapping of commands to completion
   functions.
3. When the user presses Tab after typing a command, Zsh looks up the appropriate
   completion function (autoloading it on demand) and executes it to generate
   completions.
4. `compinit` dumps its mapping to `~/.zcompdump` on first initialization and reuses
   it on subsequent shell starts for faster loading.[^zsh-doc-compinit]

zsh-completions provides completion files that follow this convention. Its `src/`
directory must be added to `fpath` **before** `compinit` is called.

## Installation Methods

zsh-completions is available via many operating system package managers, via
Homebrew on macOS, via Zsh plugin managers, or can be installed manually by cloning
the Git repository.

### Git Clone (Manual Installation)

This is the canonical installation method documented in the project README. It
works on all platforms that have Git installed.

#### Supported Platforms

- All platforms that support Git and Zsh:
  - macOS
  - All Linux distributions
  - BSD systems
  - Windows (WSL, Cygwin, MSYS2)

#### Dependencies

##### Common Dependencies

- **Git** (for cloning the repository)
- **Zsh** (the shell, with `compinit` available)

##### Platform-Specific Dependencies

- None. The same steps apply across all platforms.

#### Installation Steps

```sh
# Clone the repository (shallow clone is sufficient)
git clone --depth 1 https://github.com/zsh-users/zsh-completions.git

# Or a full clone:
# git clone https://github.com/zsh-users/zsh-completions.git
```

The recommended installation path is `/usr/local/share/zsh-completions` for a
system-wide install, or `~/.local/share/zsh-completions` for a per-user install.
The completion files are in the `src/` subdirectory.[^readme-manual]

#### Installation Verification

```sh
# Verify the repository was cloned and the src directory exists
test -d /path/to/zsh-completions/src && echo "cloned"

# List a few completion files to confirm they are present
ls /path/to/zsh-completions/src/_git
ls /path/to/zsh-completions/src/_systemctl
```

Expected output: the completion files should exist as regular files with names
starting with `_` (underscore prefix).

#### Configuration Options

##### Version Selection

Version selection is done by checking out the desired Git tag:

```sh
# List available tags
cd /path/to/zsh-completions
git tag --list

# Checkout a specific version
git checkout tags/0.36.0

# Or for the latest master (bleeding edge):
git checkout master
```

The `--depth 1` flag gives the current `master` branch tip (latest development
state). For a specific release version, omit `--depth 1` or use a full clone.

##### Installation Path

Any writable directory can be used. Common choices:

- **System-wide**: `/usr/local/share/zsh-completions` (requires root/sudo for
  creation but not for the Git clone itself)
- **Per-user**: `~/.local/share/zsh-completions` or `~/.zsh-completions`
- **oh-my-zsh**: `${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-completions`

The path choice determines how `fpath` is configured in [Post-Installation
Steps](#post-installation-steps).

##### User Targeting

- **System-wide**: Clone to a shared location (e.g., `/usr/local/share/`). All users
  with Zsh can add the directory to their `fpath`.
- **Per-user**: Clone under the user's home directory. Only that user has access.

##### Required Privileges

- **System-wide install** (e.g., `/usr/local/share/`): Requires root/sudo
  privileges to create the directory and clone into it.
- **Per-user install** (e.g., `~/.local/share/`): No special privileges needed.

##### Tool-Specific Configurations

No tool-specific configuration options exist for the Git clone method. The
completion files are self-contained and require no build-time configuration.

#### Post-Installation Steps and Cleanup

After cloning the repository, the `src/` directory must be added to Zsh's
`fpath` **before** `compinit` is called so that the completion functions are
discovered and registered by the completion system.[^readme-manual]

##### PATH Setup

No PATH changes are needed. Zsh completions use `fpath`, not `PATH`.

##### Configuration Files

Add the following line to `~/.zshrc` (per-user) or `/etc/zsh/zshrc`
(system-wide, for all users) **before** the call to `compinit`:

```sh
# Add zsh-completions src directory to fpath (before compinit!)
fpath=(/path/to/zsh-completions/src $fpath)

# Then initialize completion system
autoload -Uz compinit && compinit
```

For example, with a system-wide install at `/usr/local/share/zsh-completions`:
```sh
fpath=(/usr/local/share/zsh-completions/src $fpath)
```

For a per-user install:
```sh
fpath=(${HOME}/.local/share/zsh-completions/src $fpath)
```

##### Environment Variables

- **`fpath`** (or `FPATH`) — The Zsh function path. zsh-completions' `src/`
  directory must be added to this array before `compinit` is called.
- **`ZDOTDIR`** — The directory where Zsh looks for startup files and where
  the `.zcompdump` cache file is created. Defaults to `$HOME` if not set.

No persistent environment variables need to be set for zsh-completions to work.

##### Activation Scripts

No activation scripts need to be sourced. The completion functions are autoloaded
by Zsh's `compinit` when needed. The only requirement is that `compinit` is
called (which typically happens in `~/.zshrc` or via a Zsh framework).

##### Shell Completions

zsh-completions **provides** Zsh completion functions. Once the `src/` directory
is added to `fpath` and `compinit` is initialized, completions for all commands
with matching functions in the `src/` directory become available automatically.

If completions do not appear, force a rebuild of the `zcompdump` cache:
```sh
rm -f ~/.zcompdump; compinit
```[^readme-manual]

This is needed when `compinit` was called before the `fpath` was updated, or
when the completion files changed after `compinit` was last run.

##### Cleanup

No cleanup is needed beyond removing the cloned directory if the installation
is to be undone.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

To update to a newer version (or switch to a specific one):

```sh
cd /path/to/zsh-completions
git pull --ff-only origin master  # Update to latest master
# OR: git checkout tags/0.35.0   # Switch to a specific version

# Force rebuild of compinit cache
rm -f ~/.zcompdump; compinit
```

After changing versions, it is recommended to delete the `.zcompdump` cache and
re-run `compinit` to ensure the new completion files are properly registered.

##### Uninstallation

1. Remove or comment out the `fpath` line added to `~/.zshrc` or `/etc/zsh/zshrc`.
2. Delete the cloned repository:
   ```sh
   rm -rf /path/to/zsh-completions
   ```
3. Delete the `.zcompdump` cache:
   ```sh
   rm -f ~/.zcompdump
   ```
4. Restart the shell for changes to take effect.

##### Idempotency

The `git clone` command itself is **not** idempotent — if the target directory
already exists, `git clone` will exit with an error and refuse to overwrite it.
To achieve idempotent installation in automated scripts:
- Before cloning, check if the directory exists. If it does, either skip the
  clone (leaving the existing installation in place) or update it with
  `git pull --ff-only` to bring it up to date.
- Adding the same `fpath` entries repeatedly has no harmful side effects.
- Deleting and re-creating the `.zcompdump` cache is also idempotent.

#### Notes and Best Practices

- **Order matters**: The `fpath` entry for zsh-completions must be set **before**
  `compinit` is called. If `compinit` has already been called, completion
  functions in newly added `fpath` directories will not be registered until
  `compinit` is called again (or the cache is rebuilt).[^zsh-doc-compinit]
- **Shallow clone**: A `--depth 1` clone is sufficient for installation and
  significantly faster. To switch to a specific release tag, a full clone is
  needed.
- **Plugin managers**: When using a Zsh plugin manager (antigen, zinit, oh-my-zsh),
  the manager usually handles `fpath` and `compinit` automatically. See the
  [Zsh Plugin Managers](#zsh-plugin-managers) section.

### Homebrew (macOS and Linux)

The `zsh-completions` formula is available in Homebrew's core repository.

#### Supported Platforms

- macOS (Apple Silicon and Intel)
- Linux (Homebrew-on-Linux)

#### Dependencies

- **Homebrew** must be installed
- **Zsh** (for testing purposes, declared as `uses_from_macos "zsh" => :test`
  in the formula)[^brew-formula-code]

#### Installation Steps

```sh
brew install zsh-completions
```

After installation, Homebrew prints caveats with instructions for activating the
completions (see [Configuration Files](#configuration-files-1)).[^brew-caveats]

#### Installation Verification

```sh
# Verify the formula is installed
brew list zsh-completions

# Check for completion files in the Homebrew prefix
ls "$(brew --prefix)/share/zsh-completions/_afew"
# Expected: exists (first completion in alphabetical order)
```

#### Configuration Options

##### Version Selection

The formula provides two variants:
- **Stable**: Latest release from GitHub (currently 0.36.0)
- **HEAD**: Build from the latest Git commit on the `master` branch

```sh
brew install zsh-completions --HEAD
```

##### Installation Path

Controlled by Homebrew's standard prefix:
- Apple Silicon: `/opt/homebrew/share/zsh-completions`
- Intel macOS: `/usr/local/share/zsh-completions`
- Linux (Homebrew-on-Linux): Homebrew's standard Linux prefix

The formula installs completions to `$(brew --prefix)/share/zsh-completions`
(using `pkgshare` to avoid conflicts with completions from other formulae).[^brew-formula-code]

##### User Targeting

System-wide installation via Homebrew is the standard. All users on the system
with access to the Homebrew prefix will have zsh-completions available, provided
they add the `FPATH` line to their `.zshrc`.

##### Required Privileges

- No root/sudo privileges needed; Homebrew installs to user-writable prefix.

##### Tool-Specific Configurations

The formula performs two `inreplace` operations during installation:
1. Patches `src/_ghc` to replace `/usr/local` with `HOMEBREW_PREFIX`
2. Patches `src/_gio` to replace `/usr/local/share` with `HOMEBREW_PREFIX/share`[^brew-formula-code]

No user-configurable options are exposed through the formula.

#### Post-Installation Steps and Cleanup

##### PATH Setup

No PATH changes are needed. Zsh completions use `fpath`, not `PATH`.

##### Configuration Files

Add the following to `~/.zshrc` (as printed by Homebrew's caveats):[^brew-caveats]

```sh
if type brew &>/dev/null; then
  FPATH=$(brew --prefix)/share/zsh-completions:$FPATH
  autoload -Uz compinit
  compinit
fi
```

This sets `FPATH` and initializes the completion system. The `if type brew` guard
ensures the block is skipped if Homebrew is not available (e.g., on a different
system where the same `.zshrc` is used).

##### Environment Variables

- **`FPATH`** — Set to include `$(brew --prefix)/share/zsh-completions` before
  its previous value. This is the environment variable form of `fpath`.

##### Activation Scripts

No activation scripts need to be sourced. The `compinit` call in the
configuration snippet handles initialization.

##### Shell Completions

Same as the Git clone method — once `FPATH` is set and `compinit` is called,
all completion functions from the Homebrew installation are available.

##### Cleanup

No additional cleanup steps beyond the Homebrew uninstallation procedure.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

```sh
# Upgrade to latest version
brew upgrade zsh-completions

# Reinstall from HEAD
brew reinstall zsh-completions --HEAD
```

Homebrew handles version management. To pin to a specific version, use
`brew pin zsh-completions`. To unpin: `brew unpin zsh-completions`.

##### Uninstallation

```sh
brew uninstall zsh-completions
```

After uninstalling, remove or comment out the `FPATH` and `compinit` lines
added to `~/.zshrc` and delete the `.zcompdump` cache:
```sh
rm -f ~/.zcompdump
```

##### Idempotency

Running `brew install zsh-completions` when already installed is a no-op.
To force reinstallation: `brew reinstall zsh-completions`.

#### Notes and Best Practices

- On macOS, you may encounter "zsh compinit: insecure directories" warnings. This
  is caused by world-writable permissions on Homebrew's `share` directory. The
  fix (as printed by the formula caveats):[^brew-caveats]
  ```sh
  chmod go-w "$(brew --prefix)/share"
  chmod -R go-w "$(brew --prefix)/share/zsh"
  ```
- The Homebrew formula uses `pkgshare` (i.e., `$(brew --prefix)/share/zsh-completions`)
  rather than `$(brew --prefix)/share/zsh/site-functions` to avoid conflicts with
  completions installed by other formulae.[^brew-formula-code]

#### Details

The Homebrew formula performs the following steps during installation:

1. **Downloads the release tarball** from GitHub for the specified version.
2. **Applies two `inreplace` patches** to fix hardcoded paths in upstream
   completion scripts that assume `/usr/local` as the prefix:[^brew-formula-code]
   - `src/_ghc`: replaces `/usr/local` with `HOMEBREW_PREFIX` (the GHC
     completion script searches for GHC-installed packages at this path).
   - `src/_gio`: replaces `/usr/local/share` with `HOMEBREW_PREFIX/share`
     (the GLib I/O completion script looks for MIME and icon data there).
3. **Installs to `pkgshare`** — The completions are installed to
   `$(brew --prefix)/share/zsh-completions/` rather than
   `$(brew --prefix)/share/zsh/site-functions/`. This avoids conflicts with
   completions from other Homebrew formulae that also install to
   `site-functions/`. The decision was made in
   [Homebrew/homebrew-core#126586](https://github.com/Homebrew/homebrew-core/pull/126586).[^brew-formula-code]
4. **Prints caveats** after installation with instructions for adding the
   `FPATH` line to `~/.zshrc` and fixing directory permissions if needed.[^brew-caveats]

The formula has no build-time dependencies beyond what Homebrew provides;
it ships as a bottle (precompiled binary package) for all supported platforms.

### OS Package Manager

zsh-completions is available in the official repositories of several Linux
distributions and via the Open Build Service (OBS) for others.

#### Supported Platforms

| System | Package |
|---|---|
| Debian / Ubuntu | [OBS repository](https://software.opensuse.org/download.html?project=shells%3Azsh-users%3Azsh-completions&package=zsh-completions) |
| Fedora / CentOS / RHEL / Scientific Linux | [OBS repository](https://software.opensuse.org/download.html?project=shells%3Azsh-users%3Azsh-completions&package=zsh-completions) |
| openSUSE / SLE | [OBS repository](https://software.opensuse.org/download.html?project=shells%3Azsh-users%3Azsh-completions&package=zsh-completions) |
| Arch Linux / Manjaro etc. | `zsh-completions` in `extra` repo[^arch-pkg] |
| Gentoo / Funtoo | `app-shells/zsh-completions`[^gentoo-pkg] |
| NixOS | `zsh-completions`[^nixos-pkg] |
| Void Linux | `zsh-completions`[^void-pkg] |
| Slackware | [Slackbuilds](https://slackbuilds.org/repository/14.2/system/zsh-completions/) |
| macOS | Homebrew[^brew-formula-code] |
| NetBSD | `pkgsrc`[^netbsd-pkg] |
| FreeBSD | `shells/zsh-completions`[^freebsd-pkg] |

Note: The Debian/Ubuntu/Fedora/openSUSE packages are **not** available in the
default distribution repositories. They are published via the
[Open Build Service (OBS)](https://software.opensuse.org/download.html?project=shells%3Azsh-users%3Azsh-completions&package=zsh-completions)
project `shells:zsh-users:zsh-completions`. The OBS repository must be added
as an additional package source to use the package manager for installation on
those distributions.[^readme]

#### Dependencies

##### Common Dependencies

- **Zsh** (runtime dependency; completion files are Zsh scripts)
- The system's package manager (`apt`, `pacman`, `emerge`, etc.)

##### Platform-Specific Dependencies

- **Arch Linux**: The package depends on `zsh`.[^arch-pkg]
- **Debian/Ubuntu/Fedora/openSUSE**: The OBS repository must be configured first.
  The package provides a `source` entry that specifies the repository URL.

#### Installation Steps

**Arch Linux:**
```sh
pacman -S zsh-completions
```

**Debian/Ubuntu, Fedora/CentOS/RHEL, openSUSE (via OBS):**

Follow the instructions for your distribution at
<https://software.opensuse.org/download.html?project=shells%3Azsh-users%3Azsh-completions&package=zsh-completions>.
The OBS download page provides distribution-specific setup commands. As an
example, the general approach for Debian/Ubuntu is:

```sh
# Add the OBS repository (specific commands vary by distribution)
echo 'deb http://download.opensuse.org/repositories/shells:/zsh-users:/zsh-completions/xUbuntu_24.04/ /' \
  > /etc/apt/sources.list.d/zsh-completions.list

# Add the OBS signing key
curl -fsSL https://download.opensuse.org/repositories/shells:zsh-users:zsh-completions/xUbuntu_24.04/Release.key \
  | gpg --dearmor > /etc/apt/trusted.gpg.d/zsh-completions.gpg

# Install
apt-get update
apt-get install zsh-completions
```

**Gentoo:**
```sh
emerge -a app-shells/zsh-completions
```

**NixOS:**
```nix
# In configuration.nix:
environment.systemPackages = [ pkgs.zsh-completions ];
```

#### Installation Verification

**Arch Linux:**
```sh
pacman -Q zsh-completions
# Expected output: zsh-completions 0.36.0-1
```

**Generic:**
```sh
# Check that completion files exist on the system
ls /usr/share/zsh/site-functions/_afew 2>/dev/null && echo "installed"
ls /usr/share/zsh-completions/ 2>/dev/null && echo "installed via alternate path"
```

> **NixOS note**: Packages on NixOS are installed to the Nix store
> (`/nix/store/<hash>-zsh-completions-0.36.0/share/zsh/site-functions/`),
> which is not at `/usr/share/zsh/site-functions/`. The generic path check
> will not work on NixOS. Instead, use `nix-env -q zsh-completions` or check
> `nix profile list | grep zsh-completions` (depending on your Nix setup).
> **FreeBSD**: The package installs to `/usr/local/share/zsh/site-functions/`.

The exact installation path varies by distribution:
- **Arch Linux**: `/usr/share/zsh/site-functions/`
- **FreeBSD**: `/usr/local/share/zsh/site-functions/`[^freebsd-pkg]
- **Other distributions using OBS**: may vary

#### Configuration Options

##### Version Selection

Version selection depends on the distribution's repository. Arch Linux typically
tracks the latest release. OBS packages may lag behind the latest release.

##### Installation Path

Determined by the distribution's packaging conventions:
- **Arch Linux**: Installs to `/usr/share/zsh/site-functions/` (which is already
  in the default `fpath` of most Zsh installations, making the package effectively
  zero-configuration)
- **FreeBSD**: Installs to `/usr/local/share/zsh/site-functions/`[^freebsd-pkg]
- **OBS packages**: Installation path varies

##### User Targeting

System-wide installation is the standard for package manager installs.
All users with Zsh on the system benefit from the installed completions.

##### Required Privileges

Installing via a package manager requires root/sudo privileges.

##### Tool-Specific Configurations

No tool-specific configuration options are exposed through the package manager.

#### Post-Installation Steps and Cleanup

**Arch Linux**: The package installs completion files to
`/usr/share/zsh/site-functions/`, which is typically already in Zsh's default
`fpath`. No additional configuration is needed — completions work out of the
box after restarting the shell (or running `compinit`).

**Other distributions**: Depending on the installation path, the directory may
need to be added to `fpath` as described in the [Git Clone post-installation
steps](#configuration-files).

##### PATH Setup

No PATH changes are needed.

##### Configuration Files

If the package installs to a non-standard path or a path not already in the
default `fpath`, add it to `~/.zshrc` or `/etc/zsh/zshrc`:

```sh
fpath=(/path/to/zsh-completions $fpath)
autoload -Uz compinit && compinit
```

##### Environment Variables

No persistent environment variables need to be set.

##### Activation Scripts

No activation scripts need to be sourced. The `fpath` configuration and
`compinit` call in the user's shell startup files handle initialization.

##### Shell Completions

Same as other methods — once the directory is in `fpath` and `compinit` is
called, completions are available.

##### Cleanup

No cleanup is needed after package manager installation.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

Use the system's normal package management commands:
- Arch: `pacman -Syu zsh-completions`
- OBS: `apt-get update && apt-get install zsh-completions`

Downgrading requires specific version pinning or manual package file installation.

##### Uninstallation

```sh
# Arch Linux
pacman -R zsh-completions

# Debian/Ubuntu (OBS)
apt-get remove zsh-completions
```

After uninstalling, remove any `fpath` lines added manually to shell configuration
files and delete the `.zcompdump` cache:
```sh
rm -f ~/.zcompdump
```

##### Idempotency

Package manager installations are fully idempotent. Running `pacman -S
zsh-completions` on a system where it is already installed is a no-op.

### Zsh Plugin Managers

zsh-completions works with several Zsh plugin managers, which automate the
process of cloning the repository and setting up `fpath` and `compinit`.

#### Supported Platforms

All platforms supported by the Git clone method (plugin managers handle the
underlying clone).

#### Dependencies

- The respective plugin manager (antigen, zinit, oh-my-zsh, etc.)
- **Git** (for cloning the repository)

#### Installation Steps

**Antigen**[^readme-antigen]:
```sh
# Add to ~/.zshrc
antigen bundle zsh-users/zsh-completions
```

**oh-my-zsh**[^readme-omz]:

The project's README recommends NOT using the standard plugin loading method;
instead:
```sh
# Clone into custom plugins directory
git clone https://github.com/zsh-users/zsh-completions.git \
  ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions
```

Then in `~/.zshrc`, **before** sourcing `oh-my-zsh.sh`:
```sh
fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src
  autoload -Uz compinit && compinit
source "$ZSH/oh-my-zsh.sh"
```

This avoids `compinit` being called twice (oh-my-zsh calls it again), which
would degrade startup performance and cause redundant `.zcompdump` generation.

**zinit**[^readme-zinit]:
```sh
# Add to ~/.zshrc
zinit light zsh-users/zsh-completions
```

#### Installation Verification

```sh
# Check if the repository was cloned
test -d "${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions" \
  && echo "installed by oh-my-zsh"

# Restart shell and test completion
# Type "systemctl <TAB><TAB>" and verify completions appear
```

#### Configuration Options

##### Version Selection

- **Antigen**: Use `antigen bundle zsh-users/zsh-completions@0.36.0` for a
  specific version/tag.
- **zinit**: Use `zinit light zsh-users/zsh-completions` for latest master,
  or `zinit ice ver="0.36.0"` followed by `zinit light zsh-users/zsh-completions`
  for a specific version.
- **oh-my-zsh**: Version is determined by what was cloned.

##### Required Privileges

No special privileges needed for per-user plugin manager installs.

#### Post-Installation Steps and Cleanup

Plugin managers handle the `fpath` setup and `compinit` call automatically.
No additional user configuration is required.

#### Changing Versions and Uninstallation

Follow the plugin manager's normal update/uninstall procedures:
- Antigen: `antigen update` / `antigen purge zsh-users/zsh-completions`
- zinit: `zinit update` / `zinit delete zsh-users/zsh-completions`
- oh-my-zsh: Manual update via `git pull` / manual directory removal

#### Idempotency

Plugin manager installations are generally idempotent — re-adding the same
`bundle` or `plugin` line has no harmful effect if the repository is already
cloned.

## Dev Container Setup

In a development container environment, zsh-completions requires attention to
a few specific points:

1. **Zsh must be installed**: The `install-zsh-completion` feature depends on
   Zsh being available. Zsh is not installed by default in many minimal
   container images (e.g., `ubuntu:latest`). An `install-zsh` feature (or the
   OS package manager) should be run first to ensure Zsh is available.

2. **`compinit` must be called**: zsh-completions is only active if `compinit`
   has been called in the user's Zsh configuration. Ensure that `compinit` is
   invoked in the system-wide `/etc/zsh/zshrc` or per-user `~/.zshrc`.

3. **`fpath` must be set before `compinit`**: The completion directory (whether
   from Git clone or Homebrew) must be added to `fpath` **before** `compinit`.
   In a container setup, this is typically done by modifying
   `/etc/zsh/zshrc` (for all users) or by writing to the user's `~/.zshrc`.

4. **Root/non-root considerations**: The feature may run as root during
   container build, but completions should work for the non-root user (e.g.,
   `vscode`). If modifying `/etc/zsh/zshrc`, both root and non-root users
   benefit from the setup.

5. **Non-login shells**: Dev containers typically run non-login shells (the
   VS Code terminal does not start with `-l`). Zsh's startup files are
   `/etc/zsh/zshrc` and `~/.zshrc` for non-login shells (not `.zprofile`
   or `.zshenv`). Configuration for `fpath` and `compinit` should be placed
   in `/etc/zsh/zshrc` or `~/.zshrc` accordingly.[^zsh-startup]

6. **Homebrew in containers**: If the dev container uses Homebrew (e.g., on
   macOS or via Homebrew-on-Linux), the Homebrew installation method applies.
   Otherwise, the Git clone method is the most portable option for containers.

## References

[^readme]: [GitHub README — zsh-users/zsh-completions](https://github.com/zsh-users/zsh-completions/blob/master/README.md)
    — Official README with usage, installation methods, and license information.

[^release-0360]: [GitHub Release — v0.36.0 (2026-03-09)](https://github.com/zsh-users/zsh-completions/releases/tag/0.36.0)
    — Latest stable release of zsh-completions.

[^readme-manual]: [README.md — Manual Installation](https://github.com/zsh-users/zsh-completions/blob/master/README.md#manual-installation)
    — Official manual installation instructions showing Git clone, fpath setup, and compinit.

[^readme-antigen]: [README.md — Antigen](https://github.com/zsh-users/zsh-completions/blob/master/README.md#antigen)
    — Antigen plugin manager setup instructions.

[^readme-omz]: [README.md — oh-my-zsh](https://github.com/zsh-users/zsh-completions/blob/master/README.md#oh-my-zsh)
    — oh-my-zsh plugin manager setup, including the optimized approach to avoid redundant compinit.

[^readme-zinit]: [README.md — zinit](https://github.com/zsh-users/zsh-completions/blob/master/README.md#zinit)
    — zinit plugin manager setup instructions.

[^plugin-zsh]: [zsh-completions.plugin.zsh](https://github.com/zsh-users/zsh-completions/blob/master/zsh-completions.plugin.zsh)
    — The plugin script used by Zsh plugin managers; adds `src/` to fpath.

[^howto]: [zsh-completions-howto.org](https://github.com/zsh-users/zsh-completions/blob/master/zsh-completions-howto.org)
    — Guide for writing Zsh completion functions, distributed with the project.

[^contributing]: [CONTRIBUTING.md](https://github.com/zsh-users/zsh-completions/blob/master/CONTRIBUTING.md)
    — Contribution guidelines for the zsh-completions project.

[^brew-formula-code]: [Homebrew/homebrew-core — zsh-completions.rb](https://github.com/Homebrew/homebrew-core/blob/master/Formula/z/zsh-completions.rb)
    — Homebrew formula source code showing installation steps, pkgshare usage, license, and caveats.

[^brew-caveats]: [Homebrew Formulae — zsh-completions (Caveats)](https://formulae.brew.sh/formula/zsh-completions)
    — Post-installation instructions printed by Homebrew, including FPATH/compinit setup and permission fix.

[^arch-pkg]: [Arch Linux — zsh-completions](https://archlinux.org/packages/extra/any/zsh-completions/)
    — Arch Linux package details showing version 0.36.0-1, dependencies, and installation paths.

[^gentoo-pkg]: [Gentoo Packages — app-shells/zsh-completions](https://packages.gentoo.org/packages/app-shells/zsh-completions)
    — Gentoo package for zsh-completions.

[^nixos-pkg]: [NixOS/nixpkgs — zsh-completions](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/zs/zsh-completions/package.nix)
    — NixOS package definition for zsh-completions.

[^void-pkg]: [Void Linux — zsh-completions](https://github.com/void-linux/void-packages/blob/master/srcpkgs/zsh-completions/template)
    — Void Linux package template for zsh-completions.

[^netbsd-pkg]: [NetBSD pkgsrc — shells/zsh-completions](https://ftp.netbsd.org/pub/pkgsrc/current/pkgsrc/shells/zsh-completions/README.html)
    — NetBSD pkgsrc package for zsh-completions.

[^freebsd-pkg]: [FreshPorts — shells/zsh-completions](https://www.freshports.org/shells/zsh-completions)
    — FreeBSD ports package for zsh-completions.

[^zsh-doc-compinit]: [Zsh Documentation — Completion System (compinit)](https://zsh.sourceforge.io/Doc/Release/Completion-System.html#Use-of-compinit)
    — Official Zsh documentation for the compinit function, fpath, compdump, and initialization.

[^zsh-startup]: [Zsh Documentation — Startup Files](https://zsh.sourceforge.io/Doc/Release/Files.html)
    — Official Zsh documentation on startup files (zshenv, zprofile, zshrc, zlogin) and their sourcing order.
