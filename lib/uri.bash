# shellcheck shell=bash
# URI resolution: materialize local paths and remote URIs to files for feature installers.
#
# Provides a unified download pipeline via uri__fetch_asset, which handles scheme routing
# (http/https, ftp/ftps/sftp, file://, gh://, oci://, local paths), optional integrity
# verification (sha256 fragment, explicit hex, sidecar checksum file, GPG detached signature),
# archive extraction, and binary installation. uri__resolve and related functions are thin
# backward-compatible wrappers around uri__fetch_asset.

_uri__split_frag() {
  # _uri__split_frag <full-uri> — prints base-uri on first line, fragment part on second (may be empty).
  local _in="$1"
  local _base="${_in%%#*}"
  local _frag=""
  [[ "$_in" == *"#"* ]] && _frag="${_in#*#}"
  printf '%s\n%s\n' "$_base" "$_frag"
}

_uri__frag_sha256() {
  # _uri__frag_sha256 <frag> — prints expected sha256 hex if present in fragment (else empty).
  local _frag="$1" _p _v
  [[ -z "$_frag" ]] && return 0
  local _IFS="$IFS"
  IFS='&'
  # shellcheck disable=SC2086
  set -- ${_frag}
  IFS="$_IFS"
  for _p in "$@"; do
    case "$_p" in
      sha256=*)
        _v="${_p#sha256=}"
        printf '%s\n' "${_v%%&*}"
        return 0
        ;;
    esac
  done
  return 0
}

_uri__file_url_path() {
  # _uri__file_url_path <file-uri> — strip file:// and print absolute path.
  local _u="$1"
  _u="${_u#file://}"
  [[ "$_u" == /* ]] || _u="/${_u}"
  printf '%s\n' "$_u"
}

_uri__gh_to_https() {
  # _uri__gh_to_https <gh-uri> — translate gh://owner/repo@ref:path to raw.githubusercontent URL.
  local _in="$1" _rest _or _at _ref _path
  _rest="${_in#gh://}"
  [[ -n "$_rest" ]] || {
    logging__error "invalid gh:// URI: missing owner/repo."
    return 1
  }
  if [[ "$_rest" == *"@"* ]]; then
    _or="${_rest%%@*}"
    _at="${_rest#*@}"
    _ref="${_at%%:*}"
    _path="${_at#*:}"
  else
    _or="${_rest%%:*}"
    _path="${_rest#*:}"
    _ref="main"
  fi
  [[ -n "$_or" && -n "$_path" ]] || {
    logging__error "invalid gh:// URI: owner/repo and path are required."
    return 1
  }
  printf 'https://raw.githubusercontent.com/%s/%s/%s\n' "$_or" "$_ref" "$_path"
}

_uri__safe_basename() {
  # _uri__safe_basename <uri-without-frag> — derive a filename for materialized downloads.
  local _u="$1"
  local _b="${_u%%\?*}"
  _b="${_b##*/}"
  [[ -n "$_b" ]] || _b="download"
  printf '%s\n' "$_b"
}

uri__dest_for_uri() {
  # @brief uri__dest_for_uri <dest_dir> <full-uri> — Stable materialization path under dest_dir.
  local _dir="$1" _uri="$2"
  local _id _base
  bootstrap__sha256sum || true
  if command -v sha256sum > /dev/null 2>&1; then
    _id="$(printf '%s' "$_uri" | sha256sum | awk '{print $1}' | cut -c1-16)"
  elif command -v shasum > /dev/null 2>&1; then
    _id="$(printf '%s' "$_uri" | shasum -a 256 | awk '{print $1}' | cut -c1-16)"
  else
    _id="$(printf '%s' "$_uri" | cksum | awk '{print $1}')"
  fi
  local _base_raw
  _base_raw="$(_uri__split_frag "$_uri")"
  _base_raw="$(printf '%s\n' "$_base_raw" | head -n1)"
  _base="$(_uri__safe_basename "$_base_raw")"
  printf '%s/%s-%s\n' "$_dir" "$_id" "$_base"
}

uri__classify() {
  # @brief uri__classify <input> — Print the URI class: `local` | `file` | `http` | `ftp` | `oci` | `gh`. Returns non-zero for unsupported schemes.
  #
  # Args:
  #   <input>  URI or local path to classify.
  #
  # Stdout: one of `local`, `file`, `http`, `ftp`, `oci`, `gh`.
  local _in="$1"
  local _base
  _base="$(_uri__split_frag "$_in")"
  _base="$(printf '%s\n' "$_base" | head -n1)"
  case "$_base" in
    "")
      logging__error "URI is empty."
      return 1
      ;;
    http://* | https://*) printf 'http\n' ;;
    ftp://* | ftps://* | sftp://*) printf 'ftp\n' ;;
    file://*) printf 'file\n' ;;
    oci://*) printf 'oci\n' ;;
    gh://*) printf 'gh\n' ;;
    *://*)
      logging__error "unsupported scheme in '${_base}'."
      return 1
      ;;
    *) printf 'local\n' ;;
  esac
  return 0
}

_uri__net_fetch() {
  # _uri__net_fetch — Run net__fetch_url_file with optional headers and netrc.
  local _url="$1" _dest="$2"
  shift 2
  net__fetch_url_file "$_url" "$_dest" "$@"
}

