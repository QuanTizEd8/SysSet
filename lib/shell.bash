# shellcheck shell=bash
# Shell startup file helpers: detect, read, and write login shell configuration.
#
# Provides helpers for detecting system-wide and per-user startup files,
# writing idempotent named config blocks, and resolving `ZDOTDIR` for zsh.
# Supports bash, zsh, and login-shell path configuration.

# Shared awk helpers used by shell__write_block and shell__sync_block.
# norm() strips BOM, leading/trailing whitespace, and CR; is_blank_line() tests for empty.
_SHELL__AWK_NORM='
  function norm(l) {
    if (length(l) >= 3 && substr(l, 1, 3) == "\357\273\277") l = substr(l, 4)
    sub(/^[[:space:]]+/, "", l)
    sub(/\r$/, "", l)
    sub(/[[:space:]]+$/, "", l)
    return l
  }
  function is_blank_line(l) { return norm(l) == "" }
'

shell__bash() {
  # @brief shell__bash — Run the active bash binary.
  # Uses _BASH_BIN set by install.sh bootstrap when available; otherwise falls back to bash on PATH.
  "${_BASH_BIN:-bash}" "$@"
}

shell__detect_bashrc() {
  # @brief shell__detect_bashrc — Print the system-wide bashrc path for the current distro.
  #
  # Uses os-release platform IDs. Never uses file-existence checks — a file at
  # the wrong path for this distro won't be sourced by any shell.
  #
  # Stdout: one of `/etc/bash.bashrc`, `/etc/bashrc`, or `/etc/bash/bashrc`.
  case "$(os__platform)" in
    alpine)
      echo "/etc/bash/bashrc"
      return 0
      ;;
    rhel | suse | macos)
      echo "/etc/bashrc"
      return 0
      ;;
  esac
  echo "/etc/bash.bashrc"
  return 0
}

shell__detect_zshdir() {
  # @brief shell__detect_zshdir — Print the system-wide zsh config directory (`/etc/zsh` or `/etc`). Uses binary probing, never directory-existence checks.
  #
  # Detection order: (1) strings-probe the zsh binary (zsh compiles in the
  # path of its global zshenv); (2) os-release platform IDs. Never uses
  # directory-existence checks — a directory at the wrong path won't be used
  # by the shell anyway.
  #
  # Stdout: `/etc/zsh` (most distros) or `/etc` (Fedora/RHEL, openSUSE, macOS).

  # Ask zsh which global zshenv path it was compiled with.
  local _compiled
  bootstrap__strings || true
  _compiled="$(strings "$(command -v zsh 2> /dev/null)" 2> /dev/null |
    grep -m1 -E '^/etc/(zsh/)?zshenv$' || true)"
  if [ -n "$_compiled" ]; then
    dirname "$_compiled"
    return 0
  fi
  # os__platform fallback.
  case "$(os__platform)" in
    rhel | suse | macos)
      echo "/etc"
      return 0
      ;;
  esac
  echo "/etc/zsh"
  return 0
}

shell__detect_installed_shells() {
  # @brief shell__detect_installed_shells — Print the names of shells that appear to be installed on this system.
  #
  # A shell is considered present if its binary is on PATH or any well-known
  # system config file for it exists. Always emits at least `bash` (the
  # running interpreter).
  #
  # Stdout: one shell name per line (bash, zsh, fish, tcsh, elvish).
  local -a _dsh_shells=(bash)
  local _zshdir
  _zshdir="$(shell__detect_zshdir)"
  if command -v zsh > /dev/null 2>&1 || [ -f "${_zshdir}/zshenv" ] || [ -f "${_zshdir}/zshrc" ]; then
    _dsh_shells+=(zsh)
  fi
  if command -v fish > /dev/null 2>&1 || [ -d "/etc/fish" ]; then
    _dsh_shells+=(fish)
  fi
  command -v tcsh > /dev/null 2>&1 && _dsh_shells+=(tcsh) || true
  command -v elvish > /dev/null 2>&1 && _dsh_shells+=(elvish) || true
  printf '%s\n' "${_dsh_shells[@]}"
  return 0
}

shell__detect_fish_sysdir() {
  # @brief shell__detect_fish_sysdir — Print the system-wide fish vendor completions directory.
  #
  # On macOS (Darwin), /usr/share is a read-only filesystem even for root (SIP
  # applies), so the Linux-standard /usr/share/fish/vendor_completions.d cannot
  # be created there.  Instead, resolve the Homebrew prefix and return
  # `${brew_prefix}/share/fish/vendor_completions.d`.  If Homebrew is absent,
  # no system fish path is usable — print nothing and return 0.
  #
  # On Linux, return the FHS path /usr/share/fish/vendor_completions.d.
  #
  # Stdout: the system fish vendor completions directory, or empty on macOS
  #         when Homebrew is not installed.
  if [ "$(os__kernel)" = "Darwin" ]; then
    local _prefix
    _prefix="$(brew --prefix 2> /dev/null)" || true
    [[ -n "${_prefix}" ]] && printf '%s\n' "${_prefix}/share/fish/vendor_completions.d" || true
  else
    printf '%s\n' "/usr/share/fish/vendor_completions.d"
  fi
}

shell__write_block() {
  # @brief shell__write_block --file <f> --marker <id> --content <c> — Idempotently write a named `# >>> <id> >>>` … `# <<< <id> <<<` block to a file. Creates the file if needed.
  #
  # Updates the block in-place if the marker already exists; appends otherwise.
  # Creates parent directories and the file if they do not exist.
  # Blank lines: one empty line below every block; one empty line above unless the
  # begin marker would be the first line of the file (append or in-place update).
  #
  # Args:
  #   --file <f>     Path to the target file.
  #   --marker <id>  Block identifier used in the begin/end comment markers.
  #   --content <c>  Content to write inside the block.
  local _file="" _marker="" _content="" _lb=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --file)
        shift
        _file="$1"
        shift
        ;;
      --marker)
        shift
        _marker="$1"
        shift
        ;;
      --content)
        shift
        _content="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  [[ -n "$_file" && -n "$_marker" ]] || {
    logging__error "--file and --marker are required."
    return 1
  }
  logging__install "Writing shell block '${_marker}' to '${_file}'."
  local _begin="# >>> ${_marker} >>>"
  local _end="# <<< ${_marker} <<<"
  file__mkdir "$(dirname "$_file")"
  if [[ ! -f "$_file" ]]; then
    printf '' | file__tee "$_file"
  fi
  if grep -qF "$_begin" "$_file"; then
    # Normalize marker lines before comparing: hosted macOS ~/.bash_profile often
    # uses CRLF; some images also add a UTF-8 BOM and/or leading whitespace on
    # continued lines. grep -qF still finds the marker substring, but raw $0
    # equality with begin/end would otherwise never match.
    #
    # Content is passed via ENVIRON, not `awk -v`: -v assignments undergo awk's
    # C-escape processing, which mangles backslashes in shell content (gawk
    # strips unknown escapes like `\u` in PS1 strings and eats `\<newline>`
    # line continuations).
    #
    # Formatting: one blank line above the block when it is not the first line
    # in the file (unless a blank line is already there); one blank line below —
    # swallowing one pre-existing blank after the old end marker so repeated
    # updates don't accumulate blank lines.
    local _tmp
    _tmp="$(mktemp)"
    _SHELL__WB_CONTENT="$_content" \
      awk -v begin="$_begin" -v end="$_end" "$_SHELL__AWK_NORM"'
      BEGIN { last_blank = 1; content = ENVIRON["_SHELL__WB_CONTENT"] }
      norm($0) == begin {
        if (NR > 1 && !last_blank) print ""
        print begin
        print content
        found = 1
        next
      }
      found && norm($0) == end {
        print end
        print ""
        last_blank = 1
        found = 0
        swallow_blank = 1
        next
      }
      found { next }
      swallow_blank { swallow_blank = 0; if (is_blank_line($0)) next }
      { print; last_blank = is_blank_line($0) }
    ' "$_file" > "$_tmp" && file__cp "$_tmp" "$_file"
    rm -f "$_tmp"
    logging__info "Updated shell block '${_marker}' in '${_file}'."
  else
    # Begin marker starts on its own line. Surround with blank lines: none above
    # when the block is the entire file; otherwise one empty line above (after
    # ensuring the file ends with a newline) and one empty line below.
    if [ -f "$_file" ] && [ -s "$_file" ]; then
      _lb="$(tail -c1 "$_file" 2> /dev/null || printf '')"
      if [ "$_lb" != "$(printf '\n')" ]; then
        printf '\n' | file__tee --append "$_file"
      fi
      printf '\n%s\n%s\n%s\n\n' "$_begin" "$_content" "$_end" | file__tee --append "$_file"
    else
      printf '%s\n%s\n%s\n\n' "$_begin" "$_content" "$_end" | file__tee --append "$_file"
    fi
    logging__success "Appended shell block '${_marker}' to '${_file}'."
  fi
  return 0
}

