#!/usr/bin/env bats
# Unit tests for lib/ver.bash

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  load 'helpers/test_tools'
  reload_lib
  test_tools__wire_jq_yq
}

# ---------------------------------------------------------------------------
# ver__semver_ge
# ---------------------------------------------------------------------------

@test "ver__semver_ge returns true for equal versions" {
  run ver__semver_ge "1.2.3" "1.2.3"
  assert_success
}

@test "ver__semver_ge returns true for greater version" {
  run ver__semver_ge "1.10.0" "1.9.0"
  assert_success
}

@test "ver__semver_ge returns false for lesser version" {
  run ver__semver_ge "1.2.0" "1.10.0"
  assert_failure
}

@test "ver__semver_ge strips leading v before comparing" {
  run ver__semver_ge "v2.0.0" "v1.9.9"
  assert_success
}

# ---------------------------------------------------------------------------
# ver__extract_version (default mode)
# ---------------------------------------------------------------------------

@test "ver__extract_version strips leading non-numeric prefix" {
  run ver__extract_version "jq-1.7.1"
  assert_output "1.7.1"
  assert_success
}

@test "ver__extract_version strips leading v" {
  run ver__extract_version "v3.7.0"
  assert_output "3.7.0"
  assert_success
}

@test "ver__extract_version extracts from prose output" {
  run ver__extract_version "gh version 2.46.0 (2024-01-15)"
  assert_output "2.46.0"
  assert_success
}

@test "ver__extract_version drops pre-release suffix by default" {
  run ver__extract_version "v1.2.3-rc1"
  assert_output "1.2.3"
  assert_success
}

@test "ver__extract_version drops inline alpha suffix by default" {
  run ver__extract_version "3.13.0a4"
  assert_output "3.13.0"
  assert_success
}

@test "ver__extract_version returns empty for non-version string" {
  run ver__extract_version "latest"
  assert_output ""
  assert_success
}

# ---------------------------------------------------------------------------
# ver__extract_version --keep-suffix
# ---------------------------------------------------------------------------

@test "ver__extract_version --keep-suffix preserves dash pre-release" {
  run ver__extract_version --keep-suffix "v1.2.3-rc1"
  assert_output "1.2.3-rc1"
  assert_success
}

@test "ver__extract_version --keep-suffix strips package-name prefix, keeps suffix" {
  run ver__extract_version --keep-suffix "jq-1.7.1-rc1"
  assert_output "1.7.1-rc1"
  assert_success
}

@test "ver__extract_version --keep-suffix captures inline alpha label" {
  run ver__extract_version --keep-suffix "3.13.0a4"
  assert_output "3.13.0a4"
  assert_success
}

@test "ver__extract_version --keep-suffix captures dot-separated suffix" {
  run ver__extract_version --keep-suffix "1.2.3.post1"
  assert_output "1.2.3.post1"
  assert_success
}

@test "ver__extract_version --keep-suffix returns unchanged bare version" {
  run ver__extract_version --keep-suffix "1.2.3"
  assert_output "1.2.3"
  assert_success
}

@test "ver__extract_version --keep-suffix returns empty for non-version string" {
  run ver__extract_version --keep-suffix "latest"
  assert_output ""
  assert_success
}

# ---------------------------------------------------------------------------
# ver__extract_version --full-match
# ---------------------------------------------------------------------------

@test "ver__extract_version --full-match accepts bare semver" {
  run ver__extract_version --full-match "v1.2.3"
  assert_output "1.2.3"
  assert_success
}

@test "ver__extract_version --full-match drops suffix when --keep-suffix absent" {
  run ver__extract_version --full-match "v1.2.3-rc1"
  assert_output "1.2.3"
  assert_success
}

@test "ver__extract_version --full-match rejects package-prefixed string" {
  run ver__extract_version --full-match "jq-1.7.1"
  assert_output ""
  assert_success
}

