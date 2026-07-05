#!/usr/bin/env bats
# Unit tests for lib/shell.bash

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
}

# ---------------------------------------------------------------------------
# bootstrap__strings
# ---------------------------------------------------------------------------

@test "bootstrap__strings: returns 0 when strings is present" {
  run bootstrap__strings
  assert_success
}

@test "bootstrap__strings: returns 1 when strings is absent and install fails" {
  ospkg__run() { return 1; }
  export -f ospkg__run
  begin_path_isolation
  run bootstrap__strings
  end_path_isolation
  assert_failure
}

# ---------------------------------------------------------------------------
# shell__detect_bashrc  (strings-probe path, then os__platform fallback)
# ---------------------------------------------------------------------------

@test "shell__detect_bashrc returns /etc/bash.bashrc for unrecognised platform" {
  reload_lib
  os__platform() { echo "debian"; }
  export -f os__platform
  run shell__detect_bashrc
  assert_output "/etc/bash.bashrc"
}

@test "shell__detect_bashrc returns /etc/bashrc for rhel via platform fallback" {
  reload_lib
  # No strings output → fall through to os__platform.
  strings() { :; }
  # shellcheck disable=SC2329
  os__platform() { printf 'rhel\n'; }
  export -f strings os__platform
  run shell__detect_bashrc
  assert_output "/etc/bashrc"
}

@test "shell__detect_bashrc returns /etc/bashrc for suse via platform fallback" {
  reload_lib
  strings() { :; }
  # shellcheck disable=SC2329
  os__platform() { printf 'suse\n'; }
  export -f strings os__platform
  run shell__detect_bashrc
  assert_output "/etc/bashrc"
}

@test "shell__detect_bashrc returns /etc/bash/bashrc for alpine via platform fallback" {
  reload_lib
  strings() { :; }
  # shellcheck disable=SC2329
  os__platform() { printf 'alpine\n'; }
  export -f strings os__platform
  run shell__detect_bashrc
  assert_output "/etc/bash/bashrc"
}

@test "shell__detect_bashrc returns /etc/bash.bashrc as default fallback" {
  reload_lib
  strings() { :; }
  # shellcheck disable=SC2329
  os__platform() { printf 'debian\n'; }
  export -f strings os__platform
  run shell__detect_bashrc
  assert_output "/etc/bash.bashrc"
}

# ---------------------------------------------------------------------------
# shell__detect_zshdir  (strings-probe path, then os__platform fallback)
# ---------------------------------------------------------------------------

@test "shell__detect_zshdir returns /etc/zsh from strings probe" {
  reload_lib
  strings() { echo "/etc/zsh/zshenv"; }
  export -f strings
  run shell__detect_zshdir
  assert_output "/etc/zsh"
}

@test "shell__detect_zshdir returns /etc from strings probe when zshenv is at /etc/zshenv" {
  reload_lib
  strings() { echo "/etc/zshenv"; }
  export -f strings
  run shell__detect_zshdir
  assert_output "/etc"
}

@test "shell__detect_zshdir returns /etc for rhel via platform fallback" {
  reload_lib
  strings() { :; }
  # shellcheck disable=SC2329
  os__platform() { printf 'rhel\n'; }
  export -f strings os__platform
  run shell__detect_zshdir
  assert_output "/etc"
}

@test "shell__detect_zshdir returns /etc for suse via platform fallback" {
  reload_lib
  strings() { :; }
  # shellcheck disable=SC2329
  os__platform() { printf 'suse\n'; }
  export -f strings os__platform
  run shell__detect_zshdir
  assert_output "/etc"
}

@test "shell__detect_zshdir returns /etc/zsh as default fallback" {
  reload_lib
  strings() { :; }
  # shellcheck disable=SC2329
  os__platform() { printf 'debian\n'; }
  export -f strings os__platform
  run shell__detect_zshdir
  assert_output "/etc/zsh"
}

# ---------------------------------------------------------------------------
# shell__detect_fish_sysdir
# ---------------------------------------------------------------------------

@test "shell__detect_fish_sysdir returns /usr/share/fish/vendor_completions.d on Linux" {
  reload_lib
  os__kernel() { printf 'Linux\n'; }
  run shell__detect_fish_sysdir
  assert_output "/usr/share/fish/vendor_completions.d"
  assert_success
}

@test "shell__detect_fish_sysdir returns Homebrew fish path on macOS" {
  reload_lib
  os__kernel() { printf 'Darwin\n'; }
  create_fake_bin "brew" "/opt/homebrew"
  prepend_fake_bin_path
  run shell__detect_fish_sysdir
  assert_output "/opt/homebrew/share/fish/vendor_completions.d"
  assert_success
}

@test "shell__detect_fish_sysdir returns empty on macOS when Homebrew is absent" {
  reload_lib
  os__kernel() { printf 'Darwin\n'; }
  begin_path_isolation
  run shell__detect_fish_sysdir
  assert_output ""
  assert_success
}

# ---------------------------------------------------------------------------
# shell__write_block
# ---------------------------------------------------------------------------

@test "shell__write_block appends a new block to a file" {
  reload_lib
  local _f="${BATS_TEST_TMPDIR}/rc"
  shell__write_block --file "$_f" --marker "mytest" --content "export FOO=bar"
  assert_file_exists "$_f"
  run grep -c "# >>> mytest >>>" "$_f"
  assert_output "1"
  run grep "export FOO=bar" "$_f"
  assert_success
}

