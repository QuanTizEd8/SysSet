# Implementation Reference — install-git

The installer has two top-level code paths (`package`, `source`) dispatched directly from `$METHOD`. The `package` path installs git via the OS package manager; on Ubuntu with `VERSION=latest` it first configures the git-core PPA before installing. The `source` path downloads a `kernel.org` tarball, verifies its SHA-256 checksum, and runs `make && make install` with platform-appropriate flags.

The script lives at `src/install-git/scripts/install.sh` and must only orchestrate; all reusable logic (GitHub API, checksum, OS detection) is delegated to `lib/` functions.

---

## Building Blocks

### 1. `github__tags` + `_github__api_list_field` — **NEW in `lib/github.sh`**

**Responsibility:** `github__tags` enumerates git tag names from the GitHub **Tags** API (`/tags?per_page=<n>`). Needed because the `git/git` repository does not publish GitHub Releases; version discovery for source builds must use the Tags endpoint.

`github__release_tags` (existing) and `github__tags` (new) share identical structure — build a URL, fetch it, extract a string field from every array element, handle errors — differing only in the endpoint path (`/releases` vs `/tags`) and the JSON field name (`tag_name` vs `name`). To avoid duplication, both are refactored to delegate to a new private helper `_github__api_list_field`.

**`_github__api_list_field <url> <field>` — private helper:**
```sh
# _github__api_list_field <url> <field>
# Fetches <url> via _github__api_get and prints the value of <field>
# for every JSON object in the response array, one per line.
# Exits 1 on fetch failure or empty response.
_github__api_list_field() {
  local _url="$1" _field="$2"
  local _json
  _json="$(_github__api_get "$_url")" || {
    echo "⛔ _github__api_list_field: failed to reach '${_url}'." >&2
    return 1
  }
  [ -z "$_json" ] && {
    echo "⛔ _github__api_list_field: empty response from '${_url}'." >&2
    return 1
  }
  printf '%s\n' "$_json" \
    | grep "\"${_field}\"" \
    | sed "s/.*\"${_field}\": *\"\([^\"]*\)\".*/\1/"
  return 0
}
```

**Refactored `github__release_tags`** (body replaces current implementation):
```sh
github__release_tags() {
  local _repo="$1"; shift
  local _per_page=100
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --per_page) shift; _per_page="$1"; shift ;;
      *) echo "⛔ github__release_tags: unknown option: '$1'" >&2; return 1 ;;
    esac
  done
  _github__api_list_field \
    "https://api.github.com/repos/${_repo}/releases?per_page=${_per_page}" \
    "tag_name" || {
    echo "⛔ github__release_tags: failed for '${_repo}'." >&2
    return 1
  }
  return 0
}
```

**New `github__tags`:**
```sh
# github__tags <owner/repo> [--per_page <n>]
# Prints one tag name per line for the given repository using the /tags endpoint.
# Works for repositories that publish tags without formal GitHub Releases.
# Respects GITHUB_TOKEN. Caller is responsible for sorting and filtering.
github__tags() {
  local _repo="$1"; shift
  local _per_page=100
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --per_page) shift; _per_page="$1"; shift ;;
      *) echo "⛔ github__tags: unknown option: '$1'" >&2; return 1 ;;
    esac
  done
  _github__api_list_field \
    "https://api.github.com/repos/${_repo}/tags?per_page=${_per_page}" \
    "name" || {
    echo "⛔ github__tags: failed for '${_repo}'." >&2
    return 1
  }
  return 0
}
```

**JSON format note:** Tags API objects have a top-level `"name"` field (the tag string, e.g. `"v2.47.2"`). The only nested object is `"commit"`, which contains only `"sha"` and `"url"` — no nested `"name"` — so the `grep`/`sed` extraction is safe.

**Caller sorting:** The Tags API does not guarantee version-sorted order. For `version=latest`: sort all tags numerically by three components, take the highest (RCs included). For `version=stable`: filter to `^v[0-9]+\.[0-9]+\.[0-9]+$` first (strips `-rc*`, `-beta*`, etc.), then sort. Both use `sort -t. -k1,1n -k2,2n -k3,3n` after stripping the `v` prefix.

---

### 2. `ospkg__run` — **REUSED from `lib/ospkg.sh`**

**Responsibility:** Full pipeline (update → install from manifest → clean) for installing OS packages from a YAML manifest. Used by the `source` method to install build dependencies before compiling.

**Usage:**
```bash
ospkg__run --manifest "${_BASE_DIR}/dependencies/source-build.yaml"
```

---

### 3. `ospkg__install` — **REUSED from `lib/ospkg.sh`**

**Responsibility:** Install one or more named packages. Used by the `package` method after PPA configuration to install `git` from the freshly added repo.

