#!/usr/bin/env bats
# Unit tests for lib/shell.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
}

# ---------------------------------------------------------------------------
# shell__detect_bashrc  (strings-probe path, then os__platform fallback)
# ---------------------------------------------------------------------------

@test "shell__detect_bashrc returns path from strings probe" {
  reload_lib shell.sh
  # Fake strings to return the compiled-in bashrc path.
  strings() { echo "/etc/bash.bashrc"; }
  export -f strings
  run shell__detect_bashrc
  assert_output "/etc/bash.bashrc"
}

@test "shell__detect_bashrc returns /etc/bashrc for rhel via platform fallback" {
  reload_lib shell.sh
  # No strings output → fall through to os__platform.
  strings() { :; }
  export -f strings
  _OS__ID="fedora"
  _OS__ID_LIKE=""
  _OS__RELEASE_LOADED=1
  run shell__detect_bashrc
  assert_output "/etc/bashrc"
}

@test "shell__detect_bashrc returns /etc/bash/bashrc for alpine via platform fallback" {
  reload_lib shell.sh
  strings() { :; }
  export -f strings
  _OS__ID="alpine"
  _OS__ID_LIKE=""
  _OS__RELEASE_LOADED=1
  run shell__detect_bashrc
  assert_output "/etc/bash/bashrc"
}

@test "shell__detect_bashrc returns /etc/bash.bashrc as default fallback" {
  reload_lib shell.sh
  strings() { :; }
  export -f strings
  _OS__ID="ubuntu"
  _OS__ID_LIKE=""
  _OS__RELEASE_LOADED=1
  run shell__detect_bashrc
  assert_output "/etc/bash.bashrc"
}

# ---------------------------------------------------------------------------
# shell__detect_zshdir  (strings-probe path, then os__platform fallback)
# ---------------------------------------------------------------------------

@test "shell__detect_zshdir returns /etc/zsh from strings probe" {
  reload_lib shell.sh
  strings() { echo "/etc/zsh/zshenv"; }
  export -f strings
  run shell__detect_zshdir
  assert_output "/etc/zsh"
}

@test "shell__detect_zshdir returns /etc from strings probe when zshenv is at /etc/zshenv" {
  reload_lib shell.sh
  strings() { echo "/etc/zshenv"; }
  export -f strings
  run shell__detect_zshdir
  assert_output "/etc"
}

@test "shell__detect_zshdir returns /etc for rhel via platform fallback" {
  reload_lib shell.sh
  strings() { :; }
  export -f strings
  _OS__ID="fedora"
  _OS__ID_LIKE=""
  _OS__RELEASE_LOADED=1
  run shell__detect_zshdir
  assert_output "/etc"
}

@test "shell__detect_zshdir returns /etc/zsh as default fallback" {
  reload_lib shell.sh
  strings() { :; }
  export -f strings
  _OS__ID="ubuntu"
  _OS__ID_LIKE=""
  _OS__RELEASE_LOADED=1
  run shell__detect_zshdir
  assert_output "/etc/zsh"
}

# ---------------------------------------------------------------------------
# shell__write_block
# ---------------------------------------------------------------------------

@test "shell__write_block appends a new block to a file" {
  reload_lib shell.sh
  local _f="${BATS_TEST_TMPDIR}/rc"
  shell__write_block --file "$_f" --marker "mytest" --content "export FOO=bar"
  assert_file_exists "$_f"
  run grep -c "# >>> mytest >>>" "$_f"
  assert_output "1"
  run grep "export FOO=bar" "$_f"
  assert_success
}

@test "shell__write_block updates existing block in place" {
  reload_lib shell.sh
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
  reload_lib shell.sh
  local _f="${BATS_TEST_TMPDIR}/subdir/rc"
  shell__write_block --file "$_f" --marker "test" --content "x=1"
  assert_file_exists "$_f"
}

# ---------------------------------------------------------------------------
# shell__user_login_file
# ---------------------------------------------------------------------------