shell__resolve_inject_line_v1() {
  # @brief shell__resolve_inject_line_v1 --file <f> --anchor <a> — Print the 1-based line number before which a new marker block should be inserted on first inject into an existing file.
  #
  # Anchors (v1 — minimal enum, see inject_anchor in feature registries):
  #   file-top-after-comments          First line that is not a leading `#` comment or blank; falls back to EOF if the whole file is comments/blank.
  #   after-interactivity-guard-or-eof  Line after a `case $- in ... esac` interactivity guard's closing `esac`; falls back to EOF if no such guard is found.
  #
  # A returned value of `<total lines in file> + 1` means "insert at end of
  # file" (there is no line `n` to insert before). Callers (see
  # shell__insert_block_at_line) must treat this as an append, not a no-op —
  # an awk pass keyed purely on `NR == n` would never fire for it.
  #
  # Args:
  #   --file <f>     Path to the file being scanned. A missing file resolves to line 1.
  #   --anchor <a>   One of the two anchors above (any other value, including `eof`, resolves to end-of-file — callers should prefer shell__write_block directly for plain `eof`).
  #
  # Stdout: a single 1-based line number, followed by a newline.
  local _file="" _anchor="eof"
  while [[ $# -gt 0 ]]; do
    case $1 in
      --file)
        shift
        _file="$1"
        shift
        ;;
      --anchor)
        shift
        _anchor="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  [[ -n "$_file" ]] || {
    logging__error "shell__resolve_inject_line_v1: --file is required."
    return 1
  }
  if [[ ! -f "$_file" ]]; then
    printf '1\n'
    return 0
  fi
  case "$_anchor" in
    file-top-after-comments)
      # Skip existing managed marker blocks too (their begin lines are `#`
      # comments, but their bodies are code) so a second top-anchored inject
      # stacks BELOW a previous one instead of landing inside its markers.
      awk '
        /^[[:space:]]*# >>> / { inblock = 1; next }
        /^[[:space:]]*# <<< / { inblock = 0; next }
        inblock { next }
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        { print NR; found = 1; exit }
        END { if (!found) print NR + 1 }
      ' "$_file"
      ;;
    after-interactivity-guard-or-eof)
      # Find a `case $- in ... esac` interactivity guard and return the line
      # after its closing `esac`; else EOF. Guards *inside* an existing managed
      # marker block (# >>> ... >>> / # <<< ... <<<) are skipped — otherwise a
      # previously-injected guard block would itself be matched, causing every
      # subsequent block to nest inside it.
      awk '
        /^[[:space:]]*# >>> / { inblock = 1; next }
        /^[[:space:]]*# <<< / { inblock = 0; next }
        inblock { next }
        /^[[:space:]]*case[[:space:]]+\$-[[:space:]]+in/ { inguard = 1 }
        inguard && /^[[:space:]]*esac[[:space:]]*$/ { print NR + 1; found = 1; exit }
        END { if (!found) print NR + 1 }
      ' "$_file"
      ;;
    *)
      awk 'END { print NR + 1 }' "$_file"
      ;;
  esac
  return 0
}

shell__insert_block_at_line() {
  # @brief shell__insert_block_at_line --file <f> --marker <id> --content <c> --line <n> — Insert a new marker block before 1-based line <n>, appending at end of file when <n> is past the last line.
  #
  # If the marker already exists in the file, delegates to shell__write_block
  # (in-place sync at its current position) instead of inserting a second copy.
  #
  # `<n>` past the last line (as returned by shell__resolve_inject_line_v1's
  # EOF fallback) is handled by an explicit END-block append, not just the
  # `NR == n` match — a file with N lines never produces a record numbered
  # N+1, so relying solely on line-number matching would silently insert
  # nothing when the anchor search comes up empty. This is deliberate, not an
  # oversight: appending at the true end of file is a safe fallback even when
  # the anchor isn't found (see the registry's inject_anchor documentation).
  #
  # Args:
  #   --file <f>     Path to the target file.
  #   --marker <id>  Block identifier used in the begin/end comment markers.
  #   --content <c>  Content to write inside the block.
  #   --line <n>     1-based line number to insert before (from shell__resolve_inject_line_v1).
  local _file="" _marker="" _content="" _line=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --file)
        shift
        _file="$1"
        shift
        ;;
      --marker)
        shift
        _marker="$1"
        shift
        ;;
      --content)
        shift
        _content="$1"
        shift
        ;;
      --line)
        shift
        _line="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  [[ -n "$_file" && -n "$_marker" && -n "$_line" ]] || {
    logging__error "shell__insert_block_at_line: --file, --marker, and --line are required."
    return 1
  }
  local _begin="# >>> ${_marker} >>>"
  local _end="# <<< ${_marker} <<<"
  file__mkdir "$(dirname "$_file")"
  [[ -f "$_file" ]] || printf '' | file__tee "$_file"
  if grep -qF "$_begin" "$_file"; then
    shell__write_block --file "$_file" --marker "$_marker" --content "$_content"
    return $?
  fi
  # Content via ENVIRON, not `awk -v`: -v assignments undergo awk's C-escape
  # processing, which mangles backslashes in shell content (gawk strips unknown
  # escapes like `\u` in PS1 strings and eats `\<newline>` line continuations).
  local _tmp
  _tmp="$(mktemp)"
  _SHELL__WB_CONTENT="$_content" \
    awk -v n="$_line" -v begin="$_begin" -v end="$_end" '
    BEGIN { content = ENVIRON["_SHELL__WB_CONTENT"] }
    NR == n { print ""; print begin; print content; print end; print "" }
    { print }
    END { if (NR < n) { print ""; print begin; print content; print end; print "" } }
  ' "$_file" > "$_tmp" && file__cp "$_tmp" "$_file"
  rm -f "$_tmp"
  logging__success "Inserted shell block '${_marker}' at line ${_line} in '${_file}'."
  return 0
}

shell__sync_block() {
  # @brief shell__sync_block --files <list> --marker <id> [--content <c>] — Write (if `--content` given) or remove the named block in each file in the newline-separated list.
  #
  # For each file in the newline-separated <files> list:
  #   - If --content is given: write or update the named idempotency block.
  #   - If --content is absent: remove the named idempotency block if present.
  # Skips blank lines in the file list.
  #
  # Args:
  #   --files <list>  Newline-separated list of file paths.
  #   --marker <id>   Block identifier (same format as shell__write_block).
  #   --content <c>   Block content (optional; omit to remove the block).
  local _files="" _marker="" _content="" _has_content=false
  while [[ $# -gt 0 ]]; do
    case $1 in
      --files)
        shift
        _files="$1"
        shift
        ;;
      --marker)
        shift
        _marker="$1"
        shift
        ;;
      --content)
        shift
        _content="$1"
        _has_content=true
        shift
        ;;
      *) shift ;;
    esac
  done
  local _begin="# >>> ${_marker} >>>"
  local _end="# <<< ${_marker} <<<"
  local _f
  while IFS= read -r _f; do
    [ -z "$_f" ] && continue
    if [ "$_has_content" = true ]; then
      shell__write_block --file "$_f" --marker "$_marker" --content "$_content"
    else
      [ -f "$_f" ] || continue
      grep -qF "$_begin" "$_f" || continue
      awk -v begin="$_begin" -v end="$_end" "$_SHELL__AWK_NORM"'
        norm($0) == begin { found=1; next }
        found && norm($0) == end { found=0; next }
        found { next }
        { print }
      ' "$_f" > "${_f}.tmp" && mv "${_f}.tmp" "$_f"
      logging__remove "Removed shell block '${_marker}' from '${_f}'."
    fi
  done <<< "$_files"
  return 0
}

shell__user_login_file() {
  # @brief shell__user_login_file [--home <dir>] — Print the bash login startup file path (`~/.bash_profile`, `~/.bash_login`, or `~/.profile`). Falls back to `~/.bash_profile`.
  #
  # Probes in order: .bash_profile, .bash_login, .profile. Falls back to
  # <home>/.bash_profile if none exist yet.
  #
  # Args:
  #   --home <dir>  User home directory (default: $HOME).
  #
  # Stdout: absolute path to the login file.
  local _home="${HOME:-}"
  while [[ $# -gt 0 ]]; do
    case $1 in
      --home)
        shift
        _home="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  local _f
  for _f in "${_home}/.bash_profile" "${_home}/.bash_login" "${_home}/.profile"; do
    [ -f "$_f" ] && {
      echo "$_f"
      return 0
    }
  done
  echo "${_home}/.bash_profile"
  return 0
}

shell__system_path_files() {
  # @brief shell__system_path_files [--profile_d <filename>] — Print system-wide shell startup file paths for PATH/env injection.
  #
  # Intended for use when configuring PATH or environment variables as root
  # on Linux. Prints one path per line:
  # BASH_ENV file (via shell__ensure_bashenv); /etc/profile.d/<f> (if --profile_d given); global bashrc; <zshdir>/zshenv.
  #
  # Args:
  #   --profile_d <filename>  Base filename for an /etc/profile.d/ drop-in (optional).
  #
  # Stdout: one path per line for each applicable shell startup file.
  local _profiled=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --profile_d)
        shift
        _profiled="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  shell__ensure_bashenv
  [ -n "$_profiled" ] && echo "/etc/profile.d/${_profiled}"
  shell__detect_bashrc
  echo "$(shell__detect_zshdir)/zshenv"
  return 0
}