**Usage:**
```bash
ospkg__install git
```

---

### 4. `checksum__verify_sha256` — **REUSED from `lib/checksum.sh`**

**Responsibility:** Verify a downloaded file's SHA-256 digest. Used after fetching the `kernel.org` tarball for the `source` method.

**Usage:** The script fetches `sha256sums.asc` alongside the tarball, parses the expected hash for the specific filename with `awk`/`grep`, and passes it to this function:
```bash
_expected="$(grep "git-${_VERSION}.tar.gz" "${_INSTALLER_DIR}/sha256sums.asc" | awk '{print $1}')"
checksum__verify_sha256 "${_INSTALLER_DIR}/git-${_VERSION}.tar.gz" "$_expected"
```

Note: `sha256sums.asc` from kernel.org is a GPG-signed file; the plaintext hash lines are still readable without GPG verification. The feature verifies the **hash** of the tarball but does NOT verify the GPG signature of the sidecar file itself (requiring `gpg` and the kernel.org key would add significant complexity). This is the same posture as the devcontainers/features reference implementation.

---

### 5. `net__fetch_url_file` / `net__fetch_url_stdout` — **REUSED from `lib/net.sh`** (auto-sourced by ospkg.sh)

**Responsibility:** HTTP fetch with curl/wget auto-selection and 3 retries. Used for:
- Downloading the source tarball and checksum file (→ `net__fetch_url_file`)
- Fetching the PPA GPG key from `keyserver.ubuntu.com` (→ `net__fetch_url_stdout`)

---

### 6. `os__id`, `os__platform`, `os__kernel` — **REUSED from `lib/os.sh`** (auto-sourced by ospkg.sh)

**Responsibility:**
- `os__id` → returns `ubuntu`, `debian`, `alpine`, `fedora`, `rhel`, `macos`, etc. Used to detect Ubuntu for PPA eligibility and to gate the `ppa` method.
- `os__platform` → returns `debian` | `alpine` | `rhel` | `macos`. Used to select Alpine-specific make flags.
- `os__kernel` → returns `Linux` | `Darwin`. Used to gate macOS-specific warnings.

---

### 7. `os__codename` — **NEW in `lib/os.sh`**

**Responsibility:** Returns the Ubuntu (or Debian) codename for the running OS. Used by `_git__ppa_check_codename` to decide whether to attempt the PPA. Reads `VERSION_CODENAME` from `/etc/os-release`, falling back to `UBUNTU_CODENAME` (present on some older Ubuntu releases). Returns an empty string on non-Debian systems or when neither field exists.

**Implementation:** Extend `_os__load_release` to also cache `VERSION_CODENAME` / `UBUNTU_CODENAME` into `_OS__CODENAME`. Add a public accessor:
```sh
os__codename() {
  _os__load_release
  echo "${_OS__CODENAME:-}"
  return 0
}
```
In `_os__load_release`, add after the `ID_LIKE` extraction:
```sh
_OS__CODENAME="$(grep -m1 '^VERSION_CODENAME=' /etc/os-release 2>/dev/null | \
  sed 's/^VERSION_CODENAME=//;s/^"//' | sed 's/"$//' || true)"
if [ -z "${_OS__CODENAME:-}" ]; then
  _OS__CODENAME="$(grep -m1 '^UBUNTU_CODENAME=' /etc/os-release 2>/dev/null | \
    sed 's/^UBUNTU_CODENAME=//;s/^"//' | sed 's/"$//' || true)"
fi
```

---

### 8. `users__resolve_list` — **REUSED from `lib/users.sh`**

**Responsibility:** Expands env-var-driven user lists (via `ADD_USER_CONFIG`, `ADD_REMOTE_USER_CONFIG`, `ADD_CONTAINER_USER_CONFIG`, `ADD_CURRENT_USER_CONFIG`) into a deduplicated, newline-separated list of concrete usernames on stdout. Used by `_git__write_user_gitconfig` to enumerate per-user gitconfig targets.

---

### 9. `shell__resolve_home` — **REUSED from `lib/shell.sh`**

**Responsibility:** Returns the home directory for a given username via `eval echo "~${_user}"`. Used by `_git__write_user_gitconfig` to locate each user's `~/.gitconfig`.

---

## Dependency Manifests

### `dependencies/os-pkg.yaml` (NEW — simple one-liner)

Contains only `git`. All OS package managers name the package `git`.

```yaml
packages:
  - git
```

Used by the `package` method (plain package path) via `ospkg__run --manifest "${_BASE_DIR}/dependencies/os-pkg.yaml"`.

---

### `dependencies/source-build.yaml` (NEW — replaces current `base.yaml`)

Contains the full set of build dependencies for the `source` method, with per-PM blocks and per-codename conditionals for the `libpcre2-posix*` package split on Debian/Ubuntu.

