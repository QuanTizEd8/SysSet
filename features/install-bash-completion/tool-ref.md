<!--
This document serves as the comprehensive Feature Reference for bash-completion,
the underlying tool that the install-bash-completion feature installs and sets up.
It provides detailed information about the tool's architecture, installation methods,
supported platforms, dependencies, configuration options, and post-installation setup
for implementers, auditors, and maintainers.
-->

# Feature Reference

bash-completion is a collection of shell functions that take advantage of the
programmable completion feature of Bash. It provides tab-completion for commands,
their arguments, file names, and other command-line elements. The project includes
a library of helper functions for creating new completions, an on-demand loading
system that automatically loads completions based on the command being invoked,
and hundreds of ready-made completion definitions for common Unix/Linux commands.
It is the de facto standard for Bash completion on Linux and macOS systems.

- **Homepage**: <https://github.com/scop/bash-completion>
- **Source Code**: <https://github.com/scop/bash-completion>
- **Documentation**: <https://github.com/scop/bash-completion/blob/main/README.md>
- **Latest Release**: 2.17.0 (as of 2026-07-02)[^release-2170]

## Tool Architecture

bash-completion is a set of **shell scripts** (primarily Bash) organized into
several components. It is **not** a compiled binary or a daemon; it is sourced
directly into the user's interactive Bash shell at session startup.

**Main components:**

- **`bash_completion`** — The main file (~3700 lines) that implements the core
  infrastructure: helper functions (e.g., `_init_completion`, `_filedir`,
  `_known_hosts`), the on-demand completion loading system (`_comp_load`),
  and default completion rules. This is the file that must be sourced at shell
  startup.[^src-bash-completion]

- **`completions/`** — A directory containing the actual completion definition
  files for individual commands (e.g., `apt`, `git`, `ssh`, `docker`). Each file
  defines a `_<cmd>` function and registers it with `complete -F _<cmd> <cmd>`.
  These are loaded **on demand** by the dynamic loading system in
  `bash_completion`.[^faq-completionsdir]

- **`completions-core/`** — The completion files shipped as part of the
  bash-completion project itself (the canonical set maintained by the project).

- **`completions-fallback/`** — Fallback completions for third-party or less
  common commands, loaded when no dedicated completion is found in the main
  directories.

- **`helpers/`** — Helper scripts used by completion functions (accessed via
  `pkg-config --variable=helpersdir bash-completion`).[^faq-helpersdir]

- **`startup/`** — Startup completion files that are loaded when bash-completion
  is initialized, used for settings that must be applied early (e.g., overriding
  `complete -D` defaults).

- **`bash_completion.sh`** — The `profile.d` entry-point script installed to
  `/etc/profile.d/bash_completion.sh` (or `$sysconfdir/profile.d/`). It checks
  for interactive Bash, verifies Bash >= 4.2, checks the user's config hook,
  and sources the main `bash_completion` file.[^src-profiled]

**Key architectural characteristics:**

- **Single-binary/library/script type**: Collection of shell scripts; entirely
  interpreter-based (Bash).
- **Self-contained**: No external services or daemons required. It operates
  entirely within the Bash shell process.
- **Client-server?**: None. It is sourced inline into the running shell.
- **Runtime dependencies**: Requires Bash >= 4.2 (for v2). The scripts themselves
  are pure Bash/shell, with no external language runtime needed.
- **Build system**: GNU Autotools (`autoreconf`, `./configure`, `make`, `make install`).
  Provides a `pkg-config` file (`bash-completion.pc`) and CMake config files
  (`bash-completion-config.cmake`) for third-party packages to integrate
  completion installation.[^configure-ac][^makefile-am]
- **Programming language**: Shell (66.5%), with Python (29.8%) used for the test
  suite; automated tests use `pytest` with the `pexpect` library.
- **License**: GPL-2.0-or-later.

## Installation Methods

bash-completion is available via nearly every major operating system package
manager, via Homebrew on macOS, and can also be built from source using GNU
Autotools.

### OS Package Manager

This is the recommended installation method on Linux. The package is called
`bash-completion` on virtually all distributions.

#### Supported Platforms

- All major Linux distributions (Debian, Ubuntu, Fedora, RHEL/CentOS, Arch,
  openSUSE, Alpine, etc.)
- BSD systems (FreeBSD, OpenBSD) via ports/packages
- macOS via Homebrew[^brew-formula] or MacPorts[^macports]
- Cygwin, MSYS2 on Windows

