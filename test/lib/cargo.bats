#!/usr/bin/env bats
# Unit tests for lib/cargo.bash
#
# The crates.io HTTP fetch is replaced with a function stub that returns canned
# JSON, so no real network connections are made. Version parsing/sorting and
# spec resolution (via ver__resolve_from_list) run against the real library.

bats_require_minimum_version 1.7.0

setup() {
  load 'helpers/common'
  load 'helpers/test_tools'
  reload_lib
  # cargo__resolve_version_uri parses crate JSON via json__query → jq. Put the
  # cached jq on PATH so bootstrap__jq short-circuits instead of running its
  # download path (whose release fetch a net stub could otherwise hijack).
  test_tools__wire_jq
  # Stub out network-layer helpers so no real connections are made even if a
  # test forgets to stub _cargo__registry_get.
  net__ensure_fetch_tool() {
    _NET__FETCH_TOOL=curl
    _NET__CA_CERTS_OK=true
    return 0
  }
  export -f net__ensure_fetch_tool
}

# A crate document with a realistic (publish-order, NOT version-order) versions
# array, one yanked release, and a pre-release newer than the newest stable.
_cargo_test__crate_json() {
  cat << 'JSON'
{
  "crate": { "name": "widget" },
  "versions": [
    { "num": "1.2.0", "yanked": false },
    { "num": "2.0.0-beta.1", "yanked": false },
    { "num": "1.9.0", "yanked": true },
    { "num": "1.8.5", "yanked": false },
    { "num": "1.8.0", "yanked": false },
    { "num": "1.10.0", "yanked": false }
  ]
}
JSON
}

# ---------------------------------------------------------------------------
# cargo__resolve_version_uri — argument handling
# ---------------------------------------------------------------------------

@test "cargo__resolve_version_uri fails when uri is empty" {
  run cargo__resolve_version_uri ""
  assert_failure
  assert_output --partial "uri is required"
}

@test "cargo__resolve_version_uri fails when the fetch fails" {
  _cargo__registry_get() { return 1; }
  export -f _cargo__registry_get
  run cargo__resolve_version_uri "https://crates.io/api/v1/crates/widget" "stable"
  assert_failure
  assert_output --partial "failed to fetch crate document"
}

@test "cargo__resolve_version_uri fails on empty response" {
  _cargo__registry_get() {
    printf ''
    return 0
  }
  export -f _cargo__registry_get
  run cargo__resolve_version_uri "https://crates.io/api/v1/crates/widget" "stable"
  assert_failure
  assert_output --partial "empty response"
}

# ---------------------------------------------------------------------------
# stable — excludes pre-releases, picks newest final
# ---------------------------------------------------------------------------

@test "cargo__resolve_version_uri stable excludes pre-releases" {
  _cargo__registry_get() {
    _cargo_test__crate_json
    return 0
  }
  export -f _cargo__registry_get _cargo_test__crate_json
  run cargo__resolve_version_uri "https://crates.io/api/v1/crates/widget" "stable"
  assert_success
  # 1.10.0 is the newest final version (2.0.0-beta.1 is a pre-release; 1.9.0 is yanked).
  assert_output "1.10.0"
}

@test "cargo__resolve_version_uri empty spec resolves as stable" {
  _cargo__registry_get() {
    _cargo_test__crate_json
    return 0
  }
  export -f _cargo__registry_get _cargo_test__crate_json
  run cargo__resolve_version_uri "https://crates.io/api/v1/crates/widget" ""
  assert_success
  assert_output "1.10.0"
}

@test "cargo__resolve_version_uri defaults spec to stable when omitted" {
  _cargo__registry_get() {
    _cargo_test__crate_json
    return 0
  }
  export -f _cargo__registry_get _cargo_test__crate_json
  run cargo__resolve_version_uri "https://crates.io/api/v1/crates/widget"
  assert_success
  assert_output "1.10.0"
}

# ---------------------------------------------------------------------------
# latest — includes pre-releases, picks newest overall
# ---------------------------------------------------------------------------

@test "cargo__resolve_version_uri latest includes pre-releases" {
  _cargo__registry_get() {
    _cargo_test__crate_json
    return 0
  }
  export -f _cargo__registry_get _cargo_test__crate_json
  run cargo__resolve_version_uri "https://crates.io/api/v1/crates/widget" "latest"
  assert_success
  # 2.0.0-beta.1 sorts above every 1.x release under `sort -rV`.
  assert_output "2.0.0-beta.1"
}

# ---------------------------------------------------------------------------
# semver prefix — newest final matching the prefix
# ---------------------------------------------------------------------------

