#!/bin/sh
# Bootstrap: install dependencies via install-os-pkg, then hand off to the main
# bash install script.
set -e

_SELF_DIR="$(dirname "$0")"

# Install all dependencies declared in packages.txt (including bash).
install-os-pkg --manifest "$_SELF_DIR/packages.txt" --check_installed

exec bash "$_SELF_DIR/scripts/install.sh" "$@"
