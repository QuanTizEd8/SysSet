#!/usr/bin/env bats
# Unit tests for lib/github.bash
#
# Network calls are replaced with function stubs or fake curl binaries that
# return canned JSON fixtures.

bats_require_minimum_version 1.7.0

setup_file() {
  load 'helpers/common'
  load 'helpers/bootstrap_tools'
  # Provision a real jq onto PATH (copied into BATS_FILE_TMPDIR, a stable
  # per-file directory) before any test's setup() installs the
  # net__fetch_url_stdout stub below. install__state_dir is per-process
  # session-scoped (a fresh random tmpdir every time __init__.bash is
  # sourced), so a bare `bootstrap__jq` call here would NOT leave anything
  # for later, separate test invocations to find via its "previously
  # bootstrapped" fast path — only a real jq already on PATH short-circuits
  # bootstrap__jq before it ever touches the network. Without this, several
  # functions here (github__release_tags, github__resolve_version, ...) that
  # parse JSON arrays via real jq would trigger a mid-test bootstrap__jq,
  # which resolves jq's own version through that same stubbed net layer and
  # mistakes a test's canned tag_name fixture for jq's real release data.
  test_bootstrap__setup_file_jq_yq
}

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  load 'helpers/bootstrap_tools'
  reload_lib
  test_bootstrap__prepend_tools_path
  # Stub out the network-layer helpers so no real connections are made.
  net__ensure_fetch_tool() {
    _NET__FETCH_TOOL=curl
    _NET__CA_CERTS_OK=true
    return 0
  }
  net__ensure_ca_certs() {
    _NET__CA_CERTS_OK=true
    return 0
  }
  export -f net__ensure_fetch_tool net__ensure_ca_certs
}

# ---------------------------------------------------------------------------
# github__latest_tag  (parsing logic)
# ---------------------------------------------------------------------------

@test "github__latest_tag parses tag_name from JSON" {
  github__fetch_release_json() {
    echo '{"tag_name": "v1.2.3", "name": "Release v1.2.3"}'
    return 0
  }
  export -f github__fetch_release_json
  run --separate-stderr github__latest_tag "owner/repo"
  assert_output "v1.2.3"
  assert_success
}

@test "github__latest_tag fails when fetch returns empty" {
  github__fetch_release_json() { return 1; }
  net__fetch_url_stdout() { return 1; }
  export -f net__fetch_url_stdout
  export -f github__fetch_release_json
  run github__latest_tag "owner/repo"
  assert_failure
}

@test "github__latest_tag falls back to releases/latest HTML redirect parsing" {
  github__fetch_release_json() { return 1; }
  net__fetch_url_stdout() {
    printf '%s\n' '<a href="/owner/repo/releases/tag/v9.8.7">latest</a>'
    return 0
  }
  export -f github__fetch_release_json net__fetch_url_stdout
  run github__latest_tag "owner/repo"
  assert_success
  assert_output "v9.8.7"
}

@test "github__latest_tag fails when tag_name is absent from JSON" {
  github__fetch_release_json() {
    echo '{"name": "oops no tag_name field"}'
    return 0
  }
  export -f github__fetch_release_json
  run github__latest_tag "owner/repo"
  assert_failure
  assert_output --partial "could not parse tag_name"
}

@test "github__latest_tag caps the retry budget on the releases/latest redirect" {
  # The redirect probe must not inherit the default 60x/5s budget (a repo with
  # no published "latest" release would stall ~5 min before the fallback runs),
  # but the retry must still be able to ride a transient: a bounded attempt
  # count AND a delay long enough to matter (not a 1s token pause).
  github__fetch_release_json() { return 1; }
  local _args="${BATS_TEST_TMPDIR}/latest.args"
  export _args
  net__fetch_url_stdout() {
    printf '%s\n' "$@" > "$_args"
    printf '%s\n' '<a href="/owner/repo/releases/tag/v9.8.7">latest</a>'
    return 0
  }
  export -f github__fetch_release_json net__fetch_url_stdout
  run github__latest_tag "owner/repo"
  assert_success
  assert_output "v9.8.7"
  local _n _d
  _n="$(awk '/^--retries$/ { getline; print; exit }' "$_args")"
  _d="$(awk '/^--delay$/ { getline; print; exit }' "$_args")"
  # Bounded (well below the 60 default) but a real retry (>= 2 attempts).
  assert [ -n "$_n" ]
  assert [ "$_n" -ge 2 ]
  assert [ "$_n" -le 10 ]
  # Delay long enough to ride a transient, not a token 1s pause.
  assert [ -n "$_d" ]
  assert [ "$_d" -ge 3 ]
}

# ---------------------------------------------------------------------------
# github__release_tags  (parsing logic via fake curl)
# ---------------------------------------------------------------------------

@test "github__release_tags parses multiple tags from JSON array" {
  # net__fetch_url_stdout is used inside; override it to return canned JSON.
  net__fetch_url_stdout() {
    printf '%s\n' '[{"tag_name":"v3.0.0"},{"tag_name":"v2.1.0"},{"tag_name":"v2.0.0"}]'
    return 0
  }
  export -f net__fetch_url_stdout
  run github__release_tags "owner/repo"
  assert_output "v3.0.0
v2.1.0
v2.0.0"
}

@test "github__release_tags accepts --per_page option" {
  net__fetch_url_stdout() {
    printf '%s\n' '[{"tag_name":"v1.0.0"}]'
    return 0
  }
  export -f net__fetch_url_stdout
  run github__release_tags "owner/repo" --per_page 5
  assert_output "v1.0.0"
  assert_success
}

@test "github__release_tags rejects unknown option" {
  run github__release_tags "owner/repo" --bogus
  assert_failure
  assert_output --partial "unknown option"
}

@test "github__release_tags --retries replays after repeated API list failure" {
  # Stub the list helper (not net__fetch_url_stdout): sourcing json/ospkg pulls
  # net.bash back in and would replace a net stub before github__release_tags runs.
  _gh_list_n=0
  _github__api_list_field() {
    _gh_list_n=$((_gh_list_n + 1))
    if [ "$_gh_list_n" -lt 3 ]; then
      return 1
    fi
    printf '%s\n' 'v1.0.0'
    return 0
  }
  export -f _github__api_list_field
  run --separate-stderr github__release_tags "owner/repo" --retries 3 --retry-delay 0
  assert_success
  assert_output "v1.0.0"
  assert_stderr --partial "retrying"
}

# ---------------------------------------------------------------------------
# github__release_asset_urls  (parsing logic via fake fetch_release_json)
# ---------------------------------------------------------------------------

@test "github__release_asset_urls returns download URLs" {
  github__fetch_release_json() {
    # Write canned JSON to --dest file if provided.
    local _dest=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --dest)
          shift
          _dest="$1"
          shift
          ;;
        *) shift ;;
      esac
    done
    local _json
    _json='{"assets":[
      {"browser_download_url":"https://example.com/tool-linux-x86_64.tar.gz"},
      {"browser_download_url":"https://example.com/tool-darwin-arm64.tar.gz"}
    ]}'
    if [ -n "$_dest" ]; then
      printf '%s\n' "$_json" > "$_dest"
    else
      printf '%s\n' "$_json"
    fi
    return 0
  }
  export -f github__fetch_release_json
  run github__release_asset_urls "owner/repo"
  assert_output --partial "https://example.com/tool-linux-x86_64.tar.gz"
  assert_output --partial "https://example.com/tool-darwin-arm64.tar.gz"
}

@test "github__release_asset_urls applies --filter" {
  github__fetch_release_json() {
    local _dest=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --dest)
          shift
          _dest="$1"
          shift
          ;;
        *) shift ;;
      esac
    done
    local _json
    _json='{"assets":[
      {"browser_download_url":"https://example.com/tool-linux-x86_64.tar.gz"},
      {"browser_download_url":"https://example.com/tool-darwin-arm64.tar.gz"}
    ]}'
    [ -n "$_dest" ] && printf '%s\n' "$_json" > "$_dest" || printf '%s\n' "$_json"
    return 0
  }
  export -f github__fetch_release_json
  run github__release_asset_urls "owner/repo" --filter "linux"
  assert_output "https://example.com/tool-linux-x86_64.tar.gz"
  refute_output --partial "darwin"
}

# ---------------------------------------------------------------------------
# github__fetch_release_json  (option parsing and header injection)
# ---------------------------------------------------------------------------

@test "github__fetch_release_json rejects unknown option" {
  run github__fetch_release_json "owner/repo" --bogus
  assert_failure
  assert_output --partial "unknown option"
}

@test "github__fetch_release_json includes Authorization header when GITHUB_TOKEN is set" {
  # Override net__fetch_url_stdout to print all its arguments so we can inspect headers.
  net__fetch_url_stdout() {
    printf '%s\n' "$@"
    return 0
  }
  export -f net__fetch_url_stdout
  GITHUB_TOKEN="mytoken" run github__fetch_release_json "owner/repo"
  assert_output --partial "Authorization: Bearer mytoken"
}

@test "github__fetch_release_json builds a tag URL when --tag is given" {
  net__fetch_url_stdout() {
    printf '%s\n' "$@"
    return 0
  }
  export -f net__fetch_url_stdout
  run github__fetch_release_json "owner/repo" --tag "v2.0.0"
  assert_output --partial "releases/tags/v2.0.0"
}

# ---------------------------------------------------------------------------
# github__release_json_tag_name / github__release_json_id (single-release file)
# ---------------------------------------------------------------------------

@test "github__release_json_tag_name and github__release_json_id parse minified JSON" {
  _fixture="${BATS_TEST_TMPDIR}/release.json"
  printf '%s' '{"url":"u","id":708,"author":{"id":9959},"tag_name":"v2.304.8","draft":false}' > "$_fixture"
  run github__release_json_tag_name "$_fixture"
  assert_success
  assert_output "v2.304.8"
  run github__release_json_id "$_fixture"
  assert_success
  assert_output "708"
}

@test "github__release_json_id reads root id when assets appear first (minified)" {
  _fixture="${BATS_TEST_TMPDIR}/release-assets-first.json"
  # Root id must not be confused with the first asset id in a one-line payload.
  printf '%s' '{"assets":[{"id":111,"name":"a.zip"}],"tag_name":"v9.0","id":999888}' > "$_fixture"
  run github__release_json_tag_name "$_fixture"
  assert_success
  assert_output "v9.0"
  run github__release_json_id "$_fixture"
  assert_success
  assert_output "999888"
}

# ---------------------------------------------------------------------------
# github__release_json_digest_for_asset
# ---------------------------------------------------------------------------

@test "github__release_json_digest_for_asset prints lowercase hex from sha256 digest" {
  _fixture="${BATS_TEST_TMPDIR}/release-fzf-digest.json"
  printf '%s' '{"assets":[{"name":"fzf-0.71.0-linux_amd64.tar.gz","digest":"sha256:ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef0123456789"}]}' > "$_fixture"
  run github__release_json_digest_for_asset "$_fixture" "fzf-0.71.0-linux_amd64.tar.gz"
  assert_success
  assert_output "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
}

@test "github__release_json_digest_for_asset fails when digest absent" {
  _fixture="${BATS_TEST_TMPDIR}/release-no-digest.json"
  printf '%s' '{"assets":[{"name":"tool.tar.gz","size":3}]}' > "$_fixture"
  run github__release_json_digest_for_asset "$_fixture" "tool.tar.gz"
  assert_failure
}

@test "github__release_json_digest_for_asset fails when asset name mismatches" {
  _fixture="${BATS_TEST_TMPDIR}/release-wrong-name.json"
  printf '%s' '{"assets":[{"name":"other.tar.gz","digest":"sha256:00"}]}' > "$_fixture"
  run github__release_json_digest_for_asset "$_fixture" "tool.tar.gz"
  assert_failure
}

@test "github__release_json_digest_from_uri fetches JSON and extracts digest" {
  _fixture="${BATS_TEST_TMPDIR}/release-uri-digest.json"
  printf '%s' '{"assets":[{"name":"tool.tar.gz","digest":"sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"}]}' > "$_fixture"
  _github__api_get() {
    cp "$_fixture" "$2"
    return 0
  }
  export -f _github__api_get
  export _fixture
  run github__release_json_digest_from_uri "https://api.github.com/repos/o/r/releases/tags/v1.0" "tool.tar.gz"
  assert_success
  assert_output "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
}

