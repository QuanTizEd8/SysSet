# shellcheck shell=bash
# HTTP fetch helpers with retry support using curl or wget.
#
# Auto-detects `curl` or `wget` (installs via `ospkg` if absent). All fetch
# functions support configurable retries, delay between attempts, and custom
# HTTP headers.

_NET__FETCH_TOOL=

_net__hdrs_with_default_ua() {
  # @brief _net__hdrs_with_default_ua <hdr_block> — Return `<hdr_block>` unchanged when it already contains a `User-Agent` header; otherwise prepend `User-Agent: devfeats`.
  #
  # GitHub's raw-content CDN and some other hosts return HTTP 403 for requests
  # carrying curl's default `curl/<version>` User-Agent. This helper ensures a
  # recognisable User-Agent is always present without overriding a caller-supplied
  # one.
  #
  # Args:
  #   <hdr_block>  Newline-separated list of HTTP headers (may be empty).
  #
  # Stdout: the original block if a User-Agent header is present, or the block
  #         with `User-Agent: devfeats` prepended as the first line.
  local _net__ua_in="$1"
  if printf '%s\n' "$_net__ua_in" | grep -qi '^user-agent:'; then
    printf '%s' "$_net__ua_in"
  else
    printf '%s%s' "User-Agent: devfeats
" "$_net__ua_in"
  fi
}

_net__fetch__persistent_http_status() {
  # @brief _net__fetch__persistent_http_status <status> — Return success only for responses that cannot be repaired by retrying an unchanged request.
  #
  # Fetches are idempotent. Unknown failures, including 404, redirects, and
  # unlisted 4xx/5xx statuses, may result from CDN propagation, proxies, or
  # registry publication and must therefore be retried.
  case "$1" in
    400 | 401 | 405 | 406 | 407 | 410 | 411 | 413 | 414 | 415 | 416 | 422 | 426 | 428 | 431 | 451) return 0 ;;
    *) return 1 ;;
  esac
}

_net__fetch__success_http_status() {
  # @brief _net__fetch__success_http_status <status> — Return success for a completed transfer or a successful HTTP response.
  case "$1" in
    # 000 is curl's status for non-HTTP protocols such as FTP. A 3xx response
    # is not a completed download: with -L, curl/wget follow redirects and a
    # final 3xx has no usable target.
    000 | 2[0-9][0-9]) return 0 ;;
    *) return 1 ;;
  esac
}

_net__fetch__persistent_curl_error() {
  # @brief _net__fetch__persistent_curl_error <exit_code> <stderr_file> [<num_redirects>] — Return success only for curl failures known to be local/configuration errors.
  #
  # All other curl failures are retried. In particular, a generic TLS handshake
  # error is ambiguous and must be retried; only clear certificate diagnostics
  # are excluded. Remote-peer certificate failures behind a redirect are treated
  # as retryable: a redirect pool (e.g. mirror.ctan.org) resolves each request
  # to a different backend, so retrying the original URL may reach a valid one.
  local _rc="$1" _stderr_file="$2" _num_redirects="${3:-0}"
  case "$_rc" in
    # Unsupported/malformed options and URLs, local file/resource failures,
    # redirect loops, and fixed local TLS/authentication configuration errors.
    1 | 2 | 3 | 4 | 23 | 26 | 27 | 37 | 42 | 43 | 45 | 47 | 48 | 49 | 53 | 54 | 58 | 59 | 63 | 65 | 66 | 67 | 89 | 90 | 91 | 93 | 94 | 98 | 99 | 100 | 101) return 0 ;;
    60)
      # Peer certificate could not be authenticated. Direct → the origin's own
      # cert is genuinely untrusted (fail fast); behind a redirect → a varying
      # mirror-pool backend, so retry.
      [ "${_num_redirects:-0}" -gt 0 ] 2> /dev/null && return 1
      return 0
      ;;
    35)
      # Generic TLS error: fail fast only on a clear certificate diagnostic, and
      # only when not behind a redirect (pool backends vary per request).
      [ "${_num_redirects:-0}" -gt 0 ] 2> /dev/null && return 1
      if grep -Eiq 'certificate problem|certificate verify failed|unable to get local issuer|self[ -]signed certificate|no alternative certificate subject name matches|peer certificate' "$_stderr_file"; then
        return 0
      fi
      ;;
  esac
  return 1
}

