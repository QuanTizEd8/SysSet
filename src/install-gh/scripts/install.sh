#!/usr/bin/env bash
set -euo pipefail

_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
_BASE_DIR="$(cd "$_SELF_DIR/.." && pwd)"

# shellcheck source=lib/ospkg.sh
. "$_SELF_DIR/_lib/ospkg.sh"
# shellcheck source=lib/logging.sh
. "$_SELF_DIR/_lib/logging.sh"
logging__setup
echo "↪️ Script entry: GitHub CLI Installer" >&2
# Override _cleanup_hook in the hand-written section for feature-specific
# cleanup (e.g. removing temp files). Do NOT call logging__cleanup there;
# _on_exit owns that call and guarantees it runs exactly once, last.
# shellcheck disable=SC2329
_cleanup_hook() { return; }
# shellcheck disable=SC2329
_on_exit() {
  local _rc=$?
  _cleanup_hook
  if [[ $_rc -eq 0 ]]; then
    echo "✅ GitHub CLI Installer script finished successfully." >&2
  else
    echo "❌ GitHub CLI Installer script exited with error ${_rc}." >&2
  fi
  logging__cleanup
  return
}
trap '_on_exit' EXIT

__usage__() {
  cat << 'EOF'
Usage: install.sh [OPTIONS]

Options:
  --version <value>                          Version of gh to install. (default: "latest")
  --method {repos|binary}                    Installation strategy. (default: "repos")
  --prefix <value>                           Installation prefix when method=binary. The 'gh' binary is placed at '$prefix/bin/gh'. (default: "auto")
  --symlink {true,false}                     Create a symlink from the canonical bin directory to $prefix/bin/gh when prefix resolves to a non-default path (method=binary only). (default: "true")
  --shell_completions <value>  (repeatable)  Shell names to install completions for.
  --if_exists {skip|fail}                    What to do when 'gh' is already present in PATH before installation begins. (default: "skip")
  --extensions <value>  (repeatable)         GitHub CLI extensions to install after gh itself is installed.
  --add_current_user {true,false}            Apply per-user git configuration (git_protocol, setup_git, sign_commits) and install extensions for the current non-root user (SUDO_USER if run via sudo, otherwise the result of whoami). (default: "true")
  --add_remote_user {true,false}             Apply per-user git configuration (git_protocol, setup_git, sign_commits) and install extensions for the devcontainer remoteUser (the _REMOTE_USER environment variable set by the devcontainer tooling). (default: "true")
  --add_container_user {true,false}          Apply per-user git configuration (git_protocol, setup_git, sign_commits) and install extensions for the devcontainer containerUser (the _CONTAINER_USER environment variable set by the devcontainer tooling). (default: "true")
  --add_users <value>  (repeatable)          Additional usernames to apply per-user git configuration and install extensions for.
  --git_protocol <value>                     Set the default git protocol in gh's per-user config (~/.config/gh/config.yml) by running 'gh config set git_protocol <value>' for each resolved user.
  --setup_git {true,false}                   Register gh as the git credential helper by running 'gh auth setup-git --force --hostname <git_hostname>' for each resolved user. (default: "false")
  --sign_commits <value>                     Pre-configure commit signing in each resolved user's ~/.gitconfig.
  --git_hostname <value>                     The hostname to configure as the git credential helper target when setup_git=true. (default: "github.com")
  --installer_dir <value>                    Working directory used for method=binary: the binary archive and checksums file are downloaded and extracted here. (default: "/tmp/gh-install")
  --keep_installer {true,false}              Keep the installer_dir after a successful install when method=binary. (default: "false")
  --debug {true,false}                       Enable debug output (set -x). (default: "false")
  --logfile <value>                          Append install log to this file path.
  -h, --help                                 Show this help
EOF
  return
}

