#!/usr/bin/env bats
# Unit tests for lib/github.sh
#
# Network calls are replaced with function stubs or fake curl binaries that
# return canned JSON fixtures.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  reload_lib net.sh
  reload_lib github.sh
  # Stub out the network-layer helpers so no real connections are made.
  net__ensure_fetch_tool() {
    _NET_FETCH_TOOL=curl
    _NET_CA_CERTS_OK=true
    return 0
  }
  net__ensure_ca_certs() {
    _NET_CA_CERTS_OK=true
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
  run github__latest_tag "owner/repo"
  assert_output "v1.2.3"
  assert_success
}

@test "github__latest_tag fails when fetch returns empty" {
  github__fetch_release_json() { return 1; }
  export -f github__fetch_release_json
  run github__latest_tag "owner/repo"
  assert_failure
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

# ---------------------------------------------------------------------------
# github__release_tags  (parsing logic via fake curl)
# ---------------------------------------------------------------------------

@test "github__release_tags parses multiple tags from JSON array" {
  # net__fetch_url_stdout is used inside; override it to return canned JSON.
  # Each object must be on its own line so that the grep/sed pipeline in
  # github__release_tags extracts one tag per line correctly.
  net__fetch_url_stdout() {
    printf '{"tag_name":"v3.0.0"}\n'
    printf '{"tag_name":"v2.1.0"}\n'
    printf '{"tag_name":"v2.0.0"}\n'
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