_net__fetch__persistent_wget_error() {
  # @brief _net__fetch__persistent_wget_error <exit_code> <status> [<num_redirects>] — Return success only for wget failures known to be local/configuration errors.
  #
  # GNU wget uses exit 4 for network errors while BusyBox commonly collapses
  # failures to exit 1. Both, and every other unrecognised failure, are retried
  # by default. HTTP responses are handled via their final status.
  local _rc="$1" _status="$2" _num_redirects="${3:-0}"
  _net__fetch__persistent_http_status "$_status" && return 0
  case "$_rc" in
    # Command-line parse, local file I/O, and authentication.
    2 | 3 | 6) return 0 ;;
    5)
      # SSL verification failure. Direct → the origin's cert is untrusted (fail
      # fast); behind a redirect → a varying mirror-pool backend, so retry.
      [ "${_num_redirects:-0}" -gt 0 ] 2> /dev/null && return 1
      return 0
      ;;
  esac
  return 1
}

_net__fetch__http_status_from_headers() {
  # @brief _net__fetch__http_status_from_headers <headers_file> — Return the final HTTP status observed in a response trace.
  awk '$1 ~ /^HTTP\/[0-9.]+$/ && $2 ~ /^[0-9][0-9][0-9]$/ { status = $2 } END { print status + 0 }' "$1" 2> /dev/null
}

_net__fetch__num_redirects_from_headers() {
  # @brief _net__fetch__num_redirects_from_headers <headers_file> — Count 3xx responses in a response trace (a proxy for redirects followed).
  #
  # curl exposes %{num_redirects} directly; wget does not, but its -S trace lists
  # every response header including each 3xx redirect hop, so counting 3xx status
  # lines yields the number of redirects followed.
  awk '$1 ~ /^HTTP\/[0-9.]+$/ && $2 ~ /^3[0-9][0-9]$/ { n++ } END { print n + 0 }' "$1" 2> /dev/null
}

_net__fetch__retry_after_seconds() {
  # @brief _net__fetch__retry_after_seconds <headers_file> — Convert the last Retry-After header to seconds, when possible.
  local _headers_file="$1" _value _now _when
  # wget's -S trace indents every header line with leading whitespace, so the
  # match must tolerate it (curl's -D dump is unindented). The value capture
  # strips the leading label and any surrounding whitespace regardless.
  _value="$(awk 'tolower($0) ~ /^[[:space:]]*retry-after:/ { sub(/^[[:space:]]*[^:]*:[[:space:]]*/, ""); gsub(/\r/, ""); sub(/[[:space:]]+$/, ""); value = $0 } END { print value }' "$_headers_file" 2> /dev/null)"
  [ -n "$_value" ] || return 1
  if [[ "$_value" =~ ^[0-9]+$ ]]; then
    printf '%s' "$_value"
    return 0
  fi
  _now="$(date -u +%s 2> /dev/null)" || return 1
  _when="$(date -u -d "$_value" +%s 2> /dev/null)" ||
    _when="$(date -j -f '%a, %d %b %Y %H:%M:%S %Z' "$_value" +%s 2> /dev/null)" || return 1
  if [ "$_when" -gt "$_now" ]; then
    printf '%s' "$((_when - _now))"
  else
    printf '0'
  fi
}

