#!/usr/bin/env bash
set -euo pipefail

_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
_BASE_DIR="$(cd "$_SELF_DIR/.." && pwd)"

# shellcheck source=lib/ospkg.sh
. "$_SELF_DIR/_lib/ospkg.sh"
# shellcheck source=lib/logging.sh
. "$_SELF_DIR/_lib/logging.sh"
# shellcheck source=lib/github.sh
. "$_SELF_DIR/_lib/github.sh"
# shellcheck source=lib/checksum.sh
. "$_SELF_DIR/_lib/checksum.sh"
# shellcheck source=lib/users.sh
. "$_SELF_DIR/_lib/users.sh"
# shellcheck source=lib/shell.sh
. "$_SELF_DIR/_lib/shell.sh"
logging__setup
echo "↪️ Script entry: Git Installation Devcontainer Feature Installer" >&2
trap 'logging__cleanup' EXIT

# ── Argument parsing ─────────────────────────────────────────────────────────

if [ "$#" -gt 0 ]; then
  echo "ℹ️ Script called with arguments: $*" >&2
  DEBUG=""
  DEFAULT_BRANCH=""
  EXPORT_PATH="auto"
  IF_EXISTS=""
  INSTALL_COMPLETIONS=""
  INSTALLER_DIR=""
  LOGFILE=""
  MAKE_FLAGS=""
  METHOD=""
  NO_CLEAN=""
  NO_FLAGS=""
  PREFIX=""
  SAFE_DIRECTORY=""
  SYMLINK=""
  SYSCONFDIR=""
  SYSTEM_GITCONFIG=""
  USER_EMAIL=""
  USER_GITCONFIG=""
  USER_NAME=""
  USERS=""
  VERSION=""
  while [ "$#" -gt 0 ]; do
    case $1 in
      --debug)
        shift
        DEBUG="$1"
        echo "📩 Read argument 'debug': '${DEBUG}'" >&2
        shift
        ;;
      --default_branch)
        shift
        DEFAULT_BRANCH="$1"
        echo "📩 Read argument 'default_branch': '${DEFAULT_BRANCH}'" >&2
        shift
        ;;
      --export_path)
        shift
        EXPORT_PATH="$1"
        echo "📩 Read argument 'export_path': '${EXPORT_PATH}'" >&2
        shift
        ;;
      --if_exists)
        shift
        IF_EXISTS="$1"
        echo "📩 Read argument 'if_exists': '${IF_EXISTS}'" >&2
        shift
        ;;
      --install_completions)
        shift
        INSTALL_COMPLETIONS="$1"
        echo "📩 Read argument 'install_completions': '${INSTALL_COMPLETIONS}'" >&2
        shift
        ;;
      --installer_dir)
        shift
        INSTALLER_DIR="$1"
        echo "📩 Read argument 'installer_dir': '${INSTALLER_DIR}'" >&2
        shift
        ;;
      --logfile)
        shift
        LOGFILE="$1"
        echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
        shift
        ;;
      --make_flags)
        shift
        MAKE_FLAGS="$1"
        echo "📩 Read argument 'make_flags': '${MAKE_FLAGS}'" >&2
        shift
        ;;
      --method)
        shift
        METHOD="$1"
        echo "📩 Read argument 'method': '${METHOD}'" >&2
        shift
        ;;
      --no_clean)
        shift
        NO_CLEAN="$1"
        echo "📩 Read argument 'no_clean': '${NO_CLEAN}'" >&2
        shift
        ;;
      --no_flags)
        shift
        NO_FLAGS="$1"
        echo "📩 Read argument 'no_flags': '${NO_FLAGS}'" >&2
        shift
        ;;
      --prefix)
        shift
        PREFIX="$1"
        echo "📩 Read argument 'prefix': '${PREFIX}'" >&2
        shift
        ;;
      --safe_directory)
        shift
        SAFE_DIRECTORY="$1"
        echo "📩 Read argument 'safe_directory': '${SAFE_DIRECTORY}'" >&2
        shift
        ;;
      --symlink)
        shift
        SYMLINK="$1"
        echo "📩 Read argument 'symlink': '${SYMLINK}'" >&2
        shift
        ;;
      --sysconfdir)
        shift
        SYSCONFDIR="$1"
        echo "📩 Read argument 'sysconfdir': '${SYSCONFDIR}'" >&2
        shift
        ;;
      --system_gitconfig)
        shift
        SYSTEM_GITCONFIG="$1"
        echo "📩 Read argument 'system_gitconfig': '${SYSTEM_GITCONFIG}'" >&2
        shift
        ;;
      --user_email)
        shift
        USER_EMAIL="$1"
        echo "📩 Read argument 'user_email': '${USER_EMAIL}'" >&2
        shift
        ;;
      --user_gitconfig)
        shift
        USER_GITCONFIG="$1"
        echo "📩 Read argument 'user_gitconfig': '${USER_GITCONFIG}'" >&2
        shift
        ;;
      --user_name)
        shift
        USER_NAME="$1"
        echo "📩 Read argument 'user_name': '${USER_NAME}'" >&2
        shift
        ;;
      --users)
        shift
        USERS="$1"
        echo "📩 Read argument 'users': '${USERS}'" >&2
        shift
        ;;
      --version)
        shift
        VERSION="$1"
        echo "📩 Read argument 'version': '${VERSION}'" >&2
        shift
        ;;
      --*)
        echo "⛔ Unknown option: '${1}'" >&2
        exit 1
        ;;
      *)
        echo "⛔ Unexpected argument: '${1}'" >&2
        exit 1
        ;;
    esac
  done
