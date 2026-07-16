# shellcheck shell=bash
# Git helpers: shallow clone and other repository operations.
#
# `git__clone` performs a `--depth=1` clone and is idempotent: it skips the
# clone if the target directory already contains a `.git` directory.

# Client-side git config flags applied to all clone/fetch operations in this module.
# core.eol/autocrlf: enforce LF in Linux containers.
# fsck/fetch.fsck zeroPaddedFilemode: tolerate historical repos (e.g. ohmyzsh) with
# zero-padded filemode entries. receive.fsck is a server-side setting and is
# intentionally omitted — it has no effect on a git client doing clone or fetch.
_GIT__CONF=(
  -c core.eol=lf
  -c core.autocrlf=false
  -c fsck.zeroPaddedFilemode=ignore
  -c fetch.fsck.zeroPaddedFilemode=ignore
)

git__resolve_ref() {
  # @brief git__resolve_ref <url> <ref> — Probe the remote and return the SHA for <ref>.
  #
  # If <ref> is advertised as a named ref (branch or tag), prints its remote SHA.
  # If not found, prints <ref> unchanged (caller treats it as a commit SHA).
  #
  # Args:
  #   <url>  Repository URL.
  #   <ref>  Branch name, tag name, or commit SHA.
  #
  # Returns: 0 on success, 1 when the remote probe fails after retrying. An
  # empty successful response still means that <ref> is not a named ref and
  # is returned unchanged so callers can try the commit-SHA path.
  local _raw _remote_sha
  _raw="$(net__fetch_with_retry --retry-if _git__retryable_error git ls-remote "$1" "$2")" || {
    logging__error "failed to resolve ref '$2' from '$1'."
    return 1
  }
  # Prefer the peeled (^{}) entry for annotated tags: it holds the commit SHA,
  # which matches git__head_sha after checkout. Branches and lightweight tags
  # produce no ^{} line, so the grep returns empty and we fall back to head -1.
  _remote_sha="$(printf '%s\n' "${_raw}" | grep $'\t.*\^{}$' | cut -f1 | head -1 || true)"
  if [[ -z "${_remote_sha}" ]]; then
    _remote_sha="$(printf '%s\n' "${_raw}" | head -1 | cut -f1 || true)"
  fi
  printf '%s\n' "${_remote_sha:-$2}"
}

_git__retryable_error() {
  # @brief _git__retryable_error <exit-code> <stderr-file> — Return success unless a Git failure is certainly persistent for an unchanged read operation.
  #
  # Clone/fetch/ls-remote are idempotent at this layer. Git has many transport
  # backends and diagnostic formats, so an allowlist of transient messages is
  # unsafe: Git's normal "requested URL returned error: 503" wording does not
  # resemble a literal "HTTP 503". Only clear malformed URL/protocol and
  # credential failures stop retries.
  local _rc="$1" _stderr_file="$2"
  [ "$_rc" -ne 0 ] || return 1
  if grep -Eiq \
    'authentication failed|authentication is required|terminal prompts disabled|could not read Username|invalid url|url using bad/illegal format|unsupported protocol|protocol .* not supported|not a git repository' \
    "$_stderr_file"; then
    return 1
  fi
  return 0
}

_git__fetch_sha_attempt() {
  local _dir="$1" _sha="$2"
  git -C "${_dir}" "${_GIT__CONF[@]}" -c protocol.version=2 \
    fetch --depth=1 origin "${_sha}" && return 0
  git -C "${_dir}" "${_GIT__CONF[@]}" fetch origin "${_sha}"
}

_git__clone_named_attempt() {
  local _url="$1" _dir="$2" _ref="$3"
  rm -rf "${_dir}" 2> /dev/null || true
  git clone --depth=1 "${_GIT__CONF[@]}" --branch "${_ref}" "${_url}" "${_dir}"
}

_git__clone_default_attempt() {
  local _url="$1" _dir="$2"
  rm -rf "${_dir}" 2> /dev/null || true
  git clone --depth=1 "${_GIT__CONF[@]}" "${_url}" "${_dir}"
}