@test "shell__write_block updates existing block in place" {
  reload_lib
  local _f="${BATS_TEST_TMPDIR}/rc2"
  shell__write_block --file "$_f" --marker "mytest" --content "export FOO=bar"
  shell__write_block --file "$_f" --marker "mytest" --content "export FOO=baz"
  run grep -c "# >>> mytest >>>" "$_f"
  assert_output "1"
  run grep "export FOO=baz" "$_f"
  assert_success
  run grep "export FOO=bar" "$_f"
  assert_failure
}

@test "shell__write_block creates parent directories" {
  reload_lib
  local _f="${BATS_TEST_TMPDIR}/subdir/rc"
  shell__write_block --file "$_f" --marker "test" --content "x=1"
  assert_file_exists "$_f"
}

# ---------------------------------------------------------------------------
# shell__user_login_file
# ---------------------------------------------------------------------------

@test "shell__user_login_file returns .bash_profile when it exists" {
  reload_lib
  local _home="${BATS_TEST_TMPDIR}/home1"
  mkdir -p "$_home"
  touch "${_home}/.bash_profile"
  run shell__user_login_file --home "$_home"
  assert_output "${_home}/.bash_profile"
}

@test "shell__user_login_file returns .bash_login over .profile" {
  reload_lib
  local _home="${BATS_TEST_TMPDIR}/home2"
  mkdir -p "$_home"
  touch "${_home}/.bash_login"
  touch "${_home}/.profile"
  run shell__user_login_file --home "$_home"
  assert_output "${_home}/.bash_login"
}

@test "shell__user_login_file falls back to .bash_profile when none exist" {
  reload_lib
  local _home="${BATS_TEST_TMPDIR}/home3"
  mkdir -p "$_home"
  run shell__user_login_file --home "$_home"
  assert_output "${_home}/.bash_profile"
}

# ---------------------------------------------------------------------------
# shell__user_path_files
# ---------------------------------------------------------------------------

@test "shell__user_path_files includes login file, .bashrc and .zshenv" {
  reload_lib
  local _home="${BATS_TEST_TMPDIR}/home4"
  mkdir -p "$_home"
  run shell__user_path_files --home "$_home"
  assert_output "${_home}/.bash_profile
${_home}/.bashrc
${_home}/.zshenv"
}

# ---------------------------------------------------------------------------
# shell__user_init_files
# ---------------------------------------------------------------------------

@test "shell__user_init_files includes login file, .bashrc, .zprofile and .zshrc" {
  reload_lib
  local _home="${BATS_TEST_TMPDIR}/home5"
  mkdir -p "$_home"
  run shell__user_init_files --home "$_home"
  assert_output "${_home}/.bash_profile
${_home}/.bashrc
${_home}/.zprofile
${_home}/.zshrc"
}

# ---------------------------------------------------------------------------
# shell__resolve_omz_theme
# ---------------------------------------------------------------------------

@test "shell__resolve_omz_theme returns repo/theme when theme file found" {
  reload_lib
  local _custom="${BATS_TEST_TMPDIR}/zsh_custom"
  mkdir -p "${_custom}/themes/powerlevel10k"
  touch "${_custom}/themes/powerlevel10k/powerlevel10k.zsh-theme"
  run shell__resolve_omz_theme \
    --theme_slug "romkatv/powerlevel10k" \
    --custom_dir "$_custom"
  assert_output "powerlevel10k/powerlevel10k"
}

@test "shell__resolve_omz_theme returns repo name when no theme file" {
  reload_lib
  local _custom="${BATS_TEST_TMPDIR}/zsh_custom_empty"
  mkdir -p "$_custom"
  run shell__resolve_omz_theme \
    --theme_slug "romkatv/powerlevel10k" \
    --custom_dir "$_custom"
  assert_output "powerlevel10k"
}

@test "shell__resolve_omz_theme returns empty for empty slug" {
  reload_lib
  run shell__resolve_omz_theme --theme_slug "" --custom_dir "/tmp"
  assert_output ""
  assert_success
}

# ---------------------------------------------------------------------------
# users__resolve_home (via shell.bash which sources users.bash)
# ---------------------------------------------------------------------------

@test "users__resolve_home returns home for current user" {
  reload_lib
  local _expected
  _expected="$(eval echo "~$(whoami)")"
  run --separate-stderr users__resolve_home "$(whoami)"
  assert_output "$_expected"
  assert_success
}

@test "users__resolve_home returns the correct home for the root user" {
  reload_lib
  # Use eval to get the platform-actual home (e.g. /root on Linux, /var/root on macOS).
  local _root_home
  _root_home="$(eval echo '~root')"
  run --separate-stderr users__resolve_home "root"
  assert_output "$_root_home"
  assert_success
}

@test "users__resolve_home returns unexpanded tilde for unknown user" {
  reload_lib
  run --separate-stderr users__resolve_home "___no_such_user_xyz___"
  assert_output "~___no_such_user_xyz___"
  assert_success
}

# ---------------------------------------------------------------------------
# shell__sync_block
# ---------------------------------------------------------------------------

@test "shell__sync_block writes a block when --content is provided" {
  reload_lib
  local _home="${BATS_TEST_TMPDIR}/sync_home"
  mkdir -p "$_home"
  local _syncfile="${_home}/rc"
  shell__sync_block --files "$_syncfile" --marker "myblock" --content "export X=1"
  assert_file_exists "$_syncfile"
  run grep "export X=1" "$_syncfile"
  assert_success
}

@test "shell__sync_block removes an existing block when --content is absent" {
  reload_lib
  local _f="${BATS_TEST_TMPDIR}/rcremove"
  shell__write_block --file "$_f" --marker "removetest" --content "export Y=2"
  shell__sync_block --files "$_f" --marker "removetest"
  run grep "removetest" "$_f"
  assert_failure
}

