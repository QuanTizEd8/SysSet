#!/usr/bin/env bats
# Unit tests for ospkg manifest YAML parsing and package resolution.
#
# These tests call ospkg__run --manifest <content> --dry_run directly,
# asserting that the resolved package list matches the per-platform expected
# files in test/lib/cases/install-os-pkg/.
#
# Test matrix: 11 cases × 6 platform contexts (ubuntu, debian, alpine, fedora,
# opensuse-leap, arch). A case with a missing <platform>.expected file is
# skipped; a case with an empty file asserts zero packages are resolved.
#
# jq and yq are immutable suite-level test prerequisites.

bats_require_minimum_version 1.5.0

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
CASES_DIR="${REPO_ROOT}/test/lib/cases/install-os-pkg"

setup() {
  load 'helpers/common'
  load 'helpers/test_tools'
  load 'helpers/stubs'
  test_tools__wire_jq_yq
}

# _seed_context <pm> <id> [<id_like>] [<version_id>]
#
# Reloads ospkg.bash, fakes the PM binary using a restricted PATH so
# _ospkg__detect picks exactly the right PM, then restores the real PATH with
# the fake dir prepended.  Seeds the unified ctx registry for cross-platform
# manifest tests. The per-test helper points bootstrap__yq at the immutable
# suite copy.
_seed_context() {
  local _pm="$1" _id="$2" _id_like="${3:-}" _version_id="${4:-}"

  reload_lib

  # Create only the target PM binary and a uname stub in the fake bin dir.
  create_fake_bin "uname" "Linux"
  case "$_pm" in
    apt) create_fake_bin "apt-get" ;;
    apk) create_fake_bin "apk" ;;
    dnf) create_fake_bin "dnf" ;;
    zypper) create_fake_bin "zypper" ;;
    pacman) create_fake_bin "pacman" ;;
  esac

  # Use a completely restricted PATH for _ospkg__detect so only our fake PM is
  # found.  This prevents the real apt-get (present in Ubuntu containers) from
  # being detected when testing non-apt platforms.
  PATH="${BATS_TEST_TMPDIR}/bin" _ospkg__detect

  # Restore PATH with fake bins prepended for subsequent commands (ospkg__run).
  prepend_fake_bin_path

  # Put the cached jq binary on PATH so json__query's bootstrap__jq
  # short-circuits at `command -v jq` instead of attempting a fresh
  # GitHub-release download. That download path calls os__release_arch →
  # `uname -m`, which create_fake_bin's `uname` stub answers with "Linux"
  # (it prints "Linux" for every argument), breaking arch detection. yq is
  # invoked via its test-only stub, but jq is invoked
  # as a bare `jq` after bootstrap__jq, so it must be resolvable on PATH.
  ln -sf "${DEVFEATS_TEST_JQ_BIN}" "${BATS_TEST_TMPDIR}/bin/jq"

  ctx__reset
  ctx__set "plat.pm=${_pm}"
  ctx__set "plat.kernel=linux"
  ctx__set "plat.machine_release=amd64"
  ctx__set "os.id=${_id}"
  ctx__set "os.id_like=${_id_like}"
  ctx__set "os.version_id=${_version_id}"
  _CTX__REGISTRY_INITIALIZED=true

  # Point bootstrap__yq at the immutable suite-cached binary.
  test_tools__wire_yq

  # Fake PMs (e.g. apk, pacman) exit 0 for all calls, which makes
  # ospkg__is_installed report every package as already installed and skip it.
  # Stub to return 1 so packages are always considered absent in dry-run tests.
  ospkg__is_installed() { return 1; }
  export -f ospkg__is_installed
}

