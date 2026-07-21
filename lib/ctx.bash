# shellcheck shell=bash
# Unified condition and substitution context registry.
#
# Maintains a flat `qualified=value` registry (`os.*`, `plat.*`, `feat.*`) that
# install scripts and library code populate and query.  The registry is filled
# lazily on first access from the host (`/etc/os-release`, `sw_vers`, `os.bash`,
# `ospkg__pm_key`) and from feature options (`feat.version`, `feat.method`, …).
#
# Two consumers share the same keys:
# - **Pattern expansion** — `ctx__expand_pattern` replaces `{os.id}`, `{feat.version:lower}`,
#   and nested `{cond?yes:no}` tokens in URI templates and shell strings.
# - **When evaluation** — `ctx__match_when`, `ctx__match_spec`, and `ctx__select_first`
#   evaluate YAML condition blobs via `ctx-when-eval.jq` (same semantics as manifest
#   `when:` clauses).

declare -gA _CTX__REGISTRY=()
declare -g _CTX__REGISTRY_INITIALIZED=false
declare -g _CTX__OS_RELEASE_FILE=""
declare -g _CTX__LIB_DIR
_CTX__LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

declare -g _ctx__quiet=false

_ctx__fail() {
  # @brief _ctx__fail <message> — Log an error unless `--quiet` was passed to the caller.
  #
  # Used by public matchers and `ctx__select_first` for parse/usage errors.  When
  # `_ctx__quiet` is true (set by `--quiet` on `ctx__match_*` / `ctx__select_first`),
  # the message is suppressed and the function still returns 1.
  #
  # Args:
  #   <message>  Error text passed to `logging__error`.
  #
  # Returns: 1 always.
  [[ "${_ctx__quiet}" == true ]] || logging__error "$1"
  return 1
}

ctx__reset() {
  # @brief ctx__reset — Clear the in-process context registry and lazy-init flag.
  #
  # Empties `_CTX__REGISTRY` and sets `_CTX__REGISTRY_INITIALIZED=false` so the
  # next `ctx__get` / `ctx__json` / matcher call repopulates from the host.
  # Does not reset `_CTX__OS_RELEASE_FILE` (test seam for Linux os-release path).
  #
  # Returns: 0.
  _CTX__REGISTRY=()
  _CTX__REGISTRY_INITIALIZED=false
}

ctx__set() {
  # @brief ctx__set <qualified>=<value> … — Sole write API for the context registry.
  #
  # Stores each pair in `_CTX__REGISTRY`.  Keys must be fully qualified (`os.id`,
  # `plat.pm`, `feat.version`, …).  Values are plain strings; later writes overwrite.
  # Does not trigger `_ctx__ensure_registry` — callers may pre-seed before lazy load.
  #
  # Args:
  #   <qualified>=<value>  One or more `key=value` tokens (bash word splitting applies;
  #                        values must not contain unquoted whitespace).
  #
  # Returns: 0.
  local _pair _k _v
  for _pair in "$@"; do
    _k="${_pair%%=*}"
    _v="${_pair#*=}"
    _CTX__REGISTRY["${_k}"]="${_v}"
  done
}

ctx__parse_key() {
  # @brief ctx__parse_key <qualified> — Split a pattern token into namespace, field, and optional case flavor.
  #
  # Parses keys used inside `{…}` during pattern expansion.  Only `:upper`, `:lower`,
  # and `:title` suffixes are recognised as flavors; the base key stored in the registry
  # never includes a flavor suffix.
  #
  # Args:
  #   <qualified>  Token inner text (e.g. `os.id`, `plat.kernel:lower`).
  #
  # Stdout: three lines — namespace (`os`|`plat`|`feat`), field name (`id`, `kernel`, …),
  #         and flavor (`upper`|`lower`|`title`, or empty when absent).
  #
  # Returns: 0 on success; 1 when `<qualified>` contains no `.` (not a valid key).
  local _q="$1" _ns _rest _flavor=""
  [[ "${_q}" == *.* ]] || return 1
  _ns="${_q%%.*}"
  _rest="${_q#*.}"
  case "${_rest}" in
    *:upper | *:lower | *:title)
      _flavor="${_rest##*:}"
      _rest="${_rest%:*}"
      ;;
  esac
  printf '%s\n' "${_ns}" "${_rest}" "${_flavor}"
}

