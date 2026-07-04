#!/usr/bin/env bats
# Unit tests for lib/uri.bash

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  reload_lib
}

# ── uri__classify ─────────────────────────────────────────────────────────────

@test "uri__classify recognizes http, gh, file, local, oci" {
  run uri__classify "https://example.com/a"
  assert_success
  assert_output "http"

  run uri__classify "gh://org/repo@main:path/to.txt"
  assert_success
  assert_output "gh"

  run uri__classify "file:///etc/hosts"
  assert_success
  assert_output "file"

  run uri__classify "/tmp/foo"
  assert_success
  assert_output "local"

  run uri__classify "oci://ghcr.io/org/img:v1"
  assert_success
  assert_output "oci"
}

@test "uri__classify: ftp/ftps/sftp all return ftp" {
  run uri__classify "ftp://ftp.example.com/pub/file.tar.gz"
  assert_success
  assert_output "ftp"

  run uri__classify "ftps://secure.ftp.com/file"
  assert_success
  assert_output "ftp"

  run uri__classify "sftp://user@host/path/file"
  assert_success
  assert_output "ftp"
}

@test "uri__classify strips fragment before classification" {
  run uri__classify "https://example.com/a#sha256=abc"
  assert_success
  assert_output "http"

  run uri__classify "/tmp/foo#sha256=abc"
  assert_success
  assert_output "local"
}

@test "uri__classify rejects unknown scheme" {
  run uri__classify "s3://bucket/key"
  assert_failure
}

# ── bootstrap__sha256sum ──────────────────────────────────────────────────────

@test "bootstrap__sha256sum: returns 0 when sha256sum is present" {
  run bootstrap__sha256sum
  assert_success
}

@test "bootstrap__sha256sum: returns 0 when only shasum is available" {
  ospkg__run() { return 1; }
  export -f ospkg__run
  create_fake_bin "shasum" "abc123"
  begin_path_isolation
  run bootstrap__sha256sum
  end_path_isolation
  assert_success
}

@test "bootstrap__sha256sum: returns 1 when no sha256 tool available and install fails" {
  ospkg__run() { return 1; }
  export -f ospkg__run
  begin_path_isolation
  run bootstrap__sha256sum
  end_path_isolation
  assert_failure
}

# ── _uri__gh_to_https ─────────────────────────────────────────────────────────

@test "_uri__gh_to_https maps gh:// to raw.githubusercontent.com" {
  run bash -c "source '${LIB_ROOT}/uri.bash'; _uri__gh_to_https 'gh://quantized8/devfeats@v1.2.3:docs/README.md'"
  assert_success
  assert_output "https://raw.githubusercontent.com/quantized8/devfeats/v1.2.3/docs/README.md"
}

@test "_uri__gh_to_https defaults to main when no @ref" {
  run bash -c "source '${LIB_ROOT}/uri.bash'; _uri__gh_to_https 'gh://org/repo:path/file.sh'"
  assert_success
  assert_output "https://raw.githubusercontent.com/org/repo/main/path/file.sh"
}

# ── _uri__sidecar_hash ────────────────────────────────────────────────────────

@test "_uri__sidecar_hash: multi-entry sha256sum format matches by bare filename" {
  local _sc="${BATS_TEST_TMPDIR}/sums.txt"
  printf 'dead0000dead0000dead0000dead0000dead0000dead0000dead0000dead0000  other.bin\n' > "$_sc"
  printf 'beef1111beef1111beef1111beef1111beef1111beef1111beef1111beef1111  tool.tar.gz\n' >> "$_sc"
  run bash -c "source '${LIB_ROOT}/uri.bash'; _uri__sidecar_hash 'tool.tar.gz' '${_sc}'"
  assert_success
  assert_output "beef1111beef1111beef1111beef1111beef1111beef1111beef1111beef1111"
}

@test "_uri__sidecar_hash: BSD-style *<filename> prefix is stripped" {
  local _sc="${BATS_TEST_TMPDIR}/sums.txt"
  printf 'aaaa0000aaaa0000aaaa0000aaaa0000aaaa0000aaaa0000aaaa0000aaaa0000 *tool.tar.gz\n' > "$_sc"
  run bash -c "source '${LIB_ROOT}/uri.bash'; _uri__sidecar_hash 'tool.tar.gz' '${_sc}'"
  assert_success
  assert_output "aaaa0000aaaa0000aaaa0000aaaa0000aaaa0000aaaa0000aaaa0000aaaa0000"
}

@test "_uri__sidecar_hash: path-prefixed entry strips path component (new fix)" {
  local _sc="${BATS_TEST_TMPDIR}/sums.txt"
  printf 'cccc0000cccc0000cccc0000cccc0000cccc0000cccc0000cccc0000cccc0000  ./release/tool.tar.gz\n' > "$_sc"
  run bash -c "source '${LIB_ROOT}/uri.bash'; _uri__sidecar_hash 'tool.tar.gz' '${_sc}'"
  assert_success
  assert_output "cccc0000cccc0000cccc0000cccc0000cccc0000cccc0000cccc0000cccc0000"
}

@test "_uri__sidecar_hash: raw single-hash file (NR==1 NF==1 fallback)" {
  local _sc="${BATS_TEST_TMPDIR}/asset.sha256"
  printf 'dddd0000dddd0000dddd0000dddd0000dddd0000dddd0000dddd0000dddd0000\n' > "$_sc"
  run bash -c "source '${LIB_ROOT}/uri.bash'; _uri__sidecar_hash 'anything' '${_sc}'"
  assert_success
  assert_output "dddd0000dddd0000dddd0000dddd0000dddd0000dddd0000dddd0000dddd0000"
}

@test "_uri__sidecar_hash: returns empty when asset not in multi-entry file" {
  local _sc="${BATS_TEST_TMPDIR}/sums.txt"
  printf 'dead0000dead0000dead0000dead0000dead0000dead0000dead0000dead0000  other.bin\n' > "$_sc"
  run bash -c "source '${LIB_ROOT}/uri.bash'; _uri__sidecar_hash 'missing.bin' '${_sc}'"
  assert_success
  assert_output ""
}

