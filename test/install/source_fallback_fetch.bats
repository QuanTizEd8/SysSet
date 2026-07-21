#!/usr/bin/env bats
# shellcheck disable=SC2329  # stubs are invoked indirectly by __install_run_source__ via `run`
# Tests __install_run_source__'s primary→fallback source-asset fetch.
#
# When a feature configures paired version/source fallbacks (only install-zsh
# today), the source fetch must retain the location that resolved the version.
# Current versions belong at the primary URL; archived versions belong at the
# fallback URL. A transient fetch failure must not permanently switch a newly
# resolved current version to an archive that cannot contain it.

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

@test "sidecar resolution records that an archived version used the fallback index" {
  VERSION_RESOLUTION=sidecar
  VERSION_URI="https://primary.example/"
  VERSION_FALLBACK_URI="https://fallback.example/old/"
  VERSION_PATTERN='zsh-[version].tar.xz'
  export VERSION_RESOLUTION VERSION_URI VERSION_FALLBACK_URI VERSION_PATTERN

  # shellcheck disable=SC2329
  ver__resolve_from_sidecar() {
    [[ "$1" == "$VERSION_FALLBACK_URI" ]] || return 1
    printf '5.9.1\n'
  }
  export -f ver__resolve_from_sidecar

  __feat_resolve_version_spec__ 5.9.1 --update-globals > /dev/null

  assert [ "$_FEAT_RESOLVE_VERSION_RESULT" = 5.9.1 ]
  assert [ "$_FEAT_VERSION_SOURCE_AFFINITY" = fallback ]
}

@test "sidecar resolution records that a current version used the primary index" {
  VERSION_RESOLUTION=sidecar
  VERSION_URI="https://primary.example/"
  VERSION_FALLBACK_URI="https://fallback.example/old/"
  VERSION_PATTERN='zsh-[version].tar.xz'
  export VERSION_RESOLUTION VERSION_URI VERSION_FALLBACK_URI VERSION_PATTERN

  # shellcheck disable=SC2329
  ver__resolve_from_sidecar() { printf '5.9.2\n'; }
  export -f ver__resolve_from_sidecar

  __feat_resolve_version_spec__ stable --update-globals > /dev/null

  assert [ "$_FEAT_RESOLVE_VERSION_RESULT" = 5.9.2 ]
  assert [ "$_FEAT_VERSION_SOURCE_AFFINITY" = primary ]
}

@test "__install_run_source__ gives a primary-resolved release the full primary retry budget" {
  SOURCE_ASSET_URI="https://primary.example/zsh-5.9.1.tar.xz"
  SOURCE_FALLBACK_ASSET_URI="https://fallback.example/old/zsh-5.9.1.tar.xz"
  _FEAT_VERSION_SOURCE_AFFINITY=primary
  export SOURCE_ASSET_URI SOURCE_FALLBACK_ASSET_URI _FEAT_VERSION_SOURCE_AFFINITY

  run __install_run_source__

  local _primary _fallback
  _primary="$(grep -F "$SOURCE_ASSET_URI" "$_FETCH_LOG" | head -1 | awk '{print $1}')"
  _fallback="$(grep -F "$SOURCE_FALLBACK_ASSET_URI" "$_FETCH_LOG" | head -1 | awk '{print $1}')"

  # A current release stays on the current-release URL for the full budget.
  assert [ -n "$_primary" ]
  assert [ "$_primary" -eq 60 ]
  assert [ -n "$_fallback" ]
  assert [ "$_fallback" -eq 60 ]
}

@test "__install_run_source__ fetches a fallback-resolved release from the archive first" {
  SOURCE_ASSET_URI="https://primary.example/zsh-5.9.1.tar.xz"
  SOURCE_FALLBACK_ASSET_URI="https://fallback.example/old/zsh-5.9.1.tar.xz"
  _FEAT_VERSION_SOURCE_AFFINITY=fallback
  export SOURCE_ASSET_URI SOURCE_FALLBACK_ASSET_URI _FEAT_VERSION_SOURCE_AFFINITY

  run __install_run_source__

  assert [ "$(wc -l < "$_FETCH_LOG")" -eq 1 ]
  assert grep -Fq "60 ${SOURCE_FALLBACK_ASSET_URI}" "$_FETCH_LOG"
}

@test "__install_run_source__ retains fail-fast probing when resolution has no location affinity" {
  SOURCE_ASSET_URI="https://primary.example/zsh-5.9.1.tar.xz"
  SOURCE_FALLBACK_ASSET_URI="https://fallback.example/old/zsh-5.9.1.tar.xz"
  unset _FEAT_VERSION_SOURCE_AFFINITY
  export SOURCE_ASSET_URI SOURCE_FALLBACK_ASSET_URI

  run __install_run_source__

  local _primary _fallback
  _primary="$(grep -F "$SOURCE_ASSET_URI" "$_FETCH_LOG" | head -1 | awk '{print $1}')"
  _fallback="$(grep -F "$SOURCE_FALLBACK_ASSET_URI" "$_FETCH_LOG" | head -1 | awk '{print $1}')"
  assert [ "$_primary" -le 3 ]
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
