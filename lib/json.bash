# shellcheck shell=bash
# JSON query and manipulation helpers using jq (auto-installed via ospkg if absent).
#
# Functions read from stdin and write to stdout.

_json__ensure_json_lib_dir() {
  # _json__ensure_json_lib_dir (internal) — kept for backward compat; _JSON__LIB_DIR is always set at load time.
  return 0
}

json__from_yaml() {
  # @brief json__from_yaml <file> — Convert a YAML or JSON file to canonical JSON on stdout.
  #
  # Wraps `yq -o=json` (mikefarah/yq, bootstrapped automatically via bootstrap__yq).
  # `yq` accepts JSON as a subset of YAML, so this also normalises an already-JSON
  # file (e.g. stripping comments would not apply, but formatting is canonicalised).
  #
  # Args:
  #   <file>  Path to a YAML or JSON file.
  #
  # Stdout: canonical JSON.
  #
  # Returns: 0 on success, 1 if yq is unavailable or the file cannot be parsed.
  local _file="${1-}"
  [[ -n "${_file}" ]] || {
    logging__error "json__from_yaml: file path is required."
    return 1
  }
  local _yq
  _yq="$(bootstrap__yq)"
  local _rc=$?
  [[ $_rc == 0 && -n "${_yq}" ]] || {
    logging__error "json__from_yaml: yq could not be installed."
    return 1
  }
  "${_yq}" -o=json '.' "${_file}"
}

json__query_multi() {
  # @brief json__query_multi <json> <jq-expr>... — Evaluate multiple jq expressions against the same JSON input in ONE jq invocation.
  #
  # Reading N fields off the same JSON object via N separate json__query calls
  # forks N subprocesses. This batches any number of jq expressions into a
  # single jq invocation, evaluated in the given order against the same input.
  #
  # Each <jq-expr> should include its own default (e.g. '.src // ""') since a
  # missing/null result serialises to an empty string. Array and object results
  # are serialised via `tojson`; every other type is stringified via `tostring`
  # — EXCEPT null, which serialises to "" rather than the literal string
  # "null". Deliberately NOT `. // "" | tostring`: jq's `//` treats JSON
  # `false` as falsy (same as null), so that idiom would silently turn an
  # explicit boolean `false` result into "" too — indistinguishable from the
  # field being absent. Callers still need their own `// <default>` inside
  # <jq-expr> to supply a schema default for a genuinely MISSING field, but
  # that is a separate concern from this function's own type-to-string step.
  # Every result — INCLUDING THE LAST — is TERMINATED by a NUL byte (built via
  # jq's `[0]|implode`, not a shell-level escape), the same convention as
  # `find -print0`. Terminating (rather than merely separating) matters: if
  # the last expression's result happens to be an empty string, a
  # separator-only scheme would produce a byte stream indistinguishable from
  # "one fewer record", and `mapfile -d ''` would silently drop it.
  #
  # Args:
  #   <json>       JSON document (object or array) to query.
  #   <jq-expr>... One or more jq expressions, evaluated against <json> in order.
  #
  # Stdout: NUL-terminated results, one per expression, in the same order.
  #   Consume via: mapfile -d '' -t out < <(json__query_multi "$json" '.a' '.b // ""')
  #
  # Returns: jq exit code.
  local _json="${1-}"
  shift
  [[ $# -gt 0 ]] || {
    logging__error "json__query_multi: at least one jq expression is required."
    return 1
  }
  local _prog="" _e
  for _e in "$@"; do
    _prog+="(${_e} | if (type==\"array\" or type==\"object\") then tojson elif . == null then \"\" else tostring end), ([0]|implode), "
  done
  _prog="${_prog%, }"
  json__query -j "${_prog}" <<< "${_json}"
}

json__string_or_array_lines() {
  # @brief json__string_or_array_lines <json> <field> — Print one value per line for a field that may be absent, a plain string, or an array of strings.
  #
  # A field typed `["string", "array"]` (single scalar or a native list) is a
  # common JSON/YAML shape. `jq -r` alone errors on the array form (raw output
  # mode requires a string result), so this normalises both forms.
  #
  # Args:
  #   <json>   JSON object to query.
  #   <field>  Top-level field name to read.
  #
  # Stdout: one value per line; nothing when the field is absent or null.
  #
  # Returns: jq exit code.
  local _json="${1-}" _field="${2-}"
  [[ -n "${_field}" ]] || {
    logging__error "json__string_or_array_lines: field name is required."
    return 1
  }
  # shellcheck disable=SC2016
  json__query -r --arg f "${_field}" \
    'if (.[$f] == null) then empty
     elif (.[$f] | type) == "array" then .[$f][]
     else .[$f]
     end' <<< "${_json}"
}

json__query() {
  # @brief json__query — jq passthrough; ensures jq is available (installs via ospkg if needed).
  #
  # All arguments are forwarded to `jq` unchanged.
  #
  # Stdout: jq output.
  #
  # Returns: jq exit code.
  bootstrap__jq
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "jq is required for JSON query."
    return "$_rc"
  }
  jq "$@"
}

