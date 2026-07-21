#!/usr/bin/env bats
# Unit tests for lib/file.bash

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  reload_lib
}

# ---------------------------------------------------------------------------
# _file__ensure_extract_tool
# ---------------------------------------------------------------------------

@test "_file__ensure_extract_tool tar: succeeds when tar is available" {
  create_fake_bin "tar" ""
  prepend_fake_bin_path

  run _file__ensure_extract_tool tar
  assert_success
}

@test "_file__ensure_extract_tool tar: fails with diagnostic when tar is absent" {
  # Restrict PATH to only our empty bin dir so tar is not found.
  # We must NOT call prepend_fake_bin_path before this — just restrict directly.
  begin_path_isolation

  run _file__ensure_extract_tool tar

  end_path_isolation
  assert_failure
  assert_output --partial "tar is required"
}

@test "_file__ensure_extract_tool zip: succeeds when unzip is available" {
  create_fake_bin "unzip" ""
  prepend_fake_bin_path

  run _file__ensure_extract_tool zip
  assert_success
}

@test "_file__ensure_extract_tool zip: fails with diagnostic when unzip absent and ospkg install fails" {
  # ospkg is now always loaded; simulate install failure so unzip stays absent.
  begin_path_isolation

  ospkg__update() { return 0; }
  export -f ospkg__update
  ospkg__install_tracked() { return 1; }
  export -f ospkg__install_tracked

  run _file__ensure_extract_tool zip

  end_path_isolation
  assert_failure
  assert_output --partial "unzip is required"
}

@test "_file__ensure_extract_tool zip: installs unzip via ospkg when ospkg is loaded" {
  # Simulate ospkg loaded but unzip absent; ospkg stubs install a fake unzip.
  reload_lib
  export _FILE__SESSION_ROOT="${BATS_TEST_TMPDIR}"

  # Seed a minimal apt context without invoking the real PM.
  _OSPKG__DETECTED=true
  _OSPKG__PKG_MNGR="apt-get"
  _OSPKG__FAMILY="apt"
  ctx__set plat.pm=apt plat.machine_release=amd64 os.id=ubuntu os.id_like=debian os.version_id=22.04 os.version_codename=jammy plat.kernel=linux
  _CTX__REGISTRY_INITIALIZED=true

  # Stub ospkg__update and ospkg__install_tracked; the latter creates a fake unzip.
  ospkg__update() { return 0; }
  export -f ospkg__update

  local _fake_unzip="${BATS_TEST_TMPDIR}/bin/unzip"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/bash\nexit 0\n' > "$_fake_unzip"
  chmod +x "$_fake_unzip"

  ospkg__install_tracked() {
    # Simulate installation: unzip now appears on PATH.
    return 0
  }
  export -f ospkg__install_tracked

  # unzip is already available via fake bin, which the stubs put on PATH;
  # prepend it so command -v unzip resolves to our fake.
  prepend_fake_bin_path

  run _file__ensure_extract_tool zip
  assert_success
}

@test "_file__ensure_extract_tool unknown ext: is a no-op" {
  run _file__ensure_extract_tool "weirdfmt"
  assert_success
}

# ---------------------------------------------------------------------------
# file__extract_archive — format detection and tool delegation
# ---------------------------------------------------------------------------

@test "file__extract_archive: invokes unzip -q -o <archive> -d <dest> for .zip" {
  local _arc="${BATS_TEST_TMPDIR}/test.zip"
  touch "$_arc"
  local _dest="${BATS_TEST_TMPDIR}/out_zip"
  local _call_log="${BATS_TEST_TMPDIR}/unzip_calls"

  # Stub unzip: record the argument list to a log file and exit 0.
  # bootstrap__unzip finds the stub on PATH and skips install; file__extract_archive
  # then invokes the stub with the actual extraction arguments.
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n' \
    "${_call_log}" > "${BATS_TEST_TMPDIR}/bin/unzip"
  chmod +x "${BATS_TEST_TMPDIR}/bin/unzip"
  prepend_fake_bin_path

  run file__extract_archive "$_arc" "$_dest"
  assert_success
  assert [ -f "${_call_log}" ]
  local _invocation
  _invocation="$(cat "${_call_log}")"
  [[ "${_invocation}" == *"-q"* ]]
  [[ "${_invocation}" == *"-o"* ]]
  [[ "${_invocation}" == *"-d"* ]]
  [[ "${_invocation}" == *"${_arc}"* ]]
  [[ "${_invocation}" == *"${_dest}"* ]]
}

