# shellcheck shell=bash
#
# install-nix — feature-specific logic.
#
# Nix installs to the hardcoded path /nix, so this is not a prefix feature: it
# drives the official Nix installer script (or the Rust nix-installer) and wires
# up shell activation itself. See metadata.yaml for the option surface.

# ── Resolution & validation ───────────────────────────────────────────────────

# Resolve installer, mode, and single-user owner from the parsed options, and
# enforce the method×mode×platform validity matrix. Sets these globals:
#   _NIX_INSTALLER  — "shell" | "nix-installer"
#   NIX_MULTI_USER  — "true" | "false"   (also the entrypoint _conf_var)
#   INSTALL_USER    — single-user owner   (single-user only)
__init_args_post() {
  local _kernel
  _kernel="$(ctx__get plat.kernel)" # "Linux" | "Darwin"

  # --- installer ---
  case "${INSTALLER:-auto}" in
    nix-installer) _NIX_INSTALLER=nix-installer ;;
    shell | auto | *) _NIX_INSTALLER=shell ;;
  esac
  declare -g _NIX_INSTALLER

  # Candidate single-user owner: an explicit install_user, else the contextual
  # user (SUDO_USER / devcontainer _REMOTE_USER / process owner). Used both to
  # resolve `multi_user=auto` and as the single-user owner.
  local _owner="${INSTALL_USER:-}"
  [ -n "${_owner}" ] || _owner="$(users__get_current)"

  # --- mode ---
  case "${MULTI_USER:-auto}" in
    single) NIX_MULTI_USER=false ;;
    multi) NIX_MULTI_USER=true ;;
    auto | *)
      if [ "${_kernel}" = "Darwin" ]; then
        # macOS supports multi-user only.
        NIX_MULTI_USER=true
      elif [ "${_owner}" = "root" ]; then
        # No non-root owner available (bare root install, not a devcontainer with
        # a remote user) — a single-user store can't be owned by root, so install
        # system-wide multi-user.
        NIX_MULTI_USER=true
      else
        # A non-root owner exists (devcontainer remote user, non-root caller, or
        # explicit install_user) — install single-user owned by them.
        NIX_MULTI_USER=false
      fi
      ;;
  esac
  declare -g NIX_MULTI_USER

  # --- validity matrix ---
  if [ "${_kernel}" = "Darwin" ] && [ "${NIX_MULTI_USER}" = "false" ]; then
    logging__error "Single-user Nix is not supported on macOS; use multi_user=multi (or auto)."
    return 1
  fi
  if [ "${_NIX_INSTALLER}" = "nix-installer" ] && [ "${NIX_MULTI_USER}" = "false" ]; then
    logging__error "installer=nix-installer requires multi_user=multi; it cannot perform a single-user install."
    return 1
  fi

  # --- single-user owner finalization ---
  if [ "${NIX_MULTI_USER}" = "false" ]; then
    INSTALL_USER="${_owner}"
    declare -g INSTALL_USER
    if [ "${INSTALL_USER}" = "root" ]; then
      logging__error "Single-user Nix cannot be owned by root; set install_user to a non-root account or use multi_user=multi."
      return 1
    fi
    # Only root can install on behalf of another user.
    local _cur
    _cur="$(users__get_current --no-sudo)"
    if ! users__is_root && [ "${INSTALL_USER}" != "${_cur}" ]; then
      logging__error "install_user='${INSTALL_USER}' differs from the current user '${_cur}'; only root can install for another user."
      return 1
    fi
    if ! id "${INSTALL_USER}" &> /dev/null; then
      logging__error "install_user='${INSTALL_USER}' does not exist on this system."
      return 1
    fi
    # The owner is the only account that can use a single-user store, so it must
    # always be configured for activation — even when it is not the current /
    # remote / container user (e.g. a root standalone install with an explicit
    # install_user). configure_users resolves ADD_USERS; append the owner there.
    # (shell__sync_block is marker-based, so a duplicate is harmless.)
    if [[ -v ADD_USERS ]]; then
      ADD_USERS+=("${INSTALL_USER}")
    else
      declare -g -a ADD_USERS=("${INSTALL_USER}")
    fi
  fi

  local _mode_label="single-user"
  [ "${NIX_MULTI_USER}" = "true" ] && _mode_label="multi-user"
  logging__info "Nix install plan: installer=${_NIX_INSTALLER}, mode=${_mode_label}${INSTALL_USER:+, owner=${INSTALL_USER}}."
  return 0
}

