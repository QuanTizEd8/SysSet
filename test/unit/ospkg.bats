#!/usr/bin/env bats
# Unit tests for lib/ospkg.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
}

# ---------------------------------------------------------------------------
# ospkg__detect  (direct calls — checks internal state variables)
# ---------------------------------------------------------------------------

@test "ospkg__detect identifies apt-get ecosystem" {
  reload_lib ospkg.sh
  create_fake_bin "apt-get"
  create_fake_bin "uname" "Linux"
  prepend_fake_bin_path
  ospkg__detect
  [[ "$_OSPKG_PREFIX" == "apt" ]]
  [[ "$_OSPKG_PKG_MNGR" == "apt-get" ]]
  [[ "$_OSPKG_DETECTED" == true ]]
}

@test "ospkg__detect identifies apk ecosystem" {
  reload_lib ospkg.sh
  create_fake_bin "apk"
  create_fake_bin "uname" "Linux"
  PATH="${BATS_TEST_TMPDIR}/bin" ospkg__detect
  [[ "$_OSPKG_PREFIX" == "apk" ]]
  [[ "$_OSPKG_PKG_MNGR" == "apk" ]]
  [[ "$_OSPKG_DETECTED" == true ]]
}

@test "ospkg__detect identifies dnf ecosystem" {
  reload_lib ospkg.sh
  create_fake_bin "dnf"
  create_fake_bin "uname" "Linux"
  PATH="${BATS_TEST_TMPDIR}/bin" ospkg__detect
  [[ "$_OSPKG_PREFIX" == "dnf" ]]
  [[ "$_OSPKG_PKG_MNGR" == "dnf" ]]
  [[ "$_OSPKG_DETECTED" == true ]]
}

@test "ospkg__detect is idempotent when _OSPKG_DETECTED=true" {
  reload_lib ospkg.sh
  _OSPKG_DETECTED=true
  _OSPKG_PREFIX="sentinel"
  ospkg__detect
  [[ "$_OSPKG_PREFIX" == "sentinel" ]]
}

@test "ospkg__detect fails when no package manager is found" {
  reload_lib ospkg.sh
  # Override PATH to empty so no package manager binary is found.
  PATH="${BATS_TEST_TMPDIR}/bin" run ospkg__detect
  assert_failure
  assert_output --partial "No supported package manager"
}

@test "ospkg__detect identifies zypper ecosystem" {
  reload_lib ospkg.sh
  create_fake_bin "zypper"
  create_fake_bin "uname" "Linux"
  PATH="${BATS_TEST_TMPDIR}/bin" ospkg__detect
  [[ "$_OSPKG_PREFIX" == "zypper" ]]
  [[ "$_OSPKG_PKG_MNGR" == "zypper" ]]
  [[ "$_OSPKG_DETECTED" == true ]]
}

