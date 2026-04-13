#!/bin/sh
# shellcheck disable=SC3043  # 'local' is not POSIX but is supported by all targeted shells (dash, ash, macOS sh)
# POSIX sh compatible — safe to source from sh and bash scripts alike.
# Do not edit _lib/ copies directly — edit lib/ instead.

[ -n "${_CHECKSUM__LIB_LOADED-}" ] && return 0
_CHECKSUM__LIB_LOADED=1


# checksum__verify_sha256 <file> <expected_hash>
#
# Verifies the SHA-256 digest of <file> against <expected_hash>.
# Uses sha256sum (Linux) or shasum --algorithm 256 (macOS) transparently.
# Exits 1 if neither tool is available or if the digest does not match.
checksum__verify_sha256() {
  local _file="$1"
  local _expected="$2"
  local _actual

  if command -v sha256sum > /dev/null 2>&1; then
    _actual="$(sha256sum "$_file" | awk '{print $1}')"
  elif command -v shasum > /dev/null 2>&1; then
    _actual="$(shasum --algorithm 256 "$_file" | awk '{print $1}')"
  else
    echo "⛔ checksum__verify_sha256: neither sha256sum nor shasum is available." >&2
    return 1
  fi

  if [ "$_expected" = "$_actual" ]; then
    echo "✅ Checksum verification passed." >&2
  else
    echo "❌ Checksum verification failed." >&2
    echo "   Expected: ${_expected}" >&2
    echo "   Actual:   ${_actual}" >&2
    return 1
  fi
  return 0
}


# checksum__verify_sha256_sidecar <file> <sha256_file>
#
# Reads the first whitespace-separated field of <sha256_file> as the expected
# hash, then delegates to checksum__verify_sha256.
# Suitable for the common pattern of <name>.sha256 sidecar files.
checksum__verify_sha256_sidecar() {
  local _file="$1"
  local _sha256_file="$2"
  local _expected
  _expected="$(awk '{print $1}' "$_sha256_file")"
  [ -z "$_expected" ] && {
    echo "⛔ checksum__verify_sha256_sidecar: could not read hash from '${_sha256_file}'." >&2
    return 1
  }
  checksum__verify_sha256 "$_file" "$_expected"
  return $?
}
