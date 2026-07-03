#!/usr/bin/env bats
# Integration tests for lib/ctx.bash — verifies actual context registry values
# against the real system in every supported environment.
#
# No root, no network required. Runs wherever the devfeats test suite runs:
# Linux containers (ubuntu, debian, alpine, fedora, rocky, …) and macOS.
# Individual tests skip automatically when not applicable to the current platform.
#
# Design principle: every assertion cross-checks ctx__get against the
# authoritative system source (os-release, uname, sw_vers, dpkg) rather
# than against hardcoded expected strings, so the tests remain valid across
# every distro/version without per-environment expected-value tables.

bats_require_minimum_version 1.5.0

setup() {
  load '../helpers/common'
  reload_lib
}

# ── Internal helpers ──────────────────────────────────────────────────────────

# Read and unquote a single field from /etc/os-release.
_os_release_field() {
  local _field="$1" _raw
  [[ -f /etc/os-release ]] || return 1
  _raw="$(grep -m1 "^${_field}=" /etc/os-release 2> /dev/null || true)"
  [[ -n "${_raw}" ]] || return 1
  _raw="${_raw#*=}"
  _raw="${_raw#\"}"
  _raw="${_raw%\"}"
  _raw="${_raw#\'}"
  _raw="${_raw%\'}"
  printf '%s' "${_raw}"
}

# Compute expected os.version_id_mm from a VERSION_ID string.
_expected_version_id_mm() {
  local _vid="$1"
  if [[ "${_vid}" == *.*.* ]]; then
    printf '%s' "${_vid%.*}"
  else
    printf '%s' "${_vid}"
  fi
}

# ── os.* keys on Linux ───────────────────────────────────────────────────────

@test "ctx_real: os.id matches /etc/os-release ID (lowercased)" {
  [[ -f /etc/os-release ]] || skip "no /etc/os-release"
  local _expected _actual
  _expected="$(_os_release_field ID)" || skip "no ID field"
  _actual="$(ctx__get os.id)"
  [[ "${_actual}" == "${_expected,,}" ]]
}

@test "ctx_real: os.id_like matches /etc/os-release ID_LIKE" {
  [[ -f /etc/os-release ]] || skip "no /etc/os-release"
  local _expected _actual
  _expected="$(_os_release_field ID_LIKE || true)"
  _actual="$(ctx__get os.id_like)"
  [[ "${_actual}" == "${_expected}" ]]
}

@test "ctx_real: os.name matches /etc/os-release NAME" {
  [[ -f /etc/os-release ]] || skip "no /etc/os-release"
  local _expected _actual
  _expected="$(_os_release_field NAME)" || skip "no NAME field"
  _actual="$(ctx__get os.name)"
  [[ "${_actual}" == "${_expected}" ]]
}

@test "ctx_real: os.version_id matches /etc/os-release VERSION_ID" {
  [[ -f /etc/os-release ]] || skip "no /etc/os-release"
  local _expected _actual
  _expected="$(_os_release_field VERSION_ID || true)"
  [[ -n "${_expected}" ]] || skip "no VERSION_ID field"
  _actual="$(ctx__get os.version_id)"
  [[ "${_actual}" == "${_expected}" ]]
}

@test "ctx_real: os.version_codename matches /etc/os-release VERSION_CODENAME" {
  [[ -f /etc/os-release ]] || skip "no /etc/os-release"
  local _expected _actual
  _expected="$(_os_release_field VERSION_CODENAME || true)"
  _actual="$(ctx__get os.version_codename)"
  [[ "${_actual}" == "${_expected}" ]]
}

@test "ctx_real: os.version matches /etc/os-release VERSION" {
  [[ -f /etc/os-release ]] || skip "no /etc/os-release"
  local _expected _actual
  _expected="$(_os_release_field VERSION || true)"
  _actual="$(ctx__get os.version)"
  [[ "${_actual}" == "${_expected}" ]]
}

# ── Derived os.* keys on Linux ───────────────────────────────────────────────