_uri__resolve_oci_to() {
  # _uri__resolve_oci_to <oci-uri> <dest-file>
  bootstrap__find || return 1
  local _uri="$1" _dest="$2"
  local _base _frag _rest _ref_part _query _path_pat _pull_dir
  _base="$(_uri__split_frag "$_uri")"
  _base="$(printf '%s\n' "$_base" | head -n1)"
  _frag="$(_uri__split_frag "$_uri")"
  _frag="$(printf '%s\n' "$_frag" | tail -n1)"
  _rest="${_base#oci://}"
  _ref_part="${_rest%%\?*}"
  _query=""
  [[ "$_rest" == *"?"* ]] && _query="${_rest#*\?}"
  _path_pat=""
  if [[ -n "$_query" ]]; then
    local _q _p
    IFS='&' read -ra _q <<< "$_query" || true
    for _p in "${_q[@]}"; do
      case "$_p" in
        path=*)
          _path_pat="${_p#path=}"
          ;;
      esac
    done
  fi
  oci__ensure_oras
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "oras is required to resolve OCI URI."
    return "$_rc"
  }
  _oci__ensure_auth_for "$_ref_part"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "OCI registry authentication failed for '${_ref_part}'."
    return "$_rc"
  }
  _pull_dir="$(file__mktmpdir "uri-oci-pull")"
  local _oci_target _oci_plain
  IFS=$'\t' read -r _oci_target _oci_plain <<< "$(_oci__normalize_target "$_ref_part")"
  if ! _oci__oras_capture "$_oci_target" "$_oci_plain" oras pull -o "$_pull_dir" > /dev/null; then
    logging__error "oras pull failed for '${_ref_part}'."
    return 1
  fi
  local _picked=""
  if [[ -n "$_path_pat" ]]; then
    _picked="$(find "$_pull_dir" -type f \( -name "${_path_pat}" -o -path "*/${_path_pat}" \) -print -quit 2> /dev/null)"
    [[ -z "$_picked" ]] && _picked="$(find "$_pull_dir" -type f -path "*${_path_pat}*" -print -quit 2> /dev/null)"
  fi
  if [[ -z "$_picked" ]]; then
    local _n
    _n="$(find "$_pull_dir" -type f | wc -l | tr -d ' ')"
    if [[ "$_n" == "1" ]]; then
      _picked="$(find "$_pull_dir" -type f -print -quit)"
    fi
  fi
  [[ -n "$_picked" && -f "$_picked" ]] || {
    logging__error "could not pick a single file from OCI artefact '${_ref_part}'."
    return 1
  }
  cp -f "$_picked" "$_dest" || {
    logging__error "failed to copy OCI artifact '${_picked}' to '${_dest}'."
    return 1
  }
  local _expect
  _expect="$(_uri__frag_sha256 "$_frag")"
  if [[ -n "$_expect" ]]; then
    verify__sha "$_dest" "$_expect"
    local _rc=$?
    [[ $_rc == 0 ]] || {
      logging__error "OCI artifact checksum verification failed for '${_dest}'."
      return "$_rc"
    }
  fi
  return 0
}

_uri__sidecar_hash() {
  # _uri__sidecar_hash <asset_name> <sidecar_file> — extract the sha256 hex for <asset_name>
  # from a sidecar checksum file. Supports the GNU coreutils sha256sum multi-entry format
  # (<hash>  <filename> or <hash> *<filename>), the OpenSSL/BSD-style format
  # (ALGO (<filename>) = <hash>, e.g. `SHA256 (tool.tar.gz) = <hash>`), and raw single-hash
  # files (one line, one field). Prints the hex string (or empty on no match). Returns 0.
  local _name="$1" _file="$2"
  awk -v a="$_name" \
    '{
      if (NF >= 4 && $1 ~ /^(MD5|SHA1|SHA224|SHA256|SHA384|SHA512)$/ && $(NF - 1) == "=") {
        fn = $2; sub(/^\(/, "", fn); sub(/\)$/, "", fn); sub(/.*\//, "", fn)
        hash = $NF
      } else {
        fn = $NF; sub(/^\*/, "", fn); sub(/.*\//, "", fn)
        hash = $1
      }
    }
    fn == a { print hash; _f = 1; exit }
    END { if (!_f && NR == 1 && NF == 1) print $1 }' \
    "$_file"
}

_uri__sidecar_content_may_be_transient() {
  # @brief _uri__sidecar_content_may_be_transient <sidecar-file> — Return success for empty or obvious HTML/proxy responses that merit one refetch.
  local _file="$1"
  [ ! -s "$_file" ] && return 0
  grep -Eiq '<[[:space:]]*!?doctype|<[[:space:]]*(html|head|body|title)([[:space:]>]|$)' "$_file"
}

_uri__match_binary_src() {
  # _uri__match_binary_src <spec> <extract_dir> — find file(s) matching suffix-path <spec>
  # inside <extract_dir>. Whole-component boundary match (e.g. "bin/gh" matches path ending
  # in .../bin/gh but not .../bin/ghx). Prints one path per match line.
  bootstrap__find || return 1
  local _spec="$1" _dir="$2"
  local _ncomp
  _ncomp="$(printf '%s\n' "$_spec" | tr '/' '\n' | wc -l)"
  find "$_dir" -type f | awk -v spec="$_spec" -v n="$_ncomp" '
    BEGIN { split(spec, sp, "/") }
    {
      m = split($0, p, "/")
      if (m < n) next
      match_ok = 1
      for (j = 1; j <= n; j++) {
        if (p[m - n + j] != sp[j]) { match_ok = 0; break }
      }
      if (match_ok) print $0
    }
  '
}

_uri__download_to() {
  # _uri__download_to <url> <dest> [--header H]... [--netrc-file path]
  # Route a URI to a local file using the appropriate transport. Strips the #fragment
  # from the URL before the actual request. Does NOT verify the sha256 fragment —
  # that is the caller's responsibility. Returns 0 on success, 1 on failure.
  local _url="$1" _dest="$2"
  shift 2
  local _args=("$@")
  local _cls _base
  _cls="$(uri__classify "$_url")"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "unsupported URI scheme in '${_url}'."
    return "$_rc"
  }
  _base="$(_uri__split_frag "$_url")"
  _base="$(printf '%s\n' "$_base" | head -n1)"
  case "$_cls" in
    local)
      [[ -e "$_base" ]] || {
        logging__error "local path not found: '${_base}'."
        return 1
      }
      [[ "$_base" -ef "$_dest" ]] || cp -f "$_base" "$_dest" || {
        logging__error "failed to copy '${_base}' to '${_dest}'."
        return 1
      }
      ;;
    file)
      local _fp
      _fp="$(_uri__file_url_path "$_base")"
      [[ -f "$_fp" ]] || {
        logging__error "file:// target not found: '${_fp}'."
        return 1
      }
      cp -f "$_fp" "$_dest" || {
        logging__error "failed to copy '${_fp}' to '${_dest}'."
        return 1
      }
      ;;
    http | ftp)
      _uri__net_fetch "$_base" "$_dest" "${_args[@]}"
      local _rc=$?
      [[ $_rc == 0 ]] || {
        logging__error "failed to download '${_base}'."
        return "$_rc"
      }
      ;;
    gh)
      local _https
      _https="$(_uri__gh_to_https "$_base")"
      local _rc=$?
      [[ $_rc == 0 ]] || {
        logging__error "invalid gh:// URI '${_base}'."
        return "$_rc"
      }
      _uri__net_fetch "$_https" "$_dest" "${_args[@]}"
      local _rc=$?
      [[ $_rc == 0 ]] || {
        logging__error "failed to download '${_https}'."
        return "$_rc"
      }
      ;;
    oci)
      # _uri__resolve_oci_to handles its own sha256 fragment verification internally.
      _uri__resolve_oci_to "$_url" "$_dest"
      local _rc=$?
      [[ $_rc == 0 ]] || {
        logging__error "failed to resolve OCI URI '${_url}'."
        return "$_rc"
      }
      ;;
    *)
      logging__error "internal error (class=${_cls})."
      return 1
      ;;
  esac
  return 0
}

