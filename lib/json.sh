#!/bin/sh
# shellcheck disable=SC3043  # 'local' is not POSIX but is supported by all targeted shells (dash, ash, macOS sh)
# POSIX sh compatible — safe to source from sh and bash scripts alike.
# Do not edit _lib/ copies directly — edit lib/ instead.
#
# JSON helpers: lazy-detected backend (jq, mikefarah yq, or python3). When none
# are on PATH and ospkg.sh is already sourced, installs jq via ospkg (same idea
# as net.sh installing curl). Does not source ospkg from this file.

[ -n "${_JSON__LIB_LOADED-}" ] && return 0
_JSON__LIB_LOADED=1

# _json__ensure_parse_tool (internal)
#
# Sets _JSON__PARSE_TOOL once to jq, yq, or python (mikefarah yq only — probed
# with yq -o=json). If none exist and ospkg__install_tracked is available with
# ospkg loaded, runs ospkg__update / ospkg__install_tracked lib-json jq, then
# retries jq. Idempotent. Returns 0 if a structured parser is available, else 1.
_json__ensure_parse_tool() {
  if [ -n "${_JSON__ENSURE_PARSE_DONE:-}" ]; then
    [ -n "${_JSON__PARSE_TOOL:-}" ]
    return $?
  fi
  if command -v jq >/dev/null 2>&1; then
    _JSON__PARSE_TOOL=jq
    _JSON__ENSURE_PARSE_DONE=1
    return 0
  fi
  if command -v yq >/dev/null 2>&1 && yq -o=json '.' /dev/null >/dev/null 2>&1; then
    _JSON__PARSE_TOOL=yq
    _JSON__ENSURE_PARSE_DONE=1
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    _JSON__PARSE_TOOL=python
    _JSON__ENSURE_PARSE_DONE=1
    return 0
  fi
  if command -v ospkg__install_tracked >/dev/null 2>&1 && [ -n "${_OSPKG__LIB_LOADED-}" ]; then
    echo "ℹ️  No JSON parser (jq, yq, python3) — installing jq." >&2
    ospkg__update >&2 || true
    ospkg__install_tracked "lib-json" jq >&2 || true
    if command -v jq >/dev/null 2>&1; then
      _JSON__PARSE_TOOL=jq
      _JSON__ENSURE_PARSE_DONE=1
      return 0
    fi
  fi
  _JSON__ENSURE_PARSE_DONE=1
  _JSON__PARSE_TOOL=""
  return 1
}

# @brief json__root_scalar_stdin <key> — Read one JSON object from stdin; print .[key] when string or number.
#
# After _json__ensure_parse_tool, uses jq, mikefarah yq (probed), or python3. Returns 1 if no parser
# is available, stdin is empty, or the value is missing or non-scalar. Does not use grep.
json__root_scalar_stdin() {
  local _key="$1" _json _out
  _json="$(cat)" || return 1
  [ -z "$_json" ] && return 1
  _json__ensure_parse_tool || return 1
  case "${_JSON__PARSE_TOOL}" in
    jq)
      _out="$(printf '%s\n' "$_json" | jq -r --arg k "$_key" \
        '.[$k] | if type == "number" or type == "string" then tostring elif . == null then empty else empty end' 2> /dev/null)" || _out=""
      ;;
    yq)
      _out="$(
        printf '%s\n' "$_json" |
          env _JYQ_K="$_key" yq eval -p=json -r \
            '.[strenv(_JYQ_K)] | select(tag != "!!null") | select(tag == "!!str" or tag == "!!int" or tag == "!!float")' - 2> /dev/null
      )" || _out=""
      ;;
    python)
      _out="$(printf '%s\n' "$_json" | python3 -c '
import json, sys
k = sys.argv[1]
d = json.load(sys.stdin)
if not isinstance(d, dict):
    sys.exit(1)
v = d[k]
print(v if isinstance(v, str) else str(v))
' "$_key" 2> /dev/null)" || _out=""
      ;;
    *)
      return 1
      ;;
  esac
  if [ -n "$_out" ] && [ "$_out" != "null" ]; then
    printf '%s\n' "$_out"
    return 0
  fi
  return 1
}

# @brief json__array_field_lines_stdin <field> — Read JSON from stdin (expected: top-level array); print one line per element's .[field] when string or number.
#
# After _json__ensure_parse_tool, uses jq, mikefarah yq, or python3; if none, falls back to grep -o
# for double-quoted string values only (can false-positive on nested keys).
json__array_field_lines_stdin() {
  local _field="$1" _json _out
  _json="$(cat)" || return 1
  [ -z "$_json" ] && return 1
  _out=""
  if _json__ensure_parse_tool; then
    case "${_JSON__PARSE_TOOL}" in
      jq)
        _out="$(printf '%s\n' "$_json" | jq -r --arg f "$_field" \
          'if type == "array" then .[] | .[$f] // empty | if type == "string" or type == "number" then tostring else empty end else empty end' 2> /dev/null)" || _out=""
        ;;
      yq)
        _out="$(
          printf '%s\n' "$_json" |
            env _JYQ_F="$_field" yq eval -p=json -r \
              '.[] | .[strenv(_JYQ_F)] | select(tag != "!!null") | select(tag == "!!str" or tag == "!!int" or tag == "!!float")' - 2> /dev/null
        )" || _out=""
        ;;
      python)
        _out="$(printf '%s\n' "$_json" | python3 -c '
