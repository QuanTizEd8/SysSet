# Feature Reference

The Go programming language (often referred to as Go or Golang) is a statically typed, compiled programming language designed at Google by Robert Griesemer, Rob Pike, and Ken Thompson. It is used for building reliable, efficient software at scale — from command-line tools and web servers to cloud-native infrastructure and microservices. The Go distribution includes a self-contained toolchain (compiler `go` tool, linker, standard library, supplementary build tools, and the `go` command) that ships as a single directory tree. No external runtime (JVM, Node.js, Python) is required — Go compiles directly to native machine code and statically links by default. The standard distribution provides first-class support for Linux, macOS, Windows, and FreeBSD on multiple architectures, with prebuilt binary archives (`.tar.gz` for Unix, `.zip` for Windows, `.pkg`/`.msi` for platform-specific installers) available from the official downloads page. The most common and recommended installation method for containers and CI/CD environments is the **official prebuilt binary tarball** downloaded directly from `https://go.dev/dl/` and extracted to `/usr/local/go`.

- **Homepage**: https://go.dev
- **Source Code**: https://go.googlesource.com/go (mirrored on GitHub at https://github.com/golang/go)
- **Documentation**: https://go.dev/doc/
- **Latest Release**: 1.26.4 (as of 2026-07-02)[^go-dl-json]

## Tool Architecture

Go's toolchain has the following architecture:

- **Single directory tree** — The entire Go distribution is a self-contained directory (typically `/usr/local/go`) containing:
  - `bin/go` — The Go tool (`go build`, `go test`, `go install`, etc.)[^go-cmd-go]
  - `bin/gofmt` — Source code formatter[^go-cmd-gofmt]
  - `bin/godoc` — Documentation server (deprecated in favor of `go doc` or `pkg.go.dev`)
  - `pkg/` — Compiled standard library object files (pre-built)
  - `src/` — Standard library source code
  - `misc/`, `api/`, `test/` — Miscellaneous support files and test data
- **No external dependencies at runtime** — The Go toolchain is self-contained. It does not require any runtime environment (JVM, Node.js, Python, etc.). The only system-level dependency for compiling Go code is a C compiler (`gcc` or `clang`) for `cgo` support, but `cgo` is optional and can be disabled with `CGO_ENABLED=0`.[^go-install-source]
- **Go is written in Go** — Since Go 1.5, the Go compiler and tools are written in Go itself. To build Go from source, a pre-existing Go toolchain (the "bootstrap" compiler) is required.[^go-install-source]
- **Standard library** — Go ships a comprehensive standard library covering HTTP servers/clients, JSON/XML/Protobuf encoding, cryptography, compression, templating, testing, and dozens of other packages — all precompiled in `pkg/` for each target platform.[^go-pkg-std]
- **No package manager dependency** — Go modules are integrated into the `go` command itself; no separate `npm`/`pip`/`gem`-like tool is needed. Modules are fetched from version control systems or module proxies on demand (`go mod download`), cached under `$GOPATH/pkg/mod`.[^go-ref-mod]
- **Cross-compilation built-in** — Go supports cross-compilation by setting the `GOOS` and `GOARCH` environment variables. For example, `GOOS=linux GOARCH=arm64 go build` compiles a Linux ARM64 binary on any platform without any additional toolchain.[^go-doc-code]
- **Environment variables** — The Go toolchain behavior is extensively configurable through environment variables: `GOROOT` (where Go is installed), `GOPATH` (workspace and module cache), `GOBIN` (binary install directory), `GOOS`/`GOARCH` (cross-compilation target), `GOPROXY` (module proxy URL), `GONOSUMCHECK`, `GONOSUMDB`, `GOVCS`, and many others.[^go-env-list]

## Installation Methods

There are several ways to install Go. The **official binary tarball** is the recommended method for containers, CI/CD systems, and automated installations because it is architecture-aware, version-pinable, dependency-free (no runtime requirements), and works identically across all supported Unix platforms. Operating system package managers (apt, yum, etc.) provide an alternative but typically ship outdated versions. Building from source is possible but rarely needed outside bootstrap scenarios.

### Official Binary Tarball (Recommended for Containers and Automation)

#### Supported Platforms

