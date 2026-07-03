# shellcheck shell=bash
# Artifact integrity verification: SHA-256 hash checking and GPG signature verification.
#
# Returns non-zero on mismatch, logging expected and actual values. Designed
# for use with downloaded release artifacts.

_verify__sha_dispatch() {
  # @brief _verify__sha_dispatch <file> <algo> — Try sha<algo>sum then shasum; return 1 if neither is found.
  local _file="$1" _algo="$2"
  if command -v "sha${_algo}sum" > /dev/null 2>&1; then
    "sha${_algo}sum" "$_file" | awk '{print $1}'
  elif command -v shasum > /dev/null 2>&1; then
    shasum --algorithm "${_algo}" "$_file" | awk '{print $1}'
  else
    return 1
  fi
}

verify__hash_file() {
  # @brief verify__hash_file <file> [algo] — Print lowercase hex digest of `<file>` to stdout.
  #
  # `algo` is `256` (default) or `512`.
  # Uses `sha<N>sum` (Linux/coreutils) or `shasum --algorithm <N>` (macOS/Perl).
  # Falls back to installing coreutils via ospkg when neither tool exists.
  #
  # Args:
  #   <file>   Path to an existing regular file.
  #   [algo]   Hash algorithm: `256` (default) or `512`.
  #
  # Stdout: lowercase hex digest string.
  #
  # Returns: 0 on success, 1 if file does not exist or tool unavailable.
  local _file="$1"
  local _algo="${2:-256}"
  [ -f "$_file" ] || {
    logging__error "file not found: '${_file}'."
    return 1
  }
  _verify__sha_dispatch "$_file" "$_algo" && return
  logging__info "sha${_algo}sum/shasum not found — installing coreutils."
  ospkg__install_tracked "lib-verify" coreutils
  _verify__sha_dispatch "$_file" "$_algo"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "no sha${_algo}sum or shasum available after coreutils install."
    return "$_rc"
  }
}

verify__sha() {
  # @brief verify__sha <file> <expected_hash> [algo] — Verify the SHA digest of `<file>` against `<expected_hash>`.
  #
  # `algo` is `256` (default) or `512`.
  #
  # Args:
  #   <file>           Path to the file to verify.
  #   <expected_hash>  Expected lowercase hex digest.
  #   [algo]           Hash algorithm: `256` (default) or `512`.
  #
  # Returns: 0 on match, 1 on mismatch or error.
  local _file="$1"
  local _expected="$2"
  local _algo="${3:-256}"
  local _actual

  _actual="$(verify__hash_file "$_file" "$_algo")"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "could not hash file '${_file}'."
    return "$_rc"
  }

  if [ "$_expected" = "$_actual" ]; then
    logging__success "Checksum verification passed."
  else
    logging__fatal "Checksum verification failed."
    logging__error "   Expected: ${_expected}"
    logging__error "   Actual:   ${_actual}"
    return 1
  fi
  return 0
}

verify__sha_sidecar() {
  # @brief verify__sha_sidecar <file> <hash_file> [algo] — Read expected hash from the first field of `<hash_file>` and verify via `verify__sha`.
  #
  # Suitable for the common `<name>.sha256` / `<name>.sha512` sidecar file pattern.
  #
  # Args:
  #   <file>       Path to the file to verify.
  #   <hash_file>  Path to the sidecar file containing the expected hash.
  #   [algo]       Hash algorithm: `256` (default) or `512`.
  #
  # Returns: 0 on match, 1 on mismatch or unreadable hash file.
  local _file="$1"
  local _hash_file="$2"
  local _algo="${3:-256}"
  local _expected
  _expected="$(awk '{print $1}' "$_hash_file")"
  [ -z "$_expected" ] && {
    logging__error "could not read hash from '${_hash_file}'."
    return 1
  }
  verify__sha "$_file" "$_expected" "$_algo"
  return $?
}