@test "_uri__sidecar_hash: OpenSSL/BSD-style 'SHA256 (file) = hash' format" {
  local _sc="${BATS_TEST_TMPDIR}/CHECKSUMS.txt"
  printf 'SHA256 (tool.tar.gz) = beef1111beef1111beef1111beef1111beef1111beef1111beef1111beef1111\n' > "$_sc"
  run bash -c "source '${LIB_ROOT}/uri.bash'; _uri__sidecar_hash 'tool.tar.gz' '${_sc}'"
  assert_success
  assert_output "beef1111beef1111beef1111beef1111beef1111beef1111beef1111beef1111"
}

@test "_uri__sidecar_hash: OpenSSL/BSD-style format matches correct entry among multiple platforms" {
  local _sc="${BATS_TEST_TMPDIR}/CHECKSUMS.txt"
  {
    printf 'SHA256 (tool-darwin-arm64.zip) = aaaa0000aaaa0000aaaa0000aaaa0000aaaa0000aaaa0000aaaa0000aaaa0000\n'
    printf 'SHA256 (tool-linux-x86_64.zip) = beef1111beef1111beef1111beef1111beef1111beef1111beef1111beef1111\n'
    printf 'SHA256 (tool-linux-arm64.zip) = cccc2222cccc2222cccc2222cccc2222cccc2222cccc2222cccc2222cccc2222\n'
  } > "$_sc"
  run bash -c "source '${LIB_ROOT}/uri.bash'; _uri__sidecar_hash 'tool-linux-x86_64.zip' '${_sc}'"
  assert_success
  assert_output "beef1111beef1111beef1111beef1111beef1111beef1111beef1111beef1111"
}

@test "_uri__sidecar_hash: OpenSSL/BSD-style format returns empty when asset not present" {
  local _sc="${BATS_TEST_TMPDIR}/CHECKSUMS.txt"
  printf 'SHA256 (tool-linux-x86_64.zip) = beef1111beef1111beef1111beef1111beef1111beef1111beef1111beef1111\n' > "$_sc"
  run bash -c "source '${LIB_ROOT}/uri.bash'; _uri__sidecar_hash 'missing.zip' '${_sc}'"
  assert_success
  assert_output ""
}

# ── uri__resolve ──────────────────────────────────────────────────────────────

@test "uri__resolve copies a local file" {
  local _src="${BATS_TEST_TMPDIR}/src.txt"
  printf 'hello-local\n' > "$_src"
  local _dst="${BATS_TEST_TMPDIR}/dst.txt"
  run uri__resolve "$_src" "$_dst"
  assert_success
  run cat "$_dst"
  assert_output "hello-local"
}

@test "uri__resolve reads file:// path" {
  local _src="${BATS_TEST_TMPDIR}/x.yml"
  printf 'y: 1\n' > "$_src"
  local _dst="${BATS_TEST_TMPDIR}/out.yml"
  run uri__resolve "file://${_src}" "$_dst"
  assert_success
  run cat "$_dst"
  assert_output "y: 1"
}

@test "uri__resolve gh:// uses net__fetch_url_file (stubbed)" {
  net__fetch_url_file() {
    printf '%s\n' "$1" > "$2"
  }
  export -f net__fetch_url_file

  local _dst="${BATS_TEST_TMPDIR}/gh.txt"
  run uri__resolve "gh://acme/demo@release:cfg/app.yaml" "$_dst"
  assert_success
  run cat "$_dst"
  assert_output "https://raw.githubusercontent.com/acme/demo/release/cfg/app.yaml"
}

@test "uri__resolve http(s) uses net__fetch_url_file with extra args (stubbed)" {
  net__fetch_url_file() {
    printf 'got\n' > "$2"
    [[ "$3" == "--header" && "$4" == "X-Test: 1" && "$5" == "--netrc-file" && "$6" == "/tmp/n" ]] || return 1
    return 0
  }
  export -f net__fetch_url_file

  local _dst="${BATS_TEST_TMPDIR}/http.bin"
  run uri__resolve "https://example.com/z" "$_dst" --header "X-Test: 1" --netrc-file "/tmp/n"
  assert_success
  run cat "$_dst"
  assert_output "got"
}

@test "uri__resolve http:// uses _uri__net_fetch seam when stubbed (netrc content)" {
  _uri__net_fetch() {
    printf 'machine github.com login x password y\n' > "$2"
  }
  export -f _uri__net_fetch

  local _dst="${BATS_TEST_TMPDIR}/netrc"
  run uri__resolve "http://stub.example/netrc" "$_dst"
  assert_success
  run grep -q '^machine github.com' "$_dst"
  assert_success
}

@test "uri__resolve http:// uses _uri__net_fetch seam when stubbed (conda env YAML)" {
  _uri__net_fetch() {
    printf 'name: from-http-stub\ndependencies:\n  - numpy\n' > "$2"
  }
  export -f _uri__net_fetch

  local _dst="${BATS_TEST_TMPDIR}/env.yml"
  run uri__resolve "http://stub.example/env.yml" "$_dst"
  assert_success
  run grep -q 'from-http-stub' "$_dst"
  assert_success
}

@test "uri__resolve https:// uses _uri__net_fetch seam when stubbed (os-pkg manifest)" {
  _uri__net_fetch() {
    printf '%s\n' 'packages:' '  - tree' > "$2"
  }
  export -f _uri__net_fetch

  local _dst="${BATS_TEST_TMPDIR}/manifest.yaml"
  run uri__resolve "https://stub.internal/manifest.yaml" "$_dst"
  assert_success
  run grep -q '^  - tree' "$_dst"
  assert_success
}

@test "uri__resolve verifies #sha256 for local file" {
  local _src="${BATS_TEST_TMPDIR}/data"
  printf 'payload\n' > "$_src"
  local _expect
  _expect="$(verify__hash_file "$_src")"
  local _dst="${BATS_TEST_TMPDIR}/out"
  run uri__resolve "${_src}#sha256=${_expect}" "$_dst"
  assert_success

  run uri__resolve "${_src}#sha256=0000000000000000000000000000000000000000000000000000000000000000" "${_dst}.bad"
  assert_failure
}

@test "uri__resolve --chmod-exec installs binary with executable bit" {
  local _src="${BATS_TEST_TMPDIR}/script.sh"
  printf '#!/bin/sh\necho ok\n' > "$_src"
  chmod 0644 "$_src"

  local _dst="${BATS_TEST_TMPDIR}/out.sh"
  run uri__resolve "$_src" "$_dst" --chmod-exec
  assert_success
  [[ -x "$_dst" ]]
}

