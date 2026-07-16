#!/bin/sh

_STATE_DIR="${_FEAT_SHARE_DIR_ROOT}/state"
_STATE_FILE="${_STATE_DIR}/config.env"

[ -f "${_STATE_FILE}" ] || exit 0

# shellcheck disable=SC1090
. "${_STATE_FILE}"

_workspace_dir="${1-}"
_repo_dir="${GIT_LFS_STATE_REPO_DIR:-}"
[ -n "${_repo_dir}" ] || _repo_dir="${_workspace_dir}"

_scope="${GIT_LFS_STATE_CONFIG_SCOPE:-none}"
_skip_repo="${GIT_LFS_STATE_SKIP_REPO:-true}"
_skip_smudge="${GIT_LFS_STATE_SKIP_SMUDGE:-false}"
_force_config="${GIT_LFS_STATE_FORCE_CONFIG:-false}"
_manual_hooks="${GIT_LFS_STATE_MANUAL_HOOKS:-false}"
_auto_pull="${GIT_LFS_STATE_AUTO_PULL:-true}"
_config_file="${GIT_LFS_STATE_CONFIG_FILE:-}"

_needs_repo=false
if [ "${_scope}" != "none" ]; then
  case "${_scope}" in
    local | worktree | file) _needs_repo=true ;;
  esac
  [ "${_skip_repo}" = "false" ] && _needs_repo=true
fi

if [ "${_needs_repo}" = true ]; then
  if [ -z "${_repo_dir}" ]; then
    printf '[%s] No repository directory resolved; skipping deferred Git LFS repo configuration.\n' "$(basename "$0")" >&2
    exit 0
  fi
  if ! git -C "${_repo_dir}" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    printf '[%s] %s is not a Git work tree; skipping deferred Git LFS repo configuration.\n' "$(basename "$0")" "${_repo_dir}" >&2
    exit 0
  fi
fi

if [ "${_scope}" = "file" ] && [ -n "${_config_file}" ] && [ "${_config_file#"/"}" = "${_config_file}" ]; then
  _config_file="${_repo_dir%/}/${_config_file}"
fi

case "${_scope}" in
  local | worktree | file)
    if [ "${_scope}" = "worktree" ]; then
      git -C "${_repo_dir}" config extensions.worktreeConfig true
    fi

    set -- install
    case "${_scope}" in
      local) set -- "$@" --local ;;
      worktree) set -- "$@" --worktree ;;
      file) set -- "$@" "--file=${_config_file}" ;;
    esac
    [ "${_skip_repo}" = "true" ] && set -- "$@" --skip-repo
    [ "${_skip_smudge}" = "true" ] && set -- "$@" --skip-smudge
    [ "${_force_config}" = "true" ] && set -- "$@" --force
    if [ "${_skip_repo}" = "true" ] && [ "${_manual_hooks}" = "true" ]; then
      printf '[%s] manual_hooks=true has no effect when skip_repo=true; ignoring.\n' "$(basename "$0")" >&2
    elif [ "${_manual_hooks}" = "true" ]; then
      set -- "$@" --manual
    fi

    printf '[%s] Applying deferred Git LFS configuration in %s.\n' "$(basename "$0")" "${_repo_dir}" >&2
    git -C "${_repo_dir}" lfs "$@"
    ;;
esac

[ "${_auto_pull}" = "true" ] || exit 0
[ -n "${_repo_dir}" ] || exit 0
git -C "${_repo_dir}" rev-parse --is-inside-work-tree > /dev/null 2>&1 || exit 0
git -C "${_repo_dir}" lfs ls-files 2> /dev/null | grep -q . || exit 0

if ! git -C "${_repo_dir}" config --get filter.lfs.process > /dev/null 2>&1; then
  printf '[%s] Git LFS filters are not active in %s; bootstrapping local config for auto_pull.\n' "$(basename "$0")" "${_repo_dir}" >&2
  git -C "${_repo_dir}" lfs install --local --skip-repo || exit $?
fi

printf '[%s] Running git lfs pull in %s.\n' "$(basename "$0")" "${_repo_dir}" >&2
_pull_max="${DEVFEATS_NET_FETCH_RETRIES:-5}"
_pull_delay="${DEVFEATS_NET_FETCH_DELAY:-5}"
_pull_attempt=1
while [ "${_pull_attempt}" -le "${_pull_max}" ]; do
  _pull_err="$(mktemp "${TMPDIR:-/tmp}/devfeats-git-lfs.XXXXXX")" || exit 1
  _pull_rc=0
  git -C "${_repo_dir}" lfs pull 2> "${_pull_err}" || _pull_rc=$?
  cat "${_pull_err}" >&2
  if [ "${_pull_rc}" -eq 0 ]; then
    rm -f "${_pull_err}"
    exit 0
  fi
  # `git lfs pull` is an idempotent read. Git/LFS diagnostics vary across
  # versions and transports, so retry every failure except clear local URL or
  # credential configuration errors. In particular, Git often renders a 503 as
  # "The requested URL returned error: 503", which a narrow HTTP regex misses.
  if ! grep -Eiq 'authentication failed|authentication is required|terminal prompts disabled|could not read Username|invalid url|url using bad/illegal format|unsupported protocol|protocol .* not supported|not a git repository|x509: certificate signed by unknown authority|certificate verify failed' "${_pull_err}" && [ "${_pull_attempt}" -lt "${_pull_max}" ]; then
    printf '[%s] Git LFS pull attempt %s/%s failed; retrying in %ss.\n' "$(basename "$0")" "${_pull_attempt}" "${_pull_max}" "${_pull_delay}" >&2
    rm -f "${_pull_err}"
    sleep "${_pull_delay}"
    _pull_attempt=$((_pull_attempt + 1))
    continue
  fi
  rm -f "${_pull_err}"
  exit "${_pull_rc}"
done
exit 1