verify__gpg_detached() {
  # @brief verify__gpg_detached <file> <sig_file> <key_file> [group_id] — Verify a file against a detached ASCII-armored GPG signature.
  #
  # Creates an isolated `GNUPGHOME`, imports the key, runs `gpg --verify`, then
  # removes the temporary keyring. The caller is responsible for downloading
  # `sig_file` and `key_file` before calling this function.
  #
  # Unlike most bootstrap__* tools, gpg has no official prebuilt Linux binary
  # to fall back to (upstream ships source tarballs only, with its own
  # dependency chain — libgcrypt, libksba, libassuan, npth — so downloading a
  # static binary the way bootstrap__jq/bootstrap__yq do isn't viable). When
  # gpg cannot be installed because the caller lacks privilege, verification
  # is skipped with a warning rather than failing the whole install — the
  # same graceful-degradation policy already used for privileged-only side
  # operations elsewhere (e.g. package-manager cache cleanup, dependency
  # auto-install). A privileged caller with a genuinely broken gpg install
  # still fails loudly.
  #
  # Args:
  #   <file>      Path to the artifact to verify.
  #   <sig_file>  Path to the detached PGP signature file (`.asc` or `.sig`).
  #   <key_file>  Path to the ASCII-armored or binary public key.
  #   [group_id]  Tracking group used when auto-installing gpg (default: `lib-verify`).
  #
  # Returns: 0 on successful (or skipped) verification, 1 on failure.
  local _file="$1" _sig="${2-}" _key="${3-}" _group="${4:-lib-verify}"
  [[ -f "$_file" ]] || {
    logging__error "artifact not found: '${_file}'."
    return 1
  }
  [[ -f "$_sig" ]] || {
    logging__error "signature file not found: '${_sig}'."
    return 1
  }
  [[ -f "$_key" ]] || {
    logging__error "key file not found: '${_key}'."
    return 1
  }

  bootstrap__gpg "$_group"
  local _rc=$?
  if [[ $_rc != 0 ]]; then
    if ! users__is_privileged; then
      logging__warn "gpg is not available and cannot be installed without privilege; skipping signature verification for '$(basename "$_file")'."
      return 0
    fi
    logging__error "gpg is required for detached signature verification."
    return "$_rc"
  fi

  local _ghome
  _ghome="$(file__mktmpdir "verify-gpg")"
  chmod 0700 "$_ghome"

  if ! gpg --homedir "$_ghome" --batch --no-autostart --import "$_key" > /dev/null; then
    logging__error "failed to import key from '${_key}'."
    return 1
  fi

  if ! gpg --homedir "$_ghome" --batch --no-autostart --verify "$_sig" "$_file" > /dev/null; then
    logging__error "signature verification failed for '$(basename "$_file")'."
    return 1
  fi

  logging__success "Signature verification passed for '$(basename "$_file")'."
  return 0
}

verify__gpg_dearmor_stream() {
  # @brief verify__gpg_dearmor_stream <dest_file> [group_id] — Read ASCII-armored key from stdin and write dearmored binary keyring to `<dest_file>`.
  #
  # Args:
  #   <dest_file>  Destination path for the dearmored binary keyring.
  #   [group_id]   Tracking group for auto-installing gpg (default: lib-verify).
  local _dest="$1" _group="${2:-lib-verify}"
  bootstrap__gpg "$_group"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "gpg is required to dearmor a key stream."
    return "$_rc"
  }
  gpg --dearmor -o "$_dest"
}

verify__gpg_fetch_key_by_fingerprint() {
  # @brief verify__gpg_fetch_key_by_fingerprint <fingerprint> <dest> [group_id] — Fetch a GPG public key by fingerprint and write a dearmored binary keyring to `<dest>`.
  #
  # Tries Ubuntu HTTPS keyserver first, then HKP keyserver fallbacks.
  # The HKP path uses an isolated GNUPGHOME so the system keyring is not polluted.
  #
  # Args:
  #   <fingerprint>  40-hex-char GPG key fingerprint (with or without leading 0x).
  #   <dest>         Destination path for the dearmored binary keyring.
  #   [group_id]     Tracking group for auto-installing gpg (default: lib-verify).
  local _fingerprint="$1" _dest="$2" _group="${3:-lib-verify}"
  bootstrap__gpg "$_group"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "gpg is required to fetch a key by fingerprint."
    return "$_rc"
  }
  mkdir -p "$(dirname "$_dest")"

  # Primary: HTTPS download from Ubuntu keyserver.
  local _key_data
  _key_data="$(net__fetch_url_stdout \
    "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${_fingerprint#0x}" 2> /dev/null)" || true
  if printf '%s' "${_key_data}" | grep -q 'BEGIN PGP'; then
    if printf '%s' "${_key_data}" | gpg --dearmor -o "${_dest}"; then
      chmod 0644 "${_dest}"
      logging__success "GPG key installed via HTTPS keyserver → ${_dest}"
      return 0
    fi
  fi

  # Fallback: gpg --recv-keys via HKP keyservers (isolated GNUPGHOME).
  local _ghome _ks
  _ghome="$(file__mktmpdir "verify-gpg")"
  chmod 0700 "$_ghome"
  for _ks in "hkp://keyserver.ubuntu.com" "hkp://keyserver.pgp.com"; do
    logging__info "Trying keyserver ${_ks}..."
    if gpg --homedir "$_ghome" --recv-keys --keyserver "${_ks}" "${_fingerprint}" 2> /dev/null; then
      if gpg --homedir "$_ghome" --export "${_fingerprint}" | gpg --dearmor -o "${_dest}"; then
        chmod 0644 "${_dest}"
        logging__success "GPG key installed via ${_ks} → ${_dest}"
        return 0
      fi
    fi
  done
  logging__error "failed to fetch key ${_fingerprint} from all keyservers."
  return 1
}