_uri__file_mode_octal() {
  if stat -c '%a' "$1" &> /dev/null; then
    stat -c '%a' "$1"
  else
    stat -f '%OLp' "$1"
  fi
}

@test "uri__resolve --chmod 600 restricts permissions on fetched file" {
  _uri__net_fetch() {
    printf 'machine example.com login u password p\n' > "$2"
  }
  export -f _uri__net_fetch

  local _dst="${BATS_TEST_TMPDIR}/netrc"
  run uri__resolve "http://stub.example/netrc" "$_dst" --chmod 600
  assert_success
  [[ "$(_uri__file_mode_octal "$_dst")" == "600" ]]
}

@test "uri__resolve --chmod +x makes copied script executable" {
  local _src="${BATS_TEST_TMPDIR}/script.sh"
  printf '#!/bin/sh\necho ok\n' > "$_src"
  chmod 0644 "$_src"

  local _dst="${BATS_TEST_TMPDIR}/out.sh"
  run uri__resolve "$_src" "$_dst" --chmod +x
  assert_success
  [[ -x "$_dst" ]]
}

@test "uri__resolve_line --chmod 600 applies only after remote fetch" {
  _uri__net_fetch() {
    printf 'secret\n' > "$2"
  }
  export -f _uri__net_fetch

  local _mdir="${BATS_TEST_TMPDIR}/mat"
  local _out
  _out="$(uri__resolve_line "http://stub.example/secret" "$_mdir" --chmod 600)"
  [[ "$(_uri__file_mode_octal "$_out")" == "600" ]]

  local _local="${BATS_TEST_TMPDIR}/local.txt"
  printf 'x\n' > "$_local"
  local _mode_before
  _mode_before="$(_uri__file_mode_octal "$_local")"
  run uri__resolve_line "$_local" "$_mdir" --chmod 600
  assert_success
  assert_output "$_local"
  [[ "$(_uri__file_mode_octal "$_local")" == "$_mode_before" ]]
}

@test "uri__resolve OCI path is bypassed via stub (_uri__resolve_oci_to)" {
  _uri__resolve_oci_to() {
    printf 'from-oci\n' > "$2"
    return 0
  }

  local _dst="${BATS_TEST_TMPDIR}/oci.txt"
  run uri__resolve "oci://example.com/ns/art:v1?path=x.yaml" "$_dst"
  assert_success
  run cat "$_dst"
  assert_output "from-oci"
}

# ── uri__resolve_line ─────────────────────────────────────────────────────────

@test "uri__resolve_line leaves local paths unchanged" {
  local _p="${BATS_TEST_TMPDIR}/exists"
  touch "$_p"
  run uri__resolve_line "$_p" "${BATS_TEST_TMPDIR}/mat"
  assert_success
  assert_output "$_p"
}

@test "uri__resolve_list resolves two local lines" {
  local _a="${BATS_TEST_TMPDIR}/a"
  local _b="${BATS_TEST_TMPDIR}/b"
  touch "$_a" "$_b"
  run uri__resolve_list "$(printf '%s\n' "$_a" "$_b")" "${BATS_TEST_TMPDIR}/m"
  assert_success
  assert_line -n 0 "$_a"
  assert_line -n 1 "$_b"
}

# ── uri__fetch_asset: common stubs ────────────────────────────────────────────

# _stub_fa_common: minimal stubs for a successful uri__fetch_asset call.
# net__fetch_url_file writes the requested URL to the dest file.
# verify__sha and verify__gpg_detached record their calls.
# file__detect_type returns "elf" (non-archive).
# install__copy_bin and install__track_internal_path are no-ops that copy the file.
_stub_fa_common() {
  net__fetch_url_file() { printf '%s\n' "$1" > "$2"; }
  export -f net__fetch_url_file

  _VERIFY_SHA_CALLS="${BATS_TEST_TMPDIR}/_sha_calls"
  export _VERIFY_SHA_CALLS
  verify__sha() {
    printf '%s %s\n' "$1" "$2" >> "$_VERIFY_SHA_CALLS"
    return 0
  }
  export -f verify__sha

  _VERIFY_GPG_CALLS="${BATS_TEST_TMPDIR}/_gpg_calls"
  export _VERIFY_GPG_CALLS
  verify__gpg_detached() {
    printf '%s\n' "$@" >> "$_VERIFY_GPG_CALLS"
    return 0
  }
  export -f verify__gpg_detached

  file__detect_type() { printf 'elf'; }
  export -f file__detect_type

  install__copy_bin() { cp "$1" "$2" && chmod +x "$2"; }
  export -f install__copy_bin

  install__track_internal_path() { return 0; }
  export -f install__track_internal_path
}

# ── uri__fetch_asset: argument validation ────────────────────────────────────

@test "uri__fetch_asset: URI (positional first arg) is required" {
  run uri__fetch_asset --file-dest "${BATS_TEST_TMPDIR}/out"
  assert_failure
  assert_output --partial "URI is required"
}

@test "uri__fetch_asset: unknown option is rejected" {
  run uri__fetch_asset /tmp/x --bogus-option
  assert_failure
  assert_output --partial "unknown option"
}

@test "uri__fetch_asset: --binary-src requires --binary-dest" {
  run uri__fetch_asset /tmp/x --binary-src foo
  assert_failure
  assert_output --partial "--binary-src requires --binary-dest"
}

@test "uri__fetch_asset: --file-src requires --file-dest" {
  run uri__fetch_asset /tmp/x --file-src foo
  assert_failure
  assert_output --partial "--file-src requires --file-dest"
}

@test "uri__fetch_asset: --sha256 none cannot combine with --sidecar" {
  run uri__fetch_asset "https://x.com/a" \
    --sha256 none --sidecar "https://x.com/a.sha256"
  assert_failure
  assert_output --partial "none"
}

@test "uri__fetch_asset: invalid --sha256 hex is rejected" {
  run uri__fetch_asset /tmp/x --sha256 "not-a-hex" --file-dest /tmp/out
  assert_failure
  assert_output --partial "--sha256"
}

@test "uri__fetch_asset: N=1 binary-src, M=2 binary-dest is rejected (N≠M, M>1)" {
  local _src="${BATS_TEST_TMPDIR}/src"
  touch "$_src"
  run uri__fetch_asset "$_src" \
    --binary-src tool \
    --binary-dest /tmp/bin/a \
    --binary-dest /tmp/bin/b
  assert_failure
  assert_output --partial "--binary-dest"
}

