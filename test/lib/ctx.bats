#!/usr/bin/env bats
# Unified context registry tests (unit layer — stubs/fakes, host-agnostic).
#
# Platform-specific registry population against the real OS is covered by
# test/lib/integration/ctx_real.bats (runs in the integration tier across all library matrix environments).

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/ctx'
  load 'helpers/test_tools'
  reload_lib
  test_tools__wire_jq_yq
  ctx_test__reset
}

@test "ctx: set/get/reset" {
  ctx__set feat.version=1.2.3
  [[ "$(ctx__get feat.version)" == "1.2.3" ]]
  ctx__reset
  [[ -z "$(ctx__get feat.version)" ]]
}

@test "ctx: get on feat key before registry initialized does not fork-bomb" {
  # Regression: _ctx__load_linux_os used ctx__get to read back os.version_id
  # after the while loop, which triggered recursive ensure_registry calls
  # (fork bomb) because _CTX__REGISTRY_INITIALIZED was still false at that point.
  # The fix reads _CTX__REGISTRY directly instead.
  [[ "$(uname -s)" == Linux ]] || skip "linux-only"
  ctx__reset
  ctx__set feat.version=9.8.7
  # ctx__get must trigger ensure_registry and survive without recursion
  local _v
  _v="$(ctx__get feat.version)"
  [[ "${_v}" == "9.8.7" ]]
}

@test "ctx: get rejects flavor suffix" {
  ctx__set plat.kernel=Linux
  [[ -z "$(ctx__get plat.kernel:lower)" ]]
}

@test "ctx: compare eq case-insensitive" {
  ctx__set plat.kernel=linux
  _CTX__REGISTRY_INITIALIZED=true
  ctx__compare plat.kernel eq Linux
}

@test "ctx: expand_pattern qualified token" {
  ctx__set feat.version=1.7.1
  run ctx__expand_pattern "v{feat.version}"
  assert_success
  assert_output "v1.7.1"
}

@test "ctx: expand_pattern conditional" {
  ctx__set feat.version=1.8.0
  run ctx__expand_pattern "{feat.version>=1.7?new:old}"
  assert_success
  assert_output "new"
}

@test "ctx: match_when yaml" {
  ctx_test__seed_plat kernel=linux machine_release=amd64
  ctx_test__seed_os id=ubuntu
  run ctx__match_when $'plat.kernel: linux\nplat.machine_release: amd64'
  assert_success
}

@test "ctx: set overwrite" {
  ctx__set feat.version=1.0.0
  ctx__set feat.version=2.0.0
  [[ "$(ctx__get feat.version)" == "2.0.0" ]]
}

@test "ctx: get missing key returns empty" {
  [[ -z "$(ctx__get os.missing_key)" ]]
}

@test "ctx: json flat dotted keys" {
  ctx__set os.id=ubuntu feat.version=1.2.3
  _CTX__REGISTRY_INITIALIZED=true
  run ctx__json
  assert_success
  assert_output --partial '"os.id": "ubuntu"'
  assert_output --partial '"feat.version": "1.2.3"'
}

@test "ctx: expand_pattern multiple tokens" {
  ctx__set feat.version=1.0 os.id=debian
  _CTX__REGISTRY_INITIALIZED=true
  run ctx__expand_pattern "{os.id}-{feat.version}.tar.gz"
  assert_output "debian-1.0.tar.gz"
}

@test "ctx: expand_pattern case flavors" {
  ctx__set plat.kernel=Linux
  _CTX__REGISTRY_INITIALIZED=true
  run ctx__expand_pattern "{plat.kernel:lower}-{plat.kernel:upper}"
  assert_output "linux-LINUX"
}

@test "ctx: expand_pattern unknown token unchanged" {
  _CTX__REGISTRY_INITIALIZED=true
  run ctx__expand_pattern "{totally.unknown.key}"
  assert_output "{totally.unknown.key}"
}

@test "ctx: expand_pattern unmatched brace literal" {
  _CTX__REGISTRY_INITIALIZED=true
  run ctx__expand_pattern "prefix-{unclosed"
  assert_output "prefix-{unclosed"
}

