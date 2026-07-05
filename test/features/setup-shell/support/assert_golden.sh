# shellcheck shell=bash
# Byte-for-byte golden assertion for setup-shell.
#
# Compares the live setup-shell-managed files against the committed fixtures at
# test/features/setup-shell/expected/<scenario>/<full-path> (mounted read-only at
# ${REPO_ROOT}/test/features/setup-shell/expected in standalone runs). The check
# is symmetric:
#   1. every fixture must match its live counterpart byte-for-byte, and
#   2. every live managed file must have a corresponding fixture — so an
#      unexpected/extra deployment (e.g. zsh files when setup_zsh=false) fails
#      even though no fixture exists for it.
# On any mismatch it prints a unified diff so failures are actionable.

ss_assert_golden() {
  local _scenario="${1:?scenario name required}"
  local _base="${REPO_ROOT:-/repo}/test/features/setup-shell"
  local _root="${_base}/expected/${_scenario}"
  local _fail=0 _f _rel _live

  # shellcheck source=golden_paths.sh disable=SC1091
  . "${_base}/support/golden_paths.sh"

  if [ ! -d "$_root" ]; then
    echo "golden fixtures missing: ${_root} (run: python3 ${_base}/generate_golden.py --scenario ${_scenario})" >&2
    return 1
  fi

  # (1) Fixture → live: every committed golden file matches, and exists live.
  while IFS= read -r -d '' _f; do
    _rel="${_f#"${_root}"/}"
    _live="/${_rel}"
    if [ ! -f "$_live" ]; then
      echo "MISSING: golden has ${_rel} but it was not deployed to ${_live}" >&2
      _fail=1
    elif ! cmp -s "$_f" "$_live"; then
      echo "MISMATCH: ${_live}" >&2
      diff -u "$_f" "$_live" 2>&1 | sed 's/^/    /' >&2 || true
      _fail=1
    fi
  done < <(find "$_root" -type f -print0)

  # (2) Live → fixture: no unexpected managed file lacking a golden counterpart.
  while IFS= read -r -d '' _live; do
    _rel="${_live#/}"
    if [ ! -f "${_root}/${_rel}" ]; then
      echo "UNEXPECTED: ${_live} is setup-shell-managed but has no golden fixture" >&2
      _fail=1
    fi
  done < <(ss_golden_live_files)

  return "$_fail"
}
