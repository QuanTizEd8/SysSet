# shellcheck shell=bash
# Capture the live setup-shell-managed files into a golden fixture tree.
#
# Run inside the generator container after install. Copies every managed file
# (per golden_paths.sh) to ${GOLDEN_OUT}/<full-path>, preserving the absolute
# path layout that assert_golden.sh diffs against. ${GOLDEN_OUT} is a host
# bind-mount (test/features/setup-shell/expected/<scenario>).

set -eu

_here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=golden_paths.sh disable=SC1091
. "${_here}/golden_paths.sh"

# GOLDEN_OUT is a bind-mount; the generator clears its contents on the host
# before the run, so this script only copies (it must not rm the mount point).
: "${GOLDEN_OUT:?GOLDEN_OUT (fixture output dir) required}"
mkdir -p "${GOLDEN_OUT}"

_count=0
while IFS= read -r -d '' _f; do
  _rel="${_f#/}"
  mkdir -p "${GOLDEN_OUT}/$(dirname "${_rel}")"
  cp -p "$_f" "${GOLDEN_OUT}/${_rel}"
  _count=$((_count + 1))
done < <(ss_golden_live_files)

echo "captured ${_count} file(s) → ${GOLDEN_OUT}"