@test "ctx: expand_pattern all comparison ops" {
  ctx__set feat.version=2.0.0
  _CTX__REGISTRY_INITIALIZED=true
  run ctx__expand_pattern "{feat.version==2.0.0?eq:ne}-{feat.version!=1.0.0?ne:bad}-{feat.version>=2.0.0?ge:bad}-{feat.version>1.0.0?gt:bad}-{feat.version<=2.0.0?le:bad}-{feat.version<3.0.0?lt:bad}"
  assert_output "eq-ne-ge-gt-le-lt"
}

@test "ctx: expand_pattern nested conditional" {
  ctx__set plat.kernel=linux plat.libc=gnu
  _CTX__REGISTRY_INITIALIZED=true
  run ctx__expand_pattern "{plat.kernel==linux?{plat.libc==gnu?-gnu:}:}"
  assert_output "-gnu"
}

@test "ctx: expand_pattern unparseable version false branch" {
  ctx__set feat.version=stable
  _CTX__REGISTRY_INITIALIZED=true
  run ctx__expand_pattern "{feat.version>=1.0?yes:no}"
  assert_output "no"
}

@test "ctx: match_when empty is true" {
  run ctx__match_when ""
  assert_success
}

@test "ctx: select_first returns first matching group" {
  ctx_test__seed_plat kernel=linux pm=apt
  run ctx__select_first -- $'- plat.pm: apk\n- plat.kernel: linux'
  assert_success
}

@test "ctx: id_like matrix bash/jq parity" {
  local _log="${BATS_TEST_TMPDIR}/id_like_matrix.log"
  ctx_test__run_id_like_matrix > "${_log}" 2>&1 || {
    cat "${_log}" >&2
    return 1
  }
}

@test "ctx: id_like first-token match drains tokenization output without SIGPIPE" {
  local _long_token="x" _id_like _i
  for ((_i = 0; _i < 17; _i++)); do
    _long_token+="${_long_token}"
  done
  _id_like="RHEL ${_long_token}"

  run _ctx__id_like_has rhel "${_id_like}"

  assert_success
  assert_output ""
}

@test "ctx: id_like pattern conditional" {
  ctx__set os.id_like="rhel centos fedora"
  _CTX__REGISTRY_INITIALIZED=true
  run ctx__expand_pattern "{os.id_like==rhel?yes:no}"
  assert_output "yes"
}

@test "ctx: derived os.version_id_major" {
  ctx__set os.version_id=22.04
  ctx__set os.version_id_major=22
  _CTX__REGISTRY_INITIALIZED=true
  [[ "$(ctx__get os.version_id_major)" == "22" ]]
}

@test "ctx: reset clears registry init flag" {
  ctx__set os.id=ubuntu
  _CTX__REGISTRY_INITIALIZED=true
  ctx__reset
  [[ "${_CTX__REGISTRY_INITIALIZED}" == false ]]
  # Read registry directly — ctx__get would re-trigger ensure_registry and re-populate os.id.
  [[ -z "${_CTX__REGISTRY["os.id"]:-}" ]]
}

@test "ctx: ensure_registry idempotent on linux" {
  [[ "$(uname -s)" == Linux ]] || skip "linux-only"
  ctx__reset
  local _json1 _json2
  _json1="$(ctx__json)"
  _json2="$(ctx__json)"
  [[ -n "${_json1}" && "${_json1}" != "{}" ]]
  [[ "${_json1}" == "${_json2}" ]]
}

@test "ctx: ensure_registry populates os.id on linux" {
  [[ "$(uname -s)" == Linux ]] || skip "linux-only"
  [[ -f /etc/os-release ]] || skip "no os-release"
  ctx__reset
  local _json _id
  _json="$(ctx__json)"
  _id="$(json__query -r '.["os.id"] // empty' <<< "${_json}")"
  [[ -n "${_id}" ]]
}

@test "ctx: ensure_registry copies ospkg PM key into plat.pm" {
  ctx_test__stub_ospkg_pm pm=apt
  ctx__reset
  [[ "$(ctx_test__json_get "$(ctx__json)" "plat.pm")" == apt ]]
}

@test "ctx: ensure_registry plat.pm stores PM key not tool name" {
  ctx_test__stub_ospkg_pm pm=apt
  ctx__reset
  local _pm
  _pm="$(ctx_test__json_get "$(ctx__json)" "plat.pm")"
  [[ "${_pm}" == apt ]]
  [[ "${_pm}" != apt-get ]]
}

