#!/usr/bin/env bats
# Unit tests for lib/logging.sh
#
# logging::setup uses 'exec 3>&1 4>&2' to save/redirect file descriptors.
# Bats itself uses fd 3 internally for TAP output, so tests that call
# logging::setup must run in isolated subprocesses via 'run bash -c' to
# avoid corrupting bats' own fd setup.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
}

# Absolute path to logging.sh for use inside bash -c subshells.
_LOGGING_LIB="${BATS_TEST_DIRNAME}/../../lib/logging.sh"

# ---------------------------------------------------------------------------
# logging::setup / logging::cleanup — isolated subprocess tests
# ---------------------------------------------------------------------------

@test "logging::setup creates a temp log file" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging::setup
    [[ -f \"\${_LOGFILE_TMP}\" ]] && echo TMPFILE_EXISTS
    logging::cleanup
  "
  assert_success
  assert_output --partial "TMPFILE_EXISTS"
}

@test "logging::setup sets _LIB_LOGGING_SETUP to true" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging::setup
    [[ \"\${_LIB_LOGGING_SETUP}\" == true ]] && echo SETUP_TRUE
    logging::cleanup
  "
  assert_success
  assert_output --partial "SETUP_TRUE"
}

@test "logging::cleanup resets _LIB_LOGGING_SETUP to false" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging::setup
    logging::cleanup
    [[ \"\${_LIB_LOGGING_SETUP}\" == false ]] && echo CLEANED
  "
  assert_success
  assert_output --partial "CLEANED"
}

@test "logging::cleanup removes the temp log file" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging::setup
    _tmp=\"\${_LOGFILE_TMP}\"
    logging::cleanup
    [[ ! -f \"\${_tmp}\" ]] && echo FILE_GONE
  "
  assert_success
  assert_output --partial "FILE_GONE"
}

@test "logging::cleanup writes captured output to LOGFILE when set" {
  local _dest="${BATS_TEST_TMPDIR}/out.log"
  run bash -c "
    source '${_LOGGING_LIB}'
    logging::setup
    echo 'hello log'
    LOGFILE='${_dest}' logging::cleanup
  "
  assert_success
  assert_file_exists "$_dest"
  run grep "hello log" "$_dest"
  assert_success
}

@test "logging::cleanup is a no-op when setup was never called" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging::cleanup
    [[ \"\${_LIB_LOGGING_SETUP}\" == false ]] && echo NOOP_OK
  "
  assert_success
  assert_output --partial "NOOP_OK"
}

@test "logging::setup creates _SYSSET_TMPDIR" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging::setup
    [[ -d \"\${_SYSSET_TMPDIR}\" ]] && echo DIR_EXISTS
    logging::cleanup
  "
  assert_success
  assert_output --partial "DIR_EXISTS"
}

@test "logging::cleanup removes _SYSSET_TMPDIR" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging::setup
    _dir=\"\${_SYSSET_TMPDIR}\"
    logging::cleanup
    [[ ! -d \"\${_dir}\" ]] && echo DIR_GONE
  "
  assert_success
  assert_output --partial "DIR_GONE"
}

@test "logging::cleanup resets _SYSSET_TMPDIR to empty" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging::setup
    logging::cleanup
    [[ -z \"\${_SYSSET_TMPDIR}\" ]] && echo CLEARED
  "
  assert_success
  assert_output --partial "CLEARED"
}

@test "logging::tmpdir creates a subdirectory inside _SYSSET_TMPDIR" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging::setup
    _sub=\"\$(logging::tmpdir 'mymod')\"
    [[ -d \"\${_sub}\" ]] && echo SUBDIR_EXISTS
    [[ \"\${_sub}\" == \"\${_SYSSET_TMPDIR}/mymod\" ]] && echo PATH_CORRECT
    logging::cleanup
  "
  assert_success
  assert_output --partial "SUBDIR_EXISTS"
  assert_output --partial "PATH_CORRECT"
}

@test "logging::tmpdir is idempotent" {
  run bash -c "
    source '${_LOGGING_LIB}'
    logging::setup
    _p1=\"\$(logging::tmpdir 'x')\"
    _p2=\"\$(logging::tmpdir 'x')\"
    [[ \"\${_p1}\" == \"\${_p2}\" ]] && echo SAME_PATH
    logging::cleanup
  "
  assert_success
  assert_output --partial "SAME_PATH"
}

@test "logging::tmpdir lazy-inits _SYSSET_TMPDIR without logging::setup" {
  run bash -c "
    source '${_LOGGING_LIB}'
    _sub=\"\$(logging::tmpdir 'lazy')\"
    [[ -d \"\${_sub}\" ]] && echo LAZY_OK
  "
  assert_success
  assert_output --partial "LAZY_OK"
}