net__fetch_with_retry() {
  # @brief net__fetch_with_retry [--retries N] [--delay N] [--bail-on CODE] [--retry-if FUNCTION] <cmd...> — Run `<cmd>` up to N times with a delay between failures (default: 60 retries, 5s delay).
  #
  # Does NOT require ospkg.bash. Prefer net__fetch_url_stdout / net__fetch_url_file
  # for curl/wget downloads; those handle tool detection, --compressed, and
  # retry-by-default classification automatically. Use this function only for commands
  # that are not curl/wget.
  #
  # Args:
  #   --retries N      Maximum number of attempts (default: 60, or DEVFEATS_NET_FETCH_RETRIES).
  #   --delay N        Seconds to wait between failures (default: 5, or DEVFEATS_NET_FETCH_DELAY).
  #   --bail-on CODE   If the command exits with CODE, stop immediately without
  #                    retrying (use for non-transient configuration errors).
  #   --retry-if FUNCTION
  #                    Retry only when FUNCTION <exit-code> <stderr-file>
  #                    returns success. When supplied, command stderr is
  #                    captured for classification and replayed unchanged.
  #   <cmd...>         Command and arguments to run.
  #
  # Returns: 0 on success, 1 after all retries exhausted.
  local _max="${DEVFEATS_NET_FETCH_RETRIES:-60}" _delay="${DEVFEATS_NET_FETCH_DELAY:-5}" _bail_on="" _retry_if="" _xt=false
  case "$-" in *x*) _xt=true ;; esac
  { set +x; } 2> /dev/null
  while [ $# -gt 0 ]; do
    case "$1" in
      --retries)
        _max="$2"
        shift 2
        ;;
      --delay)
        _delay="$2"
        shift 2
        ;;
      --bail-on)
        _bail_on="$2"
        shift 2
        ;;
      --retry-if)
        _retry_if="$2"
        shift 2
        ;;
      --)
        shift
        break
        ;;
      *) break ;;
    esac
  done
  local _i=1 _rc=0 _attempts_used=0 _stderr_file="" _stdout_file="" _retry_allowed=true
  if [ -n "$_retry_if" ]; then
    # Capture stdout per attempt as well as stderr: a failed attempt may emit
    # partial stdout before the connection drops, and letting that flow straight
    # to the caller's capture would concatenate it with the successful retry's
    # output (e.g. git__resolve_ref's `head -1` picking a truncated SHA). Only
    # the winning (or final) attempt's stdout is replayed.
    _stderr_file="$(mktemp "${TMPDIR:-/tmp}/devfeats-net-cmd.XXXXXX")" || {
      [[ "$_xt" == true ]] && set -x
      logging__error "failed to create temporary stderr file for retry classification."
      return 1
    }
    _stdout_file="$(mktemp "${TMPDIR:-/tmp}/devfeats-net-out.XXXXXX")" || {
      rm -f "$_stderr_file"
      [[ "$_xt" == true ]] && set -x
      logging__error "failed to create temporary stdout file for retry classification."
      return 1
    }
  fi
  while [ "$_i" -le "$_max" ]; do
    _attempts_used="$_i"
    _rc=0
    _retry_allowed=true
    if [ -n "$_retry_if" ]; then
      : > "$_stderr_file"
      : > "$_stdout_file"
      "$@" > "$_stdout_file" 2> "$_stderr_file" || _rc=$?
      cat "$_stderr_file" >&2
      if ! "$_retry_if" "$_rc" "$_stderr_file" > /dev/null 2>&1; then
        _retry_allowed=false
      fi
    else
      "$@" || _rc=$?
    fi
    [ "$_rc" -eq 0 ] && {
      [ -n "$_stdout_file" ] && cat "$_stdout_file"
      _net__fetch_with_retry_cleanup "$_stdout_file" "$_stderr_file"
      [[ "$_xt" == true ]] && set -x
      return 0
    }
    [ -n "$_bail_on" ] && [ "$_rc" -eq "$_bail_on" ] && {
      [ -n "$_stdout_file" ] && cat "$_stdout_file"
      _net__fetch_with_retry_cleanup "$_stdout_file" "$_stderr_file"
      [[ "$_xt" == true ]] && set -x
      return "$_rc"
    }
    [ "$_retry_allowed" = true ] || break
    if [ "$_i" -lt "$_max" ]; then
      logging__warn "Attempt $_i/$_max failed — retrying in ${_delay}s..."
      sleep "$_delay"
    fi
    _i=$((_i + 1))
  done
  # Replay the final attempt's stdout on failure so callers still see whatever
  # the last run produced, without any accumulation across attempts.
  [ -n "$_stdout_file" ] && cat "$_stdout_file"
  _net__fetch_with_retry_cleanup "$_stdout_file" "$_stderr_file"
  logging__error "Failed after $_attempts_used attempt(s)."
  [[ "$_xt" == true ]] && set -x
  return 1
}

_net__fetch_with_retry_cleanup() {
  # @brief _net__fetch_with_retry_cleanup <stdout_file> <stderr_file> — Remove per-attempt scratch files if set.
  [ -n "${1:-}" ] && rm -f "$1"
  [ -n "${2:-}" ] && rm -f "$2"
  return 0
}

_net__umask_file_mode() {
  # @brief _net__umask_file_mode — Print the octal mode a newly created regular file receives under the current umask (0666 & ~umask), e.g. `644` under umask 022.
  printf '%o' "$((0666 & ~0$(umask)))"
}