if [ "$#" -gt 0 ]; then
  echo "ℹ️ Script called with arguments: $*" >&2
  VERSION="latest"
  METHOD="repos"
  PREFIX="auto"
  SYMLINK=true
  SHELL_COMPLETIONS=()
  IF_EXISTS="skip"
  EXTENSIONS=()
  ADD_CURRENT_USER=true
  ADD_REMOTE_USER=true
  ADD_CONTAINER_USER=true
  ADD_USERS=()
  GIT_PROTOCOL=""
  SETUP_GIT=false
  SIGN_COMMITS=""
  GIT_HOSTNAME="github.com"
  INSTALLER_DIR="/tmp/gh-install"
  KEEP_INSTALLER=false
  DEBUG=false
  LOGFILE=""
  while [ "$#" -gt 0 ]; do
    case $1 in
      --version)
        shift
        VERSION="$1"
        echo "📩 Read argument 'version': '${VERSION}'" >&2
        shift
        ;;
      --method)
        shift
        METHOD="$1"
        echo "📩 Read argument 'method': '${METHOD}'" >&2
        shift
        ;;
      --prefix)
        shift
        PREFIX="$1"
        echo "📩 Read argument 'prefix': '${PREFIX}'" >&2
        shift
        ;;
      --symlink)
        shift
        SYMLINK="$1"
        echo "📩 Read argument 'symlink': '${SYMLINK}'" >&2
        shift
        ;;
      --shell_completions)
        shift
        SHELL_COMPLETIONS+=("$1")
        echo "📩 Read argument 'shell_completions': '$1'" >&2
        shift
        ;;
      --if_exists)
        shift
        IF_EXISTS="$1"
        echo "📩 Read argument 'if_exists': '${IF_EXISTS}'" >&2
        shift
        ;;
      --extensions)
        shift
        EXTENSIONS+=("$1")
        echo "📩 Read argument 'extensions': '$1'" >&2
        shift
        ;;
      --add_current_user)
        shift
        ADD_CURRENT_USER="$1"
        echo "📩 Read argument 'add_current_user': '${ADD_CURRENT_USER}'" >&2
        shift
        ;;
      --add_remote_user)
        shift
        ADD_REMOTE_USER="$1"
        echo "📩 Read argument 'add_remote_user': '${ADD_REMOTE_USER}'" >&2
        shift
        ;;
      --add_container_user)
        shift
        ADD_CONTAINER_USER="$1"
        echo "📩 Read argument 'add_container_user': '${ADD_CONTAINER_USER}'" >&2
        shift
        ;;
      --add_users)
        shift
        ADD_USERS+=("$1")
        echo "📩 Read argument 'add_users': '$1'" >&2
        shift
        ;;
      --git_protocol)
        shift
        GIT_PROTOCOL="$1"
        echo "📩 Read argument 'git_protocol': '${GIT_PROTOCOL}'" >&2
        shift
        ;;
      --setup_git)
        shift
        SETUP_GIT="$1"
        echo "📩 Read argument 'setup_git': '${SETUP_GIT}'" >&2
        shift
        ;;
      --sign_commits)
        shift
        SIGN_COMMITS="$1"
        echo "📩 Read argument 'sign_commits': '${SIGN_COMMITS}'" >&2
        shift
        ;;
      --git_hostname)
        shift
        GIT_HOSTNAME="$1"
        echo "📩 Read argument 'git_hostname': '${GIT_HOSTNAME}'" >&2
        shift
        ;;
      --installer_dir)
        shift
        INSTALLER_DIR="$1"
        echo "📩 Read argument 'installer_dir': '${INSTALLER_DIR}'" >&2
        shift
        ;;
      --keep_installer)
        shift
        KEEP_INSTALLER="$1"
        echo "📩 Read argument 'keep_installer': '${KEEP_INSTALLER}'" >&2
        shift
        ;;
      --debug)
        shift
        DEBUG="$1"
        echo "📩 Read argument 'debug': '${DEBUG}'" >&2
        shift
        ;;
      --logfile)
        shift
        LOGFILE="$1"
        echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
        shift
        ;;
      -h | --help)
        __usage__
        exit 0
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
  [ "${VERSION+defined}" ] && echo "📩 Read argument 'version': '${VERSION}'" >&2
  [ "${METHOD+defined}" ] && echo "📩 Read argument 'method': '${METHOD}'" >&2
  [ "${PREFIX+defined}" ] && echo "📩 Read argument 'prefix': '${PREFIX}'" >&2
  [ "${SYMLINK+defined}" ] && echo "📩 Read argument 'symlink': '${SYMLINK}'" >&2
  if [ "${SHELL_COMPLETIONS+defined}" ]; then
    if [ -n "${SHELL_COMPLETIONS-}" ]; then
      mapfile -t SHELL_COMPLETIONS < <(printf '%s\n' "${SHELL_COMPLETIONS}" | grep -v '^$')
      for _item in "${SHELL_COMPLETIONS[@]}"; do
        echo "📩 Read argument 'shell_completions': '$_item'" >&2
      done
    else
      SHELL_COMPLETIONS=()
    fi
  fi
  [ "${IF_EXISTS+defined}" ] && echo "📩 Read argument 'if_exists': '${IF_EXISTS}'" >&2
  if [ "${EXTENSIONS+defined}" ]; then
    if [ -n "${EXTENSIONS-}" ]; then
      mapfile -t EXTENSIONS < <(printf '%s\n' "${EXTENSIONS}" | grep -v '^$')
      for _item in "${EXTENSIONS[@]}"; do
        echo "📩 Read argument 'extensions': '$_item'" >&2
      done
    else
      EXTENSIONS=()
    fi
  fi
  [ "${ADD_CURRENT_USER+defined}" ] && echo "📩 Read argument 'add_current_user': '${ADD_CURRENT_USER}'" >&2
  [ "${ADD_REMOTE_USER+defined}" ] && echo "📩 Read argument 'add_remote_user': '${ADD_REMOTE_USER}'" >&2
  [ "${ADD_CONTAINER_USER+defined}" ] && echo "📩 Read argument 'add_container_user': '${ADD_CONTAINER_USER}'" >&2
  if [ "${ADD_USERS+defined}" ]; then
    if [ -n "${ADD_USERS-}" ]; then
      mapfile -t ADD_USERS < <(printf '%s\n' "${ADD_USERS}" | grep -v '^$')
      for _item in "${ADD_USERS[@]}"; do
        echo "📩 Read argument 'add_users': '$_item'" >&2
      done
    else
      ADD_USERS=()
    fi
  fi
  [ "${GIT_PROTOCOL+defined}" ] && echo "📩 Read argument 'git_protocol': '${GIT_PROTOCOL}'" >&2
  [ "${SETUP_GIT+defined}" ] && echo "📩 Read argument 'setup_git': '${SETUP_GIT}'" >&2
  [ "${SIGN_COMMITS+defined}" ] && echo "📩 Read argument 'sign_commits': '${SIGN_COMMITS}'" >&2
  [ "${GIT_HOSTNAME+defined}" ] && echo "📩 Read argument 'git_hostname': '${GIT_HOSTNAME}'" >&2
  [ "${INSTALLER_DIR+defined}" ] && echo "📩 Read argument 'installer_dir': '${INSTALLER_DIR}'" >&2
  [ "${KEEP_INSTALLER+defined}" ] && echo "📩 Read argument 'keep_installer': '${KEEP_INSTALLER}'" >&2
  [ "${DEBUG+defined}" ] && echo "📩 Read argument 'debug': '${DEBUG}'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
