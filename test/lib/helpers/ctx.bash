# shellcheck shell=bash
# Test helpers for lib/ctx.bash

ctx_test__reset() {
  ctx__reset
}

ctx_test__seed_os() {
  local _pair _k _v
  for _pair in "$@"; do
    _k="${_pair%%=*}"
    _v="${_pair#*=}"
    ctx__set "os.${_k}=${_v}"
  done
  _CTX__REGISTRY_INITIALIZED=true
}

ctx_test__seed_plat() {
  local _pair _k _v
  for _pair in "$@"; do
    _k="${_pair%%=*}"
    _v="${_pair#*=}"
    ctx__set "plat.${_k}=${_v}"
  done
  _CTX__REGISTRY_INITIALIZED=true
}

ctx_test__seed_feat() {
  local _pair _k _v
  for _pair in "$@"; do
    _k="${_pair%%=*}"
    _v="${_pair#*=}"
    ctx__set "feat.${_k}=${_v}"
  done
  _CTX__REGISTRY_INITIALIZED=true
}

ctx_test__apply_ctx_pairs() {
  local _pair _k _v
  for _pair in "$@"; do
    [[ "${_pair}" == *"="* ]] || continue
    _k="${_pair%%=*}"
    _v="${_pair#*=}"
    ctx__set "${_k}=${_v}"
  done
  _CTX__REGISTRY_INITIALIZED=true
}

ctx_test__fixtures_dir() {
  printf '%s' "${REPO_ROOT}/test/lib/fixtures/ctx"
}

ctx_test__require_yq() {
  bootstrap__yq > /dev/null || return 1
  bootstrap__yq
}

ctx_test__jq_compare() {
  local _a="$1" _b="$2"
  json__query -n --arg a "${_a}" --arg b "${_b}" '$a == $b'
}

ctx_test__jq_ver_cmp() {
  local _a="$1" _b="$2"
  json__query -L "${LIB_ROOT}" --arg a "${_a}" --arg b "${_b}" \
    -n 'include "ctx-match"; ver_cmp_jq($a; $b) | tostring'
}

ctx_test__run_vector_file() {
  local _file="$1" _runner="$2"
  local _yq _count _i
  _yq="$(ctx_test__require_yq)" || {
    echo "yq unavailable" >&2
    return 1
  }
  _count="$("${_yq}" '. | length' "${_file}")"
  for ((_i = 0; _i < _count; _i++)); do
    local _name _expect
    _name="$("${_yq}" -r ".[${_i}].name" "${_file}")"
    _expect="$("${_yq}" -r ".[${_i}].expect" "${_file}")"
    "${_runner}" "${_file}" "${_i}" "${_name}" "${_expect}" || return 1
  done
}

ctx_test__jq_when() {
  local _yaml="$1" _when_json _ctx_json _result _yq
  bootstrap__yq > /dev/null || return 1
  _yq="$(bootstrap__yq)"
  _when_json="$(printf '%s' "${_yaml}" | "${_yq}" -o=json '.' -)"
  _ctx_json="$(ctx__json)"
  _result="$(json__query -L "${LIB_ROOT}" --argjson ctx "${_ctx_json}" --argjson when "${_when_json}" \
    -n -f "${LIB_ROOT}/ctx-when-eval.jq" 2> /dev/null || echo false)"
  printf '%s' "${_result}"
}

ctx_test__load_vector_ctx() {
  local _file="$1" _index="$2"
  local _yq _pair
  _yq="$(ctx_test__require_yq)" || return 1
  ctx__reset
  while IFS= read -r _pair; do
    [[ -n "${_pair}" && "${_pair}" == *"="* ]] || continue
    [[ -n "${_pair%%=*}" ]] || continue
    ctx__set "${_pair}"
  done < <("${_yq}" -r ".[${_index}].ctx | to_entries | .[] | \"\\(.key)=\\(.value)\"" "${_file}" 2> /dev/null || true)
  _CTX__REGISTRY_INITIALIZED=true
}