shell__detect_zdotdir() {
  # @brief shell__detect_zdotdir [--home <dir>] [--user <username>] — Print the effective ZDOTDIR for a user. Probes the live environment, parses system and user zshenv, then falls back to `<home>`.
  #
  # Detection order:
  #   1. If --user is given and is a different user and zsh is available:
  #      run `zsh` as that user to read ZDOTDIR from the live environment.
  #   2. If <home> matches $HOME and $ZDOTDIR is set → use $ZDOTDIR directly
  #      (we are the target user; the value is live in the current environment).
  #   3. Parse ZDOTDIR= assignments from the system zshenv and <home>/.zshenv.
  #      Substitutes $HOME, ${HOME}, ~, $XDG_CONFIG_HOME, ${XDG_CONFIG_HOME}.
  #      Falls back to the next tier if the result still contains unresolvable variables.
  #   4. Falls back to <home>.
  #
  # Args:
  #   --home <dir>      User home directory (default: $HOME).
  #   --user <username> Target username. When given and differs from the current
  #                     user, spawns zsh as that user to read the live ZDOTDIR.
  #
  # Stdout: absolute path to the effective ZDOTDIR.
  local _home="${HOME:-}" _user=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --home)
        shift
        _home="$1"
        shift
        ;;
      --user)
        shift
        _user="$1"
        shift
        ;;
      *) shift ;;
    esac
  done

  # Tier 1: run zsh as the target user to get the live ZDOTDIR.
  # Only when a username is given, it differs from the current user, and zsh
  # is available.
  if [[ -n "$_user" && "$_user" != "$(users__get_current --no-sudo 2> /dev/null)" ]] &&
    command -v zsh > /dev/null 2>&1; then
    local _live_zdotdir=""
    # shellcheck disable=SC2016  # ZDOTDIR is a zsh variable, not a bash variable
    _live_zdotdir="$(users__run_as "$_user" -- zsh -c 'printf "%s" "${ZDOTDIR:-}"' \
      2> /dev/null || true)"
    if [[ -n "$_live_zdotdir" ]]; then
      echo "$_live_zdotdir"
      return 0
    fi
  fi

  # Tier 2: live environment — we ARE the target user.
  if [[ "$_home" == "${HOME:-}" && -n "${ZDOTDIR:-}" ]]; then
    echo "$ZDOTDIR"
    return 0
  fi

  # Tier 3: parse ZDOTDIR= from zshenv files.
  local _zshenv_files=""
  local _sys_zshenv
  _sys_zshenv="$(shell__detect_zshdir)/zshenv"
  [[ -f "$_sys_zshenv" ]] && _zshenv_files="$_sys_zshenv"
  [[ -f "${_home}/.zshenv" ]] && _zshenv_files="${_zshenv_files:+${_zshenv_files}
}${_home}/.zshenv"

  if [[ -n "$_zshenv_files" ]]; then
    local _val="" _f
    while IFS= read -r _f; do
      [[ -z "$_f" ]] && continue
      # Match last ZDOTDIR= assignment (last wins, like shell evaluation).
      # Strips optional 'export ', quotes, and trailing comments.
      # Uses [[:space:]] instead of \s for macOS sed compatibility.
      _val="$(grep -E '^[[:space:]]*(export[[:space:]]+)?ZDOTDIR=' "$_f" 2> /dev/null | tail -1 |
        sed -E 's/^[[:space:]]*(export[[:space:]]+)?ZDOTDIR=//; s/^["'"'"']//; s/["'"'"'][[:space:]]*(#.*)?$//; s/[[:space:]]*#.*//')" || true
      # Keep iterating — user .zshenv overrides system zshenv.
    done <<< "$_zshenv_files"
    if [[ -n "$_val" ]]; then
      # Substitute known variables with concrete values.
      local _xdg="${XDG_CONFIG_HOME:-${_home}/.config}"
      _val="${_val//\$\{XDG_CONFIG_HOME\}/$_xdg}"
      _val="${_val//\$XDG_CONFIG_HOME/$_xdg}"
      _val="${_val//\$\{HOME\}/$_home}"
      _val="${_val//\$HOME/$_home}"
      _val="${_val/#\~/$_home}"
      # If unresolvable variables remain, fall back to <home>.
      if [[ "$_val" == *'$'* ]]; then
        echo "$_home"
        return 0
      fi
      echo "$_val"
      return 0
    fi
  fi

  # Tier 4: fallback.
  echo "$_home"
  return 0
}

shell__detect_xdg_config_home() {
  # @brief shell__detect_xdg_config_home [<username>] — Print the effective XDG_CONFIG_HOME for a user.
  #
  # Detection order:
  #   1. If a username is given and differs from the current user and bash is
  #      available: run `bash` as that user to read XDG_CONFIG_HOME from the
  #      live environment.
  #   2. If no username (or same as current user) and $XDG_CONFIG_HOME is set
  #      in the current environment → use it directly.
  #   3. Falls back to `<home>/.config`.
  #
  # Args:
  #   <username>  (optional positional) Target username. Home is resolved via
  #               users__resolve_home. Defaults to the current user.
  #
  # Stdout: absolute path to the effective XDG_CONFIG_HOME.
  local _user="${1:-}" _home
  if [[ -n "$_user" ]]; then
    _home="$(users__resolve_home "$_user")"
  else
    _home="${HOME:-}"
  fi

  # Tier 1: run bash as the target user to get the live XDG_CONFIG_HOME.
  if [[ -n "$_user" && "$_user" != "$(users__get_current --no-sudo 2> /dev/null)" ]] &&
    command -v "${_BASH_BIN:-bash}" > /dev/null 2>&1; then
    local _live_xdg=""
    # shellcheck disable=SC2016  # XDG_CONFIG_HOME is a variable for the target user's shell
    _live_xdg="$(users__run_as "$_user" -- "${_BASH_BIN:-bash}" -c 'printf "%s" "${XDG_CONFIG_HOME:-}"' \
      2> /dev/null || true)"
    if [[ -n "$_live_xdg" ]]; then
      echo "$_live_xdg"
      return 0
    fi
  fi

  # Tier 2: live environment — we ARE the target user.
  if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
    echo "$XDG_CONFIG_HOME"
    return 0
  fi

  # Tier 3: fallback.
  echo "${_home}/.config"
  return 0
}

shell__resolve_zsh_theme_file() {
  # @brief shell__resolve_zsh_theme_file [<username>] [--zdotdir <dir>] --source-marker <marker>
  #
  # Resolves the path of the per-user Zsh theme file (`zshtheme`) and ensures it
  # is wired into the user's `.zshrc` via a sourced block.
  #
  # Detects ZDOTDIR (via --zdotdir override or shell__detect_zdotdir) and returns
  # `$ZDOTDIR/zshtheme`. When the theme file does not already exist, a guarded
  # source block is injected into `$ZDOTDIR/.zshrc` (created if absent) using
  # --source-marker so that `.zshrc` sources the theme file on startup.
  #
  # Call this only when no user-provided path override is in effect; handle that
  # check at the call site before invoking this function.
  #
  # Args:
  #   <username>          (optional positional) Target username. Home resolved via
  #                       users__resolve_home. Defaults to current user.
  #   --zdotdir <dir>     ZDOTDIR override (skips live detection when given).
  #   --source-marker <m> Marker for the shell__write_block source-injection block.
  #
  # Stdout: absolute path to the theme file to write the feature block into.
  local _user="" _zdotdir_override="" _source_marker=""
  # Consume the optional leading positional username only when the first arg is
  # not a flag (does not start with '--').
  if [[ $# -gt 0 && "$1" != --* ]]; then
    _user="$1"
    shift
  fi
  while [[ $# -gt 0 ]]; do
    case $1 in
      --zdotdir)
        shift
        _zdotdir_override="$1"
        shift
        ;;
      --source-marker)
        shift
        _source_marker="$1"
        shift
        ;;
      *) shift ;;
    esac
  done

  local _home
  if [[ -n "$_user" ]]; then
    _home="$(users__resolve_home "$_user")"
  else
    _home="${HOME:-}"
  fi

  local _zdotdir
  if [[ -n "$_zdotdir_override" ]]; then
    _zdotdir="$_zdotdir_override"
  else
    _zdotdir="$(shell__detect_zdotdir --user "$_user" --home "$_home")"
  fi

  local _theme_file="${_zdotdir}/zshtheme"
  if [[ ! -f "$_theme_file" ]]; then
    # shellcheck disable=SC2016  # ZDOTDIR/$HOME are runtime shell variables, not bash variables
    shell__write_block \
      --file "${_zdotdir}/.zshrc" \
      --marker "$_source_marker" \
      --content '[ -f "${ZDOTDIR:-$HOME}/zshtheme" ] && source "${ZDOTDIR:-$HOME}/zshtheme"'
  fi

  echo "$_theme_file"
  return 0
}

shell__resolve_bash_theme_file() {
  # @brief shell__resolve_bash_theme_file [<username>] --source-marker <marker>
  #
  # Resolves the path of the per-user Bash theme file (`bashtheme`) and ensures it
  # is wired into the user's `.bashrc` via a sourced block.
  #
  # Detects XDG_CONFIG_HOME (via shell__detect_xdg_config_home) and returns
  # `$XDG_CONFIG_HOME/bash/bashtheme`. When the theme file does not already exist,
  # a guarded source block is injected into `$HOME/.bashrc` (created if absent)
  # using --source-marker.
  #
  # Call this only when no user-provided path override is in effect; handle that
  # check at the call site before invoking this function.
  #
  # Args:
  #   <username>          (optional positional) Target username. Home resolved via
  #                       users__resolve_home. Defaults to current user.
  #   --source-marker <m> Marker for the shell__write_block source-injection block.
  #
  # Stdout: absolute path to the theme file to write the feature block into.
  local _user="" _source_marker=""
  # Consume the optional leading positional username only when the first arg is
  # not a flag (does not start with '--').
  if [[ $# -gt 0 && "$1" != --* ]]; then
    _user="$1"
    shift
  fi
  while [[ $# -gt 0 ]]; do
    case $1 in
      --source-marker)
        shift
        _source_marker="$1"
        shift
        ;;
      *) shift ;;
    esac
  done

  local _home
  if [[ -n "$_user" ]]; then
    _home="$(users__resolve_home "$_user")"
  else
    _home="${HOME:-}"
  fi

  local _xdg_config_home
  _xdg_config_home="$(shell__detect_xdg_config_home "$_user")"

  local _theme_file="${_xdg_config_home}/bash/bashtheme"
  if [[ ! -f "$_theme_file" ]]; then
    # shellcheck disable=SC2016  # XDG_CONFIG_HOME/$HOME are runtime shell variables, not bash variables
    shell__write_block \
      --file "${_home}/.bashrc" \
      --marker "$_source_marker" \
      --content '[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/bash/bashtheme" ] && . "${XDG_CONFIG_HOME:-$HOME/.config}/bash/bashtheme"'
  fi

  echo "$_theme_file"
  return 0
}

shell__user_path_files() {
  # @brief shell__user_path_files [--home <dir>] [--zdotdir <dir>] — Print user startup file paths for a PATH export: bash login file, `.bashrc`, and `<zdotdir>/.zshenv`.
  #
  # Args:
  #   --home <dir>    User home directory (default: `$HOME`).
  #   --zdotdir <dir> ZDOTDIR override (default: auto-detected via `shell__detect_zdotdir`).
  #
  # Stdout: one path per line — login file, `<home>/.bashrc`, `<zdotdir>/.zshenv`.
  # shellcheck disable=SC2120  # called with no args at call site (SC2119 suppressed there)
  local _home="${HOME:-}" _zdotdir=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --home)
        shift
        _home="$1"
        shift
        ;;
      --zdotdir)
        shift
        _zdotdir="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  [[ -z "$_zdotdir" ]] && _zdotdir="$(shell__detect_zdotdir --home "$_home")"
  shell__user_login_file --home "$_home"
  echo "${_home}/.bashrc"
  echo "${_zdotdir}/.zshenv"
  return 0
}

shell__write_env_block() {
  # @brief shell__write_env_block --opt <value> --profile-d <name> --marker <id> --content <c> [--scope system|user] [--home <dir>] — Resolve shell startup file targets and write an idempotent env-export block.
  #
  # Centralises the "auto vs. explicit file list" routing that every export-path
  # handler needs: pick system-wide files when in system scope, user-scoped files
  # when in user scope, or write directly to the caller-supplied list.
  #
  # Args:
  #   --opt <value>          "auto" to target the standard system/user startup files, or
  #                          a newline-separated list of absolute paths to target directly
  #                          (pass via `$(printf '%s\n' "${ARRAY[@]}")`).
  #   --profile-d <n>        Base filename for an /etc/profile.d/ drop-in; only used when
  #                          --opt is "auto" and scope is system (optional).
  #   --marker <id>          Block identifier passed to shell__sync_block.
  #   --content <c>          Shell code to write inside the idempotency block.
  #   --scope system|user    Explicit scope override. When omitted, falls back to
  #                          users__is_root (system if root, user otherwise).
  #   --home <dir>           Home directory for user-scoped writes; passed to
  #                          shell__user_path_files (default: $HOME).
  #
  # When --opt is "auto":
  #   system scope (--scope system, or root when --scope omitted) → shell__system_path_files
  #   user scope   (--scope user,   or non-root when --scope omitted) → shell__user_path_files
  # When --opt is an explicit newline-separated list: writes to those paths only.
  local _opt="" _profile_d="" _marker="" _content="" _scope="" _home="${HOME:-}"
  while [[ $# -gt 0 ]]; do
    case $1 in
      --opt)
        shift
        _opt="$1"
        shift
        ;;
      --profile-d)
        shift
        _profile_d="$1"
        shift
        ;;
      --marker)
        shift
        _marker="$1"
        shift
        ;;
      --content)
        shift
        _content="$1"
        shift
        ;;
      --scope)
        shift
        _scope="$1"
        shift
        ;;
      --home)
        shift
        _home="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  local _target_files
  if [ "$_opt" = "auto" ]; then
    if [[ "$_scope" = "system" ]] || { [[ -z "$_scope" ]] && users__is_root; }; then
      logging__info "System-wide env block write (system scope)."
      _target_files="$(shell__system_path_files ${_profile_d:+--profile_d "$_profile_d"})"
    else
      logging__info "User-scoped env block write (user scope)."
      _target_files="$(shell__user_path_files --home "$_home")"
    fi
  else
    _target_files="$_opt"
  fi
  shell__sync_block --files "${_target_files}" --marker "${_marker}" --content "${_content}"
  return 0
}

