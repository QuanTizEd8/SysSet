#!/usr/bin/env bats
# Unit tests for lib/git.bash

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  reload_lib
  # Stub bootstrap__git to succeed by default; individual tests override as needed.
  bootstrap__git() { return 0; }
  export -f bootstrap__git
}

# ---------------------------------------------------------------------------
# _install_git_stub — configures a fake 'git' function exported to subshells.
#
# Parses past git global options (-C <dir>, -c <key>=<val>) to find the
# subcommand.  All subcommands succeed by default.  Behavior is controlled
# via exported _GITFAKE_* variables set before calling run:
#
#   _GITFAKE_SHA              SHA for ls-remote / rev-parse  (default: deadbeef…)
#   _GITFAKE_BRANCH           Branch name used in HEAD refs   (default: main)
#   _GITFAKE_LS_REMOTE_FAIL   1 → ls-remote returns 1
#   _GITFAKE_CLONE_FAIL       1 → clone returns 1
#   _GITFAKE_INIT_FAIL        1 → init returns 1
#   _GITFAKE_REMOTE_FAIL      1 → remote returns 1
#   _GITFAKE_FETCH_FAIL       1 → fetch returns 1
#   _GITFAKE_CHECKOUT_FAIL    1 → checkout returns 1
#   _GITFAKE_MERGE_FAIL       1 → merge returns 1
#   _GITFAKE_DETACHED         1 → symbolic-ref returns 1 (detached HEAD)
#   _GITFAKE_CONFIG_FAIL      1 → config returns 1
#   _GITFAKE_CALL_LOG         path — each subcommand name is appended here
# ---------------------------------------------------------------------------
_install_git_stub() {
  git() {
    local _dir=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -C)
          _dir="$2"
          shift 2
          ;;
        -c) shift 2 ;;
        *) break ;;
      esac
    done
    local _sub="${1:-}"
    shift || true
    [[ -n "${_GITFAKE_CALL_LOG:-}" ]] && printf '%s\n' "${_sub}" >> "${_GITFAKE_CALL_LOG}"
    case "${_sub}" in
      ls-remote)
        [[ "${_GITFAKE_LS_REMOTE_FAIL:-0}" == 1 ]] && return 1
        printf '%s\trefs/heads/%s\n' \
          "${_GITFAKE_SHA:-deadbeefdeadbeefdeadbeefdeadbeefdeadbeef}" \
          "${_GITFAKE_BRANCH:-main}"
        ;;
      clone)
        [[ "${_GITFAKE_CLONE_FAIL:-0}" == 1 ]] && return 1
        local _dst="${@: -1}"
        mkdir -p "${_dst}/.git"
        printf 'ref: refs/heads/%s\n' "${_GITFAKE_BRANCH:-main}" > "${_dst}/.git/HEAD"
        ;;
      init)
        [[ "${_GITFAKE_INIT_FAIL:-0}" == 1 ]] && return 1
        local _dst="${@: -1}"
        mkdir -p "${_dst}/.git"
        printf 'ref: refs/heads/%s\n' "${_GITFAKE_BRANCH:-main}" > "${_dst}/.git/HEAD"
        ;;
      remote)
        [[ "${_GITFAKE_REMOTE_FAIL:-0}" == 1 ]] && return 1
        [[ "${1:-}" == "get-url" ]] && printf 'https://example.com/repo.git\n'
        ;;
      fetch)
        [[ "${_GITFAKE_FETCH_FAIL:-0}" == 1 ]] && return 1
        ;;
      checkout)
        [[ "${_GITFAKE_CHECKOUT_FAIL:-0}" == 1 ]] && return 1
        ;;
      merge)
        [[ "${_GITFAKE_MERGE_FAIL:-0}" == 1 ]] && return 1
        ;;
      symbolic-ref)
        [[ "${_GITFAKE_DETACHED:-0}" == 1 ]] && return 1
        printf 'refs/heads/%s\n' "${_GITFAKE_BRANCH:-main}"
        ;;
      rev-parse)
        printf '%s\n' "${_GITFAKE_SHA:-deadbeefdeadbeefdeadbeefdeadbeefdeadbeef}"
        ;;
      config)
        [[ "${_GITFAKE_CONFIG_FAIL:-0}" == 1 ]] && return 1
        ;;
    esac
    return 0
  }
  export -f git
}

