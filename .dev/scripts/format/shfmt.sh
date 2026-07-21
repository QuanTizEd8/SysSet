#!/usr/bin/env bash

# Run shfmt.
#
# When no paths are provided, runs shfmt on all tracked .sh/.bash files.
# Respects .editorconfig ignore rules (e.g. *.tmpl.bash, generated paths).
# With paths, runs shfmt on those paths alone.
#
# Usage:
#   shfmt.sh [--check] [paths...]
#
# Options:
#   --check  Diff mode (no writes); exits non-zero if any file differs.

set -euo pipefail

check=false
if [[ "${1:-}" == "--check" ]]; then
  check=true
  shift
fi

if "$check"; then
  cmd=(shfmt --apply-ignore --diff)
else
  cmd=(shfmt --apply-ignore --write)
fi

if [[ $# -gt 0 ]]; then
  "${cmd[@]}" "$@"
else
  # git ls-files includes tracked paths deleted in the working tree. Filter
  # those before invoking shfmt so renames/deletions do not make `just format`
  # fail with lstat errors. NUL separation also preserves unusual filenames.
  declare -a files=()
  while IFS= read -r -d '' path; do
    [[ -f "$path" ]] && files+=("$path")
  done < <(git ls-files -z -- '*.sh' '*.bash' '*.bats')
  ((${#files[@]} == 0)) || "${cmd[@]}" "${files[@]}"
fi