_net__fetch_cleanup() {
  # @brief _net__fetch_cleanup <tmpdir> <payload> — Remove HTTP-fetch scratch: the temp dir and any payload staged beside the destination.
  #
  # <payload> may live inside <tmpdir> (stdout path) or beside the destination
  # (file path); removing both is safe and idempotent in either case.
  [ -n "${1:-}" ] && rm -rf "$1"
  [ -n "${2:-}" ] && rm -f "$2"
  return 0
}

_net__fetch() {
  # @brief _net__fetch <url> <dest> [--retries N] [--delay N] [--connect-timeout N] [--max-time N] [--header <H>]... [--netrc-file <path>] — Internal: download URL via curl or wget.
  #
  # <dest> is the output file path (its parent directory is created if missing),
  # or empty string for stdout output.
  # curl and wget are invoked once per attempt. The shared retry loop classifies
  # transport errors and HTTP statuses so both clients have identical behavior.
  local _url="$1" _dest="$2"
  shift 2
  local _max="${DEVFEATS_NET_FETCH_RETRIES:-60}" _delay="${DEVFEATS_NET_FETCH_DELAY:-5}" _max_delay="${DEVFEATS_NET_FETCH_MAX_DELAY:-300}" _hdrs='' _netrc='' _head=false
  local _connect_timeout="${DEVFEATS_NET_FETCH_CONNECT_TIMEOUT:-}" _max_time="${DEVFEATS_NET_FETCH_MAX_TIME:-}"
  while [ $# -gt 0 ]; do
    case "$1" in
      --retries)
        _max="$2"
        shift 2
        ;;
      --delay)
        _delay="$2"
        shift 2
        ;;
      --header)
        _hdrs="${_hdrs}${2}