- **Linux** — amd64, 386, arm64, armv6l, loong64, mips, mipsle, mips64, mips64le, ppc64, ppc64le, riscv64, s390x. Requires Linux 2.6.23 or later with glibc. Other libc variants (musl/Alpine) are not supported by the official prebuilt binaries; install from source on such systems.[^go-install-doc][^go-minimum-reqs]
- **macOS** — amd64 (Intel), arm64 (Apple Silicon). Requires macOS 12 or later.[^go-install-doc]
- **FreeBSD** — 386, amd64, arm, arm64. Requires FreeBSD 10.3 or later. Debian GNU/kFreeBSD not supported.[^go-install-doc]
- **Windows** — 386, amd64, arm64. Requires Windows 10 or later, or Windows Server 2008R2 or later.[^go-install-doc]

**Not supported by the official binary tarballs:** AIX, Android, DragonFly BSD, illumos, iOS, NetBSD, OpenBSD, Plan 9, Solaris — these platforms must build from source or use a third-party distribution (e.g., gccgo). The Go source supports many more OS/arch combinations than the binary builds cover.[^go-porting-policy]

#### Dependencies

##### Common Dependencies

- **`curl`** or **`wget`** — For downloading the binary archive.
- **`tar`** — For extraction of the `.tar.gz` archive.
- **`sha256sum`** (or equivalent) — For verifying the archive checksum.
- **`gpg`** (optional) — For GPG signature verification of the archive.
- **`ca-certificates`** — For HTTPS download support.
- **System C toolchain** (`gcc`/`clang`, `make`, `pkg-config`, `glibc-devel`/`libc6-dev`) — Required only if `cgo` support is needed at build time. For most use cases, Go works without a C toolchain by setting `CGO_ENABLED=0`.

##### Platform-Specific Dependencies

- **Linux (Debian/Ubuntu)**: `ca-certificates`, `curl`, `gpg` (for signature verification), `gcc`, `libc6-dev`, `make`, `pkg-config` (the last four only if `cgo` is needed).
- **Linux (RHEL/Fedora/CentOS)**: `ca-certificates`, `curl`, `gnupg2`, `gcc`, `glibc-devel`, `make`, `pkg-config` (the last four only if `cgo` is needed).
- **macOS**: Xcode Command Line Tools (`xcode-select --install`) provides `clang`, `ld`, `make`, and other build tools needed for `cgo`.
- **Windows**: MinGW (386) or MinGW-W64 (amd64) GCC for `cgo` support. No need for Cygwin or MSYS. `.zip` archives or `.msi` installers are available.[^go-install-doc]

#### Installation Steps

The official installation process for Linux, macOS, and FreeBSD is as follows:[^go-install-doc]

```bash
# 1. Determine target architecture
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)   GOARCH="amd64" ;;
  aarch64)  GOARCH="arm64" ;;
  armv7l|armhf) GOARCH="armv6l" ;;
  i686|i386) GOARCH="386" ;;
  *)        echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# 2. Remove any previous Go installation
rm -rf /usr/local/go

# 3. Download the Go binary archive (as root/sudo)
# Use https://go.dev/dl/go{VERSION}.linux-${GOARCH}.tar.gz
# Example for Go 1.26.4 on linux/amd64:
curl -fsSL -o /tmp/go.tar.gz \
  "https://go.dev/dl/go1.26.4.linux-${GOARCH}.tar.gz"

# 4. Verify SHA256 checksum
# Checksums are listed on the downloads page: https://go.dev/dl/
# Example: echo "1153d3d5 ... 3ad7f  go.tar.gz" | sha256sum --check
# For automated verification, fetch the JSON metadata:
CHECKSUM=$(curl -fsSL "https://go.dev/dl/?mode=json" | \
  jq -r '.[] | select(.stable == true) | .files[] |
         select(.filename == "go1.26.4.linux-'${GOARCH}'.tar.gz") | .sha256')
echo "${CHECKSUM}  /tmp/go.tar.gz" | sha256sum --check -

# 5. Extract the archive to /usr/local (creates /usr/local/go)
tar -C /usr/local -xzf /tmp/go.tar.gz

# 6. Clean up
rm -f /tmp/go.tar.gz

# 7. Add to PATH
export PATH="/usr/local/go/bin:${PATH}"

# 8. Verify installation
go version
# Expected output:
# go version go1.26.4 linux/amd64
```