else
  echo "ℹ️ Script called with no arguments. Read environment variables." >&2
  [ "${DEBUG+defined}" ] && echo "📩 Read argument 'debug': '${DEBUG}'" >&2
  [ "${DEFAULT_BRANCH+defined}" ] && echo "📩 Read argument 'default_branch': '${DEFAULT_BRANCH}'" >&2
  [ "${EXPORT_PATH+defined}" ] && echo "📩 Read argument 'export_path': '${EXPORT_PATH}'" >&2
  [ "${IF_EXISTS+defined}" ] && echo "📩 Read argument 'if_exists': '${IF_EXISTS}'" >&2
  [ "${INSTALL_COMPLETIONS+defined}" ] && echo "📩 Read argument 'install_completions': '${INSTALL_COMPLETIONS}'" >&2
  [ "${INSTALLER_DIR+defined}" ] && echo "📩 Read argument 'installer_dir': '${INSTALLER_DIR}'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
  [ "${MAKE_FLAGS+defined}" ] && echo "📩 Read argument 'make_flags': '${MAKE_FLAGS}'" >&2
  [ "${METHOD+defined}" ] && echo "📩 Read argument 'method': '${METHOD}'" >&2
  [ "${NO_CLEAN+defined}" ] && echo "📩 Read argument 'no_clean': '${NO_CLEAN}'" >&2
  [ "${NO_FLAGS+defined}" ] && echo "📩 Read argument 'no_flags': '${NO_FLAGS}'" >&2
  [ "${PREFIX+defined}" ] && echo "📩 Read argument 'prefix': '${PREFIX}'" >&2
  [ "${SAFE_DIRECTORY+defined}" ] && echo "📩 Read argument 'safe_directory': '${SAFE_DIRECTORY}'" >&2
  [ "${SYMLINK+defined}" ] && echo "📩 Read argument 'symlink': '${SYMLINK}'" >&2
  [ "${SYSCONFDIR+defined}" ] && echo "📩 Read argument 'sysconfdir': '${SYSCONFDIR}'" >&2
  [ "${SYSTEM_GITCONFIG+defined}" ] && echo "📩 Read argument 'system_gitconfig': '${SYSTEM_GITCONFIG}'" >&2
  [ "${USER_EMAIL+defined}" ] && echo "📩 Read argument 'user_email': '${USER_EMAIL}'" >&2
  [ "${USER_GITCONFIG+defined}" ] && echo "📩 Read argument 'user_gitconfig': '${USER_GITCONFIG}'" >&2
  [ "${USER_NAME+defined}" ] && echo "📩 Read argument 'user_name': '${USER_NAME}'" >&2
  [ "${USERS+defined}" ] && echo "📩 Read argument 'users': '${USERS}'" >&2
  [ "${VERSION+defined}" ] && echo "📩 Read argument 'version': '${VERSION}'" >&2
fi

[[ "${DEBUG:-}" == true ]] && set -x

