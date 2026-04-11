# shellcheck shell=bash
# Fail scenarios for install-miniforge.
# Each call to fail_scenario expects scripts/install.sh to exit non-zero.
# See .devcontainer/test/run-fail-scenarios.sh for the DSL reference.

fail_scenario "invalid version 0.0.0" \
  VERSION=0.0.0

fail_scenario "GitHub API unreachable (network isolated)" \
  --network none