# ===========================================================================
# git__resolve_ref
# ===========================================================================

@test "git__resolve_ref: returns remote SHA when ref is a named branch" {
  git() {
    case "${1:-}" in
      ls-remote)
        printf 'abc123def456abc123def456abc123def456abc123\trefs/heads/main\n'
        return 0
        ;;
    esac
  }
  export -f git
  run git__resolve_ref "https://example.com/repo.git" "main"
  assert_success
  assert_output "abc123def456abc123def456abc123def456abc123"
}

@test "git__resolve_ref: returns remote SHA when ref is a tag" {
  git() {
    case "${1:-}" in
      ls-remote)
        printf 'tagsha000tagsha000tagsha000tagsha000tagsha0\trefs/tags/v1.0.0\n'
        return 0
        ;;
    esac
  }
  export -f git
  run git__resolve_ref "https://example.com/repo.git" "v1.0.0"
  assert_success
  assert_output "tagsha000tagsha000tagsha000tagsha000tagsha0"
}

@test "git__resolve_ref: returns commit SHA for an annotated tag (prefers peeled ^{} entry)" {
  git() {
    case "${1:-}" in
      ls-remote)
        # Annotated tags produce two lines: tag-object SHA first, then peeled commit SHA.
        printf 'tagobjsha0tagobjsha0tagobjsha0tagobjsha0tag\trefs/tags/v1.0.0\n'
        printf 'commitsha0commitsha0commitsha0commitsha0comm\trefs/tags/v1.0.0^{}\n'
        return 0
        ;;
    esac
  }
  export -f git
  run git__resolve_ref "https://example.com/repo.git" "v1.0.0"
  assert_success
  # Must return the commit SHA (from ^{} entry), not the tag-object SHA.
  assert_output "commitsha0commitsha0commitsha0commitsha0comm"
}

@test "git__resolve_ref: returns ref unchanged when ls-remote returns nothing (SHA input)" {
  git() { :; }
  export -f git
  run git__resolve_ref "https://example.com/repo.git" "abc123deadbeefabc123deadbeefabc123deadbee"
  assert_success
  assert_output "abc123deadbeefabc123deadbeefabc123deadbee"
}

@test "git__resolve_ref: fails on a persistent authentication error" {
  git() {
    case "${1:-}" in
      ls-remote)
        printf 'fatal: unable to access: authentication failed\n' >&2
        return 1
        ;;
    esac
  }
  export -f git
  run git__resolve_ref "https://example.com/repo.git" "abc123sha"
  assert_failure
  assert_output --partial "failed to resolve ref"
}

@test "git__resolve_ref: retries a transient ls-remote failure" {
  local _attempts="${BATS_TEST_TMPDIR}/attempts"
  printf '0' > "$_attempts"
  export _attempts DEVFEATS_NET_FETCH_RETRIES=2 DEVFEATS_NET_FETCH_DELAY=0
  git() {
    local _n
    _n=$(($(cat "$_attempts") + 1))
    printf '%s' "$_n" > "$_attempts"
    if [[ "$_n" -eq 1 ]]; then
      printf 'fatal: unable to access https://example.com/repo.git: The requested URL returned error: 503\n' >&2
      return 1
    fi
    printf 'abc123def456abc123def456abc123def456abc123\trefs/heads/main\n'
  }
  export -f git
  run --separate-stderr git__resolve_ref "https://example.com/repo.git" "main"
  assert_success
  assert_output "abc123def456abc123def456abc123def456abc123"
  assert_stderr --partial "requested URL returned error: 503"
  assert [ "$(cat "$_attempts")" -eq 2 ]
}

