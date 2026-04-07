#!/bin/bash
# Verifies that version_codename= and version_id= selectors work correctly.
#
# Base image: debian:bookworm (version_codename=bookworm, version_id=12)
#
#   tree            → no selector, always installed
#   bc              → [version_codename=bookworm] → installed
#   less            → [version_id=12]            → installed
#   mlocate         → [version_codename=jammy]   → NOT installed (Ubuntu Jammy codename)
set -e

source dev-container-features-test-lib

check "tree installed (no selector)" command -v tree
check "bc installed (version_codename=bookworm)" command -v bc
check "less installed (version_id=12)" command -v less
check "mlocate not installed (version_codename=jammy — no match on bookworm)" bash -c "! command -v mlocate"

reportResults