@test "ver__extract_version --full-match rejects non-numeric-prefixed OCI tag" {
  run ver__extract_version --full-match "arm64-1.0.0"
  assert_output ""
  assert_success
}

@test "ver__extract_version --full-match rejects non-version string" {
  run ver__extract_version --full-match "latest"
  assert_output ""
  assert_success
}

# ---------------------------------------------------------------------------
# ver__extract_version --full-match --keep-suffix
# ---------------------------------------------------------------------------

@test "ver__extract_version --full-match --keep-suffix preserves pre-release" {
  run ver__extract_version --full-match --keep-suffix "v1.2.3-rc1"
  assert_output "1.2.3-rc1"
  assert_success
}

@test "ver__extract_version --full-match --keep-suffix captures inline alpha label" {
  run ver__extract_version --full-match --keep-suffix "3.13.0a4"
  assert_output "3.13.0a4"
  assert_success
}

@test "ver__extract_version --full-match --keep-suffix rejects non-numeric-prefixed tag" {
  run ver__extract_version --full-match --keep-suffix "arm64-1.0.0"
  assert_output ""
  assert_success
}

@test "ver__extract_version --full-match --keep-suffix accepts bare semver" {
  run ver__extract_version --full-match --keep-suffix "1.2.3"
  assert_output "1.2.3"
  assert_success
}

@test "ver__extract_version --full-match --keep-suffix rejects non-version string" {
  run ver__extract_version --full-match --keep-suffix "latest"
  assert_output ""
  assert_success
}

# ---------------------------------------------------------------------------
# Major-only (X) version format and fallback behaviour
# ---------------------------------------------------------------------------

@test "ver__extract_version accepts major-only version" {
  run ver__extract_version "1"
  assert_output "1"
  assert_success
}

@test "ver__extract_version --keep-suffix accepts major-only version" {
  run ver__extract_version --keep-suffix "1"
  assert_output "1"
  assert_success
}

@test "ver__extract_version --full-match accepts major-only version" {
  run ver__extract_version --full-match "1"
  assert_output "1"
  assert_success
}

@test "ver__extract_version --full-match --keep-suffix accepts major-only version" {
  run ver__extract_version --full-match --keep-suffix "1"
  assert_output "1"
  assert_success
}

@test "ver__extract_version --full-match --keep-suffix accepts major-only with v prefix" {
  run ver__extract_version --full-match --keep-suffix "v1"
  assert_output "1"
  assert_success
}

@test "ver__extract_version prefers X.Y match in prose over bare digits" {
  run ver__extract_version "step 1 of 3: version 2.46.0"
  assert_output "2.46.0"
  assert_success
}

@test "ver__extract_version handles two-part version" {
  run ver__extract_version "1.2"
  assert_output "1.2"
  assert_success
}

@test "ver__extract_version --full-match accepts two-part version" {
  run ver__extract_version --full-match "1.2"
  assert_output "1.2"
  assert_success
}

@test "ver__semver_ge returns false when a is zero and b is real version" {
  run ver__semver_ge "0" "1.2.0"
  assert_failure
}

# ---------------------------------------------------------------------------
# ver__semver_is_final
# ---------------------------------------------------------------------------

@test "ver__semver_is_final returns true for stable three-part version" {
  run ver__semver_is_final "1.2.3"
  assert_success
}

@test "ver__semver_is_final returns true for major-only version" {
  run ver__semver_is_final "1"
  assert_success
}

@test "ver__semver_is_final returns true for two-part version" {
  run ver__semver_is_final "1.2"
  assert_success
}

@test "ver__semver_is_final returns false for version with hyphen pre-release suffix" {
  run ver__semver_is_final "1.2.3-rc1"
  assert_failure
}

@test "ver__semver_is_final returns false for version with beta suffix" {
  run ver__semver_is_final "1.0.0-beta.1"
  assert_failure
}

@test "ver__semver_is_final returns false for version with inline alpha label" {
  run ver__semver_is_final "3.13.0a4"
  assert_failure
}

