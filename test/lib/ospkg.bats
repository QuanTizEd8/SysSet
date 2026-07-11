#!/usr/bin/env bats
# Unit tests for lib/ospkg.bash

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  load 'helpers/ctx'
}

setup_file() {
  load 'helpers/common'
  OSPKG_JQ_READY=0
  if bash -c '. "$1/__init__.bash" && bootstrap__jq' _ "${LIB_ROOT}" > /dev/null 2>&1; then
    OSPKG_JQ_READY=1
  fi
  export OSPKG_JQ_READY
}

_require_ospkg_jq() {
  [[ "${OSPKG_JQ_READY:-0}" == "1" ]] || skip "jq bootstrap unavailable for ospkg manifest tests"
}

# ---------------------------------------------------------------------------
# _ospkg__detect  (direct calls — checks internal state variables)
# ---------------------------------------------------------------------------

@test "_ospkg__detect identifies apt-get ecosystem" {
  reload_lib
  create_fake_bin "apt-get"
  create_fake_bin "uname" "Linux"
  prepend_fake_bin_path
  _ospkg__detect
  [[ "$_OSPKG__FAMILY" == "apt" ]]
  [[ "$_OSPKG__PKG_MNGR" == "apt-get" ]]
  [[ "$_OSPKG__DETECTED" == true ]]
}

@test "_ospkg__detect identifies apk ecosystem" {
  reload_lib
  create_fake_bin "apk"
  create_fake_bin "uname" "Linux"
  PATH="${BATS_TEST_TMPDIR}/bin" _ospkg__detect
  [[ "$_OSPKG__FAMILY" == "apk" ]]
  [[ "$_OSPKG__PKG_MNGR" == "apk" ]]
  [[ "$_OSPKG__DETECTED" == true ]]
}

@test "_ospkg__detect identifies dnf ecosystem" {
  reload_lib
  create_fake_bin "dnf"
  create_fake_bin "uname" "Linux"
  PATH="${BATS_TEST_TMPDIR}/bin" _ospkg__detect
  [[ "$_OSPKG__FAMILY" == "dnf" ]]
  [[ "$_OSPKG__PKG_MNGR" == "dnf" ]]
  [[ "$_OSPKG__DETECTED" == true ]]
}

@test "_ospkg__detect is idempotent when _OSPKG__DETECTED=true" {
  reload_lib
  _OSPKG__DETECTED=true
  _OSPKG__FAMILY="sentinel"
  _ospkg__detect
  [[ "$_OSPKG__FAMILY" == "sentinel" ]]
}

@test "_ospkg__detect fails when no package manager is found" {
  reload_lib
  begin_path_isolation mkdir chmod
  rm -f "${BATS_TEST_TMPDIR}/bin/uname"
  create_fake_bin "uname" "Linux"
  run _ospkg__detect
  end_path_isolation
  assert_failure
  assert_output --partial "No supported package manager"
}

@test "_ospkg__detect identifies zypper ecosystem" {
  reload_lib
  create_fake_bin "zypper"
  create_fake_bin "uname" "Linux"
  PATH="${BATS_TEST_TMPDIR}/bin" _ospkg__detect
  [[ "$_OSPKG__FAMILY" == "zypper" ]]
  [[ "$_OSPKG__PKG_MNGR" == "zypper" ]]
  [[ "$_OSPKG__DETECTED" == true ]]
}

