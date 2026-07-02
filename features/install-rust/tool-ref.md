# Feature Reference

The Rust toolchain comprises a collection of tools for developing in the Rust programming language — a modern, type-safe, high-performance systems programming language focused on safety, concurrency, and speed. The core components are the `rustc` compiler, the `cargo` package manager and build system, and the `rustup` toolchain multiplexer/installer. Together they provide a complete development environment for building everything from embedded systems to web applications. Rust is developed in the open with a 6-week rapid release process, shipping stable, beta, and nightly release channels. The recommended and most common way to install the Rust toolchain is via `rustup`, which handles downloading, installing, updating, and switching between multiple Rust toolchains on any supported platform.

- **Homepage**: https://www.rust-lang.org
- **Source Code**: https://github.com/rust-lang/rust
- **Documentation**: https://doc.rust-lang.org/
- **Latest Release**: 1.96.1 (as of 2026-07-01)[^rust-release-1.96.1]

## Tool Architecture

The Rust toolchain has a layered architecture with several distinct components:

- **`rustup`** — The toolchain multiplexer and installer. It is the primary entry point for managing Rust installations. `rustup` downloads and manages multiple Rust toolchains (stable, beta, nightly, or specific versions) and makes them available through a set of proxy binaries installed to a single `bin` directory (typically `~/.cargo/bin`). These proxies — `rustc`, `cargo`, `rustdoc`, etc. — automatically delegate to the currently active toolchain. This design is analogous to Ruby's `rbenv`, Python's `pyenv`, or Node's `nvm`.[^rustup-concepts]
- **`rustc`** — The Rust compiler, which compiles Rust source code into machine code. It also includes `rustdoc`, the documentation generator. `rustc` is written in Rust and uses LLVM as its backend code generation framework.[^rustc-book]
- **`cargo`** — The Rust package manager and build tool. It downloads dependencies from [crates.io](https://crates.io) (the Rust community package registry), compiles packages, runs tests, generates documentation, and publishes packages. Cargo is also written in Rust.[^cargo-book]
- **Components** — Each toolchain includes several optional components managed via `rustup component`:[^rustup-components]
  - `rustc` — The Rust compiler and Rustdoc (required)
  - `cargo` — The package manager and build tool (required)
  - `rust-std` — The Rust standard library for the host target (required)
  - `rust-docs` — Local copy of Rust documentation
  - `rust-analyzer` — Language server for IDE integration
  - `clippy` — Linter providing extra checks for common mistakes
  - `rustfmt` — Code formatter
  - `miri` — Experimental Rust interpreter for checking undefined behavior
  - `rust-src` — Local copy of the standard library source code
  - `llvm-tools` — Collection of LLVM tools (unstable)
  - `rustc-dev` — Compiler as a library
  - `rust-mingw` — Linker and platform libraries for Windows GNU builds
- **Profiles** — Named groupings of components that `rustup` uses to determine which components to install with a toolchain:[^rustup-profiles]
  - `minimal` — Only `rustc`, `rust-std`, and `cargo`
  - `default` — `minimal` plus `rust-docs`, `rustfmt`, and `clippy`
  - `complete` — All components (not recommended; almost always fails)
- **Channels** — Rust is released to three channels on a 6-week cadence:[^rustup-channels]
  - `stable` — The current stable release, updated every 6 weeks
  - `beta` — The next stable release, updated weekly
  - `nightly` — Daily builds with experimental features

The toolchain is self-contained: the `rustup` binary itself is a statically-linked Rust executable that handles downloading and managing toolchain components from the official distribution servers (`https://static.rust-lang.org`). It does not rely on any runtime environment like the JVM, Node.js, or Python — the only system requirement is a C compiler and linker for compiling native code (provided by the system or installed separately). Cross-compilation to additional targets requires target-specific standard libraries (installed via `rustup target add`) and appropriate linkers/toolchains for the target platform.

## Installation Methods

There are several ways to install the Rust toolchain. The primary and recommended method is via `rustup` (the `rustup-init` script/executable). Alternative methods include using OS package managers, standalone installers (offline tarballs, MSI, PKG), and building from source.[^forge-standalone-installers] This section covers all major installation methods.

### `rustup-init` (Recommended)

#### Supported Platforms

- **All Linux distributions**: any Linux distribution with glibc or musl libc on supported architectures (`x86_64`, `aarch64`, `i686`, `armv7`, `riscv64gc`, etc.). The script auto-detects libc flavor and downloads the appropriate binary. No specific package manager is required — the `rustup-init.sh` script is self-contained and only needs `curl` or `wget` for downloading.[^rustup-init-sh]
- **macOS**: x86_64 (Intel) and aarch64 (Apple Silicon) with macOS 10.13+
- **Windows**: x86_64, i686, and aarch64 via `rustup-init.exe` (requires MSVC build tools or MSYS2/MinGW for GNU builds)
- **FreeBSD, NetBSD, illumos, Solaris**: via the Unix shell script
- **Alpine Linux**: `rustup-init.sh` supports Alpine Linux and other musl-based Linux distributions. The script auto-detects musl libc via `ldd --version` and downloads the appropriate musl-based `rustup-init` binary (e.g., `x86_64-unknown-linux-musl`). Rust's official Rustup binaries are distributed for `x86_64-unknown-linux-musl` and `aarch64-unknown-linux-musl` targets.[^rustup-init-sh] Note: some minimal Alpine installations may lack required utilities (e.g., `mktemp`), which need to be installed separately.

The official `rustup-init.sh` script performs automatic platform detection for the following OS/arch combinations (detected from `uname` and other system properties):[^rustup-init-sh]

**Operating Systems:**
- Linux (glibc and musl)
- macOS (Darwin)
- FreeBSD
- NetBSD
- DragonFly (BSD)
- illumos
- Solaris
- Windows (via MINGW/MSYS/CYGWIN — detected as `pc-windows-gnu`)
- Android (Linux kernel with Android userland)

**CPU Architectures:**
- `x86_64` (amd64)
- `i686` (32-bit x86)
- `aarch64` (ARM 64-bit)
- `armv7` (ARM v7 with hard-float)
- `arm` (ARM v6 with hard-float)
- `riscv64gc` (RISC-V 64-bit)
- `loongarch64` (LoongArch 64-bit)
- `powerpc`, `powerpc64`, `powerpc64le`
- `s390x`
- `mips`, `mips64`, `mipsel`, `mips64el`
- `sparcv9` (Solaris)

#### Dependencies

##### Common Dependencies

- **`curl`** or **`wget`** — One of these must be available for downloading the `rustup-init` binary. The script prefers `curl` but falls back to `wget`.[^rustup-init-sh]
- **`sh`** (POSIX-compliant shell) — The initial `rustup-init.sh` script is a POSIX shell script.
- **`uname`**, **`mktemp`**, **`chmod`**, **`mkdir`**, **`rm`**, **`rmdir`** — POSIX utilities verified by `need_cmd` at script startup; installation fails immediately if missing.[^rustup-init-sh]
- **`head`**, **`tail`**, **`grep`**, **`cut`**, **`printf`** — POSIX utilities used at runtime in helper functions but **not** pre-checked by `need_cmd`. The script will fail at the point of use if they are absent.[^rustup-init-sh]
- **C compiler and linker** — Required for compiling Rust code. On Linux this is typically `gcc` or `clang` with `binutils`. On macOS this is `clang` (from Xcode Command Line Tools). On Windows with MSVC target, this requires Visual Studio build tools.[^rust-book-install]
- **`rustup` executable architecture compatibility** — The pre-built `rustup-init` binary for the host target must be executable on the system. For Linux, this means glibc-based builds require glibc; musl-based builds require musl libc.[^rustup-other-install]

##### Platform-Specific Dependencies

- **Linux (glibc)**: `gcc` (`build-essential` on Debian/Ubuntu, `Development Tools` on RHEL/Fedora), `glibc-devel` (RHEL/Fedora) or `libc6-dev` (Debian/Ubuntu), `ca-certificates` (for HTTPS downloads), `git` (used by `cargo` for git-based dependencies; also used by some features for version lookup).[^devcontainers-rust-install]
- **Linux (musl/Alpine)**: `gcc`, `musl-dev`, `ca-certificates`, `git` — The `rustup-init.sh` script auto-detects musl libc and downloads the correct binary. Ensure `mktemp`, `curl` (or `wget`), and other POSIX utilities are available.[^rustup-init-sh]
- **macOS**: Xcode Command Line Tools (`xcode-select --install`), which provides `clang`, `ld`, and other required build tools.[^rust-book-install]
- **Windows (MSVC)**: Visual Studio 2017+ (or Visual C++ Build Tools) with "Desktop development with C++" workload, including MSVC v143 build tools and Windows SDK.[^rustup-msvc-prereqs]
- **Windows (GNU)**: MSYS2 with MinGW toolchain.[^rustup-other-install]
- **FreeBSD**: `gcc` (or `clang`), `binutils`

#### Installation Steps

The recommended installation process using `rustup-init` on Unix-like systems (Linux, macOS, FreeBSD, etc.) is:

1. **Download and run the installer script** (non-interactive, accepting defaults):
   ```sh
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
   ```
   
   Or with custom options:
   ```sh
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- \
     --default-toolchain stable \
     --profile minimal \
     --no-modify-path \
     -y
   ```

2. **What the script does internally**:[^rustup-init-sh]
   1. Detects the host platform (OS, CPU architecture, libc flavor) by examining `uname -s` and `uname -m`, ELF headers of `/proc/self/exe`, and other system properties.
   2. Creates a temporary directory with `mktemp -d`.
   3. Downloads the appropriate `rustup-init` binary for the detected target triple from `https://static.rust-lang.org/rustup/dist/{target-triple}/rustup-init` (or a custom `RUSTUP_UPDATE_ROOT`).
   4. Makes the downloaded binary executable.
   5. Runs the `rustup-init` binary, which:
      - Detects or prompts for the installation configuration (default host triple, default toolchain, whether to modify PATH).
      - Downloads and installs the requested toolchain from the release channel.
      - Sets up proxy binaries in `~/.cargo/bin` (unless `--no-modify-path` is used).
      - Creates or modifies shell profile files (`~/.profile`, `~/.bash_profile`, `~/.bashrc`, `~/.zshenv`) to add `~/.cargo/bin` to `PATH`.
      - Creates the `~/.cargo/env` file for manual sourcing.
   6. Removes the temporary directory and downloaded binary.

3. **Source the environment** (if not using `--no-modify-path`, the script should have already modified shell profiles; but for immediate use in the current shell):
   ```sh
   . "$HOME/.cargo/env"
   ```

4. **Windows installation**:
   - Download `rustup-init.exe` from https://win.rustup.rs (auto-detects architecture) or directly from https://static.rust-lang.org/rustup/dist/{target-triple}/rustup-init.exe
   - Run the executable; it will detect MSVC build tools and prompt for configuration.
   - Or run non-interactively: `rustup-init.exe -y --default-toolchain stable --profile minimal`
   
   The Windows installer works the same way as the Unix script — it downloads the appropriate toolchain and installs it.[^rustup-other-install]

5. **Verify installation**:
   ```sh
   rustc --version
   cargo --version
   rustup --version
   ```

#### Installation Verification

- **SHA-256 checksums**: The official `rustup-init` binaries are distributed alongside `.sha256` checksum files, available at the same download URL with `.sha256` appended. For example: `https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init.sha256`.[^rustup-other-install]
- **Version check**: After installation, verify that `rustc --version`, `cargo --version`, and `rustup --version` report the expected versions and are executable from `~/.cargo/bin/`.
- **Rust toolchain files**: The installed toolchain is stored under `~/.rustup/toolchains/` (or `$RUSTUP_HOME/toolchains/`). Installed components can be listed with `rustup component list`.
- **`rustc --version` output example**:
  ```
  rustc 1.96.1 (9820e2c6a 2026-06-11)
  ```
- **`cargo --version` output example**:
  ```
  cargo 1.96.1 (1c429c8f0 2026-05-28)
  ```

#### Configuration Options

##### Version Selection

The version of Rust to install is specified via the `--default-toolchain` argument to `rustup-init`:[^rustup-init-sh]

- `--default-toolchain stable` — Install the latest stable release (default)
- `--default-toolchain beta` — Install the latest beta release
- `--default-toolchain nightly` — Install the latest nightly release
- `--default-toolchain 1.85.0` — Install a specific version
- `--default-toolchain nightly-2026-05-01` — Install a specific nightly by date
- `--default-toolchain none` — Install `rustup` without installing any toolchain (useful for multi-stage setup)

The RUSTUP_VERSION environment variable can also be set to pin the `rustup` version itself. If unset, the latest version of `rustup` is downloaded.[^rustup-init-sh]

##### Installation Path

The installation paths are controlled by two environment variables:[^rustup-installation]

- `CARGO_HOME` (default: `~/.cargo` or `%USERPROFILE%\.cargo`) — Location of Cargo's cache, configuration, and installed binaries. The `bin/` subdirectory contains the proxy binaries and is the primary entry point for all Rust tools. This is a Cargo environment variable, documented in The Cargo Book.[^cargo-book]
- `RUSTUP_HOME` (default: `~/.rustup` or `%USERPROFILE%\.rustup`) — Location where `rustup` stores installed toolchains, configuration, and metadata. Documented in the rustup book.[^rustup-env-vars]

These must be set before running `rustup-init`. If set, they must also be persisted in the environment for subsequent `rustup` and `cargo` usage. The `CARGO_HOME/bin` directory must be on `PATH` for tools to be accessible.[^rustup-installation]

##### User Targeting

- **User-local installation (default)**: `rustup-init` installs to the user's home directory (`~/.cargo`, `~/.rustup`) and does not require root privileges. This is the recommended and default mode.[^rust-book-install]
- **System-wide installation**: By setting `CARGO_HOME` and `RUSTUP_HOME` to system-wide locations (e.g., `/usr/local/cargo` and `/usr/local/rustup`) and running with appropriate permissions, a system-wide installation is possible. This is how many devcontainer features install Rust.[^devcontainers-rust-install]

##### Required Privileges

- **User-local installation**: No special privileges required — `rustup-init` writes only to the user's home directory.[^rust-book-install]
- **System-wide installation**: Requires `root`/`sudo` privileges to create and write to system directories.

##### Tool-Specific Configurations

The `rustup-init` executable accepts the following command-line flags:[^rustup-init-sh]

| Flag | Description |
|------|-------------|
| `-h`, `--help` | Print help information and exit |
| `-V`, `--version` | Print version information and exit |
| `-y`, `--yes` | Disable the confirmation prompt (non-interactive) |
| `-v`, `--verbose` | Enable verbose (DEBUG-level) logging |
| `-q`, `--quiet` | Disable progress output, set log level to `WARN` (if `RUSTUP_LOG` is unset) |
| `--default-host <HOST>` | Override the detected host target triple (e.g., `x86_64-pc-windows-gnu`) |
| `--default-toolchain <TOOLCHAIN>` | Set the default toolchain to install (e.g., `stable`, `nightly`, `1.85.0`, `none`) |
| `--profile <PROFILE>` | Select the install profile: `minimal`, `default`, or `complete` (default: `default`) |
| `-c`, `--component <COMPONENT>` | Comma-separated list of additional components to install (e.g., `rust-analyzer,clippy`) |
| `-t`, `--target <TARGET>` | Comma-separated list of additional targets to install (e.g., `wasm32-unknown-unknown`) |
| `--no-update-default-toolchain` | Don't update any existing default toolchain |
| `--no-modify-path` | Don't modify `PATH` environment variable or shell profile files |

**Environment variables** affecting `rustup` behavior (can be set before running `rustup-init`):[^rustup-env-vars]

| Variable | Default | Description |
|----------|---------|-------------|
| `RUSTUP_HOME` | `~/.rustup` | Root directory for rustup data[^rustup-installation] |
| `CARGO_HOME` | `~/.cargo` | Root directory for Cargo data (this is a Cargo variable, documented in the Cargo book)[^cargo-book] |
| `RUSTUP_DIST_SERVER` | `https://static.rust-lang.org` | Root URL for downloading Rust distribution artifacts (for mirrors) |
| `RUSTUP_UPDATE_ROOT` | `https://static.rust-lang.org/rustup` | Root URL for downloading rustup self-updates |
| `RUSTUP_VERSION` | (none) | Pins a specific rustup version to install |
| `RUSTUP_TOOLCHAIN` | (none) | Overrides the active toolchain for all invocations |
| `RUSTUP_AUTO_INSTALL` | `1` | Auto-install missing toolchains (set to `0` to disable) |
| `RUSTUP_DOWNLOAD_TIMEOUT` *(unstable)* | `180` | Timeout in seconds for component downloads |
| `RUSTUP_CONCURRENT_DOWNLOADS` *(unstable)* | `2` | Number of concurrent downloads |
| `RUSTUP_IO_THREADS` *(unstable)* | auto (max 8) | Number of threads for performing close IO |
| `RUSTUP_TERM_COLOR` | `auto` | Color output: `auto`, `always`, or `never` |
| `RUSTUP_TERM_PROGRESS_WHEN` | `auto` | Progress bar display: `always`, `never`, or `auto` |
| `RUSTUP_PERMIT_COPY_RENAME` *(unstable)* | (unset) | Permit copy+rename in place of atomic rename on OverlayFS (Docker) — sacrifices transactional safety[^rustup-env-vars] |
| `RUSTUP_LOG` | (none) | Custom logging mode with `tracing_subscriber` directive syntax |
| `RUSTUP_NO_BACKTRACE` | (none) | Disable backtraces on non-panic errors |
| `RUSTUP_UNPACK_RAM` *(unstable)* | free memory or 500MiB, min 210MiB | Caps RAM (in bytes) used for IO during unpacking |
| `RUSTUP_TRACE_DIR` *(unstable)* | (none) | Enable tracing output directory |
| `RUSTUP_HARDLINK_PROXIES` *(unstable)* | (unset) | Force hardlinks instead of symlinks for proxy binaries |
| `RUSTUP_TERM_WIDTH` | (none) | Override terminal width for progress bars |
| `RUSTUP_TOOLCHAIN_SOURCE` *(unstable)* | (none) | Set by rustup to tell proxied tools how the toolchain was determined; should not be set manually |

#### Post-Installation Steps and Cleanup

##### PATH Setup

After installation, the `bin` directory within `CARGO_HOME` (typically `~/.cargo/bin` on Unix or `%USERPROFILE%\.cargo\bin` on Windows) must be added to `PATH` for the Rust tools to be accessible from the command line. When running `rustup-init` with the default settings (without `--no-modify-path`), the installer automatically modifies the shell profile files to add this directory to `PATH`.[^rustup-installation]

Files modified on Unix:
- `~/.profile` (login shells)
- `~/.bash_profile` (if exists) or `~/.bashrc` (if Bash)
- `~/.zshenv` (if Zsh)

The installer also creates `~/.cargo/env`, a shell script that can be sourced manually:
```sh
source "$HOME/.cargo/env"
```

If `--no-modify-path` was used, the system administrator must ensure `CARGO_HOME/bin` is on `PATH` through other means (e.g., by adding it to `/etc/environment`, `/etc/profile.d/`, or shell initialization files).

For **system-wide installations**, the PATH should typically be configured via `/etc/profile.d/` scripts or `/etc/environment`.

##### Configuration Files

`rustup` stores its configuration in a TOML file at `$RUSTUP_HOME/settings.toml` (default: `~/.rustup/settings.toml`). The schema is not part of the public interface — the `rustup` CLI should be used to query and set settings rather than editing the file directly. On Unix, a fallback settings file `/etc/rustup/settings.toml` can define `default_toolchain`.[^rustup-config]

##### Environment Variables

The following environment variables should be set persistently for all users of the Rust toolchain (typically via shell profile files or `/etc/environment`):[^rustup-env-vars]

- `CARGO_HOME=/usr/local/cargo` (if using system-wide install)
- `RUSTUP_HOME=/usr/local/rustup` (if using system-wide install)
- `PATH` must include `$CARGO_HOME/bin` (e.g., `export PATH="$CARGO_HOME/bin:$PATH"`)

##### Activation Scripts

The `~/.cargo/env` file (on Unix) or the PATH modifications made by the installer serve as the activation mechanism. There is no separate activation script or virtual environment activation required.

##### Shell Completions

`rustup` supports generating completion scripts for Bash, Fish, Zsh, and PowerShell. After installation, completions can be generated with:[^rustup-installation]

```sh
# Bash (user-local, no root required)
rustup completions bash > ~/.local/share/bash-completion/completions/rustup

# Bash (system-wide, common path for bash-completion package)
sudo rustup completions bash > /usr/share/bash-completion/completions/rustup

# Bash (macOS/Homebrew)
rustup completions bash > $(brew --prefix)/etc/bash_completion.d/rustup.bash-completion

# Fish
mkdir -p ~/.config/fish/completions
rustup completions fish > ~/.config/fish/completions/rustup.fish

# Zsh
mkdir -p ~/.zfunc
rustup completions zsh > ~/.zfunc/_rustup
# Then add in ~/.zshrc: fpath+=~/.zfunc (before compinit)

# PowerShell
rustup completions powershell >> $PROFILE.CurrentUserCurrentHost
```

##### Cleanup

The `rustup-init.sh` script automatically removes the temporary directory and downloaded binary after installation. No further cleanup is necessary for a successful installation. If the download fails or is interrupted, temporary files may remain in `/tmp/` — these can be safely deleted manually.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- **Upgrading to the latest release**: `rustup update` — updates all installed toolchains to their latest versions and updates `rustup` itself.
- **Installing additional toolchains**: `rustup toolchain install <toolchain>` (e.g., `rustup toolchain install nightly`). When installing nightly with specific components, use `--allow-downgrade` to select an older nightly if the latest is missing required components (e.g., `rustup toolchain install nightly --allow-downgrade --profile minimal --component clippy`).[^rustup-installation]
- **Changing the default toolchain**: `rustup default <toolchain>` (e.g., `rustup default nightly` or `rustup default 1.85.0`).
- **Using a specific toolchain per project**: `rustup override set <toolchain>` in a project directory, or use a `rust-toolchain.toml` / `rust-toolchain` file in the project root.
- **Changing the default install profile**: `rustup set profile <profile>` to change which components are installed by default for new toolchains (e.g., `rustup set profile minimal`).[^rustup-profiles]

Multiple toolchains can coexist. Changing versions does not affect existing configuration files or environment variable settings — only the proxies in `CARGO_HOME/bin` are updated/repointed.[^rustup-toolchains]

##### Uninstallation

To completely remove `rustup` and all installed toolchains:[^rustup-installation]

```sh
rustup self uninstall
```

This command removes:
- All installed toolchains and their components
- The `RUSTUP_HOME` directory
- The `CARGO_HOME` directory (including all Cargo-installed binaries, projects, and caches)
- Shell profile modifications made during installation

To manually uninstall (without `rustup`):
- Remove the `~/.rustup` (`%USERPROFILE%\.rustup`) and `~/.cargo` (`%USERPROFILE%\.cargo`) directories
- Remove `~/.cargo/bin` from `PATH` in shell profile files
- Remove any `rustup` completions scripts

Uninstallation requires no special privileges for user-local installations. For system-wide installations, root privileges are required.

##### Idempotency

Running `rustup-init` downloads and runs the latest `rustup-init` binary.[^rustup-init-sh] When run on a system where `rustup` is already installed, the binary will detect the existing installation and allow updating `rustup` itself.[^rustup-installation] The toolchain installation itself is idempotent — running `rustup toolchain install stable` when stable is already at the latest version will be a no-op. When a specific version is requested and already installed, it will not be re-downloaded. The `rustup update` command is also idempotent — it only downloads toolchain updates when newer versions are available.[^rustup-installation]

#### Details

The `rustup-init.sh` script (≈930 lines of POSIX shell code) performs the following detailed sequence:[^rustup-init-sh]

1. **Platform detection** (`get_architecture` function):
   - Runs `uname -s` to get the OS type (Linux, Darwin, FreeBSD, etc.)
   - Runs `uname -m` to get the CPU architecture
   - For Linux: detects musl vs glibc by checking `ldd --version` output
   - For macOS: uses `sysctl` to detect Rosetta 2 (x86_64 emulation on Apple Silicon) and the actual architecture
   - For Windows MINGW/MSYS: detected via `uname -s` patterns
   - Determines 32-bit vs 64-bit userland by examining the ELF header of `/proc/self/exe`
   - On armv7 Linux, checks `/proc/cpuinfo` for NEON/SIMD support
   - Returns a target triple like `x86_64-unknown-linux-gnu`

2. **Downloader selection** (`downloader` function):
   - Prefers `curl` over `wget`, with security checks:
     - For `curl`: uses `--proto '=https' --tlsv1.2` to enforce HTTPS and TLS 1.2+
     - For `wget`: uses `--https-only --secure-protocol=TLSv1_2`
     - Supports `--retry 3 -C -` for curl to resume interrupted downloads
     - Enforces strong TLS cipher suites (AES-128-GCM, CHACHA20-POLY1305, AES-256-GCM) via `--ciphers`
    - Detects "snap" curl on Linux and falls back to `wget` if available; errors out with instructions to reinstall curl via a non-snap package manager if neither works

3. **Binary download**:
   - Constructs the download URL: `$RUSTUP_UPDATE_ROOT/dist/$ARCH/rustup-init` (or with `$RUSTUP_VERSION` under `archive/` subpath)
   - Downloads the `rustup-init` binary and makes it executable

4. **Execution**:
    - If stdin is not a terminal (piped script scenario) and stdout is a terminal (`[ -t 1 ]`), connects `/dev/tty` to the installer's stdin for interactive prompts
    - If both stdin and stdout are non-TTY (fully non-interactive without `-y`), the script errors out: "Unable to run interactively. Run with -y to accept defaults, --help for additional options"
   - Runs the downloaded `rustup-init` binary with any passed arguments and the auto-detected `--default-host` flag (for Windows)
   - On success, removes the temporary files

The official `rustup-init` and `rustup` executables are themselves written in Rust. The source code is at https://github.com/rust-lang/rustup.

#### Notes and Best Practices

- **Non-interactive installation**: Always use the `-y` flag when automating installation in scripts or containers: `sh -s -- -y`.
- **Installation profiles**: For CI/CD environments or containers where disk space is at a premium, use `--profile minimal`, which only installs `rustc`, `cargo`, and `rust-std`. The `default` profile is recommended for interactive development.
- **Avoiding PATH modification**: Use `--no-modify-path` in container environments where PATH is managed independently.
- **Alpine Linux**: The `rustup-init.sh` script works on Alpine Linux — it detects musl libc automatically. Ensure `mktemp`, `curl` (or `wget`), and other POSIX utilities are available. If the script fails, manually download the `x86_64-unknown-linux-musl` or `aarch64-unknown-linux-musl` `rustup-init` binary and run it directly.[^rustup-init-sh]
- **Running as root**: Installing `rustup` as root and then running `cargo install` or `rustup` should be avoided for security reasons. When system-wide installation is needed, install as root and create a dedicated group (e.g., `rustlang`) with appropriate permissions.[^devcontainers-rust-install]
- **OverlayFS / Docker**: On OverlayFS (common in Docker), file renames can produce cross-device link errors. Set `RUSTUP_PERMIT_COPY_RENAME=1` to work around this (though it sacrifices some transactional protections).[^rustup-env-vars]
- **Nightly component availability**: Nightly builds may be missing certain non-default components. Use `rustup toolchain install nightly --allow-downgrade --profile minimal --component clippy` to install a nightly toolchain that includes specific components even if the latest nightly doesn't have them.[^rustup-installation]
- **GPG signatures**: Standalone installers are signed with the Rust signing key, but `rustup` itself does not verify these signatures — it relies on HTTPS for transport security.

### Standalone Installers

#### Supported Platforms

Standalone installers are available for all Tier 1 and Tier 2 Rust targets. They come in three forms:[^forge-standalone-installers]

- **Unix-like** (Linux, macOS, FreeBSD, etc.): `.tar.xz` archives
- **Windows**: `.msi` installers
- **macOS**: `.pkg` installers

#### Dependencies

##### Common Dependencies

Same as `rustup-init` — requires a C compiler and linker for compiling Rust code. No additional dependencies beyond system libraries.

##### Platform-Specific Dependencies

None unique to standalone installers.

#### Installation Steps

1. Download the appropriate standalone installer for the target channel and platform from `https://static.rust-lang.org/dist/`.
2. Extract the archive:
    ```sh
    curl -LO https://static.rust-lang.org/dist/rust-1.96.1-x86_64-unknown-linux-gnu.tar.xz
    tar -xf rust-1.96.1-x86_64-unknown-linux-gnu.tar.xz
    cd rust-1.96.1-x86_64-unknown-linux-gnu
    ```
3. Run the installation script:
   ```sh
   sudo ./install.sh
   ```
   (The `install.sh` script accepts `--prefix=` to customize the installation path.)
4. On Windows, run the `.msi` installer (graphical).
5. On macOS, run the `.pkg` installer (graphical).

#### Installation Verification

Standalone installers are signed with the Rust GPG signing key. Signatures (`.asc` files) are available alongside the downloads. GPG verification can be done with:[^forge-standalone-installers]
```sh
gpg --verify rust-1.96.1-x86_64-unknown-linux-gnu.tar.xz.asc
```

Standalone installer archives have SHA-256 checksums available through two mechanisms. First, the channel manifest (e.g., `channel-rust-stable.toml`) includes `hash` and `xz_hash` fields for each package/target entry, providing integrity verification through rustup's standard update mechanism.[^forge-channel-layout] Second, `.sha256` sidecar files exist alongside the archives (e.g., `rust-1.96.1-x86_64-unknown-linux-gnu.tar.xz.sha256`), following the same URL pattern as the archives — appending `.sha256` to the archive URL.[^rustup-other-install] The Rust Forge page only documents GPG signatures (.asc) for standalone installers; the SHA-256 files follow a naming convention analogous to the rustup-init checksum files documented in the rustup book.

The Rust signing key is available at https://static.rust-lang.org/rust-key.gpg.ascii.

#### Configuration Options

##### Version Selection

The version to install is determined by which installer archive is downloaded. Archives are available for stable, beta, and nightly releases, with specific version numbers and dates. For example:
- `rust-1.96.1-x86_64-unknown-linux-gnu.tar.xz` (specific stable version)
- `rust-beta-x86_64-unknown-linux-gnu.tar.xz` (latest beta)
- `rust-nightly-x86_64-unknown-linux-gnu.tar.xz` (latest nightly)

##### Installation Path

On Unix, the `install.sh` script accepts `--prefix` to customize the installation path:[^forge-standalone-installers]

```sh
sudo ./install.sh --prefix=/opt/rust
```

The default prefix is `/usr/local`. On Windows, MSI installers prompt for the installation directory. On macOS, PKG installers install to `/usr/local` (binaries to `/usr/local/bin`, libraries to `/usr/local/lib/rustlib/`).[^rust-installer-template]

##### User Targeting

Standalone installers always install system-wide (require root/sudo on Unix). There is no user-local installation option — use `rustup` for that.

##### Required Privileges

On Unix, the `install.sh` script writes to system directories and typically needs to be run with `sudo` (e.g., `sudo ./install.sh`). On Windows, MSI installers may prompt for administrator elevation.

##### Tool-Specific Configurations

Standalone installers have minimal configuration options:
- `--prefix=<path>` — Set the installation prefix (Unix only)[^forge-standalone-installers]
- `--disable-ldconfig` — Skip running ldconfig after installation (Linux only)[^rust-installer-template]
- No post-install configuration is created (no `settings.toml`, no profile modifications)

#### Post-Installation Steps and Cleanup

##### PATH Setup

Standalone installers place binaries in `/usr/local/bin` by default (or in the directory specified by `--prefix`). Ensure this directory is on `PATH` for the tools to be accessible.

##### Configuration Files

Standalone installers do not create any configuration files. No `settings.toml` is created — use `rustup` for toolchain management.

##### Environment Variables

Standalone installers do not set any environment variables. The installation prefix's `bin` directory must be manually added to `PATH`.

##### Activation Scripts

No activation scripts are provided. The installed binaries are available immediately after installation (subject to `PATH` configuration).

##### Shell Completions

Standalone installers do not provide shell completion scripts. Use `rustup` for completion support.

##### Cleanup

No temporary files are left behind by the standalone installer. The downloaded archive can be deleted after extraction and installation.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

Standalone installers do not support version management. To switch versions, download and install a different version's archive — this will overwrite the previous installation. Different versions cannot easily coexist; `rustup` is recommended for multi-version management.

##### Uninstallation

To uninstall, run the uninstall script included in the installed directory (e.g., `/usr/local/lib/rustlib/uninstall.sh`) or remove the Rust files manually from `/usr/local/lib/rustlib/` and the binaries from `/usr/local/bin/`.[^rust-installer-readme]

##### Idempotency

Re-running the same standalone installer version overwrites the previous installation with identical files and is effectively a no-op.

#### Details

The standalone installer `install.sh` (and its macOS `.pkg` and Windows `.msi` equivalents) is generated from the `rust-installer` template (`src/tools/rust-installer/install-template.sh` in the Rust repository). It copies files from the extracted archive into the target prefix directory, runs `ldconfig` on Linux to register shared libraries (unless `--disable-ldconfig` is specified), and creates an installation manifest and uninstall script in `$libdir/rustlib/`.[^rust-installer-template]

#### Notes and Best Practices

Standalone installers are primarily intended for offline installation or for users who prefer not to use `rustup`. They do not provide the following `rustup` features:
- Multiple toolchain management
- Cross-compilation target management
- Easy version switching
- Automatic updates via `rustup update`

### OS Package Manager Installation

#### Supported Platforms

- **Debian/Ubuntu**: `apt install rustup` (available on Debian 13+ and Ubuntu 24.04+)
- **macOS**: `brew install rustup` (Homebrew)
- **Arch Linux**: `pacman -S rustup`
- **Fedora/RHEL**: `dnf install rustup` (rustup-init provided)
- **Alpine Linux**: `apk add rustup` (available from the community repository)[^alpine-rustup]

Note: These packages are maintained by the respective distributions, not by the Rust project. The `rustup` package installs the `rustup-init` command, which must then be run to actually install a Rust toolchain.[^rustup-other-install]

#### Dependencies

##### Common Dependencies

Same as the respective OS package manager's requirements, plus the same build dependencies as `rustup-init`.

##### Platform-Specific Dependencies

None beyond the OS package manager itself.

#### Installation Steps

```sh
# Debian/Ubuntu 24.04+
sudo apt update && sudo apt install -y rustup
rustup default stable

# macOS (Homebrew)
brew install rustup
# The rustup formula is keg-only; if rustup is not on PATH, add it:
# export PATH="$(brew --prefix rustup)/bin:$PATH"
rustup default stable

# Arch Linux
sudo pacman -S rustup
rustup default stable

# Fedora
sudo dnf install rustup
rustup-init -y
```

#### Installation Verification

Same as `rustup-init` — `rustc --version`, `cargo --version`, `rustup --version`.

#### Configuration Options

##### Version Selection

The version provided by the OS package manager is determined by the distribution's package repositories and typically lags behind the latest upstream release. To use a different version, install `rustup` from the package manager and then use `rustup` to install the desired toolchain version (e.g., `rustup toolchain install 1.85.0`).

##### Installation Path

Installation paths are determined by the OS package manager conventions:
- **APT** (Debian/Ubuntu): Files installed to system directories (/usr/bin, /usr/lib, etc.)
- **Homebrew** (macOS): Files installed to the Homebrew prefix (/opt/homebrew or /usr/local)
- **Pacman** (Arch): Files installed to /usr/bin, /usr/lib, etc.

##### User Targeting

OS package manager installations are always system-wide.

##### Required Privileges

All OS package manager installations require `sudo` (or equivalent administrative privileges) to install packages.

##### Tool-Specific Configurations

The OS package manager itself does not offer Rust-specific configuration options. After installation, `rustup` must be used to select a default toolchain (e.g., `rustup default stable`) and manage components and targets.

#### Post-Installation Steps and Cleanup

##### PATH Setup

For APT and Pacman-managed installations, the `rustup` binary is typically in `/usr/bin` and is on `PATH` automatically. For Homebrew's keg-only formula, the `rustup` binary must be added to `PATH` manually (e.g., `export PATH="$(brew --prefix rustup)/bin:$PATH"`).

After installing the `rustup` package from the OS package manager, users must still run `rustup default stable` (or another toolchain variant) to download and install an actual Rust toolchain. The OS package only provides the `rustup` manager itself.

##### Configuration Files

The OS package manager may install a default `settings.toml` configuration file. Refer to the distribution's documentation for details.

##### Environment Variables

The OS package manager installation itself does not set `CARGO_HOME` or `RUSTUP_HOME`. These are managed by `rustup` at runtime.

##### Activation Scripts

No activation scripts are created by the OS package manager. After installing a toolchain with `rustup default stable`, the Rust proxy binaries (in `~/.cargo/bin`) must be on `PATH`.

##### Shell Completions

Shell completions are managed through the OS package manager if provided, or can be generated via `rustup completions` as described in the `rustup-init` section.

##### Cleanup

OS package manager installations are cleaned up through the package manager itself (e.g., `apt remove rustup`, `pacman -R rustup`, `brew uninstall rustup`).

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

The `rustup` package itself is upgraded through the OS package manager's normal update process. The installed Rust toolchains (managed by `rustup`) are updated independently via `rustup update`.

On Arch Linux, `rustup self update` will **not** work when installed via `pacman`; `rustup` itself must always be updated through `pacman`.[^archlinux-wiki-rust]

##### Uninstallation

To remove the OS package manager installation of `rustup`: use the package manager's remove command (e.g., `apt remove rustup`, `pacman -R rustup`, `brew uninstall rustup`). This removes the `rustup` binary and associated system files but does **not** remove user-local toolchain installations under `~/.rustup/` or `~/.cargo/`. Those must be removed separately if desired.

##### Idempotency

Re-installing the `rustup` package via the OS package manager is idempotent — the package manager detects that the package is already installed at the latest version and does nothing.

#### Details

The OS package manager's `rustup` packages typically install the `rustup-init` binary (or the `rustup` binary itself for newer distributions). On Debian-based systems (Debian 13+, Ubuntu 24.04+), the package installs the `rustup` binary with symlinks for `rustc` and `cargo`. On Arch Linux, the package provides `rustup` with symlinks to common Rust executables in `/usr/bin/`. The Homebrew formula is keg-only, meaning it does not create symlinks in `/usr/local/bin` to avoid conflicts with the Rust toolchain installed via `rustup-init.sh`.

#### Notes and Best Practices

- The system package manager version of `rustup` may lag behind the latest release. Consider using the official `rustup-init.sh` script for the most up-to-date version.
- On Debian-based systems, the `rustup` package installs the `rustup-init` command, which then needs to be run to complete installation. Some distributions (APT on Debian 13+, pacman) provide the `rustup` command with proxies for Rust tools directly.
- The Homebrew `rustup` formula is keg-only — the `rustup` binary is not linked into `/usr/local/bin` by default. Add `$(brew --prefix rustup)/bin` to `PATH` if needed.
- On Arch Linux, `rustup self update` will **not** work when installed via `pacman`; the package must be updated by `pacman` itself. This limitation does not affect other `rustup` functionality such as `rustup update` for updating Rust toolchains.[^archlinux-wiki-rust]

## Dev Container Setup

When installing the Rust toolchain in a devcontainer environment, the following considerations apply:

- **Base images**: The feature should work on Debian/Ubuntu, RHEL/Fedora, Alpine, and other Linux distributions that have `apt`, `dnf`, `yum`, `microdnf`, `tdnf`, or `apk` available. The official devcontainers Rust feature does **not** support Alpine for two reasons: (a) its `install.sh` only handles `apt`, `dnf`, `yum`, `microdnf`, and `tdnf` as package managers — it does not recognize `apk`, so installation fails before any download occurs; and (b) it unconditionally downloads the glibc-based `x86_64-unknown-linux-gnu` `rustup-init` binary, which requires glibc. The upstream `rustup-init.sh` script works on Alpine because it identifies the platform as `x86_64-unknown-linux-musl` and downloads the musl-linked binary accordingly, with no package manager dependency for the initial download.[^devcontainers-rust-readme][^rustup-init-sh]
- **System-wide installation**: In a devcontainer, Rust should typically be installed system-wide (to `/usr/local/cargo` and `/usr/local/rustup`) rather than to a user's home directory. This ensures that the toolchain is available to all users and persists across container rebuilds.[^devcontainers-rust-install]
- **The `rustlang` group**: The official devcontainers Rust feature creates a `rustlang` group and makes the `CARGO_HOME` and `RUSTUP_HOME` directories group-writable so that non-root users can install Cargo packages and manage toolchains.[^devcontainers-rust-install]
- **`SYS_PTRACE` capability**: The official devcontainers Rust feature requests the `SYS_PTRACE` capability, which is needed by `rust-lldb` and other debugging tools for process tracing. The `seccomp=unconfined` security option may also be required.[^devcontainers-rust-json]
- **`--no-modify-path`**: In containers, it's best practice to use `--no-modify-path` to avoid modifying shell profiles, since the devcontainer environment typically manages PATH via `/etc/profile.d/` or `containerEnv` in `devcontainer.json`.
- **`containerEnv`**: The official devcontainers Rust feature sets `CARGO_HOME`, `RUSTUP_HOME`, and PATH via `containerEnv` in `devcontainer-feature.json`, which ensures these are set correctly for all users without relying on shell profile files.[^devcontainers-rust-json]
- **Platform architecture detection**: Container environments may use `dpkg --print-architecture` (Debian-based) or `uname -m` to determine the architecture for downloading the correct `rustup-init` binary. The mapping is: `amd64`/`x86_64` → `x86_64`, `arm64`/`aarch64` → `aarch64`.[^devcontainers-rust-install]
- **SHA-256 verification**: The official devcontainers Rust feature downloads and verifies the SHA-256 checksum of the `rustup-init` binary before execution to ensure integrity.[^devcontainers-rust-install]
- **Official devcontainer Rust image**: A pre-built Rust devcontainer image is available at `mcr.microsoft.com/devcontainers/rust:latest` (based on Debian). This image already has the Rust toolchain installed and is ready to use without additional features.[^devcontainers-rust-image]
- **Recommended VS Code extensions** (from the official feature):[^devcontainers-rust-json]
  - `vadimcn.vscode-lldb` — Native debugger
  - `rust-lang.rust-analyzer` — Rust language server
  - `tamasfe.even-better-toml` — TOML file support

## Plugins and Extensions

### rust-analyzer

**rust-analyzer** is a language server for Rust that provides IDE features such as code completion, go-to-definition, find references, inline documentation, refactoring, and more. It is the official successor to the now-deprecated RLS (Rust Language Server).

- **Homepage**: https://rust-analyzer.github.io/
- **Source Code**: https://github.com/rust-lang/rust-analyzer
- **Documentation**: https://rust-analyzer.github.io/manual.html
- **Installation**: rust-analyzer is available as a Rustup component:
  ```sh
  rustup component add rust-analyzer
  ```
  The server binary is installed to `$CARGO_HOME/bin/rust-analyzer`. For full source-level IDE features (go-to-definition for standard library types, inline documentation, etc.), add the `rust-src` component as well:
  ```sh
  rustup component add rust-src
  ```
  Editor integration varies:
  - **VS Code**: Install the `rust-lang.rust-analyzer` extension
  - **Vim/Neovim**: Use the `rust-analyzer` language server with `coc.nvim`, `vim-lsp`, or `nvim-lspconfig`
  - **Emacs**: Use `eglot` or `lsp-mode`
  - **Helix**: Built-in support for rust-analyzer
- **Configuration**: rust-analyzer is configured via `.vscode/settings.json` (in VS Code) or via LSP client configuration in other editors. Key settings include `rust-analyzer.cargo.allFeatures` (default: `false`), `rust-analyzer.check.command` (default: `check`), and `rust-analyzer.linkedProjects`.

### Clippy

**Clippy** is the official Rust linter, providing a vast collection of checks for common mistakes and stylistic issues. It is distributed as a Rustup component.

- **Homepage**: https://github.com/rust-lang/rust-clippy
- **Documentation**: https://doc.rust-lang.org/clippy/
- **Installation**: `rustup component add clippy`
- **Usage**: `cargo clippy` or `cargo clippy --fix` to auto-fix issues
- **Configuration**: Configured via `clippy.toml` or `.clippy.toml` files, or through `[lints.clippy]` sections in `Cargo.toml`. Individual lint levels can be controlled with `#[allow(clippy::some_lint)]`, `#[warn(clippy::some_lint)]`, etc.

### Rustfmt

**Rustfmt** is the official Rust code formatter, ensuring consistent code style across projects.

- **Homepage**: https://github.com/rust-lang/rustfmt
- **Documentation**: https://doc.rust-lang.org/rustfmt/
- **Installation**: `rustup component add rustfmt`
- **Usage**: `cargo fmt` to format all files, `cargo fmt --check` to verify formatting
- **Configuration**: Configured via `rustfmt.toml` or `.rustfmt.toml` files. Common options include `max_width`, `tab_spaces`, `edition`, and `imports_granularity`.

## References

[^rust-release-1.96.1]: [Rust Releases — 1.96.1 - GitHub](https://github.com/rust-lang/rust/releases/tag/1.96.1). The latest stable Rust release as of this writing (2026-07-01). Also verified at [releases.rs](https://releases.rs/).

[^rustup-concepts]: [The rustup book — Concepts](https://rust-lang.github.io/rustup/concepts/index.html). Overview of how rustup works, including toolchain multiplexing, proxy binaries, and terminology.

[^rustc-book]: [The rustc book](https://doc.rust-lang.org/rustc/). Official documentation for the Rust compiler, including its architecture and LLVM backend.

[^cargo-book]: [The Cargo Book](https://doc.rust-lang.org/cargo/). Official documentation for Cargo, the Rust package manager. Documents `CARGO_HOME` in its [configuration chapter](https://doc.rust-lang.org/cargo/reference/config.html).

[^rustup-components]: [The rustup book — Components](https://rust-lang.github.io/rustup/concepts/components.html). Lists all available rustup components and their descriptions.

[^rustup-profiles]: [The rustup book — Profiles](https://rust-lang.github.io/rustup/concepts/profiles.html). Documentation on rustup install profiles (minimal, default, complete).

[^rustup-channels]: [The rustup book — Channels](https://rust-lang.github.io/rustup/concepts/channels.html). Description of the stable, beta, and nightly release channels.

[^rustup-other-install]: [The rustup book — Other installation methods](https://rust-lang.github.io/rustup/installation/other.html). Direct download links for rustup-init binaries for all supported platforms, SHA-256 checksum information, and package manager installation instructions.

[^rustup-init-sh]: [rustup-init.sh source code — GitHub](https://github.com/rust-lang/rustup/blob/main/rustup-init.sh). Full source code (926 lines) of the POSIX shell installer script. Contains all platform detection logic, downloader implementation, and installation orchestration.

[^rust-book-install]: [The Rust Programming Language — Installation](https://doc.rust-lang.org/book/ch01-01-installation.html). Official Rust book's installation chapter, describing system requirements (C compiler, linker) and the rustup installation process.

[^rustup-installation]: [The rustup book — Installation](https://rust-lang.github.io/rustup/installation/index.html). Covers the standard installation process, environment setup, tab completions, and uninstallation.

[^rustup-msvc-prereqs]: [The rustup book — MSVC prerequisites](https://rust-lang.github.io/rustup/installation/windows-msvc.html). Detailed prerequisites for using Rust on Windows with the MSVC toolchain, including Visual Studio installation walkthrough.

[^rustup-env-vars]: [The rustup book — Environment variables](https://rust-lang.github.io/rustup/environment-variables.html). Comprehensive list of all environment variables supported by rustup.

[^rustup-config]: [The rustup book — Configuration](https://rust-lang.github.io/rustup/configuration.html). Information about rustup's settings.toml configuration file.

[^rustup-toolchains]: [The rustup book — Toolchains](https://rust-lang.github.io/rustup/concepts/toolchains.html). Documentation on toolchain naming, specification, and management.

[^devcontainers-rust-install]: [devcontainers/features — Rust install.sh](https://github.com/devcontainers/features/blob/main/src/rust/install.sh). The official devcontainers Rust feature installation script. Illustrates system-wide installation, group/permission setup, SHA-256 verification, and component/target management.

[^devcontainers-rust-readme]: [devcontainers/features — Rust README](https://github.com/devcontainers/features/tree/main/src/rust). Official devcontainers Rust feature documentation, including OS support notes and Alpine Linux incompatibility.

[^devcontainers-rust-json]: [devcontainers/features — Rust devcontainer-feature.json](https://github.com/devcontainers/features/blob/main/src/rust/devcontainer-feature.json). Metadata for the official devcontainers Rust feature, including options, containerEnv, capabilities, and VS Code extension recommendations.

[^devcontainers-rust-image]: [microsoft/devcontainers-rust — Docker Hub](https://hub.docker.com/r/microsoft/devcontainers-rust). Pre-built Rust devcontainer images on Docker Hub.

[^rust-installer-template]: [rust-installer — install-template.sh — GitHub](https://github.com/rust-lang/rust/blob/master/src/tools/rust-installer/install-template.sh). Source template for the standalone installer `install.sh` script. Defines all available installation options including `--prefix` (default: `/usr/local`), `--disable-ldconfig`, `--verbose`, and others. The default prefix of `/usr/local` determines where macOS PKG installers place files.

[^rust-installer-readme]: [rust — src/etc/installer/README.md — GitHub](https://github.com/rust-lang/rust/blob/master/src/etc/installer/README.md). The README shipped with the Rust standalone installer, documenting the `install.sh` and `uninstall.sh` usage including the default prefix of `/usr/local` and the uninstall script path at `/usr/local/lib/rustlib/uninstall.sh`.

[^forge-standalone-installers]: [Rust Forge — Other Installation Methods](https://forge.rust-lang.org/infra/other-installation-methods.html). Official documentation on standalone installers, source code downloads, and GPG signature verification.

[^forge-channel-layout]: [Rust Forge — The Rust Release Channel Layout](https://forge.rust-lang.org/infra/channel-layout.html). Document describing the channel manifest format, which includes `hash` and `xz_hash` fields for each package/target entry, providing SHA-256 checksums for all distributed artifacts.

[^archlinux-wiki-rust]: [ArchWiki — Rust](https://wiki.archlinux.org/title/Rust). Arch Linux documentation on the `rustup` package, including the note that `rustup self update` does not work when installed via pacman.

[^alpine-rustup]: [Alpine Linux packages — rustup](https://pkgs.alpinelinux.org/package/edge/community/x86_64/rustup). Alpine Linux `rustup` package in the community repository, providing `rustup-init`.
