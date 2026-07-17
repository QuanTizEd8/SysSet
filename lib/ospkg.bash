# shellcheck shell=bash
# Cross-distro package manager abstraction: install, update, clean, and track dependencies.
#
# Detects the host package manager (`apt`, `apk`, `brew`, `dnf`/`yum`, `zypper`)
# automatically. Supports grouping packages into build-time and run-time
# dependency groups for later cleanup.

_OSPKG__LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Internal state ────────────────────────────────────────────────────────────
_OSPKG__DETECTED=false
_OSPKG__UPDATED=false
_OSPKG__PKG_MNGR=
_OSPKG__FAMILY=
_OSPKG__INSTALL=()
_OSPKG__REMOVE=()
_OSPKG__REMOVE_FORCE=()
_OSPKG__UPDATE=()
_OSPKG__CLEAN=
_OSPKG__LISTS_PATH=
_OSPKG__LISTS_PATTERN=
_OSPKG__PREFER_LINUXBREW=false
# DNF mark subcommand names; overridden to "user"/"dependency" for DNF5.
_OSPKG__DNF_MARK_USER="install"
_OSPKG__DNF_MARK_DEP="remove"
_OSPKG__PM_KEY=""
_OSPKG__DEB_ARCH=""
# Live-registry state (concurrency-safe build-dep co-ownership; see the "Live
# registry" section below and docs/source/dev-guide/features/lib.md).
# _OSPKG__REGISTRY_ROOT is an OPTIONAL override honoured verbatim (no privilege
# wrapper) so tests can pin the registry under a writable temp dir; it is left
# unset in production, where the root is derived from the feature share dir.
_OSPKG__REGISTERED=false
_OSPKG__SELF_TOKEN=""
# Whether this invocation performed the shared "last-out" teardown at cleanup
# (true when it was the last live registrant, or when no registry was active).
_OSPKG__LAST_OUT_DECISION=true
# Backstop (seconds) after which a mutex owner or session registrant is treated
# as stale even when liveness cannot be established.
_OSPKG__REGISTRY_STALE_SECS=900

_ospkg__clean_apk() {
  # @brief _ospkg__clean_apk — Remove the Alpine APK package cache (`/var/cache/apk/*`).
  users__run_privileged rm -rf /var/cache/apk/*
  return 0
}

_ospkg__clean_apt() {
  # @brief _ospkg__clean_apt — Clean the APT package cache and remove downloaded index files.
  #
  # Runs `apt-get clean` (removes cached `.deb` files) then `apt-get dist-clean`
  # (APT 3.x; removes `/var/lib/apt/lists/*` while preserving Release files).
  # Falls back to a direct `rm -rf /var/lib/apt/lists/*` on APT 2.x and below
  # where `dist-clean` does not exist.
  users__run_privileged apt-get clean >&2
  # apt-get dist-clean is an APT 3.x command that removes /var/lib/apt/lists/*
  # while preserving the Release/InRelease files for security.
  # Docs: https://manpages.debian.org/unstable/apt/apt-get.8.en.html#distclean
  # Fall back to rm -rf on older APT (2.x and below) where the command does not exist.
  users__run_privileged apt-get dist-clean >&2 2> /dev/null || users__run_privileged rm -rf /var/lib/apt/lists/*
  return 0
}

_ospkg__clean_dnf() {
  # @brief _ospkg__clean_dnf — Clean the dnf/yum package cache and remove cached metadata.
  users__run_privileged "$_OSPKG__PKG_MNGR" clean all >&2 2> /dev/null || true
  users__run_privileged rm -rf /var/cache/dnf/* /var/cache/yum/*
  return 0
}

_ospkg__clean_pacman() {
  # @brief _ospkg__clean_pacman — Remove all cached pacman packages and unused sync databases.
  users__run_privileged pacman -Scc --noconfirm >&2
  return 0
}

_ospkg__clean_zypper() {
  # @brief _ospkg__clean_zypper — Clean all zypper repository caches.
  users__run_privileged zypper clean --all >&2
  return 0
}

_ospkg__zypper_install() {
  # @brief _ospkg__zypper_install <pkg>... — Run `zypper install` and normalise non-fatal exit codes.
  #
  # Wraps `zypper --non-interactive --no-refresh install` for use as `_OSPKG__INSTALL` on zypper
  # systems. When zypper exits with a code other than 0 or the repos-skipped info code but every
  # requested package is already present on disk, the error is non-fatal: it results from
  # CDN/metadata problems on secondary repos (backports, SLE update) that are irrelevant to
  # packages successfully resolved from the main repository. In that case the function returns 6
  # so the caller's `net__fetch_with_retry --bail-on 6` stops retrying immediately instead of
  # looping 60 times (each attempt ≈ 1+ minute of CDN timeouts).
  #
  # Note: ZYPPER_EXIT_INF_REPOS_SKIPPED is 106 on openSUSE Leap 15.x (not 6); both are
  # treated as non-fatal here.
  #
  # Exit 0/6/106 → forwarded as-is (success or non-fatal repos-skipped).
  # Other        → if all <pkg> args are now installed: return 6 (non-fatal, bail).
  #                Otherwise: return the original code so the caller retries.
  local _rc=0
  users__run_privileged zypper --non-interactive --no-refresh install "$@" || _rc=$?
  [[ "$_rc" -eq 0 ]] && return 0
  # 106 = ZYPPER_EXIT_INF_REPOS_SKIPPED on openSUSE Leap 15.x (empirically verified);
  # older docs cite 6, which may appear on other zypper versions. Both are non-fatal.
  # Return 6 in both cases so the caller's --bail-on 6 fires immediately.
  [[ "$_rc" -eq 6 || "$_rc" -eq 106 ]] && return 6
  # Non-zero, non-repos-skipped: check whether packages landed despite the zypper error.
  # Skip flag-style args (starting with -) — they are zypper options, not package names.
  local _pkg _has_pkg=false
  for _pkg in "$@"; do
    [[ "$_pkg" == -* ]] && continue
    _has_pkg=true
    ospkg__is_installed "${_pkg%%=*}" || return "$_rc"
  done
  [[ "$_has_pkg" == false ]] && return "$_rc"
  logging__warn "zypper install exited $_rc but all packages are present — treating as repos-skipped (6)."
  return 6
}

_ospkg__clean_brew() {
  # @brief _ospkg__clean_brew — Run `brew cleanup --prune=all` to remove stale Homebrew downloads.
  _ospkg__brew_run cleanup --prune=all >&2 2> /dev/null || true
  return 0
}

_ospkg__update_cmd() {
  # @brief _ospkg__update_cmd — Run the package-manager index update command (`_OSPKG__UPDATE`), normalising non-fatal exit codes to 0.
  #
  # Wraps `_OSPKG__UPDATE` for use with `net__fetch_with_retry`. Non-fatal PM
  # codes normalised to 0:
  #   - dnf/yum exit 100  — "updates available" (informational, not a failure).
  #   - zypper exit 4     — ZYPPER_EXIT_ERR_ZYPP: empirically returned by
  #                         `zypper refresh` when CDN repos are unreachable
  #                         (verified on openSUSE Leap 15.6 via Docker test).
  #   - zypper exit 6     — ZYPPER_EXIT_INF_REPOS_SKIPPED (older zypper).
  #   - zypper exit 106   — ZYPPER_EXIT_INF_REPOS_SKIPPED (openSUSE Leap 15.x;
  #                         empirically verified; also documented in environments.yaml).
  # APT index-corruption error strings (Hash Sum mismatch, Failed to fetch, etc.)
  # are detected and force-retried even when APT itself exits 0.
  #
  # Returns: 0 on success; 2 for non-transient configuration errors (malformed
  # source lists, parse errors) so `net__fetch_with_retry --bail-on 2` skips
  # pointless retries; other non-zero codes pass through unchanged for retry.
  [[ ${#_OSPKG__UPDATE[@]} -eq 0 ]] && return 0
  local _rc=0 _err_tmp
  _err_tmp="$(mktemp)"
  # Keep interactive mode possible on TTY, but prevent PMs from draining
  # caller-provided stdin in piped/non-interactive contexts.
  # Use || _rc=$? on each branch so set -e callers do not abort before we can
  # normalise non-fatal exit codes (e.g. dnf check-update exits 100 when
  # updates are available; zypper refresh exits 6 for skipped repos).
  if [[ -t 0 ]]; then
    "${_OSPKG__UPDATE[@]}" >&2 2> "$_err_tmp" || _rc=$?
  elif [[ "$_OSPKG__PKG_MNGR" == "apt-get" && -z "${DEBIAN_FRONTEND-}" ]]; then
    DEBIAN_FRONTEND=noninteractive "${_OSPKG__UPDATE[@]}" < /dev/null >&2 2> "$_err_tmp" || _rc=$?
  else
    "${_OSPKG__UPDATE[@]}" < /dev/null >&2 2> "$_err_tmp" || _rc=$?
  fi
  cat "$_err_tmp" >&2
  # APT can occasionally report index corruption/partial fetch failures while
  # still exiting successfully; force retry when those signatures appear.
  if [[ "$_OSPKG__PKG_MNGR" == "apt-get" ]] && grep -qiE \
    'Hash Sum mismatch|Failed to fetch|Some index files failed to download' \
    "$_err_tmp" 2> /dev/null; then
    _rc=100
    users__run_privileged apt-get clean > /dev/null 2>&1 || true
    users__run_privileged apt-get dist-clean 2> /dev/null || users__run_privileged rm -rf /var/lib/apt/lists/* 2> /dev/null || true
  fi
  [[ "$_OSPKG__PKG_MNGR" == "dnf" || "$_OSPKG__PKG_MNGR" == "yum" ]] &&
    [[ $_rc -eq 100 ]] && rm -f "$_err_tmp" && return 0
  if [[ "$_OSPKG__PKG_MNGR" == "zypper" ]] && [[ "$_rc" -eq 4 || "$_rc" -eq 6 || "$_rc" -eq 106 ]]; then
    rm -f "$_err_tmp"
    return 0
  fi
  if [[ $_rc -ne 0 ]]; then
    # Detect non-transient configuration errors — retrying will never fix these.
    if grep -qiE 'Malformed line|source list could not be read|parse error|invalid source' \
      "$_err_tmp" 2> /dev/null; then
      logging__error "Package list update failed due to a configuration error — not retrying."
      rm -f "$_err_tmp"
      return 2
    fi
  fi
  rm -f "$_err_tmp"
  return "$_rc"
}

_ospkg__dnf_bin() {
  # @brief _ospkg__dnf_bin — Print the name of a full-featured `dnf`-compatible binary (`dnf` or `yum`), or return 1.
  #
  # `microdnf` does not implement the `copr` or `module` subcommands. This
  # helper resolves a usable binary for those operations using the following
  # priority:
  #   1. Full `dnf` in PATH — always preferred, even when microdnf is the
  #      detected package manager.
  #   2. `yum` as the detected PM — supports copr/module via plugins on older
  #      RHEL/CentOS.
  #   3. Neither available — logs an error and returns 1.
  #
  # Stdout: `dnf` or `yum`.
  # Returns: 0 on success, 1 if no suitable binary is found.
  if command -v dnf > /dev/null 2>&1; then
    echo "dnf"
    return 0
  fi
  if [[ "$_OSPKG__PKG_MNGR" == "yum" ]]; then
    echo "yum"
    return 0
  fi
  logging__error "'${_OSPKG__PKG_MNGR}' does not support copr/module subcommands; install full dnf first."
  return 1
}

_ospkg__key_effective_path() {
  # @brief _ospkg__key_effective_path <dest> <dearmor> — Print the filesystem path the key will actually be written to, accounting for dearmor mode.
  #
  # When `dearmor` is `false` and `<dest>` ends in `.gpg`, the key is stored as
  # a raw `.key` file (the `.gpg` extension is reserved for dearmored binaries
  # in APT conventions). All other combinations return `<dest>` unchanged.
  #
  # Args:
  #   <dest>     Intended destination path for the key file.
  #   <dearmor>  `true`, `false`, or `auto` (empty/`null` treated as `auto`).
  #
  # Stdout: effective file path.
  local _dest="$1" _dearmor="${2:-auto}"
  [[ -z "${_dearmor}" || "${_dearmor}" == "null" ]] && _dearmor=auto
  if [[ "${_dearmor}" == "false" && "${_dest}" == *.gpg ]]; then
    printf '%s' "${_dest%.gpg}.key"
  else
    printf '%s' "${_dest}"
  fi
}

_ospkg__install_key_entry() {
  # @brief _ospkg__install_key_entry <url> <dest> [<dearmor>] [<fingerprint>] — Download and install a GPG signing key for a package repository.
  #
  # Supports three dearmoring modes:
  #   `true`  — always pipe through `gpg --dearmor` regardless of `<dest>` extension.
  #   `false` — store the raw file (using `.key` instead of `.gpg` extension when needed).
  #   `auto`  — dearmor when `<dest>` ends in `.gpg`; raw otherwise (default).
  # When `<url>` is empty/null and `<fingerprint>` is provided, the key is
  # fetched from HKP keyservers via `verify__gpg_fetch_key_by_fingerprint`.
  #
  # Args:
  #   <url>          URL to download the key from (may be empty when fingerprint is given).
  #   <dest>         Destination path for the installed key file.
  #   [dearmor]      Dearmoring mode: `true`, `false`, or `auto` (default).
  #   [fingerprint]  40-char hex GPG fingerprint (used when URL is absent).
  #
  # Returns: 0 on success, 1 on error.
  local _url="$1" _dest="$2" _dearmor="${3:-auto}" _fingerprint="${4:-}"
  [[ -z "${_dearmor}" || "${_dearmor}" == "null" ]] && _dearmor=auto
  [[ -z "${_fingerprint}" || "${_fingerprint}" == "null" ]] && _fingerprint=""
  local _target
  _target="$(_ospkg__key_effective_path "$_dest" "$_dearmor")"
  mkdir -p "$(dirname "$_dest")"

  # Fingerprint-only: no URL, fetch from keyserver.
  if [[ -z "${_url}" || "${_url}" == "null" ]]; then
    if [[ -n "${_fingerprint}" ]]; then
      logging__info "Installing key by fingerprint ${_fingerprint} → ${_target}"
      _ospkg__install_key_by_fingerprint "${_fingerprint}" "${_target}"
      return $?
    fi
    logging__error "neither url nor fingerprint provided."
    return 1
  fi

  case "${_dearmor}" in
    true)
      logging__info "Fetching and dearmoring key (dearmor: true) → ${_target}"
      net__fetch_url_stdout "$_url" | verify__gpg_dearmor_stream "${_target}" "devfeats-ospkg-internals"
      ;;
    false)
      logging__info "Fetching key (dearmor: false) → ${_target}"
      net__fetch_url_file "$_url" "${_target}"
      ;;
    auto)
      if [[ "${_dest}" == *.gpg ]]; then
        logging__info "Fetching and dearmoring key (dest ends in .gpg) → ${_target}"
        net__fetch_url_stdout "$_url" | verify__gpg_dearmor_stream "${_target}" "devfeats-ospkg-internals"
      else
        logging__info "Fetching key → ${_target}"
        net__fetch_url_file "$_url" "${_target}"
      fi
      ;;
    *)
      logging__error "invalid dearmor (use true, false, or auto): '${_dearmor}'"
      return 1
      ;;
  esac
  users__run_privileged chmod 0644 "${_target}"
  return 0
}

_ospkg__install_key_by_fingerprint() {
  # @brief _ospkg__install_key_by_fingerprint <fingerprint> <dest> — Fetch a GPG signing key by fingerprint and install it to `<dest>`.
  #
  # Delegates to `verify__gpg_fetch_key_by_fingerprint` with the
  # `devfeats-ospkg-internals` tracking group.
  #
  # Args:
  #   <fingerprint>  40-char hex GPG key fingerprint.
  #   <dest>         Destination path for the dearmored binary keyring.
  #
  # Returns: 0 on success, 1 if the key cannot be fetched from any keyserver.
  local _fingerprint="$1" _dest="$2"
  verify__gpg_fetch_key_by_fingerprint "$_fingerprint" "$_dest" "devfeats-ospkg-internals"
}

_ospkg__install_repo_content() {
  # @brief _ospkg__install_repo_content <content> — Append expanded repository configuration `<content>` to the appropriate PM config file for the current OS.
  #
  # Substitutes `{qualified.key}` tokens via `ctx__expand_pattern` before writing.
  # Routes to the correct file based on `_OSPKG__FAMILY`:
  #   apt     → `/etc/apt/sources.list.d/syspkg-installer.list`
  #   apk     → `/etc/apk/repositories` (one repo URL per non-blank line)
  #   dnf/yum → `/etc/yum.repos.d/syspkg-installer.repo`
  #   zypper  → `/etc/zypp/repos.d/syspkg-installer.repo`
  #   pacman  → `/etc/pacman.d/syspkg-installer.conf` (with `Include =` wired into `pacman.conf`)
  # Uses `file__append_privileged` so writes succeed whether or not the current
  # process is root.
  #
  # Args:
  #   <content>  Repository config content, possibly containing `{KEY}` tokens.
  #
  # Returns: 0 always.
  if [[ "$_OSPKG__FAMILY" = "apt" ]]; then
    ctx__expand_pattern "$1" | file__append_privileged /etc/apt/sources.list.d/syspkg-installer.list
    logging__info "Appended to /etc/apt/sources.list.d/syspkg-installer.list"
  elif [[ "$_OSPKG__FAMILY" = "apk" ]]; then
    local _rline
    while IFS= read -r _rline || [[ -n "${_rline:-}" ]]; do
      [[ -z "${_rline:-}" || "${_rline}" =~ ^[[:space:]]*# ]] && continue
      printf '%s\n' "$_rline" | file__append_privileged /etc/apk/repositories
      _OSPKG__APK_ADDED_REPOS+=("$_rline")
      logging__info "Added APK repo: ${_rline}"
    done < <(ctx__expand_pattern "$1")
  elif [[ "$_OSPKG__FAMILY" = "dnf" ]]; then
    ctx__expand_pattern "$1" | file__append_privileged /etc/yum.repos.d/syspkg-installer.repo
    logging__info "Appended to /etc/yum.repos.d/syspkg-installer.repo"
  elif [[ "$_OSPKG__FAMILY" = "zypper" ]]; then
    ctx__expand_pattern "$1" | file__append_privileged /etc/zypp/repos.d/syspkg-installer.repo
    logging__info "Appended to /etc/zypp/repos.d/syspkg-installer.repo"
  elif [[ "$_OSPKG__FAMILY" = "pacman" ]]; then
    users__run_privileged mkdir -p /etc/pacman.d
    ctx__expand_pattern "$1" | file__append_privileged /etc/pacman.d/syspkg-installer.conf
    grep -qxF 'Include = /etc/pacman.d/syspkg-installer.conf' /etc/pacman.conf ||
      printf 'Include = /etc/pacman.d/syspkg-installer.conf\n' | file__append_privileged /etc/pacman.conf
    logging__info "Written to /etc/pacman.d/syspkg-installer.conf"
  fi
  return 0
}

_ospkg__brew_run() {
  # @brief _ospkg__brew_run <args...> — Run `brew` with the correct user context, working around Homebrew's root restriction.
  #
  # Homebrew refuses to run as root on bare-metal macOS. Three cases are handled:
  #   Non-root           → run `brew` directly.
  #   Root in container  → run `brew` directly (Homebrew explicitly allows root
  #                        in containers via `HOMEBREW_ALLOW_INSTALL_FROM_API`).
  #   Root on bare metal → `su` to the owner of the Homebrew prefix and run
  #                        `brew` as that user via `users__run_as`.
  #
  # Args:
  #   <args...>  Arguments forwarded verbatim to `brew`.
  #
  # Returns: exit code of `brew`.
  if ! users__is_root; then
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
    logging__error "Could not determine Homebrew prefix."
    return 1
  }
  _owner="$(stat -f '%Su' "$_prefix" 2> /dev/null || stat -c '%U' "$_prefix" 2> /dev/null)"
  if [[ -z "${_owner:-}" || "$_owner" == "root" ]]; then
    brew "$@"
    return
  fi
  logging__info "Running brew as user '${_owner}' (brew prefix owner)."
  users__run_as "$_owner" -- brew "$@"
  return 0
}

_ospkg__configure_pm() {
  # _ospkg__configure_pm <label> <family> <pm> <pm_key> <clean_fn> <lists_path> <lists_pattern>
  logging__detect "Detected ecosystem: $1"
  _OSPKG__FAMILY="$2"
  _OSPKG__PKG_MNGR="$3"
  _OSPKG__PM_KEY="$4"
  _OSPKG__CLEAN="$5"
  _OSPKG__LISTS_PATH="$6"
  _OSPKG__LISTS_PATTERN="$7"
}

_ospkg__set_apt() {
  _ospkg__configure_pm "APT (tool: apt-get)" apt apt-get apt _ospkg__clean_apt "/var/lib/apt/lists" "*_Packages*"
  _OSPKG__UPDATE=(users__run_privileged apt-get update)
  _OSPKG__INSTALL=(users__run_privileged apt-get -y install --no-install-recommends)
  _OSPKG__REMOVE=(users__run_privileged apt-get -y --purge remove)
  # dpkg --force-depends removes the package without cascade-removing reverse-dependents.
  # Use for binary-replacement: dependents stay installed with a temporarily broken dep.
  _OSPKG__REMOVE_FORCE=(users__run_privileged dpkg --purge --force-depends)
  _OSPKG__DEB_ARCH="$(dpkg --print-architecture 2> /dev/null || uname -m)"
}

_ospkg__set_apk() {
  _ospkg__configure_pm "APK (tool: apk)" apk apk apk _ospkg__clean_apk "/var/cache/apk" "APKINDEX*"
  _OSPKG__UPDATE=(users__run_privileged apk update)
  _OSPKG__INSTALL=(users__run_privileged apk add --no-cache)
  _OSPKG__REMOVE=(users__run_privileged apk del)
  _OSPKG__REMOVE_FORCE=(users__run_privileged apk del --force-broken-world)
}

_ospkg__set_dnf() {
  _ospkg__configure_pm "DNF (tool: dnf)" dnf dnf dnf _ospkg__clean_dnf "/var/cache/dnf" "*"
  _OSPKG__UPDATE=(users__run_privileged dnf -y check-update)
  _OSPKG__INSTALL=(users__run_privileged dnf -y install)
  _OSPKG__REMOVE=(users__run_privileged dnf -y remove)
  # rpm -e --nodeps removes the package without cascade-removing reverse-dependents.
  _OSPKG__REMOVE_FORCE=(users__run_privileged rpm -e --nodeps)
  # DNF5 (Fedora 41+) renamed mark subcommands: install→user, remove→dependency.
  if dnf --version 2> /dev/null | grep -qE '(^5\.| 5\.[0-9])'; then
    _OSPKG__DNF_MARK_USER="user"
    _OSPKG__DNF_MARK_DEP="dependency"
  else
    _OSPKG__DNF_MARK_USER="install"
    _OSPKG__DNF_MARK_DEP="remove"
  fi
}

_ospkg__set_microdnf() {
  _ospkg__configure_pm "DNF (tool: microdnf)" dnf microdnf dnf _ospkg__clean_dnf "" ""
  _OSPKG__UPDATE=()
  _OSPKG__INSTALL=(users__run_privileged microdnf -y install --refresh --best --nodocs --noplugins --setopt=install_weak_deps=0)
  _OSPKG__REMOVE=(users__run_privileged microdnf -y remove)
  _OSPKG__REMOVE_FORCE=(users__run_privileged rpm -e --nodeps)
}

_ospkg__set_yum() {
  _ospkg__configure_pm "YUM (tool: yum)" dnf yum yum _ospkg__clean_dnf "/var/cache/yum" "*"
  _OSPKG__UPDATE=(users__run_privileged yum -y check-update)
  _OSPKG__INSTALL=(users__run_privileged yum -y install)
  _OSPKG__REMOVE=(users__run_privileged yum -y remove)
  _OSPKG__REMOVE_FORCE=(users__run_privileged rpm -e --nodeps)
  _OSPKG__DNF_MARK_USER="install"
  _OSPKG__DNF_MARK_DEP="remove"
}

_ospkg__set_zypper() {
  _ospkg__configure_pm "Zypper (tool: zypper)" zypper zypper zypper _ospkg__clean_zypper "/var/cache/zypp/raw" "*"
  _OSPKG__UPDATE=(users__run_privileged zypper --gpg-auto-import-keys --non-interactive refresh)
  _OSPKG__INSTALL=(_ospkg__zypper_install)
  _OSPKG__REMOVE=(users__run_privileged zypper --non-interactive remove --clean-deps)
  _OSPKG__REMOVE_FORCE=(users__run_privileged rpm -e --nodeps)
}

_ospkg__set_pacman() {
  _ospkg__configure_pm "Pacman (tool: pacman)" pacman pacman pacman _ospkg__clean_pacman "/var/lib/pacman/sync" "*.db"
  _OSPKG__UPDATE=(users__run_privileged pacman -Sy --noconfirm)
  _OSPKG__INSTALL=(users__run_privileged pacman -S --noconfirm --needed)
  _OSPKG__REMOVE=(users__run_privileged pacman -Rs --noconfirm)
  # -Rdd skips all dependency version checks; removes without cascade.
  _OSPKG__REMOVE_FORCE=(users__run_privileged pacman -Rdd --noconfirm)
}

_ospkg__set_brew() {
  local _label="${1:-Linux}"
  _ospkg__configure_pm "Homebrew (tool: brew) [${_label}]" brew brew brew _ospkg__clean_brew "" ""
  _OSPKG__UPDATE=(_ospkg__brew_run update)
  _OSPKG__INSTALL=(_ospkg__brew_run install)
  _OSPKG__REMOVE=(_ospkg__brew_run uninstall)
  _OSPKG__REMOVE_FORCE=(_ospkg__brew_run uninstall --ignore-dependencies)
}

_ospkg__detect() {
  # Detect the package manager. Idempotent; PM-only (no os-release parsing).
  [[ "$_OSPKG__DETECTED" == true ]] && return 0

  if [[ "$(uname -s)" == "Darwin" ]]; then
    if type brew > /dev/null 2>&1; then
      _ospkg__set_brew "macOS"
    fi
    _OSPKG__DETECTED=true
    return 0
  fi

  if [[ "${_OSPKG__PREFER_LINUXBREW:-false}" == "true" ]] && type brew > /dev/null 2>&1; then
    _ospkg__set_brew "Linux/Linuxbrew"
    _OSPKG__DETECTED=true
    return 0
  fi

  if type apt-get > /dev/null 2>&1; then
    _ospkg__set_apt
  elif type apk > /dev/null 2>&1; then
    _ospkg__set_apk
  elif type dnf > /dev/null 2>&1; then
    _ospkg__set_dnf
  elif type microdnf > /dev/null 2>&1; then
    _ospkg__set_microdnf
  elif type yum > /dev/null 2>&1; then
    _ospkg__set_yum
  elif type zypper > /dev/null 2>&1; then
    _ospkg__set_zypper
  elif type pacman > /dev/null 2>&1; then
    _ospkg__set_pacman
  elif type brew > /dev/null 2>&1; then
    _ospkg__set_brew "Linux/Linuxbrew"
  else
    logging__error "No supported package manager found."
    return 1
  fi

  _OSPKG__DETECTED=true
  return 0
}

ospkg__pm_key() {
  # @brief ospkg__pm_key — Print the detected package manager manifest key (e.g. `apt`, `dnf`, `yum`, `brew`).
  #
  # This is the key used in manifest YAML top-level sections and `plat.pm` when
  # clauses, not the command name (`apt-get` vs `apt`). Returns 0 when detection
  # succeeds (stdout may still be empty on Darwin without Homebrew). Returns 1 when
  # no supported package manager is found on Linux.
  #
  # Stdout: PM key, or empty when none applies.
  #
  # Returns: 0 on successful detection; 1 when detection fails.
  _ospkg__detect || return 1
  printf '%s' "${_OSPKG__PM_KEY:-}"
  return 0
}

ospkg__deb_arch() {
  # @brief ospkg__deb_arch — Print the Debian package architecture when APT is the detected PM.
  #
  # Stdout: architecture string (e.g. `amd64`), or empty on non-APT systems and when
  # detection fails.
  #
  # Returns: 0 always.
  _ospkg__detect || return 0
  printf '%s' "${_OSPKG__DEB_ARCH:-}"
  return 0
}

ospkg__pm() {
  # @brief ospkg__pm — Print the detected package manager command name (e.g. `apt-get`, `apk`, `dnf`, `brew`).
  # Returns 1 if no supported package manager was found.
  _ospkg__detect
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "no package manager detected."
    return "$_rc"
  }
  printf '%s\n' "$_OSPKG__PKG_MNGR"
}

ospkg__is_managed() {
  # @brief ospkg__is_managed <bin_path> — Return 0 if <bin_path> is owned by the OS package manager, 1 otherwise.
  #
  # Calls `_ospkg__detect` (idempotent) and dispatches on `_OSPKG__FAMILY`, so
  # the correct tool is used even when Linuxbrew is active or on Arch Linux
  # (where `os__platform` has no mapping).
  #
  # Args:
  #   <bin_path>  Absolute path to the binary to check (may be empty).
  #
  # Returns: 0 if owned by the package manager, 1 otherwise (including empty or
  #          nonexistent paths, or when no supported package manager is found).
  local _bin="${1-}"
  [[ -n "$_bin" && -e "$_bin" ]] || return 1
  _ospkg__detect
  local _rc=$?
  [[ $_rc == 0 ]] || return "$_rc"
  case "$_OSPKG__FAMILY" in
    apt) dpkg -S "$_bin" > /dev/null 2>&1 ;;
    apk) apk info --who-owns "$_bin" > /dev/null 2>&1 ;;
    dnf) rpm -qf "$_bin" > /dev/null 2>&1 ;;
    zypper) rpm -qf "$_bin" > /dev/null 2>&1 ;;
    pacman) pacman -Qo "$_bin" > /dev/null 2>&1 ;;
    brew)
      local _prefix _real
      _prefix="$(brew --prefix 2> /dev/null)" || {
        logging__error "could not determine Homebrew prefix."
        return 1
      }
      # Canonicalize prefix so macOS /var → /private/var expansion is consistent
      # with the file__canonical_path-resolved _real path used in the comparison below.
      _prefix="$(file__canonical_path "$_prefix")"
      _real="$(file__canonical_path "$_bin")"
      [[ "$_real" == /* ]] || _real="$(dirname "$_bin")/${_real}"
      [[ "$_real" == "${_prefix}/Cellar/"* || "$_real" == "${_prefix}/opt/"* ]]
      ;;
    *) return 1 ;;
  esac
}

_ospkg__assert_privilege() {
  # @brief _ospkg__assert_privilege — Fail fast when the current PM requires root or sudo but neither is available.
  #
  # brew never needs privilege; all other PMs do.
  # Must be called after _ospkg__detect so _OSPKG__PKG_MNGR is set.
  #
  # Returns: 0 if privilege is available or not needed; 1 with an error message otherwise.
  [[ "$_OSPKG__PKG_MNGR" == "brew" ]] && return 0
  if users__is_privileged; then
    return 0
  fi
  logging__error "Package manager operations require root or passwordless sudo."
  return 1
}

_ospkg__lists_index_present() {
  # _ospkg__lists_index_present — True when package-list index files exist under _OSPKG__LISTS_PATH.
  #
  # Mirrors `find <path> -mindepth 1 -maxdepth 2 -name <_OSPKG__LISTS_PATTERN>` without requiring find.
  local _root="${_OSPKG__LISTS_PATH:-}" _pat="${_OSPKG__LISTS_PATTERN:-*}" _entry _base
  [[ -n "$_root" && -d "$_root" ]] || return 1
  for _entry in "$_root"/* "$_root"/*/*; do
    [[ -e "$_entry" ]] || continue
    _base="${_entry##*/}"
    # shellcheck disable=SC2254 # _pat is a glob pattern (e.g. *_Packages*, *.db), not a literal string.
    case "$_base" in
      $_pat) return 0 ;;
    esac
  done
  return 1
}

