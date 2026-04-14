# shellcheck shell=bash
# Fail scenarios for install-git.
# Each call to fail_scenario expects scripts/install.sh to exit non-zero.
# See test/run-fail-scenarios.sh for the DSL and runner logic.

# Nonexistent tarball: version 0.0.0 does not exist on kernel.org.
# The source build installs build deps, then curl fails on the 404.
fail_scenario "source build: nonexistent version 0.0.0" \
  METHOD=source \
  VERSION=0.0.0

# Invalid enums should fail before any install work begins.
fail_scenario "invalid method" \
  METHOD=invalid

fail_scenario "invalid if_exists" \
  IF_EXISTS=invalid

# Preinstalled git + if_exists=fail is the canonical failure path.
fail_scenario "if_exists=fail with preinstalled git" \
  --setup-cmd "apt-get update -qq && apt-get install -y --no-install-recommends git >/dev/null 2>&1" \
  IF_EXISTS=fail

# Network isolated source build: GitHub / kernel.org unreachable.
# ospkg__run (apt-get update) fails immediately → exit 1.
fail_scenario "source build: network isolated" \
  --network none \
  METHOD=source
