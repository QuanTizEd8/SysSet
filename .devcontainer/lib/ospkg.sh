#!/usr/bin/env bash
# This file must be sourced from bash (>=4.0), not sh.
# Do not edit _lib/ copies directly — edit .devcontainer/lib/ instead.

[[ -n "${_LIB_OSPKG_LOADED-}" ]] && return 0
_LIB_OSPKG_LOADED=1

_OSPKG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_OSPKG_LIB_DIR/os.sh"
. "$_OSPKG_LIB_DIR/net.sh"

# ── Internal state ────────────────────────────────────────────────────────────
_OSPKG_DETECTED=false
_OSPKG_PKG_MNGR=
_OSPKG_PREFIX=
_OSPKG_INSTALL=()
_OSPKG_UPDATE=()
_OSPKG_CLEAN=
_OSPKG_LISTS_PATH=
_OSPKG_LISTS_PATTERN=
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
  apt-get dist-clean 2>/dev/null || rm -rf /var/lib/apt/lists/*
  return 0
}
_ospkg_clean_dnf() {
  "${_OSPKG_INSTALL[0]%% *}" clean all 2>/dev/null || "$_OSPKG_PKG_MNGR" clean all
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

# ── Private: key / repo helpers ──────────────────────────────────────────────
_ospkg_ensure_gpg() {
  command -v gpg > /dev/null 2>&1 && return 0
  echo "ℹ️  gpg not found — installing gnupg." >&2
  local _gpg_pkg
  case "$_OSPKG_PREFIX" in
    dnf) _gpg_pkg=gnupg2 ;;
    *)   _gpg_pkg=gnupg  ;;
  esac
  "${_OSPKG_INSTALL[@]}" "$_gpg_pkg"
  return 0
}

# _ospkg_install_key_entry <url> <dest>
_ospkg_install_key_entry() {
  local _url="$1"
  local _dest="$2"
  net::ensure_fetch_tool
  mkdir -p "$(dirname "$_dest")"
  if [[ "$_dest" == *.gpg ]]; then
    _ospkg_ensure_gpg
    echo "🔑 Fetching and dearmoring key → $_dest" >&2
    net::fetch_url_stdout "$_url" | gpg --dearmor -o "$_dest"
  else
    echo "🔑 Fetching key → $_dest" >&2
    net::fetch_url_file "$_url" "$_dest"
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
    grep -qxF 'Include = /etc/pacman.d/syspkg-installer.conf' /etc/pacman.conf \
      || echo "Include = /etc/pacman.d/syspkg-installer.conf" >> /etc/pacman.conf
    echo "📄 Written to /etc/pacman.d/syspkg-installer.conf" >&2
  fi
  return 0
}

# ── Public: ospkg::detect ────────────────────────────────────────────────────
# Idempotent: detects the package manager and populates _OSPKG_* state.
ospkg::detect() {
  [[ "$_OSPKG_DETECTED" == true ]] && return 0

  if type apt-get > /dev/null 2>&1; then
    echo "🛠️  Detected ecosystem: APT (tool: apt-get)" >&2
    _OSPKG_PREFIX="apt"
    _OSPKG_PKG_MNGR="apt-get"
    _OSPKG_UPDATE=(apt-get update)
    _OSPKG_INSTALL=(apt-get -y install --no-install-recommends)
    _OSPKG_CLEAN=_ospkg_clean_apt
    _OSPKG_LISTS_PATH="/var/lib/apt/lists"
    _OSPKG_LISTS_PATTERN="*_Packages*"
  elif type apk > /dev/null 2>&1; then
    echo "🛠️  Detected ecosystem: APK (tool: apk)" >&2
    _OSPKG_PREFIX="apk"
    _OSPKG_PKG_MNGR="apk"
    _OSPKG_UPDATE=(apk update)
    _OSPKG_INSTALL=(apk add --no-cache)
    _OSPKG_CLEAN=_ospkg_clean_apk
    _OSPKG_LISTS_PATH="/var/cache/apk"
    _OSPKG_LISTS_PATTERN="APKINDEX*"
  elif type dnf > /dev/null 2>&1; then
    echo "🛠️  Detected ecosystem: DNF (tool: dnf)" >&2
    _OSPKG_PREFIX="dnf"
    _OSPKG_PKG_MNGR="dnf"
    _OSPKG_UPDATE=(dnf check-update)
    _OSPKG_INSTALL=(dnf -y install)
    _OSPKG_CLEAN=_ospkg_clean_dnf
    _OSPKG_LISTS_PATH="/var/cache/dnf"
    _OSPKG_LISTS_PATTERN="*"
  elif type microdnf > /dev/null 2>&1; then
    echo "🛠️  Detected ecosystem: DNF (tool: microdnf)" >&2
    _OSPKG_PREFIX="dnf"
    _OSPKG_PKG_MNGR="microdnf"
    _OSPKG_UPDATE=()
    _OSPKG_INSTALL=(microdnf -y install --refresh --best --nodocs --noplugins --setopt=install_weak_deps=0)
    _OSPKG_CLEAN=_ospkg_clean_dnf
    _OSPKG_LISTS_PATH=""
    _OSPKG_LISTS_PATTERN=""
  elif type yum > /dev/null 2>&1; then
    echo "🛠️  Detected ecosystem: DNF (tool: yum)" >&2
    _OSPKG_PREFIX="dnf"
    _OSPKG_PKG_MNGR="yum"
    _OSPKG_UPDATE=(yum check-update)
    _OSPKG_INSTALL=(yum -y install)
    _OSPKG_CLEAN=_ospkg_clean_dnf
    _OSPKG_LISTS_PATH="/var/cache/yum"
    _OSPKG_LISTS_PATTERN="*"
  elif type zypper > /dev/null 2>&1; then
    echo "🛠️  Detected ecosystem: Zypper (tool: zypper)" >&2
    _OSPKG_PREFIX="zypper"
    _OSPKG_PKG_MNGR="zypper"
    _OSPKG_UPDATE=(zypper --non-interactive refresh)
    _OSPKG_INSTALL=(zypper --non-interactive install)
    _OSPKG_CLEAN=_ospkg_clean_zypper
    _OSPKG_LISTS_PATH="/var/cache/zypp/raw"
    _OSPKG_LISTS_PATTERN="*"
  elif type pacman > /dev/null 2>&1; then
    echo "🛠️  Detected ecosystem: Pacman (tool: pacman)" >&2
    _OSPKG_PREFIX="pacman"
    _OSPKG_PKG_MNGR="pacman"
    _OSPKG_UPDATE=(pacman -Sy --noconfirm)
    _OSPKG_INSTALL=(pacman -S --noconfirm --needed)
    _OSPKG_CLEAN=_ospkg_clean_pacman
    _OSPKG_LISTS_PATH="/var/lib/pacman/sync"
    _OSPKG_LISTS_PATTERN="*.db"
  else
    echo "⛔ No supported package manager found." >&2
    return 1
  fi

  # Load /etc/os-release.
  if [[ -f /etc/os-release ]]; then
    local _key _val
    while IFS='=' read -r _key _val; do
      [[ -z "${_key-}" || "$_key" =~ ^# ]] && continue
      _val="${_val#\"}" ; _val="${_val%\"}"
      _val="${_val#\'}" ; _val="${_val%\'}"
      _OSPKG_OS_RELEASE["${_key,,}"]="$_val"
    done < /etc/os-release
  fi
  _OSPKG_OS_RELEASE[pm]="$_OSPKG_PREFIX"
  _OSPKG_OS_RELEASE[arch]="$(uname -m)"
  echo "🔍 OS context: pm=${_OSPKG_OS_RELEASE[pm]} arch=${_OSPKG_OS_RELEASE[arch]} id=${_OSPKG_OS_RELEASE[id]-} id_like=${_OSPKG_OS_RELEASE[id_like]-} version_id=${_OSPKG_OS_RELEASE[version_id]-} version_codename=${_OSPKG_OS_RELEASE[version_codename]-}" >&2

  _OSPKG_DETECTED=true
  return 0
}

# ── Public: ospkg::update ────────────────────────────────────────────────────
# Usage: ospkg::update [--force] [--lists_max_age <N>] [--repo_added]
# Runs the package index update, optionally skipping if lists are fresh.
ospkg::update() {
  ospkg::detect
  local _force=false _max_age=300 _repo_added=false
  while [[ $# -gt 0 ]]; do
    case $1 in
      --force)         shift; _force=true ;;
      --lists_max_age) shift; _max_age="$1"; shift ;;
      --repo_added)    shift; _repo_added=true ;;
      *) echo "⛔ ospkg::update: unknown option: $1" >&2; return 1 ;;
    esac
  done

  if [[ ${#_OSPKG_UPDATE[@]} -eq 0 ]]; then
    echo "ℹ️  Package list update not supported by '${_OSPKG_PKG_MNGR}' — skipping." >&2
    return 0
  fi

  local _skip=false
  if [[ "$_force" == true || "$_repo_added" == true ]]; then
    _skip=false
  elif [[ -n "${_OSPKG_LISTS_PATH:-}" && -d "$_OSPKG_LISTS_PATH" ]]; then
    if [[ -n "$(find "$_OSPKG_LISTS_PATH" -mindepth 1 -maxdepth 2 -name "${_OSPKG_LISTS_PATTERN:-*}" 2>/dev/null | head -1)" ]]; then
      local _mtime _age
      _mtime=$(stat -c %Y "$_OSPKG_LISTS_PATH" 2>/dev/null || echo 0)
      _age=$(( $(date +%s) - _mtime ))
      if [[ $_age -lt $_max_age ]]; then
        _skip=true
        echo "ℹ️  Package lists refreshed ${_age}s ago — skipping update (threshold: ${_max_age}s)." >&2
      fi
    fi
  fi

  if [[ "$_skip" == false ]]; then
    echo "🔄 Updating package lists." >&2
    if [[ "$_OSPKG_PKG_MNGR" = "dnf" || "$_OSPKG_PKG_MNGR" = "yum" ]]; then
      "${_OSPKG_UPDATE[@]}" || [[ $? -eq 100 ]]
    else
      "${_OSPKG_UPDATE[@]}"
    fi
    echo "✅ Package lists updated." >&2
  fi
  return 0
}

# ── Public: ospkg::install ───────────────────────────────────────────────────
# Usage: ospkg::install <pkg>...
# Installs packages, with idempotency check for apt and dnf.
ospkg::install() {
  ospkg::detect
  if [[ "$_OSPKG_PKG_MNGR" = "apt-get" ]]; then
    if dpkg -s "$@" > /dev/null 2>&1; then
      echo "ℹ️  Packages already installed: $*" >&2
      return 0
    fi
  elif [[ "$_OSPKG_PKG_MNGR" = "dnf" || "$_OSPKG_PKG_MNGR" = "yum" ]]; then
    local _num_pkgs=$#
    local _num_installed
    _num_installed=$("$_OSPKG_PKG_MNGR" -C list installed "$@" 2>/dev/null | sed '1,/^Installed/d' | wc -l) || _num_installed=0
    if [[ $_num_pkgs -eq $_num_installed ]]; then
      echo "ℹ️  Packages already installed: $*" >&2
      return 0
    fi
  fi
  echo "📲 Installing packages:" >&2
  printf '  - %s\n' "$@" >&2
  "${_OSPKG_INSTALL[@]}" "$@"
  return 0
}

# ── Public: ospkg::clean ─────────────────────────────────────────────────────
ospkg::clean() {
  ospkg::detect
  echo "🧹 Cleaning package manager cache." >&2
  "$_OSPKG_CLEAN"
  return 0
}

# ── Public: ospkg::eval_selector_block ───────────────────────────────────────
# Usage: ospkg::eval_selector_block "key=val,key=val,..."
# Returns 0 if ALL conditions match _OSPKG_OS_RELEASE, 1 otherwise.
ospkg::eval_selector_block() {
  ospkg::detect
  local block="$1"
  local cond key val actual
  local -a _conds
  IFS=',' read -ra _conds <<< "$block"
  for cond in "${_conds[@]}"; do
    cond="${cond// /}"
    key="${cond%%=*}"
    val="${cond#*=}"
    actual="${_OSPKG_OS_RELEASE[$key]-}"
    if [[ "${actual,,}" != "${val,,}" ]]; then
      return 1
    fi
  done
  return 0
}

# ── Public: ospkg::pkg_matches_selectors ─────────────────────────────────────
# Usage: ospkg::pkg_matches_selectors "raw pkg line"
# Returns 0 if the line has no selector blocks, or if ANY block passes (OR).
ospkg::pkg_matches_selectors() {
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
    if ospkg::eval_selector_block "$block"; then
      return 0
    fi
  done
  return 1
}

# ── Public: ospkg::parse_manifest ────────────────────────────────────────────
# Usage: ospkg::parse_manifest <content>
# Parses manifest content (single string) into caller-scope output variables:
#   _M_KEY  _M_PRESCRIPT  _M_REPO  _M_PKG  _M_SCRIPT
ospkg::parse_manifest() {
  local content="$1"
  _M_PRESCRIPT="" _M_REPO="" _M_KEY="" _M_PKG="" _M_SCRIPT=""
  local _type=pkg _active=true _line _mtype _mselectors _mpkg
  while IFS= read -r _line || [[ -n "$_line" ]]; do
    if [[ "$_line" =~ ^---[[:space:]]+(key|pkg|prescript|repo|script)(([[:space:]].*)?$) ]]; then
      _mtype="${BASH_REMATCH[1]}"
      _mselectors="${BASH_REMATCH[2]# }"
      _type="$_mtype"
      if ospkg::pkg_matches_selectors "$_mselectors"; then _active=true; else _active=false; fi
      continue
    fi
    [[ "$_active" == true ]] || continue
    [[ "$_line" =~ ^[[:space:]]*(#|$) ]] && continue
    case "$_type" in
      pkg)
        if ospkg::pkg_matches_selectors "$_line"; then
          _mpkg="${_line%%\[*}"
          _mpkg="${_mpkg%"${_mpkg##*[! $'\t']}"}"
          [[ -n "$_mpkg" ]] && _M_PKG+="${_mpkg}"$'\n'
        fi
        ;;
      key)       _M_KEY+="${_line}"$'\n'       ;;
      prescript) _M_PRESCRIPT+="${_line}"$'\n' ;;
      repo)      _M_REPO+="${_line}"$'\n'      ;;
      script)    _M_SCRIPT+="${_line}"$'\n'    ;;
    esac
  done <<< "$content"
  return 0
}

# ── Public: ospkg::run ───────────────────────────────────────────────────────
# Full pipeline: detect → root check → parse manifest → prescript → keys →
# repos → update → install → script → remove repos → clean.
#
# Usage: ospkg::run [--manifest <file-or-inline>] [--no_update] [--no_clean]
#                   [--keep_repos] [--lists_max_age <N>] [--dry_run]
#                   [--check_installed] [--interactive]
ospkg::run() {
  local _manifest= _no_update=false _no_clean=false _keep_repos=false
  local _lists_max_age=300 _dry_run=false _check_installed=false _interactive=false

  while [[ $# -gt 0 ]]; do
    case $1 in
      --manifest)       shift; _manifest="$1";       shift ;;
      --no_update)      shift; _no_update=true              ;;
      --no_clean)       shift; _no_clean=true               ;;
      --keep_repos)     shift; _keep_repos=true             ;;
      --lists_max_age)  shift; _lists_max_age="$1";  shift ;;
      --dry_run)        shift; _dry_run=true                ;;
      --check_installed) shift; _check_installed=true       ;;
      --interactive)    shift; _interactive=true            ;;
      *) echo "⛔ ospkg::run: unknown option: $1" >&2; return 1 ;;
    esac
  done

  if ! [[ "$_lists_max_age" =~ ^[0-9]+$ ]]; then
    echo "⛔ ospkg::run: invalid lists_max_age value: '$_lists_max_age'." >&2
    return 1
  fi

  [[ "$_dry_run" == true ]] && echo "🔍 Dry-run mode enabled — no changes will be made." >&2
  [[ "$_dry_run" == true ]] || os::require_root

  ospkg::detect

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
      _manifest_content="$(<"$_manifest")"
    else
      echo "⛔ Manifest file not found: '$_manifest'" >&2; return 1
    fi
  fi

  # Parse manifest.
  local _M_PRESCRIPT= _M_REPO= _M_KEY= _M_PKG= _M_SCRIPT=
  if [[ -n "$_manifest_content" ]]; then
    ospkg::parse_manifest "$_manifest_content"
    echo "ℹ️  Manifest parsed: $(echo -n "$_M_PRESCRIPT" | wc -l | tr -d ' ') prescript line(s), $(echo -n "$_M_KEY" | wc -l | tr -d ' ') key entry/entries, $(echo -n "$_M_REPO" | wc -l | tr -d ' ') repo line(s), $(echo -n "$_M_PKG" | wc -w | tr -d ' ') pkg(s), $(echo -n "$_M_SCRIPT" | wc -l | tr -d ' ') script line(s)." >&2
  fi

  # Prescript.
  if [[ -n "$_M_PRESCRIPT" ]]; then
    echo "🚀 Running manifest prescript." >&2
    local _prescript_tmp
    _prescript_tmp="$(mktemp)"
    printf '%s' "$_M_PRESCRIPT" > "$_prescript_tmp"
    chmod +x "$_prescript_tmp"
    if [[ "$_dry_run" == true ]]; then
      echo "🔍 [dry-run] prescript: $(echo -n "$_M_PRESCRIPT" | wc -l | tr -d ' ') line(s) — would execute:" >&2
      sed 's/^/    /' "$_prescript_tmp" >&2
    else
      bash "$_prescript_tmp"
    fi
    rm -f "$_prescript_tmp"
    echo "✅ Manifest prescript completed." >&2
  else
    echo "ℹ️  No prescript found — skipping." >&2
  fi

  # Signing keys.
  if [[ -n "$_M_KEY" ]]; then
    echo "🔑 Installing signing keys." >&2
    local _key_gnupghome
    _key_gnupghome="$(mktemp -d)"
    chmod 700 "$_key_gnupghome"
    if [[ "$_dry_run" == true ]]; then
      echo "🔍 [dry-run] key: $(echo -n "$_M_KEY" | wc -l | tr -d ' ') entry/entries — would fetch:" >&2
      local _kline _kurl _kdest
      while IFS= read -r _kline || [[ -n "$_kline" ]]; do
        [[ -z "${_kline:-}" ]] && continue
        _kurl="${_kline%% *}"
        _kdest="${_kline#* }"
        echo "    $_kurl → $_kdest" >&2
      done <<< "$_M_KEY"
    else
      export GNUPGHOME="$_key_gnupghome"
      local _kline _kurl _kdest
      while IFS= read -r _kline || [[ -n "$_kline" ]]; do
        [[ -z "${_kline:-}" ]] && continue
        _kurl="${_kline%% *}"
        _kdest="${_kline#* }"
        _ospkg_install_key_entry "$_kurl" "$_kdest"
      done <<< "$_M_KEY"
      unset GNUPGHOME
    fi
    rm -rf "$_key_gnupghome"
    echo "✅ Signing keys installed." >&2
  else
    echo "ℹ️  No key entries found — skipping." >&2
  fi

  # Repositories.
  local _repo_added=false
  local _OSPKG_APK_ADDED_REPOS=()
  if [[ -n "$_M_REPO" ]]; then
    echo "🗃  Adding repositories." >&2
    echo "📂 From manifest repo section." >&2
    if [[ "$_dry_run" == true ]]; then
      echo "🔍 [dry-run] repo: $(echo -n "$_M_REPO" | wc -l | tr -d ' ') line(s) — would add to package manager repos." >&2
    else
      _ospkg_install_repo_content "$_M_REPO"
      _repo_added=true
    fi
  else
    echo "ℹ️  No repo content found — skipping." >&2
  fi

  # Update.
  if [[ -n "$_M_PKG" && "$_no_update" == false ]]; then
    if [[ "$_dry_run" == true ]]; then
      if [[ ${#_OSPKG_UPDATE[@]} -gt 0 ]]; then
        echo "🔍 [dry-run] update: would run: ${_OSPKG_UPDATE[*]}" >&2
      else
        echo "ℹ️  Package list update not supported by '${_OSPKG_PKG_MNGR}' — skipping." >&2
      fi
    else
      local _update_args=(--lists_max_age "$_lists_max_age")
      [[ "$_repo_added" == true ]] && _update_args+=(--repo_added)
      ospkg::update "${_update_args[@]}"
    fi
  elif [[ -z "$_M_PKG" ]]; then
    echo "ℹ️  Package list update skipped (no packages in manifest)." >&2
  else
    echo "ℹ️  Package list update skipped (--no_update)." >&2
    if [[ "$_repo_added" == true ]]; then
      echo "⚠️  A repository was added by the manifest but --no_update is set." >&2
      echo "⚠️  Packages from the new repository will not be found unless the package lists are already up-to-date." >&2
    fi
  fi

  # Install packages.
  local -a _packages=()
  if [[ -n "$_M_PKG" ]]; then
    local _mpkg
    while IFS= read -r _mpkg || [[ -n "$_mpkg" ]]; do
      [[ -n "$_mpkg" ]] && _packages+=("$_mpkg")
    done <<< "$_M_PKG"
  fi

  if [[ "$_check_installed" == true && ${#_packages[@]} -gt 0 ]]; then
    local _filtered=() _pkg
    for _pkg in "${_packages[@]}"; do
      if command -v "$_pkg" > /dev/null 2>&1; then
        echo "ℹ️  '$_pkg' already available in PATH — skipping." >&2
      else
        _filtered+=("$_pkg")
      fi
    done
    _packages=("${_filtered[@]}")
  fi

  if [[ ${#_packages[@]} -eq 0 ]]; then
    echo "ℹ️  No packages to install — skipping." >&2
  else
    echo "📦 Installing ${#_packages[@]} package(s)." >&2
    if [[ "$_dry_run" == true ]]; then
      echo "🔍 [dry-run] packages (${#_packages[@]}): ${_packages[*]}" >&2
    else
      ospkg::install "${_packages[@]}"
    fi
  fi

  # Post-install script.
  if [[ -n "$_M_SCRIPT" ]]; then
    echo "🚀 Running manifest script." >&2
    local _script_tmp
    _script_tmp="$(mktemp)"
    printf '%s' "$_M_SCRIPT" > "$_script_tmp"
    chmod +x "$_script_tmp"
    if [[ "$_dry_run" == true ]]; then
      echo "🔍 [dry-run] script: $(echo -n "$_M_SCRIPT" | wc -l | tr -d ' ') line(s) — would execute:" >&2
      sed 's/^/    /' "$_script_tmp" >&2
    else
      bash "$_script_tmp"
    fi
    rm -f "$_script_tmp"
    echo "✅ Manifest script completed." >&2
  else
    echo "ℹ️  No script found — skipping." >&2
  fi

  # Remove added repositories.
  if [[ "$_repo_added" == true && "$_keep_repos" == false ]]; then
    echo "🗑️  Removing added repositories." >&2
    if [[ "$_OSPKG_PREFIX" = "apt" ]]; then
      rm -f /etc/apt/sources.list.d/syspkg-installer.list
      echo "🗑️  Removed /etc/apt/sources.list.d/syspkg-installer.list" >&2
    elif [[ "$_OSPKG_PREFIX" = "apk" ]]; then
      local _repo_line
      for _repo_line in "${_OSPKG_APK_ADDED_REPOS[@]}"; do
        sed -i "\\|^${_repo_line}$|d" /etc/apk/repositories
        echo "🗑️  Removed APK repo: ${_repo_line}" >&2
      done
    elif [[ "$_OSPKG_PREFIX" = "dnf" ]]; then
      rm -f /etc/yum.repos.d/syspkg-installer.repo
      echo "🗑️  Removed /etc/yum.repos.d/syspkg-installer.repo" >&2
    elif [[ "$_OSPKG_PREFIX" = "zypper" ]]; then
      rm -f /etc/zypp/repos.d/syspkg-installer.repo
      echo "🗑️  Removed /etc/zypp/repos.d/syspkg-installer.repo" >&2
    elif [[ "$_OSPKG_PREFIX" = "pacman" ]]; then
      rm -f /etc/pacman.d/syspkg-installer.conf
      sed -i '/^Include = \/etc\/pacman.d\/syspkg-installer.conf$/d' /etc/pacman.conf
      echo "🗑️  Removed /etc/pacman.d/syspkg-installer.conf and Include entry from /etc/pacman.conf" >&2
    fi
  elif [[ "$_repo_added" == true ]]; then
    echo "ℹ️  Keeping added repositories (--keep_repos)." >&2
  fi

  # Clean.
  if [[ "$_dry_run" == true ]]; then
    echo "🔍 [dry-run] cache clean: would run $_OSPKG_CLEAN" >&2
  elif [[ "$_no_clean" == false ]]; then
    ospkg::clean
  else
    echo "ℹ️  Cache cleanup skipped (--no_clean)." >&2
  fi

  return 0
}
