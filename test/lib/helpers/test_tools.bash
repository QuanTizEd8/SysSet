# shellcheck shell=bash
# Per-test wiring for immutable external tools prepared by setup_suite.bash.
# This helper never resolves, provisions, or downloads a tool.

_test_tools__require_export() {
  local _name=$1 _path=$2
  if [[ -z "$_path" || ! -f "$_path" || ! -x "$_path" || -L "$_path" ]]; then
    printf '⛔ required suite-cached test tool %s is unavailable: %s\n' \
      "$_name" "${_path:-<unset>}" >&2
    return 1
  fi
}

_test_tools__wire() {
  local _name=$1 _source=$2 _bin_dir="${BATS_TEST_TMPDIR}/bin"
  _test_tools__require_export "$_name" "$_source" || return 1
  mkdir -p "$_bin_dir" || return 1
  ln -sf "$_source" "${_bin_dir}/${_name}" || return 1
  case ":${PATH}:" in
    *":${_bin_dir}:"*) ;;
    *)
      PATH="${_bin_dir}:${PATH}"
      export PATH
      ;;
  esac
}

test_tools__wire_jq() {
  _test_tools__wire jq "${DEVFEATS_TEST_JQ_BIN:-}"
}

test_tools__stub_yq() {
  _test_tools__require_export yq "${DEVFEATS_TEST_YQ_BIN:-}" || return 1
  # shellcheck disable=SC2329  # exported test double invoked by library code
  bootstrap__yq() {
    if [[ -z "${_BOOTSTRAP__YQ_BIN:-}" ]]; then
      _BOOTSTRAP__YQ_BIN="${DEVFEATS_TEST_YQ_BIN}"
    fi
    printf '%s\n' "${_BOOTSTRAP__YQ_BIN}"
  }
  export -f bootstrap__yq
}

test_tools__wire_yq() {
  _test_tools__wire yq "${DEVFEATS_TEST_YQ_BIN:-}" || return 1
  test_tools__stub_yq
}

test_tools__wire_jsonschema() {
  _test_tools__wire jsonschema "${DEVFEATS_TEST_JSONSCHEMA_BIN:-}" || return 1
  # shellcheck disable=SC2329  # exported test double invoked by library code
  bootstrap__jsonschema() {
    _BOOTSTRAP__JSONSCHEMA_BIN="${DEVFEATS_TEST_JSONSCHEMA_BIN}"
    printf '%s\n' "${DEVFEATS_TEST_JSONSCHEMA_BIN}"
  }
  export -f bootstrap__jsonschema
}

test_tools__wire_oras() {
  _test_tools__wire oras "${DEVFEATS_TEST_ORAS_BIN:-}"
}

test_tools__wire_jq_yq() {
  test_tools__wire_jq || return 1
  test_tools__wire_yq
}

test_tools__wire_jq_jsonschema() {
  test_tools__wire_jq || return 1
  test_tools__wire_jsonschema
}

test_tools__wire_jq_yq_jsonschema() {
  test_tools__wire_jq_yq || return 1
  test_tools__wire_jsonschema
}

test_tools__wire_jq_oras() {
  test_tools__wire_jq || return 1
  test_tools__wire_oras
}

test_tools__wire_all() {
  test_tools__wire_jq_yq || return 1
  test_tools__wire_jsonschema || return 1
  test_tools__wire_oras
}