@test "uri__fetch_asset: N=1 file-src, M=2 file-dest is rejected (N≠M, M>1)" {
  local _src="${BATS_TEST_TMPDIR}/src"
  touch "$_src"
  run uri__fetch_asset "$_src" \
    --file-src data.txt \
    --file-dest /tmp/a.txt \
    --file-dest /tmp/b.txt
  assert_failure
  assert_output --partial "--file-dest"
}

# ── uri__fetch_asset: download routing ───────────────────────────────────────

@test "uri__fetch_asset: local file copied via --file-dest, path on stdout" {
  local _src="${BATS_TEST_TMPDIR}/src.txt"
  printf 'hello\n' > "$_src"
  local _dst="${BATS_TEST_TMPDIR}/dst.txt"
  run --separate-stderr uri__fetch_asset "$_src" --file-dest "$_dst" --sha256 none
  assert_success
  assert_output "$_dst"
  run cat "$_dst"
  assert_output "hello"
}

@test "uri__fetch_asset: https URL calls net__fetch_url_file (stubbed)" {
  _stub_fa_common
  local _dst="${BATS_TEST_TMPDIR}/http.bin"
  run --separate-stderr uri__fetch_asset \
    "https://example.com/file.bin" --file-dest "$_dst" --sha256 none
  assert_success
  assert_output "$_dst"
  run cat "$_dst"
  assert_output "https://example.com/file.bin"
}

@test "uri__fetch_asset: ftp:// URI routes through net__fetch_url_file" {
  _FETCH_LOG="${BATS_TEST_TMPDIR}/_ftp_log"
  export _FETCH_LOG
  net__fetch_url_file() {
    printf '%s\n' "$1" > "$_FETCH_LOG"
    printf 'content\n' > "$2"
  }
  export -f net__fetch_url_file

  local _dst="${BATS_TEST_TMPDIR}/ftp.out"
  run --separate-stderr uri__fetch_asset \
    "ftp://ftp.example.com/pub/file.tar" --file-dest "$_dst" --sha256 none
  assert_success
  run grep -q "ftp://ftp.example.com" "$_FETCH_LOG"
  assert_success
}

@test "uri__fetch_asset: file:// URI copies from absolute path" {
  local _src="${BATS_TEST_TMPDIR}/x.conf"
  printf 'cfg\n' > "$_src"
  local _dst="${BATS_TEST_TMPDIR}/out.conf"
  run --separate-stderr uri__fetch_asset \
    "file://${_src}" --file-dest "$_dst" --sha256 none
  assert_success
  run cat "$_dst"
  assert_output "cfg"
}

# ── uri__fetch_asset: sha256 verification ────────────────────────────────────

@test "uri__fetch_asset: #sha256 fragment is verified automatically" {
  _stub_fa_common
  local _src="${BATS_TEST_TMPDIR}/payload"
  printf 'data\n' > "$_src"
  local _hex
  _hex="$(verify__hash_file "$_src")"
  local _dst="${BATS_TEST_TMPDIR}/out"
  run --separate-stderr uri__fetch_asset \
    "${_src}#sha256=${_hex}" --file-dest "$_dst"
  assert_success
  run grep -qF "$_hex" "$_VERIFY_SHA_CALLS"
  assert_success
}

@test "uri__fetch_asset: wrong #sha256 fragment causes failure" {
  local _src="${BATS_TEST_TMPDIR}/payload"
  printf 'data\n' > "$_src"
  local _dst="${BATS_TEST_TMPDIR}/out"
  local _zerohex="0000000000000000000000000000000000000000000000000000000000000000"
  run uri__fetch_asset "${_src}#sha256=${_zerohex}" --file-dest "$_dst"
  assert_failure
}

@test "uri__fetch_asset: --sha256 hex is verified via verify__sha" {
  _stub_fa_common
  local _src="${BATS_TEST_TMPDIR}/payload"
  printf 'data\n' > "$_src"
  local _hex
  _hex="$(verify__hash_file "$_src")"
  local _dst="${BATS_TEST_TMPDIR}/out"
  run --separate-stderr uri__fetch_asset "$_src" --sha256 "$_hex" --file-dest "$_dst"
  assert_success
  run grep -qF "$_hex" "$_VERIFY_SHA_CALLS"
  assert_success
}

@test "uri__fetch_asset: --sha256 none suppresses all sha checks" {
  _stub_fa_common
  local _src="${BATS_TEST_TMPDIR}/payload"
  printf 'data\n' > "$_src"
  local _dst="${BATS_TEST_TMPDIR}/out"
  run --separate-stderr uri__fetch_asset "$_src" --sha256 none --file-dest "$_dst"
  assert_success
  [[ ! -f "$_VERIFY_SHA_CALLS" ]] || [[ ! -s "$_VERIFY_SHA_CALLS" ]]
}

@test "uri__fetch_asset: --sidecar multi-entry format matched by filename" {
  _stub_fa_common
  local _src="${BATS_TEST_TMPDIR}/asset.bin"
  printf 'content\n' > "$_src"
  local _hash="aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd"
  local _sc="${BATS_TEST_TMPDIR}/checksums.sha256"
  printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef  other.bin\n' > "$_sc"
  printf '%s  asset.bin\n' "$_hash" >> "$_sc"
  local _dst="${BATS_TEST_TMPDIR}/out.bin"
  run --separate-stderr uri__fetch_asset \
    "$_src" --sidecar "file://${_sc}" --file-dest "$_dst"
  assert_success
  run grep -qF "$_hash" "$_VERIFY_SHA_CALLS"
  assert_success
}

@test "uri__fetch_asset: --sidecar raw single-hash uses NR==1 NF==1 fallback" {
  _stub_fa_common
  local _src="${BATS_TEST_TMPDIR}/asset.bin"
  printf 'content\n' > "$_src"
  local _hash="aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd"
  local _sc="${BATS_TEST_TMPDIR}/asset.sha256"
  printf '%s\n' "$_hash" > "$_sc"
  local _dst="${BATS_TEST_TMPDIR}/out.bin"
  run --separate-stderr uri__fetch_asset \
    "$_src" --sidecar "file://${_sc}" --file-dest "$_dst"
  assert_success
  run grep -qF "$_hash" "$_VERIFY_SHA_CALLS"
  assert_success
}

