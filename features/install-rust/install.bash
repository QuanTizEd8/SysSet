# shellcheck shell=bash

# ── Helper functions ──────────────────────────────────────────────────────────

# _rust_real_triple — Rust target triple corrected for the ACTUAL host libc.
#
# `plat.rust_triple` (os__rust_triple) is deliberately musl-biased on Linux
# (portable static builds, correct for tools like uv/jq that publish universal
# musl binaries). That bias is wrong here: rustup's own default-toolchain
# selection must match the host's real libc, or a glibc host would silently
# get a musl-linked toolchain with a mismatched ABI. Reuses os__rust_triple's
# arch/bitness/NEON/Rosetta-2 detection and only corrects the libc suffix.
_rust_real_triple() {
  local _t
  _t="$(os__rust_triple)" || return 1
  if [[ "$(os__kernel)" == "Linux" ]] && [[ "$(os__libc 2> /dev/null)" == "gnu" ]]; then
    _t="${_t/musl/gnu}"
  fi
  printf '%s\n' "$_t"
}

# ── Template hook implementations ─────────────────────────────────────────────

# Prefer rustup-init over the framework's default auto-priority (which would
# otherwise pick METHOD=package first): rustup-init.sh's own platform/libc
# detection is more robust than re-deriving it, and OS-packaged rustup lags
# upstream (tool-ref.md's own compatibility notes).
# shellcheck disable=SC2329,SC2317
__resolve_method() {
  printf 'script'
}

# Rust's numbered releases are ordinary semver (rust-lang/rust GitHub Releases
# use clean X.Y.Z tags), so stable/latest/X/X.Y/X.Y.Z all resolve the standard
# way. beta/nightly/nightly-YYYY-MM-DD are rolling channels outside the
# numbered release history and must pass through unresolved — rustup and the
# standalone-installer URL both understand them directly.
# shellcheck disable=SC2329,SC2317
__resolve_version() {
  case "$VERSION" in
    beta | nightly | nightly-????-??-??)
      printf '%s' "$VERSION"
      return 0
      ;;
  esac
  github__resolve_version "$VERSION_URI" "$VERSION" --endpoint release --version
}

# Rust needs two sibling directories: CARGO_HOME (= _RESOLVED_PREFIX, holds
# bin/ with the rustc/cargo/rustup/rustdoc proxies — modeled by _options.prefix)
# and RUSTUP_HOME (holds installed toolchains, no bin/ of its own — not modeled
# by _options.prefix at all). Compute RUSTUP_HOME's default here, mirroring the
# exact same root/nonroot scope decision already made for _RESOLVED_PREFIX.
# shellcheck disable=SC2329,SC2317
__resolve_input_prefixes_post() {
  [[ -n "${RUSTUP_HOME:-}" ]] && return 0
  if users__is_user_path "${_RESOLVED_PREFIX}"; then
    RUSTUP_HOME="$(users__resolve_home "${INSTALL_USER:-$(users__get_current)}")/.rustup"
  else
    RUSTUP_HOME="/usr/local/rustup"
  fi
  logging__debug "Computed default RUSTUP_HOME='${RUSTUP_HOME}'."
}

# -- METHOD=script (rustup-init) --

# shellcheck disable=SC2329,SC2317
__install_run_script_pre() {
  [[ "$(os__kernel)" == "Darwin" ]] && bootstrap__xcode
  return 0
}

# shellcheck disable=SC2329,SC2317
__install_run_script_run() {
  local _installer="$1"
  file__mkdir "${_RESOLVED_PREFIX}"
  file__mkdir "${RUSTUP_HOME}"
  local -a _args=(-y --no-modify-path --default-toolchain "${VERSION}" --profile "${PROFILE}")
  local _c
  for _c in "${COMPONENTS[@]}"; do [[ -n "${_c}" ]] && _args+=(-c "${_c}"); done
  for _c in "${TARGETS[@]}"; do [[ -n "${_c}" ]] && _args+=(-t "${_c}"); done
  logging__launch "Running rustup-init (toolchain='${VERSION}', profile='${PROFILE}', prefix='${_RESOLVED_PREFIX}')."
  CARGO_HOME="${_RESOLVED_PREFIX}" RUSTUP_HOME="${RUSTUP_HOME}" "${_installer}" "${_args[@]}"
  local _rc=$?
  [[ ${_rc} == 0 ]] || {
    logging__error "rustup-init exited with status ${_rc}."
    return "${_rc}"
  }
  logging__success "Rust toolchain installed at '${_RESOLVED_PREFIX}'."
}

