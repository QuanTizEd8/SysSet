#!/usr/bin/env bash
set -euo pipefail
__usage__() {
  echo "Usage:" >&2
  echo "  --debug (boolean): " >&2
  echo "  --installer_dir (string): " >&2
  echo "  --logfile (string): " >&2
  echo "  --no_clean (boolean): " >&2
  echo "  --prefix (string): " >&2
  echo "  --source (string): The full URL is built by appending the resolved version to this URL." >&2
  echo "  --sysconfdir (string): " >&2
  echo "  --syspkg_install_script (string): " >&2
  echo "  --version (string): This must be a regex matching a version number ($(^) and $($) are automatically added to this). The latest version matching the regex will be selected. If not specified, the latest version will be installed." >&2
  exit 0
}

__cleanup__() {
  echo "↪️ Function entry: __cleanup__" >&2
  [[ "${NO_CLEAN-}" == false ]] && (cd / && rm -rf "${INSTALLER_DIR-}/git-${VERSION-}")
  if [ -n "${LOGFILE-}" ]; then
    exec 1>&3 2>&4
    wait 2> /dev/null
    echo "ℹ️ Write logs to file '$LOGFILE'" >&2
    mkdir -p "$(dirname "$LOGFILE")"
    cat "$_LOGFILE_TMP" >> "$LOGFILE"
    rm -f "$_LOGFILE_TMP"
  fi
  echo "↩️ Function exit: __cleanup__" >&2
}

exit_if_not_root() {
  echo "↪️ Function entry: exit_if_not_root" >&2
  if [ "$(id -u)" -ne 0 ]; then
    echo '⛔ This script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.' >&2
    exit 1
  fi
  echo "↩️ Function exit: exit_if_not_root" >&2
}

