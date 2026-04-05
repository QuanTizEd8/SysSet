#!/usr/bin/env bash
set -euo pipefail
__cleanup__() {
  echo "↪️ Function entry: __cleanup__" >&2
  if [ -n "${LOGFILE-}" ]; then
    exec 1>&3 2>&4
    wait 2>/dev/null
    echo "ℹ️ Write logs to file '$LOGFILE'" >&2
    mkdir -p "$(dirname "$LOGFILE")"
    cat "$_LOGFILE_TMP" >> "$LOGFILE"
    rm -f "$_LOGFILE_TMP"
  fi
  echo "↩️ Function exit: __cleanup__" >&2
}
clean_apk() {
  echo "↪️ Function entry: clean_apk" >&2
  rm -rf /var/cache/apk/*
  echo "↩️ Function exit: clean_apk" >&2
}
clean_apt() {
  echo "↪️ Function entry: clean_apt" >&2
  if ! apt-get dist-clean; then
      echo "⚠️  'apt-get dist-clean' failed — falling back to 'apt-get clean'." >&2
      apt-get clean
      rm -rf /var/lib/apt/lists/*
  fi
  echo "↩️ Function exit: clean_apt" >&2
}
clean_dnf() {
  echo "↪️ Function entry: clean_dnf" >&2
  ${PKG_MNGR} clean all
  rm -rf /var/cache/dnf/* /var/cache/yum/*
  echo "↩️ Function exit: clean_dnf" >&2
}
clean_pacman() {
  echo "↪️ Function entry: clean_pacman" >&2
  pacman -Scc --noconfirm
  echo "↩️ Function exit: clean_pacman" >&2
}
clean_zypper() {
  echo "↪️ Function entry: clean_zypper" >&2
  zypper clean --all
  echo "↩️ Function exit: clean_zypper" >&2
}
exit_if_not_root() {
  echo "↪️ Function entry: exit_if_not_root" >&2
  if [ "$(id -u)" -ne 0 ]; then
      echo '⛔ This script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.' >&2
      exit 1
  fi
  echo "↩️ Function exit: exit_if_not_root" >&2
}
install() {
  echo "↪️ Function entry: install" >&2
  if [ ${PKG_MNGR} = "apt-get" ]; then
      if dpkg -s "$@" > /dev/null 2>&1; then
          echo "ℹ️  Packages already installed: $@" >&2
          return 0
      fi
  elif [ ${PKG_MNGR} = "dnf" ] || [ ${PKG_MNGR} = "yum" ]; then
      _num_pkgs=$#
      _num_installed=$(${PKG_MNGR} -C list installed "$@" 2>/dev/null | sed '1,/^Installed/d' | wc -l) || _num_installed=0
      if [ ${_num_pkgs} == ${_num_installed} ]; then
          echo "ℹ️  Packages already installed: $@" >&2
          return 0
      fi
  fi
  echo "📲 Installing packages:" >&2
  printf '  - %s\n' "$@" >&2
  "${INSTALL[@]}" "$@"
  echo "↩️ Function exit: install" >&2
}
# eval_selector_block "key=val,key=val,..."
# Returns 0 if ALL conditions match OS_RELEASE, 1 otherwise.
eval_selector_block() {
  local block="$1"
  local cond key val actual
  IFS=',' read -ra _conds <<< "$block"
  for cond in "${_conds[@]}"; do
    cond="${cond// /}"   # strip spaces
    key="${cond%%=*}"
    val="${cond#*=}"
    actual="${OS_RELEASE[$key]-}"
    if [[ "${actual,,}" != "${val,,}" ]]; then
      return 1
    fi
  done
  return 0
}
# pkg_matches_selectors "raw pkg line"
# Returns 0 if the line has no selector blocks, or if ANY block passes (OR logic).
pkg_matches_selectors() {
  local line="$1"
  local -a blocks=()
  local rest="$line"
  while [[ "$rest" =~ \[([^]]+)\] ]]; do
    blocks+=("${BASH_REMATCH[1]}")
    rest="${rest#*]}"
  done
  if [[ ${#blocks[@]} -eq 0 ]]; then
    return 0
  fi
  local block
  for block in "${blocks[@]}"; do
    if eval_selector_block "$block"; then
      return 0
    fi
  done
  return 1
}
# filter_pkg_lines <file>
# Reads a pkg file, applies selector logic, prints matching package names.
filter_pkg_lines() {
  local file="$1"
  local line pkg
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    if pkg_matches_selectors "$line"; then
      pkg="${line%%\[*}"
      pkg="${pkg%"${pkg##*[! $'\t']}"}"  # rtrim
      [[ -n "$pkg" ]] && echo "$pkg"
    fi
  done < "$file"
}
_LOGFILE_TMP="$(mktemp)"
exec 3>&1 4>&2
exec > >(tee -a "$_LOGFILE_TMP" >&3) 2>&1
echo "↪️ Script entry: System Package Installation" >&2
trap __cleanup__ EXIT
if [ "$#" -gt 0 ]; then
  echo "ℹ️ Script called with arguments: $@" >&2
  DEBUG=""
  DIR=""
  INTERACTIVE=""
  KEEP_REPOS=""
  LOGFILE=""
  NO_CLEAN=""
  NO_UPDATE=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --debug) shift; DEBUG=true; echo "📩 Read argument 'debug': '"$DEBUG"'" >&2;;
      --dir) shift; DIR="$1"; echo "📩 Read argument 'dir': '"$DIR"'" >&2; shift;;
      --interactive) shift; INTERACTIVE=true; echo "📩 Read argument 'interactive': '"$INTERACTIVE"'" >&2;;
      --keep_repos) shift; KEEP_REPOS=true; echo "📩 Read argument 'keep_repos': '"$KEEP_REPOS"'" >&2;;
      --logfile) shift; LOGFILE="$1"; echo "📩 Read argument 'logfile': '"$LOGFILE"'" >&2; shift;;
      --no_clean) shift; NO_CLEAN=true; echo "📩 Read argument 'no_clean': '"$NO_CLEAN"'" >&2;;
      --no_update) shift; NO_UPDATE=true; echo "📩 Read argument 'no_update': '"$NO_UPDATE"'" >&2;;
      --*) echo "⛔ Unknown option: "$1"" >&2; exit 1;;
      *) echo "⛔ Unexpected argument: "$1"" >&2; exit 1;;
    esac
  done
else
  echo "ℹ️ Script called with no arguments. Read environment variables." >&2
  [ "${DEBUG+defined}" ] && echo "📩 Read argument 'debug': '"$DEBUG"'" >&2
  [ "${DIR+defined}" ] && echo "📩 Read argument 'dir': '"$DIR"'" >&2
  [ "${INTERACTIVE+defined}" ] && echo "📩 Read argument 'interactive': '"$INTERACTIVE"'" >&2
  [ "${KEEP_REPOS+defined}" ] && echo "📩 Read argument 'keep_repos': '"$KEEP_REPOS"'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '"$LOGFILE"'" >&2
  [ "${NO_CLEAN+defined}" ] && echo "📩 Read argument 'no_clean': '"$NO_CLEAN"'" >&2
  [ "${NO_UPDATE+defined}" ] && echo "📩 Read argument 'no_update': '"$NO_UPDATE"'" >&2
fi
[[ "$DEBUG" == true ]] && set -x
[ -z "${DEBUG-}" ] && { echo "ℹ️ Argument 'DEBUG' set to default value 'false'." >&2; DEBUG=false; }
[ -z "${DIR-}" ] && { echo "⛔ Missing required argument 'DIR'." >&2; exit 1; }
[ -n "${DIR-}" ] && [ ! -d "$DIR" ] && { echo "⛔ Directory argument to parameter 'DIR' not found: '$DIR'" >&2; exit 1; }
[ -z "${INTERACTIVE-}" ] && { echo "ℹ️ Argument 'INTERACTIVE' set to default value 'false'." >&2; INTERACTIVE=false; }
[ -z "${KEEP_REPOS-}" ] && { echo "ℹ️ Argument 'KEEP_REPOS' set to default value 'false'." >&2; KEEP_REPOS=false; }
[ -z "${LOGFILE-}" ] && { echo "ℹ️ Argument 'LOGFILE' set to default value ''." >&2; LOGFILE=""; }
[ -z "${NO_CLEAN-}" ] && { echo "ℹ️ Argument 'NO_CLEAN' set to default value 'false'." >&2; NO_CLEAN=false; }
[ -z "${NO_UPDATE-}" ] && { echo "ℹ️ Argument 'NO_UPDATE' set to default value 'false'." >&2; NO_UPDATE=false; }
exit_if_not_root
DIR="${DIR%/}"
if type apt-get > /dev/null 2>&1; then
    echo "🛠️  Detected ecosystem: APT (tool: apt-get)" >&2
    PKG_PREFIX="apt"
    PKG_MNGR="apt-get"
    UPDATE=(apt-get update)
    INSTALL=(apt-get -y install --no-install-recommends)
    CLEAN=(clean_apt)
elif type apk > /dev/null 2>&1; then
    echo "🛠️  Detected ecosystem: APK (tool: apk)" >&2
    PKG_PREFIX="apk"
    PKG_MNGR="apk"
    UPDATE=(apk update)
    INSTALL=(apk add --no-cache)
    CLEAN=(clean_apk)
elif type dnf > /dev/null 2>&1; then
    echo "🛠️  Detected ecosystem: DNF (tool: dnf)" >&2
    PKG_PREFIX="dnf"
    PKG_MNGR="dnf"
    UPDATE=(dnf check-update)
    INSTALL=(dnf -y install)
    CLEAN=(clean_dnf)
elif type microdnf > /dev/null 2>&1; then
    echo "🛠️  Detected ecosystem: DNF (tool: microdnf)" >&2
    PKG_PREFIX="dnf"
    PKG_MNGR="microdnf"
    UPDATE=()
    INSTALL=(microdnf -y install --refresh --best --nodocs --noplugins --setopt=install_weak_deps=0)
    CLEAN=(clean_dnf)
elif type yum > /dev/null 2>&1; then
    echo "🛠️  Detected ecosystem: DNF (tool: yum)" >&2
    PKG_PREFIX="dnf"
    PKG_MNGR="yum"
    UPDATE=(yum check-update)
    INSTALL=(yum -y install)
    CLEAN=(clean_dnf)
elif type zypper > /dev/null 2>&1; then
    echo "🛠️  Detected ecosystem: Zypper (tool: zypper)" >&2
    PKG_PREFIX="zypper"
    PKG_MNGR="zypper"
    UPDATE=(zypper --non-interactive refresh)
    INSTALL=(zypper --non-interactive install)
    CLEAN=(clean_zypper)
elif type pacman > /dev/null 2>&1; then
    echo "🛠️  Detected ecosystem: Pacman (tool: pacman)" >&2
    PKG_PREFIX="pacman"
    PKG_MNGR="pacman"
    UPDATE=(pacman -Sy --noconfirm)
    INSTALL=(pacman -S --noconfirm --needed)
    CLEAN=(clean_pacman)
else
    echo "⛔ No supported package manager found." >&2
    exit 1
fi
# Load /etc/os-release into an associative array for selector evaluation.
declare -A OS_RELEASE=()
if [[ -f /etc/os-release ]]; then
    while IFS='=' read -r _key _val; do
        [[ -z "${_key-}" || "$_key" =~ ^# ]] && continue
        _val="${_val#\"}" ; _val="${_val%\"}"   # strip double quotes
        _val="${_val#\'}" ; _val="${_val%\'}"   # strip single quotes
        OS_RELEASE["${_key,,}"]="$_val"
    done < /etc/os-release
fi
OS_RELEASE[pm]="$PKG_PREFIX"
OS_RELEASE[arch]="$(uname -m)"
echo "🔍 OS context: pm=${OS_RELEASE[pm]} arch=${OS_RELEASE[arch]} id=${OS_RELEASE[id]-} id_like=${OS_RELEASE[id_like]-} version_id=${OS_RELEASE[version_id]-} version_codename=${OS_RELEASE[version_codename]-}" >&2
PRESCRIPT_FILE="${DIR}/${PKG_PREFIX}-prescript"
REPO_FILE="${DIR}/${PKG_PREFIX}-repo"
PKG_FILE="${DIR}/${PKG_PREFIX}-pkg"
SCRIPT_FILE="${DIR}/${PKG_PREFIX}-script"
echo "ℹ️  Looking for files with prefix '${PKG_PREFIX}' in '${DIR}':" >&2
echo "   prescript : ${PRESCRIPT_FILE}" >&2
echo "   repo      : ${REPO_FILE}" >&2
echo "   pkg       : ${PKG_FILE}" >&2
echo "   script    : ${SCRIPT_FILE}" >&2
if [[ ! -f "$PRESCRIPT_FILE" && ! -f "$REPO_FILE" && ! -f "$PKG_FILE" && ! -f "$SCRIPT_FILE" ]]; then
    echo "ℹ️  No files found for ecosystem '${PKG_PREFIX}' in '${DIR}'. Nothing to do." >&2
    exit 0
fi
if [[ -f "$PRESCRIPT_FILE" ]]; then
    echo "🚀 Running pre-installation script '${PRESCRIPT_FILE}'." >&2
    chmod +x "$PRESCRIPT_FILE"
    "$PRESCRIPT_FILE"
    echo "✅ Pre-installation script completed." >&2
else
    echo "ℹ️  No prescript file found — skipping." >&2
fi
REPO_ADDED=false
if [[ -f "$REPO_FILE" ]]; then
    echo "🗃  Adding repositories from '${REPO_FILE}'." >&2
    if [[ "$PKG_PREFIX" = "apt" ]]; then
        cp "$REPO_FILE" /etc/apt/sources.list.d/syspkg-installer.list
        echo "📄 Written to /etc/apt/sources.list.d/syspkg-installer.list" >&2
    elif [[ "$PKG_PREFIX" = "apk" ]]; then
        APK_ADDED_REPOS=()
        while IFS= read -r _line; do
            [[ -z "${_line:-}" || "${_line}" =~ ^[[:space:]]*# ]] && continue
            echo "$_line" >> /etc/apk/repositories
            APK_ADDED_REPOS+=("$_line")
            echo "📄 Added APK repo: ${_line}" >&2
        done < "$REPO_FILE"
    elif [[ "$PKG_PREFIX" = "dnf" ]]; then
        cp "$REPO_FILE" /etc/yum.repos.d/syspkg-installer.repo
        echo "📄 Written to /etc/yum.repos.d/syspkg-installer.repo" >&2
    elif [[ "$PKG_PREFIX" = "zypper" ]]; then
        cp "$REPO_FILE" /etc/zypp/repos.d/syspkg-installer.repo
        echo "📄 Written to /etc/zypp/repos.d/syspkg-installer.repo" >&2
    elif [[ "$PKG_PREFIX" = "pacman" ]]; then
        mkdir -p /etc/pacman.d
        cp "$REPO_FILE" /etc/pacman.d/syspkg-installer.conf
        echo "Include = /etc/pacman.d/syspkg-installer.conf" >> /etc/pacman.conf
        echo "📄 Written to /etc/pacman.d/syspkg-installer.conf (referenced from /etc/pacman.conf)" >&2
    fi
    REPO_ADDED=true
else
    echo "ℹ️  No repo file found — skipping." >&2
fi
if [[ "$PKG_MNGR" = "apt-get" && "$INTERACTIVE" == false ]]; then
    echo "🆗 Setting APT to non-interactive mode." >&2
    export DEBIAN_FRONTEND=noninteractive
fi
if [[ -f "$PKG_FILE" && "$NO_UPDATE" == false ]]; then
    if [[ ${#UPDATE[@]} -gt 0 ]]; then
        echo "🔄 Updating package lists." >&2
        if [[ "$PKG_MNGR" = "dnf" || "$PKG_MNGR" = "yum" ]]; then
            "${UPDATE[@]}" || [[ $? -eq 100 ]]
        else
            "${UPDATE[@]}"
        fi
        echo "✅ Package lists updated." >&2
    else
        echo "ℹ️  Package list update not supported by '${PKG_MNGR}' — skipping." >&2
    fi
elif [[ ! -f "$PKG_FILE" ]]; then
    echo "ℹ️  Package list update skipped (no pkg file)." >&2
else
    echo "ℹ️  Package list update skipped (--no_update)." >&2
fi
if [[ -f "$PKG_FILE" ]]; then
    mapfile -t PACKAGES < <(filter_pkg_lines "$PKG_FILE")
    if [[ ${#PACKAGES[@]} -eq 0 ]]; then
        echo "⚠️  No packages found in '${PKG_FILE}' — skipping install." >&2
    else
        echo "📦 Installing ${#PACKAGES[@]} package(s) from '${PKG_FILE}'." >&2
        install "${PACKAGES[@]}"
    fi
else
    echo "ℹ️  No pkg file found — skipping install." >&2
fi
if [[ -f "$SCRIPT_FILE" ]]; then
    echo "🚀 Running post-installation script '${SCRIPT_FILE}'." >&2
    chmod +x "$SCRIPT_FILE"
    "$SCRIPT_FILE"
    echo "✅ Post-installation script completed." >&2
else
    echo "ℹ️  No script file found — skipping." >&2
fi
if [[ "$REPO_ADDED" == true && "$KEEP_REPOS" == false ]]; then
    echo "🗑️  Removing added repositories." >&2
    if [[ "$PKG_PREFIX" = "apt" ]]; then
        rm -f /etc/apt/sources.list.d/syspkg-installer.list
        echo "🗑️  Removed /etc/apt/sources.list.d/syspkg-installer.list" >&2
    elif [[ "$PKG_PREFIX" = "apk" ]]; then
        for _repo_line in "${APK_ADDED_REPOS[@]}"; do
            sed -i "\\|^${_repo_line}$|d" /etc/apk/repositories
            echo "🗑️  Removed APK repo: ${_repo_line}" >&2
        done
    elif [[ "$PKG_PREFIX" = "dnf" ]]; then
        rm -f /etc/yum.repos.d/syspkg-installer.repo
        echo "🗑️  Removed /etc/yum.repos.d/syspkg-installer.repo" >&2
    elif [[ "$PKG_PREFIX" = "zypper" ]]; then
        rm -f /etc/zypp/repos.d/syspkg-installer.repo
        echo "🗑️  Removed /etc/zypp/repos.d/syspkg-installer.repo" >&2
    elif [[ "$PKG_PREFIX" = "pacman" ]]; then
        rm -f /etc/pacman.d/syspkg-installer.conf
        sed -i '/^Include = \/etc\/pacman.d\/syspkg-installer.conf$/d' /etc/pacman.conf
        echo "🗑️  Removed /etc/pacman.d/syspkg-installer.conf and Include entry from /etc/pacman.conf" >&2
    fi
elif [[ "$REPO_ADDED" == true ]]; then
    echo "ℹ️  Keeping added repositories (--keep_repos)." >&2
fi
if [[ "$NO_CLEAN" == false ]]; then
    echo "🧹 Cleaning package manager cache." >&2
    "${CLEAN[@]}"
else
    echo "ℹ️  Cache cleanup skipped (--no_clean)." >&2
fi
echo "✅ Package installation complete."
echo "↩️ Script exit: System Package Installation" >&2