@test "uri__fetch_asset: --sidecar fails when asset name not found in sidecar" {
  local _src="${BATS_TEST_TMPDIR}/asset.bin"
  printf 'content\n' > "$_src"
  local _sc="${BATS_TEST_TMPDIR}/checksums.sha256"
  printf 'aaaa0000aaaa0000aaaa0000aaaa0000aaaa0000aaaa0000aaaa0000aaaa0000  other.bin\n' > "$_sc"
  run uri__fetch_asset \
    "$_src" --sidecar "file://${_sc}" --file-dest "${BATS_TEST_TMPDIR}/out.bin"
  assert_failure
  assert_output --partial "could not extract hash"
}

# ── uri__fetch_asset: retry on hash mismatch ─────────────────────────────────

@test "uri__fetch_asset: retries up to --retry N times on hash mismatch then fails" {
  local _attempt_file="${BATS_TEST_TMPDIR}/attempts"
  printf '0' > "$_attempt_file"
  net__fetch_url_file() {
    local _n
    _n="$(cat "$_attempt_file")"
    _n=$((_n + 1))
    printf '%d' "$_n" > "$_attempt_file"
    printf 'wrong content\n' > "$2"
  }
  export -f net__fetch_url_file
  export _attempt_file

  file__detect_type() { printf 'elf'; }
  export -f file__detect_type

  local _src="${BATS_TEST_TMPDIR}/good.bin"
  printf 'correct content\n' > "$_src"
  local _good_hex
  _good_hex="$(verify__hash_file "$_src")"
  local _dst="${BATS_TEST_TMPDIR}/out.bin"

  run uri__fetch_asset "https://example.com/good.bin" \
    --sha256 "$_good_hex" --file-dest "$_dst" --retry 2
  assert_failure
  assert_output --partial "after 2 attempt(s)"
  local _n
  _n="$(cat "$_attempt_file")"
  [[ "$_n" -eq 2 ]]
}

@test "uri__fetch_asset: succeeds when hash passes on second attempt" {
  local _src="${BATS_TEST_TMPDIR}/real.bin"
  printf 'real content\n' > "$_src"
  local _good_hex
  _good_hex="$(verify__hash_file "$_src")"

  local _attempt_file="${BATS_TEST_TMPDIR}/attempts"
  printf '0' > "$_attempt_file"
  export _attempt_file _src _good_hex

  net__fetch_url_file() {
    local _n
    _n="$(cat "$_attempt_file")"
    _n=$((_n + 1))
    printf '%d' "$_n" > "$_attempt_file"
    if [[ "$_n" -eq 1 ]]; then
      printf 'wrong\n' > "$2"
    else
      cat "$_src" > "$2"
    fi
  }
  export -f net__fetch_url_file

  file__detect_type() { printf 'elf'; }
  export -f file__detect_type

  install__copy_bin() { cp "$1" "$2" && chmod +x "$2"; }
  export -f install__copy_bin

  local _dst="${BATS_TEST_TMPDIR}/out.bin"
  run --separate-stderr uri__fetch_asset "https://example.com/real.bin" \
    --sha256 "$_good_hex" --file-dest "$_dst" --retry 3
  assert_success
  local _n
  _n="$(cat "$_attempt_file")"
  [[ "$_n" -eq 2 ]]
}

# ── uri__fetch_asset: --header and --netrc-file ───────────────────────────────

@test "uri__fetch_asset: --header and --netrc-file forwarded to net__fetch_url_file" {
  _FETCH_LOG="${BATS_TEST_TMPDIR}/_fetch_log"
  export _FETCH_LOG
  net__fetch_url_file() {
    printf '%s\n' "$@" > "$_FETCH_LOG"
    printf 'ok\n' > "$2"
  }
  export -f net__fetch_url_file

  local _dst="${BATS_TEST_TMPDIR}/out"
  run --separate-stderr uri__fetch_asset \
    "https://example.com/f" --file-dest "$_dst" --sha256 none \
    --header "X-Tok: abc" --netrc-file "/tmp/nr"
  assert_success
  run grep -q "X-Tok: abc" "$_FETCH_LOG"
  assert_success
  run grep -q "/tmp/nr" "$_FETCH_LOG"
  assert_success
}

# ── uri__fetch_asset: GPG verification ───────────────────────────────────────

@test "uri__fetch_asset: GPG verification calls verify__gpg_detached" {
  _stub_fa_common
  net__fetch_url_file() { printf 'stub\n' > "$2"; }
  export -f net__fetch_url_file

  local _src="${BATS_TEST_TMPDIR}/payload"
  printf 'data\n' > "$_src"
  local _dst="${BATS_TEST_TMPDIR}/out"
  run --separate-stderr uri__fetch_asset \
    "$_src" --file-dest "$_dst" --sha256 none \
    --gpg-key "https://example.com/key.gpg" \
    --gpg-sig "https://example.com/payload.asc"
  assert_success
  [[ -s "$_VERIFY_GPG_CALLS" ]]
}

@test "uri__fetch_asset: --gpg-sig defaults to <uri>.asc when not set" {
  _stub_fa_common
  _FETCH_LOG="${BATS_TEST_TMPDIR}/_fetch_log"
  export _FETCH_LOG
  net__fetch_url_file() {
    printf '%s\n' "$1" >> "$_FETCH_LOG"
    printf 'stub\n' > "$2"
  }
  export -f net__fetch_url_file

  local _src="${BATS_TEST_TMPDIR}/payload.bin"
  printf 'data\n' > "$_src"
  local _dst="${BATS_TEST_TMPDIR}/out"
  run --separate-stderr uri__fetch_asset \
    "https://example.com/payload.bin" --file-dest "$_dst" --sha256 none \
    --gpg-key "https://example.com/key.gpg"
  assert_success
  run grep -q "payload.bin.asc" "$_FETCH_LOG"
  assert_success
}

@test "uri__fetch_asset: GPG runs independently of --sha256 none" {
  _stub_fa_common
  net__fetch_url_file() { printf 'stub\n' > "$2"; }
  export -f net__fetch_url_file

  local _src="${BATS_TEST_TMPDIR}/payload"
  printf 'data\n' > "$_src"
  local _dst="${BATS_TEST_TMPDIR}/out"
  run --separate-stderr uri__fetch_asset \
    "$_src" --file-dest "$_dst" --sha256 none \
    --gpg-key "https://example.com/key.gpg" \
    --gpg-sig "https://example.com/payload.asc"
  assert_success
  [[ -s "$_VERIFY_GPG_CALLS" ]]
  [[ ! -f "$_VERIFY_SHA_CALLS" ]] || [[ ! -s "$_VERIFY_SHA_CALLS" ]]
}

