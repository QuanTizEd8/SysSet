#!/usr/bin/env bats
# Unit tests for lib/logging.sh
#
# logging__setup uses 'exec 3>&1 4>&2' to save/redirect file descriptors.
# Bats itself uses fd 3 internally for TAP output, so tests that call
# logging__setup must run in isolated subprocesses via 'run bash -c' to
# avoid corrupting bats' own fd setup.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
}

# Absolute path to logging.sh for use inside bash -c subshells.
_LOGGING_LIB="${BATS_TEST_DIRNAME}/../../lib/logging.sh"

# ---------------------------------------------------------------------------
# logging__setup / logging__cleanup — isolated subprocess tests
# ---------------------------------------------------------------------------

@test "logging__setup creates a temp log file" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__setup
    [[ -f \"\${_LOGFILE_TMP}\" ]] && echo TMPFILE_EXISTS
    logging__cleanup
  "
  assert_success
  assert_output --partial "TMPFILE_EXISTS"
}

@test "logging__setup sets _LIB_LOGGING_SETUP to true" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__setup
    [[ \"\${_LIB_LOGGING_SETUP}\" == true ]] && echo SETUP_TRUE
    logging__cleanup
  "
  assert_success
  assert_output --partial "SETUP_TRUE"
}

@test "logging__cleanup resets _LIB_LOGGING_SETUP to false" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__setup
    logging__cleanup
    [[ \"\${_LIB_LOGGING_SETUP}\" == false ]] && echo CLEANED
  "
  assert_success
  assert_output --partial "CLEANED"
}

@test "logging__cleanup removes the temp log file" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__setup
    _tmp=\"\${_LOGFILE_TMP}\"
    logging__cleanup
    [[ ! -f \"\${_tmp}\" ]] && echo FILE_GONE
  "
  assert_success
  assert_output --partial "FILE_GONE"
}

@test "logging__cleanup writes captured output to LOGFILE when set" {
  local _dest="${BATS_TEST_TMPDIR}/out.log"
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__setup
    echo 'hello log'
    LOGFILE='${_dest}' logging__cleanup
  "
  assert_success
  assert_file_exists "$_dest"
  run grep "hello log" "$_dest"
  assert_success
}

@test "logging__cleanup is a no-op when setup was never called" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__cleanup
    [[ \"\${_LIB_LOGGING_SETUP}\" == false ]] && echo NOOP_OK
  "
  assert_success
  assert_output --partial "NOOP_OK"
}

@test "logging__setup creates _SYSSET_TMPDIR" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__setup
    [[ -d \"\${_SYSSET_TMPDIR}\" ]] && echo DIR_EXISTS
    logging__cleanup
  "
  assert_success
  assert_output --partial "DIR_EXISTS"
}

@test "logging__cleanup removes _SYSSET_TMPDIR" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__setup
    _dir=\"\${_SYSSET_TMPDIR}\"
    logging__cleanup
    [[ ! -d \"\${_dir}\" ]] && echo DIR_GONE
  "
  assert_success
  assert_output --partial "DIR_GONE"
}

@test "logging__cleanup resets _SYSSET_TMPDIR to empty" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__setup
    logging__cleanup
    [[ -z \"\${_SYSSET_TMPDIR}\" ]] && echo CLEARED
  "
  assert_success
  assert_output --partial "CLEARED"
}

@test "logging__tmpdir creates a subdirectory inside _SYSSET_TMPDIR" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__setup
    _sub=\"\$(logging__tmpdir 'mymod')\"
    [[ -d \"\${_sub}\" ]] && echo SUBDIR_EXISTS
    [[ \"\${_sub}\" == \"\${_SYSSET_TMPDIR}/mymod\" ]] && echo PATH_CORRECT
    logging__cleanup
  "
  assert_success
  assert_output --partial "SUBDIR_EXISTS"
  assert_output --partial "PATH_CORRECT"
}

@test "logging__tmpdir is idempotent" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__setup
    _p1=\"\$(logging__tmpdir 'x')\"
    _p2=\"\$(logging__tmpdir 'x')\"
    [[ \"\${_p1}\" == \"\${_p2}\" ]] && echo SAME_PATH
    logging__cleanup
  "
  assert_success
  assert_output --partial "SAME_PATH"
}

@test "logging__tmpdir lazy-inits _SYSSET_TMPDIR without logging__setup" {
  run bash -c "
    source '${_LOGGING_LIB}'
    _sub=\"\$(logging__tmpdir 'lazy')\"
    [[ -d \"\${_sub}\" ]] && echo LAZY_OK
  "
  assert_success
  assert_output --partial "LAZY_OK"
}

# ---------------------------------------------------------------------------
# logging__mask_secret / GITHUB_TOKEN masking
# ---------------------------------------------------------------------------

@test "logging__mask_secret redacts registered value in LOGFILE" {
  local _dest="${BATS_TEST_TMPDIR}/masked.log"
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__setup
    logging__mask_secret 'supersecret'
    echo 'value is supersecret here'
    LOGFILE='${_dest}' logging__cleanup
  "
  assert_success
  assert_file_exists "$_dest"
  run grep "supersecret" "$_dest"
  assert_failure # must NOT appear literally
  run grep '\*\*\*' "$_dest"
  assert_success # placeholder must appear
}

@test "logging__mask_secret does not redact unregistered values" {
  local _dest="${BATS_TEST_TMPDIR}/plain.log"
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__setup
    echo 'value is notasecret here'
    LOGFILE='${_dest}' logging__cleanup
  "
  assert_success
  assert_file_exists "$_dest"
  run grep "notasecret" "$_dest"
  assert_success # must appear unchanged
}

@test "logging__mask_secret redacts multiple values in LOGFILE" {
  local _dest="${BATS_TEST_TMPDIR}/multi.log"
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__setup
    logging__mask_secret 'token-aaa'
    logging__mask_secret 'token-bbb'
    echo 'first token-aaa second token-bbb done'
    LOGFILE='${_dest}' logging__cleanup
  "
  assert_success
  assert_file_exists "$_dest"
  run grep "token-aaa" "$_dest"
  assert_failure
  run grep "token-bbb" "$_dest"
  assert_failure
}

@test "logging__setup auto-masks GITHUB_TOKEN in LOGFILE" {
  local _dest="${BATS_TEST_TMPDIR}/ghtoken.log"
  run bash -c "
    source '${_LOGGING_LIB}'
    export GITHUB_TOKEN='ghp_testtoken123'
    logging__setup
    echo \"token value is \${GITHUB_TOKEN}\"
    LOGFILE='${_dest}' logging__cleanup
  "
  assert_success
  assert_file_exists "$_dest"
  run grep "ghp_testtoken123" "$_dest"
  assert_failure # must NOT appear literally
}

@test "logging__cleanup resets _SYSSET_MASKED_VALUES to empty" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging__setup
    logging__mask_secret 'some-secret'
    logging__cleanup
    [[ \${#_SYSSET_MASKED_VALUES[@]} -eq 0 ]] && echo EMPTY
  "
  assert_success
  assert_output --partial "EMPTY"
}
