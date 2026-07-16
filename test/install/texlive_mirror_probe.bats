#!/usr/bin/env bats
# Unit tests for install-texlive's historic-mirror probe policy.

bats_require_minimum_version 1.5.0

setup() {
  export INSTALL_TEST_FIXTURE=install-texlive
  load 'helpers/ensure_framework'
  install_test__ensure_framework

  _probe_log="${BATS_TEST_TMPDIR}/probe.log"
}

@test "_tl_probe_year_mirror uses the shared bounded probe and selects the first reachable mirror" {
  local _year=2024
  local _first="https://ftp.math.utah.edu/pub/tex/historic/systems/texlive/${_year}/tlnet-final"
  local _second="https://ftp.tu-chemnitz.de/pub/tug/historic/systems/texlive/${_year}/tlnet-final"
  # A transport must be present on PATH, or the first candidate's failed probe
  # would trip the no-transport fallback (return the first mirror) instead of
  # advancing to the reachable one — making this test host-dependent.
  local _transport_bin="${BATS_TEST_TMPDIR}/transport-bin"
  mkdir -p "$_transport_bin"
  printf '%s\n' '#!/bin/sh' 'exit 0' > "${_transport_bin}/curl"
  chmod +x "${_transport_bin}/curl"
  # shellcheck disable=SC2329
  net__probe_url() {
    printf '%s\n' "$*" >> "$_probe_log"
    [[ "$1" == "${_second}/install-tl-unx.tar.gz" ]]
  }

  PATH="${_transport_bin}:${PATH}" run _tl_probe_year_mirror "$_year"
  assert_success
  assert_output "$_second"
  assert [ "$(wc -l < "$_probe_log")" -eq 2 ]
  assert [ "$(sed -n '1p' "$_probe_log")" = "${_first}/install-tl-unx.tar.gz --retries 2 --delay 1 --connect-timeout 10 --max-time 15" ]
  assert [ "$(sed -n '2p' "$_probe_log")" = "${_second}/install-tl-unx.tar.gz --retries 2 --delay 1 --connect-timeout 10 --max-time 15" ]
}

@test "_tl_probe_year_mirror fails after every candidate when a transport is available" {
  local _transport_bin="${BATS_TEST_TMPDIR}/transport-bin"
  mkdir -p "$_transport_bin"
  printf '%s\n' '#!/bin/sh' 'exit 0' > "${_transport_bin}/curl"
  chmod +x "${_transport_bin}/curl"
  # shellcheck disable=SC2329
  net__probe_url() {
    printf '%s\n' "$*" >> "$_probe_log"
    return 1
  }

  PATH="$_transport_bin" run _tl_probe_year_mirror 2024
  assert_failure
  assert_output ""
  assert [ "$(wc -l < "$_probe_log")" -eq 4 ]
}

@test "_tl_probe_year_mirror retains the first mirror fallback without curl or wget" {
  local _empty_path="${BATS_TEST_TMPDIR}/empty-path"
  local _first="https://ftp.math.utah.edu/pub/tex/historic/systems/texlive/2024/tlnet-final"
  mkdir -p "$_empty_path"
  # shellcheck disable=SC2329
  net__probe_url() { return 1; }

  PATH="$_empty_path" run _tl_probe_year_mirror 2024
  assert_success
  assert_output "$_first"
}