# ── uri__fetch_asset: sidecar GPG verification ────────────────────────────────

@test "uri__fetch_asset: --sidecar-gpg-key requires --sidecar" {
  run uri__fetch_asset /tmp/x --sidecar-gpg-key "https://example.com/key.gpg"
  assert_failure
  assert_output --partial "--sidecar-gpg-key requires --sidecar"
}

@test "uri__fetch_asset: sidecar GPG verification calls verify__gpg_detached with the sidecar file" {
  _stub_fa_common
  local _src="${BATS_TEST_TMPDIR}/asset.bin"
  printf 'content\n' > "$_src"
  local _hash="aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd"
  local _sc="${BATS_TEST_TMPDIR}/checksums.sha256"
  printf '%s  asset.bin\n' "$_hash" > "$_sc"
  local _dst="${BATS_TEST_TMPDIR}/out.bin"
  run --separate-stderr uri__fetch_asset \
    "$_src" --sidecar "file://${_sc}" --file-dest "$_dst" \
    --sidecar-gpg-key "https://example.com/key.gpg" \
    --sidecar-gpg-sig "https://example.com/checksums.sha256.asc"
  assert_success
  run grep -qF "checksums.sha256" "$_VERIFY_GPG_CALLS"
  assert_success
}

@test "uri__fetch_asset: --sidecar-gpg-sig defaults to <sidecar-uri>.asc when not set" {
  _stub_fa_common
  _FETCH_LOG="${BATS_TEST_TMPDIR}/_fetch_log"
  export _FETCH_LOG
  local _hash="aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd"
  net__fetch_url_file() {
    printf '%s\n' "$1" >> "$_FETCH_LOG"
    case "$1" in
      *checksums.sha256) printf '%s  asset.bin\n' "$_hash" > "$2" ;;
      *) printf 'stub\n' > "$2" ;;
    esac
  }
  export -f net__fetch_url_file

  local _src="${BATS_TEST_TMPDIR}/asset.bin"
  printf 'content\n' > "$_src"
  local _dst="${BATS_TEST_TMPDIR}/out.bin"
  run --separate-stderr uri__fetch_asset \
    "$_src" --sidecar "https://example.com/checksums.sha256" --file-dest "$_dst" \
    --sidecar-gpg-key "https://example.com/key.gpg"
  assert_success
  run grep -qF "checksums.sha256.asc" "$_FETCH_LOG"
  assert_success
}

@test "uri__fetch_asset: asset GPG and sidecar GPG verify independently when both configured" {
  _stub_fa_common
  # Override to record one line per call (space-joined args) so calls are countable.
  verify__gpg_detached() {
    printf '%s\n' "$*" >> "$_VERIFY_GPG_CALLS"
    return 0
  }
  export -f verify__gpg_detached

  local _src="${BATS_TEST_TMPDIR}/asset.bin"
  printf 'content\n' > "$_src"
  local _hash="aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd"
  local _sc="${BATS_TEST_TMPDIR}/checksums.sha256"
  printf '%s  asset.bin\n' "$_hash" > "$_sc"
  local _dst="${BATS_TEST_TMPDIR}/out.bin"
  run --separate-stderr uri__fetch_asset \
    "$_src" --sidecar "file://${_sc}" --file-dest "$_dst" \
    --gpg-key "https://example.com/asset-key.gpg" \
    --gpg-sig "https://example.com/asset.asc" \
    --sidecar-gpg-key "https://example.com/sidecar-key.gpg" \
    --sidecar-gpg-sig "https://example.com/checksums.sha256.asc"
  assert_success
  [[ "$(wc -l < "$_VERIFY_GPG_CALLS")" -eq 2 ]]
  run grep -qF "asset.bin" "$_VERIFY_GPG_CALLS"
  assert_success
  run grep -qF "checksums.sha256" "$_VERIFY_GPG_CALLS"
  assert_success
}

# ── uri__fetch_asset: installer-dir and work-dir layout ──────────────────────

@test "uri__fetch_asset: no install flags prints asset/ directory path" {
  local _src="${BATS_TEST_TMPDIR}/data.bin"
  printf 'payload\n' > "$_src"
  run --separate-stderr uri__fetch_asset "$_src" --sha256 none
  assert_success
  # Output is the asset/ directory, not a file path.
  assert_output --regexp ".*/asset$"
  [[ -d "$output" ]]
}

@test "uri__fetch_asset: --installer-dir places work tree under that dir" {
  local _src="${BATS_TEST_TMPDIR}/myfile.bin"
  printf 'content\n' > "$_src"
  local _idir="${BATS_TEST_TMPDIR}/idir"
  mkdir -p "$_idir"
  run --separate-stderr uri__fetch_asset \
    "$_src" --installer-dir "$_idir" --sha256 none
  assert_success
  # Prints the asset/ dir under installer-dir.
  assert_output "${_idir}/asset"
  [[ -f "${_idir}/asset/myfile.bin" ]]
}

@test "uri__fetch_asset: --installer-dir is idempotent (sub-dirs recreated)" {
  local _src="${BATS_TEST_TMPDIR}/myfile.bin"
  printf 'v1\n' > "$_src"
  local _idir="${BATS_TEST_TMPDIR}/idir"
  mkdir -p "$_idir"
  uri__fetch_asset "$_src" --installer-dir "$_idir" --sha256 none > /dev/null
  # Overwrite source and call again.
  printf 'v2\n' > "$_src"
  run --separate-stderr uri__fetch_asset "$_src" --installer-dir "$_idir" --sha256 none
  assert_success
  run cat "${_idir}/asset/myfile.bin"
  assert_output "v2"
}

# ── uri__fetch_asset: --filename override ────────────────────────────────────

@test "uri__fetch_asset: --filename overrides URI basename for asset name" {
  local _src="${BATS_TEST_TMPDIR}/odd-name-v1.2.3"
  printf 'data\n' > "$_src"
  local _idir="${BATS_TEST_TMPDIR}/idir"
  run --separate-stderr uri__fetch_asset \
    "$_src" --filename "tool.bin" --installer-dir "$_idir" --sha256 none
  assert_success
  [[ -f "${_idir}/asset/tool.bin" ]]
}

