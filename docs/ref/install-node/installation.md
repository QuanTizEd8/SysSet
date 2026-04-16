# Installation Reference — install-node

Node.js is the most widely-deployed JavaScript runtime and ships npm (Node Package Manager) as a bundled component. It is available through virtually every OS package manager, but distro repositories carry severely outdated versions (Ubuntu 22.04 ships Node 12; Ubuntu 24.04 ships Node 18). Three approaches cover practical container and bare-metal use cases: **nvm (Node Version Manager)**, the **official prebuilt binary tarballs** from nodejs.org/dist, and **OS package managers** (only viable when a current version is not required). For devcontainer features and cross-platform standalone installers required to support version pinning and both Linux and macOS, nvm is the recommended primary method because it is the Node.js project's own recommended installation tool, handles version resolution by alias ("lts", major number, or semver), works on macOS natively, and compiles from source automatically on Alpine (musl). Official prebuilt binary tarballs are the recommended secondary method for environments where a lean, dependency-free install is preferred (no nvm overhead, no shell function wrapping) and Alpine support is not required.

---

## Available Methods

### Method 1 — nvm (Node Version Manager)

**Supported platforms:** Linux (Debian/Ubuntu, Alpine, RHEL/Fedora, Arch, and any glibc or musl distro); macOS. Works in containers and on bare metal.