# Apply defaults.
[ -z "${DEBUG-}" ] && DEBUG=false
[ -z "${DEFAULT_BRANCH-}" ] && DEFAULT_BRANCH="main"
[ "${EXPORT_PATH+defined}" ] || EXPORT_PATH="auto"
[ -z "${IF_EXISTS-}" ] && IF_EXISTS="skip"
[ -z "${INSTALL_COMPLETIONS-}" ] && INSTALL_COMPLETIONS=true
[ -z "${INSTALLER_DIR-}" ] && INSTALLER_DIR="/tmp/git-build"
[ -z "${LOGFILE-}" ] && LOGFILE=""
[ -z "${MAKE_FLAGS-}" ] && MAKE_FLAGS=""
[ -z "${METHOD-}" ] && METHOD="package"
[ -z "${NO_CLEAN-}" ] && NO_CLEAN=false
[ -z "${NO_FLAGS-}" ] && NO_FLAGS=""
[ -z "${PREFIX-}" ] && PREFIX="auto"
[ -z "${SAFE_DIRECTORY-}" ] && SAFE_DIRECTORY=""
[ -z "${SYMLINK-}" ] && SYMLINK=true
[ -z "${SYSCONFDIR-}" ] && SYSCONFDIR="auto"
[ -z "${SYSTEM_GITCONFIG-}" ] && SYSTEM_GITCONFIG=""
[ -z "${USER_EMAIL-}" ] && USER_EMAIL=""
[ -z "${USER_GITCONFIG-}" ] && USER_GITCONFIG=""
[ -z "${USER_NAME-}" ] && USER_NAME=""
[ -z "${USERS-}" ] && USERS=""
[ -z "${VERSION-}" ] && VERSION="latest"

# Validate enum options early (fail fast before any install steps).
case "${METHOD}" in
  package | source) ;;
  *)
    echo "⛔ Unknown method: '${METHOD}' (expected: package, source)" >&2
    exit 1
    ;;
esac
case "${IF_EXISTS}" in
  skip | fail | reinstall | update) ;;
  *)
    echo "⛔ Unknown if_exists value: '${IF_EXISTS}' (expected: skip, fail, reinstall, update)" >&2
    exit 1
    ;;
esac

# ── Helper functions ──────────────────────────────────────────────────────────

# _git__check_exists
# Checks whether git is already in PATH and applies the $IF_EXISTS policy.
# Exits 0 (skip) or 1 (fail) when appropriate; returns normally to continue.
# Contract: if the installed version exactly matches the resolved target, we
# always exit 0 regardless of if_exists.
_git__check_exists() {
  command -v git > /dev/null 2>&1 || return 0

  local _installed_ver
  _installed_ver="$(git --version 2> /dev/null | sed 's/^git version //')"

  # Same-version idempotency: always skip when installed == target, regardless
  # of if_exists.  For source, resolve best-effort (|| true) so an offline
  # container with git already present does not abort during skip/fail.
  local _resolved_ver=""
  if [ "${METHOD}" = "source" ]; then
    _resolved_ver="$(_git__source_resolve_version)" || true
  elif [ "${METHOD}" = "package" ] &&
    [ "${VERSION}" != "latest" ] && [ "${VERSION}" != "stable" ]; then
    _resolved_ver="${VERSION}"
  fi
  if [ -n "${_resolved_ver}" ] && [ "${_installed_ver}" = "${_resolved_ver}" ]; then
    echo "ℹ️ git ${_resolved_ver} is already installed — skipping." >&2
    exit 0
  fi

  # Apply if_exists policy.
  case "${IF_EXISTS}" in
    skip)
      echo "ℹ️ git is already installed (${_installed_ver}) — skipping (if_exists=skip)." >&2
      exit 0
      ;;
    fail)
      echo "⛔ git is already installed (${_installed_ver}) and if_exists=fail." >&2
      exit 1
      ;;
    reinstall)
      local _existing_method _old_prefix
      _existing_method="$(_git__detect_install_method)"
      if [ "${_existing_method}" = "source" ]; then
        _old_prefix="$(dirname "$(dirname "$(command -v git)")")"
        _git__reinstall "source" "${_old_prefix}"
      else
        _git__reinstall "${_existing_method}"
      fi
      ;;
    update)
      local _existing_method
      _existing_method="$(_git__detect_install_method)"
      if [ "${_existing_method}" != "${METHOD}" ]; then
        _git__reinstall "${_existing_method}"
      elif [ "${METHOD}" = "source" ]; then
        local _old_prefix
        _old_prefix="$(dirname "$(dirname "$(command -v git)")")"
        if [ "${_old_prefix}" != "${PREFIX}" ]; then
          _git__reinstall "source" "${_old_prefix}"
        fi
        # Same prefix: make install overwrites in place — no teardown needed.
      fi
      # package→package: package manager handles upgrade natively.
      ;;
    *)
      echo "⛔ Unknown if_exists value: '${IF_EXISTS}'" >&2
      exit 1
      ;;
  esac
  return 0
}

