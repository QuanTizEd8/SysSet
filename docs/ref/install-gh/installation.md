# Installation Reference — install-gh

GitHub CLI (`gh`) is the official command-line interface to GitHub. It is a pre-compiled Go binary that brings
pull requests, issues, workflows, and other GitHub concepts directly into the terminal. Releases are published
on the GitHub Releases page at [github.com/cli/cli/releases](https://github.com/cli/cli/releases) as native
package files (`.deb`, `.rpm`) and compressed archives (`.tar.gz` for Linux, `.zip` for macOS). Release
binaries are available for Linux (`386`, `amd64`, `arm64`, `armv6`) and macOS (`amd64`, `arm64`). Official
package repositories are maintained by the GitHub CLI team for Debian/Ubuntu (apt) and RHEL/Fedora/SUSE (rpm),
enabling clean package-manager–managed installation with GPG-signed metadata. On macOS, Homebrew is officially
supported by the GitHub CLI team. Community (unofficial) packages are available on Alpine (`apk`) and Arch
Linux (`pacman`). **The Linux release binaries are built with `CGO_ENABLED=0`** (confirmed in
`.goreleaser.yml`), producing statically linked Go binaries with no glibc dependency. They run natively on
Alpine/musl and any Linux distribution without any glibc compatibility shim.

---

## Available Methods

### Method 1 — Official Package Repository (apt / rpm)

**Supported platforms:** Debian, Ubuntu, Raspberry Pi OS (via apt); RHEL, CentOS, Fedora, Amazon Linux,
openSUSE, SUSE (via dnf/yum/zypper). Not available for Alpine, Arch, or macOS (see Methods 2–4 for those platforms).

**Dependencies:** `curl` or `wget`, `gpg`, `apt-transport-https` (Debian), `dnf-plugins-core` or
`yum-utils` or `zypper` (RPM families).

#### Debian/Ubuntu (apt)

**Installation steps:**

```bash
# 1. Install prerequisites
apt-get install -y wget gpg

# 2. Download and install the GPG keyring
mkdir -p /etc/apt/keyrings
wget -nv -O /tmp/githubcli-archive-keyring.gpg \
  https://cli.github.com/packages/githubcli-archive-keyring.gpg
install -m 644 /tmp/githubcli-archive-keyring.gpg \
  /etc/apt/keyrings/githubcli-archive-keyring.gpg

# 3. Add the repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] \
  https://cli.github.com/packages stable main" \
  > /etc/apt/sources.list.d/github-cli.list

# 4. Install
apt-get update
apt-get install -y gh             # latest
apt-get install -y gh=2.89.0      # specific version (version string as-is)
```

**GPG key fingerprints** (for verification):
- `2C6106201985B60E6C7AC87323F3D4EA75716059`
- `7F38BBB59D064DBCB3D84D725612B36462313325`

**Upgrade path:** `apt-get update && apt-get install gh`.

**Uninstall:** `apt-get remove gh` (leaves keyring/repo files; remove them manually or save in a cleanup step).

**Version idempotency:** Re-running with the same version is safe. Requesting a version already installed
exits 0 (apt is idempotent).

**Known issues:**
- The community Ubuntu/Debian package in the system repos (`packages.ubuntu.com`, `packages.debian.org`)
  is **not recommended** as of November 2025 due to broken deprecated API usage in versions 2.45.x/2.46.x.
  Always use the official GitHub CLI repository.

#### RPM (dnf4 / dnf5 / yum / zypper)
Supported distros: RHEL, CentOS, Fedora, Amazon Linux 2, openSUSE, SUSE.

**dnf4 (Fedora < 41, RHEL, CentOS):**

```bash
dnf install -y 'dnf-command(config-manager)'
dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
dnf install -y gh --repo gh-cli
dnf update gh   # upgrade
```

**dnf5 (Fedora 41+):**

```bash
dnf install -y dnf5-plugins
dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo
dnf install -y gh --repo gh-cli
dnf update gh   # upgrade
```

**Amazon Linux 2 (yum):**

```bash
yum install -y yum-utils
yum-config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
yum install -y gh
yum update gh   # upgrade
```

**openSUSE / SUSE (zypper):**

```bash
# Download the .repo file directly — 'zypper addrepo <URL>' treats the URL as
# a baseurl, which produces the wrong metadata path for .repo file URLs.
mkdir -p /etc/zypp/repos.d
curl -fsSL https://cli.github.com/packages/rpm/gh-cli.repo \
  -o /etc/zypp/repos.d/gh-cli.repo
zypper --gpg-auto-import-keys ref gh-cli
zypper install -y gh
zypper update gh  # upgrade
```

**Version pinning:** The official docs show only un-versioned `dnf install gh`; they do not document a version-pinned RPM install form. This is a design constraint of `method=repos` on RPM-family distros, not a gap in the feature: for exact version pinning on RHEL/Fedora, use `method=binary`.

**Note on dnf4 vs dnf5:** Both accept `dnf install -y gh --repo gh-cli` when the repo file is copied directly to `/etc/yum.repos.d/` — no `config-manager` plugin is needed.

---

### Method 2 — Binary Download from GitHub Releases

**Supported platforms:** Linux (Debian, Ubuntu, RHEL, Fedora, Arch, Alpine — including musl/Alpine since the binaries are statically linked), macOS.
Works in containers and on bare metal. The only method that supports arbitrary version pinning on all platforms.

**Dependencies (Linux):** `curl` or `wget`, `tar`. No additional dependencies on Alpine — the binaries are statically linked (`CGO_ENABLED=0`).

**Dependencies (macOS):** `curl` or `wget`, `unzip`.

**Release asset naming convention:**

| Pattern | Platform | Example |
|---|---|---|
| `gh_<ver>_linux_<arch>.tar.gz` | Linux | `gh_2.89.0_linux_amd64.tar.gz` |
| `gh_<ver>_macOS_<arch>.zip` | macOS | `gh_2.89.0_macOS_arm64.zip` |
| `gh_<ver>_checksums.txt` | all platforms | SHA-256 for all assets |

**Architecture mapping:**

| `uname -m` output | `gh` asset arch |
|---|---|
| `x86_64` | `amd64` |
| `aarch64`, `arm64` | `arm64` |
| `i386`, `i686` | `386` |
| `armv6l`, `armv7l` | `armv6` |

**Note on macOS:** The macOS binaries use `macOS` (mixed-case) in the filename, not `darwin`.

**Installation steps (Linux):**

```bash
VERSION="2.89.0"
ARCH="amd64"   # from uname -m mapping above
BASE_URL="https://github.com/cli/cli/releases/download/v${VERSION}"

# 1. Download binary archive and checksums
curl -fsSL -o /tmp/gh.tar.gz "${BASE_URL}/gh_${VERSION}_linux_${ARCH}.tar.gz"
curl -fsSL -o /tmp/gh_checksums.txt "${BASE_URL}/gh_${VERSION}_checksums.txt"

# 2. Verify SHA-256
expected="$(grep "gh_${VERSION}_linux_${ARCH}.tar.gz" /tmp/gh_checksums.txt | awk '{print $1}')"
actual="$(sha256sum /tmp/gh.tar.gz | awk '{print $1}')"
[ "$expected" = "$actual" ] || { echo "checksum mismatch"; exit 1; }

# 3. Extract and install
tar -xzf /tmp/gh.tar.gz -C /tmp
install -m 755 /tmp/gh_${VERSION}_linux_${ARCH}/bin/gh /usr/local/bin/gh

# 4. Clean up
rm -rf /tmp/gh.tar.gz /tmp/gh_checksums.txt /tmp/gh_${VERSION}_linux_${ARCH}

# 5. Verify
gh --version
```

**Installation steps (macOS):**

```bash
VERSION="2.89.0"
ARCH="arm64"   # or amd64
BASE_URL="https://github.com/cli/cli/releases/download/v${VERSION}"

curl -fsSL -o /tmp/gh.zip "${BASE_URL}/gh_${VERSION}_macOS_${ARCH}.zip"
curl -fsSL -o /tmp/gh_checksums.txt "${BASE_URL}/gh_${VERSION}_checksums.txt"

expected="$(grep "gh_${VERSION}_macOS_${ARCH}.zip" /tmp/gh_checksums.txt | awk '{print $1}')"
actual="$(shasum -a 256 /tmp/gh.zip | awk '{print $1}')"
[ "$expected" = "$actual" ] || { echo "checksum mismatch"; exit 1; }

unzip -q /tmp/gh.zip -d /tmp/gh_unzip
install -m 755 /tmp/gh_unzip/gh_${VERSION}_macOS_${ARCH}/bin/gh /usr/local/bin/gh

rm -rf /tmp/gh.zip /tmp/gh_checksums.txt /tmp/gh_unzip
gh --version
```

**Version resolution:** Use the GitHub Releases API (`/releases/latest`) to resolve `version=latest` → exact
version tag. The `github__latest_tag cli/cli` function from `lib/github.sh` handles this, returning e.g.
`v2.89.0`; strip the `v` prefix for the download URL.

**Alpine / musl:**

The Linux binaries are built with `CGO_ENABLED=0` (source: [`.goreleaser.yml`](https://github.com/cli/cli/blob/trunk/.goreleaser.yml)), producing fully static Go executables with no glibc dependency. They run natively on Alpine/musl with no compatibility shim required.

**Shell completions:**

The `gh_<ver>_linux_<arch>.tar.gz` and macOS `.zip` archives include completions:
- `share/bash-completion/completions/gh` (bash)
- `share/zsh/site-functions/_gh` (zsh)
- `share/fish/vendor_completions.d/gh.fish` (fish)

Standard system completion install paths:
- Bash: `/etc/bash_completion.d/gh` (root) or `$HOME/.local/share/bash-completion/completions/gh` (non-root)
- Zsh: `<zshdir>/completions/_gh` (detected by `shell__detect_zshdir`) or `$HOME/.zfunc/_gh`

**Idempotency:** The binary is overwritten by `install` if a new version is requested. Check the existing
version with `gh --version` before deciding whether to skip.

---

### Method 3 — Native OS Package Manager (without GitHub CLI repo setup)

**Supported platforms:** Alpine Linux, Arch Linux. Also works on macOS via Homebrew.

**Alpine Linux (community package — unofficial, not supported by GitHub CLI team):**

```bash
apk add --no-cache github-cli
```

Package name: `github-cli` (not `gh`). Maintained by the Alpine Linux community, not by the GitHub CLI team.
Version may lag official releases. Does not support explicit version pinning via apk. The package is compiled
for musl — alternative to the static binaries from GitHub Releases, which also run on Alpine without issues.

**Arch Linux (extra repo — community, not supported by GitHub CLI team):**

```bash
pacman -S --noconfirm github-cli
```

Package name: `github-cli`. Maintained by the Arch Linux community, not by the GitHub CLI team.

**macOS via Homebrew (official — supported by GitHub CLI maintainers):**

```bash
brew install gh    # latest
```

The Homebrew formula (`gh`) is officially supported by the GitHub CLI maintainers (see [Homebrew formula](https://formulae.brew.sh/formula/gh) and [official macOS docs](https://github.com/cli/cli/blob/trunk/docs/install_macos.md)).
Homebrew tracks the latest release. Version pinning with `gh@<version>` is not generally available
for this formula (Homebrew does not maintain versioned formula variants for `gh`); use `method=binary`
for exact version pinning on macOS.

---

## Results

For a devcontainer feature targeting containers and standalone Linux/macOS system setup, the recommended
installation strategy is **two methods**:

**1. `method=repos` (default):** Sets up and uses the officially maintained package repositories
("supported by the GitHub CLI maintainers" per official docs):
- Debian/Ubuntu: official apt repo with GPG key (`cli.github.com/packages`) — supports version pinning as `gh=<version>` via apt
- RHEL/Fedora/CentOS/Amazon Linux/SUSE: official rpm repo — installs latest; exact version pinning is not documented by upstream for rpm-family installs and is excluded from this feature (use `method=binary` instead)
- macOS: Homebrew (`brew install gh`) — officially supported; version pinning via `@version` is not available for this formula
- Alpine and Arch: **community/unofficial** packages via `apk add github-cli` / `pacman -S github-cli`. These are not maintained by the GitHub CLI team and may lag behind official releases. No version pinning. Scripts log a notice when a specific version is requested on these platforms.

**2. `method=binary` (recommended for exact version pinning on all platforms):** Downloads the pre-built binary
from GitHub Releases (`github.com/cli/cli/releases`), verifies SHA-256 against `gh_<ver>_checksums.txt`, and
installs the `gh` binary to `$prefix/bin/gh`. Because the Linux binaries are built with
`CGO_ENABLED=0` (confirmed in `.goreleaser.yml`), they are fully static Go executables that run without
dependencies on any Linux distribution, including Alpine/musl. macOS binaries (zip) are also supported. Shell
completions from the archive are optionally installed. This method is slightly more maintenance-intensive:
the feature must track the release asset naming convention and checksums format.

**Key trade-offs:**
- `method=repos` gives OS-managed packages (dpkg/rpm metadata, `apt upgrade` support). On Alpine/Arch, it
  uses community-maintained packages without version pinning. On macOS, Homebrew is the official path.
- `method=binary` enables exact version pinning on all platforms including Alpine (native static binary, no
  compatibility shim needed). It installs outside the OS package manager.
- For security-conscious deployments: `method=repos` provides GPG-signed packages (official repos on
  Debian/Ubuntu/RPM). `method=binary` relies on SHA-256 checksum verification from the same release page.

**Scope of this feature:** Covers installation, shell completions, per-user git protocol and credential helper configuration (`gh config set`, `gh auth setup-git`), commit signing configuration (`gpg.format`, `commit.gpgsign`), and extension installation. Authentication (`gh auth login`) requires user interaction or a `GH_TOKEN` secret and is intentionally out of scope — users supply those at runtime.

## References

- [Official Docs — Linux Installation Methods](https://github.com/cli/cli/blob/trunk/docs/install_linux.md)
- [Official Docs — macOS Installation Methods](https://github.com/cli/cli/blob/trunk/docs/install_macos.md)
- [GitHub CLI Releases — Asset naming and checksums.txt format](https://github.com/cli/cli/releases/latest)
- [GitHub CLI Source — Repository & build overview](https://github.com/cli/cli)
- [.goreleaser.yml — Confirms `CGO_ENABLED=0` for Linux builds, archive naming convention, and completion file paths](https://github.com/cli/cli/blob/trunk/.goreleaser.yml)
- [Official Debian/Ubuntu Package Repo — GPG key, repo URL, apt instructions](https://cli.github.com/packages/)
- [Official RPM Repo File](https://cli.github.com/packages/rpm/gh-cli.repo)
- [devcontainers/features github-cli — Reference implementation (binary .deb, apt repo approach)](https://github.com/devcontainers/features/tree/main/src/github-cli)
- [Alpine Package — github-cli community package](https://pkgs.alpinelinux.org/package/edge/community/x86_64/github-cli)
- [Homebrew Formula — gh formula (maintained by GitHub CLI team)](https://formulae.brew.sh/formula/gh)
- [GitHub CLI November 2025 advisory — Community packages (2.45/2.46) broken on Ubuntu/Debian](https://github.com/cli/cli/blob/trunk/docs/install_linux.md#debian-community)
