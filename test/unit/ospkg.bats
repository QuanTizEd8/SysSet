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
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest_XXXXXX.json")"
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
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest_XXXXXX.json")"
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
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest_XXXXXX.json")"
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
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest_XXXXXX.json")"
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
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest_XXXXXX.json")"
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
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest_XXXXXX.json")"
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
