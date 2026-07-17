#!/usr/bin/env bats
# Integration tests for lib/ospkg.bash — exercises real package-manager operations.
#
# Requires a real package manager and typically runs as root inside a container.
# Skipped when the canary package is already installed on the system.

bats_require_minimum_version 1.5.0

# Small, widely-available package unlikely to be pre-installed in minimal containers.
_OSPKG_INT_PKG=bc

# _pkg_force_remove <name> — unconditionally remove <name>; errors are ignored.
_pkg_force_remove() {
  case "$_OSPKG__PKG_MNGR" in
    apt-get) DEBIAN_FRONTEND=noninteractive apt-get -y --purge remove "$1" > /dev/null 2>&1 || true ;;
    apk) apk del "$1" > /dev/null 2>&1 || true ;;
    dnf) dnf -y remove "$1" > /dev/null 2>&1 || true ;;
    yum) yum -y remove "$1" > /dev/null 2>&1 || true ;;
    microdnf) microdnf remove "$1" > /dev/null 2>&1 || true ;;
    zypper) zypper --non-interactive remove "$1" > /dev/null 2>&1 || true ;;
    pacman) pacman -R --noconfirm "$1" > /dev/null 2>&1 || true ;;
  esac
}

setup() {
  load '../helpers/common'
  reload_lib
  # Isolate sidecar / snapshot files in the per-test tmpdir so tests do not share state.
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"
  # Skip when the canary is already installed — we cannot safely use it as a marker.
  # ospkg__is_installed auto-detects the package manager.
  if ospkg__is_installed "$_OSPKG_INT_PKG"; then
    skip "'${_OSPKG_INT_PKG}' is already installed on this system; cannot use it as a canary"
  fi
}

teardown() {
  if [[ -n "${_OSPKG__PKG_MNGR:-}" ]]; then
    ospkg__cleanup_all_build_groups 2> /dev/null || true
    # apk tracked installs live in named virtual groups (.df-*); `apk del <pkg>`
    # is blocked while its virtual still depends on it, so drop the virtuals
    # first to release members a test intentionally kept (e.g. keep=true).
    if [[ "$_OSPKG__PKG_MNGR" == apk ]]; then
      local _v
      for _v in $(apk info 2> /dev/null | grep -E '^\.df-' || true); do
        apk del "$_v" > /dev/null 2>&1 || true
      done
    fi
    local _p
    for _p in "$_OSPKG_INT_PKG" tree; do
      ospkg__is_installed "$_p" && _pkg_force_remove "$_p" || true
    done
  fi
}

# _int_concurrency_canary — echo a portable leaf package for the concurrency
# tests, or return 1 (test skips) for package managers without one. `tree` is in
# the default repos of every supported Linux PM; brew is user-scoped and covered
# by the unit tests, so it is skipped here.
_int_concurrency_canary() {
  case "$_OSPKG__PKG_MNGR" in
    apt-get | apk | dnf | yum | microdnf | zypper | pacman) printf 'tree' ;;
    *) return 1 ;;
  esac
}

# _int_bg_invocation <label> <context> <canary> <keep> <post_install_bash>
# Background a real lib invocation that shares the test registry ($_REG) but has
# its own, correctly-established session root, installs <canary> as a tracked
# build dep, signals "<_SYNC>/<label>_installed", then runs <post_install_bash>.
# NOTE: _FILE__SESSION_ROOT and KEEP_BUILD_DEPS are exported INSIDE the subshell
# after sourcing — lib/file.bash resets the former at source time (see the
# concurrency test below), and this keeps both robust.
_int_bg_invocation() {
  local _label="$1" _ctx="$2" _canary="$3" _keep="$4" _post="$5"
  mkdir -p "${BATS_TEST_TMPDIR}/${_label}"
  env _OSPKG__REGISTRY_ROOT="$_REG" _SESS_ROOT="${BATS_TEST_TMPDIR}/${_label}" \
    _KEEP_VAL="$_keep" _SYSSET_BUILD_CONTEXT="$_ctx" LIB_ROOT="$LIB_ROOT" \
    _CANARY="$_canary" _SYNC="$_SYNC" _LABEL="$_label" \
    bash -c '
      set +e
      # shellcheck source=/dev/null
      source "${LIB_ROOT}/__init__.bash"
      export _FILE__SESSION_ROOT="$_SESS_ROOT"
      export KEEP_BUILD_DEPS="$_KEEP_VAL"
      _ospkg__detect
      ospkg__install_tracked "grp" "$_CANARY" && : > "${_SYNC}/${_LABEL}_installed"
      '"$_post"'
    ' < /dev/null > /dev/null 2>&1 3>&- &
  _INT_BG_PID=$!
}