@test "ctx_real: os.version_id_major is first dot-segment of VERSION_ID" {
  [[ -f /etc/os-release ]] || skip "no /etc/os-release"
  local _vid _expected _actual
  _vid="$(_os_release_field VERSION_ID || true)"
  [[ -n "${_vid}" ]] || skip "no VERSION_ID"
  _expected="${_vid%%.*}"
  _actual="$(ctx__get os.version_id_major)"
  [[ "${_actual}" == "${_expected}" ]]
}

@test "ctx_real: os.version_id_major is a non-empty numeric string" {
  [[ -f /etc/os-release ]] || skip "no /etc/os-release"
  local _vid _actual
  _vid="$(_os_release_field VERSION_ID || true)"
  [[ -n "${_vid}" ]] || skip "no VERSION_ID"
  _actual="$(ctx__get os.version_id_major)"
  [[ -n "${_actual}" && "${_actual}" =~ ^[0-9]+$ ]]
}

@test "ctx_real: os.version_id_mm is correct major.minor prefix of VERSION_ID" {
  [[ -f /etc/os-release ]] || skip "no /etc/os-release"
  local _vid _expected _actual
  _vid="$(_os_release_field VERSION_ID || true)"
  [[ -n "${_vid}" ]] || skip "no VERSION_ID"
  _expected="$(_expected_version_id_mm "${_vid}")"
  _actual="$(ctx__get os.version_id_mm)"
  [[ "${_actual}" == "${_expected}" ]]
}

@test "ctx_real: os.version_id_mm is a prefix of (or equal to) os.version_id" {
  [[ -f /etc/os-release ]] || skip "no /etc/os-release"
  local _vid _mm
  _vid="$(_os_release_field VERSION_ID || true)"
  [[ -n "${_vid}" ]] || skip "no VERSION_ID"
  _mm="$(ctx__get os.version_id_mm)"
  [[ "${_vid}" == "${_mm}" || "${_vid}" == "${_mm}."* ]]
}

@test "ctx_real: os.version_id_mm equals os.version_id when VERSION_ID has ≤2 segments" {
  [[ -f /etc/os-release ]] || skip "no /etc/os-release"
  local _vid _actual
  _vid="$(_os_release_field VERSION_ID || true)"
  [[ -n "${_vid}" ]] || skip "no VERSION_ID"
  # Only meaningful assertion when version has ≤2 segments (e.g. "22.04" or "40")
  [[ "${_vid}" == *.*.* ]] && skip "three-part version_id; mm trimming expected"
  _actual="$(ctx__get os.version_id_mm)"
  [[ "${_actual}" == "${_vid}" ]]
}

@test "ctx_real: os.version_id_mm trims third segment when VERSION_ID has 3 segments" {
  [[ -f /etc/os-release ]] || skip "no /etc/os-release"
  local _vid _actual
  _vid="$(_os_release_field VERSION_ID || true)"
  [[ "${_vid}" == *.*.* ]] || skip "version_id has fewer than 3 segments; trimming not applicable"
  _actual="$(ctx__get os.version_id_mm)"
  [[ "${_actual}" == "${_vid%.*}" ]]
}

# ── plat.* computed keys ──────────────────────────────────────────────────────

@test "ctx_real: plat.kernel matches uname -s" {
  local _expected _actual
  _expected="$(uname -s)"
  _actual="$(ctx__get plat.kernel)"
  [[ "${_actual}" == "${_expected}" ]]
}

@test "ctx_real: plat.machine matches uname -m" {
  local _expected _actual
  _expected="$(uname -m)"
  _actual="$(ctx__get plat.machine)"
  [[ "${_actual}" == "${_expected}" ]]
}

@test "ctx_real: plat.machine_release is a recognised release arch token" {
  local _actual
  _actual="$(ctx__get plat.machine_release)"
  [[ -n "${_actual}" ]] || fail "plat.machine_release is empty"
  case "${_actual}" in
    amd64 | arm64 | armv7 | i386 | ppc64le | s390x | riscv64 | loong64 | armv6) ;;
    *) fail "unrecognised plat.machine_release: '${_actual}'" ;;
  esac
}

