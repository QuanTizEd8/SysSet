#!/usr/bin/env bats
# Unit tests for lib/shell.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
}

# ---------------------------------------------------------------------------
# shell::detect_bashrc  (strings-probe path, then os::platform fallback)
# ---------------------------------------------------------------------------

@test "shell::detect_bashrc returns path from strings probe" {
  reload_lib shell.sh
  # Fake strings to return the compiled-in bashrc path.
  strings() { echo "/etc/bash.bashrc"; }
  export -f strings
  run shell::detect_bashrc
  assert_output "/etc/bash.bashrc"
}

@test "shell::detect_bashrc returns /etc/bashrc for rhel via platform fallback" {
  reload_lib shell.sh
  # No strings output → fall through to os::platform.
  strings() { :; }
  export -f strings
  _OS_ID="fedora"
  _OS_ID_LIKE=""
  _OS_RELEASE_LOADED=1
  run shell::detect_bashrc
  assert_output "/etc/bashrc"
}

@test "shell::detect_bashrc returns /etc/bash/bashrc for alpine via platform fallback" {
  reload_lib shell.sh
  strings() { :; }
  export -f strings
  _OS_ID="alpine"
  _OS_ID_LIKE=""
  _OS_RELEASE_LOADED=1
  run shell::detect_bashrc
  assert_output "/etc/bash/bashrc"
}

@test "shell::detect_bashrc returns /etc/bash.bashrc as default fallback" {
  reload_lib shell.sh
  strings() { :; }
  export -f strings
  _OS_ID="ubuntu"
  _OS_ID_LIKE=""
  _OS_RELEASE_LOADED=1
  run shell::detect_bashrc
  assert_output "/etc/bash.bashrc"
}

# ---------------------------------------------------------------------------
# shell::detect_zshdir  (strings-probe path, then os::platform fallback)
# ---------------------------------------------------------------------------

@test "shell::detect_zshdir returns /etc/zsh from strings probe" {
  reload_lib shell.sh
  strings() { echo "/etc/zsh/zshenv"; }
  export -f strings
  run shell::detect_zshdir
  assert_output "/etc/zsh"
}

@test "shell::detect_zshdir returns /etc from strings probe when zshenv is at /etc/zshenv" {
  reload_lib shell.sh
  strings() { echo "/etc/zshenv"; }
  export -f strings
  run shell::detect_zshdir
  assert_output "/etc"
}

@test "shell::detect_zshdir returns /etc for rhel via platform fallback" {
  reload_lib shell.sh
  strings() { :; }
  export -f strings
  _OS_ID="fedora"
  _OS_ID_LIKE=""
  _OS_RELEASE_LOADED=1
  run shell::detect_zshdir
  assert_output "/etc"
}

@test "shell::detect_zshdir returns /etc/zsh as default fallback" {
  reload_lib shell.sh
  strings() { :; }
  export -f strings
  _OS_ID="ubuntu"
  _OS_ID_LIKE=""
  _OS_RELEASE_LOADED=1
  run shell::detect_zshdir
  assert_output "/etc/zsh"
}

# ---------------------------------------------------------------------------
# shell::write_block
# ---------------------------------------------------------------------------

@test "shell::write_block appends a new block to a file" {
  reload_lib shell.sh
  local _f="${BATS_TEST_TMPDIR}/rc"
  shell::write_block --file "$_f" --marker "mytest" --content "export FOO=bar"
  assert_file_exists "$_f"
  run grep -c "# >>> mytest >>>" "$_f"
  assert_output "1"
  run grep "export FOO=bar" "$_f"
  assert_success
}

@test "shell::write_block updates existing block in place" {
  reload_lib shell.sh
  local _f="${BATS_TEST_TMPDIR}/rc2"
  shell::write_block --file "$_f" --marker "mytest" --content "export FOO=bar"
  shell::write_block --file "$_f" --marker "mytest" --content "export FOO=baz"
  run grep -c "# >>> mytest >>>" "$_f"
  assert_output "1"
  run grep "export FOO=baz" "$_f"
  assert_success
  run grep "export FOO=bar" "$_f"
  assert_failure
}

@test "shell::write_block creates parent directories" {
  reload_lib shell.sh
  local _f="${BATS_TEST_TMPDIR}/subdir/rc"
  shell::write_block --file "$_f" --marker "test" --content "x=1"
  assert_file_exists "$_f"
}