@test "shell__user_login_file returns .bash_profile when it exists" {
  reload_lib shell.sh
  local _home="${BATS_TEST_TMPDIR}/home1"
  mkdir -p "$_home"
  touch "${_home}/.bash_profile"
  run shell__user_login_file --home "$_home"
  assert_output "${_home}/.bash_profile"
}

@test "shell__user_login_file returns .bash_login over .profile" {
  reload_lib shell.sh
  local _home="${BATS_TEST_TMPDIR}/home2"
  mkdir -p "$_home"
  touch "${_home}/.bash_login"
  touch "${_home}/.profile"
  run shell__user_login_file --home "$_home"
  assert_output "${_home}/.bash_login"
}

@test "shell__user_login_file falls back to .bash_profile when none exist" {
  reload_lib shell.sh
  local _home="${BATS_TEST_TMPDIR}/home3"
  mkdir -p "$_home"
  run shell__user_login_file --home "$_home"
  assert_output "${_home}/.bash_profile"
}

# ---------------------------------------------------------------------------
# shell__user_path_files
# ---------------------------------------------------------------------------

@test "shell__user_path_files includes login file, .bashrc and .zshenv" {
  reload_lib shell.sh
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
  reload_lib shell.sh
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
  reload_lib shell.sh
  local _custom="${BATS_TEST_TMPDIR}/zsh_custom"
  mkdir -p "${_custom}/themes/powerlevel10k"
  touch "${_custom}/themes/powerlevel10k/powerlevel10k.zsh-theme"
  run shell__resolve_omz_theme \
    --theme_slug "romkatv/powerlevel10k" \
    --custom_dir "$_custom"
  assert_output "powerlevel10k/powerlevel10k"
}

@test "shell__resolve_omz_theme returns repo name when no theme file" {
  reload_lib shell.sh
  local _custom="${BATS_TEST_TMPDIR}/zsh_custom_empty"
  mkdir -p "$_custom"
  run shell__resolve_omz_theme \
    --theme_slug "romkatv/powerlevel10k" \
    --custom_dir "$_custom"
  assert_output "powerlevel10k"
}

@test "shell__resolve_omz_theme returns empty for empty slug" {
  reload_lib shell.sh
  run shell__resolve_omz_theme --theme_slug "" --custom_dir "/tmp"
  assert_output ""
  assert_success
}

# ---------------------------------------------------------------------------
# shell__resolve_home
# ---------------------------------------------------------------------------

@test "shell__resolve_home returns home for current user" {
  reload_lib shell.sh
  local _expected
  _expected="$(eval echo "~$(whoami)")"
  run shell__resolve_home "$(whoami)"
  assert_output "$_expected"
  assert_success
}

@test "shell__resolve_home returns the correct home for the root user" {
  reload_lib shell.sh
  # Use eval to get the platform-actual home (e.g. /root on Linux, /var/root on macOS).
  local _root_home
  _root_home="$(eval echo '~root')"
  run shell__resolve_home "root"
  assert_output "$_root_home"
  assert_success
}

@test "shell__resolve_home returns unexpanded tilde for unknown user" {
  reload_lib shell.sh
  run shell__resolve_home "___no_such_user_xyz___"
  assert_output "~___no_such_user_xyz___"
  assert_success
}

# ---------------------------------------------------------------------------
# shell__sync_block
# ---------------------------------------------------------------------------

@test "shell__sync_block writes a block when --content is provided" {
  reload_lib shell.sh
  local _home="${BATS_TEST_TMPDIR}/sync_home"
  mkdir -p "$_home"
  # Use a distinct variable name: shell__sync_block internally reads lines with
  # 'while IFS= read -r _f', which (without a local declaration) overwrites any
  # caller-scoped '_f' after the loop ends with an empty value.  Avoid the clash
  # by using a different name here.
  local _syncfile="${_home}/rc"
  shell__sync_block --files "$_syncfile" --marker "myblock" --content "export X=1"
  assert_file_exists "$_syncfile"
  run grep "export X=1" "$_syncfile"
  assert_success
}