shell__user_init_files() {
  # @brief shell__user_init_files [--home <dir>] [--zdotdir <dir>] — Print user startup file paths for a full initializer: bash login, `.bashrc`, `<zdotdir>/.zprofile`, `<zdotdir>/.zshrc`.
  #
  # Suitable for initializers that need to run in all contexts (e.g.
  # `eval "$(brew shellenv)"`).
  #
  # Args:
  #   --home <dir>    User home directory (default: `$HOME`).
  #   --zdotdir <dir> ZDOTDIR override (default: auto-detected via `shell__detect_zdotdir`).
  #
  # Stdout: one path per line — login file, `<home>/.bashrc`, `<zdotdir>/.zprofile`, `<zdotdir>/.zshrc`.
  local _home="${HOME:-}" _zdotdir=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --home)
        shift
        _home="$1"
        shift
        ;;
      --zdotdir)
        shift
        _zdotdir="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  [[ -z "$_zdotdir" ]] && _zdotdir="$(shell__detect_zdotdir --home "$_home")"
  shell__user_login_file --home "$_home"
  echo "${_home}/.bashrc"
  echo "${_zdotdir}/.zprofile"
  echo "${_zdotdir}/.zshrc"
  return 0
}

shell__user_rc_files() {
  # @brief shell__user_rc_files [--home <dir>] [--zdotdir <dir>] — Print user-scoped interactive RC file paths (`.bashrc`, `<zdotdir>/.zshrc`). Excludes login files.
  #
  # Intended for initializers that must only run in interactive shells
  # (e.g. conda init, shell prompt setup). Does NOT include login files —
  # use `shell__user_init_files` when those are needed too.
  #
  # Args:
  #   --home <dir>    User home directory (default: `$HOME`).
  #   --zdotdir <dir> ZDOTDIR override (default: auto-detected via `shell__detect_zdotdir`).
  #
  # Stdout: one path per line — `<home>/.bashrc`, `<zdotdir>/.zshrc`.
  local _home="${HOME:-}" _zdotdir=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --home)
        shift
        _home="$1"
        shift
        ;;
      --zdotdir)
        shift
        _zdotdir="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  [[ -z "$_zdotdir" ]] && _zdotdir="$(shell__detect_zdotdir --home "$_home")"
  echo "${_home}/.bashrc"
  echo "${_zdotdir}/.zshrc"
  return 0
}

shell__system_rc_files() {
  # @brief shell__system_rc_files — Print system-wide interactive RC file paths (global bashrc, `<zshdir>/zshrc`). Does not include login or PATH-export files.
  #
  # Intended for system-wide interactive-only setup when no per-user targets
  # are resolved (e.g. running as root with no resolved users).
  #
  # Stdout: global bashrc path, then `<zshdir>/zshrc`.
  shell__detect_bashrc
  echo "$(shell__detect_zshdir)/zshrc"
  return 0
}

shell__resolve_omz_theme() {
  # @brief shell__resolve_omz_theme --theme_slug <slug> --custom_dir <dir> — Given an `owner/repo` slug and `ZSH_CUSTOM` dir, print the `ZSH_THEME` value expected by oh-my-zsh.
  #
  # Falls back to the repo name alone if the `.zsh-theme` file cannot be found.
  #
  # Args:
  #   --theme_slug <slug>  GitHub slug in "owner/repo" format.
  #   --custom_dir <dir>   Path to $ZSH_CUSTOM (oh-my-zsh custom directory).
  #
  # Stdout: ZSH_THEME value (e.g. `repo-name/theme-stem` or just `repo-name`).
  local slug="" custom_dir=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --theme_slug)
        shift
        slug="$1"
        shift
        ;;
      --custom_dir)
        shift
        custom_dir="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  [ -z "$slug" ] && return 0

  local _repo_name
  _repo_name="$(basename "$slug")"
  local _theme_dir="${custom_dir}/themes/${_repo_name}"
  local _theme_file
  _theme_file="$(file__first_glob_match "$_theme_dir" '*.zsh-theme')"

  if [ -n "$_theme_file" ]; then
    local _stem
    _stem="$(basename "${_theme_file%.zsh-theme}")"
    echo "${_repo_name}/${_stem}"
  else
    echo "$_repo_name"
  fi
  return 0
}

shell__ensure_bashenv() {
  # @brief shell__ensure_bashenv — Detect or create the system-wide BASH_ENV file and register it in `/etc/environment`. Print the absolute path to the file.
  #
  # Callers are responsible for writing content to the returned path.
  #
  # Detection priority: `$BASH_ENV` (live env var) → `BASH_ENV=` in `/etc/environment` → create `<bashrc_dir>/bashenv`.
  #
  # Stdout: absolute path to the BASH_ENV file.

  # 1. Live environment variable
  if [ -n "${BASH_ENV:-}" ]; then
    logging__info "BASH_ENV already set to '${BASH_ENV}'; reusing."
    echo "$BASH_ENV"
    return 0
  fi
  # Allow tests (and callers) to override the path via _SHELL_ENV_FILE.
  local _env_file="${_SHELL_ENV_FILE:-/etc/environment}"
  # 2. Existing /etc/environment entry
  if [ -f "$_env_file" ]; then
    local _env_val
    _env_val="$(grep -m1 '^BASH_ENV=' "$_env_file" 2> /dev/null || true)"
    if [ -n "$_env_val" ]; then
      _env_val="${_env_val#BASH_ENV=}"
      _env_val="${_env_val#[\"\']}"
      _env_val="${_env_val%[\"\']}"
      logging__info "Found BASH_ENV='${_env_val}' in '${_env_file}'; reusing."
      echo "$_env_val"
      return 0
    fi
  fi
  # 3. Create new bashenv file and register in /etc/environment
  local _bashrc
  _bashrc="$(shell__detect_bashrc)"
  local _bashenv_dir
  _bashenv_dir="$(dirname "$_bashrc")"
  local _bashenv_path="${_bashenv_dir}/bashenv"
  logging__info "No BASH_ENV found; creating '${_bashenv_path}' and registering in '${_env_file}'."
  mkdir -p "$_bashenv_dir"
  [ -f "$_bashenv_path" ] || touch "$_bashenv_path"
  printf 'BASH_ENV="%s"\n' "$_bashenv_path" >> "$_env_file"
  echo "$_bashenv_path"
  return 0
}