ctx__get() {
  # @brief ctx__get <base-qualified> — Look up a registry value; missing keys yield empty string.
  #
  # Triggers `_ctx__ensure_registry` on first access.  Keys with a case-flavor suffix
  # (`:upper`, `:lower`, `:title`) are rejected and return empty without lookup — flavors
  # apply only in `ctx__expand_pattern`, not in direct reads.
  #
  # Args:
  #   <base-qualified>  Registry key without flavor suffix (e.g. `feat.version`, `plat.pm`).
  #
  # Stdout: stored value, or empty when the key is unset.
  #
  # Returns: 0 (including for missing keys and flavor-suffixed keys).
  local _key="$1"
  case "${_key}" in
    *:upper | *:lower | *:title) return 0 ;;
  esac
  _ctx__ensure_registry
  printf '%s' "${_CTX__REGISTRY[$_key]:-}"
}

ctx__pairs() {
  # @brief ctx__pairs — Print all registry entries as `key=value` lines.
  #
  # Iterates `_CTX__REGISTRY` in arbitrary hash order.  Does not call
  # `_ctx__ensure_registry` — only entries already present are emitted.
  #
  # Stdout: one `qualified=value` line per registry entry.
  #
  # Returns: 0.
  local _k
  for _k in "${!_CTX__REGISTRY[@]}"; do
    printf '%s=%s\n' "${_k}" "${_CTX__REGISTRY[$_k]}"
  done
}

