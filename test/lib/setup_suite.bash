#!/usr/bin/env bash
# setup_suite.bash — immutable suite-level test-tool cache.
# Called once by bats before running any tests in the suite.  Ordinary tests
# receive validated private copies of their external parsers/clients.  The
# dedicated bootstrap workload receives no prepared tools at all.

_test_suite__fail() {
  printf '⛔ library test-suite setup: %s\n' "$1" >&2
  return 1
}

_test_suite__resolve_tool() {
  local _name=$1 _source_dir=${2:-} _candidate _dir
  if [[ -n "$_source_dir" ]]; then
    _candidate="${_source_dir}/${_name}"
  else
    _candidate="$(command -v "$_name" 2> /dev/null || true)"
    [[ -n "$_candidate" ]] || _test_suite__fail "required tool '${_name}' was not found on PATH" || return
    if [[ "$_candidate" != /* ]]; then
      _dir="$(cd "$(dirname "$_candidate")" 2> /dev/null && pwd -P)" ||
        _test_suite__fail "could not resolve '${_name}' path '${_candidate}'" || return
      _candidate="${_dir}/$(basename "$_candidate")"
    fi
  fi
  [[ -f "$_candidate" && -x "$_candidate" ]] ||
    _test_suite__fail "required tool '${_name}' is not a regular executable: ${_candidate}" || return
  [[ ! -L "$_candidate" ]] ||
    _test_suite__fail "required tool '${_name}' must not be a symlink: ${_candidate}" || return
  printf '%s\n' "$_candidate"
}

_test_suite__probe_tool() {
  local _name=$1 _bin=$2 _out _version_line _major _minor
  case "$_name" in
    jq)
      _out="$("$_bin" --version 2> /dev/null)" || return 1
      [[ "$_out" =~ ^jq-1\.[0-9]+([.][0-9]+)?$ ]] || return 1
      [[ "$(printf '%s\n' '{"value":42}' | "$_bin" -r '.value' 2> /dev/null)" == 42 ]]
      ;;
    yq)
      _out="$("$_bin" --version 2> /dev/null)" || return 1
      [[ "$_out" =~ version[[:space:]]+v4\.[0-9]+\.[0-9]+$ ]] || return 1
      [[ "$(printf 'value: 42\n' | "$_bin" -r '.value' 2> /dev/null)" == 42 ]]
      ;;
    jsonschema)
      _out="$("$_bin" version 2> /dev/null)" || return 1
      [[ "$_out" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
      printf '%s\n' \
        '{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"integer"}' \
        > "${BATS_SUITE_TMPDIR}/probe.schema.json" || return 1
      printf '42\n' > "${BATS_SUITE_TMPDIR}/probe.instance.json" || return 1
      "$_bin" validate "${BATS_SUITE_TMPDIR}/probe.schema.json" \
        "${BATS_SUITE_TMPDIR}/probe.instance.json" > /dev/null 2>&1
      ;;
    oras)
      _out="$("$_bin" version 2> /dev/null)" || return 1
      _version_line="${_out%%$'\n'*}"
      [[ "$_version_line" =~ ^Version:[[:space:]]*([0-9]+)\.([0-9]+)\.[0-9]+$ ]] || return 1
      _major="${BASH_REMATCH[1]}"
      _minor="${BASH_REMATCH[2]}"
      ((10#${_major} > 1 || (10#${_major} == 1 && 10#${_minor} >= 2)))
      ;;
    *) return 1 ;;
  esac
}

setup_suite() {
  # lib/ospkg.bash, lib/shell.bash, lib/git.bash, lib/logging.bash all require bash ≥ 4.
  if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "⛔ bash ≥ 4.0 is required for the unit tests (found ${BASH_VERSION})" >&2
    return 1
  fi

  case "${DEVFEATS_TEST_TOOL_CACHE:-}" in
    disabled)
      unset DEVFEATS_TEST_TOOLS_DIR DEVFEATS_TEST_JQ_BIN DEVFEATS_TEST_YQ_BIN
      unset DEVFEATS_TEST_JSONSCHEMA_BIN DEVFEATS_TEST_ORAS_BIN
      unset DEVFEATS_TEST_TOOL_SOURCE_DIR DEVFEATS_TEST_REQUIRED_TOOLS
      return 0
      ;;
    required) ;;
    '')
      _test_suite__fail "DEVFEATS_TEST_TOOL_CACHE must be set to required or disabled"
      return
      ;;
    *)
      _test_suite__fail "invalid DEVFEATS_TEST_TOOL_CACHE='${DEVFEATS_TEST_TOOL_CACHE}' (expected required or disabled)"
      return
      ;;
  esac

  local _source_dir="${DEVFEATS_TEST_TOOL_SOURCE_DIR:-}" _canonical_source=""
  if [[ -n "$_source_dir" ]]; then
    [[ "$_source_dir" == /* ]] || {
      _test_suite__fail "DEVFEATS_TEST_TOOL_SOURCE_DIR must be absolute: ${_source_dir}"
      return
    }
    [[ -d "$_source_dir" && ! -L "$_source_dir" ]] || {
      _test_suite__fail "DEVFEATS_TEST_TOOL_SOURCE_DIR is not a regular directory: ${_source_dir}"
      return
    }
    _canonical_source="$(cd "$_source_dir" 2> /dev/null && pwd -P)" || {
      _test_suite__fail "could not resolve DEVFEATS_TEST_TOOL_SOURCE_DIR: ${_source_dir}"
      return
    }
    [[ "$_canonical_source" == "$_source_dir" ]] || {
      _test_suite__fail "DEVFEATS_TEST_TOOL_SOURCE_DIR must be canonical: ${_source_dir} (resolved ${_canonical_source})"
      return
    }
  fi

  local _tools_dir="${BATS_SUITE_TMPDIR}/tools" _name _source _dest
  local _required_tools="${DEVFEATS_TEST_REQUIRED_TOOLS:-jq yq}"
  [[ -n "$_canonical_source" ]] && _required_tools="jq yq jsonschema oras"
  mkdir -p "$_tools_dir" || {
    _test_suite__fail "could not create suite tool cache: ${_tools_dir}"
    return
  }
  chmod 0700 "$_tools_dir" || return 1
  for _name in $_required_tools; do
    case "$_name" in
      jq | yq | jsonschema | oras) ;;
      *)
        _test_suite__fail "unsupported entry in DEVFEATS_TEST_REQUIRED_TOOLS: ${_name}"
        return
        ;;
    esac
    _source="$(_test_suite__resolve_tool "$_name" "$_canonical_source")" || return 1
    _test_suite__probe_tool "$_name" "$_source" || {
      _test_suite__fail "required tool '${_name}' is incompatible or failed its functional probe: ${_source}"
      return
    }
    _dest="${_tools_dir}/${_name}"
    cp "$_source" "$_dest" || {
      _test_suite__fail "could not copy '${_name}' into the suite cache"
      return
    }
    chmod 0555 "$_dest" || return 1
    [[ -f "$_dest" && -x "$_dest" && ! -L "$_dest" ]] || {
      _test_suite__fail "suite copy for '${_name}' is not an immutable regular executable"
      return
    }
    cmp -s "$_source" "$_dest" || {
      _test_suite__fail "suite copy for '${_name}' differs from its validated source"
      return
    }
    _test_suite__probe_tool "$_name" "$_dest" || {
      _test_suite__fail "suite copy for '${_name}' failed its functional probe"
      return
    }
    case "$_name" in
      jq)
        DEVFEATS_TEST_JQ_BIN="$_dest"
        export DEVFEATS_TEST_JQ_BIN
        ;;
      yq)
        DEVFEATS_TEST_YQ_BIN="$_dest"
        export DEVFEATS_TEST_YQ_BIN
        ;;
      jsonschema)
        DEVFEATS_TEST_JSONSCHEMA_BIN="$_dest"
        export DEVFEATS_TEST_JSONSCHEMA_BIN
        ;;
      oras)
        DEVFEATS_TEST_ORAS_BIN="$_dest"
        export DEVFEATS_TEST_ORAS_BIN
        ;;
    esac
  done
  chmod 0555 "$_tools_dir" || {
    _test_suite__fail "could not make the suite tool cache read-only"
    return
  }
  DEVFEATS_TEST_TOOLS_DIR="$_tools_dir"
  export DEVFEATS_TEST_TOOLS_DIR
}

teardown_suite() {
  # The cache is read-only for the entire test workload. Re-open only its
  # containing directory after every test has finished so BATS can remove its
  # own suite temp tree without reporting a false cleanup failure.
  [[ "${DEVFEATS_TEST_TOOL_CACHE:-}" == required ]] || return 0
  local _tools_dir="${BATS_SUITE_TMPDIR}/tools"
  [[ -d "$_tools_dir" && ! -L "$_tools_dir" ]] || return 0
  chmod 0700 "$_tools_dir" || {
    _test_suite__fail "could not reopen the suite tool cache for BATS cleanup"
    return 1
  }
}