@test "git__resolve_ref: does not retry a certainly persistent authentication failure" {
  local _attempts="${BATS_TEST_TMPDIR}/attempts"
  printf '0' > "$_attempts"
  export _attempts DEVFEATS_NET_FETCH_RETRIES=3 DEVFEATS_NET_FETCH_DELAY=0
  git() {
    printf '%s' "$(($(cat "$_attempts") + 1))" > "$_attempts"
    printf 'fatal: Authentication failed for https://example.com/repo.git\n' >&2
    return 128
  }
  export -f git

  run git__resolve_ref "https://example.com/repo.git" "main"
  assert_failure
  assert [ "$(cat "$_attempts")" -eq 1 ]
}

@test "deferred Git LFS hook retries Git's normal HTTP 503 diagnostic" {
  local _root="${BATS_TEST_TMPDIR}/share" _repo="${BATS_TEST_TMPDIR}/repo"
  local _bin="${BATS_TEST_TMPDIR}/bin" _attempts="${BATS_TEST_TMPDIR}/attempts"
  local _hook="${BATS_TEST_DIRNAME}/../../features/install-git-lfs/files/post-create--configure-and-pull.sh"
  mkdir -p "${_root}/state" "$_repo" "$_bin"
  printf '0' > "$_attempts"
  cat > "${_root}/state/config.env" << EOF
GIT_LFS_STATE_REPO_DIR="$_repo"
GIT_LFS_STATE_CONFIG_SCOPE="none"
GIT_LFS_STATE_AUTO_PULL="true"
EOF
  cat > "${_bin}/git" << EOF
#!/bin/sh
if [ "\${1-}" = -C ]; then shift 2; fi
case "\${1-}:\${2-}" in
  rev-parse:*) exit 0 ;;
  config:*) exit 0 ;;
  lfs:ls-files) printf 'tracked.bin\n'; exit 0 ;;
  lfs:pull)
    _n=\$(cat "$_attempts")
    _n=\$((\$_n + 1))
    printf '%s' "\$_n" > "$_attempts"
    if [ "\$_n" -eq 1 ]; then
      printf 'fatal: unable to access https://example.com/repo.git: The requested URL returned error: 503\n' >&2
      exit 1
    fi
    exit 0
    ;;
esac
exit 1
EOF
  chmod +x "${_bin}/git"

  run env \
    _FEAT_SHARE_DIR_ROOT="$_root" \
    DEVFEATS_NET_FETCH_RETRIES=2 DEVFEATS_NET_FETCH_DELAY=0 \
    PATH="${_bin}:${PATH}" \
    sh "$_hook" "$_repo"
  assert_success
  assert [ "$(cat "$_attempts")" -eq 2 ]
  assert_output --partial 'retrying in 0s'
}

# ===========================================================================
# git__clone — argument validation
# ===========================================================================

@test "git__clone fails when --url is missing" {
  run git__clone --dir "${BATS_TEST_TMPDIR}/repo"
  assert_failure
  assert_output --partial "missing --url"
}

@test "git__clone fails when --dir is missing" {
  run git__clone --url "https://example.com/repo.git"
  assert_failure
  assert_output --partial "missing --dir"
}

@test "git__clone rejects unknown options" {
  run git__clone --url "https://example.com/repo.git" --dir "/tmp/x" --bogus
  assert_failure
  assert_output --partial "unknown option"
}

# ===========================================================================
# git__clone — idempotency
# ===========================================================================

@test "git__clone skips when target .git already exists" {
  local _dir="${BATS_TEST_TMPDIR}/existing"
  mkdir -p "${_dir}/.git"
  run git__clone --url "https://example.com/repo.git" --dir "$_dir"
  assert_success
  assert_output --partial "already cloned"
}

# ===========================================================================
# git__clone — bootstrap + real-stub interaction (existing tests preserved)
# ===========================================================================