ctx__json() {
  # @brief ctx__json — Serialize the registry to a flat JSON object.
  #
  # Triggers `_ctx__ensure_registry`, then builds a JSON object whose keys are
  # dotted qualified names and values are strings.  Used as `$ctx` input to
  # `ctx-when-eval.jq` and manifest jq filters.
  #
  # Stdout: JSON object (e.g. `{"os.id":"ubuntu","plat.pm":"apt"}`), or `{}` when empty.
  #
  # Returns: 0; non-zero if `json__query` / jq fails on non-empty registry.
  _ctx__ensure_registry
  local _k _pairs=()
  for _k in "${!_CTX__REGISTRY[@]}"; do
    _pairs+=("${_k}" "${_CTX__REGISTRY[$_k]}")
  done
  if ((${#_pairs[@]} == 0)); then
    printf '{}'
    return 0
  fi
  # shellcheck disable=SC2016  # $i and $[] are jq variables, not bash
  printf '%s\n' "${_pairs[@]}" |
    json__query -Rn '[inputs] | [range(0; length; 2) as $i | {key: .[$i], value: .[$i + 1]}] | from_entries'
}

_ctx__id_like_tokens() {
  # @brief _ctx__id_like_tokens <id_like-string> — Split `os.id_like` into lowercase word tokens.
  #
  # Normalises whitespace and emits one token per line for membership tests used by
  # `ctx__compare` and jq `id_like_has` parity.
  #
  # Args:
  #   <id_like-string>  Space-separated ID_LIKE value (may be empty).
  #
  # Stdout: one lowercased token per line; nothing when input is empty/whitespace-only.
  #
  # Returns: 0.
  local _s="${1:-}" _tok
  _s="${_s#"${_s%%[![:space:]]*}"}"
  _s="${_s%"${_s##*[![:space:]]}"}"
  [[ -n "${_s}" ]] || return 0
  for _tok in ${_s}; do
    printf '%s\n' "${_tok,,}"
  done
}

_ctx__id_like_has() {
  # @brief _ctx__id_like_has <token> <id_like-string> — Test whether `<token>` appears in ID_LIKE.
  #
  # Case-insensitive exact token match against whitespace-separated words in
  # `<id_like-string>` (same semantics as jq `id_like_has`).
  #
  # Args:
  #   <token>           Single ID token to find (e.g. `rhel`, `fedora`).
  #   <id_like-string>  Full `os.id_like` registry value.
  #
  # Returns: 0 when `<token>` is present; 1 otherwise.
  local _want="${1,,}" _actual="$2" _tok _found=false
  while IFS= read -r _tok; do
    [[ -n "${_tok}" && "${_tok}" == "${_want}" ]] && _found=true
  done < <(_ctx__id_like_tokens "${_actual}")
  [[ "${_found}" == true ]]
}

_ctx__compare_eq() {
  # @brief _ctx__compare_eq <key> <expected> <actual> — Internal `eq` comparison for `ctx__compare`.
  #
  # For `os.id_like`, `<expected>` is a single token or `|`‑separated alternates tested
  # via token membership.  For other keys, `<expected>` may be `|`‑separated alternates
  # compared case-insensitively to `<actual>`.
  #
  # Args:
  #   <key>       Registry key being compared (drives id_like handling).
  #   <expected>  Right-hand side from the condition (literal or `a|b` alternates).
  #   <actual>    Left-hand value from the registry.
  #
  # Returns: 0 when equal per key-specific rules; 1 otherwise.
  local _key="$1" _expected="$2" _actual="$3"
  if [[ "${_key}" == "os.id_like" ]]; then
    if [[ "${_expected}" == *"|"* ]]; then
      local _alt _matched=false
      IFS='|' read -ra _alts <<< "${_expected}"
      for _alt in "${_alts[@]}"; do
        _ctx__id_like_has "${_alt}" "${_actual}" && {
          _matched=true
          break
        }
      done
      [[ "${_matched}" == true ]]
      return $?
    fi
    _ctx__id_like_has "${_expected}" "${_actual}"
    return $?
  fi
  if [[ "${_expected}" == *"|"* ]]; then
    local _alt
    IFS='|' read -ra _alts <<< "${_expected}"
    for _alt in "${_alts[@]}"; do
      [[ "${_actual,,}" == "${_alt,,}" ]] && return 0
    done
    return 1
  fi
  [[ "${_actual,,}" == "${_expected,,}" ]]
}

_ctx__compare_ne() {
  # @brief _ctx__compare_ne <key> <expected> <actual> — Internal `ne` comparison for `ctx__compare`.
  #
  # Inverse of `_ctx__compare_eq` with the same `os.id_like` and `|` alternate rules.
  #
  # Args:
  #   <key>       Registry key being compared.
  #   <expected>  Right-hand side from the condition.
  #   <actual>    Left-hand value from the registry.
  #
  # Returns: 0 when not equal per key-specific rules; 1 otherwise.
  local _key="$1" _expected="$2" _actual="$3"
  if [[ "${_key}" == "os.id_like" ]]; then
    if [[ "${_expected}" == *"|"* ]]; then
      local _alt
      IFS='|' read -ra _alts <<< "${_expected}"
      for _alt in "${_alts[@]}"; do
        _ctx__id_like_has "${_alt}" "${_actual}" && return 1
      done
      return 0
    fi
    _ctx__id_like_has "${_expected}" "${_actual}" && return 1
    return 0
  fi
  if [[ "${_expected}" == *"|"* ]]; then
    local _alt
    IFS='|' read -ra _alts <<< "${_expected}"
    for _alt in "${_alts[@]}"; do
      [[ "${_actual,,}" == "${_alt,,}" ]] && return 1
    done
    return 0
  fi
  [[ "${_actual,,}" != "${_expected,,}" ]]
}

ctx__compare() {
  # @brief ctx__compare <key> <op> <expected> — Compare a registry value to an expected literal.
  #
  # Reads `<key>` via `ctx__get` and applies `<op>`.  Ordering operators delegate to
  # `ver__cmp` (semver-aware).  `os.id_like` supports only `eq` and `ne`; ordering ops
  # always fail.
  #
  # Args:
  #   <key>       Qualified registry key (e.g. `feat.version`, `os.id_like`).
  #   <op>        One of `eq`, `ne`, `lt`, `lte`, `gt`, `gte`.
  #   <expected>  Right-hand literal; `|` alternates allowed for `eq`/`ne`.
  #
  # Returns: 0 when the comparison is true; 1 when false or unsupported (logs via
  #           `_ctx__fail` unless caller set `--quiet` on a matcher).
  local _key="$1" _op="$2" _expected="$3"
  local _actual
  _actual="$(ctx__get "${_key}")"
  case "${_op}" in
    eq) _ctx__compare_eq "${_key}" "${_expected}" "${_actual}" ;;
    ne) _ctx__compare_ne "${_key}" "${_expected}" "${_actual}" ;;
    lt | lte | gt | gte)
      [[ "${_key}" == "os.id_like" ]] && return 1
      local _cmp
      _cmp="$(ver__cmp "${_actual}" "${_expected}")" || return 1
      case "${_op}" in
        lt) [[ "${_cmp}" -lt 0 ]] ;;
        lte) [[ "${_cmp}" -le 0 ]] ;;
        gt) [[ "${_cmp}" -gt 0 ]] ;;
        gte) [[ "${_cmp}" -ge 0 ]] ;;
      esac
      ;;
    *)
      _ctx__fail "unsupported op '${_op}'."
      return 1
      ;;
  esac
}