@test "cargo__resolve_version_uri semver prefix finds newest stable match" {
  _cargo__registry_get() {
    _cargo_test__crate_json
    return 0
  }
  export -f _cargo__registry_get _cargo_test__crate_json
  run cargo__resolve_version_uri "https://crates.io/api/v1/crates/widget" "1.8"
  assert_success
  # Newest final 1.8.x is 1.8.5 (not 1.10.0, which does not match the "1.8" prefix).
  assert_output "1.8.5"
}

@test "cargo__resolve_version_uri major-only prefix finds newest stable match" {
  _cargo__registry_get() {
    _cargo_test__crate_json
    return 0
  }
  export -f _cargo__registry_get _cargo_test__crate_json
  run cargo__resolve_version_uri "https://crates.io/api/v1/crates/widget" "1"
  assert_success
  assert_output "1.10.0"
}

# ---------------------------------------------------------------------------
# exact — resolves to the exact version
# ---------------------------------------------------------------------------

@test "cargo__resolve_version_uri exact version matches" {
  _cargo__registry_get() {
    _cargo_test__crate_json
    return 0
  }
  export -f _cargo__registry_get _cargo_test__crate_json
  run cargo__resolve_version_uri "https://crates.io/api/v1/crates/widget" "1.8.0"
  assert_success
  assert_output "1.8.0"
}

# ---------------------------------------------------------------------------
# yanked-skip
# ---------------------------------------------------------------------------

@test "cargo__resolve_version_uri skips yanked versions for a matching prefix" {
  # 1.9.0 is the only 1.9.x release and it is yanked, so a "1.9" spec must NOT
  # resolve to it (no non-yanked 1.9.x exists → failure).
  _cargo__registry_get() {
    _cargo_test__crate_json
    return 0
  }
  export -f _cargo__registry_get _cargo_test__crate_json
  run cargo__resolve_version_uri "https://crates.io/api/v1/crates/widget" "1.9"
  assert_failure
  assert_output --partial "no version matching"
}

@test "cargo__resolve_version_uri stable skips a yanked newest release" {
  # Newest release is yanked; stable must fall through to the newest non-yanked.
  _cargo__registry_get() {
    cat << 'JSON'
{ "versions": [ { "num": "3.0.0", "yanked": true }, { "num": "2.9.0", "yanked": false }, { "num": "2.8.0", "yanked": false } ] }
JSON
    return 0
  }
  export -f _cargo__registry_get
  run cargo__resolve_version_uri "https://crates.io/api/v1/crates/widget" "stable"
  assert_success
  assert_output "2.9.0"
}

# ---------------------------------------------------------------------------
# empty / all-yanked list → error
# ---------------------------------------------------------------------------

@test "cargo__resolve_version_uri fails when versions array is empty" {
  _cargo__registry_get() {
    printf '{"versions":[]}\n'
    return 0
  }
  export -f _cargo__registry_get
  run cargo__resolve_version_uri "https://crates.io/api/v1/crates/widget" "stable"
  assert_failure
  assert_output --partial "no non-yanked versions found"
}

@test "cargo__resolve_version_uri fails when every version is yanked" {
  _cargo__registry_get() {
    printf '{"versions":[{"num":"1.0.0","yanked":true},{"num":"0.9.0","yanked":true}]}\n'
    return 0
  }
  export -f _cargo__registry_get
  run cargo__resolve_version_uri "https://crates.io/api/v1/crates/widget" "stable"
  assert_failure
  assert_output --partial "no non-yanked versions found"
}

@test "cargo__resolve_version_uri fails when versions key is absent" {
  _cargo__registry_get() {
    printf '{"crate":{"name":"widget"}}\n'
    return 0
  }
  export -f _cargo__registry_get
  run cargo__resolve_version_uri "https://crates.io/api/v1/crates/widget" "stable"
  assert_failure
  assert_output --partial "no non-yanked versions found"
}

# ---------------------------------------------------------------------------
# _cargo__registry_get — sends the required User-Agent header
# ---------------------------------------------------------------------------

@test "_cargo__registry_get sends a User-Agent header (crates.io requires one)" {
  local _hdr_log="${BATS_TEST_TMPDIR}/headers.txt"
  net__fetch_url_stdout() {
    shift # drop the URL
    printf '%s\n' "$@" > "${_hdr_log}"
    printf '{"versions":[]}\n'
    return 0
  }
  export -f net__fetch_url_stdout
  run _cargo__registry_get "https://crates.io/api/v1/crates/widget"
  assert_success
  run cat "${_hdr_log}"
  assert_output --partial "User-Agent: devfeats"
  assert_output --partial "Accept: application/json"
}