# -- METHOD=source (standalone offline installer: tarball + bundled install.sh) --

# shellcheck disable=SC2329,SC2317
__install_run_source_pre() {
  # {feat.rust_real_triple} is consumed by SOURCE_ASSET_URI/SOURCE_SIDECAR_URI
  # in metadata.yaml — must be registered before ctx__expand_pattern runs.
  ctx__set "feat.rust_real_triple=$(_rust_real_triple)"
  if users__is_user_path "${_RESOLVED_PREFIX}"; then
    logging__warn "METHOD=source (standalone installer) is documented upstream as system-wide only; a non-root/user-scoped prefix may not work correctly. Prefer METHOD=script (rustup) for user-local installs."
  fi
  return 0
}

# shellcheck disable=SC2329,SC2317
__install_run_source_build() {
  local _src_dir="$1"
  local -a _args=("--prefix=${_RESOLVED_PREFIX}")
  [[ "$(os__kernel)" == "Linux" ]] && _args+=(--disable-ldconfig)
  logging__install "Running standalone Rust installer from '${_src_dir}' (prefix='${_RESOLVED_PREFIX}')."
  "${_src_dir}/install.sh" "${_args[@]}"
}

# -- METHOD=package (OS package manager: only bootstraps 'rustup' itself) --

# The OS package only bootstraps a manager — it still has to provision an
# actual toolchain — but WHICH manager binary the package provides differs by
# distro (confirmed empirically in real containers, not assumed):
#   - Alpine (apk) and Fedora/RHEL-family (dnf) only package the `rustup-init`
#     bootstrap binary (tool-ref.md's own "rustup-init provided" note) — no
#     plain `rustup` command exists yet. Bootstrap it exactly like METHOD=script,
#     creating proxies at our chosen prefix.
#   - Debian/Ubuntu (apt), Arch (pacman), openSUSE (zypper) package `rustup`
#     itself as the system binary (rustc/cargo already on PATH via it). Running
#     `rustup toolchain install` against it manages toolchains under
#     $RUSTUP_HOME directly — it does NOT create a rustup-init-style proxy
#     layer under a custom CARGO_HOME even when CARGO_HOME is redirected
#     (confirmed empirically: the prefix's bin/ stayed empty). Accept the OS
#     package's own binary locations instead of forcing them into our prefix.
#     The Debian/Ubuntu build additionally prints a benign "rustup is not
#     installed at '<CARGO_HOME>'" self-check message and a non-zero exit even
#     on a fully successful install (confirmed empirically) — verify the
#     actual outcome instead of trusting that exit code.
#   - macOS/Linuxbrew (brew) package a KEG-ONLY, MULTIPLEXER-ONLY `rustup`
#     (built `--features no-self-update`: no `rustup-init`/self-install path,
#     and not on PATH). Handled by a dedicated branch: install the toolchain
#     with the keg multiplexer, then mirror its proxy set onto our prefix (see
#     `_rust_link_brew_proxies`).
# shellcheck disable=SC2329,SC2317
__install_run_package_post() {
  # Always ensure the prefix directory exists, even for the "rustup already
  # present" branch below where it's otherwise unused: __install_finish__'s
  # own write_group step unconditionally chowns _RESOLVED_PREFIX afterward,
  # regardless of which package-method branch actually populated it
  # (confirmed empirically: Arch's rustup manages toolchains under its own
  # default location, never touching /usr/local/cargo, so the chown step
  # failed with "No such file or directory" until this ran unconditionally).
  file__mkdir "${_RESOLVED_PREFIX}"

  local -a _components=() _targets=()
  local _c
  for _c in "${COMPONENTS[@]}"; do [[ -n "${_c}" ]] && _components+=("${_c}"); done
  for _c in "${TARGETS[@]}"; do [[ -n "${_c}" ]] && _targets+=("${_c}"); done

  local _rustup_init
  _rustup_init="$(command -v rustup-init 2> /dev/null || true)"
  if [[ -n "${_rustup_init}" ]]; then
    file__mkdir "${RUSTUP_HOME}"
    local -a _args=(-y --no-modify-path --default-toolchain "${VERSION}" --profile "${PROFILE}")
    for _c in "${_components[@]}"; do _args+=(-c "${_c}"); done
    for _c in "${_targets[@]}"; do _args+=(-t "${_c}"); done
    logging__install "Bootstrapping rustup via 'rustup-init' (toolchain='${VERSION}', profile='${PROFILE}', prefix='${_RESOLVED_PREFIX}')."
    CARGO_HOME="${_RESOLVED_PREFIX}" RUSTUP_HOME="${RUSTUP_HOME}" "${_rustup_init}" "${_args[@]}"
    local _rc=$?
    [[ ${_rc} == 0 ]] || {
      logging__error "'rustup-init' failed (rc=${_rc})."
      return "${_rc}"
    }
    return 0
  fi

  # -- Homebrew keg-only rustup (macOS & Linuxbrew) --
  # Homebrew's `rustup` is a keg-only, MULTIPLEXER-ONLY build (see
  # `_rust_link_brew_proxies`): there is no `rustup-init`/self-install path, so
  # the branch above never fires, and — being keg-only — `$(brew --prefix
  # rustup)/bin` is off PATH. Provision the toolchain into `${RUSTUP_HOME}` with
  # the keg multiplexer, then mirror the keg's proxy set onto
  # `${_RESOLVED_PREFIX}/bin` so the feature's persisted prefix-PATH discovery +
  # CARGO_HOME/RUSTUP_HOME exports expose it in the runtime/verify shell (a
  # process-local PATH tweak would not persist). Resolve the keg via `brew
  # --prefix rustup` — correct on both Apple Silicon (`/opt/homebrew`) and Intel
  # (`/usr/local`), no hardcoded path. Gated on brew being the detected PM
  # (always so on macOS; also covers Linuxbrew); a strict no-op for the native
  # Linux OS package managers (handled below) and the METHOD=script path.
  if [[ "$(ospkg__pm_key 2> /dev/null)" == "brew" ]]; then
    local _brew_prefix _keg_bin
    _brew_prefix="$(brew --prefix rustup 2> /dev/null || true)"
    _keg_bin="${_brew_prefix}/bin"
    [[ -n "${_brew_prefix}" && -x "${_keg_bin}/rustup" ]] || {
      logging__error "METHOD=package: Homebrew keg 'rustup' not found via 'brew --prefix rustup' (looked in '${_keg_bin}')."
      return 1
    }
    file__mkdir "${RUSTUP_HOME}"
    local -a _args=(--profile "${PROFILE}")
    for _c in "${_components[@]}"; do _args+=(--component "${_c}"); done
    for _c in "${_targets[@]}"; do _args+=(--target "${_c}"); done
    logging__install "Provisioning Rust toolchain '${VERSION}' via keg-only 'rustup toolchain install' (prefix='${_RESOLVED_PREFIX}', RUSTUP_HOME='${RUSTUP_HOME}')."
    CARGO_HOME="${_RESOLVED_PREFIX}" RUSTUP_HOME="${RUSTUP_HOME}" "${_keg_bin}/rustup" toolchain install "${VERSION}" "${_args[@]}" || true
    CARGO_HOME="${_RESOLVED_PREFIX}" RUSTUP_HOME="${RUSTUP_HOME}" "${_keg_bin}/rustup" default "${VERSION}" || true
    _rust_link_brew_proxies "${_keg_bin}"
    if [[ ! -x "${_RESOLVED_PREFIX}/bin/rustc" ]] || ! CARGO_HOME="${_RESOLVED_PREFIX}" RUSTUP_HOME="${RUSTUP_HOME}" "${_RESOLVED_PREFIX}/bin/rustc" --version > /dev/null 2>&1; then
      logging__error "'rustc' not usable at '${_RESOLVED_PREFIX}/bin/rustc' after keg toolchain provisioning."
      return 1
    fi
    return 0
  fi

  local _rustup
  _rustup="$(command -v rustup 2> /dev/null || true)"
  [[ -n "${_rustup}" ]] || {
    logging__error "METHOD=package: neither 'rustup' nor 'rustup-init' found on PATH after package install."
    return 1
  }
  local -a _args=(--profile "${PROFILE}")
  for _c in "${_components[@]}"; do _args+=(--component "${_c}"); done
  for _c in "${_targets[@]}"; do _args+=(--target "${_c}"); done
  logging__install "Provisioning Rust toolchain '${VERSION}' via 'rustup toolchain install'."
  "${_rustup}" toolchain install "${VERSION}" "${_args[@]}" || true
  "${_rustup}" default "${VERSION}" || true
  if ! command -v rustc > /dev/null 2>&1 || ! rustc --version > /dev/null 2>&1; then
    logging__error "'rustc' still not usable after 'rustup toolchain install'."
    return 1
  fi
}

