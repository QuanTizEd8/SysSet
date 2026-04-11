#!/usr/bin/env bats
# Unit tests for lib/git.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  reload_lib git.sh
}

# ---------------------------------------------------------------------------
# git::clone argument validation
# ---------------------------------------------------------------------------

@test "git::clone fails when --url is missing" {
  run git::clone --dir "${BATS_TEST_TMPDIR}/repo"
  assert_failure
  assert_output --partial "missing --url"
}

@test "git::clone fails when --dir is missing" {
  run git::clone --url "https://example.com/repo.git"
  assert_failure
  assert_output --partial "missing --dir"
}

@test "git::clone rejects unknown options" {
  run git::clone --url "https://example.com/repo.git" --dir "/tmp/x" --bogus
  assert_failure
  assert_output --partial "unknown option"
}

# ---------------------------------------------------------------------------
# git::clone idempotency
# ---------------------------------------------------------------------------

@test "git::clone skips when target .git already exists" {
  local _dir="${BATS_TEST_TMPDIR}/existing"
  mkdir -p "${_dir}/.git"
  run git::clone --url "https://example.com/repo.git" --dir "$_dir"
  assert_success
  assert_output --partial "already exists"
}

# ---------------------------------------------------------------------------
# git::clone real clone (shallow, local bare repo as server)
# ---------------------------------------------------------------------------

@test "git::clone clones a local bare repo" {
  # Create a minimal local bare repository to avoid network access.
  local _src="${BATS_TEST_TMPDIR}/src.git"
  local _dst="${BATS_TEST_TMPDIR}/dst"
  git init --bare "$_src" > /dev/null 2>&1
  # Provide at least one commit so the clone has something to fetch.
  local _work="${BATS_TEST_TMPDIR}/work"
  git clone "$_src" "$_work" > /dev/null 2>&1
  git -C "$_work" config user.email "test@test.com"
  git -C "$_work" config user.name "Test"
  echo "hi" > "${_work}/file.txt"
  git -C "$_work" add file.txt
  git -C "$_work" commit -m "init" > /dev/null 2>&1
  git -C "$_work" push > /dev/null 2>&1

  run git::clone --url "file://${_src}" --dir "$_dst"
  assert_success
  assert_file_exists "${_dst}/.git/HEAD"
}

@test "git::clone removes partial directory on clone failure" {
  local _dst="${BATS_TEST_TMPDIR}/bad_dst"
  run git::clone --url "https://0.0.0.0/nonexistent.git" --dir "$_dst"
  assert_failure
  [[ ! -d "$_dst" ]]
}