_json__root_scalar_stdin() {
  # _json__root_scalar_stdin (internal) — silent probe; no logging on failure.
  local _key="$1" _json _out
  _json="$(cat)" || return 1
  [ -n "$_json" ] || return 1
  bootstrap__jq
  local _rc=$?
  [[ $_rc == 0 ]] || return "$_rc"
  _out="$(printf '%s\n' "$_json" | jq -r --arg k "$_key" \
    '.[$k] | if type == "number" or type == "string" then tostring elif . == null then empty else empty end' 2> /dev/null)" || _out=""
  if [ -n "$_out" ] && [ "$_out" != "null" ]; then
    printf '%s\n' "$_out"
    return 0
  fi
  return 1
}

json__root_scalar_stdin() {
  # @brief json__root_scalar_stdin <key> — Read one JSON object from stdin; print `.[key]` when it is a string or number.
  #
  # Args:
  #   <key>  Top-level object key to extract.
  #
  # Stdout: string value of `.[key]`.
  #
  # Returns: 0 on success, 1 if jq is unavailable, stdin is empty, or the value is missing or non-scalar.
  local _key="$1"
  _json__root_scalar_stdin "$_key"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "root scalar '${_key}' not found or not a string/number."
    return "$_rc"
  }
}

json__array_field_lines_stdin() {
  # @brief json__array_field_lines_stdin <field> — Read JSON from stdin (expected: top-level array); print one line per element's `.[field]` when string or number.
  #
  # Args:
  #   <field>  Field name to extract from each array element.
  #
  # Stdout: one value per line.
  #
  # Returns: 0 on success, 1 if no values found or jq is unavailable.
  local _field="$1" _json _out
  _json="$(cat)" || {
    logging__error "failed to read JSON from stdin."
    return 1
  }
  [ -z "$_json" ] && {
    logging__error "empty JSON input."
    return 1
  }
  bootstrap__jq
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "jq is required to read array field '${_field}'."
    return "$_rc"
  }
  _out="$(printf '%s\n' "$_json" | jq -r --arg f "$_field" \
    'if type == "array" then .[] | .[$f] // empty | if type == "string" or type == "number" then tostring else empty end else empty end' 2> /dev/null)" || _out=""
  if [ -n "$_out" ]; then
    printf '%s\n' "$_out"
    return 0
  fi
  logging__error "no values found for array field '${_field}'."
  return 1
}

json__object_array_field_lines_stdin() {
  # @brief json__object_array_field_lines_stdin <arrayKey> <field> — Read one JSON object from stdin; print one line per element of `.[arrayKey][].[field]` when string or number.
  #
  # Requires root to be an object and `.[arrayKey]` to be an array of objects.
  #
  # Args:
  #   <arrayKey>  Key whose value is the array to iterate.
  #   <field>     Field to extract from each array element.
  #
  # Stdout: one value per line.
  #
  # Returns: 0 on success, 1 if no values found or jq is unavailable.
  local _ak="$1" _field="$2" _json _out
  _json="$(cat)" || {
    logging__error "failed to read JSON from stdin."
    return 1
  }
  [ -z "$_json" ] && {
    logging__error "empty JSON input."
    return 1
  }
  bootstrap__jq
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "jq is required to read '${_ak}[].${_field}'."
    return "$_rc"
  }
  _out="$(printf '%s\n' "$_json" | jq -r --arg ak "$_ak" --arg f "$_field" \
    '(.[$ak] | if type == "array" then .[] else empty end) | .[$f] // empty | if type == "string" or type == "number" then tostring else empty end' 2> /dev/null)" || _out=""
  if [ -n "$_out" ]; then
    printf '%s\n' "$_out"
    return 0
  fi
  logging__error "no values found for '${_ak}[].${_field}'."
  return 1
}