_uri__gpg_verify() {
  # _uri__gpg_verify <target-file> <key-uri> <sig-uri> <sig-dir> <key-dir> <label> [auth-arg]...
  # Download the detached GPG signature and public key, then verify <target-file>
  # against them via verify__gpg_detached. <label> (e.g. "GPG" or "sidecar GPG")
  # is interpolated into the log/error messages. Returns 0 on success, non-zero
  # (propagating the failing step's exit code) on any download or verify failure.
  local _target="$1" _key_uri="$2" _sig_uri="$3" _sig_dir="$4" _key_dir="$5" _label="$6"
  shift 6
  mkdir -p "$_sig_dir" "$_key_dir"
  local _sig_base _sig_file
  _sig_base="$(printf '%s\n' "$(_uri__split_frag "$_sig_uri")" | head -n1)"
  _sig_file="${_sig_dir}/$(_uri__safe_basename "$_sig_base")"
  local _key_base _key_file
  _key_base="$(printf '%s\n' "$(_uri__split_frag "$_key_uri")" | head -n1)"
  _key_file="${_key_dir}/$(_uri__safe_basename "$_key_base")"
  logging__download "Fetching ${_label} signature from '${_sig_base}'"
  _uri__download_to "$_sig_uri" "$_sig_file" "$@"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to download ${_label} signature from '${_sig_base}'."
    return "$_rc"
  }
  logging__download "Fetching ${_label} key from '${_key_base}'"
  _uri__download_to "$_key_uri" "$_key_file" "$@"
  _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to download ${_label} key from '${_key_base}'."
    return "$_rc"
  }
  verify__gpg_detached "$_target" "$_sig_file" "$_key_file"
  _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "${_label} signature verification failed for '$(basename "$_target")'."
    return "$_rc"
  }
}