@test "shell__sync_block skips removal for non-existent file" {
  reload_lib
  local _f="${BATS_TEST_TMPDIR}/nope_rc"
  # File doesn't exist; sync_block with no --content should be a no-op (no error).
  run shell__sync_block --files "$_f" --marker "absent"
  assert_success
}

# ---------------------------------------------------------------------------
# shell__system_path_files
# ---------------------------------------------------------------------------

@test "shell__system_path_files returns bashrc and zshenv paths" {
  reload_lib
  shell__detect_bashrc() { echo "/etc/bash.bashrc"; }
  export -f shell__detect_bashrc
  BASH_ENV="/etc/bashenv"
  run shell__system_path_files
  # Output must contain the bashrc and zshenv paths.
  assert_output --partial "/etc/bash.bashrc"
  assert_output --partial "zshenv"
  assert_success
}

@test "shell__system_path_files includes profile.d path when --profile_d is given" {
  reload_lib
  shell__detect_bashrc() { echo "/etc/bash.bashrc"; }
  export -f shell__detect_bashrc
  BASH_ENV="/etc/bashenv"
  run shell__system_path_files --profile_d "myenv.sh"
  assert_output --partial "/etc/profile.d/myenv.sh"
  assert_success
}

# ---------------------------------------------------------------------------
# shell__ensure_bashenv
# ---------------------------------------------------------------------------

@test "shell__ensure_bashenv returns BASH_ENV when already set in environment" {
  reload_lib
  BASH_ENV="/usr/local/etc/bashenv" run shell__ensure_bashenv
  assert_output --partial "/usr/local/etc/bashenv"
  assert_success
}

@test "shell__ensure_bashenv reads BASH_ENV from _SHELL_ENV_FILE when entry exists" {
  reload_lib
  local _env="${BATS_TEST_TMPDIR}/environment"
  printf 'BASH_ENV="/etc/bash/bashenv"\n' > "$_env"
  _SHELL_ENV_FILE="$_env" run shell__ensure_bashenv
  assert_success
  assert_output --partial "/etc/bash/bashenv"
}

@test "shell__ensure_bashenv creates bashenv file and registers it when no entry exists" {
  reload_lib
  local _env="${BATS_TEST_TMPDIR}/environment"
  touch "$_env" # exists but empty — no BASH_ENV entry
  # Stub detect_bashrc so the bashenv dir is inside BATS_TEST_TMPDIR.
  shell__detect_bashrc() { echo "${BATS_TEST_TMPDIR}/bash.bashrc"; }
  export -f shell__detect_bashrc
  _SHELL_ENV_FILE="$_env" run shell__ensure_bashenv
  assert_success
  # Output must be the created bashenv path.
  assert_output --partial "${BATS_TEST_TMPDIR}/bashenv"
  # _SHELL_ENV_FILE must now contain a BASH_ENV= line.
  run grep "BASH_ENV=" "$_env"
  assert_success
}

# ---------------------------------------------------------------------------
# shell__detect_zdotdir
# ---------------------------------------------------------------------------

@test "shell__detect_zdotdir returns ZDOTDIR when home matches HOME" {
  reload_lib
  ZDOTDIR="/custom/zsh" run shell__detect_zdotdir --home "$HOME"
  assert_output "/custom/zsh"
}

@test "shell__detect_zdotdir falls back to home when no ZDOTDIR and no zshenv" {
  reload_lib
  local _home="${BATS_TEST_TMPDIR}/homeZD1"
  mkdir -p "$_home"
  # Stub shell__detect_zshdir to point to a nonexistent system dir.
  shell__detect_zshdir() { echo "${BATS_TEST_TMPDIR}/no_etc_zsh"; }
  export -f shell__detect_zshdir
  unset ZDOTDIR
  run shell__detect_zdotdir --home "$_home"
  assert_output "$_home"
}

@test "shell__detect_zdotdir parses ZDOTDIR=\$HOME/... from user .zshenv" {
  reload_lib
  local _home="${BATS_TEST_TMPDIR}/homeZD2"
  mkdir -p "$_home"
  printf 'export ZDOTDIR="$HOME/.config/zsh"\n' > "${_home}/.zshenv"
  shell__detect_zshdir() { echo "${BATS_TEST_TMPDIR}/no_etc_zsh"; }
  export -f shell__detect_zshdir
  run shell__detect_zdotdir --home "$_home"
  assert_output "${_home}/.config/zsh"
}

@test "shell__detect_zdotdir parses ZDOTDIR=\${HOME}/... from user .zshenv" {
  reload_lib
  local _home="${BATS_TEST_TMPDIR}/homeZD3"
  mkdir -p "$_home"
  printf 'ZDOTDIR="${HOME}/.config/zsh"\n' > "${_home}/.zshenv"
  shell__detect_zshdir() { echo "${BATS_TEST_TMPDIR}/no_etc_zsh"; }
  export -f shell__detect_zshdir
  run shell__detect_zdotdir --home "$_home"
  assert_output "${_home}/.config/zsh"
}

@test "shell__detect_zdotdir parses ZDOTDIR=~/... from user .zshenv" {
  reload_lib
  local _home="${BATS_TEST_TMPDIR}/homeZD4"
  mkdir -p "$_home"
  printf 'ZDOTDIR=~/.config/zsh\n' > "${_home}/.zshenv"
  shell__detect_zshdir() { echo "${BATS_TEST_TMPDIR}/no_etc_zsh"; }
  export -f shell__detect_zshdir
  run shell__detect_zdotdir --home "$_home"
  assert_output "${_home}/.config/zsh"
}