_git__fetch_sha() {
  # _git__fetch_sha <dir> <sha> — Fetch a specific commit SHA into an existing repo.
  #
  # Tries a protocol-v2 shallow fetch first (works on GitHub and modern servers);
  # falls back to a full (non-shallow) fetch if the server rejects it.
  # The repo at <dir> must already have `origin` configured.
  #
  # Returns: 0 on success, 1 on failure.
  local _dir="$1" _sha="$2"
  net__fetch_with_retry --retry-if _git__retryable_error _git__fetch_sha_attempt "${_dir}" "${_sha}" || {
    logging__error "fetch of SHA '${_sha}' failed in '${_dir}'."
    return 1
  }
  git -C "${_dir}" checkout FETCH_HEAD 2>&1 || {
    logging__error "checkout of FETCH_HEAD failed in '${_dir}'."
    return 1
  }
}

git__clone() {
  # @brief git__clone --url <url> --dir <dir> [--ref <ref>] [--resolved-sha <sha>] — Shallow clone (`--depth=1`) of `<url>` into `<dir>`. Idempotent: skips if `<dir>/.git` already exists.
  #
  # On failure, any partially-created `<dir>` is removed so that a re-run does
  # not silently skip a broken clone.
  #
  # Ref handling:
  #   Named refs (branches/tags): probed via `git ls-remote` (or supplied via
  #                              --resolved-sha); cloned with `--branch`.
  #   Commit SHAs:               not found by ls-remote; cloned via `git init` +
  #                              `_git__fetch_sha` (protocol v2, with non-shallow
  #                              fallback).
  #
  # The umask is set to `g-w,o-w` during the clone so cloned files are not
  # group/world-writable. It is restored on every exit path.
  #
  # Args:
  #   --url <url>           Repository URL to clone.
  #   --dir <dir>           Local destination directory.
  #   --ref <ref>           Branch, tag, or commit SHA to check out (optional; defaults to HEAD).
  #   --resolved-sha <sha>  Pre-resolved SHA from git__resolve_ref (optional). When
  #                         provided the ls-remote probe is skipped; sha == ref means
  #                         SHA path, sha != ref means named-ref path.
  #
  # Returns: 0 on success or if already cloned, 1 on failure.
  local ref="" dir="" url="" resolved_sha=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --ref)
        shift
        ref="$1"
        shift
        ;;
      --dir)
        shift
        dir="$1"
        shift
        ;;
      --url)
        shift
        url="$1"
        shift
        ;;
      --resolved-sha)
        shift
        resolved_sha="$1"
        shift
        ;;
      --*)
        logging__error "unknown option '${1}'"
        return 1
        ;;
      *)
        logging__error "unexpected argument '${1}'"
        return 1
        ;;
    esac
  done
  [ -z "${dir}" ] && {
    logging__error "missing --dir"
    return 1
  }
  [ -z "${url}" ] && {
    logging__error "missing --url"
    return 1
  }

  if [ -d "${dir}/.git" ]; then
    logging__skip "Repository already cloned at '${dir}' — skipping clone."
    return 0
  fi

  # shellcheck disable=SC2016
  logging__download "Cloning '${url}' into '${dir}'${ref:+ (ref='${ref}')}."

  # Auto-provision git if not yet available (idempotent if already installed).
  logging__install "Ensuring git is available before clone."
  bootstrap__git

  # Restrict permissions of all files created during the clone.
  local _prev_umask
  _prev_umask="$(umask)"
  umask g-w,o-w

  if [[ -n "${ref}" ]]; then
    # Probe the remote: if the ref is advertised (branch or tag), use --branch.
    # If not found as a named ref, treat it as a commit SHA.
    # Use a pre-resolved SHA when provided by the caller (avoids a second ls-remote).
    local _probed_sha
    if [[ -n "${resolved_sha}" ]]; then
      _probed_sha="${resolved_sha}"
    else
      if ! _probed_sha="$(git__resolve_ref "${url}" "${ref}")"; then
        umask "${_prev_umask}"
        rm -rf "${dir}" 2> /dev/null || true
        logging__error "could not resolve ref '${ref}' from '${url}'."
        return 1
      fi
    fi

    if [[ "${_probed_sha}" != "${ref}" ]]; then
      # Named ref (branch or tag) — _probed_sha is its remote SHA.
      if ! net__fetch_with_retry --retry-if _git__retryable_error _git__clone_named_attempt "${url}" "${dir}" "${ref}"; then
        umask "${_prev_umask}"
        rm -rf "${dir}" 2> /dev/null || true
        logging__error "git clone of '${url}' (ref '${ref}') failed."
        return 1
      fi
    else
      # Not a named ref — treat as commit SHA.
      # Use git init + protocol-v2 fetch, which allows fetching specific commits
      # on GitHub (uploadpack.allowReachableSHA1InWant) and most modern servers.
      mkdir -p "${dir}"
      if ! git "${_GIT__CONF[@]}" init "${dir}" 2>&1; then
        umask "${_prev_umask}"
        rm -rf "${dir}" 2> /dev/null || true
        logging__error "git init of '${dir}' failed."
        return 1
      fi
      if ! git -C "${dir}" remote add origin "${url}" 2>&1; then
        umask "${_prev_umask}"
        rm -rf "${dir}" 2> /dev/null || true
        logging__error "git remote add for '${url}' failed."
        return 1
      fi
      if ! _git__fetch_sha "${dir}" "${ref}"; then
        umask "${_prev_umask}"
        rm -rf "${dir}" 2> /dev/null || true
        logging__error "git fetch/checkout of SHA '${ref}' from '${url}' failed."
        return 1
      fi
    fi
  else
    # No ref → clone the remote's default branch.
    if ! net__fetch_with_retry --retry-if _git__retryable_error _git__clone_default_attempt "${url}" "${dir}"; then
      umask "${_prev_umask}"
      rm -rf "${dir}" 2> /dev/null || true
      logging__error "git clone of '${url}' failed."
      return 1
    fi
  fi

  umask "${_prev_umask}"
  return 0
}