uri__fetch_asset() {
  # @brief uri__fetch_asset <uri> [OPTIONS] — Download, verify, extract, and optionally install one or more files from a single asset.
  #
  # Downloads a file from any supported URI, verifies integrity, extracts archives,
  # and installs files. Regardless of which flags are provided, the same layout is
  # always built inside a work directory:
  #
  # ```
  # work_dir/
  #   archive/<basename>      Raw downloaded file (archives only); <basename> is
  #                           the basename of <uri>, or --filename if set.
  #   asset/                  Archive extracted verbatim (no path stripping): the
  #                           archive's internal tree is reproduced exactly under
  #                           asset/. For non-archives: the downloaded file as
  #                           <basename>.
  #   sidecar/<basename>      Basename of --sidecar URI (only when --sidecar given).
  #   gpg-sig/<basename>      Basename of --gpg-sig URI (only when --gpg-key given).
  #   gpg-key/<basename>      Basename of --gpg-key URI (only when --gpg-key given).
  #   sidecar-gpg-sig/<basename> Basename of --sidecar-gpg-sig URI (only when
  #                           --sidecar-gpg-key given).
  #   sidecar-gpg-key/<basename> Basename of --sidecar-gpg-key URI (only when
  #                           --sidecar-gpg-key given).
  # ```
  #
  # `work_dir` is `--installer-dir` when provided, otherwise an auto-cleaned tmpdir
  # (removed on script exit). When `--installer-dir` is provided, the seven managed
  # subdirectories are removed and recreated on each invocation (idempotency).
  #
  # Pairing rules apply independently to the binary pair (`--binary-src` /
  # `--binary-dest`) and the file pair (`--file-src` / `--file-dest`). Within each
  # pair, a trailing `/` on the dest treats it as a directory (installed file keeps
  # its basename); without a trailing `/` the dest is the exact output path,
  # enabling renaming. For N src and M dest values within one pair:
  #
  # - N=M → 1-to-1 paired in order.
  # - N>1, M=1-dir → all matched files fan out into the directory.
  # - Otherwise → error.
  #
  # When N=0 (no `--binary-src` or `--file-src` given):
  #
  # - Binary, archive: auto-discover all executables in `asset/`. With M=1-file
  #   dest, error if not exactly one executable found.
  # - Binary, non-archive: install `asset/<basename>` directly.
  # - File, archive: error — no auto-discovery for non-binary files.
  # - File, non-archive: install `asset/<basename>` directly.
  #
  # Args:
  #   <uri>                   Asset URI. Supported schemes: `https://`, `http://`,
  #                           `ftp://`, `ftps://`, `sftp://`, `file://<abs-path>`,
  #                           `gh://owner/repo@ref:path`, `oci://ref[?path=glob]`,
  #                           and bare local paths. A `#sha256=<hex>` fragment is
  #                           verified automatically after download (unless
  #                           `--sha256 none`).
  #   --installer-dir <dir>   Use `<dir>` as `work_dir` (persistent; caller owns
  #                           cleanup). Orthogonal to all output flags.
  #   --binary-src <spec>     Suffix-path match inside `asset/` (whole-component
  #                           boundary; ambiguous match → error). Repeatable. For
  #                           non-archives, `asset/` contains one file (`<basename>`);
  #                           omit to install it directly, or give a matching spec.
  #                           Requires `--binary-dest`.
  #   --binary-dest <path>    Install matched or auto-discovered binary/binaries via
  #                           `install__copy_bin` (sets executable bit). Repeatable.
  #   --file-src <spec>       Suffix-path match inside `asset/` (whole-component
  #                           boundary; ambiguous match → error). Repeatable. Required
  #                           for archives (no auto-discovery). For non-archives,
  #                           omit to install `asset/<basename>` directly.
  #                           Requires `--file-dest`.
  #   --file-dest <path>      Install matched file(s) via plain copy. Repeatable.
  #   --chmod-exec <spec>     Suffix-path match inside `asset/`; sets exec bit in
  #                           place without copying. Repeatable. Useful for running
  #                           a tool from `work_dir` during installation (tmpdir
  #                           persists until script exit).
  #   --header <H>            HTTP/FTP request header; repeatable.
  #   --netrc-file <path>     netrc file for HTTP Basic / FTP / SFTP auth.
  #   --sha256 <hex|none>     64-char hex: verify the downloaded asset against this
  #                           hash. `none`: suppress all sha256 checks (URI fragment,
  #                           sidecar, and explicit hex). GPG is unaffected.
  #   --sidecar <uri>         URI of a checksum file containing the asset's sha256.
  #                           Same `--header` and `--netrc` args apply. Formats:
  #                           `sha256sum` multi-entry (`<hex>  <filename>` or
  #                           `<hex> *<filename>`) matched by asset name, or raw
  #                           single-hash (one line, one field). Hard-fails on
  #                           mismatch or missing entry. Cannot be combined with
  #                           `--sha256 none`.
  #   --gpg-key <uri>         URI of the GPG public key; enables GPG verification of
  #                           the downloaded asset itself.
  #   --gpg-sig <uri>         URI of the detached GPG signature for the asset.
  #                           Default: the asset `<uri>` with `.asc` appended.
  #   --sidecar-gpg-key <uri> URI of the GPG public key used to verify the
  #                           `--sidecar` checksum file itself (independent of, and
  #                           combinable with, `--gpg-key`/`--gpg-sig`). Requires
  #                           `--sidecar`.
  #   --sidecar-gpg-sig <uri> URI of the detached GPG signature for the `--sidecar`
  #                           file. Default: the `--sidecar` URI with `.asc` appended.
  #   --filename <name>       Override the URI basename for `archive/` placement
  #                           and sidecar hash lookup. Does not affect the extracted
  #                           tree layout under `asset/`.
  #   --owner-group <id>      Call `install__track_internal_path` for each installed
  #                           path (binary and file installs only).
  #   --retry <n>             Re-download and re-verify up to `<n>` times on any
  #                           sha256 mismatch (URI fragment, `--sha256`, or
  #                           `--sidecar`). Does not retry GPG failures. Default: `3`.
  #
  # `--binary-src` requires `--binary-dest`; `--file-src` requires `--file-dest`.
  #
  # Stdout:
  #   - `--binary-dest` given: one absolute installed binary path per line, in
  #     `--binary-src` order (or auto-discovery order when N=0).
  #   - `--file-dest` given: one absolute installed file path per line, in
  #     `--file-src` order.
  #   - Both given: binary paths first, then file paths.
  #   - Neither given: the `work_dir/asset` directory path (one line).
  #
  # Returns: 0 on success, 1 on any failure (bad args, download, hash mismatch, GPG, extract, install).
  local _uri=""
  local _installer_dir="" _filename="" _owner_group="" _netrc_file=""
  local _sha256_spec="" _sidecar_uri="" _gpg_key_uri="" _gpg_sig_uri=""
  local _sidecar_gpg_key_uri="" _sidecar_gpg_sig_uri=""
  local _retry=3
  local -a _headers=() _binary_src=() _binary_dest=() _file_src=() _file_dest=() _chmod_exec_specs=()

  if [[ $# -gt 0 && "$1" != --* ]]; then
    _uri="$1"
    shift
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --installer-dir)
        _installer_dir="$2"
        shift 2
        ;;
      --binary-src)
        _binary_src+=("$2")
        shift 2
        ;;
      --binary-dest)
        _binary_dest+=("$2")
        shift 2
        ;;
      --file-src)
        _file_src+=("$2")
        shift 2
        ;;
      --file-dest)
        _file_dest+=("$2")
        shift 2
        ;;
      --chmod-exec)
        _chmod_exec_specs+=("$2")
        shift 2
        ;;
      --header)
        _headers+=("$2")
        shift 2
        ;;
      --netrc-file)
        _netrc_file="$2"
        shift 2
        ;;
      --sha256)
        _sha256_spec="$2"
        shift 2
        ;;
      --sidecar)
        _sidecar_uri="$2"
        shift 2
        ;;
      --gpg-key)
        _gpg_key_uri="$2"
        shift 2
        ;;
      --gpg-sig)
        _gpg_sig_uri="$2"
        shift 2
        ;;
      --sidecar-gpg-key)
        _sidecar_gpg_key_uri="$2"
        shift 2
        ;;
      --sidecar-gpg-sig)
        _sidecar_gpg_sig_uri="$2"
        shift 2
        ;;
      --filename)
        _filename="$2"
        shift 2
        ;;
      --owner-group)
        _owner_group="$2"
        shift 2
        ;;
      --retry)
        _retry="$2"
        shift 2
        ;;
      *)
        logging__error "unknown option '$1'."
        return 1
        ;;
    esac
  done

  # ── Validate ──────────────────────────────────────────────────────────────
  [[ -n "$_uri" ]] || {
    logging__error "URI is required."
    return 1
  }

  local _sha256_none=false _sha256_hex=""
  case "$_sha256_spec" in
    "") ;;
    none) _sha256_none=true ;;
    *)
      if [[ "$_sha256_spec" =~ ^[0-9a-fA-F]{64}$ ]]; then
        _sha256_hex="${_sha256_spec,,}"
      else
        logging__error "--sha256 accepts a 64-char hex or 'none', got '${_sha256_spec}'."
        return 1
      fi
      ;;
  esac
  "$_sha256_none" && [[ -n "$_sidecar_uri" ]] && {
    logging__error "--sha256 none cannot be combined with --sidecar."
    return 1
  }
  [[ -n "$_sidecar_gpg_key_uri" && -z "$_sidecar_uri" ]] && {
    logging__error "--sidecar-gpg-key requires --sidecar."
    return 1
  }

  local _nbsrc="${#_binary_src[@]}" _nbdest="${#_binary_dest[@]}"
  local _nfsrc="${#_file_src[@]}" _nfdest="${#_file_dest[@]}"
  [[ "$_nbsrc" -gt 0 && "$_nbdest" -gt 1 && "$_nbsrc" -ne "$_nbdest" ]] && {
    logging__error "${_nbsrc} --binary-src but ${_nbdest} --binary-dest (must be equal or use 1 --binary-dest for all)."
    return 1
  }
  [[ "$_nfsrc" -gt 0 && "$_nfdest" -gt 1 && "$_nfsrc" -ne "$_nfdest" ]] && {
    logging__error "${_nfsrc} --file-src but ${_nfdest} --file-dest (must be equal or use 1 --file-dest for all)."
    return 1
  }
  [[ "$_nbsrc" -gt 0 && "$_nbdest" -eq 0 ]] && {
    logging__error "--binary-src requires --binary-dest."
    return 1
  }
  [[ "$_nfsrc" -gt 0 && "$_nfdest" -eq 0 ]] && {
    logging__error "--file-src requires --file-dest."
    return 1
  }

  # ── Auth args ─────────────────────────────────────────────────────────────
  local -a _auth_args=()
  local _h
  for _h in "${_headers[@]}"; do _auth_args+=(--header "$_h"); done
  [[ -n "$_netrc_file" ]] && _auth_args+=(--netrc-file "$_netrc_file")

  # ── Work dir and asset name ───────────────────────────────────────────────
  local _split _base_uri _frag
  _split="$(_uri__split_frag "$_uri")"
  _base_uri="$(printf '%s\n' "$_split" | head -n1)"
  _frag="$(printf '%s\n' "$_split" | tail -n1)"
  local _asset_name="${_filename:-$(_uri__safe_basename "$_base_uri")}"

  local _work_dir
  if [[ -n "$_installer_dir" ]]; then
    _work_dir="$_installer_dir"
    mkdir -p "$_work_dir"
    local _sd
    for _sd in archive asset sidecar gpg-sig gpg-key sidecar-gpg-sig sidecar-gpg-key; do
      rm -rf "${_work_dir:?}/${_sd}"
    done
  else
    _work_dir="$(file__mktmpdir "uri-fetch-asset")"
  fi

  local _archive_dir="${_work_dir}/archive"
  local _asset_dir="${_work_dir}/asset"
  mkdir -p "$_archive_dir" "$_asset_dir"
  local _dl_path="${_archive_dir}/${_asset_name}"

  # ── Sidecar transaction state ─────────────────────────────────────────────
  local _sidecar_hash="" _sidecar_file="" _sc_base="" _sc_name=""
  if [[ -n "$_sidecar_uri" ]] && ! "$_sha256_none"; then
    local _sidecar_dir="${_work_dir}/sidecar"
    mkdir -p "$_sidecar_dir"
    _sc_base="$(printf '%s\n' "$(_uri__split_frag "$_sidecar_uri")" | head -n1)"
    _sc_name="$(_uri__safe_basename "$_sc_base")"
    _sidecar_file="${_sidecar_dir}/${_sc_name}"
  fi

  local _frag_sha=""
  ! "$_sha256_none" && _frag_sha="$(_uri__frag_sha256 "$_frag")"
  local _cls
  _cls="$(uri__classify "$_uri" 2> /dev/null)" || true

  # ── Retry loop: re-download on sha256 mismatch ────────────────────────────
  if "$_sha256_none"; then
    logging__warn "sha256 verification skipped for '${_asset_name}'."
  elif [[ -z "$_frag_sha" && -z "$_sha256_hex" && -z "$_sidecar_uri" && -z "$_gpg_key_uri" ]]; then
    logging__debug "no integrity verification configured for '${_asset_name}'."
  fi

  local _attempt=0
  while true; do
    _attempt=$((_attempt + 1))

    if [[ -n "$_sidecar_uri" ]] && ! "$_sha256_none"; then
      local _sidecar_attempt=0 _sidecar_refetch=false
      while true; do
        _sidecar_attempt=$((_sidecar_attempt + 1))
        rm -f "$_sidecar_file"
        logging__download "Fetching checksum sidecar from '${_sc_base}'"
        _uri__download_to "$_sidecar_uri" "$_sidecar_file" "${_auth_args[@]}"
        local _rc=$?
        [[ $_rc == 0 ]] || {
          logging__error "failed to download sidecar from '${_sc_base}'."
          return "$_rc"
        }
        _sidecar_hash="$(_uri__sidecar_hash "$_asset_name" "$_sidecar_file")"
        if [[ "$_sidecar_hash" =~ ^[0-9a-fA-F]{64}$ ]]; then
          break
        fi
        _sidecar_refetch=false
        if [[ "$_sidecar_attempt" -eq 1 ]] && _uri__sidecar_content_may_be_transient "$_sidecar_file"; then
          _sidecar_refetch=true
        fi
        if [ "$_sidecar_refetch" = true ]; then
          logging__warn "checksum sidecar '${_sc_base}' was empty or looked like an HTML response; refetching once."
          continue
        fi
        logging__error "could not extract a valid SHA-256 hash for '${_asset_name}' from sidecar '${_sc_base}'."
        return 1
      done

      if [[ -n "$_sidecar_gpg_key_uri" ]]; then
        local _sc_sig_uri="${_sidecar_gpg_sig_uri:-${_sidecar_uri}.asc}"
        _uri__gpg_verify "$_sidecar_file" "$_sidecar_gpg_key_uri" "$_sc_sig_uri" \
          "${_work_dir}/sidecar-gpg-sig" "${_work_dir}/sidecar-gpg-key" "sidecar GPG" "${_auth_args[@]}" || return $?
      fi
    fi

    logging__download "Fetching '${_asset_name}' from '${_base_uri}'"
    _uri__download_to "$_uri" "$_dl_path" "${_auth_args[@]}"
    local _rc=$?
    [[ $_rc == 0 ]] || {
      logging__error "failed to download '${_asset_name}' from '${_base_uri}'."
      return "$_rc"
    }

    if "$_sha256_none"; then break; fi

    local _mismatch=false
    if [[ -n "$_frag_sha" && "$_cls" != "oci" ]]; then
      verify__sha "$_dl_path" "$_frag_sha" 2> /dev/null || _mismatch=true
    fi
    if ! "$_mismatch" && [[ -n "$_sha256_hex" ]]; then
      verify__sha "$_dl_path" "$_sha256_hex" 2> /dev/null || _mismatch=true
    fi
    if ! "$_mismatch" && [[ -n "$_sidecar_hash" ]]; then
      verify__sha "$_dl_path" "$_sidecar_hash" 2> /dev/null || _mismatch=true
    fi
    if ! "$_mismatch"; then break; fi

    if [[ "$_attempt" -ge "$_retry" ]]; then
      # Emit full verify output for the final failure to surface the mismatch details.
      [[ -n "$_frag_sha" && "$_cls" != "oci" ]] && verify__sha "$_dl_path" "$_frag_sha" 2>&1 || true
      [[ -n "$_sha256_hex" ]] && verify__sha "$_dl_path" "$_sha256_hex" 2>&1 || true
      [[ -n "$_sidecar_hash" ]] && verify__sha "$_dl_path" "$_sidecar_hash" 2>&1 || true
      logging__error "sha256 mismatch for '${_asset_name}' after ${_retry} attempt(s)."
      return 1
    fi
    logging__warn "sha256 mismatch on attempt ${_attempt}/${_retry} — re-downloading '${_asset_name}'..."
    rm -f "$_dl_path"
  done

  # ── GPG verification ──────────────────────────────────────────────────────
  if [[ -n "$_gpg_key_uri" ]]; then
    local _sig_uri="${_gpg_sig_uri:-${_base_uri}.asc}"
    _uri__gpg_verify "$_dl_path" "$_gpg_key_uri" "$_sig_uri" \
      "${_work_dir}/gpg-sig" "${_work_dir}/gpg-key" "GPG" "${_auth_args[@]}" || return $?
  fi

  # ── Archive detection and extraction ──────────────────────────────────────
  local _filetype _is_archive=false
  _filetype="$(file__detect_type "$_dl_path")"
  case "$_filetype" in
    gzip | xz | bzip2 | zip) _is_archive=true ;;
  esac

  if "$_is_archive"; then
    logging__install "Extracting '${_asset_name}'..."
    local _extract_name
    case "$_filetype" in
      gzip) _extract_name="asset.tar.gz" ;;
      xz) _extract_name="asset.tar.xz" ;;
      bzip2) _extract_name="asset.tar.bz2" ;;
      zip) _extract_name="asset.zip" ;;
      *) _extract_name="$_asset_name" ;;
    esac
    file__extract_archive "$_dl_path" "$_asset_dir" "$_extract_name"
    local _rc=$?
    [[ $_rc == 0 ]] || {
      logging__error "extraction of '${_asset_name}' failed."
      return "$_rc"
    }
  else
    mv -f "$_dl_path" "${_asset_dir}/${_asset_name}" || {
      logging__error "failed to move downloaded asset '${_asset_name}' into work directory."
      return 1
    }
  fi

  # ── chmod-exec specs ──────────────────────────────────────────────────────
  if [[ "${#_chmod_exec_specs[@]}" -gt 0 ]]; then
    local _cspec _cmatches _cm
    for _cspec in "${_chmod_exec_specs[@]}"; do
      _cmatches="$(_uri__match_binary_src "$_cspec" "$_asset_dir")"
      [[ -n "$_cmatches" ]] || {
        logging__error "--chmod-exec '${_cspec}': no match in asset directory."
        return 1
      }
      while IFS= read -r _cm; do
        [[ -n "$_cm" ]] && chmod +x "$_cm"
      done <<< "$_cmatches"
    done
  fi

  # ── Binary installation ───────────────────────────────────────────────────
  if [[ "$_nbdest" -gt 0 ]]; then
    local -a _found_srcs=() _install_names=()
    if [[ "$_nbsrc" -gt 0 ]]; then
      local _i
      for _i in "${!_binary_src[@]}"; do
        local _spec="${_binary_src[$_i]}" _found_src _mc
        _found_src="$(_uri__match_binary_src "$_spec" "$_asset_dir")"
        _mc="$(printf '%s\n' "$_found_src" | grep -c . || true)"
        [[ "$_mc" -gt 1 ]] && {
          logging__error "ambiguous --binary-src '${_spec}': ${_mc} matches in '${_asset_name}'."
          return 1
        }
        [[ -z "$_found_src" ]] && {
          logging__error "--binary-src '${_spec}' not found in '${_asset_name}'."
          return 1
        }
        _found_srcs+=("$_found_src")
        _install_names+=("$(basename "$_spec")")
      done
    elif "$_is_archive"; then
      bootstrap__find || return 1
      local _discovered _f
      _discovered="$(find "$_asset_dir" -type f -perm -u+x 2> /dev/null || true)"
      if [[ -z "$_discovered" ]]; then
        while IFS= read -r _f; do chmod +x "$_f" 2> /dev/null || true; done \
          < <(find "$_asset_dir" -type f)
        _discovered="$(find "$_asset_dir" -type f 2> /dev/null || true)"
      fi
      if [[ "$_nbdest" -eq 1 && "${_binary_dest[0]}" != */ ]]; then
        local _disc_count
        _disc_count="$(printf '%s\n' "$_discovered" | grep -c . || true)"
        [[ "$_disc_count" -ne 1 ]] && {
          logging__error "auto-discovery found ${_disc_count} executables but --binary-dest is an exact path (not a directory)."
          return 1
        }
      fi
      while IFS= read -r _f; do
        [[ -n "$_f" ]] || continue
        _found_srcs+=("$_f")
        _install_names+=("$(basename "$_f")")
      done <<< "$_discovered"
      [[ "${#_found_srcs[@]}" -eq 0 ]] && {
        logging__error "no executables found in extracted '${_asset_name}'."
        return 1
      }
    else
      _found_srcs+=("${_asset_dir}/${_asset_name}")
      _install_names+=("$_asset_name")
    fi

    local _j
    for _j in "${!_found_srcs[@]}"; do
      local _src="${_found_srcs[$_j]}" _name="${_install_names[$_j]}" _dest_spec _dest_path
      if [[ "$_nbdest" -gt 1 && "$_j" -lt "$_nbdest" ]]; then
        _dest_spec="${_binary_dest[$_j]}"
      else
        _dest_spec="${_binary_dest[0]}"
      fi
      if [[ "$_dest_spec" == */ ]]; then
        _dest_path="${_dest_spec%/}/${_name}"
      else
        _dest_path="$_dest_spec"
      fi
      mkdir -p "$(dirname "$_dest_path")"
      chmod +x "$_src" 2> /dev/null || true
      logging__install "Installing '${_name}' to '${_dest_path}'"
      install__copy_bin "$_src" "$_dest_path"
      local _rc=$?
      [[ $_rc == 0 ]] || {
        logging__error "failed to install binary '${_name}' to '${_dest_path}'."
        return "$_rc"
      }
      [[ -n "$_owner_group" ]] && install__track_internal_path "$_owner_group" "$_dest_path"
      logging__success "Installed '${_name}' → '${_dest_path}'"
      printf '%s\n' "$_dest_path"
    done
  fi

  # ── File installation ─────────────────────────────────────────────────────
  if [[ "$_nfdest" -gt 0 ]]; then
    local -a _fnd_srcs=() _fnd_names=()
    if [[ "$_nfsrc" -gt 0 ]]; then
      local _i
      for _i in "${!_file_src[@]}"; do
        local _spec="${_file_src[$_i]}" _found_src _mc
        _found_src="$(_uri__match_binary_src "$_spec" "$_asset_dir")"
        _mc="$(printf '%s\n' "$_found_src" | grep -c . || true)"
        [[ "$_mc" -gt 1 ]] && {
          logging__error "ambiguous --file-src '${_spec}': ${_mc} matches in '${_asset_name}'."
          return 1
        }
        [[ -z "$_found_src" ]] && {
          logging__error "--file-src '${_spec}' not found in '${_asset_name}'."
          return 1
        }
        _fnd_srcs+=("$_found_src")
        _fnd_names+=("$(basename "$_spec")")
      done
    elif "$_is_archive"; then
      logging__error "--file-dest requires --file-src for archive assets."
      return 1
    else
      _fnd_srcs+=("${_asset_dir}/${_asset_name}")
      _fnd_names+=("$_asset_name")
    fi

    local _k
    for _k in "${!_fnd_srcs[@]}"; do
      local _src="${_fnd_srcs[$_k]}" _name="${_fnd_names[$_k]}" _dest_spec _dest_path
      if [[ "$_nfdest" -gt 1 && "$_k" -lt "$_nfdest" ]]; then
        _dest_spec="${_file_dest[$_k]}"
      else
        _dest_spec="${_file_dest[0]}"
      fi
      if [[ "$_dest_spec" == */ ]]; then
        _dest_path="${_dest_spec%/}/${_name}"
      else
        _dest_path="$_dest_spec"
      fi
      mkdir -p "$(dirname "$_dest_path")"
      logging__install "Installing '${_name}' to '${_dest_path}'"
      cp -f "$_src" "$_dest_path" || {
        logging__error "failed to install file '${_name}' to '${_dest_path}'."
        return 1
      }
      [[ -n "$_owner_group" ]] && install__track_internal_path "$_owner_group" "$_dest_path"
      logging__success "Installed '${_name}' → '${_dest_path}'"
      printf '%s\n' "$_dest_path"
    done
  fi

  # ── No install flags: print asset dir ────────────────────────────────────
  if [[ "$_nbdest" -eq 0 && "$_nfdest" -eq 0 ]]; then
    printf '%s\n' "$_asset_dir"
  fi
  return 0
}