import json, sys
field = sys.argv[1]
data = json.load(sys.stdin)
if not isinstance(data, list):
    sys.exit(1)
for item in data:
    if isinstance(item, dict) and field in item and item[field] is not None:
        v = item[field]
        print(v if isinstance(v, str) else str(v))
' "$_field" 2> /dev/null)" || _out=""
        ;;
    esac
    if [ -n "$_out" ]; then
      printf '%s\n' "$_out"
      return 0
    fi
  fi
  _out="$(printf '%s\n' "$_json" |
    grep -o "\"${_field}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" |
    sed "s/^\"${_field}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\"$/\1/")" || _out=""
  [ -z "$_out" ] && return 1
  printf '%s\n' "$_out"
  return 0
}

# @brief json__object_array_field_lines_stdin <arrayKey> <field> — Read one JSON object from stdin; print one line per element of .[arrayKey][].[field] when string or number.
#
# Requires root to be an object and .[arrayKey] to be an array of objects. Uses jq, mikefarah yq, or python3
# after _json__ensure_parse_tool. No grep fallback (fail closed on invalid shape).
json__object_array_field_lines_stdin() {
  local _ak="$1" _field="$2" _json _out
  _json="$(cat)" || return 1
  [ -z "$_json" ] && return 1
  _json__ensure_parse_tool || return 1
  case "${_JSON__PARSE_TOOL}" in
    jq)
      _out="$(printf '%s\n' "$_json" | jq -r --arg ak "$_ak" --arg f "$_field" \
        '(.[$ak] | if type == "array" then .[] else empty end) | .[$f] // empty | if type == "string" or type == "number" then tostring else empty end' 2> /dev/null)" || _out=""
      ;;
    yq)
      _out="$(
        printf '%s\n' "$_json" |
          env _JYQ_AK="$_ak" _JYQ_F="$_field" yq eval -p=json -r \
            '.[strenv(_JYQ_AK)] | .[] | .[strenv(_JYQ_F)] | select(tag != "!!null") | select(tag == "!!str" or tag == "!!int" or tag == "!!float")' - 2> /dev/null
      )" || _out=""
      ;;
    python)
      _out="$(printf '%s\n' "$_json" | python3 -c '
import json, sys
ak, f = sys.argv[1], sys.argv[2]
d = json.load(sys.stdin)
if not isinstance(d, dict) or ak not in d:
    sys.exit(1)
arr = d[ak]
if not isinstance(arr, list):
    sys.exit(1)
for item in arr:
    if isinstance(item, dict) and f in item and item[f] is not None:
        v = item[f]
        if isinstance(v, bool):
            continue
        print(v if isinstance(v, str) else str(v))
' "$_ak" "$_field" 2> /dev/null)" || _out=""
      ;;
    *)
      return 1
      ;;
  esac
  if [ -n "$_out" ]; then
    printf '%s\n' "$_out"
    return 0
  fi
  return 1
}

# @brief json__object_map_string_values_stdin [<objectKey>] — Read one JSON object; print all string values from the root object or from .[objectKey] when it is an object (e.g. conda env list --json "envs" map).
#
# If <objectKey> is omitted or empty, uses the root object. One line per string value. Uses jq, yq, or python3; no grep fallback.
json__object_map_string_values_stdin() {
  local _sub="${1-}" _json _out
  _json="$(cat)" || return 1
  [ -z "$_json" ] && return 1
  _json__ensure_parse_tool || return 1
  case "${_JSON__PARSE_TOOL}" in
    jq)
      _out="$(printf '%s\n' "$_json" | jq -r --arg sk "$_sub" \
        'if ($sk | length) == 0 then
          (if type == "object" then to_entries[].value | select(type == "string") else empty end)
        else
          (.[$sk] | if type == "object" then to_entries[].value | select(type == "string") else empty end)
        end' 2> /dev/null)" || _out=""
      ;;
    yq)
      if [ -z "$_sub" ]; then
        _out="$(
          printf '%s\n' "$_json" | yq eval -p=json -r \
            'to_entries | .[].value | select(tag == "!!str")' - 2> /dev/null
        )" || _out=""
      else
        _out="$(
          printf '%s\n' "$_json" |
            env _JYQ_SK="$_sub" yq eval -p=json -r \
              '.[strenv(_JYQ_SK)] | to_entries | .[].value | select(tag == "!!str")' - 2> /dev/null
        )" || _out=""
      fi
      ;;
    python)
      _out="$(printf '%s\n' "$_json" | python3 -c '
