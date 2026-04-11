#!/usr/bin/env bash
# setup_suite.bash — suite-level precondition checks.
# Called once by bats before running any tests in the suite.

setup_suite() {
  # lib/ospkg.sh, lib/shell.sh, lib/git.sh, lib/logging.sh all require bash ≥ 4.
  if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "⛔ bash ≥ 4.0 is required for the unit tests (found ${BASH_VERSION})" >&2
    exit 1
  fi
}

teardown_suite() { :; }