# ---------------------------------------------------------------------------
# shell::user_login_file
# ---------------------------------------------------------------------------

@test "shell::user_login_file returns .bash_profile when it exists" {
  reload_lib shell.sh
  local _home="${BATS_TEST_TMPDIR}/home1"
  mkdir -p "$_home"
  touch "${_home}/.bash_profile"
  run shell::user_login_file --home "$_home"
  assert_output "${_home}/.bash_profile"
}

@test "shell::user_login_file returns .bash_login over .profile" {
  reload_lib shell.sh
  local _home="${BATS_TEST_TMPDIR}/home2"
  mkdir -p "$_home"
  touch "${_home}/.bash_login"
  touch "${_home}/.profile"
  run shell::user_login_file --home "$_home"
  assert_output "${_home}/.bash_login"
}

@test "shell::user_login_file falls back to .bash_profile when none exist" {
  reload_lib shell.sh
  local _home="${BATS_TEST_TMPDIR}/home3"
  mkdir -p "$_home"
  run shell::user_login_file --home "$_home"
  assert_output "${_home}/.bash_profile"
}

# ---------------------------------------------------------------------------
# shell::user_path_files
# ---------------------------------------------------------------------------

@test "shell::user_path_files includes login file, .bashrc and .zshenv" {
  reload_lib shell.sh
  local _home="${BATS_TEST_TMPDIR}/home4"
  mkdir -p "$_home"
  run shell::user_path_files --home "$_home"
  assert_output "${_home}/.bash_profile
${_home}/.bashrc
${_home}/.zshenv"
}

# ---------------------------------------------------------------------------
# shell::user_init_files
# ---------------------------------------------------------------------------

@test "shell::user_init_files includes login file, .bashrc, .zprofile and .zshrc" {
  reload_lib shell.sh
  local _home="${BATS_TEST_TMPDIR}/home5"
  mkdir -p "$_home"
  run shell::user_init_files --home "$_home"
  assert_output "${_home}/.bash_profile
${_home}/.bashrc
${_home}/.zprofile
${_home}/.zshrc"
}

# ---------------------------------------------------------------------------
# shell::resolve_omz_theme
# ---------------------------------------------------------------------------

@test "shell::resolve_omz_theme returns repo/theme when theme file found" {
  reload_lib shell.sh
  local _custom="${BATS_TEST_TMPDIR}/zsh_custom"
  mkdir -p "${_custom}/themes/powerlevel10k"
  touch "${_custom}/themes/powerlevel10k/powerlevel10k.zsh-theme"
  run shell::resolve_omz_theme \
    --theme_slug "romkatv/powerlevel10k" \
    --custom_dir "$_custom"
  assert_output "powerlevel10k/powerlevel10k"
}

@test "shell::resolve_omz_theme returns repo name when no theme file" {
  reload_lib shell.sh
  local _custom="${BATS_TEST_TMPDIR}/zsh_custom_empty"
  mkdir -p "$_custom"
  run shell::resolve_omz_theme \
    --theme_slug "romkatv/powerlevel10k" \
    --custom_dir "$_custom"
  assert_output "powerlevel10k"
}

@test "shell::resolve_omz_theme returns empty for empty slug" {
  reload_lib shell.sh
  run shell::resolve_omz_theme --theme_slug "" --custom_dir "/tmp"
  assert_output ""
  assert_success
}

# ---------------------------------------------------------------------------
# shell::plugin_names_from_slugs
# ---------------------------------------------------------------------------

@test "shell::plugin_names_from_slugs extracts repo names from CSV" {
  reload_lib shell.sh
  run shell::plugin_names_from_slugs "zsh-users/zsh-autosuggestions,zsh-users/zsh-syntax-highlighting"
  assert_output "zsh-autosuggestions
zsh-syntax-highlighting"
}

@test "shell::plugin_names_from_slugs returns empty for empty input" {
  reload_lib shell.sh
  run shell::plugin_names_from_slugs ""
  assert_output ""
  assert_success
}

# ---------------------------------------------------------------------------
# shell::resolve_home
# ---------------------------------------------------------------------------

@test "shell::resolve_home returns home for current user" {
  reload_lib shell.sh
  run shell::resolve_home "$(whoami)"
  assert_output "$HOME"
  assert_success
}

@test "shell::resolve_home returns /root for the root user" {
  reload_lib shell.sh
  run shell::resolve_home "root"
  assert_output "/root"
  assert_success
}

