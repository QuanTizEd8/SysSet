# shellcheck shell=bash
# Re-export the suite-prepared tool wiring used by install-framework tests.

# shellcheck source=test/lib/helpers/test_tools.bash
source "${REPO_ROOT:?REPO_ROOT must identify the repository}/test/lib/helpers/test_tools.bash"