# _assert_manifest_pkgs <case_name> <platform>
#
# Loads test/lib/cases/install-os-pkg/<case_name>/manifest.yaml, runs
# ospkg__run --dry_run, extracts and sorts the resolved package list, and
# asserts it matches <platform>.expected (sorted).
# Skips if <platform>.expected does not exist for this case.
# Asserts zero packages when the expected file is empty.
_assert_manifest_pkgs() {
  local _case="$1" _platform="$2"
  local _manifest_file="${CASES_DIR}/${_case}/manifest.yaml"
  local _expected_file="${CASES_DIR}/${_case}/${_platform}.expected"

  [[ -f "${_expected_file}" ]] || skip "no expected file for ${_platform} in ${_case}"

  local _expected
  _expected="$(sort "${_expected_file}")"

  run ospkg__run --manifest "$(cat "${_manifest_file}")" --dry_run
  assert_success

  # Extract packages from the [dry-run] packages: line (logged to stderr,
  # which bats captures into $output together with stdout).
  local _actual
  _actual="$(printf '%s\n' "${output}" |
    grep '\[dry-run\] packages' |
    sed 's/.*packages: //' |
    tr ' ' '\n' | sort | grep -v '^$' || true)"

  if [[ -z "${_expected}" ]]; then
    [[ -z "${_actual}" ]] || {
      printf 'expected 0 packages for %s on %s but got:\n%s\n' \
        "${_case}" "${_platform}" "${_actual}" >&2
      return 1
    }
  else
    assert_equal "${_actual}" "${_expected}"
  fi
}

# ---------------------------------------------------------------------------
# Case: comments_and_blank
# Comment lines (# ...) and blank lines are stripped before resolving.
# Non-comment packages are always installed on every PM.
# ---------------------------------------------------------------------------

@test "manifest case comments_and_blank on ubuntu: resolves expected packages" {
  _seed_context "apt" "ubuntu" "debian" "22.04"
  _assert_manifest_pkgs "comments_and_blank" "ubuntu"
}

@test "manifest case comments_and_blank on debian: resolves expected packages" {
  _seed_context "apt" "debian" "" "12"
  _assert_manifest_pkgs "comments_and_blank" "debian"
}

@test "manifest case comments_and_blank on alpine: resolves expected packages" {
  _seed_context "apk" "alpine" "" "3.20"
  _assert_manifest_pkgs "comments_and_blank" "alpine"
}

@test "manifest case comments_and_blank on fedora: resolves expected packages" {
  _seed_context "dnf" "fedora" "" "40"
  _assert_manifest_pkgs "comments_and_blank" "fedora"
}

@test "manifest case comments_and_blank on opensuse-leap: resolves expected packages" {
  _seed_context "zypper" "opensuse-leap" "" "15.5"
  _assert_manifest_pkgs "comments_and_blank" "opensuse-leap"
}

@test "manifest case comments_and_blank on arch: resolves expected packages" {
  _seed_context "pacman" "arch" "" ""
  _assert_manifest_pkgs "comments_and_blank" "arch"
}

# ---------------------------------------------------------------------------
# Case: id_selectors
# AND logic within a condition object: {pm: apt, id: debian} requires BOTH.
# Distinguishes Debian and Ubuntu even though both use apt.
# ---------------------------------------------------------------------------

@test "manifest case id_selectors on ubuntu: common-apt-pkg and ubuntu-only" {
  _seed_context "apt" "ubuntu" "debian" "22.04"
  _assert_manifest_pkgs "id_selectors" "ubuntu"
}

@test "manifest case id_selectors on debian: common-apt-pkg and debian-only" {
  _seed_context "apt" "debian" "" "12"
  _assert_manifest_pkgs "id_selectors" "debian"
}

@test "manifest case id_selectors on alpine: no expected file — skips" {
  _seed_context "apk" "alpine" "" "3.20"
  _assert_manifest_pkgs "id_selectors" "alpine"
}

@test "manifest case id_selectors on fedora: no expected file — skips" {
  _seed_context "dnf" "fedora" "" "40"
  _assert_manifest_pkgs "id_selectors" "fedora"
}

# ---------------------------------------------------------------------------
# Case: implicit_leading_block
# Lines before any section header belong to an always-active pkg section.
# Per-line selectors still apply within that block.
# ---------------------------------------------------------------------------

@test "manifest case implicit_leading_block on ubuntu: universal plus apt-specific" {
  _seed_context "apt" "ubuntu" "debian" "22.04"
  _assert_manifest_pkgs "implicit_leading_block" "ubuntu"
}

@test "manifest case implicit_leading_block on debian: universal plus apt-specific" {
  _seed_context "apt" "debian" "" "12"
  _assert_manifest_pkgs "implicit_leading_block" "debian"
}

@test "manifest case implicit_leading_block on alpine: universal only" {
  _seed_context "apk" "alpine" "" "3.20"
  _assert_manifest_pkgs "implicit_leading_block" "alpine"
}