ospkg__update() {
  # @brief ospkg__update [--force] [--lists_max_age N] [--repo_added] — Refresh the package index. Skips when lists are fresh (within `--lists_max_age` seconds).
  #
  # Args:
  #   --force             Unconditionally refresh (overrides the age check).
  #   --lists_max_age N   Skip if package lists were updated within N seconds (default: 300).
  #   --repo_added        A new repo was just added; forces an unconditional refresh.
  #
  # Returns: 0 on success.
  _ospkg__detect
  local _force=false _max_age=3600 _repo_added=false
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
        logging__error "unknown option: $1"
        return 1
        ;;
    esac
  done

  if [[ ${#_OSPKG__UPDATE[@]} -eq 0 ]]; then
    # microdnf bakes --refresh into every install call; no separate update step is needed.
    logging__info "Package list update handled per-install by '${_OSPKG__PKG_MNGR}' (--refresh) — skipping explicit update."
    return 0
  fi

  local _skip=false
  if [[ "$_force" == true || "$_repo_added" == true ]]; then
    _skip=false
  elif [[ "$_OSPKG__UPDATED" == true ]]; then
    # Already ran an update in this process — skip unless force/repo_added.
    logging__info "Package lists already updated in this process — skipping."
    _skip=true
  elif [[ "$_OSPKG__PKG_MNGR" == "brew" ]]; then
    # brew: no simple lists age check — always update unless forced off.
    _skip=false
  elif [[ -n "${_OSPKG__LISTS_PATH:-}" && -d "$_OSPKG__LISTS_PATH" ]]; then
    if _ospkg__lists_index_present; then
      local _mtime _age
      # stat -c (Linux) or stat -f (macOS)
      _mtime=$(stat -c %Y "$_OSPKG__LISTS_PATH" 2> /dev/null || stat -f %m "$_OSPKG__LISTS_PATH" 2> /dev/null || echo 0)
      _age=$(($(date +%s) - _mtime))
      if [[ $_age -lt $_max_age ]]; then
        _skip=true
        logging__info "Package lists refreshed ${_age}s ago — skipping update (threshold: ${_max_age}s)."
      fi
    fi
  fi

  if [[ "$_skip" == false ]]; then
    _ospkg__assert_privilege
    local _rc=$?
    [[ $_rc == 0 ]] || {
      logging__error "insufficient privilege to update package lists."
      return "$_rc"
    }
    logging__info "Updating package lists."
    net__fetch_with_retry --bail-on 2 --retries 10 _ospkg__update_cmd
    local _rc=$?
    [[ $_rc == 0 ]] || {
      logging__error "package list update failed."
      return "$_rc"
    }
    _OSPKG__UPDATED=true
    logging__success "Package lists updated."
  fi
  return 0
}

ospkg__install() {
  # @brief ospkg__install [--update] <pkg>... — Install one or more packages, skipping already-installed ones.
  #
  # Without --update each package is checked via PM-native query; only missing
  # packages are passed to the package manager. With --update already-installed
  # packages are also upgraded (brew uses `brew upgrade`; all other PMs upgrade
  # in place via their install command).
  #
  # Args:
  #   --update  Also upgrade already-installed packages.
  #   <pkg>...  One or more package names. PM-native version suffixes accepted
  #             (e.g. gh=2.40.0 for apt); the suffix is stripped for the
  #             existence check before calling ospkg__is_installed.
  #
  # Returns: 0 on success.
  _ospkg__detect
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "no package manager detected."
    return "$_rc"
  }
  if [[ -z "$_OSPKG__PKG_MNGR" ]]; then
    logging__error "No supported package manager found."
    if [[ "$(uname -s)" == "Darwin" ]]; then
      logging__error "Homebrew (brew) not found on macOS."
      logging__error "Install Homebrew first: https://brew.sh"
    fi
    return 1
  fi
  local _do_update=false
  if [[ "${1:-}" == "--update" ]]; then
    _do_update=true
    shift
  fi

  if [[ "$_do_update" == false ]]; then
    # Filter: collect only packages not yet installed.
    local -a _to_install=()
    local _pkg _bare
    for _pkg in "$@"; do
      # Strip PM-native version suffix for the existence check.
      case "$_OSPKG__PKG_MNGR" in
        apt-get | apk | pacman | zypper) _bare="${_pkg%%=*}" ;;
        dnf | yum | microdnf) _bare="${_pkg%-[0-9]*}" ;;
        brew) _bare="${_pkg%%@*}" ;;
        *) _bare="$_pkg" ;;
      esac
      ospkg__is_installed "$_bare" || _to_install+=("$_pkg")
    done
    if [[ ${#_to_install[@]} -eq 0 ]]; then
      logging__info "Packages already installed: $*"
      return 0
    fi
    set -- "${_to_install[@]}"
  fi

  # brew --update: split into install (new) vs upgrade (existing).
  if [[ "$_do_update" == true && "$_OSPKG__PKG_MNGR" == "brew" ]]; then
    local -a _new=() _existing=()
    local _pkg _bare
    for _pkg in "$@"; do
      _bare="${_pkg%%@*}"
      if ospkg__is_installed "$_bare"; then
        _existing+=("$_pkg")
      else
        _new+=("$_pkg")
      fi
    done
    ospkg__update
    local _rc=$?
    [[ $_rc == 0 ]] || {
      logging__error "package list update failed."
      return "$_rc"
    }
    if [[ ${#_new[@]} -gt 0 ]]; then
      logging__info "Installing packages:"
      printf '  - %s\n' "${_new[@]}" >&2
      _ospkg__brew_run install "${_new[@]}" >&2
    fi
    if [[ ${#_existing[@]} -gt 0 ]]; then
      logging__info "Upgrading packages:"
      printf '  - %s\n' "${_existing[@]}" >&2
      _ospkg__brew_run upgrade "${_existing[@]}" >&2
    fi
    return 0
  fi

  _ospkg__assert_privilege
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "insufficient privilege to install packages."
    return "$_rc"
  }
  ospkg__update
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "package list update failed."
    return "$_rc"
  }
  logging__info "Installing packages:"
  printf '  - %s\n' "$@" >&2
  # Keep interactive mode possible on TTY, but prevent PMs from draining
  # caller-provided stdin in piped/non-interactive contexts.
  # zypper: _OSPKG__INSTALL is _ospkg__zypper_install, which runs zypper with
  # --no-refresh and normalises exit codes so that a successful install from
  # available repos is always treated as exit 6 (repos-skipped) even when zypper
  # returns a different non-zero code due to CDN failures on secondary repos.
  # --bail-on 6 stops net__fetch_with_retry immediately (no 60-attempt loop),
  # and [[ _rc -eq 6 ]] below converts that to a clean 0 return.
  local _rc=0
  if [[ "$_OSPKG__PKG_MNGR" == "zypper" ]]; then
    if [[ -t 0 ]]; then
      net__fetch_with_retry --bail-on 6 "${_OSPKG__INSTALL[@]}" "$@" >&2 || _rc=$?
    else
      net__fetch_with_retry --bail-on 6 "${_OSPKG__INSTALL[@]}" "$@" < /dev/null >&2 || _rc=$?
    fi
    [[ "$_rc" -eq 6 ]] && return 0
  elif [[ -t 0 ]]; then
    net__fetch_with_retry "${_OSPKG__INSTALL[@]}" "$@" >&2 || _rc=$?
  elif [[ "$_OSPKG__PKG_MNGR" == "apt-get" && -z "${DEBIAN_FRONTEND-}" ]]; then
    DEBIAN_FRONTEND=noninteractive net__fetch_with_retry "${_OSPKG__INSTALL[@]}" "$@" < /dev/null >&2 || _rc=$?
  else
    net__fetch_with_retry "${_OSPKG__INSTALL[@]}" "$@" < /dev/null >&2 || _rc=$?
  fi
  if ((_rc != 0)); then
    logging__error "failed to install packages: $*."
    return 1
  fi
  return 0
}

ospkg__clean() {
  # @brief ospkg__clean — Remove the package manager cache to reduce image layer size.
  #
  # Returns: 0 on success.
  _ospkg__detect
  [[ -z "${_OSPKG__CLEAN:-}" ]] && return 0
  logging__clean "Cleaning package manager cache."
  "$_OSPKG__CLEAN"
  return 0
}

ospkg__parse_manifest_yaml() {
  # @brief ospkg__parse_manifest_yaml <json-file> — Parse a YAML manifest (pre-converted to JSON by `yq`) and emit normalised installation records to stdout.
  #
  # Requires jq in PATH and context populated via `_ctx__ensure_registry` / `ctx__set`.
  # Each record is a compact JSON object with a "kind" field.
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
  #
  # Args:
  #   <json-file>  Path to the manifest JSON file (use `yq -o=json` to convert YAML first).
  #
  # Stdout: one compact JSON record per line.
  #
  # Returns: 0 on success.
  local _json_file="$1"
  local _ctx_json _pm
  _ctx_json="$(ctx__json)"
  _pm="$(ctx__get plat.pm)"
  [[ -n "${_pm}" ]] || _pm="${_OSPKG__PM_KEY:-${_OSPKG__FAMILY:-}}"

  json__query -c -L "${_OSPKG__LIB_DIR}" \
    --argjson ctx "$_ctx_json" \
    --arg pm "$_pm" \
    -f "${_OSPKG__LIB_DIR}/ospkg-manifest.jq" \
    "$_json_file"
  return 0
}

_ospkg__build_deps_dir() {
  # _ospkg__build_deps_dir — returns the directory used for build-dep sidecar files.
  printf '%s' "$(file__tmpdir "ospkg/build-deps")"
  return
}

_ospkg__protect_user_pkgs() {
  # _ospkg__protect_user_pkgs <pkg-name>... — mark packages as user-requested so
  # build-group cleanup cannot remove them. Accepts bare package names only (no
  # version suffixes). Applies PM-native marking for marking-capable PMs and
  # evicts each package from every build-group sidecar (covers explicit-list PMs:
  # apk, zypper, microdnf, brew). All operations are non-fatal.
  [[ $# -eq 0 ]] && return 0
  _ospkg__detect
  # PM-native marking: reverse any auto/asdeps/removable mark on these packages.
  case "$_OSPKG__PKG_MNGR" in
    apt-get) users__run_privileged apt-mark manual "$@" > /dev/null 2>&1 || true ;;
    dnf | yum) users__run_privileged "$_OSPKG__PKG_MNGR" -y mark "${_OSPKG__DNF_MARK_USER}" "$@" > /dev/null 2>&1 || true ;;
    pacman) users__run_privileged pacman -D --asexplicit "$@" > /dev/null 2>&1 || true ;;
    *) ;;
  esac
  # Sidecar eviction: remove each package from every build-group sidecar so
  # explicit-list PMs do not delete them during build-group cleanup.
  local _bd_dir _sidecar _sidecar_name _pkg _tmp
  _bd_dir="$(_ospkg__build_deps_dir)"
  [[ -d "$_bd_dir" ]] || return 0
  for _sidecar in "$_bd_dir"/*; do
    [[ -f "$_sidecar" ]] || continue
    _sidecar_name="$(basename "$_sidecar")"
    # Skip temporary snapshot files used during build-dep tracking.
    [[ "$_sidecar_name" == *.before || "$_sidecar_name" == *.after || "$_sidecar_name" == *.apkvirts || "$_sidecar_name" == .global_auto_before ]] && continue
    for _pkg in "$@"; do
      if grep -qxF "$_pkg" "$_sidecar" 2> /dev/null; then
        _tmp="${_sidecar}.protect_tmp"
        grep -Fxv "$_pkg" "$_sidecar" > "$_tmp" 2> /dev/null || true
        if [[ -s "$_tmp" ]]; then
          mv "$_tmp" "$_sidecar"
        else
          rm -f "$_tmp" "$_sidecar"
        fi
        logging__info "Evicted '${_pkg}' from build-group sidecar '${_sidecar_name}'."
      fi
    done
  done
  return 0
}

ospkg__take_initial_snapshot() {
  # @brief ospkg__take_initial_snapshot <file> — Snapshot the current installed-package list to `<file>` as a session baseline.
  #
  # Called once by install.bash before any installs in manifest mode. Used by
  # `ospkg__install_tracked` to exclude pre-existing packages from session
  # co-ownership tracking.
  #
  # Args:
  #   <file>  Destination path for the snapshot (one package name per line).
  #
  # Returns: 0 on success.
  local _dest="$1"
  _ospkg__detect
  _ospkg__snapshot_packages "$_dest"
  logging__info "Initial package snapshot written to ${_dest}."
  return 0
}

_ospkg__global_auto_snapshot_file() {
  # _ospkg__global_auto_snapshot_file — print the path for the global pre-install
  # auto-state snapshot. When the live registry is active it is relocated to the
  # registry root (shared across concurrent invocations; first-in snapshots,
  # last-out restores). Otherwise it lives alongside the per-invocation build-dep
  # sidecars (today's behaviour, byte-compatible).
  local _root
  if _ospkg__registry_active && _root="$(_ospkg__registry_root)" && [[ -n "$_root" ]]; then
    printf '%s/.global_auto_before' "$_root"
    return 0
  fi
  printf '%s/.global_auto_before' "$(_ospkg__build_deps_dir)"
}

_ospkg__snap_exists() {
  # _ospkg__snap_exists <file> — test existence of a global-auto snapshot file,
  # routing through the registry privilege channel when the registry is active.
  local _f="$1"
  if _ospkg__registry_active; then
    _ospkg__reg_run test -f "$_f"
  else
    [[ -f "$_f" ]]
  fi
}

_ospkg__snap_write() {
  # _ospkg__snap_write <file> — write stdin to a global-auto snapshot file.
  local _f="$1"
  if _ospkg__registry_active; then
    _ospkg__reg_write "$_f"
  else
    cat > "$_f"
  fi
}

_ospkg__snap_read() {
  # _ospkg__snap_read <file> — print a global-auto snapshot file (empty if absent).
  local _f="$1"
  if _ospkg__registry_active; then
    _ospkg__reg_read "$_f"
  else
    cat "$_f" 2> /dev/null || true
  fi
}

_ospkg__snap_rm() {
  # _ospkg__snap_rm <file> — remove a global-auto snapshot file.
  local _f="$1"
  if _ospkg__registry_active; then
    _ospkg__reg_run rm -f "$_f" 2> /dev/null || true
  else
    rm -f "$_f"
  fi
}

_ospkg__ensure_global_auto_snapshot() {
  # _ospkg__ensure_global_auto_snapshot — idempotent; called before the first
  # ospkg__install_tracked install. Snapshots the current auto/dep-marked packages
  # and temporarily pins them as manual so PM-native autoremove during cleanup
  # cannot touch packages that pre-existed our build.
  local _snap
  _snap="$(_ospkg__global_auto_snapshot_file)"
  _ospkg__snap_exists "$_snap" && return 0
  case "$_OSPKG__PKG_MNGR" in
    apt-get)
      apt-mark showauto 2> /dev/null | sort | _ospkg__snap_write "$_snap"
      local -a _auto_pkgs=()
      mapfile -t _auto_pkgs < <(_ospkg__snap_read "$_snap")
      [[ ${#_auto_pkgs[@]} -gt 0 ]] &&
        users__run_privileged apt-mark manual "${_auto_pkgs[@]}" > /dev/null 2>&1 || true
      ;;
    dnf | yum)
      # comm -23: packages not in userinstalled = dep-installed; pin those as
      # user-installed so autoremove won't touch them during our cleanup.
      comm -23 \
        <(rpm -qa --queryformat='%{NAME}\n' 2> /dev/null | sort) \
        <("$_OSPKG__PKG_MNGR" history userinstalled 2> /dev/null | sort) | _ospkg__snap_write "$_snap"
      local -a _dep_pkgs=()
      mapfile -t _dep_pkgs < <(_ospkg__snap_read "$_snap")
      [[ ${#_dep_pkgs[@]} -gt 0 ]] &&
        users__run_privileged "$_OSPKG__PKG_MNGR" -y mark "${_OSPKG__DNF_MARK_USER}" "${_dep_pkgs[@]}" > /dev/null 2>&1 || true
      ;;
    pacman)
      # Snapshot all asdeps packages and temporarily mark them asexplicit so
      # 'pacman -Qdtq' only surfaces packages we newly installed.
      pacman -Qq --deps 2> /dev/null | sort | _ospkg__snap_write "$_snap"
      local -a _dep_pkgs=()
      mapfile -t _dep_pkgs < <(_ospkg__snap_read "$_snap")
      [[ ${#_dep_pkgs[@]} -gt 0 ]] &&
        users__run_privileged pacman -D --asexplicit "${_dep_pkgs[@]}" > /dev/null 2>&1 || true
      ;;
    *)
      # apk uses virtual groups; zypper/microdnf/brew use per-package safe removal.
      # Create an empty sentinel so subsequent calls skip this work.
      printf '' | _ospkg__snap_write "$_snap"
      ;;
  esac
  return 0
}

_ospkg__restore_global_auto_state() {
  # _ospkg__restore_global_auto_state — called after all build groups are cleaned.
  # Restores pre-existing auto-marked packages back to their original state and
  # removes the snapshot file. Idempotent (no-op if no snapshot was taken).
  local _snap
  _snap="$(_ospkg__global_auto_snapshot_file)"
  _ospkg__snap_exists "$_snap" || return 0
  local -a _pkgs=()
  mapfile -t _pkgs < <(_ospkg__snap_read "$_snap")
  _ospkg__snap_rm "$_snap"
  [[ ${#_pkgs[@]} -eq 0 ]] && return 0
  # Intersect snapshot with currently installed packages in one batch query.
  # Some packages may have been removed as build deps and no longer exist.
  local -a _still_installed=()
  case "$_OSPKG__PKG_MNGR" in
    apt-get)
      mapfile -t _still_installed < <(comm -12 \
        <(printf '%s\n' "${_pkgs[@]}") \
        <(dpkg-query -W -f='${Package}\n' 2> /dev/null | sort))
      [[ ${#_still_installed[@]} -gt 0 ]] &&
        users__run_privileged apt-mark auto "${_still_installed[@]}" > /dev/null 2>&1 || true
      ;;
    dnf | yum)
      mapfile -t _still_installed < <(comm -12 \
        <(printf '%s\n' "${_pkgs[@]}") \
        <(rpm -qa --queryformat='%{NAME}\n' 2> /dev/null | sort))
      [[ ${#_still_installed[@]} -gt 0 ]] &&
        users__run_privileged "$_OSPKG__PKG_MNGR" -y mark "${_OSPKG__DNF_MARK_DEP}" "${_still_installed[@]}" > /dev/null 2>&1 || true
      ;;
    pacman)
      mapfile -t _still_installed < <(comm -12 \
        <(printf '%s\n' "${_pkgs[@]}") \
        <(pacman -Qq 2> /dev/null | sort))
      [[ ${#_still_installed[@]} -gt 0 ]] &&
        users__run_privileged pacman -D --asdeps "${_still_installed[@]}" > /dev/null 2>&1 || true
      ;;
    *) ;;
  esac
  return 0
}

_ospkg__apk_virtual_name() {
  # _ospkg__apk_virtual_name <group_id> — emit a valid APK virtual package name
  # derived from <group_id>. Format: .df-<sanitized> (dot prefix, lowercase alnum
  # and hyphens). Dot prefix prevents conflicts with real package names.
  local _name="${1//[^a-zA-Z0-9_-]/-}"
  _name="${_name,,}"
  printf '.df-%s' "$_name"
}

_ospkg__apk_virts_file() {
  # _ospkg__apk_virts_file <sidecar_path> — print the path for the auxiliary file
  # that stores the list of APK virtual package names created for a build group.
  printf '%s.apkvirts' "$1"
}

ospkg__is_installed() {
  # @brief ospkg__is_installed <pkg>... — Return 0 if all listed packages are installed.
  #
  # Uses PM-native point queries; no subshell, no file I/O. Calls `_ospkg__detect`
  # automatically. Accepts bare package names only (no version suffixes).
  #
  # Args:
  #   <pkg>...  One or more bare package names.
  #
  # Returns: 0 if all packages are installed, 1 if any is missing or PM unknown.
  _ospkg__detect
  local _rc=$?
  [[ $_rc == 0 ]] || return "$_rc"
  local _pkg
  for _pkg in "$@"; do
    case "$_OSPKG__PKG_MNGR" in
      apt-get) dpkg -s "$_pkg" > /dev/null 2>&1 ;;
      apk) apk info -e "$_pkg" > /dev/null 2>&1 ;;
      dnf | yum | microdnf) rpm -q "$_pkg" > /dev/null 2>&1 ;;
      zypper) rpm -q "$_pkg" > /dev/null 2>&1 ;;
      pacman) pacman -Qq "$_pkg" > /dev/null 2>&1 ;;
      brew) brew list --formula "$_pkg" > /dev/null 2>&1 ;;
      *) return 1 ;;
    esac || return 1
  done
}

_ospkg__command_satisfied() {
  # _ospkg__command_satisfied <update-flag> <command> [runtime-path] — Whether a
  # manifest package's PATH guard (`command:`) is satisfied, so it can be skipped.
  #
  # A runtime dependency is treated as satisfied when the named command resolves
  # on the *runtime* PATH, regardless of how it was installed (a binary/cargo/npm
  # install by another feature, or an existing system tool). This is the cross-
  # platform, method-agnostic complement to ospkg__is_installed (which only sees
  # PM-registered packages). Gated off under --update so refresh runs still
  # (re)install deps — matching the PM-native already-installed skip.
  #
  # Args:
  #   <update-flag>   "true" when installing with --update (guard disabled); else "false".
  #   <command>       Command to probe; empty/absent means no guard (returns 1).
  #   [runtime-path]  PATH to probe against — the feature's resolved runtime_path,
  #                   i.e. where the tool will resolve when the user runs it. Empty
  #                   or absent falls back to the ambient install-time PATH.
  #
  # Returns: 0 when the guard is satisfied (skip the package); 1 otherwise.
  local _update="${1:-false}" _cmd="${2:-}" _path="${3:-}"
  [[ "$_update" == false && -n "$_cmd" ]] || return 1
  if [[ -n "$_path" ]]; then
    PATH="$_path" command -v "$_cmd" > /dev/null 2>&1
  else
    command -v "$_cmd" > /dev/null 2>&1
  fi
}

_ospkg__snapshot_packages() {
  # _ospkg__snapshot_packages <dest-file> — writes a sorted list of installed
  # package names (one per line) to <dest-file>.
  local _dest="$1"
  case "$_OSPKG__PKG_MNGR" in
    apt-get) dpkg-query -W -f='${Package}\n' 2> /dev/null | sort > "$_dest" ;;
    apk) apk info 2> /dev/null | sort > "$_dest" ;;
    dnf | yum | microdnf) rpm -qa --queryformat='%{NAME}\n' 2> /dev/null | sort > "$_dest" ;;
    zypper) rpm -qa --queryformat='%{NAME}\n' 2> /dev/null | sort > "$_dest" ;;
    pacman) pacman -Qq 2> /dev/null | sort > "$_dest" ;;
    brew) brew list 2> /dev/null | sort > "$_dest" ;;
    *) : > "$_dest" ;;
  esac
  return 0
}

_ospkg__mark_build_group() {
  # _ospkg__mark_build_group <group-id> <before-file> — diff current state against
  # <before-file>, apply PM-native removable marking to newly-installed packages,
  # and write the sidecar tracking file.
  local _group_id="$1" _before_file="$2"
  local _deps_dir _after_file _sidecar
  _deps_dir="$(_ospkg__build_deps_dir)"
  _after_file="${_deps_dir}/${_group_id//\//_}.after"
  _sidecar="${_deps_dir}/${_group_id//\//_}"
  _ospkg__snapshot_packages "$_after_file"
  local -a _new_pkgs=()
  mapfile -t _new_pkgs < <(comm -13 "$_before_file" "$_after_file" 2> /dev/null)
  rm -f "$_after_file"
  if [[ ${#_new_pkgs[@]} -eq 0 ]]; then
    logging__info "Build group '${_group_id}': no new packages installed — nothing to track."
    # Preserve an existing sidecar (may already list packages from a prior call
    # with the same group ID).  Only create an empty sentinel if not yet present.
    [[ ! -f "$_sidecar" ]] && : > "$_sidecar"
    return 0
  fi
  logging__info "Build group '${_group_id}': tracking ${#_new_pkgs[@]} package(s): ${_new_pkgs[*]}"
  # Append to the sidecar so that multiple calls with the same group ID
  # accumulate all tracked packages (idempotent across repeat calls).
  printf '%s\n' "${_new_pkgs[@]}" >> "$_sidecar"
  sort -u "$_sidecar" -o "$_sidecar"
  # Apply PM-native removable marking to newly-installed packages only.
  # Safety: _new_pkgs is derived from a before/after snapshot diff taken in
  # ospkg__install_tracked, so it only contains packages that were absent before
  # this call. Packages already installed (e.g. from run.base in the header)
  # never appear here and their manual marks are therefore never disturbed.
  case "$_OSPKG__PKG_MNGR" in
    apt-get)
      users__run_privileged apt-mark auto "${_new_pkgs[@]}" >&2 || true
      ;;
    dnf | yum)
      users__run_privileged "$_OSPKG__PKG_MNGR" -y mark "${_OSPKG__DNF_MARK_DEP}" "${_new_pkgs[@]}" >&2 || true
      ;;
    pacman)
      users__run_privileged pacman -D --asdeps "${_new_pkgs[@]}" >&2 || true
      ;;
    *) ;;
  esac
  return 0
}

_ospkg__remove_build_group() {
  # _ospkg__remove_build_group <group-id> — remove previously-installed build-only
  # packages using PM-native mechanisms based on the sidecar tracking file.
  local _group_id="$1"
  local _deps_dir _sidecar
  _deps_dir="$(_ospkg__build_deps_dir)"
  _sidecar="${_deps_dir}/${_group_id//\//_}"
  if [[ ! -f "$_sidecar" ]]; then
    logging__info "Build group '${_group_id}': sidecar not found — nothing to remove."
    return 0
  fi
  local -a _pkgs=()
  mapfile -t _pkgs < "$_sidecar"
  if [[ ${#_pkgs[@]} -eq 0 ]]; then
    logging__info "Build group '${_group_id}': sidecar empty — nothing to remove."
    return 0
  fi
  logging__remove "Build group '${_group_id}': removing ${#_pkgs[@]} package(s): ${_pkgs[*]}"
  local _pkg
  case "$_OSPKG__PKG_MNGR" in
    apt-get)
      # Pre-existing auto-marked packages were pinned manual by
      # _ospkg__ensure_global_auto_snapshot, so autoremove only removes build
      # deps installed in this session. Explicit list removal is avoided because
      # it cascades to reverse-dependencies regardless of manual marks.
      users__run_privileged apt-get -y --purge autoremove >&2 || true
      ;;
    apk)
      # Remove the APK virtual groups created during ospkg__install_tracked.
      # apk del VIRT removes each virtual's packages unless still needed by world.
      local _virts_file _virt_name
      _virts_file="$(_ospkg__apk_virts_file "$_sidecar")"
      if [[ -f "$_virts_file" ]]; then
        while IFS= read -r _virt_name; do
          [[ -z "$_virt_name" ]] && continue
          users__run_privileged apk del "$_virt_name" >&2 || true
        done < "$_virts_file"
        rm -f "$_virts_file"
      else
        # Fallback for sidecars written before virtual tracking was added.
        for _pkg in "${_pkgs[@]}"; do
          users__run_privileged apk del "$_pkg" >&2 || true
        done
      fi
      ;;
    dnf | yum)
      # Pre-existing dep-marked packages were pinned user-installed by
      # _ospkg__ensure_global_auto_snapshot, so only our build deps are eligible.
      users__run_privileged "$_OSPKG__PKG_MNGR" -y autoremove >&2 || true
      ;;
    microdnf)
      # microdnf has no mark or autoremove; remove per-package so a single
      # blocked removal does not prevent the rest from being cleaned.
      for _pkg in "${_pkgs[@]}"; do
        users__run_privileged microdnf remove "$_pkg" >&2 || true
      done
      ;;
    zypper)
      # zypper has no native autoremove. Remove one package at a time so that a
      # package still required by a user install blocks only itself, not the
      # whole transaction.
      for _pkg in "${_pkgs[@]}"; do
        users__run_privileged zypper --non-interactive remove --clean-deps "$_pkg" >&2 || true
      done
      ;;
    pacman)
      # Pre-existing asdeps packages were pinned asexplicit by
      # _ospkg__ensure_global_auto_snapshot, so pacman -Qdtq lists only orphaned
      # build deps we introduced. -Rns removes each orphan and its now-unneeded deps.
      local -a _orphans=()
      mapfile -t _orphans < <(pacman -Qdtq 2> /dev/null)
      [[ ${#_orphans[@]} -gt 0 ]] &&
        users__run_privileged pacman -Rns --noconfirm "${_orphans[@]}" >&2 || true
      ;;
    brew)
      for _pkg in "${_pkgs[@]}"; do
        if [[ -z "$(brew uses --installed "$_pkg" 2> /dev/null)" ]]; then
          _ospkg__brew_run remove "$_pkg" >&2 || true
        else
          logging__info "brew: keeping '$_pkg' (still in use)."
        fi
      done
      ;;
  esac
  rm -f "$_sidecar"
  return 0
}

# ── Live registry (concurrency-safe build-dep co-ownership) ───────────────────
# A machine-visible registry, shared across all concurrent installer invocations
# and features, co-located with the guarded package state (the feature-share-dir
# namespace parent for system PMs; the user share dir for brew). It lets the LAST
# invocation to exit ("last-out") perform the machine-global build-dep purge,
# global-auto restore, cache clean, and bootstrap-bash removal, while earlier
# ("parked") invocations skip those shared teardown steps so they cannot reap a
# still-live sibling's in-use build dependencies. All filesystem ops for system
# PMs route through users__run_privileged (the same channel tracked installs use);
# brew and the _OSPKG__REGISTRY_ROOT test override run direct.

_ospkg__registry_root() {
  # _ospkg__registry_root — print the registry root for the active PM, or return
  # 1 when none applies (unknown PM, or the share-dir base var is unset).
  if [[ -n "${_OSPKG__REGISTRY_ROOT:-}" ]]; then
    printf '%s' "${_OSPKG__REGISTRY_ROOT}"
    return 0
  fi
  case "${_OSPKG__PKG_MNGR:-}" in
    brew)
      [[ -n "${_FEAT_SHARE_DIR_NONROOT:-}" ]] || return 1
      printf '%s/.ospkg-live' "$(dirname "${_FEAT_SHARE_DIR_NONROOT}")"
      ;;
    '')
      return 1
      ;;
    *)
      [[ -n "${_FEAT_SHARE_DIR_ROOT:-}" ]] || return 1
      printf '%s/.ospkg-live' "$(dirname "${_FEAT_SHARE_DIR_ROOT}")"
      ;;
  esac
  return 0
}

_ospkg__registry_active() {
  # _ospkg__registry_active — return 0 when the live registry is usable for the
  # active PM. System PMs require privilege (a nonroot-no-sudo invocation cannot
  # do tracked installs, so the registry no-ops and behaviour degrades to today).
  local _root
  _root="$(_ospkg__registry_root)" || return 1
  [[ -n "$_root" ]] || return 1
  [[ -n "${_OSPKG__REGISTRY_ROOT:-}" ]] && return 0   # test override → active (direct)
  [[ "${_OSPKG__PKG_MNGR:-}" == "brew" ]] && return 0 # brew → active (user-owned)
  users__is_privileged                                # system PM → needs privilege
}

_ospkg__reg_privileged() {
  # _ospkg__reg_privileged — return 0 when registry filesystem ops must be wrapped
  # in users__run_privileged (system PMs). The test override and brew run direct.
  [[ -n "${_OSPKG__REGISTRY_ROOT:-}" ]] && return 1
  [[ "${_OSPKG__PKG_MNGR:-}" == "brew" ]] && return 1
  return 0
}

_ospkg__reg_run() {
  # _ospkg__reg_run <cmd>... — run a registry filesystem command with the correct
  # privilege routing.
  if _ospkg__reg_privileged; then
    users__run_privileged "$@"
  else
    "$@"
  fi
}

_ospkg__reg_write() {
  # _ospkg__reg_write <file> — write stdin to <file> with the correct privilege
  # routing (a privileged `tee` for system PMs; a direct redirect otherwise).
  local _file="$1"
  if _ospkg__reg_privileged; then
    users__run_privileged tee "$_file" > /dev/null
  else
    cat > "$_file"
  fi
}

_ospkg__reg_read() {
  # _ospkg__reg_read <file> — print <file> (empty when absent), privilege-routed.
  _ospkg__reg_run cat "$1" 2> /dev/null || true
}

_ospkg__reg_list() {
  # _ospkg__reg_list <dir> — print entry basenames of <dir> (empty when absent).
  _ospkg__reg_run ls -1A "$1" 2> /dev/null || true
}

_ospkg__reg_path_age_gt() {
  # _ospkg__reg_path_age_gt <path> <seconds> — return 0 when <path> mtime is older
  # than <seconds>.
  local _path="$1" _secs="$2" _mtime _now
  _mtime="$(_ospkg__reg_run stat -c %Y "$_path" 2> /dev/null || _ospkg__reg_run stat -f %m "$_path" 2> /dev/null || true)"
  [[ -n "${_mtime:-}" ]] || return 1
  _now="$(date +%s)"
  ((_now - _mtime > _secs))
}

_ospkg__proc_token() {
  # _ospkg__proc_token [<pid>] — print a stable per-process token (the process
  # start time) that guards against PID reuse. On Linux the PRIMARY source is
  # /proc/<pid>/stat starttime (field 22): deterministic and load-insensitive.
  # `ps -o lstart=` is only the fallback (e.g. macOS, no /proc). The sources must
  # not be mixed within a run: register-time and check-time must agree, so a
  # transient `ps` failure that silently switched representations (date string vs
  # clock ticks) would misjudge a live registrant as PID-reused and wrongly purge.
  # Prints `noproc` when neither is available.
  local _pid="${1:-$$}" _t=""
  if [[ -r "/proc/${_pid}/stat" ]]; then
    local _line _rest
    _line="$(cat "/proc/${_pid}/stat" 2> /dev/null)"
    _rest="${_line##*) }"
    _t="$(printf '%s\n' "$_rest" | awk '{print $20}')"
  fi
  if [[ -z "$_t" ]]; then
    _t="$(ps -o lstart= -p "$_pid" 2> /dev/null | tr -s '[:space:]' '_')"
    _t="${_t#_}"
    _t="${_t%_}"
  fi
  [[ -n "$_t" ]] || _t="noproc"
  printf '%s' "$_t"
}

_ospkg__registrant_alive() {
  # _ospkg__registrant_alive <pid> <token> — return 0 when the process is alive
  # AND its current start-time token matches <token> (guards PID reuse).
  local _pid="$1" _token="$2" _cur
  [[ -n "$_pid" ]] || return 1
  _ospkg__reg_run kill -0 "$_pid" 2> /dev/null || return 1
  _cur="$(_ospkg__proc_token "$_pid")"
  [[ "$_cur" == "$_token" ]]
}

_ospkg__session_reg_key() {
  # _ospkg__session_reg_key — print the session registrant key derived from a hash
  # of _SYSSET_SESSION_TRACK_DIR so a live session appears as one registrant.
  local _h
  _h="$(printf '%s' "${_SYSSET_SESSION_TRACK_DIR:-}" | cksum 2> /dev/null | awk '{print $1}')"
  [[ -n "${_h:-}" ]] || _h="0"
  printf 'session.%s' "$_h"
}

_ospkg__self_keep() {
  # _ospkg__self_keep — print this invocation's keep_build_deps intent (best-effort
  # from the KEEP_BUILD_DEPS install.bash global; false when unset).
  if [[ "${KEEP_BUILD_DEPS:-false}" == "true" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

_ospkg__mutex_owner_entry() {
  # _ospkg__mutex_owner_entry <mutex-dir> — print the single owner.<pid>.<token>
  # subdir name that records the current holder (empty when none). Ownership is a
  # DIRECTORY, not a file, so a takeover can remove exactly one owner generation
  # with an atomic, identity-specific rmdir (see _ospkg__mutex_acquire).
  local _mutex="$1" _e
  while IFS= read -r _e; do
    [[ "$_e" == owner.* ]] && {
      printf '%s' "$_e"
      return 0
    }
  done < <(_ospkg__reg_list "$_mutex")
  return 0
}

_ospkg__mutex_acquire() {
  # _ospkg__mutex_acquire <root> — acquire the registry mutex.
  #
  # Exclusion is the atomic `mkdir` of the lock dir (only one racer wins). The
  # holder records itself as an identity-named SUBDIR `owner.<pid>.<token>`. A DEAD
  # (or age-force-broken) owner is taken over by `rmdir`-ing exactly that subdir:
  # rmdir is atomic AND name-specific, so only one racer removes a given owner
  # generation (the rest get ENOENT and re-loop), and — crucially — a racer still
  # acting on a stale "evict the dead owner" decision can only ever rmdir that dead
  # name. A concurrent winner has already installed a DIFFERENTLY-named owner dir,
  # so the stale evictor's rmdir gets ENOENT and it re-loops instead of evicting a
  # live holder. This closes the takeover TOCTOU of the older owner-FILE rename,
  # where a stale evictor could `mv` away a freshly-written live owner and admit a
  # second holder into the critical section. Bounded; never deadlocks.
  local _root="$1"
  local _mutex="${_root}/mutex"
  local _self _tries=0
  # Absolute anti-deadlock cap, kept well ABOVE the staleness backstop so a
  # legitimately long-held lock is reclaimed by the age-based takeover below,
  # never force-broken while its owner is alive and working.
  local _max_tries=$(((${_OSPKG__REGISTRY_STALE_SECS:-900} + 300) * 5))
  _self="$$.$(_ospkg__proc_token "$$")"
  # Ensure the registry root exists so the atomic (non -p) mkdir of the mutex dir
  # can only fail on EEXIST (lock held), never ENOENT (missing parent).
  _ospkg__reg_run mkdir -p "$_root" 2> /dev/null || true
  while true; do
    if _ospkg__reg_run mkdir "$_mutex" 2> /dev/null; then
      # We hold the lock dir. Record ourselves as owner (best-effort: exclusion is
      # the lock dir itself; the owner subdir only enables dead-owner recovery).
      _ospkg__reg_run mkdir "${_mutex}/owner.${_self}" 2> /dev/null || true
      return 0
    fi
    local _owner_entry _owner _pid _token
    _owner_entry="$(_ospkg__mutex_owner_entry "$_mutex")"
    if [[ -z "$_owner_entry" ]]; then
      # No owner subdir yet: the holder died between the two mkdirs, or a takeover
      # is mid-flight. Reclaim only once the dir is older than the backstop.
      if _ospkg__reg_path_age_gt "$_mutex" "${_OSPKG__REGISTRY_STALE_SECS:-900}"; then
        _ospkg__reg_run rm -rf "$_mutex" 2> /dev/null || true
      fi
    else
      _owner="${_owner_entry#owner.}"
      _pid="${_owner%%.*}"
      _token="${_owner#*.}"
      if ! _ospkg__registrant_alive "$_pid" "$_token" ||
        _ospkg__reg_path_age_gt "${_mutex}/${_owner_entry}" "${_OSPKG__REGISTRY_STALE_SECS:-900}"; then
        # Atomic, identity-specific takeover — see the header note.
        if _ospkg__reg_run rmdir "${_mutex}/${_owner_entry}" 2> /dev/null; then
          _ospkg__reg_run mkdir "${_mutex}/owner.${_self}" 2> /dev/null || true
          return 0
        fi
      fi
    fi
    _tries=$((_tries + 1))
    if ((_tries >= _max_tries)); then
      logging__warn "ospkg registry: mutex acquire exceeded the deadlock cap — forcing takeover."
      _ospkg__reg_run rm -rf "$_mutex" 2> /dev/null || true
      _tries=0
    fi
    sleep 0.2
  done
}

_ospkg__mutex_release() {
  # _ospkg__mutex_release <root> — release the registry mutex.
  _ospkg__reg_run rm -rf "${1}/mutex" 2> /dev/null || true
}

_ospkg__registry_register() {
  # _ospkg__registry_register — register this invocation in the live registry
  # (lazily, idempotent per process). In session mode a single session-keyed
  # registrant is (re)written so the session appears live across child processes.
  # The FIRST registrant takes the shared global-auto snapshot under the mutex.
  [[ "${_OSPKG__REGISTERED}" == true ]] && return 0
  _ospkg__registry_active || return 0
  local _root
  _root="$(_ospkg__registry_root)" || return 0
  _ospkg__reg_run mkdir -p "${_root}/registrants" "${_root}/groups" 2> /dev/null || return 0
  local _self_key
  if [[ -n "${_SYSSET_SESSION_TRACK_DIR:-}" ]]; then
    _self_key="$(_ospkg__session_reg_key)"
  else
    _OSPKG__SELF_TOKEN="$(_ospkg__proc_token "$$")"
    _self_key="$$.${_OSPKG__SELF_TOKEN}"
  fi
  _ospkg__mutex_acquire "$_root"
  local _existing
  _existing="$(_ospkg__reg_list "${_root}/registrants")"
  {
    printf 'feat=%s\n' "${_FEAT_ID:-unknown}"
    printf 'keep=%s\n' "$(_ospkg__self_keep)"
    printf 'pm=%s\n' "${_OSPKG__PKG_MNGR:-}"
  } | _ospkg__reg_write "${_root}/registrants/${_self_key}"
  if [[ -z "${_existing//[[:space:]]/}" ]]; then
    _ospkg__ensure_global_auto_snapshot
  fi
  _ospkg__mutex_release "$_root"
  _OSPKG__REGISTERED=true
  return 0
}

_ospkg__registry_mirror_group() {
  # _ospkg__registry_mirror_group <group-id> — mirror the local build-group
  # sidecar (+ .keep, + .apkvirts for apk) into the registry `groups/` so it
  # survives this invocation's temp session root. Non-session mode only; keep is
  # keep-wins with any existing registry entry for the same group name.
  _ospkg__registry_active || return 0
  local _group_id="$1"
  local _root _bd_dir _name _sidecar _gfile _keep _existing_keep
  _root="$(_ospkg__registry_root)" || return 0
  _bd_dir="$(_ospkg__build_deps_dir)"
  _name="${_group_id//\//_}"
  _sidecar="${_bd_dir}/${_name}"
  [[ -f "$_sidecar" ]] || return 0
  _ospkg__reg_run mkdir -p "${_root}/groups" 2> /dev/null || return 0
  _gfile="${_root}/groups/${_name}"
  {
    _ospkg__reg_read "$_gfile"
    cat "$_sidecar"
  } | sort -u | _ospkg__reg_write "$_gfile"
  _keep="$(_ospkg__self_keep)"
  _existing_keep="$(_ospkg__reg_read "${_gfile}.keep")"
  [[ "$_existing_keep" == "true" ]] && _keep=true
  printf '%s\n' "$_keep" | _ospkg__reg_write "${_gfile}.keep"
  if [[ "${_OSPKG__PKG_MNGR:-}" == "apk" ]]; then
    local _virts
    _virts="$(_ospkg__apk_virts_file "$_sidecar")"
    if [[ -f "$_virts" ]]; then
      {
        _ospkg__reg_read "${_gfile}.apkvirts"
        cat "$_virts"
      } | sort -u | _ospkg__reg_write "${_gfile}.apkvirts"
    fi
  fi
  return 0
}

_ospkg__registry_park_pkgs() {
  # _ospkg__registry_park_pkgs <root> <keep> <group-name> <pkg>... — record
  # <pkg>... into a registry group (keep-wins `.keep`) so a still-live sibling's
  # last-out invocation applies the session's keep decision to them.
  local _root="$1" _keep="$2" _gname="$3"
  shift 3
  [[ $# -gt 0 ]] || return 0
  _ospkg__reg_run mkdir -p "${_root}/groups" 2> /dev/null || return 0
  local _gfile="${_root}/groups/${_gname}" _existing_keep
  {
    _ospkg__reg_read "$_gfile"
    printf '%s\n' "$@"
  } | sort -u | _ospkg__reg_write "$_gfile"
  _existing_keep="$(_ospkg__reg_read "${_gfile}.keep")"
  [[ "$_existing_keep" == "true" ]] && _keep=true
  printf '%s\n' "$_keep" | _ospkg__reg_write "${_gfile}.keep"
  return 0
}

_ospkg__registry_prune_dead() {
  # _ospkg__registry_prune_dead <root> — remove registrants whose process is gone
  # or whose PID was reused (token mismatch). Session registrants (no owning PID)
  # are pruned only once older than the backstop.
  local _root="$1"
  local _reg_dir="${_root}/registrants"
  local -a _entries=()
  mapfile -t _entries < <(_ospkg__reg_list "$_reg_dir")
  local _entry _pid _token
  for _entry in "${_entries[@]}"; do
    [[ -z "$_entry" ]] && continue
    if [[ "$_entry" == session.* ]]; then
      _ospkg__reg_path_age_gt "${_reg_dir}/${_entry}" "${_OSPKG__REGISTRY_STALE_SECS:-900}" &&
        _ospkg__reg_run rm -f "${_reg_dir}/${_entry}" 2> /dev/null || true
      continue
    fi
    _pid="${_entry%%.*}"
    _token="${_entry#*.}"
    _ospkg__registrant_alive "$_pid" "$_token" ||
      _ospkg__reg_run rm -f "${_reg_dir}/${_entry}" 2> /dev/null || true
  done
  return 0
}

_ospkg__registry_has_live() {
  # _ospkg__registry_has_live <root> — return 0 when any registrant remains.
  local _list
  _list="$(_ospkg__reg_list "${1}/registrants")"
  [[ -n "${_list//[[:space:]]/}" ]]
}

_ospkg__registry_purge_groups() {
  # _ospkg__registry_purge_groups <root> — union all registry group sidecars,
  # apply keep-wins from each group's `.keep`, and remove the resulting
  # build-only packages by writing the synthetic `__session_cleanup__` sidecar and
  # calling the UNCHANGED per-PM removal path. Kept packages are protected first.
  local _root="$1"
  local _groups_dir="${_root}/groups"
  local -A _pkg_keep=()
  local -a _names=()
  mapfile -t _names < <(_ospkg__reg_list "$_groups_dir")
  local _name _keep _pkg
  for _name in "${_names[@]}"; do
    [[ -z "$_name" ]] && continue
    [[ "$_name" == *.keep || "$_name" == *.apkvirts ]] && continue
    _keep="$(_ospkg__reg_read "${_groups_dir}/${_name}.keep")"
    [[ "$_keep" == "true" ]] || _keep=false
    while IFS= read -r _pkg; do
      [[ -z "$_pkg" ]] && continue
      [[ "${_pkg_keep[$_pkg]:-false}" == "true" ]] && continue
      _pkg_keep["$_pkg"]="$_keep"
    done < <(_ospkg__reg_read "${_groups_dir}/${_name}")
  done

  local -a _to_remove=() _to_keep=()
  for _pkg in "${!_pkg_keep[@]}"; do
    if [[ "${_pkg_keep[$_pkg]}" == "true" ]]; then
      _to_keep+=("$_pkg")
    else
      _to_remove+=("$_pkg")
    fi
  done

  if [[ ${#_to_remove[@]} -eq 0 ]]; then
    logging__info "ospkg registry last-out: no build-dep packages to remove."
    return 0
  fi

  [[ ${#_to_keep[@]} -gt 0 ]] && _ospkg__protect_user_pkgs "${_to_keep[@]}"

  local _synth_dir _synth_sidecar
  _synth_dir="$(_ospkg__build_deps_dir)"
  _synth_sidecar="${_synth_dir}/__session_cleanup__"
  printf '%s\n' "${_to_remove[@]}" | sort > "$_synth_sidecar"

  if [[ "${_OSPKG__PKG_MNGR:-}" == "apk" ]]; then
    local _grp_has_keep
    for _name in "${_names[@]}"; do
      [[ -z "$_name" ]] && continue
      [[ "$_name" == *.keep || "$_name" == *.apkvirts ]] && continue
      _grp_has_keep=false
      while IFS= read -r _pkg; do
        [[ -z "$_pkg" ]] && continue
        if [[ "${_pkg_keep[$_pkg]:-false}" == "true" ]]; then
          _grp_has_keep=true
          break
        fi
      done < <(_ospkg__reg_read "${_groups_dir}/${_name}")
      [[ "$_grp_has_keep" == true ]] && continue
      _ospkg__reg_read "${_groups_dir}/${_name}.apkvirts" >> "${_synth_sidecar}.apkvirts"
    done
  fi

  logging__remove "ospkg registry last-out: removing ${#_to_remove[@]} build-dep package(s): ${_to_remove[*]}"
  _ospkg__remove_build_group "__session_cleanup__" || true
  return 0
}

_ospkg__registry_gate() {
  # _ospkg__registry_gate <self-key> — the shared last-out critical section:
  # under the mutex, deregister <self-key>, prune dead registrants, and either
  # PARK (a live sibling remains → skip shared teardown) or run LAST-OUT (purge
  # unioned groups, restore global-auto, clear the registry). Sets
  # _OSPKG__LAST_OUT_DECISION. Assumes the registry is active.
  local _self_key="$1" _root
  _root="$(_ospkg__registry_root)" || {
    _OSPKG__LAST_OUT_DECISION=true
    return 0
  }
  _ospkg__mutex_acquire "$_root"
  _ospkg__reg_run rm -f "${_root}/registrants/${_self_key}" 2> /dev/null || true
  _ospkg__registry_prune_dead "$_root"
  if _ospkg__registry_has_live "$_root"; then
    logging__info "ospkg registry: live sibling invocation(s) present — parking build-dep teardown."
    _OSPKG__LAST_OUT_DECISION=false
    _ospkg__mutex_release "$_root"
    return 0
  fi
  _OSPKG__LAST_OUT_DECISION=true
  _ospkg__registry_purge_groups "$_root"
  _ospkg__restore_global_auto_state
  _ospkg__reg_run rm -rf "${_root}/groups" "${_root}/registrants" 2> /dev/null || true
  _ospkg__mutex_release "$_root"
  return 0
}

ospkg__is_last_out() {
  # @brief ospkg__is_last_out — Return 0 when this invocation may perform shared,
  # machine-global teardown (package-manager cache clean, bootstrap-bash removal).
  #
  # Under the live registry this is true only for the last-out invocation (the
  # last live registrant at cleanup); without an active registry it is always
  # true (today's single-invocation behaviour). Meaningful only after
  # `ospkg__cleanup_all_build_groups` / `ospkg__cleanup_session_build_groups` has
  # run for this invocation.
  #
  # Returns: 0 when shared teardown is permitted, 1 when parked.
  [[ "${_OSPKG__LAST_OUT_DECISION:-true}" == true ]]
}

ospkg__install_tracked() {
  # @brief ospkg__install_tracked <sub-id> <pkg>... — Install packages and register them as build-only under `<sub-id>` for later cleanup. Idempotent.
  #
  # The full group-id is `"${_SYSSET_BUILD_CONTEXT:-uncontexted}::<sub-id>"`. When
  # `_SYSSET_SESSION_TRACK_DIR` is set, also mirrors tracking to the session dir
  # for cross-feature co-ownership.
  #
  # Args:
  #   <sub-id>  Build-group sub-identifier (e.g. `lib-net`); context prefix added automatically.
  #   <pkg>...  One or more package names to install.
  #
  # Returns: 0 on success.
  local _group_id="${_SYSSET_BUILD_CONTEXT:-uncontexted}::$1"
  shift
  local _bd_dir _before_snapshot
  _bd_dir="$(_ospkg__build_deps_dir)"
  _before_snapshot="${_bd_dir}/${_group_id//\//\_}.before"
  logging__detect "Detecting package manager for tracked install (group '${_group_id}')."
  _ospkg__detect
  # Register in the live registry (first-in takes the shared global-auto snapshot
  # under the mutex). Without an active registry, snapshot per-invocation as before.
  _ospkg__registry_register
  _ospkg__registry_active || _ospkg__ensure_global_auto_snapshot

  if [[ "$_OSPKG__PKG_MNGR" == "apk" ]]; then
    # APK: create a named virtual group so 'apk del VIRT' at cleanup removes
    # exactly our packages — and only those no longer needed by world.
    # Filter to only packages not already installed: pre-existing packages must
    # not be tracked in the virtual group or they would be removed at cleanup.
    local -a _apk_to_install=()
    local _pkg
    for _pkg in "$@"; do
      ospkg__is_installed "$_pkg" || _apk_to_install+=("$_pkg")
    done
    if [[ ${#_apk_to_install[@]} -gt 0 ]]; then
      local _sidecar _virts_file _virt_name _count _existing_virts=()
      _sidecar="${_bd_dir}/${_group_id//\//_}"
      _virts_file="$(_ospkg__apk_virts_file "$_sidecar")"
      [[ -f "$_virts_file" ]] && mapfile -t _existing_virts < "$_virts_file"
      _count="${#_existing_virts[@]}"
      _virt_name="$(_ospkg__apk_virtual_name "$_group_id")-${_count}"
      users__run_privileged apk add --no-cache --virtual "$_virt_name" "${_apk_to_install[@]}" >&2 || {
        logging__error "failed to install tracked APK packages: ${_apk_to_install[*]}."
        return 1
      }
      printf '%s\n' "$_virt_name" >> "$_virts_file"
      # Keep a human-readable sidecar for logging and session tracking.
      printf '%s\n' "${_apk_to_install[@]}" >> "$_sidecar"
      sort -u "$_sidecar" -o "$_sidecar"
    else
      logging__info "Packages already installed: $*"
    fi
  else
    _ospkg__snapshot_packages "$_before_snapshot"
    logging__install "Installing tracked packages: $* (group '${_group_id}')."
    if ! ospkg__install "$@"; then
      rm -f "$_before_snapshot"
      return 1
    fi
    _ospkg__mark_build_group "$_group_id" "$_before_snapshot"
    rm -f "$_before_snapshot"
  fi

  # Session co-ownership tracking (manifest mode only).
  # Register all requested packages not present in the initial snapshot so that
  # the install.bash coordinator can apply keep-wins policy across all co-owners.
  if [[ -n "${_SYSSET_SESSION_TRACK_DIR:-}" && -d "${_SYSSET_SESSION_TRACK_DIR}" ]]; then
    local _session_sidecar _pkg
    _session_sidecar="${_SYSSET_SESSION_TRACK_DIR}/${_group_id//\//_}"
    for _pkg in "$@"; do
      # Skip packages that existed before the session (pre-existing is never cleaned).
      if [[ -n "${_SYSSET_INITIAL_SNAPSHOT:-}" && -f "${_SYSSET_INITIAL_SNAPSHOT}" ]]; then
        grep -qxF "$_pkg" "$_SYSSET_INITIAL_SNAPSHOT" && continue
      fi
      printf '%s\n' "$_pkg" >> "$_session_sidecar"
    done
    [[ -f "$_session_sidecar" ]] && sort -u "$_session_sidecar" -o "$_session_sidecar"
  else
    # Non-session: mirror the group into the live registry so it survives this
    # invocation's temp session root and is visible to a concurrent last-out.
    _ospkg__registry_mirror_group "$_group_id"
  fi
  return 0
}

ospkg__cleanup_all_build_groups() {
  # @brief ospkg__cleanup_all_build_groups [<keep_build_deps>] — Remove every registered build-dep group (or defer to the last-out invocation under the live registry).
  #
  # Without an active registry (nonroot-no-sudo, brew without a share dir, or the
  # registry disabled) this is today's behaviour: with `<keep_build_deps>` unset or
  # `false` it scans the per-invocation sidecar directory and removes each group,
  # then restores the global-auto state; with `true` it is a no-op (build deps are
  # kept). With the registry active it deregisters this invocation under the mutex
  # and, only if it is the last live registrant ("last-out"), unions all co-owned
  # groups, applies per-group keep-wins, purges, and restores the global-auto state;
  # a parked invocation removes nothing. `ospkg__is_last_out` reports the decision.
  #
  # Args:
  #   <keep_build_deps>  `true` or `false` (default `false`) — this invocation's
  #                      keep_build_deps intent.
  #
  # Returns: 0 on success.
  local _keep="${1:-false}"
  _OSPKG__LAST_OUT_DECISION=true

  if _ospkg__registry_active; then
    local _self_key="$$.${_OSPKG__SELF_TOKEN:-$(_ospkg__proc_token "$$")}"
    _ospkg__registry_gate "$_self_key"
    return 0
  fi

  # ── No active registry: today's exact, byte-compatible behaviour. ──
  if [[ "$_keep" == "true" ]]; then
    return 0
  fi
  local _deps_dir
  _deps_dir="$(_ospkg__build_deps_dir)"
  [[ -d "$_deps_dir" ]] || return 0
  local _sidecar _group_id
  for _sidecar in "$_deps_dir"/*; do
    [[ -f "$_sidecar" ]] || continue
    _group_id="$(basename "$_sidecar")"
    # Skip temporary snapshot files and apk virtual-group auxiliary files.
    [[ "$_group_id" == *.before || "$_group_id" == *.after || "$_group_id" == *.apkvirts || "$_group_id" == .global_auto_before ]] && continue
    _ospkg__remove_build_group "$_group_id"
  done
  _ospkg__restore_global_auto_state
  return 0
}

ospkg__cleanup_session_build_groups() {
  # @brief ospkg__cleanup_session_build_groups <install-bash-keep> — Manifest-mode coordinator: apply keep-wins policy across co-owners and remove unneeded build packages.
  #
  # Reads co-ownership entries from `_SYSSET_SESSION_TRACK_DIR`, applies keep-wins
  # (any `true` overrides all `false`), then removes packages not kept by any
  # co-owner. Deletes `_SYSSET_SESSION_TRACK_DIR` on completion. No-op when
  # `_SYSSET_SESSION_TRACK_DIR` is unset or does not exist.
  #
  # Args:
  #   <install-bash-keep>  `"true"` or `"false"` — keep_build_deps for the install-bash context. Feature keep_build_deps is read from `_OPT_OF`.
  #
  # Returns: 0 on success.
  #
  # The keep-wins to-remove computation is unchanged. When the live registry is
  # active the ACTUATION is routed through the same last-out gate as
  # `ospkg__cleanup_all_build_groups`: the session is one registrant, so if a
  # concurrent invocation is still live the session's groups are PARKED into the
  # registry (with keep-wins preserved) for whoever is last-out, and the session's
  # own purge / global-auto restore / session-dir removal are deferred.
  local _getbash_keep="${1:-false}"
  [[ -n "${_SYSSET_SESSION_TRACK_DIR:-}" ]] || return 0
  [[ -d "$_SYSSET_SESSION_TRACK_DIR" ]] || return 0
  _OSPKG__LAST_OUT_DECISION=true

  # Build pkg -> should_keep map (keep wins: any true overrides all false).
  local -A _session_pkg_keep=()
  local _sidecar _basename _context _feature_id _keep _pkg
  for _sidecar in "$_SYSSET_SESSION_TRACK_DIR"/*; do
    [[ -f "$_sidecar" ]] || continue
    _basename="$(basename "$_sidecar")"
    # Derive keep policy from context prefix in the filename.
    # Filename is the context-qualified group ID, e.g.:
    #   "install-bash::bootstrap", "feature::install-gh::lib-net"
    if [[ "$_basename" == install-bash::* ]]; then
      _keep="$_getbash_keep"
    else
      # Extract feature ID from "feature::<id>::<module>" pattern.
      _feature_id="${_basename#feature::}"
      _feature_id="${_feature_id%%::*}"
      _keep=false
      # Read from _OPT_OF if declared in the caller's scope (install.bash).
      if argparse__var_declared _OPT_OF && [[ -n "${_OPT_OF[$_feature_id]+x}" ]]; then
        if [[ "${_OPT_OF[$_feature_id]}" =~ \"keep_build_deps\":[[:space:]]*true ]]; then
          _keep=true
        fi
      fi
    fi
    while IFS= read -r _pkg; do
      [[ -z "$_pkg" ]] && continue
      # Keep wins: once set true, never overridden by false.
      if [[ "${_session_pkg_keep[$_pkg]:-false}" != "true" ]]; then
        _session_pkg_keep["$_pkg"]="$_keep"
      fi
    done < "$_sidecar"
  done

  # Partition into to-remove (all co-owners said keep=false) and to-keep.
  local -a _to_remove=() _to_keep=()
  for _pkg in "${!_session_pkg_keep[@]}"; do
    if [[ "${_session_pkg_keep[$_pkg]}" == "true" ]]; then
      _to_keep+=("$_pkg")
    else
      _to_remove+=("$_pkg")
    fi
  done

  # Route actuation through the live-registry last-out gate.
  local _reg_root='' _reg_active=false _mode=purge
  if _ospkg__registry_active; then
    _reg_active=true
    _reg_root="$(_ospkg__registry_root)"
    _ospkg__mutex_acquire "$_reg_root"
    _ospkg__reg_run rm -f "${_reg_root}/registrants/$(_ospkg__session_reg_key)" 2> /dev/null || true
    _ospkg__registry_prune_dead "$_reg_root"
    _ospkg__registry_has_live "$_reg_root" && _mode=park
  fi

  if [[ "$_mode" == park ]]; then
    # A concurrent invocation is still live — park the session's groups (keep-wins
    # preserved) for whoever is last-out; defer purge, global-auto restore, and
    # session-dir removal. Nothing is removed now.
    logging__info "Session cleanup: live sibling invocation(s) present — parking session build groups for last-out."
    [[ ${#_to_keep[@]} -gt 0 ]] && _ospkg__registry_park_pkgs "$_reg_root" true "__session_keep__" "${_to_keep[@]}"
    [[ ${#_to_remove[@]} -gt 0 ]] && _ospkg__registry_park_pkgs "$_reg_root" false "__session_drop__" "${_to_remove[@]}"
    _ospkg__mutex_release "$_reg_root"
    rm -rf "$_SYSSET_SESSION_TRACK_DIR"
    _OSPKG__LAST_OUT_DECISION=false
    return 0
  fi

  # PURGE — no registry, or registry last-out (mutex held while _reg_active).
  if [[ ${#_to_remove[@]} -gt 0 ]]; then
    # Protect packages that should be kept: mark them manual so autoremove-based
    # cleanup (apt, dnf, pacman) doesn't remove them as orphaned build deps.
    [[ ${#_to_keep[@]} -gt 0 ]] && _ospkg__protect_user_pkgs "${_to_keep[@]}"

    logging__remove "Session cleanup: removing ${#_to_remove[@]} build-dep package(s): ${_to_remove[*]}"
    local _synth_dir _synth_sidecar
    _synth_dir="$(_ospkg__build_deps_dir)"
    _synth_sidecar="${_synth_dir}/__session_cleanup__"
    printf '%s\n' "${_to_remove[@]}" | sort > "$_synth_sidecar"
    # APK: synthetic sidecars have no .apkvirts file; apk del <package> fails for
    # packages owned by a virtual group. Collect the virtual names from groups
    # whose packages are all being removed, so _ospkg__remove_build_group uses the
    # correct apk del path rather than falling back to per-package deletion.
    if [[ "$_OSPKG__PKG_MNGR" == "apk" ]]; then
      local _grp_sidecar _grp_virts_path _grp_pkg _grp_has_keep
      for _grp_sidecar in "$_synth_dir"/*; do
        [[ -f "$_grp_sidecar" ]] || continue
        local _gname
        _gname="$(basename "$_grp_sidecar")"
        [[ "$_gname" == __session_cleanup__ || "$_gname" == *.before || "$_gname" == *.after || "$_gname" == *.apkvirts || "$_gname" == .global_auto_before ]] && continue
        _grp_virts_path="$(_ospkg__apk_virts_file "$_grp_sidecar")"
        [[ -f "$_grp_virts_path" ]] || continue
        _grp_has_keep=false
        while IFS= read -r _grp_pkg; do
          [[ -z "$_grp_pkg" ]] && continue
          if [[ "${_session_pkg_keep[$_grp_pkg]:-false}" == "true" ]]; then
            _grp_has_keep=true
            break
          fi
        done < "$_grp_sidecar"
        [[ "$_grp_has_keep" == false ]] && cat "$_grp_virts_path" >> "${_synth_sidecar}.apkvirts"
      done
    fi
    _ospkg__remove_build_group "__session_cleanup__" || true
  else
    logging__info "Session cleanup: no packages to remove (all kept or nothing installed)."
  fi

  rm -rf "$_SYSSET_SESSION_TRACK_DIR"
  _ospkg__restore_global_auto_state
  if [[ "$_reg_active" == true ]]; then
    _ospkg__reg_run rm -rf "${_reg_root}/groups" "${_reg_root}/registrants" 2> /dev/null || true
    _ospkg__mutex_release "$_reg_root"
  fi
  return 0
}

ospkg__track_resource() {
  # @brief ospkg__track_resource <group-id> <path>... — Register filesystem paths for cleanup via `ospkg__cleanup_resources`. Also mirrors to the session dir when `_SYSSET_SESSION_TRACK_DIR` is set.
  #
  # Args:
  #   <group-id>  Cleanup group identifier.
  #   <path>...   One or more absolute paths to register.
  #
  # Returns: 0 on success.
  local _group_id="$1"
  shift
  local _res_dir _sidecar _path
  _res_dir="$(file__tmpdir "ospkg/resources")"
  _sidecar="${_res_dir}/${_group_id//\//_}"
  for _path in "$@"; do
    printf '%s\n' "$_path" >> "$_sidecar"
  done
  if [[ -n "${_SYSSET_SESSION_TRACK_DIR:-}" && -d "${_SYSSET_SESSION_TRACK_DIR}" ]]; then
    local _sess_res_dir="${_SYSSET_SESSION_TRACK_DIR}/resources"
    mkdir -p "$_sess_res_dir"
    local _sess_sidecar="${_sess_res_dir}/${_group_id//\//_}"
    for _path in "$@"; do
      printf '%s\n' "$_path" >> "$_sess_sidecar"
    done
  fi
  return 0
}

ospkg__untrack_resource() {
  # @brief ospkg__untrack_resource <group-id> <path>... — Remove resource paths from local and session sidecars registered by `ospkg__track_resource`.
  #
  # Args:
  #   <group-id>  Cleanup group identifier.
  #   <path>...   One or more paths to deregister.
  #
  # Returns: 0 on success, 1 if copying the sidecar fails.
  local _group_id="$1"
  shift
  local _res_dir _sidecar _path _tmp
  _res_dir="$(file__tmpdir "ospkg/resources")"
  _sidecar="${_res_dir}/${_group_id//\//_}"
  if [[ -f "$_sidecar" ]]; then
    _tmp="${_sidecar}.tmp.$$"
    cp "$_sidecar" "$_tmp" || {
      logging__error "failed to copy sidecar '${_sidecar}'."
      return 1
    }
    for _path in "$@"; do
      awk -v p="$_path" '$0 != p { print }' "$_tmp" > "${_tmp}.next"
      mv "${_tmp}.next" "$_tmp"
    done
    mv "$_tmp" "$_sidecar"
  fi
  if [[ -n "${_SYSSET_SESSION_TRACK_DIR:-}" && -d "${_SYSSET_SESSION_TRACK_DIR}/resources" ]]; then
    local _sess_sidecar="${_SYSSET_SESSION_TRACK_DIR}/resources/${_group_id//\//_}"
    if [[ -f "$_sess_sidecar" ]]; then
      _tmp="${_sess_sidecar}.tmp.$$"
      cp "$_sess_sidecar" "$_tmp" || {
        logging__error "failed to copy session sidecar '${_sess_sidecar}'."
        return 1
      }
      for _path in "$@"; do
        awk -v p="$_path" '$0 != p { print }' "$_tmp" > "${_tmp}.next"
        mv "${_tmp}.next" "$_tmp"
      done
      mv "$_tmp" "$_sess_sidecar"
    fi
  fi
  return 0
}

ospkg__cleanup_resources() {
  # @brief ospkg__cleanup_resources — Remove all files registered via `ospkg__track_resource`. Reads sidecars from `_FILE__SESSION_ROOT/ospkg/resources/` and `rm -f`s each listed path.
  #
  # Returns: 0 (always; removal failures emit a warning and continue).
  local _res_dir
  _res_dir="$(file__tmpdir "ospkg/resources")"
  [[ -d "$_res_dir" ]] || return 0
  local _sidecar _path
  for _sidecar in "$_res_dir"/*; do
    [[ -f "$_sidecar" ]] || continue
    while IFS= read -r _path; do
      [[ -z "$_path" ]] && continue
      if [[ -e "$_path" ]]; then
        rm -f "$_path" 2> /dev/null || logging__warn "could not remove '${_path}'"
      fi
    done < "$_sidecar"
    rm -f "$_sidecar"
  done
  return 0
}

ospkg__install_user() {
  # @brief ospkg__install_user [--update] <pkg>... — Install packages and protect them from build-group cleanup. Prefer over `ospkg__install` for all user-facing installs.
  #
  # Without --update each package is checked via PM-native query; only missing
  # packages are passed to the package manager. With --update already-installed
  # packages are also upgraded (brew uses `brew upgrade`; all other PMs upgrade
  # in place via their install command).
  #
  # Version suffixes are stripped per PM convention before calling
  # `_ospkg__protect_user_pkgs`, so packages will not be removed by
  # `ospkg__cleanup_all_build_groups` even if a prior build-group install had
  # marked them.
  #
  # Args:
  #   --update  Also upgrade already-installed packages.
  #   <pkg>...  One or more package specs (versioned forms like `gh=2.40.0` accepted).
  #
  # Returns: 0 on success.
  local _do_update=false
  if [[ "${1:-}" == "--update" ]]; then
    _do_update=true
    shift
  fi
  if [[ "$_do_update" == true ]]; then
    ospkg__install --update "$@"
  else
    ospkg__install "$@"
  fi
  _ospkg__detect
  # Strip PM-native version suffixes to get bare package names for marking.
  local -a _bare_names=()
  local _p
  for _p in "$@"; do
    case "$_OSPKG__PKG_MNGR" in
      apt-get | apk | pacman | zypper) _bare_names+=("${_p%%=*}") ;;
      dnf | yum) _bare_names+=("${_p%%-[0-9]*}") ;;
      brew) _bare_names+=("${_p%%@*}") ;;
      *) _bare_names+=("$_p") ;;
    esac
  done
  _ospkg__protect_user_pkgs "${_bare_names[@]}"
  return 0
}

ospkg__has_rdeps() {
  # @brief ospkg__has_rdeps <pkg> — Return 0 if any installed package depends on <pkg>, 1 otherwise.
  #
  # Uses PM-native reverse-dependency queries for all PMs supported by _ospkg__detect.
  #
  # Returns: 0 if reverse deps exist, 1 if none or if the PM is unsupported.
  local _pkg="${1:?ospkg__has_rdeps: pkg required}"
  _ospkg__detect
  local _rc=$?
  [[ $_rc == 0 ]] || return "$_rc"
  local _out=""
  case "$_OSPKG__PKG_MNGR" in
    apt-get)
      _out="$(apt-cache rdepends --installed "$_pkg" 2> /dev/null |
        grep -v "^${_pkg}$\|^Reverse Depends:\|^[[:space:]]*|\|^[[:space:]]*$")" || true
      ;;
    apk)
      _out="$(apk info --rdepends "$_pkg" 2> /dev/null |
        grep -v "has no dependants\|is required by\|^[[:space:]]*$")" || true
      ;;
    dnf | yum | microdnf)
      _out="$(rpm -q --whatrequires "$_pkg" 2> /dev/null | grep -v "^no package requires")" || true
      ;;
    zypper)
      _out="$(zypper search --requires "$_pkg" --installed-only 2> /dev/null | grep -E '^i ')" || true
      ;;
    pacman)
      _out="$(pacman -Qi "$_pkg" 2> /dev/null | grep "^Required By" | grep -v ": None")" || true
      ;;
    brew)
      _out="$(brew uses --installed "$_pkg" 2> /dev/null)" || true
      ;;
  esac
  [[ -n "${_out:-}" ]]
}

_ospkg__normalize_pkg_version_spec() {
  # Channel selectors in feat.pm_version / feat.version_input mean "install whatever
  # the PM provides" for package/upstream-package methods.
  case "${1:-}" in
    '' | stable | latest) printf '' ;;
    *) printf '%s' "$1" ;;
  esac
}

ospkg__resolve_version() {
  # @brief ospkg__resolve_version <package> <spec> — Resolve a version spec to the exact PM version string available in the repository.
  #
  # Queries repository metadata without installing anything and returns the
  # PM-native version string (e.g. `5.9-6ubuntu2` on Debian/Ubuntu, `5.9-r4`
  # on Alpine) that satisfies `<spec>`. When the repository exposes multiple
  # matching versions (possible with DNF), the newest one is returned.
  #
  # `<spec>` is matched using prefix semantics: `5.9` matches `5.9-6ubuntu2`
  # and `5.9.1` but not `5.90`. An exact spec (e.g. `5.9.1`) is also accepted
  # and must appear verbatim (modulo distro suffix) in the repository.
  #
  # Args:
  #   <package>  Package name.
  #   <spec>     Version prefix or exact version (e.g. `5.9`, `5.9.1`).
  #
  # Stdout: Exact PM version string (e.g. `5.9-6ubuntu2`).
  # Returns: 0 on success, 1 if unavailable, unsupported PM, or query error.
  local _pkg="${1:-}" _spec="${2:-}"
  [[ -n "${_pkg}" && -n "${_spec}" ]] || return 1
  _ospkg__detect || return 1
  local _candidates=""
  case "${_OSPKG__FAMILY}" in
    apt)
      _candidates="$(apt-cache policy "${_pkg}" 2> /dev/null | awk '/Candidate:/{print $2; exit}')"
      [[ -n "${_candidates}" && "${_candidates}" != "(none)" ]] || return 1
      ;;
    apk)
      _candidates="$(apk search --exact "${_pkg}" 2> /dev/null | sed "s/^${_pkg}-//" | sort -V -r)"
      [[ -n "${_candidates}" ]] || return 1
      ;;
    dnf)
      case "${_OSPKG__PKG_MNGR}" in
        dnf)
          _candidates="$(dnf repoquery --available "${_pkg}" --qf '%{version}\n' 2> /dev/null | sort -V -r)"
          ;;
        yum)
          _candidates="$(yum info "${_pkg}" 2> /dev/null | awk -F' *: *' '/^Version/{print $2; exit}')"
          ;;
        *) return 1 ;;
      esac
      [[ -n "${_candidates}" ]] || return 1
      ;;
    zypper)
      _candidates="$(zypper info "${_pkg}" 2> /dev/null | sed -n 's/^Version[[:space:]]*:[[:space:]]*//p' | head -1)"
      [[ -n "${_candidates}" ]] || return 1
      ;;
    pacman)
      _candidates="$(pacman -Si "${_pkg}" 2> /dev/null | awk -F' : ' '/^Version/{print $2; exit}')"
      [[ -n "${_candidates}" ]] || return 1
      ;;
    brew)
      _candidates="$(brew info --formula "${_pkg}" 2> /dev/null | grep -oE 'stable [0-9][0-9._-]*' | awk '{print $2}' | head -1)"
      [[ -n "${_candidates}" ]] || return 1
      ;;
    *) return 1 ;;
  esac
  printf '%s\n' "${_candidates}" | ver__first_matching_prefix "${_spec}"
}

ospkg__has_available_version() {
  # @brief ospkg__has_available_version <package> <version> — Return 0 if the OS PM's repository can satisfy the version spec for <package>.
  #
  # Thin wrapper around `ospkg__resolve_version` that discards the resolved
  # version string and returns only the exit code. See `ospkg__resolve_version`
  # for matching semantics.
  #
  # Args:
  #   <package>  Package name.
  #   <version>  Version prefix or exact version to check.
  #
  # Returns: 0 if the PM can provide the requested version, 1 otherwise.
  local _pkg="${1:-}" _spec="${2:-}"
  [[ -n "${_pkg}" && -n "${_spec}" ]] || return 1
  ospkg__resolve_version "${_pkg}" "${_spec}" > /dev/null 2>&1
}

ospkg__remove_user() {
  # @brief ospkg__remove_user [--ignore-deps] <pkg>... — Remove one or more user-installed packages via the OS package manager.
  #
  # Uses the platform-native removal command for each supported package manager.
  # Continues on best-effort basis: non-zero exit from the package manager is
  # logged as a warning but does not fail the function.
  #
  # When --ignore-deps is given, uses low-level force-remove commands that bypass
  # dependency checks and drop the package files without cascade-removing or
  # refusing due to reverse-dependents (dpkg --force-depends, rpm --nodeps,
  # pacman -Rdd, apk --force-broken-world, brew --ignore-dependencies). Use this
  # when replacing a PM-installed package with a non-PM-managed binary: the
  # reverse-dependent packages remain installed with a temporarily unsatisfied
  # declared dependency that resolves once the replacement is in place.
  #
  # Args:
  #   --ignore-deps  Bypass dependency checks; do not cascade-remove reverse-dependents.
  #   <pkg>...       One or more bare package names (no version suffixes).
  #
  # Returns: 0 on success (including best-effort partial removal).
  local _ignore_deps=false
  while [[ $# -gt 0 && "$1" == --* ]]; do
    case "$1" in
      --ignore-deps)
        _ignore_deps=true
        shift
        ;;
      *) break ;;
    esac
  done
  [[ $# -gt 0 ]] || return 0
  _ospkg__detect
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "no package manager detected."
    return "$_rc"
  }
  logging__info "removing package(s): $*"
  local -a _cmd
  if [[ "$_ignore_deps" == true ]]; then
    _cmd=("${_OSPKG__REMOVE_FORCE[@]}")
  else
    _cmd=("${_OSPKG__REMOVE[@]}")
  fi
  local _rc=0
  if [[ -t 0 ]]; then
    "${_cmd[@]}" "$@" >&2 || _rc=$?
  elif [[ "$_OSPKG__PKG_MNGR" == "apt-get" && -z "${DEBIAN_FRONTEND-}" ]]; then
    DEBIAN_FRONTEND=noninteractive "${_cmd[@]}" "$@" < /dev/null >&2 || _rc=$?
  else
    "${_cmd[@]}" "$@" < /dev/null >&2 || _rc=$?
  fi
  [[ $_rc -ne 0 ]] && logging__warn "package removal failed for: $*"
  return 0
}

ospkg__register_dummy() {
  # @brief ospkg__register_dummy <pkg> <version> [--provides <name>...] [--description <text>] — Install a dummy Debian package to register a non-PM tool with the package manager.
  #
  # Creates and installs a minimal equivs-generated .deb that satisfies
  # `Depends:` constraints for a tool installed by non-PM means (binary, source,
  # script, cargo, npm, etc.). The package is tagged with `XB-Devfeats-Dummy: true`
  # so `ospkg__unregister_dummy` can identify and remove it without risk of
  # removing a real package with the same name.
  #
  # Debian/Ubuntu (apt family) only. No-op on all other platforms.
  # Non-fatal: emits a warning on failure and returns 0.
  # Requires privilege (root or sudo); emits a warning and skips when absent.
  #
  # Args:
  #   <pkg>              Package name to register (e.g., `git`).
  #   <version>          Exact version string — bare, no PM suffix (e.g., `2.47.2`).
  #   --provides <name>  Additional package names this dummy Provides. Repeatable.
  #                      The primary <pkg> is always included.
  #   --description <t>  Package description. Defaults to a devfeats sentinel string.
  #
  # Returns: 0 always (non-fatal).
  if ! _ospkg__detect; then return 0; fi
  [[ "$_OSPKG__FAMILY" == "apt" ]] || return 0

  if [[ $# -lt 2 ]]; then
    logging__warn "usage: ospkg__register_dummy <pkg> <version> [--provides <name>...] [--description <text>]"
    return 0
  fi

  local _pkg="$1" _version="$2"
  shift 2

  if [[ -z "${_pkg:-}" || -z "${_version:-}" ]]; then
    logging__warn "<pkg> and <version> must be non-empty."
    return 0
  fi

  local -a _provides=()
  local _description="devfeats: non-PM installation of ${_pkg} (${_version})"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --provides)
        shift
        [[ $# -gt 0 ]] && {
          _provides+=("$1")
          shift
        }
        ;;
      --description)
        shift
        [[ $# -gt 0 ]] && {
          _description="$1"
          shift
        }
        ;;
      *)
        logging__warn "ignoring unknown argument: '$1'"
        shift
        ;;
    esac
  done

  if ! users__is_privileged; then
    logging__warn "skipping dummy registration for '${_pkg}' (no privilege)."
    return 0
  fi

  # Ensure equivs is available.
  if ! command -v equivs-build > /dev/null 2>&1; then
    logging__info "equivs not found — installing."
    ospkg__install_tracked "devfeats-ospkg-internals" equivs 2> /dev/null || {
      logging__warn "could not install equivs; skipping dummy registration for '${_pkg}'."
      return 0
    }
  fi

  local _work_dir
  _work_dir="$(file__mktmpdir "ospkg-dummy")"

  # Provides line always includes the primary package name.
  local _provides_line="${_pkg}"
  local _p
  for _p in "${_provides[@]}"; do
    [[ "$_p" != "$_pkg" ]] && _provides_line+=", ${_p}"
  done

  # equivs control file — use XB- prefix so the field is recorded in the
  # binary package and queryable via dpkg-query for reliable identification.
  printf 'Package: %s\nVersion: %s\nArchitecture: all\nMaintainer: devfeats <devfeats@local>\nDescription: %s\nXB-Devfeats-Dummy: true\nProvides: %s\n' \
    "$_pkg" "$_version" "$_description" "$_provides_line" > "${_work_dir}/${_pkg}.ctrl"

  # equivs-build writes the .deb to CWD.
  local _rc=0
  (
    cd "$_work_dir"
    equivs-build "${_work_dir}/${_pkg}.ctrl"
  ) > /dev/null || _rc=$?

  if [[ $_rc -ne 0 ]]; then
    logging__warn "equivs-build failed for '${_pkg}' — skipping."
    rm -rf "$_work_dir"
    return 0
  fi

  local _deb
  _deb="$(file__first_glob_match "$_work_dir" '*.deb')"
  if [[ -z "${_deb:-}" ]]; then
    logging__warn "no .deb produced by equivs-build for '${_pkg}' — skipping."
    rm -rf "$_work_dir"
    return 0
  fi

  # --force-depends prevents failure when equivs generates a trivial
  # ${misc:Depends} that isn't present in all images.
  local _dpkg_rc=0
  users__run_privileged dpkg --force-depends -i "$_deb" > /dev/null || _dpkg_rc=$?
  rm -rf "$_work_dir"

  if [[ $_dpkg_rc -ne 0 ]]; then
    logging__warn "dpkg install failed for '${_pkg}' dummy — skipping."
    return 0
  fi

  logging__success "Registered dummy package '${_pkg}' (${_version})."
  return 0
}

ospkg__unregister_dummy() {
  # @brief ospkg__unregister_dummy <pkg> — Remove a devfeats dummy package if installed.
  #
  # Queries the dpkg database for the `XB-Devfeats-Dummy` custom field and only
  # removes the package when the field equals `true`. This prevents accidental
  # removal of a real package with the same name installed by other means.
  #
  # Debian/Ubuntu (apt family) only. No-op on all other platforms.
  # Non-fatal: emits a warning on failure and returns 0.
  # Requires privilege (root or sudo); emits a warning and skips when absent.
  #
  # Args:
  #   <pkg>  Package name to unregister.
  #
  # Returns: 0 always (non-fatal).
  if ! _ospkg__detect; then return 0; fi
  [[ "$_OSPKG__FAMILY" == "apt" ]] || return 0

  local _pkg="${1:-}"
  if [[ -z "${_pkg:-}" ]]; then
    logging__warn "<pkg> must be non-empty."
    return 0
  fi

  # Only remove when we installed the dummy (identified by custom dpkg field).
  local _dummy_field
  _dummy_field="$(dpkg-query -f '${XB-Devfeats-Dummy}' -W "$_pkg" 2> /dev/null)" || true

  if [[ "${_dummy_field:-}" != "true" ]]; then
    logging__info "'${_pkg}' is not a devfeats dummy — skipping."
    return 0
  fi

  if ! users__is_privileged; then
    logging__warn "skipping removal of dummy '${_pkg}' (no privilege)."
    return 0
  fi

  logging__remove "Removing devfeats dummy package '${_pkg}'."
  local _rc=0
  if [[ -t 0 ]]; then
    users__run_privileged apt-get -y remove "$_pkg" > /dev/null || _rc=$?
  else
    DEBIAN_FRONTEND=noninteractive users__run_privileged apt-get -y remove "$_pkg" < /dev/null > /dev/null || _rc=$?
  fi

  if [[ $_rc -ne 0 ]]; then
    logging__warn "removal of dummy '${_pkg}' failed."
    return 0
  fi

  logging__success "Removed dummy package '${_pkg}'."
  return 0
}

ospkg__run() {
  # @brief ospkg__run [--manifest <f>] [--fetch-netrc-file <path>] [--fetch-header <H>]... [--update] [--update-index <bool>] [--keep_repos] [--dry_run] [--interactive] [--build-group <id>] — Run the full installation pipeline from a manifest.
  #
  # Full pipeline: detect → root check → parse manifest → prescript → keys →
  # repos → PM setup → update → install → casks → script.
  #
  # Cache cleanup is NOT performed by this function. Call ospkg__clean explicitly
  # (e.g. via an exit trap) when you want to purge the package manager cache.
  #
  # Args:
  #   --manifest <f>          Path to the YAML manifest file, inline YAML/JSON (with
  #                           embedded newlines), or a URI (http(s)://, file://, oci://, gh://).
  #   --fetch-netrc-file <path>  Optional .netrc file passed to URI fetches when
  #                           resolving a URI manifest.
  #   --fetch-header <H>      Additional HTTP header passed to URI fetches when
  #                           resolving a URI manifest. Repeatable.
  #   --runtime-path <p>      PATH the installed tools will resolve on at container
  #                           runtime (the feature's resolved runtime_path). Per-package
  #                           `command:` guards probe this to decide whether a runtime
  #                           dependency is already satisfied. Empty → install-time PATH.
  #   --update                Also upgrade already-installed packages (brew uses `brew upgrade`;
  #                           all other PMs upgrade in place via their install command).
  #   --update-index <bool>   Refresh the package index before installing (default: true).
  #   --keep_repos            Do not remove added third-party repo files after installation.
  #   --dry_run               Print what would be installed without doing it.
  #   --interactive           Preserve TTY for interactive package prompts.
  #   --build-group <id>      Mark all newly-installed packages as build-only and record
  #                           them in a sidecar file for later cleanup. Requires --manifest.
  #   --remove                Remove mode: parse the manifest and uninstall the listed
  #                           packages/casks via ospkg__remove_user. Keys, repos,
  #                           prescripts, scripts, modules, and groups are skipped.
  #                           Mutually exclusive with --build-group and --update.
  #   --fail-if-installed     Fail with an error if any package from the manifest is
  #                           already installed. Mutually exclusive with --update and --remove.
  #
  # Returns: 0 on success, 1 on invalid arguments or manifest parse failure.
  local _manifest='' _update_index=true _keep_repos=false
  local _lists_max_age=300 _dry_run=false _interactive=false
  local _prefer_linuxbrew=false _build_group=''
  local _do_pkg_update=false _do_remove=false _fail_if_installed=false
  local _fetch_netrc_file='' _runtime_path=''
  local -a _fetch_headers=()

  while [[ $# -gt 0 ]]; do
    case $1 in
      --manifest)
        shift
        _manifest="$1"
        shift
        ;;
      --fetch-netrc-file)
        shift
        _fetch_netrc_file="$1"
        shift
        ;;
      --fetch-header)
        shift
        _fetch_headers+=("$1")
        shift
        ;;
      --runtime-path)
        shift
        _runtime_path="$1"
        shift
        ;;
      --update)
        shift
        _do_pkg_update=true
        ;;
      --update-index)
        shift
        _update_index="$1"
        shift
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

      --interactive)
        shift
        _interactive=true
        ;;
      --prefer_linuxbrew)
        shift
        _prefer_linuxbrew=true
        ;;
      --build-group)
        shift
        _build_group="$1"
        shift
        ;;
      --remove)
        shift
        _do_remove=true
        ;;
      --fail-if-installed)
        shift
        _fail_if_installed=true
        ;;

      *)
        logging__error "unknown option: $1"
        return 1
        ;;
    esac
  done

  if ! [[ "$_lists_max_age" =~ ^[0-9]+$ ]]; then
    logging__error "invalid lists_max_age value: '$_lists_max_age'."
    return 1
  fi

  if [[ -n "$_build_group" && -z "$_manifest" ]]; then
    logging__error "--build-group requires --manifest."
    return 1
  fi

  [[ "$_dry_run" == true ]] && logging__inspect "Dry-run mode enabled — no changes will be made."

  # Set prefer_linuxbrew early so detect() picks it up.
  _OSPKG__PREFER_LINUXBREW="$_prefer_linuxbrew"

  _ospkg__detect
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "no package manager detected."
    return "$_rc"
  }

  if [[ "$_OSPKG__PKG_MNGR" = "apt-get" && "$_interactive" == false ]]; then
    logging__info "Setting APT to non-interactive mode."
    export DEBIAN_FRONTEND=noninteractive
  fi

  # Resolve manifest content.
  local _manifest_content=
  local _hl=''
  local -a _ospkg__uri_args=()
  local _ospkg__uri_tmp=''

  if [[ -n "$_manifest" ]]; then
    if [[ "$_manifest" == *$'\n'* ]]; then
      _manifest_content="$_manifest"
    elif uri__classify "$_manifest" > /dev/null 2>&1 &&
      [[ "$(uri__classify "$_manifest" 2> /dev/null)" != "local" ]]; then
      _ospkg__uri_tmp="$(mktemp "${TMPDIR:-/tmp}/ospkg-manifest-uri.XXXXXX")"
      _ospkg__uri_args=()
      if [[ -n "${_fetch_netrc_file:-}" ]]; then
        _ospkg__uri_args+=(--netrc-file "$_fetch_netrc_file")
      fi
      for _hl in "${_fetch_headers[@]}"; do
        [[ -z "${_hl//[[:space:]]/}" ]] && continue
        _ospkg__uri_args+=(--header "$_hl")
      done
      if ! uri__resolve "$_manifest" "$_ospkg__uri_tmp" "${_ospkg__uri_args[@]}"; then
        rm -f "$_ospkg__uri_tmp"
        return 1
      fi
      if ! _manifest_content="$(< "$_ospkg__uri_tmp")"; then
        rm -f "$_ospkg__uri_tmp"
        return 1
      fi
      rm -f "$_ospkg__uri_tmp"
    elif [[ -f "$_manifest" ]]; then
      _manifest_content="$(< "$_manifest")"
    else
      logging__error "Manifest file not found: '$_manifest'"
      return 1
    fi
  fi

  local _before_snapshot_file=''

  # ── YAML / JSON manifest path ──────────────────────────────────────────────
  if [[ -n "$_manifest_content" ]]; then

    # yq is required to convert YAML to JSON.
    if ! bootstrap__yq > /dev/null; then
      logging__error "yq is required for YAML manifests but could not be obtained."
      return 1
    fi

    # Convert YAML (or JSON) to JSON via yq, then parse into phase arrays.
    # Temp files live inside _FILE__SESSION_ROOT so file__session_cleanup removes them
    # automatically on exit, even on unexpected failure.
    local _ospkg__dir _json_tmp
    _ospkg__dir="$(file__tmpdir "ospkg")"
    _json_tmp="$(mktemp "${_ospkg__dir}/yaml_XXXXXX")"

    local -a _Y_PRESCRIPTS=() _Y_KEYS=() _Y_REPOS=() _Y_PPAS=() _Y_TAPS=() _Y_COPR=()
    local -a _Y_MODULES=() _Y_GROUPS=() _Y_PACKAGES=() _Y_CASKS=() _Y_SCRIPTS=()

    logging__info "Converting manifest to JSON via yq."
    if [[ "$_manifest_content" == *$'\n'* ]]; then
      printf '%s' "$_manifest_content" | "$_BOOTSTRAP__YQ_BIN" -o=json '.' - > "$_json_tmp"
    else
      "$_BOOTSTRAP__YQ_BIN" -o=json '.' - <<< "$_manifest_content" > "$_json_tmp" 2> /dev/null ||
        echo "$_manifest_content" | "$_BOOTSTRAP__YQ_BIN" -o=json '.' - > "$_json_tmp"
    fi

    local _item _kind
    local _parsed_records
    if ! _parsed_records="$(ospkg__parse_manifest_yaml "$_json_tmp")"; then
      local _manifest_origin _manifest_preview
      if [[ "$_manifest" == *$'\n'* ]]; then
        _manifest_origin="<inline>"
      else
        _manifest_origin="$_manifest"
      fi
      _manifest_preview="$(printf '%s' "$_manifest_content" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g' | cut -c1-220)"
      rm -f "$_json_tmp"
      logging__error "Manifest parse failed for: ${_manifest_origin}"
      [[ -n "${_manifest_preview:-}" ]] && logging__info "Manifest preview: ${_manifest_preview}"
      logging__error "Manifest parse failed — see jq error above."
      return 1
    fi
    while IFS= read -r _item; do
      _kind="$(printf '%s' "$_item" | json__query -r '.kind' 2> /dev/null)" || continue
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
    done <<< "$_parsed_records"
    rm -f "$_json_tmp"
    logging__info "YAML manifest parsed: ${#_Y_PRESCRIPTS[@]} prescript(s), ${#_Y_KEYS[@]} key(s), ${#_Y_REPOS[@]} repo(s), ${#_Y_PPAS[@]} ppa(s), ${#_Y_TAPS[@]} tap(s), ${#_Y_COPR[@]} copr(s), ${#_Y_MODULES[@]} module(s), ${#_Y_GROUPS[@]} group(s), ${#_Y_PACKAGES[@]} package(s), ${#_Y_CASKS[@]} cask(s), ${#_Y_SCRIPTS[@]} script(s)."

    # Remove path: uninstall packages/casks from the manifest, then return.
    # Keys, repos, prescripts, scripts, modules, and groups are skipped —
    # only the installed packages and casks are removed.
    if [[ "$_do_remove" == true ]]; then
      local -a _pkgs_to_remove=()
      local _rpkgitem _rpkgname
      for _rpkgitem in "${_Y_PACKAGES[@]}"; do
        _rpkgname="$(printf '%s' "$_rpkgitem" | json__query -r '.name')"
        [[ -z "${_rpkgname:-}" ]] && continue
        _pkgs_to_remove+=("$_rpkgname")
      done
      if [[ ${#_pkgs_to_remove[@]} -gt 0 ]]; then
        logging__info "Removing ${#_pkgs_to_remove[@]} package(s) from manifest."
        ospkg__remove_user "${_pkgs_to_remove[@]}"
      fi
      if [[ ${#_Y_CASKS[@]} -gt 0 && "$_OSPKG__PKG_MNGR" == "brew" && "$(uname -s)" == "Darwin" ]]; then
        local _rcaskitem _rcask
        for _rcaskitem in "${_Y_CASKS[@]}"; do
          _rcask="$(printf '%s' "$_rcaskitem" | json__query -r '.cask')"
          logging__remove "Removing cask: ${_rcask}"
          _ospkg__brew_run uninstall --cask "$_rcask" >&2
          logging__success "Cask removed: ${_rcask}"
        done
      fi
      return 0
    fi

    # Build-group snapshots diff the PM package list. Defer until after manifest
    # parse so top-level/nested `when` clauses can yield zero install actions (e.g.
    # Linux-only build deps on macOS) without calling the PM list command.
    if [[ -n "$_build_group" ]] &&
      [[ ${#_Y_PACKAGES[@]} -eq 0 && ${#_Y_GROUPS[@]} -eq 0 &&
        ${#_Y_CASKS[@]} -eq 0 && ${#_Y_MODULES[@]} -eq 0 ]]; then
      logging__skip "Build group '${_build_group}': manifest has no install actions on this platform; skipping build-dep tracking."
      return 0
    fi

    if [[ -n "$_build_group" && "$_dry_run" == false ]]; then
      local _bd_dir
      _bd_dir="$(_ospkg__build_deps_dir)"
      _before_snapshot_file="${_bd_dir}/${_build_group//\//_}.before"
      logging__info "Build group '${_build_group}': recording pre-install package snapshot."
      # Register in the live registry (first-in takes the shared global-auto
      # snapshot under the mutex); otherwise snapshot per-invocation as before.
      _ospkg__registry_register
      _ospkg__registry_active || _ospkg__ensure_global_auto_snapshot
      _ospkg__snapshot_packages "$_before_snapshot_file"
    fi

    # Helper: run a shell script with dry-run support.
    _run_script() {
      local _label="$1" _content="$2"
      local _stmp
      _stmp="$(mktemp "${_ospkg__dir}/script_XXXXXX")"
      printf '%s\n' "$_content" > "$_stmp"
      chmod +x "$_stmp"
      logging__launch "Running ${_label}."
      if [[ "$_dry_run" == true ]]; then
        logging__inspect "[dry-run] ${_label} — would execute:"
        sed 's/^/    /' "$_stmp" >&2
      else
        shell__bash "$_stmp"
      fi
      rm -f "$_stmp"
      return 0
    }

    # Phase: PRESCRIPTS.
    if [[ ${#_Y_PRESCRIPTS[@]} -gt 0 ]]; then
      local _combined_prescript=""
      local _pitem
      for _pitem in "${_Y_PRESCRIPTS[@]}"; do
        _combined_prescript+="$(printf '%s' "$_pitem" | json__query -r '.content')"$'\n'
      done
      _run_script "prescript" "$_combined_prescript"
      logging__success "Prescript(s) completed."
    else
      logging__info "No prescripts found — skipping."
    fi

    local _yaml_key_added=false
    local -a _yaml_keys_written=()

    # Phase: SIGNING KEYS.
    if [[ ${#_Y_KEYS[@]} -gt 0 ]]; then
      logging__info "Installing ${#_Y_KEYS[@]} signing key(s)."
      local _key_gnupghome
      _key_gnupghome="$(file__mktmpdir "ospkg-gnupg")"
      chmod 700 "$_key_gnupghome"
      if [[ "$_dry_run" == false ]]; then
        export GNUPGHOME="$_key_gnupghome"
      fi
      local _kitem _kurl _kdest _kdearmor _kfp _keff
      for _kitem in "${_Y_KEYS[@]}"; do
        _kurl="$(printf '%s' "$_kitem" | json__query -r '.url // empty')"
        _kdest="$(printf '%s' "$_kitem" | json__query -r '.dest')"
        _kdearmor="$(printf '%s' "$_kitem" | json__query -r 'if .dearmor == true then "true" elif .dearmor == false then "false" else "auto" end')"
        _kfp="$(printf '%s' "$_kitem" | json__query -r '.fingerprint // empty')"
        # Expand ${token} substitutions in url and dest.
        _kurl="$(ctx__expand_pattern "${_kurl}")"
        _kdest="$(ctx__expand_pattern "${_kdest}")"
        _keff="$(_ospkg__key_effective_path "$_kdest" "$_kdearmor")"
        if [[ "$_dry_run" == true ]]; then
          if [[ -n "${_kfp:-}" && -z "${_kurl:-}" ]]; then
            logging__inspect "[dry-run] key: fingerprint=${_kfp} → ${_keff}"
          elif [[ "${_keff}" != "${_kdest}" ]]; then
            logging__inspect "[dry-run] key: ${_kurl} → ${_keff} (dearmor=${_kdearmor}; manifest dest=${_kdest})"
          else
            logging__inspect "[dry-run] key: ${_kurl} → ${_keff} (dearmor=${_kdearmor})"
          fi
        else
          _ospkg__install_key_entry "$_kurl" "$_kdest" "$_kdearmor" "$_kfp"
          _yaml_keys_written+=("$_keff")
          _yaml_key_added=true
        fi
      done
      if [[ "$_dry_run" == false ]]; then
        unset GNUPGHOME
      fi
      rm -rf "$_key_gnupghome"
      logging__success "Signing keys installed."
    else
      logging__info "No signing keys found — skipping."
    fi

    # Phase: REPOS.
    local _yaml_repo_added=false
    local _OSPKG__APK_ADDED_REPOS=()
    if [[ ${#_Y_REPOS[@]} -gt 0 ]]; then
      logging__info "Adding ${#_Y_REPOS[@]} repository entry/entries."
      local _ritem _rcontent
      for _ritem in "${_Y_REPOS[@]}"; do
        _rcontent="$(printf '%s' "$_ritem" | json__query -r '.content')"
        if [[ "$_dry_run" == true ]]; then
          logging__inspect "[dry-run] repo: would add: ${_rcontent}"
        else
          _ospkg__install_repo_content "${_rcontent}"$'\n'
          _yaml_repo_added=true
        fi
      done
    else
      logging__info "No repo entries found — skipping."
    fi

    # Phase: PPAs (APT only).
    if [[ ${#_Y_PPAS[@]} -gt 0 ]]; then
      if [[ "$_OSPKG__FAMILY" == "apt" ]]; then
        logging__info "Adding ${#_Y_PPAS[@]} PPA(s)."
        if ! command -v add-apt-repository > /dev/null 2>&1; then
          logging__info "add-apt-repository not found — installing software-properties-common."
          [[ "$_dry_run" == false ]] && ospkg__install_tracked "devfeats-ospkg-internals" software-properties-common
        fi
        local _ppitem _ppa
        for _ppitem in "${_Y_PPAS[@]}"; do
          _ppa="$(printf '%s' "$_ppitem" | json__query -r '.ppa')"
          if [[ "$_dry_run" == true ]]; then
            logging__inspect "[dry-run] ppa: would run: add-apt-repository -y '${_ppa}'"
          else
            logging__info "Adding PPA: ${_ppa}"
            users__run_privileged add-apt-repository -y "$_ppa" >&2
            _yaml_repo_added=true
            logging__success "PPA added: ${_ppa}"
          fi
        done
      else
        logging__warn "PPAs are only supported on APT — ignoring (current PM: ${_OSPKG__PKG_MNGR})."
      fi
    fi

    # Phase: TAPS (brew only).
    if [[ ${#_Y_TAPS[@]} -gt 0 ]]; then
      if [[ "$_OSPKG__PKG_MNGR" == "brew" ]]; then
        logging__info "Adding ${#_Y_TAPS[@]} Homebrew tap(s)."
        local _titem _tap_val _tap_name _tap_url
        for _titem in "${_Y_TAPS[@]}"; do
          _tap_val="$(printf '%s' "$_titem" | json__query -r '.tap')"
          if printf '%s' "$_tap_val" | json__query -e 'type == "object"' > /dev/null 2>&1; then
            _tap_name="$(printf '%s' "$_tap_val" | json__query -r '.name')"
            _tap_url="$(printf '%s' "$_tap_val" | json__query -r '.url // empty')"
          else
            # tap is a plain string in the json__query -c output
            _tap_name="$(printf '%s' "$_titem" | json__query -r '.tap | if type == "object" then .name else . end')"
            _tap_url="$(printf '%s' "$_titem" | json__query -r '.tap | if type == "object" then (.url // "") else "" end')"
          fi
          if [[ "$_dry_run" == true ]]; then
            logging__inspect "[dry-run] tap: would run: brew tap ${_tap_name}${_tap_url:+ ${_tap_url}}"
          else
            logging__info "Tapping: ${_tap_name}"
            if [[ -n "${_tap_url:-}" ]]; then
              _ospkg__brew_run tap "$_tap_name" "$_tap_url" >&2
            else
              _ospkg__brew_run tap "$_tap_name" >&2
            fi
            logging__success "Tap added: ${_tap_name}"
          fi
        done
      else
        logging__warn "Homebrew taps are only supported when PM is brew — ignoring."
      fi
    fi

    # Phase: COPR (DNF only).
    if [[ ${#_Y_COPR[@]} -gt 0 ]]; then
      if [[ "$_OSPKG__FAMILY" == "dnf" ]]; then
        local _copr_dnf_bin
        if ! _copr_dnf_bin="$(_ospkg__dnf_bin)"; then
          logging__warn "COPR repos require full dnf — '${_OSPKG__PKG_MNGR}' does not support 'copr enable'; skipping."
        else
          logging__info "Enabling ${#_Y_COPR[@]} COPR repo(s)."
          local _copritem _copr
          for _copritem in "${_Y_COPR[@]}"; do
            _copr="$(printf '%s' "$_copritem" | json__query -r '.copr')"
            if [[ "$_dry_run" == true ]]; then
              logging__inspect "[dry-run] copr: would run: ${_copr_dnf_bin} copr enable -y '${_copr}'"
            else
              logging__info "Enabling COPR: ${_copr}"
              users__run_privileged "$_copr_dnf_bin" copr enable -y "$_copr" >&2
              _yaml_repo_added=true
            fi
          done
        fi
      else
        logging__warn "COPR repos are only supported on DNF — ignoring (current PM: ${_OSPKG__PKG_MNGR})."
      fi
    fi

    # Phase: MODULES (DNF only).
    if [[ ${#_Y_MODULES[@]} -gt 0 ]]; then
      if [[ "$_OSPKG__FAMILY" == "dnf" ]]; then
        local _mod_dnf_bin
        if ! _mod_dnf_bin="$(_ospkg__dnf_bin)"; then
          logging__warn "DNF module streams require full dnf — '${_OSPKG__PKG_MNGR}' does not support 'module enable'; skipping."
        else
          logging__info "Enabling ${#_Y_MODULES[@]} DNF module stream(s)."
          local _moditem _mod
          for _moditem in "${_Y_MODULES[@]}"; do
            _mod="$(printf '%s' "$_moditem" | json__query -r '.module')"
            if [[ "$_dry_run" == true ]]; then
              logging__inspect "[dry-run] module: would run: ${_mod_dnf_bin} module enable -y '${_mod}'"
            else
              logging__info "Enabling module: ${_mod}"
              users__run_privileged "$_mod_dnf_bin" module enable -y "$_mod" >&2
              logging__success "Module enabled: ${_mod}"
            fi
          done
        fi
      else
        logging__warn "DNF modules are only supported on DNF — ignoring (current PM: ${_OSPKG__PKG_MNGR})."
      fi
    fi

    # Phase: GROUPS.
    if [[ ${#_Y_GROUPS[@]} -gt 0 ]]; then
      local _grpitem _grp
      for _grpitem in "${_Y_GROUPS[@]}"; do
        _grp="$(printf '%s' "$_grpitem" | json__query -r '.group')"
        case "$_OSPKG__FAMILY" in
          dnf)
            if [[ "$_dry_run" == true ]]; then
              logging__inspect "[dry-run] group: would run: ${_OSPKG__PKG_MNGR} group install -y '${_grp}'"
            else
              logging__install "Installing group '${_grp}' (dnf)."
              users__run_privileged "$_OSPKG__PKG_MNGR" group install -y "$_grp" >&2
              logging__success "Group '${_grp}' installed."
            fi
            ;;
          zypper)
            if [[ "$_dry_run" == true ]]; then
              logging__inspect "[dry-run] group: would run: zypper --non-interactive install -t pattern '${_grp}'"
            else
              logging__install "Installing pattern '${_grp}' (zypper)."
              users__run_privileged zypper --non-interactive install -t pattern "$_grp" >&2
            fi
            ;;
          pacman)
            if [[ "$_dry_run" == true ]]; then
              logging__inspect "[dry-run] group: would run: ${_OSPKG__INSTALL[*]} '${_grp}'"
            else
              logging__install "Installing group '${_grp}' (pacman)."
              ospkg__install "$_grp"
              if [[ -z "${_build_group:-}" ]]; then
                local -a _grp_members=()
                mapfile -t _grp_members < <(pacman -Sg "$_grp" 2> /dev/null | awk '{print $2}')
                [[ ${#_grp_members[@]} -gt 0 ]] && _ospkg__protect_user_pkgs "${_grp_members[@]}"
              fi
            fi
            ;;
          *)
            logging__warn "Group '${_grp}' — groups not supported on '${_OSPKG__PKG_MNGR}'; skipping."
            ;;
        esac
      done
    fi

    # Phase: INSTALL PACKAGES.
    # Package list update is deferred: called lazily only when a package
    # actually needs installing (or a repo was added but no packages ran).
    # This avoids running privileged ospkg__update when all packages are
    # already installed.
    local -a _update_args=(--lists_max_age "$_lists_max_age")
    [[ "$_yaml_repo_added" == true ]] && _update_args+=(--repo_added)
    local _pkg_update_done=false
    _ensure_pkg_update() {
      [[ "$_pkg_update_done" == true ]] && return 0
      _pkg_update_done=true
      if [[ "$_update_index" == false ]]; then
        logging__info "Package list update skipped (update-index=false)."
        _OSPKG__UPDATED=true
        [[ "$_yaml_repo_added" == true ]] && logging__warn "A repository was added but update-index=false — packages may not be found."
        return 0
      fi
      if [[ "$_dry_run" == true ]]; then
        if [[ ${#_OSPKG__UPDATE[@]} -gt 0 ]]; then
          logging__inspect "[dry-run] update: would run: ${_OSPKG__UPDATE[*]}"
        else
          logging__info "Package list update not supported by '${_OSPKG__PKG_MNGR}' — skipping."
        fi
      else
        ospkg__update "${_update_args[@]}"
      fi
    }
    local -a _pkgs_to_install=() _pkg_base_names=()
    local _pkgitem _pkgname _pkgflags _pkgversion _pkginstall _resolved_ver _pkgcommand
    for _pkgitem in "${_Y_PACKAGES[@]}"; do
      _pkgname="$(printf '%s' "$_pkgitem" | json__query -r '.name')"
      _pkgcommand="$(printf '%s' "$_pkgitem" | json__query -r '.command // empty')"
      _pkgflags="$(printf '%s' "$_pkgitem" | json__query -r '.flags // empty')"
      _pkgversion="$(printf '%s' "$_pkgitem" | json__query -r '.version // empty')"
      _pkgversion="$(ctx__expand_pattern "${_pkgversion}")"
      _pkgversion="$(_ospkg__normalize_pkg_version_spec "${_pkgversion}")"
      [[ -z "${_pkgname:-}" ]] && continue

      # PATH guard: skip when the dependency is already satisfied by a command on
      # PATH — regardless of how it was installed (a binary/cargo/npm install by
      # another feature, or an existing system tool). Unlike ospkg__is_installed
      # (PM-native, below), this works on every platform and honours non-PM
      # installs. Same non-`--update` gating, so `--update` runs still refresh it.
      if _ospkg__command_satisfied "$_do_pkg_update" "${_pkgcommand:-}" "${_runtime_path:-}"; then
        logging__skip "'${_pkgname}' satisfied by on-PATH command '${_pkgcommand}' (runtime PATH); skipping install."
        # A run dependency must persist at runtime. If the satisfying tool was
        # installed as a build dependency or bootstrapped (tracked for cleanup),
        # promote it out of the build-dep registry — exactly as the PM-native
        # already-installed skip below does — so end-of-install cleanup cannot
        # remove it. Build deps keep `_build_group` set and stay removable.
        [[ -z "${_build_group:-}" ]] && _ospkg__protect_user_pkgs "$_pkgname"
        continue
      fi

      # Apply version constraint (PM-native syntax).
      if [[ -n "${_pkgversion:-}" ]]; then
        # Resolve the user spec (e.g. "5.9") to the PM's exact version string
        # (e.g. "5.9-6ubuntu2") so the install command uses an exact match.
        if ! _resolved_ver="$(ospkg__resolve_version "${_pkgname}" "${_pkgversion}" 2> /dev/null)"; then
          # On a supported PM, a resolution failure means the repository has no
          # version matching the spec. Fail fast with a clear message rather than
          # building an unsatisfiable versioned spec (e.g. `zsh=5.9.1` when the
          # repo only ships 5.9), which the installer would otherwise retry many
          # times over before finally giving up. Unknown PMs keep the previous
          # best-effort raw-spec fallback.
          case "$_OSPKG__FAMILY" in
            apt | apk | dnf | yum | zypper | pacman | brew)
              logging__error "No version of '${_pkgname}' matching '${_pkgversion}' is available in the ${_OSPKG__FAMILY} repositories."
              return 1
              ;;
            *) _resolved_ver="${_pkgversion}" ;;
          esac
        fi
        case "$_OSPKG__FAMILY" in
          apt | apk | pacman | zypper) _pkginstall="${_pkgname}=${_resolved_ver}" ;;
          dnf | yum) _pkginstall="${_pkgname}-${_resolved_ver}" ;;
          brew) _pkginstall="${_pkgname}@${_resolved_ver}" ;;
          *) _pkginstall="${_pkgname}" ;;
        esac
      else
        _pkginstall="${_pkgname}"
      fi

      if [[ "$_do_pkg_update" == false ]] && ospkg__is_installed "$_pkgname"; then
        if [[ "$_fail_if_installed" == true ]]; then
          logging__error "Package '${_pkgname}' is already installed (if_exists=fail)."
          return 1
        fi
        [[ -z "${_build_group:-}" ]] && _ospkg__protect_user_pkgs "$_pkgname"
        continue
      fi

      # For PMs that support per-package flags, build the install command.
      if [[ -n "${_pkgflags:-}" ]]; then
        _ensure_pkg_update || {
          logging__error "package list update failed."
          return 1
        }
        if [[ "$_dry_run" == true ]]; then
          logging__inspect "[dry-run] package: ${_OSPKG__INSTALL[*]} ${_pkgflags} ${_pkginstall}"
        else
          logging__info "Installing: ${_pkginstall} (flags: ${_pkgflags})"
          # shellcheck disable=SC2086
          "${_OSPKG__INSTALL[@]}" $_pkgflags "$_pkginstall" >&2
          [[ -z "${_build_group:-}" ]] && _ospkg__protect_user_pkgs "$_pkgname"
        fi
      else
        _pkgs_to_install+=("$_pkginstall")
        _pkg_base_names+=("$_pkgname")
      fi
    done

    if [[ ${#_pkgs_to_install[@]} -gt 0 ]]; then
      _ensure_pkg_update || {
        logging__error "package list update failed."
        return 1
      }
      logging__install "Installing ${#_pkgs_to_install[@]} package(s)."
      if [[ "$_dry_run" == true ]]; then
        logging__inspect "[dry-run] packages: ${_pkgs_to_install[*]}"
      else
        if [[ "$_do_pkg_update" == true ]]; then
          ospkg__install --update "${_pkgs_to_install[@]}"
        else
          ospkg__install "${_pkgs_to_install[@]}"
        fi
        [[ -z "${_build_group:-}" ]] && _ospkg__protect_user_pkgs "${_pkg_base_names[@]}"
      fi
    elif [[ ${#_Y_PACKAGES[@]} -eq 0 ]]; then
      logging__info "No packages to install — skipping."
    fi

    # If a repo was added but no packages needed installing, still refresh so
    # the newly configured repo is usable by subsequent code.
    if [[ "$_yaml_repo_added" == true && "$_pkg_update_done" == false ]]; then
      _ensure_pkg_update || {
        logging__error "package list update failed after adding a repository."
        return 1
      }
    fi

    # Phase: CASKS (brew/macOS only).
    if [[ ${#_Y_CASKS[@]} -gt 0 ]]; then
      if [[ "$_OSPKG__PKG_MNGR" == "brew" && "$(uname -s)" == "Darwin" ]]; then
        logging__info "Installing ${#_Y_CASKS[@]} Homebrew cask(s)."
        local _caskitem _cask
        for _caskitem in "${_Y_CASKS[@]}"; do
          _cask="$(printf '%s' "$_caskitem" | json__query -r '.cask')"
          _cask="$(ctx__expand_pattern "${_cask}")"
          if [[ "$_dry_run" == true ]]; then
            logging__inspect "[dry-run] cask: would run: brew install --cask '${_cask}'"
          else
            logging__info "Installing cask: ${_cask}"
            _ospkg__brew_run install --cask "$_cask" >&2
            logging__success "Cask installed: ${_cask}"
          fi
        done
      else
        logging__warn "Casks are only supported on macOS with Homebrew — ignoring."
      fi
    fi

    # Phase: SCRIPTS.
    if [[ ${#_Y_SCRIPTS[@]} -gt 0 ]]; then
      local _combined_script=""
      local _sitem
      for _sitem in "${_Y_SCRIPTS[@]}"; do
        _combined_script+="$(printf '%s' "$_sitem" | json__query -r '.content')"$'\n'
      done
      _run_script "script" "$_combined_script"
      logging__success "Script(s) completed."
    else
      logging__info "No scripts found — skipping."
    fi

    # Phase: REPO CLEANUP.
    # Taps: always kept (never cleaned up).
    # Other repos: remove unless --keep_repos.
    if [[ "$_yaml_repo_added" == true && "$_keep_repos" == false ]]; then
      logging__remove "Removing added repositories."
      if [[ "$_OSPKG__FAMILY" = "apt" ]]; then
        users__run_privileged rm -f /etc/apt/sources.list.d/syspkg-installer.list
        logging__remove "Removed /etc/apt/sources.list.d/syspkg-installer.list"
      elif [[ "$_OSPKG__FAMILY" = "apk" ]]; then
        local _rl
        for _rl in "${_OSPKG__APK_ADDED_REPOS[@]}"; do
          users__run_privileged sed -i "\\|^${_rl}$|d" /etc/apk/repositories
          logging__remove "Removed APK repo: ${_rl}"
        done
      elif [[ "$_OSPKG__FAMILY" = "dnf" ]]; then
        users__run_privileged rm -f /etc/yum.repos.d/syspkg-installer.repo
        logging__remove "Removed /etc/yum.repos.d/syspkg-installer.repo"
      elif [[ "$_OSPKG__FAMILY" = "zypper" ]]; then
        users__run_privileged rm -f /etc/zypp/repos.d/syspkg-installer.repo
      elif [[ "$_OSPKG__FAMILY" = "pacman" ]]; then
        users__run_privileged rm -f /etc/pacman.d/syspkg-installer.conf
        users__run_privileged sed -i '/^Include = \/etc\/pacman.d\/syspkg-installer.conf$/d' /etc/pacman.conf
      fi
    elif [[ "$_yaml_repo_added" == true ]]; then
      logging__info "Keeping added repositories (--keep_repos)."
    fi

    # Phase: KEY CLEANUP.
    # Signing keys added during this run are removed unless --keep_repos.
    if [[ "$_yaml_key_added" == true && "$_keep_repos" == false ]]; then
      logging__remove "Removing installed signing keys."
      local _kpath
      for _kpath in "${_yaml_keys_written[@]}"; do
        rm -f "$_kpath"
        logging__remove "Removed signing key: ${_kpath}"
      done
    elif [[ "$_yaml_key_added" == true ]]; then
      logging__info "Keeping installed signing keys (--keep_repos)."
    fi

    # Apply build-group tracking: diff against pre-install snapshot, mark new packages.
    if [[ -n "$_build_group" && -n "$_before_snapshot_file" ]]; then
      _ospkg__mark_build_group "$_build_group" "$_before_snapshot_file"
      rm -f "$_before_snapshot_file"
      # Mirror the group into the live registry (non-session mode) so it survives
      # this invocation's temp session root and a concurrent last-out can see it.
      [[ -z "${_SYSSET_SESSION_TRACK_DIR:-}" ]] &&
        _ospkg__registry_mirror_group "$_build_group"
    fi

  fi # end manifest processing

  return 0
}
