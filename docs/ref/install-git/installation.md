# Installation Reference — install-git

Git is available on every major Linux distribution and macOS through OS package managers, and also via a dedicated Ubuntu PPA (`ppa:git-core/ppa`) that tracks the upstream stable release much more closely than distro base repos. When a precise version is required—or the running distro's package is too old—Git can be compiled from source using tarballs published on `kernel.org`. On macOS, Homebrew maintains the `git` formula at the latest stable release and is the recommended non-source method. The source build is architecture-agnostic and is the only approach that guarantees any specific version across every target platform. This document describes all available methods and derives the recommended installation strategy for the `install-git` devcontainer feature; the strategy is richer than the upstream `devcontainers/features` git feature and is an intentional design decision, not a mirror of that implementation.

---

## Available Methods

### Method 1 — OS Package Manager

**Supported platforms:** All Linux distributions with `apt`, `dnf`/`yum`, `apk`, `zypper`, or `pacman`; macOS with `brew`.

**Dependencies / requirements:** None — the package manager is already present.

**Installation steps:**

| Platform | Command |
|---|---|
| Debian/Ubuntu | `apt-get install -y git` |
| Fedora/RHEL 8+ | `dnf install -y git` |
| RHEL 7 / CentOS 7 | `yum install -y git` |
| Alpine | `apk add --no-cache git` |
| openSUSE / SLES | `zypper install -y git` |
| Arch / Manjaro | `pacman -S --noconfirm git` |
| macOS | `brew install git` |

**Version available:** Determined by the distro's own freeze point. Ubuntu 22.04 (as of April 2026) ships git 2.34 in its base repos, while the latest upstream stable is in the 2.5x range. For containers needing a recent version without building, the PPA (Ubuntu) or source method is preferable.

**Homebrew note:** As of April 2026 the `git` formula provides the latest stable git (2.53.0). The `git-gui` and `git-svn` sub-tools have been split into separate formulae (`git-gui`, `git-svn`).

**Verification:** `git --version`

**Post-install:** No extra PATH or shell configuration required — packages place git in the system PATH automatically.

**Idempotency:** Re-running install when git is already present either upgrades it (default behaviour) or no-ops if already at the latest available version.

**Upgrade:** `apt-get upgrade git` / `dnf upgrade git` / etc.

**Uninstall:** `apt-get remove git` / `dnf remove git` / etc.

---

### Method 2 — Ubuntu PPA (`ppa:git-core/ppa`)

**Supported platforms:** Ubuntu only (not Debian or other apt-based distros; the PPA ships Ubuntu-specific packages keyed to Ubuntu codenames).

**PPA name:** `ppa:git-core/ppa` — maintained by the Ubuntu Git Maintainers team.  
**Signing key fingerprint:** `F911AB184317630C59970973E363C90F8F1B6217`

**Available versions:** As of April 2026 the PPA publishes git 2.53.0 for Ubuntu 22.04 (jammy), 24.04 (noble), and 26.04 (plucky), plus older EOL series. Coverage is per-codename; a codename must be present in the PPA's package list before use (check the live [PPA packages page](https://launchpad.net/~git-core/+archive/ubuntu/ppa/+packages)).

**Dependencies required before adding PPA:** `curl`, `ca-certificates`, `gpg`/`gnupg`.

**No `software-properties-common` / `add-apt-repository` needed** — the PPA repo can be added manually with a `sources.list.d` entry after importing the key, avoiding the `software-properties-common` package (which pulls in Python).

**Installation steps:**
```bash
# 1. Import GPG key directly from Launchpad (more reliable than keyserver pools in containers)
curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF911AB184317630C59970973E363C90F8F1B6217" \
  | gpg --dearmor -o /usr/share/keyrings/git-core-ppa.gpg

# 2. Add sources.list entry
CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
printf 'deb [arch=%s signed-by=/usr/share/keyrings/git-core-ppa.gpg] https://ppa.launchpadcontent.net/git-core/ppa/ubuntu %s main\n' \
  "$(dpkg --print-architecture)" "$CODENAME" \
  > /etc/apt/sources.list.d/git-core-ppa.list

# 3. Install
apt-get update
apt-get install -y --no-install-recommends git

# 4. Cleanup
apt-get clean
apt-get dist-clean 2>/dev/null || rm -rf /var/lib/apt/lists/*
```