@test "ctx_real: plat.machine_go is a recognised GOARCH-style token" {
  local _actual
  _actual="$(ctx__get plat.machine_go)"
  [[ -n "${_actual}" ]] || fail "plat.machine_go is empty"
  case "${_actual}" in
    amd64 | arm64 | arm | 386 | ppc64le | s390x | riscv64 | loong64) ;;
    *) fail "unrecognised plat.machine_go: '${_actual}'" ;;
  esac
}

@test "ctx_real: plat.machine_go is 'amd64' on x86_64/amd64 hosts" {
  local _machine
  _machine="$(uname -m)"
  case "${_machine}" in x86_64 | amd64) ;; *) skip "not an x86_64 host" ;; esac
  [[ "$(ctx__get plat.machine_go)" == "amd64" ]]
}

@test "ctx_real: plat.machine_gnu is 'x86_64' on x86_64/amd64 hosts" {
  local _machine
  _machine="$(uname -m)"
  case "${_machine}" in x86_64 | amd64) ;; *) skip "not an x86_64 host" ;; esac
  [[ "$(ctx__get plat.machine_gnu)" == "x86_64" ]]
}

@test "ctx_real: plat.machine_gnu equals plat.machine_release on non-x86_64 hosts" {
  local _machine
  _machine="$(uname -m)"
  case "${_machine}" in x86_64 | amd64) skip "x86_64 host — gnu flavor canonicalises" ;; esac
  [[ "$(ctx__get plat.machine_gnu)" == "$(ctx__get plat.machine_release)" ]]
}

@test "ctx_real: plat.kernel_gh is 'linux' on Linux" {
  [[ "$(uname -s)" == "Linux" ]] || skip "linux-only"
  [[ "$(ctx__get plat.kernel_gh)" == "linux" ]]
}

@test "ctx_real: plat.kernel_macos is 'linux' on Linux" {
  [[ "$(uname -s)" == "Linux" ]] || skip "linux-only"
  [[ "$(ctx__get plat.kernel_macos)" == "linux" ]]
}

@test "ctx_real: plat.kernel_osx is 'linux' on Linux" {
  [[ "$(uname -s)" == "Linux" ]] || skip "linux-only"
  [[ "$(ctx__get plat.kernel_osx)" == "linux" ]]
}

@test "ctx_real: plat.kernel_gh is 'macOS' on Darwin" {
  [[ "$(uname -s)" == "Darwin" ]] || skip "darwin-only"
  [[ "$(ctx__get plat.kernel_gh)" == "macOS" ]]
}

@test "ctx_real: plat.kernel_macos is 'macos' on Darwin" {
  [[ "$(uname -s)" == "Darwin" ]] || skip "darwin-only"
  [[ "$(ctx__get plat.kernel_macos)" == "macos" ]]
}

@test "ctx_real: plat.kernel_osx is 'osx' on Darwin" {
  [[ "$(uname -s)" == "Darwin" ]] || skip "darwin-only"
  [[ "$(ctx__get plat.kernel_osx)" == "osx" ]]
}

@test "ctx_real: plat.platform is a recognised platform tag" {
  local _actual
  _actual="$(ctx__get plat.platform)"
  [[ -n "${_actual}" ]] || fail "plat.platform is empty"
  case "${_actual}" in
    debian | alpine | rhel | suse | macos) ;;
    *) fail "unrecognised plat.platform: '${_actual}'" ;;
  esac
}

@test "ctx_real: plat.platform is 'debian' on Debian/Ubuntu" {
  [[ -f /etc/os-release ]] || skip "no /etc/os-release"
  local _id
  _id="$(_os_release_field ID || true)"
  case "${_id,,}" in debian | ubuntu) ;; *) skip "not debian/ubuntu" ;; esac
  [[ "$(ctx__get plat.platform)" == "debian" ]]
}

@test "ctx_real: plat.platform is 'alpine' on Alpine" {
  [[ -f /etc/os-release ]] || skip "no /etc/os-release"
  local _id
  _id="$(_os_release_field ID || true)"
  [[ "${_id,,}" == "alpine" ]] || skip "not alpine"
  [[ "$(ctx__get plat.platform)" == "alpine" ]]
}