@test "shell__detect_zdotdir substitutes \$XDG_CONFIG_HOME" {
  reload_lib
  local _home="${BATS_TEST_TMPDIR}/homeZD5"
  mkdir -p "$_home"
  printf 'export ZDOTDIR="$XDG_CONFIG_HOME/zsh"\n' > "${_home}/.zshenv"
  shell__detect_zshdir() { echo "${BATS_TEST_TMPDIR}/no_etc_zsh"; }
  export -f shell__detect_zshdir
  XDG_CONFIG_HOME="${_home}/.xdg" run shell__detect_zdotdir --home "$_home"
  assert_output "${_home}/.xdg/zsh"
}

@test "shell__detect_zdotdir defaults XDG_CONFIG_HOME to home/.config" {
  reload_lib
  local _home="${BATS_TEST_TMPDIR}/homeZD6"
  mkdir -p "$_home"
  printf 'ZDOTDIR="${XDG_CONFIG_HOME}/zsh"\n' > "${_home}/.zshenv"
  shell__detect_zshdir() { echo "${BATS_TEST_TMPDIR}/no_etc_zsh"; }
  export -f shell__detect_zshdir
  unset XDG_CONFIG_HOME
  run shell__detect_zdotdir --home "$_home"
  assert_output "${_home}/.config/zsh"
}

@test "shell__detect_zdotdir falls back to home on unresolvable variable" {
  reload_lib
  local _home="${BATS_TEST_TMPDIR}/homeZD7"
  mkdir -p "$_home"
  printf 'ZDOTDIR="${CUSTOM_VAR}/zsh"\n' > "${_home}/.zshenv"
  shell__detect_zshdir() { echo "${BATS_TEST_TMPDIR}/no_etc_zsh"; }
  export -f shell__detect_zshdir
  run shell__detect_zdotdir --home "$_home"
  assert_output "$_home"
}

@test "shell__detect_zdotdir user .zshenv overrides system zshenv" {
  reload_lib
  local _home="${BATS_TEST_TMPDIR}/homeZD8"
  local _sys="${BATS_TEST_TMPDIR}/sysZD8"
  mkdir -p "$_home" "$_sys"
  printf 'ZDOTDIR="$HOME/.system-zsh"\n' > "${_sys}/zshenv"
  printf 'ZDOTDIR="$HOME/.user-zsh"\n' > "${_home}/.zshenv"
  shell__detect_zshdir() { echo "$_sys"; }
  export -f shell__detect_zshdir
  run shell__detect_zdotdir --home "$_home"
  assert_output "${_home}/.user-zsh"
}

# ---------------------------------------------------------------------------
# shell__user_path_files  (additional scenario)
# ---------------------------------------------------------------------------

@test "shell__user_path_files picks .bash_login when it is the login file" {
  reload_lib
  local _home="${BATS_TEST_TMPDIR}/homePF"
  mkdir -p "$_home"
  touch "${_home}/.bash_login"
  run shell__user_path_files --home "$_home"
  assert_output "${_home}/.bash_login
${_home}/.bashrc
${_home}/.zshenv"
}

@test "shell__user_path_files uses --zdotdir for .zshenv" {
  reload_lib
  local _home="${BATS_TEST_TMPDIR}/homePZ"
  local _zd="${BATS_TEST_TMPDIR}/zdotPZ"
  mkdir -p "$_home" "$_zd"
  run shell__user_path_files --home "$_home" --zdotdir "$_zd"
  assert_output "${_home}/.bash_profile
${_home}/.bashrc
${_zd}/.zshenv"
}

@test "shell__user_path_files auto-detects zdotdir from .zshenv" {
  reload_lib
  local _home="${BATS_TEST_TMPDIR}/homePZA"
  mkdir -p "$_home"
  printf 'ZDOTDIR="$HOME/.config/zsh"\n' > "${_home}/.zshenv"
  shell__detect_zshdir() { echo "${BATS_TEST_TMPDIR}/no_etc_zsh"; }
  export -f shell__detect_zshdir
  run shell__user_path_files --home "$_home"
  assert_output "${_home}/.bash_profile
${_home}/.bashrc
${_home}/.config/zsh/.zshenv"
}

# ---------------------------------------------------------------------------
# shell__user_init_files  (additional scenario)
# ---------------------------------------------------------------------------

@test "shell__user_init_files picks .bash_login when it is the login file" {
  reload_lib
  local _home="${BATS_TEST_TMPDIR}/homeIF"
  mkdir -p "$_home"
  touch "${_home}/.bash_login"
  run shell__user_init_files --home "$_home"
  assert_output "${_home}/.bash_login
${_home}/.bashrc
${_home}/.zprofile
${_home}/.zshrc"
}

@test "shell__user_init_files uses --zdotdir for zsh files" {
  reload_lib
  local _home="${BATS_TEST_TMPDIR}/homeIZ"
  local _zd="${BATS_TEST_TMPDIR}/zdotIZ"
  mkdir -p "$_home" "$_zd"
  run shell__user_init_files --home "$_home" --zdotdir "$_zd"
  assert_output "${_home}/.bash_profile
${_home}/.bashrc
${_zd}/.zprofile
${_zd}/.zshrc"
}