@test "shell__sync_block removes an existing block when --content is absent" {
  reload_lib shell.sh
  local _f="${BATS_TEST_TMPDIR}/rcremove"
  shell__write_block --file "$_f" --marker "removetest" --content "export Y=2"
  shell__sync_block --files "$_f" --marker "removetest"
  run grep "removetest" "$_f"
  assert_failure
}

@test "shell__sync_block skips removal for non-existent file" {
  reload_lib shell.sh
  local _f="${BATS_TEST_TMPDIR}/nope_rc"
  # File doesn't exist; sync_block with no --content should be a no-op (no error).
  run shell__sync_block --files "$_f" --marker "absent"
  assert_success
}

# ---------------------------------------------------------------------------
# shell__system_path_files
# ---------------------------------------------------------------------------

@test "shell__system_path_files returns bashrc and zshenv paths" {
  reload_lib shell.sh
  strings() { echo "/etc/bash.bashrc"; }
  export -f strings
  BASH_ENV="/etc/bashenv"
  run shell__system_path_files
  # Output must contain the bashrc and zshenv paths.
  assert_output --partial "/etc/bash.bashrc"
  assert_output --partial "zshenv"
  assert_success
}

@test "shell__system_path_files includes profile.d path when --profile_d is given" {
  reload_lib shell.sh
  strings() { echo "/etc/bash.bashrc"; }
  export -f strings
  BASH_ENV="/etc/bashenv"
  run shell__system_path_files --profile_d "myenv.sh"
  assert_output --partial "/etc/profile.d/myenv.sh"
  assert_success
}

# ---------------------------------------------------------------------------
# shell__ensure_bashenv
# ---------------------------------------------------------------------------

@test "shell__ensure_bashenv returns BASH_ENV when already set in environment" {
  reload_lib shell.sh
  BASH_ENV="/usr/local/etc/bashenv" run shell__ensure_bashenv
  assert_output --partial "/usr/local/etc/bashenv"
  assert_success
}

@test "shell__ensure_bashenv reads BASH_ENV from _SHELL_ENV_FILE when entry exists" {
  reload_lib shell.sh
  local _env="${BATS_TEST_TMPDIR}/environment"
  printf 'BASH_ENV="/etc/bash/bashenv"\n' > "$_env"
  _SHELL_ENV_FILE="$_env" run shell__ensure_bashenv
  assert_success
  assert_output --partial "/etc/bash/bashenv"
}

@test "shell__ensure_bashenv creates bashenv file and registers it when no entry exists" {
  reload_lib shell.sh
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
  reload_lib shell.sh
  ZDOTDIR="/custom/zsh" run shell__detect_zdotdir --home "$HOME"
  assert_output "/custom/zsh"
}

@test "shell__detect_zdotdir falls back to home when no ZDOTDIR and no zshenv" {
  reload_lib shell.sh
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
  reload_lib shell.sh
  local _home="${BATS_TEST_TMPDIR}/homeZD2"
  mkdir -p "$_home"
  printf 'export ZDOTDIR="$HOME/.config/zsh"\n' > "${_home}/.zshenv"
  shell__detect_zshdir() { echo "${BATS_TEST_TMPDIR}/no_etc_zsh"; }
  export -f shell__detect_zshdir
  run shell__detect_zdotdir --home "$_home"
  assert_output "${_home}/.config/zsh"
}

@test "shell__detect_zdotdir parses ZDOTDIR=\${HOME}/... from user .zshenv" {
  reload_lib shell.sh
  local _home="${BATS_TEST_TMPDIR}/homeZD3"
  mkdir -p "$_home"
  printf 'ZDOTDIR="${HOME}/.config/zsh"\n' > "${_home}/.zshenv"
  shell__detect_zshdir() { echo "${BATS_TEST_TMPDIR}/no_etc_zsh"; }
  export -f shell__detect_zshdir
  run shell__detect_zdotdir --home "$_home"
  assert_output "${_home}/.config/zsh"
}