@test "manifest case implicit_leading_block on fedora: universal only" {
  _seed_context "dnf" "fedora" "" "40"
  _assert_manifest_pkgs "implicit_leading_block" "fedora"
}

@test "manifest case implicit_leading_block on opensuse-leap: universal only" {
  _seed_context "zypper" "opensuse-leap" "" "15.5"
  _assert_manifest_pkgs "implicit_leading_block" "opensuse-leap"
}

@test "manifest case implicit_leading_block on arch: universal only" {
  _seed_context "pacman" "arch" "" ""
  _assert_manifest_pkgs "implicit_leading_block" "arch"
}

# ---------------------------------------------------------------------------
# Case: key_section
# Dry-run mode must:
#   1. Resolve packages normally.
#   2. Log the key URL (without fetching it).
#   3. NOT create the key dest file.
# ---------------------------------------------------------------------------

@test "manifest case key_section on ubuntu: resolves packages, logs key, no file" {
  _seed_context "apt" "ubuntu" "debian" "22.04"

  run ospkg__run --manifest "$(cat "${CASES_DIR}/key_section/manifest.yaml")" --dry_run
  assert_success

  local _actual_pkgs
  _actual_pkgs="$(printf '%s\n' "${output}" |
    grep '\[dry-run\] packages' |
    sed 's/.*packages: //' |
    tr ' ' '\n' | sort | grep -v '^$' || true)"
  assert_equal "${_actual_pkgs}" "tree"

  assert_output --partial "[dry-run] key: https://example.com/signing.key"
  assert_not_exists /tmp/test-signing.key
}

@test "manifest case key_section on alpine: resolves packages, logs key, no file" {
  _seed_context "apk" "alpine" "" "3.20"

  run ospkg__run --manifest "$(cat "${CASES_DIR}/key_section/manifest.yaml")" --dry_run
  assert_success

  local _actual_pkgs
  _actual_pkgs="$(printf '%s\n' "${output}" |
    grep '\[dry-run\] packages' |
    sed 's/.*packages: //' |
    tr ' ' '\n' | sort | grep -v '^$' || true)"
  assert_equal "${_actual_pkgs}" "tree"

  assert_output --partial "[dry-run] key: https://example.com/signing.key"
  assert_not_exists /tmp/test-signing.key
}

@test "manifest case key_section on fedora: resolves packages, logs key, no file" {
  _seed_context "dnf" "fedora" "" "40"

  run ospkg__run --manifest "$(cat "${CASES_DIR}/key_section/manifest.yaml")" --dry_run
  assert_success

  local _actual_pkgs
  _actual_pkgs="$(printf '%s\n' "${output}" |
    grep '\[dry-run\] packages' |
    sed 's/.*packages: //' |
    tr ' ' '\n' | sort | grep -v '^$' || true)"
  assert_equal "${_actual_pkgs}" "tree"

  assert_output --partial "[dry-run] key: https://example.com/signing.key"
  assert_not_exists /tmp/test-signing.key
}

# ---------------------------------------------------------------------------
# Case: multi_pkg_sections
# Multiple pm-sections with same PM selector are accumulated.
# Platforms with no matching section (fedora/opensuse-leap) resolve 0 packages.
# ---------------------------------------------------------------------------

@test "manifest case multi_pkg_sections on ubuntu: apt packages only" {
  _seed_context "apt" "ubuntu" "debian" "22.04"
  _assert_manifest_pkgs "multi_pkg_sections" "ubuntu"
}

@test "manifest case multi_pkg_sections on debian: apt packages only" {
  _seed_context "apt" "debian" "" "12"
  _assert_manifest_pkgs "multi_pkg_sections" "debian"
}

@test "manifest case multi_pkg_sections on alpine: apk packages only" {
  _seed_context "apk" "alpine" "" "3.20"
  _assert_manifest_pkgs "multi_pkg_sections" "alpine"
}

@test "manifest case multi_pkg_sections on arch: pacman packages only" {
  _seed_context "pacman" "arch" "" ""
  _assert_manifest_pkgs "multi_pkg_sections" "arch"
}

@test "manifest case multi_pkg_sections on fedora: resolves 0 packages (no dnf section)" {
  _seed_context "dnf" "fedora" "" "40"
  _assert_manifest_pkgs "multi_pkg_sections" "fedora"
}

