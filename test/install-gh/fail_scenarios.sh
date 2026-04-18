# shellcheck shell=bash
# Fail scenarios for install-gh.
# Each call to fail_scenario expects install.bash to exit non-zero.
# See test/run-fail-scenarios.sh for the DSL reference.

# Invalid enum values must be rejected before any install work begins.
fail_scenario "invalid method value" \
  METHOD=invalid

fail_scenario "invalid if_exists value" \
  IF_EXISTS=invalid

fail_scenario "invalid sign_commits value" \
  SIGN_COMMITS=invalid

# if_exists=fail with a pre-existing gh binary.
fail_scenario "if_exists=fail with preinstalled gh" \
  --setup-cmd "mkdir -p /usr/local/bin && printf '#!/bin/sh\necho \"gh version 2.67.0 (2025-01-01)\"\n' > /usr/local/bin/gh && chmod +x /usr/local/bin/gh" \
  IF_EXISTS=fail

# version=latest + if_exists=fail should reject a preinstalled gh even with no
# network access; the early-exit must fire before any GitHub API call.
fail_scenario "if_exists=fail with preinstalled gh (network isolated)" \
  --network none \
  --setup-cmd "mkdir -p /usr/local/bin && printf '#!/bin/sh\necho \"gh version 2.67.0 (2025-01-01)\"\n' > /usr/local/bin/gh && chmod +x /usr/local/bin/gh" \
  IF_EXISTS=fail

# version=latest with no network access: GitHub API is unreachable → exit 1.
fail_scenario "network isolated (version resolution fails)" \
  --network none