@test "shell__detect_zdotdir parses ZDOTDIR=~/... from user .zshenv" {
  reload_lib shell.sh
  local _home="${BATS_TEST_TMPDIR}/homeZD4"
  mkdir -p "$_home"
  printf 'ZDOTDIR=~/.config/zsh\n' > "${_home}/.zshenv"
  shell__detect_zshdir() { echo "${BATS_TEST_TMPDIR}/no_etc_zsh"; }
  export -f shell__detect_zshdir
  run shell__detect_zdotdir --home "$_home"
  assert_output "${_home}/.config/zsh"
}

@test "shell__detect_zdotdir substitutes \$XDG_CONFIG_HOME" {
  reload_lib shell.sh
  local _home="${BATS_TEST_TMPDIR}/homeZD5"
  mkdir -p "$_home"
  printf 'export ZDOTDIR="$XDG_CONFIG_HOME/zsh"\n' > "${_home}/.zshenv"
  shell__detect_zshdir() { echo "${BATS_TEST_TMPDIR}/no_etc_zsh"; }
  export -f shell__detect_zshdir
  XDG_CONFIG_HOME="${_home}/.xdg" run shell__detect_zdotdir --home "$_home"
  assert_output "${_home}/.xdg/zsh"
}

@test "shell__detect_zdotdir defaults XDG_CONFIG_HOME to home/.config" {
  reload_lib shell.sh
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
  reload_lib shell.sh
  local _home="${BATS_TEST_TMPDIR}/homeZD7"
  mkdir -p "$_home"
  printf 'ZDOTDIR="${CUSTOM_VAR}/zsh"\n' > "${_home}/.zshenv"
  shell__detect_zshdir() { echo "${BATS_TEST_TMPDIR}/no_etc_zsh"; }
  export -f shell__detect_zshdir
  run shell__detect_zdotdir --home "$_home"
  assert_output "$_home"
}

@test "shell__detect_zdotdir user .zshenv overrides system zshenv" {
  reload_lib shell.sh
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
  reload_lib shell.sh
  local _home="${BATS_TEST_TMPDIR}/homePF"
  mkdir -p "$_home"
  touch "${_home}/.bash_login"
  run shell__user_path_files --home "$_home"
  assert_output "${_home}/.bash_login
${_home}/.bashrc
${_home}/.zshenv"
}

@test "shell__user_path_files uses --zdotdir for .zshenv" {
  reload_lib shell.sh
  local _home="${BATS_TEST_TMPDIR}/homePZ"
  local _zd="${BATS_TEST_TMPDIR}/zdotPZ"
  mkdir -p "$_home" "$_zd"
  run shell__user_path_files --home "$_home" --zdotdir "$_zd"
  assert_output "${_home}/.bash_profile
${_home}/.bashrc
${_zd}/.zshenv"
}

@test "shell__user_path_files auto-detects zdotdir from .zshenv" {
  reload_lib shell.sh
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
  reload_lib shell.sh
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
  reload_lib shell.sh
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
  reload_lib shell.sh
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
  reload_lib shell.sh
  local _home="${BATS_TEST_TMPDIR}/homeRC1"
  mkdir -p "$_home"
  run shell__user_rc_files --home "$_home"
  assert_output "${_home}/.bashrc
${_home}/.zshrc"
}

@test "shell__user_rc_files does not include login file" {
  reload_lib shell.sh
  local _home="${BATS_TEST_TMPDIR}/homeRC2"
  mkdir -p "$_home"
  touch "${_home}/.bash_profile"
  run shell__user_rc_files --home "$_home"
  # Must NOT contain .bash_profile
  refute_output --partial ".bash_profile"
  assert_output --partial ".bashrc"
}

@test "shell__user_rc_files uses explicit --zdotdir for .zshrc" {
  reload_lib shell.sh
  local _home="${BATS_TEST_TMPDIR}/homeRCZ"
  local _zd="${BATS_TEST_TMPDIR}/zdotRCZ"
  mkdir -p "$_home" "$_zd"
  run shell__user_rc_files --home "$_home" --zdotdir "$_zd"
  assert_output "${_home}/.bashrc
${_zd}/.zshrc"
}