@test "github__release_json_digest_from_uri fails when API fetch fails" {
  _github__api_get() { return 1; }
  export -f _github__api_get
  run github__release_json_digest_from_uri "https://api.github.com/repos/o/r/releases/tags/v1.0" "tool.tar.gz"
  assert_failure
}

@test "github__release_json_tag_name fails for missing file" {
  run github__release_json_tag_name "${BATS_TEST_TMPDIR}/does-not-exist.json"
  assert_failure
}

# ---------------------------------------------------------------------------
# github__release_asset_urls  (--tag forwarding)
# ---------------------------------------------------------------------------

@test "github__release_asset_urls accepts --tag option" {
  github__fetch_release_json() {
    local _dest=""
    while [ "$#" -gt 0 ]; do
      [ "$1" = "--dest" ] && {
        shift
        _dest="$1"
        shift
        continue
      }
      shift
    done
    [ -n "$_dest" ] && printf '{"assets":[{"browser_download_url":"https://example.com/v2.tar.gz"}]}\n' > "$_dest"
    return 0
  }
  export -f github__fetch_release_json
  run github__release_asset_urls "owner/repo" --tag "v2.0.0"
  assert_success
  assert_output "https://example.com/v2.tar.gz"
}

# ---------------------------------------------------------------------------
# _github__api_list_field  (shared extraction helper)
# ---------------------------------------------------------------------------

@test "_github__api_list_field extracts name field from JSON array" {
  net__fetch_url_stdout() {
    printf '%s\n' '[{"name":"v2.0.0"},{"name":"v1.9.0"}]'
    return 0
  }
  export -f net__fetch_url_stdout
  run _github__api_list_field "https://api.github.com/repos/owner/repo/tags?per_page=100" "name"
  assert_output "v2.0.0
v1.9.0"
  assert_success
}

@test "_github__api_list_field extracts every tag_name from minified one-line JSON" {
  net__fetch_url_stdout() {
    printf '%s' '[{"tag_name":"24.7.1-2","id":1},{"tag_name":"24.7.1-1","id":2},{"tag_name":"4.8.4-0","id":3}]'
    return 0
  }
  export -f net__fetch_url_stdout
  run _github__api_list_field "https://api.github.com/repos/conda-forge/miniforge/releases?per_page=100" "tag_name"
  assert_success
  assert_output "24.7.1-2
24.7.1-1
4.8.4-0"
}

@test "_github__api_list_field returns 1 when fetch fails" {
  net__fetch_url_stdout() { return 1; }
  export -f net__fetch_url_stdout
  run _github__api_list_field "https://api.github.com/repos/owner/repo/tags?per_page=100" "name"
  assert_failure
}

@test "_github__api_list_field returns 1 on empty response" {
  net__fetch_url_stdout() {
    printf ''
    return 0
  }
  export -f net__fetch_url_stdout
  run _github__api_list_field "https://api.github.com/repos/owner/repo/tags?per_page=100" "name"
  assert_failure
}

@test "_github__api_list_field returns 1 when the requested field is absent" {
  net__fetch_url_stdout() {
    printf '{"message":"API rate limit exceeded"}\n'
    return 0
  }
  export -f net__fetch_url_stdout
  run _github__api_list_field "https://api.github.com/repos/owner/repo/tags?per_page=100" "name"
  assert_failure
}

# ---------------------------------------------------------------------------
# github__tags
# ---------------------------------------------------------------------------

@test "github__tags prints tag names from /tags endpoint" {
  net__fetch_url_stdout() {
    printf '%s\n' '[{"name":"v2.48.0"},{"name":"v2.47.2"},{"name":"v2.47.1"}]'
    return 0
  }
  export -f net__fetch_url_stdout
  run github__tags "git/git"
  assert_output "v2.48.0
v2.47.2
v2.47.1"
  assert_success
}

@test "github__tags accepts --per_page option" {
  # Stub _github__api_get to echo the URL as a "name" field so it passes
  # through json extraction and appears in the final output.
  _github__api_get() {
    printf '[{"name":"%s"}]\n' "$1"
    return 0
  }
  export -f _github__api_get
  run github__tags "git/git" --per_page 50
  assert_output --partial "tags?per_page=50"
  assert_success
}

@test "github__tags rejects unknown option" {
  run github__tags "git/git" --bogus
  assert_failure
  assert_output --partial "unknown option"
}

@test "github__tags fails when API call fails" {
  net__fetch_url_stdout() { return 1; }
  export -f net__fetch_url_stdout
  run github__tags "git/git"
  assert_failure
  assert_output --partial "failed to reach GitHub API"
}

@test "github__tags fails when the tags response has no name fields" {
  net__fetch_url_stdout() {
    printf '{"message":"API rate limit exceeded"}\n'
    return 0
  }
  export -f net__fetch_url_stdout
  run github__tags "git/git"
  assert_failure
  assert_output --partial "failed to reach GitHub API"
}

# ---------------------------------------------------------------------------
# github__release_tags still works after refactor
# ---------------------------------------------------------------------------

@test "github__release_tags still parses tag_name via shared helper" {
  net__fetch_url_stdout() {
    printf '%s\n' '[{"tag_name":"v3.0.0"},{"tag_name":"v2.9.0"}]'
    return 0
  }
  export -f net__fetch_url_stdout
  run github__release_tags "owner/repo"
  assert_output "v3.0.0
v2.9.0"
  assert_success
}

# ---------------------------------------------------------------------------
# github__pick_release_asset  (heuristic asset selector)
#
# All tests stub github__release_asset_urls, os__arch, and os__kernel to
# avoid network calls and make assertions deterministic.
# ---------------------------------------------------------------------------

# Helper: stub os__arch and os__kernel to fixed values.
_stub_arch_kernel() {
  _STUB_ARCH="$1"
  _STUB_KERNEL="$2"
  export _STUB_ARCH _STUB_KERNEL
  os__arch() { printf '%s\n' "$_STUB_ARCH"; }
  os__kernel() { printf '%s\n' "$_STUB_KERNEL"; }
  export -f os__arch os__kernel
}

# Helper: stub github__release_asset_urls to print the given newline-separated URLs.
_stub_urls() {
  _STUB_URLS="$1"
  export _STUB_URLS
  github__release_asset_urls() {
    printf '%s\n' "$_STUB_URLS"
    return 0
  }
  export -f github__release_asset_urls
}

# --- basic success / failure ------------------------------------------------

@test "github__pick_release_asset returns the single matching URL" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64.tar.gz"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/tool-linux-amd64.tar.gz"
}

@test "github__pick_release_asset fails when no assets are returned" {
  _stub_arch_kernel "x86_64" "Linux"
  github__release_asset_urls() { return 1; }
  export -f github__release_asset_urls
  run github__pick_release_asset "owner/repo"
  assert_failure
}

@test "github__pick_release_asset fails when asset list is empty" {
  _stub_arch_kernel "x86_64" "Linux"
  github__release_asset_urls() {
    printf ''
    return 0
  }
  export -f github__release_asset_urls
  run github__pick_release_asset "owner/repo"
  assert_failure
  assert_output --partial "no assets found"
}

@test "github__pick_release_asset rejects unknown option" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool.tar.gz"
  run github__pick_release_asset "owner/repo" --bogus
  assert_failure
  assert_output --partial "unknown option"
}

# --- --asset-regex pre-filter -----------------------------------------------

@test "github__pick_release_asset --asset-regex: exact single match returns immediately" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64.tar.gz
https://example.com/tool-linux-arm64.tar.gz
https://example.com/tool-darwin-amd64.tar.gz"
  run github__pick_release_asset "owner/repo" --asset-regex "linux-amd64"
  assert_success
  assert_output "https://example.com/tool-linux-amd64.tar.gz"
}

@test "github__pick_release_asset --asset-regex: no match returns failure" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64.tar.gz"
  run github__pick_release_asset "owner/repo" --asset-regex "does-not-match"
  assert_failure
  assert_output --partial "matched no assets"
}

# --- negative arch filter ---------------------------------------------------

@test "github__pick_release_asset removes other-arch assets on x86_64" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64.tar.gz
https://example.com/tool-linux-arm64.tar.gz
https://example.com/tool-linux-aarch64.tar.gz"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/tool-linux-amd64.tar.gz"
}

@test "github__pick_release_asset removes other-arch assets on aarch64" {
  _stub_arch_kernel "aarch64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64.tar.gz
https://example.com/tool-linux-arm64.tar.gz"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/tool-linux-arm64.tar.gz"
}

@test "github__pick_release_asset skips arch filter when it would produce empty list" {
  # Only one asset; it would be removed by the bad-arch filter (no arch keyword
  # matches x86_64 negative patterns).  The filter must be skipped.
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux.tar.gz"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/tool-linux.tar.gz"
}

# --- negative platform filter -----------------------------------------------

@test "github__pick_release_asset removes Windows assets on Linux" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64.tar.gz
https://example.com/tool-windows-amd64.exe
https://example.com/tool-Windows-amd64.zip"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/tool-linux-amd64.tar.gz"
}

@test "github__pick_release_asset removes macOS assets on Linux" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64.tar.gz
https://example.com/tool-darwin-amd64.tar.gz"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/tool-linux-amd64.tar.gz"
}

@test "github__pick_release_asset removes Linux assets on Darwin" {
  _stub_arch_kernel "x86_64" "Darwin"
  _stub_urls "https://example.com/tool-darwin-amd64.tar.gz
https://example.com/tool-linux-amd64.tar.gz"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/tool-darwin-amd64.tar.gz"
}

# --- negative misc filter ---------------------------------------------------

@test "github__pick_release_asset removes checksum files" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64.tar.gz
https://example.com/tool-linux-amd64.tar.gz.sha256
https://example.com/Checksums.txt"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/tool-linux-amd64.tar.gz"
}

@test "github__pick_release_asset removes .deb and .rpm packages" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64.tar.gz
https://example.com/tool-amd64.deb
https://example.com/tool-x86_64.rpm"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/tool-linux-amd64.tar.gz"
}

@test "github__pick_release_asset skips misc filter when it would empty the list" {
  # All assets are .txt — the misc filter would remove everything, so it must
  # be skipped and we still get exactly one candidate.
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/install.txt"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/install.txt"
}

# --- positive arch tiebreaker -----------------------------------------------

@test "github__pick_release_asset prefers explicit arch match (amd64) on x86_64" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64.tar.gz
https://example.com/tool-linux.tar.gz"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/tool-linux-amd64.tar.gz"
}

@test "github__pick_release_asset prefers explicit arch match (arm64) on aarch64" {
  _stub_arch_kernel "aarch64" "Linux"
  _stub_urls "https://example.com/tool-linux-arm64.tar.gz
https://example.com/tool-linux.tar.gz"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/tool-linux-arm64.tar.gz"
}

# --- positive static/musl tiebreaker ----------------------------------------

@test "github__pick_release_asset prefers musl/static build when multiple remain" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64-musl.tar.gz
https://example.com/tool-linux-amd64-gnu.tar.gz"
  run github__pick_release_asset "owner/repo"
  assert_success
  assert_output "https://example.com/tool-linux-amd64-musl.tar.gz"
}

# --- ambiguity error --------------------------------------------------------

@test "github__pick_release_asset fails when more than one candidate remains" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64-v1.tar.gz
https://example.com/tool-linux-amd64-v2.tar.gz"
  run github__pick_release_asset "owner/repo"
  assert_failure
  assert_output --partial "ambiguous"
}

@test "github__pick_release_asset lists filenames on ambiguity" {
  _stub_arch_kernel "x86_64" "Linux"
  _stub_urls "https://example.com/tool-linux-amd64-v1.tar.gz
https://example.com/tool-linux-amd64-v2.tar.gz"
  run github__pick_release_asset "owner/repo"
  assert_failure
  assert_output --partial "tool-linux-amd64-v1.tar.gz"
  assert_output --partial "tool-linux-amd64-v2.tar.gz"
}

# --- --tag forwarding -------------------------------------------------------