ctx_test__vector_when_yaml() {
  local _file="$1" _index="$2"
  local _yq
  _yq="$(ctx_test__require_yq)" || return 1
  "${_yq}" -r ".[${_index}].when" "${_file}"
}

_when_vector__bash_runner() {
  local _file="$1" _index="$2" _name="$3" _expect="$4"
  local _yaml _rc=0
  ctx_test__load_vector_ctx "${_file}" "${_index}"
  _yaml="$(ctx_test__vector_when_yaml "${_file}" "${_index}")"
  if [[ "${_expect}" == true ]]; then
    ctx__match_when "${_yaml}" || _rc=$?
    [[ ${_rc} -eq 0 ]] || {
      echo "vector ${_name}: expected bash match (file=${_file} index=${_index})" >&2
      return 1
    }
  else
    ctx__match_when "${_yaml}" && {
      echo "vector ${_name}: expected bash non-match" >&2
      return 1
    }
  fi
}

_when_vector__jq_runner() {
  local _file="$1" _index="$2" _name="$3" _expect="$4"
  local _yaml _result
  ctx_test__load_vector_ctx "${_file}" "${_index}"
  _yaml="$(ctx_test__vector_when_yaml "${_file}" "${_index}")"
  _result="$(ctx_test__jq_when "${_yaml}" 2> /dev/null || echo false)"
  if [[ "${_expect}" == true ]]; then
    [[ "${_result}" == true ]] || {
      echo "vector ${_name}: expected jq match got ${_result} (file=${_file} index=${_index})" >&2
      return 1
    }
  else
    [[ "${_result}" == false ]] || {
      echo "vector ${_name}: expected jq non-match got ${_result}" >&2
      return 1
    }
  fi
}

ctx_test__run_when_vectors() {
  local _file
  _file="$(ctx_test__fixtures_dir)/when_vectors.yaml"
  ctx_test__run_vector_file "${_file}" _when_vector__bash_runner
  ctx_test__run_vector_file "${_file}" _when_vector__jq_runner
}

_id_like__bash_runner() {
  local _file="$1" _index="$2" _name="$3" _expect="$4"
  local _yq _actual _op _expected _rc=0
  _yq="$(ctx_test__require_yq)" || return 1
  _actual="$("${_yq}" -r ".[${_index}].actual" "${_file}")"
  _op="$("${_yq}" -r ".[${_index}].op" "${_file}")"
  _expected="$("${_yq}" -r ".[${_index}].expected" "${_file}")"
  ctx__set "os.id_like=${_actual}"
  _CTX__REGISTRY_INITIALIZED=true
  if [[ "${_expect}" == true ]]; then
    ctx__compare os.id_like "${_op}" "${_expected}" || _rc=$?
    [[ ${_rc} -eq 0 ]] || {
      echo "id_like ${_name}: expected bash true" >&2
      return 1
    }
  else
    ctx__compare os.id_like "${_op}" "${_expected}" && {
      echo "id_like ${_name}: expected bash false" >&2
      return 1
    }
  fi
}

_id_like__jq_runner() {
  local _file="$1" _index="$2" _name="$3" _expect="$4"
  local _yq _actual _op _expected _when _result
  _yq="$(ctx_test__require_yq)" || return 1
  _actual="$("${_yq}" -r ".[${_index}].actual" "${_file}")"
  _op="$("${_yq}" -r ".[${_index}].op" "${_file}")"
  _expected="$("${_yq}" -r ".[${_index}].expected" "${_file}")"
  ctx__set "os.id_like=${_actual}"
  _CTX__REGISTRY_INITIALIZED=true
  if [[ "${_op}" == eq || "${_op}" == ne ]]; then
    if [[ "${_expected}" == *"|"* ]]; then
      local _item _lines=$'os.id_like:\n  '"${_op}"':'
      IFS='|' read -ra _items <<< "${_expected}"
      for _item in "${_items[@]}"; do
        _lines+=$'\n    - '"${_item}"
      done
      _when="${_lines}"
    else
      _when=$'os.id_like:\n  '"${_op}"': '"${_expected}"
    fi
  else
    _when=$'os.id_like:\n  '"${_op}"': "'"${_expected}"'"'
  fi
  _result="$(ctx_test__jq_when "${_when}" 2> /dev/null || echo false)"
  if [[ "${_expect}" == true ]]; then
    [[ "${_result}" == true ]] || {
      echo "id_like ${_name}: expected jq true got ${_result}" >&2
      return 1
    }
  else
    [[ "${_result}" == false ]] || {
      echo "id_like ${_name}: expected jq false got ${_result}" >&2
      return 1
    }
  fi
}