@test "ver__semver_is_final returns false for empty string" {
  run ver__semver_is_final ""
  assert_failure
}

@test "ver__semver_is_final returns true for version with build metadata only" {
  run ver__semver_is_final "1.2.3+build.1"
  assert_success
}

@test "ver__semver_is_final returns false for pre-release version with build metadata" {
  run ver__semver_is_final "1.2.3-rc1+build"
  assert_failure
}

# ---------------------------------------------------------------------------
# ver__first_matching_prefix
# ---------------------------------------------------------------------------

@test "ver__first_matching_prefix matches exact version" {
  run ver__first_matching_prefix "1.2.3" <<< "1.2.3"
  assert_output "1.2.3"
  assert_success
}

@test "ver__first_matching_prefix matches prefix followed by dot" {
  run ver__first_matching_prefix "1.2" <<< "$(printf '%s\n' "1.3.0" "1.2.5" "1.2.0" "1.1.0")"
  assert_output "1.2.5"
  assert_success
}

@test "ver__first_matching_prefix matches prefix followed by dash" {
  run ver__first_matching_prefix "1.2.0" <<< "$(printf '%s\n' "1.2.0-rc1" "1.1.0")"
  assert_output "1.2.0-rc1"
  assert_success
}

@test "ver__first_matching_prefix returns first match from list" {
  run ver__first_matching_prefix "1.2" <<< "$(printf '%s\n' "2.0.0" "1.2.5" "1.2.3" "1.2.0")"
  assert_output "1.2.5"
  assert_success
}

@test "ver__first_matching_prefix strips leading non-numeric prefix from input lines" {
  run ver__first_matching_prefix "1.2" <<< "$(printf '%s\n' "v2.0.0" "v1.2.5" "v1.1.0")"
  assert_output "v1.2.5"
  assert_success
}

@test "ver__first_matching_prefix does not match longer prefix" {
  run ver__first_matching_prefix "1.2" <<< "$(printf '%s\n' "1.20.0" "1.21.0")"
  assert_failure
}

@test "ver__first_matching_prefix returns failure when no match" {
  run ver__first_matching_prefix "1.2" <<< "$(printf '%s\n' "2.0.0" "3.1.0")"
  assert_failure
}

@test "ver__first_matching_prefix matches major-only spec" {
  run ver__first_matching_prefix "1" <<< "$(printf '%s\n' "2.1.0" "1.9.0" "1.8.0")"
  assert_output "1.9.0"
  assert_success
}

@test "ver__first_matching_prefix strips slash-delimited tag prefix (e.g. lib/1.2.3)" {
  run ver__first_matching_prefix "1.2" <<< "$(printf '%s\n' "lib/2.0.0" "lib/1.2.5" "lib/1.1.0")"
  assert_output "lib/1.2.5"
  assert_success
}

@test "ver__first_matching_prefix slash-delimited tag returns original full tag name" {
  run ver__first_matching_prefix "0.1.0" <<< "$(printf '%s\n' "lib/0.2.0" "lib/0.1.0")"
  assert_output "lib/0.1.0"
  assert_success
}

# ---------------------------------------------------------------------------
# ver__resolve_from_list
# ---------------------------------------------------------------------------

@test "ver__resolve_from_list fails on empty list" {
  run ver__resolve_from_list "stable" <<< ""
  assert_failure
}

@test "ver__resolve_from_list stable returns first final version" {
  run ver__resolve_from_list "stable" <<< "$(printf '%s\n' "5.9.1" "5.9" "5.8.1")"
  assert_output "5.9.1"
  assert_success
}

@test "ver__resolve_from_list stable skips prerelease versions" {
  run ver__resolve_from_list "stable" <<< "$(printf '%s\n' "5.9.1-rc1" "5.9.0-beta.1" "5.9" "5.8.1")"
  assert_output "5.9"
  assert_success
}

