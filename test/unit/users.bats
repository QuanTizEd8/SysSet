#!/usr/bin/env bats
# Unit tests for lib/users.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  reload_lib users.sh
}

# ---------------------------------------------------------------------------
# users::resolve_list
# ---------------------------------------------------------------------------

@test "users::resolve_list includes SUDO_USER when ADD_CURRENT_USER_CONFIG=true" {
  ADD_CURRENT_USER_CONFIG=true \
    SUDO_USER=alice \
    ADD_REMOTE_USER_CONFIG=false \
    ADD_CONTAINER_USER_CONFIG=false \
    ADD_USER_CONFIG="" \
    run users::resolve_list
  assert_output "alice"
}

@test "users::resolve_list includes _REMOTE_USER when ADD_REMOTE_USER_CONFIG=true" {
  ADD_CURRENT_USER_CONFIG=false \
    _REMOTE_USER=bob \
    ADD_REMOTE_USER_CONFIG=true \
    ADD_CONTAINER_USER_CONFIG=false \
    ADD_USER_CONFIG="" \
    run users::resolve_list
  assert_output "bob"
}

@test "users::resolve_list includes _CONTAINER_USER when ADD_CONTAINER_USER_CONFIG=true" {
  ADD_CURRENT_USER_CONFIG=false \
    ADD_REMOTE_USER_CONFIG=false \
    _CONTAINER_USER=carol \
    ADD_CONTAINER_USER_CONFIG=true \
    ADD_USER_CONFIG="" \
    run users::resolve_list
  assert_output "carol"
}

@test "users::resolve_list includes extra users from ADD_USER_CONFIG" {
  ADD_CURRENT_USER_CONFIG=false \
    ADD_REMOTE_USER_CONFIG=false \
    ADD_CONTAINER_USER_CONFIG=false \
    ADD_USER_CONFIG="dave,eve" \
    run users::resolve_list
  assert_output "dave
eve"
}

@test "users::resolve_list deduplicates users" {
  ADD_CURRENT_USER_CONFIG=false \
    ADD_REMOTE_USER_CONFIG=false \
    ADD_CONTAINER_USER_CONFIG=false \
    ADD_USER_CONFIG="alice,alice,bob" \
    run users::resolve_list
  assert_output "alice
bob"
}

@test "users::resolve_list excludes root from auto-detected paths" {
  # Root must be excluded when it comes from SUDO_USER / _REMOTE_USER / _CONTAINER_USER
  # (the build user is root, but it should not be treated as a target user).
  ADD_CURRENT_USER_CONFIG=true \
    SUDO_USER=root \
    ADD_REMOTE_USER_CONFIG=true \
    _REMOTE_USER=root \
    ADD_CONTAINER_USER_CONFIG=true \
    _CONTAINER_USER=root \
    ADD_USER_CONFIG="" \
    run users::resolve_list
  assert_output ""
  assert_success
}

@test "users::resolve_list allows root when explicitly in ADD_USER_CONFIG" {
  # Explicitly listing root in ADD_USER_CONFIG is a deliberate override
  # (used by install-podman to configure rootless Podman for the root user).
  ADD_CURRENT_USER_CONFIG=false \
    ADD_REMOTE_USER_CONFIG=false \
    ADD_CONTAINER_USER_CONFIG=false \
    ADD_USER_CONFIG="root,alice" \
    run users::resolve_list
  assert_output "root
alice"
}

@test "users::resolve_list returns empty output when all sources are disabled" {
  ADD_CURRENT_USER_CONFIG=false \
    ADD_REMOTE_USER_CONFIG=false \
    ADD_CONTAINER_USER_CONFIG=false \
    ADD_USER_CONFIG="" \
    run users::resolve_list
  assert_output ""
  assert_success
}

@test "users::resolve_list trims spaces around names in ADD_USER_CONFIG" {
  ADD_CURRENT_USER_CONFIG=false \
    ADD_REMOTE_USER_CONFIG=false \
    ADD_CONTAINER_USER_CONFIG=false \
    ADD_USER_CONFIG=" alice , bob " \
    run users::resolve_list
  assert_output "alice
bob"
}

# ---------------------------------------------------------------------------
# users::set_login_shell
# ---------------------------------------------------------------------------

@test "users::set_login_shell warns when chsh is not installed" {
  reload_lib users.sh
  # Save PATH first; export an empty fake bin dir so chsh is not found.
  local _saved="$PATH"
  export PATH="${BATS_TEST_TMPDIR}/bin"
  run users::set_login_shell "/usr/bin/zsh" "alice"
  export PATH="$_saved"
  assert_success
  assert_output --partial "chsh not found"
}

@test "users::set_login_shell skips user whose shell is already set" {
  reload_lib users.sh
  create_fake_bin "chsh" ""
  # fake getent returns a passwd line where the shell is already /usr/bin/zsh
  cat > "${BATS_TEST_TMPDIR}/bin/getent" << 'EOF'
#!/bin/sh
printf 'alice:x:1000:1000::/home/alice:/usr/bin/zsh\n'
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/getent"
  prepend_fake_bin_path
  run users::set_login_shell "/usr/bin/zsh" "alice"
  assert_success
  assert_output --partial "already set"
}

@test "users::set_login_shell changes the shell when it differs" {
  reload_lib users.sh
  create_fake_bin "chsh" ""
  # fake getent returns a passwd line with a different shell
  cat > "${BATS_TEST_TMPDIR}/bin/getent" << 'EOF'
#!/bin/sh
printf 'alice:x:1000:1000::/home/alice:/bin/bash\n'
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/getent"
  prepend_fake_bin_path
  run users::set_login_shell "/usr/bin/zsh" "alice"
  assert_success
  assert_output --partial "set to '/usr/bin/zsh'"
}
