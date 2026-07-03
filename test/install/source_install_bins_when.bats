#!/usr/bin/env bats
# Unit tests for source build env filtering/injection and source auto-install in the install framework.
# shellcheck disable=SC2034  # framework state vars are consumed by sourced functions called via `run`

bats_require_minimum_version 1.5.0

setup_file() {
  load 'helpers/bootstrap_tools'
  test_bootstrap__setup_file_jq_yq
}

setup() {
  load 'helpers/ensure_framework'
  install_test__ensure_framework
  load 'helpers/bootstrap_tools'
  test_bootstrap__require_jq_yq
  test_bootstrap__wire_tools_for_run
  load 'helpers/stubs'
  load 'helpers/ctx'
  load 'helpers/capture'

  VERSION="3.7.1"
  METHOD="source"
  _FEAT_RESOLVED_TAG="v3.7.1"
  SOURCE_BUILD_ENV=()
  SOURCE_INSTALL_BINS=()
  ctx__reset
  ctx__set feat.version=3.7.1
  ctx__set feat.version_input=3.7.1
  ctx__set feat.tag=v3.7.1
  ctx__set feat.method=source
  _CTX__REGISTRY_INITIALIZED=true
}

_publish_feat_ctx() {
  install_test__capture_version_input
  ctx__set feat.version="${VERSION}"
  ctx__set feat.version_input="${VERSION_INPUT}"
  ctx__set feat.tag="${_FEAT_RESOLVED_TAG:-}"
  ctx__set feat.method="${METHOD:-source}"
}

@test "__feat_filter_source_install_bins__: plain path passes through" {
  SOURCE_INSTALL_BINS=("bin/git-lfs")
  run __feat_filter_source_install_bins__
  assert_success
  assert_output "bin/git-lfs"
}

@test "__feat_filter_source_install_bins__: tab-when line included when condition matches" {
  local _when=$'plat.kernel: linux'
  ctx__set plat.kernel=linux
  SOURCE_INSTALL_BINS=("bin/git-lfs	${_when}")
  run __feat_filter_source_install_bins__
  assert_success
  assert_output "bin/git-lfs"
}

@test "__feat_filter_source_install_bins__: tab-when line excluded when condition fails" {
  local _when=$'plat.kernel: darwin'
  ctx__set plat.kernel=linux
  SOURCE_INSTALL_BINS=("bin/git-lfs	${_when}")
  run __feat_filter_source_install_bins__
  assert_success
  assert_output ""
}

@test "__feat_filter_source_build_env__: tab-when line included when condition matches" {
  local _when=$'plat.kernel: linux'
  ctx__set plat.kernel=linux
  SOURCE_BUILD_ENV=("GOTOOLCHAIN=auto	${_when}")
  run __feat_filter_source_build_env__
  assert_success
  assert_output "GOTOOLCHAIN=auto"
}

@test "__install_run_source_auto_build__: injects SOURCE_BUILD_ENV into make recipes" {
  # Stub make: exits 0 only when FEATURE_TEST_ENV is correctly injected by env.
  # Tests the framework's env injection without requiring a real make installation.
  # shellcheck disable=SC2016
  printf '#!/bin/sh\ntest "${FEATURE_TEST_ENV:-}" = "expected"\n' \
    > "${BATS_TEST_TMPDIR}/bin/make"
  chmod +x "${BATS_TEST_TMPDIR}/bin/make"
  prepend_fake_bin_path

  local _src_dir="${BATS_TEST_TMPDIR}/src-build-env"
  mkdir -p "${_src_dir}"
  SOURCE_BUILD_SYSTEM="make"
  SOURCE_BUILD_ENV=("FEATURE_TEST_ENV=expected")
  SOURCE_MAKE_FLAGS=()
  SOURCE_MAKE_TARGETS=("all")

  run __install_run_source_auto_build__ "${_src_dir}"
  assert_success
}

@test "__install_run_source_auto_build__: fails with invalid SOURCE_BUILD_ENV entry" {
  local _src_dir="${BATS_TEST_TMPDIR}/src-invalid-env"
  mkdir -p "${_src_dir}"
  SOURCE_BUILD_SYSTEM="make"
  SOURCE_BUILD_ENV=("not-an-assignment")
  SOURCE_MAKE_FLAGS=()
  SOURCE_MAKE_TARGETS=("all")

  run __install_run_source_auto_build__ "${_src_dir}"
  assert_failure
  assert_output --partial "not a valid NAME=value assignment"
}

