#!/usr/bin/env bats
# Unit tests for install__release_asset (lib/install.bash)

bats_require_minimum_version 1.7.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"

  net__ensure_fetch_tool() {
    _NET__FETCH_TOOL=curl
    _NET__CA_CERTS_OK=true
    return 0
  }
  net__ensure_ca_certs() {
    _NET__CA_CERTS_OK=true
    return 0
  }
  export -f net__ensure_fetch_tool net__ensure_ca_certs
}

_stub_release_asset_happy_path() {
  net__fetch_url_file() {
    case "$1" in
      *.sha256 | */SHA256SUMS | */sha256sum.txt) return 1 ;;
    esac
    printf '\x7fELF\x00\x00' > "$2"
    return 0
  }
  export -f net__fetch_url_file

  file__detect_type() { printf 'elf'; }
  export -f file__detect_type

  install__copy_bin() {
    touch "$2"
    chmod +x "$2"
    return 0
  }
  export -f install__copy_bin

  _URI_FETCH_CALLS="${BATS_TEST_TMPDIR}/uri_fetch_calls"
  export _URI_FETCH_CALLS
  uri__fetch_asset() {
    printf '%s\n' "$@" >> "$_URI_FETCH_CALLS"
    printf '%s/bin/out\n' "${BATS_TEST_TMPDIR}"
    return 0
  }
  export -f uri__fetch_asset
}

# ---------------------------------------------------------------------------
# install__release_asset — validation
# ---------------------------------------------------------------------------

@test "install__release_asset: fails when --asset-uri is missing" {
  run install__release_asset --binary-dest "/tmp/out"
  assert_failure
  assert_output --partial "--asset-uri is required"
}

@test "install__release_asset: rejects unknown option" {
  run install__release_asset --asset-uri "https://example.com/tool" --bogus
  assert_failure
  assert_output --partial "unknown option"
}

@test "install__release_asset: rejects invalid --sha256 token" {
  run install__release_asset \
    --asset-uri "https://example.com/releases/download/v1/tool" \
    --sha256 "not-a-hash"
  assert_failure
  assert_output --partial "64-char hex"
}

# ---------------------------------------------------------------------------
# install__release_asset — delegation
# ---------------------------------------------------------------------------

@test "install__release_asset: delegates to uri__fetch_asset with asset URI" {
  _stub_release_asset_happy_path
  local _dest="${BATS_TEST_TMPDIR}/bin/tool"
  run install__release_asset \
    --asset-uri "https://example.com/releases/download/v1.0/tool" \
    --binary-src tool \
    --binary-dest "$_dest"
  assert_success
  run head -1 "$_URI_FETCH_CALLS"
  assert_output "https://example.com/releases/download/v1.0/tool"
  run grep -qF -- "--binary-dest" "$_URI_FETCH_CALLS"
  assert_success
  run grep -qF -- "$_dest" "$_URI_FETCH_CALLS"
  assert_success
}

@test "install__release_asset: forwards caller --sha256 to uri__fetch_asset" {
  _stub_release_asset_happy_path
  local _hex="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  run install__release_asset \
    --asset-uri "https://example.com/releases/download/v1.0/tool" \
    --sha256 "$_hex" \
    --binary-dest "${BATS_TEST_TMPDIR}/bin/tool"
  assert_success
  run grep -qF -- "--sha256" "$_URI_FETCH_CALLS"
  assert_success
  run grep -qF -- "$_hex" "$_URI_FETCH_CALLS"
  assert_success
}

@test "install__release_asset: --sha256 none skips sidecar auto-probe" {
  _stub_release_asset_happy_path
  _SIDECAR_PROBE_CALLS="${BATS_TEST_TMPDIR}/sidecar_probes"
  export _SIDECAR_PROBE_CALLS
  net__fetch_url_file() {
    printf '%s\n' "$1" >> "$_SIDECAR_PROBE_CALLS"
    return 1
  }
  export -f net__fetch_url_file

  run --separate-stderr install__release_asset \
    --asset-uri "https://example.com/releases/download/v1.0/tool" \
    --sha256 none \
    --binary-dest "${BATS_TEST_TMPDIR}/bin/tool"
  assert_success
  [[ ! -f "$_SIDECAR_PROBE_CALLS" ]]
}

@test "install__release_asset: relative --sidecar is resolved against release base" {
  _stub_release_asset_happy_path
  run install__release_asset \
    --asset-uri "https://example.com/releases/download/v1.0/tool.tar.gz" \
    --sidecar "tool.tar.gz.sha256" \
    --sha256 none \
    --binary-dest "${BATS_TEST_TMPDIR}/bin/tool"
  assert_success
  run grep -qF "https://example.com/releases/download/v1.0/tool.tar.gz.sha256" "$_URI_FETCH_CALLS"
  assert_success
}

@test "install__release_asset: auto-detected sidecar is forwarded to uri__fetch_asset" {
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"
  local _sidecar="${BATS_TEST_TMPDIR}/tool.sha256"
  printf '%s  tool\n' "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" > "$_sidecar"

  net__fetch_url_file() {
    case "$1" in
      *tool.sha256)
        cp "$_sidecar" "$2"
        return 0
        ;;
      *.sha256 | */SHA256SUMS | */sha256sum.txt) return 1 ;;
    esac
    printf '\x7fELF\x00\x00' > "$2"
    return 0
  }
  export -f net__fetch_url_file
  export _sidecar

  file__detect_type() { printf 'elf'; }
  export -f file__detect_type
  install__copy_bin() {
    touch "$2"
    chmod +x "$2"
    return 0
  }
  export -f install__copy_bin

  _URI_FETCH_CALLS="${BATS_TEST_TMPDIR}/uri_fetch_calls"
  export _URI_FETCH_CALLS
  uri__fetch_asset() {
    printf '%s\n' "$@" >> "$_URI_FETCH_CALLS"
    printf '%s/bin/out\n' "${BATS_TEST_TMPDIR}"
    return 0
  }
  export -f uri__fetch_asset

  run --separate-stderr install__release_asset \
    --asset-uri "https://example.com/releases/download/v1.0/tool" \
    --binary-dest "${BATS_TEST_TMPDIR}/bin/tool"
  assert_success
  run grep -qF -- "--sidecar" "$_URI_FETCH_CALLS"
  assert_success
  run grep -qF "https://example.com/releases/download/v1.0/tool.sha256" "$_URI_FETCH_CALLS"
  assert_success
}
