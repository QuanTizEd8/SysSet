# shellcheck shell=bash
# helpers/common.bash — loaded in setup() of every .bats file.
#
# Sets LIB_ROOT, configures BATS_LIB_PATH, loads bats-support/-assert/-file,
# and defines the reload_lib() helper.

# LIB_ROOT: canonical lib/ directory.
# REPO_ROOT is exported by the test runner; fall back to git for direct invocation.
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
fi
# In CI, LIB_ROOT is set to the extracted library artifact so tests run against
# the packaged tarball rather than the raw source tree.  Fall back to lib/ for
# local development.
LIB_ROOT="${LIB_ROOT:-${REPO_ROOT}/lib}"

# Point bats library loader at the vendored bats/ subdirectory.
export BATS_LIB_PATH="${REPO_ROOT}/test/lib/bats"

bats_load_library bats-support
bats_load_library bats-assert
bats_load_library bats-file

# Pre-declare global associative/indexed arrays before sourcing modules.
declare -gA _OCI__AUTH_USER=()
declare -gA _OCI__AUTH_TOKEN=()
declare -gA _OCI__AUTH_DONE=()
declare -ga _LOGGING__SYSSET_MASKED_VALUES=()
declare -gA _CTX__REGISTRY=()
declare -g _CTX__REGISTRY_INITIALIZED=false

# Source lib once at test-process startup.
# shellcheck source=/dev/null
source "${LIB_ROOT}/__init__.bash"

# Pending journal for pre-setup logging__* calls. Do NOT use logging__pending_init
# here: its EXIT trap is inherited by bats `run` command-substitution subshells and
# corrupts output capture / kills workers.
_lib_test__init_pending_journal() {
  # Avoid mktemp so PATH-isolated tests (ospkg__detect, etc.) still work.
  if [[ -z "${_LOGGING__PENDING_FILE:-}" ]]; then
    _LOGGING__PENDING_FILE="${BATS_TEST_TMPDIR}/df-pending-${$}-${RANDOM}"
  fi
  : > "${_LOGGING__PENDING_FILE}"
}

_lib_test__init_pending_journal

_lib_test__clear_pending_journal() {
  if [[ -n "${_LOGGING__PENDING_FILE:-}" ]]; then
    /bin/rm -f "${_LOGGING__PENDING_FILE}" 2> /dev/null || true
    _LOGGING__PENDING_FILE=
    unset _LOGGING__PENDING_FILE
  fi
  _LOGGING__PENDING_FLUSHED=0
  _LOGGING__PENDING_HANDED_OFF=0
}

_lib_test__append_pending_journal_to() {
  local _dest="$1"
  [[ -n "${_LOGGING__PENDING_FILE:-}" && -s "${_LOGGING__PENDING_FILE}" ]] || return 0
  _logging__pending_dump_stderr >> "$_dest" 2>&1
}

_lib_test__replay_pending_journal() {
  [[ -n "${_LOGGING__PENDING_FILE:-}" && -f "${_LOGGING__PENDING_FILE}" ]] || return 0
  local _log_line _min _payload _pending=""
  while IFS= read -r _log_line || [[ -n "$_log_line" ]]; do
    [[ -z "$_log_line" ]] && continue
    _min="${_log_line%%$'\t'*}"
    _payload="${_log_line#*$'\t'}"
    _payload="$(_logging__prefix_payload "$_payload")"
    [[ -n "$_payload" ]] && _pending+="${_pending:+$'\n'}${_payload}"
  done < "${_LOGGING__PENDING_FILE}"
  [[ -n "$_pending" ]] || return 0
  if [[ -n "${stderr+set}" ]]; then
    stderr+="${stderr:+$'\n'}${_pending}"
    bats_separate_lines stderr_lines stderr
  else
    output+="${output:+$'\n'}${_pending}"
    bats_separate_lines lines output
  fi
}

# Wrap bats `run` once per process so failure-path logging__* calls are visible to
# assert_output / assert_stderr (pending journal is not live stderr before setup).
if ! declare -f _lib_test_run_orig > /dev/null 2>&1; then
  eval "$(declare -f run | sed '1s/^run/_lib_test_run_orig/')"

  run() {
    _lib_test_run_orig "$@"
    local _replay_pending=false
    # shellcheck disable=SC2154
    if ((status != 0)); then
      _replay_pending=true
    elif [[ -z "$output" ]]; then
      _replay_pending=true
    elif [[ -n "${stderr+set}" ]]; then
      _replay_pending=true
    fi
    if $_replay_pending && [[ -n "${_LOGGING__PENDING_FILE:-}" && -s "${_LOGGING__PENDING_FILE}" ]]; then
      _lib_test__replay_pending_journal
    fi
    _lib_test__clear_pending_journal
    _lib_test__init_pending_journal
  }
fi

# reload_lib [<module.{bash,sh}>]
#
# Resets all cached globals so a test can inject stubs and observe fresh
# behaviour. The module argument is accepted for backward compatibility but
# ignored: all modules are already loaded at process startup.
reload_lib() {
  # Reset os.bash lazy-cached globals.
  unset _OS__KERNEL _OS__ARCH _OS__PLATFORM

  # Reset net.bash cached state.
  unset _NET__FETCH_TOOL _NET__CA_CERTS_OK

  # Reset ospkg.bash detection flag.
  _OSPKG__DETECTED=false
  _OSPKG__PM_KEY=""
  _OSPKG__DEB_ARCH=""
  # Reset ospkg.bash live-registry state and drop any test override so registry
  # tests do not bleed into each other.
  _OSPKG__REGISTERED=false
  _OSPKG__SELF_TOKEN=""
  _OSPKG__LAST_OUT_DECISION=true
  _OSPKG__REGISTRY_STALE_SECS=900
  unset _OSPKG__REGISTRY_ROOT
  ctx__reset

  # Reset logging state flags.
  _LOGGING__LIB_SETUP=false
  _FILE__SESSION_ROOT=
  _FILE__SESSION_OWNED=false
  declare -ga _LOGGING__SYSSET_MASKED_VALUES=()
  _lib_test__clear_pending_journal
  _lib_test__init_pending_journal

  # Re-declare global associative arrays so prior test runs don't leave stale
  # entries (also guards against any code path that might 'unset' them).
  declare -gA _OCI__AUTH_USER=()
  declare -gA _OCI__AUTH_TOKEN=()
  declare -gA _OCI__AUTH_DONE=()
  declare -gA _CTX__REGISTRY=()
  _CTX__REGISTRY_INITIALIZED=false
}

# lib_test__net_fetch_fail_fast — opt-in for bats tests that expect a network fetch
# to fail (unreachable host, blocked network). lib/net.bash reads these when
# --retries/--delay are omitted. Do not call in success-path network tests.
lib_test__net_fetch_fail_fast() {
  export DEVFEATS_NET_FETCH_RETRIES=1
  export DEVFEATS_NET_FETCH_DELAY=0
}