ctx_test__run_id_like_matrix() {
  local _file
  _file="$(ctx_test__fixtures_dir)/id_like_matrix.yaml"
  ctx_test__run_vector_file "${_file}" _id_like__bash_runner
  ctx_test__run_vector_file "${_file}" _id_like__jq_runner
}

# ctx_test__stub_ospkg_pm pm=<key> [deb_arch=<value>]
#
# Stub ospkg__pm_key / ospkg__deb_arch so _ctx__ensure_registry copies deterministic
# PM state into plat.pm / plat.deb_arch without relying on the host image.
ctx_test__stub_ospkg_pm() {
  _CTX_TEST__STUB_PM=""
  _CTX_TEST__STUB_DEB_ARCH=""
  local _pair _k _v
  for _pair in "$@"; do
    _k="${_pair%%=*}"
    _v="${_pair#*=}"
    case "${_k}" in
      pm) _CTX_TEST__STUB_PM="${_v}" ;;
      deb_arch) _CTX_TEST__STUB_DEB_ARCH="${_v}" ;;
    esac
  done
  # shellcheck disable=SC2329  # exported stub for bats run subshells
  ospkg__pm_key() {
    printf '%s' "${_CTX_TEST__STUB_PM}"
    return 0
  }
  # shellcheck disable=SC2329  # exported stub for bats run subshells
  ospkg__deb_arch() {
    printf '%s' "${_CTX_TEST__STUB_DEB_ARCH}"
    return 0
  }
  export -f ospkg__pm_key ospkg__deb_arch
}

ctx_test__stub_darwin_platform() {
  # Prime a host-platform jq BEFORE stubbing uname to Darwin. ctx__json needs
  # jq, and if it isn't already on PATH (as in CI's minimal lib-test envs)
  # bootstrap__jq downloads it for the *currently detected* platform. Once
  # uname reports Darwin, that download would be a macOS jq — a Mach-O binary
  # that can't execute on the Linux runner ("cannot execute binary file: Exec
  # format error"), failing every ctx__json call in the darwin-stub tests.
  # Bootstrapping here (while uname is still real) records the correct Linux jq
  # in install-state, which the later stubbed ctx__json reuses instead of
  # re-downloading. On a real macOS host this is a harmless no-op (jq is
  # already present); the stub is only ever applied on Linux CI runners.
  bootstrap__jq > /dev/null 2>&1 || true
  # shellcheck disable=SC2329  # exported for use in subshells via export -f
  uname() {
    case "${1:-}" in
      -s) printf '%s\n' "Darwin" ;;
      -m) printf '%s\n' "arm64" ;;
      *) printf '%s\n' "Darwin" ;;
    esac
  }
  # shellcheck disable=SC2329  # exported for use in subshells via export -f
  sw_vers() {
    case "${1:-}" in
      -productName) printf '%s\n' "macOS" ;;
      -productVersion) printf '%s\n' "14.2.1" ;;
      -buildVersion) printf '%s\n' "23C71" ;;
      -productVersionExtra) printf '%s\n' "" ;;
      *) return 0 ;;
    esac
  }
  export -f uname sw_vers
}

ctx_test__json_get() {
  local _json="$1" _key="$2"
  json__query -r --arg k "${_key}" '.[$k] // empty' <<< "${_json}"
}

ctx_test__registry_keys_from_json() {
  local _json="$1"
  json__query -r 'keys[]' <<< "${_json}"
}