# ── Installer invocation ──────────────────────────────────────────────────────

# Suppress the template's GitHub release-JSON checksum probe for the fetched
# script. We resolve the *version* from git tags (github_tag), but the installer
# script and the binary tarball are served from releases.nixos.org — they are not
# GitHub release assets, and Nix publishes no GitHub releases at all, so the probe
# (GET …/releases/tags/<tag>) 404s and then retries for minutes. The Nix installer
# verifies its own tarball's SHA-256 internally, so no external checksum is needed.
# shellcheck disable=SC2329  # invoked indirectly by __install_run_script__
__github_release_sha256_args__() {
  local -n _nix_sha_out="$2"
  _nix_sha_out=()
  return 0
}

# Build the installer asset URI and argument list before the script is fetched.
# For the shell installer, SCRIPT_ASSET_URI is already the releases.nixos.org URL
# from metadata; only the argument list is computed here.
__install_run_script_pre() {
  if [ "${_NIX_INSTALLER}" = "nix-installer" ]; then
    # nix-installer args are built in __nix_run_installer_binary; only the asset
    # URI differs from the shell installer here.
    SCRIPT_ASSET_URI="https://artifacts.nixos.org/nix-installer"
    declare -g SCRIPT_ASSET_URI
    return 0
  fi

  local -a _args=()
  if [ "${NIX_MULTI_USER}" = "true" ]; then
    _args+=(--daemon)
    [ -n "${BUILD_USER_COUNT:-}" ] && _args+=(--daemon-user-count "${BUILD_USER_COUNT}")
  else
    _args+=(--no-daemon)
  fi
  # We own profile activation (see __configure_user), so tell the installer not to
  # touch shell profiles; --yes runs it non-interactively.
  _args+=(--no-modify-profile --yes)
  [ "${ADD_CHANNEL:-true}" = "true" ] || _args+=(--no-channel-add)

  declare -g -a _NIX_INSTALL_ARGS=("${_args[@]}")
  return 0
}

# Execute the fetched installer: as root for multi-user, or as the install user
# (with /nix pre-provisioned) for single-user.
__install_run_script_run() {
  local _script="$1"

  if [ "${_NIX_INSTALLER}" = "nix-installer" ]; then
    __nix_run_installer_binary "${_script}"
    return $?
  fi

  # runuser drops to INSTALL_USER, which must be able to traverse and read the
  # (root, mode-700) process temp tree the installer was fetched into.
  local _work_dir
  _work_dir="$(dirname "$(dirname "${_script}")")"
  file__chmod -R a+rX "${_work_dir}" 2> /dev/null || true
  file__chmod a+x "$(dirname "${_work_dir}")" 2> /dev/null || true

  local _rc
  if [ "${NIX_MULTI_USER}" = "true" ]; then
    logging__launch "Running the Nix multi-user installer."
    sh "${_script}" "${_NIX_INSTALL_ARGS[@]}"
    _rc=$?
  else
    __nix_prepare_store_dir "${INSTALL_USER}"
    logging__launch "Running the Nix single-user installer as '${INSTALL_USER}'."
    users__run_as "${INSTALL_USER}" -- sh "${_script}" "${_NIX_INSTALL_ARGS[@]}"
    _rc=$?
  fi

  [ "${_rc}" -eq 0 ] || {
    logging__error "Nix installer exited with status ${_rc}."
    return "${_rc}"
  }
  logging__success "Nix installer completed."
  return 0
}

# Create /nix owned by the single-user owner before running the installer, so it
# need not escalate to create the store directory itself.
__nix_prepare_store_dir() {
  local _user="$1"
  if [ ! -e /nix ]; then
    logging__install "Creating '/nix' owned by '${_user}'."
    file__mkdir /nix
    file__chmod 0755 /nix
    file__chown "${_user}" /nix
  fi
  return 0
}