```yaml
# Build dependencies for compiling git from source.
# These are only installed when method=source.

packages:
  - curl
  - ca-certificates
  - tar

apt:
  packages:
    - build-essential
    - gettext
    - libcurl4-openssl-dev
    - libexpat1-dev
    - libpcre2-dev
    - libssl-dev
    - zlib1g-dev
    # libpcre2-posix package name varies by Debian/Ubuntu codename:
    - name: libpcre2-posix3
      when: {version_codename: [bookworm, jammy, noble, plucky, oracular, mantic]}
    - name: libpcre2-posix2
      when: {version_codename: [focal, bullseye]}
    - name: libpcre2-posix0
      when: {version_codename: [bionic, buster]}

brew:
  packages:
    - make
    - openssl
    - pcre2
    - gettext

dnf:
  packages:
    - gcc
    - make
    - gettext-devel
    - libcurl-devel
    - expat-devel
    - openssl-devel
    - pcre2-devel
    - perl-devel
    - zlib-devel

apk:
  packages:
    - make
    - gcc
    - g++
    - musl-dev
    - curl-dev
    - expat-dev
    - openssl-dev
    - pcre2-dev
    - perl-dev
    - zlib-dev

zypper:
  packages:
    - gcc
    - make
    - gettext-tools
    - libcurl-devel
    - libexpat-devel
    - libopenssl-devel
    - libpcre2-devel
    - zlib-devel

pacman:
  packages:
    - base-devel
    - pcre2
    - curl
    - expat
    - openssl
    - zlib
```

---

### `dependencies/base.yaml` (REPLACED by the two files above)

The existing `dependencies/base.yaml` (apt-only, incomplete) will be replaced. The file will be removed and replaced by `os-pkg.yaml` and `source-build.yaml`.

---

## Script Functions (in `scripts/install.sh`)

### `_git__check_exists`

Checks whether `git` is already in PATH and applies the `$IF_EXISTS` policy.

```
inputs:  IF_EXISTS, METHOD, VERSION, PREFIX
logic:
  if git not in PATH: return 0  # proceed with install

  # Version short-circuit — scope depends on METHOD and VERSION:
  #
  # method=source OR method=package with a specific version string:
  #   Resolve _RESOLVED_VERSION:
  #     - source: call _git__source_resolve_version (GitHub Tags API)
  #     - package, specific version: _RESOLVED_VERSION="${VERSION}" (no API call)
  #   Parse installed version: strip "git version " prefix from `git --version`.
  #   If installed == _RESOLVED_VERSION: log notice + exit 0 (always, ignoring IF_EXISTS).
  #
  # method=package, version=latest or stable:
  #   Skip version comparison entirely — querying the PM for its candidate version
  #   is complex, PM-specific, and unnecessary. Go directly to IF_EXISTS policy.
  #   (Package managers are inherently idempotent; reinstalling a current version
  #   is always a cheap no-op.)

  # Apply IF_EXISTS policy:
  case IF_EXISTS in
    skip)      log notice; exit 0 ;;
    fail)      log error; exit 1 ;;
    reinstall) _git__detect_install_method → _EXISTING_METHOD
               _git__reinstall "${_EXISTING_METHOD}" ;;
    update)    _git__detect_install_method → _EXISTING_METHOD
               if [ "${_EXISTING_METHOD}" != "${METHOD}" ]; then
                 # method switch — identical to reinstall
                 _git__reinstall "${_EXISTING_METHOD}"
               elif [ "${METHOD}" = "source" ]; then
                 # source→source: only tear down if prefix changed
                 _old_prefix="$(dirname "$(dirname "$(command -v git)")")"
                 if [ "${_old_prefix}" != "${PREFIX}" ]; then
                   _git__reinstall "source" "${_old_prefix}"
                 fi
                 # else: same prefix → make install overwrites in place, no teardown
               fi
               # package→package: fall through; package manager handles upgrade natively
               ;;
  esac
```

---

### `_git__detect_install_method`

Detects whether the currently installed `git` was installed by the OS package manager or built from source. Returns `"package"` or `"source"` via stdout.

```
inputs:  none (uses `command -v git` internally)
outputs: prints "package" or "source" to stdout

logic (per platform):
  _git_bin="$(command -v git)"
  debian/ubuntu: dpkg -S "${_git_bin}" → succeeds → "package"
  alpine:        apk info --who-owns "${_git_bin}" | grep -q 'owned by' → "package"
  rhel/fedora:   rpm -qf "${_git_bin}" → exit 0 → "package"
  macos:         brew list git 2>/dev/null → non-empty → "package"
  fallback:      echo "source"
```

---

### `_git__reinstall`

Removes the existing git installation (using the detected method) to prepare for a clean reinstall.