@test "ctx_real: plat.platform is 'rhel' on Fedora/RHEL family" {
  [[ -f /etc/os-release ]] || skip "no /etc/os-release"
  local _id
  _id="$(_os_release_field ID || true)"
  case "${_id,,}" in fedora | rhel | rocky | almalinux | centos) ;; *) skip "not rhel-family" ;; esac
  [[ "$(ctx__get plat.platform)" == "rhel" ]]
}

@test "ctx_real: plat.platform is 'macos' on Darwin" {
  [[ "$(uname -s)" == "Darwin" ]] || skip "darwin-only"
  [[ "$(ctx__get plat.platform)" == "macos" ]]
}

# ── PM detection keys ─────────────────────────────────────────────────────────

@test "ctx_real: plat.pm is a recognised PM key when a PM is present" {
  local _actual
  _actual="$(ctx__get plat.pm)"
  [[ -n "${_actual}" ]] || skip "no PM detected on this system"
  case "${_actual}" in
    apt | apk | dnf | yum | zypper | pacman | brew) ;;
    *) fail "unrecognised plat.pm: '${_actual}'" ;;
  esac
}

@test "ctx_real: plat.pm is 'apt' (not 'apt-get') on Debian/Ubuntu" {
  [[ -f /etc/os-release ]] || skip "no /etc/os-release"
  local _id
  _id="$(_os_release_field ID || true)"
  case "${_id,,}" in debian | ubuntu) ;; *) skip "not debian/ubuntu" ;; esac
  [[ "$(ctx__get plat.pm)" == "apt" ]]
}

@test "ctx_real: plat.pm is 'apk' on Alpine" {
  [[ -f /etc/os-release ]] || skip "no /etc/os-release"
  [[ "$(_os_release_field ID || true)" == "alpine" ]] || skip "not alpine"
  [[ "$(ctx__get plat.pm)" == "apk" ]]
}

@test "ctx_real: plat.pm is 'dnf' on Fedora" {
  [[ -f /etc/os-release ]] || skip "no /etc/os-release"
  [[ "$(_os_release_field ID || true)" == "fedora" ]] || skip "not fedora"
  [[ "$(ctx__get plat.pm)" == "dnf" ]]
}

@test "ctx_real: plat.deb_arch matches dpkg --print-architecture on apt systems" {
  [[ "$(ctx__get plat.pm)" == "apt" ]] || skip "not an apt system"
  command -v dpkg > /dev/null 2>&1 || skip "dpkg not available"
  local _expected _actual
  _expected="$(dpkg --print-architecture 2> /dev/null)"
  [[ -n "${_expected}" ]] || skip "dpkg --print-architecture returned empty"
  _actual="$(ctx__get plat.deb_arch)"
  [[ "${_actual}" == "${_expected}" ]]
}

@test "ctx_real: plat.deb_arch is empty on non-apt systems" {
  local _pm
  _pm="$(ctx__get plat.pm)"
  [[ "${_pm}" == "apt" ]] && skip "apt system — deb_arch is expected to be set"
  [[ -z "$(ctx__get plat.deb_arch)" ]]
}

# ── libc and Rust triple ──────────────────────────────────────────────────────

@test "ctx_real: plat.libc is 'gnu' or 'musl' on Linux" {
  [[ "$(uname -s)" == "Linux" ]] || skip "linux-only"
  local _actual
  _actual="$(ctx__get plat.libc)"
  [[ "${_actual}" == "gnu" || "${_actual}" == "musl" ]]
}

@test "ctx_real: plat.libc is 'musl' on Alpine" {
  [[ -f /etc/os-release ]] || skip "no /etc/os-release"
  [[ "$(_os_release_field ID || true)" == "alpine" ]] || skip "not alpine"
  [[ "$(ctx__get plat.libc)" == "musl" ]]
}

