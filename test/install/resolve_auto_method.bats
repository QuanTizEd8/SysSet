#!/usr/bin/env bats
# Unit tests for __resolve_auto_method__() in the install framework (install.tmpl.bash).
#
# The synced install.bash fixture is sourced without __main__ in setup_file.
# OS lib functions are loaded via helpers/common; ctx is seeded per-test via
# _stub() so no real OS detection is needed.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/ensure_framework'
  install_test__ensure_framework
  load 'helpers/test_tools'
  test_tools__wire_jq_yq
  load 'helpers/stubs'
  load 'helpers/ctx'
  load 'helpers/capture'

  # Default contract: empty (no methods).
  _FEAT_CONTRACT_METHODS=""
  _FEAT_CONTRACT_BINARY_WHEN=""
  _FEAT_CONTRACT_PACKAGE_WHEN=""
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN=""
  _FEAT_CONTRACT_PRIMARY_BIN=""
  REGISTER_PACKAGE_NAME=""
  BINARY_ASSET_URI=""
  VERSION="stable"
  VERSION_RESOLUTION=""
  _OSPKG__FAMILY=""
  _OSPKG__DETECTED=false

  # Default stubs: Linux/amd64/apt/privileged/debian.
  _stub linux amd64 apt privileged debian
}

# ──────────────────────────────────────────────────────────────────────────────
# Stub helpers
# ──────────────────────────────────────────────────────────────────────────────

# _stub <kernel> <arch> <pm> <privileged|unprivileged> [<platform/os-id>]
#
# Stores stub values in _STUB_* globals and seeds the ctx registry so
# ctx__match_when (used by __resolve_auto_method__) sees deterministic values.
_stub() {
  _STUB_KERNEL="${1:-linux}"
  _STUB_ARCH="${2:-amd64}"
  _STUB_PM="${3:-apt}"
  _STUB_PRIV="${4:-privileged}"
  _STUB_PLATFORM="${5:-debian}"

  os__release_kernel() { printf '%s\n' "${_STUB_KERNEL}"; }
  os__release_arch() { printf '%s\n' "${_STUB_ARCH}"; }
  os__platform() { printf '%s\n' "${_STUB_PLATFORM}"; }
  os__rust_triple() { return 1; } # no triple by default
  ctx__reset
  ctx__set "plat.kernel=${_STUB_KERNEL}"
  ctx__set "plat.machine_release=${_STUB_ARCH}"
  ctx__set "plat.pm=${_STUB_PM}"
  ctx__set "os.id=${_STUB_PLATFORM}"
  _CTX__REGISTRY_INITIALIZED=true
  ospkg__has_available_version() { return 0; }
  logging__error() { printf 'ERROR: %s\n' "$*" >&2; }
  logging__debug() { :; }

  if [[ "${_STUB_PRIV}" == "privileged" ]]; then
    users__is_privileged() { return 0; }
  else
    users__is_privileged() { return 1; }
  fi
  export -f os__release_kernel os__release_arch os__platform os__rust_triple
  export -f ospkg__has_available_version logging__error logging__debug
  export -f users__is_privileged
}

run_auto_method() {
  local _preserve_input=false _saved_input=""
  if [[ -v VERSION_INPUT ]]; then
    _preserve_input=true
    _saved_input="${VERSION_INPUT}"
  fi
  install_test__capture_version_input
  if [[ "${_preserve_input}" == true ]]; then
    declare -g VERSION_INPUT="${_saved_input}"
  fi
  __ctx_sync_version__
  __ctx_sync_method__
  run __resolve_auto_method__
}

# ──────────────────────────────────────────────────────────────────────────────
# binary — arch constraint via when
# ──────────────────────────────────────────────────────────────────────────────

@test "binary: selected when arch matches when condition" {
  _FEAT_CONTRACT_METHODS="binary package"
  _FEAT_CONTRACT_BINARY_WHEN=$'plat.machine_release:\n- amd64\n- arm64'
  run_auto_method
  assert_success
  assert_output "binary"
}