@test "file__extract_archive: returns failure for unrecognized format" {
  local _arc="${BATS_TEST_TMPDIR}/test.weirdfmt"
  touch "$_arc"
  local _dest="${BATS_TEST_TMPDIR}/out_weird"

  run file__extract_archive "$_arc" "$_dest"
  assert_failure
  assert_output --partial "Unrecognized archive format"
}

@test "file__extract_archive: fails when gzip is absent and format is .tar.gz" {
  local _arc="${BATS_TEST_TMPDIR}/test_no_gzip.tar.gz"
  touch "$_arc"
  local _dest="${BATS_TEST_TMPDIR}/out_no_gzip"
  # Use a fake tar stub (not a pass-through) so the test works regardless of
  # whether real tar is pre-installed (e.g. openSUSE Leap minimal image has no
  # tar). The test only needs command -v tar to succeed so execution reaches
  # the gzip availability check; it does not need tar to actually extract.
  create_fake_bin "tar" ""
  begin_path_isolation "basename" "mkdir" "sort" "tar"

  run file__extract_archive "$_arc" "$_dest"

  end_path_isolation
  assert_failure
  assert_output --partial "gzip is required"
}

# ---------------------------------------------------------------------------
# file__detect_type — magic byte detection
# ---------------------------------------------------------------------------

@test "file__detect_type: gzip magic bytes → gzip" {
  local _f="${BATS_TEST_TMPDIR}/test.bin"
  printf '\x1f\x8b\x00\x00\x00\x00' > "$_f"
  run file__detect_type "$_f"
  assert_success
  assert_output "gzip"
}

@test "file__detect_type: xz magic bytes → xz" {
  local _f="${BATS_TEST_TMPDIR}/test.bin"
  printf '\xfd\x37\x7a\x58\x5a\x00' > "$_f"
  run file__detect_type "$_f"
  assert_success
  assert_output "xz"
}

@test "file__detect_type: zip magic bytes → zip" {
  local _f="${BATS_TEST_TMPDIR}/test.bin"
  printf '\x50\x4b\x03\x04\x00\x00' > "$_f"
  run file__detect_type "$_f"
  assert_success
  assert_output "zip"
}

@test "file__detect_type: ELF magic bytes → elf" {
  local _f="${BATS_TEST_TMPDIR}/test.bin"
  printf '\x7f\x45\x4c\x46\x00\x00' > "$_f"
  run file__detect_type "$_f"
  assert_success
  assert_output "elf"
}

@test "file__detect_type: shebang → script" {
  local _f="${BATS_TEST_TMPDIR}/test.sh"
  printf '#!/usr/bin/env bash\n' > "$_f"
  run file__detect_type "$_f"
  assert_success
  assert_output "script"
}

@test "file__detect_type: bzip2 magic bytes → bzip2" {
  local _f="${BATS_TEST_TMPDIR}/test.bin"
  printf '\x42\x5a\x68\x00\x00\x00' > "$_f"
  run file__detect_type "$_f"
  assert_success
  assert_output "bzip2"
}

@test "file__detect_type: unknown bytes → unknown" {
  local _f="${BATS_TEST_TMPDIR}/test.bin"
  printf '\x00\x01\x02\x03\x04\x05' > "$_f"
  run file__detect_type "$_f"
  assert_success
  assert_output "unknown"
}