**Important notes:**
- Do **not** untar the archive into an existing `/usr/local/go` tree. Always remove the old directory first (`rm -rf /usr/local/go`) before extracting the new one. Extracting a tarball on top of an existing installation is known to produce broken Go installations.[^go-install-doc]
- The download URL pattern for Linux is `https://go.dev/dl/go{VERSION}.linux-{ARCH}.tar.gz`. For macOS, use `darwin` instead of `linux`. For FreeBSD, use `freebsd`.
- For macOS, a `.pkg` installer is also available that handles the installation automatically.

#### Installation Verification

1. **SHA256 checksum verification**: Every binary archive published on `https://go.dev/dl/` has a SHA256 checksum listed on the same page. The checksum can also be retrieved programmatically from the JSON API at `https://go.dev/dl/?mode=json`.[^go-dl-json]
2. **GPG signature verification**: Archived tarballs have detached GPG signatures available by appending `.asc` to the download URL (e.g., `https://go.dev/dl/go1.26.4.linux-amd64.tar.gz.asc`). Signatures are made with Google's Linux Packages Signing Authority key, available at `https://dl.google.com/linux/linux_signing_key.pub`. The primary key fingerprint is `EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796`.[^go-gpg-issue][^go-gpg-verify]
3. **Version check**: Run `go version` — it should output the expected version and platform.
4. **Environment check**: Run `go env GOROOT GOPATH` to verify the installation paths.

#### Configuration Options

##### Version Selection

Go versions are specified as semantic version strings prefixed with `go` in the tarball filename. The download URL format is consistent:

```
https://go.dev/dl/go{VERSION}.{OS}-{ARCH}.tar.gz
```

Where:
- `{VERSION}` is the Go version in semver format prefixed with `go` (e.g., `go1.26.4`, `go1.25.11`, `go1.27rc1`)
- `{OS}` is the target operating system (`linux`, `darwin`, `freebsd`)
- `{ARCH}` is the target architecture (`amd64`, `arm64`, `386`, `armv6l`, etc.)

To find the latest stable version programmatically, use the JSON API:[^go-dl-json]

```bash
LATEST=$(curl -fsSL "https://go.dev/dl/?mode=json" | \
  jq -r '[.[] | select(.stable == true)] | .[0].version | sub("^go"; "")')
echo "$LATEST"
# Example output: 1.26.4
```

Versions can be pinned to specific releases. The Go release cycle follows semantic versioning with a 6-month release cadence (major.new.minor). Go 1.x releases are backward compatible; patch releases (e.g., 1.26.1 → 1.26.4) include security fixes and bug fixes.

##### Installation Path

The default installation path is `/usr/local/go` (corresponding to `GOROOT`). This matches the official documentation and is the canonical location.[^go-install-doc]

The installation path can be customized by extracting to a different directory. When doing so, `GOROOT` must be set to point to that directory:

```bash
export GOROOT=/opt/go
export PATH="${GOROOT}/bin:${PATH}"
```

##### User Targeting

- **System-wide installation**: Extract to `/usr/local/go` (requires root/sudo). This is the standard configuration for development containers, CI/CD pipelines, and shared/multi-user systems.
- **User-local installation**: Extract to a user-writable location (e.g., `$HOME/go-install`) and set `GOROOT` and `PATH` accordingly. This does not require root.

##### Required Privileges

- **System-wide installation** (default, `/usr/local/go`): Must be run as root or via `sudo`, as `/usr/local` is not writable by regular users.
- **User-local installation**: No special privileges required; can be run entirely within a user's home directory.

##### Tool-Specific Configurations

Go's behavior is controlled by environment variables, specified in `go help environment`:[^go-env-list]

