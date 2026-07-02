# Feature Reference

jsonschema is a command-line tool for working with [JSON Schema](https://json-schema.org), the world's most popular schema language. It provides a comprehensive suite of commands for maintaining repositories of JSON Schemas and ensuring their quality, including formatting, linting, testing, bundling, validating, upgrading, and more. It is designed for use both during local development and in CI/CD pipelines.[^readme]

The binary name is `jsonschema`. Official releases are published on GitHub with per-asset SHA256 checksums (in `CHECKSUMS.txt`) that are GPG-signed (`CHECKSUMS.txt.asc`), enabling integrity verification.[^release-v1600] Release tags use a `v` prefix followed by semver (e.g., `v16.0.0`).[^releases]

- **Homepage**: https://github.com/sourcemeta/jsonschema
- **Source Code**: https://github.com/sourcemeta/jsonschema
- **Documentation**: https://github.com/sourcemeta/jsonschema/blob/main/README.markdown (overview); per-command docs are under the [`docs/`](https://github.com/sourcemeta/jsonschema/tree/main/docs) directory in the repository.
- **Latest Release**: **16.0.0** (as of 2026-07-02)[^release-v1600]

## Tool Architecture

jsonschema is a **single, self-contained CLI binary** written in **C++** and built with **CMake**.[^readme] It does not depend on any interpreted runtime (e.g., JVM, Node.js, Python) to function. The binary is compiled with release-specific processor optimizations by default.[^readme-build]

### Networking Approach (Platform-Specific)

The CLI performs HTTP requests to fetch remote schema references, resolve `$ref` pointers, and install schema dependencies. The networking layer is platform-specific:[^readme][^release-v15110][^release-v1600]

| Platform | Networking Mechanism | Runtime Dependency |
|----------|---------------------|-------------------|
| **macOS** | `NSURLSession` (native) | None |
| **Windows** | `WinHTTP` (native) | None |
| **Linux / BSD** | `libcurl` loaded via `dlopen` at runtime | `libcurl.so.4` (see below) |

On Linux and BSD, the binary probes common system paths for `libcurl.so.4` and dynamically loads it. This keeps the binary distribution-independent and makes it respect the system's TLS trust store.[^readme] If `libcurl` is not found, a friendly runtime error instructs the user on how to install it or point to a custom location via the `SOURCEMETA_CORE_CURL_SO` environment variable.[^readme]

Before v16.0.0, the Linux binaries were statically linked against a vendored copy of cURL. v16.0.0 switched to the `dlopen`-based approach for better CA trust store compatibility.[^release-v1600]

### Build System and Portability

- **Build system**: CMake with a C++ compiler.[^readme]
- **Portable builds**: Setting `-DJSONSCHEMA_PORTABLE:BOOL=ON` at CMake configure time disables processor-specific optimizations for a portable binary.[^readme-build]
- **Backward compatibility**: Aggressive processor-specific optimizations may cause `Illegal instruction` errors on older hardware. The `-DJSONSCHEMA_PORTABLE:BOOL=ON` flag resolves this.[^readme-build]

### Commands and Capabilities

The CLI exposes the following subcommands:[^readme]

| Command | Purpose |
|---------|---------|
| `jsonschema version` | Print version information |
| `jsonschema validate` | Validate instances against a schema |
| `jsonschema metaschema` | Ensure a schema is valid against its meta-schema |
| `jsonschema compile` | Pre-compile schemas for faster validation |
| `jsonschema test` | Write and run unit tests for schemas |
| `jsonschema fmt` | Format schema files (indentation, keyword ordering) |
| `jsonschema lint` | Detect and fix common JSON Schema anti-patterns |
| `jsonschema bundle` | Inline remote `$ref` references for distribution |
| `jsonschema upgrade` | Upgrade schemas to a newer JSON Schema dialect |
| `jsonschema inspect` | Debug schema references and resolution |
| `jsonschema codegen` | Generate code from schemas |
| `jsonschema encode` | Binary compression of schemas |
| `jsonschema decode` | Decompress binary-encoded schemas |
| `jsonschema install` | Fetch external schema dependencies |

### Configuration File

The CLI supports an experimental `jsonschema.json` configuration file (analogous to NPM's `package.json`) for project-level settings such as default dialect, schema resolution mappings, dependencies, lint rules, and more. It is discovered via an ancestor lookup algorithm starting from the schema's directory.[^docs-configuration]

### Runtime Environment

jsonschema is a **standalone CLI** with no client-server architecture, no daemon, and no external service dependency at runtime (other than optionally `libcurl` on Linux for HTTP operations). It can operate entirely offline for local schema work (formatting, linting, compiling) as long as no remote `$ref` references need to be resolved.

### License

The project is released under the **GNU Affero General Public License v3.0** (AGPL-3.0). According to the maintainers, using the CLI as a tool during local development or in CI/CD pipelines does not trigger the AGPL's copyleft requirements.[^readme]

## Installation Methods

jsonschema offers multiple installation routes. The primary method for DevFeats/devcontainer features is the **pre-built binary download from GitHub Releases** via the official POSIX install script or direct download. Other methods are documented for completeness.

1. **Pre-built Binary Download (GitHub Releases)** — direct, deterministic, version-pinnable; the recommended method for DevFeats/devcontainer features.
2. **GitHub Actions** — composite action for CI/CD pipelines.
3. **Homebrew** — macOS only; convenient for interactive use.
4. **npm (Node.js package)** — installs the binary via npm, requires Node.js.
5. **PyPI (Python package)** — installs the binary via pip, requires Python.
6. **Snap** — Linux-only; sandboxed but confined to `$HOME`.
7. **Docker Image** — containerized execution via `ghcr.io/sourcemeta/jsonschema`.
8. **mise** — version manager integration.
9. **gah** — third-party install helper.
10. **Build from Source** — full control; requires C++ toolchain and CMake.

### Pre-built Binary Download (GitHub Releases)

#### Supported Platforms

Based on the release assets for v16.0.0:[^release-v1600]

| OS | Architecture | Libc | Asset filename |
|----|-------------|------|---------------|
| Linux | x86_64 (amd64) | glibc | `jsonschema-{version}-linux-x86_64.zip` |
| Linux | x86_64 (amd64) | musl (Alpine) | `jsonschema-{version}-linux-x86_64-musl.zip` |
| Linux | arm64 (aarch64) | glibc | `jsonschema-{version}-linux-arm64.zip` |
| Linux | arm64 (aarch64) | musl (Alpine) | `jsonschema-{version}-linux-arm64-musl.zip` |
| macOS | x86_64 (Intel) | — | `jsonschema-{version}-darwin-x86_64.zip` |
| macOS | arm64 (Apple Silicon) | — | `jsonschema-{version}-darwin-arm64.zip` |
| Windows | x86_64 | — | `jsonschema-{version}-windows-x86_64.zip` |

The Linux glibc binaries conservatively target Ubuntu. For Alpine Linux (musl libc), separate `-musl` variants are provided. Other musl-based distributions should use the `-musl` variants as well.[^readme]

Additionally, a **[continuous](https://github.com/sourcemeta/jsonschema/releases/tag/continuous)** pre-release tag is maintained, which is updated on every commit to the `main` branch. This can be used to test bleeding-edge builds before they are published as a stable release.[^releases]

There are **no** provided assets for:
- Linux i386 (32-bit x86)
- Linux armv6/armv7 (32-bit ARM)
- Windows arm64
- Windows i386 (32-bit x86)

#### Dependencies

##### Common Dependencies

- **curl**: Required to download the binary archive and checksum files.[^install-sh]
- **unzip**: Required to extract the downloaded `.zip` archive.[^install-sh]
- **POSIX `install`**: Required to copy the binary to the target directory.[^install-sh]

##### Platform-Specific Dependencies

- **Linux / BSD**: `libcurl.so.4` is required at runtime for any command that performs HTTP requests (e.g., `validate` with remote `$ref`, `install`, `bundle`). On most systems it is pre-installed; if missing, install it via the system package manager (`apt install libcurl4`, `dnf install libcurl`, `apk add libcurl`).[^readme] The binary itself (non-networked commands) runs without it.
- **macOS**: No runtime dependencies beyond system libraries. Networking uses `NSURLSession` natively.[^release-v15110]
- **Windows**: No runtime dependencies beyond system libraries. Networking uses `WinHTTP` natively.[^release-v15110]

#### Installation Steps

The official POSIX install script (`install` at the root of the repository) performs the following steps:[^install-sh]

1. **Detect platform**: Uses `uname` to determine OS (`Darwin` or `Linux`) and `uname -m` for architecture.
2. **Determine version**:
   - If no version argument is given, or the argument is `latest`, the script fetches the latest release tag from `https://api.github.com/repos/sourcemeta/jsonschema/releases/latest`.
   - Otherwise, it uses the user-provided version string directly.
3. **Construct download URL**: Builds the GitHub Release download URL in the format:
   `https://github.com/sourcemeta/jsonschema/releases/download/v{version}/jsonschema-{version}-{os}-{arch}[-musl].zip`
   - On Linux, if `/etc/os-release` contains `Alpine` (case-insensitive), the `-musl` variant is selected.
4. **Download**: Downloads the zip archive to a temporary directory using `curl --retry 5 --location`.
5. **Extract**: Unzips the archive into the temporary output directory.
6. **Install binary**: Uses `install -d -m 0755` to ensure the target `bin/` directory exists, then `install -v -m 0755` to copy the `jsonschema` binary into it.
7. **Cleanup**: Removes the temporary directory via a `trap` on `EXIT`.

The default installation prefix is `/usr/local` (set via the `OUTPUT` variable), but a custom prefix can be passed as the second argument.

> **Important — GitHub API rate limiting**: When no version argument is given (i.e., using `latest`), the script makes an **unauthenticated** request to the GitHub API (`api.github.com`), which is subject to a [rate limit of 60 requests per hour](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api). In CI/CD environments where builds run frequently, this may cause the script to fail. To avoid rate limiting, either pin a specific version or implement an authenticated fallback (e.g., using `GITHUB_TOKEN` via the `Authorization` header).

**Direct usage:**
```sh
# Install latest version to /usr/local/bin
curl -fsSL https://raw.githubusercontent.com/sourcemeta/jsonschema/main/install \
  -H 'Cache-Control: no-cache, no-store, must-revalidate' | /bin/sh

# Install specific version to a custom prefix
curl -fsSL https://raw.githubusercontent.com/sourcemeta/jsonschema/main/install \
  -H 'Cache-Control: no-cache, no-store, must-revalidate' | /bin/sh -s -- 16.0.0 /opt

# Manual download and install for a specific version/platform
VERSION="16.0.0"
ARCH="linux-x86_64"
curl -fsSL --retry 5 \
  "https://github.com/sourcemeta/jsonschema/releases/download/v${VERSION}/jsonschema-${VERSION}-${ARCH}.zip" \
  -o /tmp/jsonschema.zip
unzip /tmp/jsonschema.zip -d /tmp/jsonschema
install -d -m 0755 /usr/local/bin
install -m 0755 "/tmp/jsonschema/jsonschema-${VERSION}-${ARCH}/bin/jsonschema" /usr/local/bin
rm -rf /tmp/jsonschema.zip /tmp/jsonschema
```

#### Installation Verification

**Checksum verification** (recommended): A `CHECKSUMS.txt` file containing SHA256 hashes for all release assets is published alongside each release, along with a GPG-signed `CHECKSUMS.txt.asc` file. To verify the integrity of the downloaded binary using GPG:[^readme]

```sh
curl --silent --show-error --location 'https://www.sourcemeta.com/gpg.asc' | gpg --import
gpg --verify CHECKSUMS.txt.asc CHECKSUMS.txt
```

**Binary verification**: After installation, confirm the binary is operational:

```sh
jsonschema version
# Expected output: "v16.0.0" (for the latest release)
```

Note: The version output format uses a `v` prefix (e.g., `v16.0.0`).

#### Configuration Options

##### Version Selection

Version can be specified in two ways:[^install-sh]

1. **Latest version** (default): Pass no arguments or `latest` as the first argument to the install script. The script fetches the latest release tag from the GitHub API.
2. **Specific version**: Pass a version number (without a `v` prefix) as the first argument, e.g., `16.0.0`. The script appends the `v` prefix internally when constructing the download URL.

The feature will expose a `version` option (string, default `latest`).

##### Installation Path

The default installation prefix is `/usr/local`, placing the binary at `/usr/local/bin/jsonschema`. A custom prefix can be specified as the second argument to the install script:[^install-sh]

```sh
# Install to /opt
curl -fsSL https://raw.githubusercontent.com/sourcemeta/jsonschema/main/install \
  -H 'Cache-Control: no-cache, no-store, must-revalidate' | /bin/sh -s -- latest /opt
```

The feature will expose an `installPath` option (string, default `/usr/local`).

##### User Targeting

The install script does not distinguish between system-wide and user-local installation; the target is determined solely by the installation prefix argument:[^install-sh]

- **System-wide** (requires root/sudo): Default prefix `/usr/local` (e.g., `sudo ... | /bin/sh`).
- **User-local** (no root required): Prefix e.g., `$HOME/.local` (must be in `PATH`).

The feature will expose an `installToUserDir` option (boolean, default `false`). When `true`, the binary is installed to `$HOME/.local/bin`.

##### Required Privileges

Installing to the default prefix (`/usr/local`) requires **root/sudo** on most systems, as `/usr/local/bin` is typically owned by root. Installing to a user-local directory (e.g., `$HOME/.local`) does not require elevated privileges.[^install-sh]

##### Tool-Specific Configurations

The CLI supports the following environment variables for runtime configuration:

| Variable | Description |
|----------|-------------|
| `SOURCEMETA_CORE_CURL_SO` | On Linux/BSD, sets the full path to a custom `libcurl.so.4` if it lives in a non-standard location.[^readme] |

These environment variables are optional; the CLI works out of the box on most systems without setting them.

#### Post-Installation Steps and Cleanup

##### PATH Setup

No additional PATH setup is required if the binary is installed to a directory already on the system `PATH` (e.g., `/usr/local/bin`). For user-local installations, ensure the target directory is added to `PATH`:

```sh
# For user-local installations (e.g., $HOME/.local/bin)
export PATH="$HOME/.local/bin:$PATH"
```

This can be added to `~/.profile`, `~/.bashrc`, or `~/.zshrc` for persistence.

##### Configuration Files

The CLI does not create or modify any system or user configuration files during installation. It optionally reads a `jsonschema.json` configuration file from the project directory for per-project settings, but this file is created by the user, not the installer.[^docs-configuration]

##### Environment Variables

No environment variables need to be set persistently for the CLI to work correctly.

##### Activation Scripts

No shell scripts need to be sourced or activated.

##### Shell Completions

The CLI does not ship with shell completion scripts in the binary release archives. Completions can be generated manually if the tool provides completion support in the future.

##### Cleanup

The official install script creates a temporary directory via `mktemp -d` and sets a `trap clean EXIT` handler to remove it on exit. No manual cleanup is needed.[^install-sh]

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

To change versions, simply re-run the install script with a different version argument. The new binary will overwrite the existing one at the target path. No configuration files or environment variables need to be updated.[^install-sh]

##### Uninstallation

To uninstall, simply delete the binary:

```sh
rm -f /usr/local/bin/jsonschema
```

No additional cleanup is required as the tool does not create any configuration files, caches, or data directories during installation.

##### Idempotency

The installation is fully idempotent — running the install script multiple times with the same version will overwrite the existing binary with an identical copy. Running with a different version will replace the existing binary with the new one.[^install-sh]

#### Details

The official install script is a stand-alone POSIX shell script (requires only `/bin/sh`). Below is the complete annotated logic:[^install-sh]

```sh
#!/bin/sh

set -o errexit
set -o nounset

UNAME="$(uname)"
ARCH="$(uname -m)"
OUTPUT="${2:-/usr/local}"

if [ "$UNAME" = "Darwin" ] || [ "$UNAME" = "Linux" ]
then
  echo "---- Fetching the pre-built JSON Schema CLI binary from GitHub Releases" 1>&2
  OWNER="sourcemeta"
  REPOSITORY="jsonschema"

  if [ $# -lt 1 ] || [ "$1" = "latest" ]
  then
    VERSION="$(curl --retry 5 --silent \
      "https://api.github.com/repos/$OWNER/$REPOSITORY/releases/latest" \
      | grep '"tag_name"' | cut -d ':' -f 2 | tr -d 'v" ,')"
  else
    VERSION="$1"
  fi

  PACKAGE_BASE_URL="https://github.com/$OWNER/$REPOSITORY/releases/download/v$VERSION"
  PACKAGE_PLATFORM_NAME="$(echo "$UNAME" | tr '[:upper:]' '[:lower:]')"

  if [ "$UNAME" = "Linux" ] && [ -f /etc/os-release ] && grep -qi alpine /etc/os-release
  then
    PACKAGE_NAME="jsonschema-$VERSION-$PACKAGE_PLATFORM_NAME-$ARCH-musl"
  else
    PACKAGE_NAME="jsonschema-$VERSION-$PACKAGE_PLATFORM_NAME-$ARCH"
  fi

  PACKAGE_URL="$PACKAGE_BASE_URL/$PACKAGE_NAME.zip"
  echo "---- Fetching version v$VERSION from $PACKAGE_URL" 1>&2
  TMP="$(mktemp -d)"
  clean() { rm -rf "$TMP"; }
  trap clean EXIT
  curl --retry 5 --location --output "$TMP/artifact.zip" "$PACKAGE_URL"
  unzip "$TMP/artifact.zip" -d "$TMP/out"
  install -d -m 0755 "$OUTPUT/bin"
  install -v -m 0755 "$TMP/out/$PACKAGE_NAME/bin/jsonschema" "$OUTPUT/bin"
  echo "" 1>&2
  echo "Tip: Try the Sourcemeta Studio VS Code extension for an enhanced experience!" 1>&2
  echo "     Open in VS Code: vscode:extension/sourcemeta.sourcemeta-studio" 1>&2
  echo "     Or visit: https://marketplace.visualstudio.com/items?itemName=sourcemeta.sourcemeta-studio" 1>&2
else
  echo "ERROR: I don't know how to install the JSON Schema CLI in $UNAME!" 1>&2
  echo "Open an issue here: https://github.com/sourcemeta/jsonschema/issues" 1>&2
  exit 1
fi
```

Key observations:
- The script does **not** install any dependencies (like `curl` or `unzip`) — it assumes they are already present.
- The script only supports **macOS** and **Linux** (no Windows).
- Musl detection is based on a case-insensitive grep for "alpine" in `/etc/os-release`.
- The `OUTPUT` path defaults to `/usr/local` if not provided as the second argument.
- The script prints a tip about the Visual Studio Code extension after installation.
- GitHub API is called without authentication, which is subject to [rate limiting](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api) (60 requests/hour for unauthenticated requests). If the latest version detection via API fails, the script exits with an error.

#### Notes and Best Practices

- **Rate limiting**: The install script's version detection calls the GitHub API without authentication. If the feature detects the latest version using the script's logic, it should either use a cached version or implement a fallback mechanism to avoid API rate limits.
- **Alpine Linux detection**: The musl variant selection uses a simple grep for "alpine" in `/etc/os-release`. This will correctly detect Alpine Linux but may not detect other musl-based distributions (e.g., postmarketOS, Adelie Linux). For those, you may need to manually select the `-musl` variant.
- **libcurl runtime dependency (v16.0.0+)**: On Linux, if `libcurl.so.4` is not available, any HTTP-related operation will fail at runtime with a message indicating how to install it. For strictly offline/local use (formatting, linting, compiling without remote refs), `libcurl` is not needed.
- **Processor-specific optimizations**: The pre-built binaries are compiled with optimizations for the build machine's CPU. In rare cases, this may cause `Illegal instruction` errors on older hardware. Users encountering this should build from source with `-DJSONSCHEMA_PORTABLE:BOOL=ON`.[^readme-build]
- **VS Code extension**: The install script promotes the "Sourcemeta Studio" VS Code extension. This can be mentioned to users but is not required for the CLI to function.

### GitHub Actions (Composite Action)

The official GitHub repository provides a composite GitHub Action that installs the JSON Schema CLI in CI/CD workflows.[^action-yml]

#### Supported Platforms

- Any GitHub Actions runner (Linux, macOS, Windows).

#### Dependencies

- A GitHub Actions runner environment (the action handles all tool dependencies internally).

#### Installation Steps

Add the following step to a GitHub Actions workflow:

```yaml
- name: Install the JSON Schema CLI
  uses: sourcemeta/jsonschema@v16.0.0
```

The action downloads the pre-built binary from GitHub Releases and installs it to `$HOME/.local/bin`. It then appends that directory to `$GITHUB_PATH` so the `jsonschema` command is available in subsequent workflow steps.[^action-yml]

The action internally uses the official install script with version `16.0.0` and installation prefix `$HOME/.local`.[^action-yml]

#### Installation Verification

After the action runs, the `jsonschema` command is available:

```yaml
- run: jsonschema version
```

#### Version Selection

Use a Git tag to pin the version:

```yaml
- uses: sourcemeta/jsonschema@v16.0.0
```

The action currently installs version `16.0.0` for all invocations. To use a different version, reference the corresponding tag.

#### Installation Path

The binary is installed to `$HOME/.local/bin` (typically `/home/runner/.local/bin` on GitHub-hosted runners). The action automatically adds this to `$GITHUB_PATH`.

#### Required Privileges

No special privileges are required; the action runs in the default runner user context.

#### Post-Installation Steps and Cleanup

The `jsonschema` command is available for the remainder of the workflow job via `$GITHUB_PATH`. No cleanup is required.

### Homebrew

#### Supported Platforms

- macOS (Homebrew is primarily a macOS tool; Linux support via [Linuxbrew](https://docs.brew.sh/Homebrew-on-Linux) may work but is not documented for this formula).

#### Dependencies

- Homebrew must be installed on the system.
- Xcode Command Line Tools (required by Homebrew).

#### Installation Steps

```sh
brew install sourcemeta/apps/jsonschema
```

This installs the `jsonschema` binary to Homebrew's default prefix (usually `/opt/homebrew/bin` on Apple Silicon, `/usr/local/bin` on Intel).[^readme]

#### Installation Verification

```sh
jsonschema version
```

#### Version Selection

Homebrew installs the latest available version by default. To install a specific version, you can check out an older formula revision or use the GitHub Release URL directly.

#### Installation Path

The binary is installed to Homebrew's `bin` directory, which Homebrew automatically adds to `PATH`.

#### User Targeting

Homebrew installations are per-user by design. The user must own the Homebrew prefix.

#### Required Privileges

No `sudo` is needed if Homebrew is installed in its default per-user prefix. If Homebrew is installed in `/usr/local` (older Intel macOS setups), `sudo` may be required.

#### Post-Installation Steps and Cleanup

No additional steps are required. Homebrew manages PATH and cleanup automatically.

#### Changing Versions and Uninstallation

- **Upgrade**: `brew upgrade sourcemeta/apps/jsonschema`
- **Uninstall**: `brew uninstall sourcemeta/apps/jsonschema`
- **Idempotency**: Running `brew install` again is idempotent — it will skip if the package is already installed at the latest version.

### npm (Node.js Package)

#### Supported Platforms

- macOS, Linux, Windows (Node.js is required).

#### Dependencies

- **Node.js**: Required to run `npm install`. The npm package (`@sourcemeta/jsonschema`) wraps the native binary for distribution.

#### Installation Steps

```sh
npm install --global @sourcemeta/jsonschema
```

This installs the binary globally. The npm package version matches the CLI version (e.g., `@sourcemeta/jsonschema@16.0.0` corresponds to CLI v16.0.0).[^readme]

#### Installation Verification

```sh
jsonschema version
```

#### Version Selection

Use the npm package version tag:

```sh
npm install --global @sourcemeta/jsonschema@16.0.0
```

#### Installation Path

The binary is installed to npm's global `bin` directory (usually `/usr/local/bin` or a version-managed directory).

#### Required Privileges

`sudo` may be required if npm's global prefix requires root access. Use `npm config set prefix` to configure a user-local prefix.

### PyPI (Python Package)

#### Supported Platforms

- macOS, Linux, Windows (Python is required).

#### Dependencies

- **Python 3.7+**: Required to run `pip install`.[^pypi]

#### Installation Steps

```sh
pip install sourcemeta-jsonschema
```

The package name on PyPI is `sourcemeta-jsonschema`, and the version matches the CLI version (e.g., `sourcemeta-jsonschema==16.0.0` corresponds to CLI v16.0.0).[^pypi]

#### Installation Verification

```sh
jsonschema version
```

#### Version Selection

```sh
pip install sourcemeta-jsonschema==16.0.0
```

#### Installation Path

The binary is installed into the Python environment's `bin` directory (e.g., within a virtual environment's `bin/` or system-wide `Scripts/`).

#### Required Privileges

`sudo` may be required for system-wide pip installs. Use `pip install --user` or a virtual environment for user-local installation.

### Snap

#### Supported Platforms

- **Linux**: Snap packages are available for both **amd64** and **arm64** architectures.[^release-v1600]

#### Dependencies

- `snapd` must be installed.

#### Installation Steps

```sh
sudo snap install jsonschema
```

Available since v10.0.0.[^readme]

#### Limitations

Due to Snap confinement, the Snap version can only access files under `$HOME`.[^readme]

### Docker Image

#### Supported Platforms

- Any system with Docker installed.

#### Dependencies

- **Docker Engine**: Required to run the container.

#### Installation Steps

```sh
docker run --interactive --volume "$PWD:/workspace" \
  ghcr.io/sourcemeta/jsonschema:v16.0.0 lint --verbose myschema.json
```

The Docker image is published to `ghcr.io/sourcemeta/jsonschema` and supports both `amd64` and `arm64` architectures.[^readme]

#### Important Notes

- **Do NOT allocate a pseudo-TTY** (`--tty`/`-t`) when running through Docker, as it may cause line-ending incompatibilities affecting formatting.[^readme]
- Mount the desired working directory as `/workspace` to give the CLI access to schema files.

### mise

[mise](https://mise.jdx.dev/) is a version manager that can install and switch between versions of the JSON Schema CLI.

#### Supported Platforms

- macOS, Linux (mise must be installed).

#### Dependencies

- **mise**: Must be installed and configured on the system.

#### Installation Steps

```sh
mise use jsonschema
```

This installs the latest version of the JSON Schema CLI and sets it as the active version for the current project. Subsequent invocations of `jsonschema` will use the mise-managed version.[^readme]

#### Installation Verification

```sh
jsonschema version
```

#### Version Selection

mise can install specific versions and switch between them:

```sh
mise install jsonschema@16.0.0
mise use jsonschema@16.0.0
```

#### Installation Path

mise installs tools into its own directory (typically `~/.local/share/mise/installs` or `$MISE_DATA_DIR`) and manages symlinks.

#### Required Privileges

No `sudo` is required, as mise installs to user-local directories.

### gah

[gah](https://github.com/get-gah/gah) is a third-party tool for installing applications distributed via GitHub Releases, including the JSON Schema CLI. It does not require `sudo` and installs binaries to `~/.local/bin`.[^readme]

#### Supported Platforms

- macOS, Linux (gah must be installed).

#### Dependencies

- **gah**: Must be installed on the system.

#### Installation Steps

```sh
gah install jsonschema
```

gah does not require `sudo`, but the installation directory (`$HOME/.local/bin` by default) should be on `PATH`.[^readme]

#### Installation Verification

```sh
jsonschema version
```

#### Required Privileges

No `sudo` is required, as gah installs to `$HOME/.local/bin`.

### Build from Source

#### Supported Platforms

- Any platform with a C++ compiler, CMake, and required dependencies.

#### Dependencies

- **C++ compiler** (GCC, Clang, MSVC, etc.)
- **CMake** (3.16+)
- **Git** (to clone the repository)

#### Installation Steps

```sh
git clone https://github.com/sourcemeta/jsonschema
cd jsonschema
cmake -S . -B ./build -DCMAKE_BUILD_TYPE:STRING=Release
cmake --build ./build --config Release --parallel 4
cmake --install ./build --prefix /usr/local \
  --config Release --verbose --component sourcemeta_jsonschema
```

Where `/usr/local` can be replaced with any desired prefix such as `/opt`.[^readme-build]

#### Portable Build

For a portable binary that avoids processor-specific optimizations:

```sh
cmake -S . -B ./build \
  -DCMAKE_BUILD_TYPE:STRING=Release \
  -DJSONSCHEMA_PORTABLE:BOOL=ON
```

## Dev Container Setup

When installing the jsonschema CLI in a dev container, the following considerations apply:

- **Recommended installation method**: Use the pre-built binary download (GitHub Releases) approach, as it is fast, deterministic, and does not require Node.js, Python, or a C++ toolchain in the container.
- **libcurl on Linux**: The v16.0.0+ binaries use system `libcurl` via `dlopen` on Linux. If the dev container base image does not include `libcurl4`, it should be installed (`apt-get install -y libcurl4` for Debian/Ubuntu, `apk add libcurl` for Alpine).
- **Non-root user**: Installation to `/usr/local/bin` typically requires root. The install script should be run as root (default in most dev container builds) or the `installToUserDir` option should be used for non-root installations.
- **Workspace bind mount**: No special volume mounts are required. The CLI operates on files in the workspace directory.
- **No persistent services**: The CLI requires no daemon, background service, or special container capabilities.

### Example Dockerfile snippet

```dockerfile
# Install libcurl (for Linux containers using v16.0.0+)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4 \
    && rm -rf /var/lib/apt/lists/*

# Download and install jsonschema
RUN curl -fsSL --retry 5 \
    "https://github.com/sourcemeta/jsonschema/releases/download/v16.0.0/jsonschema-16.0.0-linux-x86_64.zip" \
    -o /tmp/jsonschema.zip \
    && unzip /tmp/jsonschema.zip -d /tmp/jsonschema \
    && install -d -m 0755 /usr/local/bin \
    && install -m 0755 "/tmp/jsonschema/jsonschema-16.0.0-linux-x86_64/bin/jsonschema" /usr/local/bin \
    && rm -rf /tmp/jsonschema.zip /tmp/jsonschema
```

### pre-commit Hooks

The repository provides a `pre-commit` hook configuration. To use it, add the following to `.pre-commit-config.yaml`:[^pre-commit-hooks]

```yaml
repos:
  - repo: https://github.com/sourcemeta/jsonschema
    rev: v16.0.0
    hooks:
      - id: sourcemeta-jsonschema-lint
```

This requires the `jsonschema` CLI to be installed on the system (the hook uses `language: system`).

## Plugins and Extensions

### Sourcemeta Studio (VS Code Extension)

Sourcemeta Studio is a Visual Studio Code extension that provides JSON Schema editing, visualization, and validation capabilities in the editor. It pairs with the CLI to offer an enhanced experience.[^install-sh]

- **VS Code Marketplace**: https://marketplace.visualstudio.com/items?itemName=sourcemeta.sourcemeta-studio
- **Direct VS Code link**: `vscode:extension/sourcemeta.sourcemeta-studio`

This extension is unrelated to the feature itself but is promoted by the install script as a value-add for users.

## References

[^readme]: [Official README — Overview, Installation, Architecture, Commands, License](https://github.com/sourcemeta/jsonschema/blob/main/README.markdown)
[^readme-build]: [Official README — Building from Source, Portable Build Flag](https://github.com/sourcemeta/jsonschema/blob/main/README.markdown#building-from-source)
[^releases]: [GitHub Releases — All Releases and Tags](https://github.com/sourcemeta/jsonschema/releases)
[^release-v15110]: [GitHub Release v15.11.0 — NSURLSession/WinHTTP Support](https://github.com/sourcemeta/jsonschema/releases/tag/v15.11.0)
[^release-v1600]: [GitHub Release v16.0.0 — Assets, Checksums, Release Notes, libcurl dlopen Breaking Change](https://github.com/sourcemeta/jsonschema/releases/tag/v16.0.0)
[^install-sh]: [Official Install Script — Source Code](https://github.com/sourcemeta/jsonschema/blob/main/install)
[^action-yml]: [Official GitHub Action — Composite Action Configuration](https://github.com/sourcemeta/jsonschema/blob/main/action.yml)
[^docs-configuration]: [Official Documentation — jsonschema.json Configuration File](https://github.com/sourcemeta/jsonschema/blob/main/docs/configuration.markdown)
[^pypi]: [PyPI — sourcemeta-jsonschema Package](https://pypi.org/project/sourcemeta-jsonschema/)
[^pre-commit-hooks]: [Official pre-commit Hooks Configuration](https://github.com/sourcemeta/jsonschema/blob/main/.pre-commit-hooks.yaml)
