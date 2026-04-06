#!/bin/bash
# Verifies that a '--- key' section with a .gpg destination fetches the
# ASCII-armored key and converts it to binary PGP format via gpg --dearmor.
# Also exercises auto-installation of curl and gnupg when absent.
set -e

source dev-container-features-test-lib

check "tree is installed" command -v tree
check "curl was auto-installed" command -v curl
check "gpg was auto-installed" command -v gpg
check "dearmored key file exists" test -f /usr/share/keyrings/nginx-archive-keyring.gpg
check "dearmored key is non-empty" test -s /usr/share/keyrings/nginx-archive-keyring.gpg
check "dearmored key is not ASCII armor" bash -c '! grep -q "BEGIN PGP" /usr/share/keyrings/nginx-archive-keyring.gpg'

reportResults
