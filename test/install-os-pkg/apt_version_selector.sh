#!/bin/bash
# Verifies that version_id= selectors work correctly.
#
# Base image: debian:bookworm (id=debian, version_id=12)
#
#   tree            → no selector, always installed
#   bc              → [version_id=12]             → installed
#   less            → [id=debian, version_id=12]  → installed
#   mlocate         → [version_id=22.04]          → NOT installed (Ubuntu version)
set -e

source dev-container-features-test-lib

check "tree installed (no selector)" command -v tree
check "bc installed (version_id=12)" command -v bc
check "less installed (id=debian and version_id=12)" command -v less
check "mlocate not installed (version_id=22.04 — no match on debian 12)" bash -c "! command -v mlocate"

reportResults