@test "shell__user_rc_files auto-detects zdotdir from .zshenv" {
  reload_lib shell.sh
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
  reload_lib shell.sh
  strings() { echo "/etc/bash.bashrc"; }
  export -f strings
  _OS__ID="ubuntu"
  _OS__ID_LIKE=""
  _OS__RELEASE_LOADED=1
  run shell__system_rc_files
  assert_output "/etc/bash.bashrc
/etc/zsh/zshrc"
  assert_success
}

@test "shell__system_rc_files uses distro-correct bashrc for fedora" {
  reload_lib shell.sh
  strings() { :; }
  export -f strings
  _OS__ID="fedora"
  _OS__ID_LIKE=""
  _OS__RELEASE_LOADED=1
  run shell__system_rc_files
  assert_output "/etc/bashrc
/etc/zshrc"
  assert_success
}

@test "shell__system_rc_files uses /etc/zsh/zshrc for debian-family" {
  reload_lib shell.sh
  strings() { echo "/etc/bash.bashrc"; }
  export -f strings
  _OS__ID="debian"
  _OS__ID_LIKE=""
  _OS__RELEASE_LOADED=1
  run shell__system_rc_files
  assert_output "/etc/bash.bashrc
/etc/zsh/zshrc"
  assert_success
}

# ---------------------------------------------------------------------------
# shell__create_symlink
# ---------------------------------------------------------------------------

# Fake passwd with two users: vscode (/home/vscode) and bob (/Users/bob).
_FAKE_PASSWD="root:x:0:0:root:/root:/bin/bash
vscode:x:1000:1000::/home/vscode:/bin/bash
bob:x:1001:1001::/Users/bob:/bin/zsh"

@test "shell__create_symlink creates system-wide symlink for non-home src" {
  reload_lib shell.sh
  local _src="${BATS_TEST_TMPDIR}/opt/mytool/bin/mytool"
  local _sys="${BATS_TEST_TMPDIR}/usr/local/bin/mytool"
  local _usr="${BATS_TEST_TMPDIR}/home/user/.local/bin/mytool"
  mkdir -p "$(dirname "$_src")"
  touch "$_src"
  getent() { printf '%s\n' "$_FAKE_PASSWD"; }
  export -f getent
  run shell__create_symlink \
    --src "$_src" \
    --system-target "$_sys" \
    --user-target "$_usr"
  assert_success
  assert [ -L "$_sys" ]
  assert [ ! -e "$_usr" ]
}

@test "shell__create_symlink creates user-scoped symlink for /home src" {
  reload_lib shell.sh
  local _src="/home/vscode/.mypixi/bin/pixi"
  local _sys="${BATS_TEST_TMPDIR}/usr/local/bin/pixi"
  local _usr="${BATS_TEST_TMPDIR}/home/vscode/.pixi/bin/pixi"
  getent() { printf '%s\n' "$_FAKE_PASSWD"; }
  export -f getent
  run shell__create_symlink \
    --src "$_src" \
    --system-target "$_sys" \
    --user-target "$_usr"
  assert_success
  assert [ -L "$_usr" ]
  assert [ ! -e "$_sys" ]
}

@test "shell__create_symlink creates user-scoped symlink for custom home src" {
  reload_lib shell.sh
  local _src="/data/users/alice/mytool/bin/mytool"
  local _sys="${BATS_TEST_TMPDIR}/usr/local/bin/mytool"
  local _usr="${BATS_TEST_TMPDIR}/data/users/alice/.local/bin/mytool"
  # alice has a custom home dir not matching /home/* or /Users/*
  getent() {
    printf '%s\n' "$_FAKE_PASSWD"
    printf 'alice:x:1002:1002::/data/users/alice:/bin/bash\n'
  }
  export -f getent
  run shell__create_symlink \
    --src "$_src" \
    --system-target "$_sys" \
    --user-target "$_usr"
  assert_success
  assert [ -L "$_usr" ]
  assert [ ! -e "$_sys" ]
}