@test "binary: skipped when arch not in when condition" {
  _FEAT_CONTRACT_METHODS="binary package"
  _FEAT_CONTRACT_BINARY_WHEN=$'plat.machine_release:\n- amd64\n- arm64'
  _stub linux armv7 apt privileged
  run_auto_method
  assert_success
  assert_output "package"
}

@test "binary: skipped when feat.version lte constraint fails" {
  _FEAT_CONTRACT_METHODS="binary cargo"
  _FEAT_CONTRACT_BINARY_WHEN=$'plat.machine_release: amd64\nfeat.version:\n  lte: "12.1.2"'
  VERSION=14.0.0
  create_fake_bin cargo
  prepend_fake_bin_path
  run_auto_method
  assert_success
  assert_output "cargo"
}

@test "binary: selected when feat.version lte constraint passes" {
  _FEAT_CONTRACT_METHODS="binary cargo"
  _FEAT_CONTRACT_BINARY_WHEN=$'plat.machine_release: amd64\nfeat.version:\n  lte: "12.1.2"'
  VERSION=12.1.2
  create_fake_bin cargo
  run_auto_method
  assert_success
  assert_output "binary"
}

@test "binary: selected when kernel:arch matches when condition (array form)" {
  _FEAT_CONTRACT_METHODS="binary package"
  _FEAT_CONTRACT_BINARY_WHEN=$'- plat.kernel: linux\n  plat.machine_release: amd64\n- plat.kernel: linux\n  plat.machine_release: arm64\n- plat.kernel: darwin\n  plat.machine_release: amd64\n- plat.kernel: darwin\n  plat.machine_release: arm64'
  run_auto_method
  assert_success
  assert_output "binary"
}

@test "binary: skipped when kernel:arch not in when condition (array form)" {
  _FEAT_CONTRACT_METHODS="binary package"
  _FEAT_CONTRACT_BINARY_WHEN=$'- plat.kernel: linux\n  plat.machine_release: amd64\n- plat.kernel: linux\n  plat.machine_release: arm64\n- plat.kernel: darwin\n  plat.machine_release: amd64'
  _stub darwin arm64 brew privileged macos
  run_auto_method
  assert_success
  assert_output "package"
}

@test "binary: selected with no when condition (unconstrained)" {
  _FEAT_CONTRACT_METHODS="binary"
  # No when, no plat.rust_triple in URI → always feasible
  run_auto_method
  assert_success
  assert_output "binary"
}

# ──────────────────────────────────────────────────────────────────────────────
# binary — plat.rust_triple fallback (independent of when)
# ──────────────────────────────────────────────────────────────────────────────

@test "binary: selected via plat.rust_triple when no when declared" {
  _FEAT_CONTRACT_METHODS="binary script"
  BINARY_ASSET_URI="https://example.com/tool-{plat.rust_triple}.tar.gz"
  os__rust_triple() { printf 'x86_64-unknown-linux-musl\n'; }
  run_auto_method
  assert_success
  assert_output "binary"
}

@test "binary: skipped via plat.rust_triple when triple unavailable" {
  _FEAT_CONTRACT_METHODS="binary script"
  BINARY_ASSET_URI="https://example.com/tool-{plat.rust_triple}.tar.gz"
  # os__rust_triple returns failure by default in _stub
  run_auto_method
  assert_success
  assert_output "script"
}

# ──────────────────────────────────────────────────────────────────────────────
# upstream-package
# ──────────────────────────────────────────────────────────────────────────────

@test "upstream-package: selected when PM matches when condition and VERSION=stable" {
  _FEAT_CONTRACT_METHODS="upstream-package script"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN=$'plat.pm:\n- apt\n- dnf'
  run_auto_method
  assert_success
  assert_output "upstream-package"
}

@test "upstream-package: skipped when PM not in when condition" {
  _FEAT_CONTRACT_METHODS="upstream-package script"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN=$'plat.pm:\n- apt\n- dnf'
  _stub linux amd64 apk privileged
  run_auto_method
  assert_success
  assert_output "script"
}