# _rust_link_brew_proxies <keg-bin-dir> — mirror Homebrew's keg-only rustup
# proxy set onto the resolved prefix bin/.
#
# Homebrew's `rustup` is a MULTIPLEXER-ONLY build: it is compiled with
# `--features no-self-update`, which strips the installer/setup ("rustup-init")
# code path ("This formula no longer provides `rustup-init`"; confirmed on a
# real macOS runner — even invoked as `rustup-init` the keg binary runs as the
# multiplexer and rejects `-y`). So there is no self-install to populate
# `${CARGO_HOME}/bin`, and — being keg-only — `$(brew --prefix rustup)/bin` is
# never on PATH. That keg bin/ ships the `rustup` multiplexer plus its proxy set
# (rustc, cargo, cargo-clippy, cargo-fmt, cargo-miri, clippy-driver, rls,
# rust-analyzer, rustdoc, rustfmt, rust-gdb, rust-gdbgui, rust-lldb — all
# dispatching through rustup). Symlink every entry into `${_RESOLVED_PREFIX}/bin`
# (= CARGO_HOME/bin — the exact dir the framework's prefix-PATH discovery
# persists and the script/rustup-init method populates natively), enumerated at
# runtime so the formula's set is mirrored without hardcoding it. Once the
# toolchain is installed under `${RUSTUP_HOME}` and CARGO_HOME/RUSTUP_HOME are
# exported (`_rust_sync_env`), these proxies resolve it in the persisted verify
# shell — the same exposure METHOD=script gets.
# shellcheck disable=SC2329,SC2317
_rust_link_brew_proxies() {
  local _keg_bin="$1"
  file__mkdir "${_RESOLVED_PREFIX}/bin"
  local _src _name
  for _src in "${_keg_bin}"/*; do
    [[ -e "${_src}" ]] || continue
    _name="${_src##*/}"
    ln -sf "${_src}" "${_RESOLVED_PREFIX}/bin/${_name}"
  done
}