# Drive the Rust nix-installer (multi-user only). The fetched asset
# (artifacts.nixos.org/nix-installer) is a shell script that downloads the right
# static binary and runs it.
#
# Note: nix-installer has no version-pin flag — it installs its own bundled Nix
# version and rejects `--nix-package-url`. To pin an exact Nix version, use
# installer=shell. (The daemon self-test may warn at build time because the
# daemon socket is not up yet under --init none; that is non-fatal — the daemon
# is started by this feature's entrypoint at container start.)
__nix_run_installer_binary() {
  local _script="$1"
  local -a _args=(install)

  if [ "$(ctx__get plat.kernel)" = "Darwin" ]; then
    _args+=(macos)
  else
    _args+=(linux)
    # No systemd (container) → do not manage an init service (root-only Nix; the
    # daemon is started by this feature's entrypoint).
    [ -d /run/systemd/system ] || _args+=(--init none)
  fi
  _args+=(--no-confirm)

  logging__launch "Running the Rust nix-installer: nix-installer ${_args[*]}"
  sh "${_script}" "${_args[@]}"
  local _rc=$?
  [ "${_rc}" -eq 0 ] || {
    logging__error "nix-installer exited with status ${_rc}."
    return "${_rc}"
  }
  logging__success "nix-installer completed."
  return 0
}

# ── Shell activation ──────────────────────────────────────────────────────────

# Write a per-user activation block that sources the appropriate Nix profile
# script. Called for each configured user (configure_users: true).
__configure_user() {
  local _user="$1"
  local _home _files _snippet
  local _marker="nix (install-nix)"

  if [ "${NIX_MULTI_USER}" = "true" ]; then
    _snippet='if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh; fi'
  else
    # Single-user Nix lives in the owner's ~/.nix-profile; only that user gets it.
    if [ "${_user}" != "${INSTALL_USER}" ]; then
      logging__skip "Single-user Nix is owned by '${INSTALL_USER}'; skipping activation for '${_user}'."
      return 0
    fi
    # shellcheck disable=SC2016  # $HOME must expand in the user's shell, not now.
    _snippet='if [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then . "$HOME/.nix-profile/etc/profile.d/nix.sh"; fi'
  fi

  _home="$(users__resolve_home "${_user}")"
  _files="$(shell__user_path_files --home "${_home}")"
  logging__install "Writing Nix activation block for '${_user}'."
  shell__sync_block --files "${_files}" --marker "${_marker}" --content "${_snippet}"
  return 0
}

# ── Post-install: nix.conf, packages, flakes, manifest ────────────────────────

# Runs after installation and activation are complete.
__install_finish_post() {
  __nix_write_conf || return 1
  __nix_realize || return 1
  return 0
}

# Append experimental-features / extra_nix_config lines to /etc/nix/nix.conf
# (the installer creates the file; we augment it idempotently).
__nix_write_conf() {
  local _want_flakes=false
  { [ "${ENABLE_FLAKES:-false}" = "true" ] || [ "${#FLAKES[@]}" -gt 0 ]; } && _want_flakes=true
  if [ "${_want_flakes}" = "false" ] && [ "${#EXTRA_NIX_CONFIG[@]}" -eq 0 ]; then
    return 0
  fi

  file__mkdir /etc/nix
  [ -e /etc/nix/nix.conf ] || printf '' | file__tee /etc/nix/nix.conf > /dev/null

  [ "${_want_flakes}" = "true" ] && __nix_conf_append "experimental-features = nix-command flakes"

  local _line
  for _line in "${EXTRA_NIX_CONFIG[@]+"${EXTRA_NIX_CONFIG[@]}"}"; do
    [ -n "${_line}" ] || continue
    __nix_conf_append "${_line}"
  done
  return 0
}

__nix_conf_append() {
  local _line="$1"
  grep -Fqx "${_line}" /etc/nix/nix.conf 2> /dev/null && return 0
  logging__install "nix.conf += '${_line}'."
  printf '%s\n' "${_line}" | file__tee --append /etc/nix/nix.conf > /dev/null
  return 0
}

# Realize manifest, packages, and flakes into the profile. For multi-user this
# starts a transient build-time daemon and always stops it afterwards, so the
# backgrounded daemon can never keep the installer process alive.
__nix_realize() {
  local _have_work=false
  { [ -n "${MANIFEST:-}" ] || [ "${#PACKAGES[@]}" -gt 0 ] || [ "${#FLAKES[@]}" -gt 0 ]; } && _have_work=true
  [ "${_have_work}" = "true" ] || return 0

  # Multi-user realization at build needs the daemon (no systemd here).
  [ "${NIX_MULTI_USER}" = "true" ] && __nix_ensure_daemon

  local _rc=0
  __nix_realize_all || _rc=$?

  # Stop the transient daemon we started (if any) so the installer can exit.
  __nix_stop_build_daemon
  return "${_rc}"
}