```
inputs:  $1 = existing_method ("package" or "source")
         $2 = prefix_to_remove (optional; defaults to $PREFIX — used by update when old prefix differs)

_remove_prefix="${2:-${PREFIX}}"

if existing_method == "package":
  debian/ubuntu: apt-get remove -y git
  alpine:        apk del git
  rhel/fedora:   dnf remove -y git  (or yum)
  macos:         brew remove git

if existing_method == "source":
  remove: ${_remove_prefix}/bin/git ${_remove_prefix}/bin/git-*
  remove: ${_remove_prefix}/lib/git-core/
  remove: ${_remove_prefix}/share/git-core/
  remove: ${_remove_prefix}/share/man/man1/git* ${_remove_prefix}/share/man/man5/git*
         ${_remove_prefix}/share/man/man7/git*
  debian/ubuntu only: if dpkg -s git 2>/dev/null shows equivs-installed dummy:
    apt-get purge -y git  # removes the equivs dummy
return 0
```

After `_git__reinstall` returns, the normal `_git__install_package` or `_git__install_source` flow proceeds unconditionally.

---

### `_git__install_package`

Installs git via the OS package manager. Internally decides between PPA and plain package install based on `VERSION` and OS.

```
inputs: VERSION
logic:
  if VERSION == "latest" && os__id == "ubuntu":
    call _git__ppa_check_codename → confirms codename is in PPA; if not, warn + fall back
    if codename supported:
      call _git__ppa_import_key
      write /etc/apt/sources.list.d/git-core-ppa.list (signed-by=)
      apt-get update
      ospkg__install git
      apt-get clean + dist-clean
    else:
      ospkg__run --manifest ${_BASE_DIR}/dependencies/os-pkg.yaml
  elif VERSION == "stable" or os__id != "ubuntu":
    ospkg__run --manifest ${_BASE_DIR}/dependencies/os-pkg.yaml
  else:
    # specific version string — build an inline manifest with a version object.
    # ospkg translates {name: git, version: X.Y.Z} to the PM-native syntax
    # automatically: git=X.Y.Z (apt/apk/pacman/zypper), git-X.Y.Z (dnf/yum),
    # git@X.Y.Z (brew). No manual PM-specific translation needed.
    ospkg__run --manifest "$(printf 'packages:\n  - name: git\n    version: "%s"\n' "${VERSION}")"
```

---

### `_git__ppa_check_codename` (internal helper called by `_git__install_package`)

Decides whether the PPA should be attempted for the running Ubuntu codename.

```
inputs:  none
outputs: returns 0 (proceed with PPA) or 1 (skip PPA, fall back to base repo)

logic:
  _codename="$(os__codename)"
  case "${_codename}" in
    # Known EOL codenames dropped by ppa:git-core/ppa.
    bionic|eoan|groovy|hirsute|impish|kinetic|lunar|mantic)
      log warning "Ubuntu ${_codename} is EOL and not supported by ppa:git-core/ppa — falling back to base apt repo."
      return 1
      ;;
    *)
      # Unknown or new codename: attempt the PPA and let apt-get update
      # be the real gate. This automatically supports future Ubuntu releases
      # without requiring a list update.
      return 0
      ;;
  esac
```

---

### `_git__ppa_import_key` (internal helper called by `_git__install_package`)

Imports the PPA GPG key to `/usr/share/keyrings/git-core-ppa.gpg`.

Strategy:
1. Try HTTPS fetch first: `net__fetch_url_stdout "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF911AB184317630C59970973E363C90F8F1B6217" | gpg --dearmor -o /usr/share/keyrings/git-core-ppa.gpg`
2. On failure, fall back to `gpg --recv-keys --keyserver <ks> <fingerprint>` for keyservers: `hkp://keyserver.ubuntu.com`, `hkp://keyserver.pgp.com`, `hkps://keys.openpgp.org`
3. After successful `gpg --recv-keys`, export: `gpg --export --armor "$_fingerprint" | gpg --dearmor -o "$_keyring"`
4. If all attempts fail, log a fatal error and exit 1.

---

### `_git__install_source`

Main source-build orchestrator. Called when `METHOD=source`. By this point `PREFIX` and `SYSCONFDIR` are already resolved (no `auto` values remain).

Steps:
1. Validate writeability of `PREFIX`: `mkdir -p "${PREFIX}" 2>/dev/null && [ -w "${PREFIX}" ]`; exit 1 with clear error if not writable.
2. Call `_git__source_resolve_version` → sets `_RESOLVED_VERSION`
3. If macOS: check Xcode CLT via `xcode-select --print-path`; exit 1 with clear error if absent
4. Install build deps: `ospkg__run --manifest "${_BASE_DIR}/dependencies/source-build.yaml"`
5. Call `_git__source_fetch_verify` → fetches tarball to `$INSTALLER_DIR/git-<version>.tar.gz`
6. Extract: `tar -xzf`
7. Call `_git__source_build` → make + make install
8. Call `_git__source_register` → register with package manager on Debian/Ubuntu (equivs dummy .deb)
9. Call `_git__source_cleanup` → remove build dir unless `no_clean=true`
10. Verify: `"${PREFIX}/bin/git" --version`