json__object_map_string_values_stdin() {
  # @brief json__object_map_string_values_stdin [<objectKey>] — Read one JSON object from stdin; print all string values from the root object or from `.[objectKey]`.
  #
  # When `.[key]` may be an array of strings instead, use `json__object_key_string_lines_stdin`.
  #
  # Args:
  #   [<objectKey>]  Optional sub-key to descend into (defaults to root object).
  #
  # Stdout: one string value per line.
  #
  # Returns: 0 on success, 1 if no values found or jq is unavailable.
  local _sub="${1-}" _json _out
  _json="$(cat)" || {
    logging__error "failed to read JSON from stdin."
    return 1
  }
  [ -z "$_json" ] && {
    logging__error "empty JSON input."
    return 1
  }
  bootstrap__jq
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "jq is required to read object string values."
    return "$_rc"
  }
  _out="$(printf '%s\n' "$_json" | jq -r --arg sk "$_sub" \
    'if ($sk | length) == 0 then
      (if type == "object" then to_entries[].value | select(type == "string") else empty end)
    else
      (.[$sk] | if type == "object" then to_entries[].value | select(type == "string") else empty end)
    end' 2> /dev/null)" || _out=""
  if [ -n "$_out" ]; then
    printf '%s\n' "$_out"
    return 0
  fi
  logging__error "no string values found in JSON object."
  return 1
}

json__object_key_string_lines_stdin() {
  # @brief json__object_key_string_lines_stdin <key> — Read one JSON object from stdin; print each string from `.[key]` when that value is a JSON array of strings or an object whose values are strings (one line per string).
  #
  # Args:
  #   <key>  Object key to read (e.g. `envs` for `conda env list --json`).
  #
  # Stdout: one string per line.
  local _key="${1-}" _json _out
  [ -z "$_key" ] && {
    logging__error "object key is required."
    return 1
  }
  _json="$(cat)" || {
    logging__error "failed to read JSON from stdin."
    return 1
  }
  [ -z "$_json" ] && {
    logging__error "empty JSON input."
    return 1
  }
  bootstrap__jq
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "jq is required to read object key '${_key}'."
    return "$_rc"
  }
  _out="$(printf '%s\n' "$_json" | jq -r --arg k "$_key" '
    .[$k]
    | if type == "array" then .[] | strings
      elif type == "object" then .[] | strings
      else empty end' 2> /dev/null)" || _out=""
  if [ -n "$_out" ]; then
    printf '%s\n' "$_out"
    return 0
  fi
  logging__error "no string values found for object key '${_key}'."
  return 1
}

json__object_keys_stdin() {
  # @brief json__object_keys_stdin [<objectKey>] — Print keys of the root object or of `.[objectKey]`; one key per line.
  #
  # Args:
  #   [<objectKey>]  Optional sub-key to descend into (defaults to root object).
  #
  # Stdout: one key per line.
  #
  # Returns: 0 on success, 1 if jq is unavailable or input is not an object.
  local _sub="${1-}" _json _out
  _json="$(cat)" || {
    logging__error "failed to read JSON from stdin."
    return 1
  }
  [ -z "$_json" ] && {
    logging__error "empty JSON input."
    return 1
  }
  bootstrap__jq
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "jq is required to read object keys."
    return "$_rc"
  }
  if [ -z "$_sub" ]; then
    _out="$(printf '%s\n' "$_json" | jq -r 'keys[]' 2> /dev/null)" || {
      logging__error "failed to read root object keys."
      return 1
    }
  else
    _out="$(printf '%s\n' "$_json" | jq -r --arg sk "$_sub" '.[$sk] | if type == "object" then keys[] else empty end' 2> /dev/null)" || {
      logging__error "failed to read keys for object '${_sub}'."
      return 1
    }
  fi
  [ -n "$_out" ] && printf '%s\n' "$_out"
  return 0
}