@test "github__pick_release_asset passes --tag to github__release_asset_urls" {
  _stub_arch_kernel "x86_64" "Linux"
  github__release_asset_urls() {
    # Capture the arguments and echo back the tag value found.
    while [ "$#" -gt 0 ]; do
      [ "$1" = "--tag" ] && {
        printf 'TAG=%s\n' "$2"
        return 0
      }
      shift
    done
    printf 'NO_TAG\n'
    return 0
  }
  export -f github__release_asset_urls
  run github__pick_release_asset "owner/repo" --tag "v1.2.3"
  assert_success
  assert_output "TAG=v1.2.3"
}

# ---------------------------------------------------------------------------
# github__resolve_version
# ---------------------------------------------------------------------------

@test "github__resolve_version empty spec delegates to github__latest_tag" {
  github__latest_tag() {
    printf 'v3.0.1\n'
    return 0
  }
  export -f github__latest_tag
  run github__resolve_version "owner/repo" ""
  assert_success
  assert_output "v3.0.1
3.0.1"
}

@test "github__resolve_version 'stable' spec delegates to github__latest_tag" {
  github__latest_tag() {
    printf 'v2.5.0\n'
    return 0
  }
  export -f github__latest_tag
  run github__resolve_version "owner/repo" "stable"
  assert_success
  assert_output "v2.5.0
2.5.0"
}

@test "github__resolve_version omitted spec defaults to stable" {
  github__latest_tag() {
    printf 'v4.0.0\n'
    return 0
  }
  export -f github__latest_tag
  run github__resolve_version "owner/repo"
  assert_success
  assert_output "v4.0.0
4.0.0"
}

@test "github__resolve_version non-v tag prefix is stripped in bare version" {
  github__latest_tag() {
    printf 'jq-1.7.1\n'
    return 0
  }
  export -f github__latest_tag
  run github__resolve_version "owner/repo" "stable"
  assert_success
  assert_output "jq-1.7.1
1.7.1"
}

@test "github__resolve_version stable failure propagates" {
  github__latest_tag() { return 1; }
  export -f github__latest_tag
  run github__resolve_version "owner/repo" "" --endpoint release
  assert_failure
  assert_output --partial "no release matching"
}

@test "github__resolve_version 'latest' uses list API, not github__latest_tag" {
  github__latest_tag() {
    echo "⛔ unexpected call to github__latest_tag" >&2
    return 1
  }
  _github__api_list_field() {
    printf 'v5.0.0-beta.1\n'
    return 0
  }
  export -f github__latest_tag _github__api_list_field
  run github__resolve_version "owner/repo" "latest"
  assert_success
  assert_output "v5.0.0-beta.1
5.0.0-beta.1"
}

@test "github__resolve_version 'latest' failure propagates" {
  _github__api_list_field() { return 1; }
  export -f _github__api_list_field
  run github__resolve_version "owner/repo" "latest" --endpoint release
  assert_failure
  assert_output --partial "no release matching"
}