**Dependencies:**
- `curl` or `wget`, `bash` ≥ 3.1, `git` (optional, only for nvm's own update mechanism)
- On Alpine (musl): nvm does NOT provide prebuilt binaries for musl; Node.js must be compiled from source using `nvm install -s <version>`. Required build dependencies for Alpine 3.13+: `curl bash ca-certificates openssl ncurses coreutils python3 make gcc g++ libgcc linux-headers grep util-linux binutils findutils`. On Alpine 3.5–3.12, use `python2` instead of `python3`.

**How nvm works:** nvm is a **shell function** (not a binary), loaded via `source "$NVM_DIR/nvm.sh"`. It downloads and manages multiple Node.js versions under `$NVM_DIR/versions/node/`. It does not install any system-level package. On Alpine / musl, nvm's prebuilt binaries are incompatible (glibc-only); compilation from source is required and must be requested explicitly with `nvm install -s <version>` — nvm does NOT auto-detect musl and fall back.

**Installation steps:**

```bash
# 1. Install nvm (system-wide, as root):
export NVM_DIR="/usr/local/share/nvm"
mkdir -p "$NVM_DIR"
curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh \
  | PROFILE=/dev/null NVM_DIR="$NVM_DIR" bash

# 2. Source nvm (in the same RUN session or new shell):
. "$NVM_DIR/nvm.sh"

# 3. Install Node.js by alias or version:
nvm install 'lts/*'       # latest Active LTS (quotes prevent glob expansion)
nvm install --lts         # equivalent flag form
nvm install 22            # latest v22.x (Jod LTS)
nvm install v24.11.1      # exact version
nvm alias default 'lts/*' # set default to latest LTS

# 4. Verify:
node --version
npm --version
```

**Version aliases supported by nvm:**
- `'lts/*'` — latest Active LTS release (must be quoted in shell to prevent glob expansion; nvm README uses `'lts/*'`)
- `--lts` — equivalent flag form; no quoting needed (e.g. `nvm install --lts`)
- `lts/<codename>` — specific LTS line by codename (e.g. `lts/krypton`, `lts/jod`); also accepted without quotes
- `latest` / `node` — very latest release (may not be LTS)
- Major number (e.g. `22`) — latest stable in that major
- Exact semver (e.g. `v22.15.1`) — specific release

**nvm install script environment variables:**
| Variable | Default | Effect |
|---|---|---|
| `NVM_DIR` | `~/.nvm` | Where nvm is installed |
| `PROFILE` | auto-detected | Shell RC file to modify; set to `/dev/null` to suppress RC edits |
| `NVM_SOURCE` | GitHub raw | Override installer URL for air-gapped installs |
| `NVM_NODEJS_ORG_MIRROR` | `https://nodejs.org/dist` | Override binary download mirror |

**nvm install directory structure:**
```
$NVM_DIR/
  nvm.sh          # main shell function loader
  bash_completion # bash completion
  versions/
    node/
      v24.11.1/
        bin/
          node
          npm
          npx
```

**Post-install PATH:** After `nvm install`, the active Node.js binary directory is available via two mechanisms:
1. **`NVM_SYMLINK_CURRENT=true` + `current` symlink**: when this env var is set before nvm install and `nvm use`, nvm maintains a `$NVM_DIR/current` symlink pointing to the active version's directory. Setting `PATH=$NVM_DIR/current/bin:$PATH` is then version-agnostic and survives `nvm use` version switches. This is the recommended approach for devcontainer features (via `containerEnv.PATH`) and for bare-metal installs (via the nvm init snippet in shell RC files).
2. **Direct versioned path export**: `$NVM_DIR/versions/node/v{VERSION}/bin` can be added to `PATH` directly, but this is only correct for single-version installs where the version never changes — writing this to shell RC files is an anti-pattern because it becomes stale after `nvm use`.

**Docker / non-interactive shell caveat:** nvm is a shell function and must be explicitly sourced in each `RUN` step:
```dockerfile
# Each RUN step that needs node must source nvm:
RUN . /usr/local/share/nvm/nvm.sh && node --version
```

**Alpine (musl) support:**
On Alpine, nvm cannot download prebuilt Node.js binaries (glibc-only); compilation from source is required and must be explicitly requested with the `-s` flag. The nvm README documents the following build dependencies for **Alpine 3.13+**:
```bash
apk add -U curl bash ca-certificates openssl ncurses coreutils python3 make gcc g++ libgcc linux-headers grep util-linux binutils findutils
```
Then install Node.js from source:
```bash
. "$NVM_DIR/nvm.sh"
nvm install -s 'lts/*'
```
For **Alpine 3.5–3.12**, substitute `python2` for `python3`. Note that older Alpine versions impose an upper bound on which Node.js versions can be built (e.g., Alpine 3.5 supports up to Node v6.9.5; Alpine 3.13/3.14 supports up to v14.20.0).

Build time: ~10–20 minutes for Node.js LTS on typical container hardware.

**Idempotency:** Checking `nvm ls <version>` returns version if already installed; `nvm install` is idempotent (skips if already present).

**nvm version pinning:** Use nvm's tag-based installer URL (`/nvm-sh/nvm/v0.40.4/install.sh`) rather than the unversioned redirect (`github.com/nvm-sh/nvm/install.sh`).

**Key known issue:** nvm's PATH updates target user-level RC files (`~/.bashrc`, `~/.zshrc`), not system-wide files. For system-wide installs (as root in containers), a manual system-wide PATH setup is required.

---

### Method 2 — Official Prebuilt Binary Tarball from nodejs.org/dist

**Supported platforms:** Linux glibc (x64, arm64, armv7l, ppc64le, s390x); macOS (x64, arm64). **Not compatible with Alpine (musl)** — the official binaries are glibc-linked.

**Dependencies:** `curl` or `wget`, `tar`, `xz-utils` (for `.tar.xz`), `checksums verify` (for SHASUMS256.txt verification).

**Version discovery:**
```bash
# Query dist index for latest LTS version:
# https://nodejs.org/dist/index.json  — JSON array, most recent first
# Field: "lts" is the LTS codename (string) or false (non-LTS/pre-release)

# Latest LTS:
node_ver=$(curl -fsSL https://nodejs.org/dist/index.json \
  | python3 -c "import sys,json; d=json.load(sys.stdin); \
    print(next(v['version'] for v in d if v['lts']))")

# Latest in a specific major:
node_ver=$(curl -fsSL https://nodejs.org/dist/index.json \
  | python3 -c "import sys,json; d=json.load(sys.stdin); \
    print(next(v['version'] for v in d if v['lts'] and v['version'].startswith('v22.')))")
```

**Architecture-to-platform mapping:**

| `uname -m` | `uname -s` | nodejs.org platform string |
|---|---|---|
| `x86_64` | Linux | `linux-x64` |
| `aarch64` | Linux | `linux-arm64` |
| `armv7l` | Linux | `linux-armv7l` |
| `ppc64le` | Linux | `linux-ppc64le` |
| `s390x` | Linux | `linux-s390x` |
| `x86_64` | Darwin | `darwin-x64` |
| `arm64` | Darwin | `darwin-arm64` |

> **Important macOS note:** on macOS, `uname -m` returns `arm64` (not `aarch64`). The nodejs.org platform string also uses `arm64`, not `aarch64`.

**Binary download URL pattern:**
```
https://nodejs.org/dist/v{VERSION}/node-v{VERSION}-{PLATFORM}.tar.xz
https://nodejs.org/dist/v{VERSION}/node-v{VERSION}-{PLATFORM}.tar.gz  (also available)
https://nodejs.org/dist/v{VERSION}/SHASUMS256.txt                       (shasum sidecar)
```

Example: `https://nodejs.org/dist/v24.11.1/node-v24.11.1-linux-x64.tar.xz`

**Installation steps:**
```bash
PLATFORM="linux-x64"   # or darwin-arm64, etc.
VERSION="v24.11.1"
PREFIX="/usr/local"

TARBALL="node-${VERSION}-${PLATFORM}.tar.xz"
BASE_URL="https://nodejs.org/dist/${VERSION}"

# Download tarball + checksum sidecar
curl -fsSLO "${BASE_URL}/${TARBALL}"
curl -fsSL  "${BASE_URL}/SHASUMS256.txt" -o SHASUMS256.txt

# Verify SHA-256
grep "${TARBALL}" SHASUMS256.txt | sha256sum --check -

# Extract (strip leading path component: node-v24.11.1-linux-x64/)
tar -xJf "${TARBALL}" --strip-components=1 -C "${PREFIX}"

# Verify
node --version   # expects: v24.11.1
npm --version

# Cleanup
rm -f "${TARBALL}" SHASUMS256.txt
```

> **macOS alternative:** On macOS, `sha256sum` is not available; use `shasum -a 256 --check` instead.

> **Security note:** `SHASUMS256.txt` is GPG-signed by the Node.js release team (signature files `SHASUMS256.txt.sig` and `SHASUMS256.txt.asc` are available at the same dist URL). This feature performs **SHA-256 checksum verification only** (against the downloaded `SHASUMS256.txt`). It does NOT verify the GPG signature of `SHASUMS256.txt` itself. Transport-layer integrity (HTTPS to `nodejs.org`) provides a baseline guarantee. Full verification would additionally require importing the [Node.js release GPG key](https://github.com/nodejs/release-keys) and verifying the `.sig` or `.asc` sidecar file.

**What gets installed:**
```
$PREFIX/
  bin/
    node
    npm
    npx
    corepack
  include/
    node/...
  lib/
    node_modules/
      npm/
      corepack/
  share/man/...
```

**No need to add to PATH when `PREFIX=/usr/local`** — `/usr/local/bin` is already in PATH in virtually all Linux distributions and macOS.

**Idempotency:** No built-in idempotency — extraction overwrites existing files. A pre-check against `node --version` output guards against re-installation.

**Version range available:** Available for every release since v4.0.0. Binaries for v18+ are `.tar.xz` and `.tar.gz`; older releases may only have `.tar.gz`.

**Alpine incompatibility:** The official Node.js prebuilt binaries are linked against glibc. Running them on musl (Alpine) will fail with `exec format error` or missing shared library errors. Alpine users must use Method 1 (nvm with source compilation) or `apk add nodejs`.

---

### Method 3 — OS Package Manager

**Supported platforms:** Any Linux distro with a package manager; macOS with Homebrew.

**Dependencies:** None beyond the existing package manager.

**Available versions by platform:**

| Platform | Package name | Version as of 2026 |
|---|---|---|
| Debian 12 (bookworm) | `nodejs` | 18.x |
| Ubuntu 22.04 (jammy) | `nodejs` | 12.x (**too old**) |
| Ubuntu 24.04 (noble) | `nodejs` | 18.x |
| Alpine 3.20+ | `nodejs`, `npm` | 22.x |
| Fedora 41 | `nodejs` | 22.x |
| RHEL 9 / Rocky 9 | `nodejs` | 18.x |
| macOS (Homebrew) | `node` | Latest stable (24.x as of 2026) |

**Installation:**
```bash
# Debian/Ubuntu
apt-get install -y nodejs npm

# Alpine
apk add --no-cache nodejs npm

# Fedora/RHEL
dnf install -y nodejs npm

# macOS
brew install node
```

**Key limitation:** Distro packages are typically 1–3 major versions behind the latest LTS, and do not allow version pinning within the distro's frozen repository. This method is only appropriate when the exact Node.js version does not matter and speed of installation is the priority.

**Homebrew note:** `brew install node` installs the latest stable Node.js release. For specific LTS versions, `brew install node@22` installs the v22 LTS series and requires `brew link --overwrite --force node@22` to make it the active version.

---

### Method 4 — NodeSource Repository (Debian/Ubuntu/RHEL)

**Supported platforms:** Debian/Ubuntu (deb packages), RHEL/Fedora/CentOS (rpm packages).

**Purpose:** Provides Debian and RPM packages for specific Node.js major versions, more up-to-date than distro base repos, but less flexible than nvm or binary downloads.

**Setup (Debian/Ubuntu):**
```bash
# NodeSource provides a convenience setup script:
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs
```

**Version selection:** The major version is embedded in the setup URL (`setup_{MAJOR}.x`). Available: 18, 20, 22, 24.

**NodeSource note:** NodeSource repos include both `nodejs` and `npm` in a single package. They follow the LTS maintenance schedule. As of 2026, NodeSource supports Node.js 18, 20, 22, and 24.

**Limitations:**
- Only Debian/Ubuntu and RHEL-family; not Alpine, Arch, macOS.
- Requires network access to `deb.nodesource.com` at install time.
- Adds a third-party apt/rpm repository to the system.
- Less flexible than nvm for multi-version management.
- Not recommended for this feature due to complexity and limited platform coverage.

---

## Results

For the `install-node` devcontainer feature and standalone installers, two methods are recommended, selected by a `method` option:

1. **`nvm` (default):** Recommended for the broadest compatibility. Uses a pinned nvm version (default: latest, resolved at install time) to install the specified Node.js version. Works on all glibc Linux distributions and macOS. Alpine is supported via source compilation using `nvm install -s`, requiring the build dependencies documented above. The nvm installation is performed system-wide to a configurable `$NVM_DIR` (e.g. `/usr/local/share/nvm`); PATH is configured by exporting the active Node.js binary directory to system-wide shell startup files. Node version aliases (`lts/*`, `--lts`, major number, exact semver) are handled natively by nvm.

2. **`binary`:** Recommended for lean, fast container images where Alpine support is not required. Downloads the official prebuilt Node.js tarball from `https://nodejs.org/dist/` and verifies SHA-256 integrity against `SHASUMS256.txt`. Version resolution (`lts/*`, `latest`, major number) is performed by querying `https://nodejs.org/dist/index.json`. No nvm overhead; installs directly to a configurable prefix (default: `/usr/local`). Not compatible with Alpine (musl) — must fail with a clear actionable error message when Alpine is detected, directing the user to use `method=nvm`.

**Implementation design notes** (for Phase 3/4, not research findings): The nvm method will use `github__latest_tag nvm-sh/nvm` to resolve the latest nvm release tag. The binary method will use `checksum__verify_sha256` (with a hash extracted from `SHASUMS256.txt`) for SHA-256 verification; for multi-user PATH configuration, `users__resolve_list` is called with `ADD_USER_CONFIG="$USERS"`, then `shell__system_path_files` / `shell__user_path_files` + `shell__sync_block` from `lib/shell.sh` are used to write PATH and nvm init snippets to shell startup files. There is no `shell__export_path` function in `lib/shell.sh`; the correct pattern is `shell__system_path_files` → `shell__sync_block` (as used in `install-miniforge`). These are design recommendations, not installation research.

**OS package manager** (Method 3) and **NodeSource** (Method 4) are not exposed as supported methods for this feature due to version staleness and limited platform coverage. If a user only needs "whatever Node.js the distro ships", they should use the `install-os-pkg` feature instead.

**Key considerations:**
- **Alpine support:** Only `method=nvm` supports Alpine. When Alpine is detected with `method=binary`, the script must fail with a clear actionable error.
- **Version resolution:** Both methods need a version resolver for `lts`, `latest`, or major-number inputs. For `method=binary`, this resolver queries `nodejs.org/dist/index.json`. For `method=nvm`, version aliases are passed directly to `nvm install`.
- **Multi-user PATH:** Both methods should support configuring PATH for multiple users via the `users` option and `users__resolve_list` + `shell__system_path_files`/`shell__user_path_files` + `shell__sync_block` from the shared library.

## References

- [Official Node.js Downloads Page](https://nodejs.org/en/download/) — Prebuilt binaries, LTS schedule, version aliases.
- [nodejs.org/dist/index.json](https://nodejs.org/dist/index.json) — Machine-readable release index; each entry has `version`, `lts` (string codename or `false`), `npm`, `date`, `files` (available platform strings).
- [Node.js Previous Releases / LTS Schedule](https://nodejs.org/en/about/previous-releases) — Detailed LTS lifecycle (release, active, maintenance, EOL dates).
- [nvm GitHub Repository](https://github.com/nvm-sh/nvm) — Official nvm documentation; installation, usage, Alpine support, container usage, Docker best practices.
- [nvm install.sh v0.40.4 (source)](https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh) — Actual installer script; `NVM_DIR`, `PROFILE`, `NVM_SOURCE`, `NVM_NODEJS_ORG_MIRROR` env vars; no-modify-PATH option.
- [devcontainers/features node install.sh](https://raw.githubusercontent.com/devcontainers/features/main/src/node/install.sh) — Reference implementation using nvm; handles Debian/RHEL/Alpine; group creation; yarn/pnpm; node-gyp.
- [NodeSource Distributions README](https://github.com/nodesource/distributions) — NodeSource apt/rpm repository setup for specific Node.js major versions.
- [lib/github.sh](../../../lib/github.sh) — `github__latest_tag` function for resolving latest nvm release tag.
- [lib/checksum.sh](../../../lib/checksum.sh) — `checksum__verify_sha256` for verifying downloaded binaries against SHASUMS256.txt.
- [lib/shell.sh](../../../lib/shell.sh) — `shell__system_path_files`, `shell__user_path_files`, `shell__sync_block` for PATH and shell initialisation configuration.
- [lib/users.sh](../../../lib/users.sh) — `users__resolve_list` for multi-user targeting.
