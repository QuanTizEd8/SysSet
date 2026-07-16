#!/usr/bin/env bats
# shellcheck disable=SC2329  # stubs are invoked indirectly by __install_run_source__ via `run`
# Tests __install_run_source__'s primary→fallback source-asset fetch.
#
# When a feature configures source.fallback_asset_uri (only install-zsh today),
# a primary failure is an expected outcome (e.g. a 404 because a pinned older
# version has been archived to a different path — zsh's /pub → /pub/old). The
# template must bound the primary fetch's HTTP retry budget so it fails fast and
# the fallback runs promptly, instead of retrying the primary URL ~60x first.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/ensure_framework'
  install_test__ensure_framework

  INSTALLER_DIR="${BATS_TEST_TMPDIR}/installer"
  mkdir -p "${INSTALLER_DIR}/asset"

  _FETCH_LOG="${BATS_TEST_TMPDIR}/fetch.log"
  : > "$_FETCH_LOG"
  export _FETCH_LOG

  # A known-high global budget so the cap is observable and deterministic.
  export DEVFEATS_NET_FETCH_RETRIES=60

  # Neutralize the template machinery surrounding the fetch under test. The
  # missing extracted dir makes the function return after the fetch attempts,
  # which is fine — we assert on the recorded fetch calls, not the return.
  __run_feature_hook__() { :; }
  ctx__expand_pattern() { printf '%s' "$1"; }
  file__first_child_dir() { printf ''; }
  export -f __run_feature_hook__ ctx__expand_pattern file__first_child_dir

  # Record each fetch as "<retries-seen> <uri>".
  # shellcheck disable=SC2329
  uri__fetch_asset() {
    printf '%s %s\n' "${DEVFEATS_NET_FETCH_RETRIES:-60}" "$1" >> "$_FETCH_LOG"
    [[ "$1" == "${SOURCE_ASSET_URI:-}" ]] && return 1
    return 0
  }
  export -f uri__fetch_asset
}

@test "__install_run_source__ bounds the primary retry budget when a fallback exists" {
  SOURCE_ASSET_URI="https://primary.example/zsh-5.9.1.tar.xz"
  SOURCE_FALLBACK_ASSET_URI="https://fallback.example/old/zsh-5.9.1.tar.xz"
  export SOURCE_ASSET_URI SOURCE_FALLBACK_ASSET_URI

  run __install_run_source__

  local _primary _fallback
  _primary="$(grep -F "$SOURCE_ASSET_URI" "$_FETCH_LOG" | head -1 | awk '{print $1}')"
  _fallback="$(grep -F "$SOURCE_FALLBACK_ASSET_URI" "$_FETCH_LOG" | head -1 | awk '{print $1}')"

  # Primary fetch capped (fails fast); fallback tried with the full budget.
  assert [ -n "$_primary" ]
  assert [ "$_primary" -le 3 ]
  assert [ -n "$_fallback" ]
  assert [ "$_fallback" -eq 60 ]
}

@test "__install_run_source__ keeps the full budget when no fallback is configured" {
  SOURCE_ASSET_URI="https://primary.example/zsh-5.9.2.tar.xz"
  export SOURCE_ASSET_URI
  unset SOURCE_FALLBACK_ASSET_URI

  # No fallback: the primary must NOT fail (nowhere to fall back to).
  # shellcheck disable=SC2329
  uri__fetch_asset() {
    printf '%s %s\n' "${DEVFEATS_NET_FETCH_RETRIES:-60}" "$1" >> "$_FETCH_LOG"
    return 0
  }
  export -f uri__fetch_asset

  run __install_run_source__

  local _primary
  _primary="$(head -1 "$_FETCH_LOG" | awk '{print $1}')"
  assert [ "$_primary" -eq 60 ]
}