@test "shell__user_init_files auto-detects zdotdir from .zshenv" {
  reload_lib
  local _home="${BATS_TEST_TMPDIR}/homeIZA"
  mkdir -p "$_home"
  printf 'ZDOTDIR="$HOME/.config/zsh"\n' > "${_home}/.zshenv"
  shell__detect_zshdir() { echo "${BATS_TEST_TMPDIR}/no_etc_zsh"; }
  export -f shell__detect_zshdir
  run shell__user_init_files --home "$_home"
  assert_output "${_home}/.bash_profile
${_home}/.bashrc
${_home}/.config/zsh/.zprofile
${_home}/.config/zsh/.zshrc"
}

# ---------------------------------------------------------------------------
# shell__user_rc_files
# ---------------------------------------------------------------------------

@test "shell__user_rc_files returns .bashrc and .zshrc only" {
  reload_lib
  local _home="${BATS_TEST_TMPDIR}/homeRC1"
  mkdir -p "$_home"
  run shell__user_rc_files --home "$_home"
  assert_output "${_home}/.bashrc
${_home}/.zshrc"
}

@test "shell__user_rc_files does not include login file" {
  reload_lib
  local _home="${BATS_TEST_TMPDIR}/homeRC2"
  mkdir -p "$_home"
  touch "${_home}/.bash_profile"
  run shell__user_rc_files --home "$_home"
  # Must NOT contain .bash_profile
  refute_output --partial ".bash_profile"
  assert_output --partial ".bashrc"
}

@test "shell__user_rc_files uses explicit --zdotdir for .zshrc" {
  reload_lib
  local _home="${BATS_TEST_TMPDIR}/homeRCZ"
  local _zd="${BATS_TEST_TMPDIR}/zdotRCZ"
  mkdir -p "$_home" "$_zd"
  run shell__user_rc_files --home "$_home" --zdotdir "$_zd"
  assert_output "${_home}/.bashrc
${_zd}/.zshrc"
}

@test "shell__user_rc_files auto-detects zdotdir from .zshenv" {
  reload_lib
  local _home="${BATS_TEST_TMPDIR}/homeRCZA"
  mkdir -p "$_home"
  printf 'ZDOTDIR="$HOME/.config/zsh"\n' > "${_home}/.zshenv"
  shell__detect_zshdir() { echo "${BATS_TEST_TMPDIR}/no_etc_zsh"; }
  export -f shell__detect_zshdir
  run shell__user_rc_files --home "$_home"
  assert_output "${_home}/.bashrc
${_home}/.config/zsh/.zshrc"
}

# ---------------------------------------------------------------------------
# shell__system_rc_files
# ---------------------------------------------------------------------------

@test "shell__system_rc_files returns system bashrc and zshrc" {
  reload_lib
  strings() { echo "/etc/bash.bashrc"; }
  # shellcheck disable=SC2329
  os__platform() { printf 'debian\n'; }
  export -f strings os__platform
  run shell__system_rc_files
  assert_output "/etc/bash.bashrc
/etc/zsh/zshrc"
  assert_success
}

@test "shell__system_rc_files uses distro-correct bashrc for fedora" {
  reload_lib
  strings() { :; }
  # shellcheck disable=SC2329
  os__platform() { printf 'rhel\n'; }
  export -f strings os__platform
  run shell__system_rc_files
  assert_output "/etc/bashrc
/etc/zshrc"
  assert_success
}

@test "shell__system_rc_files uses /etc/zsh/zshrc for debian-family" {
  reload_lib
  strings() { echo "/etc/bash.bashrc"; }
  # shellcheck disable=SC2329
  os__platform() { printf 'debian\n'; }
  export -f strings os__platform
  run shell__system_rc_files
  assert_output "/etc/bash.bashrc
/etc/zsh/zshrc"
  assert_success
}

# ---------------------------------------------------------------------------
# shell__create_symlink
# ---------------------------------------------------------------------------

@test "shell__create_symlink creates system-wide symlink when system dir is writable" {
  reload_lib
  local _src="${BATS_TEST_TMPDIR}/opt/mytool/bin/mytool"
  local _sys="${BATS_TEST_TMPDIR}/usr/local/bin/mytool"
  local _usr="${BATS_TEST_TMPDIR}/home/user/.local/bin/mytool"
  mkdir -p "$(dirname "$_sys")" # writable → system target chosen
  run shell__create_symlink \
    --src "$_src" \
    --system-target "$_sys" \
    --user-target "$_usr"
  assert_success
  assert [ -L "$_sys" ]
  assert [ ! -e "$_usr" ]
}

@test "shell__create_symlink creates user-scoped symlink when system dir is not writable" {
  [ "$(id -u)" -eq 0 ] && skip "Cannot simulate non-writable directory as root (chmod 555 bypassed by CAP_DAC_OVERRIDE)"
  reload_lib
  local _src="${BATS_TEST_TMPDIR}/opt/git/bin/git"
  local _sys_dir="${BATS_TEST_TMPDIR}/readonly/bin"
  local _sys="${_sys_dir}/git"
  local _usr="${BATS_TEST_TMPDIR}/home/vscode/.local/bin/git"
  mkdir -p "$_sys_dir"
  chmod 555 "$_sys_dir" # exists but not writable → user target chosen
  run shell__create_symlink \
    --src "$_src" \
    --system-target "$_sys" \
    --user-target "$_usr"
  assert_success
  assert [ -L "$_usr" ]
  assert [ ! -e "$_sys" ]
}