# _git__detect_install_method
# Detects whether the currently installed git was installed by the OS package
# manager or built from source. Prints "package" or "source" to stdout.
_git__detect_install_method() {
  local _git_bin
  _git_bin="$(command -v git)"
  case "$(os__platform)" in
    debian)
      dpkg -S "${_git_bin}" > /dev/null 2>&1 && echo "package" && return 0
      ;;
    alpine)
      apk info --who-owns "${_git_bin}" 2> /dev/null | grep -q 'owned by' &&
        echo "package" && return 0
      ;;
    rhel)
      rpm -qf "${_git_bin}" > /dev/null 2>&1 && echo "package" && return 0
      ;;
    macos)
      brew list git > /dev/null 2>&1 && echo "package" && return 0
      ;;
  esac
  echo "source"
  return 0
}

# _git__reinstall
# Removes the existing git installation to prepare for a clean reinstall.
# $1 = existing_method ("package" or "source")
# $2 = prefix_to_remove (optional; defaults to $PREFIX)
_git__reinstall() {
  local _existing_method="$1"
  local _remove_prefix="${2:-${PREFIX}}"

  if [ "${_existing_method}" = "package" ]; then
    echo "🗑 Removing package-managed git..." >&2
    case "$(os__platform)" in
      debian) apt-get remove -y git ;;
      alpine) apk del git ;;
      rhel) dnf remove -y git 2> /dev/null || yum remove -y git ;;
      macos) brew remove git ;;
    esac
  else
    echo "🗑 Removing source-installed git from ${_remove_prefix}..." >&2
    rm -f "${_remove_prefix}/bin/git" "${_remove_prefix}/bin/git-"*
    rm -rf "${_remove_prefix}/lib/git-core/"
    rm -rf "${_remove_prefix}/share/git-core/"
    rm -f "${_remove_prefix}/share/man/man1/git"* \
      "${_remove_prefix}/share/man/man5/git"* \
      "${_remove_prefix}/share/man/man7/git"*
    # Remove equivs dummy package on Debian/Ubuntu if registered.
    case "$(os__platform)" in
      debian)
        if dpkg -s git 2> /dev/null | grep -q 'Status: install ok installed'; then
          apt-get purge -y git || true
        fi
        ;;
    esac
  fi
  return 0
}

# _git__ppa_check_codename
# Returns 0 if the PPA should be attempted; 1 if the codename is EOL/unsupported.
_git__ppa_check_codename() {
  local _codename
  _codename="$(os__codename)"
  case "${_codename}" in
    bionic | eoan | groovy | hirsute | impish | kinetic | lunar | mantic)
      echo "⚠️ Ubuntu ${_codename} is EOL and not supported by ppa:git-core/ppa — falling back to standard apt." >&2
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

# _git__ppa_import_key
# Imports the git-core PPA GPG key to /usr/share/keyrings/git-core-ppa.gpg.
_git__ppa_setup() {
  # Refreshes package lists, then sets up the git-core PPA (signing key +
  # sources.list entry + apt-get update).
  #
  # Primary: add-apt-repository -y ppa:git-core/ppa — the standard method.
  # It downloads the key directly from Launchpad over HTTPS (no keyserver
  # dependency) and runs apt-get update automatically.
  #
  # Fallback: manual GPG import + sources.list, used only when
  # add-apt-repository cannot be installed.
  echo "🔑 Setting up git-core PPA..." >&2

  # Ensure package lists are fresh before installing any prerequisite.
  ospkg__update

  if ! command -v add-apt-repository > /dev/null 2>&1; then
    ospkg__install software-properties-common
  fi
  if command -v add-apt-repository > /dev/null 2>&1 &&
    add-apt-repository -y ppa:git-core/ppa; then
    # add-apt-repository already ran apt-get update — no extra update needed.
    return 0
  fi

  # Last-resort fallback: manual GPG key import + sources.list entry.
  echo "⚠️  add-apt-repository failed or unavailable — using manual key import." >&2
  ospkg__install gpg || ospkg__install gnupg || {
    echo "⛔ Cannot install gpg/gnupg for PPA key import." >&2
    return 1
  }
  _git__ppa_import_key
  local _codename
  _codename="$(os__codename)"
  printf 'deb [signed-by=/usr/share/keyrings/git-core-ppa.gpg] https://ppa.launchpadcontent.net/git-core/ppa/ubuntu %s main\n' \
    "${_codename}" > /etc/apt/sources.list.d/git-core-ppa.list
  apt-get update -y
  return 0
}