@test "shell::resolve_home returns unexpanded tilde for unknown user" {
  reload_lib shell.sh
  run shell::resolve_home "___no_such_user_xyz___"
  assert_output "~___no_such_user_xyz___"
  assert_success
}

# ---------------------------------------------------------------------------
# shell::sync_block
# ---------------------------------------------------------------------------

@test "shell::sync_block writes a block when --content is provided" {
  reload_lib shell.sh
  local _home="${BATS_TEST_TMPDIR}/sync_home"
  mkdir -p "$_home"
  local _f="${_home}/rc"
  shell::sync_block --files "$_f" --marker "myblock" --content "export X=1"
  assert_file_exists "$_f"
  run grep "export X=1" "$_f"
  assert_success
}

@test "shell::sync_block removes an existing block when --content is absent" {
  reload_lib shell.sh
  local _f="${BATS_TEST_TMPDIR}/rcremove"
  shell::write_block --file "$_f" --marker "removetest" --content "export Y=2"
  shell::sync_block --files "$_f" --marker "removetest"
  run grep "removetest" "$_f"
  assert_failure
}

@test "shell::sync_block skips removal for non-existent file" {
  reload_lib shell.sh
  local _f="${BATS_TEST_TMPDIR}/nope_rc"
  # File doesn't exist; sync_block with no --content should be a no-op (no error).
  run shell::sync_block --files "$_f" --marker "absent"
  assert_success
}

# ---------------------------------------------------------------------------
# shell::system_path_files
# ---------------------------------------------------------------------------

@test "shell::system_path_files returns bashrc and zshenv paths" {
  reload_lib shell.sh
  strings() { echo "/etc/bash.bashrc"; }
  export -f strings
  BASH_ENV="/etc/bashenv"
  run shell::system_path_files
  # Output must contain the bashrc and zshenv paths.
  assert_output --partial "/etc/bash.bashrc"
  assert_output --partial "zshenv"
  assert_success
}

@test "shell::system_path_files includes profile.d path when --profile_d is given" {
  reload_lib shell.sh
  strings() { echo "/etc/bash.bashrc"; }
  export -f strings
  BASH_ENV="/etc/bashenv"
  run shell::system_path_files --profile_d "myenv.sh"
  assert_output --partial "/etc/profile.d/myenv.sh"
  assert_success
}

# ---------------------------------------------------------------------------
# shell::ensure_bashenv
# ---------------------------------------------------------------------------

@test "shell::ensure_bashenv returns BASH_ENV when already set in environment" {
  reload_lib shell.sh
  BASH_ENV="/usr/local/etc/bashenv" run shell::ensure_bashenv
  assert_output --partial "/usr/local/etc/bashenv"
  assert_success
}

@test "shell::ensure_bashenv reads BASH_ENV from /etc/environment via grep" {
  reload_lib shell.sh
  # Override grep to simulate /etc/environment containing BASH_ENV.
  grep() {
    case "$*" in
      *'/etc/environment')
        echo 'BASH_ENV="/etc/bash/bashenv"'
        return 0
        ;;
      *)
        command grep "$@"
        ;;
    esac
  }
  export -f grep
  run shell::ensure_bashenv
  assert_output --partial "/etc/bash/bashenv"
  assert_success
}

# ---------------------------------------------------------------------------
# shell::user_path_files  (additional scenario)
# ---------------------------------------------------------------------------

@test "shell::user_path_files picks .bash_login when it is the login file" {
  reload_lib shell.sh
  local _home="${BATS_TEST_TMPDIR}/homePF"
  mkdir -p "$_home"
  touch "${_home}/.bash_login"
  run shell::user_path_files --home "$_home"
  assert_output "${_home}/.bash_login
${_home}/.bashrc
${_home}/.zshenv"
}

# ---------------------------------------------------------------------------
# shell::user_init_files  (additional scenario)
# ---------------------------------------------------------------------------

@test "shell::user_init_files picks .bash_login when it is the login file" {
  reload_lib shell.sh
  local _home="${BATS_TEST_TMPDIR}/homeIF"
  mkdir -p "$_home"
  touch "${_home}/.bash_login"
  run shell::user_init_files --home "$_home"
  assert_output "${_home}/.bash_login
${_home}/.bashrc
${_home}/.zprofile
${_home}/.zshrc"
}