json__value_stdin() {
  # @brief json__value_stdin <jq-expr> — Read JSON from stdin; print compact value at `<jq-expr>`.
  #
  # Args:
  #   <jq-expr>  jq expression to evaluate (e.g. `.name`, `.features`).
  #
  # Stdout: compact JSON value at the given path.
  #
  # Returns: 0 on success, 1 if jq is unavailable or expression is empty.
  local _expr="${1-}" _json
  [ -z "$_expr" ] && {
    logging__error "jq expression is required."
    return 1
  }
  _json="$(cat)" || {
    logging__error "failed to read JSON from stdin."
    return 1
  }
  [ -z "$_json" ] && {
    logging__error "empty JSON input."
    return 1
  }
  bootstrap__jq
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "jq is required to evaluate expression '${_expr}'."
    return "$_rc"
  }
  printf '%s\n' "$_json" | jq -c "$_expr" 2> /dev/null
}

json__validate() {
  # @brief json__validate <instance-file> <schema-file> — Validate a JSON or YAML instance file against a JSON Schema using sourcemeta/jsonschema.
  #
  # Bootstraps sourcemeta/jsonschema automatically if not already on PATH.
  # Validation errors are written to stderr verbatim from the jsonschema CLI.
  #
  # The instance file may be JSON (`.json`, `.jsonl`) or YAML (`.yaml`, `.yml`);
  # the schema file may also be JSON or YAML. All major JSON Schema drafts are
  # supported (draft-04, draft-06, draft-07, 2019-09, 2020-12); the dialect is
  # read from the schema's `$schema` keyword.
  #
  # Args:
  #   <instance-file>  Path to the JSON or YAML instance file to validate.
  #   <schema-file>    Path to the JSON Schema file.
  #
  # Returns: 0 if the instance is valid, 1 on schema violation or error.
  local _instance="${1-}" _schema="${2-}"
  [[ -f "${_instance}" ]] || {
    logging__error "json__validate: instance file not found: '${_instance}'"
    return 1
  }
  [[ -f "${_schema}" ]] || {
    logging__error "json__validate: schema file not found: '${_schema}'"
    return 1
  }
  local _jsonschema_bin
  _jsonschema_bin="$(bootstrap__jsonschema)"
  local _rc=$?
  [[ $_rc == 0 && -n "${_jsonschema_bin}" ]] || {
    logging__error "json__validate: sourcemeta/jsonschema could not be installed."
    return 1
  }
  local _val_rc=0 _val_output
  _val_output=$("${_jsonschema_bin}" validate "${_schema}" "${_instance}" 2>&1) || _val_rc=$?
  [[ $_val_rc -ne 0 && -n "${_val_output}" ]] && logging__error "${_val_output}"
  [[ $_val_rc -eq 0 ]]
}

json__coerce_scalar_stdin() {
  # @brief json__coerce_scalar_stdin — Read one JSON scalar from stdin; print its string form for use in environment variables.
  #
  # Booleans and numbers are converted via `jq tostring`; strings are printed raw; null prints an empty line. Objects and arrays return 1.
  #
  # Stdout: string representation of the scalar value.
  #
  # Returns: 0 on success, 1 for objects, arrays, or jq errors.
  local _json _t
  _json="$(cat)" || {
    logging__error "failed to read JSON from stdin."
    return 1
  }
  [ -z "$_json" ] && {
    logging__error "empty JSON input."
    return 1
  }
  bootstrap__jq
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "jq is required to coerce JSON scalar."
    return "$_rc"
  }
  _t="$(printf '%s\n' "$_json" | jq -r 'type' 2> /dev/null)" || {
    logging__error "failed to determine JSON value type."
    return 1
  }
  case "$_t" in
    string)
      printf '%s\n' "$_json" | jq -r '.'
      return 0
      ;;
    number | boolean)
      printf '%s\n' "$_json" | jq -r 'tostring'
      return 0
      ;;
    "null")
      printf '\n'
      return 0
      ;;
    object | array)
      logging__error "JSON value is not a scalar (type=${_t})."
      return 1
      ;;
    *)
      logging__error "unsupported JSON value type '${_t}'."
      return 1
      ;;
  esac
}