_git__ppa_import_key() {
  local _fingerprint="F911AB184317630C59970973E363C90F8F1B6217"
  local _keyring="/usr/share/keyrings/git-core-ppa.gpg"
  mkdir -p "$(dirname "${_keyring}")"

  echo "🔑 Importing git-core PPA GPG key..." >&2
  if net__fetch_url_stdout \
    "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${_fingerprint}" |
    gpg --dearmor -o "${_keyring}" 2> /dev/null; then
    echo "✅ GPG key imported via HTTPS keyserver." >&2
    return 0
  fi

  # Fallback: gpg --recv-keys with multiple keyservers.
  local _ks
  for _ks in \
    "hkp://keyserver.ubuntu.com" \
    "hkp://keyserver.pgp.com" \
    "hkps://keys.openpgp.org"; do
    echo "ℹ️ Trying keyserver ${_ks}..." >&2
    if gpg --recv-keys --keyserver "${_ks}" "${_fingerprint}" 2> /dev/null; then
      gpg --export --armor "${_fingerprint}" | gpg --dearmor -o "${_keyring}" && return 0
    fi
  done

  echo "⛔ Failed to import git-core PPA GPG key from all keyservers." >&2
  return 1
}

# _git__install_package
# Installs git via the OS package manager.
_git__install_package() {
  if [ "${VERSION}" = "latest" ] && [ "$(os__id)" = "ubuntu" ]; then
    if _git__ppa_check_codename; then
      _git__ppa_setup
      ospkg__install git
      apt-get clean
      apt-get dist-clean 2> /dev/null || rm -rf /var/lib/apt/lists/*
      return 0
    fi
    # PPA codename unsupported — fall through to standard repo.
  fi

  if [ "${VERSION}" != "latest" ] && [ "${VERSION}" != "stable" ]; then
    # Specific version: pass directly to ospkg.
    # shellcheck disable=SC2059
    ospkg__run --manifest "$(printf 'packages:\n  - name: git\n    version: "%s"\n' "${VERSION}")"
  else
    ospkg__run --manifest "${_BASE_DIR}/dependencies/os-pkg.yaml"
  fi
  return 0
}

# _git__source_resolve_version
# Resolves $VERSION to an exact version string (no "v" prefix, e.g. "2.47.2").
# Prints the resolved version to stdout.
_git__source_resolve_version() {
  local _tags _tag
  if [ "${VERSION}" = "latest" ]; then
    _tags="$(github__tags "git/git")" || {
      echo "⛔ Failed to fetch git tags from GitHub." >&2
      return 1
    }
    _tag="$(printf '%s\n' "${_tags}" |
      sed 's/^v//' |
      grep -E '^[0-9]+\.[0-9]+' |
      sort -t. -k1,1n -k2,2n -k3,3n |
      tail -1)"
  elif [ "${VERSION}" = "stable" ]; then
    _tags="$(github__tags "git/git")" || {
      echo "⛔ Failed to fetch git tags from GitHub." >&2
      return 1
    }
    _tag="$(printf '%s\n' "${_tags}" |
      sed 's/^v//' |
      grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' |
      sort -t. -k1,1n -k2,2n -k3,3n |
      tail -1)"
  else
    _tag="${VERSION}"
  fi

  if [ -z "${_tag}" ]; then
    echo "⛔ Could not resolve a git version from tags." >&2
    return 1
  fi
  echo "${_tag}"
  return 0
}

# _git__source_fetch_verify
# Downloads the tarball and sha256sums.asc, verifies the checksum.
# $1 = resolved version string (e.g. "2.47.2")
_git__source_fetch_verify() {
  local _ver="$1"
  local _tar_url="https://www.kernel.org/pub/software/scm/git/git-${_ver}.tar.gz"
  local _sum_url="https://www.kernel.org/pub/software/scm/git/sha256sums.asc"
  local _tarfile="${INSTALLER_DIR}/git-${_ver}.tar.gz"
  local _sumfile="${INSTALLER_DIR}/sha256sums.asc"

  mkdir -p "${INSTALLER_DIR}"
  echo "📥 Downloading git-${_ver}.tar.gz..." >&2
  net__fetch_url_file "${_tar_url}" "${_tarfile}"
  net__fetch_url_file "${_sum_url}" "${_sumfile}"

  local _expected
  _expected="$(grep "git-${_ver}.tar.gz" "${_sumfile}" | awk '{print $1}')"
  if [ -z "${_expected}" ]; then
    echo "⛔ No checksum found for git-${_ver}.tar.gz in sha256sums.asc." >&2
    return 1
  fi
  checksum__verify_sha256 "${_tarfile}" "${_expected}"
  return 0
}

# _git__source_build
# Compiles and installs git from source.
# $1 = resolved version string
_git__source_build() {
  local _ver="$1"
  local _make_flags="prefix=${PREFIX} sysconfdir=${SYSCONFDIR} USE_LIBPCRE2=YesPlease"

  # Alpine requires these extra flags.
  if [ "$(os__platform)" = "alpine" ]; then
    _make_flags="${_make_flags} NO_GETTEXT=YesPlease NO_REGEX=YesPlease NO_SVN_TESTS=YesPlease NO_SYS_POLL_H=1"
  fi

  # Parse NO_FLAGS: space/comma-separated keywords → NO_<FLAG>=YesPlease.
  local _user_flags
  _user_flags="$(printf '%s' "${NO_FLAGS}" | tr '[:lower:],' '[:upper:] ')"
  local _flag
  for _flag in ${_user_flags}; do
    case "${_flag}" in
      PERL | PYTHON | TCLTK | GETTEXT)
        case " ${_make_flags} " in
          *" NO_${_flag}="*) ;;
          *) _make_flags="${_make_flags} NO_${_flag}=YesPlease" ;;
        esac
        ;;
      '') ;;
      *)
        echo "⚠️ no_flags: unknown keyword '${_flag}' — ignored" >&2
        ;;
    esac
  done

  local _ncpus
  _ncpus="$(nproc 2> /dev/null || sysctl -n hw.ncpu 2> /dev/null || echo 1)"

  cd "${INSTALLER_DIR}/git-${_ver}"
  # shellcheck disable=SC2086
  make -s -j"${_ncpus}" ${_make_flags} ${MAKE_FLAGS} all
  # shellcheck disable=SC2086
  make -s ${_make_flags} ${MAKE_FLAGS} install
  cd /
  return 0
}

# _git__source_cleanup
# Removes the build directory unless NO_CLEAN=true.
_git__source_cleanup() {
  if [ "${NO_CLEAN}" != "true" ]; then
    rm -rf "${INSTALLER_DIR}"
  fi
  return 0
}

# _git__source_register
# Registers the source-built git with apt on Debian/Ubuntu via an equivs dummy
# package so dependency resolution sees git as satisfied.  Non-fatal.
# $1 = resolved version string
_git__source_register() {
  local _ver="$1"
  case "$(os__platform)" in
    debian) ;;
    *) return 0 ;;
  esac

  local _had_equivs=false
  dpkg -s equivs 2> /dev/null | grep -q 'Status: install ok installed' && _had_equivs=true

  if [ "${_had_equivs}" = "false" ]; then
    ospkg__install equivs || {
      echo "⚠️ Could not install equivs — skipping package manager registration." >&2
      return 0
    }
  fi

  local _tmpdir
  _tmpdir="$(mktemp -d)"

  cat > "${_tmpdir}/git.control" << EOF
Section: misc
Priority: optional
Standards-Version: 3.9.2

Package: git
Version: ${_ver}-equivs
Maintainer: install-git-feature
Description: Dummy package — git built from source
EOF

  (
    cd "${_tmpdir}"
    equivs-build ./git.control
    dpkg -i ./git_*.deb
  ) || {
    echo "⚠️ equivs dummy package installation failed — skipping registration." >&2
    rm -rf "${_tmpdir}"
    if [ "${_had_equivs}" = "false" ]; then
      apt-get purge -y equivs > /dev/null 2>&1 || true
    fi
    return 0
  }

  rm -rf "${_tmpdir}"

  if [ "${_had_equivs}" = "false" ]; then
    apt-get purge -y equivs > /dev/null 2>&1 || true
    apt-get autoremove -y > /dev/null 2>&1 || true
  fi
  echo "✅ Registered git ${_ver} with apt via equivs dummy package." >&2
  return 0
}

# _git__install_source
# Main source-build orchestrator (10 steps).
_git__install_source() {
  # 1. Validate prefix writeability.
  mkdir -p "${PREFIX}" 2> /dev/null || true
  if [ ! -w "${PREFIX}" ]; then
    echo "⛔ PREFIX '${PREFIX}' is not writable." >&2
    return 1
  fi

  # 2. Resolve version.
  local _resolved_ver
  _resolved_ver="$(_git__source_resolve_version)"

  # 3. Check Xcode CLT on macOS.
  if [ "$(os__kernel)" = "Darwin" ]; then
    xcode-select --print-path > /dev/null 2>&1 || {
      echo "⛔ Xcode Command Line Tools are required for source builds on macOS." >&2
      echo "   Install with: xcode-select --install" >&2
      return 1
    }
  fi

  # 4. Install build dependencies.
  ospkg__run --manifest "${_BASE_DIR}/dependencies/source-build.yaml"

  # 5. Download and verify tarball.
  _git__source_fetch_verify "${_resolved_ver}"

  # 6. Extract.
  echo "📦 Extracting git-${_resolved_ver}.tar.gz..." >&2
  tar -xzf "${INSTALLER_DIR}/git-${_resolved_ver}.tar.gz" -C "${INSTALLER_DIR}"

  # 7. Build and install.
  echo "🔨 Building git ${_resolved_ver}..." >&2
  _git__source_build "${_resolved_ver}"

  # 8. Register with package manager (Debian/Ubuntu only, non-fatal).
  _git__source_register "${_resolved_ver}"

  # 9. Clean up build directory.
  _git__source_cleanup

  # 10. Verify.
  "${PREFIX}/bin/git" --version
  echo "✅ git ${_resolved_ver} installed to ${PREFIX}/bin/git." >&2
  return 0
}

# _git__write_system_gitconfig
# Writes system-level gitconfig settings (init.defaultBranch, safe.directory,
# and any raw ini lines from $SYSTEM_GITCONFIG).
_git__write_system_gitconfig() {
  local _cfg
  if [ "$(id -u)" = "0" ]; then
    _cfg="${SYSCONFDIR}/gitconfig"
  else
    _cfg="${HOME}/.config/git/config"
  fi
  mkdir -p "$(dirname "${_cfg}")"

  if [ -n "${DEFAULT_BRANCH}" ]; then
    git config --file "${_cfg}" init.defaultBranch "${DEFAULT_BRANCH}"
  fi

  if [ -n "${SAFE_DIRECTORY}" ]; then
    local _entry
    printf '%s\n' "${SAFE_DIRECTORY}" | while IFS= read -r _entry; do
      [ -z "${_entry}" ] && continue
      git config --file "${_cfg}" --add safe.directory "${_entry}"
    done
  fi

  if [ -n "${SYSTEM_GITCONFIG}" ]; then
    printf '%s\n' "${SYSTEM_GITCONFIG}" >> "${_cfg}"
  fi
  return 0
}

# _git__write_user_gitconfig
# Writes per-user gitconfig settings (user.name, user.email, raw ini lines)
# for each user resolved from $USERS.
_git__write_user_gitconfig() {
  # Translate $USERS token list into the env vars users__resolve_list reads.
  ADD_REMOTE_USER_CONFIG=false
  ADD_CONTAINER_USER_CONFIG=false
  ADD_CURRENT_USER_CONFIG=false
  ADD_USER_CONFIG=""
  local _token
  IFS=',' read -r -a _tokens <<< "${USERS}"
  for _token in "${_tokens[@]}"; do
    _token="$(printf '%s' "${_token}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    case "${_token}" in
      _REMOTE_USER) ADD_REMOTE_USER_CONFIG=true ;;
      _CONTAINER_USER) ADD_CONTAINER_USER_CONFIG=true ;;
      all)
        ADD_CURRENT_USER_CONFIG=true
        ADD_REMOTE_USER_CONFIG=true
        ADD_CONTAINER_USER_CONFIG=true
        ;;
      '') ;;
      *)
        if [ -n "${ADD_USER_CONFIG}" ]; then
          ADD_USER_CONFIG="${ADD_USER_CONFIG},${_token}"
        else
          ADD_USER_CONFIG="${_token}"
        fi
        ;;
    esac
  done
  export ADD_REMOTE_USER_CONFIG ADD_CONTAINER_USER_CONFIG ADD_CURRENT_USER_CONFIG ADD_USER_CONFIG

  local _current_user
  _current_user="$(id -un)"
  local _user _home _cfg

  while IFS= read -r _user; do
    [ -z "${_user}" ] && continue
    # Non-root: only write to the invoking user's config.
    if [ "$(id -u)" != "0" ] && [ "${_user}" != "${_current_user}" ]; then
      echo "⚠️ Non-root: skipping gitconfig for '${_user}' (can only write for '${_current_user}')." >&2
      continue
    fi

    _home="$(shell__resolve_home "${_user}")" || {
      echo "⚠️ Could not resolve home directory for '${_user}' — skipping." >&2
      continue
    }
    _cfg="${_home}/.gitconfig"

    [ -n "${USER_NAME}" ] && git config --file "${_cfg}" user.name "${USER_NAME}"
    [ -n "${USER_EMAIL}" ] && git config --file "${_cfg}" user.email "${USER_EMAIL}"
    [ -n "${USER_GITCONFIG}" ] && printf '%s\n' "${USER_GITCONFIG}" >> "${_cfg}"

    # Fix ownership when root writes to a non-root user's file.
    if [ "$(id -u)" = "0" ]; then
      chown "${_user}:${_user}" "${_cfg}" 2> /dev/null || true
    fi
    echo "✅ Wrote gitconfig for user '${_user}'." >&2
  done < <(users__resolve_list)
  return 0
}

# ── Top-level dispatch ────────────────────────────────────────────────────────

# 1. Resolve auto prefix/sysconfdir.
if [ "${PREFIX}" = "auto" ]; then
  [ "$(id -u)" = "0" ] && PREFIX="/usr/local" || PREFIX="${HOME}/.local"
fi
if [ "${SYSCONFDIR}" = "auto" ]; then
  [ "$(id -u)" = "0" ] && SYSCONFDIR="/etc" || SYSCONFDIR="${HOME}/.config"
fi

# 2. Root check for method=package on Linux.
if [ "${METHOD}" = "package" ] && [ "$(os__kernel)" != "Darwin" ]; then
  os__require_root
fi

# 3. if_exists gate.
_git__check_exists

# 4. Install.
case "${METHOD}" in
  package) _git__install_package ;;
  source) _git__install_source ;;
  *)
    echo "⛔ Unknown method: '${METHOD}'" >&2
    exit 1
    ;;
esac

# 5. Shell completions (source build only).
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
    cp "${_comp_src}/git-completion.bash" \
      "${HOME}/.local/share/bash-completion/completions/git"
    mkdir -p "${HOME}/.zfunc"
    cp "${_comp_src}/git-completion.zsh" "${HOME}/.zfunc/_git"
  fi
fi

# 6. PATH/MANPATH export (source build only).
if [ "${METHOD}" = "source" ] && [ -n "${EXPORT_PATH}" ]; then
  _path_files="${EXPORT_PATH}"
  if [ "${EXPORT_PATH}" = "auto" ]; then
    if [ "$(id -u)" = "0" ]; then
      _path_files="$(shell__system_path_files --profile_d install-git.sh)"
    else
      # shellcheck disable=SC2119
      _path_files="$(shell__user_path_files)"
    fi
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

# 7. Git configuration.
if [ -n "${DEFAULT_BRANCH}${SAFE_DIRECTORY}${SYSTEM_GITCONFIG}" ]; then
  _git__write_system_gitconfig
fi
if [ -n "${USERS}" ] && [ -n "${USER_NAME}${USER_EMAIL}${USER_GITCONFIG}" ]; then
  _git__write_user_gitconfig
fi

# 8. Symlink /usr/local/bin/git → ${PREFIX}/bin/git
#    (source + root + non-standard prefix only).
if [ "${METHOD}" = "source" ] && [ "${SYMLINK}" = "true" ] &&
  [ "$(id -u)" = "0" ] && [ "${PREFIX}" != "/usr/local" ]; then
  ln -sf "${PREFIX}/bin/git" /usr/local/bin/git
fi

echo "↩️ Script exit: Git Installation Devcontainer Feature Installer" >&2
