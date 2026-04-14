#!/bin/bash
# method=source with no_flags=perl.
# Verifies Perl-dependent helpers are omitted from the installed exec-path.
set -e

source dev-container-features-test-lib

check "git on PATH" command -v git
check "git --version succeeds" git --version
check "git-svn is not installed" bash -c '! test -e "$(git --exec-path)/git-svn"'
check "git-send-email is not installed" bash -c '! test -e "$(git --exec-path)/git-send-email"'

reportResults