# ── PM detection ─────────────────────────────────────────────────────────────

@test "ospkg__pm_key identifies a known package manager key" {
  local _key
  _key="$(ospkg__pm_key)"
  [[ -n "${_key}" ]]
  case "${_key}" in
    apt | apk | dnf | yum | zypper | pacman | brew) ;;
    *) fail "unexpected package manager key: '${_key}'" ;;
  esac
}

# ── Install and sidecar tracking ─────────────────────────────────────────────

@test "ospkg__install_tracked installs package and writes a sidecar file" {
  run ospkg__install_tracked "ospkg-inttest" "$_OSPKG_INT_PKG"
  assert_success

  # Package must be present on the system.
  ospkg__is_installed "$_OSPKG_INT_PKG"

  # At least one non-dot sidecar file must exist in the build-deps directory.
  local _bd_dir="${BATS_TEST_TMPDIR}/ospkg/build-deps"
  local _found=false
  local _f
  for _f in "${_bd_dir}"/*; do
    [[ -f "$_f" ]] || continue
    [[ "$(basename "$_f")" == .* ]] && continue
    _found=true
    break
  done
  [[ "$_found" == true ]]
}

# ── Cleanup removes tracked packages ─────────────────────────────────────────

@test "ospkg__cleanup_all_build_groups removes the tracked package" {
  ospkg__install_tracked "ospkg-inttest" "$_OSPKG_INT_PKG"
  ospkg__is_installed "$_OSPKG_INT_PKG" # sanity: confirm installed before cleanup

  run ospkg__cleanup_all_build_groups
  assert_success

  run ospkg__is_installed "$_OSPKG_INT_PKG"
  assert_failure # package must be gone
}

# ── Snapshot protection ───────────────────────────────────────────────────────

@test "cleanup does not remove pre-existing packages (snapshot protection)" {
  # Homebrew on macOS can autonomously update/remove packages during the test,
  # making the snapshot assertion unreliable outside Linux containers.
  [[ "$(uname)" == Linux ]] || skip "Homebrew auto-updates make snapshot check unreliable on macOS"
  # Record every package installed before the test touches anything.
  local _snapshot="${BATS_TEST_TMPDIR}/pretest_pkgs.txt"
  _ospkg__snapshot_packages "$_snapshot"

  ospkg__install_tracked "ospkg-inttest" "$_OSPKG_INT_PKG"
  ospkg__cleanup_all_build_groups

  # Every package in the pre-test snapshot must still be installed.
  local _missing=0 _pkg
  while IFS= read -r _pkg; do
    [[ -z "$_pkg" ]] && continue
    if ! ospkg__is_installed "$_pkg"; then
      echo "MISSING after cleanup: ${_pkg}" >&3
      ((_missing++)) || true
    fi
  done < "$_snapshot"
  [[ "$_missing" -eq 0 ]]
}

# ── User-package protection ───────────────────────────────────────────────────

@test "package promoted via ospkg__install_user survives cleanup" {
  # Step 1: install and track as a build dep.
  ospkg__install_tracked "ospkg-inttest" "$_OSPKG_INT_PKG"

  # Step 2: promote to user-installed (marks manual / evicts from sidecar).
  run ospkg__install_user "$_OSPKG_INT_PKG"
  assert_success

  # Step 3: cleanup should now leave the package in place.
  run ospkg__cleanup_all_build_groups
  assert_success

  ospkg__is_installed "$_OSPKG_INT_PKG" # must survive
}

# ── Additional PM operations ──────────────────────────────────────────────────

@test "ospkg__update: refreshes package index without error" {
  run ospkg__update --force
  assert_success
}

@test "ospkg__resolve_version: returns PM version string for a known package" {
  # Use the running bash's own major version as the spec so the test is valid
  # on all distros (e.g. bash 4.x on openSUSE Leap, 5.x on Ubuntu/Fedora/…).
  local _major
  _major="${BASH_VERSINFO[0]}"
  run ospkg__resolve_version bash "$_major"
  assert_success
  [[ -n "$output" ]]
}

@test "ospkg__has_available_version: returns 0 for bash with matching major-version spec" {
  local _major
  _major="${BASH_VERSINFO[0]}"
  run ospkg__has_available_version bash "$_major"
  assert_success
}

@test "ospkg__register_dummy: registers a dummy package on apt systems" {
  [[ "$(ospkg__pm_key)" == "apt" ]] || skip "apt only"
  run ospkg__register_dummy devfeats-inttest-dummy 1.0.0
  assert_success
  # Package must appear as installed after registration.
  ospkg__is_installed devfeats-inttest-dummy
  # Unregister; non-fatal if removal is partial.
  ospkg__unregister_dummy devfeats-inttest-dummy 2> /dev/null || true
}

# ── Concurrency: live registry last-out semantics (real apt) ──────────────────
#
# Two concurrent invocations (separate bash processes) share a live registry
# pinned under BATS_TEST_TMPDIR. Invocation A installs and holds a tracked build
# dep, then idles; invocation B installs its own tracked build dep and exits,
# running cleanup while A is still alive. B must PARK (its machine-global purge is
# deferred), so A's in-use dep survives B's exit; both are removed only when A —
# the last-out invocation — finally cleans up.

# _int_wait_for <file> <max-100ms-ticks> — poll for <file> to appear.
_int_wait_for() {
  local _f="$1" _max="${2:-600}" _n=0
  while [[ ! -e "$_f" && $_n -lt $_max ]]; do
    sleep 0.1
    _n=$((_n + 1))
  done
  [[ -e "$_f" ]]
}

@test "concurrent invocations: a sibling's in-use build dep survives its exit and is removed only at last-out" {
  [[ "$_OSPKG__PKG_MNGR" == "apt-get" ]] || skip "apt-only concurrency test"
  local _canary_b=tree
  ospkg__is_installed "$_canary_b" && skip "'${_canary_b}' already installed; cannot use as canary"
  # setup() does not refresh apt lists; do it here so the availability pre-check
  # (and the two canary installs below) see the repo. Both canaries (bc, tree)
  # live in the distro's main component, so a missing one is a real failure to
  # surface loudly — not a reason to silently skip this crux concurrency proof.
  apt-get update > /dev/null 2>&1 || true
  apt-cache show "$_canary_b" > /dev/null 2>&1 || fail "'${_canary_b}' unexpectedly not available in apt after update"

  local _reg="${BATS_TEST_TMPDIR}/registry"
  local _sync="${BATS_TEST_TMPDIR}/sync"
  mkdir -p "$_sync" "${BATS_TEST_TMPDIR}/A" "${BATS_TEST_TMPDIR}/B"

  # NOTE on _FILE__SESSION_ROOT: it must be exported INSIDE each subshell AFTER
  # sourcing __init__.bash — lib/file.bash resets it to empty at source time, so
  # an env-injected value (unlike _OSPKG__REGISTRY_ROOT) would be clobbered. A
  # stable per-invocation session root is required or each _ospkg__build_deps_dir
  # call (a command substitution) would mktemp a fresh root, and the build-group
  # sidecar written by mark would not be found by the registry mirror. Production
  # install.bash fixes the root early in the main shell via logging__setup.

  # Invocation A: install + hold "$_OSPKG_INT_PKG" as a tracked build dep, idle
  # until told to finish, then clean up (should become last-out).
  env _OSPKG__REGISTRY_ROOT="$_reg" _SESS_ROOT="${BATS_TEST_TMPDIR}/A" \
    _SYSSET_BUILD_CONTEXT="feature::inttest-A" LIB_ROOT="$LIB_ROOT" \
    _CANARY="$_OSPKG_INT_PKG" _SYNC="$_sync" \
    bash -c '
      set +e
      # shellcheck source=/dev/null
      source "${LIB_ROOT}/__init__.bash"
      export _FILE__SESSION_ROOT="$_SESS_ROOT"
      _ospkg__detect
      ospkg__install_tracked "grp" "$_CANARY" && : > "${_SYNC}/A_installed"
      _n=0
      while [[ ! -e "${_SYNC}/A_go" && $_n -lt 900 ]]; do sleep 0.2; _n=$((_n + 1)); done
      ospkg__cleanup_all_build_groups false
      : > "${_SYNC}/A_done"
    ' < /dev/null > /dev/null 2>&1 3>&- &
  local _apid=$!

  # A must finish installing before B starts (avoids dpkg-lock contention).
  _int_wait_for "${_sync}/A_installed" 1200 || {
    kill "$_apid" 2> /dev/null || true
    fail "invocation A did not install '${_OSPKG_INT_PKG}' in time"
  }
  ospkg__is_installed "$_OSPKG_INT_PKG"

  # Invocation B: install its own tracked build dep, then exit + clean up while A
  # is still alive. Its machine-global purge must be parked.
  env _OSPKG__REGISTRY_ROOT="$_reg" _SESS_ROOT="${BATS_TEST_TMPDIR}/B" \
    _SYSSET_BUILD_CONTEXT="feature::inttest-B" LIB_ROOT="$LIB_ROOT" \
    _CANARY="$_canary_b" _SYNC="$_sync" \
    bash -c '
      set +e
      # shellcheck source=/dev/null
      source "${LIB_ROOT}/__init__.bash"
      export _FILE__SESSION_ROOT="$_SESS_ROOT"
      _ospkg__detect
      ospkg__install_tracked "grp" "$_CANARY"
      ospkg__cleanup_all_build_groups false
      : > "${_SYNC}/B_done"
    ' < /dev/null > /dev/null 2>&1 3>&- &
  local _bpid=$!

  _int_wait_for "${_sync}/B_done" 1200 || {
    kill "$_apid" "$_bpid" 2> /dev/null || true
    fail "invocation B did not finish in time"
  }
  wait "$_bpid" 2> /dev/null || true

  # B parked because A is still a live registrant: A's in-use dep must survive,
  # and B's own tracked dep is deferred (not reaped mid-flight either).
  ospkg__is_installed "$_OSPKG_INT_PKG"
  ospkg__is_installed "$_canary_b"

  # Release A; it is now the last registrant → last-out purge removes both deps.
  : > "${_sync}/A_go"
  _int_wait_for "${_sync}/A_done" 1200 || {
    kill "$_apid" 2> /dev/null || true
    fail "invocation A did not finish cleanup in time"
  }
  wait "$_apid" 2> /dev/null || true

  run ospkg__is_installed "$_OSPKG_INT_PKG"
  assert_failure
  run ospkg__is_installed "$_canary_b"
  assert_failure

  # Defensive: ensure the B canary is gone even if an assertion above failed.
  ospkg__is_installed "$_canary_b" && _pkg_force_remove "$_canary_b" || true
}

# The tests below are package-manager-portable (apt/apk/dnf/yum/zypper/pacman)
# and use a single shared canary co-owned by both invocations, so the same
# assertions hold regardless of the PM-specific removal command.

@test "concurrent co-ownership: a shared build dep survives while a co-owner is live, removed only at last-out (all PMs)" {
  local _canary
  _canary="$(_int_concurrency_canary)" || skip "no portable canary for '${_OSPKG__PKG_MNGR}'"
  ospkg__is_installed "$_canary" && skip "'${_canary}' already installed; cannot use as canary"

  local _REG="${BATS_TEST_TMPDIR}/registry"
  local _SYNC="${BATS_TEST_TMPDIR}/sync"
  mkdir -p "$_SYNC"

  # A installs the canary and holds it until released, then cleans up.
  _int_bg_invocation A "feature::int-A" "$_canary" false '
    _n=0; while [[ ! -e "${_SYNC}/A_go" && $_n -lt 900 ]]; do sleep 0.2; _n=$((_n + 1)); done
    ospkg__cleanup_all_build_groups "${KEEP_BUILD_DEPS:-false}"
    : > "${_SYNC}/A_done"'
  local _apid=$_INT_BG_PID
  _int_wait_for "${_SYNC}/A_installed" 1200 || {
    kill "$_apid" 2> /dev/null || true
    fail "invocation A did not install '${_canary}' in time"
  }
  ospkg__is_installed "$_canary"

  # B co-owns the same canary, then exits + cleans while A is still live.
  _int_bg_invocation B "feature::int-B" "$_canary" false '
    ospkg__cleanup_all_build_groups "${KEEP_BUILD_DEPS:-false}"
    : > "${_SYNC}/B_done"'
  local _bpid=$_INT_BG_PID
  _int_wait_for "${_SYNC}/B_done" 1200 || {
    kill "$_apid" "$_bpid" 2> /dev/null || true
    fail "invocation B did not finish in time"
  }
  wait "$_bpid" 2> /dev/null || true

  # B parked (A is a live registrant) → the co-owned canary survives.
  ospkg__is_installed "$_canary"

  # Release A → last registrant → last-out purge removes the canary.
  : > "${_SYNC}/A_go"
  _int_wait_for "${_SYNC}/A_done" 1200 || {
    kill "$_apid" 2> /dev/null || true
    fail "invocation A did not finish cleanup in time"
  }
  wait "$_apid" 2> /dev/null || true

  run ospkg__is_installed "$_canary"
  assert_failure
  ospkg__is_installed "$_canary" && _pkg_force_remove "$_canary" || true
}

@test "concurrent keep: a keep_build_deps=true invocation's build dep survives the last-out purge (all PMs)" {
  # Cross-owner keep-wins (true overrides false on the SAME package) is covered by
  # the mocked unit tests; a real second installer of an already-present package
  # produces an empty group, so here A solely owns the canary with keep=true and B
  # is the concurrent keep=false sibling that parks. This proves keep=true is
  # honored end-to-end through the registry last-out path under a real PM.
  local _canary
  _canary="$(_int_concurrency_canary)" || skip "no portable canary for '${_OSPKG__PKG_MNGR}'"
  ospkg__is_installed "$_canary" && skip "'${_canary}' already installed; cannot use as canary"

  local _REG="${BATS_TEST_TMPDIR}/registry"
  local _SYNC="${BATS_TEST_TMPDIR}/sync"
  mkdir -p "$_SYNC"

  # A holds the canary with keep_build_deps=true.
  _int_bg_invocation A "feature::int-A" "$_canary" true '
    _n=0; while [[ ! -e "${_SYNC}/A_go" && $_n -lt 900 ]]; do sleep 0.2; _n=$((_n + 1)); done
    ospkg__cleanup_all_build_groups "${KEEP_BUILD_DEPS:-false}"
    : > "${_SYNC}/A_done"'
  local _apid=$_INT_BG_PID
  _int_wait_for "${_SYNC}/A_installed" 1200 || {
    kill "$_apid" 2> /dev/null || true
    fail "invocation A did not install '${_canary}' in time"
  }

  # B co-owns the same canary with keep_build_deps=false, then exits + cleans.
  _int_bg_invocation B "feature::int-B" "$_canary" false '
    ospkg__cleanup_all_build_groups "${KEEP_BUILD_DEPS:-false}"
    : > "${_SYNC}/B_done"'
  local _bpid=$_INT_BG_PID
  _int_wait_for "${_SYNC}/B_done" 1200 || {
    kill "$_apid" "$_bpid" 2> /dev/null || true
    fail "invocation B did not finish in time"
  }
  wait "$_bpid" 2> /dev/null || true

  # Release A (the last-out invocation). Keep-wins: the canary is co-owned by a
  # keep=true group, so last-out must NOT remove it.
  : > "${_SYNC}/A_go"
  _int_wait_for "${_SYNC}/A_done" 1200 || {
    kill "$_apid" 2> /dev/null || true
    fail "invocation A did not finish cleanup in time"
  }
  wait "$_apid" 2> /dev/null || true

  ospkg__is_installed "$_canary" || fail "'${_canary}' was removed despite keep_build_deps=true"
  _pkg_force_remove "$_canary"
}

@test "concurrent stale-registrant: a killed invocation is pruned so the survivor's last-out purges (all PMs)" {
  local _canary
  _canary="$(_int_concurrency_canary)" || skip "no portable canary for '${_OSPKG__PKG_MNGR}'"
  ospkg__is_installed "$_canary" && skip "'${_canary}' already installed; cannot use as canary"

  local _REG="${BATS_TEST_TMPDIR}/registry"
  local _SYNC="${BATS_TEST_TMPDIR}/sync"
  mkdir -p "$_SYNC"

  # A installs the canary and then idles forever — it will be killed hard,
  # simulating a crashed invocation that never deregisters.
  _int_bg_invocation A "feature::int-A" "$_canary" false '
    while true; do sleep 1; done'
  local _apid=$_INT_BG_PID
  _int_wait_for "${_SYNC}/A_installed" 1200 || {
    kill "$_apid" 2> /dev/null || true
    fail "invocation A did not install '${_canary}' in time"
  }
  ospkg__is_installed "$_canary"

  # Kill A without a chance to deregister → it leaves a stale registrant behind.
  kill -9 "$_apid" 2> /dev/null || true
  wait "$_apid" 2> /dev/null || true

  # B installs the same canary and cleans up: it must prune A's dead registrant
  # (liveness check), become last-out, and purge the canary.
  _int_bg_invocation B "feature::int-B" "$_canary" false '
    ospkg__cleanup_all_build_groups "${KEEP_BUILD_DEPS:-false}"
    : > "${_SYNC}/B_done"'
  local _bpid=$_INT_BG_PID
  _int_wait_for "${_SYNC}/B_done" 1200 || {
    kill "$_bpid" 2> /dev/null || true
    fail "invocation B did not finish in time"
  }
  wait "$_bpid" 2> /dev/null || true

  run ospkg__is_installed "$_canary"
  assert_failure
  ospkg__is_installed "$_canary" && _pkg_force_remove "$_canary" || true
}

# Mutex regression: a dead lock owner must be taken over by exactly one of several
# concurrent waiters. Uses real subprocesses (distinct PIDs — a bash subshell
# keeps the parent's $$) that guard a short critical section with an atomic
# noclobber flag; a second simultaneous holder fails the create and records an
# overlap. PM-agnostic (pure filesystem), so it runs on every environment.
@test "concurrent mutex: a dead owner is taken over by exactly one of several waiters" {
  local _root="${BATS_TEST_TMPDIR}/reg"
  local _held="${BATS_TEST_TMPDIR}/held"
  local _overlap="${BATS_TEST_TMPDIR}/overlap"
  local _done="${BATS_TEST_TMPDIR}/done"

  _spawn_mutex_racer() {
    env _OSPKG__REGISTRY_ROOT="$_root" LIB_ROOT="$LIB_ROOT" \
      _HELD="$_held" _OVERLAP="$_overlap" _DONE="$_done" \
      bash -c '
        set +e
        # shellcheck source=/dev/null
        source "${LIB_ROOT}/__init__.bash"
        _ospkg__mutex_acquire "$_OSPKG__REGISTRY_ROOT"
        if ( set -o noclobber; : > "$_HELD" ) 2> /dev/null; then
          sleep 0.15
          rm -f "$_HELD"
        else
          : > "$_OVERLAP"
        fi
        _ospkg__mutex_release "$_OSPKG__REGISTRY_ROOT"
        printf x >> "$_DONE"
      ' < /dev/null > /dev/null 2>&1 3>&- &
  }

  local _iter
  for _iter in $(seq 1 12); do
    rm -f "$_held" "$_overlap" "$_done"
    mkdir -p "${_root}/mutex"
    # Seed the mutex as owned by a now-dead process (token guards PID reuse). Use a
    # fixed, unreachable PID instead of spawning a throwaway to reap: a persistent
    # fork EAGAIN makes bash abort non-locally (fork failure -> throw_to_top_level),
    # which cannot be caught or retried in shell, so a real `sleep 30 &` here flakes
    # under CI process pressure — the failure this fixes. A PID above any
    # /proc/sys/kernel/pid_max is guaranteed dead, so _ospkg__registrant_alive
    # returns via the fast kill -0 (ESRCH) path with no start-time lookup, keeping
    # the takeover window as narrow as a real reaped PID would.
    printf '%s.deadtoken\n' 999999999 > "${_root}/mutex/owner"

    # Several waiters race to take over the dead lock at once.
    _spawn_mutex_racer
    _spawn_mutex_racer
    _spawn_mutex_racer
    wait

    [[ ! -f "$_overlap" ]] || fail "iteration ${_iter}: two processes held the mutex simultaneously"
    [[ "$(wc -c < "$_done" 2> /dev/null || echo 0)" -eq 3 ]] || fail "iteration ${_iter}: not all racers completed"
  done
}
