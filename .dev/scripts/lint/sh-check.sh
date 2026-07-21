#!/usr/bin/env bash

# Run shellcheck.
#
# When no paths are provided, runs shellcheck
# on tracked .sh/.bash files (except features/*/install.bash, *.tmpl.*)
# plus src/*/install.bash.
# With args, runs shellcheck on those paths alone.
#
# Usage:
#   sh-check.sh [paths...]
# Environment variables:
#   SHELLCHEK_JOBS: override number of parallel jobs (default: 3/4 of available CPUs)
#   SHELLCHEK_BATCH: override number of files per batch (default: 5)

set -euo pipefail

ncpu=$(nproc 2> /dev/null || sysctl -n hw.logicalcpu)

# With `external-sources`, shellcheck can be memory-heavy on large files.
# Default to 3/4 of available CPUs to balance throughput and memory pressure;
# allow override via SHELLCHEK_JOBS when needed.
jobs="${SHELLCHEK_JOBS:-}"
if [[ ! "$jobs" =~ ^[0-9]+$ || "$jobs" -lt 1 ]]; then
  jobs=$((ncpu * 3 / 4))
  ((jobs < 1)) && jobs=1
fi
((jobs > ncpu)) && jobs="$ncpu"

batch="${SHELLCHEK_BATCH:-5}"
if [[ ! "$batch" =~ ^[0-9]+$ || "$batch" -lt 1 ]]; then
  batch=5
fi

if [[ $# -gt 0 ]]; then
  printf '%s\0' "$@" | xargs -0 -P"${jobs}" -n"${batch}" shellcheck
else
  declare -a files=()
  while IFS= read -r -d '' path; do
    # git ls-files includes tracked paths deleted in the working tree.
    [[ -f "$path" ]] || continue
    [[ "$path" =~ ^features/[^/]+/install\.bash$|\.tmpl\.(bash|sh)$ ]] && continue
    files+=("$path")
  done < <(git ls-files -z -- '*.sh' '*.bash')
  while IFS= read -r -d '' path; do
    files+=("$path")
  done < <(find src -maxdepth 2 -name 'install.bash' -print0 2> /dev/null)
  ((${#files[@]} == 0)) || printf '%s\0' "${files[@]}" | xargs -0 -P"${jobs}" -n"${batch}" shellcheck
fi
