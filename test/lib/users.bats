#!/usr/bin/env bats
# Unit tests for lib/users.bash

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  reload_lib
}

# ---------------------------------------------------------------------------
# users__resolve_list
# ---------------------------------------------------------------------------

@test "users__resolve_list includes SUDO_USER when --current true" {
  users__is_root() { return 0; }
  export -f users__is_root
  SUDO_USER=alice \
    run --separate-stderr users__resolve_list --current true --remote false --container false
  assert_output "alice"
}

@test "users__resolve_list includes _REMOTE_USER when --remote true" {
  _REMOTE_USER=bob \
    run --separate-stderr users__resolve_list --current false --remote true --container false
  assert_output "bob"
}

@test "users__resolve_list includes _CONTAINER_USER when --container true" {
  _CONTAINER_USER=carol \
    run --separate-stderr users__resolve_list --current false --remote false --container true
  assert_output "carol"
}

@test "users__resolve_list includes extra users from --user flags" {
  run --separate-stderr users__resolve_list \
    --current false --remote false --container false \
    --user dave --user eve
  assert_output "dave
eve"
}

@test "users__resolve_list deduplicates users passed via --user" {
  run --separate-stderr users__resolve_list \
    --current false --remote false --container false \
    --user alice --user alice --user bob
  assert_output "alice
bob"
}

@test "users__resolve_list combines --current and --user" {
  users__is_root() { return 0; }
  export -f users__is_root
  SUDO_USER=alice \
    run --separate-stderr users__resolve_list \
    --current true --remote false --container false \
    --user bob
  assert_output "alice
bob"
}

@test "users__resolve_list includes root as fallback when it is the only user" {
  # When the build user is root and no other non-root users are auto-detected,
  # root is included so the feature has a target to configure (e.g. plain
  # container images or standalone macOS use with no remoteUser).
  users__is_root() { return 0; }
  export -f users__is_root
  SUDO_USER=root \
    run --separate-stderr users__resolve_list --current true --remote false --container false
  assert_output "root"
  assert_success
}

@test "users__resolve_list excludes root when a non-root user is also detected" {
  # Root must not be added when a non-root remoteUser / containerUser is present;
  # the build runs as root but the target for configuration is the named user.
  users__is_root() { return 0; }
  export -f users__is_root
  SUDO_USER=root \
    _REMOTE_USER=alice \
    run --separate-stderr users__resolve_list --current true --remote true --container false
  assert_output "alice"
  assert_success
}

@test "users__resolve_list allows root when explicitly passed via --user" {
  # Explicitly listing root via --user is a deliberate override
  # (used by install-podman to configure rootless Podman for the root user).
  run --separate-stderr users__resolve_list \
    --current false --remote false --container false \
    --user root --user alice
  assert_output "root
alice"
}

@test "users__resolve_list returns empty output when all sources are disabled" {
  run --separate-stderr users__resolve_list --current false --remote false --container false
  assert_output ""
  assert_success
}

@test "users__resolve_list auto-discovers all sources when called with no args" {
  users__is_root() { return 0; }
  export -f users__is_root
  SUDO_USER=alice \
    _REMOTE_USER=bob \
    _CONTAINER_USER=carol \
    run --separate-stderr users__resolve_list
  assert_output "alice
bob
carol"
}

@test "users__resolve_list skips empty _REMOTE_USER when --remote true" {
  _REMOTE_USER="" \
    run --separate-stderr users__resolve_list --current false --remote true --container false
  assert_output ""
  assert_success
}

# ---------------------------------------------------------------------------
# users__set_login_shell
# ---------------------------------------------------------------------------

@test "users__set_login_shell warns when chsh is not installed" {
  reload_lib
  # Stub ospkg__run to simulate chsh being unavailable/uninstallable.
  ospkg__run() { return 1; }
  run users__set_login_shell "/usr/bin/zsh" "alice"
  assert_success
  assert_output --partial "chsh not found"
}

@test "users__set_login_shell skips user whose shell is already set" {
  reload_lib
  ospkg__run() { return 0; } # chsh already on PATH; skip package install
  create_fake_bin "chsh" ""
  # fake getent returns a passwd line where the shell is already /usr/bin/zsh
  cat > "${BATS_TEST_TMPDIR}/bin/getent" << 'EOF'
#!/bin/sh
printf 'alice:x:1000:1000::/home/alice:/usr/bin/zsh\n'
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/getent"
  prepend_fake_bin_path
  run users__set_login_shell "/usr/bin/zsh" "alice"
  assert_success
  assert_output --partial "already set"
}

@test "users__set_login_shell changes the shell when it differs" {
  reload_lib
  ospkg__run() { return 0; }        # chsh already on PATH; skip package install
  users__run_privileged() { "$@"; } # run directly (no sudo) so fake PATH is used
  create_fake_bin "chsh" ""
  # fake getent returns a passwd line with a different shell
  cat > "${BATS_TEST_TMPDIR}/bin/getent" << 'EOF'
#!/bin/sh
printf 'alice:x:1000:1000::/home/alice:/bin/bash\n'
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/getent"
  prepend_fake_bin_path
  # Stub file__append_privileged: prevents permission-denied when registering
  # the shell in /etc/shells (test runs as non-root without write access).
  file__append_privileged() { return 0; }
  run users__set_login_shell "/usr/bin/zsh" "alice"
  assert_success
  assert_output --partial "set to '/usr/bin/zsh'"
}

# ---------------------------------------------------------------------------
# users__set_write_permissions
# ---------------------------------------------------------------------------

@test "users__set_write_permissions applies setgid recursively to nested directories" {
  local _path="${BATS_TEST_TMPDIR}/prefix with spaces"
  local _nested="${_path}/subdir/inner"
  mkdir -p "$_nested"
  touch "${_path}/plain-file"

  bootstrap__shadow_utils() { return 1; }
  users__run_privileged() {
    if [[ "$1" == "chown" ]]; then
      return 0
    fi
    "$@"
  }

  run --separate-stderr users__set_write_permissions "$_path" "$(id -un)" "$(id -gn)"
  assert_success
  [[ -g "$_path" ]]
  [[ -g "${_path}/subdir" ]]
  [[ -g "$_nested" ]]
  [[ ! -g "${_path}/plain-file" ]]
}

@test "users__set_write_permissions uses batched find -exec chmod g+s {} +" {
  bootstrap__shadow_utils() { return 1; }
  users__run_privileged() { printf '%s\n' "$@"; }

  run --separate-stderr users__set_write_permissions "/tmp/prefix with spaces" "alice" "devs"
  assert_success
  assert_output --partial "find
/tmp/prefix with spaces
-type
d
-exec
chmod
g+s
{}
+"
}

@test "users__set_write_permissions returns 1 when the batched find step fails" {
  local _path="${BATS_TEST_TMPDIR}/prefix"
  mkdir -p "${_path}/subdir"

  create_fake_bin "chown" ""
  cat > "${BATS_TEST_TMPDIR}/bin/find" << 'EOF'
#!/bin/sh
exit 1
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/find"
  prepend_fake_bin_path

  bootstrap__shadow_utils() { return 1; }
  users__run_privileged() { "$@"; }

  run --separate-stderr users__set_write_permissions "$_path" "$(id -un)" "$(id -gn)"
  assert_failure
  assert_stderr --partial "Failed to set setgid bit on directories in '${_path}'."
}