@test "manifest case multi_pkg_sections on opensuse-leap: resolves 0 packages (no zypper section)" {
  _seed_context "zypper" "opensuse-leap" "" "15.5"
  _assert_manifest_pkgs "multi_pkg_sections" "opensuse-leap"
}

# ---------------------------------------------------------------------------
# Case: nested_group_selectors
# Nested group objects inherit group-level when filters; inner packages still
# apply their own selectors. Platforms without apt/apk only get the ungrouped
# package.
# ---------------------------------------------------------------------------

@test "manifest case nested_group_selectors on ubuntu: group + apt-only-in-nested" {
  _seed_context "apt" "ubuntu" "debian" "22.04"
  _assert_manifest_pkgs "nested_group_selectors" "ubuntu"
}

@test "manifest case nested_group_selectors on debian: group + apt-only-in-nested" {
  _seed_context "apt" "debian" "" "12"
  _assert_manifest_pkgs "nested_group_selectors" "debian"
}

@test "manifest case nested_group_selectors on alpine: group + apk-only-in-nested" {
  _seed_context "apk" "alpine" "" "3.20"
  _assert_manifest_pkgs "nested_group_selectors" "alpine"
}

@test "manifest case nested_group_selectors on fedora: ungrouped package only" {
  _seed_context "dnf" "fedora" "" "40"
  _assert_manifest_pkgs "nested_group_selectors" "fedora"
}

@test "manifest case nested_group_selectors on opensuse-leap: ungrouped package only" {
  _seed_context "zypper" "opensuse-leap" "" "15.5"
  _assert_manifest_pkgs "nested_group_selectors" "opensuse-leap"
}

@test "manifest case nested_group_selectors on arch: ungrouped package only" {
  _seed_context "pacman" "arch" "" ""
  _assert_manifest_pkgs "nested_group_selectors" "arch"
}

# ---------------------------------------------------------------------------
# Case: or_selectors
# OR logic via array of condition objects [{pm:apt},{pm:apk}].
# Platforms without apt or apk resolve 0 packages.
# ---------------------------------------------------------------------------

@test "manifest case or_selectors on ubuntu: apt-only and apt-or-apk" {
  _seed_context "apt" "ubuntu" "debian" "22.04"
  _assert_manifest_pkgs "or_selectors" "ubuntu"
}

@test "manifest case or_selectors on debian: apt-only and apt-or-apk" {
  _seed_context "apt" "debian" "" "12"
  _assert_manifest_pkgs "or_selectors" "debian"
}

@test "manifest case or_selectors on alpine: apk-only and apt-or-apk" {
  _seed_context "apk" "alpine" "" "3.20"
  _assert_manifest_pkgs "or_selectors" "alpine"
}

@test "manifest case or_selectors on arch: resolves 0 packages (pacman has no match)" {
  _seed_context "pacman" "arch" "" ""
  _assert_manifest_pkgs "or_selectors" "arch"
}

@test "manifest case or_selectors on fedora: resolves 0 packages (dnf has no match)" {
  _seed_context "dnf" "fedora" "" "40"
  _assert_manifest_pkgs "or_selectors" "fedora"
}

@test "manifest case or_selectors on opensuse-leap: resolves 0 packages (zypper has no match)" {
  _seed_context "zypper" "opensuse-leap" "" "15.5"
  _assert_manifest_pkgs "or_selectors" "opensuse-leap"
}

# ---------------------------------------------------------------------------
# Case: pm_overrides
# packageObject PM override fields select the PM-specific name over 'name'.
# ---------------------------------------------------------------------------

@test "manifest case pm_overrides on ubuntu: selects pkg-apt" {
  _seed_context "apt" "ubuntu" "debian" "22.04"
  _assert_manifest_pkgs "pm_overrides" "ubuntu"
}

@test "manifest case pm_overrides on debian: selects pkg-apt" {
  _seed_context "apt" "debian" "" "12"
  _assert_manifest_pkgs "pm_overrides" "debian"
}

@test "manifest case pm_overrides on alpine: selects pkg-apk" {
  _seed_context "apk" "alpine" "" "3.20"
  _assert_manifest_pkgs "pm_overrides" "alpine"
}

