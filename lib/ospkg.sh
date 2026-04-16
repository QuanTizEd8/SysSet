#!/usr/bin/env bash
# This file must be sourced from bash (>=4.0), not sh.
# Do not edit _lib/ copies directly — edit lib/ instead.

[[ -n "${_OSPKG__LIB_LOADED-}" ]] && return 0
_OSPKG__LIB_LOADED=1

_OSPKG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/os.sh
. "$_OSPKG_LIB_DIR/os.sh"
# shellcheck source=lib/net.sh
. "$_OSPKG_LIB_DIR/net.sh"
# shellcheck source=lib/logging.sh
. "$_OSPKG_LIB_DIR/logging.sh"

# ── Internal state ────────────────────────────────────────────────────────────
_OSPKG_DETECTED=false
_OSPKG_PKG_MNGR=
_OSPKG_PREFIX=
_OSPKG_INSTALL=()
_OSPKG_UPDATE=()
_OSPKG_CLEAN=
_OSPKG_LISTS_PATH=
_OSPKG_LISTS_PATTERN=
_OSPKG_PREFER_LINUXBREW=false
_OSPKG_YQ_BIN=
declare -A _OSPKG_OS_RELEASE=()

# ── Private: clean functions ──────────────────────────────────────────────────
_ospkg_clean_apk() {
  rm -rf /var/cache/apk/*
  return 0
}
_ospkg_clean_apt() {
  apt-get clean
  # apt-get dist-clean is an APT 3.x command that removes /var/lib/apt/lists/*
  # while preserving the Release/InRelease files for security.
  # Docs: https://manpages.debian.org/unstable/apt/apt-get.8.en.html#distclean
  # Fall back to rm -rf on older APT (2.x and below) where the command does not exist.
  apt-get dist-clean 2> /dev/null || rm -rf /var/lib/apt/lists/*
  return 0
}
_ospkg_clean_dnf() {
  "${_OSPKG_INSTALL[0]%% *}" clean all 2> /dev/null || "$_OSPKG_PKG_MNGR" clean all
  rm -rf /var/cache/dnf/* /var/cache/yum/*
  return 0
}
_ospkg_clean_pacman() {
  pacman -Scc --noconfirm
  return 0
}
_ospkg_clean_zypper() {
  zypper clean --all
  return 0
}
_ospkg_clean_brew() {
  _ospkg_brew_run cleanup --prune=all 2> /dev/null || true
  return 0
}

# _ospkg_update_cmd: wraps _OSPKG_UPDATE for use with net__fetch_with_retry.
# Normalises dnf/yum exit code 100 ("updates available") to 0.
_ospkg_update_cmd() {
  "${_OSPKG_UPDATE[@]}" >&2
  local _rc=$?
  [[ "$_OSPKG_PKG_MNGR" == "dnf" || "$_OSPKG_PKG_MNGR" == "yum" ]] \
    && [[ $_rc -eq 100 ]] && return 0
  return $_rc
}

# ── Private: key / repo helpers ──────────────────────────────────────────────
_ospkg_ensure_gpg() {
  command -v gpg > /dev/null 2>&1 && return 0
  echo "ℹ️  gpg not found — installing gnupg." >&2
  local _gpg_pkg
  case "$_OSPKG_PREFIX" in
    dnf) _gpg_pkg=gnupg2 ;;
    *) _gpg_pkg=gnupg ;;
  esac
  "${_OSPKG_INSTALL[@]}" "$_gpg_pkg"
  return 0
}

# _ospkg_install_key_entry <url> <dest>
_ospkg_install_key_entry() {
  local _url="$1"
  local _dest="$2"
  mkdir -p "$(dirname "$_dest")"
  if [[ "$_dest" == *.gpg ]]; then
    _ospkg_ensure_gpg
    echo "🔑 Fetching and dearmoring key → $_dest" >&2
    net__fetch_url_stdout "$_url" | gpg --dearmor -o "$_dest"
  else
    echo "🔑 Fetching key → $_dest" >&2
    net__fetch_url_file "$_url" "$_dest"
  fi
  chmod 0644 "$_dest"
  return 0
}

# _ospkg_install_repo_content <content>
_ospkg_install_repo_content() {
  local _content="$1"
  if [[ "$_OSPKG_PREFIX" = "apt" ]]; then
    printf '%s' "$_content" >> /etc/apt/sources.list.d/syspkg-installer.list
    echo "📄 Appended to /etc/apt/sources.list.d/syspkg-installer.list" >&2
  elif [[ "$_OSPKG_PREFIX" = "apk" ]]; then
    local _rline
    while IFS= read -r _rline; do
      [[ -z "${_rline:-}" || "${_rline}" =~ ^[[:space:]]*# ]] && continue
      echo "$_rline" >> /etc/apk/repositories
      _OSPKG_APK_ADDED_REPOS+=("$_rline")
      echo "📄 Added APK repo: ${_rline}" >&2
    done <<< "$_content"
  elif [[ "$_OSPKG_PREFIX" = "dnf" ]]; then
    printf '%s' "$_content" >> /etc/yum.repos.d/syspkg-installer.repo
    echo "📄 Appended to /etc/yum.repos.d/syspkg-installer.repo" >&2
  elif [[ "$_OSPKG_PREFIX" = "zypper" ]]; then
    printf '%s' "$_content" >> /etc/zypp/repos.d/syspkg-installer.repo
    echo "📄 Appended to /etc/zypp/repos.d/syspkg-installer.repo" >&2
  elif [[ "$_OSPKG_PREFIX" = "pacman" ]]; then
    mkdir -p /etc/pacman.d
    printf '%s' "$_content" >> /etc/pacman.d/syspkg-installer.conf
    grep -qxF 'Include = /etc/pacman.d/syspkg-installer.conf' /etc/pacman.conf ||
      echo "Include = /etc/pacman.d/syspkg-installer.conf" >> /etc/pacman.conf
    echo "📄 Written to /etc/pacman.d/syspkg-installer.conf" >&2
  fi
  return 0
}

# ── Private: brew user/root handling ─────────────────────────────────────────
# _ospkg_brew_run <args...>
# Runs brew with proper user context, handling the root restriction.
#   Non-root           → run directly
#   Root in container  → run directly (brew explicitly allows this)
#   Root on bare metal → su to brew prefix owner
_ospkg_brew_run() {
  if [[ "$(id -u)" -ne 0 ]]; then
    brew "$@"
    return
  fi
  if os__is_container; then
    brew "$@"
    return
  fi
  # Bare-metal root: su to the owner of the Homebrew prefix.
  local _prefix _owner
  _prefix="$(brew --prefix 2> /dev/null)" || {
    echo "⛔ Could not determine Homebrew prefix." >&2
    return 1
  }
  _owner="$(stat -f '%Su' "$_prefix" 2> /dev/null || stat -c '%U' "$_prefix" 2> /dev/null)"
  if [[ -z "${_owner:-}" || "$_owner" == "root" ]]; then
    brew "$@"
    return
  fi
  echo "ℹ️  Running brew as user '${_owner}' (brew prefix owner)." >&2
  # shellcheck disable=SC2046
  su -l "$_owner" -c "$(printf 'brew %s' "$(printf '%q ' "$@")")"
  return 0
}

# ── Private: yq auto-installer ────────────────────────────────────────────────
# _ospkg_ensure_yq
# Ensures mikefarah/yq is available.  Sets _OSPKG_YQ_BIN.
# If a compatible yq is already in PATH it is reused; otherwise attempts to
# install from the package manager, then falls back to downloading from GitHub
# Releases if the package manager provides an incompatible or no yq.
# The download is verified against the release checksums file before the binary
# is marked executable.
_ospkg_ensure_yq() {
  [[ -n "${_OSPKG_YQ_BIN:-}" ]] && return 0
  # Accept any yq in PATH that understands the -o=json flag (mikefarah/yq).
  if command -v yq > /dev/null 2>&1 && yq -o=json '.' /dev/null > /dev/null 2>&1; then
    _OSPKG_YQ_BIN="yq"
    echo "ℹ️  yq already available: $(command -v yq)" >&2
    return 0
  fi
  # If yq is not in PATH at all, try installing from the package manager.
  # Modern distros (Ubuntu ≥22.04, Debian ≥12, Alpine ≥3.16) package mikefarah/yq.
  # Older distros package kislyuk/yq (incompatible) or nothing at all.
  if ! command -v yq > /dev/null 2>&1; then
    echo "ℹ️  yq not found — attempting package manager install." >&2
    ospkg__update >&2 || true
    ospkg__install yq >&2 || true
    # Re-test after potential install.
    if command -v yq > /dev/null 2>&1 && yq -o=json '.' /dev/null > /dev/null 2>&1; then
      _OSPKG_YQ_BIN="yq"
      echo "ℹ️  yq installed from package manager: $(command -v yq)" >&2
      return 0
    fi
  fi
  # Package manager provided no yq or an incompatible one; fetch mikefarah/yq
  # from GitHub Releases using the stable /releases/latest/download/ redirect
  # URLs.  These bypass the GitHub API entirely, avoiding rate-limit failures
  # in Docker builds that run without a GITHUB_TOKEN.
  # shellcheck source=lib/checksum.sh
  . "$_OSPKG_LIB_DIR/checksum.sh"
  local _os _arch _yq_base _url _yq_dir _dest _expected_hash
  _os="$(os__kernel | tr '[:upper:]' '[:lower:]')" # linux | darwin
  _arch="$(os__arch)"
  case "$_arch" in
    x86_64) _arch="amd64" ;;
    aarch64 | arm64) _arch="arm64" ;;
    *)
      echo "⛔ yq: unsupported architecture '${_arch}'." >&2
      return 1
      ;;
  esac
  _yq_base="https://github.com/mikefarah/yq/releases/latest/download"
  _url="${_yq_base}/yq_${_os}_${_arch}"
  _yq_dir="$(logging__tmpdir "ospkg/yq")"
  _dest="${_yq_dir}/yq"
  echo "ℹ️  Downloading yq (${_os}/${_arch}) from GitHub Releases." >&2
  net__fetch_url_file "$_url" "$_dest"
  net__fetch_url_file "${_yq_base}/checksums" "${_yq_dir}/checksums"
  net__fetch_url_file "${_yq_base}/checksums_hashes_order" "${_yq_dir}/checksums_hashes_order"
  net__fetch_url_file "${_yq_base}/extract-checksum.sh" "${_yq_dir}/extract-checksum.sh"
  _expected_hash="$(cd "${_yq_dir}" && bash extract-checksum.sh SHA-256 "yq_${_os}_${_arch}" | awk '{print $2}')"
  # Guard against CDN soft errors: a lying CDN may return HTTP 200 with an
  # error-page body, making curl exit 0 but producing garbage content.
  # A valid SHA-256 hash is exactly 64 lowercase hex characters.
  if [[ ! "${_expected_hash:-}" =~ ^[0-9a-f]{64}$ ]]; then
    echo "⛔ yq: extracted checksum is not a valid SHA-256 hash (got: '${_expected_hash:-<empty>}') — a download may have been corrupted by a CDN error page." >&2
    return 1
  fi
  if ! checksum__verify_sha256 "$_dest" "$_expected_hash"; then
    echo "⛔ yq: checksum verification failed — aborting." >&2
    return 1
  fi
  chmod +x "$_dest"
  _OSPKG_YQ_BIN="$_dest"
  echo "✅ yq downloaded to ${_dest}." >&2
  return 0
}

# ── Private: PM configuration helpers ────────────────────────────────────────
# Each _ospkg_set_* function configures the internal state for one PM family.
# Called only from ospkg__detect().

_ospkg_set_apt() {
  echo "🛠️  Detected ecosystem: APT (tool: apt-get)" >&2
  _OSPKG_PREFIX="apt"
  _OSPKG_PKG_MNGR="apt-get"
  _OSPKG_UPDATE=(apt-get update)
  _OSPKG_INSTALL=(apt-get -y install --no-install-recommends)
  _OSPKG_CLEAN=_ospkg_clean_apt
  _OSPKG_LISTS_PATH="/var/lib/apt/lists"
  _OSPKG_LISTS_PATTERN="*_Packages*"
  _OSPKG_OS_RELEASE[pm]="apt"
  return 0
}

_ospkg_set_apk() {
  echo "🛠️  Detected ecosystem: APK (tool: apk)" >&2
  _OSPKG_PREFIX="apk"
  _OSPKG_PKG_MNGR="apk"
  _OSPKG_UPDATE=(apk update)
  _OSPKG_INSTALL=(apk add --no-cache)
  _OSPKG_CLEAN=_ospkg_clean_apk
  _OSPKG_LISTS_PATH="/var/cache/apk"
  _OSPKG_LISTS_PATTERN="APKINDEX*"
  _OSPKG_OS_RELEASE[pm]="apk"
  return 0
}

_ospkg_set_dnf() {
  echo "🛠️  Detected ecosystem: DNF (tool: dnf)" >&2
  _OSPKG_PREFIX="dnf"
  _OSPKG_PKG_MNGR="dnf"
  _OSPKG_UPDATE=(dnf check-update)
  _OSPKG_INSTALL=(dnf -y install)
  _OSPKG_CLEAN=_ospkg_clean_dnf
  _OSPKG_LISTS_PATH="/var/cache/dnf"
  _OSPKG_LISTS_PATTERN="*"
  _OSPKG_OS_RELEASE[pm]="dnf"
  return 0
}

_ospkg_set_microdnf() {
  echo "🛠️  Detected ecosystem: DNF (tool: microdnf)" >&2
  _OSPKG_PREFIX="dnf"
  _OSPKG_PKG_MNGR="microdnf"
  _OSPKG_UPDATE=()
  _OSPKG_INSTALL=(microdnf -y install --refresh --best --nodocs --noplugins --setopt=install_weak_deps=0)
  _OSPKG_CLEAN=_ospkg_clean_dnf
  _OSPKG_LISTS_PATH=""
  _OSPKG_LISTS_PATTERN=""
  _OSPKG_OS_RELEASE[pm]="dnf"
  return 0
}

_ospkg_set_yum() {
  echo "🛠️  Detected ecosystem: YUM (tool: yum)" >&2
  _OSPKG_PREFIX="dnf"
  _OSPKG_PKG_MNGR="yum"
  _OSPKG_UPDATE=(yum check-update)
  _OSPKG_INSTALL=(yum -y install)
  _OSPKG_CLEAN=_ospkg_clean_dnf
  _OSPKG_LISTS_PATH="/var/cache/yum"
  _OSPKG_LISTS_PATTERN="*"
  _OSPKG_OS_RELEASE[pm]="yum"
  return 0
}

_ospkg_set_zypper() {
  echo "🛠️  Detected ecosystem: Zypper (tool: zypper)" >&2
  _OSPKG_PREFIX="zypper"
  _OSPKG_PKG_MNGR="zypper"
  _OSPKG_UPDATE=(zypper --non-interactive refresh)
  _OSPKG_INSTALL=(zypper --non-interactive install)
  _OSPKG_CLEAN=_ospkg_clean_zypper
  _OSPKG_LISTS_PATH="/var/cache/zypp/raw"
  _OSPKG_LISTS_PATTERN="*"
  _OSPKG_OS_RELEASE[pm]="zypper"
  return 0
}

_ospkg_set_pacman() {
  echo "🛠️  Detected ecosystem: Pacman (tool: pacman)" >&2
  _OSPKG_PREFIX="pacman"
  _OSPKG_PKG_MNGR="pacman"
  _OSPKG_UPDATE=(pacman -Sy --noconfirm)
  _OSPKG_INSTALL=(pacman -S --noconfirm --needed)
  _OSPKG_CLEAN=_ospkg_clean_pacman
  _OSPKG_LISTS_PATH="/var/lib/pacman/sync"
  _OSPKG_LISTS_PATTERN="*.db"
  _OSPKG_OS_RELEASE[pm]="pacman"
  return 0
}

_ospkg_set_brew() {
  local _label="${1:-Linux}"
  echo "🛠️  Detected ecosystem: Homebrew (tool: brew) [${_label}]" >&2
  _OSPKG_PREFIX="brew"
  _OSPKG_PKG_MNGR="brew"
  _OSPKG_UPDATE=(_ospkg_brew_run update)
  _OSPKG_INSTALL=(_ospkg_brew_run install)
  _OSPKG_CLEAN=_ospkg_clean_brew
  _OSPKG_LISTS_PATH=""
  _OSPKG_LISTS_PATTERN=""
  _OSPKG_OS_RELEASE[pm]="brew"
  return 0
}

# _ospkg_load_linux_release
# Parses /etc/os-release into _OSPKG_OS_RELEASE (merges; does not overwrite pm).
_ospkg_load_linux_release() {
  if [[ -f /etc/os-release ]]; then
    local _key _val
    while IFS='=' read -r _key _val; do
      [[ -z "${_key-}" || "$_key" =~ ^# ]] && continue
      _val="${_val#\"}"
      _val="${_val%\"}"
      _val="${_val#\'}"
      _val="${_val%\'}"
      [[ "$_key" == "pm" ]] && continue # never overwrite pm
      _OSPKG_OS_RELEASE["${_key,,}"]="$_val"
    done < /etc/os-release
  fi
  _OSPKG_OS_RELEASE[kernel]="linux"
  _OSPKG_OS_RELEASE[arch]="$(uname -m)"
  echo "🔍 OS context: pm=${_OSPKG_OS_RELEASE[pm]-} arch=${_OSPKG_OS_RELEASE[arch]-} id=${_OSPKG_OS_RELEASE[id]-} id_like=${_OSPKG_OS_RELEASE[id_like]-} version_id=${_OSPKG_OS_RELEASE[version_id]-} version_codename=${_OSPKG_OS_RELEASE[version_codename]-}" >&2
  return 0
}

# ── Public: ospkg__detect ────────────────────────────────────────────────────
# Idempotent: detects the package manager and populates _OSPKG_* state.
# Respects _OSPKG_PREFER_LINUXBREW: when true, brew is checked before the
# native Linux PM chain (no effect on macOS where brew is always used).
ospkg__detect() {
  [[ "$_OSPKG_DETECTED" == true ]] && return 0

  local _kernel
  _kernel="$(uname -s)"

  if [[ "$_kernel" == "Darwin" ]]; then
    # macOS: Homebrew is the only supported package manager.
    if ! type brew > /dev/null 2>&1; then
      echo "⛔ Homebrew (brew) not found on macOS." >&2
      echo "⛔ Install Homebrew first: https://brew.sh" >&2
      echo "⛔ Or add the 'install-homebrew' devcontainer feature." >&2
      return 1
    fi
    _ospkg_set_brew "macOS"
    _OSPKG_OS_RELEASE[kernel]="darwin"
    _OSPKG_OS_RELEASE[id]="macos"
    _OSPKG_OS_RELEASE[id_like]="macos"
    _OSPKG_OS_RELEASE[version_id]="$(sw_vers -productVersion 2> /dev/null || echo "")"
    _OSPKG_OS_RELEASE[arch]="$(uname -m)"
    echo "🔍 OS context: pm=brew arch=${_OSPKG_OS_RELEASE[arch]-} id=macos version_id=${_OSPKG_OS_RELEASE[version_id]-}" >&2
    _OSPKG_DETECTED=true
    return 0
  fi

  # Linux: optionally prefer Linuxbrew before the native PM chain.
  if [[ "${_OSPKG_PREFER_LINUXBREW:-false}" == "true" ]] && type brew > /dev/null 2>&1; then
    _ospkg_set_brew "Linux/Linuxbrew"
    _ospkg_load_linux_release
    _OSPKG_DETECTED=true
    return 0
  fi

  # Linux: standard native PM detection chain.
  if type apt-get > /dev/null 2>&1; then
    _ospkg_set_apt
  elif type apk > /dev/null 2>&1; then
    _ospkg_set_apk
  elif type dnf > /dev/null 2>&1; then
    _ospkg_set_dnf
  elif type microdnf > /dev/null 2>&1; then
    _ospkg_set_microdnf
  elif type yum > /dev/null 2>&1; then
    _ospkg_set_yum
  elif type zypper > /dev/null 2>&1; then
    _ospkg_set_zypper
  elif type pacman > /dev/null 2>&1; then
    _ospkg_set_pacman
  elif type brew > /dev/null 2>&1; then
    _ospkg_set_brew "Linux/Linuxbrew"
  else
    echo "⛔ No supported package manager found." >&2
    return 1
  fi

  _ospkg_load_linux_release
  _OSPKG_DETECTED=true
  return 0
}

# ── Public: ospkg__update ────────────────────────────────────────────────────
# Usage: ospkg__update [--force] [--lists_max_age <N>] [--repo_added]
# Runs the package index update, optionally skipping if lists are fresh.
ospkg__update() {
  ospkg__detect
  local _force=false _max_age=300 _repo_added=false
  while [[ $# -gt 0 ]]; do
    case $1 in
      --force)
        shift
        _force=true
        ;;
      --lists_max_age)
        shift
        _max_age="$1"
        shift
        ;;
      --repo_added)
        shift
        _repo_added=true
        ;;
      *)
        echo "⛔ ospkg__update: unknown option: $1" >&2
        return 1
        ;;
    esac
  done

  if [[ ${#_OSPKG_UPDATE[@]} -eq 0 ]]; then
    echo "ℹ️  Package list update not supported by '${_OSPKG_PKG_MNGR}' — skipping." >&2
    return 0
  fi

  local _skip=false
  if [[ "$_force" == true || "$_repo_added" == true ]]; then
    _skip=false
  elif [[ "$_OSPKG_PKG_MNGR" == "brew" ]]; then
    # brew: no simple lists age check — always update unless forced off.
    _skip=false
  elif [[ -n "${_OSPKG_LISTS_PATH:-}" && -d "$_OSPKG_LISTS_PATH" ]]; then
    if [[ -n "$(find "$_OSPKG_LISTS_PATH" -mindepth 1 -maxdepth 2 -name "${_OSPKG_LISTS_PATTERN:-*}" 2> /dev/null | head -1)" ]]; then
      local _mtime _age
      # stat -c (Linux) or stat -f (macOS)
      _mtime=$(stat -c %Y "$_OSPKG_LISTS_PATH" 2> /dev/null || stat -f %m "$_OSPKG_LISTS_PATH" 2> /dev/null || echo 0)
      _age=$(($(date +%s) - _mtime))
      if [[ $_age -lt $_max_age ]]; then
        _skip=true
        echo "ℹ️  Package lists refreshed ${_age}s ago — skipping update (threshold: ${_max_age}s)." >&2
      fi
    fi
  fi

  if [[ "$_skip" == false ]]; then
    echo "🔄 Updating package lists." >&2
    net__fetch_with_retry _ospkg_update_cmd
    echo "✅ Package lists updated." >&2
  fi
  return 0
}

# ── Public: ospkg__install ───────────────────────────────────────────────────
# Usage: ospkg__install <pkg>...
# Installs packages, with idempotency check for apt and dnf.
ospkg__install() {
  ospkg__detect
  if [[ "$_OSPKG_PKG_MNGR" == "brew" ]]; then
    echo "📲 Installing packages:" >&2
    printf '  - %s\n' "$@" >&2
    net__fetch_with_retry _ospkg_brew_run install "$@" >&2
    return 0
  fi
  if [[ "$_OSPKG_PKG_MNGR" = "apt-get" ]]; then
    if dpkg -s "$@" > /dev/null 2>&1; then
      echo "ℹ️  Packages already installed: $*" >&2
      return 0
    fi
  elif [[ "$_OSPKG_PKG_MNGR" = "dnf" || "$_OSPKG_PKG_MNGR" = "yum" ]]; then
    local _num_pkgs=$#
    local _num_installed
    _num_installed=$("$_OSPKG_PKG_MNGR" -C list installed "$@" 2> /dev/null | sed '1,/^Installed/d' | wc -l) || _num_installed=0
    if [[ $_num_pkgs -eq $_num_installed ]]; then
      echo "ℹ️  Packages already installed: $*" >&2
      return 0
    fi
  fi
  echo "📲 Installing packages:" >&2
  printf '  - %s\n' "$@" >&2
  net__fetch_with_retry "${_OSPKG_INSTALL[@]}" "$@" >&2
  return 0
}

# ── Public: ospkg__clean ─────────────────────────────────────────────────────
ospkg__clean() {
  ospkg__detect
  echo "🧹 Cleaning package manager cache." >&2
  "$_OSPKG_CLEAN"
  return 0
}

# ── Public: ospkg__parse_manifest_yaml ───────────────────────────────────────
# Usage: ospkg__parse_manifest_yaml <json-file>
# Parses a JSON manifest (pre-converted from YAML via yq) and emits a stream
# of newline-delimited compact JSON records to stdout, each with a "kind" field.
# Requires: jq in PATH; _OSPKG_OS_RELEASE populated by ospkg__detect.
#
# Output record kinds:
#   prescript   {kind,content}
#   key         {kind,url,dest,dearmor}
#   repo        {kind,content}
#   ppa         {kind,ppa}           — APT only
#   tap         {kind,tap}           — brew (string or {name,url})
#   copr        {kind,copr}          — dnf only
#   module      {kind,module}        — dnf only
#   group       {kind,group}
#   package     {kind,name,flags,version}
#   cask        {kind,cask}          — brew (macOS) only
#   script      {kind,content}
ospkg__parse_manifest_yaml() {
  local _json_file="$1"

  # Build a full JSON context object from _OSPKG_OS_RELEASE so that every
  # /etc/os-release key (including version_codename, pretty_name, etc.) plus
  # the synthetic keys (pm, arch, kernel) is available in `when` clauses.
  local _ctx_json _k
  _ctx_json="$(
    for _k in "${!_OSPKG_OS_RELEASE[@]}"; do
      printf '%s\n' "$_k" "${_OSPKG_OS_RELEASE[$_k]}"
    done | jq -Rn '[inputs] | [range(0; length; 2) as $i | {key: .[$i], value: .[$i + 1]}] | from_entries'
  )"

  local _pm="${_OSPKG_OS_RELEASE[pm]:-${_OSPKG_PREFIX}}"

  jq -c \
    --argjson ctx "$_ctx_json" \
    --arg pm "$_pm" \
    '
# ── Helper definitions ────────────────────────────────────────────────────────
def ic: ascii_downcase;
def ctx: $ctx;

def cond_matches(c):
  to_entries | all(
    .key as $k | .value as $v |
    (c[$k] // "") | ic as $actual |
    if ($v | type) == "array" then [($v[] | ic)] | any(. == $actual)
    else ($v | ic) == $actual
    end
  );

def when_matches:
  if has("when") | not then true
  elif .when == null then true
  elif (.when | type) == "array" then [.when[] | cond_matches(ctx)] | any
  elif (.when | type) == "object" then .when | cond_matches(ctx)
  else false
  end;

def to_lines: if type == "array" then join("\n") else . end;

def merge_flags(gf; pf):
  if   gf == null and pf == null then null
  elif gf == null then pf
  elif pf == null then gf
  else [(gf | if type == "array" then .[] else . end),
        (pf | if type == "array" then .[] else . end)] | join(" ")
  end;

# visit(k; inherited_flags): traverse packages array, emitting items of kind k.
def visit(k; gf):
  if type == "string" then
    if k == "package" then
      {kind: "package", name: ., flags: gf, version: null}
    else empty end
  elif has("packages") then
    # group object
    if when_matches then
      . as $g |
      merge_flags(gf; ($g.flags // null)) as $mf |
      if k == "prescript" then
        (if $g | has("prescript") then
          {kind: "prescript", content: ($g.prescript | to_lines)} else empty end),
        ($g.packages[] | visit(k; $mf))
      elif k == "key" then
        (if $g | has("keys") then
          $g.keys[] | {kind: "key", url: .url, dest: .dest, dearmor: (.dearmor // null)}
        else empty end),
        ($g.packages[] | visit(k; $mf))
      elif k == "repo" then
        (if $g | has("repos") then $g.repos[] | {kind: "repo", content: .} else empty end),
        ($g.packages[] | visit(k; $mf))
      elif k == "package" then
        ($g.packages[] | visit(k; $mf))
      elif k == "script" then
        ($g.packages[] | visit(k; $mf)),
        (if $g | has("script") then
          {kind: "script", content: ($g.script | to_lines)} else empty end)
      else
        ($g.packages[] | visit(k; $mf))
      end
    else empty
    end
  else
    # package object
    if when_matches then
      . as $e |
      if k == "prescript" then
        if $e | has("prescript") then
          {kind: "prescript", content: ($e.prescript | to_lines)}
        else empty end
      elif k == "key" then
        if $e | has("keys") then
          $e.keys[] | {kind: "key", url: .url, dest: .dest, dearmor: (.dearmor // null)}
        else empty end
      elif k == "repo" then
        if $e | has("repos") then $e.repos[] | {kind: "repo", content: .} else empty end
      elif k == "package" then
        {kind: "package",
         name: (($e[$pm] // $e.name) // null),
         flags: merge_flags(gf; ($e.flags // null)),
         version: ($e.version // null)}
      elif k == "script" then
        if $e | has("script") then
          {kind: "script", content: ($e.script | to_lines)}
        else empty end
      else empty
      end
    else empty
    end
  end;

# ── Emit items in pipeline phase order ────────────────────────────────────────
. as $doc |

# Top-level when: skip entire manifest if it does not match.
if ($doc | has("when")) and (($doc | when_matches) | not) then
  empty
else

# Phase: PRESCRIPTS — top-level, then inline
(if $doc | has("prescripts") then
  {kind: "prescript", content: ($doc.prescripts | to_lines)} else empty end),
(if $doc | has("packages") then
  $doc.packages[] | visit("prescript"; null) else empty end),

# Phase: KEYS — top-level, PM block, then inline
(if $doc | has("keys") then
  $doc.keys[] | {kind: "key", url: .url, dest: .dest, dearmor: (.dearmor // null)}
else empty end),
(if ($doc | has($pm)) and ($doc[$pm] | has("keys")) then
  $doc[$pm].keys[] | {kind: "key", url: .url, dest: .dest, dearmor: (.dearmor // null)}
else empty end),
(if $doc | has("packages") then
  $doc.packages[] | visit("key"; null) else empty end),

# Phase: REPOS — top-level, PM block, then inline
(if $doc | has("repos") then
  $doc.repos[] | {kind: "repo", content: .}
else empty end),
(if ($doc | has($pm)) and ($doc[$pm] | has("repos")) then
  $doc[$pm].repos[] | {kind: "repo", content: .}
else empty end),
(if $doc | has("packages") then
  $doc.packages[] | visit("repo"; null) else empty end),

# Phase: PM-SPECIFIC SETUP — top-level then PM-block
(if $pm == "apt" then
  (if $doc | has("ppas") then $doc.ppas[] | {kind: "ppa", ppa: .} else empty end),
  (if ($doc | has("apt")) and ($doc.apt | has("ppas")) then
    $doc.apt.ppas[] | {kind: "ppa", ppa: .} else empty end)
else empty end),
(if $pm == "brew" then
  (if $doc | has("taps") then $doc.taps[] | {kind: "tap", tap: .} else empty end),
  (if ($doc | has("brew")) and ($doc.brew | has("taps")) then
    $doc.brew.taps[] | {kind: "tap", tap: .} else empty end)
else empty end),
(if $pm == "dnf" then
  (if $doc | has("copr") then $doc.copr[] | {kind: "copr", copr: .} else empty end),
  (if ($doc | has("dnf")) and ($doc.dnf | has("copr")) then
    $doc.dnf.copr[] | {kind: "copr", copr: .} else empty end)
else empty end),
(if $pm == "dnf" then
  (if $doc | has("modules") then $doc.modules[] | {kind: "module", module: .} else empty end),
  (if ($doc | has("dnf")) and ($doc.dnf | has("modules")) then
    $doc.dnf.modules[] | {kind: "module", module: .} else empty end)
else empty end),
(if $doc | has("groups") then
  $doc.groups[] |
  if type == "string" then {kind: "group", group: .}
  elif when_matches then {kind: "group", group: .name}
  else empty
  end
else empty end),
(if ($doc | has($pm)) and ($doc[$pm] | has("groups")) then
  $doc[$pm].groups[] |
  if type == "string" then {kind: "group", group: .}
  elif when_matches then {kind: "group", group: .name}
  else empty
  end
else empty end),

# Phase: PACKAGES — inline packages array, then PM-specific packages block
(if $doc | has("packages") then
  $doc.packages[] | visit("package"; null) | select(.name != null) else empty end),
(if ($doc | has($pm)) and ($doc[$pm] | has("packages")) then
  $doc[$pm].packages[] | visit("package"; null) | select(.name != null)
else empty end),

# Phase: CASKS (brew/macOS only) — top-level then PM block
(if $pm == "brew" then
  (if $doc | has("casks") then $doc.casks[] | {kind: "cask", cask: .} else empty end),
  (if ($doc | has("brew")) and ($doc.brew | has("casks")) then
    $doc.brew.casks[] | {kind: "cask", cask: .} else empty end)
else empty end),

# Phase: SCRIPTS — PM block, then top-level, then inline
(if ($doc | has($pm)) and ($doc[$pm] | has("scripts")) then
  {kind: "script", content: ($doc[$pm].scripts | to_lines)} else empty end),
(if $doc | has("scripts") then
  {kind: "script", content: ($doc.scripts | to_lines)} else empty end),
(if $doc | has("packages") then
  $doc.packages[] | visit("script"; null) else empty end)

end
' "$_json_file"
  return 0
}

# ── Public: ospkg__run ───────────────────────────────────────────────────────
# Full pipeline: detect → root check → parse manifest → prescript → keys →
# repos → PM setup → update → install → casks → script → cleanup.
#
# Usage: ospkg__run [--manifest <file-or-inline>]
#                   [--update <bool>] [--skip_installed]
#                   [--keep_cache]  [--prefer_linuxbrew]
#                   [--keep_repos] [--lists_max_age <N>] [--dry_run]
#                   [--interactive]
ospkg__run() {
  local _manifest='' _update=true _keep_cache=false _keep_repos=false
  local _lists_max_age=300 _dry_run=false _skip_installed=false _interactive=false
  local _prefer_linuxbrew=false

  while [[ $# -gt 0 ]]; do
    case $1 in
      --manifest)
        shift
        _manifest="$1"
        shift
        ;;
      --update)
        shift
        _update="$1"
        shift
        ;;
      --keep_cache)
        shift
        _keep_cache=true
        ;;
      --keep_repos)
        shift
        _keep_repos=true
        ;;
      --lists_max_age)
        shift
        _lists_max_age="$1"
        shift
        ;;
      --dry_run)
        shift
        _dry_run=true
        ;;
      --skip_installed)
        shift
        _skip_installed=true
        ;;
      --interactive)
        shift
        _interactive=true
        ;;
      --prefer_linuxbrew)
        shift
        _prefer_linuxbrew=true
        ;;
      *)
        echo "⛔ ospkg__run: unknown option: $1" >&2
        return 1
        ;;
    esac
  done

  if ! [[ "$_lists_max_age" =~ ^[0-9]+$ ]]; then
    echo "⛔ ospkg__run: invalid lists_max_age value: '$_lists_max_age'." >&2
    return 1
  fi

  [[ "$_dry_run" == true ]] && echo "🔍 Dry-run mode enabled — no changes will be made." >&2

  # Set prefer_linuxbrew early so detect() picks it up.
  _OSPKG_PREFER_LINUXBREW="$_prefer_linuxbrew"

  ospkg__detect

  # Root check: brew is exempt (it manages its own user/root logic via _ospkg_brew_run).
  if [[ "$_dry_run" == false && "$_OSPKG_PKG_MNGR" != "brew" ]]; then
    os__require_root
  fi

  if [[ "$_OSPKG_PKG_MNGR" = "apt-get" && "$_interactive" == false ]]; then
    echo "🆗 Setting APT to non-interactive mode." >&2
    export DEBIAN_FRONTEND=noninteractive
  fi

  # Resolve manifest content.
  local _manifest_content=
  if [[ -n "$_manifest" ]]; then
    if [[ "$_manifest" == *$'\n'* ]]; then
      _manifest_content="$_manifest"
    elif [[ -f "$_manifest" ]]; then
      _manifest_content="$(< "$_manifest")"
    else
      echo "⛔ Manifest file not found: '$_manifest'" >&2
      return 1
    fi
  fi

  # ── YAML / JSON manifest path ──────────────────────────────────────────────
  if [[ -n "$_manifest_content" ]]; then

    # jq is required for YAML parsing — install unconditionally (parser tool,
    # not a user-requested package, so this runs even in dry-run mode).
    if ! command -v jq > /dev/null 2>&1; then
      echo "ℹ️  jq not found — installing." >&2
      ospkg__update --force
      ospkg__install jq
    fi

    # yq is required to convert YAML to JSON.
    if ! _ospkg_ensure_yq; then
      echo "⛔ yq is required for YAML manifests but could not be obtained." >&2
      return 1
    fi

    # Convert YAML (or JSON) to JSON via yq, then parse into phase arrays.
    # Temp files live inside _SYSSET_TMPDIR so logging__cleanup removes them
    # automatically on exit, even on unexpected failure.
    local _ospkg_dir _json_tmp
    _ospkg_dir="$(logging__tmpdir "ospkg")"
    _json_tmp="$(mktemp "${_ospkg_dir}/yaml_XXXXXX")"

    local -a _Y_PRESCRIPTS=() _Y_KEYS=() _Y_REPOS=() _Y_PPAS=() _Y_TAPS=() _Y_COPR=()
    local -a _Y_MODULES=() _Y_GROUPS=() _Y_PACKAGES=() _Y_CASKS=() _Y_SCRIPTS=()

    echo "ℹ️  Converting manifest to JSON via yq." >&2
    if [[ "$_manifest_content" == *$'\n'* ]]; then
      printf '%s' "$_manifest_content" | "$_OSPKG_YQ_BIN" -o=json '.' - > "$_json_tmp"
    else
      "$_OSPKG_YQ_BIN" -o=json '.' - <<< "$_manifest_content" > "$_json_tmp" 2> /dev/null ||
        echo "$_manifest_content" | "$_OSPKG_YQ_BIN" -o=json '.' - > "$_json_tmp"
    fi

    local _item _kind
    while IFS= read -r _item; do
      _kind="$(printf '%s' "$_item" | jq -r '.kind' 2> /dev/null)" || continue
      case "$_kind" in
        prescript) _Y_PRESCRIPTS+=("$_item") ;;
        key) _Y_KEYS+=("$_item") ;;
        repo) _Y_REPOS+=("$_item") ;;
        ppa) _Y_PPAS+=("$_item") ;;
        tap) _Y_TAPS+=("$_item") ;;
        copr) _Y_COPR+=("$_item") ;;
        module) _Y_MODULES+=("$_item") ;;
        group) _Y_GROUPS+=("$_item") ;;
        package) _Y_PACKAGES+=("$_item") ;;
        cask) _Y_CASKS+=("$_item") ;;
        script) _Y_SCRIPTS+=("$_item") ;;
      esac
    done < <(ospkg__parse_manifest_yaml "$_json_tmp")
    rm -f "$_json_tmp"
    echo "ℹ️  YAML manifest parsed: ${#_Y_PRESCRIPTS[@]} prescript(s), ${#_Y_KEYS[@]} key(s), ${#_Y_REPOS[@]} repo(s), ${#_Y_PPAS[@]} ppa(s), ${#_Y_TAPS[@]} tap(s), ${#_Y_COPR[@]} copr(s), ${#_Y_MODULES[@]} module(s), ${#_Y_GROUPS[@]} group(s), ${#_Y_PACKAGES[@]} package(s), ${#_Y_CASKS[@]} cask(s), ${#_Y_SCRIPTS[@]} script(s)." >&2

    # Helper: run a shell script with dry-run support.
    _run_script() {
      local _label="$1" _content="$2"
      local _stmp
      _stmp="$(mktemp "${_ospkg_dir}/script_XXXXXX")"
      printf '%s\n' "$_content" > "$_stmp"
      chmod +x "$_stmp"
      echo "🚀 Running ${_label}." >&2
      if [[ "$_dry_run" == true ]]; then
        echo "🔍 [dry-run] ${_label} — would execute:" >&2
        sed 's/^/    /' "$_stmp" >&2
      else
        bash "$_stmp"
      fi
      rm -f "$_stmp"
      return 0
    }

    # Phase: PRESCRIPTS.
    if [[ ${#_Y_PRESCRIPTS[@]} -gt 0 ]]; then
      local _combined_prescript=""
      local _pitem
      for _pitem in "${_Y_PRESCRIPTS[@]}"; do
        _combined_prescript+="$(printf '%s' "$_pitem" | jq -r '.content')"$'\n'
      done
      _run_script "prescript" "$_combined_prescript"
      echo "✅ Prescript(s) completed." >&2
    else
      echo "ℹ️  No prescripts found — skipping." >&2
    fi

    # Phase: SIGNING KEYS.
    if [[ ${#_Y_KEYS[@]} -gt 0 ]]; then
      echo "🔑 Installing ${#_Y_KEYS[@]} signing key(s)." >&2
      local _key_gnupghome
      _key_gnupghome="$(mktemp -d "${_SYSSET_TMPDIR:-${TMPDIR:-/tmp}}/ospkg_gnupg_XXXXXX")"
      chmod 700 "$_key_gnupghome"
      if [[ "$_dry_run" == false ]]; then
        export GNUPGHOME="$_key_gnupghome"
      fi
      local _kitem _kurl _kdest _kdearmor
      for _kitem in "${_Y_KEYS[@]}"; do
        _kurl="$(printf '%s' "$_kitem" | jq -r '.url')"
        _kdest="$(printf '%s' "$_kitem" | jq -r '.dest')"
        _kdearmor="$(printf '%s' "$_kitem" | jq -r '.dearmor // "auto"')"
        if [[ "$_dry_run" == true ]]; then
          echo "🔍 [dry-run] key: ${_kurl} → ${_kdest}" >&2
        else
          # Override dearmor auto-detection: if dearmor=false, rename dest to avoid .gpg extension
          if [[ "$_kdearmor" == "false" ]]; then
            local _ndest="${_kdest%.gpg}.key"
            [[ "$_kdest" != *.gpg ]] && _ndest="$_kdest"
            _ospkg_install_key_entry "$_kurl" "$_ndest"
          else
            _ospkg_install_key_entry "$_kurl" "$_kdest"
          fi
        fi
      done
      if [[ "$_dry_run" == false ]]; then
        unset GNUPGHOME
      fi
      rm -rf "$_key_gnupghome"
      echo "✅ Signing keys installed." >&2
    else
      echo "ℹ️  No signing keys found — skipping." >&2
    fi

    # Phase: REPOS.
    local _yaml_repo_added=false
    local _OSPKG_APK_ADDED_REPOS=()
    if [[ ${#_Y_REPOS[@]} -gt 0 ]]; then
      echo "🗃  Adding ${#_Y_REPOS[@]} repository entry/entries." >&2
      local _ritem _rcontent
      for _ritem in "${_Y_REPOS[@]}"; do
        _rcontent="$(printf '%s' "$_ritem" | jq -r '.content')"
        if [[ "$_dry_run" == true ]]; then
          echo "🔍 [dry-run] repo: would add: ${_rcontent}" >&2
        else
          _ospkg_install_repo_content "${_rcontent}"$'\n'
          _yaml_repo_added=true
        fi
      done
    else
      echo "ℹ️  No repo entries found — skipping." >&2
    fi

    # Phase: PPAs (APT only).
    if [[ ${#_Y_PPAS[@]} -gt 0 ]]; then
      if [[ "$_OSPKG_PREFIX" == "apt" ]]; then
        echo "📎 Adding ${#_Y_PPAS[@]} PPA(s)." >&2
        if ! command -v add-apt-repository > /dev/null 2>&1; then
          echo "ℹ️  add-apt-repository not found — installing software-properties-common." >&2
          [[ "$_dry_run" == false ]] && ospkg__install software-properties-common
        fi
        local _ppitem _ppa
        for _ppitem in "${_Y_PPAS[@]}"; do
          _ppa="$(printf '%s' "$_ppitem" | jq -r '.ppa')"
          if [[ "$_dry_run" == true ]]; then
            echo "🔍 [dry-run] ppa: would run: add-apt-repository -y '${_ppa}'" >&2
          else
            echo "📎 Adding PPA: ${_ppa}" >&2
            add-apt-repository -y "$_ppa"
            _yaml_repo_added=true
            echo "✅ PPA added: ${_ppa}" >&2
          fi
        done
      else
        echo "⚠️  PPAs are only supported on APT — ignoring (current PM: ${_OSPKG_PKG_MNGR})." >&2
      fi
    fi

    # Phase: TAPS (brew only).
    if [[ ${#_Y_TAPS[@]} -gt 0 ]]; then
      if [[ "$_OSPKG_PKG_MNGR" == "brew" ]]; then
        echo "🍺 Adding ${#_Y_TAPS[@]} Homebrew tap(s)." >&2
        local _titem _tap_val _tap_name _tap_url
        for _titem in "${_Y_TAPS[@]}"; do
          _tap_val="$(printf '%s' "$_titem" | jq -r '.tap')"
          if printf '%s' "$_tap_val" | jq -e 'type == "object"' > /dev/null 2>&1; then
            _tap_name="$(printf '%s' "$_tap_val" | jq -r '.name')"
            _tap_url="$(printf '%s' "$_tap_val" | jq -r '.url // empty')"
          else
            # tap is a plain string in the jq -c output
            _tap_name="$(printf '%s' "$_titem" | jq -r '.tap | if type == "object" then .name else . end')"
            _tap_url="$(printf '%s' "$_titem" | jq -r '.tap | if type == "object" then (.url // "") else "" end')"
          fi
          if [[ "$_dry_run" == true ]]; then
            echo "🔍 [dry-run] tap: would run: brew tap ${_tap_name}${_tap_url:+ ${_tap_url}}" >&2
          else
            echo "🍺 Tapping: ${_tap_name}" >&2
            if [[ -n "${_tap_url:-}" ]]; then
              _ospkg_brew_run tap "$_tap_name" "$_tap_url"
            else
              _ospkg_brew_run tap "$_tap_name"
            fi
            echo "✅ Tap added: ${_tap_name}" >&2
          fi
        done
      else
        echo "⚠️  Homebrew taps are only supported when PM is brew — ignoring." >&2
      fi
    fi

    # Phase: COPR (DNF only).
    if [[ ${#_Y_COPR[@]} -gt 0 ]]; then
      if [[ "$_OSPKG_PREFIX" == "dnf" ]]; then
        echo "🧩 Enabling ${#_Y_COPR[@]} COPR repo(s)." >&2
        local _copritem _copr
        for _copritem in "${_Y_COPR[@]}"; do
          _copr="$(printf '%s' "$_copritem" | jq -r '.copr')"
          if [[ "$_dry_run" == true ]]; then
            echo "🔍 [dry-run] copr: would run: ${_OSPKG_PKG_MNGR} copr enable -y '${_copr}'" >&2
          else
            echo "🧩 Enabling COPR: ${_copr}" >&2
            "$_OSPKG_PKG_MNGR" copr enable -y "$_copr"
            _yaml_repo_added=true
          fi
        done
      else
        echo "⚠️  COPR repos are only supported on DNF — ignoring (current PM: ${_OSPKG_PKG_MNGR})." >&2
      fi
    fi

    # Phase: MODULES (DNF only).
    if [[ ${#_Y_MODULES[@]} -gt 0 ]]; then
      if [[ "$_OSPKG_PREFIX" == "dnf" ]]; then
        echo "🔩 Enabling ${#_Y_MODULES[@]} DNF module stream(s)." >&2
        local _moditem _mod
        for _moditem in "${_Y_MODULES[@]}"; do
          _mod="$(printf '%s' "$_moditem" | jq -r '.module')"
          if [[ "$_dry_run" == true ]]; then
            echo "🔍 [dry-run] module: would run: ${_OSPKG_PKG_MNGR} module enable -y '${_mod}'" >&2
          else
            echo "🔩 Enabling module: ${_mod}" >&2
            "$_OSPKG_PKG_MNGR" module enable -y "$_mod"
            echo "✅ Module enabled: ${_mod}" >&2
          fi
        done
      else
        echo "⚠️  DNF modules are only supported on DNF — ignoring (current PM: ${_OSPKG_PKG_MNGR})." >&2
      fi
    fi

    # Phase: GROUPS.
    if [[ ${#_Y_GROUPS[@]} -gt 0 ]]; then
      local _grpitem _grp
      for _grpitem in "${_Y_GROUPS[@]}"; do
        _grp="$(printf '%s' "$_grpitem" | jq -r '.group')"
        case "$_OSPKG_PREFIX" in
          dnf)
            if [[ "$_dry_run" == true ]]; then
              echo "🔍 [dry-run] group: would run: ${_OSPKG_PKG_MNGR} group install -y '${_grp}'" >&2
            else
              echo "📦 Installing group '${_grp}' (dnf)." >&2
              "$_OSPKG_PKG_MNGR" group install -y "$_grp"
              echo "✅ Group '${_grp}' installed." >&2
            fi
            ;;
          zypper)
            if [[ "$_dry_run" == true ]]; then
              echo "🔍 [dry-run] group: would run: zypper --non-interactive install -t pattern '${_grp}'" >&2
            else
              echo "📦 Installing pattern '${_grp}' (zypper)." >&2
              zypper --non-interactive install -t pattern "$_grp"
            fi
            ;;
          pacman)
            if [[ "$_dry_run" == true ]]; then
              echo "🔍 [dry-run] group: would run: ${_OSPKG_INSTALL[*]} '${_grp}'" >&2
            else
              echo "📦 Installing group '${_grp}' (pacman)." >&2
              ospkg__install "$_grp"
            fi
            ;;
          *)
            echo "⚠️  Group '${_grp}' — groups not supported on '${_OSPKG_PKG_MNGR}'; skipping." >&2
            ;;
        esac
      done
    fi

    # Phase: PACKAGE LIST UPDATE.
    if [[ ${#_Y_PACKAGES[@]} -gt 0 && "$_update" == true ]]; then
      local _update_args=(--lists_max_age "$_lists_max_age")
      [[ "$_yaml_repo_added" == true ]] && _update_args+=(--repo_added)
      if [[ "$_dry_run" == true ]]; then
        if [[ ${#_OSPKG_UPDATE[@]} -gt 0 ]]; then
          echo "🔍 [dry-run] update: would run: ${_OSPKG_UPDATE[*]}" >&2
        else
          echo "ℹ️  Package list update not supported by '${_OSPKG_PKG_MNGR}' — skipping." >&2
        fi
      else
        ospkg__update "${_update_args[@]}"
      fi
    elif [[ ${#_Y_PACKAGES[@]} -eq 0 ]]; then
      echo "ℹ️  Package list update skipped (no packages in manifest)." >&2
    else
      echo "ℹ️  Package list update skipped (update=false)." >&2
      if [[ "$_yaml_repo_added" == true ]]; then
        echo "⚠️  A repository was added but update=false — packages may not be found." >&2
      fi
    fi

    # Phase: INSTALL PACKAGES.
    local -a _pkgs_to_install=()
    local _pkgitem _pkgname _pkgflags _pkgversion _pkginstall
    for _pkgitem in "${_Y_PACKAGES[@]}"; do
      _pkgname="$(printf '%s' "$_pkgitem" | jq -r '.name')"
      _pkgflags="$(printf '%s' "$_pkgitem" | jq -r '.flags // empty')"
      _pkgversion="$(printf '%s' "$_pkgitem" | jq -r '.version // empty')"
      [[ -z "${_pkgname:-}" ]] && continue

      # Apply version constraint (PM-native syntax).
      if [[ -n "${_pkgversion:-}" ]]; then
        case "$_OSPKG_PREFIX" in
          apt | apk | pacman | zypper) _pkginstall="${_pkgname}=${_pkgversion}" ;;
          dnf | yum) _pkginstall="${_pkgname}-${_pkgversion}" ;;
          brew) _pkginstall="${_pkgname}@${_pkgversion}" ;;
          *) _pkginstall="${_pkgname}" ;;
        esac
      else
        _pkginstall="${_pkgname}"
      fi

      if [[ "$_skip_installed" == true ]] && command -v "$_pkgname" > /dev/null 2>&1; then
        echo "ℹ️  '${_pkgname}' already available in PATH — skipping." >&2
        continue
      fi

      # For PMs that support per-package flags, build the install command.
      if [[ -n "${_pkgflags:-}" ]]; then
        if [[ "$_dry_run" == true ]]; then
          echo "🔍 [dry-run] package: ${_OSPKG_INSTALL[*]} ${_pkgflags} ${_pkginstall}" >&2
        else
          echo "📲 Installing: ${_pkginstall} (flags: ${_pkgflags})" >&2
          # shellcheck disable=SC2086
          "${_OSPKG_INSTALL[@]}" $_pkgflags "$_pkginstall"
        fi
      else
        _pkgs_to_install+=("$_pkginstall")
      fi
    done

    if [[ ${#_pkgs_to_install[@]} -gt 0 ]]; then
      echo "📦 Installing ${#_pkgs_to_install[@]} package(s)." >&2
      if [[ "$_dry_run" == true ]]; then
        echo "🔍 [dry-run] packages: ${_pkgs_to_install[*]}" >&2
      else
        ospkg__install "${_pkgs_to_install[@]}"
      fi
    elif [[ ${#_Y_PACKAGES[@]} -eq 0 ]]; then
      echo "ℹ️  No packages to install — skipping." >&2
    fi

    # Phase: CASKS (brew/macOS only).
    if [[ ${#_Y_CASKS[@]} -gt 0 ]]; then
      if [[ "$_OSPKG_PKG_MNGR" == "brew" && "$(uname -s)" == "Darwin" ]]; then
        echo "🍺 Installing ${#_Y_CASKS[@]} Homebrew cask(s)." >&2
        local _caskitem _cask
        for _caskitem in "${_Y_CASKS[@]}"; do
          _cask="$(printf '%s' "$_caskitem" | jq -r '.cask')"
          if [[ "$_dry_run" == true ]]; then
            echo "🔍 [dry-run] cask: would run: brew install --cask '${_cask}'" >&2
          else
            echo "🍺 Installing cask: ${_cask}" >&2
            _ospkg_brew_run install --cask "$_cask"
            echo "✅ Cask installed: ${_cask}" >&2
          fi
        done
      else
        echo "⚠️  Casks are only supported on macOS with Homebrew — ignoring." >&2
      fi
    fi

    # Phase: SCRIPTS.
    if [[ ${#_Y_SCRIPTS[@]} -gt 0 ]]; then
      local _combined_script=""
      local _sitem
      for _sitem in "${_Y_SCRIPTS[@]}"; do
        _combined_script+="$(printf '%s' "$_sitem" | jq -r '.content')"$'\n'
      done
      _run_script "script" "$_combined_script"
      echo "✅ Script(s) completed." >&2
    else
      echo "ℹ️  No scripts found — skipping." >&2
    fi

    # Phase: REPO CLEANUP.
    # Taps: always kept (never cleaned up).
    # Other repos: remove unless --keep_repos.
    if [[ "$_yaml_repo_added" == true && "$_keep_repos" == false ]]; then
      echo "🗑️  Removing added repositories." >&2
      if [[ "$_OSPKG_PREFIX" = "apt" ]]; then
        rm -f /etc/apt/sources.list.d/syspkg-installer.list
        echo "🗑️  Removed /etc/apt/sources.list.d/syspkg-installer.list" >&2
      elif [[ "$_OSPKG_PREFIX" = "apk" ]]; then
        local _rl
        for _rl in "${_OSPKG_APK_ADDED_REPOS[@]}"; do
          sed -i "\\|^${_rl}$|d" /etc/apk/repositories
          echo "🗑️  Removed APK repo: ${_rl}" >&2
        done
      elif [[ "$_OSPKG_PREFIX" = "dnf" ]]; then
        rm -f /etc/yum.repos.d/syspkg-installer.repo
        echo "🗑️  Removed /etc/yum.repos.d/syspkg-installer.repo" >&2
      elif [[ "$_OSPKG_PREFIX" = "zypper" ]]; then
        rm -f /etc/zypp/repos.d/syspkg-installer.repo
      elif [[ "$_OSPKG_PREFIX" = "pacman" ]]; then
        rm -f /etc/pacman.d/syspkg-installer.conf
        sed -i '/^Include = \/etc\/pacman.d\/syspkg-installer.conf$/d' /etc/pacman.conf
      fi
    elif [[ "$_yaml_repo_added" == true ]]; then
      echo "ℹ️  Keeping added repositories (--keep_repos)." >&2
    fi

  fi # end manifest processing

  # ── Cache cleanup ─────────────────────────────────────────────────────────
  if [[ "$_dry_run" == true ]]; then
    echo "🔍 [dry-run] cache clean: would run ${_OSPKG_CLEAN}" >&2
  elif [[ "$_keep_cache" == false ]]; then
    ospkg__clean
  else
    echo "ℹ️  Cache cleanup skipped (--keep_cache)." >&2
  fi

  return 0
}