@test "upstream-package: skipped for VERSION=latest" {
  _FEAT_CONTRACT_METHODS="upstream-package script"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN='plat.pm: apt'
  VERSION="latest"
  run_auto_method
  assert_success
  assert_output "script"
}

@test "upstream-package: skipped for specific VERSION" {
  _FEAT_CONTRACT_METHODS="upstream-package script"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN='plat.pm: apt'
  VERSION="1.2.3"
  run_auto_method
  assert_success
  assert_output "script"
}

@test "upstream-package: selected when VERSION resolved but VERSION_INPUT=stable" {
  _FEAT_CONTRACT_METHODS="upstream-package script"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN='plat.pm: apt'
  VERSION="2.47.0"
  VERSION_INPUT="stable"
  run_auto_method
  assert_success
  assert_output "upstream-package"
}

@test "upstream-package: skipped for VERSION_INPUT=latest after VERSION resolved" {
  _FEAT_CONTRACT_METHODS="upstream-package script"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN='plat.pm: apt'
  VERSION="2.47.0"
  VERSION_INPUT="latest"
  run_auto_method
  assert_success
  assert_output "script"
}

@test "upstream-package: skipped on linux when not privileged" {
  _FEAT_CONTRACT_METHODS="upstream-package script"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN='plat.pm: apt'
  _stub linux amd64 apt unprivileged
  run_auto_method
  assert_success
  assert_output "script"
}

@test "upstream-package: selected on macOS without privilege" {
  _FEAT_CONTRACT_METHODS="upstream-package script"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN='plat.pm: brew'
  _stub darwin arm64 brew unprivileged
  run_auto_method
  assert_success
  assert_output "upstream-package"
}

@test "upstream-package: selected with no when condition (all PMs)" {
  _FEAT_CONTRACT_METHODS="upstream-package script"
  _stub linux amd64 apk privileged
  run_auto_method
  assert_success
  assert_output "upstream-package"
}

@test "upstream-package when: selected on Ubuntu (id=ubuntu matches)" {
  _FEAT_CONTRACT_METHODS="upstream-package package"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN='os.id: ubuntu'
  _stub linux amd64 apt privileged ubuntu
  run_auto_method
  assert_success
  assert_output "upstream-package"
}

@test "upstream-package when: skipped on Debian even though PM=apt" {
  _FEAT_CONTRACT_METHODS="upstream-package package"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN='os.id: ubuntu'
  _stub linux amd64 apt privileged debian
  run_auto_method
  assert_success
  assert_output "package"
}

# ──────────────────────────────────────────────────────────────────────────────
# package
# ──────────────────────────────────────────────────────────────────────────────

@test "package: selected when PM matches when condition and VERSION=stable" {
  _FEAT_CONTRACT_METHODS="package"
  _FEAT_CONTRACT_PACKAGE_WHEN=$'plat.pm:\n- apt\n- brew'
  run_auto_method
  assert_success
  assert_output "package"
}

@test "package: skipped when PM not in when condition" {
  _FEAT_CONTRACT_METHODS="package script"
  _FEAT_CONTRACT_PACKAGE_WHEN=$'plat.pm:\n- apt\n- brew'
  _stub linux amd64 apk privileged
  run_auto_method
  assert_success
  assert_output "script"
}

@test "package: selected with no when condition (all PMs)" {
  _FEAT_CONTRACT_METHODS="package"
  _stub linux amd64 apk privileged
  run_auto_method
  assert_success
  assert_output "package"
}

@test "package: skipped for VERSION=latest" {
  _FEAT_CONTRACT_METHODS="package script"
  _FEAT_CONTRACT_PACKAGE_WHEN='plat.pm: apt'
  VERSION="latest"
  run_auto_method
  assert_success
  assert_output "script"
}

