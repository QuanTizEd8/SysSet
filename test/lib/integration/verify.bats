#!/usr/bin/env bats
# Integration tests for lib/verify.bash — exercises real GPG operations.
#
# verify__gpg_detached, verify__gpg_dearmor_stream, and
# verify__gpg_fetch_key_by_fingerprint have no tests of any kind in the
# unit suite. These tests generate a throwaway keypair, sign an artifact,
# and verify the full GPG pipeline.

bats_require_minimum_version 1.5.0

setup_file() {
  load '../helpers/common'

  command -v gpg > /dev/null 2>&1 || {
    echo "prepared integration environment is missing required gpg" >&2
    return 1
  }

  # Isolated GNUPGHOME so we don't pollute the system keyring.
  export GNUPGHOME="${BATS_FILE_TMPDIR}/gnupg"
  mkdir -m 700 "${GNUPGHOME}"

  # Generate a throwaway RSA keypair.
  gpg --batch --gen-key << 'EOF'
Key-Type: RSA
Key-Length: 2048
Name-Real: DevFeats Test Key
%no-protection
%commit
EOF

  # Export armored public key.
  gpg --armor --export > "${BATS_FILE_TMPDIR}/test.pub.asc"

  # Capture the fingerprint for keyserver tests.
  gpg --with-colons --fingerprint |
    awk -F: '/^fpr/{print $10; exit}' \
      > "${BATS_FILE_TMPDIR}/fingerprint"

  # Create a test artifact and sign it.
  printf 'test payload\n' > "${BATS_FILE_TMPDIR}/artifact.txt"
  gpg --detach-sign --armor \
    --output "${BATS_FILE_TMPDIR}/artifact.txt.asc" \
    "${BATS_FILE_TMPDIR}/artifact.txt"

  # Dearmor the public key for use with verify__gpg_detached.
  gpg --dearmor \
    < "${BATS_FILE_TMPDIR}/test.pub.asc" \
    > "${BATS_FILE_TMPDIR}/test.pub.gpg"

  # Generate a second keypair (same GNUPGHOME, so the same agent handles it) for
  # the wrong-key test. Doing this here avoids starting a separate agent for an
  # isolated home, which fails on macOS CI runners.
  gpg --batch --gen-key << 'EOF'
Key-Type: RSA
Key-Length: 2048
Name-Real: DevFeats Wrong Test Key
%no-protection
%commit
EOF
  gpg --armor --export "DevFeats Wrong Test Key" |
    gpg --dearmor > "${BATS_FILE_TMPDIR}/wrong.pub.gpg"
}

teardown_file() {
  # Shut gpg-agent (and dirmngr) down before bats removes GNUPGHOME. Otherwise
  # the agent asynchronously deletes its own S.gpg-agent.* sockets while bats
  # `rm`s BATS_FILE_TMPDIR, and BusyBox rm (Alpine) aborts the whole run on the
  # vanished socket ("can't remove '.../gnupg/S.gpg-agent.extra': No such file").
  gpgconf --kill all 2> /dev/null || true
}

setup() {
  load '../helpers/common'
  reload_lib
}

@test "verify__gpg_dearmor_stream: converts armored key to binary keyring" {
  local _dest="${BATS_TEST_TMPDIR}/dearmored.gpg"
  # Function reads armored key from stdin and writes binary keyring to <dest_file>.
  verify__gpg_dearmor_stream "$_dest" \
    < "${BATS_FILE_TMPDIR}/test.pub.asc"
  [[ -s "$_dest" ]]
}

@test "verify__gpg_detached: verifies file with valid detached signature" {
  run verify__gpg_detached \
    "${BATS_FILE_TMPDIR}/artifact.txt" \
    "${BATS_FILE_TMPDIR}/artifact.txt.asc" \
    "${BATS_FILE_TMPDIR}/test.pub.gpg"
  assert_success
}

@test "verify__gpg_detached: fails for a tampered artifact" {
  local _copy="${BATS_TEST_TMPDIR}/artifact_tampered.txt"
  cp "${BATS_FILE_TMPDIR}/artifact.txt" "$_copy"
  printf 'tampered\n' >> "$_copy"
  run verify__gpg_detached \
    "$_copy" \
    "${BATS_FILE_TMPDIR}/artifact.txt.asc" \
    "${BATS_FILE_TMPDIR}/test.pub.gpg"
  assert_failure
}

@test "verify__gpg_detached: fails when wrong key is used" {
  run verify__gpg_detached \
    "${BATS_FILE_TMPDIR}/artifact.txt" \
    "${BATS_FILE_TMPDIR}/artifact.txt.asc" \
    "${BATS_FILE_TMPDIR}/wrong.pub.gpg"
  assert_failure
}

@test "verify__gpg_fetch_key_by_fingerprint: fetches known public key from keyserver" {
  # Ubuntu Archive Automatic Signing Key 2012 — stable fingerprint on
  # keyserver.ubuntu.com for many years.
  local _dest="${BATS_TEST_TMPDIR}/fetched.gpg"
  run verify__gpg_fetch_key_by_fingerprint \
    "3B4FE6ACC0B21F32" \
    "$_dest"
  assert_success
  [[ -s "$_dest" ]]
}