# The actual realization work (kept separate so __nix_realize can guarantee
# daemon teardown regardless of outcome).
__nix_realize_all() {
  # Declarative manifest.
  if [ -n "${MANIFEST:-}" ]; then
    if [ -e "${MANIFEST}" ]; then
      logging__install "Realizing Nix manifest '${MANIFEST}'."
      __nix_env_install -if "${MANIFEST}" || return 1
    else
      # A workspace-relative path not present at build time — defer to onCreate.
      __nix_defer_manifest "${MANIFEST}"
    fi
  fi

  # Named nixpkgs packages.
  local _pkg
  for _pkg in "${PACKAGES[@]+"${PACKAGES[@]}"}"; do
    [ -n "${_pkg}" ] || continue
    logging__install "Installing Nix package 'nixpkgs.${_pkg}'."
    __nix_env_install -iA "nixpkgs.${_pkg}" || return 1
  done

  # Flake references.
  local _flake
  for _flake in "${FLAKES[@]+"${FLAKES[@]}"}"; do
    [ -n "${_flake}" ] || continue
    logging__install "Installing Nix flake '${_flake}'."
    __nix_flake_install "${_flake}" || return 1
  done
  return 0
}

# nix-env install into the right profile as the right user.
#   multi-user: system default profile, as root.
#   single-user: the owner's profile, as the owner.
__nix_env_install() {
  if [ "${NIX_MULTI_USER}" = "true" ]; then
    __nix_as_root nix-env --profile /nix/var/nix/profiles/default "$@"
  else
    __nix_as_owner nix-env "$@"
  fi
}

# nix profile install (flakes). --extra-experimental-features makes this work
# even if nix.conf was not (yet) updated.
__nix_flake_install() {
  local _ref="$1"
  if [ "${NIX_MULTI_USER}" = "true" ]; then
    __nix_as_root nix --extra-experimental-features "nix-command flakes" \
      profile install --profile /nix/var/nix/profiles/default "${_ref}"
  else
    __nix_as_owner nix --extra-experimental-features "nix-command flakes" \
      profile install "${_ref}"
  fi
}

# Run a nix command as root with the multi-user daemon environment sourced.
__nix_as_root() {
  # shellcheck disable=SC1091  # runtime-generated profile script
  (
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2> /dev/null || true
    "$@"
  )
}

# Run a nix command as the single-user owner with their profile sourced.
__nix_as_owner() {
  local _home
  _home="$(users__resolve_home "${INSTALL_USER}")"
  # shellcheck disable=SC1090,SC2016  # $1/$@ expand in the user's subshell, not here
  users__run_as "${INSTALL_USER}" -- bash -c '
    [ -e "$1" ] && . "$1" 2> /dev/null || true
    shift
    exec "$@"
  ' _ "${_home}/.nix-profile/etc/profile.d/nix.sh" "$@"
}

# Start a transient nix-daemon at build time (multi-user) and wait for its
# socket. The daemon is launched directly (not via a subshell, and without
# sourcing the client profile — which would set NIX_REMOTE=daemon) with stdin
# detached and disowned, so it never blocks the installer's exit; its PID is
# recorded so __nix_stop_build_daemon can stop it once realization is done.
__nix_ensure_daemon() {
  # macOS: the daemon is managed by launchd and started during installation
  # (and `pidof` is not available there).
  [ "$(ctx__get plat.kernel)" = "Darwin" ] && return 0
  # Already running (e.g. a systemd host started it) — leave it alone.
  pidof nix-daemon > /dev/null 2>&1 && return 0
  local _daemon=/nix/var/nix/profiles/default/bin/nix-daemon
  [ -x "${_daemon}" ] || {
    logging__warn "nix-daemon not found; cannot realize packages at build time."
    return 0
  }
  logging__info "Starting a transient nix-daemon for build-time realization."
  "${_daemon}" > /tmp/nix-daemon-build.log 2>&1 < /dev/null &
  declare -g _NIX_BUILD_DAEMON_PID=$!
  disown 2> /dev/null || true
  local _i
  for _i in $(seq 1 40); do
    [ -S /nix/var/nix/daemon-socket/socket ] && return 0
    sleep 0.5
  done
  logging__warn "nix-daemon socket did not appear in time; realization may fail."
  return 0
}