@test "package: selected for specific version when PM has it" {
  _FEAT_CONTRACT_METHODS="package script"
  _FEAT_CONTRACT_PACKAGE_WHEN='plat.pm: apt'
  _FEAT_CONTRACT_PRIMARY_BIN="mytool"
  VERSION="2.3.0"
  ospkg__has_available_version() { return 0; }
  run_auto_method
  assert_success
  assert_output "package"
}

@test "package: skipped for specific version when PM lacks it" {
  _FEAT_CONTRACT_METHODS="package script"
  _FEAT_CONTRACT_PACKAGE_WHEN='plat.pm: apt'
  _FEAT_CONTRACT_PRIMARY_BIN="mytool"
  VERSION="9.9.9"
  ospkg__has_available_version() { return 1; }
  run_auto_method
  assert_success
  assert_output "script"
}

@test "package: feasibility uses pm spec for opaque dist-tag after resolve" {
  _FEAT_CONTRACT_METHODS="package script"
  _FEAT_CONTRACT_PACKAGE_WHEN='plat.pm: apt'
  _FEAT_CONTRACT_PRIMARY_BIN="claude-code"
  VERSION="2.0.0-beta.1"
  VERSION_INPUT="beta"
  ospkg__has_available_version() {
    [[ "$1" == "claude-code" && "$2" == "2.0.0-beta.1" ]]
  }
  export -f ospkg__has_available_version
  run_auto_method
  assert_success
  assert_output "package"
}

@test "package: uses REGISTER_PACKAGE_NAME for version check when set" {
  _FEAT_CONTRACT_METHODS="package script"
  _FEAT_CONTRACT_PACKAGE_WHEN='plat.pm: apt'
  _FEAT_CONTRACT_PRIMARY_BIN="rg"
  REGISTER_PACKAGE_NAME="ripgrep"
  VERSION="15.1.0"
  ospkg__has_available_version() {
    [[ "$1" == "ripgrep" && "$2" == "15.1.0" ]]
  }
  run_auto_method
  assert_success
  assert_output "package"
}

@test "package: REGISTER_PACKAGE_NAME beats PRIMARY_BIN when PM lacks version" {
  _FEAT_CONTRACT_METHODS="package script"
  _FEAT_CONTRACT_PACKAGE_WHEN='plat.pm: apt'
  _FEAT_CONTRACT_PRIMARY_BIN="rg"
  REGISTER_PACKAGE_NAME="ripgrep"
  VERSION="15.1.0"
  ospkg__has_available_version() {
    [[ "$1" == "ripgrep" ]] || return 0
    return 1
  }
  run_auto_method
  assert_success
  assert_output "script"
}

@test "package: falls back to PRIMARY_BIN when REGISTER_PACKAGE_NAME unset" {
  _FEAT_CONTRACT_METHODS="package script"
  _FEAT_CONTRACT_PACKAGE_WHEN='plat.pm: apt'
  _FEAT_CONTRACT_PRIMARY_BIN="jq"
  VERSION="1.8.1"
  ospkg__has_available_version() {
    [[ "$1" == "jq" && "$2" == "1.8.1" ]]
  }
  run_auto_method
  assert_success
  assert_output "package"
}

@test "package: skipped on linux when not privileged" {
  _FEAT_CONTRACT_METHODS="package source"
  _FEAT_CONTRACT_PACKAGE_WHEN='plat.pm: apt'
  _stub linux amd64 apt unprivileged
  run_auto_method
  assert_success
  assert_output "source"
}

@test "package: selected on macOS without privilege" {
  _FEAT_CONTRACT_METHODS="package"
  _FEAT_CONTRACT_PACKAGE_WHEN='plat.pm: brew'
  _stub darwin arm64 brew unprivileged
  run_auto_method
  assert_success
  assert_output "package"
}

# ──────────────────────────────────────────────────────────────────────────────
# script / source — always feasible
# ──────────────────────────────────────────────────────────────────────────────

@test "script: always selected when in methods list" {
  _FEAT_CONTRACT_METHODS="script"
  run_auto_method
  assert_success
  assert_output "script"
}

@test "source: always selected when in methods list" {
  _FEAT_CONTRACT_METHODS="source"
  run_auto_method
  assert_success
  assert_output "source"
}