---

### `_git__source_resolve_version`

Resolves `$VERSION` to an exact version string (without `v` prefix, e.g. `"2.47.2"`).

```
if VERSION == "latest":
  # Fetch up to 100 tags; sort all (including RCs) by version, take highest
  _tags="$(github__tags git/git)"
  _tag="$(printf '%s\n' "$_tags"
    | sed 's/^v//'
    | grep -E '^[0-9]+\.[0-9]+'
    | sort -t. -k1,1n -k2,2n -k3,3n
    | tail -1)"
  _RESOLVED_VERSION="$_tag"   # already without v prefix

elif VERSION == "stable":
  # Fetch up to 100 tags; filter to stable-only (no -rc, -beta, etc.), sort, take highest
  _tags="$(github__tags git/git)"
  _tag="$(printf '%s\n' "$_tags"
    | sed 's/^v//'
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$'
    | sort -t. -k1,1n -k2,2n -k3,3n
    | tail -1)"
  _RESOLVED_VERSION="$_tag"

else:
  # Specific version string (e.g. "2.47.2" or "2.47.0-rc1") — use directly
  _RESOLVED_VERSION="$VERSION"
```

Validation: check that `_RESOLVED_VERSION` is non-empty. If the tags API returned no usable tags, exit 1 with a clear error message.

---

### `_git__source_fetch_verify`

Downloads the tarball and `sha256sums.asc` from kernel.org, then verifies the hash.

```bash
_TAR_URL="https://www.kernel.org/pub/software/scm/git/git-${_RESOLVED_VERSION}.tar.gz"
_SUM_URL="https://www.kernel.org/pub/software/scm/git/sha256sums.asc"
_TARFILE="${INSTALLER_DIR}/git-${_RESOLVED_VERSION}.tar.gz"
_SUMFILE="${INSTALLER_DIR}/sha256sums.asc"

mkdir -p "$INSTALLER_DIR"
net__fetch_url_file "$_TAR_URL" "$_TARFILE"
net__fetch_url_file "$_SUM_URL" "$_SUMFILE"

_expected="$(grep "git-${_RESOLVED_VERSION}.tar.gz" "$_SUMFILE" | awk '{print $1}')"
[ -z "$_expected" ] → fatal: version not found in sha256sums.asc
checksum__verify_sha256 "$_TARFILE" "$_expected"
```

---

### `_git__source_build`

Compiles and installs git. Appends Alpine-specific required flags, then user-requested `no_flags`.

```bash
_MAKE_FLAGS="prefix=${PREFIX} sysconfdir=${SYSCONFDIR} USE_LIBPCRE2=YesPlease"

# Alpine requires these flags unconditionally for a successful build.
if [ "$(os__platform)" = "alpine" ]; then
  _MAKE_FLAGS="${_MAKE_FLAGS} NO_GETTEXT=YesPlease NO_REGEX=YesPlease NO_SVN_TESTS=YesPlease NO_SYS_POLL_H=1"
fi

# Parse NO_FLAGS: space-separated list of component names → make flags.
# Normalise to upper-case; validate against the known set.
_user_flags="$(printf '%s' "${NO_FLAGS}" | tr '[:lower:]' '[:upper:]')"
for _flag in ${_user_flags}; do
  case "${_flag}" in
    PERL|PYTHON|TCLTK|GETTEXT)
      # Dedup: only append if not already present (e.g. GETTEXT on Alpine).
      case " ${_MAKE_FLAGS} " in
        *" NO_${_flag}="*) ;;
        *) _MAKE_FLAGS="${_MAKE_FLAGS} NO_${_flag}=YesPlease" ;;
      esac
      ;;
    '')
      ;; # skip empty tokens from leading/trailing separators
    *)
      log_warning "no_flags: unknown value '${_flag}' — ignored"
      ;;
  esac
done

_NCPUS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)"

cd "${INSTALLER_DIR}/git-${_RESOLVED_VERSION}"
# shellcheck disable=SC2086
make -s -j"$_NCPUS" ${_MAKE_FLAGS} ${MAKE_FLAGS} all
# shellcheck disable=SC2086
make -s ${_MAKE_FLAGS} ${MAKE_FLAGS} install
```

---

### `_git__source_cleanup`

Removes the build directory unless `NO_CLEAN=true`.