_ctx__apply_case_flavor() {
  # @brief _ctx__apply_case_flavor <flavor> <value> — Apply `:upper`, `:lower`, or `:title` to a string.
  #
  # Args:
  #   <flavor>  `upper`, `lower`, `title`, or empty/other (passthrough).
  #   <value>   Raw registry string.
  #
  # Stdout: transformed string (`title` capitalises the first character only).
  #
  # Returns: 0.
  local _flavor="$1" _value="$2"
  case "${_flavor}" in
    upper) printf '%s' "${_value^^}" ;;
    lower) printf '%s' "${_value,,}" ;;
    title)
      [[ -z "${_value}" ]] && return 0
      local _first="${_value:0:1}"
      printf '%s%s' "${_first^^}" "${_value:1}"
      ;;
    *) printf '%s' "${_value}" ;;
  esac
}

_ctx__load_linux_os() {
  # @brief _ctx__load_linux_os — Populate `os.*` keys from a Linux os-release file.
  #
  # Reads `_CTX__OS_RELEASE_FILE` when set (test seam), otherwise `/etc/os-release`.
  # Each `KEY=value` line becomes `os.<key>` (lower-case field name).  Quotes are
  # stripped from values.  When `VERSION_ID` is present, derives `os.version_id_major`
  # (segment before first `.`) and `os.version_id_mm` (major.minor prefix, or full
  # `VERSION_ID` when fewer than three dot-separated segments).
  #
  # Returns: 0 (no-op when the os-release file is missing).
  local _file="${_CTX__OS_RELEASE_FILE:-/etc/os-release}"
  if [[ ! -f "${_file}" ]]; then
    return 0
  fi
  local _key _val _qkey
  while IFS='=' read -r _key _val; do
    [[ -z "${_key-}" || "${_key}" =~ ^# ]] && continue
    _val="${_val#\"}"
    _val="${_val%\"}"
    _val="${_val#\'}"
    _val="${_val%\'}"
    _qkey="os.${_key,,}"
    ctx__set "${_qkey}=${_val}"
  done < "${_file}"
  local _vid="${_CTX__REGISTRY["os.version_id"]:-}"
  if [[ -n "${_vid}" ]]; then
    ctx__set "os.version_id_major=${_vid%%.*}"
    if [[ "${_vid}" == *.*.* ]]; then
      ctx__set "os.version_id_mm=${_vid%.*}"
    else
      ctx__set "os.version_id_mm=${_vid}"
    fi
  fi
}

_ctx__load_darwin_os() {
  # @brief _ctx__load_darwin_os — Populate `os.*` keys from `sw_vers` on macOS.
  #
  # Sets fixed `os.id=macos` and `os.id_like=macos`, plus product name, version,
  # build, and optional version extra from `sw_vers`.  Derives `os.version_id_major`
  # and `os.version_id_mm` from `productVersion` using the same rules as Linux
  # `VERSION_ID` handling.
  #
  # Returns: 0 (fields left empty when `sw_vers` is unavailable).
  local _name _vid _build _extra
  _name="$(sw_vers -productName 2> /dev/null || true)"
  _vid="$(sw_vers -productVersion 2> /dev/null || true)"
  _build="$(sw_vers -buildVersion 2> /dev/null || true)"
  _extra="$(sw_vers -productVersionExtra 2> /dev/null || true)"
  ctx__set os.id=macos
  ctx__set os.id_like=macos
  ctx__set "os.name=${_name}"
  ctx__set "os.version_id=${_vid}"
  ctx__set "os.build_id=${_build}"
  ctx__set "os.version_extra=${_extra}"
  if [[ -n "${_name}" && -n "${_vid}" ]]; then
    ctx__set "os.version=${_name} ${_vid}"
  elif [[ -n "${_name}" ]]; then
    ctx__set "os.version=${_name}"
  fi
  if [[ -n "${_vid}" ]]; then
    ctx__set "os.version_id_major=${_vid%%.*}"
    if [[ "${_vid}" == *.*.* ]]; then
      ctx__set "os.version_id_mm=${_vid%.*}"
    else
      ctx__set "os.version_id_mm=${_vid}"
    fi
  fi
}

_ctx__populate_plat() {
  # @brief _ctx__populate_plat — Populate `plat.*` keys from `os.bash` release helpers.
  #
  # Always sets `plat.kernel`, `plat.machine`, `plat.platform`, `plat.machine_release`,
  # and `plat.musl_suffix`. Optional keys are set only when the underlying helper
  # returns non-empty: `plat.kernel_gh`, `plat.kernel_macos`, `plat.kernel_osx`,
  # `plat.machine_gh`, `plat.machine_node`, `plat.machine_go`, `plat.machine_gnu`,
  # `plat.machine_bitness`, `plat.rust_triple`, `plat.libc`.
  #
  # Returns: 0.
  local _v
  ctx__set "plat.kernel=$(os__kernel)"
  ctx__set "plat.machine=$(os__arch)"
  ctx__set "plat.platform=$(os__platform)"
  _v="$(os__release_arch 2> /dev/null || os__arch)"
  ctx__set "plat.machine_release=${_v}"
  _v="$(os__release_kernel gh 2> /dev/null || true)"
  if [[ -n "${_v}" ]]; then ctx__set "plat.kernel_gh=${_v}"; fi
  _v="$(os__release_kernel macos 2> /dev/null || true)"
  if [[ -n "${_v}" ]]; then ctx__set "plat.kernel_macos=${_v}"; fi
  _v="$(os__release_kernel osx 2> /dev/null || true)"
  if [[ -n "${_v}" ]]; then ctx__set "plat.kernel_osx=${_v}"; fi
  _v="$(os__release_arch --flavor gh 2> /dev/null || true)"
  if [[ -n "${_v}" ]]; then ctx__set "plat.machine_gh=${_v}"; fi
  _v="$(os__release_arch --flavor node 2> /dev/null || true)"
  if [[ -n "${_v}" ]]; then ctx__set "plat.machine_node=${_v}"; fi
  _v="$(os__release_arch --flavor go 2> /dev/null || true)"
  if [[ -n "${_v}" ]]; then ctx__set "plat.machine_go=${_v}"; fi
  _v="$(os__release_arch --flavor gnu 2> /dev/null || true)"
  if [[ -n "${_v}" ]]; then ctx__set "plat.machine_gnu=${_v}"; fi
  _v="$(os__release_arch --flavor bitness 2> /dev/null || true)"
  if [[ -n "${_v}" ]]; then ctx__set "plat.machine_bitness=${_v}"; fi
  _v="$(os__rust_triple 2> /dev/null || true)"
  if [[ -n "${_v}" ]]; then ctx__set "plat.rust_triple=${_v}"; fi
  _v="$(os__libc 2> /dev/null || true)"
  if [[ -n "${_v}" ]]; then ctx__set "plat.libc=${_v}"; fi
  if os__has_avx2; then
    ctx__set "plat.avx2=true"
  else
    ctx__set "plat.avx2=false"
  fi
  if [[ "${_v}" == "musl" ]]; then
    ctx__set "plat.musl_suffix=-musl"
  else
    ctx__set "plat.musl_suffix="
  fi
}

_ctx__ensure_registry() {
  # @brief _ctx__ensure_registry — Lazily initialise the context registry from the host.
  #
  # No-op when `_CTX__REGISTRY_INITIALIZED` is already true.  Otherwise loads OS
  # fields (`_ctx__load_darwin_os` or `_ctx__load_linux_os`), platform keys
  # (`_ctx__populate_plat`), and package-manager metadata via `ospkg__pm_key`
  # / `ospkg__deb_arch` (`plat.pm`, and `plat.deb_arch` when set).  On PM detection
  # failure, sets `plat.pm` to empty.  Pre-seeded `ctx__set` values for the same keys are overwritten.
  #
  # Returns: 0.
  [[ "${_CTX__REGISTRY_INITIALIZED}" == true ]] && return 0
  case "$(uname -s)" in
    Darwin) _ctx__load_darwin_os ;;
    *) _ctx__load_linux_os ;;
  esac
  _ctx__populate_plat
  local _pm_key _deb_arch
  if _pm_key="$(ospkg__pm_key)"; then
    ctx__set "plat.pm=${_pm_key}"
    _deb_arch="$(ospkg__deb_arch)"
    [[ -n "${_deb_arch}" ]] && ctx__set "plat.deb_arch=${_deb_arch}"
  else
    ctx__set "plat.pm="
  fi
  _CTX__REGISTRY_INITIALIZED=true
}