# ──────────────────────────────────────────────────────────────────────────────
# npm-bundled
# ──────────────────────────────────────────────────────────────────────────────

@test "npm-bundled: selected on linux/amd64 non-alpine" {
  _FEAT_CONTRACT_METHODS="npm-bundled"
  _stub linux amd64 apt privileged debian
  run_auto_method
  assert_success
  assert_output "npm-bundled"
}

@test "npm-bundled: skipped on alpine, falls through to npm" {
  _FEAT_CONTRACT_METHODS="npm-bundled npm"
  _stub linux amd64 apk privileged alpine
  create_fake_bin npm
  prepend_fake_bin_path
  run_auto_method
  assert_success
  assert_output "npm"
}

@test "npm-bundled: skipped on unsupported arch (armv7), falls through to npm" {
  _FEAT_CONTRACT_METHODS="npm-bundled npm"
  _stub linux armv7 apt privileged debian
  create_fake_bin npm
  prepend_fake_bin_path
  run_auto_method
  assert_success
  assert_output "npm"
}

@test "npm-bundled: selected on darwin/arm64" {
  _FEAT_CONTRACT_METHODS="npm-bundled"
  _stub darwin arm64 brew privileged macos
  run_auto_method
  assert_success
  assert_output "npm-bundled"
}

# ──────────────────────────────────────────────────────────────────────────────
# npm / cargo / git-clone — command availability
# ──────────────────────────────────────────────────────────────────────────────

@test "npm: selected when npm is on PATH" {
  _FEAT_CONTRACT_METHODS="npm"
  create_fake_bin npm
  prepend_fake_bin_path
  run_auto_method
  assert_success
  assert_output "npm"
}

@test "npm: skipped when npm not on PATH" {
  _FEAT_CONTRACT_METHODS="npm source"
  begin_path_isolation
  run_auto_method
  end_path_isolation
  assert_success
  assert_output "source"
}

@test "cargo: selected when cargo is on PATH" {
  _FEAT_CONTRACT_METHODS="cargo"
  create_fake_bin cargo
  prepend_fake_bin_path
  run_auto_method
  assert_success
  assert_output "cargo"
}

@test "cargo: skipped when cargo not on PATH" {
  _FEAT_CONTRACT_METHODS="cargo source"
  begin_path_isolation
  run_auto_method
  end_path_isolation
  assert_success
  assert_output "source"
}

@test "git-clone: selected when git is on PATH" {
  _FEAT_CONTRACT_METHODS="git-clone"
  create_fake_bin git
  prepend_fake_bin_path
  run_auto_method
  assert_success
  assert_output "git-clone"
}

@test "git-clone: skipped when git not on PATH" {
  _FEAT_CONTRACT_METHODS="git-clone source"
  begin_path_isolation
  run_auto_method
  end_path_isolation
  assert_success
  assert_output "source"
}

# ──────────────────────────────────────────────────────────────────────────────
# Priority order
# ──────────────────────────────────────────────────────────────────────────────

@test "priority: binary beats package when both feasible" {
  _FEAT_CONTRACT_METHODS="binary package"
  _FEAT_CONTRACT_BINARY_WHEN='plat.machine_release: amd64'
  _FEAT_CONTRACT_PACKAGE_WHEN='plat.pm: apt'
  run_auto_method
  assert_success
  assert_output "binary"
}

@test "priority: upstream-package beats package when both feasible" {
  _FEAT_CONTRACT_METHODS="upstream-package package"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN='plat.pm: apt'
  _FEAT_CONTRACT_PACKAGE_WHEN='plat.pm: apt'
  run_auto_method
  assert_success
  assert_output "upstream-package"
}

@test "priority: package beats script when both feasible" {
  _FEAT_CONTRACT_METHODS="package script"
  _FEAT_CONTRACT_PACKAGE_WHEN='plat.pm: apt'
  run_auto_method
  assert_success
  assert_output "package"
}