shell__install_completion() {
  # @brief shell__install_completion [--system] [--home <dir>] <shell> <name> <content> — Write a shell completion script to the appropriate completion directory.
  #
  # Selects the install path based on scope (system vs user) and shell:
  #   bash    system: /etc/bash_completion.d/<name>
  #           user:   <home>/.local/share/bash-completion/completions/<name>
  #   zsh     system: <shell__detect_zshdir>/completions/_<name>
  #           user:   <home>/.zfunc/_<name>
  #   fish    system: /usr/share/fish/vendor_completions.d/<name>.fish
  #           user:   <home>/.config/fish/completions/<name>.fish
  #   nushell (no system path): <home>/.config/nushell/autoload/<name>.nu
  #   elvish  (no system path): named block in <home>/.config/elvish/rc.elv
  #
  # Args:
  #   --system      Use system-wide paths (root behaviour). When omitted, user paths are used.
  #                 Ignored for nushell and elvish (no standard system paths exist).
  #   --home <dir>  Home directory for user-scoped paths. Defaults to $HOME.
  #   <shell>       Target shell: bash, zsh, fish, nushell, or elvish.
  #   <name>        Completion file base name (tool name, e.g. "yq").
  #   <content>     Completion script text to write.
  #
  # Returns: 0 on success, 1 for unsupported shells or write errors.
  local _system=false _home="${HOME:-}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --system)
        _system=true
        shift
        ;;
      --home)
        shift
        _home="$1"
        shift
        ;;
      *) break ;;
    esac
  done
  local _shell="$1" _name="$2" _content="$3"
  local _dest
  case "${_shell}" in
    bash)
      if "${_system}"; then
        _dest="/etc/bash_completion.d/${_name}"
      else
        _dest="${_home}/.local/share/bash-completion/completions/${_name}"
      fi
      ;;
    zsh)
      if "${_system}"; then
        _dest="$(shell__detect_zshdir)/completions/_${_name}"
      else
        _dest="${_home}/.zfunc/_${_name}"
      fi
      ;;
    fish)
      if "${_system}"; then
        local _fish_sysdir
        _fish_sysdir="$(shell__detect_fish_sysdir)"
        if [[ -z "${_fish_sysdir}" ]]; then
          logging__skip "No system fish completion directory available on this platform; skipping fish completions."
          return 0
        fi
        _dest="${_fish_sysdir}/${_name}.fish"
      else
        _dest="${_home}/.config/fish/completions/${_name}.fish"
      fi
      ;;
    nushell)
      _dest="${_home}/.config/nushell/autoload/${_name}.nu"
      ;;
    elvish)
      local _rc="${_home}/.config/elvish/rc.elv"
      file__mkdir "$(dirname "${_rc}")"
      shell__write_block --file "${_rc}" --marker "${_name} completion" --content "${_content}"
      logging__success "Shell completion for '${_shell}' written to '${_rc}'."
      return 0
      ;;
    *)
      logging__error "unsupported shell '${_shell}' (expected: bash, zsh, fish, nushell, elvish)."
      return 1
      ;;
  esac
  file__mkdir "$(dirname "${_dest}")"
  printf '%s\n' "${_content}" | file__tee "${_dest}"
  logging__success "Shell completion for '${_shell}' written to '${_dest}'."
}

shell__create_symlink() {
  # @brief shell__create_symlink --src <s> --system-target <t> --user-target <t> — Create a symlink, choosing system-wide or user-scoped location based on write access.
  #
  # Places the symlink at <system-target> if the system target's parent directory
  # exists and is writable by the caller; otherwise at <user-target>. If the
  # chosen target equals src, no symlink is needed and the function returns
  # without error.
  #
  # Errors if the chosen target path is a real file or directory (not a symlink).
  # Creates parent directories of the target as needed.
  #
  # Args:
  #   --src <s>            The path the symlink will point to.
  #   --system-target <t>  Symlink path for system-wide installations.
  #   --user-target <t>    Symlink path for user-scoped installations.
  #
  # Returns: 0 on success, 1 if the target is a real file or directory.
  local _src="" _system_target="" _user_target=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --src)
        shift
        _src="$1"
        shift
        ;;
      --system-target)
        shift
        _system_target="$1"
        shift
        ;;
      --user-target)
        shift
        _user_target="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  # Choose symlink target based on write access to the target directory.
  # Walk up to the nearest existing ancestor of each target's parent to check
  # if the caller can write there (and thus create the full path via mkdir -p).
  # Prefer the system target; fall back to the user target; error if neither is
  # writable so the caller gets a clear diagnostic instead of a set -e death.
  # Exception: when --src lives under the user's home directory the installation
  # is inherently user-scoped, so skip the system target entirely and go
  # straight to the user target (even if the system dir happens to be writable).
  _nearest_writable_ancestor() {
    local _d
    _d="$(dirname "$1")"
    while [ ! -d "$_d" ]; do _d="$(dirname "$_d")"; done
    [ -w "$_d" ]
  }
  local _src_is_user_space=false
  if [[ -n "${HOME:-}" ]] && [[ "$_src" == "${HOME}/"* ]]; then
    _src_is_user_space=true
  fi
  local _target
  if ! $_src_is_user_space && _nearest_writable_ancestor "$_system_target"; then
    _target="$_system_target"
  elif _nearest_writable_ancestor "$_user_target"; then
    _target="$_user_target"
  else
    logging__error "Cannot create symlink: no writable location available (tried '${_system_target}' and '${_user_target}')."
    return 1
  fi
  unset -f _nearest_writable_ancestor
  # If src and target are the same path, no symlink is needed.
  if [[ "$_src" == "$_target" ]]; then
    logging__info "src and target are identical ('${_target}'); no symlink needed."
    return 0
  fi
  # Guard: refuse to clobber a real file or directory.
  if [[ -e "$_target" && ! -L "$_target" ]]; then
    logging__error "'${_target}' exists as a real file or directory; cannot create symlink."
    return 1
  fi
  # Remove stale symlink before recreating.
  [[ -L "$_target" ]] && rm -f "$_target"
  mkdir -p "$(dirname "$_target")"
  ln -s "${_src}" "$_target"
  logging__success "Created symlink '${_target}' -> '${_src}'."
  return 0
}

