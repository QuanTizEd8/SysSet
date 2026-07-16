#!/usr/bin/env bats
# Unit tests for lib/oci.bash

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  reload_lib
  export DEVFEATS_NET_FETCH_RETRIES=1 DEVFEATS_NET_FETCH_DELAY=0
}

_test_sha256_file() {
  local _f="${1-}"
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum "$_f" | awk '{print $1}'
    return 0
  fi
  if command -v shasum > /dev/null 2>&1; then
    shasum -a 256 "$_f" | awk '{print $1}'
    return 0
  fi
  return 1
}

_mock_oras_pull_outdir() {
  local _i
  for ((_i = 1; _i <= $#; _i++)); do
    if [[ "${!_i}" == "-o" ]]; then
      _i=$((_i + 1))
      printf '%s\n' "${!_i}"
      return 0
    fi
  done
  return 1
}

_mock_tar_fixture_bin() {
  local _dir="${1-}" _good="${2-}" _bad="${3-}"
  local _good_hash _bad_hash
  _good_hash="$(_test_sha256_file "$_good")"
  _bad_hash="$(_test_sha256_file "$_bad")"
  mkdir -p "${_dir}/bin"
  cat > "${_dir}/bin/tar" << EOF
#!/usr/bin/env bash
set -euo pipefail
_sha256_file() {
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum "\$1" | awk '{print \$1}'
    return 0
  fi
  shasum -a 256 "\$1" | awk '{print \$1}'
}
if [[ "\${1-}" == "-tzf" ]]; then
  _h="\$(_sha256_file "\${2-}")"
  if [[ "\$_h" == "${_bad_hash}" ]]; then
    printf '%s\\n' "./devcontainer-feature.json"
    exit 0
  fi
  if [[ "\$_h" == "${_good_hash}" ]]; then
    printf '%s\\n' "./install.sh" "./devcontainer-feature.json"
    exit 0
  fi
  exit 1
fi
exit 1
EOF
  chmod +x "${_dir}/bin/tar"
}

@test "oci__ghcr_image_ref prints ghcr.io qualified name" {
  run oci__ghcr_image_ref "quantized8/devfeats" "install-pixi" "1.2.3"
  assert_success
  assert_output "ghcr.io/quantized8/devfeats/install-pixi:1.2.3"
}

@test "oci__is_feature_ref_key accepts OCI refs and rejects non-refs" {
  run oci__is_feature_ref_key "ghcr.io/devcontainers/features/git:1"
  assert_success

  run oci__is_feature_ref_key "localhost:5000/devcontainers/features/git:1"
  assert_success

  run oci__is_feature_ref_key "mcr.microsoft.com/devcontainers/features/common-utils@sha256:abc123"
  assert_success

  run oci__is_feature_ref_key "docker-in-docker"
  assert_failure

  run oci__is_feature_ref_key "localhost:abc/devcontainers/features/git:1"
  assert_failure

  run oci__is_feature_ref_key "foo:bar"
  assert_failure
}

@test "_oci__oras_capture retries transient registry failures" {
  local _attempts="${BATS_TEST_TMPDIR}/attempts"
  printf '0' > "$_attempts"
  export _attempts DEVFEATS_NET_FETCH_RETRIES=2
  oras() {
    local _n
    _n=$(($(cat "$_attempts") + 1))
    printf '%s' "$_n" > "$_attempts"
    if [[ "$_n" -eq 1 ]]; then
      printf 'failed to fetch manifest: unexpected EOF\n' >&2
      return 1
    fi
    printf '{"layers":[]}\n'
  }
  export -f oras

  run _oci__oras_capture "ghcr.io/acme/feature" 0 oras manifest fetch
  assert_success
  assert_output '{"layers":[]}'
  assert [ "$(cat "$_attempts")" -eq 2 ]
}

@test "_oci__oras_capture does not retry permanent registry failures" {
  local _attempts="${BATS_TEST_TMPDIR}/attempts"
  printf '0' > "$_attempts"
  export _attempts DEVFEATS_NET_FETCH_RETRIES=3
  oras() {
    printf '%s' "$(($(cat "$_attempts") + 1))" > "$_attempts"
    printf 'denied: authentication required\n' >&2
    return 1
  }
  export -f oras

  run _oci__oras_capture "ghcr.io/acme/feature" 0 oras manifest fetch
  assert_failure
  assert [ "$(cat "$_attempts")" -eq 1 ]
}

@test "_oci__retryable_error retries unknown registry diagnostics and rejects credential failures" {
  local _stderr="${BATS_TEST_TMPDIR}/oras.stderr"
  printf '%s\n' 'server returned 404 Not Found' > "$_stderr"
  run _oci__retryable_error 1 "$_stderr"
  assert_success

  printf '%s\n' 'denied: authentication required' > "$_stderr"
  run _oci__retryable_error 1 "$_stderr"
  assert_failure
}

@test "oci__resolve_version resolves latest and partial specs" {
  oci__list_tags() {
    cat << 'EOF'
latest
1
1.2
1.2.3
1.2.4
2.0.0-rc.1
EOF
  }
  export -f oci__list_tags

  run oci__resolve_version "ghcr.io/acme/feat" ""
  assert_success
  assert_output "latest"

  run oci__resolve_version "ghcr.io/acme/feat" "1.2"
  assert_success
  assert_output "1.2.4"

  run oci__resolve_version "ghcr.io/acme/feat" "2"
  assert_failure
}

@test "oci__resolve_version excludes prereleases unless explicitly requested" {
  oci__list_tags() {
    cat << 'EOF'
1.2.3
1.2.4-rc.1
1.2.4
2.0.0-beta.1
EOF
  }
  export -f oci__list_tags

  run oci__resolve_version "ghcr.io/acme/feat" ""
  assert_success
  assert_output "1.2.4"

  run oci__resolve_version "ghcr.io/acme/feat" "2.0.0-beta.1"
  assert_success
  assert_output "2.0.0-beta.1"
}

@test "oci__resolve_version falls back to highest semver when latest tag missing" {
  oci__list_tags() {
    cat << 'EOF'
1.0.0
1.1.0
2.0.0-rc.1
EOF
  }
  export -f oci__list_tags

  run oci__resolve_version "ghcr.io/acme/feat" "latest"
  assert_success
  assert_output "1.1.0"
}

@test "oci__pull_feature_tgz validates pulled archive shape" {
  local _tmp
  _tmp="$(mktemp -d)"
  local _good="${_tmp}/good.tgz"
  local _bad="${_tmp}/bad.tgz"
  printf '%s\n' "good archive fixture" > "$_good"
  printf '%s\n' "bad archive fixture" > "$_bad"
  _mock_tar_fixture_bin "$_tmp" "$_good" "$_bad"
  export PATH="${_tmp}/bin:${PATH}"
  hash -r
  local _hash
  _hash="$(_test_sha256_file "$_good")"

  oras() {
    if [[ "$1" == "version" ]]; then
      printf '%s\n' "Version: 1.2.0"
      return 0
    fi
    if [[ "$1" == "login" ]]; then
      return 0
    fi
    if [[ "$1" == "manifest" && "$2" == "fetch" ]]; then
      cat << EOF
{"layers":[{"mediaType":"application/vnd.devcontainers.layer.v1+tgz","digest":"sha256:${_hash}"}]}
EOF
      return 0
    fi
    if [[ "$1" == "pull" ]]; then
      local _out
      _out="$(_mock_oras_pull_outdir "$@")" || return 1
      mkdir -p "$_out"
      cp "$_good" "$_out/devcontainer-feature-x.tgz"
      return 0
    fi
    return 1
  }
  export -f oras

  local _out="${_tmp}/out.tgz"
  run oci__pull_feature_tgz "ghcr.io/acme/x:1.0.0" "$_out"
  assert_success
}

@test "oci__pull_feature_tgz performs registry login from SYSSET_OCI_AUTH" {
  local _tmp
  _tmp="$(mktemp -d)"
  local _good="${_tmp}/good.tgz"
  local _bad="${_tmp}/bad.tgz"
  printf '%s\n' "good archive fixture" > "$_good"
  printf '%s\n' "bad archive fixture" > "$_bad"
  _mock_tar_fixture_bin "$_tmp" "$_good" "$_bad"
  export PATH="${_tmp}/bin:${PATH}"
  hash -r
  local _hash
  _hash="$(_test_sha256_file "$_good")"
  local _log="${_tmp}/log"

  oras() {
    if [[ "$1" == "version" ]]; then
      printf '%s\n' "Version: 1.2.0"
      return 0
    fi
    if [[ "$1" == "login" ]]; then
      printf '%s\n' "$*" >> "$_log"
      return 0
    fi
    if [[ "$1" == "manifest" && "$2" == "fetch" ]]; then
      cat << EOF
{"layers":[{"mediaType":"application/vnd.devcontainers.layer.v1+tgz","digest":"sha256:${_hash}"}]}
EOF
      return 0
    fi
    if [[ "$1" == "pull" ]]; then
      local _out
      _out="$(_mock_oras_pull_outdir "$@")" || return 1
      mkdir -p "$_out"
      cp "$_good" "$_out/devcontainer-feature-x.tgz"
      return 0
    fi
    return 1
  }
  export -f oras

  export SYSSET_OCI_AUTH="ghcr.io|u|t"
  local _out="${_tmp}/out.tgz"
  run oci__pull_feature_tgz "ghcr.io/acme/x:1.0.0" "$_out"
  assert_success
  run bash -c "grep -q 'login ghcr.io -u u --password-stdin' '$_log'"
  assert_success
  [[ -f "$_out" ]]
}

@test "oci__list_tags authenticates using SYSSET_OCI_AUTH_FILE" {
  local _tmp
  _tmp="$(mktemp -d)"
  local _authf="${_tmp}/auth.txt"
  local _log="${_tmp}/log"
  printf '%s' 'ghcr.io|user1|tok1' > "$_authf"

  oras() {
    if [[ "$1" == "version" ]]; then
      printf '%s\n' "Version: 1.2.0"
      return 0
    fi
    if [[ "$1" == "login" ]]; then
      printf '%s\n' "$*" >> "$_log"
      return 0
    fi
    if [[ "$1" == "repo" && "$2" == "tags" ]]; then
      printf '%s\n' "1.0.0"
      return 0
    fi
    return 1
  }
  export -f oras

  export SYSSET_OCI_AUTH=""
  export SYSSET_OCI_AUTH_FILE="$_authf"
  run oci__list_tags "ghcr.io/acme/feature"
  assert_success
  assert_output "1.0.0"
  run bash -c "grep -q 'login ghcr.io -u user1 --password-stdin' '$_log'"
  assert_success
}

@test "oci__list_tags uses GITHUB_TOKEN for ghcr.io when SYSSET_OCI_AUTH is unset" {
  local _tmp
  _tmp="$(mktemp -d)"
  local _log="${_tmp}/log"

  oras() {
    if [[ "$1" == "version" ]]; then
      printf '%s\n' "Version: 1.2.0"
      return 0
    fi
    if [[ "$1" == "login" ]]; then
      printf '%s\n' "$*" >> "$_log"
      return 0
    fi
    if [[ "$1" == "repo" && "$2" == "tags" ]]; then
      printf '%s\n' "1.0.0"
      return 0
    fi
    return 1
  }
  export -f oras

  export SYSSET_OCI_AUTH=""
  export SYSSET_OCI_AUTH_FILE=""
  export GITHUB_TOKEN="ghp_test_token"
  run oci__list_tags "ghcr.io/acme/feature"
  assert_success
  assert_output "1.0.0"
  # Must have logged in to ghcr.io with x-access-token and the GITHUB_TOKEN.
  run bash -c "grep -q 'login ghcr.io -u x-access-token --password-stdin' '$_log'"
  assert_success
}

@test "oci__pull_feature_tgz fails invalid archive shape" {
  local _tmp
  _tmp="$(mktemp -d)"
  local _bad="${_tmp}/bad.tgz"
  local _good="${_tmp}/good.tgz"
  printf '%s\n' "bad archive fixture" > "$_bad"
  printf '%s\n' "good archive fixture" > "$_good"
  _mock_tar_fixture_bin "$_tmp" "$_good" "$_bad"
  export PATH="${_tmp}/bin:${PATH}"
  hash -r

  oras() {
    if [[ "$1" == "version" ]]; then
      printf '%s\n' "Version: 1.2.0"
      return 0
    fi
    if [[ "$1" == "pull" ]]; then
      local _out
      _out="$(_mock_oras_pull_outdir "$@")" || return 1
      mkdir -p "$_out"
      cp "$_bad" "$_out/devcontainer-feature-x.tgz"
      return 0
    fi
    return 1
  }
  export -f oras

  local _out="${_tmp}/out.tgz"
  run oci__pull_feature_tgz "ghcr.io/acme/x:1.0.0" "$_out"
  assert_failure
}

@test "oci__pull_feature_tgz fails on manifest digest mismatch" {
  local _tmp
  _tmp="$(mktemp -d)"
  local _good="${_tmp}/good.tgz"
  local _bad="${_tmp}/bad.tgz"
  printf '%s\n' "good archive fixture" > "$_good"
  printf '%s\n' "bad archive fixture" > "$_bad"
  _mock_tar_fixture_bin "$_tmp" "$_good" "$_bad"
  export PATH="${_tmp}/bin:${PATH}"
  hash -r

  oras() {
    if [[ "$1" == "version" ]]; then
      printf '%s\n' "Version: 1.2.0"
      return 0
    fi
    if [[ "$1" == "manifest" && "$2" == "fetch" ]]; then
      cat << 'EOF'
{"layers":[{"mediaType":"application/vnd.devcontainers.layer.v1+tgz","digest":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]}
EOF
      return 0
    fi
    if [[ "$1" == "pull" ]]; then
      local _out
      _out="$(_mock_oras_pull_outdir "$@")" || return 1
      mkdir -p "$_out"
      cp "$_good" "$_out/devcontainer-feature-x.tgz"
      return 0
    fi
    return 1
  }
  export -f oras

  local _out="${_tmp}/out.tgz"
  run oci__pull_feature_tgz "ghcr.io/acme/x:1.0.0" "$_out"
  assert_failure
}

@test "oci__pull_feature_tgz supports plain-http mirrors for pull and manifest" {
  local _tmp
  _tmp="$(mktemp -d)"
  local _good="${_tmp}/good.tgz"
  local _bad="${_tmp}/bad.tgz"
  printf '%s\n' "good archive fixture" > "$_good"
  printf '%s\n' "bad archive fixture" > "$_bad"
  _mock_tar_fixture_bin "$_tmp" "$_good" "$_bad"
  export PATH="${_tmp}/bin:${PATH}"
  hash -r
  local _hash
  _hash="$(_test_sha256_file "$_good")"

  oras() {
    if [[ "${1-}" == "version" ]]; then
      printf '%s\n' "Version: 1.2.0"
      return 0
    fi
    if [[ "${1-}" == "manifest" && "${2-}" == "fetch" ]]; then
      [[ "${ORAS_PLAIN_HTTP-}" == "1" || "${3-}" == "--plain-http" ]] || return 1
      cat << EOF
{"layers":[{"mediaType":"application/vnd.devcontainers.layer.v1+tgz","digest":"sha256:${_hash}"}]}
EOF
      return 0
    fi
    if [[ "${1-}" == "pull" ]]; then
      [[ "${ORAS_PLAIN_HTTP-}" == "1" || "${2-}" == "--plain-http" ]] || return 1
      local _out_dir=""
      _out_dir="$(_mock_oras_pull_outdir "$@")" || return 1
      mkdir -p "$_out_dir"
      cp "$_good" "$_out_dir/devcontainer-feature-x.tgz"
      return 0
    fi
    return 1
  }
  export -f oras

  local _out="${_tmp}/out.tgz"
  run oci__pull_feature_tgz "http://127.0.0.1:5000/acme/x:1.0.0" "$_out"
  assert_success
  [[ -f "$_out" ]]
}