git__config() {
  # @brief git__config <dir> <key>=<val> [<key>=<val> ...] — Set one or more git config entries in a repository.
  #
  # Args:
  #   <dir>          Path to the git repository.
  #   <key>=<val>    One or more key=value pairs. The key is everything before the first `=`.
  #
  # Returns: 0 on success, 1 on any failure.
  local _dir="$1"
  shift
  [ -z "${_dir}" ] && {
    logging__error "missing directory argument"
    return 1
  }
  [ "$#" -eq 0 ] && return 0

  logging__install "Ensuring git is available before config."
  bootstrap__git

  local _pair _key _val
  for _pair in "$@"; do
    _key="${_pair%%=*}"
    _val="${_pair#*=}"
    if ! git -C "${_dir}" config "${_key}" "${_val}" 2>&1; then
      logging__error "failed to set '${_key}' in '${_dir}'."
      return 1
    fi
  done
  return 0
}

git__update() {
  # @brief git__update <dir> [--ref <ref>] [--resolved-sha <sha>] — Fetch and update an existing git clone to the specified ref.
  #
  # Sequence for named refs (branches/tags):
  #   1. git fetch --depth=1 origin  (uses the repo's configured refspecs)
  #   2. git checkout <ref>
  #   3. If on a branch (not detached HEAD): git merge --ff-only
  #
  # Sequence for commit SHAs (ref not found as a named ref on the remote):
  #   1. _git__fetch_sha — protocol-v2 shallow fetch with non-shallow fallback
  #   2. git checkout FETCH_HEAD
  #
  # Args:
  #   <dir>                 Path to the git repository.
  #   --ref <ref>           Branch, tag, or SHA to check out (optional; defaults to refreshing the current branch).
  #   --resolved-sha <sha>  Pre-resolved SHA from git__resolve_ref (optional). When
  #                         provided the ls-remote probe is skipped; sha == ref means
  #                         SHA path, sha != ref means named-ref path.
  #
  # Returns: 0 on success, 1 on any failure.
  local _dir="$1"
  shift
  [ -z "${_dir}" ] && {
    logging__error "missing directory argument"
    return 1
  }

  logging__install "Ensuring git is available before update."
  bootstrap__git

  local _ref="" resolved_sha=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --ref)
        shift
        _ref="$1"
        shift
        ;;
      --resolved-sha)
        shift
        resolved_sha="$1"
        shift
        ;;
      *)
        logging__error "unknown argument '${1}'"
        return 1
        ;;
    esac
  done

  # shellcheck disable=SC2016
  logging__download "Updating git repository at '${_dir}'${_ref:+ to ref '${_ref}'}."
  if [[ -n "${_ref}" ]]; then
    # Determine whether _ref is a named ref (branch/tag) or a commit SHA.
    local _probed_sha
    if [[ -n "${resolved_sha}" ]]; then
      _probed_sha="${resolved_sha}"
    else
      local _origin_url
      _origin_url="$(git -C "${_dir}" remote get-url origin 2> /dev/null || true)"
      if ! _probed_sha="$(git__resolve_ref "${_origin_url}" "${_ref}")"; then
        logging__error "could not resolve ref '${_ref}' from '${_origin_url}'."
        return 1
      fi
    fi

    if [[ "${_probed_sha}" != "${_ref}" ]]; then
      # Named ref — fetch via the repo's configured refspecs, checkout, merge.
      if ! net__fetch_with_retry --retry-if _git__retryable_error git -C "${_dir}" "${_GIT__CONF[@]}" fetch --depth=1 origin; then
        logging__error "fetch failed in '${_dir}'."
        return 1
      fi
      if ! git -C "${_dir}" checkout "${_ref}" 2>&1; then
        logging__error "checkout of '${_ref}' failed in '${_dir}'."
        return 1
      fi
      if git__symbolic_ref "${_dir}" > /dev/null 2>&1; then
        if ! git -C "${_dir}" merge --ff-only 2>&1; then
          logging__error "fast-forward merge failed in '${_dir}'."
          return 1
        fi
      fi
    else
      # Commit SHA — use the same protocol-v2 fetch helper as git__clone.
      if ! _git__fetch_sha "${_dir}" "${_ref}"; then
        logging__error "failed to fetch SHA '${_ref}' in '${_dir}'."
        return 1
      fi
    fi
  else
    # No ref — refresh the current branch using the configured refspecs.
    if ! net__fetch_with_retry --retry-if _git__retryable_error git -C "${_dir}" "${_GIT__CONF[@]}" fetch --depth=1 origin; then
      logging__error "fetch failed in '${_dir}'."
      return 1
    fi
    if git__symbolic_ref "${_dir}" > /dev/null 2>&1; then
      if ! git -C "${_dir}" merge --ff-only 2>&1; then
        logging__error "fast-forward merge failed in '${_dir}'."
        return 1
      fi
    fi
  fi

  return 0
}

git__symbolic_ref() {
  # @brief git__symbolic_ref <dir> — Check whether HEAD is a symbolic ref (i.e. on a branch).
  #
  # Args:
  #   <dir>  Path to the git repository.
  #
  # Returns: 0 if on a branch, 1 if in detached-HEAD state or on error.
  local _dir="$1"
  [ -z "${_dir}" ] && {
    logging__error "missing directory argument"
    return 1
  }
  git -C "${_dir}" symbolic-ref --quiet HEAD > /dev/null
}

git__head_sha() {
  # @brief git__head_sha <dir> — Print the full SHA of HEAD.
  #
  # Args:
  #   <dir>  Path to the git repository.
  #
  # Returns: 0 on success, non-zero (typically 128) if not a git repository or on error.
  local _dir="$1"
  [ -z "${_dir}" ] && {
    logging__error "missing directory argument"
    return 1
  }
  git -C "${_dir}" rev-parse HEAD 2> /dev/null
}