# ---------------------------------------------------------------------------
# users__resolve_home
# ---------------------------------------------------------------------------

@test "users__resolve_home resolves home via getent" {
  create_fake_bin "getent" "alice:x:1000:1000::/home/alice:/bin/bash"
  prepend_fake_bin_path
  run users__resolve_home "alice"
  assert_success
  assert_output "/home/alice"
}

@test "users__resolve_home falls back to /etc/passwd awk scan when getent is absent" {
  ospkg__run() { return 1; }
  export -f ospkg__run
  begin_path_isolation awk mktemp uname
  run --separate-stderr users__resolve_home "root"
  end_path_isolation
  assert_success
  assert_output "$(eval echo '~root')"
}

@test "users__resolve_home returns unexpanded tilde when user is absent from all sources" {
  ospkg__run() { return 1; }
  export -f ospkg__run
  begin_path_isolation awk mktemp
  run --separate-stderr users__resolve_home "___no_such_user_xyz___"
  end_path_isolation
  assert_success
  assert_output "~___no_such_user_xyz___"
}

@test "users__resolve_home with no args resolves home of current user" {
  create_fake_bin "getent" "alice:x:1000:1000::/home/alice:/bin/bash"
  prepend_fake_bin_path
  users__get_current() { printf 'alice\n'; }
  export -f users__get_current
  run users__resolve_home
  assert_success
  assert_output "/home/alice"
}

# ---------------------------------------------------------------------------
# users__run_as
# ---------------------------------------------------------------------------

@test "users__run_as runs in-process when user matches" {
  reload_lib
  _me="$(id -un)"
  run users__run_as "$_me" -- echo "ran"
  assert_output "ran"
  assert_success
}

@test "users__run_as same user: --cwd changes directory" {
  reload_lib
  _me="$(id -un)"
  run users__run_as "$_me" --cwd "$BATS_TEST_TMPDIR" -- pwd
  assert_success
  assert_output "$BATS_TEST_TMPDIR"
}

@test "users__run_as same user: --cwd with spaces in path" {
  reload_lib
  _me="$(id -un)"
  _dir="$BATS_TEST_TMPDIR/path with spaces"
  mkdir -p "$_dir"
  run users__run_as "$_me" --cwd "$_dir" -- pwd
  assert_success
  assert_output "$_dir"
}

@test "users__run_as returns failure when user argument is empty" {
  reload_lib
  run users__run_as "" -- echo "nope"
  assert_failure
}

@test "users__run_as returns failure when no command given" {
  reload_lib
  _me="$(id -un)"
  run users__run_as "$_me" --
  assert_failure
}

# ---------------------------------------------------------------------------
# users__run_as — different-user path (su stubbed with eval)
# In these tests, `id` is faked to return "notme" so the current-user check
# fails and execution proceeds to the su path.  `su` is overridden as a shell
# function that eval's its 4th argument (the -c command string) so we can
# verify the constructed command string is correctly quoted and executable.
# ---------------------------------------------------------------------------

@test "users__run_as different user: runs command via su" {
  reload_lib
  create_fake_bin "id" "notme"
  prepend_fake_bin_path
  su() { eval "$4"; }
  users__run_privileged() { "$@"; }
  export -f su users__run_privileged
  run users__run_as "otheruser" -- echo "via-su"
  assert_success
  assert_output "via-su"
}

@test "users__run_as different user: preserves args with spaces" {
  reload_lib
  create_fake_bin "id" "notme"
  prepend_fake_bin_path
  su() { eval "$4"; }
  users__run_privileged() { "$@"; }
  export -f su users__run_privileged
  run users__run_as "otheruser" -- echo "hello world"
  assert_success
  assert_output "hello world"
}

@test "users__run_as different user: --cwd with spaces in path" {
  reload_lib
  create_fake_bin "id" "notme"
  prepend_fake_bin_path
  _dir="$BATS_TEST_TMPDIR/path with spaces"
  mkdir -p "$_dir"
  su() { eval "$4"; }
  users__run_privileged() { "$@"; }
  export -f su users__run_privileged
  run users__run_as "otheruser" --cwd "$_dir" -- pwd
  assert_success
  assert_output "$_dir"
}

@test "users__run_as different user: --cwd with single quote in path" {
  reload_lib
  create_fake_bin "id" "notme"
  prepend_fake_bin_path
  _dir="$BATS_TEST_TMPDIR/user's dir"
  mkdir -p "$_dir"
  su() { eval "$4"; }
  users__run_privileged() { "$@"; }
  export -f su users__run_privileged
  run users__run_as "otheruser" --cwd "$_dir" -- pwd
  assert_success
  assert_output "$_dir"
}

@test "users__run_as fails with error when bash is not on PATH" {
  reload_lib
  create_fake_bin "id" "notme"
  begin_path_isolation # only fake bin dir; bash not present
  run users__run_as "otheruser" -- echo "nope"
  end_path_isolation
  assert_failure
  assert_output --partial "bash is required"
}

@test "users__run_as different user: bootstraps su when absent" {
  reload_lib
  begin_path_isolation mktemp chmod bash mkdir
  create_fake_bin "id" "notme"
  bootstrap__su() {
    cat > "${BATS_TEST_TMPDIR}/bin/su" << 'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do
  case "$1" in
    -c) shift; eval "$1"; exit $? ;;
  esac
  shift
done
exit 1
EOF
    chmod +x "${BATS_TEST_TMPDIR}/bin/su"
    return 0
  }
  export -f bootstrap__su
  users__run_privileged() { "$@"; }
  export -f users__run_privileged
  run users__run_as "otheruser" -- echo "bootstrapped-su"
  end_path_isolation
  assert_success
  assert_output "bootstrapped-su"
}

# ---------------------------------------------------------------------------
# users__uid_of_path_owner
# ---------------------------------------------------------------------------