shell__sync_config() {
  # @brief shell__sync_config [--scope system|user] [--home <dir>] --marker <id> --profile-d <name> [--<shell>-content <text> [--<shell>-everywhere]]... [<shell>...] — Write or remove idempotent marker blocks across shell startup files.
  #
  # Write mode: pass --<shell>-content for each shell to write. --<shell>-everywhere
  # additionally writes to non-interactive startup files (profile.d + BASH_ENV for bash,
  # zshenv for zsh, /etc/csh.login for tcsh). Without it, only the RC file is written.
  #
  # Remove mode: list shells as positional args (without --<shell>-content). The marker
  # block is removed from ALL possible file locations for each shell — safe because
  # shell__sync_block is a no-op when the marker is absent.
  #
  # Supported shells: bash, zsh, fish, tcsh, elvish. fish and elvish have no
  # everywhere/interactive distinction; --fish-everywhere and --elvish-everywhere are ignored.
  #
  # Args:
  #   --marker <id>           Idempotency marker passed to shell__sync_block.
  #   --profile-d <name>      Basename for /etc/profile.d/ (bash system everywhere) and
  #                           /etc/fish/conf.d/ (fish system, .sh suffix replaced with .fish).
  #   --scope system|user     Scope override (default: system when root, user otherwise).
  #   --home <dir>            Home directory for user-scoped writes (default: $HOME).
  #   --bash-content <text>   Content to write to bash startup files.
  #   --bash-everywhere       Write to non-interactive bash files (profile.d, BASH_ENV).
  #   --zsh-content <text>    Content to write to zsh startup files.
  #   --zsh-everywhere        Write to non-interactive zsh files (zshenv).
  #   --fish-content <text>   Content to write to fish startup files.
  #   --tcsh-content <text>   Content to write to tcsh startup files.
  #   --tcsh-everywhere       Write to /etc/csh.login in addition to /etc/csh.cshrc.
  #   --elvish-content <text> Content to write to elvish startup files.
  #   [<shell>...]            Positional: shells to remove (all locations).
  local _sc_marker="" _sc_profile_d="" _sc_scope="" _sc_home="${HOME:-}"
  local _sc_bash_content="" _sc_bash_everywhere=false
  local _sc_zsh_content="" _sc_zsh_everywhere=false
  local _sc_fish_content=""
  local _sc_tcsh_content="" _sc_tcsh_everywhere=false
  local _sc_elvish_content=""
  local -a _sc_remove=()
  while [[ $# -gt 0 ]]; do
    case $1 in
      --marker)
        shift
        _sc_marker="$1"
        shift
        ;;
      --profile-d)
        shift
        _sc_profile_d="$1"
        shift
        ;;
      --scope)
        shift
        _sc_scope="$1"
        shift
        ;;
      --home)
        shift
        _sc_home="$1"
        shift
        ;;
      --bash-content)
        shift
        _sc_bash_content="$1"
        shift
        ;;
      --bash-everywhere)
        _sc_bash_everywhere=true
        shift
        ;;
      --zsh-content)
        shift
        _sc_zsh_content="$1"
        shift
        ;;
      --zsh-everywhere)
        _sc_zsh_everywhere=true
        shift
        ;;
      --fish-content)
        shift
        _sc_fish_content="$1"
        shift
        ;;
      --tcsh-content)
        shift
        _sc_tcsh_content="$1"
        shift
        ;;
      --tcsh-everywhere)
        _sc_tcsh_everywhere=true
        shift
        ;;
      --elvish-content)
        shift
        _sc_elvish_content="$1"
        shift
        ;;
      --)
        shift
        break
        ;;
      --*)
        shift
        [ $# -gt 0 ] && shift || true
        ;;
      *)
        _sc_remove+=("$1")
        shift
        ;;
    esac
  done
  _sc_remove+=("$@")
  local _sc_is_system=false
  if [[ "$_sc_scope" = "system" ]] || { [[ -z "$_sc_scope" ]] && users__is_root; }; then
    _sc_is_system=true
  fi

  # ── Write mode ────────────────────────────────────────────────────────────────
  local _sc_shell _sc_content _sc_everywhere _sc_files
  for _sc_shell in bash zsh fish tcsh elvish; do
    case "$_sc_shell" in
      bash)
        _sc_content="$_sc_bash_content"
        _sc_everywhere="$_sc_bash_everywhere"
        ;;
      zsh)
        _sc_content="$_sc_zsh_content"
        _sc_everywhere="$_sc_zsh_everywhere"
        ;;
      fish)
        _sc_content="$_sc_fish_content"
        _sc_everywhere=false
        ;;
      tcsh)
        _sc_content="$_sc_tcsh_content"
        _sc_everywhere="$_sc_tcsh_everywhere"
        ;;
      elvish)
        _sc_content="$_sc_elvish_content"
        _sc_everywhere=false
        ;;
      *) continue ;;
    esac
    [[ -z "$_sc_content" ]] && continue
    _sc_files=""
    if "$_sc_is_system"; then
      if "$_sc_everywhere"; then
        case "$_sc_shell" in
          bash)
            local _sc_benv
            _sc_benv="$(shell__ensure_bashenv)"
            shell__sync_block \
              --files "/etc/profile.d/${_sc_profile_d}"$'\n'"${_sc_benv}" \
              --marker "$_sc_marker" --content "$_sc_content"
            _sc_files="$(shell__detect_bashrc)"
            ;;
          zsh) _sc_files="$(shell__detect_zshdir)/zshenv" ;;
          fish) _sc_files="/etc/fish/conf.d/${_sc_profile_d%.sh}.fish" ;;
          tcsh)
            shell__sync_block --files "/etc/csh.login" \
              --marker "$_sc_marker" --content "$_sc_content"
            _sc_files="/etc/csh.cshrc"
            ;;
        esac
      else
        case "$_sc_shell" in
          bash) _sc_files="$(shell__detect_bashrc)" ;;
          zsh) _sc_files="$(shell__detect_zshdir)/zshrc" ;;
          fish) _sc_files="/etc/fish/conf.d/${_sc_profile_d%.sh}.fish" ;;
          tcsh) _sc_files="/etc/csh.cshrc" ;;
        esac
      fi
      if [[ "$_sc_shell" = "elvish" ]]; then
        local -a _sc_elv_users=()
        mapfile -t _sc_elv_users < <(users__resolve_list)
        local _sc_eu
        for _sc_eu in "${_sc_elv_users[@]+"${_sc_elv_users[@]}"}"; do
          local _sc_euhome
          _sc_euhome="$(users__resolve_home "$_sc_eu" 2> /dev/null)" || continue
          [[ -z "$_sc_euhome" ]] && continue
          local _sc_eurc="${_sc_euhome}/.config/elvish/rc.elv"
          file__mkdir "$(dirname "$_sc_eurc")"
          [[ ! -f "$_sc_eurc" ]] && printf '' | file__tee "$_sc_eurc"
          shell__sync_block --files "$_sc_eurc" --marker "$_sc_marker" --content "$_sc_content"
        done
        continue
      fi
    else
      if "$_sc_everywhere"; then
        case "$_sc_shell" in
          bash)
            shell__sync_block \
              --files "$(shell__user_login_file --home "$_sc_home")" \
              --marker "$_sc_marker" --content "$_sc_content"
            _sc_files="${_sc_home}/.bashrc"
            ;;
          zsh) _sc_files="$(shell__detect_zdotdir --home "$_sc_home")/.zshenv" ;;
          fish) _sc_files="${_sc_home}/.config/fish/config.fish" ;;
          tcsh)
            local _sc_tcsh_rc="${_sc_home}/.cshrc"
            [[ -f "${_sc_home}/.tcshrc" ]] && _sc_tcsh_rc="${_sc_home}/.tcshrc"
            shell__sync_block --files "${_sc_home}/.login" \
              --marker "$_sc_marker" --content "$_sc_content"
            _sc_files="$_sc_tcsh_rc"
            ;;
          elvish) _sc_files="${_sc_home}/.config/elvish/rc.elv" ;;
        esac
      else
        case "$_sc_shell" in
          bash) _sc_files="${_sc_home}/.bashrc" ;;
          zsh) _sc_files="$(shell__detect_zdotdir --home "$_sc_home")/.zshrc" ;;
          fish) _sc_files="${_sc_home}/.config/fish/config.fish" ;;
          tcsh)
            local _sc_tcsh_rc2="${_sc_home}/.cshrc"
            [[ -f "${_sc_home}/.tcshrc" ]] && _sc_tcsh_rc2="${_sc_home}/.tcshrc"
            _sc_files="$_sc_tcsh_rc2"
            ;;
          elvish) _sc_files="${_sc_home}/.config/elvish/rc.elv" ;;
        esac
      fi
    fi
    [[ -n "$_sc_files" ]] || continue
    file__mkdir "$(dirname "$_sc_files")"
    [[ ! -f "$_sc_files" ]] && printf '' | file__tee "$_sc_files"
    shell__sync_block --files "$_sc_files" --marker "$_sc_marker" --content "$_sc_content"
  done

  # ── Remove mode ───────────────────────────────────────────────────────────────
  local -a _sc_rm_files=()
  local _sc_rf
  for _sc_shell in "${_sc_remove[@]}"; do
    [[ -z "$_sc_shell" ]] && continue
    _sc_rm_files=()
    if "$_sc_is_system"; then
      case "$_sc_shell" in
        bash)
          _sc_rm_files+=("/etc/profile.d/${_sc_profile_d}")
          local _sc_benv2
          _sc_benv2="$(shell__ensure_bashenv 2> /dev/null || true)"
          [ -n "$_sc_benv2" ] && _sc_rm_files+=("$_sc_benv2")
          _sc_rm_files+=("$(shell__detect_bashrc)")
          ;;
        zsh)
          _sc_rm_files+=("$(shell__detect_zshdir)/zshenv" "$(shell__detect_zshdir)/zshrc")
          ;;
        fish) _sc_rm_files+=("/etc/fish/conf.d/${_sc_profile_d%.sh}.fish") ;;
        tcsh) _sc_rm_files+=("/etc/csh.login" "/etc/csh.cshrc") ;;
        elvish)
          local -a _sc_elv_users2=()
          mapfile -t _sc_elv_users2 < <(users__resolve_list)
          local _sc_eu2
          for _sc_eu2 in "${_sc_elv_users2[@]+"${_sc_elv_users2[@]}"}"; do
            local _sc_euhome2
            _sc_euhome2="$(users__resolve_home "$_sc_eu2" 2> /dev/null)" || continue
            [[ -z "$_sc_euhome2" ]] && continue
            shell__sync_block \
              --files "${_sc_euhome2}/.config/elvish/rc.elv" --marker "$_sc_marker"
          done
          continue
          ;;
        *) continue ;;
      esac
    else
      case "$_sc_shell" in
        bash)
          _sc_rm_files+=("$(shell__user_login_file --home "$_sc_home")")
          _sc_rm_files+=("${_sc_home}/.bashrc")
          ;;
        zsh)
          local _sc_zdotdir2
          _sc_zdotdir2="$(shell__detect_zdotdir --home "$_sc_home")"
          _sc_rm_files+=("${_sc_zdotdir2}/.zshenv" "${_sc_zdotdir2}/.zshrc")
          ;;
        fish) _sc_rm_files+=("${_sc_home}/.config/fish/config.fish") ;;
        tcsh)
          _sc_rm_files+=("${_sc_home}/.login" "${_sc_home}/.cshrc" "${_sc_home}/.tcshrc")
          ;;
        elvish) _sc_rm_files+=("${_sc_home}/.config/elvish/rc.elv") ;;
        *) continue ;;
      esac
    fi
    for _sc_rf in "${_sc_rm_files[@]}"; do
      [ -n "$_sc_rf" ] && shell__sync_block --files "$_sc_rf" --marker "$_sc_marker"
    done
  done
  return 0
}