fi

[[ "${DEBUG:-}" == true ]] && set -x

# Apply defaults.
[ "${VERSION+defined}" ] || VERSION="latest"
[ "${METHOD+defined}" ] || METHOD="repos"
[ "${PREFIX+defined}" ] || PREFIX="auto"
[ "${SYMLINK+defined}" ] || SYMLINK=true
[ "${SHELL_COMPLETIONS+defined}" ] || mapfile -t SHELL_COMPLETIONS < <(printf '%s' $'bash\nzsh' | grep -v '^$')
[ "${IF_EXISTS+defined}" ] || IF_EXISTS="skip"
[ "${EXTENSIONS+defined}" ] || EXTENSIONS=()
[ "${ADD_CURRENT_USER+defined}" ] || ADD_CURRENT_USER=true
[ "${ADD_REMOTE_USER+defined}" ] || ADD_REMOTE_USER=true
[ "${ADD_CONTAINER_USER+defined}" ] || ADD_CONTAINER_USER=true
[ "${ADD_USERS+defined}" ] || ADD_USERS=()
[ "${GIT_PROTOCOL+defined}" ] || GIT_PROTOCOL=""
[ "${SETUP_GIT+defined}" ] || SETUP_GIT=false
[ "${SIGN_COMMITS+defined}" ] || SIGN_COMMITS=""
[ "${GIT_HOSTNAME+defined}" ] || GIT_HOSTNAME="github.com"
[ "${INSTALLER_DIR+defined}" ] || INSTALLER_DIR="/tmp/gh-install"
[ "${KEEP_INSTALLER+defined}" ] || KEEP_INSTALLER=false
[ "${DEBUG+defined}" ] || DEBUG=false
[ "${LOGFILE+defined}" ] || LOGFILE=""

# Validate enum options.
case "${METHOD}" in
  repos | binary) ;;
  *)
    echo "⛔ Invalid value for 'method': '${METHOD}' (expected: repos, binary)" >&2
    exit 1
    ;;
esac
case "${IF_EXISTS}" in
  skip | fail) ;;
  *)
    echo "⛔ Invalid value for 'if_exists': '${IF_EXISTS}' (expected: skip, fail)" >&2
    exit 1
    ;;
esac

ospkg__run --manifest "${_BASE_DIR}/dependencies/base.yaml" --skip_installed

# END OF AUTOGENERATED BLOCK

# _gh__resolve_version — prints the resolved semver (no "v" prefix) to stdout.
_gh__resolve_version() {
  echo "↪️ Function entry: _gh__resolve_version" >&2
  if [ "${VERSION}" = "latest" ]; then
    local _tag
    _tag="$(github__latest_tag "cli/cli")" || {
      echo "⛔ Failed to fetch latest gh tag from GitHub." >&2
      exit 1
    }
    local _ver="${_tag#v}"
    echo "ℹ️ Resolved 'latest' to version '${_ver}'" >&2
    echo "${_ver}"
  else
    echo "${VERSION#v}"
  fi
  echo "↩️ Function exit: _gh__resolve_version" >&2
  return 0
}