@test "shell__create_symlink errors with clear message when neither location is writable" {
  [ "$(id -u)" -eq 0 ] && skip "Cannot simulate non-writable directory as root (chmod 555 bypassed by CAP_DAC_OVERRIDE)"
  reload_lib
  local _sys_dir="${BATS_TEST_TMPDIR}/sys/bin"
  local _usr_dir="${BATS_TEST_TMPDIR}/usr/bin"
  mkdir -p "$_sys_dir" "$_usr_dir"
  chmod 555 "$_sys_dir" "$_usr_dir"
  run shell__create_symlink \
    --src "/opt/mytool/bin/mytool" \
    --system-target "${_sys_dir}/mytool" \
    --user-target "${_usr_dir}/mytool"
  assert_failure
  assert_output --partial "no writable location available"
}

@test "shell__create_symlink skips when src equals chosen target" {
  reload_lib
  local _path="${BATS_TEST_TMPDIR}/usr/local/bin/mytool"
  mkdir -p "$(dirname "$_path")" # writable → system target chosen; src == target → skip
  run shell__create_symlink \
    --src "$_path" \
    --system-target "$_path" \
    --user-target "${BATS_TEST_TMPDIR}/home/u/.local/bin/mytool"
  assert_success
  assert_output --partial "no symlink needed"
  assert [ ! -e "$_path" ]
}

@test "shell__create_symlink errors when target is a real file" {
  reload_lib
  local _sys="${BATS_TEST_TMPDIR}/usr/local/bin/mytool"
  mkdir -p "$(dirname "$_sys")"
  touch "$_sys" # real file → error
  run shell__create_symlink \
    --src "/opt/mytool/bin/mytool" \
    --system-target "$_sys" \
    --user-target "${BATS_TEST_TMPDIR}/home/u/.local/bin/mytool"
  assert_failure
  assert_output --partial "exists as a real file or directory"
}

@test "shell__create_symlink replaces stale symlink" {
  reload_lib
  local _sys="${BATS_TEST_TMPDIR}/usr/local/bin/mytool"
  local _old_src="${BATS_TEST_TMPDIR}/old/src"
  local _new_src="${BATS_TEST_TMPDIR}/new/src"
  mkdir -p "$(dirname "$_sys")"
  ln -s "$_old_src" "$_sys" # stale symlink
  run shell__create_symlink \
    --src "$_new_src" \
    --system-target "$_sys" \
    --user-target "${BATS_TEST_TMPDIR}/home/u/.local/bin/mytool"
  assert_success
  run readlink "$_sys"
  assert_output "$_new_src"
}

@test "shell__create_symlink creates parent directories for user target" {
  [ "$(id -u)" -eq 0 ] && skip "Cannot simulate non-writable directory as root (chmod 555 bypassed by CAP_DAC_OVERRIDE)"
  reload_lib
  local _sys_dir="${BATS_TEST_TMPDIR}/readonly/bin"
  local _usr="${BATS_TEST_TMPDIR}/deep/user/bin/mytool"
  mkdir -p "$_sys_dir"
  chmod 555 "$_sys_dir" # exists but not writable → user target chosen;
  # user target's parent also does not exist → mkdir -p must create it.
  run shell__create_symlink \
    --src "/opt/mytool/bin/mytool" \
    --system-target "${_sys_dir}/mytool" \
    --user-target "$_usr"
  assert_success
  assert [ -L "$_usr" ]
}

# ---------------------------------------------------------------------------
# shell__write_env_block
# ---------------------------------------------------------------------------

@test "shell__write_env_block writes block to explicit file list" {
  reload_lib
  shell__write_env_block \
    --opt "${BATS_TEST_TMPDIR}/explicit_rc" \
    --marker "test block" \
    --content "export MY_VAR=hello"
  run grep "export MY_VAR=hello" "${BATS_TEST_TMPDIR}/explicit_rc"
  assert_success
}

@test "shell__write_env_block routes auto to system_path_files when root" {
  reload_lib
  create_fake_bin "id" "0"
  prepend_fake_bin_path
  local _sys_file="${BATS_TEST_TMPDIR}/fake_system_rc"
  # Stub system_path_files to return a writable tmpdir path.
  shell__system_path_files() { echo "$_sys_file"; }
  export -f shell__system_path_files
  shell__write_env_block \
    --opt "auto" \
    --profile-d "myfeature.sh" \
    --marker "test block root" \
    --content "export ROOT_VAR=1"
  run grep "export ROOT_VAR=1" "$_sys_file"
  assert_success
}

@test "shell__write_env_block routes auto to user_path_files when non-root" {
  reload_lib
  create_fake_bin "id" "1001"
  prepend_fake_bin_path
  local _home="${BATS_TEST_TMPDIR}/home_nonroot"
  mkdir -p "$_home"
  HOME="$_home"
  shell__detect_zdotdir() { echo "$_home"; }
  export -f shell__detect_zdotdir
  shell__write_env_block \
    --opt "auto" \
    --profile-d "ignored.sh" \
    --marker "test block nonroot" \
    --content "export NONROOT_VAR=2"
  run grep -r "export NONROOT_VAR=2" "$_home"
  assert_success
}

# ---------------------------------------------------------------------------
# shell__detect_installed_shells
# ---------------------------------------------------------------------------

@test "shell__detect_installed_shells always returns bash" {
  reload_lib
  run shell__detect_installed_shells
  assert_line "bash"
  assert_success
}

@test "shell__detect_installed_shells returns zsh when binary is on PATH" {
  reload_lib
  create_fake_bin "zsh" ""
  prepend_fake_bin_path
  run shell__detect_installed_shells
  assert_line "bash"
  assert_line "zsh"
  assert_success
}