@test "ver__resolve_from_list stable fails when only prereleases in list" {
  run ver__resolve_from_list "stable" <<< "$(printf '%s\n' "5.9.1-rc1" "5.9.0-beta.1")"
  assert_failure
}

@test "ver__resolve_from_list empty spec behaves like stable" {
  run ver__resolve_from_list "" <<< "$(printf '%s\n' "5.9.1-rc1" "5.9" "5.8.1")"
  assert_output "5.9"
  assert_success
}

@test "ver__resolve_from_list latest returns first version regardless of prerelease" {
  run ver__resolve_from_list "latest" <<< "$(printf '%s\n' "5.9.1-rc1" "5.9" "5.8.1")"
  assert_output "5.9.1-rc1"
  assert_success
}

@test "ver__resolve_from_list exact version wins over prefix when both in list" {
  run ver__resolve_from_list "5.9" <<< "$(printf '%s\n' "6.0" "5.9.2" "5.9.1" "5.9" "5.8.1")"
  assert_output "5.9"
  assert_success
}

@test "ver__resolve_from_list prefix returns latest when exact absent" {
  run ver__resolve_from_list "5.9" <<< "$(printf '%s\n' "6.0" "5.9.2" "5.9.1" "5.8.1")"
  assert_output "5.9.2"
  assert_success
}

@test "ver__resolve_from_list exact version skips prerelease prefix but returns exact stable" {
  run ver__resolve_from_list "5.9" <<< "$(printf '%s\n' "5.9.2-rc1" "5.9.1" "5.9")"
  assert_output "5.9"
  assert_success
}

@test "ver__resolve_from_list prefix skips prerelease matches when exact absent" {
  run ver__resolve_from_list "5.9" <<< "$(printf '%s\n' "5.9.2-rc1" "5.9.1")"
  assert_output "5.9.1"
  assert_success
}

@test "ver__resolve_from_list exact version matches precisely" {
  run ver__resolve_from_list "5.9.1" <<< "$(printf '%s\n' "5.9.2" "5.9.1" "5.9")"
  assert_output "5.9.1"
  assert_success
}

@test "ver__resolve_from_list exact version fails when not in list" {
  run ver__resolve_from_list "5.9.3" <<< "$(printf '%s\n' "5.9.2" "5.9.1" "5.9")"
  assert_failure
}

@test "ver__resolve_from_list numeric prefix fails with no match" {
  run ver__resolve_from_list "6" <<< "$(printf '%s\n' "5.9.2" "5.9.1")"
  assert_failure
}

@test "ver__resolve_from_list non-numeric spec fails" {
  run ver__resolve_from_list "nope" <<< "$(printf '%s\n' "5.9.1" "5.9")"
  assert_failure
}

@test "ver__resolve_from_list handles v-prefixed versions (strips v for is_final check)" {
  run ver__resolve_from_list "stable" <<< "$(printf '%s\n' "v5.9.1-rc1" "v5.9" "v5.8.1")"
  assert_output "v5.9"
  assert_success
}

@test "ver__resolve_from_list major-only prefix matches first stable X.Y.Z" {
  run ver__resolve_from_list "5" <<< "$(printf '%s\n' "5.9.1" "5.9" "5.8" "4.9")"
  assert_output "5.9.1"
  assert_success
}

# ---------------------------------------------------------------------------
# ver__resolve_from_sidecar
# ---------------------------------------------------------------------------