| Variable | Default | Description |
|---|---|---|
| `GOROOT` | Built-in path | Root directory of the Go installation. Inferred from the location of the `go` binary; rarely needs to be set explicitly unless the binary is relocated or symlinked away from its original tree. |
| `GOPATH` | `$HOME/go` | Workspace root. Controls where `go install` puts compiled binaries (`$GOPATH/bin`), where `go get`/`go mod download` caches modules (`$GOPATH/pkg/mod`), and where the checksum database state is stored (`$GOPATH/pkg/sumdb`). |
| `GOBIN` | `$GOPATH/bin` | Directory where `go install` installs compiled executables. |
| `GOOS` | Host OS | Target operating system for cross-compilation (e.g., `linux`, `darwin`, `windows`). |
| `GOARCH` | Host arch | Target architecture for cross-compilation (e.g., `amd64`, `arm64`, `386`). |
| `GOAMD64` | `v1` | Microarchitecture level for amd64 (`v1`, `v2`, `v3`, `v4`). Higher levels enable newer instruction sets. |
| `GOPROXY` | `https://proxy.golang.org,direct` | Go module proxy URL. Set to `off` to disable, `direct` to bypass proxy. |
| `GONOSUMCHECK` | (none) | Comma-separated patterns of modules for which the checksum database should not be consulted. |
| `GONOSUMDB` | (none) | Comma-separated patterns of modules for which the checksum database should not be used. |
| `GONOSUMCHECK` | (none) | Comma-separated patterns of modules for which the checksum database should not be consulted. |
| `GOVCS` | `*:all` | Controls version control tools allowed for module fetches (e.g., `github.com:git`). |
| `GO111MODULE` | `on` (since Go 1.16) | Controls module mode: `on` (module mode always), `off` (GOPATH mode), `auto` (auto-detect). |
| `CGO_ENABLED` | `1` | Whether to enable `cgo` (C interop). Set to `0` to force pure Go builds (no C compiler required). |

#### Post-Installation Steps and Cleanup

##### PATH Setup

After installing Go, `/usr/local/go/bin` must be on `PATH`. Additionally, `$GOPATH/bin` should be on `PATH` for locally installed Go tools (e.g., those installed via `go install`).

For system-wide installation, this can be done in `/etc/profile` or via `/etc/profile.d/go.sh`:

```bash
# /etc/profile.d/go.sh
export PATH="/usr/local/go/bin:${PATH}"

# Optionally set GOPATH
export GOPATH="/go"
export PATH="${GOPATH}/bin:${PATH}"
```

For user-local installation, similar entries go into `$HOME/.profile`, `$HOME/.bashrc`, or `$HOME/.zshrc`.

##### Configuration Files

Go does not create or require any configuration files at installation time. The `go env -w` command can persist environment variable overrides to a user-configuration file (located at the path returned by `go env GOENV`, typically `$HOME/.config/go/env` on Linux, `$HOME/Library/Application Support/go/env` on macOS). These peristent settings are read by `go` commands and can be managed via:

```bash
go env -w GOPROXY=https://proxy.golang.org,direct
go env -w GONOSUMCHECK=*.internal.example.com
```

##### Environment Variables

The following environment variables should typically be set for a functional Go development environment:

- `PATH` must include `$GOROOT/bin` and `$GOPATH/bin`.
- `GOPATH` should point to a writable workspace directory (commonly set to `/go` in containers).

The `devcontainers/features/go` reference feature sets:[^devcontainers-go-json]

```
GOROOT=/usr/local/go
GOPATH=/go
PATH=/usr/local/go/bin:/go/bin:${PATH}
```

##### Activation Scripts

No shell activation scripts are required for Go. The `go` binary is a standard executable and does not require sourcing any shell functions. Unlike `nvm` or `rustup`, Go does not use shell functions or wrapper scripts — it is a direct binary on `PATH`.

##### Shell Completions

The `go` command does not ship with built-in shell completion generation. Community-maintained completion scripts are available:
- **bash**: `source <(go completion bash)` (Go 1.22+ includes a `go completion` subcommand)[^go-cmd-completion]
- **zsh**: `source <(go completion zsh)`
- **fish**: `go completion fish`

These can be installed to the system completions directory:
```bash
# Bash (system-wide)
go completion bash > /etc/bash_completion.d/go

# Zsh (system-wide)
go completion zsh > /usr/share/zsh/vendor-completions/_go

# Fish (system-wide)
go completion fish > /usr/share/fish/vendor_completions.d/go.fish
```