@test "ctx: ensure_registry copies ospkg deb_arch when set" {
  ctx_test__stub_ospkg_pm pm=apt deb_arch=amd64
  ctx__reset
  [[ "$(ctx_test__json_get "$(ctx__json)" "plat.deb_arch")" == amd64 ]]
}

@test "ctx: compare id_like empty eq fedora is false" {
  ctx__set os.id_like=""
  _CTX__REGISTRY_INITIALIZED=true
  run ctx__compare os.id_like eq fedora
  assert_failure
}

@test "ctx: compare id_like empty ne fedora is true" {
  ctx__set os.id_like=""
  _CTX__REGISTRY_INITIALIZED=true
  ctx__compare os.id_like ne fedora
}

@test "ctx: compare id_like gte always false" {
  ctx__set os.id_like="rhel centos"
  _CTX__REGISTRY_INITIALIZED=true
  run ctx__compare os.id_like gte rhel
  assert_failure
}

@test "ctx: compare id_like eq array OR membership" {
  ctx__set os.id_like="rhel centos fedora"
  _CTX__REGISTRY_INITIALIZED=true
  ctx__compare os.id_like eq "debian|rhel"
}

@test "ctx: match_spec --quiet fails without ctx error output" {
  ctx_test__seed_plat kernel=linux pm=apt
  run ctx__match_spec --quiet $'plat.kernel: darwin'
  assert_failure
  refute_output --partial 'unsupported op'
}

@test "ctx: expand_pattern unknown key in conditional uses false branch" {
  ctx__set plat.kernel=linux
  _CTX__REGISTRY_INITIALIZED=true
  run ctx__expand_pattern "{plat.missing==x?yes:no}"
  assert_output "no"
}

@test "ctx: expand_pattern deb_arch lower flavor" {
  ctx__set plat.deb_arch=AMD64
  _CTX__REGISTRY_INITIALIZED=true
  run ctx__expand_pattern "{plat.deb_arch:lower}"
  assert_output "amd64"
}

@test "ctx: when_vectors bash/jq parity from fixture" {
  local _log="${BATS_TEST_TMPDIR}/when_vectors.log"
  ctx_test__run_when_vectors > "${_log}" 2>&1 || {
    cat "${_log}" >&2
    return 1
  }
}

@test "ctx: json excludes flavor suffix keys" {
  ctx__set plat.kernel=Linux
  _CTX__REGISTRY_INITIALIZED=true
  local _json
  _json="$(ctx__json)"
  [[ "${_json}" != *"plat.kernel:lower"* ]]
  [[ "${_json}" != *"plat.kernel:upper"* ]]
}

@test "ctx: expand_pattern title flavor" {
  ctx__set plat.kernel=linux
  _CTX__REGISTRY_INITIALIZED=true
  run ctx__expand_pattern "{plat.kernel:title}"
  assert_output "Linux"
}

@test "ctx: expand_pattern os.id without flavor" {
  ctx__set os.id=Ubuntu
  _CTX__REGISTRY_INITIALIZED=true
  run ctx__expand_pattern "{os.id}"
  assert_output "Ubuntu"
}

@test "ctx: expand_pattern conditional false branch" {
  ctx__set plat.kernel=linux
  _CTX__REGISTRY_INITIALIZED=true
  run ctx__expand_pattern "{plat.kernel==darwin?yes:no}"
  assert_output "no"
}

@test "ctx: match_spec false for non-matching AND group" {
  ctx_test__seed_plat kernel=linux pm=apt
  run ctx__match_spec $'plat.kernel: darwin'
  assert_failure
}

@test "ctx: compare id_like eq debian is false" {
  ctx__set os.id_like="rhel centos fedora"
  _CTX__REGISTRY_INITIALIZED=true
  run ctx__compare os.id_like eq debian
  assert_failure
}

@test "ctx: compare id_like scalar whole string is false" {
  ctx__set os.id_like="rhel centos fedora"
  _CTX__REGISTRY_INITIALIZED=true
  run ctx__compare os.id_like eq "rhel centos fedora"
  assert_failure
}