# -- Idempotency / completions (method-aware; rustup is absent for METHOD=source) --

# rustc --version works identically across all three methods (rustup always
# proxies it, and the standalone installer places it directly), so this needs
# no method branching. Also matches the generic if_exists test harness, which
# seeds a fake stub at the primary bin (rustc) reporting "rustc-9.9.9 (fake)" —
# the same ver__extract_version call the framework's own default __installed_version
# auto-impl uses, so both the fake stub and real rustc output parse correctly.
# shellcheck disable=SC2329,SC2317
__installed_version() {
  local _rustc="${_RESOLVED_PREFIX}/bin/rustc"
  [[ -x "${_rustc}" ]] || {
    printf ''
    return 0
  }
  ver__extract_version --keep-suffix "$("${_rustc}" --version 2>&1)"
}

# shellcheck disable=SC2329,SC2317
__get_completion_content__() {
  local _shell="$1"
  local _rustup="${_RESOLVED_PREFIX}/bin/rustup"
  [[ -x "${_rustup}" ]] || {
    logging__warn "rustup not present at '${_rustup}' (METHOD=${METHOD:-unset}); shell completions require rustup and are unavailable for standalone (source-method) installs."
    return 1
  }
  CARGO_HOME="${_RESOLVED_PREFIX}" RUSTUP_HOME="${RUSTUP_HOME}" "${_rustup}" completions "${_shell}"
}

# -- Post-install / uninstall --

