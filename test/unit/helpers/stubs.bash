# shellcheck shell=bash
# helpers/stubs.bash — PATH-based stub/fake binary helpers.
#
# Provides create_fake_bin() and prepend_fake_bin_path() for injecting
# lightweight fake executables that shadow real ones during a test.

# create_fake_bin <name> [<stdout_line>]
#
# Creates a tiny executable under ${BATS_TEST_TMPDIR}/bin named <name>.
# When invoked, the fake prints <stdout_line> to stdout (ignoring all
# arguments) and exits 0.  If <stdout_line> is omitted the fake prints
# nothing.
create_fake_bin() {
  local _name="$1"
  local _stdout="${2:-}"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  # Use printf to avoid issues with special chars in _stdout.
  printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$_stdout" \
    > "${BATS_TEST_TMPDIR}/bin/${_name}"
  chmod +x "${BATS_TEST_TMPDIR}/bin/${_name}"
}

# prepend_fake_bin_path
#
# Puts ${BATS_TEST_TMPDIR}/bin at the front of PATH so fake binaries
# shadow their real counterparts for the remainder of the test.
prepend_fake_bin_path() {
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
}