get_matching_github_ref() {
  echo "↪️ Function entry: get_matching_github_ref" >&2
  __usage__() {
    echo "Usage:" >&2
    echo "  --owner (string): " >&2
    echo "  --ref (string): All references starting with this string will match.
  " >&2
    echo "  --regex (string): This is used to further filter the references,
  after removing the prefix. The leading \"^\" and
  trailing \"\$\" are automatically added to this regex.
  " >&2
    echo "  --remove_prefix (string): This is used to clean up the reference names.
  For example, if the ref is \"tags/v1.2.3\",
  and the prefix is \"tags/v\",
  the result will be \"1.2.3\".
  " >&2
    echo "  --repo (string): " >&2
    exit 0
  }
  local owner=""
  local ref=""
  local regex=""
  local remove_prefix=""
  local repo=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --owner)
        shift
        owner="$1"
        echo "📩 Read argument 'owner': '${owner}'" >&2
        shift
        ;;
      --ref)
        shift
        ref="$1"
        echo "📩 Read argument 'ref': '${ref}'" >&2
        shift
        ;;
      --regex)
        shift
        regex="$1"
        echo "📩 Read argument 'regex': '${regex}'" >&2
        shift
        ;;
      --remove_prefix)
        shift
        remove_prefix="$1"
        echo "📩 Read argument 'remove_prefix': '${remove_prefix}'" >&2
        shift
        ;;
      --repo)
        shift
        repo="$1"
        echo "📩 Read argument 'repo': '${repo}'" >&2
        shift
        ;;
      --help | -h) __usage__ ;;
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
  [ -z "${owner-}" ] && {
    echo "⛔ Missing required argument 'owner'." >&2
    exit 1
  }
  [ -z "${ref-}" ] && {
    echo "⛔ Missing required argument 'ref'." >&2
    exit 1
  }
  [ -z "${regex-}" ] && {
    echo "ℹ️ Argument 'regex' set to default value ''." >&2
    regex=""
  }
  [ -z "${remove_prefix-}" ] && {
    echo "ℹ️ Argument 'remove_prefix' set to default value ''." >&2
    remove_prefix=""
  }
  [ -z "${repo-}" ] && {
    echo "⛔ Missing required argument 'repo'." >&2
    exit 1
  }
  local api_url="https://api.github.com/repos/${owner}/${repo}/git/matching-refs/${ref}"
  local all_refs=()
  mapfile -t all_refs < <(
    curl -fsSL "$api_url" |
      jq -r '.[] | .ref' |
      while IFS= read -r full_ref; do
        local clean_ref="${full_ref#refs/}"
        if [[ "$clean_ref" == "$remove_prefix"* ]]; then
          clean_ref="${clean_ref#"$remove_prefix"}"
          printf '%s\n' "$clean_ref"
        fi
      done
  )
  echo "ℹ️ Initial matched refs:" >&2
  printf '- %s\n' "${all_refs[@]}" >&2
  local matched_refs=()
  if [[ -z "$regex" ]]; then
    matched_refs=("${all_refs[@]}")
  else
    regex="^${regex}\$"
    for ref in "${all_refs[@]}"; do
      if [[ "$ref" =~ $regex ]]; then
        matched_refs+=("$ref")
      fi
    done
    echo "ℹ️ Final matched refs:" >&2
    printf '- %s\n' "${matched_refs[@]}" >&2
  fi
  if [[ ${#matched_refs[@]} -eq 0 ]]; then
    echo "⛔ No matching refs found." >&2
    exit 1
  fi
  ref="${matched_refs[-1]}"
  echo "📤 Write output 'ref': '${ref}'" >&2
  echo "${ref}"
  echo "↩️ Function exit: get_matching_github_ref" >&2
}

get_script_dir() {
  echo "↪️ Function entry: get_script_dir" >&2
  local script_dir
  script_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
  echo "📤 Write output 'script_dir': '${script_dir}'" >&2
  echo "${script_dir}"
  echo "↩️ Function exit: get_script_dir" >&2
}

_LOGFILE_TMP="$(mktemp)"
exec 3>&1 4>&2
exec > >(tee -a "$_LOGFILE_TMP" >&3) 2>&1
echo "↪️ Script entry: Git Installation" >&2
trap __cleanup__ EXIT
if [ "$#" -gt 0 ]; then
  # shellcheck disable=SC2145
  echo "ℹ️ Script called with arguments: $@" >&2
  DEBUG=""
  INSTALLER_DIR=""
  LOGFILE=""
  NO_CLEAN=""
  PREFIX=""
  SOURCE=""
  SYSCONFDIR=""
  SYSPKG_INSTALL_SCRIPT=""
  VERSION=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --debug)
        shift
        DEBUG=true
        echo "📩 Read argument 'debug': '${DEBUG}'" >&2
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
      --no_clean)
        shift
        NO_CLEAN=true
        echo "📩 Read argument 'no_clean': '${NO_CLEAN}'" >&2
        ;;
      --prefix)
        shift
        PREFIX="$1"
        echo "📩 Read argument 'prefix': '${PREFIX}'" >&2
        shift
        ;;
      --source)
        shift
        SOURCE="$1"
        echo "📩 Read argument 'source': '${SOURCE}'" >&2
        shift
        ;;
      --sysconfdir)
        shift
        SYSCONFDIR="$1"
        echo "📩 Read argument 'sysconfdir': '${SYSCONFDIR}'" >&2
        shift
        ;;
      --syspkg_install_script)
        shift
        SYSPKG_INSTALL_SCRIPT="$1"
        echo "📩 Read argument 'syspkg_install_script': '${SYSPKG_INSTALL_SCRIPT}'" >&2
        shift
        ;;
      --version)
        shift
        VERSION="$1"
        echo "📩 Read argument 'version': '${VERSION}'" >&2
        shift
        ;;
      --help | -h) __usage__ ;;
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
  [ "${INSTALLER_DIR+defined}" ] && echo "📩 Read argument 'installer_dir': '${INSTALLER_DIR}'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
  [ "${NO_CLEAN+defined}" ] && echo "📩 Read argument 'no_clean': '${NO_CLEAN}'" >&2
  [ "${PREFIX+defined}" ] && echo "📩 Read argument 'prefix': '${PREFIX}'" >&2
  [ "${SOURCE+defined}" ] && echo "📩 Read argument 'source': '${SOURCE}'" >&2
  [ "${SYSCONFDIR+defined}" ] && echo "📩 Read argument 'sysconfdir': '${SYSCONFDIR}'" >&2
  [ "${SYSPKG_INSTALL_SCRIPT+defined}" ] && echo "📩 Read argument 'syspkg_install_script': '${SYSPKG_INSTALL_SCRIPT}'" >&2
  [ "${VERSION+defined}" ] && echo "📩 Read argument 'version': '${VERSION}'" >&2