@test "github__resolve_version exact X.Y.Z spec resolves to matching stable tag" {
  _github__api_get() {
    printf '[{"tag_name":"v1.2.3","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "1.2.3"
  assert_success
  assert_output "v1.2.3
1.2.3"
}

@test "github__resolve_version v-prefixed spec is equivalent to bare spec" {
  _github__api_get() {
    printf '[{"tag_name":"v1.2.3","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "v1.2.3"
  assert_success
  assert_output "v1.2.3
1.2.3"
}

@test "github__resolve_version MAJOR spec resolves to newest stable matching tag" {
  _github__api_get() {
    printf '[{"tag_name":"v3.0.0","prerelease":false,"draft":false},{"tag_name":"v2.9.1","prerelease":false,"draft":false},{"tag_name":"v2.9.0","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "2"
  assert_success
  assert_output "v2.9.1
2.9.1"
}

@test "github__resolve_version MAJOR.MINOR spec resolves to newest stable matching tag" {
  _github__api_get() {
    printf '[{"tag_name":"v2.10.0","prerelease":false,"draft":false},{"tag_name":"v2.9.1","prerelease":false,"draft":false},{"tag_name":"v2.9.0","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "2.9"
  assert_success
  assert_output "v2.9.1
2.9.1"
}

@test "github__resolve_version spec '2' does not match tag 'v20.0.0'" {
  _github__api_get() {
    printf '[{"tag_name":"v20.0.0","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "2" --endpoint release
  assert_failure
  assert_output --partial "no release matching '2'"
}

@test "github__resolve_version spec '1.2' does not match tag 'v1.20.0'" {
  _github__api_get() {
    printf '[{"tag_name":"v1.20.0","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "1.2" --endpoint release
  assert_failure
  assert_output --partial "no release matching '1.2'"
}

@test "github__resolve_version pre-releases are skipped when resolving numeric spec" {
  _github__api_get() {
    printf '[{"tag_name":"v1.2.3-rc.1","prerelease":true,"draft":false},{"tag_name":"v1.2.2","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "1.2"
  assert_success
  assert_output "v1.2.2
1.2.2"
}

@test "github__resolve_version draft releases are skipped when resolving numeric spec" {
  _github__api_get() {
    printf '[{"tag_name":"v1.2.3","prerelease":false,"draft":true},{"tag_name":"v1.2.2","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "1.2"
  assert_success
  assert_output "v1.2.2
1.2.2"
}

@test "github__resolve_version spec 'X.Y.Z' matches build-suffix tag 'X.Y.Z-N'" {
  _github__api_get() {
    printf '[{"tag_name":"24.11.0-1","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "24.11.0"
  assert_success
  assert_output "24.11.0-1
24.11.0-1"
}

@test "github__resolve_version jq-style prefixed spec matches tag with same prefix" {
  _github__api_get() {
    printf '[{"tag_name":"jq-1.7.1","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "jq-1.7.1"
  assert_success
  assert_output "jq-1.7.1
1.7.1"
}

@test "github__resolve_version finds match on page 2 when page 1 has only pre-releases" {
  _github__api_get() {
    case "$1" in
      *\&page=1)
        local i
        printf '['
        for i in $(seq 1 100); do
          [ "$i" -gt 1 ] && printf ','
          printf '{"tag_name":"v2.%d.0-rc.1","prerelease":true,"draft":false}' "$i"
        done
        printf ']\n'
        return 0
        ;;
      *\&page=2)
        printf '[{"tag_name":"v2.0.0","prerelease":false,"draft":false}]\n'
        return 0
        ;;
      *)
        echo "⛔ unexpected page: $1" >&2
        return 1
        ;;
    esac
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "2"
  assert_success
  assert_output "v2.0.0
2.0.0"
}

@test "github__resolve_version stops pagination immediately after match is found" {
  # Page 2 is a full page (100 items) — without early exit the function would
  # request page 3; the catch-all arm fails to prove page 3 is never fetched.
  _github__api_get() {
    case "$1" in
      *\&page=1)
        local i
        printf '['
        for i in $(seq 1 100); do
          [ "$i" -gt 1 ] && printf ','
          printf '{"tag_name":"v0.%d.0","prerelease":true,"draft":false}' "$i"
        done
        printf ']\n'
        return 0
        ;;
      *\&page=2)
        local i
        printf '[{"tag_name":"v1.0.0","prerelease":false,"draft":false}'
        for i in $(seq 1 99); do
          printf ',{"tag_name":"v0.%d.1","prerelease":true,"draft":false}' "$i"
        done
        printf ']\n'
        return 0
        ;;
      *)
        echo "⛔ unexpected page beyond page 2: $1" >&2
        return 1
        ;;
    esac
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "1"
  assert_success
  assert_output "v1.0.0
1.0.0"
}

@test "github__resolve_version fails when no stable release matches spec" {
  _github__api_get() {
    printf '[{"tag_name":"v3.0.0","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "9" --endpoint release
  assert_failure
  assert_output --partial "no release matching '9'"
}

@test "github__resolve_version spec with no numeric content fails immediately" {
  _github__api_get() {
    echo "⛔ unexpected API call" >&2
    return 1
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "abc"
  assert_failure
  assert_output --partial "no numeric version content"
}

@test "github__resolve_version rejects unknown option" {
  run github__resolve_version "owner/repo" "--bogus"
  assert_failure
  assert_output --partial "unknown option"
}

@test "github__resolve_version rejects extra positional argument" {
  run github__resolve_version "owner/repo" "1.2.3" "extra"
  assert_failure
  assert_output --partial "unexpected positional"
}

# --- --endpoint flag --------------------------------------------------------

@test "github__resolve_version --endpoint with invalid value fails" {
  run github__resolve_version "owner/repo" --endpoint bogus
  assert_failure
  assert_output --partial "must be 'release', 'tag', or 'auto'"
}

@test "github__resolve_version --endpoint release uses releases API and succeeds" {
  github__latest_tag() {
    printf 'v9.1.0\n'
    return 0
  }
  export -f github__latest_tag
  run github__resolve_version "owner/repo" "stable" --endpoint release
  assert_success
  assert_output "v9.1.0
9.1.0"
}

@test "github__resolve_version --endpoint release failure gives 'no release matching' error" {
  github__latest_tag() { return 1; }
  export -f github__latest_tag
  run github__resolve_version "owner/repo" "stable" --endpoint release
  assert_failure
  assert_output --partial "no release matching"
  refute_output --partial "no tag matching"
  refute_output --partial "no release or tag"
}

@test "github__resolve_version --endpoint tag stable finds newest non-prerelease tag" {
  github__tags() {
    printf 'v2.0.0-rc1\nv1.5.0\nv1.4.2\n'
    return 0
  }
  export -f github__tags
  run github__resolve_version "owner/repo" "stable" --endpoint tag
  assert_success
  assert_output "v1.5.0
1.5.0"
}

@test "github__resolve_version --endpoint tag stable skips tags with pre-release suffix" {
  # All tags contain a hyphen in the bare version — none are considered stable.
  github__tags() {
    printf 'v1.0.0-rc2\nv0.9.0-beta\n'
    return 0
  }
  export -f github__tags
  run github__resolve_version "owner/repo" "stable" --endpoint tag
  assert_failure
  assert_output --partial "no tag matching"
}

@test "github__resolve_version --endpoint tag latest returns first tag" {
  github__tags() {
    printf 'v3.0.0-beta\nv2.9.1\n'
    return 0
  }
  export -f github__tags
  run github__resolve_version "owner/repo" "latest" --endpoint tag
  assert_success
  assert_output "v3.0.0-beta
3.0.0-beta"
}

@test "github__resolve_version --endpoint tag numeric spec finds matching tag" {
  github__tags() {
    printf 'v2.1.0\nv1.3.5\nv1.2.1\nv1.1.0\n'
    return 0
  }
  export -f github__tags
  run github__resolve_version "owner/repo" "1.2" --endpoint tag
  assert_success
  assert_output "v1.2.1
1.2.1"
}

@test "github__resolve_version --endpoint tag failure gives 'no tag matching' error" {
  github__tags() { return 1; }
  export -f github__tags
  run github__resolve_version "owner/repo" "stable" --endpoint tag
  assert_failure
  assert_output --partial "no tag matching"
  refute_output --partial "no release matching"
  refute_output --partial "no release or tag"
}

@test "github__resolve_version auto falls back to tags when releases return empty (stable)" {
  github__latest_tag() { return 1; }
  github__tags() {
    printf 'v4.2.0\n'
    return 0
  }
  export -f github__latest_tag github__tags
  run github__resolve_version "owner/repo" "stable"
  assert_success
  assert_output "v4.2.0
4.2.0"
}

@test "github__resolve_version auto falls back to tags when releases return empty (numeric spec)" {
  _github__first_release_matching() { return 1; }
  github__tags() {
    printf 'v1.9.0\nv1.8.3\n'
    return 0
  }
  export -f _github__first_release_matching github__tags
  run github__resolve_version "owner/repo" "1.8"
  assert_success
  assert_output "v1.8.3
1.8.3"
}

@test "github__resolve_version auto gives combined error when both APIs return nothing" {
  github__latest_tag() { return 1; }
  github__tags() { return 1; }
  export -f github__latest_tag github__tags
  run github__resolve_version "owner/repo" "stable"
  assert_failure
  assert_output --partial "no release or tag matching"
}

# ---------------------------------------------------------------------------
# _github__first_release_matching (internal)
# ---------------------------------------------------------------------------
# These tests exercise the internal helper directly to verify that refactoring
# for --tag-prefix and --prerelease did not alter the original stable-filter
# and pagination behaviour.

@test "_github__first_release_matching baseline: pre-releases are excluded" {
  _github__api_get() {
    printf '[{"tag_name":"v1.2.3-rc1","prerelease":true,"draft":false},{"tag_name":"v1.2.2","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run _github__first_release_matching "https://api.github.com/repos/owner/repo" "1.2"
  assert_success
  assert_output "v1.2.2"
}

@test "_github__first_release_matching baseline: draft releases are excluded" {
  _github__api_get() {
    printf '[{"tag_name":"v1.2.3","prerelease":false,"draft":true},{"tag_name":"v1.2.2","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run _github__first_release_matching "https://api.github.com/repos/owner/repo" "1.2"
  assert_success
  assert_output "v1.2.2"
}

@test "_github__first_release_matching baseline: returns failure when no stable match exists" {
  _github__api_get() {
    printf '[{"tag_name":"v1.2.3-rc1","prerelease":true,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run _github__first_release_matching "https://api.github.com/repos/owner/repo" "1.2"
  assert_failure
}

@test "_github__first_release_matching norm_spec='' returns first (newest) stable tag" {
  # New code path used by stable+tag_prefix; head -1 of filtered list.
  _github__api_get() {
    printf '[{"tag_name":"v2.0.0","prerelease":false,"draft":false},{"tag_name":"v1.9.0","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run _github__first_release_matching "https://api.github.com/repos/owner/repo" ""
  assert_success
  assert_output "v2.0.0"
}

@test "_github__first_release_matching norm_spec='' skips pre-releases even when first" {
  _github__api_get() {
    printf '[{"tag_name":"v2.0.0-rc1","prerelease":true,"draft":false},{"tag_name":"v1.9.0","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run _github__first_release_matching "https://api.github.com/repos/owner/repo" ""
  assert_success
  assert_output "v1.9.0"
}

@test "_github__first_release_matching --prerelease: pre-releases are included" {
  _github__api_get() {
    printf '[{"tag_name":"v1.2.3-rc1","prerelease":true,"draft":false},{"tag_name":"v1.2.2","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run _github__first_release_matching "https://api.github.com/repos/owner/repo" "1.2" --prerelease
  assert_success
  assert_output "v1.2.3-rc1"
}

@test "_github__first_release_matching --prerelease + norm_spec='': returns first release regardless of prerelease status" {
  # Used by latest+tag_prefix: returns the newest item in the filtered list.
  _github__api_get() {
    printf '[{"tag_name":"v2.0.0-rc1","prerelease":true,"draft":false},{"tag_name":"v1.9.0","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run _github__first_release_matching "https://api.github.com/repos/owner/repo" "" --prerelease
  assert_success
  assert_output "v2.0.0-rc1"
}

@test "_github__first_release_matching --tag-prefix + norm_spec='': returns first stable tag matching prefix" {
  _github__api_get() {
    printf '[{"tag_name":"install-just/1.0.0","prerelease":false,"draft":false},{"tag_name":"lib/0.2.0","prerelease":false,"draft":false},{"tag_name":"lib/0.1.0","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run _github__first_release_matching "https://api.github.com/repos/owner/repo" "" --tag-prefix "lib/"
  assert_success
  assert_output "lib/0.2.0"
}

@test "_github__first_release_matching --tag-prefix + norm_spec='': skips non-matching prefix even if first" {
  _github__api_get() {
    printf '[{"tag_name":"install-just/1.0.0","prerelease":false,"draft":false},{"tag_name":"lib/0.2.0","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run _github__first_release_matching "https://api.github.com/repos/owner/repo" "" --tag-prefix "lib/"
  assert_success
  assert_output "lib/0.2.0"
}

@test "_github__first_release_matching --tag-prefix: paginates when full page has no matching-prefix releases" {
  _github__api_get() {
    case "$1" in
      *\&page=1)
        # Full page (100 items), none with lib/ prefix.
        local i out='['
        for i in $(seq 1 100); do
          [ "$i" -gt 1 ] && out="${out},"
          out="${out}{\"tag_name\":\"install-just/${i}.0.0\",\"prerelease\":false,\"draft\":false}"
        done
        printf '%s]\n' "$out"
        ;;
      *\&page=2)
        printf '[{"tag_name":"lib/0.1.0","prerelease":false,"draft":false}]\n'
        ;;
      *)
        echo "unexpected page: $1" >&2
        return 1
        ;;
    esac
    return 0
  }
  export -f _github__api_get
  run _github__first_release_matching "https://api.github.com/repos/owner/repo" "" --tag-prefix "lib/"
  assert_success
  assert_output "lib/0.1.0"
}

@test "_github__first_release_matching rejects unknown option" {
  _github__api_get() { return 0; }
  export -f _github__api_get
  run _github__first_release_matching "https://api.github.com/repos/owner/repo" "1.0" --bad-flag
  assert_failure
  assert_output --partial "unknown option"
}

# --- --tag-prefix flag -------------------------------------------------------

@test "github__resolve_version --tag-prefix stable uses pagination not latest_tag" {
  # When tag_prefix is set, github__latest_tag must NOT be called (it can't filter).
  # Instead, paginated listing is used and filtered by prefix.
  github__latest_tag() {
    printf 'install-just/1.0.0\n'
    return 0
  }
  export -f github__latest_tag
  _github__api_get() {
    printf '[{"tag_name":"lib/0.2.0","prerelease":false,"draft":false},{"tag_name":"install-just/1.0.0","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "stable" --tag-prefix "lib/" --endpoint release
  assert_success
  assert_output "lib/0.2.0
0.2.0"
}

@test "github__resolve_version --tag-prefix stable skips releases outside prefix" {
  _github__api_get() {
    printf '[{"tag_name":"install-just/1.0.0","prerelease":false,"draft":false},{"tag_name":"install-taskfile/2.0.0","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "stable" --tag-prefix "lib/" --endpoint release
  assert_failure
  assert_output --partial "no release matching"
}

@test "github__resolve_version --tag-prefix latest uses pagination not per_page=1" {
  _github__api_get() {
    printf '[{"tag_name":"install-just/2.0.0-rc1","prerelease":true,"draft":false},{"tag_name":"lib/0.3.0-rc1","prerelease":true,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "latest" --tag-prefix "lib/" --endpoint release
  assert_success
  assert_output "lib/0.3.0-rc1
0.3.0-rc1"
}

@test "github__resolve_version --tag-prefix numeric spec filters releases to prefix" {
  _github__api_get() {
    # Mix of lib/* and other feature releases; spec 1.2 must only match lib/*
    printf '[{"tag_name":"install-just/1.2.0","prerelease":false,"draft":false},{"tag_name":"lib/1.2.3","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "1.2" --tag-prefix "lib/" --endpoint release
  assert_success
  assert_output "lib/1.2.3
1.2.3"
}

@test "github__resolve_version --tag-prefix numeric spec does not spuriously match other release lines" {
  _github__api_get() {
    printf '[{"tag_name":"install-just/1.2.0","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "1.2" --tag-prefix "lib/" --endpoint release
  assert_failure
  assert_output --partial "no release matching '1.2'"
}

@test "github__resolve_version --tag-prefix exact version resolves correctly" {
  _github__api_get() {
    printf '[{"tag_name":"lib/0.1.0","prerelease":false,"draft":false}]\n'
    return 0
  }
  export -f _github__api_get
  run github__resolve_version "owner/repo" "0.1.0" --tag-prefix "lib/" --endpoint release
  assert_success
  assert_output "lib/0.1.0
0.1.0"
}

@test "github__resolve_version without --tag-prefix behavior unchanged (regression)" {
  github__latest_tag() {
    printf 'v3.0.0\n'
    return 0
  }
  export -f github__latest_tag
  run github__resolve_version "owner/repo" "stable" --endpoint release
  assert_success
  assert_output "v3.0.0
3.0.0"
}

# --- --tag-prefix: tags API fallback -----------------------------------------

@test "github__resolve_version --tag-prefix stable: auto falls back to tags and filters by prefix" {
  # Releases API returns nothing for the prefix; tags API has mixed tags.
  _github__first_release_matching() { return 1; }
  export -f _github__first_release_matching
  github__tags() {
    printf 'install-just/1.0.0\nlib/0.2.0\nlib/0.1.0-rc1\nlib/0.1.0\n'
    return 0
  }
  export -f github__tags
  run github__resolve_version "owner/repo" "stable" --tag-prefix "lib/"
  assert_success
  # lib/0.2.0 is first stable (lib/0.1.0-rc1 is pre-release suffix → skipped)
  assert_output "lib/0.2.0
0.2.0"
}

@test "github__resolve_version --tag-prefix stable: tags API skips pre-release-suffix tags" {
  _github__first_release_matching() { return 1; }
  export -f _github__first_release_matching
  github__tags() {
    printf 'lib/0.2.0-rc1\nlib/0.1.0-beta\n'
    return 0
  }
  export -f github__tags
  run github__resolve_version "owner/repo" "stable" --tag-prefix "lib/"
  assert_failure
  assert_output --partial "no release or tag matching"
}

@test "github__resolve_version --tag-prefix latest: auto falls back to tags and takes first matching tag" {
  # latest accepts pre-releases; the first matching-prefix tag wins.
  _github__first_release_matching() { return 1; }
  export -f _github__first_release_matching
  github__tags() {
    printf 'install-just/1.0.0\nlib/0.3.0-rc1\nlib/0.2.0\n'
    return 0
  }
  export -f github__tags
  run github__resolve_version "owner/repo" "latest" --tag-prefix "lib/"
  assert_success
  assert_output "lib/0.3.0-rc1
0.3.0-rc1"
}

@test "github__resolve_version --tag-prefix numeric: auto falls back to tags and version-matches within prefix" {
  _github__first_release_matching() { return 1; }
  export -f _github__first_release_matching
  github__tags() {
    printf 'install-just/1.2.0\nlib/0.2.5\nlib/0.2.0\nlib/0.1.0\n'
    return 0
  }
  export -f github__tags
  run github__resolve_version "owner/repo" "0.2" --tag-prefix "lib/"
  assert_success
  assert_output "lib/0.2.5
0.2.5"
}

@test "github__resolve_version --tag-prefix numeric: tags API does not match tags outside prefix" {
  _github__first_release_matching() { return 1; }
  export -f _github__first_release_matching
  github__tags() {
    printf 'install-just/1.2.0\ninstall-taskfile/1.2.5\n'
    return 0
  }
  export -f github__tags
  run github__resolve_version "owner/repo" "1.2" --tag-prefix "lib/"
  assert_failure
  assert_output --partial "no release or tag matching"
}

@test "github__resolve_version --tag-prefix: fails when no prefix match in either API" {
  _github__first_release_matching() { return 1; }
  github__tags() { return 1; }
  export -f _github__first_release_matching github__tags
  run github__resolve_version "owner/repo" "stable" --tag-prefix "lib/"
  assert_failure
  assert_output --partial "no release or tag matching"
}

# ---------------------------------------------------------------------------
# github__release_tags --all pagination
# ---------------------------------------------------------------------------

@test "github__release_tags --all walks pages until a short page" {
  # Fake _github__api_get returns 100-item page 1, 3-item page 2, empty page 3.
  # Patterns MUST anchor on '&page=' (with leading '&') so they don't false-match
  # the 'per_page=100' substring (which also contains 'page=1').
  _github__api_get() {
    case "$1" in
      *\&page=1)
        local i
        printf '['
        for i in $(seq 1 100); do
          [ "$i" -gt 1 ] && printf ','
          printf '{"tag_name":"p1-%d"}' "$i"
        done
        printf ']\n'
        return 0
        ;;
      *\&page=2)
        printf '[{"tag_name":"p2-1"},{"tag_name":"p2-2"},{"tag_name":"p2-3"}]\n'
        return 0
        ;;
      *)
        printf '[]\n'
        return 0
        ;;
    esac
  }
  export -f _github__api_get
  run github__release_tags "owner/repo" --all
  assert_success
  # Expect 103 lines total.
  [ "${#lines[@]}" -eq 103 ]
  [ "${lines[0]}" = "p1-1" ]
  [ "${lines[99]}" = "p1-100" ]
  [ "${lines[100]}" = "p2-1" ]
  [ "${lines[102]}" = "p2-3" ]
}

@test "github__release_tags without --all fetches only first page" {
  # Non-paginated call contains 'per_page=100' and has NO '&page=' segment.
  # Match the paginated-call case on '&page=' so it doesn't false-match the
  # 'per_page=…' substring.
  _github__api_get() {
    case "$1" in
      *\&page=*)
        echo "⛔ unexpected paginated call: $1" >&2
        return 1
        ;;
      *per_page=100*)
        printf '[{"tag_name":"only-1"},{"tag_name":"only-2"}]\n'
        return 0
        ;;
    esac
  }
  export -f _github__api_get
  run github__release_tags "owner/repo"
  assert_success
  assert_output "only-1
only-2"
}

@test "github__release_tags --all short single page terminates after one request" {
  # 50 items on page=1 with per_page=100 → short page → terminate without
  # fetching page=2. Pattern must anchor on '&page=' to avoid false-matching
  # 'per_page=100'.
  _github__api_get() {
    case "$1" in
      *\&page=1)
        local i
        printf '['
        for i in $(seq 1 50); do
          [ "$i" -gt 1 ] && printf ','
          printf '{"tag_name":"t%d"}' "$i"
        done
        printf ']\n'
        return 0
        ;;
      *)
        echo "⛔ unexpected subsequent page request: $1" >&2
        return 1
        ;;
    esac
  }
  export -f _github__api_get
  run github__release_tags "owner/repo" --all
  assert_success
  [ "${#lines[@]}" -eq 50 ]
  [ "${lines[0]}" = "t1" ]
  [ "${lines[49]}" = "t50" ]
}

@test "github__tags --all walks pages until a short page" {
  _github__api_get() {
    case "$1" in
      *\&page=1)
        local i
        printf '['
        for i in $(seq 1 100); do
          [ "$i" -gt 1 ] && printf ','
          printf '{"name":"t1-%d"}' "$i"
        done
        printf ']\n'
        return 0
        ;;
      *\&page=2)
        printf '[{"name":"t2-1"},{"name":"t2-2"}]\n'
        return 0
        ;;
      *)
        printf '[]\n'
        return 0
        ;;
    esac
  }
  export -f _github__api_get
  run github__tags "owner/repo" --all
  assert_success
  [ "${#lines[@]}" -eq 102 ]
  [ "${lines[101]}" = "t2-2" ]
}

# ---------------------------------------------------------------------------
# github__fetch_release_asset_tarball
# ---------------------------------------------------------------------------

@test "github__fetch_release_asset_tarball downloads asset when API omits digest" {
  _dest="$(mktemp "${BATS_TEST_TMPDIR}/gh-asset.XXXXXX")"
  github__fetch_release_json() {
    while [ $# -gt 0 ]; do
      case "$1" in
        --dest)
          printf '%s' '{"assets":[]}' > "$2"
          return 0
          ;;
        *) shift ;;
      esac
    done
    return 1
  }
  net__fetch_url_file() {
    printf 'tar-bytes' > "$2"
    return 0
  }
  export -f github__fetch_release_json net__fetch_url_file
  run github__fetch_release_asset_tarball "o/r" "t1" "a.tgz" "$_dest"
  assert_success
  run cat "$_dest"
  assert_output "tar-bytes"
  rm -f "$_dest"
}

# ---------------------------------------------------------------------------
# github__install_release
# ---------------------------------------------------------------------------

# Configure stubs for a minimal happy-path run:
#   ELF direct binary, no JSON digest, no GPG; sidecar probes all fail.
_stub_install_release_common() {
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"

  net__fetch_url_file() {
    # Fail sidecar probe candidates so auto-detection is a no-op by default.
    case "$1" in
      *.sha256 | */SHA256SUMS | */sha256sum.txt) return 1 ;;
    esac
    printf '\x7fELF\x00\x00' > "$2"
    return 0
  }
  export -f net__fetch_url_file

  github__fetch_release_json() {
    local _d=""
    while [ $# -gt 0 ]; do
      case "$1" in --dest)
        shift
        _d="$1"
        shift
        ;;
      *) shift ;; esac
    done
    [ -n "$_d" ] && printf '{"assets":[]}' > "$_d"
    return 0
  }
  export -f github__fetch_release_json

  github__release_json_digest_for_asset() { return 1; }
  export -f github__release_json_digest_for_asset
  github__release_json_digest_from_uri() { return 1; }
  export -f github__release_json_digest_from_uri

  file__detect_type() { printf 'elf'; }
  export -f file__detect_type

  install__copy_bin() {
    touch "$2"
    chmod +x "$2"
    return 0
  }
  export -f install__copy_bin

  _TRACKED_PATHS="${BATS_TEST_TMPDIR}/_tracked"
  export _TRACKED_PATHS
  install__track_internal_path() {
    printf '%s %s\n' "$1" "$2" >> "$_TRACKED_PATHS"
    return 0
  }
  export -f install__track_internal_path

  _VERIFY_SHA_CALLS="${BATS_TEST_TMPDIR}/_sha_calls"
  _VERIFY_GPG_CALLS="${BATS_TEST_TMPDIR}/_gpg_calls"
  export _VERIFY_SHA_CALLS _VERIFY_GPG_CALLS
  verify__sha() {
    printf '%s %s\n' "$1" "$2" >> "$_VERIFY_SHA_CALLS"
    return 0
  }
  export -f verify__sha
  verify__gpg_detached() {
    printf '%s\n' "$@" >> "$_VERIFY_GPG_CALLS"
    return 0
  }
  export -f verify__gpg_detached
}

# install_release resolves JSON digest via github__release_json_digest_from_uri.
_stub_github_json_digest_from_uri() {
  github__release_json_digest_from_uri() {
    printf '%s\n' "${_DIGEST:-${_JSON_HASH:-}}"
    return 0
  }
  export -f github__release_json_digest_from_uri
}

# fetch_release_asset_tarball reads digest via _github__release_json_digest_for_asset.
_stub_github_release_json_digest_for_asset() {
  _github__release_json_digest_for_asset() {
    printf '%s\n' "${_DIGEST}"
    return 0
  }
  export -f _github__release_json_digest_for_asset
}

# --- Argument validation ---

@test "github__install_release: fails when --repo is missing" {
  run github__install_release --tag "v1.0" --binary-dest "/tmp" --asset "b"
  assert_failure
  assert_output --partial "required"
}

@test "github__install_release: fails when --tag is missing" {
  run github__install_release --repo "o/r" --binary-dest "/tmp" --asset "b"
  assert_failure
  assert_output --partial "required"
}

@test "github__install_release: without --binary-dest and --installer-dir succeeds and prints asset dir" {
  # Omitting both is valid: uri__fetch_asset prints the work_dir/asset directory path on stdout.
  _stub_install_release_common
  run --separate-stderr github__install_release \
    --repo "o/r" --tag "v1.0" --asset "mybin" --sha256 none
  assert_success
  # Stdout is the asset/ directory inside the tmpdir work tree
  assert_output --partial "/asset"
}

@test "github__install_release: --installer-dir without --binary-dest succeeds and prints asset dir" {
  _stub_install_release_common
  local _idir="${BATS_TEST_TMPDIR}/idir"
  mkdir -p "$_idir"
  run --separate-stderr github__install_release \
    --repo "o/r" --tag "v1.0" --asset "mybin" --sha256 none \
    --installer-dir "$_idir"
  assert_success
  # Stdout is the asset/ subdirectory of the installer dir
  assert_output "${_idir}/asset"
  # Downloaded asset must be present in installer_dir/asset/
  [[ -f "${_idir}/asset/mybin" ]]
}

@test "github__install_release: --installer-dir only mode verifies JSON digest" {
  local _digest="deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  _stub_install_release_common
  _DIGEST="$_digest"
  export _DIGEST _VERIFY_SHA_CALLS
  _stub_github_json_digest_from_uri

  local _idir="${BATS_TEST_TMPDIR}/idir"
  mkdir -p "$_idir"
  run --separate-stderr github__install_release \
    --repo "o/r" --tag "v1.0" --asset "mybin" \
    --installer-dir "$_idir"
  assert_success
  # JSON digest must have been verified
  run grep -qF "$_digest" "$_VERIFY_SHA_CALLS"
  assert_success
  # Asset file must be present in installer_dir/asset/
  [[ -f "${_idir}/asset/mybin" ]]
}

@test "github__install_release: --asset and --asset-regex are mutually exclusive" {
  run github__install_release --repo "o/r" --tag "v1.0" --binary-dest "/tmp" \
    --asset "a.tar.gz" --asset-regex "linux"
  assert_failure
  assert_output --partial "mutually exclusive"
}

@test "github__install_release: mismatched multi-binary count fails" {
  run github__install_release --repo "o/r" --tag "v1.0" \
    --binary-src a --binary-src b \
    --binary-dest "/tmp/d1" --binary-dest "/tmp/d2" --binary-dest "/tmp/d3" \
    --asset "mybin"
  assert_failure
  assert_output --partial "2 --binary-src"
}

@test "github__install_release: N binary-src + 1 binary-dest fan-out installs all binaries" {
  _stub_install_release_common
  file__detect_type() { printf 'gzip'; }
  export -f file__detect_type
  file__extract_archive() {
    mkdir -p "$2"
    touch "$2/tool-a" "$2/tool-b"
    chmod +x "$2/tool-a" "$2/tool-b"
    return 0
  }
  export -f file__extract_archive

  local _dest="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$_dest"
  run github__install_release \
    --repo "o/r" --tag "v1.0" \
    --binary-src tool-a --binary-src tool-b --binary-dest "${_dest}/" \
    --asset "tools.tar.gz" --sha256 none
  assert_success
  # Both binaries must appear in stdout
  assert_output --partial "tool-a"
  assert_output --partial "tool-b"
  # Both binaries must be installed to the shared dest directory
  [[ -f "${_dest}/tool-a" ]]
  [[ -f "${_dest}/tool-b" ]]
}

# --- SHA-256 spec validation ---

@test "github__install_release: --sha256 none with --sidecar is a validation error" {
  run github__install_release --repo "o/r" --tag "v1.0" --binary-dest "/tmp" \
    --asset "a" --sha256 none --sidecar "https://dl.invalid/sums.txt"
  assert_failure
  assert_output --partial "cannot be combined with --sidecar"
}

@test "github__install_release: --sha256 unknown token fails" {
  run github__install_release --repo "o/r" --tag "v1.0" --binary-dest "/tmp" \
    --asset "a" --sha256 "bogusmode"
  assert_failure
  assert_output --partial "--sha256 accepts"
}

@test "github__install_release: --sha256 hex of wrong length fails" {
  _stub_install_release_common
  run github__install_release --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --asset "a" --sha256 "abcdef"
  assert_failure
  assert_output --partial "64-char"
}

# --- SHA-256: JSON digest (default behavior) ---

@test "github__install_release: JSON digest verified by default (no --sha256 flag)" {
  local _digest="abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
  _stub_install_release_common
  _DIGEST="$_digest"
  export _DIGEST
  _stub_github_json_digest_from_uri

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin"
  assert_success
  run grep -qF "$_digest" "$_VERIFY_SHA_CALLS"
  assert_success
}

@test "github__install_release: JSON digest absent warns and continues" {
  _stub_install_release_common

  run --separate-stderr github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin"
  assert_success
  [[ ! -f "$_VERIFY_SHA_CALLS" ]]
  assert_stderr --partial "skipping JSON SHA-256"
}

# --- SHA-256: retry on JSON digest mismatch ---

@test "github__install_release: JSON digest mismatch retries — 2 corrupt downloads then success" {
  local _digest="1111111111111111111111111111111111111111111111111111111111111111"
  _stub_install_release_common
  _DIGEST="$_digest"
  _SHA_FAIL_UNTIL="${BATS_TEST_TMPDIR}/_fail_until"
  printf '2\n' > "$_SHA_FAIL_UNTIL"
  export _DIGEST _SHA_FAIL_UNTIL _VERIFY_SHA_CALLS
  _stub_github_json_digest_from_uri
  verify__sha() {
    printf '%s %s\n' "$1" "$2" >> "$_VERIFY_SHA_CALLS"
    local _c
    _c="$(wc -l < "$_VERIFY_SHA_CALLS")"
    _c="${_c// /}"
    local _fail
    _fail="$(cat "$_SHA_FAIL_UNTIL" 2> /dev/null || printf '0')"
    [ "$_c" -le "$_fail" ] && return 1
    return 0
  }
  export -f verify__sha

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin"
  assert_success
  local _call_count
  _call_count="$(wc -l < "$_VERIFY_SHA_CALLS")"
  _call_count="${_call_count// /}"
  [ "$_call_count" -eq 3 ]
}

@test "github__install_release: JSON digest mismatch hard-fails after 3 attempts" {
  local _digest="2222222222222222222222222222222222222222222222222222222222222222"
  _stub_install_release_common
  _DIGEST="$_digest"
  _ASSET_DL_COUNT="${BATS_TEST_TMPDIR}/_dl_count"
  export _DIGEST _ASSET_DL_COUNT
  _stub_github_json_digest_from_uri
  net__fetch_url_file() {
    case "$1" in
      *.sha256 | */SHA256SUMS | */sha256sum.txt) return 1 ;;
      */api.github.com/*)
        printf '{}' > "$2"
        return 0
        ;;
    esac
    printf 'x\n' >> "$_ASSET_DL_COUNT"
    printf '\x7fELF\x00\x00' > "$2"
    return 0
  }
  export -f net__fetch_url_file
  verify__sha() { return 1; }
  export -f verify__sha

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin"
  assert_failure
  assert_output --partial "after 3 attempt"
  # Must have attempted exactly 3 downloads (each failed sha256 triggers a re-download)
  local _dl_count
  _dl_count="$(wc -l < "$_ASSET_DL_COUNT")"
  _dl_count="${_dl_count// /}"
  [ "$_dl_count" -eq 3 ]
}

# --- SHA-256: sidecar (explicit --sidecar) ---

@test "github__install_release: --sidecar alone triggers sidecar verification" {
  _stub_install_release_common
  local _hash="aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd"
  local _sidecar_url="https://dl.invalid/sums.txt"
  _SIDECAR_URL="$_sidecar_url"
  _SIDECAR_HASH="$_hash"
  export _SIDECAR_URL _SIDECAR_HASH
  net__fetch_url_file() {
    if [ "$1" = "$_SIDECAR_URL" ]; then
      printf '%s  mybin\n' "$_SIDECAR_HASH" > "$2"
    else
      printf '\x7fELF\x00\x00' > "$2"
    fi
    return 0
  }
  export -f net__fetch_url_file

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin" --sidecar "$_sidecar_url"
  assert_success
  run grep -qF "$_hash" "$_VERIFY_SHA_CALLS"
  assert_success
}

@test "github__install_release: JSON digest and explicit sidecar both verified" {
  local _json_hash="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa00"
  local _sidecar_hash="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb00"
  local _sidecar_url="https://dl.invalid/sums.txt"
  _stub_install_release_common
  _JSON_HASH="$_json_hash"
  _SIDECAR_URL="$_sidecar_url"
  _SIDECAR_HASH="$_sidecar_hash"
  export _JSON_HASH _SIDECAR_URL _SIDECAR_HASH
  _stub_github_json_digest_from_uri
  net__fetch_url_file() {
    if [ "$1" = "$_SIDECAR_URL" ]; then
      printf '%s  mybin\n' "$_SIDECAR_HASH" > "$2"
    else
      printf '\x7fELF\x00\x00' > "$2"
    fi
    return 0
  }
  export -f net__fetch_url_file

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin" --sidecar "$_sidecar_url"
  assert_success
  run grep -qF "$_json_hash" "$_VERIFY_SHA_CALLS"
  assert_success
  run grep -qF "$_sidecar_hash" "$_VERIFY_SHA_CALLS"
  assert_success
}

@test "github__install_release: sidecar parses multi-entry sha256sum format" {
  _stub_install_release_common
  local _hash="deadbeef01234567890123456789012345678901234567890123456789abcdef"
  local _sidecar_url="https://dl.invalid/sums.txt"
  _SIDECAR_URL="$_sidecar_url"
  _SIDECAR_HASH="$_hash"
  export _SIDECAR_URL _SIDECAR_HASH
  net__fetch_url_file() {
    if [ "$1" = "$_SIDECAR_URL" ]; then
      printf '%s  %s\n' "$_SIDECAR_HASH" "mybin" > "$2"
      printf 'otherhash  otherfile\n' >> "$2"
    else
      printf '\x7fELF\x00\x00' > "$2"
    fi
    return 0
  }
  export -f net__fetch_url_file

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin" --sidecar "$_sidecar_url"
  assert_success
  run grep -qF "$_hash" "$_VERIFY_SHA_CALLS"
  assert_success
}

@test "github__install_release: sidecar parses raw single-hash file" {
  _stub_install_release_common
  local _hash="1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
  local _sidecar_url="https://dl.invalid/tool.sha256"
  _SIDECAR_URL="$_sidecar_url"
  _SIDECAR_HASH="$_hash"
  export _SIDECAR_URL _SIDECAR_HASH
  net__fetch_url_file() {
    if [ "$1" = "$_SIDECAR_URL" ]; then
      printf '%s\n' "$_SIDECAR_HASH" > "$2"
    else
      printf '\x7fELF\x00\x00' > "$2"
    fi
    return 0
  }
  export -f net__fetch_url_file

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin" --sidecar "$_sidecar_url"
  assert_success
  run grep -qF "$_hash" "$_VERIFY_SHA_CALLS"
  assert_success
}

@test "github__install_release: sidecar double-print regression — single-line sha256sum file" {
  # Regression: single-line 'hash  filename' sidecars (fzf, pixi) previously triggered an
  # awk double-print — exit in the matched rule + END{NR==1} both printed $1, producing a
  # doubled hash that failed verify__sha's strict string comparison.
  _stub_install_release_common
  local _hash="fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
  local _sidecar_url="https://dl.invalid/mybin.sha256"
  _SIDECAR_URL="$_sidecar_url"
  _SIDECAR_HASH="$_hash"
  export _SIDECAR_URL _SIDECAR_HASH
  net__fetch_url_file() {
    if [ "$1" = "$_SIDECAR_URL" ]; then
      printf '%s  %s\n' "$_SIDECAR_HASH" "mybin" > "$2"
    else
      printf '\x7fELF\x00\x00' > "$2"
    fi
    return 0
  }
  export -f net__fetch_url_file

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin" --sidecar "$_sidecar_url"
  assert_success
  # verify__sha must be called exactly once with the correct (undoubled) hash
  run grep -cF "$_hash" "$_VERIFY_SHA_CALLS"
  assert_output "1"
}

@test "github__install_release: explicit --sidecar hard-fails when unreachable" {
  _stub_install_release_common
  local _sidecar_url="https://dl.invalid/sums.txt"
  export _sidecar_url
  net__fetch_url_file() {
    if [ "$1" = "$_sidecar_url" ]; then return 1; fi
    printf '\x7fELF\x00\x00' > "$2"
    return 0
  }
  export -f net__fetch_url_file

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin" --sidecar "$_sidecar_url"
  assert_failure
  assert_output --partial "failed to download sidecar"
}

@test "github__install_release: explicit --sidecar hard-fails when asset not found in multi-entry file" {
  _stub_install_release_common
  local _sidecar_url="https://dl.invalid/sums.txt"
  export _sidecar_url
  net__fetch_url_file() {
    if [ "$1" = "$_sidecar_url" ]; then
      # Multi-entry file that does NOT contain an entry for "mybin"
      printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  othertool\n' > "$2"
      printf 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  anothertool\n' >> "$2"
      return 0
    fi
    printf '\x7fELF\x00\x00' > "$2"
    return 0
  }
  export -f net__fetch_url_file

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin" --sidecar "$_sidecar_url"
  assert_failure
  assert_output --partial "could not extract a valid SHA-256 hash"
}

@test "github__install_release: explicit --sidecar wrong-asset single-entry file hard-fails (not NR==1 false-positive)" {
  _stub_install_release_common
  local _sidecar_url="https://dl.invalid/othertool.sha256"
  export _sidecar_url
  net__fetch_url_file() {
    if [ "$1" = "$_sidecar_url" ]; then
      # Single-line sha256sum-style entry for a different file — must NOT match via NR==1 fallback
      printf 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc  othertool\n' > "$2"
      return 0
    fi
    printf '\x7fELF\x00\x00' > "$2"
    return 0
  }
  export -f net__fetch_url_file

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin" --sidecar "$_sidecar_url"
  assert_failure
  assert_output --partial "could not extract a valid SHA-256 hash"
}

@test "github__install_release: explicit --sidecar with ./ path prefix in filename field succeeds" {
  # Miniforge-style sidecar: hash followed by './filename' — the ./ prefix must
  # be stripped before comparing against the asset name.
  _stub_install_release_common
  local _hash="dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
  local _sidecar_url="https://dl.invalid/mybin.sha256"
  export _hash _sidecar_url
  net__fetch_url_file() {
    if [ "$1" = "$_sidecar_url" ]; then
      printf '%s  ./mybin\n' "$_hash" > "$2"
      return 0
    fi
    printf '\x7fELF\x00\x00' > "$2"
    return 0
  }
  export -f net__fetch_url_file
  verify__sha256() { return 0; }
  export -f verify__sha256
  file__detect_type() { printf 'elf'; }
  export -f file__detect_type

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin" --sidecar "$_sidecar_url"
  assert_success
}

# --- SHA-256: sidecar auto-detection ---

@test "github__install_release: auto-detect finds {asset_url}.sha256" {
  _stub_install_release_common
  local _hash="cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  _SIDECAR_HASH="$_hash"
  export _SIDECAR_HASH
  net__fetch_url_file() {
    case "$1" in
      *.sha256)
        printf '%s  mybin\n' "$_SIDECAR_HASH" > "$2"
        return 0
        ;;
      */SHA256SUMS | */sha256sum.txt)
        return 1
        ;;
      *)
        printf '\x7fELF\x00\x00' > "$2"
        return 0
        ;;
    esac
  }
  export -f net__fetch_url_file

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin"
  assert_success
  run grep -qF "$_hash" "$_VERIFY_SHA_CALLS"
  assert_success
}

@test "github__install_release: auto-detect finds SHA256SUMS when .sha256 fails" {
  _stub_install_release_common
  local _hash="dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
  _SIDECAR_HASH="$_hash"
  export _SIDECAR_HASH
  net__fetch_url_file() {
    case "$1" in
      *.sha256)
        return 1
        ;;
      */SHA256SUMS)
        printf '%s  mybin\n' "$_SIDECAR_HASH" > "$2"
        return 0
        ;;
      */sha256sum.txt)
        return 1
        ;;
      *)
        printf '\x7fELF\x00\x00' > "$2"
        return 0
        ;;
    esac
  }
  export -f net__fetch_url_file

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin"
  assert_success
  run grep -qF "$_hash" "$_VERIFY_SHA_CALLS"
  assert_success
}