@test "__install_run_source_auto_build__: cmake configures, builds, and installs in sequence" {
  # Stub cmake: logs each invocation's args so the configure/build/install
  # sequence and their exact flags can be asserted afterwards.
  local _log="${BATS_TEST_TMPDIR}/cmake-invocations.log"
  # shellcheck disable=SC2016
  cat > "${BATS_TEST_TMPDIR}/bin/cmake" << EOF
#!/bin/sh
printf '%s\n' "\$*" >> "${_log}"
exit 0
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/cmake"
  prepend_fake_bin_path

  local _src_dir="${BATS_TEST_TMPDIR}/src-cmake"
  local _prefix="${BATS_TEST_TMPDIR}/prefix-cmake"
  mkdir -p "${_src_dir}" "${_prefix}"
  _RESOLVED_PREFIX="${_prefix}"
  SOURCE_BUILD_SYSTEM="cmake"
  SOURCE_CMAKE_ARGS=("-DJSONSCHEMA_PORTABLE:BOOL=ON")

  run __install_run_source_auto_build__ "${_src_dir}"
  assert_success

  run cat "${_log}"
  assert_line --index 0 --partial "-S ${_src_dir} -B ${_src_dir}/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${_prefix} -DJSONSCHEMA_PORTABLE:BOOL=ON"
  assert_line --index 1 --partial "--build ${_src_dir}/build --parallel"
  assert_line --index 2 "--install ${_src_dir}/build"
}

@test "__install_run_source_auto_build__: injects SOURCE_BUILD_ENV into cmake invocations" {
  # Stub cmake: exits 0 only when FEATURE_TEST_ENV is correctly injected by env.
  # shellcheck disable=SC2016
  printf '#!/bin/sh\ntest "${FEATURE_TEST_ENV:-}" = "expected"\n' \
    > "${BATS_TEST_TMPDIR}/bin/cmake"
  chmod +x "${BATS_TEST_TMPDIR}/bin/cmake"
  prepend_fake_bin_path

  local _src_dir="${BATS_TEST_TMPDIR}/src-cmake-env"
  mkdir -p "${_src_dir}"
  SOURCE_BUILD_SYSTEM="cmake"
  SOURCE_BUILD_ENV=("FEATURE_TEST_ENV=expected")
  SOURCE_CMAKE_ARGS=()

  run __install_run_source_auto_build__ "${_src_dir}"
  assert_success
}

@test "__install_run_source_auto_build__: fails when cmake configure step fails" {
  printf '#!/bin/sh\nexit 1\n' > "${BATS_TEST_TMPDIR}/bin/cmake"
  chmod +x "${BATS_TEST_TMPDIR}/bin/cmake"
  prepend_fake_bin_path

  local _src_dir="${BATS_TEST_TMPDIR}/src-cmake-fail"
  mkdir -p "${_src_dir}"
  SOURCE_BUILD_SYSTEM="cmake"
  SOURCE_CMAKE_ARGS=()

  run __install_run_source_auto_build__ "${_src_dir}"
  assert_failure
  assert_output --partial "CMake build: configure failed"
}

@test "__install_run_source_auto_install_bins__: copies built binaries into PREFIX/bin" {
  local _src_dir="${BATS_TEST_TMPDIR}/src"
  local _prefix="${BATS_TEST_TMPDIR}/prefix"
  mkdir -p "${_src_dir}/bin" "${_prefix}"
  printf '#!/bin/sh\nexit 0\n' > "${_src_dir}/bin/git-lfs"
  chmod 0644 "${_src_dir}/bin/git-lfs"
  _RESOLVED_PREFIX="${_prefix}"
  SOURCE_INSTALL_BINS=("bin/git-lfs")

  run __install_run_source_auto_install_bins__ "${_src_dir}"
  assert_success
  assert_output --partial "Installing binary"
  test -x "${_prefix}/bin/git-lfs"
}

@test "__install_run_source_auto_install_bins__: fails when all entries are filtered out" {
  local _src_dir="${BATS_TEST_TMPDIR}/src"
  local _prefix="${BATS_TEST_TMPDIR}/prefix"
  mkdir -p "${_src_dir}/bin" "${_prefix}"
  printf '#!/bin/sh\nexit 0\n' > "${_src_dir}/bin/git-lfs"
  chmod 0755 "${_src_dir}/bin/git-lfs"
  _RESOLVED_PREFIX="${_prefix}"
  ctx__set plat.kernel=linux
  SOURCE_INSTALL_BINS=($'bin/git-lfs\tplat.kernel: darwin')

  run __install_run_source_auto_install_bins__ "${_src_dir}"
  assert_failure
  assert_output --partial "No source_install_bins entries matched"
}