fi
[[ "$DEBUG" == true ]] && set -x
[ -z "${DEBUG-}" ] && {
  echo "ℹ️ Argument 'DEBUG' set to default value 'false'." >&2
  DEBUG=false
}
[ -z "${INSTALLER_DIR-}" ] && {
  echo "ℹ️ Argument 'INSTALLER_DIR' set to default value '/tmp/git-installer'." >&2
  INSTALLER_DIR="/tmp/git-installer"
}
[ -z "${LOGFILE-}" ] && {
  echo "ℹ️ Argument 'LOGFILE' set to default value ''." >&2
  LOGFILE=""
}
[ -z "${NO_CLEAN-}" ] && {
  echo "ℹ️ Argument 'NO_CLEAN' set to default value 'false'." >&2
  NO_CLEAN=false
}
[ -z "${PREFIX-}" ] && {
  echo "ℹ️ Argument 'PREFIX' set to default value '/usr/local/git'." >&2
  PREFIX="/usr/local/git"
}
[ -z "${SOURCE-}" ] && {
  echo "ℹ️ Argument 'SOURCE' set to default value 'https://www.kernel.org/pub/software/scm/git/git-'." >&2
  SOURCE="https://www.kernel.org/pub/software/scm/git/git-"
}
[ -z "${SYSCONFDIR-}" ] && {
  echo "ℹ️ Argument 'SYSCONFDIR' set to default value '/etc'." >&2
  SYSCONFDIR="/etc"
}
[ -z "${SYSPKG_INSTALL_SCRIPT-}" ] && {
  echo "⛔ Missing required argument 'SYSPKG_INSTALL_SCRIPT'." >&2
  exit 1
}
[ -n "${SYSPKG_INSTALL_SCRIPT-}" ] && [ ! -x "${SYSPKG_INSTALL_SCRIPT}" ] && {
  echo "⛔ Executable argument to parameter 'SYSPKG_INSTALL_SCRIPT' not found: '${SYSPKG_INSTALL_SCRIPT}'" >&2
  exit 1
}
[ -z "${VERSION-}" ] && {
  echo "ℹ️ Argument 'VERSION' set to default value ''." >&2
  VERSION=""
}
exit_if_not_root
_install_args=(--apt "$(get_script_dir)/requirements/apt.txt" --logfile "$LOGFILE")
[[ "$DEBUG" == true ]] && _install_args+=(--debug)
"$SYSPKG_INSTALL_SCRIPT" "${_install_args[@]}"
VERSION=$(
  get_matching_github_ref \
    --owner git \
    --repo git \
    --ref "tags/v" \
    --remove_prefix "tags/v" \
    --regex "$VERSION"
)
mkdir -p "$INSTALLER_DIR"
echo "📥 Download source code for Git v${VERSION}."
curl -sL "${SOURCE}${VERSION}.tar.gz" | tar -xzC "$INSTALLER_DIR" 2>&1
echo "🏗 Build Git."
cd "$INSTALLER_DIR/git-$VERSION"
git_options=("prefix=$PREFIX")
git_options+=("sysconfdir=$SYSCONFDIR")
git_options+=("USE_LIBPCRE=YesPlease")
make -s "${git_options[@]}" all && make -s "${git_options[@]}" install 2>&1
echo "✅ Git v${VERSION} installed successfully."
echo "↩️ Script exit: Git Installation" >&2