@test "github__install_release: auto-detect finds sha256sum.txt when first two fail" {
  _stub_install_release_common
  local _hash="eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
  _SIDECAR_HASH="$_hash"
  export _SIDECAR_HASH
  net__fetch_url_file() {
    case "$1" in
      *.sha256 | */SHA256SUMS)
        return 1
        ;;
      */sha256sum.txt)
        printf '%s  mybin\n' "$_SIDECAR_HASH" > "$2"
        return 0
        ;;
      *)
        printf '\x7fELF\x00\x00' > "$2"
        return 0
        ;;
    esac
  }
  export -f net__fetch_url_file

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin"
  assert_success
  run grep -qF "$_hash" "$_VERIFY_SHA_CALLS"
  assert_success
}

@test "github__install_release: auto-detect all candidates miss — warns and continues" {
  _stub_install_release_common
  # Default stub already fails all three sidecar candidate patterns.

  run --separate-stderr github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin"
  assert_success
  [[ ! -f "$_VERIFY_SHA_CALLS" ]]
  assert_stderr --partial "no sidecar found"
}

@test "github__install_release: auto-detect candidate has no entry for asset — tries next" {
  _stub_install_release_common
  local _hash="ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  _SIDECAR_HASH="$_hash"
  export _SIDECAR_HASH
  net__fetch_url_file() {
    case "$1" in
      *.sha256)
        # Multi-line file with no entry for mybin — awk NR==1 fallback won't fire.
        printf 'aaaa0000aaaa0000aaaa0000aaaa0000aaaa0000aaaa0000aaaa0000aaaa0000  otherfile1\n' > "$2"
        printf 'bbbb1111bbbb1111bbbb1111bbbb1111bbbb1111bbbb1111bbbb1111bbbb1111  otherfile2\n' >> "$2"
        return 0
        ;;
      */SHA256SUMS)
        printf '%s  mybin\n' "$_SIDECAR_HASH" > "$2"
        return 0
        ;;
      */sha256sum.txt)
        return 1
        ;;
      *)
        printf '\x7fELF\x00\x00' > "$2"
        return 0
        ;;
    esac
  }
  export -f net__fetch_url_file

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin"
  assert_success
  run grep -qF "$_hash" "$_VERIFY_SHA_CALLS"
  assert_success
}