"
        shift 2
        ;;
      --netrc-file)
        _netrc="$2"
        shift 2
        ;;
      --head)
        _head=true
        shift
        ;;
      --connect-timeout)
        _connect_timeout="$2"
        shift 2
        ;;
      --max-time)
        _max_time="$2"
        shift 2
        ;;
      *)
        logging__error "unknown option: '$1'"
        return 1
        ;;
    esac
  done
  _hdrs="$(_net__hdrs_with_default_ua "$_hdrs")"
  _net__ensure_fetch_tool
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to set up HTTP fetch tool."
    return "$_rc"
  }
  # Create the destination's parent directory before writing. `curl -o` / `wget
  # -O` do NOT create missing parents — they abort with "Failure writing output
  # to destination" (curl exit 23). uri__fetch_asset mkdir -p's its managed work
  # dirs before fetching, but this transport is also called directly with an
  # arbitrary dest (e.g. install-texlive's installer_dir download), so create the
  # parent here so every direct caller is hardened the same way. No-op for the
  # stdout path (empty dest).
  if [ -n "$_dest" ]; then
    file__mkdir "$(dirname "$_dest")" || {
      logging__error "failed to create parent directory for '${_dest}'."
      return 1
    }
  fi
  if ! [[ "$_max" =~ ^[0-9]+$ ]] || ! [[ "$_delay" =~ ^[0-9]+$ ]] || ! [[ "$_max_delay" =~ ^[0-9]+$ ]]; then
    logging__error "invalid HTTP retry configuration (retries='${_max}', delay='${_delay}', max-delay='${_max_delay}')."
    return 1
  fi
  if { [ -n "$_connect_timeout" ] && ! [[ "$_connect_timeout" =~ ^[0-9]+$ ]]; } ||
    { [ -n "$_max_time" ] && ! [[ "$_max_time" =~ ^[0-9]+$ ]]; }; then
    logging__error "invalid HTTP timeout configuration (connect-timeout='${_connect_timeout}', max-time='${_max_time}')."
    return 1
  fi
  [ "$_max" -gt 0 ] || _max=1

  local _tmpdir _attempt_file _headers_file _stderr_file
  _tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/devfeats-net.XXXXXX")" || {
    logging__error "failed to create temporary directory for HTTP fetch."
    return 1
  }
  _headers_file="${_tmpdir}/headers"
  _stderr_file="${_tmpdir}/stderr"
  if [ -n "$_dest" ]; then
    # Stage the payload as a sibling of the destination (its parent was created
    # above) so the successful replace is a same-filesystem atomic rename, and a
    # large download never has to fit inside a possibly-smaller $TMPDIR before
    # reaching its target volume.
    _attempt_file="$(mktemp "${_dest}.df-net.XXXXXX")" || {
      rm -rf "$_tmpdir"
      logging__error "failed to create staging file for '${_dest}'."
      return 1
    }
    # mktemp creates the staging file 0600; restore the umask-derived mode a
    # direct `curl -o`/`wget -O` would have produced (0644 under umask 022) so
    # the atomic-rename replace does not silently tighten the destination's
    # permissions relative to the pre-staging behaviour.
    chmod "$(_net__umask_file_mode)" "$_attempt_file" 2> /dev/null || true
  else
    _attempt_file="${_tmpdir}/payload"
  fi

  local _attempt=1 _rc=0 _status=000 _status_output _num_redirects=0 _retry=false _retry_delay _retry_after _h
  while [ "$_attempt" -le "$_max" ]; do
    : > "$_attempt_file"
    : > "$_headers_file"
    : > "$_stderr_file"
    _rc=0
    _status=000
    _num_redirects=0

    if [ "$_NET__FETCH_TOOL" = "curl" ]; then
      local -a _curl_args=(-fsSL --http1.1 --compressed -D "$_headers_file")
      [[ "$_head" == true ]] && _curl_args+=(-I)
      [ -n "$_connect_timeout" ] && _curl_args+=(--connect-timeout "$_connect_timeout")
      [ -n "$_max_time" ] && _curl_args+=(--max-time "$_max_time")
      [ -n "$_netrc" ] && _curl_args+=(--netrc-file "$_netrc")
      while IFS= read -r _h; do
        [ -z "$_h" ] && continue
        _curl_args+=(-H "$_h")
      done <<< "$_hdrs"
      _status_output="$(curl "${_curl_args[@]}" -w '%{http_code} %{num_redirects}' -o "$_attempt_file" "$_url" 2> "$_stderr_file")" || _rc=$?
      read -r _status _num_redirects _ <<< "$_status_output"
      [[ "$_status" =~ ^[0-9]{3}$ ]] || _status=000
      [[ "$_num_redirects" =~ ^[0-9]+$ ]] || _num_redirects=0
    elif [ "$_NET__FETCH_TOOL" = "wget" ]; then
      local -a _wget_args=(-q -S -O "$_attempt_file")
      [[ "$_head" == true ]] && _wget_args+=(--spider)
      [ -n "${_max_time:-$_connect_timeout}" ] && _wget_args+=("--timeout=${_max_time:-$_connect_timeout}")
      [ -n "$_netrc" ] && _wget_args+=("--netrc-file=${_netrc}")
      while IFS= read -r _h; do
        [ -z "$_h" ] && continue
        _wget_args+=("--header=${_h}")
      done <<< "$_hdrs"
      wget "${_wget_args[@]}" "$_url" 2> "$_stderr_file" || _rc=$?
      _status="$(_net__fetch__http_status_from_headers "$_stderr_file")"
      [[ "$_status" =~ ^[0-9]{3}$ ]] || _status=000
      _num_redirects="$(_net__fetch__num_redirects_from_headers "$_stderr_file")"
      [[ "$_num_redirects" =~ ^[0-9]+$ ]] || _num_redirects=0
    else
      _net__fetch_cleanup "$_tmpdir" "$_attempt_file"
      logging__error "no HTTP fetch tool available (curl/wget missing after bootstrap)."
      return 1
    fi

    if [ "$_rc" -eq 0 ] && _net__fetch__success_http_status "$_status"; then
      if [ -n "$_dest" ]; then
        if mv -f "$_attempt_file" "$_dest"; then
          :
        else
          _rc=$?
          _net__fetch_cleanup "$_tmpdir" "$_attempt_file"
          logging__error "failed to move fetched content to '${_dest}' (exit ${_rc})."
          return "$_rc"
        fi
      else
        if cat "$_attempt_file"; then
          :
        else
          _rc=$?
          _net__fetch_cleanup "$_tmpdir" "$_attempt_file"
          logging__error "failed to write fetched content for '${_url}' (exit ${_rc})."
          return "$_rc"
        fi
      fi
      _net__fetch_cleanup "$_tmpdir" "$_attempt_file"
      return 0
    fi

    [ "$_rc" -eq 0 ] && _rc=22
    _retry=true
    _net__fetch__persistent_http_status "$_status" && _retry=false
    if [ "$_NET__FETCH_TOOL" = "curl" ]; then
      _net__fetch__persistent_curl_error "$_rc" "$_stderr_file" "$_num_redirects" && _retry=false
    else
      _net__fetch__persistent_wget_error "$_rc" "$_status" "$_num_redirects" && _retry=false
    fi

    if [ "$_retry" = true ] && [ "$_attempt" -lt "$_max" ]; then
      _retry_delay="$_delay"
      if [ "$_NET__FETCH_TOOL" = "curl" ]; then
        _retry_after="$(_net__fetch__retry_after_seconds "$_headers_file" 2> /dev/null)" || _retry_after=''
      else
        _retry_after="$(_net__fetch__retry_after_seconds "$_stderr_file" 2> /dev/null)" || _retry_after=''
      fi
      [ -n "$_retry_after" ] && _retry_delay="$_retry_after"
      [ "$_retry_delay" -gt "$_max_delay" ] && _retry_delay="$_max_delay"
      logging__warn "HTTP fetch attempt ${_attempt}/${_max} for '${_url}' failed (exit ${_rc}, status ${_status}); retrying in ${_retry_delay}s."
      sleep "$_retry_delay"
      _attempt=$((_attempt + 1))
      continue
    fi
    break
  done

  local _error_summary=''
  if [ "$_status" = 000 ] && [ -s "$_stderr_file" ]; then
    _error_summary="$(awk 'NF { line = $0 } END { gsub(/\r/, "", line); print line }' "$_stderr_file")"
  fi
  _net__fetch_cleanup "$_tmpdir" "$_attempt_file"
  if [ -n "$_dest" ]; then
    logging__error "failed to fetch '${_url}' to '${_dest}' with ${_NET__FETCH_TOOL} (exit ${_rc}, status ${_status})."
  else
    logging__error "failed to fetch '${_url}' with ${_NET__FETCH_TOOL} (exit ${_rc}, status ${_status})."
  fi
  [ -n "$_error_summary" ] && logging__error "${_NET__FETCH_TOOL} error: ${_error_summary}"
  return "$_rc"
}

