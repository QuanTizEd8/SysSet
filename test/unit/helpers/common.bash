# shellcheck shell=bash
# helpers/common.bash — loaded in setup() of every .bats file.
#
# Sets LIB_ROOT, configures BATS_LIB_PATH, loads bats-support/-assert/-file,
# and defines the reload_lib() helper.

# LIB_ROOT: canonical lib/ directory (two levels up from test/unit/).
LIB_ROOT="${BATS_TEST_DIRNAME}/../../lib"

# Point bats library loader at the vendored bats/ subdirectory so that
# bats_load_library <name> finds <name>/load.bash inside test/unit/bats/.
export BATS_LIB_PATH="${BATS_TEST_DIRNAME}/bats"

bats_load_library bats-support
bats_load_library bats-assert
bats_load_library bats-file

# reload_lib <module.sh>
#
# Clears all lib load-guards and cached globals so a test can inject stubs
# before sourcing the library for the first time in that test's subprocess.
reload_lib() {
  local _mod="$1"

  # Clear all lib load guards.
  unset _OS__LIB_LOADED _SHELL__LIB_LOADED _OSPKG__LIB_LOADED \
    _NET__LIB_LOADED _GIT__LIB_LOADED _LOGGING__LIB_LOADED \
    _CHECKSUM__LIB_LOADED _GITHUB__LIB_LOADED _USERS__LIB_LOADED

  # Reset os.sh lazy-cached globals.
  unset _OS__KERNEL _OS__ARCH _OS__ID _OS__ID_LIKE _OS__CODENAME _OS__PLATFORM _OS__RELEASE_LOADED

  # Reset net.sh cached state.
  unset _NET_FETCH_TOOL _NET_CA_CERTS_OK

  # Reset ospkg.sh detection flag (sourcing ospkg.sh re-declares it as false).
  _OSPKG_DETECTED=false

  # Reset logging state flags.
  _LIB_LOGGING_SETUP=false
  _SYSSET_TMPDIR=
  # Pre-declare _SYSSET_MASKED_VALUES as a global indexed array BEFORE sourcing;
  # 'declare' without -g inside a function creates a local, which would
  # disappear when reload_lib returns and leave the global unset.
  declare -ga _SYSSET_MASKED_VALUES=()

  # Pre-declare global associative arrays BEFORE sourcing to work around a bash
  # scoping rule: 'declare -A' without -g in a file sourced from within a
  # function creates a LOCAL variable (goes away when the function returns).
  # Using declare -gA here ensures the array exists at global scope; the local
  # copy created by the source statement in ospkg.sh simply shadows it during
  # this function's execution and disappears on return, leaving the global.
  case "$_mod" in
    ospkg.sh) declare -gA _OSPKG_OS_RELEASE=() ;;
  esac

  # shellcheck source=/dev/null
  source "${LIB_ROOT}/${_mod}"
}
