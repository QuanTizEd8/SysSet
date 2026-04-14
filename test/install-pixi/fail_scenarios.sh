# shellcheck shell=bash
# Fail scenarios for install-pixi.
# Each call to fail_scenario expects scripts/install.sh to exit non-zero.
# See test/run-fail-scenarios.sh for the DSL reference.

fail_scenario "invalid version string" \
  VERSION=not_a_semver_string

fail_scenario "invalid version suffix slips past validator" \
  --setup-cmd "mkdir -p /tmp/pixi-archive && printf '#!/bin/sh\necho pixi 0.0.0\n' > /tmp/pixi-archive/pixi && chmod +x /tmp/pixi-archive/pixi && tar -czf /tmp/pixi-custom.tar.gz -C /tmp/pixi-archive pixi" \
  VERSION=1.2beta \
  DOWNLOAD_URL=file:///tmp/pixi-custom.tar.gz

fail_scenario "if_exists=fail with pre-existing binary" \
  --setup-cmd "mkdir -p /usr/local/bin && echo '#!/bin/sh' > /usr/local/bin/pixi && chmod +x /usr/local/bin/pixi" \
  IF_EXISTS=fail

fail_scenario "GitHub API unreachable (network isolated)" \
  --network none