net__fetch_url_stdout() {
  # @brief net__fetch_url_stdout <url> [--retries N] [--delay N] [--connect-timeout N] [--max-time N] [--header <H>]... [--netrc-file <path>] — Download `<url>` to stdout with retries. Auto-detects curl/wget.
  #
  # Both curl and wget retry by default, excluding only certainly persistent
  # local/request failures. Calls
  # _net__ensure_fetch_tool automatically if not already initialised.
  #
  # Args:
  #   <url>                URL to download.
  #   --retries N          Maximum number of attempts (default: 60, or DEVFEATS_NET_FETCH_RETRIES).
  #   --delay N            Seconds between failures (default: 5, or DEVFEATS_NET_FETCH_DELAY).
  #   --connect-timeout N  Connection timeout in seconds; overrides DEVFEATS_NET_FETCH_CONNECT_TIMEOUT.
  #   --max-time N         Per-attempt curl transfer timeout in seconds; wget maps this to its network timeout.
  #   --header <H>         Request header (e.g. `Authorization: Bearer $TOKEN`); repeatable.
  #   --netrc-file <path>  Optional netrc file for HTTP authentication.
  #
  # Env:
  #   DEVFEATS_NET_FETCH_RETRIES          Maximum attempts when --retries is omitted (default: 60).
  #   DEVFEATS_NET_FETCH_DELAY            Delay in seconds when --delay is omitted (default: 5).
  #   DEVFEATS_NET_FETCH_MAX_DELAY        Cap for server-provided Retry-After delays (default: 300).
  #   DEVFEATS_NET_FETCH_CONNECT_TIMEOUT  Connection timeout in seconds when the flag is omitted (default: unset).
  #   DEVFEATS_NET_FETCH_MAX_TIME         Curl transfer/wget network timeout in seconds when the flag is omitted (default: unset).
  #
  # Stdout: downloaded content.
  #
  # Returns: 0 on success, non-zero on HTTP error or timeout.
  local _url="$1"
  shift
  logging__download "Fetching '${_url}' to stdout."
  _net__fetch "$_url" "" "$@"
}

