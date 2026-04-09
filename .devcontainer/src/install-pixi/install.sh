#!/bin/sh
# Bootstrap: install dependencies via install-os-pkg,
# then hand off to the main bash install script.
set -e

_SELF_DIR="$(dirname "$0")"

# Install all base dependencies.
install-os-pkg --manifest "$_SELF_DIR/dependencies/base.txt" --check_installed

exec bash "$_SELF_DIR/scripts/install.sh" "$@"