@test "manifest case pm_overrides on fedora: selects pkg-dnf" {
  _seed_context "dnf" "fedora" "" "40"
  _assert_manifest_pkgs "pm_overrides" "fedora"
}

@test "manifest case pm_overrides on opensuse-leap: selects pkg-zypper" {
  _seed_context "zypper" "opensuse-leap" "" "15.5"
  _assert_manifest_pkgs "pm_overrides" "opensuse-leap"
}

@test "manifest case pm_overrides on arch: selects pkg-pacman" {
  _seed_context "pacman" "arch" "" ""
  _assert_manifest_pkgs "pm_overrides" "arch"
}

# ---------------------------------------------------------------------------
# Case: pm_selectors
# when: {plat.pm: X} installs only on package manager family X.
# Packages without a when clause are always installed.
# ---------------------------------------------------------------------------

@test "manifest case pm_selectors on ubuntu: always-installed + apt-only" {
  _seed_context "apt" "ubuntu" "debian" "22.04"
  _assert_manifest_pkgs "pm_selectors" "ubuntu"
}

@test "manifest case pm_selectors on debian: always-installed + apt-only" {
  _seed_context "apt" "debian" "" "12"
  _assert_manifest_pkgs "pm_selectors" "debian"
}

@test "manifest case pm_selectors on alpine: always-installed + apk-only" {
  _seed_context "apk" "alpine" "" "3.20"
  _assert_manifest_pkgs "pm_selectors" "alpine"
}

@test "manifest case pm_selectors on fedora: always-installed + dnf-only" {
  _seed_context "dnf" "fedora" "" "40"
  _assert_manifest_pkgs "pm_selectors" "fedora"
}

@test "manifest case pm_selectors on opensuse-leap: always-installed + zypper-only" {
  _seed_context "zypper" "opensuse-leap" "" "15.5"
  _assert_manifest_pkgs "pm_selectors" "opensuse-leap"
}

@test "manifest case pm_selectors on arch: always-installed + pacman-only" {
  _seed_context "pacman" "arch" "" ""
  _assert_manifest_pkgs "pm_selectors" "arch"
}

# ---------------------------------------------------------------------------
# Case: section_selectors
# PM-specific blocks (apt:, apk:, dnf:, zypper:, pacman:) restrict packages.
# The top-level packages: block is always active on all PMs.
# ---------------------------------------------------------------------------

@test "manifest case section_selectors on ubuntu: always-installed + apt section" {
  _seed_context "apt" "ubuntu" "debian" "22.04"
  _assert_manifest_pkgs "section_selectors" "ubuntu"
}

@test "manifest case section_selectors on debian: always-installed + apt section" {
  _seed_context "apt" "debian" "" "12"
  _assert_manifest_pkgs "section_selectors" "debian"
}

@test "manifest case section_selectors on alpine: always-installed + apk section" {
  _seed_context "apk" "alpine" "" "3.20"
  _assert_manifest_pkgs "section_selectors" "alpine"
}

@test "manifest case section_selectors on fedora: always-installed + dnf section" {
  _seed_context "dnf" "fedora" "" "40"
  _assert_manifest_pkgs "section_selectors" "fedora"
}

@test "manifest case section_selectors on opensuse-leap: always-installed + zypper section" {
  _seed_context "zypper" "opensuse-leap" "" "15.5"
  _assert_manifest_pkgs "section_selectors" "opensuse-leap"
}

@test "manifest case section_selectors on arch: always-installed + pacman section" {
  _seed_context "pacman" "arch" "" ""
  _assert_manifest_pkgs "section_selectors" "arch"
}

# ---------------------------------------------------------------------------
# Case: version_selectors
# version_id= selector matches only on specific OS release versions.
# ubuntu 24.04 gets ubuntu2404-pkg; debian 13 gets debian13-pkg; others get
# only the unconditional package.
# ---------------------------------------------------------------------------

@test "manifest case version_selectors on ubuntu 24.04: always + ubuntu2404-pkg" {
  _seed_context "apt" "ubuntu" "debian" "24.04"
  _assert_manifest_pkgs "version_selectors" "ubuntu"
}

@test "manifest case version_selectors on debian 13: always + debian13-pkg" {
  _seed_context "apt" "debian" "" "13"
  _assert_manifest_pkgs "version_selectors" "debian"
}