# ── uri__fetch_asset: --file-dest (plain copy, no exec bit) ──────────────────

@test "uri__fetch_asset: --file-dest installs non-archive as plain copy" {
  local _src="${BATS_TEST_TMPDIR}/data.conf"
  printf 'key=value\n' > "$_src"
  local _dst="${BATS_TEST_TMPDIR}/out.conf"
  run --separate-stderr uri__fetch_asset \
    "$_src" --file-dest "$_dst" --sha256 none
  assert_success
  assert_output "$_dst"
  run cat "$_dst"
  assert_output "key=value"
}

@test "uri__fetch_asset: --file-dest with trailing slash uses URI basename" {
  local _src="${BATS_TEST_TMPDIR}/data.conf"
  printf 'key=value\n' > "$_src"
  local _dir="${BATS_TEST_TMPDIR}/dest_dir"
  mkdir -p "$_dir"
  run --separate-stderr uri__fetch_asset \
    "$_src" --file-dest "${_dir}/" --sha256 none
  assert_success
  assert_output "${_dir}/data.conf"
  [[ -f "${_dir}/data.conf" ]]
}

@test "uri__fetch_asset: archive + --file-src + --file-dest extracts specific file" {
  file__detect_type() { printf 'gzip'; }
  export -f file__detect_type
  file__extract_archive() {
    mkdir -p "$2/etc"
    printf 'config content\n' > "$2/etc/app.conf"
    return 0
  }
  export -f file__extract_archive

  local _src="${BATS_TEST_TMPDIR}/app.tar.gz"
  printf 'fake\n' > "$_src"
  local _dst="${BATS_TEST_TMPDIR}/app.conf"
  run --separate-stderr uri__fetch_asset \
    "$_src" --file-src "etc/app.conf" --file-dest "$_dst" --sha256 none
  assert_success
  assert_output "$_dst"
  run cat "$_dst"
  assert_output "config content"
}

@test "uri__fetch_asset: archive + --file-dest without --file-src fails (no auto-discovery)" {
  file__detect_type() { printf 'gzip'; }
  export -f file__detect_type
  file__extract_archive() {
    mkdir -p "$2"
    printf 'x\n' > "$2/file.txt"
    return 0
  }
  export -f file__extract_archive

  local _src="${BATS_TEST_TMPDIR}/app.tar.gz"
  printf 'fake\n' > "$_src"
  run uri__fetch_asset \
    "$_src" --file-dest "${BATS_TEST_TMPDIR}/out.txt" --sha256 none
  assert_failure
  assert_output --partial "--file-src"
}

# ── uri__fetch_asset: --binary-dest (install__copy_bin) ──────────────────────

@test "uri__fetch_asset: direct binary installed to exact --binary-dest path" {
  _stub_fa_common
  local _src="${BATS_TEST_TMPDIR}/mytool"
  printf '#!/bin/sh\n' > "$_src"
  chmod +x "$_src"
  local _dst="${BATS_TEST_TMPDIR}/out/mytool"
  mkdir -p "$(dirname "$_dst")"
  run --separate-stderr uri__fetch_asset \
    "$_src" --binary-dest "$_dst" --sha256 none
  assert_success
  assert_output "$_dst"
  [[ -f "$_dst" ]]
}

@test "uri__fetch_asset: direct binary installed into --binary-dest directory (trailing slash)" {
  _stub_fa_common
  local _src="${BATS_TEST_TMPDIR}/mytool"
  printf '#!/bin/sh\n' > "$_src"
  chmod +x "$_src"
  local _dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$_dir"
  run --separate-stderr uri__fetch_asset \
    "$_src" --binary-dest "${_dir}/" --sha256 none
  assert_success
  assert_output "${_dir}/mytool"
  [[ -f "${_dir}/mytool" ]]
}

@test "uri__fetch_asset: archive binary installed via --binary-src suffix match" {
  _stub_fa_common
  file__detect_type() { printf 'gzip'; }
  export -f file__detect_type
  file__extract_archive() {
    mkdir -p "$2/bin"
    printf '#!/bin/sh\n' > "$2/bin/mytool"
    chmod +x "$2/bin/mytool"
    return 0
  }
  export -f file__extract_archive

  local _src="${BATS_TEST_TMPDIR}/archive.tar.gz"
  printf 'fake\n' > "$_src"
  local _bdest="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$_bdest"
  run --separate-stderr uri__fetch_asset \
    "$_src" --binary-src "bin/mytool" --binary-dest "${_bdest}/" --sha256 none
  assert_success
  assert_output "${_bdest}/mytool"
  [[ -f "${_bdest}/mytool" ]]
}

@test "uri__fetch_asset: archive auto-discovers all executables when no --binary-src" {
  _stub_fa_common
  file__detect_type() { printf 'gzip'; }
  export -f file__detect_type
  file__extract_archive() {
    mkdir -p "$2"
    printf '#!/bin/sh\n' > "$2/tool-a"
    printf '#!/bin/sh\n' > "$2/tool-b"
    chmod +x "$2/tool-a" "$2/tool-b"
    return 0
  }
  export -f file__extract_archive

  local _src="${BATS_TEST_TMPDIR}/archive.tar.gz"
  printf 'fake\n' > "$_src"
  local _bdest="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$_bdest"
  run --separate-stderr uri__fetch_asset \
    "$_src" --binary-dest "${_bdest}/" --sha256 none
  assert_success
  assert_line --partial "tool-a"
  assert_line --partial "tool-b"
  [[ -f "${_bdest}/tool-a" && -f "${_bdest}/tool-b" ]]
}

@test "uri__fetch_asset: auto-discovery with exact (non-dir) dest fails when >1 executable" {
  _stub_fa_common
  file__detect_type() { printf 'gzip'; }
  export -f file__detect_type
  file__extract_archive() {
    mkdir -p "$2"
    printf '#!/bin/sh\n' > "$2/tool-a"
    printf '#!/bin/sh\n' > "$2/tool-b"
    chmod +x "$2/tool-a" "$2/tool-b"
    return 0
  }
  export -f file__extract_archive

  local _src="${BATS_TEST_TMPDIR}/archive.tar.gz"
  printf 'fake\n' > "$_src"
  run uri__fetch_asset \
    "$_src" --binary-dest "${BATS_TEST_TMPDIR}/bin/exact-name" --sha256 none
  assert_failure
  assert_output --partial "auto-discovery"
}