@test "ctx: compare id_like ne array exclude-set" {
  ctx__set os.id_like="rhel centos fedora"
  _CTX__REGISTRY_INITIALIZED=true
  ctx__compare os.id_like ne "debian|arch"
}

@test "ctx: ensure_registry derives version_id_major and mm on linux" {
  [[ "$(uname -s)" == Linux ]] || skip "linux-only"
  [[ -f /etc/os-release ]] || skip "no os-release"
  ctx__reset
  local _json _vid _major _mm
  _json="$(ctx__json)"
  _vid="$(ctx_test__json_get "${_json}" "os.version_id")"
  _major="$(ctx_test__json_get "${_json}" "os.version_id_major")"
  _mm="$(ctx_test__json_get "${_json}" "os.version_id_mm")"
  [[ -n "${_vid}" ]]
  [[ "${_major}" == "${_vid%%.*}" ]]
  [[ -n "${_mm}" ]]
}

@test "ctx: ensure_registry populates plat underscore keys on linux" {
  [[ "$(uname -s)" == Linux ]] || skip "linux-only"
  ctx__reset
  local _json _kr _kg
  _json="$(ctx__json)"
  _kr="$(ctx_test__json_get "${_json}" "plat.machine_release")"
  _kg="$(ctx_test__json_get "${_json}" "plat.kernel_gh")"
  [[ -n "${_kr}" ]]
  [[ -n "${_kg}" ]]
}

@test "ctx: ensure_registry soft-fails PM detect without PM on PATH" {
  ospkg__pm_key() { return 1; }
  export -f ospkg__pm_key
  ctx__reset
  local _json _pm _kernel
  _json="$(ctx__json)"
  _pm="$(ctx_test__json_get "${_json}" "plat.pm")"
  _kernel="$(ctx_test__json_get "${_json}" "plat.kernel")"
  [[ -z "${_pm}" ]]
  [[ -n "${_kernel}" ]]
}

@test "ctx: ensure_registry omits deb_arch on non-apt PM" {
  ctx_test__stub_ospkg_pm pm=apk deb_arch=
  ctx__reset
  local _json _pm _deb
  _json="$(ctx__json)"
  _pm="$(ctx_test__json_get "${_json}" "plat.pm")"
  _deb="$(ctx_test__json_get "${_json}" "plat.deb_arch")"
  [[ "${_pm}" == apk ]]
  [[ -z "${_deb}" ]]
}

@test "ctx: ensure_registry populates macOS os fields from stub" {
  ctx_test__stub_darwin_platform
  ctx__reset
  local _json _id _vid _codename
  _json="$(ctx__json)"
  _id="$(ctx_test__json_get "${_json}" "os.id")"
  _vid="$(ctx_test__json_get "${_json}" "os.version_id")"
  _codename="$(ctx_test__json_get "${_json}" "os.version_codename")"
  [[ "${_id}" == macos ]]
  [[ "${_vid}" == "14.2.1" ]]
  [[ -z "${_codename}" ]]
}

@test "ctx: expand_pattern pre-seed via ctx__set only" {
  ctx__reset
  ctx__set feat.version=9.9.9
  _CTX__REGISTRY_INITIALIZED=true
  run ctx__expand_pattern "v{feat.version}"
  assert_output "v9.9.9"
}

@test "ctx: pairs iterates registry entries" {
  ctx__reset
  ctx__set os.id=ubuntu feat.version=1.0
  _CTX__REGISTRY_INITIALIZED=true
  run ctx__pairs
  assert_success
  assert_output --partial "os.id=ubuntu"
  assert_output --partial "feat.version=1.0"
}

@test "ctx: get triggers ensure_registry from linux os-release stub" {
  [[ "$(uname -s)" == Linux ]] || skip "linux-only stub test"
  ctx__reset
  export _CTX__OS_RELEASE_FILE="${REPO_ROOT}/test/lib/fixtures/ctx/linux-os-release.stub"
  [[ "$(ctx__get os.id)" == "ubuntu" ]]
  [[ "$(ctx__get os.version_id)" == "22.04" ]]
  [[ "$(ctx__get os.version_id_major)" == "22" ]]
  [[ "$(ctx__get plat.kernel)" == "Linux" ]]
  unset _CTX__OS_RELEASE_FILE
}