@test "priority: falls through to script when binary arch unsupported" {
  _FEAT_CONTRACT_METHODS="binary script"
  _FEAT_CONTRACT_BINARY_WHEN=$'plat.machine_release:\n- amd64\n- arm64'
  _stub linux ppc64le apt privileged
  run_auto_method
  assert_success
  assert_output "script"
}

# ──────────────────────────────────────────────────────────────────────────────
# Error cases
# ──────────────────────────────────────────────────────────────────────────────

@test "error: returns 1 when no feasible method found" {
  _FEAT_CONTRACT_METHODS="binary"
  _FEAT_CONTRACT_BINARY_WHEN='plat.machine_release: arm64' # current arch is amd64
  run_auto_method
  assert_failure
}

@test "error: returns 1 with empty methods contract" {
  _FEAT_CONTRACT_METHODS=""
  run_auto_method
  assert_failure
}

# ──────────────────────────────────────────────────────────────────────────────
# VERSION_RESOLUTION=none bypasses version-based skipping
# ──────────────────────────────────────────────────────────────────────────────

@test "package: VERSION=latest with VERSION_RESOLUTION=none → selected (not skipped)" {
  _FEAT_CONTRACT_METHODS="package"
  _FEAT_CONTRACT_PACKAGE_WHEN='plat.pm: apk'
  _stub linux amd64 apk privileged alpine
  VERSION="latest"
  VERSION_RESOLUTION="none"
  run_auto_method
  assert_success
  assert_output "package"
}

@test "package: VERSION=2024 with VERSION_RESOLUTION=none → selected (no ospkg check)" {
  _FEAT_CONTRACT_METHODS="package"
  _FEAT_CONTRACT_PACKAGE_WHEN='plat.pm: apk'
  _stub linux amd64 apk privileged alpine
  VERSION="2024"
  VERSION_RESOLUTION="none"
  ospkg__has_available_version() { return 1; } # would reject if called
  run_auto_method
  assert_success
  assert_output "package"
}

@test "upstream-package: VERSION=latest with VERSION_RESOLUTION=none → selected" {
  _FEAT_CONTRACT_METHODS="upstream-package script"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN='plat.pm: apk'
  _stub linux amd64 apk privileged alpine
  VERSION="latest"
  VERSION_RESOLUTION="none"
  run_auto_method
  assert_success
  assert_output "upstream-package"
}

@test "package: VERSION=latest without VERSION_RESOLUTION=none → still skipped" {
  _FEAT_CONTRACT_METHODS="package script"
  _FEAT_CONTRACT_PACKAGE_WHEN='plat.pm: apk'
  _stub linux amd64 apk privileged alpine
  VERSION="latest"
  # VERSION_RESOLUTION unset / empty
  run_auto_method
  assert_success
  assert_output "script"
}

# ──────────────────────────────────────────────────────────────────────────────
# Realistic feature scenarios
# ──────────────────────────────────────────────────────────────────────────────

@test "scenario: install-fzf on amd64 linux → binary" {
  _FEAT_CONTRACT_METHODS="binary package"
  _FEAT_CONTRACT_BINARY_WHEN=$'plat.machine_release:\n- amd64\n- arm64\n- armv7\n- armv6\n- armv5\n- ppc64le\n- riscv64\n- s390x\n- loong64'
  run_auto_method
  assert_success
  assert_output "binary"
}

@test "scenario: install-shellcheck on darwin:arm64 → package (no darwin:arm64 binary)" {
  _FEAT_CONTRACT_METHODS="binary package script"
  _FEAT_CONTRACT_BINARY_WHEN=$'- plat.kernel: linux\n  plat.machine_release: amd64\n- plat.kernel: linux\n  plat.machine_release: arm64\n- plat.kernel: darwin\n  plat.machine_release: amd64'
  _stub darwin arm64 brew privileged macos
  run_auto_method
  assert_success
  assert_output "package"
}