@test "uri__fetch_asset: ambiguous --binary-src (multiple matches) fails" {
  _stub_fa_common
  file__detect_type() { printf 'gzip'; }
  export -f file__detect_type
  file__extract_archive() {
    mkdir -p "$2/a" "$2/b"
    printf '#!/bin/sh\n' > "$2/a/tool"
    printf '#!/bin/sh\n' > "$2/b/tool"
    chmod +x "$2/a/tool" "$2/b/tool"
    return 0
  }
  export -f file__extract_archive

  local _src="${BATS_TEST_TMPDIR}/archive.tar.gz"
  printf 'fake\n' > "$_src"
  run uri__fetch_asset \
    "$_src" --binary-src "tool" --binary-dest "${BATS_TEST_TMPDIR}/bin/" --sha256 none
  assert_failure
  assert_output --partial "ambiguous"
}

@test "uri__fetch_asset: --binary-src not found in archive fails" {
  _stub_fa_common
  file__detect_type() { printf 'gzip'; }
  export -f file__detect_type
  file__extract_archive() {
    mkdir -p "$2"
    printf '#!/bin/sh\n' > "$2/other"
    return 0
  }
  export -f file__extract_archive

  local _src="${BATS_TEST_TMPDIR}/archive.tar.gz"
  printf 'fake\n' > "$_src"
  run uri__fetch_asset \
    "$_src" --binary-src "nothere" --binary-dest "${BATS_TEST_TMPDIR}/bin/" --sha256 none
  assert_failure
  assert_output --partial "not found"
}

@test "uri__fetch_asset: N=M binary pairing installs each src to matching dest" {
  _stub_fa_common
  file__detect_type() { printf 'gzip'; }
  export -f file__detect_type
  file__extract_archive() {
    mkdir -p "$2/bin"
    printf '#!/bin/sh\necho a\n' > "$2/bin/tool-a"
    printf '#!/bin/sh\necho b\n' > "$2/bin/tool-b"
    chmod +x "$2/bin/tool-a" "$2/bin/tool-b"
    return 0
  }
  export -f file__extract_archive

  local _src="${BATS_TEST_TMPDIR}/archive.tar.gz"
  printf 'fake\n' > "$_src"
  local _out1="${BATS_TEST_TMPDIR}/dest/a"
  local _out2="${BATS_TEST_TMPDIR}/dest/b"
  mkdir -p "${BATS_TEST_TMPDIR}/dest"
  run --separate-stderr uri__fetch_asset "$_src" \
    --binary-src "bin/tool-a" --binary-dest "$_out1" \
    --binary-src "bin/tool-b" --binary-dest "$_out2" \
    --sha256 none
  assert_success
  assert_line -n 0 "$_out1"
  assert_line -n 1 "$_out2"
  [[ -f "$_out1" && -f "$_out2" ]]
}

@test "uri__fetch_asset: fan-out (N>1 src, 1 dir dest) installs all to that dir" {
  _stub_fa_common
  file__detect_type() { printf 'gzip'; }
  export -f file__detect_type
  file__extract_archive() {
    mkdir -p "$2/bin"
    printf '#!/bin/sh\n' > "$2/bin/tool-a"
    printf '#!/bin/sh\n' > "$2/bin/tool-b"
    chmod +x "$2/bin/tool-a" "$2/bin/tool-b"
    return 0
  }
  export -f file__extract_archive

  local _src="${BATS_TEST_TMPDIR}/archive.tar.gz"
  printf 'fake\n' > "$_src"
  local _dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$_dir"
  run --separate-stderr uri__fetch_asset "$_src" \
    --binary-src "bin/tool-a" \
    --binary-src "bin/tool-b" \
    --binary-dest "${_dir}/" \
    --sha256 none
  assert_success
  [[ -f "${_dir}/tool-a" && -f "${_dir}/tool-b" ]]
}

# ── uri__fetch_asset: --chmod-exec <spec> ────────────────────────────────────

@test "uri__fetch_asset: --chmod-exec sets exec bit on matched file in asset/ in-place" {
  local _src="${BATS_TEST_TMPDIR}/tool"
  printf '#!/bin/sh\necho ok\n' > "$_src"
  chmod 0644 "$_src"

  local _idir="${BATS_TEST_TMPDIR}/idir"
  run --separate-stderr uri__fetch_asset \
    "$_src" --installer-dir "$_idir" --chmod-exec "tool" --sha256 none
  assert_success
  [[ -x "${_idir}/asset/tool" ]]
}

@test "uri__fetch_asset: --chmod-exec fails when spec matches nothing" {
  local _src="${BATS_TEST_TMPDIR}/tool"
  printf 'data\n' > "$_src"
  local _idir="${BATS_TEST_TMPDIR}/idir"
  run uri__fetch_asset \
    "$_src" --installer-dir "$_idir" --chmod-exec "nonexistent" --sha256 none
  assert_failure
  assert_output --partial "no match"
}

# ── uri__fetch_asset: --owner-group ──────────────────────────────────────────

@test "uri__fetch_asset: --owner-group calls install__track_internal_path" {
  _stub_fa_common
  _TRACK_CALLS="${BATS_TEST_TMPDIR}/_track_calls"
  export _TRACK_CALLS
  install__track_internal_path() {
    printf '%s %s\n' "$1" "$2" >> "$_TRACK_CALLS"
  }
  export -f install__track_internal_path

  local _src="${BATS_TEST_TMPDIR}/tool"
  printf '#!/bin/sh\n' > "$_src"
  chmod +x "$_src"
  local _dst="${BATS_TEST_TMPDIR}/out/tool"
  mkdir -p "$(dirname "$_dst")"
  run --separate-stderr uri__fetch_asset \
    "$_src" --binary-dest "$_dst" --owner-group "mygroup" --sha256 none
  assert_success
  run grep -q "mygroup" "$_TRACK_CALLS"
  assert_success
}

# ── uri__resolve wrapper ──────────────────────────────────────────────────────

@test "uri__resolve wraps uri__fetch_asset (positional args mapped correctly)" {
  local _src="${BATS_TEST_TMPDIR}/data.txt"
  printf 'wrapped\n' > "$_src"
  local _dst="${BATS_TEST_TMPDIR}/out.txt"
  run uri__resolve "$_src" "$_dst"
  assert_success
  run cat "$_dst"
  assert_output "wrapped"
}