# Stop the transient build-time daemon (if we started one) so the installer
# process can exit cleanly. A daemon already running before we started (systemd
# host) has no recorded PID and is left untouched.
__nix_stop_build_daemon() {
  [ -n "${_NIX_BUILD_DAEMON_PID:-}" ] || return 0
  logging__info "Stopping the transient build-time nix-daemon (pid ${_NIX_BUILD_DAEMON_PID})."
  kill "${_NIX_BUILD_DAEMON_PID}" 2> /dev/null || true
  _NIX_BUILD_DAEMON_PID=""
  return 0
}

# Deploy an onCreate hook to realize a workspace manifest once it is mounted.
__nix_defer_manifest() {
  local _manifest="$1"
  logging__info "Manifest '${_manifest}' not present at build time; deferring to container-create."
  # Nothing else to do here: __deploy_lifecycle_scripts__ deploys the
  # files/on-create--nix-manifest.sh hook, and MANIFEST is passed to it via
  # _conf_vars (see metadata.yaml).
  return 0
}

# ── Existing installation (if_exists) ─────────────────────────────────────────

# Probe for an existing Nix. nix-env is not on the default PATH, so also check
# the well-known default-profile path and a populated store. Overriding
# __detect_existing_path__ (not the __detect_existing__ wrapper) keeps the
# template's method detection — which sets _FEAT_EXISTING_METHOD — in play.
__detect_existing_path__() {
  declare -g _FEAT_EXISTING_PATH=""
  declare -g _FEAT_EXISTING=false
  _FEAT_EXISTING_PATH="$(command -v nix-env 2> /dev/null || true)"
  if [ -z "${_FEAT_EXISTING_PATH}" ] && [ -x /nix/var/nix/profiles/default/bin/nix-env ]; then
    _FEAT_EXISTING_PATH="/nix/var/nix/profiles/default/bin/nix-env"
  fi
  if [ -z "${_FEAT_EXISTING_PATH}" ] && [ -d /nix/store ]; then
    _FEAT_EXISTING_PATH="/nix"
  fi
  [ -n "${_FEAT_EXISTING_PATH}" ] && _FEAT_EXISTING=true
  return 0
}

# Best-effort removal (if_exists=uninstall / reinstall).
__uninstall_run__() {
  # Prefer the nix-installer receipt for a clean, complete uninstall.
  if [ -x /nix/nix-installer ]; then
    logging__remove "Uninstalling Nix via the nix-installer receipt."
    if /nix/nix-installer uninstall --no-confirm; then
      return 0
    fi
    logging__warn "nix-installer uninstall failed; falling back to manual removal."
  fi
  __nix_manual_uninstall
}

__nix_manual_uninstall() {
  logging__remove "Removing Nix (best-effort manual uninstall)."

  # Stop the daemon (systemd service or a bare background process).
  if [ -e /run/systemd/system ]; then
    systemctl stop nix-daemon.socket nix-daemon.service 2> /dev/null || true
    systemctl disable nix-daemon.socket nix-daemon.service 2> /dev/null || true
    systemctl daemon-reload 2> /dev/null || true
  fi
  pkill -x nix-daemon 2> /dev/null || true

  # Remove build users and group.
  local _u
  while IFS=: read -r _u _; do
    case "${_u}" in nixbld*) userdel "${_u}" 2> /dev/null || true ;; esac
  done < /etc/passwd
  groupdel nixbld 2> /dev/null || true

  # Remove the store, system config, and daemon artifacts.
  file__rm -rf /nix /etc/nix /etc/profile.d/nix.sh /etc/tmpfiles.d/nix-daemon.conf 2> /dev/null || true

  # Remove per-user Nix state and our activation blocks for configured users.
  local _cu _home _files
  for _cu in "${_FEAT_CONFIGURE_USERS[@]+"${_FEAT_CONFIGURE_USERS[@]}"}"; do
    _home="$(users__resolve_home "${_cu}" 2> /dev/null || true)"
    [ -n "${_home}" ] || continue
    file__rm -rf "${_home}/.nix-profile" "${_home}/.nix-defexpr" "${_home}/.nix-channels" 2> /dev/null || true
    _files="$(shell__user_path_files --home "${_home}" 2> /dev/null || true)"
    [ -n "${_files}" ] && shell__sync_block --files "${_files}" --marker "nix (install-nix)" 2> /dev/null || true
  done

  logging__success "Nix removed (best-effort)."
  return 0
}
