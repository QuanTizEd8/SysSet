#!/usr/bin/env bats
# Integration tests for lib/git.bash — require a real git installation.
#
# A shared local bare repo (with two commits + a tag) is created once per
# file in ${BATS_FILE_TMPDIR} and reused across tests.

bats_require_minimum_version 1.5.0

# ---------------------------------------------------------------------------
# setup_file: create the shared bare repo used by most tests.
#
# Repo layout on main:
#   commit A  (tag: v0.1.0)  — file.txt = "v1"
#   commit B  (HEAD)         — file.txt = "v2"
#
# SHA of each commit is saved to files in BATS_FILE_TMPDIR so individual
# tests can read them (setup_file runs in a different subshell context).
# ---------------------------------------------------------------------------
setup_file() {
  load '../helpers/common'
  command -v git > /dev/null 2>&1 || {
    echo "prepared integration environment is missing required git" >&2
    return 1
  }

  local _src="${BATS_FILE_TMPDIR}/src.git"
  git -c init.defaultBranch=main init --bare "${_src}" > /dev/null 2>&1

  local _work="${BATS_FILE_TMPDIR}/work"
  git -c init.defaultBranch=main clone "file://${_src}" "${_work}" > /dev/null 2>&1
  git -C "${_work}" config user.email "test@test.com"
  git -C "${_work}" config user.name "Test"

  # Enable fetching arbitrary SHAs from this bare repo (needed by _git__fetch_sha).
  # Use --git-dir because git -C does not work on bare repos in git 2.x.
  git --git-dir="${_src}" config uploadpack.allowAnySHA1InWant true

  # Commit A.
  printf 'v1\n' > "${_work}/file.txt"
  git -C "${_work}" add file.txt
  git -C "${_work}" commit -m "init" > /dev/null 2>&1
  # Lightweight tag; -c tag.gpgsign=false guards against global gpgsign config.
  # Push branch and tag separately: --follow-tags only pushes annotated tags.
  git -c tag.gpgsign=false -C "${_work}" tag "v0.1.0"
  git -C "${_work}" push > /dev/null 2>&1
  git -C "${_work}" push origin "refs/tags/v0.1.0" > /dev/null 2>&1
  local _sha_a
  _sha_a="$(git -C "${_work}" rev-parse HEAD)"

  # Commit B.
  printf 'v2\n' > "${_work}/file.txt"
  git -C "${_work}" commit -am "update" > /dev/null 2>&1
  git -C "${_work}" push > /dev/null 2>&1
  local _sha_b
  _sha_b="$(git -C "${_work}" rev-parse HEAD)"

  # Persist state for individual tests.
  printf '%s' "file://${_src}" > "${BATS_FILE_TMPDIR}/repo_url"
  printf '%s' "${_sha_a}" > "${BATS_FILE_TMPDIR}/sha_a"
  printf '%s' "${_sha_b}" > "${BATS_FILE_TMPDIR}/sha_b"
}

# ---------------------------------------------------------------------------
# setup: load helpers, reload lib, enforce skip conditions.
# ---------------------------------------------------------------------------
setup() {
  load '../helpers/common'
  reload_lib
  command -v git > /dev/null 2>&1 || fail "prepared integration environment is missing required git"

  # Read shared repo state written by setup_file.
  _REPO_URL="$(< "${BATS_FILE_TMPDIR}/repo_url")"
  _SHA_A="$(< "${BATS_FILE_TMPDIR}/sha_a")"
  _SHA_B="$(< "${BATS_FILE_TMPDIR}/sha_b")"
}

# ===========================================================================
# git__resolve_ref (real ls-remote against a local bare repo)
# ===========================================================================

@test "git__resolve_ref: returns SHA for an existing named branch" {
  run git__resolve_ref "${_REPO_URL}" "main"
  assert_success
  # Output must be a 40-hex SHA, matching the tip of main (commit B).
  assert_output "${_SHA_B}"
}

@test "git__resolve_ref: returns SHA for an existing tag" {
  run git__resolve_ref "${_REPO_URL}" "v0.1.0"
  assert_success
  # The tag points to commit A.
  assert_output "${_SHA_A}"
}

@test "git__resolve_ref: returns ref unchanged when ref is not advertised" {
  run git__resolve_ref "${_REPO_URL}" "nosuchref"
  assert_success
  assert_output "nosuchref"
}

@test "git__resolve_ref: returns full SHA unchanged when given a commit SHA" {
  run git__resolve_ref "${_REPO_URL}" "${_SHA_A}"
  assert_success
  # ls-remote won't advertise a raw SHA; it is returned as-is.
  assert_output "${_SHA_A}"
}

# ===========================================================================
# git__clone (real shallow clones)
# ===========================================================================

@test "git__clone: clones the default branch when no --ref is given" {
  local _dst="${BATS_TEST_TMPDIR}/dst"
  run git__clone --url "${_REPO_URL}" --dir "${_dst}"
  assert_success
  assert_file_exists "${_dst}/.git/HEAD"
  run cat "${_dst}/file.txt"
  assert_output "v2"
}

@test "git__clone: clones a named branch (--ref)" {
  local _dst="${BATS_TEST_TMPDIR}/dst"
  run git__clone --url "${_REPO_URL}" --dir "${_dst}" --ref "main"
  assert_success
  assert_file_exists "${_dst}/.git/HEAD"
}