@test "file__extract_archive: fails when tar is absent and format is .tar.gz" {
  # Create test artifacts and pass-through bins for system tools BEFORE restricting PATH.
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  local _arc="${BATS_TEST_TMPDIR}/test_no_tar.tar.gz"
  touch "$_arc"
  local _dest="${BATS_TEST_TMPDIR}/out_no_tar"
  # Restrict PATH so tar is not found (our bin dir has no tar).
  begin_path_isolation "basename" "mkdir" "sort"

  run file__extract_archive "$_arc" "$_dest"

  end_path_isolation
  assert_failure
  assert_output --partial "tar is required"
}

# ---------------------------------------------------------------------------
# file__nearest_existing
# ---------------------------------------------------------------------------

@test "file__nearest_existing: existing path is returned unchanged" {
  run file__nearest_existing "$BATS_TEST_TMPDIR"
  assert_success
  assert_output "$BATS_TEST_TMPDIR"
}

@test "file__nearest_existing: non-existent child returns parent" {
  run file__nearest_existing "$BATS_TEST_TMPDIR/does-not-exist"
  assert_success
  assert_output "$BATS_TEST_TMPDIR"
}

@test "file__nearest_existing: deeply nested non-existent path returns nearest existing ancestor" {
  run file__nearest_existing "$BATS_TEST_TMPDIR/a/b/c/d"
  assert_success
  assert_output "$BATS_TEST_TMPDIR"
}

@test "file__nearest_existing: returns / when no ancestor above root exists" {
  run file__nearest_existing "/_devfeats_nonexistent_xyz/bin/foo"
  assert_success
  assert_output "/"
}

# ---------------------------------------------------------------------------
# file__session_* / file__tmpdir
# ---------------------------------------------------------------------------