##### Cleanup

The downloaded tarball (`/tmp/go.tar.gz`) can be removed after extraction:

```bash
rm -f /tmp/go.tar.gz
```

If GPG keys were imported for signature verification, they can be removed:

```bash
rm -rf /tmp/tmp-gnupg
```

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

1. **Remove the existing installation**: `rm -rf /usr/local/go`
2. **Download the desired version tarball** and extract to `/usr/local/go`.

Since Go installs as a complete, self-contained directory tree, upgrading or downgrading is simply a matter of replacing `/usr/local/go` with a different version. No configuration files need to be updated, except for `PATH` (which points to `/usr/local/go/bin` and remains unchanged regardless of version). Go does not have a central package database or registry that tracks installed versions — it is purely a file-level installation.

The official `go install golang.org/dl/goX.Y.Z@latest` mechanism can also be used to install side-by-side versions, but this requires an existing Go installation to use.[^go-manage-install]

##### Uninstallation

1. **Remove the Go directory**: `rm -rf /usr/local/go` (or whichever `GOROOT` is set to).
2. **Remove `PATH` entries** referencing `$GOROOT/bin` and `$GOPATH/bin` from shell profile files.
3. **Remove GOPATH data** (optional): `rm -rf /go` (or wherever `GOPATH` points).
4. **Remove persistent environment variables** (optional): `go env -u GOPROXY` etc.
5. **Remove shell completions** (optional): Delete completion scripts installed in the system completions directories.

##### Idempotency

The binary tarball installation method is **fully idempotent** when the previous installation is removed first:

```bash
rm -rf /usr/local/go && tar -C /usr/local -xzf go.tar.gz
```

Without the `rm -rf` step, extracting a tarball into an existing `/usr/local/go` overwrites files but may leave stale files from the previous version, leading to a broken installation. The official documentation explicitly warns against this.[^go-install-doc]

If running the installation script repeatedly, a common pattern is to check whether the target version is already installed:

```bash
if [ "$(go version 2>/dev/null)" = "go version go${VERSION} linux/${GOARCH}" ]; then
    echo "Go ${VERSION} is already installed."
    exit 0
fi
```

#### Details

The official binary tarball installation works as follows:

1. **Version resolution** — The desired version is specified as a semver string (e.g., `1.26.4`). For automated features, the version can be resolved to the latest stable release by querying `https://go.dev/dl/?mode=json` and parsing the JSON response for the first entry with `"stable": true`.[^go-dl-json]
2. **Download** — The archive is downloaded from `https://go.dev/dl/go{VERSION}.{OS}-{ARCH}.tar.gz`. The URL pattern is well-known and documented on the official install page. Go binaries are hosted on Google's CDN at `dl.google.com/go/` (redirected from `go.dev/dl/`).
3. **Verification** — SHA256 checksums are published on the downloads page and accessible via the JSON API. GPG signatures (`.asc` files) are available for all `.tar.gz` archives and can be verified against Google's Linux Packages Signing Authority key.
4. **Extraction** — The archive is a standard gzip-compressed tar archive. Its internal structure is a single `go/` directory containing the entire Go distribution tree. Extracting with `tar -C /usr/local -xzf` places everything under `/usr/local/go`. After extraction, the `go/` directory must be renamed or extracted as a top-level directory — the official instruction uses `tar -C /usr/local -xzf` which creates `/usr/local/go/`. The `--strip-components=1` option used in some scripts (e.g., `devcontainers/features/go`) strips the top-level `go/` directory component and is equivalent when extracting directly to the target location.[^devcontainers-go-install]
5. **PATH** — `/usr/local/go/bin` must be added to `PATH` for the `go` binary to be found by the shell.
6. **Post-install** — Optionally, `GOPATH` and other environment variables can be set to customize the Go workspace layout.

#### Notes and Best Practices