@test "ospkg__detect identifies microdnf ecosystem" {
  reload_lib ospkg.sh
  create_fake_bin "microdnf"
  create_fake_bin "uname" "Linux"
  PATH="${BATS_TEST_TMPDIR}/bin" ospkg__detect
  [[ "$_OSPKG_PREFIX" == "dnf" ]]
  [[ "$_OSPKG_PKG_MNGR" == "microdnf" ]]
  [[ "${#_OSPKG_UPDATE[@]}" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_seed_apt_context() {
  reload_lib ospkg.sh
  create_fake_bin "apt-get"
  create_fake_bin "uname" "Linux"
  prepend_fake_bin_path
  ospkg__detect
  _OSPKG_OS_RELEASE[pm]="apt"
  _OSPKG_OS_RELEASE[arch]="x86_64"
  _OSPKG_OS_RELEASE[id]="ubuntu"
  _OSPKG_OS_RELEASE[id_like]="debian"
  _OSPKG_OS_RELEASE[version_id]="22.04"
  _OSPKG_OS_RELEASE[version_codename]="jammy"
}

# ---------------------------------------------------------------------------
# ospkg__update
# ---------------------------------------------------------------------------

@test "ospkg__update rejects unknown option" {
  _seed_apt_context
  run ospkg__update --bogus
  assert_failure
  assert_output --partial "unknown option"
}

@test "ospkg__update skips when update command array is empty" {
  reload_lib ospkg.sh
  # Seed a microdnf-like context: detected, but no update command.
  create_fake_bin "microdnf"
  create_fake_bin "uname" "Linux"
  PATH="${BATS_TEST_TMPDIR}/bin" ospkg__detect
  run ospkg__update
  assert_success
  assert_output --partial "not supported"
}

@test "ospkg__update runs update command with --force" {
  _seed_apt_context
  # The fake apt-get stub exits 0 for any subcommand.
  run ospkg__update --force
  assert_success
}

# ---------------------------------------------------------------------------
# ospkg__install
# ---------------------------------------------------------------------------

@test "ospkg__install invokes the install command" {
  _seed_apt_context
  run ospkg__install curl
  assert_success
}

@test "ospkg__install skips when apt packages are already installed" {
  _seed_apt_context
  # Fake dpkg that reports the package as installed (exit 0).
  create_fake_bin "dpkg" ""
  prepend_fake_bin_path
  run ospkg__install curl
  assert_success
  assert_output --partial "already installed"
}

# ---------------------------------------------------------------------------
# ospkg__clean
# ---------------------------------------------------------------------------

@test "ospkg__clean succeeds for apt context" {
  _seed_apt_context
  # The fake apt-get stub handles 'clean' and 'dist-clean'.
  run ospkg__clean
  assert_success
}

# ---------------------------------------------------------------------------
# ospkg__detect — brew paths
# ---------------------------------------------------------------------------

@test "ospkg__detect identifies brew on macOS (Darwin)" {
  reload_lib ospkg.sh
  # Fake 'uname' returning Darwin and a fake 'brew' binary.
  create_fake_bin "uname" "Darwin"
  create_fake_bin "brew" ""
  prepend_fake_bin_path
  # 'sw_vers' must exist (macOS only command path).
  create_fake_bin "sw_vers" "14.0"
  ospkg__detect
  [[ "$_OSPKG_PREFIX" == "brew" ]]
  [[ "$_OSPKG_PKG_MNGR" == "brew" ]]
  [[ "${_OSPKG_OS_RELEASE[id]}" == "macos" ]]
}

@test "ospkg__detect selects brew when _OSPKG_PREFER_LINUXBREW=true and brew is on PATH" {
  reload_lib ospkg.sh
  create_fake_bin "uname" "Linux"
  create_fake_bin "apt-get" ""
  create_fake_bin "brew" ""
  prepend_fake_bin_path
  _OSPKG_PREFER_LINUXBREW=true
  ospkg__detect
  [[ "$_OSPKG_PREFIX" == "brew" ]]
  [[ "$_OSPKG_PKG_MNGR" == "brew" ]]
}

@test "ospkg__detect falls back to native PM when _OSPKG_PREFER_LINUXBREW=true but brew absent" {
  reload_lib ospkg.sh
  create_fake_bin "uname" "Linux"
  create_fake_bin "apt-get" ""
  # Use restricted PATH so real brew is not found.
  _OSPKG_PREFER_LINUXBREW=true
  PATH="${BATS_TEST_TMPDIR}/bin" ospkg__detect
  [[ "$_OSPKG_PREFIX" == "apt" ]]
  [[ "$_OSPKG_PKG_MNGR" == "apt-get" ]]
}

# ---------------------------------------------------------------------------
# ospkg__parse_manifest_yaml  (requires jq)
# ---------------------------------------------------------------------------

@test "ospkg__parse_manifest_yaml emits package records from plain packages list" {
  _seed_apt_context
  command -v jq > /dev/null 2>&1 || skip "jq not available"
  local _json_file
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest.XXXXXX")"
  printf '{"packages":["curl","wget","git"]}' > "$_json_file"
  local _output
  _output="$(ospkg__parse_manifest_yaml "$_json_file")"
  rm -f "$_json_file"
  [[ "$_output" == *'"kind":"package"'* ]]
  [[ "$_output" == *'"name":"curl"'* ]]
  [[ "$_output" == *'"name":"wget"'* ]]
}

@test "ospkg__parse_manifest_yaml emits prescript record" {
  _seed_apt_context
  command -v jq > /dev/null 2>&1 || skip "jq not available"
  local _json_file
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest.XXXXXX")"
  printf '{"prescripts":"echo hello\\n","packages":["curl"]}' > "$_json_file"
  local _output
  _output="$(ospkg__parse_manifest_yaml "$_json_file")"
  rm -f "$_json_file"
  [[ "$_output" == *'"kind":"prescript"'* ]]
}

@test "ospkg__parse_manifest_yaml filters packages with when clause" {
  _seed_apt_context
  command -v jq > /dev/null 2>&1 || skip "jq not available"
  local _json_file
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest.XXXXXX")"
  # brew-only package should NOT appear for apt context.
  printf '{"packages":[{"name":"brew-pkg","when":{"pm":"brew"}},{"name":"apt-pkg","when":{"pm":"apt"}}]}' \
    > "$_json_file"
  local _output
  _output="$(ospkg__parse_manifest_yaml "$_json_file")"
  rm -f "$_json_file"
  [[ "$_output" != *'"name":"brew-pkg"'* ]]
  [[ "$_output" == *'"name":"apt-pkg"'* ]]
}

@test "ospkg__parse_manifest_yaml skips the manifest when top-level when mismatches" {
  _seed_apt_context
  command -v jq > /dev/null 2>&1 || skip "jq not available"
  local _json_file
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest.XXXXXX")"
  printf '{"when":{"pm":"brew"},"packages":["should-not-appear"]}' > "$_json_file"
  local _output
  _output="$(ospkg__parse_manifest_yaml "$_json_file")"
  rm -f "$_json_file"
  [[ -z "$_output" ]]
}

@test "ospkg__parse_manifest_yaml emits packages from pm-specific apt block" {
  _seed_apt_context
  command -v jq > /dev/null 2>&1 || skip "jq not available"
  local _json_file
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest.XXXXXX")"
  printf '{"apt":{"packages":["libssl-dev"]},"brew":{"packages":["openssl"]}}' > "$_json_file"
  local _output
  _output="$(ospkg__parse_manifest_yaml "$_json_file")"
  rm -f "$_json_file"
  [[ "$_output" == *'"name":"libssl-dev"'* ]]
  [[ "$_output" != *'"name":"openssl"'* ]]
}

@test "ospkg__parse_manifest_yaml when clause supports version_codename" {
  _seed_apt_context
  command -v jq > /dev/null 2>&1 || skip "jq not available"
  local _json_file
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest.XXXXXX")"
  # jammy-only package should appear; bookworm-only should not.
  printf '{"packages":[{"name":"jammy-pkg","when":{"version_codename":"jammy"}},{"name":"bookworm-pkg","when":{"version_codename":"bookworm"}}]}' \
    > "$_json_file"
  local _output
  _output="$(ospkg__parse_manifest_yaml "$_json_file")"
  rm -f "$_json_file"
  # _seed_apt_context sets version_codename=jammy
  [[ "$_output" == *'"name":"jammy-pkg"'* ]]
  [[ "$_output" != *'"name":"bookworm-pkg"'* ]]
}

# ---------------------------------------------------------------------------
# ospkg__run — regression: stale yq binary path and silent parse failure
#
# Root cause: ospkg__run previously deleted the yq tmpdir inline at the end of
# every call (rm -rf $_OSPKG_YQ_TMPDIR; _OSPKG_YQ_TMPDIR=; _OSPKG_YQ_BIN=).
# A second call that reused _OSPKG_YQ_BIN via the early-return guard in
# _ospkg_ensure_yq would try to execute a non-existent binary.  The failure
# was silent because the yq+parse block was wrapped in `if ! {}`, which
# disables set -e.
# ---------------------------------------------------------------------------

# _seed_apt_context_with_yq — sets up apt context and creates a fake yq binary.
# Exports a mock _ospkg_ensure_yq that mirrors the real early-return guard.
_seed_apt_context_with_yq() {
  _seed_apt_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/bash\necho '"'"'{"packages":["regrpkg"]}'"'"'\n' \
    > "${BATS_TEST_TMPDIR}/bin/yq"
  chmod +x "${BATS_TEST_TMPDIR}/bin/yq"
  # Mock mirrors _ospkg_ensure_yq's real early-return guard so the second call
  # exercises the early-return code path with the already-set _OSPKG_YQ_BIN.
  # Note: _OSPKG_YQ_BIN is assigned to a stable path (not inside _SYSSET_TMPDIR)
  # to avoid command-substitution subshell scoping issues with _SYSSET_TMPDIR.
  _ospkg_ensure_yq() {
    [[ -n "${_OSPKG_YQ_BIN:-}" ]] && return 0
    _OSPKG_YQ_BIN="${BATS_TEST_TMPDIR}/bin/yq"
    return 0
  }
  export -f _ospkg_ensure_yq
}

@test "ospkg__run regression: yq binary not deleted after call returns" {
  # Old code: rm -rf "$_OSPKG_YQ_TMPDIR"; _OSPKG_YQ_BIN= inside ospkg__run.
  # Fix: yq dir lives in _SYSSET_TMPDIR for the process lifetime; ospkg__run
  # never deletes it.
  command -v jq > /dev/null 2>&1 || skip "jq not available"
  _seed_apt_context_with_yq

  ospkg__run --manifest $'packages:\n  - regrpkg\n' --dry_run > /dev/null 2>&1

  # After the call, _OSPKG_YQ_BIN must still be set and the file must exist.
  [[ -n "${_OSPKG_YQ_BIN:-}" ]] ||
    {
      echo "_OSPKG_YQ_BIN was cleared after ospkg__run"
      return 1
    }
  [[ -f "$_OSPKG_YQ_BIN" ]] ||
    {
      echo "_OSPKG_YQ_BIN no longer points to a file: ${_OSPKG_YQ_BIN}"
      return 1
    }
}

@test "ospkg__run regression: second call succeeds via _OSPKG_YQ_BIN early-return path" {
  # Old code: after first call _OSPKG_YQ_BIN was cleared (or set to a deleted
  # path) so a second call silently processed no packages.
  # Fix: _OSPKG_YQ_BIN persists; _ospkg_ensure_yq early-returns and the binary
  # at that path is still valid.
  command -v jq > /dev/null 2>&1 || skip "jq not available"
  _seed_apt_context_with_yq

  local _log="${BATS_TEST_TMPDIR}/run.log"

  # First call — sets _OSPKG_YQ_BIN via mock.
  ospkg__run --manifest $'packages:\n  - regrpkg\n' --dry_run > "$_log" 2>&1
  grep -q "\[dry-run\] packages: regrpkg" "$_log" ||
    {
      echo "First call: expected dry-run output absent"
      cat "$_log" >&2
      return 1
    }

  # Second call — _ospkg_ensure_yq early-returns; the binary at _OSPKG_YQ_BIN
  # must still be accessible.  Old code would have deleted it above.
  : > "$_log"
  ospkg__run --manifest $'packages:\n  - regrpkg\n' --dry_run > "$_log" 2>&1
  grep -q "\[dry-run\] packages: regrpkg" "$_log" ||
    {
      echo "Second call (regression): dry-run output absent — yq path was stale or deleted"
      cat "$_log" >&2
      return 1
    }
}

@test "ospkg__run regression: YAML conversion failure propagates under set -e" {
  # Old code: yq+parse block wrapped in `if ! {}`, which disables set -e so a
  # failing yq was swallowed — ospkg__run returned 0 with nothing installed.
  # Fix: block is plain sequential code; a failing yq exits the function under
  # set -e.
  command -v jq > /dev/null 2>&1 || skip "jq not available"
  local _ospkg_lib="${BATS_TEST_DIRNAME}/../../lib/ospkg.sh"

  run bash -c "
    set -euo pipefail
    source '${_ospkg_lib}'

    # Seed a minimal apt context without calling the real package manager.
    _OSPKG_DETECTED=true
    _OSPKG_PKG_MNGR='apt-get'
    _OSPKG_PREFIX='apt'
    _OSPKG_OS_RELEASE[pm]='apt'
    _OSPKG_OS_RELEASE[arch]='x86_64'
    _OSPKG_OS_RELEASE[id]='ubuntu'
    _OSPKG_OS_RELEASE[id_like]='debian'
    _OSPKG_OS_RELEASE[version_id]='22.04'
    _OSPKG_OS_RELEASE[version_codename]='jammy'

    # A yq stub that always exits non-zero (simulates corrupt binary / bad manifest).
    _OSPKG_YQ_BIN='${BATS_TEST_TMPDIR}/bin/yq'
    mkdir -p '${BATS_TEST_TMPDIR}/bin'
    printf '#!/bin/bash\nexit 1\n' > \"\$_OSPKG_YQ_BIN\"
    chmod +x \"\$_OSPKG_YQ_BIN\"
    _ospkg_ensure_yq() { return 0; }

    ospkg__run --manifest \$'packages:\n  - curl\n' --dry_run
  "
  assert_failure
}

# ---------------------------------------------------------------------------
# Build-dep tracking: ospkg__install_tracked / _ospkg_remove_build_group /
#                     ospkg__cleanup_all_build_groups
# ---------------------------------------------------------------------------

# _seed_apt_build_context — seeds apt context + stubs needed for build-dep tests:
#   · _SYSSET_TMPDIR  → BATS_TEST_TMPDIR (sidecars at a predictable path)
#   · fake apt-get    (exit 0, no-op — real install skipped)
#   · fake dpkg       (exit 1 — "not installed" so ospkg__install always proceeds)
#   · fake apt-mark   (logs every invocation to ${BATS_TEST_TMPDIR}/apt-mark.log)
#   · net__fetch_with_retry → passthrough so the fake apt-get is actually invoked
# After this, call _mock_snapshots to control the before/after package lists.
_seed_apt_build_context() {
  _seed_apt_context
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/bash\nexit 0\n' \
    > "${BATS_TEST_TMPDIR}/bin/apt-get"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-get"
  printf '#!/bin/bash\nexit 1\n' \
    > "${BATS_TEST_TMPDIR}/bin/dpkg"
  chmod +x "${BATS_TEST_TMPDIR}/bin/dpkg"
  printf '#!/bin/bash\necho "$@" >> "%s/apt-mark.log"\n' \
    "${BATS_TEST_TMPDIR}" > "${BATS_TEST_TMPDIR}/bin/apt-mark"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-mark"
  prepend_fake_bin_path
  # Passthrough: avoids the real retry loop and simply invokes the fake apt-get.
  net__fetch_with_retry() { "$@" > /dev/null 2>&1 || true; }
}

# _mock_snapshots <before_pkgs_space_sep> <after_pkgs_space_sep>
# Replaces _ospkg_snapshot_packages with a counter-based mock.  The first call
# returns <before_pkgs> (one-per-line, sorted); all subsequent calls return
# <after_pkgs>.  Uses a temp file for the counter to avoid bash closure issues.
_mock_snapshots() {
  export SNAP_BEFORE="$1"
  export SNAP_AFTER="$2"
  echo 0 > "${BATS_TEST_TMPDIR}/.snap_call"
  _ospkg_snapshot_packages() {
    local _dest="$1" _n
    _n=$(cat "${BATS_TEST_TMPDIR}/.snap_call")
    _n=$((_n + 1))
    echo "$_n" > "${BATS_TEST_TMPDIR}/.snap_call"
    if [[ $_n -le 1 ]]; then
      echo "${SNAP_BEFORE}" | tr ' ' '\n' | grep -v '^$' | sort > "$_dest"
    else
      echo "${SNAP_AFTER}" | tr ' ' '\n' | grep -v '^$' | sort > "$_dest"
    fi
  }
}

# ── ospkg__install_tracked ────────────────────────────────────────────────────

@test "ospkg__install_tracked: newly installed package is recorded in sidecar" {
  _seed_apt_build_context
  _mock_snapshots "curl" "curl newpkg"

  ospkg__install_tracked "test-group" newpkg

  local _sidecar="${BATS_TEST_TMPDIR}/ospkg/build-deps/test-group"
  assert_file_exists "$_sidecar"
  grep -q "^newpkg$" "$_sidecar"
}

@test "ospkg__install_tracked: newly installed package is marked apt auto" {
  _seed_apt_build_context
  _mock_snapshots "curl" "curl newpkg"

  ospkg__install_tracked "test-group" newpkg

  assert_file_exists "${BATS_TEST_TMPDIR}/apt-mark.log"
  grep -q "auto newpkg" "${BATS_TEST_TMPDIR}/apt-mark.log"
}

@test "ospkg__install_tracked: pre-installed package produces empty sentinel sidecar" {
  # Package is already present in the before-snapshot → diff is empty → sidecar
  # created as empty sentinel (no content, no apt-mark call).
  _seed_apt_build_context
  _mock_snapshots "curl newpkg" "curl newpkg"

  ospkg__install_tracked "test-group" newpkg

  local _sidecar="${BATS_TEST_TMPDIR}/ospkg/build-deps/test-group"
  assert_file_exists "$_sidecar"
  [[ ! -s "$_sidecar" ]]
}

@test "ospkg__install_tracked: pre-installed package — apt-mark auto not called" {
  _seed_apt_build_context
  _mock_snapshots "curl newpkg" "curl newpkg"

  ospkg__install_tracked "test-group" newpkg

  [[ ! -f "${BATS_TEST_TMPDIR}/apt-mark.log" ]]
}

@test "ospkg__install_tracked: snapshot safety — pre-existing package never auto-marked" {
  # Core correctness guarantee: a package already present before this call (e.g.
  # a run.base package installed by the generated header) appears in the
  # before-snapshot and is therefore absent from _new_pkgs — its 'manual' mark
  # is never touched regardless of what apt-get install does.
  _seed_apt_build_context
  # git is pre-existing (in before); newpkg is genuinely new (only in after).
  _mock_snapshots "curl git" "curl git newpkg"

  ospkg__install_tracked "test-group" newpkg

  # newpkg must be tracked and auto-marked.
  assert_file_exists "${BATS_TEST_TMPDIR}/apt-mark.log"
  grep -q "auto newpkg" "${BATS_TEST_TMPDIR}/apt-mark.log"
  # git must never appear as an apt-mark target.
  run grep "git" "${BATS_TEST_TMPDIR}/apt-mark.log"
  assert_failure
}

@test "ospkg__install_tracked: two calls with same group-id accumulate packages in sidecar" {
  _seed_apt_build_context

  _mock_snapshots "curl" "curl pkg1"
  ospkg__install_tracked "test-group" pkg1

  _mock_snapshots "curl pkg1" "curl pkg1 pkg2"
  ospkg__install_tracked "test-group" pkg2

  local _sidecar="${BATS_TEST_TMPDIR}/ospkg/build-deps/test-group"
  grep -q "^pkg1$" "$_sidecar"
  grep -q "^pkg2$" "$_sidecar"
}

@test "ospkg__install_tracked: sort -u prevents duplicate entries across repeated calls" {
  _seed_apt_build_context

  _mock_snapshots "" "pkg1"
  ospkg__install_tracked "test-group" pkg1

  # Second call: pkg1 already in before (no-op install), should not duplicate.
  _mock_snapshots "pkg1" "pkg1"
  ospkg__install_tracked "test-group" pkg1

  local _sidecar="${BATS_TEST_TMPDIR}/ospkg/build-deps/test-group"
  [[ $(grep -c "^pkg1$" "$_sidecar") -eq 1 ]]
}

@test "ospkg__install_tracked: different group-ids create separate sidecars" {
  _seed_apt_build_context

  _mock_snapshots "" "pkg1"
  ospkg__install_tracked "group-a" pkg1

  _mock_snapshots "pkg1" "pkg1 pkg2"
  ospkg__install_tracked "group-b" pkg2

  local _bd="${BATS_TEST_TMPDIR}/ospkg/build-deps"
  assert_file_exists "${_bd}/group-a"
  assert_file_exists "${_bd}/group-b"
  grep -q "^pkg1$" "${_bd}/group-a"
  grep -q "^pkg2$" "${_bd}/group-b"
  # pkg2 must not bleed into group-a's sidecar.
  run grep "pkg2" "${_bd}/group-a"
  assert_failure
}

# ── _ospkg_remove_build_group ────────────────────────────────────────────────

@test "_ospkg_remove_build_group: missing sidecar returns 0 with informational message" {
  _seed_apt_context
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"

  run _ospkg_remove_build_group "nonexistent-group"

  assert_success
  assert_output --partial "nothing to remove"
}

@test "_ospkg_remove_build_group: empty sidecar returns 0 without invoking autoremove" {
  _seed_apt_context
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"
  mkdir -p "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  : > "${BATS_TEST_TMPDIR}/ospkg/build-deps/test-group"

  local _apt_log="${BATS_TEST_TMPDIR}/apt-get.log"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/bash\necho "$@" >> "%s"\n' "$_apt_log" \
    > "${BATS_TEST_TMPDIR}/bin/apt-get"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-get"
  prepend_fake_bin_path

  run _ospkg_remove_build_group "test-group"

  assert_success
  assert_output --partial "nothing to remove"
  [[ ! -f "$_apt_log" ]]
}

@test "_ospkg_remove_build_group: apt — calls autoremove and deletes the sidecar" {
  _seed_apt_context
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  printf 'curl\nnewpkg\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/test-group"

  local _apt_log="${BATS_TEST_TMPDIR}/apt-get.log"
  printf '#!/bin/bash\necho "$@" >> "%s"\n' "$_apt_log" \
    > "${BATS_TEST_TMPDIR}/bin/apt-get"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-get"
  prepend_fake_bin_path

  _ospkg_remove_build_group "test-group"

  grep -q "autoremove" "$_apt_log"
  [[ ! -f "${BATS_TEST_TMPDIR}/ospkg/build-deps/test-group" ]]
}

# ── ospkg__cleanup_all_build_groups ──────────────────────────────────────────

@test "ospkg__cleanup_all_build_groups: missing build-deps directory returns 0" {
  _seed_apt_context
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}/no_such_dir_xyz"

  run ospkg__cleanup_all_build_groups

  assert_success
}

@test "ospkg__cleanup_all_build_groups: .before and .after files are skipped" {
  # Temp snapshot files left by an aborted run must not be treated as group
  # sidecars — they must remain untouched after cleanup.
  _seed_apt_context
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"
  mkdir -p "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  : > "${BATS_TEST_TMPDIR}/ospkg/build-deps/group.before"
  : > "${BATS_TEST_TMPDIR}/ospkg/build-deps/group.after"

  run ospkg__cleanup_all_build_groups

  assert_success
  assert_file_exists "${BATS_TEST_TMPDIR}/ospkg/build-deps/group.before"
  assert_file_exists "${BATS_TEST_TMPDIR}/ospkg/build-deps/group.after"
}

@test "ospkg__cleanup_all_build_groups: one group sidecar triggers apt autoremove and is deleted" {
  _seed_apt_context
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  printf 'curl\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/my-group"

  local _apt_log="${BATS_TEST_TMPDIR}/apt-get.log"
  printf '#!/bin/bash\necho "$@" >> "%s"\n' "$_apt_log" \
    > "${BATS_TEST_TMPDIR}/bin/apt-get"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-get"
  prepend_fake_bin_path

  ospkg__cleanup_all_build_groups

  grep -q "autoremove" "$_apt_log"
  [[ ! -f "${BATS_TEST_TMPDIR}/ospkg/build-deps/my-group" ]]
}

@test "ospkg__cleanup_all_build_groups: multiple group sidecars are all removed" {
  _seed_apt_context
  export _SYSSET_TMPDIR="${BATS_TEST_TMPDIR}"
  mkdir -p "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  printf 'curl\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/group-a"
  printf 'git\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/group-b"
  printf 'tar\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/group-c"

  create_fake_bin "apt-get" ""
  prepend_fake_bin_path

  ospkg__cleanup_all_build_groups

  [[ ! -f "${BATS_TEST_TMPDIR}/ospkg/build-deps/group-a" ]]
  [[ ! -f "${BATS_TEST_TMPDIR}/ospkg/build-deps/group-b" ]]
  [[ ! -f "${BATS_TEST_TMPDIR}/ospkg/build-deps/group-c" ]]
}

# ---------------------------------------------------------------------------
@test "ospkg__run YAML path works on macOS (portable mktemp)" {
  [[ "$(uname -s)" == "Darwin" ]] || skip "macOS-only"
  command -v jq > /dev/null 2>&1 || skip "jq not available"
  reload_lib ospkg.sh

  # A fake yq that ignores its arguments and emits a fixed JSON manifest.
  local _fake_yq="${BATS_TEST_TMPDIR}/bin/yq"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/bash\necho '"'"'{"packages":["foo"]}'"'"'\n' > "$_fake_yq"
  chmod +x "$_fake_yq"

  logging__cleanup() { return 0; }
  ospkg__detect() {
    _OSPKG_PREFIX="brew"
    _OSPKG_PKG_MNGR="brew"
    _OSPKG_DETECTED=true
    _OSPKG_OS_RELEASE[pm]="brew"
    _OSPKG_OS_RELEASE[kernel]="darwin"
    _OSPKG_OS_RELEASE[id]="macos"
    _OSPKG_OS_RELEASE[id_like]="macos"
    _OSPKG_OS_RELEASE[arch]="arm64"
    return 0
  }
  _ospkg_ensure_yq() {
    _OSPKG_YQ_BIN="${BATS_TEST_TMPDIR}/bin/yq"
    return 0
  }

  run ospkg__run --manifest $'packages:\n  - foo\n' --dry_run
  assert_success
  assert_output --partial "[dry-run] packages: foo"
}