**Key import fallback:** GPG keyserver availability can vary in container network environments. The direct URL above (`keyserver.ubuntu.com/pks/lookup?op=get&...`) is the same key published on Launchpad. If it fails, the reference devcontainers/features implementation probes multiple keyservers (`hkp://keyserver.ubuntu.com`, `hkp://keyserver.pgp.com`, `hkps://keys.openpgp.org`) with retries as a fallback strategy (see [reference install.sh](https://github.com/devcontainers/features/blob/main/src/git/install.sh)).

**Verification:** `git --version`

**Idempotency:** Re-running installs the latest PPA version, which may upgrade an existing installation.

**Known issues:**
- Works only on Ubuntu (not Debian). The `VERSION_CODENAME` from `/etc/os-release` must match a series present in the PPA.
- If the PPA does not yet have a package for the running codename (e.g. a new Ubuntu release published after the PPA was last updated), the install will fail; the script should detect this and fall back to the OS package or source method.

---

### Method 3 — Build from Source (kernel.org tarball)

**Supported platforms:** All Linux distributions and macOS with Xcode CLT (see macOS note below). This is the only truly version-pinned method.

**Version discovery:** The git project does **not** use GitHub Releases; it publishes releases as GitHub Tags only. Tags follow the pattern `v<major>.<minor>.<patch>` (e.g. `v2.47.2`). Use the GitHub **Tags** API to enumerate versions:
```
https://api.github.com/repos/git/git/tags
```
The `name` fields on each tag object contain the version strings (e.g. `"name": "v2.47.2"`). This is also how the [devcontainers/features reference implementation](https://github.com/devcontainers/features/blob/main/src/git/install.sh) resolves versions.

**Source tarball URLs:**
- kernel.org (preferred — also distributes signed SHA-256 checksums): `https://www.kernel.org/pub/software/scm/git/git-<version>.tar.gz` (`.tar.xz` also available and used by Alpine)
- GitHub archive (equivalent): `https://github.com/git/git/archive/v<version>.tar.gz`
- Checksum file: `https://www.kernel.org/pub/software/scm/git/sha256sums.asc` — a GPG-signed file listing SHA-256 hashes for all published tarballs.

**Build dependencies by platform (no-docs build):**

| Platform | Required packages |
|---|---|
| Debian/Ubuntu | `build-essential curl ca-certificates tar gettext libssl-dev zlib1g-dev libcurl4-openssl-dev libexpat1-dev libpcre2-dev` + `libpcre2-posix3` (≥bookworm/jammy), `libpcre2-posix2` (focal/bullseye), or `libpcre2-posix0` (bionic/buster) |
| Fedora/RHEL 8+ | `gcc make curl tar gzip ca-certificates libcurl-devel expat-devel gettext-devel openssl-devel perl-devel zlib-devel pcre2-devel` |
| Alpine | `make gcc g++ curl-dev expat-dev openssl-dev pcre2-dev perl-dev zlib-dev` |
| macOS | Xcode CLT only for the minimal build; `brew install pcre2` for `USE_LIBPCRE2` support |
| openSUSE | `gcc make curl tar gzip ca-certificates libcurl-devel libexpat-devel gettext-devel libopenssl-devel zlib-devel libpcre2-devel` |
| Arch | `base-devel pcre2 curl expat openssl zlib` |

**Build steps (Linux, no docs):**
```bash
VERSION="2.47.2"   # resolved at runtime via GitHub Tags API
INSTALLER_DIR="/tmp/git-build"
PREFIX="/usr/local"
SYSCONFDIR="/etc"

mkdir -p "${INSTALLER_DIR}"
curl -fsSL "https://www.kernel.org/pub/software/scm/git/git-${VERSION}.tar.gz" \
  | tar -xzC "${INSTALLER_DIR}"
cd "${INSTALLER_DIR}/git-${VERSION}"
make -s \
  prefix="${PREFIX}" \
  sysconfdir="${SYSCONFDIR}" \
  USE_LIBPCRE2=YesPlease \
  all
make -s \
  prefix="${PREFIX}" \
  sysconfdir="${SYSCONFDIR}" \
  USE_LIBPCRE2=YesPlease \
  install
```

**About `USE_LIBPCRE2` vs `USE_LIBPCRE`:**  
The git Makefile defines `USE_LIBPCRE2 ?= $(USE_LIBPCRE)` — so setting `USE_LIBPCRE=YesPlease` implicitly enables pcre2 when pcre2 libraries are present. `USE_LIBPCRE2=YesPlease` is the explicit flag that pins to pcre2 (libpcre2-8 ABI), preferred since git 2.14. The reference `devcontainers/features` implementation uses `USE_LIBPCRE=YesPlease` (which also works since pcre2 is installed). The Alpine APKBUILD uses `USE_LIBPCRE2=YesPlease`. Our feature uses `USE_LIBPCRE2=YesPlease` for explicitness, which is correct and consistent with Alpine practice.

**Alpine-specific Makefile flags (from Alpine APKBUILD `prepare()` section):**  
The Alpine APKBUILD writes these flags into `config.mak` before the build:
```
NO_GETTEXT=YesPlease
NO_SVN_TESTS=YesPlease
NO_REGEX=YesPlease
NO_SYS_POLL_H=1
USE_LIBPCRE2=YesPlease
```
Without `NO_REGEX=YesPlease`, the build uses a POSIX regex library that behaves differently under musl libc. Without `NO_GETTEXT=YesPlease`, linking against gettext introduces issues under musl. These flags are sourced directly from [`APKBUILD prepare()` at alpine/aports](https://gitlab.alpinelinux.org/alpine/aports/-/blob/master/main/git/APKBUILD) — the same source used by the official Alpine `git` package. The version number (e.g. 2.53.0-r1) comes from the [Alpine Packages page](https://pkgs.alpinelinux.org/package/edge/main/x86_64/git).

**Debian/Ubuntu `libpcre2-posix` codename matrix:**
| Codename | Package name |
|---|---|
| bookworm, jammy (22.04), noble (24.04), and newer | `libpcre2-posix3` |
| bullseye, focal (20.04) | `libpcre2-posix2` |
| buster, bionic (18.04) | `libpcre2-posix0` |

The dependency manifest must conditionally install the correct posix package by codename.

**macOS source build:**  
macOS source builds are **not the primary installation path** on macOS. The official git documentation recommends Xcode CLT or Homebrew for macOS users (see [git-scm.com/book Installing Git on macOS](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)). In the typical devcontainer workflow, the container is a Linux environment even when running on Apple Silicon; macOS-native use is covered by Method 1 (Homebrew). If a source build is explicitly requested on macOS, the script should warn, install Xcode CLT dependencies, and may need `brew install pcre2 gettext openssl` for full feature support.

**Verification:** `${PREFIX}/bin/git --version`

**PATH export:** `/usr/local/bin` is already on PATH in most containers. If using a non-standard prefix, a `containerEnv` PATH export or shell profile entry is required.

**Idempotency:** Check `git --version` and compare to the requested version; skip rebuild if already at the same version.

**Post-install cleanup:** Remove `${INSTALLER_DIR}/git-${VERSION}` build tree.

**Upgrade:** Re-run with a higher version string.

**Known issues:**
- Build time is significant (~3–5 minutes on a typical container CPU). Source builds should be reserved for cases where the OS package or PPA cannot satisfy the version requirement.
- The `libpcre2-posix*` package has different names across Debian/Ubuntu codenames (see matrix above); the dependency manifest must handle this with per-codename `when` clauses.

---

### Method 4 — macOS Binary Installer

**Supported platforms:** macOS only.

This method (the [git-scm.com macOS installer](https://git-scm.com/download/mac)) is not suitable for automated container or scripted server setup because it requires a GUI package manager (macOS Installer). It is not implemented in this feature. Homebrew (Method 1) is the recommended automated macOS path.

---

## Results

**Recommended strategy for the `install-git` feature — two explicit methods:**

> Note: this API design is richer than the [upstream devcontainers/features git feature](https://github.com/devcontainers/features/blob/main/src/git/devcontainer-feature.json), which only exposes `version` (proposals: `latest`, `system`, `os-provided`) and a boolean `ppa`. The `install-git` feature is intentionally designed with an explicit `method` option to give users clear control over the installation strategy.

1. **`package` (default):** Install git from the system package manager via `ospkg__run`. Fast, zero build-time dependencies. Sufficient for most uses. On macOS, this delegates to Homebrew. On Ubuntu with `version=latest`, the feature transparently attempts to add the `ppa:git-core/ppa` source to get a more recent version; this is an internal implementation detail and does not require a separate user-facing method value, since the PPA always targets the latest stable release of the same "git" package and the user experience is identical.

2. **`source`:** Build git from the kernel.org tarball. Works on all Linux distributions and macOS (requires Xcode CLT). Slowest but guaranteed version-precise and works for any version reachable via the GitHub Tags API.

**Key design decisions:**
- OS packages first for speed; source is opt-in only.
- The PPA-for-Ubuntu path is an internal optimization within the `package` method, not a separate user-facing method, keeping the API surface small and easy to reason about.
- Source builds download from `kernel.org`, which also distributes a signed SHA-256 checksum file (`sha256sums.asc`), enabling tarball integrity verification.
- Version discovery for source builds uses the GitHub Tags API (`/repos/git/git/tags`) since the git project does not publish GitHub Releases.

---

## References

- [Official Docs – Installing Git (Pro Git Book)](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git) — All platforms, source build dependencies, macOS guidance.
- [git/git INSTALL file](https://github.com/git/git/blob/master/INSTALL) — Authoritative Makefile variable reference and dependency list.
- [git/git Makefile](https://github.com/git/git/blob/master/Makefile) — `USE_LIBPCRE2`, `NO_REGEX`, `NO_GETTEXT` definitions and behavior.
- [Ubuntu Git Maintainers PPA (git-core/ppa)](https://launchpad.net/~git-core/+archive/ubuntu/ppa) — PPA description, key fingerprint, published packages by Ubuntu codename.
- [devcontainers/features – git install.sh](https://github.com/devcontainers/features/blob/main/src/git/install.sh) — Reference implementation: PPA key import with keyserver fallbacks, multi-distro source build, partial version matching via GitHub Tags API.
- [devcontainers/features – git devcontainer-feature.json](https://github.com/devcontainers/features/blob/main/src/git/devcontainer-feature.json) — Reference API (version, ppa options).
- [Homebrew Formula – git](https://formulae.brew.sh/formula/git) — macOS Homebrew support, current stable version, note on git-gui/git-svn formula splits.
- [Alpine Packages – git](https://pkgs.alpinelinux.org/package/edge/main/x86_64/git) — Alpine package version.
- [alpinelinux/aports – git APKBUILD](https://gitlab.alpinelinux.org/alpine/aports/-/blob/master/main/git/APKBUILD) — Alpine-specific build flags (`NO_REGEX`, `NO_GETTEXT`, `USE_LIBPCRE2`) and build dependencies (`curl-dev`, `expat-dev`, `openssl-dev`, `pcre2-dev`, `perl-dev`, `zlib-dev`).
- [kernel.org git release directory](https://www.kernel.org/pub/software/scm/git/) — Source tarballs (.tar.gz, .tar.xz) and signed SHA-256 checksum file (`sha256sums.asc`).
