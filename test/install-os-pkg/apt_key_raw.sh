#!/bin/bash
# Verifies that a '--- key' section with a non-.gpg destination downloads the
# key as raw bytes (no dearmoring). Also exercises auto-installation of curl
# when neither curl nor wget is present on the base image.
set -e

source dev-container-features-test-lib

check "tree is installed" command -v tree
check "fetch tool was auto-installed" command -v curl
check "raw key file exists" test -f /usr/share/keyrings/nginx-signing.key
check "raw key is non-empty" test -s /usr/share/keyrings/nginx-signing.key
check "raw key retains ASCII armor" grep -q "BEGIN PGP PUBLIC KEY BLOCK" /usr/share/keyrings/nginx-signing.key

reportResults