- **Always remove old installations first**: `rm -rf /usr/local/go` before extracting a new tarball. This is the most common pitfall and is explicitly warned against in the official documentation.[^go-install-doc]
- **Architecture detection**: Use `uname -m` and map to Go's architecture names. The mapping is: `x86_64` → `amd64`, `aarch64` → `arm64`, `armv7l`/`armhf` → `armv6l`, `i686`/`i386` → `386`. Other architectures are not supported in the official Linux binary builds.[^devcontainers-go-install]
- **GOPATH in containers**: In dev containers, `GOPATH` is typically set to `/go` (as done by the official `devcontainers/features/go` feature). This keeps the module cache separate from the user's home directory and allows the `go` command to work immediately without additional configuration.[^devcontainers-go-json]
- **Minimizing image size**: The Go tarball is ~60–70 MB compressed and ~200–250 MB extracted. To minimize the final container image layer size, always remove the downloaded tarball after extraction. Consider using `CGO_ENABLED=0` to avoid installing a C toolchain if you do not need `cgo`.
- **Prefer stable releases**: Patch releases (e.g., `1.26.4`) are preferred over minor releases (e.g., `1.26`) for reproducibility. The latest stable version can be resolved dynamically via the JSON API.
- **GPG key rotation**: Google's Linux Packages Signing Authority key is rotated periodically. The key URL `https://dl.google.com/linux/linux_signing_key.pub` always serves the current key. The primary key fingerprint as of mid-2026 is `EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796`.[^go-gpg-issue]

### OS Package Manager (apt, yum, dnf)

#### Supported Platforms

- **Debian/Ubuntu** — via `apt-get`. Canonical maintains a `golang-go` package in the official repositories, but it typically lags behind the latest Go release by several months to years. Ubuntu 22.04 LTS ships Go 1.18; Ubuntu 24.04 LTS ships Go 1.21.[^ubuntu-golang-pkg]
- **RHEL/Fedora/CentOS** — via `dnf` or `yum`. The official repositories similarly carry older versions.
- **Alpine Linux** — via `apk`. Ships Go (often very recent) as `go` package.

#### Dependencies

No additional dependencies beyond the standard system package manager infrastructure.

#### Installation Steps

```bash
# Debian/Ubuntu
apt-get update && apt-get install -y golang-go

# RHEL/Fedora/CentOS
dnf install -y golang

# Alpine
apk add go
```

#### Notes

- OS package managers typically install Go to a different location than the default `/usr/local/go` (e.g., `/usr/lib/go-{version}/bin/go` on Debian). This means `GOROOT` must be set appropriately if required.
- The version lag makes the OS package manager method unsuitable for development containers that require a specific (especially recent) Go version. The official binary tarball method should be preferred for version-pinable installations.

### Building from Source

Building Go from source is an alternative for platforms that do not have prebuilt binaries (e.g., musl-based Linux/Alpine, AIX, illumos, etc.), or when a custom build configuration is needed. This method requires a pre-existing Go toolchain as a bootstrap compiler (Go 1.22.0 or later recommended for Go 1.26.x).[^go-install-source]

Installation steps:

```bash
# 1. Install a bootstrap Go compiler (e.g., from binary tarball)
# 2. Download the Go source tarball
curl -fsSL -o /tmp/go.src.tar.gz \
  "https://go.dev/dl/go${VERSION}.src.tar.gz"

# 3. Extract source
tar -C /usr/local -xzf /tmp/go.src.tar.gz
# This creates /usr/local/go/src/

# 4. Build the toolchain
cd /usr/local/go/src
./make.bash  # or ./all.bash to run tests as well

# 5. The built binaries are now at /usr/local/go/bin/
```

This method is documented at https://go.dev/doc/install/source.

## Dev Container Setup

When installing Go in a dev container (or any Docker-based environment), the following considerations apply:

- **Standard configuration**: The official `devcontainers/features/go` feature uses `GOROOT=/usr/local/go`, `GOPATH=/go`, and adds both `/usr/local/go/bin` and `/go/bin` to `PATH` via `containerEnv` in `devcontainer-feature.json`.[^devcontainers-go-json]
- **Non-root user**: After installation, permissions on `/usr/local/go` and `/go` should be adjusted so the non-root dev container user can read and write. The reference feature solves this by creating a `golang` group, adding the non-root user to it, and setting `chown -R user:golang` on the directories.[^devcontainers-go-install]
- **`SYS_PTRACE` capability**: The reference Go feature requests `SYS_PTRACE` capability and `seccomp=unconfined` security option in `devcontainer-feature.json` to support the Delve debugger (`dlv`), which is commonly used for Go debugging in dev containers.[^devcontainers-go-json]
- **No shell function sourcing required**: Unlike `nvm` or `rustup`, Go's `go` binary is a standard executable on `PATH`. No activation scripts or shell function loading is needed. The environment variables (`GOROOT`, `GOPATH`, `PATH`) should be set via `containerEnv` or written to a profile file.
- **Profile.d configuration**: The reference feature writes `export PATH=...` to `/etc/profile.d/00-restore-env.sh` to ensure login shells have the correct `PATH` when `ENV`-based `PATH` modifications in Dockerfiles are lost in some dev container environments.[^devcontainers-go-install]
- **Common Go tools**: The reference feature optionally installs common Go development tools (`gopls`, `dlv`, `staticcheck`, `golint`, `revive`, `gomodifytags`, `goplay`, `gotests`, `impl`) via `go install` and places them under `$GOPATH/bin`. Tools are installed using `go install` for Go 1.16+ or `go get` for older versions. The `golangci-lint` linter is also optionally installed from prebuilt binaries.[^devcontainers-go-install]
- **Alpine Linux**: The official binary tarballs do not work on Alpine (musl-based). Install from source using the bootstrap method or cross-compilation. The nix package manager (`apk add go`) provides a recent Go on Alpine as well.

## Plugins and Extensions

### VS Code Extensions

The primary VS Code extension for Go development is the official Go extension (`golang.Go`), maintained by the Go team at Google. It provides language features powered by `gopls` (the Go language server), including code completion, signature help, refactoring, formatting, navigation, and debugging integration.[^vscode-go]

- **Extension ID**: `golang.Go`
- **Marketplace**: https://marketplace.visualstudio.com/items?itemName=golang.Go
- **Source**: https://github.com/golang/vscode-go
- **Prerequisites**: Go 1.14+ and `gopls` (installed automatically by the extension or via `go install golang.org/x/tools/gopls@latest`)
- **Debugging**: The extension integrates with Delve (`dlv`) for debugging Go programs. This is why the reference dev container feature requests `SYS_PTRACE` and `seccomp=unconfined`.[^devcontainers-go-json]

Other notable Go VS Code extensions:
- **GoTestMate** (`"usernamehw.errorlens"`): Test output integration for Go tests.
- **Go to Symbol** (`"ms-vscode.go-symbols"`): Symbol search for Go.

### Common Go Development Tools

The following tools are commonly installed alongside Go and are frequently bundled in dev container Go features:[^devcontainers-go-install]

| Tool | Purpose | Install Command |
|---|---|---|
| `gopls` | Go language server (IDE features) | `go install golang.org/x/tools/gopls@latest` |
| `dlv` | Delve debugger | `go install github.com/go-delve/delve/cmd/dlv@latest` |
| `staticcheck` | Advanced linter (replaces `go vet`) | `go install honnef.co/go/tools/cmd/staticcheck@latest` |
| `golint` | Basic linter | `go install golang.org/x/lint/golint@latest` |
| `revive` | Alternative linter | `go install github.com/mgechev/revive@latest` |
| `gomodifytags` | Struct tag manipulation | `go install github.com/fatih/gomodifytags@latest` |
| `goplay` | Go Playground integration | `go install github.com/haya14busa/goplay/cmd/goplay@latest` |
| `gotests` | Test generation | `go install github.com/cweill/gotests/gotests@latest` |
| `impl` | Interface implementation stub generation | `go install github.com/josharian/impl@latest` |
| `golangci-lint` | Meta-linter (aggregates multiple linters) | Install from prebuilt binaries at `https://github.com/golangci/golangci-lint` |

## References