@test "manifest case version_selectors on alpine: always only (no version match)" {
  _seed_context "apk" "alpine" "" "3.20"
  _assert_manifest_pkgs "version_selectors" "alpine"
}

@test "manifest case version_selectors on fedora: always only (no version match)" {
  _seed_context "dnf" "fedora" "" "40"
  _assert_manifest_pkgs "version_selectors" "fedora"
}

@test "manifest case version_selectors on opensuse-leap: always only (no version match)" {
  _seed_context "zypper" "opensuse-leap" "" "15.5"
  _assert_manifest_pkgs "version_selectors" "opensuse-leap"
}

@test "manifest case version_selectors on arch: always only (no version match)" {
  _seed_context "pacman" "arch" "" ""
  _assert_manifest_pkgs "version_selectors" "arch"
}

# ---------------------------------------------------------------------------
# Semver and feat-context when clauses (jq cond_matches parity)
# ---------------------------------------------------------------------------

@test "manifest feat.version lte: package included when ctx matches" {
  _seed_context "apt" "ubuntu" "debian" "22.04"
  ctx__set feat.version=12.1.2
  local _manifest=$'packages:\n  - name: old-tool\n    when:\n      feat.version:\n        lte: "12.1.2"'
  local _json_tmp _parsed
  _json_tmp="$(mktemp "${BATS_TEST_TMPDIR}/semver_XXXXXX")"
  printf '%s' "${_manifest}" | "${DEVFEATS_TEST_YQ_BIN}" -o=json '.' - > "${_json_tmp}"
  _parsed="$(ospkg__parse_manifest_yaml "${_json_tmp}")"
  rm -f "${_json_tmp}"
  [[ "${_parsed}" == *"old-tool"* ]]
}

@test "manifest feat.version lte: package excluded when ctx too high" {
  _seed_context "apt" "ubuntu" "debian" "22.04"
  ctx__set feat.version=14.0.0
  local _manifest=$'packages:\n  - name: old-tool\n    when:\n      feat.version:\n        lte: "12.1.2"'
  local _json_tmp _parsed
  _json_tmp="$(mktemp "${BATS_TEST_TMPDIR}/semver_XXXXXX")"
  printf '%s' "${_manifest}" | "${DEVFEATS_TEST_YQ_BIN}" -o=json '.' - > "${_json_tmp}"
  _parsed="$(ospkg__parse_manifest_yaml "${_json_tmp}")"
  rm -f "${_json_tmp}"
  [[ "${_parsed}" != *"old-tool"* ]]
}

@test "manifest feat.version lte: ospkg__run uses feat.version from ctx registry" {
  _seed_context "apt" "ubuntu" "debian" "22.04"
  ctx__set feat.version=12.1.2
  local _manifest=$'packages:\n  - name: old-tool\n    when:\n      feat.version:\n        lte: "12.1.2"'
  run ospkg__run --manifest "${_manifest}" --dry_run
  assert_success
  assert_output --partial "old-tool"
}

# ---------------------------------------------------------------------------
# Qualified YAML when keys in manifests (ctx refactor regression suite)
# ---------------------------------------------------------------------------

@test "manifest when os.id: package included on matching distro" {
  _seed_context "apt" "ubuntu" "debian" "22.04"
  local _manifest=$'packages:\n  - name: ubuntu-pkg\n    when:\n      os.id: ubuntu\n  - name: always'
  local _json_tmp _parsed
  _json_tmp="$(mktemp "${BATS_TEST_TMPDIR}/osid_XXXXXX")"
  printf '%s' "${_manifest}" | "${DEVFEATS_TEST_YQ_BIN}" -o=json '.' - > "${_json_tmp}"
  _parsed="$(ospkg__parse_manifest_yaml "${_json_tmp}")"
  rm -f "${_json_tmp}"
  [[ "${_parsed}" == *"ubuntu-pkg"* ]]
  [[ "${_parsed}" == *"always"* ]]
}