#### Dependencies

##### Common Dependencies

- **Bash >= 4.2** (v2.x of bash-completion requires this)[^readme-install]
- The system's package manager (`apt`, `dnf`, `apk`, `pacman`, `zypper`, etc.)

##### Platform-Specific Dependencies

- **Homebrew (macOS)**: `bash` itself must be installed via Homebrew (macOS
  ships Bash 3.2 by default, which is incompatible with bash-completion v2).
  The `bash-completion@2` formula automatically depends on the `bash` formula.[^brew-deps]
- **Linux**: No platform-specific dependencies beyond what the package manager
  handles automatically.

#### Installation Steps

**Debian / Ubuntu (apt):**
```sh
apt-get update
apt-get install bash-completion
```
The `bash-completion` package installs the main script to
`/usr/share/bash-completion/bash_completion` and the profile.d entry point to
`/etc/profile.d/bash_completion.sh`.

**Fedora / RHEL / CentOS / AlmaLinux / Rocky (dnf/yum):**
```sh
dnf install bash-completion
```
or on older systems:
```sh
yum install bash-completion
```

**Arch Linux (pacman):**
```sh
pacman -S bash-completion
```

**Alpine Linux (apk):**
```sh
apk add bash-completion
```

**openSUSE (zypper):**
```sh
zypper install bash-completion
```

