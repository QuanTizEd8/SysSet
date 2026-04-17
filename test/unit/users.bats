#!/usr/bin/env bats
# Unit tests for lib/users.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  reload_lib users.sh
}

# ---------------------------------------------------------------------------
# users__resolve_list
# ---------------------------------------------------------------------------

@test "users__resolve_list includes SUDO_USER when ADD_CURRENT_USER=true" {
  ADD_CURRENT_USER=true \
    SUDO_USER=alice \
    ADD_REMOTE_USER=false \
    ADD_CONTAINER_USER=false \
    ADD_USERS="" \
    run users__resolve_list
  assert_output "alice"
}

@test "users__resolve_list includes _REMOTE_USER when ADD_REMOTE_USER=true" {
  ADD_CURRENT_USER=false \
    _REMOTE_USER=bob \
    ADD_REMOTE_USER=true \
    ADD_CONTAINER_USER=false \
    ADD_USERS="" \
    run users__resolve_list
  assert_output "bob"
}

@test "users__resolve_list includes _CONTAINER_USER when ADD_CONTAINER_USER=true" {
  ADD_CURRENT_USER=false \
    ADD_REMOTE_USER=false \
    _CONTAINER_USER=carol \
    ADD_CONTAINER_USER=true \
    ADD_USERS="" \
    run users__resolve_list
  assert_output "carol"
}

@test "users__resolve_list includes extra users from ADD_USERS" {
  ADD_CURRENT_USER=false \
    ADD_REMOTE_USER=false \
    ADD_CONTAINER_USER=false \
    ADD_USERS="dave,eve" \
    run users__resolve_list
  assert_output "dave
eve"
}

@test "users__resolve_list deduplicates users" {
  ADD_CURRENT_USER=false \
    ADD_REMOTE_USER=false \
    ADD_CONTAINER_USER=false \
    ADD_USERS="alice,alice,bob" \
    run users__resolve_list
  assert_output "alice
bob"
}

@test "users__resolve_list includes root as fallback when it is the only user" {
  # When the build user is root and no other non-root users are auto-detected,
  # root is included so the feature has a target to configure (e.g. plain
  # container images or standalone macOS use with no remoteUser).
  ADD_CURRENT_USER=true \
    SUDO_USER=root \
    ADD_REMOTE_USER=false \
    ADD_CONTAINER_USER=false \
    ADD_USERS="" \
    run users__resolve_list
  assert_output "root"
  assert_success
}

@test "users__resolve_list excludes root when a non-root user is also detected" {
  # Root must not be added when a non-root remoteUser / containerUser is present;
  # the build runs as root but the target for configuration is the named user.
  ADD_CURRENT_USER=true \
    SUDO_USER=root \
    ADD_REMOTE_USER=true \
    _REMOTE_USER=alice \
    ADD_CONTAINER_USER=false \
    ADD_USERS="" \
    run users__resolve_list
  assert_output "alice"
  assert_success
}

@test "users__resolve_list allows root when explicitly in ADD_USERS" {
  # Explicitly listing root in ADD_USERS is a deliberate override
  # (used by install-podman to configure rootless Podman for the root user).
  ADD_CURRENT_USER=false \
    ADD_REMOTE_USER=false \
    ADD_CONTAINER_USER=false \
    ADD_USERS="root,alice" \
    run users__resolve_list
  assert_output "root
alice"
}

@test "users__resolve_list returns empty output when all sources are disabled" {
  ADD_CURRENT_USER=false \
    ADD_REMOTE_USER=false \
    ADD_CONTAINER_USER=false \
    ADD_USERS="" \
    run users__resolve_list
  assert_output ""
  assert_success
}

@test "users__resolve_list trims spaces around names in ADD_USERS" {
  ADD_CURRENT_USER=false \
    ADD_REMOTE_USER=false \
    ADD_CONTAINER_USER=false \
    ADD_USERS=" alice , bob " \
    run users__resolve_list
  assert_output "alice
bob"
}

# ---------------------------------------------------------------------------
# users__set_login_shell
# ---------------------------------------------------------------------------

@test "users__set_login_shell warns when chsh is not installed" {
  reload_lib users.sh
  # Save PATH first; export an empty fake bin dir so chsh is not found.
  local _saved="$PATH"
  export PATH="${BATS_TEST_TMPDIR}/bin"
  run users__set_login_shell "/usr/bin/zsh" "alice"
  export PATH="$_saved"
  assert_success
  assert_output --partial "chsh not found"
}

@test "users__set_login_shell skips user whose shell is already set" {
  reload_lib users.sh
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
  reload_lib users.sh
  create_fake_bin "chsh" ""
  # fake getent returns a passwd line with a different shell
  cat > "${BATS_TEST_TMPDIR}/bin/getent" << 'EOF'
#!/bin/sh
printf 'alice:x:1000:1000::/home/alice:/bin/bash\n'
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/getent"
  prepend_fake_bin_path
  run users__set_login_shell "/usr/bin/zsh" "alice"
  assert_success
  assert_output --partial "set to '/usr/bin/zsh'"
}