```bash
if [ "${NO_CLEAN}" != true ]; then
  rm -rf "${INSTALLER_DIR}"
fi
```

---

### `_git__source_register` (internal helper called by `_git__install_source`)

**Responsibility:** Registers the source-built git with the OS package manager, preventing future `apt install <pkg>` dependency resolution from pulling in a second, older git binary to `/usr/bin/git`.

**Scope:** Debian/Ubuntu only (where `equivs` exists). On all other platforms (Alpine, RHEL, macOS) this function is a no-op — those package managers either don't enforce runtime dependency resolution in the same way or don't have an equivalent tool.

**Strategy:** Build and install an `equivs` dummy package named `git` at the source-built version. The package manager records `git (<version>)` as satisfied; no binary is placed on disk by the dummy package. Source-built `/usr/local/bin/git` (or `$PREFIX/bin/git`) continues to be the active one in PATH.

**Steps:**
1. Check `os__id`: if not `ubuntu` or `debian`, return immediately.
2. Check whether `equivs` is already installed: `dpkg -s equivs 2>/dev/null | grep -q 'Status: install ok installed'`. Store result in `_had_equivs` (true/false). This is needed so we only remove it if **we** installed it.
3. If not already installed: `ospkg__install equivs`.
4. Create a temporary working directory under `$INSTALLER_DIR`.
5. Write an `equivs` control file:
   ```
   Section: misc
   Priority: optional
   Standards-Version: 3.9.2
   
   Package: git
   Version: <_RESOLVED_VERSION>-equivs
   Maintainer: install-git-feature
   Description: Dummy package — git built from source at /usr/local/bin
   ```
   The version string must be a valid Debian version. `${_RESOLVED_VERSION}-equivs` (e.g. `2.47.2-equivs`) is always valid.
6. Run `equivs-build ./git.control` inside the temp dir → produces `git_<version>-equivs_all.deb`.
7. `dpkg -i ./git_*.deb` — installs the dummy package.
8. If `_had_equivs` is false: `apt-get purge -y equivs && apt-get autoremove -y` — removes equivs and any deps it pulled in. If `_had_equivs` is true, leave equivs in place.

**Error handling:** If any step fails, log a warning (`⚠️`) and continue — failure to register with the package manager is non-fatal; PATH ordering still guarantees the correct binary is used. Do not `exit 1` here.

---

## Implementation Details

### `_git__write_system_gitconfig`

**Responsibility:** Writes system-level gitconfig settings (`default_branch`, `safe_directory`, `system_gitconfig`).

**Target file:**
- As root: `${SYSCONFDIR}/gitconfig` (typically `/etc/gitconfig`)
- As non-root: `${HOME}/.config/git/config` (XDG user config, read by git in addition to `~/.gitconfig`)

**Steps:**
1. Determine target file: `[ "$(id -u)" = "0" ] && _cfg="${SYSCONFDIR}/gitconfig" || _cfg="${HOME}/.config/git/config"`
2. `mkdir -p "$(dirname "${_cfg}")"` to ensure the parent directory exists.
3. If `DEFAULT_BRANCH` is non-empty: `git config --file "${_cfg}" init.defaultBranch "${DEFAULT_BRANCH}"`
4. If `SAFE_DIRECTORY` is non-empty: iterate newline-separated entries and call `git config --file "${_cfg}" --add safe.directory "${_entry}"` for each. Note: `safe.directory` is a multi-valued key — `--add` must be used to avoid replacing earlier entries.
5. If `SYSTEM_GITCONFIG` is non-empty: append the raw block to `"${_cfg}"` using `printf '%s\n' "${SYSTEM_GITCONFIG}" >> "${_cfg}"`.
6. If none of the above produced writes, return without touching the file.

**Note:** Using `git config --file` rather than `--system` or `--global` lets us target the correct file in both root and non-root cases with a single code path.

**Invocation:** Called from top-level dispatch only when at least one of `DEFAULT_BRANCH`, `SAFE_DIRECTORY`, `SYSTEM_GITCONFIG` is non-empty.

---

### `_git__write_user_gitconfig`

**Responsibility:** Writes per-user gitconfig settings (`user_name`, `user_email`, `user_gitconfig`) to `~/.gitconfig` for each user in `USERS`.

**Prerequisites:** Called only when `USERS` is non-empty **and** at least one of `USER_NAME`, `USER_EMAIL`, `USER_GITCONFIG` is non-empty.

**User resolution:**
- Parses `USERS` to set the `users__resolve_list` env vars:
  - Split `USERS` by comma; for each token:
    - `_REMOTE_USER` → `ADD_REMOTE_USER_CONFIG=true`
    - `_CONTAINER_USER` → `ADD_CONTAINER_USER_CONFIG=true`
    - `all` → `ADD_CURRENT_USER_CONFIG=true`, `ADD_REMOTE_USER_CONFIG=true`, `ADD_CONTAINER_USER_CONFIG=true`
    - anything else → append to `ADD_USER_CONFIG` (comma-separated)
  - Any env var not explicitly set → `false` (suppress implicit injection)