uri__resolve() {
  # @brief uri__resolve <input> <dest-file> [--header <H>]... [--netrc-file <path>] [--chmod <mode>] [--chmod-exec] — Materialize `<input>` to `<dest-file>`. Thin wrapper around uri__fetch_asset.
  #
  # Supports `http(s)://`, `ftp://`, `ftps://`, `sftp://`, `file://`, `gh://`, `oci://`, and
  # local paths. An optional `#sha256=<hex>` fragment in `<input>` is verified after fetch.
  # `--chmod <mode>` runs `file__chmod <mode> <dest-file>` after a successful resolve (octal e.g.
  # `600`, or symbolic e.g. `+x`). `--chmod-exec` is equivalent to `--chmod +x`.
  #
  # Args:
  #   <input>              URI, local path, or `gh://owner/repo@ref:path` shorthand.
  #   <dest-file>          Destination file path.
  #   --header <H>         HTTP request header; repeatable.
  #   --netrc-file <path>  Optional netrc file for authentication.
  #   --chmod <mode>       chmod mode applied to dest after successful resolve.
  #   --chmod-exec         Deprecated alias for `--chmod +x`.
  #
  # Stdout: install paths printed by uri__fetch_asset (typically `<dest-file>`).
  #
  # Returns: 0 on success, 1 on fetch or verification failure.
  local _input="$1" _dest="$2"
  shift 2
  local _chmod_mode=""
  local -a _fa_args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --header | --netrc-file)
        _fa_args+=("$1" "$2")
        shift 2
        ;;
      --chmod)
        _chmod_mode="$2"
        shift 2
        ;;
      --chmod-exec)
        _chmod_mode="+x"
        shift
        ;;
      *)
        logging__error "unknown option '$1'"
        return 1
        ;;
    esac
  done
  # Back-compat: historically `--chmod-exec` used `--binary-dest`, enabling archive
  # auto-discovery of executables. Preserve that behavior for modes that imply an
  # executable output.
  local _exec_mode=false
  if [[ "$_chmod_mode" == *x* || "$_chmod_mode" == *X* ]]; then
    _exec_mode=true
  elif [[ "$_chmod_mode" =~ ^0?[0-7]{3,4}$ ]]; then
    # Any execute bit set in octal (1/3/5/7) → treat as exec mode.
    local _m="${_chmod_mode#0}"
    local _u="${_m: -3:1}" _g="${_m: -2:1}" _o="${_m: -1:1}"
    case "$_u$_g$_o" in
      *1* | *3* | *5* | *7*) _exec_mode=true ;;
    esac
  fi

  if [[ "$_exec_mode" == true ]]; then
    logging__install "Resolving executable asset '${_input}' to '${_dest}'."
    uri__fetch_asset "$_input" --binary-dest "$_dest" "${_fa_args[@]}" > /dev/null
  else
    logging__install "Resolving file asset '${_input}' to '${_dest}'."
    uri__fetch_asset "$_input" --file-dest "$_dest" "${_fa_args[@]}" > /dev/null
  fi
  local _fa_rc=$?
  [[ $_fa_rc == 0 ]] || return "$_fa_rc"
  if [[ -n "$_chmod_mode" && -e "$_dest" ]]; then
    file__chmod "$_chmod_mode" "$_dest"
    local _rc=$?
    [[ $_rc == 0 ]] || {
      logging__error "file__chmod '${_chmod_mode}' failed on '${_dest}'."
      return "$_rc"
    }
  fi
  return 0
}