@test "git__clone installs git when absent and clones via stub" {
  local _dst="${BATS_TEST_TMPDIR}/dst"
  local _install_log="${BATS_TEST_TMPDIR}/install.log"
  local _fake_git="${BATS_TEST_TMPDIR}/bin/git"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"

  # This test exercises the bootstrap path; restore a bootstrap__git that
  # delegates to ospkg__install_tracked (mirrors the real implementation).
  bootstrap__git() { ospkg__install_tracked "lib-git" git || return 1; }
  export -f bootstrap__git

  _ospkg__detect() { return 0; }
  export -f _ospkg__detect
  ospkg__install_tracked() {
    echo "install_tracked $*" >> "$_install_log"
    cat > "$_fake_git" << 'EOF'
#!/usr/bin/env bash
if [[ "${1-}" = "clone" ]]; then
  _dst="${@: -1}"
  mkdir -p "${_dst}/.git"
  printf 'ref: refs/heads/main\n' > "${_dst}/.git/HEAD"
  exit 0
fi
exit 1
EOF
    chmod +x "$_fake_git"
    return 0
  }
  export -f ospkg__install_tracked

  begin_path_isolation "mkdir" "rm" "cat" "chmod" "bash"
  run git__clone --url "file:///tmp/fake.git" --dir "$_dst"
  end_path_isolation

  assert_success
  assert_file_exists "${_dst}/.git/HEAD"
  assert_file_exists "$_install_log"
  grep -q "lib-git git" "$_install_log"
}

@test "git__clone removes partial directory on clone failure" {
  local _dst="${BATS_TEST_TMPDIR}/bad_dst"
  # Bound this deliberately unreachable endpoint without changing production policy.
  lib_test__net_fetch_fail_fast
  run git__clone --url "https://0.0.0.0/nonexistent.git" --dir "$_dst"
  assert_failure
  [[ ! -d "$_dst" ]]
}

# ===========================================================================
# git__clone — named-ref path
# ===========================================================================