shell__prefix_link_bins() {
  # @brief shell__prefix_link_bins — Create symlinks for a set of prefix bins into target directories.
  #
  # Args:
  #   --bin-dir <dir>   Source directory containing the binaries.
  #   --bins <names>    Space-separated binary names.
  #   --target <dir>    Target directory (may be repeated).
  local _bin_dir="" _bins=""
  local -a _targets=()
  while [[ $# -gt 0 ]]; do
    case $1 in
      --bin-dir)
        shift
        _bin_dir="$1"
        shift
        ;;
      --bins)
        shift
        _bins="$1"
        shift
        ;;
      --target)
        shift
        _targets+=("$1")
        shift
        ;;
      *) shift ;;
    esac
  done
  local _bin_name _target
  for _bin_name in ${_bins}; do
    [[ -f "${_bin_dir}/${_bin_name}" ]] || continue
    for _target in "${_targets[@]}"; do
      shell__create_symlink \
        --src "${_bin_dir}/${_bin_name}" \
        --system-target "${_target}/${_bin_name}" \
        --user-target "${_target}/${_bin_name}"
    done
  done
}

shell__prefix_unlink_bins() {
  # @brief shell__prefix_unlink_bins — Remove symlinks for a set of prefix bins from target directories.
  #
  # Args:
  #   --bin-dir <dir>   Source directory (only used as context; not accessed).
  #   --bins <names>    Space-separated binary names.
  #   --target <dir>    Target directory to remove symlinks from (may be repeated).
  local _bins=""
  local -a _targets=()
  while [[ $# -gt 0 ]]; do
    case $1 in
      --bin-dir)
        shift
        shift
        ;;
      --bins)
        shift
        _bins="$1"
        shift
        ;;
      --target)
        shift
        _targets+=("$1")
        shift
        ;;
      *) shift ;;
    esac
  done
  local _bin_name _target
  for _bin_name in ${_bins}; do
    for _target in "${_targets[@]}"; do
      local _link="${_target}/${_bin_name}"
      [ -L "${_link}" ] || continue
      file__rm "${_link}"
      logging__remove "Removed symlink '${_link}'."
    done
  done
}

shell__run_prefix_undiscovery() {
  # @brief shell__run_prefix_undiscovery — Remove prefix-discovery artifacts: downstream symlinks and PATH export blocks.
  #
  # Accepts the same arguments as shell__run_prefix_discovery. Always attempts removal of
  # both symlinks (from resolved target dirs) and PATH export block (from appropriate shell
  # files), regardless of the discovery mode. Each removal operation is a no-op when the
  # artifact does not exist (shell__sync_block skips missing markers; shell__prefix_unlink_bins
  # uses a [ -L ] guard).
  #
  # Args: same as shell__run_prefix_discovery (--cmd-var and --discovery are accepted but ignored).
  local _disc_prefix="" _bin_dir="bin"
  local _bins="" _symlinks_ref="" _exports_ref="" _marker="" _profile_d=""
  local _symlink_root="/usr/local/bin" _symlink_nonroot="${HOME}/.local/bin"
  while [[ $# -gt 0 ]]; do
    case $1 in
      --prefix)
        shift
        _disc_prefix="$1"
        shift
        ;;
      --bin-dir)
        shift
        _bin_dir="$1"
        shift
        ;;
      --bins)
        shift
        _bins="$1"
        shift
        ;;
      --symlinks-ref)
        shift
        _symlinks_ref="$1"
        shift
        ;;
      --exports-ref)
        shift
        _exports_ref="$1"
        shift
        ;;
      --marker)
        shift
        _marker="$1"
        shift
        ;;
      --profile-d)
        shift
        _profile_d="$1"
        shift
        ;;
      --symlink-root)
        shift
        _symlink_root="$1"
        shift
        ;;
      --symlink-nonroot)
        shift
        _symlink_nonroot="$1"
        shift
        ;;
      *)
        shift
        [ $# -gt 0 ] && shift || true
        ;;
    esac
  done
  local _pfx_bin_dir="${_disc_prefix}/${_bin_dir}"

  # Determine scope from prefix path.
  local _disc_scope _disc_home
  if ! users__is_user_path "${_disc_prefix}"; then
    _disc_scope="system"
    _disc_home=""
  else
    _disc_scope="user"
    _disc_home="$(users__home_of_path_owner "${_disc_prefix}")"
  fi

  # Resolve symlink targets.
  local -a _sl_targets=()
  if [[ -n "$_symlinks_ref" ]]; then
    local -n _rpud_sl="${_symlinks_ref}"
    [[ "${#_rpud_sl[@]}" -gt 0 ]] && _sl_targets=("${_rpud_sl[@]}")
  fi
  if [[ "${#_sl_targets[@]}" -eq 0 ]]; then
    if [[ "$_disc_scope" = "system" ]]; then
      _sl_targets=("${_symlink_root}")
    else
      _sl_targets=("${_symlink_nonroot}")
    fi
  fi

  # Remove downstream symlinks from all resolved targets.
  local _sl_dir
  local -a _sl_args=()
  for _sl_dir in "${_sl_targets[@]}"; do _sl_args+=(--target "${_sl_dir}"); done
  shell__prefix_unlink_bins --bin-dir "${_pfx_bin_dir}" --bins "${_bins}" "${_sl_args[@]}"

  # Remove PATH export block from all appropriate shell files.
  [[ -n "${_marker}" ]] || return 0
  local -a _disc_shells=()
  if [[ -n "$_exports_ref" ]]; then
    local -n _rpud_ex="${_exports_ref}"
    [[ "${#_rpud_ex[@]}" -gt 0 ]] && _disc_shells=("${_rpud_ex[@]}")
  fi
  [[ "${#_disc_shells[@]}" -eq 0 ]] && mapfile -t _disc_shells < <(shell__detect_installed_shells)
  shell__sync_config \
    --marker "${_marker}" \
    --profile-d "${_profile_d}" \
    --scope "${_disc_scope}" \
    ${_disc_home:+--home "${_disc_home}"} \
    "${_disc_shells[@]}"
}

shell__prefix_export_path() {
  # @brief shell__prefix_export_path — Write a PATH-prepend export block for a prefix bin directory.
  #
  # For each configured shell, writes a PATH-prepend snippet to the appropriate
  # "everywhere" startup files via shell__sync_config. Custom per-shell snippets
  # (e.g. `eval "$(brew shellenv)"`) override the generic PATH export for that shell.
  #
  # Args:
  #   --bin-dir <dir>         Directory to prepend to PATH.
  #   --exports-ref <var>     Name of array variable with shell names to target (optional).
  #                           Empty array = auto-detect via shell__detect_installed_shells.
  #   --marker <id>           Idempotency marker.
  #   --profile-d <name>      /etc/profile.d basename for the system-wide drop-in.
  #   --scope system|user     Scope override (optional).
  #   --home <dir>            Home directory for user-scoped writes (default: $HOME).
  #   --bash-snippet <text>   Custom bash snippet (overrides generic PATH export).
  #   --zsh-snippet <text>    Custom zsh snippet.
  #   --fish-snippet <text>   Custom fish snippet.
  #   --tcsh-snippet <text>   Custom tcsh snippet.
  #   --elvish-snippet <text> Custom elvish snippet.
  local _bin_dir="" _exports_ref="" _marker="" _profile_d="" _scope="" _home="${HOME:-}"
  local _bash_snippet="" _zsh_snippet="" _fish_snippet="" _tcsh_snippet="" _elvish_snippet=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --bin-dir)
        shift
        _bin_dir="$1"
        shift
        ;;
      --exports-ref)
        shift
        _exports_ref="$1"
        shift
        ;;
      --marker)
        shift
        _marker="$1"
        shift
        ;;
      --profile-d)
        shift
        _profile_d="$1"
        shift
        ;;
      --scope)
        shift
        _scope="$1"
        shift
        ;;
      --home)
        shift
        _home="$1"
        shift
        ;;
      --bash-snippet)
        shift
        _bash_snippet="$1"
        shift
        ;;
      --zsh-snippet)
        shift
        _zsh_snippet="$1"
        shift
        ;;
      --fish-snippet)
        shift
        _fish_snippet="$1"
        shift
        ;;
      --tcsh-snippet)
        shift
        _tcsh_snippet="$1"
        shift
        ;;
      --elvish-snippet)
        shift
        _elvish_snippet="$1"
        shift
        ;;
      *) shift ;;
    esac
  done

  # Resolve target shells.
  local -a _pep_shells=()
  if [[ -n "$_exports_ref" ]]; then
    local -n _pep_ex="${_exports_ref}"
    [[ "${#_pep_ex[@]}" -gt 0 ]] && _pep_shells=("${_pep_ex[@]}")
  fi
  [[ "${#_pep_shells[@]}" -eq 0 ]] && mapfile -t _pep_shells < <(shell__detect_installed_shells)

  # Generic bash/zsh PATH prepend content.
  local _pep_posix_content
  # shellcheck disable=SC2162
  IFS= read -r -d '' _pep_posix_content << 'EOBLOCK' || true
_shell__df_prepend_path() {
  local _d="$1" _p="${PATH:-}" _r="" _e
  while [ -n "$_p" ]; do
    _e="${_p%%:*}"; [ "$_p" = "${_p#*:}" ] && _p="" || _p="${_p#*:}"
    [ "$_e" = "$_d" ] || _r="${_r:+${_r}:}${_e}"
  done
  export PATH="${_d}${_r:+:${_r}}"
}
EOBLOCK
  _pep_posix_content="${_pep_posix_content}_shell__df_prepend_path \"${_bin_dir}\"