# _gh__check_existing — applies IF_EXISTS policy; exits or returns normally.
# $1 = resolved version string (e.g. "2.89.0")
_gh__check_existing() {
  echo "↪️ Function entry: _gh__check_existing" >&2
  command -v gh > /dev/null 2>&1 || {
    echo "↩️ Function exit: _gh__check_existing (gh not found)" >&2
    return 0
  }

  local _installed_ver
  _installed_ver="$(gh --version 2> /dev/null | head -1 | awk '{print $3}')" || _installed_ver=""

  # Same-version idempotency: always exit 0 regardless of if_exists.
  if [ -n "${_installed_ver}" ] && [ "${_installed_ver}" = "${1}" ]; then
    echo "ℹ️ gh ${1} is already installed — skipping (version match)." >&2
    exit 0
  fi

  case "${IF_EXISTS}" in
    skip)
      echo "ℹ️ gh is already installed (${_installed_ver}) — skipping (if_exists=skip)." >&2
      exit 0
      ;;
    fail)
      echo "⛔ gh is already installed (${_installed_ver}) and if_exists=fail." >&2
      exit 1
      ;;
  esac
  echo "↩️ Function exit: _gh__check_existing" >&2
  return 0
}

# _gh__install_repos — dispatch to the correct platform-specific repos installer.
_gh__install_repos() {
  echo "↪️ Function entry: _gh__install_repos" >&2
  local _id _id_like _platform
  _id="$(os__id)"
  _id_like="$(os__id_like)"
  _platform="$(os__platform)"

  # Arch Linux has ID=arch (and Manjaro has ID_LIKE containing arch).
  case "${_id}" in
    arch | manjaro)
      _gh__repos_arch
      echo "↩️ Function exit: _gh__install_repos" >&2
      return 0
      ;;
  esac
  case "${_id_like}" in
    *arch*)
      _gh__repos_arch
      echo "↩️ Function exit: _gh__install_repos" >&2
      return 0
      ;;
  esac

  case "${_platform}" in
    alpine)
      _gh__repos_alpine
      ;;
    debian)
      _gh__repos_debian
      ;;
    rhel)
      _gh__repos_rhel
      ;;
    macos)
      _gh__repos_macos
      ;;
    *)
      echo "⛔ Unsupported platform '${_platform}' for method=repos." >&2
      exit 1
      ;;
  esac
  echo "↩️ Function exit: _gh__install_repos" >&2
  return 0
}