@test "users__uid_of_path_owner: returns numeric UID for an existing directory" {
  run users__uid_of_path_owner "$BATS_TEST_TMPDIR"
  assert_success
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "users__uid_of_path_owner: returns numeric UID for an existing file" {
  local _f="$BATS_TEST_TMPDIR/testfile"
  touch "$_f"
  run users__uid_of_path_owner "$_f"
  assert_success
  [[ "$output" =~ ^[0-9]+$ ]]
}

# ---------------------------------------------------------------------------
# users__home_of_path_owner
# ---------------------------------------------------------------------------

@test "users__home_of_path_owner: returns home of the path's owning UID" {
  users__uid_of_path_owner() { printf '1001\n'; }
  users__resolve_home() {
    [[ "${1:-}" == "--uid" && "${2:-}" == "1001" ]] && printf '/home/vscode\n'
  }
  export -f users__uid_of_path_owner users__resolve_home
  run users__home_of_path_owner "/home/vscode/.local/bin"
  assert_output "/home/vscode"
  assert_success
}

@test "users__home_of_path_owner: returns empty when owner has no resolvable home" {
  users__uid_of_path_owner() { printf '58392\n'; }
  users__resolve_home() { :; }
  export -f users__uid_of_path_owner users__resolve_home
  HOME="/home/alice"
  run users__home_of_path_owner "/home/gone/.config"
  assert_output ""
  assert_success
}

# ---------------------------------------------------------------------------
# users__run_privileged — sudo absent
# ---------------------------------------------------------------------------

@test "users__run_privileged: exits with error when sudo is not installed" {
  users__is_root() { return 1; }
  export -f users__is_root
  begin_path_isolation # sudo not in isolated PATH
  run users__run_privileged echo "should not run"
  end_path_isolation
  assert_failure
  assert_output --partial "sudo is not installed"
}

# ---------------------------------------------------------------------------
# users__is_privileged
# ---------------------------------------------------------------------------

@test "users__is_privileged: returns 0 when running as root" {
  users__is_root() { return 0; }
  export -f users__is_root
  run users__is_privileged
  assert_success
}

@test "users__is_privileged: returns 0 when non-root and sudo is passwordless" {
  users__is_root() { return 1; }
  export -f users__is_root
  create_fake_bin "sudo" ""
  prepend_fake_bin_path
  run users__is_privileged
  assert_success
}

@test "users__is_privileged: returns 1 when non-root and sudo is not installed" {
  users__is_root() { return 1; }
  export -f users__is_root
  begin_path_isolation
  run users__is_privileged
  end_path_isolation
  assert_failure
}

@test "users__is_privileged: returns 1 when non-root and sudo requires a password" {
  users__is_root() { return 1; }
  export -f users__is_root
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  # Fake sudo: exists in PATH but 'sudo -n ...' exits 1 (simulates interactive password prompt).
  printf '#!/bin/bash\n[[ "$1" == "-n" ]] && exit 1 || exit 0\n' \
    > "${BATS_TEST_TMPDIR}/bin/sudo"
  chmod +x "${BATS_TEST_TMPDIR}/bin/sudo"
  prepend_fake_bin_path
  run users__is_privileged
  assert_failure
}

# ---------------------------------------------------------------------------
# users__can_write
# ---------------------------------------------------------------------------

@test "users__can_write: returns 0 for a writable existing directory" {
  run users__can_write "$BATS_TEST_TMPDIR"
  assert_success
}

@test "users__can_write: returns 0 for a nonexistent path under a writable directory" {
  run users__can_write "$BATS_TEST_TMPDIR/new/subdir"
  assert_success
}

@test "users__can_write: returns 1 when nearest ancestor is not writable and sudo is unavailable" {
  file__nearest_existing() { printf '/__devfeats_nonexistent__\n'; }
  users__is_privileged() { return 1; }
  export -f file__nearest_existing users__is_privileged
  run users__can_write "/some/path"
  assert_failure
}

@test "users__can_write: returns 0 when nearest ancestor is not writable but sudo is available" {
  file__nearest_existing() { printf '/__devfeats_nonexistent__\n'; }
  users__is_privileged() { return 0; }
  export -f file__nearest_existing users__is_privileged
  run users__can_write "/some/path"
  assert_success
}

# ---------------------------------------------------------------------------
# users__default_prefix
# ---------------------------------------------------------------------------

@test "users__default_prefix: returns /usr/local when writable" {
  users__can_write() { return 0; }
  export -f users__can_write
  run users__default_prefix
  assert_output "/usr/local"
  assert_success
}

@test "users__default_prefix: returns home/.local when /usr/local is not writable" {
  users__can_write() { return 1; }
  users__resolve_home() { printf '/home/alice\n'; }
  export -f users__can_write users__resolve_home
  run users__default_prefix
  assert_output "/home/alice/.local"
  assert_success
}

@test "users__default_prefix: fails when /usr/local not writable and home unresolvable" {
  users__can_write() { return 1; }
  users__resolve_home() { :; }
  export -f users__can_write users__resolve_home
  run users__default_prefix
  assert_failure
}

# ---------------------------------------------------------------------------
# bootstrap__getent
# ---------------------------------------------------------------------------

@test "bootstrap__getent: returns 0 when getent is present" {
  [[ "$(uname)" != "Darwin" ]] || skip "getent is unavailable on macOS"
  run bootstrap__getent
  assert_success
}

@test "bootstrap__getent: returns 1 when getent is absent and install fails" {
  [[ "$(uname)" != "Darwin" ]] || skip "bootstrap__getent uses --skip-darwin and returns 0 on macOS"
  ospkg__run() { return 1; }
  export -f ospkg__run
  begin_path_isolation mktemp
  run --separate-stderr bootstrap__getent
  end_path_isolation
  assert_failure
}

# ---------------------------------------------------------------------------
# users__primary_group_of
# ---------------------------------------------------------------------------

@test "users__primary_group_of: returns primary group name of current user" {
  local _expected
  _expected="$(id -gn)"
  run users__primary_group_of "$(id -un)"
  assert_success
  assert_output "$_expected"
}

# ---------------------------------------------------------------------------
# users__uid_of_user
# ---------------------------------------------------------------------------

@test "users__uid_of_user: returns numeric UID for the current user" {
  local _expected
  _expected="$(id -u)"
  run users__uid_of_user "$(id -un)"
  assert_success
  assert_output "$_expected"
}

# ---------------------------------------------------------------------------
# users__username_of_uid
# ---------------------------------------------------------------------------

@test "users__username_of_uid: round-trips with users__uid_of_user" {
  local _me _uid
  _me="$(id -un)"
  _uid="$(id -u)"
  run users__username_of_uid "$_uid"
  assert_success
  assert_output "$_me"
}

# ---------------------------------------------------------------------------
# users__get_current — devcontainer paths
# ---------------------------------------------------------------------------

@test "users__get_current: returns _REMOTE_USER in devcontainer build" {
  users__is_root() { return 0; }
  export -f users__is_root
  _REMOTE_USER=alice _CONTAINER_USER=bob \
    _REMOTE_USER_HOME=/home/alice _CONTAINER_USER_HOME=/home/bob \
    run --separate-stderr users__get_current
  assert_success
  assert_output "alice"
}

@test "users__get_current: skips root _REMOTE_USER and returns _CONTAINER_USER" {
  users__is_root() { return 0; }
  export -f users__is_root
  _REMOTE_USER=root _CONTAINER_USER=bob \
    _REMOTE_USER_HOME=/root _CONTAINER_USER_HOME=/home/bob \
    run --separate-stderr users__get_current
  assert_success
  assert_output "bob"
}

@test "users__get_current: SUDO_USER takes priority over devcontainer vars" {
  users__is_root() { return 0; }
  export -f users__is_root
  SUDO_USER=carol _REMOTE_USER=alice _CONTAINER_USER=bob \
    _REMOTE_USER_HOME=/home/alice _CONTAINER_USER_HOME=/home/bob \
    run --separate-stderr users__get_current
  assert_success
  assert_output "carol"
}

@test "users__get_current: --no-sudo bypasses both SUDO_USER and devcontainer vars" {
  local _me
  _me="$(id -un)"
  SUDO_USER=carol _REMOTE_USER=alice _CONTAINER_USER=bob \
    _REMOTE_USER_HOME=/home/alice _CONTAINER_USER_HOME=/home/bob \
    run --separate-stderr users__get_current --no-sudo
  assert_success
  assert_output "$_me"
}

# ---------------------------------------------------------------------------
# users__resolve_home — devcontainer fallback
# ---------------------------------------------------------------------------

@test "users__resolve_home: returns _REMOTE_USER_HOME from devcontainer vars" {
  bootstrap__getent() { return 1; }
  export -f bootstrap__getent
  _REMOTE_USER=alice _CONTAINER_USER=bob \
    _REMOTE_USER_HOME=/home/alice _CONTAINER_USER_HOME=/home/bob \
    run --separate-stderr users__resolve_home "alice"
  assert_success
  assert_output "/home/alice"
}

@test "users__resolve_home: returns _CONTAINER_USER_HOME from devcontainer vars" {
  bootstrap__getent() { return 1; }
  export -f bootstrap__getent
  _REMOTE_USER=alice _CONTAINER_USER=bob \
    _REMOTE_USER_HOME=/home/alice _CONTAINER_USER_HOME=/home/bob \
    run --separate-stderr users__resolve_home "bob"
  assert_success
  assert_output "/home/bob"
}

@test "users__resolve_home: devcontainer UID fallback resolves via users__username_of_uid" {
  bootstrap__getent() { return 1; }
  users__username_of_uid() { printf 'alice\n'; }
  export -f bootstrap__getent users__username_of_uid
  _REMOTE_USER=alice _CONTAINER_USER=bob \
    _REMOTE_USER_HOME=/home/alice _CONTAINER_USER_HOME=/home/bob \
    run --separate-stderr users__resolve_home --uid 1001
  assert_success
  assert_output "/home/alice"
}

# ---------------------------------------------------------------------------
# users__is_user_path — no-user-arg, non-root scenarios
# ---------------------------------------------------------------------------

@test "users__is_user_path: non-root, writable path is user-local" {
  (($(id -u) != 0)) || skip "requires non-root"
  reload_lib
  run users__is_user_path "$BATS_TEST_TMPDIR"
  assert_success
}

@test "users__is_user_path: non-root, non-existent path under writable parent is user-local" {
  (($(id -u) != 0)) || skip "requires non-root"
  reload_lib
  run users__is_user_path "$BATS_TEST_TMPDIR/does-not-exist/bin"
  assert_success
}

@test "users__is_user_path: non-root, path under non-writable root ancestor is system" {
  (($(id -u) != 0)) || skip "requires non-root"
  reload_lib
  run users__is_user_path "/_devfeats_test_nonexistent_xyz/bin"
  assert_failure
}

# ---------------------------------------------------------------------------
# users__is_user_path — no-user-arg, root scenarios (stubs)
# ---------------------------------------------------------------------------

@test "users__is_user_path: root, path under root's resolved home is user-local" {
  reload_lib
  users__is_root() { return 0; }
  users__resolve_home() { printf '/root\n'; }
  export -f users__is_root users__resolve_home
  run users__is_user_path "/root/.local/bin"
  assert_success
}

@test "users__is_user_path: root, path owned by regular user (UID 1000) is user-local" {
  reload_lib
  users__is_root() { return 0; }
  users__resolve_home() { :; }
  users__uid_of_path_owner() { printf '1000\n'; }
  export -f users__is_root users__resolve_home users__uid_of_path_owner
  run users__is_user_path "/home/vscode/.local/bin"
  assert_success
}

@test "users__is_user_path: root, path owned by UID 65533 (upper boundary) is user-local" {
  reload_lib
  users__is_root() { return 0; }
  users__resolve_home() { :; }
  users__uid_of_path_owner() { printf '65533\n'; }
  export -f users__is_root users__resolve_home users__uid_of_path_owner
  run users__is_user_path "/home/highuid/.local"
  assert_success
}

@test "users__is_user_path: root, path owned by root (UID 0) is system" {
  reload_lib
  users__is_root() { return 0; }
  users__resolve_home() { printf '/root\n'; }
  users__uid_of_path_owner() { printf '0\n'; }
  export -f users__is_root users__resolve_home users__uid_of_path_owner
  run users__is_user_path "/usr/local/bin"
  assert_failure
}

@test "users__is_user_path: root, path owned by system user (UID 999) is system" {
  reload_lib
  users__is_root() { return 0; }
  users__resolve_home() { :; }
  users__uid_of_path_owner() { printf '999\n'; }
  os__kernel() { printf 'Linux\n'; }
  export -f users__is_root users__resolve_home users__uid_of_path_owner os__kernel
  run users__is_user_path "/home/linuxbrew/.linuxbrew"
  assert_failure
}

@test "users__is_user_path: root, path owned by nobody (UID 65534) is system" {
  reload_lib
  users__is_root() { return 0; }
  users__resolve_home() { :; }
  users__uid_of_path_owner() { printf '65534\n'; }
  export -f users__is_root users__resolve_home users__uid_of_path_owner
  run users__is_user_path "/srv/data"
  assert_failure
}

@test "users__is_user_path: root, macOS user (UID 501) is user-local" {
  reload_lib
  users__is_root() { return 0; }
  users__resolve_home() { :; }
  users__uid_of_path_owner() { printf '501\n'; }
  os__kernel() { printf 'Darwin\n'; }
  export -f users__is_root users__resolve_home users__uid_of_path_owner os__kernel
  run users__is_user_path "/Users/alice/.local"
  assert_success
}

@test "users__is_user_path: root, macOS system account (UID 499) is system" {
  reload_lib
  users__is_root() { return 0; }
  users__resolve_home() { :; }
  users__uid_of_path_owner() { printf '499\n'; }
  os__kernel() { printf 'Darwin\n'; }
  export -f users__is_root users__resolve_home users__uid_of_path_owner os__kernel
  run users__is_user_path "/var/lib/something"
  assert_failure
}

# ---------------------------------------------------------------------------
# users__is_user_path — specific user argument
# ---------------------------------------------------------------------------

@test "users__is_user_path: specific user, path under user's home is user-local" {
  reload_lib
  users__resolve_home() { printf '/home/alice\n'; }
  users__uid_of_user() { printf '1001\n'; }
  export -f users__resolve_home users__uid_of_user
  run users__is_user_path alice /home/alice/.local/bin
  assert_success
}

@test "users__is_user_path: specific user, path not under home but owned by user is user-local" {
  reload_lib
  users__resolve_home() { printf '/home/alice\n'; }
  users__uid_of_user() { printf '1001\n'; }
  users__uid_of_path_owner() { printf '1001\n'; }
  export -f users__resolve_home users__uid_of_user users__uid_of_path_owner
  run users__is_user_path alice /opt/alice-tools/bin
  assert_success
}

@test "users__is_user_path: specific user, system path not owned by user is system" {
  reload_lib
  users__resolve_home() { printf '/home/alice\n'; }
  users__uid_of_user() { printf '1001\n'; }
  users__uid_of_path_owner() { printf '0\n'; }
  export -f users__resolve_home users__uid_of_user users__uid_of_path_owner
  run users__is_user_path alice /usr/local/bin
  assert_failure
}

@test "users__is_user_path: specific user via --uid, path under user's home is user-local" {
  reload_lib
  users__resolve_home() { printf '/home/alice\n'; }
  export -f users__resolve_home
  run users__is_user_path --uid 1001 /home/alice/.config/nvim
  assert_success
}

@test "users__is_user_path: specific user via --uid, path owned by uid is user-local" {
  reload_lib
  users__resolve_home() { printf '/home/alice\n'; }
  users__uid_of_path_owner() { printf '1001\n'; }
  export -f users__resolve_home users__uid_of_path_owner
  run users__is_user_path --uid 1001 /opt/myapp
  assert_success
}

@test "users__is_user_path: specific user, exact home dir itself is system (no trailing-slash match)" {
  reload_lib
  users__resolve_home() { printf '/home/alice\n'; }
  users__uid_of_user() { printf '1001\n'; }
  users__uid_of_path_owner() { printf '0\n'; }
  export -f users__resolve_home users__uid_of_user users__uid_of_path_owner
  # /home/alice does not start with /home/alice/ so falls through to owner check → system
  run users__is_user_path alice /home/alice
  assert_failure
}

# ---------------------------------------------------------------------------
# bootstrap__shadow_utils
# ---------------------------------------------------------------------------

@test "bootstrap__shadow_utils: returns 0 immediately when groupadd is already on PATH" {
  ospkg__run() { return 1; }
  export -f ospkg__run
  create_fake_bin "groupadd"
  prepend_fake_bin_path
  run --separate-stderr bootstrap__shadow_utils
  assert_success
}

@test "bootstrap__shadow_utils: installs shadow-utils and returns 0 when groupadd is absent then installed" {
  ospkg__run() {
    printf '#!/bin/sh\n' > "${BATS_TEST_TMPDIR}/bin/groupadd"
    chmod +x "${BATS_TEST_TMPDIR}/bin/groupadd"
  }
  export -f ospkg__run
  begin_path_isolation mktemp chmod
  run --separate-stderr bootstrap__shadow_utils
  end_path_isolation
  assert_success
}

@test "bootstrap__shadow_utils: logs warning and returns 1 when groupadd remains absent after install attempt" {
  [[ "$(uname)" != "Darwin" ]] || skip "bootstrap__shadow_utils uses --skip-darwin and returns 0 on macOS"
  ospkg__run() { return 1; }
  export -f ospkg__run
  begin_path_isolation mktemp
  run bootstrap__shadow_utils
  end_path_isolation
  assert_failure
  assert_output --partial "shadow-utils"
}

# ---------------------------------------------------------------------------
# bootstrap__su
# ---------------------------------------------------------------------------

@test "bootstrap__su: returns 0 immediately when su is already on PATH" {
  ospkg__run() { return 1; }
  export -f ospkg__run
  create_fake_bin "su"
  prepend_fake_bin_path
  run --separate-stderr bootstrap__su
  assert_success
}

@test "bootstrap__su: installs su and returns 0 when absent then installed" {
  [[ "$(uname)" != "Darwin" ]] || skip "bootstrap__su does not install via ospkg on macOS (--skip-darwin)"
  ospkg__run() {
    printf '#!/bin/sh\n' > "${BATS_TEST_TMPDIR}/bin/su"
    chmod +x "${BATS_TEST_TMPDIR}/bin/su"
  }
  export -f ospkg__run
  begin_path_isolation mktemp chmod
  run --separate-stderr bootstrap__su
  end_path_isolation
  assert_success
}

@test "bootstrap__su: returns 1 when su remains absent after install attempt" {
  [[ "$(uname)" != "Darwin" ]] || skip "bootstrap__su uses --skip-darwin and returns 0 on macOS"
  ospkg__run() { return 1; }
  export -f ospkg__run
  begin_path_isolation mktemp
  run bootstrap__su
  end_path_isolation
  assert_failure
  assert_output --partial "'su' is required"
}

# ---------------------------------------------------------------------------
# users__gid_of_group
# ---------------------------------------------------------------------------

@test "users__gid_of_group: returns GID via getent" {
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat > "${BATS_TEST_TMPDIR}/bin/getent" << 'EOF'
#!/bin/sh
printf 'testgroup:x:4567:\n'
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/getent"
  prepend_fake_bin_path
  run users__gid_of_group "testgroup"
  assert_success
  assert_output "4567"
}

@test "users__gid_of_group: falls back to /etc/group awk scan when getent is absent" {
  bootstrap__getent() { return 1; }
  export -f bootstrap__getent
  _real_group="$(id -gn)"
  _real_gid="$(id -g)"
  run users__gid_of_group "$_real_group"
  assert_success
  assert_output "$_real_gid"
}

@test "users__gid_of_group: returns 1 for non-existent group" {
  bootstrap__getent() { return 1; }
  export -f bootstrap__getent
  run users__gid_of_group "___no_such_group_xyz___"
  assert_failure
}

# ---------------------------------------------------------------------------
# users__group_of_gid
# ---------------------------------------------------------------------------

@test "users__group_of_gid: returns group name via getent" {
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat > "${BATS_TEST_TMPDIR}/bin/getent" << 'EOF'
#!/bin/sh
printf 'mygroup:x:9876:\n'
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/getent"
  prepend_fake_bin_path
  run users__group_of_gid "9876"
  assert_success
  assert_output "mygroup"
}

@test "users__group_of_gid: falls back to /etc/group awk scan when getent is absent" {
  bootstrap__getent() { return 1; }
  export -f bootstrap__getent
  _real_gid="$(id -g)"
  _real_group="$(id -gn)"
  run users__group_of_gid "$_real_gid"
  assert_success
  assert_output "$_real_group"
}

@test "users__group_of_gid: returns 1 for non-existent GID" {
  bootstrap__getent() { return 1; }
  export -f bootstrap__getent
  run users__group_of_gid "99999999"
  assert_failure
}

# ---------------------------------------------------------------------------
# users__users_by_primary_gid
# ---------------------------------------------------------------------------

@test "users__users_by_primary_gid: lists current user when queried by their primary GID" {
  _cur_user="$(id -un)"
  _cur_gid="$(id -g)"
  run --separate-stderr users__users_by_primary_gid "$_cur_gid"
  assert_success
  assert_output --partial "$_cur_user"
}

@test "users__users_by_primary_gid: produces empty output for a non-existent GID" {
  run --separate-stderr users__users_by_primary_gid "99999999"
  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# users__group_exists
# ---------------------------------------------------------------------------

@test "users__group_exists: returns 0 when group is found via getent" {
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat > "${BATS_TEST_TMPDIR}/bin/getent" << 'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/getent"
  prepend_fake_bin_path
  run users__group_exists "anygroup"
  assert_success
}

@test "users__group_exists: returns 1 when group is not found via getent" {
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat > "${BATS_TEST_TMPDIR}/bin/getent" << 'EOF'
#!/bin/sh
exit 1
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/getent"
  prepend_fake_bin_path
  run users__group_exists "___no_such_group_xyz___"
  assert_failure
}

@test "users__group_exists: awk fallback — returns 0 for real group name on this host" {
  bootstrap__getent() { return 1; }
  export -f bootstrap__getent
  _real_group="$(id -gn)"
  run users__group_exists "$_real_group"
  assert_success
}

@test "users__group_exists: awk fallback — returns 0 for real GID on this host" {
  bootstrap__getent() { return 1; }
  export -f bootstrap__getent
  _real_gid="$(id -g)"
  run users__group_exists "$_real_gid"
  assert_success
}

@test "users__group_exists: awk fallback — returns 1 for non-existent group" {
  bootstrap__getent() { return 1; }
  export -f bootstrap__getent
  run users__group_exists "___no_such_group_xyz___"
  assert_failure
}

# ---------------------------------------------------------------------------
# users__create_group
# ---------------------------------------------------------------------------

@test "users__create_group: invokes groupadd with --gid when specified" {
  bootstrap__shadow_utils() { return 0; }
  users__run_privileged() { printf '%s\n' "$@"; }
  export -f bootstrap__shadow_utils users__run_privileged
  run users__create_group "devs" --gid "1234"
  assert_success
  assert_output "groupadd
--gid
1234
devs"
}

@test "users__create_group: invokes groupadd without --gid when omitted" {
  bootstrap__shadow_utils() { return 0; }
  users__run_privileged() { printf '%s\n' "$@"; }
  export -f bootstrap__shadow_utils users__run_privileged
  run users__create_group "devs"
  assert_success
  assert_output "groupadd
devs"
}

@test "users__create_group: returns 1 when shadow-utils cannot be installed" {
  bootstrap__shadow_utils() { return 1; }
  export -f bootstrap__shadow_utils
  run users__create_group "devs" --gid "1234"
  assert_failure
}

# ---------------------------------------------------------------------------
# users__delete_group
# ---------------------------------------------------------------------------

@test "users__delete_group: invokes groupdel with the given group name" {
  bootstrap__shadow_utils() { return 0; }
  users__run_privileged() { printf '%s\n' "$@"; }
  export -f bootstrap__shadow_utils users__run_privileged
  run users__delete_group "oldgroup"
  assert_success
  assert_output "groupdel
oldgroup"
}

@test "users__delete_group: logs error and returns 1 when groupdel fails" {
  bootstrap__shadow_utils() { return 0; }
  users__run_privileged() { return 1; }
  export -f bootstrap__shadow_utils users__run_privileged
  run users__delete_group "badgroup"
  assert_failure
  assert_output --partial "Failed to delete group 'badgroup'"
}

@test "users__delete_group: returns 1 when shadow-utils cannot be installed" {
  bootstrap__shadow_utils() { return 1; }
  export -f bootstrap__shadow_utils
  run users__delete_group "oldgroup"
  assert_failure
}

# ---------------------------------------------------------------------------
# users__delete_user
# ---------------------------------------------------------------------------

@test "users__delete_user: invokes userdel with the given username" {
  bootstrap__shadow_utils() { return 0; }
  users__run_privileged() { printf '%s\n' "$@"; }
  export -f bootstrap__shadow_utils users__run_privileged
  run users__delete_user "alice"
  assert_success
  assert_output "userdel
alice"
}

@test "users__delete_user: logs error and returns 1 when userdel fails" {
  bootstrap__shadow_utils() { return 0; }
  users__run_privileged() { return 1; }
  export -f bootstrap__shadow_utils users__run_privileged
  run users__delete_user "alice"
  assert_failure
  assert_output --partial "Failed to delete user 'alice'"
}

@test "users__delete_user: returns 1 when shadow-utils cannot be installed" {
  bootstrap__shadow_utils() { return 1; }
  export -f bootstrap__shadow_utils
  run users__delete_user "alice"
  assert_failure
}

# ---------------------------------------------------------------------------
# users__create_user
# ---------------------------------------------------------------------------

@test "users__create_user: invokes useradd with all flags in correct order" {
  bootstrap__shadow_utils() { return 0; }
  users__run_privileged() { printf '%s\n' "$@"; }
  export -f bootstrap__shadow_utils users__run_privileged
  run users__create_user "alice" --no-create-home --home "/home/alice" --gid "1000" --shell "/bin/bash" --uid "1001"
  assert_success
  assert_output "useradd
--no-create-home
--home-dir
/home/alice
--gid
1000
--shell
/bin/bash
--uid
1001
alice"
}

@test "users__create_user: maps --home flag to --home-dir in the useradd command" {
  bootstrap__shadow_utils() { return 0; }
  users__run_privileged() { printf '%s\n' "$@"; }
  export -f bootstrap__shadow_utils users__run_privileged
  run users__create_user "bob" --home "/home/bob"
  assert_success
  assert_output "useradd
--home-dir
/home/bob
bob"
}

@test "users__create_user: invokes useradd with name only when no flags are given" {
  bootstrap__shadow_utils() { return 0; }
  users__run_privileged() { printf '%s\n' "$@"; }
  export -f bootstrap__shadow_utils users__run_privileged
  run users__create_user "charlie"
  assert_success
  assert_output "useradd
charlie"
}

@test "users__create_user: omits --no-create-home from useradd when flag is not given" {
  bootstrap__shadow_utils() { return 0; }
  users__run_privileged() { printf '%s\n' "$@"; }
  export -f bootstrap__shadow_utils users__run_privileged
  run users__create_user "charlie" --uid "500"
  assert_success
  assert_output "useradd
--uid
500
charlie"
}

@test "users__create_user: returns 1 when shadow-utils cannot be installed" {
  bootstrap__shadow_utils() { return 1; }
  export -f bootstrap__shadow_utils
  run users__create_user "alice" --uid "1001"
  assert_failure
}

# ---------------------------------------------------------------------------
# users__add_to_group
# ---------------------------------------------------------------------------

@test "users__add_to_group: invokes usermod -aG with group before user" {
  bootstrap__shadow_utils() { return 0; }
  users__run_privileged() { printf '%s\n' "$@"; }
  export -f bootstrap__shadow_utils users__run_privileged
  run users__add_to_group "alice" "devs"
  assert_success
  assert_output "usermod
-aG
devs
alice"
}

@test "users__add_to_group: logs warning and returns 1 when usermod fails" {
  bootstrap__shadow_utils() { return 0; }
  users__run_privileged() { return 1; }
  export -f bootstrap__shadow_utils users__run_privileged
  run users__add_to_group "alice" "devs"
  assert_failure
  assert_output --partial "Failed to add 'alice' to group 'devs'"
}

@test "users__add_to_group: returns 1 when shadow-utils cannot be installed" {
  bootstrap__shadow_utils() { return 1; }
  export -f bootstrap__shadow_utils
  run users__add_to_group "alice" "devs"
  assert_failure
}

# ---------------------------------------------------------------------------
# users__first_writeable_path
# ---------------------------------------------------------------------------

@test "users__first_writeable_path: returns first path when writable" {
  users__can_write() { [[ "$1" == "/usr/local" ]]; }
  result="$(users__first_writeable_path -- "/usr/local" "${HOME}/.local")"
  assert [ "${result}" = "/usr/local" ]
}

@test "users__first_writeable_path: falls back to second path when first is not writable" {
  users__can_write() { [[ "$1" != "/usr/local" ]]; }
  result="$(users__first_writeable_path -- "/usr/local" "${HOME}/.local")"
  assert [ "${result}" = "${HOME}/.local" ]
}

@test "users__first_writeable_path: fails when no path in group is writable" {
  users__can_write() { return 1; }
  export -f users__can_write
  run --separate-stderr users__first_writeable_path -- "/usr/local" "${HOME}/.local"
  assert_failure
  output="${stderr}"
  assert_output --partial "no writable path found"
}

@test "users__first_writeable_path: uses platform-matching group over fallback" {
  load 'helpers/ctx'
  load 'helpers/test_tools'
  test_tools__wire_jq_yq
  ctx_test__reset
  ctx_test__seed_plat kernel=Darwin
  users__can_write() { return 0; }
  export -f users__can_write
  result="$(users__first_writeable_path -- '{plat.kernel: Darwin}' "/opt/homebrew" -- "/usr/local" "${HOME}/.local")"
  assert [ "${result}" = "/opt/homebrew" ]
}

@test "users__first_writeable_path: skips non-matching group and uses fallback" {
  load 'helpers/ctx'
  load 'helpers/test_tools'
  test_tools__wire_jq_yq
  ctx_test__reset
  ctx_test__seed_plat kernel=linux
  users__can_write() { return 0; }
  export -f users__can_write
  result="$(users__first_writeable_path -- '{plat.kernel: Darwin}' "/opt/homebrew" -- "/usr/local" "${HOME}/.local")"
  assert [ "${result}" = "/usr/local" ]
}

@test "users__first_writeable_path: fails when no group's platform condition matches" {
  load 'helpers/ctx'
  load 'helpers/test_tools'
  test_tools__wire_jq_yq
  ctx_test__reset
  ctx_test__seed_plat kernel=linux
  users__can_write() { return 0; }
  export -f users__can_write
  run --separate-stderr users__first_writeable_path -- '{plat.kernel: Darwin}' "/opt/homebrew"
  assert_failure
  output="${stderr}"
  assert_output --partial "no platform group matched"
}

@test "users__first_writeable_path: feat.version lte constraint selects matching group" {
  load 'helpers/ctx'
  load 'helpers/test_tools'
  test_tools__wire_jq_yq
  ctx_test__reset
  ctx__set feat.version=12.1.2
  users__can_write() { return 0; }
  export -f users__can_write
  result="$(users__first_writeable_path -- $'feat.version:\n  lte: "12.1.2"' "/opt/old" -- "/usr/local")"
  assert [ "${result}" = "/opt/old" ]
}

@test "users__first_writeable_path: resolves single path from unconditional group" {
  users__can_write() { return 0; }
  result="$(users__first_writeable_path -- "/usr/local")"
  assert [ "${result}" = "/usr/local" ]
}

# ---------------------------------------------------------------------------
# users__expand_path
# ---------------------------------------------------------------------------

@test "users__expand_path: absolute path returned unchanged (fast path, no subprocess)" {
  run users__expand_path "/usr/local/bin"
  assert_success
  assert_output "/usr/local/bin"
}

@test "users__expand_path: plain string without dollar or tilde returned unchanged" {
  run users__expand_path "no-dollar-no-tilde"
  assert_success
  assert_output "no-dollar-no-tilde"
}

@test "users__expand_path: expands leading ~ to HOME" {
  HOME="/home/testuser"
  export HOME
  run users__expand_path "~"
  assert_success
  assert_output "/home/testuser"
}

@test "users__expand_path: expands ~/subdir to HOME/subdir" {
  HOME="/home/testuser"
  export HOME
  run users__expand_path "~/subdir"
  assert_success
  assert_output "/home/testuser/subdir"
}

@test "users__expand_path: expands \$HOME/subdir" {
  HOME="/home/testuser"
  export HOME
  # shellcheck disable=SC2016
  run users__expand_path '$HOME/subdir'
  assert_success
  assert_output "/home/testuser/subdir"
}

@test "users__expand_path: expands \${XDG_CONFIG_HOME:-\${HOME}/.config}/app when XDG unset" {
  HOME="/home/testuser"
  export HOME
  unset XDG_CONFIG_HOME
  # shellcheck disable=SC2016
  run users__expand_path '${XDG_CONFIG_HOME:-${HOME}/.config}/myapp'
  assert_success
  assert_output "/home/testuser/.config/myapp"
}

@test "users__expand_path: expands \${XDG_CONFIG_HOME:-\${HOME}/.config}/app when XDG set" {
  HOME="/home/testuser"
  XDG_CONFIG_HOME="/custom/config"
  export HOME XDG_CONFIG_HOME
  # shellcheck disable=SC2016
  run users__expand_path '${XDG_CONFIG_HOME:-${HOME}/.config}/myapp'
  assert_success
  assert_output "/custom/config/myapp"
}

@test "users__expand_path: --user with current user resolves correctly" {
  HOME="/home/testuser"
  export HOME
  _me="$(id -un)"
  # shellcheck disable=SC2016
  run users__expand_path --user "$_me" '$HOME/foo'
  assert_success
  assert_output "/home/testuser/foo"
}

@test "users__expand_path: rejects expression containing \$() (command substitution)" {
  # shellcheck disable=SC2016
  run users__expand_path '$(echo /tmp)'
  assert_failure
  assert_output --partial "unsafe characters"
}

@test "users__expand_path: rejects expression containing backtick" {
  run users__expand_path '`echo /tmp`'
  assert_failure
  assert_output --partial "unsafe characters"
}

@test "users__expand_path: rejects expression containing semicolon" {
  # shellcheck disable=SC2016
  run users__expand_path '$HOME;rm -rf /'
  assert_failure
  assert_output --partial "unsafe characters"
}

@test "users__expand_path: rejects expression containing pipe" {
  # shellcheck disable=SC2016
  run users__expand_path '$HOME|cat /etc/passwd'
  assert_failure
  assert_output --partial "unsafe characters"
}

# ---------------------------------------------------------------------------
# users__expand_multi / users__expand_string
# ---------------------------------------------------------------------------

@test "users__expand_multi: spawns the login shell at most once for a whole batch" {
  reload_lib
  local _calls="${BATS_TEST_TMPDIR}/calls"
  : > "$_calls"
  # shellcheck disable=SC2329
  users__run_as() {
    echo call >> "$_calls"
    shift
    [[ "$1" == "--" ]] && shift
    "$@"
  }
  export -f users__run_as
  _me="$(id -un)"
  run users__expand_multi --user "$_me" -- 'plain' '${FOO}' 'also $BAR has vars'
  assert_success
  [[ "$(wc -l < "$_calls")" -le 1 ]]
}

@test "users__expand_multi: skips the login shell entirely when nothing needs expansion" {
  reload_lib
  local _calls="${BATS_TEST_TMPDIR}/calls"
  : > "$_calls"
  # shellcheck disable=SC2329
  users__run_as() { echo call >> "$_calls"; }
  export -f users__run_as
  run users__expand_multi --user testuser -- 'plain' 'no vars here'
  assert_success
  [[ "$(wc -l < "$_calls")" -eq 0 ]]
}

@test "users__expand_multi: preserves input order in NUL-terminated output" {
  reload_lib
  run bash -c '. "$1/__init__.bash" && mapfile -d "" -t out < <(users__expand_multi -- "a" "b" "c"); printf "%s\n" "${out[@]}"' _ "${LIB_ROOT}"
  assert_output "a
b
c"
}

@test "users__expand_multi: expands \${VAR} references" {
  reload_lib
  _me="$(id -un)"
  run bash -c 'export FOO=bar; . "$1/__init__.bash" && mapfile -d "" -t out < <(users__expand_multi --user "$2" -- "plain" "\${FOO}" "also \$FOO here"); printf "%s\n" "${out[@]}"' _ "${LIB_ROOT}" "$_me"
  assert_output "plain
bar
also bar here"
}

@test "users__expand_multi: does not execute \$(...) command substitution" {
  reload_lib
  _me="$(id -un)"
  local _marker="${BATS_TEST_TMPDIR}/marker"
  rm -f "$_marker"
  run bash -c '. "$1/__init__.bash" && users__expand_multi --user "$2" -- "before \$(touch $3) after"' _ "${LIB_ROOT}" "$_me" "$_marker"
  assert_success
  [[ ! -f "$_marker" ]]
}

@test "users__expand_multi: does not execute backtick command substitution" {
  reload_lib
  _me="$(id -un)"
  local _marker="${BATS_TEST_TMPDIR}/marker2"
  rm -f "$_marker"
  run bash -c '. "$1/__init__.bash" && users__expand_multi --user "$2" -- "before \`touch $3\` after"' _ "${LIB_ROOT}" "$_me" "$_marker"
  assert_success
  [[ ! -f "$_marker" ]]
}

@test "users__expand_multi: preserves embedded newlines in a single field" {
  reload_lib
  run bash -c '. "$1/__init__.bash" && mapfile -d "" -t out < <(users__expand_multi -- "$(printf "multi\nline")"); printf "%s\n" "${out[0]}"' _ "${LIB_ROOT}"
  assert_output "multi
line"
}

@test "users__expand_string: thin wrapper delegates correctly" {
  reload_lib
  run users__expand_string 'literal, no vars'
  assert_output "literal, no vars"
}

@test "users__expand_string: expands a single \${VAR} reference" {
  reload_lib
  run bash -c 'export FOO=bar; . "$1/__init__.bash" && users__expand_string "\${FOO}-suffix"' _ "${LIB_ROOT}"
  assert_output "bar-suffix"
}

# ---------------------------------------------------------------------------
# users__resolve_list --all
# ---------------------------------------------------------------------------

@test "users__resolve_list --all: includes only regular, interactive-shell users" {
  reload_lib
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat > "${BATS_TEST_TMPDIR}/bin/getent" << 'EOF'
#!/bin/sh
if [ "$1" = "passwd" ] && [ $# -eq 1 ]; then
  cat << 'PASSWD'
root:x:0:0::/root:/bin/bash
daemon:x:1:1::/usr/sbin:/usr/sbin/nologin
alice:x:1000:1000::/home/alice:/bin/bash
bob:x:1001:1001::/home/bob:/bin/zsh
nobody:x:65534:65534::/nonexistent:/usr/sbin/nologin
service:x:999:999::/var/lib/service:/bin/false
PASSWD
fi
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/getent"
  prepend_fake_bin_path
  bootstrap__getent() { return 0; }
  export -f bootstrap__getent
  run users__resolve_list --current false --remote false --container false --all
  assert_success
  assert_output "alice
bob"
}

@test "users__resolve_list --all: deduplicates against explicit --user additions" {
  reload_lib
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat > "${BATS_TEST_TMPDIR}/bin/getent" << 'EOF'
#!/bin/sh
if [ "$1" = "passwd" ] && [ $# -eq 1 ]; then
  cat << 'PASSWD'
alice:x:1000:1000::/home/alice:/bin/bash
PASSWD
fi
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/getent"
  prepend_fake_bin_path
  bootstrap__getent() { return 0; }
  export -f bootstrap__getent
  run users__resolve_list --current false --remote false --container false --user alice --all
  assert_success
  assert_output "alice"
}

# ---------------------------------------------------------------------------
# users__nonroot_share_dir
# ---------------------------------------------------------------------------

@test "users__nonroot_share_dir: substitutes the target user's home for the current user's home prefix" {
  reload_lib
  _FEAT_SHARE_DIR_NONROOT="/home/buildinguser/.local/share/testns/testfeat"
  # shellcheck disable=SC2329
  users__resolve_home() {
    if [[ -n "${1-}" ]]; then printf '/home/otheruser\n'; else printf '/home/buildinguser\n'; fi
  }
  export -f users__resolve_home
  run users__nonroot_share_dir otheruser
  assert_success
  assert_output "/home/otheruser/.local/share/testns/testfeat"
}

@test "users__nonroot_share_dir: resolves the current-user prefix via users__resolve_home, NOT the \$HOME variable" {
  # Regression test: this function is commonly called from within a subshell
  # that has transiently exported HOME to a DIFFERENT user's home (e.g. while
  # dispatching a per-user operation) for unrelated tilde-expansion purposes.
  # Reading $HOME directly here would strip the wrong prefix (or none at
  # all), silently producing a garbled path such as
  # "/root/home/buildinguser/.local/share/...". Resolving the current
  # identity via users__resolve_home (no args) must be immune to that.
  reload_lib
  _FEAT_SHARE_DIR_NONROOT="/home/buildinguser/.local/share/testns/testfeat"
  # shellcheck disable=SC2329
  users__resolve_home() {
    if [[ -n "${1-}" ]]; then printf '/home/otheruser\n'; else printf '/home/buildinguser\n'; fi
  }
  export -f users__resolve_home
  HOME=/home/otheruser run users__nonroot_share_dir otheruser
  assert_success
  assert_output "/home/otheruser/.local/share/testns/testfeat"
}

@test "users__nonroot_share_dir: fails when the user's home cannot be resolved" {
  reload_lib
  _FEAT_SHARE_DIR_NONROOT="${HOME}/.local/share/testns/testfeat"
  users__resolve_home() { printf ''; }
  export -f users__resolve_home
  run users__nonroot_share_dir ghostuser
  assert_failure
}

@test "users__nonroot_share_dir: fails when username is empty" {
  reload_lib
  _FEAT_SHARE_DIR_NONROOT="${HOME}/.local/share/testns/testfeat"
  run users__nonroot_share_dir ""
  assert_failure
}