uri__resolve_line() {
  # @brief uri__resolve_line <input> <materialize-dir> [--header <H>]... [--netrc-file <path>] [--chmod <mode>] [--chmod-exec] — For local inputs, print the original path. For remote inputs, materialize under `<materialize-dir>` and print the resulting path.
  #
  # Args:
  #   <input>              URI or local path.
  #   <materialize-dir>    Directory used to store downloaded files for remote URIs.
  #   --header <H>         HTTP request header; repeatable.
  #   --netrc-file <path>  Optional netrc file for authentication.
  #   --chmod <mode>       chmod mode applied after a remote fetch (not local/file:// passthrough).
  #   --chmod-exec         Deprecated alias for `--chmod +x`.
  #
  # Stdout: resolved local file path.
  local _input="$1" _mdir="$2"
  shift 2
  local _chmod_mode=""
  local -a _fetch_args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --header | --netrc-file)
        _fetch_args+=("$1" "$2")
        shift 2
        ;;
      --chmod)
        _chmod_mode="$2"
        shift 2
        ;;
      --chmod-exec)
        _chmod_mode="+x"
        shift
        ;;
      *)
        logging__error "unknown option '$1'"
        return 1
        ;;
    esac
  done
  local _cls
  _cls="$(uri__classify "$_input")"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "unsupported or empty URI '${_input}'."
    return "$_rc"
  }
  case "$_cls" in
    local)
      [[ -e "$(_uri__split_frag "$_input" | head -n1)" ]] || {
        logging__error "local path not found: '${_input%%#*}'."
        return 1
      }
      printf '%s\n' "${_input%%#*}"
      ;;
    file)
      local _fp _in
      _in="$(_uri__split_frag "$_input" | head -n1)"
      _fp="$(_uri__file_url_path "$_in")"
      printf '%s\n' "$_fp"
      ;;
    http | ftp | gh | oci)
      mkdir -p "$_mdir"
      local _dest
      _dest="$(uri__dest_for_uri "$_mdir" "$_input")"
      logging__download "Fetching remote URI '${_input}' into '${_dest}'."
      uri__fetch_asset "$_input" --file-dest "$_dest" "${_fetch_args[@]}" > /dev/null
      local _fa_rc=$?
      [[ $_fa_rc == 0 ]] || return "$_fa_rc"
      if [[ -n "$_chmod_mode" && -e "$_dest" ]]; then
        file__chmod "$_chmod_mode" "$_dest"
        local _rc=$?
        [[ $_rc == 0 ]] || {
          logging__error "file__chmod '${_chmod_mode}' failed on '${_dest}'."
          return "$_rc"
        }
      fi
      printf '%s\n' "$_dest"
      ;;
    *)
      logging__error "unsupported URI class '${_cls}' for '${_input}'."
      return 1
      ;;
  esac
  return 0
}

