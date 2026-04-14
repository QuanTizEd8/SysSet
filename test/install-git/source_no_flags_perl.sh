#!/bin/bash
# method=source with no_flags=perl.
# Verifies Perl-dependent helpers are omitted from the installed exec-path.
set -e

source dev-container-features-test-lib

check "git on PATH" command -v git
check "git --version succeeds" git --version
check "git-svn is not functional (perl disabled)" bash -c '! git svn --version 2>/dev/null'
check "git-send-email is not functional (perl disabled)" bash -c '! git send-email --version 2>/dev/null'

reportResults