@test "ctx_real: plat.libc is 'gnu' on Debian/Ubuntu" {
  [[ -f /etc/os-release ]] || skip "no /etc/os-release"
  local _id
  _id="$(_os_release_field ID || true)"
  case "${_id,,}" in debian | ubuntu) ;; *) skip "not debian/ubuntu" ;; esac
  [[ "$(ctx__get plat.libc)" == "gnu" ]]
}

@test "ctx_real: plat.musl_suffix is '-musl' iff plat.libc is 'musl'" {
  local _libc _suffix
  _libc="$(ctx__get plat.libc || true)"
  _suffix="$(ctx__get plat.musl_suffix)"
  if [[ "${_libc}" == "musl" ]]; then
    [[ "${_suffix}" == "-musl" ]]
  else
    [[ -z "${_suffix}" ]]
  fi
}

@test "ctx_real: plat.musl_suffix is empty on Darwin" {
  [[ "$(uname -s)" == "Darwin" ]] || skip "darwin-only"
  [[ -z "$(ctx__get plat.musl_suffix)" ]]
}

@test "ctx_real: plat.rust_triple is non-empty" {
  local _actual
  _actual="$(ctx__get plat.rust_triple)"
  [[ -n "${_actual}" ]] || fail "plat.rust_triple is empty"
}

@test "ctx_real: plat.rust_triple ends with '-linux-musl' or '-linux-gnu' variant on Linux" {
  [[ "$(uname -s)" == "Linux" ]] || skip "linux-only"
  local _actual
  _actual="$(ctx__get plat.rust_triple)"
  [[ "${_actual}" == *"-linux-musl" || "${_actual}" == *"-linux-gnu" ||
    "${_actual}" == *"-linux-musleabihf" || "${_actual}" == *"-linux-musleabi" ]]
}

@test "ctx_real: plat.rust_triple ends with '-apple-darwin' on Darwin" {
  [[ "$(uname -s)" == "Darwin" ]] || skip "darwin-only"
  [[ "$(ctx__get plat.rust_triple)" == *"-apple-darwin" ]]
}

# ── macOS os.* keys ───────────────────────────────────────────────────────────

@test "ctx_real: os.id is 'macos' on Darwin" {
  [[ "$(uname -s)" == "Darwin" ]] || skip "darwin-only"
  [[ "$(ctx__get os.id)" == "macos" ]]
}

@test "ctx_real: os.id_like is 'macos' on Darwin" {
  [[ "$(uname -s)" == "Darwin" ]] || skip "darwin-only"
  [[ "$(ctx__get os.id_like)" == "macos" ]]
}

@test "ctx_real: os.version_id matches sw_vers -productVersion on Darwin" {
  [[ "$(uname -s)" == "Darwin" ]] || skip "darwin-only"
  local _expected _actual
  _expected="$(sw_vers -productVersion 2> /dev/null)"
  [[ -n "${_expected}" ]] || skip "sw_vers unavailable"
  _actual="$(ctx__get os.version_id)"
  [[ "${_actual}" == "${_expected}" ]]
}

@test "ctx_real: os.name matches sw_vers -productName on Darwin" {
  [[ "$(uname -s)" == "Darwin" ]] || skip "darwin-only"
  local _expected _actual
  _expected="$(sw_vers -productName 2> /dev/null)"
  [[ -n "${_expected}" ]] || skip "sw_vers unavailable"
  _actual="$(ctx__get os.name)"
  [[ "${_actual}" == "${_expected}" ]]
}

@test "ctx_real: os.build_id matches sw_vers -buildVersion on Darwin" {
  [[ "$(uname -s)" == "Darwin" ]] || skip "darwin-only"
  local _expected _actual
  _expected="$(sw_vers -buildVersion 2> /dev/null)"
  [[ -n "${_expected}" ]] || skip "sw_vers unavailable"
  _actual="$(ctx__get os.build_id)"
  [[ "${_actual}" == "${_expected}" ]]
}

@test "ctx_real: os.version_codename is absent/empty on Darwin" {
  [[ "$(uname -s)" == "Darwin" ]] || skip "darwin-only"
  [[ -z "$(ctx__get os.version_codename)" ]]
}