@test "shell__detect_installed_shells returns fish when /etc/fish directory exists" {
  reload_lib
  mkdir -p "${BATS_TEST_TMPDIR}/etc/fish"
  # Stub so detect_installed_shells sees the tmp /etc/fish
  shell__detect_installed_shells() {
    local -a _sh=(bash)
    command -v zsh > /dev/null 2>&1 && _sh+=(zsh)
    [ -d "${BATS_TEST_TMPDIR}/etc/fish" ] && _sh+=(fish) || command -v fish > /dev/null 2>&1 && _sh+=(fish)
    printf '%s\n' "${_sh[@]}"
  }
  run shell__detect_installed_shells
  assert_line "bash"
  assert_line "fish"
  assert_success
}

@test "shell__detect_installed_shells does not include tcsh when binary absent" {
  [[ "$(uname -s)" == Darwin ]] && skip "macOS ships with tcsh pre-installed"
  reload_lib
  run shell__detect_installed_shells
  refute_line "tcsh"
  assert_success
}

# ---------------------------------------------------------------------------
# shell__sync_config
# ---------------------------------------------------------------------------

@test "shell__sync_config write mode user fish: writes content to config.fish" {
  reload_lib
  create_fake_bin "id" "1001"
  prepend_fake_bin_path
  local _home="${BATS_TEST_TMPDIR}/home_fish"
  mkdir -p "${_home}/.config/fish"
  touch "${_home}/.config/fish/config.fish"
  shell__sync_config \
    --scope user \
    --home "$_home" \
    --marker "test fish sync" \
    --profile-d "ignored.sh" \
    --fish-content "fish_add_path /opt/mytool/bin"
  run grep "fish_add_path /opt/mytool/bin" "${_home}/.config/fish/config.fish"
  assert_success
}

@test "shell__sync_config write mode system bash rc-only: writes only to bashrc" {
  reload_lib
  create_fake_bin "id" "0"
  prepend_fake_bin_path
  local _brc="${BATS_TEST_TMPDIR}/bash_rc_only.bashrc"
  touch "$_brc"
  shell__detect_bashrc() { echo "$_brc"; }
  export -f shell__detect_bashrc
  shell__sync_config \
    --scope system \
    --marker "test sync rc" \
    --profile-d "myfeature.sh" \
    --bash-content "export RC_ONLY=yes"
  run grep "export RC_ONLY=yes" "$_brc"
  assert_success
}

@test "shell__sync_config write mode user bash everywhere: writes to login file and .bashrc" {
  reload_lib
  create_fake_bin "id" "1001"
  prepend_fake_bin_path
  local _home="${BATS_TEST_TMPDIR}/home_scuser"
  mkdir -p "$_home"
  touch "${_home}/.bash_profile" "${_home}/.bashrc"
  shell__user_login_file() { echo "${_home}/.bash_profile"; }
  export -f shell__user_login_file
  shell__sync_config \
    --scope user \
    --home "$_home" \
    --marker "test user sync" \
    --profile-d "ignored.sh" \
    --bash-content "export USER_SYNC=1" \
    --bash-everywhere
  run grep -r "export USER_SYNC=1" "$_home"
  assert_success
}

@test "shell__sync_config write mode user bash rc-only: writes only to .bashrc" {
  reload_lib
  create_fake_bin "id" "1001"
  prepend_fake_bin_path
  local _home="${BATS_TEST_TMPDIR}/home_rc_user"
  mkdir -p "$_home"
  touch "${_home}/.bashrc"
  local _login="${_home}/.bash_profile"
  touch "$_login"
  shell__user_login_file() { echo "$_login"; }
  export -f shell__user_login_file
  shell__sync_config \
    --scope user \
    --home "$_home" \
    --marker "test user rc" \
    --profile-d "ignored.sh" \
    --bash-content "export USER_RC=1"
  run grep "export USER_RC=1" "${_home}/.bashrc"
  assert_success
  run grep "export USER_RC=1" "$_login"
  assert_failure
}

@test "shell__sync_config remove mode: removes marker from all bash locations" {
  reload_lib
  create_fake_bin "id" "0"
  prepend_fake_bin_path
  local _brc="${BATS_TEST_TMPDIR}/remove_bashrc"
  local _benv="${BATS_TEST_TMPDIR}/remove_benv"
  local _pd="${BATS_TEST_TMPDIR}/profile_d_remove.sh"
  printf '# >>> remove me >>>\nexport TO_REMOVE=1\n# <<< remove me <<<\n' > "$_brc"
  printf '# >>> remove me >>>\nexport TO_REMOVE=1\n# <<< remove me <<<\n' > "$_benv"
  printf '# >>> remove me >>>\nexport TO_REMOVE=1\n# <<< remove me <<<\n' > "$_pd"
  shell__ensure_bashenv() { echo "$_benv"; }
  export -f shell__ensure_bashenv
  shell__detect_bashrc() { echo "$_brc"; }
  export -f shell__detect_bashrc
  shell__sync_config \
    --scope system \
    --marker "remove me" \
    --profile-d "profile_d_remove.sh" \
    bash
  run grep "TO_REMOVE" "$_brc"
  assert_failure
}

@test "shell__sync_config write mode system zsh everywhere: writes to zshenv" {
  reload_lib
  create_fake_bin "id" "0"
  prepend_fake_bin_path
  local _zshdir="${BATS_TEST_TMPDIR}/zsh_dir"
  mkdir -p "$_zshdir"
  touch "${_zshdir}/zshenv"
  shell__detect_zshdir() { echo "$_zshdir"; }
  export -f shell__detect_zshdir
  shell__sync_config \
    --scope system \
    --marker "test zsh sync" \
    --profile-d "ignored.sh" \
    --zsh-content "export ZSH_VAR=1" \
    --zsh-everywhere
  run grep "export ZSH_VAR=1" "${_zshdir}/zshenv"
  assert_success
}