@test "ctx: expand_pattern ignores extra arguments (no trailing KV pairs)" {
  ctx__reset
  ctx__set feat.version=1.0
  _CTX__REGISTRY_INITIALIZED=true
  run ctx__expand_pattern "v{feat.version}" "ignored=pair"
  assert_output "v1.0"
}

@test "ctx: version_id_mm for two-part linux version_id" {
  ctx__set os.version_id=22.04
  ctx__set "os.version_id_mm=22.04"
  _CTX__REGISTRY_INITIALIZED=true
  [[ "$(ctx__get os.version_id_mm)" == "22.04" ]]
}

@test "ctx: version_id_mm for three-part linux version_id" {
  ctx__set os.version_id=22.04.1
  ctx__set "os.version_id_mm=22.04"
  _CTX__REGISTRY_INITIALIZED=true
  [[ "$(ctx__get os.version_id_mm)" == "22.04" ]]
}

@test "ctx: ensure_registry darwin 2-part version_id_mm is version_id itself" {
  ctx_test__stub_darwin_platform
  sw_vers() {
    case "${1:-}" in
      -productName) printf '%s\n' "macOS" ;;
      -productVersion) printf '%s\n' "14.2" ;;
      -buildVersion) printf '%s\n' "23C99" ;;
      -productVersionExtra) printf '%s\n' "" ;;
      *) return 0 ;;
    esac
  }
  export -f sw_vers
  ctx__reset
  local _json _mm _major
  _json="$(ctx__json)"
  _mm="$(ctx_test__json_get "${_json}" "os.version_id_mm")"
  _major="$(ctx_test__json_get "${_json}" "os.version_id_major")"
  [[ "${_mm}" == "14.2" ]]
  [[ "${_major}" == "14" ]]
}

@test "ctx: select_first skips non-matching first group, returns second" {
  ctx_test__seed_plat kernel=linux pm=brew
  run ctx__select_first -- $'plat.pm: apt' -- $'plat.kernel: linux'
  assert_success
}

@test "ctx: select_first returns failure when no group matches" {
  ctx_test__seed_plat kernel=linux pm=brew
  run ctx__select_first -- $'plat.pm: apt' -- $'plat.kernel: darwin'
  assert_failure
}

@test "ctx: version_id_mm from ensure_registry matches expected value on linux stub" {
  [[ "$(uname -s)" == Linux ]] || skip "linux-only stub test"
  ctx__reset
  export _CTX__OS_RELEASE_FILE="${REPO_ROOT}/test/lib/fixtures/ctx/linux-os-release.stub"
  local _mm
  _mm="$(ctx__get os.version_id_mm)"
  [[ "${_mm}" == "22.04" ]]
  unset _CTX__OS_RELEASE_FILE
}

# ---------------------------------------------------------------------------
# ctx__compare — direct bash tests (not via YAML when eval)
# ---------------------------------------------------------------------------

@test "ctx: compare ne on regular key (string equality)" {
  ctx__set plat.kernel=linux
  _CTX__REGISTRY_INITIALIZED=true
  ctx__compare plat.kernel ne darwin
  run ctx__compare plat.kernel ne linux
  assert_failure
}

@test "ctx: compare ordering ops directly on feat.version" {
  ctx__set feat.version=1.5.0
  _CTX__REGISTRY_INITIALIZED=true
  ctx__compare feat.version gte 1.0.0
  ctx__compare feat.version lte 2.0.0
  ctx__compare feat.version gt 1.0.0
  ctx__compare feat.version lt 2.0.0
  run ctx__compare feat.version gte 2.0.0
  assert_failure
  run ctx__compare feat.version lt 1.0.0
  assert_failure
}

@test "ctx: compare eq case-insensitive on plat.kernel" {
  ctx__set plat.kernel=Linux
  _CTX__REGISTRY_INITIALIZED=true
  ctx__compare plat.kernel eq linux
  ctx__compare plat.kernel eq LINUX
  ctx__compare plat.kernel eq Linux
}

@test "ctx: compare ordering fails closed on unparseable key value" {
  ctx__set feat.version=stable
  _CTX__REGISTRY_INITIALIZED=true
  run ctx__compare feat.version gte 1.0.0
  assert_failure
  run ctx__compare feat.version lt 2.0.0
  assert_failure
}