@test "file__session_ensure creates _FILE__SESSION_ROOT" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../lib/logging.sh'
    source '${BATS_TEST_DIRNAME}/../../lib/file.bash'
    file__session_ensure
    [[ -d \"\${_FILE__SESSION_ROOT}\" ]] && echo OK
    file__session_cleanup
  "
  assert_success
  assert_output "OK"
}

@test "file__session_root matches file__tmpdir with no args" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../lib/logging.sh'
    source '${BATS_TEST_DIRNAME}/../../lib/file.bash'
    file__session_ensure
    _r=\"\${_FILE__SESSION_ROOT}\"
    _t=\"\$(file__tmpdir)\"
    [[ \"\${_r}\" == \"\${_t}\" ]] && echo SAME
    file__session_cleanup
  "
  assert_success
  assert_output "SAME"
}

@test "file__session_ensure is idempotent" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../lib/logging.sh'
    source '${BATS_TEST_DIRNAME}/../../lib/file.bash'
    file__session_ensure
    _first=\"\${_FILE__SESSION_ROOT}\"
    file__session_ensure
    [[ \"\${_first}\" == \"\${_FILE__SESSION_ROOT}\" ]] && echo SAME_ROOT
    file__session_cleanup
  "
  assert_success
  assert_output --partial "SAME_ROOT"
}

@test "file__session_ensure sets _FILE__SESSION_OWNED" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../lib/logging.sh'
    source '${BATS_TEST_DIRNAME}/../../lib/file.bash'
    file__session_ensure
    [[ \"\${_FILE__SESSION_OWNED}\" == true ]] && echo OWNED
    file__session_cleanup
  "
  assert_success
  assert_output "OWNED"
}

@test "file__session_ensure on pre-set root does not take ownership" {
  local _pin="${BATS_TEST_TMPDIR}/injected-root"
  mkdir -p "$_pin"
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../lib/logging.sh'
    source '${BATS_TEST_DIRNAME}/../../lib/file.bash'
    export _FILE__SESSION_ROOT='${_pin}'
    file__session_ensure
    [[ \"\${_FILE__SESSION_OWNED}\" != true ]] && echo NOT_OWNED
    [[ \"\${_FILE__SESSION_ROOT}\" == '${_pin}' ]] && echo PATH_OK
  "
  assert_success
  assert_output --partial "NOT_OWNED"
  assert_output --partial "PATH_OK"
}

@test "file__session_cleanup is idempotent" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../lib/logging.sh'
    source '${BATS_TEST_DIRNAME}/../../lib/file.bash'
    file__session_ensure
    file__session_cleanup
    file__session_cleanup
    [[ -z \"\${_FILE__SESSION_ROOT:-}\" ]] && echo CLEARED
  "
  assert_success
  assert_output "CLEARED"
}

@test "file__tmpdir after parent ensure shares root via command substitution" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../lib/logging.sh'
    source '${BATS_TEST_DIRNAME}/../../lib/file.bash'
    file__session_ensure
    _sub=\"\$(file__tmpdir 'nested/sub')\"
    [[ \"\${_sub}\" == \"\${_FILE__SESSION_ROOT}/nested/sub\" ]] && echo UNDER_ROOT
    file__session_cleanup
  "
  assert_success
  assert_output --partial "UNDER_ROOT"
}

@test "file__tmpdir without parent ensure does not set parent _FILE__SESSION_ROOT" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../lib/logging.sh'
    source '${BATS_TEST_DIRNAME}/../../lib/file.bash'
    _sub=\"\$(file__tmpdir 'orphan-sub')\"
    [[ -d \"\${_sub}\" ]] && [[ -z \"\${_FILE__SESSION_ROOT:-}\" ]] && echo PARENT_EMPTY
  "
  assert_success
  assert_output --partial "PARENT_EMPTY"
}

@test "exported _FILE__SESSION_ROOT is visible in child shell" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../lib/logging.sh'
    source '${BATS_TEST_DIRNAME}/../../lib/file.bash'
    file__session_ensure
    bash -c '[[ \"\${_FILE__SESSION_ROOT}\" == \"'\"\${_FILE__SESSION_ROOT}\"'\" ]] && echo CHILD_MATCH'
    file__session_cleanup
  "
  assert_success
  assert_output --partial "CHILD_MATCH"
}

@test "file__mktmpdir creates distinct directories under same root" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../lib/logging.sh'
    source '${BATS_TEST_DIRNAME}/../../lib/file.bash'
    file__session_ensure
    _a=\"\$(file__mktmpdir 'label')\"
    _b=\"\$(file__mktmpdir 'label')\"
    [[ \"\${_a}\" != \"\${_b}\" ]] && [[ \"\${_a}\" == \"\${_FILE__SESSION_ROOT}\"/* ]] && echo DISTINCT
    file__session_cleanup
  "
  assert_success
  assert_output --partial "DISTINCT"
}

@test "logging__setup via logging.sh marks session as owned" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../lib/logging.sh'
    source '${BATS_TEST_DIRNAME}/../../lib/file.bash'
    source '${BATS_TEST_DIRNAME}/../../lib/logging.bash'
    logging__setup
    [[ \"\${_FILE__SESSION_OWNED}\" == true ]] && echo OWNED >&3
    logging__cleanup
    file__session_cleanup
  "
  assert_success
  assert_output --partial "OWNED"
}

@test "file__first_child_dir returns first immediate subdirectory" {
  local _root="${BATS_TEST_TMPDIR}/parent"
  mkdir -p "${_root}/alpha" "${_root}/beta"
  run file__first_child_dir "$_root"
  assert_success
  [[ -n "$output" ]]
  [[ "$output" == "${_root}/alpha" || "$output" == "${_root}/beta" ]]
}

@test "file__first_child_dir prints nothing when parent has no subdirectories" {
  run file__first_child_dir "${BATS_TEST_TMPDIR}"
  assert_success
  [[ -z "$output" ]]
}

@test "file__first_child_dir finds hidden immediate subdirectory" {
  local _root="${BATS_TEST_TMPDIR}/hidden-parent"
  mkdir -p "${_root}/.src"
  run file__first_child_dir "$_root"
  assert_success
  assert_output "${_root}/.src"
}

@test "file__first_glob_match returns first file matching glob in directory" {
  local _dir="${BATS_TEST_TMPDIR}/globdir"
  mkdir -p "$_dir"
  touch "${_dir}/a.deb" "${_dir}/b.deb"
  run file__first_glob_match "$_dir" '*.deb'
  assert_success
  [[ "$output" == "${_dir}/a.deb" || "$output" == "${_dir}/b.deb" ]]
}

@test "file__first_glob_match prints nothing when directory is missing" {
  run file__first_glob_match "${BATS_TEST_TMPDIR}/no-such-dir" '*.deb'
  assert_success
  [[ -z "$output" ]]
}

# ---------------------------------------------------------------------------
# file__mv
# ---------------------------------------------------------------------------

@test "file__mv: moves a file to a writable destination without escalating" {
  local _src="${BATS_TEST_TMPDIR}/a.txt"
  echo content > "$_src"
  local _dest="${BATS_TEST_TMPDIR}/b.txt"
  users__run_privileged() { fail "should not escalate for a writable destination"; }
  export -f users__run_privileged
  run file__mv "$_src" "$_dest"
  assert_success
  [[ -f "$_dest" ]]
  [[ ! -f "$_src" ]]
}

@test "file__mv: moves a directory" {
  local _src="${BATS_TEST_TMPDIR}/srcdir"
  mkdir -p "${_src}/nested"
  touch "${_src}/nested/f"
  local _dest="${BATS_TEST_TMPDIR}/destdir"
  run file__mv "$_src" "$_dest"
  assert_success
  [[ -f "${_dest}/nested/f" ]]
  [[ ! -d "$_src" ]]
}

# ---------------------------------------------------------------------------
# file__resolve_backup_policy
# ---------------------------------------------------------------------------

@test "file__resolve_backup_policy: accepts exactly true and false" {
  run file__resolve_backup_policy true
  assert_success
  assert_output "true"
  run file__resolve_backup_policy false
  assert_success
  assert_output "false"
}

@test "file__resolve_backup_policy: auto resolves to true outside a devcontainer runtime" {
  os__is_devcontainer_runtime() { return 1; }
  export -f os__is_devcontainer_runtime
  run file__resolve_backup_policy auto
  assert_success
  assert_output "true"
}

@test "file__resolve_backup_policy: auto resolves to false inside a devcontainer runtime" {
  os__is_devcontainer_runtime() { return 0; }
  export -f os__is_devcontainer_runtime
  run file__resolve_backup_policy auto
  assert_success
  assert_output "false"
}

@test "file__resolve_backup_policy: rejects missing, empty, and unknown policies without stdout" {
  local _policy
  for _policy in __missing__ "" yes AUTO 1; do
    if [[ "$_policy" == __missing__ ]]; then
      run --separate-stderr file__resolve_backup_policy
    else
      run --separate-stderr file__resolve_backup_policy "$_policy"
    fi
    assert_failure
    assert_output ""
    assert_stderr --partial "expected 'auto', 'true', or 'false'"
  done
}

# ---------------------------------------------------------------------------
# file__backup_if_policy
# ---------------------------------------------------------------------------

@test "file__backup_if_policy: creates a complete capsule with exact source identity" {
  local _src="${BATS_TEST_TMPDIR}/source path"$'\n'"with-newline.txt"
  printf 'content\n' > "$_src"
  local _dir="${BATS_TEST_TMPDIR}/backups"
  run file__backup_if_policy "$_src" true "$_dir"
  assert_success
  [[ "$output" == "$_dir"/backup.*.??????/item ]]
  local _capsule="${output%/item}"
  [[ -d "$_capsule" && -f "$output" && -f "${_capsule}/source-path" ]]
  [[ "$(cat "$output")" == "$(cat "$_src")" ]]
  [[ "$(cat "${_capsule}/source-path")" == "$_src" ]]
  [[ "$(wc -c < "${_capsule}/source-path")" -eq "${#_src}" ]]

  local -a _children=()
  shopt -s nullglob dotglob
  _children=("${_capsule}"/*)
  shopt -u nullglob dotglob
  [[ ${#_children[@]} -eq 2 ]]
  [[ "${_children[*]}" == *"${_capsule}/item"* ]]
  [[ "${_children[*]}" == *"${_capsule}/source-path"* ]]
}

@test "file__backup_if_policy: validates policy before an absent-path no-op" {
  run --separate-stderr file__backup_if_policy "${BATS_TEST_TMPDIR}/absent" unknown "${BATS_TEST_TMPDIR}"
  assert_failure
  assert_output ""
  assert_stderr --partial "expected 'auto', 'true', or 'false'"
}

@test "file__backup_if_policy: absent path with a valid true policy is an empty no-op" {
  file__mkdir() { return 71; }
  export -f file__mkdir
  run file__backup_if_policy "${BATS_TEST_TMPDIR}/absent" true "${BATS_TEST_TMPDIR}/unused"
  assert_success
  assert_output ""
}

@test "file__backup_if_policy: false is an empty no-op before backup-dir validation" {
  local _src="${BATS_TEST_TMPDIR}/src2.txt"
  printf x > "$_src"
  run file__backup_if_policy "$_src" false ""
  assert_success
  assert_output ""
}

@test "file__backup_if_policy: fails without stdout when a backup is needed but backup_dir is empty" {
  local _src="${BATS_TEST_TMPDIR}/src3.txt"
  printf x > "$_src"
  run --separate-stderr file__backup_if_policy "$_src" true ""
  assert_failure
  assert_output ""
  assert_stderr --partial "no backup directory provided"
}

@test "file__backup_if_policy: preserves a directory tree in item" {
  local _src="${BATS_TEST_TMPDIR}/tree"
  mkdir -p "${_src}/nested"
  printf payload > "${_src}/nested/file"
  run file__backup_if_policy "$_src" true "${BATS_TEST_TMPDIR}/dir-backups"
  assert_success
  [[ -d "$output" ]]
  [[ "$(cat "${output}/nested/file")" == payload ]]
}

@test "file__backup_if_policy: preserves an ordinary symlink as a symlink" {
  local _target="${BATS_TEST_TMPDIR}/target" _src="${BATS_TEST_TMPDIR}/link"
  printf target > "$_target"
  ln -s "$_target" "$_src"
  run file__backup_if_policy "$_src" true "${BATS_TEST_TMPDIR}/link-backups"
  assert_success
  [[ -L "$output" ]]
  [[ "$(readlink "$output")" == "$_target" ]]
}

@test "file__backup_if_policy: treats a dangling symlink as an existing object" {
  local _src="${BATS_TEST_TMPDIR}/dangling" _target="${BATS_TEST_TMPDIR}/missing-target"
  ln -s "$_target" "$_src"
  run file__backup_if_policy "$_src" true "${BATS_TEST_TMPDIR}/dangling-backups"
  assert_success
  [[ -L "$output" ]]
  [[ "$(readlink "$output")" == "$_target" ]]
}

@test "file__backup_if_policy: same fixed timestamp yields unique sequential capsules with changed content" {
  local _src="${BATS_TEST_TMPDIR}/src4.txt"
  printf first > "$_src"
  local _dir="${BATS_TEST_TMPDIR}/backups2"
  date() { printf '20240102T030405Z\n'; }
  export -f date

  run file__backup_if_policy "$_src" true "$_dir"
  local _first="$output"
  printf second > "$_src"
  run file__backup_if_policy "$_src" true "$_dir"
  local _second="$output"
  [[ "$_first" != "$_second" ]]
  [[ -f "$_first" && -f "$_second" ]]
  [[ "$(cat "$_first")" == first ]]
  [[ "$(cat "$_second")" == second ]]
  [[ "$_first" == "$_dir"/backup.20240102T030405Z.??????/item ]]
  [[ "$_second" == "$_dir"/backup.20240102T030405Z.??????/item ]]
}

@test "file__backup_if_policy: concurrent fixed-timestamp backups reserve unique complete capsules" {
  local _src="${BATS_TEST_TMPDIR}/concurrent-source" _dir="${BATS_TEST_TMPDIR}/concurrent-backups"
  printf concurrent > "$_src"
  date() { printf '20240102T030405Z\n'; }
  export -f date

  local _i
  for _i in {1..8}; do
    file__backup_if_policy "$_src" true "$_dir" > "${BATS_TEST_TMPDIR}/result.${_i}" &
  done
  local _wait_rc=0
  wait || _wait_rc=$?
  [[ $_wait_rc -eq 0 ]]

  local -A _seen=()
  local _item _capsule
  for _i in {1..8}; do
    IFS= read -r _item < "${BATS_TEST_TMPDIR}/result.${_i}"
    [[ -n "$_item" && -z "${_seen[$_item]+set}" ]]
    _seen["$_item"]=1
    _capsule="${_item%/item}"
    [[ -f "$_item" && "$(cat "$_item")" == concurrent ]]
    [[ "$(cat "${_capsule}/source-path")" == "$_src" ]]
  done
  [[ ${#_seen[@]} -eq 8 ]]
}

@test "file__backup_if_policy: preserves portable file mode and timestamp" {
  local _src="${BATS_TEST_TMPDIR}/metadata-source" _src_mode _dst_mode _src_mtime _dst_mtime
  printf metadata > "$_src"
  chmod 0640 "$_src"
  touch -t 202001020304.05 "$_src"
  run file__backup_if_policy "$_src" true "${BATS_TEST_TMPDIR}/metadata-backups"
  assert_success

  _src_mode="$(stat -c %a "$_src" 2> /dev/null || stat -f %Lp "$_src")"
  _dst_mode="$(stat -c %a "$output" 2> /dev/null || stat -f %Lp "$output")"
  _src_mtime="$(stat -c %Y "$_src" 2> /dev/null || stat -f %m "$_src")"
  _dst_mtime="$(stat -c %Y "$output" 2> /dev/null || stat -f %m "$output")"
  [[ "$_dst_mode" == "$_src_mode" ]]
  [[ "$_dst_mtime" == "$_src_mtime" ]]
  [[ "$(stat -c %a "${output%/item}/source-path" 2> /dev/null || stat -f %Lp "${output%/item}/source-path")" == 600 ]]
}

@test "file__backup_if_policy: mkdir failure is explicit and emits no stdout" {
  local _src="${BATS_TEST_TMPDIR}/mkdir-source"
  printf x > "$_src"
  file__mkdir() { return 41; }
  export -f file__mkdir
  run --separate-stderr file__backup_if_policy "$_src" true "${BATS_TEST_TMPDIR}/mkdir-backups"
  [[ $status -eq 41 ]]
  assert_output ""
  assert_stderr --partial "failed to create backup directory"
}

@test "file__backup_if_policy: date failure is explicit and emits no stdout" {
  local _src="${BATS_TEST_TMPDIR}/date-source"
  printf x > "$_src"
  date() { return 42; }
  export -f date
  run --separate-stderr file__backup_if_policy "$_src" true "${BATS_TEST_TMPDIR}/date-backups"
  [[ $status -eq 42 ]]
  assert_output ""
  assert_stderr --partial "valid UTC backup timestamp"
}

@test "file__backup_if_policy: invalid successful date output is rejected" {
  local _src="${BATS_TEST_TMPDIR}/bad-date-source"
  printf x > "$_src"
  date() { printf invalid; }
  export -f date
  run --separate-stderr file__backup_if_policy "$_src" true "${BATS_TEST_TMPDIR}/bad-date-backups"
  assert_failure
  assert_output ""
  assert_stderr --partial "valid UTC backup timestamp"
}

@test "file__backup_if_policy: mktemp failure is explicit and emits no stdout" {
  local _src="${BATS_TEST_TMPDIR}/mktemp-source"
  printf x > "$_src"
  mktemp() {
    if [[ "${*: -1}" == */backup.*.XXXXXX ]]; then
      return 43
    fi
    command mktemp "$@"
  }
  export -f mktemp
  run --separate-stderr file__backup_if_policy "$_src" true "${BATS_TEST_TMPDIR}/mktemp-backups"
  [[ $status -eq 43 ]]
  assert_output ""
  assert_stderr --partial "failed to reserve a unique backup capsule"
}

@test "file__backup_if_policy: non-writable allocation path delegates mktemp to users__run_privileged" {
  local _src="${BATS_TEST_TMPDIR}/priv-source" _dir="${BATS_TEST_TMPDIR}/priv-backups"
  local _call_log="${BATS_TEST_TMPDIR}/priv-call"
  printf x > "$_src"
  file__mkdir() { mkdir -p "$@"; }
  _file__backup_dir_is_writable() { return 1; }
  users__run_privileged() {
    printf '%s\n' "$*" > "$_call_log"
    "$@"
  }
  export _call_log
  export -f file__mkdir _file__backup_dir_is_writable users__run_privileged

  run file__backup_if_policy "$_src" true "$_dir"
  assert_success
  [[ -f "$output" ]]
  [[ "$(cat "$_call_log")" == mktemp\ -d\ "$_dir"/backup.*.XXXXXX ]]
}

@test "file__backup_if_policy: sidecar failure removes the capsule and preserves status" {
  local _src="${BATS_TEST_TMPDIR}/sidecar-source" _dir="${BATS_TEST_TMPDIR}/sidecar-backups"
  printf x > "$_src"
  _file__write_backup_identity() { return 44; }
  export -f _file__write_backup_identity
  run --separate-stderr file__backup_if_policy "$_src" true "$_dir"
  [[ $status -eq 44 ]]
  assert_output ""
  assert_stderr --partial "source-path write failed"
  local -a _capsules=("$_dir"/backup.*)
  [[ ! -e "${_capsules[0]}" ]]
}

@test "file__backup_if_policy: chmod failure removes the capsule and preserves status" {
  local _src="${BATS_TEST_TMPDIR}/chmod-source" _dir="${BATS_TEST_TMPDIR}/chmod-backups"
  printf x > "$_src"
  file__chmod() { return 45; }
  export -f file__chmod
  run --separate-stderr file__backup_if_policy "$_src" true "$_dir"
  [[ $status -eq 45 ]]
  assert_output ""
  assert_stderr --partial "source-path protection failed"
  local -a _capsules=("$_dir"/backup.*)
  [[ ! -e "${_capsules[0]}" ]]
}

@test "file__backup_if_policy: copy failure removes the capsule and preserves status" {
  local _src="${BATS_TEST_TMPDIR}/copy-source" _dir="${BATS_TEST_TMPDIR}/copy-backups"
  printf x > "$_src"
  file__cp() { return 46; }
  export -f file__cp
  run --separate-stderr file__backup_if_policy "$_src" true "$_dir"
  [[ $status -eq 46 ]]
  assert_output ""
  assert_stderr --partial "item copy failed"
  local -a _capsules=("$_dir"/backup.*)
  [[ ! -e "${_capsules[0]}" ]]
}

@test "file__backup_if_policy: cleanup failure reports an orphan without replacing primary status" {
  local _src="${BATS_TEST_TMPDIR}/orphan-source" _dir="${BATS_TEST_TMPDIR}/orphan-backups"
  printf x > "$_src"
  file__cp() { return 47; }
  file__rm() { return 59; }
  export -f file__cp file__rm
  run --separate-stderr file__backup_if_policy "$_src" true "$_dir"
  [[ $status -eq 47 ]]
  assert_output ""
  assert_stderr --partial "cleanup also failed"
  assert_stderr --partial "orphan remains"
  local -a _capsules=("$_dir"/backup.*)
  [[ -d "${_capsules[0]}" ]]
  [[ -f "${_capsules[0]}/source-path" ]]
}

@test "file__backup_if_policy: final stdout failure retains the complete backup" {
  local _src="${BATS_TEST_TMPDIR}/stdout-source" _dir="${BATS_TEST_TMPDIR}/stdout-backups"
  printf x > "$_src"
  _backup_with_failed_stdout() {
    file__backup_if_policy "$1" true "$2" >&-
  }
  export -f _backup_with_failed_stdout
  run --separate-stderr _backup_with_failed_stdout "$_src" "$_dir"
  assert_failure
  assert_output ""
  local -a _capsules=("$_dir"/backup.*)
  [[ ${#_capsules[@]} -eq 1 ]]
  [[ -f "${_capsules[0]}/item" ]]
  [[ -f "${_capsules[0]}/source-path" ]]
}
