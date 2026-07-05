#!/usr/bin/env bats
# Unit tests for lib/json.bash
#
# All json__* function tests require a real jq binary and live in
# test/lib/integration/json.bats. Only the bootstrap stub test lives here.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  reload_lib
}

# ---------------------------------------------------------------------------
# bootstrap__jq — auto-installs jq when absent
# ---------------------------------------------------------------------------

@test "bootstrap__jsonschema: returns cached path when already set" {
  reload_lib

  local _fake_js="${BATS_TEST_TMPDIR}/bin/jsonschema"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/sh\nprintf "%%s\\n" "16.0.0"\n' > "$_fake_js"
  chmod +x "$_fake_js"
  _BOOTSTRAP__JSONSCHEMA_BIN="$_fake_js"

  run bootstrap__jsonschema
  assert_success
  assert_output "$_fake_js"
}

@test "bootstrap__jsonschema: picks up compatible binary from PATH" {
  reload_lib

  local _fake_js="${BATS_TEST_TMPDIR}/bin/jsonschema"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/sh\nprintf "%%s\\n" "16.0.0"\n' > "$_fake_js"
  chmod +x "$_fake_js"

  begin_path_isolation jsonschema
  run bootstrap__jsonschema
  local _rc=$?
  end_path_isolation

  [[ $_rc -eq 0 ]]
  [[ "$output" == *"jsonschema"* ]]
}

@test "bootstrap__jsonschema: ignores incompatible (Python) binary on PATH" {
  reload_lib

  local _install_log="${BATS_TEST_TMPDIR}/install.log"
  local _fake_js="${BATS_TEST_TMPDIR}/bin/jsonschema"
  local _real_js="${BATS_TEST_TMPDIR}/bin/jsonschema-real"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"

  # Incompatible binary: outputs DeprecationWarning like the Python one.
  printf '#!/bin/sh\nprintf "DeprecationWarning: something\\n4.26.0\\n"\n' > "$_fake_js"
  chmod +x "$_fake_js"

  # The real binary that will be "installed" by the stub.
  printf '#!/bin/sh\nprintf "%%s\\n" "16.0.0"\n' > "$_real_js"
  chmod +x "$_real_js"

  ospkg__update() { return 0; }
  export -f ospkg__update
  ospkg__install_tracked() {
    echo "install_tracked $*" >> "$_install_log"
    return 0
  }
  export -f ospkg__install_tracked

  # Stub github__resolve_version to avoid network calls.
  github__resolve_version() {
    printf '16.0.0\n'
    return 0
  }
  export -f github__resolve_version

  # Stub install__release_asset to install our fake "real" binary.
  install__release_asset() {
    local _dest=""
    while [[ $# -gt 0 ]]; do
      case "$1" in --binary-dest)
        _dest="$2"
        shift 2
        ;;
      *) shift ;; esac
    done
    cp "$_real_js" "$_dest"
    chmod +x "$_dest"
    printf '%s\n' "$_dest"
    return 0
  }
  export -f install__release_asset

  # Stub net__fetch_url_file to produce a fake CHECKSUMS.txt.
  net__fetch_url_file() {
    local _dest="$2"
    printf 'SHA256 (jsonschema-16.0.0-linux-x86_64.zip) = %s\n' \
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" > "$_dest"
    return 0
  }
  export -f net__fetch_url_file

  begin_path_isolation jsonschema
  run bootstrap__jsonschema
  local _rc=$?
  end_path_isolation

  # Should not error out (it falls through to download, which succeeds via stub).
  [[ $_rc -eq 0 ]]
}

# ---------------------------------------------------------------------------
# bootstrap__jq — auto-installs jq when absent
# ---------------------------------------------------------------------------

@test "bootstrap__jq: downloads the GitHub release binary when jq is absent" {
  reload_lib

  local _asset_log="${BATS_TEST_TMPDIR}/asset.log"
  local _fake_jq_src="${BATS_TEST_TMPDIR}/jq-src"
  printf '#!/bin/sh\nexit 0\n' > "$_fake_jq_src"
  chmod +x "$_fake_jq_src"

  # Resolve the tag without touching the network (redirect/API both skipped).
  github__latest_tag() {
    printf 'jq-1.8.2\n'
    return 0
  }
  export -f github__latest_tag

  # Install our fake jq instead of downloading the real release asset — mirrors
  # the download-based path (bootstrap__jq no longer uses ospkg__install_tracked).
  install__release_asset() {
    echo "release_asset $*" >> "$_asset_log"
    local _dest=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --binary-dest)
          _dest="$2"
          shift 2
          ;;
        *) shift ;;
      esac
    done
    cp "$_fake_jq_src" "$_dest"
    chmod +x "$_dest"
    printf '%s\n' "$_dest"
    return 0
  }
  export -f install__release_asset

  # cp/chmod are used by the install stub above; jq stays absent so the
  # bootstrap runs its install path rather than the command -v short-circuit.
  begin_path_isolation cp chmod
  run bootstrap__jq
  local _rc=$?
  end_path_isolation

  [[ $_rc -eq 0 ]]
  assert_file_exists "$_asset_log"
  grep -q "release_asset" "$_asset_log"
}