@test "ctx_real: os.version_id_major is first segment of sw_vers productVersion on Darwin" {
  [[ "$(uname -s)" == "Darwin" ]] || skip "darwin-only"
  local _vid _expected _actual
  _vid="$(sw_vers -productVersion 2> /dev/null)"
  [[ -n "${_vid}" ]] || skip "sw_vers unavailable"
  _expected="${_vid%%.*}"
  _actual="$(ctx__get os.version_id_major)"
  [[ "${_actual}" == "${_expected}" ]]
}

@test "ctx_real: os.version_id_mm is correct prefix of sw_vers productVersion on Darwin" {
  [[ "$(uname -s)" == "Darwin" ]] || skip "darwin-only"
  local _vid _expected _actual
  _vid="$(sw_vers -productVersion 2> /dev/null)"
  [[ -n "${_vid}" ]] || skip "sw_vers unavailable"
  _expected="$(_expected_version_id_mm "${_vid}")"
  _actual="$(ctx__get os.version_id_mm)"
  [[ "${_actual}" == "${_expected}" ]]
}

# ── Registry correctness and regression tests ─────────────────────────────────

@test "ctx_real: ctx__json produces valid JSON with all keys" {
  local _json
  _json="$(ctx__json)"
  json__query -e '.' <<< "${_json}" > /dev/null
}

@test "ctx_real: all required plat.* keys are populated" {
  local _json
  _json="$(ctx__json)"
  for _key in plat.kernel plat.machine plat.machine_release plat.platform \
    plat.kernel_gh plat.kernel_macos plat.kernel_osx; do
    local _val
    _val="$(json__query -r --arg k "${_key}" '.[$k] // empty' <<< "${_json}")"
    [[ -n "${_val}" ]] || fail "required key '${_key}' missing or empty in ctx registry"
  done
}

@test "ctx_real: ensure_registry is idempotent — second call returns identical JSON" {
  local _j1 _j2
  _j1="$(ctx__json)"
  _j2="$(ctx__json)"
  [[ "${_j1}" == "${_j2}" ]]
}

@test "ctx_real: ctx__get on a feat key before initialization does not fork-bomb" {
  # Regression for the bug where _ctx__load_linux_os called ctx__get os.version_id
  # while _CTX__REGISTRY_INITIALIZED was still false, causing infinite recursive
  # subshell spawning.
  ctx__reset
  ctx__set feat.version=sentinel-value
  local _actual
  _actual="$(ctx__get feat.version)"
  [[ "${_actual}" == "sentinel-value" ]]
}

@test "ctx_real: ctx__get on feat key preserves value through ensure_registry" {
  ctx__reset
  ctx__set feat.version=9.8.7
  ctx__set feat.method=binary
  # ensure_registry populates os.*/plat.* but must not touch feat.*
  local _v _m
  _v="$(ctx__get feat.version)"
  _m="$(ctx__get feat.method)"
  [[ "${_v}" == "9.8.7" ]]
  [[ "${_m}" == "binary" ]]
}

@test "ctx_real: ctx__match_when with qualified key matches real system" {
  [[ -f /etc/os-release ]] || skip "no /etc/os-release"
  bootstrap__yq > /dev/null || skip "yq unavailable"
  local _kernel
  _kernel="$(ctx__get plat.kernel)"
  run ctx__match_when "plat.kernel: ${_kernel}"
  assert_success
}

@test "ctx_real: ctx__expand_pattern substitutes plat.kernel from real registry" {
  local _kernel _expanded
  _kernel="$(ctx__get plat.kernel)"
  _expanded="$(ctx__expand_pattern "kernel={plat.kernel}")"
  [[ "${_expanded}" == "kernel=${_kernel}" ]]
}

@test "ctx_real: ctx__expand_pattern :lower flavor produces lowercase of plat.kernel" {
  local _kernel _expanded
  _kernel="$(ctx__get plat.kernel)"
  _expanded="$(ctx__expand_pattern "{plat.kernel:lower}")"
  [[ "${_expanded}" == "${_kernel,,}" ]]
}