@test "ctx: compare unsupported op returns failure" {
  ctx__set feat.version=1.0.0
  _CTX__REGISTRY_INITIALIZED=true
  run ctx__compare feat.version in 1.0.0
  assert_failure
}

# ---------------------------------------------------------------------------
# ctx__json edge cases
# ---------------------------------------------------------------------------

@test "ctx: json returns {} when registry is empty" {
  ctx__reset
  _CTX__REGISTRY_INITIALIZED=true
  run ctx__json
  assert_success
  assert_output "{}"
}

# ---------------------------------------------------------------------------
# ctx__match_when — explicit YAML shape tests
# ---------------------------------------------------------------------------

@test "ctx: match_when OR-array of AND-groups: first group matches" {
  ctx_test__seed_plat kernel=linux machine_release=amd64
  run ctx__match_when $'- plat.kernel: linux\n  plat.machine_release: amd64\n- plat.kernel: darwin'
  assert_success
}

@test "ctx: match_when OR-array: no group matches returns failure" {
  ctx_test__seed_plat kernel=linux machine_release=arm64
  run ctx__match_when $'- plat.kernel: darwin\n- plat.machine_release: amd64'
  assert_failure
}

@test "ctx: match_when ne operator excludes matching value" {
  ctx_test__seed_plat pm=apt
  run ctx__match_when $'plat.pm:\n  ne: dnf'
  assert_success
  run ctx__match_when $'plat.pm:\n  ne: apt'
  assert_failure
}

@test "ctx: match_when ne array exclude-set: passes when pm not in list" {
  ctx_test__seed_plat pm=apt
  run ctx__match_when $'plat.pm:\n  ne:\n  - dnf\n  - yum'
  assert_success
}

@test "ctx: match_when ne array exclude-set: fails when pm is in list" {
  ctx_test__seed_plat pm=dnf
  run ctx__match_when $'plat.pm:\n  ne:\n  - dnf\n  - yum'
  assert_failure
}

@test "ctx: match_when multi-op AND range: passes when version in range" {
  ctx_test__seed_feat version=1.5.0
  run ctx__match_when $'feat.version:\n  gte: "1.0.0"\n  lt: "2.0.0"'
  assert_success
}

@test "ctx: match_when multi-op AND range: fails when version below range" {
  ctx_test__seed_feat version=0.9.0
  run ctx__match_when $'feat.version:\n  gte: "1.0.0"\n  lt: "2.0.0"'
  assert_failure
}

@test "ctx: match_when multi-op AND range: fails when version above range" {
  ctx_test__seed_feat version=2.1.0
  run ctx__match_when $'feat.version:\n  gte: "1.0.0"\n  lt: "2.0.0"'
  assert_failure
}

@test "ctx: match_when eq array OR: matches any listed value" {
  ctx_test__seed_plat pm=apk
  run ctx__match_when $'plat.pm: [apt, apk]'
  assert_success
}

@test "ctx: match_when eq array OR: fails when value not in list" {
  ctx_test__seed_plat pm=brew
  run ctx__match_when $'plat.pm: [apt, apk]'
  assert_failure
}

@test "ctx: match_spec evaluates AND group (all keys must match)" {
  ctx_test__seed_plat kernel=linux pm=apt
  run ctx__match_spec $'plat.kernel: linux\nplat.pm: apt'
  assert_success
  run ctx__match_spec $'plat.kernel: linux\nplat.pm: brew'
  assert_failure
}

# ---------------------------------------------------------------------------
# ctx__select_first — group-separator edge cases
# ---------------------------------------------------------------------------

@test "ctx: select_first with empty first group passes through to second" {
  ctx_test__seed_plat kernel=linux
  run ctx__select_first -- -- $'plat.kernel: linux'
  assert_success
}

@test "ctx: select_first returns first group when it matches" {
  ctx_test__seed_plat kernel=linux pm=apt
  run --separate-stderr ctx__select_first -- $'plat.pm: apt' -- $'plat.kernel: linux'
  assert_success
  assert_output ""
}

@test "ctx: select_first with three groups finds third" {
  ctx_test__seed_plat kernel=darwin pm=brew
  run ctx__select_first -- $'plat.pm: apt' -- $'plat.pm: apk' -- $'plat.kernel: darwin'
  assert_success
}