- Calls `users__resolve_list` (reads those env vars, returns one username per line).
- As non-root: filter the resolved list to `"$(id -un)"` only; warn and skip any other names.

**Per-user loop:**
```bash
_home="$(shell__resolve_home "${_user}")"
_cfg="${_home}/.gitconfig"
[ -n "${USER_NAME}" ]  && git config --file "${_cfg}" user.name  "${USER_NAME}"
[ -n "${USER_EMAIL}" ] && git config --file "${_cfg}" user.email "${USER_EMAIL}"
[ -n "${USER_GITCONFIG}" ] && printf '%s\n' "${USER_GITCONFIG}" >> "${_cfg}"
# Fix ownership if run as root writing to a non-root user's file
[ "$(id -u)" = "0" ] && chown "${_user}:${_user}" "${_cfg}" 2>/dev/null || true
```

**Error handling:** If `shell__resolve_home` fails for a user (no home directory), log a warning and skip that user — do not exit.

---

### Top-level Dispatch

The main script body, after argument parsing:

```bash
# 1. Resolve auto prefix/sysconfdir early — needed by _git__check_exists
#    (update path compares old prefix against PREFIX) and post-install steps.
if [ "${PREFIX}" = "auto" ]; then
  [ "$(id -u)" = "0" ] && PREFIX="/usr/local" || PREFIX="${HOME}/.local"
fi
if [ "${SYSCONFDIR}" = "auto" ]; then
  [ "$(id -u)" = "0" ] && SYSCONFDIR="/etc" || SYSCONFDIR="${HOME}/.config"
fi

# 2. Root check for method=package on Linux (package managers require root).
#    Homebrew on macOS works as any user — no root required.
if [ "${METHOD}" = "package" ] && [ "$(os__kernel)" != "Darwin" ]; then
  os__require_root
fi

# 3. if_exists gate (handles skip/fail/reinstall/update teardown).
_git__check_exists

# 4. Install.
case "$METHOD" in
  package) _git__install_package ;;
  source)  _git__install_source  ;;
  *) echo "⛔ Unknown method: '${METHOD}'" >&2; exit 1 ;;
esac

# Post-install: shell completions (source build only).
if [ "${METHOD}" = "source" ] && [ "${INSTALL_COMPLETIONS}" = "true" ]; then
  _comp_src="${PREFIX}/share/git-core/contrib/completion"
  if [ "$(id -u)" = "0" ]; then
    mkdir -p /etc/bash_completion.d
    cp "${_comp_src}/git-completion.bash" /etc/bash_completion.d/git
    _zshdir="$(shell__detect_zshdir)"
    mkdir -p "${_zshdir}/completions"
    cp "${_comp_src}/git-completion.zsh" "${_zshdir}/completions/_git"
  else
    mkdir -p "${HOME}/.local/share/bash-completion/completions"
    cp "${_comp_src}/git-completion.bash" "${HOME}/.local/share/bash-completion/completions/git"
    mkdir -p "${HOME}/.zfunc"
    cp "${_comp_src}/git-completion.zsh" "${HOME}/.zfunc/_git"
  fi
fi

# Post-install: PATH/MANPATH export (source build only).
if [ "${METHOD}" = "source" ] && [ "${EXPORT_PATH}" != "" ]; then
  if [ "${EXPORT_PATH:-auto}" = "auto" ]; then
    if [ "$(id -u)" = "0" ]; then
      _path_files="$(shell__system_path_files --profile_d install-git.sh)"
    else
      # shellcheck disable=SC2119
      _path_files="$(shell__user_path_files)"
    fi
  else
    _path_files="${EXPORT_PATH}"
  fi
  shell__sync_block \
    --files "${_path_files}" \
    --marker "git PATH (install-git)" \
    --content "export PATH=\"${PREFIX}/bin:\${PATH}\""
  # Write MANPATH only for non-standard prefixes.
  if [ "${PREFIX}" != "/usr/local" ] && [ "${PREFIX}" != "${HOME}/.local" ]; then
    shell__sync_block \
      --files "${_path_files}" \
      --marker "git MANPATH (install-git)" \
      --content "export MANPATH=\"${PREFIX}/share/man:\${MANPATH}\""
  fi
fi

# Post-install: gitconfig.
if [ -n "${DEFAULT_BRANCH}${SAFE_DIRECTORY}${SYSTEM_GITCONFIG}" ]; then
  _git__write_system_gitconfig
fi
if [ -n "${USERS}" ] && [ -n "${USER_NAME}${USER_EMAIL}${USER_GITCONFIG}" ]; then
  _git__write_user_gitconfig
fi

# Post-install: symlink /usr/local/bin/git -> ${PREFIX}/bin/git (source + root + non-default prefix only).
if [ "${METHOD}" = "source" ] && [ "${SYMLINK}" = "true" ] \
  && [ "$(id -u)" = "0" ] && [ "${PREFIX}" != "/usr/local" ]; then
  ln -sf "${PREFIX}/bin/git" /usr/local/bin/git
fi
```