[^go-dl-json]: [Go Downloads JSON API](https://go.dev/dl/?mode=json) — Returns machine-readable metadata for all Go releases, including version, stability status, SHA256 checksums, file sizes, and platform/architecture associations. The first entry with `"stable": true` is the latest stable release. Verified 2026-07-02 to show `go1.26.4`.
[^go-install-doc]: [Official Go Installation Documentation](https://go.dev/doc/install) — Documents the official Linux, macOS, and Windows installation methods. Specifies the extraction to `/usr/local/go`, the need to remove old installations first, setting `PATH`, and verification via `go version`.
[^go-cmd-go]: [Go Command Documentation — `go`](https://pkg.go.dev/cmd/go) — Comprehensive reference for the `go` command: module management, building, testing, formatting, and environment variables.
[^go-cmd-gofmt]: [Go Command Documentation — `gofmt`](https://pkg.go.dev/cmd/gofmt) — Reference for the Go source code formatter.
[^go-install-source]: [Installing Go from Source](https://go.dev/doc/install/source) — Documents building Go from source, including bootstrap compiler requirements, C compiler requirements for `cgo`, and platform-specific build notes.
[^go-manage-install]: [Managing Go Installations](https://go.dev/doc/manage-install) — Documents installing multiple Go versions, using `go install golang.org/dl/goX.Y.Z@latest`, and uninstalling Go.
[^go-minimum-reqs]: [Go Wiki — Minimum Requirements](https://go.dev/wiki/MinimumRequirements) — Minimum operating system and architecture requirements for Go.
[^go-porting-policy]: [Go Wiki — Porting Policy](https://go.dev/wiki/PortingPolicy) — Documents first-class ports (Linux, macOS, Windows, FreeBSD on select architectures) and the process for adding/removing ports.
[^go-pkg-std]: [Go Standard Library Documentation](https://pkg.go.dev/std) — Reference documentation for Go's standard library packages.
[^go-ref-mod]: [Go Modules Reference](https://go.dev/ref/mod) — Complete reference for Go modules: `go.mod`, `go.sum`, version resolution, `GOPROXY`, `GONOSUMCHECK`, etc.
[^go-doc-code]: [How to Write Go Code](https://go.dev/doc/code) — Introductory documentation covering Go workspace layout, `GOPATH`, `GOBIN`, `go install`, and module basics.
[^go-env-list]: [Go Environment Variables](https://pkg.go.dev/cmd/go#hdr-Environment_variables) — Complete list of Go environment variables with descriptions.
[^go-gpg-issue]: [Go Issue #14739 — GPG signatures for Go releases](https://github.com/golang/go/issues/14739) — Discussion and implementation of GPG signing for Go binary releases. Documents the signing key URL (`https://dl.google.com/linux/linux_signing_key.pub`) and the signature file convention (appending `.asc` to the archive URL).
[^go-gpg-verify]: [Blog post — Installing Go securely with GPG verification](https://blog.orenfromberg.tech/install-golang-securely/) — Step-by-step guide for verifying Go binary archives with GPG. Documents the Google Linux Packages Signing Authority key fingerprint (`EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796`).
[^go-cmd-completion]: [Go 1.22 Release Notes — `go completion`](https://tip.golang.org/doc/go1.22) — Documents the addition of `go completion` subcommand for generating shell completions for bash, zsh, and fish.
[^devcontainers-go-json]: [devcontainers/features — Go `devcontainer-feature.json`](https://github.com/devcontainers/features/blob/main/src/go/devcontainer-feature.json) — Reference configuration for the official Go dev container feature: sets `GOROOT=/usr/local/go`, `GOPATH=/go`, `PATH` including both, requests `SYS_PTRACE` capability and `seccomp=unconfined` for Delve support, and configures the `golang.Go` VS Code extension.
[^devcontainers-go-install]: [devcontainers/features — Go `install.sh`](https://github.com/devcontainers/features/blob/main/src/go/install.sh) — Reference implementation of the Go dev container feature installation script. Demonstrates architecture detection (`uname -m` → Go arch names), GPG key verification, version fallback logic, GOPATH setup, common tools installation, and group/permissions management for non-root users.
[^ubuntu-golang-pkg]: [Ubuntu Packages — golang-go](https://packages.ubuntu.com/search?keywords=golang-go) — Shows the Golang package versions available in various Ubuntu releases, demonstrating the version lag behind upstream.
[^vscode-go]: [VS Code Go Extension](https://marketplace.visualstudio.com/items?itemName=golang.Go) — Official Go extension for VS Code, providing language support via `gopls` and integration with `dlv` for debugging.