@test "git__clone named-ref path: calls git clone --branch (not init)" {
  local _dst="${BATS_TEST_TMPDIR}/dst"
  # Resolve returns a SHA different from ref → named-ref path.
  git__resolve_ref() { printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n'; }
  export -f git__resolve_ref
  export _GITFAKE_CALL_LOG="${BATS_TEST_TMPDIR}/calls"
  _install_git_stub

  run git__clone --url "https://example.com/r.git" --dir "${_dst}" --ref "main"
  assert_success
  grep -q "^clone$" "${BATS_TEST_TMPDIR}/calls"
  ! grep -q "^init$" "${BATS_TEST_TMPDIR}/calls"
}

@test "git__clone named-ref path: removes partial dir and returns 1 on git clone failure" {
  local _dst="${BATS_TEST_TMPDIR}/dst"
  git__resolve_ref() { printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n'; }
  export -f git__resolve_ref
  export _GITFAKE_CLONE_FAIL=1
  _install_git_stub

  lib_test__net_fetch_fail_fast
  run git__clone --url "https://example.com/r.git" --dir "${_dst}" --ref "main"
  assert_failure
  [[ ! -d "${_dst}" ]]
}

@test "git__clone named-ref path: retries a transient clone failure" {
  local _dst="${BATS_TEST_TMPDIR}/dst" _attempts="${BATS_TEST_TMPDIR}/attempts"
  printf '0' > "$_attempts"
  git__resolve_ref() { printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n'; }
  export -f git__resolve_ref
  export _attempts DEVFEATS_NET_FETCH_RETRIES=2 DEVFEATS_NET_FETCH_DELAY=0
  git() {
    local _sub="${1:-}"
    if [[ "$_sub" == clone ]]; then
      local _n
      _n=$(($(cat "$_attempts") + 1))
      printf '%s' "$_n" > "$_attempts"
      if [[ "$_n" -eq 1 ]]; then
        printf 'fatal: unable to access: Connection reset by peer\n' >&2
        return 1
      fi
      mkdir -p "${@: -1}/.git"
      return 0
    fi
    return 0
  }
  export -f git

  run git__clone --url "https://example.com/r.git" --dir "${_dst}" --ref "main"
  assert_success
  assert [ "$(cat "$_attempts")" -eq 2 ]
  [[ -d "${_dst}/.git" ]]
}

@test "git__clone no-ref path: calls git clone without --branch" {
  local _dst="${BATS_TEST_TMPDIR}/dst"
  export _GITFAKE_CALL_LOG="${BATS_TEST_TMPDIR}/calls"
  _install_git_stub

  run git__clone --url "https://example.com/r.git" --dir "${_dst}"
  assert_success
  grep -q "^clone$" "${BATS_TEST_TMPDIR}/calls"
}

# ===========================================================================
# git__clone — SHA path
# ===========================================================================

@test "git__clone SHA path: calls init + _git__fetch_sha (not git clone)" {
  local _dst="${BATS_TEST_TMPDIR}/dst"
  # Resolve returns the ref unchanged → SHA path.
  git__resolve_ref() { printf '%s\n' "$2"; }
  export -f git__resolve_ref
  _git__fetch_sha() { return 0; }
  export -f _git__fetch_sha
  export _GITFAKE_CALL_LOG="${BATS_TEST_TMPDIR}/calls"
  _install_git_stub

  run git__clone --url "https://example.com/r.git" --dir "${_dst}" --ref "abc123"
  assert_success
  grep -q "^init$" "${BATS_TEST_TMPDIR}/calls"
  ! grep -q "^clone$" "${BATS_TEST_TMPDIR}/calls"
}

@test "git__clone SHA path: removes partial dir and returns 1 on git init failure" {
  local _dst="${BATS_TEST_TMPDIR}/dst"
  git__resolve_ref() { printf '%s\n' "$2"; }
  export -f git__resolve_ref
  export _GITFAKE_INIT_FAIL=1
  _install_git_stub

  run git__clone --url "https://example.com/r.git" --dir "${_dst}" --ref "abc123"
  assert_failure
  [[ ! -d "${_dst}" ]]
}

@test "git__clone SHA path: removes partial dir and returns 1 on git remote add failure" {
  local _dst="${BATS_TEST_TMPDIR}/dst"
  git__resolve_ref() { printf '%s\n' "$2"; }
  export -f git__resolve_ref
  export _GITFAKE_REMOTE_FAIL=1
  _install_git_stub

  run git__clone --url "https://example.com/r.git" --dir "${_dst}" --ref "abc123"
  assert_failure
  [[ ! -d "${_dst}" ]]
}

@test "git__clone SHA path: removes partial dir and returns 1 when _git__fetch_sha fails" {
  local _dst="${BATS_TEST_TMPDIR}/dst"
  git__resolve_ref() { printf '%s\n' "$2"; }
  export -f git__resolve_ref
  _git__fetch_sha() { return 1; }
  export -f _git__fetch_sha
  _install_git_stub

  run git__clone --url "https://example.com/r.git" --dir "${_dst}" --ref "abc123"
  assert_failure
  [[ ! -d "${_dst}" ]]
}

# ===========================================================================
# git__clone — --resolved-sha
# ===========================================================================

@test "git__clone --resolved-sha != ref: skips ls-remote and uses named-ref path" {
  local _dst="${BATS_TEST_TMPDIR}/dst"
  export _GITFAKE_CALL_LOG="${BATS_TEST_TMPDIR}/calls"
  _install_git_stub

  run git__clone \
    --url "https://example.com/r.git" \
    --dir "${_dst}" \
    --ref "main" \
    --resolved-sha "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  assert_success
  # ls-remote must NOT have been called.
  ! grep -q "^ls-remote$" "${BATS_TEST_TMPDIR}/calls"
  # Named-ref path: clone (not init).
  grep -q "^clone$" "${BATS_TEST_TMPDIR}/calls"
}

@test "git__clone --resolved-sha == ref: skips ls-remote and uses SHA path" {
  local _dst="${BATS_TEST_TMPDIR}/dst"
  _git__fetch_sha() { return 0; }
  export -f _git__fetch_sha
  export _GITFAKE_CALL_LOG="${BATS_TEST_TMPDIR}/calls"
  _install_git_stub

  run git__clone \
    --url "https://example.com/r.git" \
    --dir "${_dst}" \
    --ref "abc123sha" \
    --resolved-sha "abc123sha"
  assert_success
  # ls-remote must NOT have been called.
  ! grep -q "^ls-remote$" "${BATS_TEST_TMPDIR}/calls"
  # SHA path: init (not clone).
  grep -q "^init$" "${BATS_TEST_TMPDIR}/calls"
}

# ===========================================================================
# git__config
# ===========================================================================

@test "git__config: fails when directory argument is missing" {
  run git__config
  assert_failure
  assert_output --partial "missing directory argument"
}

@test "git__config: returns 0 immediately when no key=val pairs given" {
  local _dir="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${_dir}/.git"
  run git__config "${_dir}"
  assert_success
}

@test "git__config: sets a config key in the repository" {
  local _dir="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${_dir}/.git"
  export _GITFAKE_CALL_LOG="${BATS_TEST_TMPDIR}/calls"
  _install_git_stub

  run git__config "${_dir}" "user.name=Test Bot"
  assert_success
  grep -q "^config$" "${BATS_TEST_TMPDIR}/calls"
}

@test "git__config: returns 1 when git config fails" {
  local _dir="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${_dir}/.git"
  export _GITFAKE_CONFIG_FAIL=1
  _install_git_stub

  run git__config "${_dir}" "user.name=Test Bot"
  assert_failure
}

# ===========================================================================
# git__update — argument validation
# ===========================================================================

@test "git__update: fails when directory argument is missing" {
  run git__update
  assert_failure
  assert_output --partial "missing directory argument"
}

@test "git__update: fails on unknown argument" {
  local _dir="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${_dir}/.git"
  run git__update "${_dir}" --bogus
  assert_failure
  assert_output --partial "unknown argument"
}

# ===========================================================================
# git__update — named-ref path
# ===========================================================================

@test "git__update named-ref path: runs fetch, checkout, merge when on branch" {
  local _dir="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${_dir}/.git"
  # Resolve returns SHA different from ref → named-ref path.
  git__resolve_ref() { printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n'; }
  export -f git__resolve_ref
  export _GITFAKE_CALL_LOG="${BATS_TEST_TMPDIR}/calls"
  _install_git_stub

  run git__update "${_dir}" --ref "main"
  assert_success
  grep -q "^fetch$" "${BATS_TEST_TMPDIR}/calls"
  grep -q "^checkout$" "${BATS_TEST_TMPDIR}/calls"
  grep -q "^merge$" "${BATS_TEST_TMPDIR}/calls"
}

@test "git__update named-ref path: skips merge when in detached HEAD state" {
  local _dir="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${_dir}/.git"
  git__resolve_ref() { printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n'; }
  export -f git__resolve_ref
  export _GITFAKE_DETACHED=1
  export _GITFAKE_CALL_LOG="${BATS_TEST_TMPDIR}/calls"
  _install_git_stub

  run git__update "${_dir}" --ref "main"
  assert_success
  grep -q "^checkout$" "${BATS_TEST_TMPDIR}/calls"
  ! grep -q "^merge$" "${BATS_TEST_TMPDIR}/calls"
}

@test "git__update named-ref path: returns 1 when fetch fails" {
  local _dir="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${_dir}/.git"
  git__resolve_ref() { printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n'; }
  export -f git__resolve_ref
  export _GITFAKE_FETCH_FAIL=1
  _install_git_stub

  lib_test__net_fetch_fail_fast
  run git__update "${_dir}" --ref "main"
  assert_failure
}

# ===========================================================================
# git__update — SHA path
# ===========================================================================

@test "git__update SHA path: calls _git__fetch_sha when resolved_sha == ref" {
  local _dir="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${_dir}/.git"
  # Resolve returns ref unchanged → SHA path.
  git__resolve_ref() { printf '%s\n' "$2"; }
  export -f git__resolve_ref
  _git__fetch_sha() {
    echo "called" >> "${BATS_TEST_TMPDIR}/fetch_sha_log"
    return 0
  }
  export -f _git__fetch_sha
  _install_git_stub

  run git__update "${_dir}" --ref "abc123sha"
  assert_success
  assert_file_exists "${BATS_TEST_TMPDIR}/fetch_sha_log"
}

@test "git__update SHA path: returns 1 when _git__fetch_sha fails" {
  local _dir="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${_dir}/.git"
  git__resolve_ref() { printf '%s\n' "$2"; }
  export -f git__resolve_ref
  _git__fetch_sha() { return 1; }
  export -f _git__fetch_sha
  _install_git_stub

  run git__update "${_dir}" --ref "abc123sha"
  assert_failure
}

# ===========================================================================
# git__update — no-ref (refresh current branch)
# ===========================================================================

@test "git__update no-ref: runs fetch and merge when on branch" {
  local _dir="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${_dir}/.git"
  export _GITFAKE_CALL_LOG="${BATS_TEST_TMPDIR}/calls"
  _install_git_stub

  run git__update "${_dir}"
  assert_success
  grep -q "^fetch$" "${BATS_TEST_TMPDIR}/calls"
  grep -q "^merge$" "${BATS_TEST_TMPDIR}/calls"
}

@test "git__update no-ref: skips merge when in detached HEAD state" {
  local _dir="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${_dir}/.git"
  export _GITFAKE_DETACHED=1
  export _GITFAKE_CALL_LOG="${BATS_TEST_TMPDIR}/calls"
  _install_git_stub

  run git__update "${_dir}"
  assert_success
  grep -q "^fetch$" "${BATS_TEST_TMPDIR}/calls"
  ! grep -q "^merge$" "${BATS_TEST_TMPDIR}/calls"
}

# ===========================================================================
# git__update — --resolved-sha
# ===========================================================================

@test "git__update --resolved-sha != ref: skips ls-remote and takes named-ref path" {
  local _dir="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${_dir}/.git"
  export _GITFAKE_CALL_LOG="${BATS_TEST_TMPDIR}/calls"
  _install_git_stub

  run git__update "${_dir}" --ref "main" --resolved-sha "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  assert_success
  ! grep -q "^ls-remote$" "${BATS_TEST_TMPDIR}/calls"
  grep -q "^fetch$" "${BATS_TEST_TMPDIR}/calls"
  grep -q "^checkout$" "${BATS_TEST_TMPDIR}/calls"
}

@test "git__update --resolved-sha == ref: skips ls-remote and calls _git__fetch_sha" {
  local _dir="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${_dir}/.git"
  _git__fetch_sha() {
    echo "called" >> "${BATS_TEST_TMPDIR}/fetch_sha_log"
    return 0
  }
  export -f _git__fetch_sha
  export _GITFAKE_CALL_LOG="${BATS_TEST_TMPDIR}/calls"
  _install_git_stub

  run git__update "${_dir}" --ref "abc123sha" --resolved-sha "abc123sha"
  assert_success
  ! grep -q "^ls-remote$" "${BATS_TEST_TMPDIR}/calls"
  assert_file_exists "${BATS_TEST_TMPDIR}/fetch_sha_log"
}

# ===========================================================================
# git__symbolic_ref
# ===========================================================================

@test "git__symbolic_ref: fails when directory argument is missing" {
  run git__symbolic_ref
  assert_failure
  assert_output --partial "missing directory argument"
}

@test "git__symbolic_ref: returns 0 when HEAD is a symbolic ref (on a branch)" {
  local _dir="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${_dir}/.git"
  _install_git_stub # default: symbolic-ref returns 0

  run git__symbolic_ref "${_dir}"
  assert_success
}

@test "git__symbolic_ref: returns 1 when HEAD is detached" {
  local _dir="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${_dir}/.git"
  export _GITFAKE_DETACHED=1
  _install_git_stub

  run git__symbolic_ref "${_dir}"
  assert_failure
}

# ===========================================================================
# git__head_sha
# ===========================================================================

@test "git__head_sha: fails when directory argument is missing" {
  run git__head_sha
  assert_failure
  assert_output --partial "missing directory argument"
}

@test "git__head_sha: returns the HEAD commit SHA" {
  local _dir="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${_dir}/.git"
  export _GITFAKE_SHA="cafecafecafecafecafecafecafecafecafecafe"
  _install_git_stub

  run git__head_sha "${_dir}"
  assert_success
  assert_output "cafecafecafecafecafecafecafecafecafecafe"
}