**macOS (Homebrew):**
```sh
brew install bash-completion@2
```
Note: Use `bash-completion@2` (not `bash-completion`) on systems running
Bash >= 4.2 (e.g., Homebrew's `bash` formula). The unversioned `bash-completion`
formula targets Bash 3.2 and is an older, incompatible version (v1.x).[^brew-v2]

**macOS (MacPorts):**
```sh
port install bash-completion
```

#### Installation Verification

Verify that the package is installed and the main script is present:

```sh
# Check that the main completion file exists
test -f /usr/share/bash-completion/bash_completion && echo "installed"

# Check installed version (via pkg-config, if available)
pkg-config --modversion bash-completion

# On Debian/Ubuntu, check the dpkg status
dpkg -l bash-completion

# On RPM-based systems
rpm -q bash-completion

# On Homebrew
brew list bash-completion@2
```

The installed files include:
- `/usr/share/bash-completion/bash_completion` — main completion infrastructure
- `/usr/share/bash-completion/completions/` — on-demand completion files
- `/etc/profile.d/bash_completion.sh` — auto-loading profile.d script[^makefile-am]

#### Configuration Options

##### Version Selection

With package managers, the version is determined by the distribution's
repositories. To get the latest version, use a distribution with up-to-date
packages (e.g., Arch, Fedora) or install from source.

For Homebrew, `bash-completion@2` always tracks the latest stable release.
The `HEAD` variant can be installed with `brew install bash-completion@2 --HEAD`
to build from the latest Git commit.

##### Installation Path

Package managers install to the distribution's standard paths:
- Main script: `$(datadir)/bash-completion/bash_completion` (usually
  `/usr/share/bash-completion/bash_completion`)
- Profile.d entry: `$(sysconfdir)/profile.d/bash_completion.sh` (usually
  `/etc/profile.d/bash_completion.sh`)
- Completions: `$(datadir)/bash-completion/completions/` (usually
  `/usr/share/bash-completion/completions/`)[^makefile-am]

On Homebrew, the prefix is `$(brew --prefix)` (typically `/opt/homebrew` on
Apple Silicon or `/usr/local` on Intel):
- Profile.d entry: `$HOMEBREW_PREFIX/etc/profile.d/bash_completion.sh`

##### User Targeting

System-wide installation is the standard for package manager installs.
The profile.d script loads bash-completion for all users automatically.
Individual users can prevent loading by creating a config file at
`$XDG_CONFIG_HOME/bash_completion` (default: `~/.config/bash_completion`)
with `shopt -u progcomp`.[^config-hook]

##### Required Privileges

Installing via a package manager requires root/sudo privileges. On Homebrew,
user-local installation is possible (Homebrew's default mode).

##### Tool-Specific Configurations

bash-completion does not have configuration files in the traditional sense.
User-specific customizations are done via:

1. **User completion files** — Placed in `$BASH_COMPLETION_USER_DIR/completions/`
   (default: `~/.local/share/bash-completion/completions/`). Files named
   `<command>.bash` are loaded on demand.[^faq-userdir]

2. **User startup files** — Placed in `$BASH_COMPLETION_USER_DIR/startup/`.
   These are loaded during bash-completion initialization.

3. **User file** — `$BASH_COMPLETION_USER_FILE` (default: `~/.bash_completion`).
   Sourced eagerly when bash-completion initializes.

4. **Per-user disable** — `$XDG_CONFIG_HOME/bash_completion`
   (default: `~/.config/bash_completion`). Setting `shopt -u progcomp` here
   prevents bash-completion from loading.[^config-hook]

#### Post-Installation Steps and Cleanup

##### PATH Setup

No PATH changes are needed; bash-completion is sourced into the shell, not
invoked as an external command.

##### Configuration Files

On **Linux**, the package manager's profile.d script at
`/etc/profile.d/bash_completion.sh` is automatically sourced by the system's
`/etc/profile` (or equivalent) for interactive login shells. In most
configurations, no user configuration file changes are needed.

On **macOS with Homebrew**, the `/etc/profile.d/` mechanism is not used, so the
user must manually add a source line. Homebrew's `bash-completion@2` formula
prints the following caveat after installation:
```sh
Add the following line to your ~/.bash_profile:
  [[ -r "$HOMEBREW_PREFIX/etc/profile.d/bash_completion.sh" ]] && . "$HOMEBREW_PREFIX/etc/profile.d/bash_completion.sh"
```[^brew-caveats]

For a **manual setup** (without profile.d), add the following to `~/.bashrc`:
```sh
# Source bash-completion if available, avoid double-sourcing
[[ $PS1 && -f /usr/share/bash-completion/bash_completion ]] && \
    . /usr/share/bash-completion/bash_completion
```[^readme-install]

##### Environment Variables

- `BASH_COMPLETION_VERSINFO` — Set automatically by bash-completion after
  loading; used to prevent double-sourcing. It is a readonly array containing
  the major and minor version numbers (e.g., `(2 17)` for v2.17.0).
- `BASH_COMPLETION_USER_DIR` — Colon-separated list of directories for
  user-installed completion files (default:
  `$XDG_DATA_HOME/bash-completion` → `~/.local/share/bash-completion`).
- `BASH_COMPLETION_USER_FILE` — Path to the user's eagerly-sourced completion
  file (default: `$HOME/.bash_completion`).
- `XDG_DATA_HOME` — Base directory for user data (used if
  `BASH_COMPLETION_USER_DIR` is not set).
- `XDG_DATA_DIRS` — Used to locate system-wide completion directories (fallback
  to `/usr/local/share:/usr/share` if unset).[^faq-search-order]

##### Activation Scripts

The profile.d script `/etc/profile.d/bash_completion.sh` serves as the
activation entry point. Its logic is:

```sh
# Check for interactive bash and that we haven't already been sourced.
if [ "x${BASH_VERSION-}" != x -a "x${PS1-}" != x -a "x${BASH_COMPLETION_VERSINFO-}" = x ]; then
    # Check for recent enough version of bash.
    if [ "${BASH_VERSINFO[0]}" -gt 4 ] ||
        [ "${BASH_VERSINFO[0]}" -eq 4 -a "${BASH_VERSINFO[1]}" -ge 2 ]; then
        [ -r "${XDG_CONFIG_HOME:-$HOME/.config}/bash_completion" ] &&
            . "${XDG_CONFIG_HOME:-$HOME/.config}/bash_completion"
        if shopt -q progcomp && [ -r @datadir@/@PACKAGE@/bash_completion ]; then
            # Source completion code.
            . @datadir@/@PACKAGE@/bash_completion
        fi
    fi
fi
```[^src-profiled]

Key behavior of this script:
1. Only runs in **interactive** Bash shells (checks `PS1`).
2. Only runs if Bash completion has **not already been loaded** (checks
   `BASH_COMPLETION_VERSINFO`).
3. Requires **Bash >= 4.2** (checks `BASH_VERSINFO`).
4. Checks the **per-user config hook** at
   `$XDG_CONFIG_HOME/bash_completion` (or `~/.config/bash_completion`) before
   proceeding. If this file contains `shopt -u progcomp`, loading is skipped.
5. Sources the main `bash_completion` file if programmable completion is enabled
   (`shopt -q progcomp`).

For **non-login shells** (common in devcontainer/terminal environments), if
the system does not source `/etc/profile.d/` automatically, add the sourcing
to `~/.bashrc` directly.

##### Shell Completions

bash-completion **is itself** the framework for shell completions. Once
activated, it automatically provides tab-completion for hundreds of commands.
The completion files are loaded on demand based on the command being typed, so
no additional setup is required beyond sourcing bash-completion itself.

##### Cleanup

No cleanup is needed after package manager installation. Package manager
handles all file placement.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- **Package manager**: Use the system's normal update mechanism
  (`apt upgrade`, `dnf update`, etc.). The package manager handles version
  changes.
- **Homebrew**: `brew upgrade bash-completion@2` or `brew pin/unpin` to
  control versioning. The formula tracks the latest stable release.
- **Downgrading**: With package managers, downgrading requires installing a
  specific version from the distribution's archives or using a snapshot
  repository. This is generally not recommended.

##### Uninstallation

- **Debian/Ubuntu**: `apt-get remove bash-completion`
- **Fedora/RHEL**: `dnf remove bash-completion`
- **Arch**: `pacman -R bash-completion`
- **Alpine**: `apk del bash-completion`
- **Homebrew**: `brew uninstall bash-completion@2`

After uninstalling, the main completion script and all shipped completion files
are removed. However, **user customization files** (`~/.bash_completion`,
`~/.local/share/bash-completion/`, `~/.config/bash_completion`) and **shell
startup modifications** (e.g., sourcing lines added to `~/.bashrc` or
`~/.bash_profile`) are **not** removed and must be cleaned up manually.

##### Idempotency

Package manager installations are fully idempotent. Running
`apt-get install bash-completion` on a system where it is already installed
is a no-op (or upgrades if a newer version is available).

#### Notes and Best Practices

- On **Linux containers** (Docker, devcontainers) that do not run a login shell
  (no `/etc/profile` sourcing), you must explicitly source the main completion
  file from `~/.bashrc` or `/etc/bash.bashrc`.[^issue-devcontainer]
- The v2.x branch requires **Bash >= 4.2**. On older systems or macOS's
  built-in Bash 3.2, use the older v1.x (`bash-completion` without `@2`),
  which has different file locations and no on-demand loading.[^brew-v1-vs-v2]
- bash-completion is typically pre-installed as part of the `bash` package on
  most Linux distributions. In minimal container images (e.g., `ubuntu:latest`),
  it may need to be explicitly installed.

### Source / GNU Autotools

For distributions without a package, or when the latest version is needed,
bash-completion can be installed from source using the standard GNU Autotools
build system.

#### Supported Platforms

All platforms supported by the package method (Linux, macOS, BSD, Cygwin).

#### Dependencies

- **GNU Autotools**: `autoconf`, `automake` (only needed if building from Git
  checkout; release tarballs include the generated `configure` script)
- **GNU make**
- **Bash >= 4.2** (runtime requirement)
- **Python 3 + pytest >= 3.6 + pexpect** (optional, for running the test suite)

#### Installation Steps

```sh
# Download the release tarball
curl -LO https://github.com/scop/bash-completion/releases/download/2.17.0/bash-completion-2.17.0.tar.xz

# Extract and enter
tar xf bash-completion-2.17.0.tar.xz
cd bash-completion-2.17.0

# If building from Git (not release tarball), generate configure first
autoreconf -i

# Configure, build, install
./configure
make
make install   # Requires root/sudo for system-wide install
```[^readme-install]

The default installation prefix is `/usr/local`. To install to a different
location:
```sh
./configure --prefix=/opt/bash-completion
make
make install
```

#### Installation Verification

```sh
# Verify the main file was installed
test -f /usr/local/share/bash-completion/bash_completion && echo "installed"

# Check version via pkg-config
pkg-config --modversion bash-completion
```

#### Configuration Options

Standard Autotools configure options apply:
- `--prefix=PREFIX` — Installation prefix (default: `/usr/local`)
- `--sysconfdir=DIR` — System configuration directory (default:
  `PREFIX/etc`; profile.d script goes here)
- `--datadir=DIR` — Read-only architecture-independent data (default:
  `PREFIX/share`; completions go here)
- `--with-pytest=EXECUTABLE` — Specify the pytest executable for the test suite

#### Post-Installation Steps and Cleanup

Same as the package manager method. The profile.d script is installed to
`$sysconfdir/profile.d/bash_completion.sh`. If `$sysconfdir/profile.d/` is not
automatically sourced by the system, add sourcing to `~/.bashrc` or
`/etc/bashrc`.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

To switch versions: download the desired release tarball and repeat the
configure/make/make-install cycle. The new version will overwrite the previous
installation files.

##### Uninstallation

From the source directory (if it still exists):
```sh
make uninstall   # Requires root if installed with sudo make install
```

Without the source tree, files must be removed manually:
```sh
rm -rf /usr/local/share/bash-completion
rm -f /usr/local/etc/profile.d/bash_completion.sh
```

##### Idempotency

Running `make install` multiple times will overwrite the previous installation
with the same version (or a new one). It is idempotent in that sense — the
same files are overwritten with identical content.

### Homebrew (macOS)

#### Supported Platforms

- macOS (Apple Silicon and Intel)
- Linux (as a secondary platform for Homebrew-on-Linux)

#### Dependencies

- Homebrew must be installed
- `bash` formula (automatically installed as a dependency of
  `bash-completion@2`)[^brew-deps]
- On macOS: `readlink -f` is not available on macOS <= Monterey; the Homebrew
  formula patches this during installation[^brew-formula-code]

#### Installation Steps

```sh
# Install bash-completion v2 (for Bash >= 4.2)
brew install bash-completion@2

# For macOS's built-in Bash 3.2, use the legacy v1 instead:
# brew install bash-completion
```

After installation, Homebrew prints:
```
Add the following line to your ~/.bash_profile:
  [[ -r "$(brew --prefix)/etc/profile.d/bash_completion.sh" ]] && . "$(brew --prefix)/etc/profile.d/bash_completion.sh"
```[^brew-caveats]

#### Configuration Options

The formula provides two variants:
- **Stable**: Latest release from GitHub (currently 2.17.0)
- **HEAD**: Build from the latest Git commit on the `main` branch

```sh
brew install bash-completion@2 --HEAD
```

#### Post-Installation Steps

On macOS, due to the way the default shell environment is configured, you must
manually add the sourcing line. Add the following to `~/.bash_profile`
(preferred) or `~/.bashrc`:

```sh
if [[ -r "$(brew --prefix)/etc/profile.d/bash_completion.sh" ]]; then
  . "$(brew --prefix)/etc/profile.d/bash_completion.sh"
fi
```[^readme-macos]

## Dev Container Setup

In a development container environment, bash-completion requires special
attention because:

1. **Containers typically run non-login shells**, which means `/etc/profile.d/`
   scripts are not automatically sourced. The ENTRYPOINT/CMD of most dev
   container images (e.g., `mcr.microsoft.com/devcontainers/base`) is
   `/bin/bash` without `-l`, so `/etc/profile` — and by extension
   `/etc/profile.d/` — is never executed.[^issue-devcontainer]

2. **Workaround**: To ensure bash-completion is available in dev containers,
   add a sourcing line to `/etc/bash.bashrc` (system-wide for all Bash
   non-login shells) or to each user's `~/.bashrc`. This ensures that the
   completion framework is loaded in interactive non-login shells, which is
   the default mode for VS Code's integrated terminal and devcontainer
   sessions.

   ```sh
   # Add to /etc/bash.bashrc (system-wide) or ~/.bashrc (per-user)
   if [ -f /usr/share/bash-completion/bash_completion ]; then
       . /usr/share/bash-completion/bash_completion
   fi
   ```

3. **Minimal container images**: Many base dev container images do not include
   bash-completion by default. The package must be explicitly installed using
   the distribution's package manager (see [OS Package Manager](#os-package-manager)).

4. **Testing**: To verify bash-completion is active in a dev container,
   start a new shell session and press Tab twice after typing a partial
   command (e.g., `systemctl <Tab><Tab>`). If completions appear, the
   framework is working.

## References

[^release-2170]: [GitHub Release — v2.17.0 (2025-10-31)](https://github.com/scop/bash-completion/releases/tag/2.17.0)
    — Latest stable release of bash-completion.

[^readme-install]: [README.md — Installation](https://github.com/scop/bash-completion/blob/main/README.md#installation)
    — Official installation instructions including package managers, manual sourcing, and build from source.

[^readme-macos]: [README.md — macOS (OS X)](https://github.com/scop/bash-completion/blob/main/README.md#macos-os-x)
    — macOS-specific installation and configuration instructions.

[^configure-ac]: [configure.ac](https://github.com/scop/bash-completion/blob/main/configure.ac)
    — Autotools configuration showing version, dependencies, platform detection, and output files.

[^makefile-am]: [Makefile.am](https://github.com/scop/bash-completion/blob/main/Makefile.am)
    — Build system showing installation paths for bash_completion, profile.d script, pkgconfig, completions directories.

[^src-bash-completion]: [bash_completion](https://github.com/scop/bash-completion/blob/main/bash_completion)
    — Main completion infrastructure file; documents version info, initialization, and core helper functions.

[^src-profiled]: [bash_completion.sh.in](https://github.com/scop/bash-completion/blob/main/bash_completion.sh.in)
    — Template for the profile.d entry-point script; shows loading logic, bash version check, and config hook.

[^faq-completionsdir]: [README.md — FAQ Q4 (Completions Directory)](https://github.com/scop/bash-completion/blob/main/README.md#q-i-authormaintainer-package-x-and-would-like-to-maintain-my-own-completion-code-for-this-package-where-should-i-put-it-to-be-sure-that-interactive-bash-shells-will-find-it-and-source-it)
    — Explanation of the completions directory and how third-party packages should install completion files.

[^faq-userdir]: [README.md — FAQ Q2 (Per-User Completions)](https://github.com/scop/bash-completion/blob/main/README.md#q-how-can-i-override-a-completion-shipped-by-bash-completion-or-install-a-new-completion-for-a-user-account)
    — User completion directories and startup files.

[^faq-helpersdir]: [README.md — FAQ Q4 (Helpers Directory)](https://github.com/scop/bash-completion/blob/main/README.md#q-i-authormaintainer-package-x-and-would-like-to-maintain-my-own-completion-code-for-this-package-where-should-i-put-it-to-be-sure-that-interactive-bash-shells-will-find-it-and-source-it)
    — Mentions the helpersdir variable from pkg-config.

[^faq-search-order]: [README.md — FAQ Q10 (Search Order)](https://github.com/scop/bash-completion/blob/main/README.md#q-what-is-the-search-order-for-the-completion-file-of-each-target-command)
    — Detailed search order for completion files including BASH_COMPLETION_USER_DIR, XDG_DATA_DIRS.

[^config-hook]: [README.md — Installation (Per-User Disable)](https://github.com/scop/bash-completion/blob/main/README.md#installation)
    — Describes the `$XDG_CONFIG_HOME/bash_completion` hook to prevent loading system-wide bash-completion.

[^brew-formula]: [Homebrew Formulae — bash-completion@2](https://formulae.brew.sh/formula/bash-completion@2)
    — Homebrew formula page for bash-completion v2.

[^brew-formula-code]: [Homebrew/homebrew-core — bash-completion@2.rb](https://github.com/Homebrew/homebrew-core/blob/bceca8aec8d45cbddeee6674417adb82afc70bbc/Formula/b/bash-completion@2.rb)
    — Homebrew formula source code showing installation steps, dependencies, and patches.

[^brew-deps]: [Homebrew API — bash-completion@2](https://formulae.brew.sh/api/formula/bash-completion@2.json)
    — Formula JSON API showing the dependency on `bash`.

[^brew-caveats]: [Homebrew Formulae — bash-completion@2 (Caveats)](https://formulae.brew.sh/formula/bash-completion@2)
    — Post-installation instructions printed by Homebrew.

[^brew-v1-vs-v2]: [Homebrew Discussion — Bash completion scripts directory](https://github.com/orgs/Homebrew/discussions/2575)
    — Explanation of the difference between bash-completion (v1, for Bash 3.2) and bash-completion@2 (v2, for Bash 4.2+).

[^brew-v2]: [Homebrew Formulae — bash-completion@2](https://formulae.brew.sh/formula/bash-completion@2)
    — "This formula is mainly for use with Bash 3. If you are using Homebrew's Bash or your system Bash is at least version 4.2, then you should install `bash-completion@2` instead."

[^macports]: [MacPorts — bash-completion](https://ports.macports.org/port/bash-completion/summary/)
    — MacPorts port for bash-completion.

[^repology]: [Repology — bash-completion](https://repology.org/project/bash-completion)
    — Comprehensive list of all OS distributions, package names, and available versions.

[^issue-devcontainer]: [devcontainers/features — Issue #1164](https://github.com/devcontainers/features/issues/1164)
    — Discussion of missing bash-completion in devcontainers due to non-login shells.