uri__resolve_list() {
  # @brief uri__resolve_list <newline-separated-list> <materialize-dir> [--header <H>]... [--netrc-file <path>] [--chmod <mode>] [--chmod-exec] — Resolve each non-empty line of `<newline-separated-list>` and print one output path per line.
  #
  # Args:
  #   <newline-separated-list>  Newline-separated list of URIs or local paths.
  #   <materialize-dir>         Directory used to store downloaded files for remote URIs.
  #   --header <H>              HTTP request header; repeatable.
  #   --netrc-file <path>       Optional netrc file for authentication.
  #   --chmod <mode>            chmod mode applied after each remote fetch (see uri__resolve_line).
  #   --chmod-exec              Deprecated alias for `--chmod +x`.
  #
  # Stdout: one resolved local file path per non-empty input line.
  local _list="$1" _mdir="$2"
  shift 2
  local _line _out
  while IFS= read -r _line || [[ -n "${_line}" ]]; do
    [[ -z "${_line//[[:space:]]/}" ]] && continue
    logging__install "Resolving URI line '${_line}'."
    _out="$(uri__resolve_line "$_line" "$_mdir" "$@")"
    local _rc=$?
    [[ $_rc == 0 ]] || {
      logging__error "failed to resolve URI line '${_line}'."
      return "$_rc"
    }
    printf '%s\n' "$_out"
  done <<< "$(printf '%s\n' "$_list")"
  return 0
}
