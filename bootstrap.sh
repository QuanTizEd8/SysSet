#!/bin/sh
# Bootstrap: ensure bash is available, then hand off to the main install script.
# Single source of truth — distributed to each feature root by sync-lib.sh.
set -e

if ! command -v bash > /dev/null 2>&1; then
    echo "🔍 bash not found — installing via system package manager." >&2
    if command -v apk > /dev/null 2>&1; then
        apk add --no-cache bash
    elif command -v apt-get > /dev/null 2>&1; then
        apt-get update && apt-get install -y --no-install-recommends bash
    elif command -v dnf > /dev/null 2>&1; then
        dnf install -y bash
    elif command -v microdnf > /dev/null 2>&1; then
        microdnf install -y bash
    elif command -v yum > /dev/null 2>&1; then
        yum install -y bash
    elif command -v zypper > /dev/null 2>&1; then
        zypper --non-interactive install bash
    elif command -v pacman > /dev/null 2>&1; then
        pacman -S --noconfirm --needed bash
    else
        echo "⛔ No supported package manager found to install bash." >&2
        exit 1
    fi
fi

_SELF_DIR="$(dirname "$0")"
exec bash "$_SELF_DIR/scripts/install.sh" "$@"