_ctx__eval_pattern_cond() {
  # @brief _ctx__eval_pattern_cond <condition> — Evaluate one inline `{key op value}` pattern test.
  #
  # Parses `<condition>` as `qualified`, comparison symbol (`==`, `!=`, `>=`, `>`, `<=`, `<`),
  # and right-hand literal, then delegates to `ctx__compare`.
  #
  # Args:
  #   <condition>  Inner text of a conditional token (e.g. `feat.version>=1.0`).
  #
  # Returns: 0 when the condition is true; 1 when false or unparsable.
  local _cond="$1"
  [[ "${_cond}" =~ ^([^=!<>]+)(==|!=|>=|>|<=|<)(.+)$ ]] || return 1
  local _key="${BASH_REMATCH[1]}" _sym="${BASH_REMATCH[2]}" _val="${BASH_REMATCH[3]}"
  local _op=""
  case "${_sym}" in
    '==') _op=eq ;;
    '!=') _op=ne ;;
    '>=') _op=gte ;;
    '>') _op=gt ;;
    '<=') _op=lte ;;
    '<') _op=lt ;;
  esac
  ctx__compare "${_key}" "${_op}" "${_val}"
}

_ctx__eval_pattern_token() {
  # @brief _ctx__eval_pattern_token <token> — Expand one `{…}` inner token for pattern substitution.
  #
  # Handles three forms:
  # - Conditional — `{cond?true_branch:false_branch}` via `str__split_conditional` (branches
  #   expanded recursively).
  # - Substitution — `{namespace.field}` or `{namespace.field:flavor}`; unknown keys are
  #   left as `{token}` unchanged.
  # - Unqualified / invalid — returned as `{token}` unchanged.
  #
  # Args:
  #   <token>  Text inside a single pair of `{` `}` (no nested braces at the top level).
  #
  # Stdout: expanded substring for this token.
  #
  # Returns: 0.
  local _tok="$1"
  local _cond _tbranch _fbranch _parsed _ns _part _flavor _base _val
  if str__split_conditional "${_tok}" _cond _tbranch _fbranch; then
    if _ctx__eval_pattern_cond "${_cond}"; then
      _ctx__expand_pattern "${_tbranch}"
    else
      _ctx__expand_pattern "${_fbranch}"
    fi
    return
  fi
  mapfile -t _parsed < <(ctx__parse_key "${_tok}" 2> /dev/null || true)
  if ((${#_parsed[@]} >= 2)); then
    _ns="${_parsed[0]}"
    _part="${_parsed[1]}"
    _flavor="${_parsed[2]:-}"
    _base="${_ns}.${_part}"
    if [[ ! -v _CTX__REGISTRY["${_base}"] ]]; then
      printf '{%s}' "${_tok}"
      return 0
    fi
    _val="$(ctx__get "${_base}")"
    if [[ -n "${_flavor}" ]]; then
      _val="$(_ctx__apply_case_flavor "${_flavor}" "${_val}")"
    fi
    printf '%s' "${_val}"
    return 0
  fi
  printf '{%s}' "${_tok}"
}

_ctx__expand_pattern() {
  # @brief _ctx__expand_pattern <pattern> — Expand all `{…}` tokens in a string (internal).
  #
  # Scans `<pattern>` left-to-right.  Unbalanced `{` is copied literally.  Each closed
  # `{token}` is passed to `_ctx__eval_pattern_token`.  Assumes `_ctx__ensure_registry`
  # has already run when called from `ctx__expand_pattern`.
  #
  # Args:
  #   <pattern>  Template string (URI, path, shell fragment).
  #
  # Stdout: fully expanded string.
  #
  # Returns: 0.
  local _s="$1"
  local _result="" _i=0 _len="${#_s}"
  while [[ ${_i} -lt ${_len} ]]; do
    local _c="${_s:${_i}:1}"
    if [[ "${_c}" == '{' ]]; then
      local _after="${_s:$((_i + 1))}"
      local _cpos _brace_rc
      _cpos="$(str__find_close_brace "${_after}")"
      _brace_rc=$?
      if [[ ${_brace_rc} -ne 0 ]]; then
        _result+='{'
        _i=$((_i + 1))
        continue
      fi
      local _tok="${_after:0:${_cpos}}"
      local _expanded
      _expanded="$(_ctx__eval_pattern_token "${_tok}")"
      _result+="${_expanded}"
      _i=$((_i + _cpos + 2))
    else
      _result+="${_c}"
      _i=$((_i + 1))
    fi
  done
  printf '%s' "${_result}"
}

ctx__expand_pattern() {
  # @brief ctx__expand_pattern <pattern> — Expand qualified `{…}` tokens and conditionals.
  #
  # Public entry point for URI templates and install-time string interpolation.
  # Ensures the registry is loaded, then expands `{os.id}`, `{feat.version:lower}`,
  # `{plat.kernel==linux?-gnu:}`, and nested forms.  Missing registry keys leave the
  # original `{token}` in place.
  #
  # Args:
  #   <pattern>  Template string containing zero or more `{…}` tokens.
  #
  # Stdout: expanded string.
  #
  # Returns: 0.
  _ctx__ensure_registry
  _ctx__expand_pattern "$1"
}

_ctx__yaml_to_json() {
  # @brief _ctx__yaml_to_json <yaml-blob> — Convert a YAML when fragment to JSON via yq.
  #
  # Bootstraps yq, then pipes `<yaml-blob>` on stdin to `yq -o=json '.' -`.
  #
  # Args:
  #   <yaml-blob>  YAML text for one when group (AND map, OR list, or operator dict).
  #
  # Stdout: JSON representation of the YAML document.
  #
  # Returns: 0 on success; 2 when yq is unavailable or conversion fails.
  local _yaml="$1" _yq
  bootstrap__yq > /dev/null || return 2
  _yq="$(bootstrap__yq)"
  printf '%s' "${_yaml}" | "${_yq}" -o=json '.' - || return 2
}

_ctx__eval_when_jq() {
  # @brief _ctx__eval_when_jq <yaml-when> — Evaluate a YAML when blob against the registry via jq.
  #
  # Serialises the current registry with `ctx__json`, converts `<yaml-when>` to JSON,
  # and runs `ctx-when-eval.jq` with `$ctx` and `$when` inputs.  Semantics match
  # manifest `when:` clauses (AND maps, OR lists, operator dicts on version fields).
  #
  # Args:
  #   <yaml-when>  YAML condition document (may be empty for unconditional match).
  #
  # Returns: 0 when jq yields `true`; 1 when false; 2 on yq/jq/bootstrap failure.
  local _yaml="$1"
  local _ctx_json _when_json _result
  _ctx_json="$(ctx__json)"
  _when_json="$(_ctx__yaml_to_json "${_yaml}")" || return $?
  _result="$(json__query -L "${_CTX__LIB_DIR}" --argjson ctx "${_ctx_json}" --argjson when "${_when_json}" \
    -n -f "${_CTX__LIB_DIR}/ctx-when-eval.jq" 2> /dev/null)" || return 2
  [[ "${_result}" == "true" ]]
}

ctx__match_spec() {
  # @brief ctx__match_spec [--quiet] <yaml-and-group> — Return 0 if one AND group matches.
  #
  # Evaluates a single YAML mapping whose keys are qualified context fields and whose
  # values are literals, arrays (OR of values), or operator dicts (`gte`, `lt`, …).
  # Empty `<yaml-and-group>` is treated as unconditional (returns 0).
  #
  # Args:
  #   [--quiet]         Suppress `logging__error` from parse/compare failures.
  #   <yaml-and-group>  YAML AND-group (e.g. `plat.kernel: linux\nplat.pm: apt`).
  #
  # Returns: 0 when the group matches the current registry; 1 when false; 2 on
  #          yq/jq/bootstrap failure.
  local _ctx__quiet=false
  [[ "${1:-}" == --quiet ]] && {
    _ctx__quiet=true
    shift
  }
  local _yaml="${1:-}"
  [[ -z "${_yaml}" ]] && return 0
  _ctx__ensure_registry
  _ctx__eval_when_jq "${_yaml}"
}

ctx__match_when() {
  # @brief ctx__match_when [--quiet] <yaml-when> — Return 0 if any OR group matches.
  #
  # Evaluates YAML that is either a single AND mapping, an OR list of AND mappings,
  # or an operator/value form accepted by `ctx-when-eval.jq`.  Empty `<yaml-when>`
  # is unconditional (returns 0).
  #
  # Args:
  #   [--quiet]    Suppress `logging__error` from parse/compare failures.
  #   <yaml-when>  YAML when document (OR list and/or AND groups).
  #
  # Returns: 0 when at least one group matches; 1 when false; 2 on
  #          yq/jq/bootstrap failure.
  local _ctx__quiet=false
  [[ "${1:-}" == --quiet ]] && {
    _ctx__quiet=true
    shift
  }
  local _yaml="${1:-}"
  [[ -z "${_yaml}" ]] && return 0
  _ctx__ensure_registry
  _ctx__eval_when_jq "${_yaml}"
}

ctx__select_first() {
  # @brief ctx__select_first [--quiet] -- [<yaml-group>] [-- [<yaml-group>] …] — Return 0 on the first matching when group.
  #
  # Tests when groups in order and returns 0 on the first match.  Groups are
  # separated by `--`; each group is a single YAML AND-blob argument passed to
  # `ctx__match_spec`.  A leading `--` is required.  Trailing group after the
  # last `--` is also evaluated when no earlier group matched.
  #
  # Args:
  #   [--quiet]       Suppress error logging from `_ctx__fail`.
  #   --              Required delimiter before the first group.
  #   <yaml-group>    One AND-group per argv word; repeat `--` between groups.
  #
  # Returns: 0 when the first matching group is found; 1 when none match or when
  #           `--` is missing (logs usage error unless `--quiet`); 2 on
  #           yq/jq/bootstrap failure.
  local _ctx__quiet=false
  [[ "${1:-}" == --quiet ]] && {
    _ctx__quiet=true
    shift
  }
  [[ "${1:-}" == "--" ]] || {
    _ctx__fail "ctx__select_first requires leading '--'."
    return 1
  }
  shift
  local -a _group=()
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--" ]]; then
      if [[ ${#_group[@]} -gt 0 ]] && ctx__match_spec "${_group[0]}"; then
        return 0
      fi
      _group=()
      shift
      continue
    fi
    _group+=("$1")
    shift
  done
  [[ ${#_group[@]} -gt 0 ]] && ctx__match_spec "${_group[0]}"
}