import json, sys
sk = sys.argv[1] if len(sys.argv) > 1 else ""
d = json.load(sys.stdin)
if not isinstance(d, dict):
    sys.exit(1)
obj = d[sk] if sk else d
if not isinstance(obj, dict):
    sys.exit(1)
for v in obj.values():
    if isinstance(v, str):
        print(v)
' "$_sub" 2> /dev/null)" || _out=""
      ;;
    *)
      return 1
      ;;
  esac
  if [ -n "$_out" ]; then
    printf '%s\n' "$_out"
    return 0
  fi
  return 1
}

# @brief json__nodejs_index_version_stdin <op> [arg] — Read nodejs.org-style dist index.json (array of objects); print one version string.
#
# <op>: lts-first (first entry with lts not JSON false), head (first entry), major (arg = major e.g. 22), exact (arg = full version as in JSON e.g. v22.0.0).
# Field is always "version". Uses jq, yq, or python3; no grep fallback.
json__nodejs_index_version_stdin() {
  local _op="$1" _arg="${2-}" _json _out
  _json="$(cat)" || return 1
  [ -z "$_json" ] && return 1
  [ -z "$_op" ] && return 1
  _json__ensure_parse_tool || return 1
  case "${_JSON__PARSE_TOOL}" in
    jq)
      case "$_op" in
        lts-first)
          _out="$(printf '%s\n' "$_json" | jq -r '[.[] | select(.lts != false)][0].version // empty | strings' 2> /dev/null)" || _out=""
          ;;
        head)
          _out="$(printf '%s\n' "$_json" | jq -r '.[0].version // empty | strings' 2> /dev/null)" || _out=""
          ;;
        major)
          [ -z "$_arg" ] && return 1
          _out="$(printf '%s\n' "$_json" | jq -r --arg p "v${_arg}." \
            '.[] | select(.version | type == "string" and startswith($p)) | .version' 2> /dev/null | head -n 1)" || _out=""
          ;;
        exact)
          [ -z "$_arg" ] && return 1
          _out="$(printf '%s\n' "$_json" | jq -r --arg v "$_arg" \
            '.[] | select(.version == $v) | .version // empty' 2> /dev/null | head -n 1)" || _out=""
          ;;
        *)
          return 1
          ;;
      esac
      ;;
    yq)
      case "$_op" in
        lts-first)
          _out="$(
            printf '%s\n' "$_json" | yq eval -p=json -r \
              '[.[] | select(.lts != false)][0].version' - 2> /dev/null
          )" || _out=""
          ;;
        head)
          _out="$(printf '%s\n' "$_json" | yq eval -p=json -r '.[0].version' - 2> /dev/null)" || _out=""
          ;;
        major)
          [ -z "$_arg" ] && return 1
          _out="$(
            printf '%s\n' "$_json" | env M="$_arg" yq eval -p=json -r \
              '.[] | select(.version | test("^v" + strenv(M) + "\\.")) | .version' - 2> /dev/null | head -n 1
          )" || _out=""
          ;;
        exact)
          [ -z "$_arg" ] && return 1
          _out="$(
            printf '%s\n' "$_json" | env _JYQ_V="$_arg" yq eval -p=json -r \
              '.[] | select(.version == strenv(_JYQ_V)) | .version' - 2> /dev/null | head -n 1
          )" || _out=""
          ;;
        *)
          return 1
          ;;
      esac
      ;;
    python)
      _out="$(printf '%s\n' "$_json" | python3 -c '
import json, sys
op, arg = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "")
data = json.load(sys.stdin)
if not isinstance(data, list):
    sys.exit(1)
if op == "lts-first":
    for item in data:
        if isinstance(item, dict) and item.get("lts") is not False:
            v = item.get("version")
            if isinstance(v, str) and v:
                print(v)
                sys.exit(0)
elif op == "head":
    if data and isinstance(data[0], dict):
        v = data[0].get("version")
        if isinstance(v, str) and v:
            print(v)
            sys.exit(0)
elif op == "major":
    if not arg or not str(arg).isdigit():
        sys.exit(1)
    pfx = "v" + str(arg) + "."
    for item in data:
        if isinstance(item, dict):
            v = item.get("version")
            if isinstance(v, str) and v.startswith(pfx):
                print(v)
                sys.exit(0)
elif op == "exact":
    if not arg:
        sys.exit(1)
    want = str(arg)
    for item in data:
        if isinstance(item, dict) and item.get("version") == want:
            print(want)
            sys.exit(0)
sys.exit(1)
' "$_op" "$_arg" 2> /dev/null)" || _out=""
      ;;
    *)
      return 1
      ;;
  esac
  case "$_out" in ''|'null') return 1 ;; esac
  printf '%s\n' "$_out"
  return 0
}