@test "_ospkg__detect identifies microdnf ecosystem" {
  reload_lib
  create_fake_bin "microdnf"
  create_fake_bin "uname" "Linux"
  PATH="${BATS_TEST_TMPDIR}/bin" _ospkg__detect
  [[ "$_OSPKG__FAMILY" == "dnf" ]]
  [[ "$_OSPKG__PKG_MNGR" == "microdnf" ]]
  [[ "${#_OSPKG__UPDATE[@]}" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# ospkg__pm_key / ospkg__deb_arch
# ---------------------------------------------------------------------------

@test "ospkg__pm_key prints manifest key not tool name for apt" {
  reload_lib
  create_fake_bin "apt-get"
  create_fake_bin "uname" "Linux"
  prepend_fake_bin_path
  run ospkg__pm_key
  assert_success
  assert_output "apt"
}

@test "ospkg__pm_key maps microdnf to dnf key" {
  reload_lib
  create_fake_bin "microdnf"
  create_fake_bin "uname" "Linux"
  PATH="${BATS_TEST_TMPDIR}/bin" _ospkg__detect
  prepend_fake_bin_path
  run ospkg__pm_key
  assert_success
  assert_output "dnf"
}

@test "ospkg__deb_arch is empty on non-apt PM" {
  reload_lib
  create_fake_bin "apk"
  create_fake_bin "uname" "Linux"
  PATH="${BATS_TEST_TMPDIR}/bin" _ospkg__detect
  prepend_fake_bin_path
  local _arch
  _arch="$(ospkg__deb_arch)"
  [[ -z "${_arch}" ]]
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_seed_apt_context() {
  reload_lib
  create_fake_bin "apt-get"
  # Argument-aware fake: -s (kernel name) → Linux, -m (machine arch) → x86_64.
  # create_fake_bin ignores arguments; write the script directly instead.
  printf '#!/bin/sh\ncase "${1-}" in -m) printf "x86_64\\n";; *) printf "Linux\\n";; esac\n' \
    > "${BATS_TEST_TMPDIR}/bin/uname"
  chmod +x "${BATS_TEST_TMPDIR}/bin/uname"
  prepend_fake_bin_path
  _ospkg__detect
  ctx_test__seed_plat pm=apt deb_arch=amd64
  ctx_test__seed_os id=ubuntu id_like=debian version_id=22.04 version_codename=jammy
  # Bypass sudo: sudo resets PATH to its secure_path, ignoring user PATH entirely.
  # Without this stub, users__run_privileged would find the real apt-get via sudo
  # instead of the fake one above, allowing destructive operations on the host.
  users__run_privileged() { "$@"; }
  export -f users__run_privileged
}

# Stub privilege gate for tests that exercise install/update paths with fake PMs.
_stub_ospkg_privilege_ok() {
  _ospkg__assert_privilege() { return 0; }
  export -f _ospkg__assert_privilege
}

@test "_ospkg__install_repo_content preserves physical line breaks across sequential apt entries" {
  reload_lib
  _OSPKG__FAMILY="apt"
  local _repo_file="${BATS_TEST_TMPDIR}/syspkg-installer.list"

  file__append_privileged() {
    [[ "$1" == "/etc/apt/sources.list.d/syspkg-installer.list" ]] || return 1
    cat >> "${_repo_file}"
  }

  _ospkg__install_repo_content $'deb https://example.invalid/git-lfs stable main\n'
  _ospkg__install_repo_content $'deb-src https://example.invalid/git-lfs stable main\n'

  mapfile -t _repo_lines < "${_repo_file}"
  [[ "${#_repo_lines[@]}" -eq 2 ]]
  [[ "${_repo_lines[0]}" == "deb https://example.invalid/git-lfs stable main" ]]
  [[ "${_repo_lines[1]}" == "deb-src https://example.invalid/git-lfs stable main" ]]
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
  reload_lib
  # Seed a microdnf-like context: detected, but no update command.
  create_fake_bin "microdnf"
  create_fake_bin "uname" "Linux"
  PATH="${BATS_TEST_TMPDIR}/bin" _ospkg__detect
  run ospkg__update
  assert_success
  assert_output --partial "skipping explicit update"
}

@test "_ospkg__lists_index_present: true when apt Packages index exists at depth 2" {
  reload_lib
  local _lists="${BATS_TEST_TMPDIR}/apt-lists"
  mkdir -p "${_lists}/partial"
  touch "${_lists}/archive.ubuntu.com_ubuntu_dists_jammy_main_binary-amd64_Packages"
  _OSPKG__LISTS_PATH="$_lists"
  _OSPKG__LISTS_PATTERN='*_Packages*'
  run _ospkg__lists_index_present
  assert_success
}

@test "_ospkg__lists_index_present: false when lists directory is empty" {
  reload_lib
  local _lists="${BATS_TEST_TMPDIR}/empty-lists"
  mkdir -p "$_lists"
  _OSPKG__LISTS_PATH="$_lists"
  _OSPKG__LISTS_PATTERN='*_Packages*'
  run _ospkg__lists_index_present
  assert_failure
}

@test "ospkg__update runs update command with --force" {
  _seed_apt_context
  _stub_ospkg_privilege_ok
  # The fake apt-get stub exits 0 for any subcommand.
  run ospkg__update --force
  assert_success
}

@test "_ospkg__detect configures non-interactive dnf check-update" {
  reload_lib
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  create_fake_bin "uname" "Linux"
  printf '#!/bin/bash\nexit 0\n' > "${BATS_TEST_TMPDIR}/bin/dnf"
  chmod +x "${BATS_TEST_TMPDIR}/bin/dnf"
  PATH="${BATS_TEST_TMPDIR}/bin" _ospkg__detect
  [[ "${_OSPKG__FAMILY}" == "dnf" ]]
  [[ "${_OSPKG__UPDATE[*]}" == "users__run_privileged dnf -y check-update" ]]
}

@test "_ospkg__detect configures non-interactive yum check-update" {
  reload_lib
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  create_fake_bin "uname" "Linux"
  printf '#!/bin/bash\nexit 0\n' > "${BATS_TEST_TMPDIR}/bin/yum"
  chmod +x "${BATS_TEST_TMPDIR}/bin/yum"
  PATH="${BATS_TEST_TMPDIR}/bin" _ospkg__detect
  [[ "${_OSPKG__FAMILY}" == "dnf" ]]
  [[ "${_OSPKG__PKG_MNGR}" == "yum" ]]
  [[ "${_OSPKG__UPDATE[*]}" == "users__run_privileged yum -y check-update" ]]
}

# ---------------------------------------------------------------------------
# _ospkg__assert_privilege
# ---------------------------------------------------------------------------

@test "_ospkg__assert_privilege: returns 0 for brew (no privilege required)" {
  reload_lib
  _OSPKG__DETECTED=true
  _OSPKG__PKG_MNGR="brew"
  run _ospkg__assert_privilege
  assert_success
}

@test "_ospkg__assert_privilege: returns 0 when running as root" {
  _seed_apt_context
  users__is_root() { return 0; }
  export -f users__is_root
  run _ospkg__assert_privilege
  assert_success
}

@test "_ospkg__assert_privilege: returns 0 when sudo is available and passwordless (non-root)" {
  _seed_apt_context
  users__is_root() { return 1; }
  export -f users__is_root
  create_fake_bin "sudo" ""
  prepend_fake_bin_path
  run _ospkg__assert_privilege
  assert_success
}

@test "_ospkg__assert_privilege: returns 1 with error when sudo requires a password" {
  _seed_apt_context
  users__is_root() { return 1; }
  export -f users__is_root
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  # sudo exists in PATH but 'sudo -n true' fails (simulates a password-protected sudo).
  printf '#!/bin/bash\n[[ "$1" == "-n" ]] && exit 1 || exit 0\n' \
    > "${BATS_TEST_TMPDIR}/bin/sudo"
  chmod +x "${BATS_TEST_TMPDIR}/bin/sudo"
  prepend_fake_bin_path
  run _ospkg__assert_privilege
  assert_failure
  assert_output --partial "passwordless sudo"
}

@test "_ospkg__assert_privilege: returns 1 with error when non-root and no sudo" {
  _seed_apt_context
  users__is_root() { return 1; }
  export -f users__is_root
  begin_path_isolation
  run _ospkg__assert_privilege
  end_path_isolation
  assert_failure
  assert_output --partial "passwordless sudo"
}

@test "ospkg__update: fails immediately when non-root and sudo absent (no retry)" {
  _seed_apt_context
  users__is_root() { return 1; }
  export -f users__is_root
  begin_path_isolation
  run ospkg__update --force
  end_path_isolation
  assert_failure
  assert_output --partial "passwordless sudo"
  refute_output --partial "retrying"
}

# ---------------------------------------------------------------------------
# ospkg__install
# ---------------------------------------------------------------------------

@test "ospkg__install invokes the install command" {
  _seed_apt_context
  _stub_ospkg_privilege_ok
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

@test "ospkg__install: fails immediately when non-root and sudo absent (no retry)" {
  _seed_apt_context
  users__is_root() { return 1; }
  export -f users__is_root
  # Fake dpkg exits 1: package appears not installed, so install is attempted.
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/sh\nexit 1\n' > "${BATS_TEST_TMPDIR}/bin/dpkg"
  chmod +x "${BATS_TEST_TMPDIR}/bin/dpkg"
  begin_path_isolation
  run ospkg__install curl
  end_path_isolation
  assert_failure
  assert_output --partial "passwordless sudo"
  refute_output --partial "retrying"
}

@test "ospkg__install: installs only missing packages when some are already installed" {
  _seed_apt_context
  users__is_root() { return 0; }
  export -f users__is_root
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  # dpkg: returns 0 (installed) for curl, 1 (not installed) for wget.
  printf '#!/bin/bash\n[[  "$2" == "curl" ]] && exit 0 || exit 1\n' \
    > "${BATS_TEST_TMPDIR}/bin/dpkg"
  chmod +x "${BATS_TEST_TMPDIR}/bin/dpkg"
  # Logging apt-get: records its arguments so we can inspect them.
  local _log="${BATS_TEST_TMPDIR}/apt-get.log"
  printf '#!/bin/bash\necho "$@" >> "%s"\n' "$_log" \
    > "${BATS_TEST_TMPDIR}/bin/apt-get"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-get"
  prepend_fake_bin_path
  run ospkg__install curl wget
  assert_success
  grep -q "wget" "$_log"
  ! grep -q "curl" "$_log"
}

@test "ospkg__install --update: passes all packages including already-installed ones" {
  _seed_apt_context
  users__is_root() { return 0; }
  export -f users__is_root
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  # dpkg: returns 0 (installed) for curl, 1 (not installed) for wget.
  printf '#!/bin/bash\n[[ "$2" == "curl" ]] && exit 0 || exit 1\n' \
    > "${BATS_TEST_TMPDIR}/bin/dpkg"
  chmod +x "${BATS_TEST_TMPDIR}/bin/dpkg"
  # Logging apt-get: records its arguments so we can inspect them.
  local _log="${BATS_TEST_TMPDIR}/apt-get.log"
  printf '#!/bin/bash\necho "$@" >> "%s"\n' "$_log" \
    > "${BATS_TEST_TMPDIR}/bin/apt-get"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-get"
  prepend_fake_bin_path
  run ospkg__install --update curl wget
  assert_success
  grep -q "curl" "$_log"
  grep -q "wget" "$_log"
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
# _ospkg__detect — brew paths
# ---------------------------------------------------------------------------

@test "_ospkg__detect identifies brew on macOS (Darwin)" {
  reload_lib
  # Fake 'uname' returning Darwin and a fake 'brew' binary.
  create_fake_bin "uname" "Darwin"
  create_fake_bin "brew" ""
  prepend_fake_bin_path
  # 'sw_vers' must exist (macOS only command path).
  create_fake_bin "sw_vers" "14.0"
  _ospkg__detect
  [[ "$_OSPKG__FAMILY" == "brew" ]]
  [[ "$_OSPKG__PKG_MNGR" == "brew" ]]
  [[ "$_OSPKG__PM_KEY" == "brew" ]]
}

@test "_ospkg__detect selects brew when _OSPKG__PREFER_LINUXBREW=true and brew is on PATH" {
  reload_lib
  create_fake_bin "uname" "Linux"
  create_fake_bin "apt-get" ""
  create_fake_bin "brew" ""
  prepend_fake_bin_path
  _OSPKG__PREFER_LINUXBREW=true
  _ospkg__detect
  [[ "$_OSPKG__FAMILY" == "brew" ]]
  [[ "$_OSPKG__PKG_MNGR" == "brew" ]]
}

@test "_ospkg__detect falls back to native PM when _OSPKG__PREFER_LINUXBREW=true but brew absent" {
  reload_lib
  create_fake_bin "uname" "Linux"
  create_fake_bin "apt-get" ""
  # Use restricted PATH so real brew is not found.
  _OSPKG__PREFER_LINUXBREW=true
  PATH="${BATS_TEST_TMPDIR}/bin" _ospkg__detect
  [[ "$_OSPKG__FAMILY" == "apt" ]]
  [[ "$_OSPKG__PKG_MNGR" == "apt-get" ]]
}

# ---------------------------------------------------------------------------
# ospkg__parse_manifest_yaml  (requires jq)
# ---------------------------------------------------------------------------

@test "ospkg__parse_manifest_yaml emits package records from plain packages list" {
  _seed_apt_context
  _require_ospkg_jq
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
  _require_ospkg_jq
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
  _require_ospkg_jq
  local _json_file
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest.XXXXXX")"
  # brew-only package should NOT appear for apt context.
  printf '{"packages":[{"name":"brew-pkg","when":{"plat.pm":"brew"}},{"name":"apt-pkg","when":{"plat.pm":"apt"}}]}' \
    > "$_json_file"
  local _output
  _output="$(ospkg__parse_manifest_yaml "$_json_file")"
  rm -f "$_json_file"
  [[ "$_output" != *'"name":"brew-pkg"'* ]]
  [[ "$_output" == *'"name":"apt-pkg"'* ]]
}

@test "ospkg__parse_manifest_yaml skips the manifest when top-level when mismatches" {
  _seed_apt_context
  _require_ospkg_jq
  local _json_file
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest.XXXXXX")"
  printf '{"when":{"plat.pm":"brew"},"packages":["should-not-appear"]}' > "$_json_file"
  local _output
  _output="$(ospkg__parse_manifest_yaml "$_json_file")"
  rm -f "$_json_file"
  [[ -z "$_output" ]]
}

@test "ospkg__parse_manifest_yaml emits packages from pm-specific apt block" {
  _seed_apt_context
  _require_ospkg_jq
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
  _require_ospkg_jq
  local _json_file
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest.XXXXXX")"
  # jammy-only package should appear; bookworm-only should not.
  printf '{"packages":[{"name":"jammy-pkg","when":{"os.version_codename":"jammy"}},{"name":"bookworm-pkg","when":{"os.version_codename":"bookworm"}}]}' \
    > "$_json_file"
  local _output
  _output="$(ospkg__parse_manifest_yaml "$_json_file")"
  rm -f "$_json_file"
  # _seed_apt_context sets version_codename=jammy
  [[ "$_output" == *'"name":"jammy-pkg"'* ]]
  [[ "$_output" != *'"name":"bookworm-pkg"'* ]]
}

@test "ospkg__parse_manifest_yaml accepts repos as strings" {
  _seed_apt_context
  _require_ospkg_jq
  local _json_file
  _json_file="$(mktemp "${BATS_TEST_TMPDIR}/manifest.XXXXXX")"
  printf '{"repos":["deb http://deb.debian.org/debian stable main","deb http://example.invalid/debian stable main"],"packages":["tree"]}' \
    > "$_json_file"
  local _output
  _output="$(ospkg__parse_manifest_yaml "$_json_file")"
  rm -f "$_json_file"
  [[ "$_output" == *'"kind":"repo","content":"deb http://deb.debian.org/debian stable main"'* ]]
  [[ "$_output" == *'"kind":"repo","content":"deb http://example.invalid/debian stable main"'* ]]
  [[ "$_output" == *'"kind":"package","name":"tree"'* ]]
}

# ---------------------------------------------------------------------------
# ospkg__run — regression: stale yq binary path and silent parse failure
#
# Root cause: ospkg__run previously deleted the yq tmpdir inline at the end of
# every call (rm -rf $_OSPKG__YQ_TMPDIR; _OSPKG__YQ_TMPDIR=; _BOOTSTRAP__YQ_BIN=).
# A second call that reused _BOOTSTRAP__YQ_BIN via the early-return guard in
# bootstrap__yq would try to execute a non-existent binary.  The failure
# was silent because the yq+parse block was wrapped in `if ! {}`, which
# disables set -e.
# ---------------------------------------------------------------------------

# _seed_apt_context_with_yq — sets up apt context and creates a fake yq binary.
# Exports a mock bootstrap__yq that mirrors the real early-return guard.
_seed_apt_context_with_yq() {
  _seed_apt_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/bash\necho '"'"'{"packages":["regrpkg"]}'"'"'\n' \
    > "${BATS_TEST_TMPDIR}/bin/yq"
  chmod +x "${BATS_TEST_TMPDIR}/bin/yq"
  # Mock mirrors bootstrap__yq's real early-return guard so the second call
  # exercises the early-return code path with the already-set _BOOTSTRAP__YQ_BIN.
  # Note: _BOOTSTRAP__YQ_BIN is assigned to a stable path (not inside _FILE__SESSION_ROOT)
  # to avoid command-substitution subshell scoping issues with _FILE__SESSION_ROOT.
  bootstrap__yq() {
    [[ -n "${_BOOTSTRAP__YQ_BIN:-}" ]] && return 0
    _BOOTSTRAP__YQ_BIN="${BATS_TEST_TMPDIR}/bin/yq"
    return 0
  }
  export -f bootstrap__yq
}

@test "ospkg__run regression: yq binary not deleted after call returns" {
  # Old code: rm -rf "$_OSPKG__YQ_TMPDIR"; _BOOTSTRAP__YQ_BIN= inside ospkg__run.
  # Fix: yq dir lives in _FILE__SESSION_ROOT for the process lifetime; ospkg__run
  # never deletes it.
  _require_ospkg_jq
  _seed_apt_context_with_yq

  ospkg__run --manifest $'packages:\n  - regrpkg\n' --dry_run > /dev/null 2>&1

  # After the call, _BOOTSTRAP__YQ_BIN must still be set and the file must exist.
  [[ -n "${_BOOTSTRAP__YQ_BIN:-}" ]] ||
    {
      echo "_BOOTSTRAP__YQ_BIN was cleared after ospkg__run"
      return 1
    }
  [[ -f "$_BOOTSTRAP__YQ_BIN" ]] ||
    {
      echo "_BOOTSTRAP__YQ_BIN no longer points to a file: ${_BOOTSTRAP__YQ_BIN}"
      return 1
    }
}

@test "ospkg__run regression: second call succeeds via _BOOTSTRAP__YQ_BIN early-return path" {
  # Old code: after first call _BOOTSTRAP__YQ_BIN was cleared (or set to a deleted
  # path) so a second call silently processed no packages.
  # Fix: _BOOTSTRAP__YQ_BIN persists; bootstrap__yq early-returns and the binary
  # at that path is still valid.
  _require_ospkg_jq
  _seed_apt_context_with_yq

  local _log="${BATS_TEST_TMPDIR}/run.log"

  # First call — sets _BOOTSTRAP__YQ_BIN via mock.
  ospkg__run --manifest $'packages:\n  - regrpkg\n' --dry_run > "$_log" 2>&1
  _lib_test__append_pending_journal_to "$_log"
  grep -q "\[dry-run\] packages: regrpkg" "$_log" ||
    {
      echo "First call: expected dry-run output absent"
      cat "$_log" >&2
      return 1
    }

  # Second call — bootstrap__yq early-returns; the binary at _BOOTSTRAP__YQ_BIN
  # must still be accessible.  Old code would have deleted it above.
  : > "$_log"
  ospkg__run --manifest $'packages:\n  - regrpkg\n' --dry_run > "$_log" 2>&1
  _lib_test__append_pending_journal_to "$_log"
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
  _require_ospkg_jq

  run bash -c "
    source \"${LIB_ROOT}/__init__.bash\"
    set -euo pipefail

    # Seed a minimal apt context without calling the real package manager.
    _OSPKG__DETECTED=true
    _OSPKG__PKG_MNGR='apt-get'
    _OSPKG__FAMILY='apt'
    ctx__set plat.pm=apt plat.machine_release=amd64 os.id=ubuntu os.id_like=debian os.version_id=22.04 os.version_codename=jammy plat.kernel=linux
    _CTX__REGISTRY_INITIALIZED=true

    # A yq stub that always exits non-zero (simulates corrupt binary / bad manifest).
    _BOOTSTRAP__YQ_BIN='${BATS_TEST_TMPDIR}/bin/yq'
    mkdir -p '${BATS_TEST_TMPDIR}/bin'
    printf '#!/bin/bash\nexit 1\n' > \"\$_BOOTSTRAP__YQ_BIN\"
    chmod +x \"\$_BOOTSTRAP__YQ_BIN\"
    bootstrap__yq() { return 0; }

    ospkg__run --manifest \$'packages:\n  - curl\n' --dry_run
  "
  assert_failure
}

@test "ospkg__run fails when manifest parser returns non-zero" {
  _require_ospkg_jq

  run bash -c "
    source \"${LIB_ROOT}/__init__.bash\"
    set -euo pipefail

    _OSPKG__DETECTED=true
    _OSPKG__PKG_MNGR='apt-get'
    _OSPKG__FAMILY='apt'
    ctx__set plat.pm=apt plat.machine_release=amd64 os.id=ubuntu os.id_like=debian os.version_id=22.04 os.version_codename=jammy plat.kernel=linux
    _CTX__REGISTRY_INITIALIZED=true

    # yq returns valid JSON; parser failure is injected directly.
    _BOOTSTRAP__YQ_BIN='${BATS_TEST_TMPDIR}/bin/yq'
    mkdir -p '${BATS_TEST_TMPDIR}/bin'
    cat > \"\$_BOOTSTRAP__YQ_BIN\" <<'YQ'
#!/bin/bash
cat <<'JSON'
{\"packages\":[\"curl\"]}
JSON
YQ
    chmod +x \"\$_BOOTSTRAP__YQ_BIN\"
    bootstrap__yq() { return 0; }
    ospkg__parse_manifest_yaml() { return 42; }

    ospkg__run --manifest \$'packages:\n  - curl\n' --dry_run
  "
  assert_failure
}

@test "ospkg__run dry_run succeeds without root when package manager is present" {
  # Documents that the removed root requirement gate was intentional:
  # non-root callers can use ospkg__run in dry-run mode without privilege.
  _seed_apt_context_with_yq
  users__is_root() { return 1; }
  export -f users__is_root
  run ospkg__run --manifest $'packages:\n  - curl\n' --dry_run
  assert_success
}

@test "ospkg__run build-group skips snapshot when manifest when yields no install actions" {
  # Regression: Linux-only build manifests on macOS must not snapshot via brew list
  # before `when` is evaluated (brew may be absent during reinstall).
  _require_ospkg_jq
  reload_lib

  local _snap_log="${BATS_TEST_TMPDIR}/snapshot-calls"
  : > "$_snap_log"
  _ospkg__snapshot_packages() {
    echo 1 >> "$_snap_log"
    return 127
  }
  export -f _ospkg__snapshot_packages

  logging__cleanup() { return 0; }
  _ospkg__detect() {
    _OSPKG__FAMILY="brew"
    _OSPKG__PKG_MNGR="brew"
    _OSPKG__DETECTED=true
    ctx__set plat.pm=brew plat.kernel=darwin os.id=macos os.id_like=macos plat.machine_release=arm64
    _CTX__REGISTRY_INITIALIZED=true
    return 0
  }
  export -f _ospkg__detect logging__cleanup

  local _fake_yq="${BATS_TEST_TMPDIR}/bin/yq"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/bash\necho '"'"'{"when":{"kernel":"linux"},"packages":["build-essential"]}'"'"'\n' \
    > "$_fake_yq"
  chmod +x "$_fake_yq"
  bootstrap__yq() {
    _BOOTSTRAP__YQ_BIN="${BATS_TEST_TMPDIR}/bin/yq"
    return 0
  }
  export -f bootstrap__yq

  run ospkg__run \
    --manifest $'when:\n  kernel: linux\npackages:\n  - build-essential\n' \
    --build-group 'test::method-script'

  assert_success
  assert_output --partial "manifest has no install actions on this platform"
  [[ ! -s "$_snap_log" ]]
}

# ---------------------------------------------------------------------------
# ctx__expand_pattern — ctx pattern expansion
# ---------------------------------------------------------------------------

@test "ctx__expand_pattern expands qualified ctx tokens" {
  reload_lib
  ctx__set feat.version=2.89.0
  ctx__set os.version_codename=stable
  _CTX__REGISTRY_INITIALIZED=true

  local _result
  _result="$(ctx__expand_pattern 'gh-{feat.version}-{os.version_codename}')"
  [[ "${_result}" == "gh-2.89.0-stable" ]]
}

@test "ctx__expand_pattern: empty ctx value collapses placeholder" {
  reload_lib
  ctx__set feat.version=
  _CTX__REGISTRY_INITIALIZED=true

  local _result
  _result="$(ctx__expand_pattern 'gh={feat.version}')"
  [[ "${_result}" == "gh=" ]]
}

@test "ctx__expand_pattern: os and feat tokens expand together" {
  reload_lib
  ctx__set os.id=ubuntu
  ctx__set feat.version=2.89.0
  _CTX__REGISTRY_INITIALIZED=true

  local _result
  _result="$(ctx__expand_pattern '{os.id}-{feat.version}')"
  [[ "${_result}" == "ubuntu-2.89.0" ]]
}

@test "ctx__expand_pattern: unknown placeholder left unchanged" {
  reload_lib
  _CTX__REGISTRY_INITIALIZED=true

  local _result
  _result="$(ctx__expand_pattern '{UNKNOWN_VAR}')"
  [[ "${_result}" == '{UNKNOWN_VAR}' ]]
}

@test "ospkg__run rejects unknown option" {
  _seed_apt_context_with_yq
  run ospkg__run --manifest $'packages:\n  - curl\n' --bogus-flag
  assert_failure
  assert_output --partial "unknown option"
}

# ---------------------------------------------------------------------------
# Build-dep tracking: ospkg__install_tracked / _ospkg__remove_build_group /
#                     ospkg__cleanup_all_build_groups
# ---------------------------------------------------------------------------

# _seed_apt_build_context — seeds apt context + stubs needed for build-dep tests:
#   · _FILE__SESSION_ROOT        → BATS_TEST_TMPDIR (sidecars at a predictable path)
#   · fake apt-get          (exit 0, no-op — real install skipped)
#   · fake dpkg             (exit 1 — "not installed" so ospkg__install always proceeds)
#   · fake apt-mark         (logs every invocation to ${BATS_TEST_TMPDIR}/apt-mark.log)
#   · users__run_privileged → "$@" directly (inherited from _seed_apt_context)
#   · net__fetch_with_retry → passthrough so the fake apt-get is actually invoked
# After this, call _mock_snapshots to control the before/after package lists.
_seed_apt_build_context() {
  _seed_apt_context
  _stub_ospkg_privilege_ok
  export _SYSSET_BUILD_CONTEXT="ctx"
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"
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
# Replaces _ospkg__snapshot_packages with a counter-based mock.  The first call
# returns <before_pkgs> (one-per-line, sorted); all subsequent calls return
# <after_pkgs>.  Uses a temp file for the counter to avoid bash closure issues.
_mock_snapshots() {
  export SNAP_BEFORE="$1"
  export SNAP_AFTER="$2"
  echo 0 > "${BATS_TEST_TMPDIR}/.snap_call"
  _ospkg__snapshot_packages() {
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

  local _sidecar="${BATS_TEST_TMPDIR}/ospkg/build-deps/ctx::test-group"
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

  local _sidecar="${BATS_TEST_TMPDIR}/ospkg/build-deps/ctx::test-group"
  assert_file_exists "$_sidecar"
  [[ ! -s "$_sidecar" ]]
}

@test "ospkg__install_tracked: pre-installed package — apt-mark auto not called" {
  _seed_apt_build_context
  _mock_snapshots "curl newpkg" "curl newpkg"

  ospkg__install_tracked "test-group" newpkg

  [[ ! -f "${BATS_TEST_TMPDIR}/apt-mark.log" ]] || ! grep -q "^auto " "${BATS_TEST_TMPDIR}/apt-mark.log"
}

@test "ospkg__install_tracked: _ospkg__detect called before before-snapshot — PM set correctly" {
  # Regression: without the _ospkg__detect call at the top of ospkg__install_tracked,
  # _OSPKG__PKG_MNGR is empty when the before-snapshot runs (hitting the '*' case that
  # writes an empty file). ospkg__install then calls _ospkg__detect internally, setting
  # the PM. The after-snapshot then captures every installed package. The diff
  # (empty before vs full after) = all packages tracked for removal — a destructive bug.
  _seed_apt_build_context
  # Reset detection state to simulate a fresh call where _ospkg__detect has not yet run.
  _OSPKG__DETECTED=false
  _OSPKG__PKG_MNGR=""

  local _pm_log="${BATS_TEST_TMPDIR}/pm_at_snapshot.log"
  local _snap_call=0
  _ospkg__snapshot_packages() {
    _snap_call=$((_snap_call + 1))
    if [[ $_snap_call -eq 1 ]]; then
      # Record _OSPKG__PKG_MNGR on the before-snapshot call.
      printf '%s\n' "${_OSPKG__PKG_MNGR:-EMPTY}" > "$_pm_log"
    fi
    : > "$1"
  }

  ospkg__install_tracked "test-group" pkg

  # The fix: _OSPKG__PKG_MNGR must be set (not empty) when the before-snapshot runs.
  assert_file_exists "$_pm_log"
  run cat "$_pm_log"
  refute_output "EMPTY"
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

  local _sidecar="${BATS_TEST_TMPDIR}/ospkg/build-deps/ctx::test-group"
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

  local _sidecar="${BATS_TEST_TMPDIR}/ospkg/build-deps/ctx::test-group"
  [[ $(grep -c "^pkg1$" "$_sidecar") -eq 1 ]]
}

@test "ospkg__install_tracked: different group-ids create separate sidecars" {
  _seed_apt_build_context

  _mock_snapshots "" "pkg1"
  ospkg__install_tracked "group-a" pkg1

  _mock_snapshots "pkg1" "pkg1 pkg2"
  ospkg__install_tracked "group-b" pkg2

  local _bd="${BATS_TEST_TMPDIR}/ospkg/build-deps"
  assert_file_exists "${_bd}/ctx::group-a"
  assert_file_exists "${_bd}/ctx::group-b"
  grep -q "^pkg1$" "${_bd}/ctx::group-a"
  grep -q "^pkg2$" "${_bd}/ctx::group-b"
  # pkg2 must not bleed into group-a's sidecar.
  run grep "pkg2" "${_bd}/ctx::group-a"
  assert_failure
}

# ── _ospkg__remove_build_group ────────────────────────────────────────────────

@test "_ospkg__remove_build_group: missing sidecar returns 0 with informational message" {
  _seed_apt_context
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"

  run _ospkg__remove_build_group "nonexistent-group"

  assert_success
  assert_output --partial "nothing to remove"
}

@test "_ospkg__remove_build_group: empty sidecar returns 0 without invoking autoremove" {
  _seed_apt_context
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"
  mkdir -p "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  : > "${BATS_TEST_TMPDIR}/ospkg/build-deps/test-group"

  local _apt_log="${BATS_TEST_TMPDIR}/apt-get.log"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/bash\necho "$@" >> "%s"\n' "$_apt_log" \
    > "${BATS_TEST_TMPDIR}/bin/apt-get"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-get"
  prepend_fake_bin_path

  run _ospkg__remove_build_group "test-group"

  assert_success
  assert_output --partial "nothing to remove"
  [[ ! -f "$_apt_log" ]]
}

@test "_ospkg__remove_build_group: apt — calls autoremove (not per-package remove) and deletes sidecar" {
  _seed_apt_context
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  printf 'curl\nnewpkg\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/test-group"

  local _apt_log="${BATS_TEST_TMPDIR}/apt-get.log"
  printf '#!/bin/bash\necho "$@" >> "%s"\n' "$_apt_log" \
    > "${BATS_TEST_TMPDIR}/bin/apt-get"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-get"
  prepend_fake_bin_path

  _ospkg__remove_build_group "test-group"

  # Pre-existing auto packages are protected by _ospkg__ensure_global_auto_snapshot,
  # so cleanup uses apt-get autoremove (not explicit per-package removal) — this
  # avoids removing reverse-dependencies of manually-marked packages.
  grep -q "autoremove" "$_apt_log"
  grep -q -- "--purge" "$_apt_log"
  # Individual package names must NOT be passed to autoremove.
  run grep -q "curl\|newpkg" "$_apt_log"
  assert_failure
  [[ ! -f "${BATS_TEST_TMPDIR}/ospkg/build-deps/test-group" ]]
}

# ── ospkg__cleanup_all_build_groups ──────────────────────────────────────────

@test "ospkg__cleanup_all_build_groups: missing build-deps directory returns 0" {
  _seed_apt_context
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}/no_such_dir_xyz"

  run ospkg__cleanup_all_build_groups

  assert_success
}

@test "ospkg__cleanup_all_build_groups: .before and .after files are skipped" {
  # Temp snapshot files left by an aborted run must not be treated as group
  # sidecars — they must remain untouched after cleanup.
  _seed_apt_context
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"
  mkdir -p "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  : > "${BATS_TEST_TMPDIR}/ospkg/build-deps/group.before"
  : > "${BATS_TEST_TMPDIR}/ospkg/build-deps/group.after"

  run ospkg__cleanup_all_build_groups

  assert_success
  assert_file_exists "${BATS_TEST_TMPDIR}/ospkg/build-deps/group.before"
  assert_file_exists "${BATS_TEST_TMPDIR}/ospkg/build-deps/group.after"
}

@test "ospkg__cleanup_all_build_groups: one group sidecar triggers autoremove and sidecar is deleted" {
  _seed_apt_context
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  printf 'curl\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/my-group"

  local _apt_log="${BATS_TEST_TMPDIR}/apt-get.log"
  printf '#!/bin/bash\necho "$@" >> "%s"\n' "$_apt_log" \
    > "${BATS_TEST_TMPDIR}/bin/apt-get"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-get"
  prepend_fake_bin_path

  ospkg__cleanup_all_build_groups

  grep -q "autoremove" "$_apt_log"
  grep -q -- "--purge" "$_apt_log"
  [[ ! -f "${BATS_TEST_TMPDIR}/ospkg/build-deps/my-group" ]]
}

@test "ospkg__cleanup_all_build_groups: multiple group sidecars are all removed" {
  _seed_apt_context
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"
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
# ospkg__is_managed
# ---------------------------------------------------------------------------

# _seed_managed_context <family> — pre-seeds detection state so ospkg__is_managed
# skips _ospkg__detect and dispatches on the given family directly.
_seed_managed_context() {
  reload_lib
  _OSPKG__DETECTED=true
  _OSPKG__FAMILY="${1}"
  _OSPKG__PKG_MNGR="${1}"
}

@test "ospkg__is_managed: empty path returns 1" {
  _seed_managed_context apt
  run ospkg__is_managed ""
  assert_failure
}

@test "ospkg__is_managed: nonexistent path returns 1" {
  _seed_managed_context apt
  run ospkg__is_managed "/nonexistent/path/does-not-exist"
  assert_failure
}

@test "ospkg__is_managed: apt — dpkg -S succeeds → returns 0" {
  _seed_managed_context apt
  local _bin
  _bin="$(mktemp "${BATS_TEST_TMPDIR}/bin-XXXXXX")"
  create_fake_bin "dpkg" ""
  prepend_fake_bin_path
  run ospkg__is_managed "$_bin"
  assert_success
}

@test "ospkg__is_managed: apt — dpkg -S fails → returns 1" {
  _seed_managed_context apt
  local _bin
  _bin="$(mktemp "${BATS_TEST_TMPDIR}/bin-XXXXXX")"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/sh\nexit 1\n' > "${BATS_TEST_TMPDIR}/bin/dpkg"
  chmod +x "${BATS_TEST_TMPDIR}/bin/dpkg"
  prepend_fake_bin_path
  run ospkg__is_managed "$_bin"
  assert_failure
}

@test "ospkg__is_managed: apk — apk info --who-owns succeeds → returns 0" {
  _seed_managed_context apk
  local _bin
  _bin="$(mktemp "${BATS_TEST_TMPDIR}/bin-XXXXXX")"
  create_fake_bin "apk" ""
  prepend_fake_bin_path
  run ospkg__is_managed "$_bin"
  assert_success
}

@test "ospkg__is_managed: apk — apk info --who-owns fails → returns 1" {
  _seed_managed_context apk
  local _bin
  _bin="$(mktemp "${BATS_TEST_TMPDIR}/bin-XXXXXX")"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/sh\nexit 1\n' > "${BATS_TEST_TMPDIR}/bin/apk"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apk"
  prepend_fake_bin_path
  run ospkg__is_managed "$_bin"
  assert_failure
}

@test "ospkg__is_managed: dnf — rpm -qf succeeds → returns 0" {
  _seed_managed_context dnf
  local _bin
  _bin="$(mktemp "${BATS_TEST_TMPDIR}/bin-XXXXXX")"
  create_fake_bin "rpm" ""
  prepend_fake_bin_path
  run ospkg__is_managed "$_bin"
  assert_success
}

@test "ospkg__is_managed: dnf — rpm -qf fails → returns 1" {
  _seed_managed_context dnf
  local _bin
  _bin="$(mktemp "${BATS_TEST_TMPDIR}/bin-XXXXXX")"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/sh\nexit 1\n' > "${BATS_TEST_TMPDIR}/bin/rpm"
  chmod +x "${BATS_TEST_TMPDIR}/bin/rpm"
  prepend_fake_bin_path
  run ospkg__is_managed "$_bin"
  assert_failure
}

@test "ospkg__is_managed: zypper — rpm -qf succeeds → returns 0" {
  _seed_managed_context zypper
  local _bin
  _bin="$(mktemp "${BATS_TEST_TMPDIR}/bin-XXXXXX")"
  create_fake_bin "rpm" ""
  prepend_fake_bin_path
  run ospkg__is_managed "$_bin"
  assert_success
}

@test "ospkg__is_managed: pacman — pacman -Qo succeeds → returns 0" {
  _seed_managed_context pacman
  local _bin
  _bin="$(mktemp "${BATS_TEST_TMPDIR}/bin-XXXXXX")"
  create_fake_bin "pacman" ""
  prepend_fake_bin_path
  run ospkg__is_managed "$_bin"
  assert_success
}

@test "ospkg__is_managed: pacman — pacman -Qo fails → returns 1" {
  _seed_managed_context pacman
  local _bin
  _bin="$(mktemp "${BATS_TEST_TMPDIR}/bin-XXXXXX")"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/sh\nexit 1\n' > "${BATS_TEST_TMPDIR}/bin/pacman"
  chmod +x "${BATS_TEST_TMPDIR}/bin/pacman"
  prepend_fake_bin_path
  run ospkg__is_managed "$_bin"
  assert_failure
}

@test "ospkg__is_managed: brew — symlink resolves into prefix/opt/ → returns 0" {
  _seed_managed_context brew
  local _prefix="${BATS_TEST_TMPDIR}/homebrew"
  local _target="${_prefix}/opt/mytool/bin/mytool"
  mkdir -p "$(dirname "$_target")"
  touch "$_target"
  local _bin="${_prefix}/bin/mytool"
  mkdir -p "$(dirname "$_bin")"
  ln -sf "$_target" "$_bin"
  create_fake_bin "brew" "$_prefix"
  prepend_fake_bin_path
  run ospkg__is_managed "$_bin"
  assert_success
}

@test "ospkg__is_managed: brew — symlink resolves into prefix/Cellar/ → returns 0" {
  _seed_managed_context brew
  local _prefix="${BATS_TEST_TMPDIR}/homebrew"
  local _target="${_prefix}/Cellar/mytool/1.0.0/bin/mytool"
  mkdir -p "$(dirname "$_target")"
  touch "$_target"
  local _bin="${_prefix}/bin/mytool"
  mkdir -p "$(dirname "$_bin")"
  ln -sf "$_target" "$_bin"
  create_fake_bin "brew" "$_prefix"
  prepend_fake_bin_path
  run ospkg__is_managed "$_bin"
  assert_success
}

@test "ospkg__is_managed: brew — non-symlink outside prefix → returns 1" {
  _seed_managed_context brew
  local _prefix="${BATS_TEST_TMPDIR}/homebrew"
  local _bin
  _bin="$(mktemp "${BATS_TEST_TMPDIR}/external-tool-XXXXXX")"
  create_fake_bin "brew" "$_prefix"
  prepend_fake_bin_path
  run ospkg__is_managed "$_bin"
  assert_failure
}

@test "ospkg__is_managed: unknown family → returns 1" {
  _seed_managed_context unknown-pm
  local _bin
  _bin="$(mktemp "${BATS_TEST_TMPDIR}/bin-XXXXXX")"
  run ospkg__is_managed "$_bin"
  assert_failure
}

@test "ospkg__is_managed: _ospkg__detect failure → returns 1" {
  reload_lib
  local _bin
  _bin="$(mktemp "${BATS_TEST_TMPDIR}/bin-XXXXXX")"
  # Isolate PATH to a dir with no package managers; uname stays available.
  begin_path_isolation uname
  run ospkg__is_managed "$_bin"
  end_path_isolation
  assert_failure
}

# ---------------------------------------------------------------------------
# ospkg__is_installed
# ---------------------------------------------------------------------------

@test "ospkg__is_installed: apt — returns 0 when dpkg reports package installed" {
  _seed_apt_context
  create_fake_bin "dpkg" ""
  prepend_fake_bin_path
  run ospkg__is_installed curl
  assert_success
}

@test "ospkg__is_installed: apt — returns 1 when dpkg reports package not installed" {
  _seed_apt_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/sh\nexit 1\n' > "${BATS_TEST_TMPDIR}/bin/dpkg"
  chmod +x "${BATS_TEST_TMPDIR}/bin/dpkg"
  prepend_fake_bin_path
  run ospkg__is_installed curl
  assert_failure
}

@test "ospkg__is_installed: apk — returns 0 when apk info -e succeeds" {
  _seed_apk_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/sh\nexit 0\n' > "${BATS_TEST_TMPDIR}/bin/apk"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apk"
  prepend_fake_bin_path
  run ospkg__is_installed curl
  assert_success
}

@test "ospkg__is_installed: apk — returns 1 when apk info -e fails" {
  _seed_apk_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/sh\nexit 1\n' > "${BATS_TEST_TMPDIR}/bin/apk"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apk"
  prepend_fake_bin_path
  run ospkg__is_installed curl
  assert_failure
}

@test "ospkg__is_installed: dnf — returns 0 when rpm -q succeeds" {
  reload_lib
  _OSPKG__DETECTED=true
  _OSPKG__PKG_MNGR="dnf"
  create_fake_bin "rpm" ""
  prepend_fake_bin_path
  run ospkg__is_installed curl
  assert_success
}

@test "ospkg__is_installed: dnf — returns 1 when rpm -q fails" {
  reload_lib
  _OSPKG__DETECTED=true
  _OSPKG__PKG_MNGR="dnf"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/sh\nexit 1\n' > "${BATS_TEST_TMPDIR}/bin/rpm"
  chmod +x "${BATS_TEST_TMPDIR}/bin/rpm"
  prepend_fake_bin_path
  run ospkg__is_installed curl
  assert_failure
}

@test "ospkg__is_installed: pacman — returns 0 when pacman -Qq succeeds" {
  _seed_pacman_context
  create_fake_bin "pacman" ""
  prepend_fake_bin_path
  run ospkg__is_installed curl
  assert_success
}

@test "ospkg__is_installed: pacman — returns 1 when pacman -Qq fails" {
  _seed_pacman_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/sh\nexit 1\n' > "${BATS_TEST_TMPDIR}/bin/pacman"
  chmod +x "${BATS_TEST_TMPDIR}/bin/pacman"
  prepend_fake_bin_path
  run ospkg__is_installed curl
  assert_failure
}

@test "ospkg__is_installed: brew — returns 0 when brew list --formula succeeds" {
  reload_lib
  _OSPKG__DETECTED=true
  _OSPKG__PKG_MNGR="brew"
  create_fake_bin "brew" ""
  prepend_fake_bin_path
  run ospkg__is_installed curl
  assert_success
}

@test "ospkg__is_installed: brew — returns 1 when brew list --formula fails" {
  reload_lib
  _OSPKG__DETECTED=true
  _OSPKG__PKG_MNGR="brew"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/sh\nexit 1\n' > "${BATS_TEST_TMPDIR}/bin/brew"
  chmod +x "${BATS_TEST_TMPDIR}/bin/brew"
  prepend_fake_bin_path
  run ospkg__is_installed curl
  assert_failure
}

@test "ospkg__is_installed: multiple packages — returns 0 when all installed" {
  _seed_apt_context
  create_fake_bin "dpkg" ""
  prepend_fake_bin_path
  run ospkg__is_installed curl wget git
  assert_success
}

@test "ospkg__is_installed: multiple packages — returns 1 when one package is not installed" {
  _seed_apt_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  # dpkg returns 0 for curl and wget, but 1 for git.
  printf '#!/bin/bash\n[[  "$2" == "git" ]] && exit 1 || exit 0\n' \
    > "${BATS_TEST_TMPDIR}/bin/dpkg"
  chmod +x "${BATS_TEST_TMPDIR}/bin/dpkg"
  prepend_fake_bin_path
  run ospkg__is_installed curl wget git
  assert_failure
}

@test "ospkg__is_installed: returns 1 when _ospkg__detect fails" {
  reload_lib
  begin_path_isolation uname
  run ospkg__is_installed curl
  end_path_isolation
  assert_failure
}

# ---------------------------------------------------------------------------
@test "ospkg__run YAML path works on macOS (portable mktemp)" {
  [[ "$(uname -s)" == "Darwin" ]] || skip "macOS-only"
  _require_ospkg_jq
  reload_lib

  # A fake yq that ignores its arguments and emits a fixed JSON manifest.
  local _fake_yq="${BATS_TEST_TMPDIR}/bin/yq"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/bash\necho '"'"'{"packages":["foo"]}'"'"'\n' > "$_fake_yq"
  chmod +x "$_fake_yq"

  logging__cleanup() { return 0; }
  _ospkg__detect() {
    _OSPKG__FAMILY="brew"
    _OSPKG__PKG_MNGR="brew"
    _OSPKG__DETECTED=true
    ctx__set plat.pm=brew plat.kernel=darwin os.id=macos os.id_like=macos plat.machine_release=arm64
    _CTX__REGISTRY_INITIALIZED=true
    return 0
  }
  bootstrap__yq() {
    _BOOTSTRAP__YQ_BIN="${BATS_TEST_TMPDIR}/bin/yq"
    return 0
  }
  export -f _ospkg__detect logging__cleanup bootstrap__yq

  run ospkg__run --manifest $'packages:\n  - foo\n' --dry_run
  assert_success
  assert_output --partial "[dry-run] packages: foo"
}

# ---------------------------------------------------------------------------
# ospkg__take_initial_snapshot
# ---------------------------------------------------------------------------

@test "ospkg__take_initial_snapshot writes sorted package list to file" {
  _seed_apt_context
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"
  # Provide a fake dpkg-query that emits a known set of packages.
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/bash\nprintf "wget\ncurl\ngit\n"\n' \
    > "${BATS_TEST_TMPDIR}/bin/dpkg-query"
  chmod +x "${BATS_TEST_TMPDIR}/bin/dpkg-query"
  prepend_fake_bin_path

  local _snap="${BATS_TEST_TMPDIR}/snap.txt"
  ospkg__take_initial_snapshot "$_snap"

  assert_file_exists "$_snap"
  # sort -u so order-independence: curl git wget
  grep -q "^curl$" "$_snap"
  grep -q "^git$" "$_snap"
  grep -q "^wget$" "$_snap"
}

@test "ospkg__take_initial_snapshot prints informational message to stderr" {
  _seed_apt_context
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"
  create_fake_bin "dpkg-query" ""
  prepend_fake_bin_path

  local _snap="${BATS_TEST_TMPDIR}/snap.txt"
  run ospkg__take_initial_snapshot "$_snap"

  assert_success
  assert_output --partial "Initial package snapshot written"
}

@test "ospkg__take_initial_snapshot creates empty file for unknown PM" {
  reload_lib
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"
  # Force an unknown PM context directly to test the '*' case.
  _OSPKG__DETECTED=true
  _OSPKG__PKG_MNGR="unknown-pm"
  _OSPKG__FAMILY="unknown"

  local _snap="${BATS_TEST_TMPDIR}/snap_unknown.txt"
  ospkg__take_initial_snapshot "$_snap"

  assert_file_exists "$_snap"
  [[ ! -s "$_snap" ]]
}

# ---------------------------------------------------------------------------
# ospkg__install_tracked — session co-ownership tracking (new behaviour)
# ---------------------------------------------------------------------------

# _seed_session_context — seeds apt build context + session tracking dir.
# Exposes _SESSION_DIR and _INITIAL_SNAP variables for use in tests.
_seed_session_context() {
  _seed_apt_build_context
  _SESSION_DIR="$(mktemp -d "${BATS_TEST_TMPDIR}/session_XXXXXX")"
  _INITIAL_SNAP="${BATS_TEST_TMPDIR}/initial.snap"
  export _SYSSET_SESSION_TRACK_DIR="$_SESSION_DIR"
  export _SYSSET_INITIAL_SNAPSHOT="$_INITIAL_SNAP"
}

@test "ospkg__install_tracked: new package is appended to session sidecar" {
  _seed_session_context
  # pre-session: curl is already installed; newpkg is not in initial snapshot
  printf 'curl\n' > "$_INITIAL_SNAP"
  _mock_snapshots "curl" "curl newpkg"

  ospkg__install_tracked "lib-net" newpkg

  local _sess_sidecar="${_SESSION_DIR}/feature::::install-test::::lib-net"
  # filename uses // substitution so :: → ::::... let's detect the real name
  local _found
  _found="$(ls "$_SESSION_DIR"/ 2> /dev/null | head -1)"
  [[ -n "$_found" ]]
  grep -q "^newpkg$" "${_SESSION_DIR}/${_found}"
}

@test "ospkg__install_tracked: pre-session package is excluded from session sidecar" {
  _seed_session_context
  # curl is in the initial snapshot → should NOT appear in session sidecar
  printf 'curl\n' > "$_INITIAL_SNAP"
  _mock_snapshots "curl" "curl"

  ospkg__install_tracked "lib-net" curl

  # Session sidecar should either not exist or not contain 'curl'
  local _found
  _found="$(ls "$_SESSION_DIR"/ 2> /dev/null | head -1)"
  if [[ -n "$_found" ]]; then
    run grep "^curl$" "${_SESSION_DIR}/${_found}"
    assert_failure
  fi
}

@test "ospkg__install_tracked: session sidecar deduplicates repeated calls" {
  _seed_session_context
  printf '' > "$_INITIAL_SNAP" # empty initial snapshot
  _mock_snapshots "" "pkgA"
  ospkg__install_tracked "lib-net" pkgA
  _mock_snapshots "pkgA" "pkgA"
  ospkg__install_tracked "lib-net" pkgA

  # Find the session sidecar
  local _found
  _found="$(ls "$_SESSION_DIR"/ 2> /dev/null | head -1)"
  [[ -n "$_found" ]]
  [[ "$(grep -c "^pkgA$" "${_SESSION_DIR}/${_found}")" -eq 1 ]]
}

@test "ospkg__install_tracked: no session tracking when _SYSSET_SESSION_TRACK_DIR is unset" {
  _seed_apt_build_context
  unset _SYSSET_SESSION_TRACK_DIR
  _mock_snapshots "" "newpkg"

  ospkg__install_tracked "test-group" newpkg

  # SYSSET_TMPDIR/ospkg/build-deps sidecar should exist (local tracking)
  local _sidecar="${BATS_TEST_TMPDIR}/ospkg/build-deps/ctx::test-group"
  assert_file_exists "$_sidecar"
  grep -q "^newpkg$" "$_sidecar"
}

@test "ospkg__install_tracked: no session tracking when session dir does not exist" {
  _seed_apt_build_context
  export _SYSSET_SESSION_TRACK_DIR="${BATS_TEST_TMPDIR}/no_such_session_dir_xyz"
  _mock_snapshots "" "newpkg"

  # Must not fail even though _SYSSET_SESSION_TRACK_DIR does not exist.
  run ospkg__install_tracked "test-group" newpkg
  assert_success
}

# ---------------------------------------------------------------------------
# ospkg__cleanup_session_build_groups
# ---------------------------------------------------------------------------

# _seed_session_cleanup_context — seeds apt context + required infrastructure.
# Callers populate ${_SESSION_DIR}/ with sidecar files and ${_BUILD_DEPS_DIR}/
# with sidecar files before calling ospkg__cleanup_session_build_groups.
_seed_session_cleanup_context() {
  _seed_apt_context
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"
  _SESSION_DIR="$(mktemp -d "${BATS_TEST_TMPDIR}/session_XXXXXX")"
  export _SYSSET_SESSION_TRACK_DIR="$_SESSION_DIR"
  mkdir -p "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  _APT_LOG="${BATS_TEST_TMPDIR}/apt-get.log"
  printf '#!/bin/bash\necho "$@" >> "%s"\n' "$_APT_LOG" \
    > "${BATS_TEST_TMPDIR}/bin/apt-get"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-get"
  prepend_fake_bin_path
}

@test "ospkg__cleanup_session_build_groups: no-ops when _SYSSET_SESSION_TRACK_DIR is unset" {
  reload_lib
  unset _SYSSET_SESSION_TRACK_DIR

  run ospkg__cleanup_session_build_groups "false"
  assert_success
}

@test "ospkg__cleanup_session_build_groups: no-ops when session dir does not exist" {
  reload_lib
  export _SYSSET_SESSION_TRACK_DIR="${BATS_TEST_TMPDIR}/no_such_dir_xyz"

  run ospkg__cleanup_session_build_groups "false"
  assert_success
}

@test "ospkg__cleanup_session_build_groups: deletes session dir on completion" {
  _seed_session_cleanup_context
  # Empty session dir — nothing to remove, but dir should still be deleted.

  ospkg__cleanup_session_build_groups "false"

  [[ ! -d "$_SESSION_DIR" ]]
}

@test "ospkg__cleanup_session_build_groups: single feature keep=false — package removed" {
  _seed_session_cleanup_context
  # One feature with keep=false contributed 'buildpkg'.
  printf 'buildpkg\n' > "${_SESSION_DIR}/feature::install-test::lib-net"

  ospkg__cleanup_session_build_groups "false"

  grep -q "autoremove\|remove" "$_APT_LOG" || grep -q "buildpkg" "$_APT_LOG"
}

@test "ospkg__cleanup_session_build_groups: keep-wins — any true prevents removal" {
  _seed_session_cleanup_context
  # Two features co-own 'sharedpkg': one keeps, one does not.
  printf 'sharedpkg\n' > "${_SESSION_DIR}/feature::install-a::lib-net"
  printf 'sharedpkg\n' > "${_SESSION_DIR}/feature::install-b::lib-net"

  # Declare _OPT_OF so ospkg__cleanup_session_build_groups can read keep policy.
  declare -gA _OPT_OF=(
    ["install-a"]='{"keep_build_deps": true}'
    ["install-b"]='{"keep_build_deps": false}'
  )

  ospkg__cleanup_session_build_groups "false"

  # Package must NOT be removed — keep wins.
  [[ ! -f "$_APT_LOG" ]] || ! grep -q "sharedpkg" "$_APT_LOG"
}

@test "ospkg__cleanup_session_build_groups: install-bash keep=true prevents removal" {
  _seed_session_cleanup_context
  # install-bash contributed 'gbpkg' and requests keep=true.
  printf 'gbpkg\n' > "${_SESSION_DIR}/install-bash::bootstrap"

  ospkg__cleanup_session_build_groups "true"

  [[ ! -f "$_APT_LOG" ]] || ! grep -q "gbpkg" "$_APT_LOG"
}

@test "ospkg__cleanup_session_build_groups: all keep=false — packages are removed" {
  _seed_session_cleanup_context
  # Two distinct packages owned by separate contexts, both keep=false.
  printf 'pkgA\n' > "${_SESSION_DIR}/feature::install-a::lib-net"
  printf 'pkgB\n' > "${_SESSION_DIR}/feature::install-b::lib-net"

  declare -gA _OPT_OF=(
    ["install-a"]='{"keep_build_deps": false}'
    ["install-b"]='{"keep_build_deps": false}'
  )

  ospkg__cleanup_session_build_groups "false"

  assert_file_exists "$_APT_LOG"
}

@test "ospkg__cleanup_session_build_groups: resources/ subdir is ignored" {
  _seed_session_cleanup_context
  # Place a file inside resources/ — must not be treated as a package sidecar.
  mkdir -p "${_SESSION_DIR}/resources"
  printf '/tmp/somefile\n' > "${_SESSION_DIR}/resources/my-group"

  ospkg__cleanup_session_build_groups "false"

  # apt-get must not have been invoked for anything.
  [[ ! -f "$_APT_LOG" ]]
}

@test "ospkg__cleanup_session_build_groups: empty session dir prints informational message" {
  _seed_session_cleanup_context

  run ospkg__cleanup_session_build_groups "false"

  assert_success
  assert_output --partial "no packages to remove"
}

@test "ospkg__cleanup_session_build_groups: pre-existing package in initial snapshot is not tracked" {
  # ospkg__install_tracked excludes packages in _SYSSET_INITIAL_SNAPSHOT;
  # therefore the session sidecar should never contain them. This test confirms
  # that if a sidecar somehow contains a package name, the coordinator still
  # processes it (defense-in-depth). But the main path: _install_tracked + initial
  # snapshot → package absent from sidecar → nothing to remove.
  _seed_session_cleanup_context
  # Session dir is empty because ospkg__install_tracked filtered pre-existing.
  # Cleanup should report "no packages to remove".

  run ospkg__cleanup_session_build_groups "false"
  assert_success
  assert_output --partial "no packages to remove"
}

# ---------------------------------------------------------------------------
# ospkg__track_resource / ospkg__cleanup_resources
# ---------------------------------------------------------------------------

@test "ospkg__track_resource: writes path to local resource sidecar" {
  reload_lib
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"
  unset _SYSSET_SESSION_TRACK_DIR

  ospkg__track_resource "test-group" "/tmp/some_file_xyz"

  local _sidecar="${BATS_TEST_TMPDIR}/ospkg/resources/test-group"
  assert_file_exists "$_sidecar"
  grep -q "^/tmp/some_file_xyz$" "$_sidecar"
}

@test "ospkg__track_resource: multiple paths written in order" {
  reload_lib
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"
  unset _SYSSET_SESSION_TRACK_DIR

  ospkg__track_resource "test-group" "/a/path1" "/b/path2" "/c/path3"

  local _sidecar="${BATS_TEST_TMPDIR}/ospkg/resources/test-group"
  grep -q "^/a/path1$" "$_sidecar"
  grep -q "^/b/path2$" "$_sidecar"
  grep -q "^/c/path3$" "$_sidecar"
}

@test "ospkg__track_resource: also mirrors to session resources dir when session dir set" {
  reload_lib
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"
  local _session_dir
  _session_dir="$(mktemp -d "${BATS_TEST_TMPDIR}/session_XXXXXX")"
  export _SYSSET_SESSION_TRACK_DIR="$_session_dir"

  ospkg__track_resource "test-group" "/tmp/mirror_test"

  # Local sidecar
  local _local="${BATS_TEST_TMPDIR}/ospkg/resources/test-group"
  assert_file_exists "$_local"
  grep -q "^/tmp/mirror_test$" "$_local"

  # Session mirror
  local _sess="${_session_dir}/resources/test-group"
  assert_file_exists "$_sess"
  grep -q "^/tmp/mirror_test$" "$_sess"
}

@test "ospkg__track_resource: no session mirror when session dir does not exist" {
  reload_lib
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"
  export _SYSSET_SESSION_TRACK_DIR="${BATS_TEST_TMPDIR}/no_such_session_xyz"

  # Must not fail even if session dir is missing.
  run ospkg__track_resource "test-group" "/tmp/no_mirror"
  assert_success

  # Session resources dir must not have been created.
  [[ ! -d "${BATS_TEST_TMPDIR}/no_such_session_xyz/resources" ]]
}

@test "ospkg__cleanup_resources: removes tracked files" {
  reload_lib
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"

  # Create real files to be removed.
  local _f1="${BATS_TEST_TMPDIR}/tracked_file_a"
  local _f2="${BATS_TEST_TMPDIR}/tracked_file_b"
  touch "$_f1" "$_f2"
  ospkg__track_resource "cleanup-group" "$_f1" "$_f2"

  ospkg__cleanup_resources

  [[ ! -e "$_f1" ]]
  [[ ! -e "$_f2" ]]
}

@test "ospkg__cleanup_resources: sidecar is deleted after processing" {
  reload_lib
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"

  local _f="${BATS_TEST_TMPDIR}/tracked_file_c"
  touch "$_f"
  ospkg__track_resource "cleanup-group2" "$_f"

  local _sidecar="${BATS_TEST_TMPDIR}/ospkg/resources/cleanup-group2"
  assert_file_exists "$_sidecar"

  ospkg__cleanup_resources

  [[ ! -f "$_sidecar" ]]
}

@test "ospkg__cleanup_resources: non-existent path does not cause failure" {
  reload_lib
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"

  # Register a path that does not exist.
  local _res_dir="${BATS_TEST_TMPDIR}/ospkg/resources"
  mkdir -p "$_res_dir"
  printf '/tmp/definitely_does_not_exist_xyz123\n' > "${_res_dir}/ghost-group"

  run ospkg__cleanup_resources
  assert_success
}

@test "ospkg__cleanup_resources: no-ops when resources dir is absent" {
  reload_lib
  # Point _FILE__SESSION_ROOT to a dir with no ospkg/resources subdir.
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}/empty_root"
  mkdir -p "$_FILE__SESSION_ROOT"

  run ospkg__cleanup_resources
  assert_success
}

# ===========================================================================
# Additional context helpers (non-APT package managers)
# ===========================================================================

# _seed_pacman_context — pacman build context with fully-detected state.
_seed_pacman_context() {
  reload_lib
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"
  _OSPKG__DETECTED=true
  _OSPKG__PKG_MNGR="pacman"
  _OSPKG__FAMILY="pacman"
  _OSPKG__INSTALL=(pacman -S --noconfirm)
  _OSPKG__UPDATE=(pacman -Sy)
  _OSPKG__CLEAN="_ospkg__clean_pacman"
  ctx__set plat.pm=pacman plat.machine_release=amd64 os.id=arch plat.kernel=linux
  _CTX__REGISTRY_INITIALIZED=true
  users__run_privileged() { "$@"; }
  export -f users__run_privileged
  _stub_ospkg_privilege_ok
}

# _seed_apk_context — Alpine APK build context with fully-detected state.
_seed_apk_context() {
  reload_lib
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"
  _OSPKG__DETECTED=true
  _OSPKG__PKG_MNGR="apk"
  _OSPKG__FAMILY="apk"
  _OSPKG__INSTALL=(apk add --no-cache)
  _OSPKG__UPDATE=()
  _OSPKG__CLEAN="_ospkg__clean_apk"
  ctx__set plat.pm=apk plat.machine_release=amd64 os.id=alpine plat.kernel=linux
  _CTX__REGISTRY_INITIALIZED=true
  users__run_privileged() { "$@"; }
  export -f users__run_privileged
}

# _seed_yum_context — yum (not dnf) build context; tests the dnf→$PM fix.
_seed_yum_context() {
  reload_lib
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"
  _OSPKG__DETECTED=true
  _OSPKG__PKG_MNGR="yum"
  _OSPKG__FAMILY="dnf"
  _OSPKG__INSTALL=(yum -y install)
  _OSPKG__UPDATE=(yum check-update)
  _OSPKG__CLEAN="_ospkg__clean_dnf"
  ctx__set plat.pm=dnf plat.machine_release=amd64 os.id=rhel plat.kernel=linux
  _CTX__REGISTRY_INITIALIZED=true
  users__run_privileged() { "$@"; }
  export -f users__run_privileged
}

# _seed_apk_build_context — APK context + tracked apk fake.
# The fake apk handles:
#   info -e <pkg>  — returns 0 if <pkg> is listed in apk-installed.txt, else 1.
#   anything else  — logs args to apk.log and returns 0.
# Seed pre-installed packages by writing one package per line to
#   "${BATS_TEST_TMPDIR}/apk-installed.txt" before calling the function.
_seed_apk_build_context() {
  _seed_apk_context
  export _SYSSET_BUILD_CONTEXT="ctx"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  local _installed="${BATS_TEST_TMPDIR}/apk-installed.txt"
  local _log="${BATS_TEST_TMPDIR}/apk.log"
  printf '#!/bin/bash\n' > "${BATS_TEST_TMPDIR}/bin/apk"
  printf 'if [[ "$1" == "info" && "$2" == "-e" ]]; then\n' >> "${BATS_TEST_TMPDIR}/bin/apk"
  printf '  [[ -f "%s" ]] && grep -qxF "$3" "%s"\n' "$_installed" "$_installed" >> "${BATS_TEST_TMPDIR}/bin/apk"
  printf 'else\n' >> "${BATS_TEST_TMPDIR}/bin/apk"
  printf '  echo "$@" >> "%s"\n' "$_log" >> "${BATS_TEST_TMPDIR}/bin/apk"
  printf 'fi\n' >> "${BATS_TEST_TMPDIR}/bin/apk"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apk"
  prepend_fake_bin_path
}

# _seed_pacman_build_context — Pacman context + smart pacman fake.
# Fake pacman behaviour is controlled by env files:
#   ${BATS_TEST_TMPDIR}/pacman-asdeps.txt   — output of pacman -Qq --deps
#   ${BATS_TEST_TMPDIR}/pacman-installed.txt — output of pacman -Qq
#   ${BATS_TEST_TMPDIR}/pacman-orphans.txt  — output of pacman -Qdtq
# All other invocations log to ${BATS_TEST_TMPDIR}/pacman.log.
_seed_pacman_build_context() {
  _seed_pacman_context
  export _SYSSET_BUILD_CONTEXT="ctx"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  local _asdeps="${BATS_TEST_TMPDIR}/pacman-asdeps.txt"
  local _installed="${BATS_TEST_TMPDIR}/pacman-installed.txt"
  local _orphans="${BATS_TEST_TMPDIR}/pacman-orphans.txt"
  local _log="${BATS_TEST_TMPDIR}/pacman.log"
  # Use if/elif chain so arg-order doesn't matter.
  printf '#!/bin/bash\n' > "${BATS_TEST_TMPDIR}/bin/pacman"
  printf 'args="$*"\n' >> "${BATS_TEST_TMPDIR}/bin/pacman"
  printf 'if [[ "$args" == *"-Qq --deps"* ]] || [[ "$args" == *"--deps"* && "$args" == *"-Qq"* ]]; then\n' >> "${BATS_TEST_TMPDIR}/bin/pacman"
  printf '  cat "%s" 2>/dev/null\n' "$_asdeps" >> "${BATS_TEST_TMPDIR}/bin/pacman"
  printf 'elif [[ "$args" == *"-Qdtq"* ]]; then\n' >> "${BATS_TEST_TMPDIR}/bin/pacman"
  printf '  cat "%s" 2>/dev/null\n' "$_orphans" >> "${BATS_TEST_TMPDIR}/bin/pacman"
  printf 'elif [[ "$args" == *"-Qq"* ]]; then\n' >> "${BATS_TEST_TMPDIR}/bin/pacman"
  printf '  cat "%s" 2>/dev/null\n' "$_installed" >> "${BATS_TEST_TMPDIR}/bin/pacman"
  printf 'else\n' >> "${BATS_TEST_TMPDIR}/bin/pacman"
  printf '  echo "$args" >> "%s"\n' "$_log" >> "${BATS_TEST_TMPDIR}/bin/pacman"
  printf 'fi\n' >> "${BATS_TEST_TMPDIR}/bin/pacman"
  chmod +x "${BATS_TEST_TMPDIR}/bin/pacman"
  prepend_fake_bin_path
}

# _create_smart_apt_mark — replaces the simple logging apt-mark with one that:
#   'showauto' → reads lines from ${BATS_TEST_TMPDIR}/apt-showauto.txt
#   anything else → logs "subcommand arg1..." to apt-mark.log
_create_smart_apt_mark() {
  local _showauto="${BATS_TEST_TMPDIR}/apt-showauto.txt"
  local _log="${BATS_TEST_TMPDIR}/apt-mark.log"
  printf '#!/bin/bash\n[[ "$1" == "showauto" ]] && { cat "%s" 2>/dev/null; exit 0; }\necho "$*" >> "%s"\n' \
    "$_showauto" "$_log" > "${BATS_TEST_TMPDIR}/bin/apt-mark"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-mark"
}

# _create_smart_rpm — fake rpm -qa that reads from ${BATS_TEST_TMPDIR}/rpm-installed.txt.
_create_smart_rpm() {
  local _installed="${BATS_TEST_TMPDIR}/rpm-installed.txt"
  printf '#!/bin/bash\ncat "%s" 2>/dev/null\n' "$_installed" \
    > "${BATS_TEST_TMPDIR}/bin/rpm"
  chmod +x "${BATS_TEST_TMPDIR}/bin/rpm"
}

# ---------------------------------------------------------------------------
# _ospkg__apk_virtual_name / _ospkg__apk_virts_file
# ---------------------------------------------------------------------------

@test "_ospkg__apk_virtual_name: sanitizes slashes and colons to hyphens, lowercases, prefixes .df-" {
  reload_lib
  local _result
  _result="$(_ospkg__apk_virtual_name "Ctx::Group/Sub")"
  # Uppercase → lowercase, :: → --, / → -
  [[ "$_result" == ".df-"* ]]
  [[ "$_result" == *"ctx"* ]]
  [[ ! "$_result" == *":"* ]]
  [[ ! "$_result" == *"/"* ]]
}

@test "_ospkg__apk_virtual_name: preserves valid chars (alphanumeric and hyphen)" {
  reload_lib
  local _result
  _result="$(_ospkg__apk_virtual_name "my-group-123")"
  [[ "$_result" == ".df-my-group-123" ]]
}

@test "_ospkg__apk_virtual_name: spaces and special chars become hyphens" {
  reload_lib
  local _result
  _result="$(_ospkg__apk_virtual_name "my group@pkg")"
  [[ ! "$_result" == *" "* ]]
  [[ ! "$_result" == *"@"* ]]
}

@test "_ospkg__apk_virts_file: appends .apkvirts suffix to sidecar path" {
  reload_lib
  local _result
  _result="$(_ospkg__apk_virts_file "/tmp/build-deps/my-group")"
  [[ "$_result" == "/tmp/build-deps/my-group.apkvirts" ]]
}

# ---------------------------------------------------------------------------
# _ospkg__ensure_global_auto_snapshot
# ---------------------------------------------------------------------------

@test "_ospkg__ensure_global_auto_snapshot: APT — creates .global_auto_before with sorted auto packages" {
  _seed_apt_build_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  # apt-mark showauto returns 'wget libz1' (unsorted)
  printf 'wget\nlibz1\n' > "${BATS_TEST_TMPDIR}/apt-showauto.txt"
  _create_smart_apt_mark
  prepend_fake_bin_path

  _ospkg__ensure_global_auto_snapshot

  local _snap
  _snap="${BATS_TEST_TMPDIR}/ospkg/build-deps/.global_auto_before"
  assert_file_exists "$_snap"
  grep -q "^libz1$" "$_snap"
  grep -q "^wget$" "$_snap"
}

@test "_ospkg__ensure_global_auto_snapshot: APT — calls apt-mark manual for all snapshotted packages" {
  _seed_apt_build_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf 'libz1\nwget\n' > "${BATS_TEST_TMPDIR}/apt-showauto.txt"
  _create_smart_apt_mark
  prepend_fake_bin_path

  _ospkg__ensure_global_auto_snapshot

  assert_file_exists "${BATS_TEST_TMPDIR}/apt-mark.log"
  grep -q "manual" "${BATS_TEST_TMPDIR}/apt-mark.log"
  grep -q "libz1" "${BATS_TEST_TMPDIR}/apt-mark.log"
  grep -q "wget" "${BATS_TEST_TMPDIR}/apt-mark.log"
}

@test "_ospkg__ensure_global_auto_snapshot: APT — idempotent; second call is a no-op if snapshot exists" {
  _seed_apt_build_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf 'wget\n' > "${BATS_TEST_TMPDIR}/apt-showauto.txt"
  _create_smart_apt_mark
  prepend_fake_bin_path

  _ospkg__ensure_global_auto_snapshot
  # Remove the log so we can check the second call doesn't log again.
  rm -f "${BATS_TEST_TMPDIR}/apt-mark.log"

  _ospkg__ensure_global_auto_snapshot

  # No apt-mark calls on second invocation.
  [[ ! -f "${BATS_TEST_TMPDIR}/apt-mark.log" ]]
}

@test "_ospkg__ensure_global_auto_snapshot: APT — empty auto list creates empty sentinel; no apt-mark manual call" {
  _seed_apt_build_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  # showauto returns nothing
  : > "${BATS_TEST_TMPDIR}/apt-showauto.txt"
  _create_smart_apt_mark
  prepend_fake_bin_path

  _ospkg__ensure_global_auto_snapshot

  local _snap="${BATS_TEST_TMPDIR}/ospkg/build-deps/.global_auto_before"
  assert_file_exists "$_snap"
  [[ ! -s "$_snap" ]]
  # No 'manual' call for empty list.
  [[ ! -f "${BATS_TEST_TMPDIR}/apt-mark.log" ]] ||
    ! grep -q "manual" "${BATS_TEST_TMPDIR}/apt-mark.log"
}

@test "_ospkg__ensure_global_auto_snapshot: APK — creates empty sentinel (no virtual tracking needed)" {
  _seed_apk_build_context

  _ospkg__ensure_global_auto_snapshot

  local _snap="${BATS_TEST_TMPDIR}/ospkg/build-deps/.global_auto_before"
  assert_file_exists "$_snap"
  [[ ! -s "$_snap" ]]
}

@test "_ospkg__ensure_global_auto_snapshot: pacman — snapshots asdeps packages and marks them asexplicit" {
  _seed_pacman_build_context
  printf 'makedep1\nmakedep2\n' > "${BATS_TEST_TMPDIR}/pacman-asdeps.txt"

  _ospkg__ensure_global_auto_snapshot

  local _snap="${BATS_TEST_TMPDIR}/ospkg/build-deps/.global_auto_before"
  assert_file_exists "$_snap"
  grep -q "^makedep1$" "$_snap"
  grep -q "^makedep2$" "$_snap"
  # pacman -D --asexplicit should have been called
  assert_file_exists "${BATS_TEST_TMPDIR}/pacman.log"
  grep -q "\-\-asexplicit" "${BATS_TEST_TMPDIR}/pacman.log"
  grep -q "makedep1" "${BATS_TEST_TMPDIR}/pacman.log"
}

@test "_ospkg__ensure_global_auto_snapshot: pacman — empty asdeps creates empty sentinel; no pacman -D call" {
  _seed_pacman_build_context
  : > "${BATS_TEST_TMPDIR}/pacman-asdeps.txt"

  _ospkg__ensure_global_auto_snapshot

  local _snap="${BATS_TEST_TMPDIR}/ospkg/build-deps/.global_auto_before"
  assert_file_exists "$_snap"
  [[ ! -s "$_snap" ]]
  [[ ! -f "${BATS_TEST_TMPDIR}/pacman.log" ]]
}

@test "_ospkg__ensure_global_auto_snapshot: yum — uses yum (not dnf) for userinstalled query" {
  _seed_yum_context
  export _SYSSET_BUILD_CONTEXT="ctx"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  # rpm returns two packages; yum history userinstalled returns one → comm -23 yields the dep.
  _create_smart_rpm
  printf 'basepkg\ndepdpkg\n' | sort > "${BATS_TEST_TMPDIR}/rpm-installed.txt"
  local _yum_log="${BATS_TEST_TMPDIR}/yum.log"
  # fake yum: userinstalled → print basepkg; mark → log
  printf '#!/bin/bash\nif [[ "$*" == *"userinstalled"* ]]; then printf "basepkg\n"; else echo "$*" >> "%s"; fi\n' \
    "$_yum_log" > "${BATS_TEST_TMPDIR}/bin/yum"
  chmod +x "${BATS_TEST_TMPDIR}/bin/yum"
  prepend_fake_bin_path

  _ospkg__ensure_global_auto_snapshot

  local _snap="${BATS_TEST_TMPDIR}/ospkg/build-deps/.global_auto_before"
  assert_file_exists "$_snap"
  # depdpkg is in rpm but not in userinstalled → should be in snap
  grep -q "^depdpkg$" "$_snap"
  # yum (not dnf!) must be used for mark install
  assert_file_exists "$_yum_log"
  grep -q "mark install" "$_yum_log"
  grep -q "depdpkg" "$_yum_log"
  # dnf must NOT appear in the log (would indicate wrong binary was called)
  run grep -q "^dnf " "$_yum_log"
  assert_failure
}

# ---------------------------------------------------------------------------
# _ospkg__restore_global_auto_state
# ---------------------------------------------------------------------------

@test "_ospkg__restore_global_auto_state: no-op when snapshot file does not exist" {
  _seed_apt_build_context
  # Ensure no snapshot file exists
  rm -f "${BATS_TEST_TMPDIR}/ospkg/build-deps/.global_auto_before"

  run _ospkg__restore_global_auto_state
  assert_success
  # No apt-mark log should exist
  [[ ! -f "${BATS_TEST_TMPDIR}/apt-mark.log" ]]
}

@test "_ospkg__restore_global_auto_state: APT — marks still-installed packages as auto and deletes snapshot" {
  _seed_apt_build_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  # Snapshot: libz1 and wget were auto before
  printf 'libz1\nwget\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/.global_auto_before"
  # dpkg-query: both are still installed
  printf '#!/bin/bash\nprintf "libz1\nwget\n"\n' > "${BATS_TEST_TMPDIR}/bin/dpkg-query"
  chmod +x "${BATS_TEST_TMPDIR}/bin/dpkg-query"
  _create_smart_apt_mark
  prepend_fake_bin_path

  _ospkg__restore_global_auto_state

  # Snapshot file must be deleted
  [[ ! -f "${BATS_TEST_TMPDIR}/ospkg/build-deps/.global_auto_before" ]]
  # apt-mark auto called with both packages
  assert_file_exists "${BATS_TEST_TMPDIR}/apt-mark.log"
  grep -q "auto" "${BATS_TEST_TMPDIR}/apt-mark.log"
  grep -q "libz1" "${BATS_TEST_TMPDIR}/apt-mark.log"
  grep -q "wget" "${BATS_TEST_TMPDIR}/apt-mark.log"
}

@test "_ospkg__restore_global_auto_state: APT — packages removed during build are excluded (intersection)" {
  _seed_apt_build_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  # Snapshot: libz1 and wget; after build wget was removed as a build dep
  printf 'libz1\nwget\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/.global_auto_before"
  # dpkg-query: only libz1 remains installed (wget was cleaned up)
  printf '#!/bin/bash\nprintf "libz1\n"\n' > "${BATS_TEST_TMPDIR}/bin/dpkg-query"
  chmod +x "${BATS_TEST_TMPDIR}/bin/dpkg-query"
  _create_smart_apt_mark
  prepend_fake_bin_path

  _ospkg__restore_global_auto_state

  # Only libz1 should be in the apt-mark auto call, not wget
  assert_file_exists "${BATS_TEST_TMPDIR}/apt-mark.log"
  grep -q "libz1" "${BATS_TEST_TMPDIR}/apt-mark.log"
  run grep -q "wget" "${BATS_TEST_TMPDIR}/apt-mark.log"
  assert_failure
}

@test "_ospkg__restore_global_auto_state: APT — empty snapshot deletes file but calls no apt-mark" {
  _seed_apt_build_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  # Empty snapshot (was created by unsupported PM sentinel path)
  : > "${BATS_TEST_TMPDIR}/ospkg/build-deps/.global_auto_before"
  _create_smart_apt_mark
  prepend_fake_bin_path

  _ospkg__restore_global_auto_state

  [[ ! -f "${BATS_TEST_TMPDIR}/ospkg/build-deps/.global_auto_before" ]]
  [[ ! -f "${BATS_TEST_TMPDIR}/apt-mark.log" ]]
}

@test "_ospkg__restore_global_auto_state: pacman — marks still-installed packages as --asdeps and deletes snapshot" {
  _seed_pacman_build_context
  mkdir -p "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  printf 'makedep1\nmakedep2\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/.global_auto_before"
  # pacman -Qq returns both still installed
  printf 'makedep1\nmakedep2\nuserpkg\n' > "${BATS_TEST_TMPDIR}/pacman-installed.txt"

  _ospkg__restore_global_auto_state

  [[ ! -f "${BATS_TEST_TMPDIR}/ospkg/build-deps/.global_auto_before" ]]
  assert_file_exists "${BATS_TEST_TMPDIR}/pacman.log"
  grep -q "\-\-asdeps" "${BATS_TEST_TMPDIR}/pacman.log"
  grep -q "makedep1" "${BATS_TEST_TMPDIR}/pacman.log"
  grep -q "makedep2" "${BATS_TEST_TMPDIR}/pacman.log"
}

# ---------------------------------------------------------------------------
# _ospkg__protect_user_pkgs  (includes yum fix verification)
# ---------------------------------------------------------------------------

@test "_ospkg__protect_user_pkgs: APT — calls apt-mark manual for each package" {
  _seed_apt_build_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  _create_smart_apt_mark
  prepend_fake_bin_path

  _ospkg__protect_user_pkgs curl git

  assert_file_exists "${BATS_TEST_TMPDIR}/apt-mark.log"
  grep -q "manual" "${BATS_TEST_TMPDIR}/apt-mark.log"
  grep -q "curl" "${BATS_TEST_TMPDIR}/apt-mark.log"
  grep -q "git" "${BATS_TEST_TMPDIR}/apt-mark.log"
}

@test "_ospkg__protect_user_pkgs: yum — uses yum (not hardcoded dnf) for mark install" {
  _seed_yum_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  local _yum_log="${BATS_TEST_TMPDIR}/yum.log"
  printf '#!/bin/bash\necho "$@" >> "%s"\n' "$_yum_log" \
    > "${BATS_TEST_TMPDIR}/bin/yum"
  chmod +x "${BATS_TEST_TMPDIR}/bin/yum"
  # Ensure dnf is NOT present (would mask the bug)
  rm -f "${BATS_TEST_TMPDIR}/bin/dnf"
  prepend_fake_bin_path

  _ospkg__protect_user_pkgs mypkg

  assert_file_exists "$_yum_log"
  grep -q "mark install" "$_yum_log"
  grep -q "mypkg" "$_yum_log"
}

@test "_ospkg__protect_user_pkgs: pacman — calls pacman -D --asexplicit" {
  _seed_pacman_build_context

  _ospkg__protect_user_pkgs mypkg

  assert_file_exists "${BATS_TEST_TMPDIR}/pacman.log"
  grep -q "\-D.*\-\-asexplicit\|--asexplicit.*-D" "${BATS_TEST_TMPDIR}/pacman.log"
  grep -q "mypkg" "${BATS_TEST_TMPDIR}/pacman.log"
}

@test "_ospkg__protect_user_pkgs: evicts package from build-group sidecar" {
  _seed_apt_build_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  _create_smart_apt_mark
  prepend_fake_bin_path
  # Pre-existing sidecar contains curl and git
  printf 'curl\ngit\nnewpkg\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/ctx::my-group"

  _ospkg__protect_user_pkgs curl

  # curl must be removed from sidecar, git and newpkg must remain
  local _sidecar="${BATS_TEST_TMPDIR}/ospkg/build-deps/ctx::my-group"
  run grep "^curl$" "$_sidecar"
  assert_failure
  grep -q "^git$" "$_sidecar"
  grep -q "^newpkg$" "$_sidecar"
}

@test "_ospkg__protect_user_pkgs: skips .before, .after, .apkvirts, .global_auto_before files in sidecar scan" {
  _seed_apt_build_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  _create_smart_apt_mark
  prepend_fake_bin_path
  # Create the special files that must be skipped
  printf 'curl\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/group.before"
  printf 'curl\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/group.after"
  printf '.df-ctx-group-0\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/group.apkvirts"
  printf 'curl\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/.global_auto_before"
  printf 'curl\nnewpkg\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/real-group"

  _ospkg__protect_user_pkgs curl

  # Special files must be untouched (content unchanged)
  grep -q "^curl$" "${BATS_TEST_TMPDIR}/ospkg/build-deps/group.before"
  grep -q "^curl$" "${BATS_TEST_TMPDIR}/ospkg/build-deps/group.after"
  grep -q "^curl$" "${BATS_TEST_TMPDIR}/ospkg/build-deps/.global_auto_before"
  # curl only evicted from the real sidecar
  run grep "^curl$" "${BATS_TEST_TMPDIR}/ospkg/build-deps/real-group"
  assert_failure
  grep -q "^newpkg$" "${BATS_TEST_TMPDIR}/ospkg/build-deps/real-group"
}

@test "_ospkg__protect_user_pkgs: no-op when no build-deps directory exists" {
  _seed_apt_build_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  _create_smart_apt_mark
  prepend_fake_bin_path
  # No ospkg/build-deps dir exists at all.

  run _ospkg__protect_user_pkgs curl
  assert_success
}

@test "_ospkg__protect_user_pkgs: no-op when called with no arguments" {
  _seed_apt_build_context
  run _ospkg__protect_user_pkgs
  assert_success
}

# ---------------------------------------------------------------------------
# _ospkg__mark_build_group — yum uses $_OSPKG__PKG_MNGR (not hardcoded dnf)
# ---------------------------------------------------------------------------

@test "_ospkg__mark_build_group: yum — uses yum (not hardcoded dnf) for mark remove" {
  _seed_yum_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  _create_smart_rpm
  printf 'basepkg\n' | sort > "${BATS_TEST_TMPDIR}/rpm-installed.txt"
  local _yum_log="${BATS_TEST_TMPDIR}/yum.log"
  printf '#!/bin/bash\necho "$@" >> "%s"\n' "$_yum_log" \
    > "${BATS_TEST_TMPDIR}/bin/yum"
  chmod +x "${BATS_TEST_TMPDIR}/bin/yum"
  rm -f "${BATS_TEST_TMPDIR}/bin/dnf"
  prepend_fake_bin_path

  # Simulate before-snapshot with basepkg; after-snapshot adds newpkg.
  local _before="${BATS_TEST_TMPDIR}/ospkg/build-deps/test-group.before"
  printf 'basepkg\n' > "$_before"
  # Snapshot after: basepkg + newpkg
  printf 'basepkg\nnewpkg\n' | sort > "${BATS_TEST_TMPDIR}/rpm-installed.txt"
  _ospkg__snapshot_packages() {
    local _dest="$1"
    printf 'basepkg\nnewpkg\n' | sort > "$_dest"
  }

  _ospkg__mark_build_group "test-group" "$_before"

  # yum mark remove must have been called (not dnf)
  assert_file_exists "$_yum_log"
  grep -q "mark remove" "$_yum_log"
  grep -q "newpkg" "$_yum_log"
  # dnf must not appear as the command (would indicate hardcoded-dnf bug)
  run grep "^dnf " "$_yum_log"
  assert_failure
}

# ---------------------------------------------------------------------------
# _ospkg__remove_build_group — APK virtual-group removal
# ---------------------------------------------------------------------------

@test "_ospkg__remove_build_group: apk — reads .apkvirts and calls apk del for each virtual" {
  _seed_apk_build_context
  mkdir -p "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  # Sidecar with bare package names (human-readable)
  printf 'cmake\nninja\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/test-group"
  # .apkvirts file with the virtual group names created at install time
  printf '.df-ctx-test-group-0\n.df-ctx-test-group-1\n' \
    > "${BATS_TEST_TMPDIR}/ospkg/build-deps/test-group.apkvirts"

  _ospkg__remove_build_group "test-group"

  # apk del must have been called for each virtual (not for the bare package names)
  assert_file_exists "${BATS_TEST_TMPDIR}/apk.log"
  grep -q "del.*\.df-ctx-test-group-0" "${BATS_TEST_TMPDIR}/apk.log"
  grep -q "del.*\.df-ctx-test-group-1" "${BATS_TEST_TMPDIR}/apk.log"
}

@test "_ospkg__remove_build_group: apk — deletes .apkvirts file after removal" {
  _seed_apk_build_context
  mkdir -p "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  printf 'cmake\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/test-group"
  printf '.df-ctx-test-group-0\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/test-group.apkvirts"

  _ospkg__remove_build_group "test-group"

  [[ ! -f "${BATS_TEST_TMPDIR}/ospkg/build-deps/test-group.apkvirts" ]]
}

@test "_ospkg__remove_build_group: apk — fallback to per-package del when no .apkvirts file exists" {
  _seed_apk_build_context
  mkdir -p "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  printf 'cmake\nninja\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/test-group"
  # No .apkvirts file — simulate older sidecar from before virtual tracking

  _ospkg__remove_build_group "test-group"

  assert_file_exists "${BATS_TEST_TMPDIR}/apk.log"
  grep -q "del.*cmake" "${BATS_TEST_TMPDIR}/apk.log"
  grep -q "del.*ninja" "${BATS_TEST_TMPDIR}/apk.log"
}

@test "_ospkg__remove_build_group: apk — no .apkvirts del calls without actual virtual names" {
  # Ensure the virtual-path never passes bare package names to apk del
  # (it would fail since bare pkgs are owned by a virtual).
  _seed_apk_build_context
  mkdir -p "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  printf 'cmake\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/test-group"
  printf '.df-ctx-test-group-0\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/test-group.apkvirts"

  _ospkg__remove_build_group "test-group"

  # 'cmake' must NOT appear in the apk del call — only the virtual name should.
  run grep "del.*cmake" "${BATS_TEST_TMPDIR}/apk.log"
  assert_failure
}

# ---------------------------------------------------------------------------
# _ospkg__remove_build_group — Pacman orphan-based removal
# ---------------------------------------------------------------------------

@test "_ospkg__remove_build_group: pacman — calls pacman -Qdtq and then -Rns for orphans" {
  _seed_pacman_build_context
  mkdir -p "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  printf 'cmake\nninja\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/test-group"
  # pacman -Qdtq returns cmake and ninja as orphaned
  printf 'cmake\nninja\n' > "${BATS_TEST_TMPDIR}/pacman-orphans.txt"

  _ospkg__remove_build_group "test-group"

  assert_file_exists "${BATS_TEST_TMPDIR}/pacman.log"
  grep -q "\-Rns\|\-\-noconfirm" "${BATS_TEST_TMPDIR}/pacman.log"
  grep -q "cmake" "${BATS_TEST_TMPDIR}/pacman.log"
  grep -q "ninja" "${BATS_TEST_TMPDIR}/pacman.log"
}

@test "_ospkg__remove_build_group: pacman — no-op when pacman -Qdtq returns no orphans" {
  _seed_pacman_build_context
  mkdir -p "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  printf 'cmake\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/test-group"
  # No orphans (user package depends on cmake)
  : > "${BATS_TEST_TMPDIR}/pacman-orphans.txt"

  _ospkg__remove_build_group "test-group"

  # No -Rns call should have been made
  [[ ! -f "${BATS_TEST_TMPDIR}/pacman.log" ]] ||
    ! grep -q "\-Rns" "${BATS_TEST_TMPDIR}/pacman.log"
}

# ---------------------------------------------------------------------------
# _ospkg__remove_build_group — DNF/YUM autoremove uses $_OSPKG__PKG_MNGR
# ---------------------------------------------------------------------------

@test "_ospkg__remove_build_group: yum — calls yum -y autoremove (not hardcoded dnf)" {
  _seed_yum_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  printf 'cmake\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/test-group"
  local _yum_log="${BATS_TEST_TMPDIR}/yum.log"
  printf '#!/bin/bash\necho "$@" >> "%s"\n' "$_yum_log" \
    > "${BATS_TEST_TMPDIR}/bin/yum"
  chmod +x "${BATS_TEST_TMPDIR}/bin/yum"
  rm -f "${BATS_TEST_TMPDIR}/bin/dnf"
  prepend_fake_bin_path

  _ospkg__remove_build_group "test-group"

  assert_file_exists "$_yum_log"
  grep -q "autoremove" "$_yum_log"
  run grep "^dnf" "$_yum_log"
  assert_failure
}

# ---------------------------------------------------------------------------
# ospkg__cleanup_all_build_groups — skip filter additions
# ---------------------------------------------------------------------------

@test "ospkg__cleanup_all_build_groups: .apkvirts files are skipped" {
  _seed_apt_context
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"
  mkdir -p "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  # A real sidecar and an .apkvirts auxiliary file
  printf 'cmake\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/my-group"
  printf '.df-ctx-my-group-0\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/my-group.apkvirts"
  create_fake_bin "apt-get" ""
  prepend_fake_bin_path

  ospkg__cleanup_all_build_groups

  # The .apkvirts file must not have been processed as a group sidecar (it should
  # remain if the group sidecar was deleted by normal processing).
  # The real sidecar must be gone.
  [[ ! -f "${BATS_TEST_TMPDIR}/ospkg/build-deps/my-group" ]]
}

@test "ospkg__cleanup_all_build_groups: .global_auto_before (dotfile) is not processed as a group" {
  _seed_apt_context
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"
  mkdir -p "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  # Create the global auto snapshot file
  printf 'libz1\nwget\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/.global_auto_before"
  # Also create a real sidecar to ensure cleanup still runs
  printf 'cmake\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/real-group"
  create_fake_bin "apt-get" ""
  # Need apt-mark for restore: use simple no-op fake
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  create_fake_bin "apt-mark" ""
  printf '#!/bin/bash\nprintf "libz1\nwget\n"\n' > "${BATS_TEST_TMPDIR}/bin/dpkg-query"
  chmod +x "${BATS_TEST_TMPDIR}/bin/dpkg-query"
  prepend_fake_bin_path

  ospkg__cleanup_all_build_groups

  # .global_auto_before should be deleted by _ospkg__restore_global_auto_state (called at end)
  # but must NOT be processed as a build group sidecar.
  # The real group sidecar must be gone.
  [[ ! -f "${BATS_TEST_TMPDIR}/ospkg/build-deps/real-group" ]]
}

@test "ospkg__cleanup_all_build_groups: calls _ospkg__restore_global_auto_state after all groups" {
  _seed_apt_build_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  # Place a global snapshot file to verify restore is called (it will be deleted)
  printf 'libz1\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/.global_auto_before"
  printf 'cmake\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/real-group"
  # apt-get for autoremove
  printf '#!/bin/bash\nexit 0\n' > "${BATS_TEST_TMPDIR}/bin/apt-get"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-get"
  # dpkg-query for restore intersection
  printf '#!/bin/bash\nprintf "libz1\n"\n' > "${BATS_TEST_TMPDIR}/bin/dpkg-query"
  chmod +x "${BATS_TEST_TMPDIR}/bin/dpkg-query"
  _create_smart_apt_mark
  prepend_fake_bin_path

  ospkg__cleanup_all_build_groups

  # Snapshot file must be gone (deleted by _ospkg__restore_global_auto_state)
  [[ ! -f "${BATS_TEST_TMPDIR}/ospkg/build-deps/.global_auto_before" ]]
  # apt-mark auto must have been called to restore libz1
  assert_file_exists "${BATS_TEST_TMPDIR}/apt-mark.log"
  grep -q "auto" "${BATS_TEST_TMPDIR}/apt-mark.log"
  grep -q "libz1" "${BATS_TEST_TMPDIR}/apt-mark.log"
}

# ---------------------------------------------------------------------------
# ospkg__install_tracked — APK virtual-group path
# ---------------------------------------------------------------------------

@test "ospkg__install_tracked: apk — creates virtual group with .df- prefixed name" {
  _seed_apk_build_context

  ospkg__install_tracked "lib-build" cmake ninja

  # apk add --virtual .df-ctx-lib-build-0 cmake ninja
  assert_file_exists "${BATS_TEST_TMPDIR}/apk.log"
  grep -q "add.*--virtual.*\.df-.*lib-build" "${BATS_TEST_TMPDIR}/apk.log"
  grep -q "cmake" "${BATS_TEST_TMPDIR}/apk.log"
  grep -q "ninja" "${BATS_TEST_TMPDIR}/apk.log"
}

@test "ospkg__install_tracked: apk — writes virtual name to .apkvirts file" {
  _seed_apk_build_context

  ospkg__install_tracked "lib-build" cmake

  local _bd="${BATS_TEST_TMPDIR}/ospkg/build-deps"
  local _virts="${_bd}/ctx::lib-build.apkvirts"
  assert_file_exists "$_virts"
  grep -q "\.df-" "$_virts"
}

@test "ospkg__install_tracked: apk — writes bare package names to sidecar for session tracking" {
  _seed_apk_build_context

  ospkg__install_tracked "lib-build" cmake ninja

  local _sidecar="${BATS_TEST_TMPDIR}/ospkg/build-deps/ctx::lib-build"
  assert_file_exists "$_sidecar"
  grep -q "^cmake$" "$_sidecar"
  grep -q "^ninja$" "$_sidecar"
}

@test "ospkg__install_tracked: apk — second call with same group increments virtual counter" {
  _seed_apk_build_context

  ospkg__install_tracked "lib-build" cmake
  ospkg__install_tracked "lib-build" ninja

  local _virts="${BATS_TEST_TMPDIR}/ospkg/build-deps/ctx::lib-build.apkvirts"
  assert_file_exists "$_virts"
  # Two distinct virtual names must exist (-0 and -1)
  local _count
  _count="$(wc -l < "$_virts")"
  [[ "$_count" -eq 2 ]]
  grep -q "\-0$" "$_virts"
  grep -q "\-1$" "$_virts"
}

@test "ospkg__install_tracked: apk — returns 1 when apk add fails" {
  _seed_apk_build_context
  # Replace fake apk with one that exits 1
  printf '#!/bin/bash\nexit 1\n' > "${BATS_TEST_TMPDIR}/bin/apk"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apk"

  run ospkg__install_tracked "lib-build" cmake
  assert_failure
}

@test "ospkg__install_tracked: apt — returns 1 when ospkg__install fails" {
  _seed_apt_build_context
  _mock_snapshots "curl" "curl newpkg"
  printf '#!/bin/bash\nexit 1\n' > "${BATS_TEST_TMPDIR}/bin/apt-get"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-get"
  # Propagate apt-get exit status (default _seed stub uses || true).
  net__fetch_with_retry() { "$@" > /dev/null 2>&1; }

  run ospkg__install_tracked "test-group" newpkg
  assert_failure
}

@test "ospkg__install_tracked: apk — skips apk add when all packages already installed" {
  printf 'cmake\nninja\n' > "${BATS_TEST_TMPDIR}/apk-installed.txt"
  _seed_apk_build_context

  ospkg__install_tracked "lib-build" cmake ninja

  # apk add must NOT have been called — no .apkvirts, no sidecar, no apk.log
  local _bd="${BATS_TEST_TMPDIR}/ospkg/build-deps"
  [[ ! -f "${_bd}/ctx::lib-build.apkvirts" ]]
  [[ ! -f "${_bd}/ctx::lib-build" ]]
  [[ ! -f "${BATS_TEST_TMPDIR}/apk.log" ]] || ! grep -q "add" "${BATS_TEST_TMPDIR}/apk.log"
}

# ---------------------------------------------------------------------------
# ospkg__cleanup_session_build_groups — APK virtual-group collection
# ---------------------------------------------------------------------------

@test "ospkg__cleanup_session_build_groups: apk — collects .apkvirts from keep=false groups into synthetic sidecar" {
  _seed_apk_build_context
  _SESSION_DIR="$(mktemp -d "${BATS_TEST_TMPDIR}/session_XXXXXX")"
  export _SYSSET_SESSION_TRACK_DIR="$_SESSION_DIR"
  mkdir -p "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  # Group A: keep=false; contributes cmake; has a .apkvirts file
  printf 'cmake\n' > "${_SESSION_DIR}/feature::install-a::lib-build"
  printf 'cmake\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/feature::install-a::lib-build"
  printf '.df-feature--install-a--lib-build-0\n' \
    > "${BATS_TEST_TMPDIR}/ospkg/build-deps/feature::install-a::lib-build.apkvirts"

  ospkg__cleanup_session_build_groups "false"

  # The synthetic sidecar's .apkvirts must contain the virtual name
  assert_file_exists "${BATS_TEST_TMPDIR}/apk.log"
  grep -q "del.*\.df-" "${BATS_TEST_TMPDIR}/apk.log"
}

@test "ospkg__cleanup_session_build_groups: apk — skips .apkvirts from groups where any package is kept" {
  _seed_apk_build_context
  _SESSION_DIR="$(mktemp -d "${BATS_TEST_TMPDIR}/session_XXXXXX")"
  export _SYSSET_SESSION_TRACK_DIR="$_SESSION_DIR"
  mkdir -p "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  # Group B: cmake is kept by feature b
  printf 'cmake\n' > "${_SESSION_DIR}/feature::install-a::lib-build"
  printf 'cmake\n' > "${_SESSION_DIR}/feature::install-b::lib-build"
  printf 'cmake\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/feature::install-a::lib-build"
  printf '.df-feature--install-a--lib-build-0\n' \
    > "${BATS_TEST_TMPDIR}/ospkg/build-deps/feature::install-a::lib-build.apkvirts"

  declare -gA _OPT_OF=(
    ["install-a"]='{"keep_build_deps": false}'
    ["install-b"]='{"keep_build_deps": true}'
  )

  ospkg__cleanup_session_build_groups "false"

  # No apk del calls — cmake is kept by install-b.
  [[ ! -f "${BATS_TEST_TMPDIR}/apk.log" ]] ||
    ! grep -q "del" "${BATS_TEST_TMPDIR}/apk.log"
}

# ---------------------------------------------------------------------------
# ospkg__install_user
# ---------------------------------------------------------------------------

@test "ospkg__install_user: APT — installs package and marks it manual (protection)" {
  _seed_apt_build_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  _create_smart_apt_mark
  prepend_fake_bin_path

  ospkg__install_user curl

  # apt-mark manual must have been called for curl
  assert_file_exists "${BATS_TEST_TMPDIR}/apt-mark.log"
  grep -q "manual" "${BATS_TEST_TMPDIR}/apt-mark.log"
  grep -q "curl" "${BATS_TEST_TMPDIR}/apt-mark.log"
}

@test "ospkg__install_user: APT — strips =version suffix before protecting" {
  _seed_apt_build_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  _create_smart_apt_mark
  prepend_fake_bin_path

  ospkg__install_user "curl=7.88.0-1"

  # Protection must be for bare name 'curl', not 'curl=7.88.0-1'
  assert_file_exists "${BATS_TEST_TMPDIR}/apt-mark.log"
  grep -q "^manual curl$" "${BATS_TEST_TMPDIR}/apt-mark.log"
  run grep "7.88" "${BATS_TEST_TMPDIR}/apt-mark.log"
  assert_failure
}

@test "ospkg__install_user: APT — evicts package from any existing build-group sidecar" {
  _seed_apt_build_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  _create_smart_apt_mark
  prepend_fake_bin_path
  # curl was tracked as a build dep by an earlier call
  printf 'curl\nwget\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/ctx::my-group"

  ospkg__install_user curl

  # curl must be removed from the sidecar; wget must remain
  run grep "^curl$" "${BATS_TEST_TMPDIR}/ospkg/build-deps/ctx::my-group"
  assert_failure
  grep -q "^wget$" "${BATS_TEST_TMPDIR}/ospkg/build-deps/ctx::my-group"
}

@test "ospkg__install_user: pacman — strips =version suffix and calls pacman -D --asexplicit" {
  _seed_pacman_build_context

  ospkg__install_user "git=2.44.0"

  assert_file_exists "${BATS_TEST_TMPDIR}/pacman.log"
  grep -q "\-\-asexplicit" "${BATS_TEST_TMPDIR}/pacman.log"
  grep -q "^-D --asexplicit git$" "${BATS_TEST_TMPDIR}/pacman.log"
}

# ---------------------------------------------------------------------------
# Integration: full APT build-dep lifecycle
# Verifies the complete snapshot → install → autoremove → restore cycle.
# ---------------------------------------------------------------------------

@test "integration: APT build-dep lifecycle — pre-existing auto pkg survives; build dep is removed" {
  # This test exercises the full snapshot/mark/autoremove/restore cycle for APT.
  _seed_apt_build_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin"

  # apt-mark showauto returns libz1 (pre-existing auto package from OS base).
  printf 'libz1\n' > "${BATS_TEST_TMPDIR}/apt-showauto.txt"
  local _apt_mark_log="${BATS_TEST_TMPDIR}/apt-mark.log"
  _create_smart_apt_mark
  prepend_fake_bin_path

  # Step 1: Snapshot global auto state (pin libz1 as manual so autoremove won't touch it).
  _ospkg__ensure_global_auto_snapshot

  # libz1 must be pinned manual.
  assert_file_exists "$_apt_mark_log"
  grep -q "^manual.*libz1" "$_apt_mark_log"

  # Step 2: Install a build dep (cmake) — tracked in a sidecar.
  _mock_snapshots "libz1" "cmake libz1"
  ospkg__install_tracked "build" cmake

  local _sidecar="${BATS_TEST_TMPDIR}/ospkg/build-deps/ctx::build"
  assert_file_exists "$_sidecar"
  grep -q "^cmake$" "$_sidecar"

  # Step 3: Remove the build group — apt-get autoremove runs.
  # cmake is now auto-marked (by _ospkg__mark_build_group); libz1 is manual.
  # autoremove removes cmake but NOT libz1.
  printf '#!/bin/bash\necho "$@" >> "%s/apt-get.log"\n' \
    "${BATS_TEST_TMPDIR}" > "${BATS_TEST_TMPDIR}/bin/apt-get"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-get"

  # Reset log so we capture only the autoremove call.
  rm -f "$_apt_mark_log"

  _ospkg__remove_build_group "ctx::build"

  # autoremove must be called.
  assert_file_exists "${BATS_TEST_TMPDIR}/apt-get.log"
  grep -q "autoremove" "${BATS_TEST_TMPDIR}/apt-get.log"

  # Step 4: Restore — libz1 must be marked back as auto.
  printf '#!/bin/bash\nprintf "libz1\n"\n' > "${BATS_TEST_TMPDIR}/bin/dpkg-query"
  chmod +x "${BATS_TEST_TMPDIR}/bin/dpkg-query"

  _ospkg__restore_global_auto_state

  assert_file_exists "$_apt_mark_log"
  grep -q "^auto.*libz1" "$_apt_mark_log"
  # Snapshot file must be gone.
  [[ ! -f "${BATS_TEST_TMPDIR}/ospkg/build-deps/.global_auto_before" ]]
}

@test "integration: APT user package survives build-dep cleanup via ospkg__install_user" {
  # Installs curl as a user package (manual mark + sidecar eviction), then
  # installs a build dep (cmake), then cleans up — curl must not be removed.
  _seed_apt_build_context
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  _create_smart_apt_mark
  prepend_fake_bin_path

  # User installs curl.
  ospkg__install_user curl
  assert_file_exists "${BATS_TEST_TMPDIR}/apt-mark.log"
  grep -q "^manual curl$" "${BATS_TEST_TMPDIR}/apt-mark.log"

  # Build dep: cmake tracked separately.
  _mock_snapshots "curl" "cmake curl"
  ospkg__install_tracked "build" cmake

  local _sidecar="${BATS_TEST_TMPDIR}/ospkg/build-deps/ctx::build"
  # curl must NOT be in the build-dep sidecar.
  run grep "^curl$" "$_sidecar"
  assert_failure
  grep -q "^cmake$" "$_sidecar"
}

@test "integration: session keep-wins prevents removal of package needed by any feature" {
  _seed_session_cleanup_context

  # Two features co-own 'cmake': one keeps (install-a), one doesn't (install-b).
  printf 'cmake\n' > "${_SESSION_DIR}/feature::install-a::lib-build"
  printf 'cmake\n' > "${_SESSION_DIR}/feature::install-b::lib-build"

  declare -gA _OPT_OF=(
    ["install-a"]='{"keep_build_deps": true}'
    ["install-b"]='{"keep_build_deps": false}'
  )

  ospkg__cleanup_session_build_groups "false"

  # cmake must not be in the autoremove call — keep wins.
  [[ ! -f "$_APT_LOG" ]] || ! grep -q "cmake" "$_APT_LOG"
}

# ---------------------------------------------------------------------------
# ospkg__has_available_version
# ---------------------------------------------------------------------------
#
# Unit tests use fake binaries (via create_fake_bin / prepend_fake_bin_path)
# that simulate PM output. Integration tests (prefixed "integration:") run
# the real PM inside the current container.

# ospkg__resolve_version
# =======================

_setup_resolve_version() {
  reload_lib
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
}

@test "ospkg__resolve_version: returns 1 for empty package name" {
  _setup_resolve_version
  run ospkg__resolve_version "" "5.9"
  assert_failure
}

@test "ospkg__resolve_version: returns 1 for empty version spec" {
  _setup_resolve_version
  run ospkg__resolve_version "zsh" ""
  assert_failure
}

@test "ospkg__resolve_version: apt — returns exact PM version for matching spec" {
  _setup_resolve_version
  printf '#!/bin/sh\nprintf "zsh:\n  Installed: (none)\n  Candidate: 5.9-6ubuntu2\n"\n' \
    > "${BATS_TEST_TMPDIR}/bin/apt-cache"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-cache"
  create_fake_bin "uname" "Linux"
  prepend_fake_bin_path
  _OSPKG__DETECTED=true
  _OSPKG__FAMILY="apt"
  _OSPKG__PKG_MNGR="apt-get"
  run ospkg__resolve_version "zsh" "5.9"
  assert_success
  assert_output "5.9-6ubuntu2"
}

@test "ospkg__resolve_version: apt — exact spec matches PM version with distro suffix" {
  _setup_resolve_version
  printf '#!/bin/sh\nprintf "zsh:\n  Installed: (none)\n  Candidate: 5.9.1-2\n"\n' \
    > "${BATS_TEST_TMPDIR}/bin/apt-cache"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-cache"
  create_fake_bin "uname" "Linux"
  prepend_fake_bin_path
  _OSPKG__DETECTED=true
  _OSPKG__FAMILY="apt"
  _OSPKG__PKG_MNGR="apt-get"
  run ospkg__resolve_version "zsh" "5.9.1"
  assert_success
  assert_output "5.9.1-2"
}

@test "ospkg__resolve_version: apt — returns 1 when spec does not match candidate" {
  _setup_resolve_version
  printf '#!/bin/sh\nprintf "zsh:\n  Installed: (none)\n  Candidate: 5.9-6ubuntu2\n"\n' \
    > "${BATS_TEST_TMPDIR}/bin/apt-cache"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-cache"
  create_fake_bin "uname" "Linux"
  prepend_fake_bin_path
  _OSPKG__DETECTED=true
  _OSPKG__FAMILY="apt"
  _OSPKG__PKG_MNGR="apt-get"
  run ospkg__resolve_version "zsh" "5.9.1"
  assert_failure
}

@test "ospkg__resolve_version: apt — returns 1 for (none) candidate" {
  _setup_resolve_version
  printf '#!/bin/sh\nprintf "zsh:\n  Installed: (none)\n  Candidate: (none)\n"\n' \
    > "${BATS_TEST_TMPDIR}/bin/apt-cache"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-cache"
  create_fake_bin "uname" "Linux"
  prepend_fake_bin_path
  _OSPKG__DETECTED=true
  _OSPKG__FAMILY="apt"
  _OSPKG__PKG_MNGR="apt-get"
  run ospkg__resolve_version "zsh" "5.9"
  assert_failure
}

@test "ospkg__resolve_version: apk — returns exact PM version for matching spec" {
  _setup_resolve_version
  create_fake_bin "apk" "zsh-5.9-r4"
  create_fake_bin "uname" "Linux"
  prepend_fake_bin_path
  _OSPKG__DETECTED=true
  _OSPKG__FAMILY="apk"
  _OSPKG__PKG_MNGR="apk"
  run ospkg__resolve_version "zsh" "5.9"
  assert_success
  assert_output "5.9-r4"
}

@test "ospkg__resolve_version: apk — returns latest when multiple versions match" {
  _setup_resolve_version
  # apk search returns multiple lines (e.g. edge + stable repos)
  printf '#!/bin/sh\nprintf "zsh-5.9.1-r0\nzsh-5.9-r4\n"\n' \
    > "${BATS_TEST_TMPDIR}/bin/apk"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apk"
  create_fake_bin "uname" "Linux"
  prepend_fake_bin_path
  _OSPKG__DETECTED=true
  _OSPKG__FAMILY="apk"
  _OSPKG__PKG_MNGR="apk"
  run ospkg__resolve_version "zsh" "5.9"
  assert_success
  assert_output "5.9.1-r0"
}

@test "ospkg__resolve_version: dnf — returns latest matching version from multiple candidates" {
  _setup_resolve_version
  printf '#!/bin/sh\nprintf "5.8\n5.9\n5.9.1\n"\n' > "${BATS_TEST_TMPDIR}/bin/dnf"
  chmod +x "${BATS_TEST_TMPDIR}/bin/dnf"
  create_fake_bin "uname" "Linux"
  prepend_fake_bin_path
  _OSPKG__DETECTED=true
  _OSPKG__FAMILY="dnf"
  _OSPKG__PKG_MNGR="dnf"
  run ospkg__resolve_version "zsh" "5.9"
  assert_success
  assert_output "5.9.1"
}

@test "ospkg__resolve_version: dnf — returns 1 for non-matching spec" {
  _setup_resolve_version
  printf '#!/bin/sh\nprintf "5.9\n"\n' > "${BATS_TEST_TMPDIR}/bin/dnf"
  chmod +x "${BATS_TEST_TMPDIR}/bin/dnf"
  create_fake_bin "uname" "Linux"
  prepend_fake_bin_path
  _OSPKG__DETECTED=true
  _OSPKG__FAMILY="dnf"
  _OSPKG__PKG_MNGR="dnf"
  run ospkg__resolve_version "zsh" "5.9.1"
  assert_failure
}

@test "ospkg__resolve_version: unknown family returns 1" {
  _setup_resolve_version
  _OSPKG__DETECTED=true
  _OSPKG__FAMILY="unknown_pm"
  _OSPKG__PKG_MNGR="unknown_pm"
  run ospkg__resolve_version "zsh" "5.9"
  assert_failure
}

@test "integration: ospkg__resolve_version returns PM version string for known package" {
  _setup_resolve_version
  type apt-cache > /dev/null 2>&1 || skip "not an apt-based system"
  local _bash_ver
  _bash_ver="$(apt-cache policy bash 2> /dev/null | awk '/Candidate:/{print $2; exit}')"
  [[ -n "${_bash_ver}" && "${_bash_ver}" != "(none)" ]] || skip "bash candidate not found in apt"
  local _prefix="${_bash_ver%%[.-]*}"
  run ospkg__resolve_version "bash" "${_prefix}"
  assert_success
  assert_output "${_bash_ver}"
}

@test "integration: ospkg__resolve_version fails for non-existent package" {
  _setup_resolve_version
  type apt-cache > /dev/null 2>&1 || skip "not an apt-based system"
  run ospkg__resolve_version "this-package-does-not-exist-12345" "1.0"
  assert_failure
}

# ospkg__run version resolution
# ==============================

@test "ospkg__run: channel selector in feat.version installs unpinned package" {
  _seed_apt_context
  _stub_ospkg_privilege_ok
  printf '#!/bin/sh\nprintf "bash:\n  Installed: (none)\n  Candidate: 5.2.21-2ubuntu1\n"\n' \
    > "${BATS_TEST_TMPDIR}/bin/apt-cache"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-cache"
  cat > "${BATS_TEST_TMPDIR}/bin/yq" << 'YQ_EOF'
#!/bin/sh
printf '{"packages":[{"name":"bash","version":"stable"}]}\n'
YQ_EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/yq"
  local _manifest
  _manifest="$(mktemp "${BATS_TEST_TMPDIR}/manifest.XXXXXX")"
  printf 'packages:\n- name: bash\n  version: "{feat.version}"\n' > "${_manifest}"
  ctx__set feat.version=stable
  _CTX__REGISTRY_INITIALIZED=true
  run ospkg__run --manifest "${_manifest}" --update --dry_run
  assert_success
  assert_output --partial "bash"
  assert_output --partial "Installing 1 package"
  refute_output --partial "bash=stable"
}

@test "ospkg__run: resolves version spec to PM-native version string before install" {
  _seed_apt_context
  _stub_ospkg_privilege_ok
  # apt-cache returns candidate "5.9-6ubuntu2" for spec "5.9"
  printf '#!/bin/sh\nprintf "zsh:\n  Installed: (none)\n  Candidate: 5.9-6ubuntu2\n"\n' \
    > "${BATS_TEST_TMPDIR}/bin/apt-cache"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-cache"
  # Fake yq so bootstrap__yq finds it via PATH without downloading (on systems
  # like Alpine where yq is not pre-installed, the real bootstrap downloads yq
  # and its progress output pollutes the captured output).
  # Output is the JSON equivalent of the test manifest; {feat.version} is expanded
  # via ctx before version resolution.
  cat > "${BATS_TEST_TMPDIR}/bin/yq" << 'YQ_EOF'
#!/bin/sh
printf '{"packages":[{"name":"zsh","version":"{feat.version}"}]}\n'
YQ_EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/yq"
  local _manifest
  _manifest="$(mktemp "${BATS_TEST_TMPDIR}/manifest.XXXXXX")"
  printf 'packages:\n- name: zsh\n  version: "{feat.version}"\n' > "${_manifest}"
  ctx__set feat.version=5.9
  _CTX__REGISTRY_INITIALIZED=true
  # --update bypasses ospkg__is_installed; --dry_run skips the actual apt-get install.
  run ospkg__run --manifest "${_manifest}" --update --dry_run
  assert_success
  assert_output --partial "zsh=5.9-6ubuntu2"
}

# ospkg__has_available_version
# ============================

_setup_has_available_version() {
  reload_lib
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
}

@test "ospkg__has_available_version: returns 1 for empty package name" {
  _setup_has_available_version
  run ospkg__has_available_version "" "5.9"
  assert_failure
}

@test "ospkg__has_available_version: returns 1 for empty version spec" {
  _setup_has_available_version
  run ospkg__has_available_version "zsh" ""
  assert_failure
}

@test "ospkg__has_available_version: apt — available version satisfies spec" {
  _setup_has_available_version
  # apt-cache policy outputs "Candidate: 5.9-6ubuntu2"
  printf '#!/bin/sh\nprintf "zsh:\n  Installed: (none)\n  Candidate: 5.9-6ubuntu2\n"\n' \
    > "${BATS_TEST_TMPDIR}/bin/apt-cache"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-cache"
  create_fake_bin "uname" "Linux"
  prepend_fake_bin_path
  _OSPKG__DETECTED=true
  _OSPKG__FAMILY="apt"
  _OSPKG__PKG_MNGR="apt-get"
  run ospkg__has_available_version "zsh" "5.9"
  assert_success
}

@test "ospkg__has_available_version: apt — version mismatch returns 1" {
  _setup_has_available_version
  printf '#!/bin/sh\nprintf "zsh:\n  Installed: (none)\n  Candidate: 5.9-6ubuntu2\n"\n' \
    > "${BATS_TEST_TMPDIR}/bin/apt-cache"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-cache"
  create_fake_bin "uname" "Linux"
  prepend_fake_bin_path
  _OSPKG__DETECTED=true
  _OSPKG__FAMILY="apt"
  _OSPKG__PKG_MNGR="apt-get"
  run ospkg__has_available_version "zsh" "5.9.1"
  assert_failure
}

@test "ospkg__has_available_version: apt — (none) candidate returns 1" {
  _setup_has_available_version
  printf '#!/bin/sh\nprintf "zsh:\n  Installed: (none)\n  Candidate: (none)\n"\n' \
    > "${BATS_TEST_TMPDIR}/bin/apt-cache"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-cache"
  create_fake_bin "uname" "Linux"
  prepend_fake_bin_path
  _OSPKG__DETECTED=true
  _OSPKG__FAMILY="apt"
  _OSPKG__PKG_MNGR="apt-get"
  run ospkg__has_available_version "zsh" "5.9"
  assert_failure
}

@test "ospkg__has_available_version: apk — available version satisfies spec" {
  _setup_has_available_version
  create_fake_bin "apk" "zsh-5.9-r4"
  create_fake_bin "uname" "Linux"
  prepend_fake_bin_path
  _OSPKG__DETECTED=true
  _OSPKG__FAMILY="apk"
  _OSPKG__PKG_MNGR="apk"
  run ospkg__has_available_version "zsh" "5.9"
  assert_success
}

@test "ospkg__has_available_version: apk — version mismatch returns 1" {
  _setup_has_available_version
  create_fake_bin "apk" "zsh-5.9-r4"
  create_fake_bin "uname" "Linux"
  prepend_fake_bin_path
  _OSPKG__DETECTED=true
  _OSPKG__FAMILY="apk"
  _OSPKG__PKG_MNGR="apk"
  run ospkg__has_available_version "zsh" "5.9.1"
  assert_failure
}

@test "ospkg__has_available_version: apk — empty result returns 1" {
  _setup_has_available_version
  create_fake_bin "apk" ""
  create_fake_bin "uname" "Linux"
  prepend_fake_bin_path
  _OSPKG__DETECTED=true
  _OSPKG__FAMILY="apk"
  _OSPKG__PKG_MNGR="apk"
  run ospkg__has_available_version "zsh" "5.9"
  assert_failure
}

@test "ospkg__has_available_version: dnf — available version satisfies spec" {
  _setup_has_available_version
  printf '#!/bin/sh\nprintf "5.9\n"\n' > "${BATS_TEST_TMPDIR}/bin/dnf"
  chmod +x "${BATS_TEST_TMPDIR}/bin/dnf"
  create_fake_bin "uname" "Linux"
  prepend_fake_bin_path
  _OSPKG__DETECTED=true
  _OSPKG__FAMILY="dnf"
  _OSPKG__PKG_MNGR="dnf"
  run ospkg__has_available_version "zsh" "5.9"
  assert_success
}

@test "ospkg__has_available_version: dnf — version mismatch returns 1" {
  _setup_has_available_version
  printf '#!/bin/sh\nprintf "5.9\n"\n' > "${BATS_TEST_TMPDIR}/bin/dnf"
  chmod +x "${BATS_TEST_TMPDIR}/bin/dnf"
  create_fake_bin "uname" "Linux"
  prepend_fake_bin_path
  _OSPKG__DETECTED=true
  _OSPKG__FAMILY="dnf"
  _OSPKG__PKG_MNGR="dnf"
  run ospkg__has_available_version "zsh" "5.9.1"
  assert_failure
}

@test "ospkg__has_available_version: unknown family returns 1" {
  _setup_has_available_version
  _OSPKG__DETECTED=true
  _OSPKG__FAMILY="unknown_pm"
  _OSPKG__PKG_MNGR="unknown_pm"
  run ospkg__has_available_version "zsh" "5.9"
  assert_failure
}

@test "integration: ospkg__has_available_version succeeds for known-installed package" {
  _setup_has_available_version
  # bash is always present in our dev container (apt-based)
  type apt-cache > /dev/null 2>&1 || skip "not an apt-based system"
  # Use 'bash' as the test package — it's always available in the apt index.
  local _bash_ver
  _bash_ver="$(apt-cache policy bash 2> /dev/null | awk '/Candidate:/{print $2; exit}')"
  [[ -n "${_bash_ver}" && "${_bash_ver}" != "(none)" ]] || skip "bash candidate not found in apt"
  local _prefix="${_bash_ver%%[.-]*}"
  run ospkg__has_available_version "bash" "${_prefix}"
  assert_success
}

@test "integration: ospkg__has_available_version fails for non-existent package" {
  _setup_has_available_version
  type apt-cache > /dev/null 2>&1 || skip "not an apt-based system"
  run ospkg__has_available_version "this-package-does-not-exist-12345" "1.0"
  assert_failure
}

# ---------------------------------------------------------------------------
# Live registry (concurrency-safe build-dep co-ownership)
#
# These tests pin _OSPKG__REGISTRY_ROOT under BATS_TEST_TMPDIR so the registry
# is active in DIRECT mode (no privilege wrapper). PM is mocked as apt-get with a
# logging fake so autoremove can be asserted. Siblings are real background
# processes; teardown reaps any that survive an early assertion failure.
# ---------------------------------------------------------------------------

teardown() {
  local _p
  for _p in "${_REG_SIBLING_PIDS[@]:-}"; do
    [[ -n "$_p" ]] && kill "$_p" 2> /dev/null || true
  done
}

# _seed_registry_apt — seed a mocked apt-get PM with the live registry pinned
# under BATS_TEST_TMPDIR (direct mode). apt-get logs its args to apt-get.log.
_seed_registry_apt() {
  _seed_apt_context
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"
  export _OSPKG__REGISTRY_ROOT="${BATS_TEST_TMPDIR}/registry"
  _OSPKG__REGISTERED=false
  _OSPKG__SELF_TOKEN=""
  _OSPKG__LAST_OUT_DECISION=true
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/bash\necho "$@" >> "%s/apt-get.log"\n' "${BATS_TEST_TMPDIR}" \
    > "${BATS_TEST_TMPDIR}/bin/apt-get"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-get"
  _create_smart_apt_mark
  prepend_fake_bin_path
}

# _reg_make_registrant <key> [keep] — write a registrant file directly.
_reg_make_registrant() {
  local _key="$1" _keep="${2:-false}"
  mkdir -p "${_OSPKG__REGISTRY_ROOT}/registrants"
  printf 'feat=test\nkeep=%s\npm=apt-get\n' "$_keep" \
    > "${_OSPKG__REGISTRY_ROOT}/registrants/${_key}"
}

# _reg_make_group <name> <keep> <pkg>... — write a registry group + .keep.
_reg_make_group() {
  local _name="$1" _keep="$2"
  shift 2
  mkdir -p "${_OSPKG__REGISTRY_ROOT}/groups"
  printf '%s\n' "$@" | sort -u > "${_OSPKG__REGISTRY_ROOT}/groups/${_name}"
  printf '%s\n' "$_keep" > "${_OSPKG__REGISTRY_ROOT}/groups/${_name}.keep"
}

@test "registry: _ospkg__registry_register creates a registrant for this process" {
  _seed_registry_apt
  _ospkg__registry_register
  local _self
  _self="$$.$(_ospkg__proc_token "$$")"
  assert_file_exists "${_OSPKG__REGISTRY_ROOT}/registrants/${_self}"
  grep -q "^pm=apt-get$" "${_OSPKG__REGISTRY_ROOT}/registrants/${_self}"
  [[ "${_OSPKG__REGISTERED}" == true ]]
}

@test "registry: _ospkg__registry_register is idempotent per process" {
  _seed_registry_apt
  _ospkg__registry_register
  _ospkg__registry_register
  local _n
  _n="$(ls -1 "${_OSPKG__REGISTRY_ROOT}/registrants" | wc -l)"
  [[ "$_n" -eq 1 ]]
}

@test "registry: cleanup parks (no autoremove) when a live sibling registrant remains" {
  _seed_registry_apt
  _ospkg__registry_register
  _reg_make_group "grpA" false curl
  sleep 300 3>&- < /dev/null > /dev/null 2>&1 &
  local _sib=$!
  _REG_SIBLING_PIDS+=("$_sib")
  local _tok
  _tok="$(_ospkg__proc_token "$_sib")"
  _reg_make_registrant "${_sib}.${_tok}" false

  ospkg__cleanup_all_build_groups false

  # Parked → not last-out and no autoremove ran.
  run ospkg__is_last_out
  assert_failure
  [[ ! -f "${BATS_TEST_TMPDIR}/apt-get.log" ]]
  # Self deregistered; sibling and parked group remain for whoever is last-out.
  local _self
  _self="$$.$(_ospkg__proc_token "$$")"
  [[ ! -e "${_OSPKG__REGISTRY_ROOT}/registrants/${_self}" ]]
  assert_file_exists "${_OSPKG__REGISTRY_ROOT}/registrants/${_sib}.${_tok}"
  assert_file_exists "${_OSPKG__REGISTRY_ROOT}/groups/grpA"

  kill "$_sib" 2> /dev/null || true
}

@test "registry: a dead-PID registrant is pruned and the survivor becomes last-out (autoremove runs)" {
  _seed_registry_apt
  _reg_make_group "grpA" false curl
  sleep 60 3>&- < /dev/null > /dev/null 2>&1 &
  local _dp=$!
  local _dtok
  _dtok="$(_ospkg__proc_token "$_dp")"
  kill "$_dp" 2> /dev/null || true
  wait "$_dp" 2> /dev/null || true
  _reg_make_registrant "${_dp}.${_dtok}" false

  ospkg__cleanup_all_build_groups false

  run ospkg__is_last_out
  assert_success
  [[ ! -e "${_OSPKG__REGISTRY_ROOT}/registrants/${_dp}.${_dtok}" ]]
  assert_file_exists "${BATS_TEST_TMPDIR}/apt-get.log"
  grep -q "autoremove" "${BATS_TEST_TMPDIR}/apt-get.log"
}

@test "registry: last-out honours .keep keep-wins (kept package is not autoremoved)" {
  _seed_registry_apt
  _reg_make_group "grpKeep" true curl
  _reg_make_group "grpDrop" false curl

  ospkg__cleanup_all_build_groups false

  run ospkg__is_last_out
  assert_success
  # curl is keep-wins true across the union → nothing to remove → no autoremove.
  [[ ! -f "${BATS_TEST_TMPDIR}/apt-get.log" ]]
}

@test "registry: mixed keep — only the keep=false package is removed, kept one is protected" {
  _seed_registry_apt
  _reg_make_group "grpKeep" true keepme
  _reg_make_group "grpDrop" false dropme

  ospkg__cleanup_all_build_groups false

  run ospkg__is_last_out
  assert_success
  # dropme triggers autoremove; keepme is pinned manual (protected) beforehand.
  assert_file_exists "${BATS_TEST_TMPDIR}/apt-get.log"
  grep -q "autoremove" "${BATS_TEST_TMPDIR}/apt-get.log"
  assert_file_exists "${BATS_TEST_TMPDIR}/apt-mark.log"
  grep -q "manual" "${BATS_TEST_TMPDIR}/apt-mark.log"
  grep -q "keepme" "${BATS_TEST_TMPDIR}/apt-mark.log"
}

@test "registry: first-in registrant snapshots global-auto into the registry root" {
  _seed_registry_apt
  printf 'wget\nlibz1\n' > "${BATS_TEST_TMPDIR}/apt-showauto.txt"
  _ospkg__registry_register
  assert_file_exists "${_OSPKG__REGISTRY_ROOT}/.global_auto_before"
  grep -q "^libz1$" "${_OSPKG__REGISTRY_ROOT}/.global_auto_before"
  grep -q "^wget$" "${_OSPKG__REGISTRY_ROOT}/.global_auto_before"
  grep -q "manual" "${BATS_TEST_TMPDIR}/apt-mark.log"
}

@test "registry: global-auto is restored only at last-out, not when parked" {
  _seed_registry_apt
  mkdir -p "${_OSPKG__REGISTRY_ROOT}"
  printf 'libz1\n' > "${_OSPKG__REGISTRY_ROOT}/.global_auto_before"
  _reg_make_group "grpA" false curl
  printf '#!/bin/bash\nprintf "libz1\\n"\n' > "${BATS_TEST_TMPDIR}/bin/dpkg-query"
  chmod +x "${BATS_TEST_TMPDIR}/bin/dpkg-query"
  prepend_fake_bin_path
  sleep 300 3>&- < /dev/null > /dev/null 2>&1 &
  local _sib=$!
  _REG_SIBLING_PIDS+=("$_sib")
  local _tok
  _tok="$(_ospkg__proc_token "$_sib")"
  _reg_make_registrant "${_sib}.${_tok}" false

  # First cleanup: parked (sibling alive) → snapshot NOT restored.
  ospkg__cleanup_all_build_groups false
  assert_file_exists "${_OSPKG__REGISTRY_ROOT}/.global_auto_before"

  # Sibling exits → next cleanup is last-out → snapshot restored (removed).
  rm -f "${_OSPKG__REGISTRY_ROOT}/registrants/${_sib}.${_tok}"
  kill "$_sib" 2> /dev/null || true
  ospkg__cleanup_all_build_groups false
  [[ ! -e "${_OSPKG__REGISTRY_ROOT}/.global_auto_before" ]]
}

@test "registry: mutex acquire takes over a stale (dead-owner) lock" {
  _seed_registry_apt
  mkdir -p "${_OSPKG__REGISTRY_ROOT}/mutex"
  sleep 60 3>&- < /dev/null > /dev/null 2>&1 &
  local _dp=$!
  local _dtok
  _dtok="$(_ospkg__proc_token "$_dp")"
  kill "$_dp" 2> /dev/null || true
  wait "$_dp" 2> /dev/null || true
  printf '%s.%s\n' "$_dp" "$_dtok" > "${_OSPKG__REGISTRY_ROOT}/mutex/owner"

  _ospkg__mutex_acquire "${_OSPKG__REGISTRY_ROOT}"
  grep -q "^$$\." "${_OSPKG__REGISTRY_ROOT}/mutex/owner"
  _ospkg__mutex_release "${_OSPKG__REGISTRY_ROOT}"
  [[ ! -d "${_OSPKG__REGISTRY_ROOT}/mutex" ]]
}

@test "registry: nonroot without sudo degrades to today's (no-registry) cleanup path" {
  _seed_apt_context
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"
  export _FEAT_SHARE_DIR_ROOT="${BATS_TEST_TMPDIR}/share/ns/feat"
  # No _OSPKG__REGISTRY_ROOT override; force unprivileged so the system-PM
  # registry is inactive and behaviour degrades to today's path.
  users__is_privileged() { return 1; }
  users__is_root() { return 1; }
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/ospkg/build-deps"
  printf '#!/bin/bash\necho "$@" >> "%s/apt-get.log"\n' "${BATS_TEST_TMPDIR}" \
    > "${BATS_TEST_TMPDIR}/bin/apt-get"
  chmod +x "${BATS_TEST_TMPDIR}/bin/apt-get"
  prepend_fake_bin_path
  printf 'curl\n' > "${BATS_TEST_TMPDIR}/ospkg/build-deps/grp"

  run _ospkg__registry_active
  assert_failure

  ospkg__cleanup_all_build_groups false
  grep -q "autoremove" "${BATS_TEST_TMPDIR}/apt-get.log"
  [[ ! -f "${BATS_TEST_TMPDIR}/ospkg/build-deps/grp" ]]
  run ospkg__is_last_out
  assert_success
}

@test "registry: single invocation is immediately last-out and removes its build group" {
  _seed_registry_apt
  _ospkg__registry_register
  _reg_make_group "grpA" false curl

  ospkg__cleanup_all_build_groups false

  run ospkg__is_last_out
  assert_success
  assert_file_exists "${BATS_TEST_TMPDIR}/apt-get.log"
  grep -q "autoremove" "${BATS_TEST_TMPDIR}/apt-get.log"
  # Registry cleared on last-out.
  [[ -z "$(ls -A "${_OSPKG__REGISTRY_ROOT}/registrants" 2> /dev/null)" ]]
  [[ -z "$(ls -A "${_OSPKG__REGISTRY_ROOT}/groups" 2> /dev/null)" ]]
}

@test "registry: session mode registers a single session-keyed registrant" {
  _seed_registry_apt
  export _SYSSET_SESSION_TRACK_DIR="${BATS_TEST_TMPDIR}/session"
  mkdir -p "$_SYSSET_SESSION_TRACK_DIR"
  _ospkg__registry_register
  local _key
  _key="$(_ospkg__session_reg_key)"
  assert_file_exists "${_OSPKG__REGISTRY_ROOT}/registrants/${_key}"
  # No PID-keyed registrant was created.
  local _n
  _n="$(ls -1 "${_OSPKG__REGISTRY_ROOT}/registrants" | wc -l)"
  [[ "$_n" -eq 1 ]]
}

@test "registry: session cleanup parks its groups when a live sibling remains" {
  _seed_registry_apt
  export _SYSSET_SESSION_TRACK_DIR="${BATS_TEST_TMPDIR}/session"
  mkdir -p "$_SYSSET_SESSION_TRACK_DIR"
  printf 'curl\n' > "${_SYSSET_SESSION_TRACK_DIR}/install-bash::grp"
  local _skey
  _skey="$(_ospkg__session_reg_key)"
  _reg_make_registrant "$_skey" false
  sleep 300 3>&- < /dev/null > /dev/null 2>&1 &
  local _sib=$!
  _REG_SIBLING_PIDS+=("$_sib")
  local _tok
  _tok="$(_ospkg__proc_token "$_sib")"
  _reg_make_registrant "${_sib}.${_tok}" false

  ospkg__cleanup_session_build_groups false

  run ospkg__is_last_out
  assert_failure
  # Parked → no autoremove; session dir gone; session registrant removed; curl
  # parked into the registry groups for the last-out invocation.
  [[ ! -f "${BATS_TEST_TMPDIR}/apt-get.log" ]]
  [[ ! -d "$_SYSSET_SESSION_TRACK_DIR" ]]
  [[ ! -e "${_OSPKG__REGISTRY_ROOT}/registrants/${_skey}" ]]
  grep -rq "^curl$" "${_OSPKG__REGISTRY_ROOT}/groups/"

  kill "$_sib" 2> /dev/null || true
}
