#!/usr/bin/env bats
# Unit tests for lib/checksum.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  reload_lib checksum.sh
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Write "hello" (no newline) to a temp file and return its path via stdout.
_make_hello_file() {
  local _f="${BATS_TEST_TMPDIR}/hello.bin"
  printf 'hello' > "$_f"
  echo "$_f"
}

# Known SHA-256 of the string "hello" (no newline).
_HELLO_SHA256="2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"

# ---------------------------------------------------------------------------
# checksum::verify_sha256
# ---------------------------------------------------------------------------

@test "checksum::verify_sha256 succeeds for correct hash" {
  local _f
  _f="$(_make_hello_file)"
  run checksum::verify_sha256 "$_f" "$_HELLO_SHA256"
  assert_success
  assert_output --partial "passed"
}

@test "checksum::verify_sha256 fails for wrong hash" {
  local _f
  _f="$(_make_hello_file)"
  run checksum::verify_sha256 "$_f" "000000000000000000000000000000000000000000000000000000000000dead"
  assert_failure
  assert_output --partial "failed"
}

@test "checksum::verify_sha256 prints expected and actual on mismatch" {
  local _f
  _f="$(_make_hello_file)"
  run checksum::verify_sha256 "$_f" "deadbeef"
  assert_output --partial "Expected: deadbeef"
  assert_output --partial "Actual:"
}

# ---------------------------------------------------------------------------
# checksum::verify_sha256_sidecar
# ---------------------------------------------------------------------------

@test "checksum::verify_sha256_sidecar succeeds when sidecar matches" {
  local _f
  _f="$(_make_hello_file)"
  local _sidecar="${BATS_TEST_TMPDIR}/hello.bin.sha256"
  printf '%s  hello.bin\n' "$_HELLO_SHA256" > "$_sidecar"
  run checksum::verify_sha256_sidecar "$_f" "$_sidecar"
  assert_success
}

@test "checksum::verify_sha256_sidecar fails when sidecar is wrong" {
  local _f
  _f="$(_make_hello_file)"
  local _sidecar="${BATS_TEST_TMPDIR}/bad.sha256"
  printf '0000000000000000000000000000000000000000000000000000000000000000  hello.bin\n' \
    > "$_sidecar"
  run checksum::verify_sha256_sidecar "$_f" "$_sidecar"
  assert_failure
}

@test "checksum::verify_sha256_sidecar fails for empty sidecar file" {
  local _f
  _f="$(_make_hello_file)"
  local _sidecar="${BATS_TEST_TMPDIR}/empty.sha256"
  touch "$_sidecar"
  run checksum::verify_sha256_sidecar "$_f" "$_sidecar"
  assert_failure
  assert_output --partial "could not read hash"
}