# --- SHA-256: explicit hex ---

@test "github__install_release: --sha256 <hex> calls verify__sha with exact hash and skips JSON API" {
  local _hex="cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  _stub_install_release_common
  _API_GET_CALLS="${BATS_TEST_TMPDIR}/_api_get_calls"
  export _API_GET_CALLS
  _github__api_get() {
    printf '%s\n' "$1" >> "$_API_GET_CALLS"
    return 0
  }
  export -f _github__api_get

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin" --sha256 "$_hex"
  assert_success
  run grep -qF "$_hex" "$_VERIFY_SHA_CALLS"
  assert_success
  [[ ! -f "$_API_GET_CALLS" ]]
}

# --- SHA-256: none ---

@test "github__install_release: --sha256 none skips verification and warns" {
  _stub_install_release_common

  run --separate-stderr github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin" --sha256 none
  assert_success
  [[ ! -f "$_VERIFY_SHA_CALLS" ]]
  assert_stderr --partial "skipped"
}

# --- GPG verification ---

@test "github__install_release: --gpg-key triggers verify__gpg_detached with default .asc URL" {
  _stub_install_release_common
  local _key_url="https://dl.invalid/release.key"
  _DOWNLOAD_URLS="${BATS_TEST_TMPDIR}/_dl_urls"
  _KEY_URL="$_key_url"
  export _DOWNLOAD_URLS _KEY_URL
  net__fetch_url_file() {
    printf '%s\n' "$1" >> "$_DOWNLOAD_URLS"
    printf 'fake' > "$2"
    return 0
  }
  export -f net__fetch_url_file

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin" --sha256 none --gpg-key "$_key_url"
  assert_success
  run grep -qF "mybin.asc" "$_DOWNLOAD_URLS"
  assert_success
  [[ -s "$_VERIFY_GPG_CALLS" ]]
}