@test "shell__sync_config write mode handles multiple shells in one call" {
  reload_lib
  create_fake_bin "id" "1001"
  prepend_fake_bin_path
  local _home="${BATS_TEST_TMPDIR}/home_multi"
  mkdir -p "$_home"
  touch "${_home}/.bashrc"
  local _zdir="${_home}"
  touch "${_zdir}/.zshrc"
  shell__detect_zdotdir() { echo "$_zdir"; }
  export -f shell__detect_zdotdir
  shell__sync_config \
    --scope user \
    --home "$_home" \
    --marker "multi shell" \
    --profile-d "ignored.sh" \
    --bash-content "export MULTI_BASH=1" \
    --zsh-content "export MULTI_ZSH=1"
  run grep "export MULTI_BASH=1" "${_home}/.bashrc"
  assert_success
  run grep "export MULTI_ZSH=1" "${_zdir}/.zshrc"
  assert_success
}

# ---------------------------------------------------------------------------
# shell__resolve_inject_line_v1
# ---------------------------------------------------------------------------

@test "shell__resolve_inject_line_v1 file-top-after-comments finds first code line" {
  reload_lib
  local _f="${BATS_TEST_TMPDIR}/top"
  printf '# comment\n\n# another\nFIRST=1\nSECOND=2\n' > "$_f"
  run shell__resolve_inject_line_v1 --file "$_f" --anchor file-top-after-comments
  assert_output "4"
}

@test "shell__resolve_inject_line_v1 file-top-after-comments falls back to EOF on all-comment file" {
  reload_lib
  local _f="${BATS_TEST_TMPDIR}/allcomments"
  printf '# a\n# b\n' > "$_f"
  run shell__resolve_inject_line_v1 --file "$_f" --anchor file-top-after-comments
  assert_output "3"
}

@test "shell__resolve_inject_line_v1 finds line after interactivity guard esac" {
  reload_lib
  local _f="${BATS_TEST_TMPDIR}/guarded"
  printf '# hdr\ncase $- in\n  *i*) ;;\n    *) return;;\nesac\nAFTER=1\n' > "$_f"
  run shell__resolve_inject_line_v1 --file "$_f" --anchor after-interactivity-guard-or-eof
  assert_output "6"
}

@test "shell__resolve_inject_line_v1 guard anchor falls back to EOF when no guard matches" {
  reload_lib
  local _f="${BATS_TEST_TMPDIR}/noguard"
  printf 'A=1\nB=2\nC=3\n' > "$_f"
  run shell__resolve_inject_line_v1 --file "$_f" --anchor after-interactivity-guard-or-eof
  assert_output "4"
}

@test "shell__resolve_inject_line_v1 skips guards inside existing marker blocks" {
  reload_lib
  local _f="${BATS_TEST_TMPDIR}/markedguard"
  printf '# >>> some-block >>>\ncase $- in\n  *i*) ;;\n    *) return;;\nesac\n# <<< some-block <<<\nTAIL=1\n' > "$_f"
  run shell__resolve_inject_line_v1 --file "$_f" --anchor after-interactivity-guard-or-eof
  assert_output "8"
}

@test "shell__resolve_inject_line_v1 missing file resolves to line 1" {
  reload_lib
  run shell__resolve_inject_line_v1 --file "${BATS_TEST_TMPDIR}/nosuch" --anchor file-top-after-comments
  assert_output "1"
}

# ---------------------------------------------------------------------------
# shell__insert_block_at_line
# ---------------------------------------------------------------------------

@test "shell__insert_block_at_line inserts before the given line" {
  reload_lib
  local _f="${BATS_TEST_TMPDIR}/insert"
  printf 'ONE=1\nTWO=2\n' > "$_f"
  shell__insert_block_at_line --file "$_f" --marker "ins" --content "MID=1" --line 2
  run grep -n 'MID=1' "$_f"
  assert_success
  # The block (blank, begin, content, end, blank = 5 lines) is inserted before
  # the old line 2, pushing TWO=2 from line 2 down to line 7.
  run bash -c "grep -n . '$_f' | grep 'TWO=2' | cut -d: -f1"
  assert_output "7"
}

@test "shell__insert_block_at_line appends when line exceeds file length (EOF fallback)" {
  reload_lib
  local _f="${BATS_TEST_TMPDIR}/eofinsert"
  printf 'ONLY=1\n' > "$_f"
  shell__insert_block_at_line --file "$_f" --marker "tailblock" --content "TAIL=1" --line 99
  run grep -c 'TAIL=1' "$_f"
  assert_output "1"
  run grep -c '# >>> tailblock >>>' "$_f"
  assert_output "1"
}

@test "shell__insert_block_at_line delegates to in-place sync when marker exists" {
  reload_lib
  local _f="${BATS_TEST_TMPDIR}/resync"
  printf 'HEAD=1\n' > "$_f"
  shell__insert_block_at_line --file "$_f" --marker "dup" --content "V=1" --line 1
  shell__insert_block_at_line --file "$_f" --marker "dup" --content "V=2" --line 99
  run grep -c '# >>> dup >>>' "$_f"
  assert_output "1"
  run grep 'V=2' "$_f"
  assert_success
  run bash -c "! grep -q 'V=1' '$_f'"
  assert_success
}