# CARGO_HOME/RUSTUP_HOME persistence
# ===================================
# The rustc/cargo/rustup proxy binaries only resolve the right toolchain when
# CARGO_HOME/RUSTUP_HOME are set — without them they silently fall back to
# their compiled-in default of ~/.cargo / ~/.rustup. _options.prefix's own
# discovery/symlink/export machinery only covers PATH, not these custom env
# vars, so they need the same explicit persistence GOROOT gets in install-go
# (confirmed necessary by an actual container run: rustc/cargo/rustup were on
# PATH and the install genuinely succeeded, but a fresh shell running `rustc
# --version` afterward failed with "no default is configured" — it was
# reading ~/.rustup, which the system-wide install never touched). Only
# meaningful for script/package methods (source installs to a flat prefix
# with no rustup multiplexing at all).
# shellcheck disable=SC2329,SC2317
_rust_sync_env() {
  local _content="${1-}"
  local _has_content=false
  [[ $# -ge 1 ]] && _has_content=true
  [[ -x "${_RESOLVED_PREFIX}/bin/rustup" ]] || return 0
  local _files
  if users__is_user_path "${_RESOLVED_PREFIX}"; then
    _files="$(shell__user_path_files --home "$(users__home_of_path_owner "${_RESOLVED_PREFIX}")")"
  else
    _files="$(shell__system_path_files --profile_d "install-rust-env.sh")"
  fi
  if [[ "${_has_content}" == true ]]; then
    shell__sync_block --files "${_files}" --marker "CARGO_HOME/RUSTUP_HOME (install-rust)" --content "${_content}"
  else
    shell__sync_block --files "${_files}" --marker "CARGO_HOME/RUSTUP_HOME (install-rust)"
  fi
}

# Symlink a user's ~/.cargo and ~/.rustup to the shared install so rustc/cargo/
# rustup resolve the right toolchain purely via rustup's own compiled-in
# default home-directory lookup — no env vars, login shell, or PAM session
# required. This is what makes a completely bare, non-interactive invocation
# work (confirmed empirically: a fresh `docker exec` with zero env vars and no
# session setup only succeeded once ~/.cargo/~/.rustup were symlinked to the
# resolved prefix/RUSTUP_HOME — CARGO_HOME/RUSTUP_HOME env vars, even when
# correctly exported by _rust_sync_env above, are only picked up by shells
# that actually go through a login/PAM session or source a startup file,
# which a plain `docker exec`/CI `RUN` layer never does).
# Never clobbers a user's pre-existing personal rustup install: skips (with a
# warning) any ~/.cargo or ~/.rustup that already exists as a real directory,
# or as a symlink to somewhere else.
# shellcheck disable=SC2329,SC2317
_rust_link_user_home() {
  local _user="$1"
  local _home
  _home="$(users__resolve_home "${_user}")" || return 0
  [[ -n "${_home}" ]] || return 0
  local _pair
  for _pair in "cargo:${_RESOLVED_PREFIX}" "rustup:${RUSTUP_HOME}"; do
    local _name="${_pair%%:*}" _target="${_pair#*:}"
    local _path="${_home}/.${_name}"
    [[ "${_path}" == "${_target}" ]] && continue
    if [[ -L "${_path}" ]]; then
      [[ "$(readlink "${_path}")" == "${_target}" ]] && continue
      logging__warn "'${_path}' is a symlink to a different location; leaving it as-is."
      continue
    fi
    if [[ -e "${_path}" ]]; then
      logging__warn "'${_path}' already exists and is not a symlink; leaving it as-is (not overwriting a pre-existing installation)."
      continue
    fi
    logging__install "Linking '${_path}' -> '${_target}' so rustup resolves the shared install without CARGO_HOME/RUSTUP_HOME set."
    ln -s "${_target}" "${_path}"
  done
}

# Removes only the symlinks _rust_link_user_home created (still pointing at
# our prefix/RUSTUP_HOME) — never touches a real directory or a symlink the
# user repointed elsewhere.
# shellcheck disable=SC2329,SC2317
_rust_unlink_user_home() {
  local _user="$1"
  local _home
  _home="$(users__resolve_home "${_user}")" || return 0
  [[ -n "${_home}" ]] || return 0
  local _pair
  for _pair in "cargo:${_RESOLVED_PREFIX}" "rustup:${RUSTUP_HOME}"; do
    local _name="${_pair%%:*}" _target="${_pair#*:}"
    local _path="${_home}/.${_name}"
    [[ -L "${_path}" ]] || continue
    [[ "$(readlink "${_path}")" == "${_target}" ]] || continue
    rm -f "${_path}"
  done
}

# shellcheck disable=SC2329,SC2317
__install_finish_post() {
  _rust_sync_env "$(printf 'export CARGO_HOME="%s"\nexport RUSTUP_HOME="%s"' "${_RESOLVED_PREFIX}" "${RUSTUP_HOME}")"

  [[ -n "${RUSTUP_HOME:-}" ]] || return 0
  file__mkdir "${RUSTUP_HOME}"

  local -a _wargs=()
  if [[ "${#WRITE_USERS[@]}" -gt 0 ]]; then
    _wargs=(--current false --remote false --container false)
    local _u
    for _u in "${WRITE_USERS[@]}"; do _wargs+=(--user "${_u}"); done
  fi
  local -a _write_users
  mapfile -t _write_users < <(users__resolve_list "${_wargs[@]}")

  if [[ -x "${_RESOLVED_PREFIX}/bin/rustup" ]]; then
    local _u
    for _u in "${_write_users[@]}"; do
      [[ -n "${_u}" ]] && _rust_link_user_home "${_u}"
    done
  fi

  [[ -n "${WRITE_GROUP:-}" ]] || return 0
  if users__is_privileged; then
    logging__install "Configuring write group '${WRITE_GROUP}' on RUSTUP_HOME '${RUSTUP_HOME}'."
    users__set_write_permissions "${RUSTUP_HOME}" "${INSTALL_USER:-$(id -nu)}" "${WRITE_GROUP}" "${_write_users[@]}"
  else
    logging__warn "write_group='${WRITE_GROUP}' requested but no privilege available; skipping RUSTUP_HOME group configuration."
  fi
}

# shellcheck disable=SC2329,SC2317
__uninstall_finish_post() {
  _rust_sync_env
}

# shellcheck disable=SC2329,SC2317
__uninstall_run__() {
  local _rustup_bin="${_RESOLVED_PREFIX}/bin/rustup"
  # Unlink the ~/.cargo·~/.rustup symlinks _rust_link_user_home created — runs
  # whenever a rustup proxy layer exists at the prefix, whether a real
  # self-installed binary (METHOD=script / package rustup-init) or the Homebrew
  # keg symlinks we mirror there.
  if [[ -x "${_rustup_bin}" ]]; then
    local -a _wargs=()
    if [[ "${#WRITE_USERS[@]}" -gt 0 ]]; then
      _wargs=(--current false --remote false --container false)
      local _u
      for _u in "${WRITE_USERS[@]}"; do _wargs+=(--user "${_u}"); done
    fi
    local -a _write_users
    mapfile -t _write_users < <(users__resolve_list "${_wargs[@]}")
    for _u in "${_write_users[@]}"; do
      [[ -n "${_u}" ]] && _rust_unlink_user_home "${_u}"
    done
  fi
  if [[ -x "${_rustup_bin}" && ! -L "${_rustup_bin}" ]]; then
    # A real, self-installed rustup owns its CARGO_HOME/RUSTUP_HOME layout — let
    # it tear itself down. (Excludes the Homebrew keg case below: there
    # `${_rustup_bin}` is a symlink into the brew-managed, multiplexer-only keg,
    # whose build has no `self uninstall`; invoking it could also try to delete
    # the keg binary itself. We only drop our own symlink layer instead.)
    logging__remove "Uninstalling Rust via 'rustup self uninstall'."
    CARGO_HOME="${_RESOLVED_PREFIX}" RUSTUP_HOME="${RUSTUP_HOME}" "${_rustup_bin}" self uninstall -y
  elif [[ -x "${_RESOLVED_PREFIX}/lib/rustlib/uninstall.sh" ]]; then
    logging__remove "Uninstalling standalone Rust installation via its bundled uninstall.sh."
    "${_RESOLVED_PREFIX}/lib/rustlib/uninstall.sh"
  else
    logging__remove "Removing Rust installation directory '${_RESOLVED_PREFIX}'."
    rm -rf "${_RESOLVED_PREFIX}"
  fi
  # Use an if-block, not `[[ ... ]] && rm`: as the last statement in the
  # function, a `&&` chain whose test is false would return exit 1 and abort
  # the (re)install via the ERR trap. RUSTUP_HOME legitimately may not exist —
  # e.g. reinstalling over a partial or non-rustup install.
  if [[ -n "${RUSTUP_HOME:-}" && -d "${RUSTUP_HOME}" ]]; then
    rm -rf "${RUSTUP_HOME}"
  fi
}