No intermediate resolution function is needed — `$METHOD` is always explicitly `"package"` or `"source"`. The PATH/MANPATH export is inlined directly rather than wrapped in a function, as it is two `shell__sync_block` calls with no branching complexity beyond the prefix check. The gitconfig writes are delegated to the two dedicated functions above. The symlink step is a single `ln -sf` guarded by four conditions and needs no dedicated function.

### macOS Source Builds

`method=source` is always explicit with this API (no auto-selection), so there are no surprises on macOS. `method=package` on macOS delegates to Homebrew. For source builds:
- `_git__install_source` checks for Xcode CLT via `xcode-select --print-path` and exits with a clear error if absent.
- `ospkg__run --manifest dependencies/source-build.yaml` installs the `brew:` packages (`make`, `openssl`, `pcre2`, `gettext`).

### Avoiding `software-properties-common`

The PPA installation uses direct `keyserver.ubuntu.com` HTTPS fetch and manual `sources.list.d` file creation — no `apt-add-repository` and no Python dependency. See `_git__install_package` and `_git__ppa_import_key` above.

### Alpine Make Flags

All Alpine-specific flags (`NO_GETTEXT`, `NO_REGEX`, `NO_SVN_TESTS`, `NO_SYS_POLL_H`) are conditionally added only when `os__platform` returns `"alpine"`. No flags are added on other platforms. Source: [alpine/aports APKBUILD prepare()](https://gitlab.alpinelinux.org/alpine/aports/-/blob/master/main/git/APKBUILD).

### Version Tag Sorting

- For `version=latest`: all tags (RCs included) are fetched, the `v` prefix is stripped, and the list is sorted numerically by three components (`sort -t. -k1,1n -k2,2n -k3,3n`). The highest is selected.
- For `version=stable`: same fetch, but filtered to `^[0-9]+\.[0-9]+\.[0-9]+$` (after stripping `v`) before sorting, which excludes all pre-release suffixes.
- For specific version strings: no API call; the `v` prefix is NOT expected in the user-supplied string (`2.47.2`, not `v2.47.2`).

### Idempotency

`_git__check_exists` runs before any installation and applies the following version short-circuit logic:

- **`method=source`** or **`method=package` with a specific version string**: the installed version (parsed from `git --version` by stripping the `"git version "` prefix) is compared against the resolved target. If they match, the script always exits 0 silently regardless of `if_exists`.
- **`method=package` with `version=latest` or `version=stable`**: no version comparison is performed; the `if_exists` policy is applied directly. Package managers are inherently idempotent — re-running an install for an already-current package is always a no-op at the PM level.

When the version short-circuit does not apply (or versions differ), the `if_exists` policy determines the outcome: `skip` (default) exits 0 with a notice; `fail` exits non-zero; `reinstall` detects and removes the existing installation before proceeding; `update` re-runs the installer in place.

### `base.yaml` Migration

The existing `dependencies/base.yaml` is replaced by `dependencies/os-pkg.yaml` and `dependencies/source-build.yaml`. The old file is removed. The new `scripts/install.sh` references the appropriate manifest for each method.

---

## References

- [Installation Reference](./installation.md) — all method details, build flags, PPA key steps, codename matrix
- [API Reference](./api.md) — option semantics, auto-selection table, usage examples
- [lib/github.sh](../../../lib/github.sh) — existing GitHub API helpers; `github__tags` added here
- [lib/checksum.sh](../../../lib/checksum.sh) — `checksum__verify_sha256` and `checksum__verify_sha256_sidecar`
- [lib/os.sh](../../../lib/os.sh) — `os__id`, `os__platform`, `os__kernel`
- [alpine/aports APKBUILD](https://gitlab.alpinelinux.org/alpine/aports/-/blob/master/main/git/APKBUILD) — Alpine-specific make flags
- [kernel.org git directory](https://www.kernel.org/pub/software/scm/git/) — tarball + sha256sums.asc
- [GitHub Tags API](https://docs.github.com/en/rest/repos/repos#list-repository-tags) — endpoint format, per_page parameter
- [devcontainers/features git install.sh](https://github.com/devcontainers/features/blob/main/src/git/install.sh) — PPA key import with multi-keyserver fallback