@test "github__install_release: --gpg-sig overrides default .asc URL" {
  _stub_install_release_common
  local _key_url="https://dl.invalid/release.key"
  local _sig_url="https://dl.invalid/custom-sig.asc"
  _DOWNLOAD_URLS="${BATS_TEST_TMPDIR}/_dl_urls"
  _KEY_URL="$_key_url"
  _SIG_URL="$_sig_url"
  export _DOWNLOAD_URLS _KEY_URL _SIG_URL
  net__fetch_url_file() {
    printf '%s\n' "$1" >> "$_DOWNLOAD_URLS"
    printf 'fake' > "$2"
    return 0
  }
  export -f net__fetch_url_file

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin" --sha256 none \
    --gpg-key "$_key_url" --gpg-sig "$_sig_url"
  assert_success
  run grep -qF "$_sig_url" "$_DOWNLOAD_URLS"
  assert_success
  run grep -qF "mybin.asc" "$_DOWNLOAD_URLS"
  assert_failure
}

# --- File type detection and extraction ---

@test "github__install_release: ELF asset used directly without extraction" {
  _stub_install_release_common
  _COPY_SRC="${BATS_TEST_TMPDIR}/_copy_src"
  export _COPY_SRC
  install__copy_bin() {
    printf '%s\n' "$1" > "$_COPY_SRC"
    touch "$2"
    chmod +x "$2"
    return 0
  }
  export -f install__copy_bin

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin"
  assert_success
  # install__copy_bin should have been called with the archive path directly.
  run grep -q "mybin" "$_COPY_SRC"
  assert_success
}

@test "github__install_release: ELF direct binary renamed via exact --binary-dest (e.g. jq-linux-amd64 → jq)" {
  # Exact dest path (no trailing slash) renames the binary at install time.
  _stub_install_release_common
  _COPY_DEST="${BATS_TEST_TMPDIR}/_copy_dest"
  export _COPY_DEST
  install__copy_bin() {
    printf '%s\n' "$2" > "$_COPY_DEST"
    touch "$2"
    chmod +x "$2"
    return 0
  }
  export -f install__copy_bin

  run --separate-stderr github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/jq" \
    --asset "jq-linux-amd64" --sha256 none
  assert_success
  # Destination must be the exact path (jq), not jq-linux-amd64
  run grep -qF "/jq" "$_COPY_DEST"
  assert_success
  run grep -qF "jq-linux-amd64" "$_COPY_DEST"
  assert_failure
}

@test "github__install_release: gzip asset is extracted and binary found in tree" {
  _stub_install_release_common
  file__detect_type() { printf 'gzip'; }
  export -f file__detect_type
  _BIN_NAME="mybin"
  export _BIN_NAME
  file__extract_archive() {
    mkdir -p "$2"
    touch "$2/${_BIN_NAME}"
    chmod +x "$2/${_BIN_NAME}"
    return 0
  }
  export -f file__extract_archive

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin.tar.gz"
  assert_success
}

@test "github__install_release: strict suffix-path matching rejects non-matching suffix" {
  _stub_install_release_common
  file__detect_type() { printf 'gzip'; }
  export -f file__detect_type
  file__extract_archive() {
    mkdir -p "$2/subdir/nested"
    touch "$2/subdir/nested/mybin"
    chmod +x "$2/subdir/nested/mybin"
    return 0
  }
  export -f file__extract_archive

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src "bin/mybin" --asset "mybin.tar.gz"
  assert_failure # bin/mybin not at that path in extracted tree
}

@test "github__install_release: suffix-path matching finds bin/gh inside archive" {
  _stub_install_release_common
  file__detect_type() { printf 'gzip'; }
  export -f file__detect_type
  file__extract_archive() {
    mkdir -p "$2/gh_2.0/bin"
    touch "$2/gh_2.0/bin/gh"
    chmod +x "$2/gh_2.0/bin/gh"
    return 0
  }
  export -f file__extract_archive

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src "bin/gh" --asset "gh.tar.gz"
  assert_success
}

@test "github__install_release: ambiguous --binary-src fails when multiple archive entries match" {
  _stub_install_release_common
  file__detect_type() { printf 'gzip'; }
  export -f file__detect_type
  file__extract_archive() {
    mkdir -p "$2/pkg/bin" "$2/pkg/extra"
    touch "$2/pkg/bin/mytool"
    chmod +x "$2/pkg/bin/mytool"
    touch "$2/pkg/extra/mytool"
    chmod +x "$2/pkg/extra/mytool"
    return 0
  }
  export -f file__extract_archive

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mytool --asset "pkg.tar.gz"
  assert_failure
  assert_output --partial "ambiguous"
  assert_output --partial "mytool"
}

@test "github__install_release: auto-discovers all executables when no --binary-src" {
  _stub_install_release_common
  file__detect_type() { printf 'gzip'; }
  export -f file__detect_type
  file__extract_archive() {
    mkdir -p "$2/tool-1.0"
    touch "$2/tool-1.0/mytool"
    chmod +x "$2/tool-1.0/mytool"
    touch "$2/tool-1.0/README"
    return 0
  }
  export -f file__extract_archive

  run --separate-stderr github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --asset "tool.tar.gz" --sha256 none
  assert_success
  # Stdout should contain the installed binary path
  assert_output --partial "mytool"
  refute_output --partial "README"
}

@test "github__install_release: auto-discover fallback — marks non-executable files and installs them" {
  # When no files have the executable bit set, the fallback chmod+x path fires.
  # All regular files should be collected; symlinks and directories excluded.
  _stub_install_release_common
  file__detect_type() { printf 'gzip'; }
  export -f file__detect_type
  file__extract_archive() {
    mkdir -p "$2/pkg"
    # Intentionally NOT chmod +x — triggers the fallback path
    touch "$2/pkg/mytool"
    touch "$2/pkg/README"
    return 0
  }
  export -f file__extract_archive

  run --separate-stderr github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --asset "pkg.tar.gz" --sha256 none
  assert_success
  # Both files are installed via the fallback (no executable filter)
  assert_output --partial "mytool"
  assert_output --partial "README"
}

# --- installer-dir ---

@test "github__install_release: --installer-dir uses that directory for download" {
  _stub_install_release_common
  local _idir="${BATS_TEST_TMPDIR}/idir"
  _DOWNLOAD_PATHS="${BATS_TEST_TMPDIR}/_dl_paths"
  export _DOWNLOAD_PATHS
  net__fetch_url_file() {
    printf '%s\n' "$2" >> "$_DOWNLOAD_PATHS"
    printf '\x7fELF\x00\x00' > "$2"
    return 0
  }
  export -f net__fetch_url_file

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin" --sha256 none \
    --installer-dir "$_idir"
  assert_success
  run grep -qF "$_idir" "$_DOWNLOAD_PATHS"
  assert_success
}

# --- Direct binary without --binary-src ---

@test "github__install_release: ELF asset without --binary-src installs using asset filename" {
  _stub_install_release_common
  _COPY_DEST="${BATS_TEST_TMPDIR}/_copy_dest"
  export _COPY_DEST
  install__copy_bin() {
    printf '%s\n' "$2" > "$_COPY_DEST"
    touch "$2"
    chmod +x "$2"
    return 0
  }
  export -f install__copy_bin

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --asset "mybin" --sha256 none
  assert_success
  # Installed path must use the asset name, not some other basename
  run grep -qF "/mybin" "$_COPY_DEST"
  assert_success
}

# --- --sha256 none skips JSON fetch ---

@test "github__install_release: --sha256 none does not call GitHub API for JSON digest" {
  _stub_install_release_common
  _API_GET_CALLS="${BATS_TEST_TMPDIR}/_api_get_calls"
  export _API_GET_CALLS
  _github__api_get() {
    printf '%s\n' "$1" >> "$_API_GET_CALLS"
    return 0
  }
  export -f _github__api_get

  run --separate-stderr github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin" --sha256 none
  assert_success
  [[ ! -f "$_API_GET_CALLS" ]]
}

# --- N+N paired binary-src / binary-dest ---

@test "github__install_release: N+N paired binary-src/dest installs each src to its own dest" {
  _stub_install_release_common
  file__detect_type() { printf 'gzip'; }
  export -f file__detect_type
  file__extract_archive() {
    mkdir -p "$2"
    touch "$2/tool-a" "$2/tool-b"
    chmod +x "$2/tool-a" "$2/tool-b"
    return 0
  }
  export -f file__extract_archive

  local _dest1="${BATS_TEST_TMPDIR}/bin1"
  local _dest2="${BATS_TEST_TMPDIR}/bin2"
  mkdir -p "$_dest1" "$_dest2"
  run github__install_release \
    --repo "o/r" --tag "v1.0" \
    --binary-src tool-a --binary-dest "${_dest1}/" \
    --binary-src tool-b --binary-dest "${_dest2}/" \
    --asset "tools.tar.gz" --sha256 none
  assert_success
  # tool-a must go to _dest1, tool-b to _dest2 (not cross-installed)
  [[ -f "${_dest1}/tool-a" ]]
  [[ -f "${_dest2}/tool-b" ]]
  [[ ! -f "${_dest1}/tool-b" ]]
  [[ ! -f "${_dest2}/tool-a" ]]
}

# --- Retry re-downloads the asset each attempt ---

