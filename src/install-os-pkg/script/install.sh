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
  apt-get clean
  apt-get dist-clean 2>/dev/null || rm -rf /var/lib/apt/lists/*
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
# parse_manifest <content>
# Parses manifest content (passed as a single string argument) into four
# newline-delimited output variables set in the caller's scope:
#   _M_PRESCRIPT  _M_REPO  _M_PKG  _M_SCRIPT
# Each variable holds the lines that belong to that section type and whose
# header selector (if any) passes.  The implicit leading block is treated
# as a pkg section.  Lines within each section are still subject to
# per-line selector filtering for pkg; other section types emit raw lines.
parse_manifest() {
  local content="$1"
  _M_PRESCRIPT="" _M_REPO="" _M_KEY="" _M_PKG="" _M_SCRIPT=""
  local _type=pkg _active=true _line _mtype _mselectors _mpkg
  while IFS= read -r _line || [[ -n "$_line" ]]; do
    if [[ "$_line" =~ ^---[[:space:]]+(key|pkg|prescript|repo|script)(([[:space:]].*)?$) ]]; then
      _mtype="${BASH_REMATCH[1]}"
      _mselectors="${BASH_REMATCH[2]# }"
      _type="$_mtype"
      if pkg_matches_selectors "$_mselectors"; then _active=true; else _active=false; fi
      continue
    fi
    [[ "$_active" == true ]] || continue
    [[ "$_line" =~ ^[[:space:]]*(#|$) ]] && continue
    case "$_type" in
      pkg)
        if pkg_matches_selectors "$_line"; then
          _mpkg="${_line%%\[*}"
          _mpkg="${_mpkg%"${_mpkg##*[! $'\t']}"}"  # rtrim
          [[ -n "$_mpkg" ]] && _M_PKG+="${_mpkg}"$'\n'
        fi
        ;;
      key)       _M_KEY+="${_line}"$'\n'       ;;
      prescript) _M_PRESCRIPT+="${_line}"$'\n' ;;
      repo)      _M_REPO+="${_line}"$'\n'      ;;
      script)    _M_SCRIPT+="${_line}"$'\n'    ;;
    esac
  done <<< "$content"
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
  LIFECYCLE_HOOK=""
  LOGFILE=""
  MANIFEST=""
  NO_CLEAN=""
  NO_UPDATE=""
  DRY_RUN=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --debug) shift; DEBUG=true; echo "📩 Read argument 'debug': '"$DEBUG"'" >&2;;
      --dir) shift; DIR="$1"; echo "📩 Read argument 'dir': '"$DIR"'" >&2; shift;;
      --install_self) shift; INSTALL_SELF="$1"; echo "📩 Read argument 'install_self': '"$INSTALL_SELF"'" >&2; shift;;
      --interactive) shift; INTERACTIVE=true; echo "📩 Read argument 'interactive': '"$INTERACTIVE"'" >&2;;
      --keep_repos) shift; KEEP_REPOS=true; echo "📩 Read argument 'keep_repos': '"$KEEP_REPOS"'" >&2;;
      --lifecycle_hook) shift; LIFECYCLE_HOOK="$1"; echo "📩 Read argument 'lifecycle_hook': '"$LIFECYCLE_HOOK"'" >&2; shift;;
      --logfile) shift; LOGFILE="$1"; echo "📩 Read argument 'logfile': '"$LOGFILE"'" >&2; shift;;
      --manifest) shift; MANIFEST="$1"; echo "📩 Read argument 'manifest': '"$MANIFEST"'" >&2; shift;;
      --no_clean) shift; NO_CLEAN=true; echo "📩 Read argument 'no_clean': '"$NO_CLEAN"'" >&2;;
      --no_update) shift; NO_UPDATE=true; echo "📩 Read argument 'no_update': '"$NO_UPDATE"'" >&2;;
      --dry_run) shift; DRY_RUN=true; echo "📩 Read argument 'dry_run': '"$DRY_RUN"'" >&2;;
      --*) echo "⛔ Unknown option: "$1"" >&2; exit 1;;
      *) echo "⛔ Unexpected argument: "$1"" >&2; exit 1;;
    esac
  done
else
  echo "ℹ️ Script called with no arguments. Read environment variables." >&2
  [ "${DEBUG+defined}" ] && echo "📩 Read argument 'debug': '"$DEBUG"'" >&2
  [ "${INSTALL_SELF+defined}" ] && echo "📩 Read argument 'install_self': '"$INSTALL_SELF"'" >&2
  [ "${INTERACTIVE+defined}" ] && echo "📩 Read argument 'interactive': '"$INTERACTIVE"'" >&2
  [ "${KEEP_REPOS+defined}" ] && echo "📩 Read argument 'keep_repos': '"$KEEP_REPOS"'" >&2
  [ "${LIFECYCLE_HOOK+defined}" ] && echo "📩 Read argument 'lifecycle_hook': '"$LIFECYCLE_HOOK"'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '"$LOGFILE"'" >&2
  [ "${MANIFEST+defined}" ] && echo "📩 Read argument 'manifest': '"$MANIFEST"'" >&2
  [ "${NO_CLEAN+defined}" ] && echo "📩 Read argument 'no_clean': '"$NO_CLEAN"'" >&2
  [ "${NO_UPDATE+defined}" ] && echo "📩 Read argument 'no_update': '"$NO_UPDATE"'" >&2
  [ "${DRY_RUN+defined}" ] && echo "📩 Read argument 'dry_run': '"$DRY_RUN"'" >&2
fi
[[ "$DEBUG" == true ]] && set -x
[ -z "${DEBUG-}" ] && { echo "ℹ️ Argument 'DEBUG' set to default value 'false'." >&2; DEBUG=false; }
[ -z "${INSTALL_SELF-}" ] && { echo "ℹ️ Argument 'INSTALL_SELF' set to default value 'true'." >&2; INSTALL_SELF=true; }
[ -z "${MANIFEST-}" ] && { echo "ℹ️ Argument 'MANIFEST' set to default value ''." >&2; MANIFEST=""; }
if [[ -z "$MANIFEST" && "$INSTALL_SELF" != true ]]; then
    echo "⛔ 'MANIFEST' is required when 'install_self' is false." >&2; exit 1
fi
# Normalize: some environments (e.g. devcontainer CLI build args) serialize
# multi-line strings with literal \n rather than real newlines.  Expand them
# so inline-manifest detection works correctly.
if [[ -n "$MANIFEST" && "$MANIFEST" != *$'\n'* && "$MANIFEST" == *'\n'* ]]; then
    MANIFEST="$(printf '%b' "$MANIFEST")"
    echo "ℹ️  Expanded literal \\n escapes in MANIFEST value." >&2
fi
[ -z "${INTERACTIVE-}" ] && { echo "ℹ️ Argument 'INTERACTIVE' set to default value 'false'." >&2; INTERACTIVE=false; }
[ -z "${KEEP_REPOS-}" ] && { echo "ℹ️ Argument 'KEEP_REPOS' set to default value 'false'." >&2; KEEP_REPOS=false; }
[ -z "${LIFECYCLE_HOOK-}" ] && { echo "ℹ️ Argument 'LIFECYCLE_HOOK' set to default value ''." >&2; LIFECYCLE_HOOK=""; }
if [[ -n "$LIFECYCLE_HOOK" ]]; then
    case "$LIFECYCLE_HOOK" in
        onCreate|updateContent|postCreate) ;;
        *) echo "⛔ Invalid lifecycle_hook value: '$LIFECYCLE_HOOK'. Must be one of: onCreate, updateContent, postCreate." >&2; exit 1;;
    esac
    if [[ -z "$MANIFEST" ]]; then
        echo "⛔ 'manifest' is required when 'lifecycle_hook' is set." >&2; exit 1
    fi
fi
[ -z "${LOGFILE-}" ] && { echo "ℹ️ Argument 'LOGFILE' set to default value ''." >&2; LOGFILE=""; }
[ -z "${NO_CLEAN-}" ] && { echo "ℹ️ Argument 'NO_CLEAN' set to default value 'false'." >&2; NO_CLEAN=false; }
[ -z "${NO_UPDATE-}" ] && { echo "ℹ️ Argument 'NO_UPDATE' set to default value 'false'." >&2; NO_UPDATE=false; }
[ -z "${DRY_RUN-}" ] && { echo "ℹ️ Argument 'DRY_RUN' set to default value 'false'." >&2; DRY_RUN=false; }
[[ "$DRY_RUN" == true ]] && echo "🔍 Dry-run mode enabled — no changes will be made." >&2
[[ "$DRY_RUN" == true ]] || exit_if_not_root
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
# When lifecycle_hook is set, write a hook script and exit without installing.
if [[ -n "$LIFECYCLE_HOOK" ]]; then
    _HOOK_DIR="/usr/local/share/install-os-pkg"
    mkdir -p "$_HOOK_DIR"
    _MANIFEST_ARG="$MANIFEST"
    if [[ "$MANIFEST" == *$'\n'* ]]; then
        printf '%s' "$MANIFEST" > "$_HOOK_DIR/manifest.txt"
        _MANIFEST_ARG="$_HOOK_DIR/manifest.txt"
        echo "ℹ️  Saved inline manifest to '$_MANIFEST_ARG'." >&2
    fi
    _HOOK_OPTS="--manifest $(printf '%q' "$_MANIFEST_ARG")"
    [[ "$DEBUG" == true ]] && _HOOK_OPTS+=" --debug"
    [[ "$INTERACTIVE" == true ]] && _HOOK_OPTS+=" --interactive"
    [[ "$KEEP_REPOS" == true ]] && _HOOK_OPTS+=" --keep_repos"
    [[ -n "$LOGFILE" ]] && _HOOK_OPTS+=" --logfile $(printf '%q' "$LOGFILE")"
    [[ "$NO_CLEAN" == true ]] && _HOOK_OPTS+=" --no_clean"
    [[ "$NO_UPDATE" == true ]] && _HOOK_OPTS+=" --no_update"
    case "$LIFECYCLE_HOOK" in
        onCreate)       _HOOK_FILE="$_HOOK_DIR/on-create.sh" ;;
        updateContent)  _HOOK_FILE="$_HOOK_DIR/update-content.sh" ;;
        postCreate)     _HOOK_FILE="$_HOOK_DIR/post-create.sh" ;;
    esac
    printf '#!/bin/sh\nset -e\nexec bash "%s" %s\n' \
        "/usr/local/lib/install-os-pkg/install.sh" "$_HOOK_OPTS" > "$_HOOK_FILE"
    chmod +x "$_HOOK_FILE"
    echo "✅ Registered lifecycle hook '$LIFECYCLE_HOOK': $_HOOK_FILE" >&2
    exit 0
fi
# Resolve and parse manifest.
_M_PRESCRIPT="" _M_REPO="" _M_KEY="" _M_PKG="" _M_SCRIPT=""
if [[ -n "$MANIFEST" ]]; then
    if [[ "$MANIFEST" == *$'\n'* ]]; then
        _MANIFEST_CONTENT="$MANIFEST"
    elif [[ -f "$MANIFEST" ]]; then
        _MANIFEST_CONTENT="$(<"$MANIFEST")"
    else
        echo "⛔ Manifest file not found: '$MANIFEST'" >&2; exit 1
    fi
    parse_manifest "$_MANIFEST_CONTENT"
    echo "ℹ️  Manifest parsed: $(echo -n "$_M_PRESCRIPT" | wc -l | tr -d ' ') prescript line(s), $(echo -n "$_M_KEY" | wc -l | tr -d ' ') key entry/entries, $(echo -n "$_M_REPO" | wc -l | tr -d ' ') repo line(s), $(echo -n "$_M_PKG" | wc -w | tr -d ' ') pkg(s), $(echo -n "$_M_SCRIPT" | wc -l | tr -d ' ') script line(s)." >&2
fi
if [[ -n "$_M_PRESCRIPT" ]]; then
    echo "🚀 Running manifest prescript." >&2
    _M_PRESCRIPT_TMP="$(mktemp)"
    printf '%s' "$_M_PRESCRIPT" > "$_M_PRESCRIPT_TMP"
    chmod +x "$_M_PRESCRIPT_TMP"
    if [[ "$DRY_RUN" == true ]]; then
        echo "🔍 [dry-run] prescript: $(echo -n "$_M_PRESCRIPT" | wc -l | tr -d ' ') line(s) — would execute:" >&2
        sed 's/^/    /' "$_M_PRESCRIPT_TMP" >&2
    else
        bash "$_M_PRESCRIPT_TMP"
    fi
    rm -f "$_M_PRESCRIPT_TMP"
    echo "✅ Manifest prescript completed." >&2
else
    echo "ℹ️  No prescript found — skipping." >&2
fi
# Ensures a fetch tool (curl or wget) is available, installing curl if neither
# is present.  Sets _FETCH_TOOL to "curl" or "wget".
# Also ensures the CA certificate bundle is present so HTTPS fetches work.
_FETCH_TOOL=""
_CA_CERTS_OK=""
_ensure_ca_certs() {
    [[ -n "${_CA_CERTS_OK:-}" ]] && return 0
    # Check for the standard CA bundle location used by curl and wget.
    if [[ ! -s /etc/ssl/certs/ca-certificates.crt ]]; then
        echo "ℹ️  CA certificate bundle missing — installing ca-certificates." >&2
        "${INSTALL[@]}" ca-certificates
    fi
    _CA_CERTS_OK=true
}
_ensure_fetch_tool() {
    if [[ -z "${_FETCH_TOOL:-}" ]]; then
        if command -v curl > /dev/null 2>&1; then
            _FETCH_TOOL=curl
        elif command -v wget > /dev/null 2>&1; then
            _FETCH_TOOL=wget
        else
            echo "ℹ️  Neither curl nor wget found — installing curl." >&2
            "${INSTALL[@]}" curl
            _FETCH_TOOL=curl
        fi
    fi
    _ensure_ca_certs
}
# _fetch_with_retry <max-attempts> <cmd...>
# Runs <cmd> up to <max-attempts> times with a 3-second pause between failures.
_fetch_with_retry() {
    local _max="$1"; shift
    local _i=1
    while [[ $_i -le $_max ]]; do
        "$@" && return 0
        [[ $_i -lt $_max ]] && echo "⚠️  Fetch attempt $_i/$_max failed — retrying in 3s..." >&2 && sleep 3
        (( _i++ ))
    done
    echo "⛔ Fetch failed after $_max attempt(s)." >&2
    return 1
}
# _fetch_url_stdout <url> — writes response body to stdout, with retries.
_fetch_url_stdout() {
    if [[ "$_FETCH_TOOL" == curl ]]; then
        _fetch_with_retry 3 curl -fsSL "$1"
    else
        _fetch_with_retry 3 wget -qO- "$1"
    fi
}
# _fetch_url_file <url> <dest> — writes response body to file, with retries.
_fetch_url_file() {
    if [[ "$_FETCH_TOOL" == curl ]]; then
        _fetch_with_retry 3 curl -fsSL "$1" -o "$2"
    else
        _fetch_with_retry 3 wget -qO "$2" "$1"
    fi
}
# Ensures gpg is available, installing gnupg/gnupg2 if not.
_ensure_gpg() {
    command -v gpg > /dev/null 2>&1 && return 0
    echo "ℹ️  gpg not found — installing gnupg." >&2
    local _gpg_pkg
    case "$PKG_PREFIX" in
        dnf) _gpg_pkg=gnupg2 ;;
        *)   _gpg_pkg=gnupg  ;;
    esac
    "${INSTALL[@]}" "$_gpg_pkg"
}
# Helper: fetch and install a single signing key.
# Usage: _install_key_entry <url> <dest-path>
# If <dest-path> ends in .gpg the downloaded content is passed through
# gpg --dearmor (ASCII-armored → binary); otherwise it is written as-is.
_install_key_entry() {
    local _url="$1"
    local _dest="$2"
    _ensure_fetch_tool
    mkdir -p "$(dirname "$_dest")"
    if [[ "$_dest" == *.gpg ]]; then
        _ensure_gpg
        echo "🔑 Fetching and dearmoring key → $_dest" >&2
        _fetch_url_stdout "$_url" | gpg --dearmor -o "$_dest"
    else
        echo "🔑 Fetching key → $_dest" >&2
        _fetch_url_file "$_url" "$_dest"
    fi
    chmod 0644 "$_dest"
}
if [[ -n "$_M_KEY" ]]; then
    echo "🔑 Installing signing keys." >&2
    # Use an isolated GNUPGHOME so gpg --dearmor does not create trust-database
    # artefacts under /root/.gnupg and pollute the container image layer.
    _KEY_GNUPGHOME="$(mktemp -d)"
    chmod 700 "$_KEY_GNUPGHOME"
    if [[ "$DRY_RUN" == true ]]; then
        echo "🔍 [dry-run] key: $(echo -n "$_M_KEY" | wc -l | tr -d ' ') entry/entries — would fetch:" >&2
        while IFS= read -r _kline || [[ -n "$_kline" ]]; do
            [[ -z "${_kline:-}" ]] && continue
            _kurl="${_kline%% *}"
            _kdest="${_kline#* }"
            echo "    $_kurl → $_kdest" >&2
        done <<< "$_M_KEY"
    else
        export GNUPGHOME="$_KEY_GNUPGHOME"
        while IFS= read -r _kline || [[ -n "$_kline" ]]; do
            [[ -z "${_kline:-}" ]] && continue
            _kurl="${_kline%% *}"
            _kdest="${_kline#* }"
            _install_key_entry "$_kurl" "$_kdest"
        done <<< "$_M_KEY"
        unset GNUPGHOME
    fi
    rm -rf "$_KEY_GNUPGHOME"
    echo "✅ Signing keys installed." >&2
else
    echo "ℹ️  No key entries found — skipping." >&2
fi
REPO_ADDED=false
APK_ADDED_REPOS=()
# Helper: install a single repo blob (string) for the detected ecosystem.
_install_repo_content() {
    local _content="$1"
    local _tmpfile
    if [[ "$PKG_PREFIX" = "apt" ]]; then
        printf '%s' "$_content" >> /etc/apt/sources.list.d/syspkg-installer.list
        echo "📄 Appended to /etc/apt/sources.list.d/syspkg-installer.list" >&2
    elif [[ "$PKG_PREFIX" = "apk" ]]; then
        local _rline
        while IFS= read -r _rline; do
            [[ -z "${_rline:-}" || "${_rline}" =~ ^[[:space:]]*# ]] && continue
            echo "$_rline" >> /etc/apk/repositories
            APK_ADDED_REPOS+=("$_rline")
            echo "📄 Added APK repo: ${_rline}" >&2
        done <<< "$_content"
    elif [[ "$PKG_PREFIX" = "dnf" ]]; then
        printf '%s' "$_content" >> /etc/yum.repos.d/syspkg-installer.repo
        echo "📄 Appended to /etc/yum.repos.d/syspkg-installer.repo" >&2
    elif [[ "$PKG_PREFIX" = "zypper" ]]; then
        printf '%s' "$_content" >> /etc/zypp/repos.d/syspkg-installer.repo
        echo "📄 Appended to /etc/zypp/repos.d/syspkg-installer.repo" >&2
    elif [[ "$PKG_PREFIX" = "pacman" ]]; then
        mkdir -p /etc/pacman.d
        printf '%s' "$_content" >> /etc/pacman.d/syspkg-installer.conf
        grep -qxF 'Include = /etc/pacman.d/syspkg-installer.conf' /etc/pacman.conf \
          || echo "Include = /etc/pacman.d/syspkg-installer.conf" >> /etc/pacman.conf
        echo "📄 Written to /etc/pacman.d/syspkg-installer.conf" >&2
    fi
}
if [[ -n "$_M_REPO" ]]; then
    echo "🗃  Adding repositories." >&2
    echo "📂 From manifest repo section." >&2
    if [[ "$DRY_RUN" == true ]]; then
        echo "🔍 [dry-run] repo: $(echo -n "$_M_REPO" | wc -l | tr -d ' ') line(s) — would add to package manager repos." >&2
    else
        _install_repo_content "$_M_REPO"
        REPO_ADDED=true
    fi
else
    echo "ℹ️  No repo content found — skipping." >&2
fi
if [[ "$PKG_MNGR" = "apt-get" && "$INTERACTIVE" == false ]]; then
    echo "🆗 Setting APT to non-interactive mode." >&2
    export DEBIAN_FRONTEND=noninteractive
fi
if [[ -n "$_M_PKG" && "$NO_UPDATE" == false ]]; then
    if [[ ${#UPDATE[@]} -gt 0 ]]; then
        echo "🔄 Updating package lists." >&2
        if [[ "$DRY_RUN" == true ]]; then
            echo "🔍 [dry-run] update: would run: ${UPDATE[*]}" >&2
        elif [[ "$PKG_MNGR" = "dnf" || "$PKG_MNGR" = "yum" ]]; then
            "${UPDATE[@]}" || [[ $? -eq 100 ]]
        else
            "${UPDATE[@]}"
        fi
        echo "✅ Package lists updated." >&2
    else
        echo "ℹ️  Package list update not supported by '${PKG_MNGR}' — skipping." >&2
    fi
elif [[ -z "$_M_PKG" ]]; then
    echo "ℹ️  Package list update skipped (no packages in manifest)." >&2
else
    echo "ℹ️  Package list update skipped (--no_update)." >&2
fi
PACKAGES=()
if [[ -n "$_M_PKG" ]]; then
    while IFS= read -r _mpkg || [[ -n "$_mpkg" ]]; do
        [[ -n "$_mpkg" ]] && PACKAGES+=("$_mpkg")
    done <<< "$_M_PKG"
fi
if [[ ${#PACKAGES[@]} -eq 0 ]]; then
    echo "ℹ️  No packages to install — skipping." >&2
else
    echo "📦 Installing ${#PACKAGES[@]} package(s)." >&2
    if [[ "$DRY_RUN" == true ]]; then
        echo "🔍 [dry-run] packages (${#PACKAGES[@]}): ${PACKAGES[*]}" >&2
    else
        install "${PACKAGES[@]}"
    fi
fi
if [[ -n "$_M_SCRIPT" ]]; then
    echo "🚀 Running manifest script." >&2
    _M_SCRIPT_TMP="$(mktemp)"
    printf '%s' "$_M_SCRIPT" > "$_M_SCRIPT_TMP"
    chmod +x "$_M_SCRIPT_TMP"
    if [[ "$DRY_RUN" == true ]]; then
        echo "🔍 [dry-run] script: $(echo -n "$_M_SCRIPT" | wc -l | tr -d ' ') line(s) — would execute:" >&2
        sed 's/^/    /' "$_M_SCRIPT_TMP" >&2
    else
        bash "$_M_SCRIPT_TMP"
    fi
    rm -f "$_M_SCRIPT_TMP"
    echo "✅ Manifest script completed." >&2
else
    echo "ℹ️  No script found — skipping." >&2
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
if [[ "$DRY_RUN" == true ]]; then
    echo "🔍 [dry-run] cache clean: would run ${CLEAN[*]}" >&2
elif [[ "$NO_CLEAN" == false ]]; then
    echo "🧹 Cleaning package manager cache." >&2
    "${CLEAN[@]}"
else
    echo "ℹ️  Cache cleanup skipped (--no_clean)." >&2
fi
echo "✅ Package installation complete."
echo "↩️ Script exit: System Package Installation" >&2