@test "manifest when os.id: package excluded on non-matching distro" {
  _seed_context "apt" "debian" "" "12"
  local _manifest=$'packages:\n  - name: ubuntu-pkg\n    when:\n      os.id: ubuntu\n  - name: always'
  local _json_tmp _parsed
  _json_tmp="$(mktemp "${BATS_TEST_TMPDIR}/osid_XXXXXX")"
  printf '%s' "${_manifest}" | "${DEVFEATS_TEST_YQ_BIN}" -o=json '.' - > "${_json_tmp}"
  _parsed="$(ospkg__parse_manifest_yaml "${_json_tmp}")"
  rm -f "${_json_tmp}"
  [[ "${_parsed}" != *"ubuntu-pkg"* ]]
  [[ "${_parsed}" == *"always"* ]]
}

@test "manifest when os.version_codename: package included on matching codename" {
  _seed_context "apt" "ubuntu" "debian" "22.04"
  ctx__set os.version_codename=jammy
  local _manifest=$'packages:\n  - name: jammy-pkg\n    when:\n      os.version_codename: [jammy, noble]\n  - name: always'
  local _json_tmp _parsed
  _json_tmp="$(mktemp "${BATS_TEST_TMPDIR}/codename_XXXXXX")"
  printf '%s' "${_manifest}" | "${DEVFEATS_TEST_YQ_BIN}" -o=json '.' - > "${_json_tmp}"
  _parsed="$(ospkg__parse_manifest_yaml "${_json_tmp}")"
  rm -f "${_json_tmp}"
  [[ "${_parsed}" == *"jammy-pkg"* ]]
}

@test "manifest when os.version_codename: package excluded on non-matching codename" {
  _seed_context "apt" "ubuntu" "debian" "22.04"
  ctx__set os.version_codename=focal
  local _manifest=$'packages:\n  - name: jammy-pkg\n    when:\n      os.version_codename: [jammy, noble]'
  local _json_tmp _parsed
  _json_tmp="$(mktemp "${BATS_TEST_TMPDIR}/codename_XXXXXX")"
  printf '%s' "${_manifest}" | "${DEVFEATS_TEST_YQ_BIN}" -o=json '.' - > "${_json_tmp}"
  _parsed="$(ospkg__parse_manifest_yaml "${_json_tmp}")"
  rm -f "${_json_tmp}"
  [[ "${_parsed}" != *"jammy-pkg"* ]]
}

@test "manifest when plat.pm: package included on matching PM" {
  _seed_context "apt" "ubuntu" "debian" "22.04"
  local _manifest=$'packages:\n  - name: apt-pkg\n    when:\n      plat.pm: apt'
  local _json_tmp _parsed
  _json_tmp="$(mktemp "${BATS_TEST_TMPDIR}/pm_XXXXXX")"
  printf '%s' "${_manifest}" | "${DEVFEATS_TEST_YQ_BIN}" -o=json '.' - > "${_json_tmp}"
  _parsed="$(ospkg__parse_manifest_yaml "${_json_tmp}")"
  rm -f "${_json_tmp}"
  [[ "${_parsed}" == *"apt-pkg"* ]]
}

@test "manifest when plat.pm: package excluded on non-matching PM" {
  _seed_context "apk" "alpine" "" "3.20"
  local _manifest=$'packages:\n  - name: apt-pkg\n    when:\n      plat.pm: apt'
  local _json_tmp _parsed
  _json_tmp="$(mktemp "${BATS_TEST_TMPDIR}/pm_XXXXXX")"
  printf '%s' "${_manifest}" | "${DEVFEATS_TEST_YQ_BIN}" -o=json '.' - > "${_json_tmp}"
  _parsed="$(ospkg__parse_manifest_yaml "${_json_tmp}")"
  rm -f "${_json_tmp}"
  [[ "${_parsed}" != *"apt-pkg"* ]]
}

@test "manifest when feat.version operator dict: package included when version matches" {
  _seed_context "apt" "ubuntu" "debian" "22.04"
  ctx__set feat.version=12.1.2
  local _manifest=$'packages:\n  - name: old-pkg\n    when:\n      feat.version:\n        gte: "10.0.0"\n        lte: "12.1.2"'
  local _json_tmp _parsed
  _json_tmp="$(mktemp "${BATS_TEST_TMPDIR}/fver_XXXXXX")"
  printf '%s' "${_manifest}" | "${DEVFEATS_TEST_YQ_BIN}" -o=json '.' - > "${_json_tmp}"
  _parsed="$(ospkg__parse_manifest_yaml "${_json_tmp}")"
  rm -f "${_json_tmp}"
  [[ "${_parsed}" == *"old-pkg"* ]]
}