@test "github__install_release: retry loop re-downloads the asset on each failed JSON digest attempt" {
  local _digest="3333333333333333333333333333333333333333333333333333333333333333"
  _stub_install_release_common
  _DIGEST="$_digest"
  _ASSET_DL_COUNT="${BATS_TEST_TMPDIR}/_asset_dl_count"
  export _DIGEST _ASSET_DL_COUNT _VERIFY_SHA_CALLS
  _stub_github_json_digest_from_uri
  net__fetch_url_file() {
    # Count downloads of the asset URL (not sidecar candidates or API calls)
    case "$1" in
      *.sha256 | */SHA256SUMS | */sha256sum.txt) return 1 ;;
      */api.github.com/*)
        printf '{}' > "$2"
        return 0
        ;;
    esac
    printf 'x\n' >> "$_ASSET_DL_COUNT"
    printf '\x7fELF\x00\x00' > "$2"
    return 0
  }
  export -f net__fetch_url_file
  verify__sha() {
    printf '%s %s\n' "$1" "$2" >> "$_VERIFY_SHA_CALLS"
    return 1 # always fail → triggers retry
  }
  export -f verify__sha

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin"
  assert_failure
  # Must have attempted exactly 3 downloads
  local _dl_count
  _dl_count="$(wc -l < "$_ASSET_DL_COUNT")"
  _dl_count="${_dl_count// /}"
  [ "$_dl_count" -eq 3 ]
}

# --- Asset selection ---

@test "github__install_release: omitting --asset calls github__pick_release_asset" {
  _stub_install_release_common
  _PICK_CALLED="${BATS_TEST_TMPDIR}/_pick_called"
  export _PICK_CALLED
  github__pick_release_asset() {
    touch "$_PICK_CALLED"
    printf 'https://github.com/o/r/releases/download/v1.0/mybin\n'
    return 0
  }
  export -f github__pick_release_asset

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/"
  assert_success
  [[ -f "$_PICK_CALLED" ]]
}

@test "github__install_release: --asset-regex passed to github__pick_release_asset" {
  _stub_install_release_common
  _PICK_ARGS="${BATS_TEST_TMPDIR}/_pick_args"
  export _PICK_ARGS
  github__pick_release_asset() {
    printf '%s\n' "$@" > "$_PICK_ARGS"
    printf 'https://github.com/o/r/releases/download/v1.0/mybin\n'
    return 0
  }
  export -f github__pick_release_asset

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --asset-regex "linux-amd64"
  assert_success
  run grep -q "\-\-asset-regex" "$_PICK_ARGS"
  assert_success
  run grep -q "linux-amd64" "$_PICK_ARGS"
  assert_success
}

# --- Misc ---

@test "github__install_release: --owner-group triggers install__track_internal_path" {
  _stub_install_release_common

  run github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin" --owner-group "mygroup"
  assert_success
  run grep -q "mygroup" "$_TRACKED_PATHS"
  assert_success
}

@test "github__install_release: stdout is the installed binary path" {
  _stub_install_release_common

  run --separate-stderr github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin" --sha256 none
  assert_success
  assert_output "${BATS_TEST_TMPDIR}/mybin"
}

# --- Auth forwarding to sidecar probe ---

@test "github__install_release: --header is forwarded to auto-detect sidecar probe" {
  _stub_install_release_common
  local _hash="aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111"
  _SIDECAR_HASH="$_hash"
  _PROBE_ARGS="${BATS_TEST_TMPDIR}/_probe_args"
  export _SIDECAR_HASH _PROBE_ARGS
  net__fetch_url_file() {
    case "$1" in
      *.sha256)
        printf '%s\n' "$@" >> "$_PROBE_ARGS"
        printf '%s  mybin\n' "$_SIDECAR_HASH" > "$2"
        return 0
        ;;
      */SHA256SUMS | */sha256sum.txt)
        return 1
        ;;
      *)
        printf '\x7fELF\x00\x00' > "$2"
        return 0
        ;;
    esac
  }
  export -f net__fetch_url_file

  run --separate-stderr github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin" \
    --header "Authorization: Bearer mytoken"
  assert_success
  run grep -qF "Authorization: Bearer mytoken" "$_PROBE_ARGS"
  assert_success
}

@test "github__install_release: --netrc-file is forwarded to auto-detect sidecar probe" {
  _stub_install_release_common
  local _hash="bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222"
  _SIDECAR_HASH="$_hash"
  _PROBE_ARGS="${BATS_TEST_TMPDIR}/_probe_args"
  local _netrc="${BATS_TEST_TMPDIR}/.netrc"
  printf 'machine github.com login user password pass\n' > "$_netrc"
  export _SIDECAR_HASH _PROBE_ARGS _netrc
  net__fetch_url_file() {
    case "$1" in
      *.sha256)
        printf '%s\n' "$@" >> "$_PROBE_ARGS"
        printf '%s  mybin\n' "$_SIDECAR_HASH" > "$2"
        return 0
        ;;
      */SHA256SUMS | */sha256sum.txt)
        return 1
        ;;
      *)
        printf '\x7fELF\x00\x00' > "$2"
        return 0
        ;;
    esac
  }
  export -f net__fetch_url_file

  run --separate-stderr github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin" \
    --netrc-file "$_netrc"
  assert_success
  run grep -qF "$_netrc" "$_PROBE_ARGS"
  assert_success
}

# --- Auto-probed sidecar: probe selects candidate, transaction refetches ---

@test "github__install_release: auto-probed sidecar is refetched by the asset transaction (probe + authoritative fetch)" {
  _stub_install_release_common
  local _hash="cccc3333cccc3333cccc3333cccc3333cccc3333cccc3333cccc3333cccc3333"
  _SIDECAR_HASH="$_hash"
  _SC_FETCH_COUNT="${BATS_TEST_TMPDIR}/_sc_count"
  printf '0\n' > "$_SC_FETCH_COUNT"
  export _SIDECAR_HASH _SC_FETCH_COUNT
  net__fetch_url_file() {
    case "$1" in
      *.sha256)
        local _c
        _c="$(cat "$_SC_FETCH_COUNT")"
        printf '%d\n' $((_c + 1)) > "$_SC_FETCH_COUNT"
        printf '%s  mybin\n' "$_SIDECAR_HASH" > "$2"
        return 0
        ;;
      */SHA256SUMS | */sha256sum.txt)
        return 1
        ;;
      *)
        printf '\x7fELF\x00\x00' > "$2"
        return 0
        ;;
    esac
  }
  export -f net__fetch_url_file

  run --separate-stderr github__install_release \
    --repo "o/r" --tag "v1.0" --binary-dest "${BATS_TEST_TMPDIR}/" \
    --binary-src mybin --asset "mybin"
  assert_success
  # The probe passes the remote *.sha256 candidate URL (not a file:// reuse) to
  # uri__fetch_asset, which owns the authoritative download and refetches it as
  # part of the payload-integrity transaction: one probe fetch + one transaction
  # fetch = 2.
  run cat "$_SC_FETCH_COUNT"
  assert_output "2"
}

# ---------------------------------------------------------------------------
# github__fetch_release_asset_tarball
# ---------------------------------------------------------------------------

@test "github__fetch_release_asset_tarball: fails when required args are missing" {
  run github__fetch_release_asset_tarball "" "v1.0" "asset.tar.gz" "/tmp/out"
  assert_failure
  run github__fetch_release_asset_tarball "o/r" "" "asset.tar.gz" "/tmp/out"
  assert_failure
  run github__fetch_release_asset_tarball "o/r" "v1.0" "" "/tmp/out"
  assert_failure
  run github__fetch_release_asset_tarball "o/r" "v1.0" "asset.tar.gz" ""
  assert_failure
}

@test "github__fetch_release_asset_tarball: basic download with JSON digest verified" {
  local _digest="d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1"
  _DIGEST="$_digest"
  _VERIFY_SHA_CALLS="${BATS_TEST_TMPDIR}/_sha_calls"
  export _DIGEST _VERIFY_SHA_CALLS

  github__fetch_release_json() {
    local _d=""
    while [ $# -gt 0 ]; do
      case "$1" in --dest)
        shift
        _d="$1"
        shift
        ;;
      *) shift ;; esac
    done
    [ -n "$_d" ] && printf '{"assets":[{"name":"asset.tar.gz","digest":"sha256:%s"}]}\n' "$_DIGEST" > "$_d"
    return 0
  }
  export -f github__fetch_release_json

  github__release_json_digest_for_asset() {
    printf '%s\n' "$_DIGEST"
    return 0
  }
  export -f github__release_json_digest_for_asset

  net__fetch_url_file() {
    printf 'data' > "$2"
    return 0
  }
  export -f net__fetch_url_file

  verify__sha() {
    printf '%s %s\n' "$1" "$2" >> "$_VERIFY_SHA_CALLS"
    return 0
  }
  export -f verify__sha

  local _dest="${BATS_TEST_TMPDIR}/out.tar.gz"
  run github__fetch_release_asset_tarball "o/r" "v1.0" "asset.tar.gz" "$_dest"
  assert_success
  [[ -f "$_dest" ]]
  run grep -qF "$_digest" "$_VERIFY_SHA_CALLS"
  assert_success
}

@test "github__fetch_release_asset_tarball: missing digest warns and continues" {
  github__fetch_release_json() {
    local _d=""
    while [ $# -gt 0 ]; do
      case "$1" in --dest)
        shift
        _d="$1"
        shift
        ;;
      *) shift ;; esac
    done
    [ -n "$_d" ] && printf '{"assets":[]}\n' > "$_d"
    return 0
  }
  export -f github__fetch_release_json

  github__release_json_digest_for_asset() { return 1; }
  export -f github__release_json_digest_for_asset

  net__fetch_url_file() {
    printf 'data' > "$2"
    return 0
  }
  export -f net__fetch_url_file

  local _dest="${BATS_TEST_TMPDIR}/out.tar.gz"
  run --separate-stderr github__fetch_release_asset_tarball "o/r" "v1.0" "asset.tar.gz" "$_dest"
  assert_success
  [[ -f "$_dest" ]]
  assert_stderr --partial "skipping verification"
}

@test "github__fetch_release_asset_tarball: download failure returns non-zero" {
  github__fetch_release_json() {
    local _d=""
    while [ $# -gt 0 ]; do
      case "$1" in --dest)
        shift
        _d="$1"
        shift
        ;;
      *) shift ;; esac
    done
    [ -n "$_d" ] && printf '{"assets":[]}\n' > "$_d"
    return 0
  }
  export -f github__fetch_release_json

  github__release_json_digest_for_asset() { return 1; }
  export -f github__release_json_digest_for_asset

  net__fetch_url_file() { return 1; }
  export -f net__fetch_url_file

  run github__fetch_release_asset_tarball "o/r" "v1.0" "asset.tar.gz" "${BATS_TEST_TMPDIR}/out.tar.gz"
  assert_failure
}

@test "github__fetch_release_asset_tarball: sha256 mismatch returns non-zero" {
  local _digest="e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2"
  _DIGEST="$_digest"
  export _DIGEST

  github__fetch_release_json() {
    local _d=""
    while [ $# -gt 0 ]; do
      case "$1" in --dest)
        shift
        _d="$1"
        shift
        ;;
      *) shift ;; esac
    done
    [ -n "$_d" ] && printf '{"assets":[]}\n' > "$_d"
    return 0
  }
  export -f github__fetch_release_json

  _stub_github_release_json_digest_for_asset

  net__fetch_url_file() {
    printf 'data' > "$2"
    return 0
  }
  export -f net__fetch_url_file

  verify__sha() { return 1; }
  export -f verify__sha

  run github__fetch_release_asset_tarball "o/r" "v1.0" "asset.tar.gz" "${BATS_TEST_TMPDIR}/out.tar.gz"
  assert_failure
}

@test "github__fetch_release_asset_tarball: API failure falls back to download without digest" {
  github__fetch_release_json() { return 1; }
  export -f github__fetch_release_json

  github__release_json_digest_for_asset() { return 1; }
  export -f github__release_json_digest_for_asset

  net__fetch_url_file() {
    printf 'data' > "$2"
    return 0
  }
  export -f net__fetch_url_file

  local _dest="${BATS_TEST_TMPDIR}/out.tar.gz"
  run --separate-stderr github__fetch_release_asset_tarball "o/r" "v1.0" "asset.tar.gz" "$_dest"
  assert_success
  [[ -f "$_dest" ]]
}