_stub_uri_fetch_asset_with_content() {
  # Override uri__fetch_asset to write _SIDECAR_CONTENT to the --file-dest path.
  uri__fetch_asset() {
    local _fd=""
    while [[ $# -gt 0 ]]; do
      [[ "$1" == "--file-dest" ]] && {
        _fd="$2"
        shift 2
        continue
      }
      shift
    done
    [[ -n "${_fd}" ]] && printf '%s\n' "${_SIDECAR_CONTENT}" > "${_fd}"
    return 0
  }
  export -f uri__fetch_asset
}

_stub_uri_fetch_asset_fail() {
  uri__fetch_asset() { return 1; }
  export -f uri__fetch_asset
}

@test "ver__resolve_from_sidecar resolves stable from zsh-style SHA256SUM" {
  export _SIDECAR_CONTENT="abc123  zsh-5.9.1.tar.xz
def456  zsh-5.9.1.tar.gz
abc123  zsh-5.9.tar.xz
abc123  zsh-5.9-doc.tar.xz
abc123  zsh-5.8.1.tar.xz"
  _stub_uri_fetch_asset_with_content
  run ver__resolve_from_sidecar "https://example.com/SHA256SUM" "zsh-[version].tar.xz" "stable"
  assert_output "5.9.1"
  assert_success
}

@test "ver__resolve_from_sidecar resolves latest including prereleases" {
  export _SIDECAR_CONTENT="abc123  zsh-5.9.2-rc1.tar.xz
abc123  zsh-5.9.1.tar.xz
abc123  zsh-5.9.tar.xz"
  _stub_uri_fetch_asset_with_content
  run ver__resolve_from_sidecar "https://example.com/SHA256SUM" "zsh-[version].tar.xz" "latest"
  assert_output "5.9.2-rc1"
  assert_success
}

@test "ver__resolve_from_sidecar exact spec returns exact match when present in sidecar" {
  export _SIDECAR_CONTENT="abc123  zsh-5.9.1.tar.xz
abc123  zsh-5.9.tar.xz
abc123  zsh-5.8.1.tar.xz"
  _stub_uri_fetch_asset_with_content
  run ver__resolve_from_sidecar "https://example.com/SHA256SUM" "zsh-[version].tar.xz" "5.9"
  assert_output "5.9"
  assert_success
}

@test "ver__resolve_from_sidecar full semver resolves via exact match" {
  export _SIDECAR_CONTENT="abc123  zsh-5.9.1.tar.xz
abc123  zsh-5.9.tar.xz"
  _stub_uri_fetch_asset_with_content
  run ver__resolve_from_sidecar "https://example.com/SHA256SUM" "zsh-[version].tar.xz" "5.9.1"
  assert_output "5.9.1"
  assert_success
}

@test "ver__resolve_from_sidecar prefix spec resolves to latest stable when exact absent" {
  export _SIDECAR_CONTENT="abc123  zsh-5.9.1.tar.xz
abc123  zsh-5.8.1.tar.xz"
  _stub_uri_fetch_asset_with_content
  run ver__resolve_from_sidecar "https://example.com/SHA256SUM" "zsh-[version].tar.xz" "5.9"
  assert_output "5.9.1"
  assert_success
}

@test "ver__resolve_from_sidecar major-only spec resolves to latest stable" {
  export _SIDECAR_CONTENT="abc123  zsh-5.9.1.tar.xz
abc123  zsh-5.9.tar.xz
abc123  zsh-5.8.1.tar.xz"
  _stub_uri_fetch_asset_with_content
  run ver__resolve_from_sidecar "https://example.com/SHA256SUM" "zsh-[version].tar.xz" "5"
  assert_output "5.9.1"
  assert_success
}

@test "ver__resolve_from_sidecar prefix spec skips prereleases" {
  export _SIDECAR_CONTENT="abc123  zsh-5.9.2-rc1.tar.xz
abc123  zsh-5.9.1.tar.xz"
  _stub_uri_fetch_asset_with_content
  run ver__resolve_from_sidecar "https://example.com/SHA256SUM" "zsh-[version].tar.xz" "5.9"
  assert_output "5.9.1"
  assert_success
}

@test "ver__resolve_from_sidecar prefix spec fails when no stable match" {
  export _SIDECAR_CONTENT="abc123  zsh-5.9.2-rc1.tar.xz"
  _stub_uri_fetch_asset_with_content
  run ver__resolve_from_sidecar "https://example.com/SHA256SUM" "zsh-[version].tar.xz" "5.9"
  assert_failure
}

@test "ver__resolve_from_sidecar resolves stable from HTML directory listing" {
  # Simulates an Apache-style HTML directory index (e.g. https://ftp.gnu.org/gnu/bash/).
  # The key difference from a plain-text SHA256SUM: filenames are embedded in href attributes
  # and link text surrounded by HTML tags, not bare words.  The awk must strip HTML tags
  # before field-splitting, otherwise '<a href="bash-5.3.tar.gz">bash-5.3.tar.gz</a>'
  # appears as one word starting with 'href=' and never matches the prefix.
  export _SIDECAR_CONTENT='<html><body>
<a href="bash-5.3.tar.gz">bash-5.3.tar.gz</a>
<a href="bash-5.3-rc2.tar.gz">bash-5.3-rc2.tar.gz</a>
<a href="bash-5.2.37.tar.gz">bash-5.2.37.tar.gz</a>
</body></html>'
  _stub_uri_fetch_asset_with_content
  run ver__resolve_from_sidecar "https://example.com/dir/" "bash-[version].tar.gz" "stable"
  assert_output "5.3"
  assert_success
}

@test "ver__resolve_from_sidecar prefix spec resolves from HTML directory listing" {
  # bash-5.2.tar.gz does not exist on GNU FTP (only patch-level tarballs like 5.2.37).
  # "5.2" is therefore a prefix that resolves to the latest 5.2.x stable entry.
  export _SIDECAR_CONTENT='<html><body>
<a href="bash-5.3.tar.gz">bash-5.3.tar.gz</a>
<a href="bash-5.2.37.tar.gz">bash-5.2.37.tar.gz</a>
<a href="bash-5.2.9.tar.gz">bash-5.2.9.tar.gz</a>
</body></html>'
  _stub_uri_fetch_asset_with_content
  run ver__resolve_from_sidecar "https://example.com/dir/" "bash-[version].tar.gz" "5.2"
  assert_output "5.2.37"
  assert_success
}

@test "ver__resolve_from_sidecar fails when pattern has no [version]" {
  run ver__resolve_from_sidecar "https://example.com/SHA256SUM" "zsh-5.9.1.tar.xz" "stable"
  assert_failure
}

@test "ver__resolve_from_sidecar fails when fetch fails" {
  _stub_uri_fetch_asset_fail
  run ver__resolve_from_sidecar "https://example.com/SHA256SUM" "zsh-[version].tar.xz" "stable"
  assert_failure
}

@test "ver__resolve_from_sidecar fails when no versions found in file" {
  export _SIDECAR_CONTENT="abc123  someotherfile.tar.xz"
  _stub_uri_fetch_asset_with_content
  run ver__resolve_from_sidecar "https://example.com/SHA256SUM" "zsh-[version].tar.xz" "stable"
  assert_failure
}

@test "ver__resolve_from_sidecar fails when URI is empty" {
  run ver__resolve_from_sidecar "" "zsh-[version].tar.xz" "stable"
  assert_failure
}

@test "ver__resolve_from_sidecar fails when sidecar has only prereleases and stable requested" {
  export _SIDECAR_CONTENT="abc123  zsh-5.9.2-rc1.tar.xz
abc123  zsh-5.9.1-beta.tar.xz"
  _stub_uri_fetch_asset_with_content
  run ver__resolve_from_sidecar "https://example.com/SHA256SUM" "zsh-[version].tar.xz" "stable"
  assert_failure
}

@test "ver__resolve_from_sidecar fails when pattern is empty" {
  run ver__resolve_from_sidecar "https://example.com/SHA256SUM" "" "stable"
  assert_failure
}

@test "ver__resolve_from_sidecar fails when pattern has old {VERSION} marker" {
  run ver__resolve_from_sidecar "https://example.com/SHA256SUM" "zsh-{VERSION}.tar.xz" "stable"
  assert_failure
}

@test "ver__resolve_from_sidecar fails when pattern has new {feat.version} marker" {
  run ver__resolve_from_sidecar "https://example.com/SHA256SUM" "zsh-{feat.version}.tar.xz" "stable"
  assert_failure
}

@test "ver__resolve_from_sidecar resolves when [version] at start of pattern (no prefix)" {
  export _SIDECAR_CONTENT="abc123  5.9.1.tar.xz
abc123  5.9.tar.xz"
  _stub_uri_fetch_asset_with_content
  run ver__resolve_from_sidecar "https://example.com/SHA256SUM" "[version].tar.xz" "stable"
  assert_output "5.9.1"
  assert_success
}

@test "ver__resolve_from_sidecar resolves when [version] at end of pattern (no suffix)" {
  export _SIDECAR_CONTENT="abc123  zsh-5.9.1
abc123  zsh-5.9"
  _stub_uri_fetch_asset_with_content
  run ver__resolve_from_sidecar "https://example.com/SHA256SUM" "zsh-[version]" "stable"
  assert_output "5.9.1"
  assert_success
}

# ---------------------------------------------------------------------------
# ver__cmp — fixture-driven semver.org parity (bash + jq)
# ---------------------------------------------------------------------------

_ver_cmp__bash_runner() {
  local _file="$1" _index="$2" _name="$3" _expect="$4"
  local _yq _a _b _result _rc=0
  _yq="${DEVFEATS_TEST_YQ_BIN}"
  _a="$("${_yq}" -r ".[${_index}].a" "${_file}")"
  _b="$("${_yq}" -r ".[${_index}].b" "${_file}")"
  if [[ "${_expect}" == fail ]]; then
    run ver__cmp "${_a}" "${_b}"
    assert_failure
    return 0
  fi
  _result="$(ver__cmp "${_a}" "${_b}")" || _rc=$?
  [[ ${_rc} -eq 0 ]] || {
    echo "ver_cmp ${_name}: bash compare failed" >&2
    return 1
  }
  [[ "${_result}" == "${_expect}" ]] || {
    echo "ver_cmp ${_name}: expected ${_expect} got ${_result}" >&2
    return 1
  }
}

_ver_cmp__jq_runner() {
  local _file="$1" _index="$2" _name="$3" _expect="$4"
  local _yq _a _b _result
  _yq="${DEVFEATS_TEST_YQ_BIN}"
  _a="$("${_yq}" -r ".[${_index}].a" "${_file}")"
  _b="$("${_yq}" -r ".[${_index}].b" "${_file}")"
  if [[ "${_expect}" == fail ]]; then
    _result="$(json__query -r -L "${LIB_ROOT}" --arg a "${_a}" --arg b "${_b}" \
      -n 'include "ctx-match"; ver_cmp_jq($a; $b) // "fail"')"
    [[ "${_result}" == fail ]] || {
      echo "ver_cmp ${_name}: expected jq fail got ${_result}" >&2
      return 1
    }
    return 0
  fi
  _result="$(json__query -r -L "${LIB_ROOT}" --arg a "${_a}" --arg b "${_b}" \
    -n 'include "ctx-match"; ver_cmp_jq($a; $b) | tostring')"
  [[ "${_result}" == "$(printf '%s' "${_expect}")" ]] || {
    echo "ver_cmp ${_name}: expected jq ${_expect} got ${_result}" >&2
    return 1
  }
}

@test "ver__cmp vectors: bash and jq parity from fixture" {
  load 'helpers/ctx'
  local _file="${REPO_ROOT}/test/lib/fixtures/ctx/ver_cmp_vectors.yaml"
  ctx_test__run_vector_file "${_file}" _ver_cmp__bash_runner
  ctx_test__run_vector_file "${_file}" _ver_cmp__jq_runner
}

@test "ver__semver_ge delegates to ver__cmp" {
  run ver__semver_ge "1.10.0" "1.9.0"
  assert_success
  run ver__semver_ge "1.2.0" "1.10.0"
  assert_failure
}
