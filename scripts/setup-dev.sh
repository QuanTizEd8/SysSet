#!/usr/bin/env bash
# setup-dev.sh — Install development tools for sysset.
# Usage: bash scripts/setup-dev.sh [--tools tool1,tool2,...]
#
# Available tools: pyyaml shfmt shellcheck devcontainers-cli lefthook
# Default (no --tools flag): install all tools.
#
# Designed to be idempotent — skips tools already installed at the required version.
# Works on macOS (Homebrew) and Debian/Ubuntu Linux (apt-get).
set -euo pipefail

# ── Pinned versions ────────────────────────────────────────────────────────────
SHFMT_VERSION="v3.10.0"

# ── Parse --tools flag ─────────────────────────────────────────────────────────
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_REPO_ROOT="$(cd "${_SCRIPT_DIR}/.." && pwd)"

_ALL_TOOLS="pyyaml shfmt shellcheck devcontainers-cli lefthook"
_tools="${_ALL_TOOLS}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tools)
      _tools="${2//,/ }"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# ── Detect OS ─────────────────────────────────────────────────────────────────
_os="$(uname -s)"

# ── Helper: check if a command exists ─────────────────────────────────────────
_has() { command -v "$1" > /dev/null 2>&1; }

# ── Install functions ──────────────────────────────────────────────────────────

_install_pyyaml() {
  echo "▶ Installing PyYAML..." >&2
  pip3 install -r "${_REPO_ROOT}/requirements.txt"
  echo "✅ PyYAML installed." >&2
}

_install_shfmt() {
  if _has shfmt && [[ "$(shfmt --version 2> /dev/null)" == "${SHFMT_VERSION}" ]]; then
    echo "✅ shfmt ${SHFMT_VERSION} already installed — skipping." >&2
    return
  fi
  echo "▶ Installing shfmt ${SHFMT_VERSION}..." >&2
  if [[ "$_os" == "Darwin" ]]; then
    # Homebrew doesn't pin versions easily; install via curl same as Linux
    _arch="$(uname -m)"
    [[ "$_arch" == "arm64" ]] && _arch="arm64" || _arch="amd64"
    _shfmt_bin="shfmt_${SHFMT_VERSION}_darwin_${_arch}"
  else
    _shfmt_bin="shfmt_${SHFMT_VERSION}_linux_amd64"
  fi
  curl -fsSL \
    "https://github.com/mvdan/sh/releases/download/${SHFMT_VERSION}/${_shfmt_bin}" \
    -o /usr/local/bin/shfmt
  chmod +x /usr/local/bin/shfmt
  echo "✅ shfmt ${SHFMT_VERSION} installed." >&2
}

_install_shellcheck() {
  if _has shellcheck; then
    echo "✅ shellcheck already installed — skipping." >&2
    return
  fi
  echo "▶ Installing shellcheck..." >&2
  if [[ "$_os" == "Darwin" ]]; then
    brew install shellcheck
  else
    apt-get install -y --no-install-recommends shellcheck
  fi
  echo "✅ shellcheck installed." >&2
}

_install_devcontainers_cli() {
  if _has devcontainer; then
    echo "✅ devcontainers-cli already installed — skipping." >&2
    return
  fi
  echo "▶ Installing @devcontainers/cli..." >&2
  npm install -g @devcontainers/cli
  echo "✅ @devcontainers/cli installed." >&2
}

_install_lefthook() {
  if _has lefthook; then
    echo "✅ lefthook already installed — skipping." >&2
    return
  fi
  echo "▶ Installing lefthook..." >&2
  npm install -g lefthook
  echo "✅ lefthook installed." >&2
}

# ── Dispatch ───────────────────────────────────────────────────────────────────
for _tool in $_tools; do
  case "$_tool" in
    pyyaml) _install_pyyaml ;;
    shfmt) _install_shfmt ;;
    shellcheck) _install_shellcheck ;;
    devcontainers-cli) _install_devcontainers_cli ;;
    lefthook) _install_lefthook ;;
    *)
      echo "Unknown tool: $_tool" >&2
      exit 1
      ;;
  esac
done