# _gh__repos_debian — add GitHub CLI apt repo and install gh.
_gh__repos_debian() {
  echo "↪️ Function entry: _gh__repos_debian" >&2
  ospkg__update
  ospkg__install gnupg curl
  mkdir -p /etc/apt/keyrings
  net__fetch_url_file \
    "https://cli.github.com/packages/githubcli-archive-keyring.gpg" \
    "/etc/apt/keyrings/githubcli-archive-keyring.gpg"
  chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  local _arch
  _arch="$(dpkg --print-architecture)"
  cat > /etc/apt/sources.list.d/github-cli.list << EOF
deb [arch=${_arch} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main
EOF
  ospkg__update --force
  if [ "${VERSION}" = "latest" ]; then
    ospkg__install gh
  else
    ospkg__install "gh=${VERSION}"
  fi
  apt-get clean
  apt-get dist-clean 2> /dev/null || rm -rf /var/lib/apt/lists/*
  echo "↩️ Function exit: _gh__repos_debian" >&2
  return 0
}

# _gh__repos_rhel — add GitHub CLI rpm repo and install gh.
_gh__repos_rhel() {
  echo "↪️ Function entry: _gh__repos_rhel" >&2
  if [ "${VERSION}" != "latest" ]; then
    echo "⚠️ Version pinning is not supported for method=repos on RHEL-based systems. Installing latest available gh." >&2
  fi
  if command -v zypper > /dev/null 2>&1; then
    mkdir -p /etc/zypp/repos.d
    # Drop the .repo file directly so zypper parses baseurl from it.
    # 'zypper addrepo <URL>' treats the URL as the baseurl directly; when the
    # URL ends in .repo the fetched metadata path becomes wrong (.repo/repodata/).
    net__fetch_url_file \
      "https://cli.github.com/packages/rpm/gh-cli.repo" \
      "/etc/zypp/repos.d/gh-cli.repo"
    zypper --gpg-auto-import-keys ref gh-cli
    # zypper exits 6 ("INFO_REPOS_SKIPPED") when system update repos have stale
    # metadata in containers. Treat exit 6 as success — gh is still installed.
    zypper install -y gh || {
      _rc=$?
      [ "${_rc}" -eq 6 ] || exit "${_rc}"
    }
  elif command -v dnf > /dev/null 2>&1; then
    mkdir -p /etc/yum.repos.d
    net__fetch_url_file \
      "https://cli.github.com/packages/rpm/gh-cli.repo" \
      "/etc/yum.repos.d/gh-cli.repo"
    # gh RPM has a hard dependency on git; ensure it is available first.
    dnf install -y git
    dnf install -y gh --repo gh-cli
  elif command -v yum > /dev/null 2>&1; then
    mkdir -p /etc/yum.repos.d
    net__fetch_url_file \
      "https://cli.github.com/packages/rpm/gh-cli.repo" \
      "/etc/yum.repos.d/gh-cli.repo"
    yum install -y gh
  else
    echo "⛔ No supported package manager found for RHEL-based system." >&2
    exit 1
  fi
  echo "↩️ Function exit: _gh__repos_rhel" >&2
  return 0
}

# _gh__repos_alpine — install github-cli via apk community package.
_gh__repos_alpine() {
  echo "↪️ Function entry: _gh__repos_alpine" >&2
  if [ "${VERSION}" != "latest" ]; then
    echo "⚠️ Version pinning is not supported for method=repos on Alpine. Installing latest available github-cli." >&2
  fi
  ospkg__install github-cli
  echo "↩️ Function exit: _gh__repos_alpine" >&2
  return 0
}

# _gh__repos_arch — install github-cli via pacman.
_gh__repos_arch() {
  echo "↪️ Function entry: _gh__repos_arch" >&2
  if [ "${VERSION}" != "latest" ]; then
    echo "⚠️ Version pinning is not supported for method=repos on Arch. Installing latest available github-cli." >&2
  fi
  ospkg__update
  ospkg__install github-cli
  echo "↩️ Function exit: _gh__repos_arch" >&2
  return 0
}

# _gh__repos_macos — install gh via Homebrew.
_gh__repos_macos() {
  echo "↪️ Function entry: _gh__repos_macos" >&2
  if [ "${VERSION}" != "latest" ]; then
    echo "⚠️ Homebrew has no versioned formula for gh. Installing latest gh. Use method=binary for version pinning." >&2
  fi
  ospkg__install gh
  echo "↩️ Function exit: _gh__repos_macos" >&2
  return 0
}

# _gh__install_binary — download, verify, extract and install the gh binary.
# $1 = resolved version string (e.g. "2.89.0")
_gh__install_binary() {
  echo "↪️ Function entry: _gh__install_binary" >&2
  local _version="${1}"

  # Determine asset name components.
  local _kernel _asset_os _arch _asset_arch _ext _archive_name _archive_dir
  _kernel="$(os__kernel)"
  _arch="$(os__arch)"
  case "${_kernel}" in
    Linux)
      _asset_os="linux"
      _ext="tar.gz"
      ;;
    Darwin)
      _asset_os="macOS"
      _ext="zip"
      ;;
    *)
      echo "⛔ Unsupported kernel '${_kernel}' for method=binary." >&2
      exit 1
      ;;
  esac
  case "${_arch}" in
    x86_64) _asset_arch="amd64" ;;
    aarch64 | arm64) _asset_arch="arm64" ;;
    i386 | i686) _asset_arch="386" ;;
    armv6l | armv7l) _asset_arch="armv6" ;;
    *)
      echo "⛔ Unsupported architecture '${_arch}' for method=binary." >&2
      exit 1
      ;;
  esac
  _archive_name="gh_${_version}_${_asset_os}_${_asset_arch}.${_ext}"
  _archive_dir="gh_${_version}_${_asset_os}_${_asset_arch}"

  # Download archive + checksums.
  mkdir -p "${INSTALLER_DIR}"
  local _url_base="https://github.com/cli/cli/releases/download/v${_version}"
  echo "📥 Downloading ${_archive_name} from GitHub Releases..." >&2
  net__fetch_url_file "${_url_base}/${_archive_name}" "${INSTALLER_DIR}/${_archive_name}"
  echo "📥 Downloading checksums file..." >&2
  net__fetch_url_file "${_url_base}/gh_${_version}_checksums.txt" "${INSTALLER_DIR}/checksums.txt"

  # Verify checksum.
  echo "🔍 Verifying SHA-256 checksum..." >&2
  local _expected
  _expected="$(grep "${_archive_name}" "${INSTALLER_DIR}/checksums.txt" | awk '{print $1}')"
  if [ -z "${_expected}" ]; then
    echo "⛔ Could not find checksum for '${_archive_name}' in checksums.txt." >&2
    exit 1
  fi
  checksum__verify_sha256 "${INSTALLER_DIR}/${_archive_name}" "${_expected}"
  echo "✅ Checksum verified." >&2

  # Ensure extraction tools are available (skip install when already present).
  case "${_ext}" in
    tar.gz) command -v tar > /dev/null 2>&1 || ospkg__install tar ;;
    zip) command -v unzip > /dev/null 2>&1 || ospkg__install unzip ;;
  esac

  # Extract archive.
  echo "📦 Extracting archive..." >&2
  case "${_ext}" in
    tar.gz) tar -xzf "${INSTALLER_DIR}/${_archive_name}" -C "${INSTALLER_DIR}" ;;
    zip) unzip -q "${INSTALLER_DIR}/${_archive_name}" -d "${INSTALLER_DIR}" ;;
  esac

  # Install binary.
  mkdir -p "${PREFIX}/bin"
  install -m 755 "${INSTALLER_DIR}/${_archive_dir}/bin/gh" "${PREFIX}/bin/gh"
  echo "✅ gh binary installed to '${PREFIX}/bin/gh'" >&2

  # Install completions from archive (if requested).
  if [ -n "${SHELL_COMPLETIONS}" ]; then
    _gh__install_completions --from-archive "${INSTALLER_DIR}/${_archive_dir}"
  fi

  # Cleanup (unless keep_installer=true).
  if [ "${KEEP_INSTALLER}" != "true" ]; then
    echo "🗑 Cleaning up installer directory '${INSTALLER_DIR}'..." >&2
    rm -rf "${INSTALLER_DIR}"
  fi

  # Verify.
  "${PREFIX}/bin/gh" --version > /dev/null
  echo "↩️ Function exit: _gh__install_binary" >&2
  return 0
}

# _gh__create_symlink — create symlink to PREFIX/bin/gh in the canonical bin dir.
_gh__create_symlink() {
  echo "↪️ Function entry: _gh__create_symlink" >&2
  if [ "${SYMLINK}" != "true" ]; then
    echo "ℹ️ symlink=false; skipping." >&2
    echo "↩️ Function exit: _gh__create_symlink" >&2
    return 0
  fi
  if [ "${METHOD}" != "binary" ]; then
    echo "ℹ️ method=repos; symlink not applicable." >&2
    echo "↩️ Function exit: _gh__create_symlink" >&2
    return 0
  fi
  shell__create_symlink \
    --src "${PREFIX}/bin/gh" \
    --system-target "/usr/local/bin/gh" \
    --user-target "${HOME}/.local/bin/gh"
  echo "↩️ Function exit: _gh__create_symlink" >&2
  return 0
}

# _gh__install_completions — install completions for shells listed in SHELL_COMPLETIONS.
# Usage: _gh__install_completions --from-archive <dir>
#        _gh__install_completions --from-command
_gh__install_completions() {
  echo "↪️ Function entry: _gh__install_completions" >&2
  if [ -z "${SHELL_COMPLETIONS}" ]; then
    echo "ℹ️ shell_completions is empty; skipping completion install." >&2
    echo "↩️ Function exit: _gh__install_completions" >&2
    return 0
  fi
  local _mode="$1"
  local _archive_dir="${2:-}"
  local _shell
  for _shell in ${SHELL_COMPLETIONS}; do
    case "${_shell}" in
      bash)
        local _bash_content
        if [ "${_mode}" = "--from-archive" ]; then
          _bash_content="$(cat "${_archive_dir}/share/bash-completion/completions/gh" 2> /dev/null)" || {
            echo "⚠️ bash completion file not found in archive; skipping bash completion." >&2
            _bash_content=""
          }
        else
          _bash_content="$(gh completion -s bash 2> /dev/null)" || {
            echo "⚠️ gh completion -s bash failed; skipping bash completion." >&2
            _bash_content=""
          }
        fi
        if [ -n "${_bash_content}" ]; then
          if [ "$(id -u)" = "0" ]; then
            mkdir -p /etc/bash_completion.d
            printf '%s\n' "${_bash_content}" > /etc/bash_completion.d/gh
            echo "✅ Bash completion written to /etc/bash_completion.d/gh" >&2
          else
            mkdir -p "${HOME}/.local/share/bash-completion/completions"
            printf '%s\n' "${_bash_content}" > "${HOME}/.local/share/bash-completion/completions/gh"
            echo "✅ Bash completion written to ${HOME}/.local/share/bash-completion/completions/gh" >&2
          fi
        fi
        ;;
      zsh)
        local _zsh_content
        if [ "${_mode}" = "--from-archive" ]; then
          _zsh_content="$(cat "${_archive_dir}/share/zsh/site-functions/_gh" 2> /dev/null)" || {
            echo "⚠️ zsh completion file not found in archive; skipping zsh completion." >&2
            _zsh_content=""
          }
        else
          _zsh_content="$(gh completion -s zsh 2> /dev/null)" || {
            echo "⚠️ gh completion -s zsh failed; skipping zsh completion." >&2
            _zsh_content=""
          }
        fi
        if [ -n "${_zsh_content}" ]; then
          if [ "$(id -u)" = "0" ]; then
            local _zshdir
            _zshdir="$(shell__detect_zshdir)"
            mkdir -p "${_zshdir}/completions"
            printf '%s\n' "${_zsh_content}" > "${_zshdir}/completions/_gh"
            echo "✅ Zsh completion written to ${_zshdir}/completions/_gh" >&2
          else
            mkdir -p "${HOME}/.zfunc"
            printf '%s\n' "${_zsh_content}" > "${HOME}/.zfunc/_gh"
            echo "✅ Zsh completion written to ${HOME}/.zfunc/_gh" >&2
          fi
        fi
        ;;
      *)
        echo "⛔ Unsupported shell: '${_shell}' (expected: bash, zsh)" >&2
        exit 1
        ;;
    esac
  done
  echo "↩️ Function exit: _gh__install_completions" >&2
  return 0
}

# _gh__configure_user — apply per-user gh/git configuration.
_gh__configure_user() {
  echo "↪️ Function entry: _gh__configure_user" >&2
  local _users
  _users="$(users__resolve_list)" || {
    echo "⚠️ users__resolve_list failed; skipping per-user configuration." >&2
    echo "↩️ Function exit: _gh__configure_user" >&2
    return 0
  }
  if [ -z "${_users}" ]; then
    echo "ℹ️ No users resolved; skipping per-user configuration." >&2
    echo "↩️ Function exit: _gh__configure_user" >&2
    return 0
  fi

  local _user _home
  while IFS= read -r _user; do
    [ -z "${_user}" ] && continue
    _home="$(shell__resolve_home "${_user}")"

    echo "ℹ️ Configuring gh/git for user '${_user}' (home: ${_home})..." >&2

    # git_protocol: run gh config set as the target user.
    if [ -n "${GIT_PROTOCOL}" ]; then
      echo "ℹ️ Setting git_protocol=${GIT_PROTOCOL} for '${_user}'..." >&2
      if [ "$(id -u)" = "0" ] && [ "${_user}" != "root" ]; then
        su -l "${_user}" -c "gh config set git_protocol '${GIT_PROTOCOL}'"
      else
        GH_CONFIG_DIR="${_home}/.config/gh" gh config set git_protocol "${GIT_PROTOCOL}"
      fi
    fi

    # setup_git: register gh as credential helper.
    if [ "${SETUP_GIT}" = "true" ]; then
      echo "ℹ️ Running gh auth setup-git for '${_user}' (hostname: ${GIT_HOSTNAME})..." >&2
      if [ "$(id -u)" = "0" ] && [ "${_user}" != "root" ]; then
        su -l "${_user}" -c "gh auth setup-git --force --hostname '${GIT_HOSTNAME}'"
      else
        GH_CONFIG_DIR="${_home}/.config/gh" HOME="${_home}" \
          gh auth setup-git --force --hostname "${GIT_HOSTNAME}"
      fi
      # Ensure .gitconfig is owned by the user (su -l may create it as root
      # if the home dir is owned by root in some images).
      if [ -f "${_home}/.gitconfig" ]; then
        chown "${_user}:${_user}" "${_home}/.gitconfig" 2> /dev/null || true
      fi
    fi

    # sign_commits: set commit signing config via git config.
    if [ -n "${SIGN_COMMITS}" ]; then
      local _git_cfg_cmd_prefix=""
      if [ "$(id -u)" = "0" ] && [ "${_user}" != "root" ]; then
        _git_cfg_cmd_prefix="su -l ${_user} -c"
      fi
      case "${SIGN_COMMITS}" in
        ssh)
          echo "ℹ️ Configuring SSH commit signing for '${_user}'..." >&2
          if [ -n "${_git_cfg_cmd_prefix}" ]; then
            ${_git_cfg_cmd_prefix} "git config --global gpg.format ssh"
            ${_git_cfg_cmd_prefix} "git config --global commit.gpgsign true"
          else
            GIT_CONFIG_GLOBAL="${_home}/.gitconfig" git config --global gpg.format ssh
            GIT_CONFIG_GLOBAL="${_home}/.gitconfig" git config --global commit.gpgsign true
          fi
          ;;
        gpg)
          echo "ℹ️ Configuring GPG commit signing for '${_user}'..." >&2
          if [ -n "${_git_cfg_cmd_prefix}" ]; then
            # Exit code 5 when key is absent — suppress with || true under set -e.
            ${_git_cfg_cmd_prefix} "git config --global --unset-all gpg.format || true"
            ${_git_cfg_cmd_prefix} "git config --global commit.gpgsign true"
          else
            GIT_CONFIG_GLOBAL="${_home}/.gitconfig" git config --global --unset-all gpg.format || true
            GIT_CONFIG_GLOBAL="${_home}/.gitconfig" git config --global commit.gpgsign true
          fi
          ;;
      esac
      if [ -f "${_home}/.gitconfig" ]; then
        chown "${_user}:${_user}" "${_home}/.gitconfig" 2> /dev/null || true
      fi
    fi
  done << EOF
${_users}
EOF
  echo "↩️ Function exit: _gh__configure_user" >&2
  return 0
}

# _gh__install_extensions — install gh CLI extensions for all resolved users.
_gh__install_extensions() {
  echo "↪️ Function entry: _gh__install_extensions" >&2
  local _users
  _users="$(users__resolve_list)" || {
    echo "⚠️ users__resolve_list failed; skipping extension install." >&2
    echo "↩️ Function exit: _gh__install_extensions" >&2
    return 0
  }
  if [ -z "${_users}" ]; then
    echo "ℹ️ No users resolved; skipping extension install." >&2
    echo "↩️ Function exit: _gh__install_extensions" >&2
    return 0
  fi

  # Split EXTENSIONS on comma.
  local _ext_list="${EXTENSIONS}"
  local _user _home _ext
  while IFS= read -r _user; do
    [ -z "${_user}" ] && continue
    _home="$(shell__resolve_home "${_user}")"
    local _old_ifs="${IFS}"
    IFS=','
    for _ext in ${_ext_list}; do
      IFS="${_old_ifs}"
      _ext="$(printf '%s' "${_ext}" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')"
      [ -z "${_ext}" ] && continue
      echo "🔌 Installing gh extension '${_ext}' for user '${_user}'..." >&2
      if [ "$(id -u)" = "0" ] && [ "${_user}" != "root" ]; then
        su -l "${_user}" -c "gh extension install '${_ext}'" || {
          echo "⚠️ Failed to install extension '${_ext}' for '${_user}' (non-fatal)." >&2
        }
      else
        GH_CONFIG_DIR="${_home}/.config/gh" \
          HOME="${_home}" \
          gh extension install "${_ext}" || {
          echo "⚠️ Failed to install extension '${_ext}' (non-fatal)." >&2
        }
      fi
    done
    IFS="${_old_ifs}"
  done << EOF
${_users}
EOF
  echo "↩️ Function exit: _gh__install_extensions" >&2
  return 0
}

# shellcheck source=lib/github.sh
. "${_SELF_DIR}/_lib/github.sh"
# shellcheck source=lib/checksum.sh
. "${_SELF_DIR}/_lib/checksum.sh"
# shellcheck source=lib/shell.sh
. "${_SELF_DIR}/_lib/shell.sh"
# shellcheck source=lib/users.sh
. "${_SELF_DIR}/_lib/users.sh"

# ── Main orchestration ────────────────────────────────────────────────────────

# Early-exit if gh is already installed and version is 'latest' with
# if_exists=skip or if_exists=fail. Avoids requiring root, installing base deps,
# and hitting the GitHub API when no installation work is needed.
# This must run before os__require_root so macOS non-root installs can skip cleanly.
if [ "${VERSION}" = "latest" ] && command -v gh > /dev/null 2>&1; then
  if [ "${IF_EXISTS}" = "skip" ]; then
    _existing="$(gh --version 2> /dev/null | head -1 | awk '{print $3}')" || _existing=""
    echo "ℹ️ gh ${_existing} is already installed — skipping (if_exists=skip, version=latest)." >&2
    exit 0
  elif [ "${IF_EXISTS}" = "fail" ]; then
    _existing="$(gh --version 2> /dev/null | head -1 | awk '{print $3}')" || _existing=""
    echo "⛔ gh is already installed (${_existing}) and if_exists=fail." >&2
    exit 1
  fi
fi

os__require_root

if [ -z "${PREFIX-}" ] || [ "${PREFIX}" = "auto" ]; then
  if [ "$(id -u)" = "0" ]; then
    PREFIX="/usr/local"
  else
    PREFIX="${HOME}/.local"
  fi
  echo "ℹ️ Argument 'PREFIX' resolved from 'auto' to '${PREFIX}'." >&2
fi

# Resolve version (may call GitHub API).
_resolved_version="$(_gh__resolve_version)"

# Export user config env vars so users__resolve_list picks them up.
export ADD_CURRENT_USER
export ADD_REMOTE_USER
export ADD_CONTAINER_USER
export ADD_USERS

# Check existing installation; may exit 0 or 1.
_gh__check_existing "${_resolved_version}"

# Install gh.
if [ "${METHOD}" = "repos" ]; then
  _gh__install_repos
else
  _gh__install_binary "${_resolved_version}"
fi

# Create /usr/local/bin symlink (binary method, non-default prefix).
_gh__create_symlink

# Install completions for repos method (binary method handles them internally).
if [ -n "${SHELL_COMPLETIONS}" ] && [ "${METHOD}" = "repos" ]; then
  _gh__install_completions --from-command
fi

# Per-user configuration (git_protocol, setup_git, sign_commits).
if [ -n "${GIT_PROTOCOL}" ] || [ "${SETUP_GIT}" = "true" ] || [ -n "${SIGN_COMMITS}" ]; then
  _gh__configure_user
fi

# Install gh extensions (if any).
if [ -n "${EXTENSIONS}" ]; then
  _gh__install_extensions
fi