@test "git__clone: clones a named tag (--ref)" {
  local _dst="${BATS_TEST_TMPDIR}/dst"
  run git__clone --url "${_REPO_URL}" --dir "${_dst}" --ref "v0.1.0"
  assert_success
  run cat "${_dst}/file.txt"
  assert_output "v1"
}

@test "git__clone: clones a specific SHA (SHA path via _git__fetch_sha)" {
  local _dst="${BATS_TEST_TMPDIR}/dst"
  run git__clone --url "${_REPO_URL}" --dir "${_dst}" --ref "${_SHA_A}"
  assert_success
  run cat "${_dst}/file.txt"
  assert_output "v1"
}

@test "git__clone: is idempotent when target .git already exists" {
  local _dst="${BATS_TEST_TMPDIR}/dst"
  # First clone.
  git__clone --url "${_REPO_URL}" --dir "${_dst}" > /dev/null 2>&1
  # Second call must succeed without re-cloning.
  run git__clone --url "${_REPO_URL}" --dir "${_dst}"
  assert_success
  assert_output --partial "already cloned"
}

@test "git__clone: --resolved-sha for named branch skips second ls-remote probe" {
  local _dst="${BATS_TEST_TMPDIR}/dst"
  # Pre-resolve the SHA (as the framework does in __resolve_input_version__).
  local _resolved
  _resolved="$(git__resolve_ref "${_REPO_URL}" "main")"
  run git__clone \
    --url "${_REPO_URL}" \
    --dir "${_dst}" \
    --ref "main" \
    --resolved-sha "${_resolved}"
  assert_success
  assert_file_exists "${_dst}/.git/HEAD"
}

@test "git__clone: removes partial directory on clone failure" {
  local _dst="${BATS_TEST_TMPDIR}/bad_dst"
  # Bound this deliberately unreachable endpoint without changing production policy.
  lib_test__net_fetch_fail_fast
  run git__clone --url "https://0.0.0.0/nonexistent.git" --dir "${_dst}"
  assert_failure
  [[ ! -d "${_dst}" ]]
}

# ===========================================================================
# git__update (real fetches on an existing clone)
# ===========================================================================

@test "git__update: refreshes current branch when no --ref is given" {
  local _dst="${BATS_TEST_TMPDIR}/dst"
  # Clone main; then unshallow so the fast-forward merge has full history.
  git__clone --url "${_REPO_URL}" --dir "${_dst}" --ref "main" > /dev/null 2>&1
  git -C "${_dst}" fetch --unshallow > /dev/null 2>&1 || true

  run git__update "${_dst}"
  assert_success
  run cat "${_dst}/file.txt"
  assert_output "v2"
}

@test "git__update: checks out a named branch (--ref)" {
  local _dst="${BATS_TEST_TMPDIR}/dst"
  git__clone --url "${_REPO_URL}" --dir "${_dst}" > /dev/null 2>&1

  run git__update "${_dst}" --ref "main"
  assert_success
}

@test "git__update: checks out a specific SHA (SHA path, --ref)" {
  local _dst="${BATS_TEST_TMPDIR}/dst"
  git__clone --url "${_REPO_URL}" --dir "${_dst}" > /dev/null 2>&1

  run git__update "${_dst}" --ref "${_SHA_A}"
  assert_success
  run cat "${_dst}/file.txt"
  assert_output "v1"
}

@test "git__update: --resolved-sha for named branch skips second ls-remote probe" {
  local _dst="${BATS_TEST_TMPDIR}/dst"
  git__clone --url "${_REPO_URL}" --dir "${_dst}" > /dev/null 2>&1
  local _resolved
  _resolved="$(git__resolve_ref "${_REPO_URL}" "main")"

  run git__update "${_dst}" --ref "main" --resolved-sha "${_resolved}"
  assert_success
}

# ===========================================================================
# git__symbolic_ref (real git)
# ===========================================================================

@test "git__symbolic_ref: returns 0 when on a branch" {
  local _dst="${BATS_TEST_TMPDIR}/dst"
  git__clone --url "${_REPO_URL}" --dir "${_dst}" > /dev/null 2>&1

  run git__symbolic_ref "${_dst}"
  assert_success
}

@test "git__symbolic_ref: returns 1 in detached HEAD state" {
  local _dst="${BATS_TEST_TMPDIR}/dst"
  git__clone --url "${_REPO_URL}" --dir "${_dst}" > /dev/null 2>&1
  # Detach HEAD.
  git -C "${_dst}" fetch --unshallow > /dev/null 2>&1 || true
  git -C "${_dst}" checkout "${_SHA_A}" > /dev/null 2>&1

  run git__symbolic_ref "${_dst}"
  assert_failure
}

# ===========================================================================
# git__head_sha (real git)
# ===========================================================================

@test "git__head_sha: returns the correct HEAD SHA" {
  local _dst="${BATS_TEST_TMPDIR}/dst"
  git__clone --url "${_REPO_URL}" --dir "${_dst}" > /dev/null 2>&1

  run git__head_sha "${_dst}"
  assert_success
  assert_output "${_SHA_B}"
}

# ===========================================================================
# git__config (real git)
# ===========================================================================

@test "git__config: sets a config key in an existing clone" {
  local _dst="${BATS_TEST_TMPDIR}/dst"
  git__clone --url "${_REPO_URL}" --dir "${_dst}" > /dev/null 2>&1

  run git__config "${_dst}" "user.name=Integration Test"
  assert_success
  run git -C "${_dst}" config user.name
  assert_output "Integration Test"
}