@test "shell__create_symlink creates user-scoped symlink for /Users src" {
  reload_lib shell.sh
  local _src="/Users/bob/.mypixi/bin/pixi"
  local _sys="${BATS_TEST_TMPDIR}/usr/local/bin/pixi"
  local _usr="${BATS_TEST_TMPDIR}/Users/bob/.pixi/bin/pixi"
  getent() { printf '%s\n' "$_FAKE_PASSWD"; }
  export -f getent
  run shell__create_symlink \
    --src "$_src" \
    --system-target "$_sys" \
    --user-target "$_usr"
  assert_success
  assert [ -L "$_usr" ]
  assert [ ! -e "$_sys" ]
}

@test "shell__create_symlink falls back to _SHELL_PASSWD_FILE when getent unavailable" {
  reload_lib shell.sh
  local _passwd="${BATS_TEST_TMPDIR}/passwd"
  printf '%s\n' "$_FAKE_PASSWD" > "$_passwd"
  local _src="/home/vscode/.mypixi/bin/pixi"
  local _sys="${BATS_TEST_TMPDIR}/usr/local/bin/pixi"
  local _usr="${BATS_TEST_TMPDIR}/home/vscode/.pixi/bin/pixi"
  _SHELL_PASSWD_FILE="$_passwd" run shell__create_symlink \
    --src "$_src" \
    --system-target "$_sys" \
    --user-target "$_usr"
  assert_success
  assert [ -L "$_usr" ]
  assert [ ! -e "$_sys" ]
}

@test "shell__create_symlink skips when src equals chosen target" {
  reload_lib shell.sh
  local _path="${BATS_TEST_TMPDIR}/usr/local/bin/mytool"
  getent() { printf '%s\n' "$_FAKE_PASSWD"; }
  export -f getent
  run shell__create_symlink \
    --src "$_path" \
    --system-target "$_path" \
    --user-target "${BATS_TEST_TMPDIR}/home/u/.local/bin/mytool"
  assert_success
  assert_output --partial "no symlink needed"
  assert [ ! -e "$_path" ]
}

@test "shell__create_symlink errors when target is a real file" {
  reload_lib shell.sh
  local _sys="${BATS_TEST_TMPDIR}/usr/local/bin/mytool"
  mkdir -p "$(dirname "$_sys")"
  touch "$_sys"
  getent() { printf '%s\n' "$_FAKE_PASSWD"; }
  export -f getent
  run shell__create_symlink \
    --src "/opt/mytool/bin/mytool" \
    --system-target "$_sys" \
    --user-target "${BATS_TEST_TMPDIR}/home/u/.local/bin/mytool"
  assert_failure
  assert_output --partial "exists as a real file or directory"
}

@test "shell__create_symlink replaces stale symlink" {
  reload_lib shell.sh
  local _sys="${BATS_TEST_TMPDIR}/usr/local/bin/mytool"
  local _old_src="${BATS_TEST_TMPDIR}/old/src"
  local _new_src="${BATS_TEST_TMPDIR}/new/src"
  mkdir -p "$(dirname "$_sys")"
  ln -s "$_old_src" "$_sys"
  getent() { printf '%s\n' "$_FAKE_PASSWD"; }
  export -f getent
  run shell__create_symlink \
    --src "$_new_src" \
    --system-target "$_sys" \
    --user-target "${BATS_TEST_TMPDIR}/home/u/.local/bin/mytool"
  assert_success
  run readlink "$_sys"
  assert_output "$_new_src"
}

@test "shell__create_symlink creates parent directories for target" {
  reload_lib shell.sh
  local _sys="${BATS_TEST_TMPDIR}/deep/nested/bin/mytool"
  getent() { printf '%s\n' "$_FAKE_PASSWD"; }
  export -f getent
  run shell__create_symlink \
    --src "/opt/mytool/bin/mytool" \
    --system-target "$_sys" \
    --user-target "${BATS_TEST_TMPDIR}/home/u/.local/bin/mytool"
  assert_success
  assert [ -L "$_sys" ]
}