net__fetch_url_file() {
  # @brief net__fetch_url_file <url> <dest> [--retries N] [--delay N] [--connect-timeout N] [--max-time N] [--header <H>]... [--netrc-file <path>] — Download `<url>` to `<dest>` with retries. Auto-detects curl/wget.
  #
  # Both curl and wget retry by default, excluding only certainly persistent
  # local/request failures. Calls
  # _net__ensure_fetch_tool automatically if not already initialised.
  #
  # Args:
  #   <url>                URL to download.
  #   <dest>               Destination file path; its parent directory is created if missing.
  #   --retries N          Maximum number of attempts (default: 60, or DEVFEATS_NET_FETCH_RETRIES).
  #   --delay N            Seconds between failures (default: 5, or DEVFEATS_NET_FETCH_DELAY).
  #   --connect-timeout N  Connection timeout in seconds; overrides DEVFEATS_NET_FETCH_CONNECT_TIMEOUT.
  #   --max-time N         Per-attempt curl transfer timeout in seconds; wget maps this to its network timeout.
  #   --header <H>         Request header (e.g. `Authorization: Bearer $TOKEN`); repeatable.
  #   --netrc-file <path>  Optional netrc file for HTTP authentication.
  #
  # Env:
  #   DEVFEATS_NET_FETCH_RETRIES          Maximum attempts when --retries is omitted (default: 60).
  #   DEVFEATS_NET_FETCH_DELAY            Delay in seconds when --delay is omitted (default: 5).
  #   DEVFEATS_NET_FETCH_MAX_DELAY        Cap for server-provided Retry-After delays (default: 300).
  #   DEVFEATS_NET_FETCH_CONNECT_TIMEOUT  Connection timeout in seconds when the flag is omitted (default: unset).
  #   DEVFEATS_NET_FETCH_MAX_TIME         Curl transfer/wget network timeout in seconds when the flag is omitted (default: unset).
  #
  # Returns: 0 on success, non-zero on HTTP error or timeout.
  local _url="$1" _dest="$2"
  shift 2
  logging__download "Fetching '${_url}' to '${_dest}'."
  _net__fetch "$_url" "$_dest" "$@"
}

net__probe_url() {
  # @brief net__probe_url <url> [--retries N] [--delay N] [--connect-timeout N] [--max-time N] [--header <H>]... [--netrc-file <path>] — Probe `<url>` with a HEAD request and retry-by-default classification.
  #
  # Uses the same curl/wget selection, HTTP status classification, Retry-After
  # handling, and retry configuration as file downloads without fetching the
  # response body. Returns non-zero for permanent HTTP errors or exhausted
  # transient failures. DEVFEATS_NET_FETCH_CONNECT_TIMEOUT and
  # DEVFEATS_NET_FETCH_MAX_TIME provide defaults for the corresponding flags.
  local _url="$1"
  shift
  logging__download "Probing '${_url}'."
  _net__fetch "$_url" "" --head "$@" > /dev/null
}

_net__ensure_fetch_tool() {
  # @brief _net__ensure_fetch_tool — Detect `curl` or `wget` and set `_NET__FETCH_TOOL`; install `curl` via bootstrap if neither is found.
  #
  # Calls `bootstrap__ca_certs` after detection so every fetch that goes through
  # this helper also has a valid CA bundle. Idempotent: does nothing when
  # `_NET__FETCH_TOOL` is already set.
  #
  # snap-packaged curl (path under /snap/) runs in a sandbox that blocks most
  # outbound network connections; it is skipped in favour of wget or a bootstrapped
  # non-snap curl. See https://github.com/starship/starship/issues/5403.
  #
  # Side effects: sets `_NET__FETCH_TOOL` to `curl` or `wget`.
  # Returns: 0 on success, 1 if a required tool or CA bundle cannot be ensured.
  if [ -z "${_NET__FETCH_TOOL:-}" ]; then
    if command -v curl > /dev/null 2>&1; then
      case "$(command -v curl)" in
        /snap/*)
          logging__warn "snap-packaged curl detected at '$(command -v curl)'; skipping (sandboxed). Trying wget."
          ;;
        *)
          _NET__FETCH_TOOL=curl
          ;;
      esac
    fi
    if [ -z "${_NET__FETCH_TOOL:-}" ] && command -v wget > /dev/null 2>&1; then
      _NET__FETCH_TOOL=wget
    fi
    if [ -z "${_NET__FETCH_TOOL:-}" ]; then
      bootstrap__curl || return 1
      _NET__FETCH_TOOL=curl
    fi
  fi
  bootstrap__ca_certs
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to ensure CA certificates."
    return "$_rc"
  }
  return 0
}
