#!/bin/bash
# Verifies that dry_run=true (as a feature option) causes no packages to be
# installed.  The manifest lists 'tree' but since dry_run is enabled the
# package should not be present in the resulting image.
set -e

source dev-container-features-test-lib

check "tree was NOT installed (dry_run=true)" bash -c "! command -v tree"

reportResults