@test "scenario: install-yq on amd64 linux with apt → binary (apt excluded from package)" {
  _FEAT_CONTRACT_METHODS="binary package script"
  _FEAT_CONTRACT_BINARY_WHEN=$'plat.machine_release:\n- amd64\n- arm64'
  _FEAT_CONTRACT_PACKAGE_WHEN=$'plat.pm:\n- dnf\n- apk\n- zypper\n- brew\n- pacman'
  # apt (default stub) is not in package when → package skipped; binary wins
  run_auto_method
  assert_success
  assert_output "binary"
}

@test "scenario: install-yq on i386 privileged apt → script (no binary, apt excluded)" {
  _FEAT_CONTRACT_METHODS="binary package script"
  _FEAT_CONTRACT_BINARY_WHEN=$'plat.machine_release:\n- amd64\n- arm64'
  _FEAT_CONTRACT_PACKAGE_WHEN=$'plat.pm:\n- dnf\n- apk\n- zypper\n- brew\n- pacman'
  _stub linux i386 apt privileged
  run_auto_method
  assert_success
  assert_output "script"
}

@test "scenario: install-uv on dnf privileged → package" {
  _FEAT_CONTRACT_METHODS="binary package script"
  BINARY_ASSET_URI="https://example.com/uv-{plat.rust_triple}.tar.gz"
  _FEAT_CONTRACT_PACKAGE_WHEN=$'plat.pm:\n- brew\n- dnf\n- apk\n- pacman\n- zypper'
  _stub linux amd64 dnf privileged
  # Ensure rust triple is unavailable on this stub (no binary)
  os__rust_triple() { return 1; }
  run_auto_method
  assert_success
  assert_output "package"
}

@test "scenario: install-claude on armv7 unprivileged → npm (no binary, no pkg priv)" {
  _FEAT_CONTRACT_METHODS="binary upstream-package npm-bundled npm"
  _FEAT_CONTRACT_BINARY_WHEN=$'plat.machine_release:\n- amd64\n- arm64'
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN=$'plat.pm:\n- apt\n- dnf\n- apk\n- brew'
  _stub linux armv7 apt unprivileged debian
  create_fake_bin npm
  prepend_fake_bin_path
  run_auto_method
  assert_success
  assert_output "npm"
}

@test "scenario: install-git on Ubuntu/apt privileged → upstream-package (Ubuntu PPA)" {
  _FEAT_CONTRACT_METHODS="upstream-package package source"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN='os.id: ubuntu'
  _stub linux amd64 apt privileged ubuntu
  run_auto_method
  assert_success
  assert_output "upstream-package"
}

@test "scenario: install-git on Debian/apt privileged → package (no Ubuntu PPA)" {
  _FEAT_CONTRACT_METHODS="upstream-package package source"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN='os.id: ubuntu'
  _stub linux amd64 apt privileged debian
  run_auto_method
  assert_success
  assert_output "package"
}

@test "scenario: install-git on Alpine/apk privileged → package (native apk)" {
  _FEAT_CONTRACT_METHODS="upstream-package package source"
  _FEAT_CONTRACT_UPSTREAM_PKG_WHEN='os.id: ubuntu'
  _stub linux amd64 apk privileged alpine
  run_auto_method
  assert_success
  assert_output "package"
}

@test "scenario: install-texlive (VERSION_RESOLUTION=none) on Alpine → package" {
  _FEAT_CONTRACT_METHODS="package source"
  _FEAT_CONTRACT_PACKAGE_WHEN='plat.pm: apk'
  _stub linux amd64 apk privileged alpine
  VERSION="latest"
  VERSION_RESOLUTION="none"
  run_auto_method
  assert_success
  assert_output "package"
}

@test "scenario: install-texlive (VERSION_RESOLUTION=none) on Debian → source (no apt package)" {
  _FEAT_CONTRACT_METHODS="package source"
  _FEAT_CONTRACT_PACKAGE_WHEN='plat.pm: apk'
  _stub linux amd64 apt privileged debian
  VERSION="latest"
  VERSION_RESOLUTION="none"
  run_auto_method
  assert_success
  assert_output "source"
}