unset -f _shell__df_prepend_path"

  # Build shell__sync_config args.
  local -a _sc_args=()
  local _pep_sh
  for _pep_sh in "${_pep_shells[@]}"; do
    local _pep_content=""
    case "$_pep_sh" in
      bash) [[ -n "$_bash_snippet" ]] && _pep_content="$_bash_snippet" || _pep_content="$_pep_posix_content" ;;
      zsh) [[ -n "$_zsh_snippet" ]] && _pep_content="$_zsh_snippet" || _pep_content="$_pep_posix_content" ;;
      fish) [[ -n "$_fish_snippet" ]] && _pep_content="$_fish_snippet" || _pep_content="fish_add_path \"${_bin_dir}\"" ;;
      tcsh) [[ -n "$_tcsh_snippet" ]] && _pep_content="$_tcsh_snippet" || _pep_content="setenv PATH \"${_bin_dir}:\${PATH}\"" ;;
      elvish) [[ -n "$_elvish_snippet" ]] && _pep_content="$_elvish_snippet" || _pep_content="set paths = [${_bin_dir} \$@paths]" ;;
      *) continue ;;
    esac
    [[ -n "$_pep_content" ]] && _sc_args+=("--${_pep_sh}-content" "$_pep_content" "--${_pep_sh}-everywhere")
  done

  if [[ "${#_sc_args[@]}" -gt 0 ]]; then
    shell__sync_config \
      --marker "${_marker}" \
      --profile-d "${_profile_d}" \
      ${_scope:+--scope "${_scope}"} \
      --home "${_home}" \
      "${_sc_args[@]}"
  fi
}

shell__run_prefix_discovery() {
  # @brief shell__run_prefix_discovery — Decide how to make prefix bins discoverable and record the expected verification command.
  #
  # Resolves symlink targets, applies the discovery decision (none|symlink|shell|all|auto),
  # delegates execution to shell__prefix_link_bins / shell__prefix_export_path, then stores
  # the expected verification command in the variable named by --cmd-var via printf -v.
  #
  # Args:
  #   --prefix <path>       Installation prefix.
  #   --bin-dir <subdir>    Subdirectory for binaries (default: bin).
  #   --discovery <value>   none|symlink|shell|all|auto (default: auto).
  #   --runtime-path <val>  Colon-separated PATH for the "already on PATH" and cmd checks.
  #   --bins <names>        Space-separated binary names to symlink.
  #   --symlinks-ref <var>  Name of array variable with explicit symlink target dirs.
  #   --exports-ref <var>   Name of array variable with explicit export file paths.
  #   --marker <id>         Idempotency marker for the PATH export block.
  #   --profile-d <name>    /etc/profile.d basename for the PATH export drop-in (root only).
  #   --bin <name>          Primary binary name for --cmd-var output.
  #   --cmd-var <varname>   Name of variable to set with the expected command string.
  #   --symlink-root <dir>  Fallback symlink target for root installs (default: /usr/local/bin).
  #   --symlink-nonroot <dir> Fallback symlink target for non-root installs (default: ${HOME}/.local/bin).
  #   --no-symlinks         Disable symlink creation.
  #   --no-exports          Disable PATH export writing.
  #   --bash-snippet <text>   Custom bash PATH discovery snippet (passed to shell__prefix_export_path).
  #   --zsh-snippet <text>    Custom zsh PATH discovery snippet.
  #   --fish-snippet <text>   Custom fish PATH discovery snippet.
  #   --tcsh-snippet <text>   Custom tcsh PATH discovery snippet.
  #   --elvish-snippet <text> Custom elvish PATH discovery snippet.
  local _disc_prefix="" _bin_dir="bin" _discovery="auto" _runtime_path="${PATH:-}"
  local _bins="" _symlinks_ref="" _exports_ref="" _marker="" _profile_d=""
  local _bin="" _cmd_var="" _no_symlinks=false _no_exports=false
  local _symlink_root="/usr/local/bin" _symlink_nonroot="${HOME}/.local/bin"
  local _bash_snippet="" _zsh_snippet="" _fish_snippet="" _tcsh_snippet="" _elvish_snippet=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --prefix)
        shift
        _disc_prefix="$1"
        shift
        ;;
      --bin-dir)
        shift
        _bin_dir="$1"
        shift
        ;;
      --discovery)
        shift
        _discovery="${1:-auto}"
        shift
        ;;
      --runtime-path)
        shift
        _runtime_path="$1"
        shift
        ;;
      --bins)
        shift
        _bins="$1"
        shift
        ;;
      --symlinks-ref)
        shift
        _symlinks_ref="$1"
        shift
        ;;
      --exports-ref)
        shift
        _exports_ref="$1"
        shift
        ;;
      --marker)
        shift
        _marker="$1"
        shift
        ;;
      --profile-d)
        shift
        _profile_d="$1"
        shift
        ;;
      --bin)
        shift
        _bin="$1"
        shift
        ;;
      --cmd-var)
        shift
        _cmd_var="$1"
        shift
        ;;
      --symlink-root)
        shift
        _symlink_root="$1"
        shift
        ;;
      --symlink-nonroot)
        shift
        _symlink_nonroot="$1"
        shift
        ;;
      --no-symlinks)
        _no_symlinks=true
        shift
        ;;
      --no-exports)
        _no_exports=true
        shift
        ;;
      --bash-snippet)
        shift
        _bash_snippet="$1"
        shift
        ;;
      --zsh-snippet)
        shift
        _zsh_snippet="$1"
        shift
        ;;
      --fish-snippet)
        shift
        _fish_snippet="$1"
        shift
        ;;
      --tcsh-snippet)
        shift
        _tcsh_snippet="$1"
        shift
        ;;
      --elvish-snippet)
        shift
        _elvish_snippet="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  local _pfx_bin_dir="${_disc_prefix}/${_bin_dir}"

  # Determine system vs. user scope from the prefix path rather than the caller's UID.
  local _disc_scope _disc_home
  if ! users__is_user_path "${_disc_prefix}"; then
    _disc_scope="system"
    _disc_home=""
  else
    _disc_scope="user"
    _disc_home="$(users__home_of_path_owner "${_disc_prefix}")"
  fi

  # Resolve symlink targets.
  local -a _sl_targets=()
  if [[ "$_no_symlinks" != true ]]; then
    if [[ -n "$_symlinks_ref" ]]; then
      local -n _rpd_sl="${_symlinks_ref}"
      [[ "${#_rpd_sl[@]}" -gt 0 ]] && _sl_targets=("${_rpd_sl[@]}")
    fi
    if [[ "${#_sl_targets[@]}" -eq 0 ]]; then
      if [[ "$_disc_scope" = "system" ]]; then
        _sl_targets=("${_symlink_root}")
      else
        _sl_targets=("${_symlink_nonroot}")
      fi
    fi
  fi

  # Discovery decision.
  local _call_symlinks=false _call_exports=false
  case "${_discovery}" in
    none) ;;
    symlink) [[ "$_no_symlinks" != true ]] && _call_symlinks=true ;;
    shell) [[ "$_no_exports" != true ]] && _call_exports=true ;;
    all)
      [[ "$_no_symlinks" != true ]] && _call_symlinks=true
      [[ "$_no_exports" != true ]] && _call_exports=true
      ;;
    auto)
      case ":${_runtime_path}:" in
        *":${_pfx_bin_dir}:"*) ;;
        *)
          if [[ "$_no_symlinks" != true ]]; then
            local _has_real=false _t
            for _t in "${_sl_targets[@]}"; do
              [[ "$_t" != "$_pfx_bin_dir" ]] && {
                _has_real=true
                break
              }
            done
            if "${_has_real}"; then
              _call_symlinks=true
            elif [[ "$_no_exports" != true ]]; then
              # Symlinks not viable (all targets equal prefix/bin) — fall back to PATH export.
              _call_exports=true
            fi
          elif [[ "$_no_exports" != true ]]; then
            # Symlinks suppressed via --no-symlinks — fall back to PATH export.
            _call_exports=true
          fi
          ;;
      esac
      ;;
  esac

  # Execute.
  if "${_call_symlinks}"; then
    local _sl_dir _sl_args=()
    for _sl_dir in "${_sl_targets[@]}"; do _sl_args+=(--target "${_sl_dir}"); done
    shell__prefix_link_bins --bin-dir "${_pfx_bin_dir}" --bins "${_bins}" "${_sl_args[@]}"
  fi
  if "${_call_exports}"; then
    shell__prefix_export_path \
      --bin-dir "${_pfx_bin_dir}" \
      --exports-ref "${_exports_ref}" \
      --marker "${_marker}" \
      --profile-d "${_profile_d}" \
      --scope "${_disc_scope}" \
      ${_disc_home:+--home "${_disc_home}"} \
      ${_bash_snippet:+--bash-snippet "${_bash_snippet}"} \
      ${_zsh_snippet:+--zsh-snippet "${_zsh_snippet}"} \
      ${_fish_snippet:+--fish-snippet "${_fish_snippet}"} \
      ${_tcsh_snippet:+--tcsh-snippet "${_tcsh_snippet}"} \
      ${_elvish_snippet:+--elvish-snippet "${_elvish_snippet}"}
  fi

  # Set expected verification command.
  if [[ -n "$_cmd_var" && -n "$_bin" ]]; then
    local _expected_cmd
    case ":${_runtime_path}:" in
      *":${_pfx_bin_dir}:"*)
        _expected_cmd="${_bin}"
        ;;
      *)
        if "${_call_symlinks}" && [[ "${#_sl_targets[@]}" -gt 0 ]]; then
          local _sl_first="${_sl_targets[0]}"
          case ":${_runtime_path}:" in
            *":${_sl_first}:"*) _expected_cmd="${_bin}" ;;
            *) _expected_cmd="${_sl_first}/${_bin}" ;;
          esac
        elif "${_call_exports}"; then
          if [[ "$_disc_scope" = "system" ]]; then
            _expected_cmd="${_bin}"
          else
            _expected_cmd="${_pfx_bin_dir}/${_bin}"
          fi
        else
          _expected_cmd="${_pfx_bin_dir}/${_bin}"
        fi
        ;;
    esac
    printf -v "${_cmd_var}" '%s' "${_expected_cmd}"
  fi
}
