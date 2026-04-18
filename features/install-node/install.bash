_cleanup_hook() {
  echo "↪️ Function entry: _cleanup_hook" >&2
  [ -n "${INSTALLER_DIR-}" ] && rm -rf "$INSTALLER_DIR" 2> /dev/null || true
  if [ "${_NVM_CLEANUP_ENABLED-}" = "true" ] && [ -n "${NVM_DIR-}" ] && [ -f "${NVM_DIR}/nvm.sh" ] && [ -n "${_NVM_USER-}" ]; then
    su "$_NVM_USER" -c ". '${NVM_DIR}/nvm.sh' && nvm clear-cache" 2> /dev/null || true
  fi
  echo "↩️ Function exit: _cleanup_hook" >&2
}

# _node_build_platform_string
# Outputs a nodejs.org platform string (e.g. linux-x64, darwin-arm64).
# Arguments: kernel arch
_node_build_platform_string() {
  echo "↪️ Function entry: _node_build_platform_string" >&2
  local _kernel="$1"
  local _arch="$2"

  # Normalise: Darwin aarch64 → arm64 (user-supplied override may use either form)
  if [ "$_kernel" = "Darwin" ] && [ "$_arch" = "aarch64" ]; then
    _arch="arm64"
  fi

  local _platform=""
  case "${_kernel}:${_arch}" in
    Linux:x86_64) _platform="linux-x64" ;;
    Linux:aarch64) _platform="linux-arm64" ;;
    Linux:arm64) _platform="linux-arm64" ;;
    Linux:armv7l) _platform="linux-armv7l" ;;
    Linux:ppc64le) _platform="linux-ppc64le" ;;
    Linux:s390x) _platform="linux-s390x" ;;
    Darwin:x86_64) _platform="darwin-x64" ;;
    Darwin:arm64) _platform="darwin-arm64" ;;
    *)
      echo "⛔ Unsupported kernel/arch combination for Node.js binary: ${_kernel}/${_arch}" >&2
      echo "   Use method=nvm for source-based installation on unsupported architectures." >&2
      return 1
      ;;
  esac
  echo "$_platform"
  echo "↩️ Function exit: _node_build_platform_string → ${_platform}" >&2
  return 0
}

# _node_resolve_binary_version
# Resolves a version spec to an exact vX.Y.Z string using a downloaded index.json.
# Arguments: version_spec index_json_path
_node_resolve_binary_version() {
  echo "↪️ Function entry: _node_resolve_binary_version" >&2
  local _spec="$1"
  local _index="$2"

  # Normalise "lts" alias → "lts/*"
  [ "$_spec" = "lts" ] && _spec="lts/*"

  local _resolved=""
  case "$_spec" in
    "lts/*")
      # First entry that is NOT "lts":false
      _resolved="$(grep -v '"lts":false' "$_index" | grep -o '"version":"v[^"]*"' | head -1 | grep -o 'v[^"]*')"
      ;;
    "latest" | "node")
      # First entry (highest version)
      _resolved="$(grep -o '"version":"v[^"]*"' "$_index" | head -1 | grep -o 'v[^"]*')"
      ;;
    [0-9]*)
      # Bare major number: find first release starting with vN.
      _resolved="$(grep -o "\"version\":\"v${_spec}\.[^\"]*\"" "$_index" | head -1 | grep -o 'v[^"]*')"
      ;;
    v[0-9]*\.*\.[0-9]*)
      # Exact semver with leading v
      _resolved="$_spec"
      # Verify it exists in index.json
      if ! grep -q "\"version\":\"${_spec}\"" "$_index"; then
        echo "⛔ Node.js version '${_spec}' was not found in nodejs.org/dist/index.json." >&2
        return 1
      fi
      ;;
    [0-9]*\.*\.[0-9]*)
      # Exact semver without leading v
      _resolved="v${_spec}"
      if ! grep -q "\"version\":\"v${_spec}\"" "$_index"; then
        echo "⛔ Node.js version '${_spec}' was not found in nodejs.org/dist/index.json." >&2
        return 1
      fi
      ;;
    *)
      echo "⛔ Version spec '${_spec}' is not supported by method=binary." >&2
      echo "   Supported formats: lts/*, latest, a major number (e.g. 22), or an exact semver." >&2
      echo "   nvm-style named LTS aliases (e.g. 'lts/iron') are not supported; use method=nvm instead." >&2
      return 1
      ;;
  esac

  if [ -z "$_resolved" ]; then
    echo "⛔ Could not resolve Node.js version '${_spec}' from index.json." >&2
    return 1
  fi

  echo "$_resolved"
  echo "↩️ Function exit: _node_resolve_binary_version → ${_resolved}" >&2
  return 0
}

# _node_check_if_exists
# Pre-install check: handles if_exists option for an existing node binary.
_node_check_if_exists() {
  echo "↪️ Function entry: _node_check_if_exists" >&2
  command -v node > /dev/null 2>&1 || {
    echo "↩️ Function exit: _node_check_if_exists (not found)" >&2
    return 0
  }

  local _installed_ver
  _installed_ver="$(node --version 2> /dev/null || true)"
  echo "ℹ️ Existing node found: ${_installed_ver}" >&2

  # For binary method: compare against the pre-resolved target version.
  if [ "$METHOD" = "binary" ] && [ -n "${_NODE_VERSION:-}" ] && [ "$_installed_ver" = "$_NODE_VERSION" ]; then
    echo "ℹ️ Node.js ${_NODE_VERSION} is already installed — skipping (version matches)." >&2
    exit 0
  fi

  # For nvm method with an exact semver spec: compare if possible.
  if [ "$METHOD" = "nvm" ]; then
    local _spec="$VERSION"
    [ "$_spec" = "lts" ] && _spec="lts/*"
    case "$_spec" in
      v[0-9]*\.*\.[0-9]* | [0-9]*\.*\.[0-9]*)
        local _target="v${_spec#v}"
        if [ "$_installed_ver" = "$_target" ]; then
          echo "ℹ️ Node.js ${_target} is already installed — skipping (version matches)." >&2
          exit 0
        fi
        ;;
    esac
  fi

  case "$IF_EXISTS" in
    skip)
      echo "ℹ️ node is already installed (${_installed_ver}) and if_exists=skip — skipping." >&2
      exit 0
      ;;
    fail)
      echo "⛔ node is already installed (${_installed_ver}) and if_exists=fail." >&2
      exit 1
      ;;
    reinstall)
      echo "ℹ️ node is already installed (${_installed_ver}) — reinstalling (if_exists=reinstall)." >&2
      if [ "$METHOD" = "binary" ]; then
        for _bin in node npm npx corepack; do
          local _p
          _p="$(command -v "$_bin" 2> /dev/null || true)"
          [ -n "$_p" ] && {
            echo "ℹ️ Removing ${_p}" >&2
            rm -f "$_p"
          }
        done
      elif [ "$METHOD" = "nvm" ]; then
        if [ -f "${NVM_DIR}/nvm.sh" ]; then
          # shellcheck disable=SC1091
          . "${NVM_DIR}/nvm.sh"
          local _ver_to_remove="$VERSION"
          [ "$_ver_to_remove" = "lts" ] && _ver_to_remove="lts/*"
          nvm uninstall "$_ver_to_remove" 2> /dev/null || true
        else
          echo "ℹ️ NVM_DIR/nvm.sh not found — skipping nvm uninstall (will install fresh)." >&2
        fi
      fi
      ;;
  esac

  echo "↩️ Function exit: _node_check_if_exists" >&2
  return 0
}

# _node_set_permissions
# Create nvm group, configure ownership/bits on NVM_DIR, add users to the group.
_node_set_permissions() {
  echo "↪️ Function entry: _node_set_permissions" >&2
  if [ "$(os__platform)" = "macos" ]; then
    echo "ℹ️ set_permissions is not supported on macOS (groupadd/usermod are unavailable) — skipping." >&2
    echo "↩️ Function exit: _node_set_permissions (skipped on macOS)" >&2
    return 0
  fi

  echo "ℹ️ Creating group '${GROUP}' and configuring permissions on '${NVM_DIR}'." >&2
  getent group "$GROUP" > /dev/null 2>&1 || groupadd -r "$GROUP"

  for _u in "${_RESOLVED_USERS[@]}"; do
    [[ -z "$_u" ]] && continue
    id -nG "$_u" 2> /dev/null | grep -qw "$GROUP" || {
      echo "ℹ️ Adding user '${_u}' to group '${GROUP}'." >&2
      usermod -a -G "$GROUP" "$_u"
    }
  done

  mkdir -p "$NVM_DIR"
  chown -R "${_RESOLVED_USERS[0]}:${GROUP}" "$NVM_DIR"
  chmod g+rws "$NVM_DIR"

  echo "↩️ Function exit: _node_set_permissions" >&2
  return 0
}

# _node_install_via_nvm
# Full nvm-based installation flow.
_node_install_via_nvm() {
  echo "↪️ Function entry: _node_install_via_nvm" >&2
  local _nvm_tag

  # Resolve nvm tag
  if [ "$NVM_VERSION" = "latest" ]; then
    echo "ℹ️ Resolving latest nvm release tag..." >&2
    _nvm_tag="$(github__latest_tag nvm-sh/nvm)"
    echo "ℹ️ Latest nvm tag: ${_nvm_tag}" >&2
  else
    _nvm_tag="v${NVM_VERSION#v}"
  fi

  echo "ℹ️ Installing nvm ${_nvm_tag}..." >&2

  # Download nvm install script
  mkdir -p "$INSTALLER_DIR"
  net__fetch_url_file \
    "https://raw.githubusercontent.com/nvm-sh/nvm/${_nvm_tag}/install.sh" \
    "${INSTALLER_DIR}/nvm-install.sh"

  # Create NVM_DIR before set_permissions (which chowns it)
  mkdir -p "$NVM_DIR"

  # Set permissions (creates group, configures ownership)
  if [ "$SET_PERMISSIONS" = "true" ] && [ "$(id -u)" = "0" ]; then
    _node_set_permissions
  fi

  # Mark nvm cleanup as active now that NVM_DIR is initialised
  _NVM_CLEANUP_ENABLED="true"

  # Run nvm installer as target user
  echo "ℹ️ Running nvm installer as user '${_NVM_USER}'..." >&2
  su "$_NVM_USER" -c \
    "umask 0002 && PROFILE=/dev/null NVM_SYMLINK_CURRENT=true NVM_DIR='${NVM_DIR}' bash '${INSTALLER_DIR}/nvm-install.sh'"

  # Verify nvm loaded (in root shell)
  # shellcheck disable=SC1091
  . "${NVM_DIR}/nvm.sh"
  command -v nvm > /dev/null 2>&1 || {
    echo "⛔ nvm command not found after installation." >&2
    return 1
  }
  echo "✅ nvm installed successfully." >&2

  # Normalise version; if none, skip Node.js install
  local _node_ver_spec="$VERSION"
  [ "$_node_ver_spec" = "lts" ] && _node_ver_spec="lts/*"

  if [ "$_node_ver_spec" = "none" ]; then
    echo "ℹ️ version=none — skipping Node.js installation." >&2
    if [ "${#ADDITIONAL_VERSIONS[@]}" -gt 0 ]; then
      echo "⚠️ VERSION=none with additional_versions: no default alias is set — run 'nvm alias default <version>' manually inside the container." >&2
      local _add_ver
      local _add_versions=("${ADDITIONAL_VERSIONS[@]}")
      for _add_ver in "${_add_versions[@]}"; do
        _add_ver="${_add_ver## }"
        _add_ver="${_add_ver%% }"
        [ -z "$_add_ver" ] && continue
        echo "ℹ️ Installing additional Node.js version: ${_add_ver}" >&2
        su "$_NVM_USER" -c "umask 0002 && . '${NVM_DIR}/nvm.sh' && nvm install '${_add_ver}'"
      done
    fi
    echo "↩️ Function exit: _node_install_via_nvm (version=none)" >&2
    return 0
  fi

  # Install primary version
  echo "ℹ️ Installing Node.js '${_node_ver_spec}' via nvm..." >&2
  if [ "$(os__platform)" = "alpine" ]; then
    echo "ℹ️ Alpine detected — compiling Node.js from source (nvm install -s)." >&2
    su "$_NVM_USER" -c "umask 0002 && . '${NVM_DIR}/nvm.sh' && nvm install -s '${_node_ver_spec}'"
  else
    su "$_NVM_USER" -c "umask 0002 && . '${NVM_DIR}/nvm.sh' && nvm install '${_node_ver_spec}'"
  fi

  # Set default alias
  su "$_NVM_USER" -c "umask 0002 && . '${NVM_DIR}/nvm.sh' && nvm alias default '${_node_ver_spec}'"

  # Restore primary version as active
  su "$_NVM_USER" -c "umask 0002 && . '${NVM_DIR}/nvm.sh' && nvm use default"

  # Capture exact version
  _NODE_VERSION="$(su "$_NVM_USER" -c "umask 0002 && . '${NVM_DIR}/nvm.sh' && nvm version '${_node_ver_spec}'")"
  echo "ℹ️ Installed Node.js version: ${_NODE_VERSION}" >&2

  # Fix version directory permissions (tarballs extracted by nvm may lack group-write)
  if [ -d "${NVM_DIR}/versions" ]; then
    chmod -R g+rw "${NVM_DIR}/versions"
  fi

  # Install additional versions
  if [ "${#ADDITIONAL_VERSIONS[@]}" -gt 0 ]; then
    local _add_ver
    local _add_versions=("${ADDITIONAL_VERSIONS[@]}")
    for _add_ver in "${_add_versions[@]}"; do
      _add_ver="${_add_ver## }"
      _add_ver="${_add_ver%% }"
      [ -z "$_add_ver" ] && continue
      echo "ℹ️ Installing additional Node.js version: ${_add_ver}" >&2
      su "$_NVM_USER" -c "umask 0002 && . '${NVM_DIR}/nvm.sh' && nvm install '${_add_ver}'"
    done
    # Restore default after additional installs
    su "$_NVM_USER" -c "umask 0002 && . '${NVM_DIR}/nvm.sh' && nvm use default"
  fi

  echo "✅ Node.js ${_NODE_VERSION} installed via nvm." >&2
  echo "↩️ Function exit: _node_install_via_nvm" >&2
  return 0
}

# _node_install_via_binary
# Full binary-tarball installation flow.
_node_install_via_binary() {
  echo "↪️ Function entry: _node_install_via_binary" >&2

  if [ "$(os__platform)" = "alpine" ]; then
    echo "⛔ method=binary is not supported on Alpine Linux (glibc-only binaries)." >&2
    echo "   Use method=nvm instead — nvm will compile Node.js from source on Alpine." >&2
    return 1
  fi

  # Build platform string
  local _arch_str="$ARCH"
  if [ -z "$_arch_str" ]; then
    _arch_str="$(os__arch)"
  fi
  local _kernel_str
  _kernel_str="$(os__kernel)"
  local _platform
  _platform="$(_node_build_platform_string "$_kernel_str" "$_arch_str")"

  # Resolve install prefix
  local _prefix="$PREFIX"
  if [ "$_prefix" = "auto" ]; then
    _prefix="/usr/local"
  fi

  # Resolve exact version (may already be set from pre-install check step)
  mkdir -p "$INSTALLER_DIR"
  if [ -z "${_NODE_VERSION:-}" ]; then
    echo "ℹ️ Downloading Node.js release index..." >&2
    net__fetch_url_file \
      "https://nodejs.org/dist/index.json" \
      "${INSTALLER_DIR}/index.json"
    _NODE_VERSION="$(_node_resolve_binary_version "$VERSION" "${INSTALLER_DIR}/index.json")"
  fi

  echo "ℹ️ Installing Node.js ${_NODE_VERSION} (${_platform}) to ${_prefix}..." >&2

  local _tarball="node-${_NODE_VERSION}-${_platform}.tar.xz"

  # Download tarball
  net__fetch_url_file \
    "https://nodejs.org/dist/${_NODE_VERSION}/${_tarball}" \
    "${INSTALLER_DIR}/${_tarball}"

  # Download checksums
  net__fetch_url_file \
    "https://nodejs.org/dist/${_NODE_VERSION}/SHASUMS256.txt" \
    "${INSTALLER_DIR}/SHASUMS256.txt"

  # Extract expected hash (two-space separator between hash and filename)
  local _hash
  _hash="$(grep "  ${_tarball}$" "${INSTALLER_DIR}/SHASUMS256.txt" | awk '{print $1}')"
  if [ -z "$_hash" ]; then
    echo "⛔ Could not find checksum for '${_tarball}' in SHASUMS256.txt." >&2
    return 1
  fi

  # Verify checksum
  checksum__verify_sha256 "${INSTALLER_DIR}/${_tarball}" "$_hash"

  # Extract to install prefix
  mkdir -p "$_prefix"
  tar -xJf "${INSTALLER_DIR}/${_tarball}" --strip-components=1 -C "$_prefix"

  # Update PREFIX with resolved value for use by caller
  PREFIX="$_prefix"

  echo "✅ Node.js ${_NODE_VERSION} extracted to ${_prefix}." >&2
  echo "↩️ Function exit: _node_install_via_binary" >&2
  return 0
}

# _node_resolve_nvm_dir
# Resolves NVM_DIR from 'auto' to an identity-appropriate path.
_node_resolve_nvm_dir() {
  echo "↪️ Function entry: _node_resolve_nvm_dir" >&2
  case "${NVM_DIR}" in
    auto)
      if [ "$(id -u)" = "0" ]; then
        NVM_DIR="/usr/local/share/nvm"
      else
        NVM_DIR="${HOME}/.nvm"
      fi
      ;;
    "") NVM_DIR="${HOME}/.nvm" ;;
    *) ;; # explicit value: use as-is
  esac
  echo "ℹ️ Resolved nvm_dir to '${NVM_DIR}'" >&2
  echo "↩️ Function exit: _node_resolve_nvm_dir" >&2
  return 0
}

# _node_create_symlinks
# Creates containerEnv-bridge symlinks and per-binary symlinks.
_node_create_symlinks() {
  echo "↪️ Function entry: _node_create_symlinks" >&2
  if [ "$SYMLINK" != "true" ]; then
    echo "ℹ️ Skipping symlink creation (symlink=false)." >&2
    echo "↩️ Function exit: _node_create_symlinks (skipped)" >&2
    return 0
  fi

  if [ "$(id -u)" = "0" ]; then
    if [ "$METHOD" = "nvm" ]; then
      # Bridge symlink: /usr/local/share/nvm → NVM_DIR (when they differ).
      # The containerEnv.NVM_DIR is always /usr/local/share/nvm; keep it valid
      # for any non-default nvm_dir value (root only — non-root can't write there).
      local _nvm_canonical_root="/usr/local/share/nvm"
      if [ "$NVM_DIR" != "${_nvm_canonical_root}" ]; then
        echo "ℹ️ Creating NVM_DIR bridge symlink: ${_nvm_canonical_root} → ${NVM_DIR}" >&2
        mkdir -p "$(dirname "${_nvm_canonical_root}")"
        ln -sf "$NVM_DIR" "${_nvm_canonical_root}"
      fi
      # Note: the nvm current → version symlink is maintained by nvm itself
      # (NVM_SYMLINK_CURRENT=true). No per-binary symlinks are needed.
    elif [ "$METHOD" = "binary" ]; then
      # Binaries already in /usr/local/bin when prefix is /usr/local
      if [ "$PREFIX" = "/usr/local" ]; then
        echo "ℹ️ prefix=/usr/local — binary symlinks not needed." >&2
      else
        for _bin in node npm npx corepack; do
          local _src="${PREFIX}/bin/${_bin}"
          if [ -f "$_src" ]; then
            echo "ℹ️ Symlinking ${_src} → /usr/local/bin/${_bin}" >&2
            ln -sf "$_src" "/usr/local/bin/${_bin}"
          fi
        done
      fi
    fi
  else
    # Non-root: only method=binary with a non-default prefix.
    if [ "$METHOD" = "binary" ] && [ "$PREFIX" != "${HOME}/.local" ]; then
      mkdir -p "${HOME}/.local/bin"
      for _bin in node npm npx corepack; do
        local _src="${PREFIX}/bin/${_bin}"
        if [ -f "$_src" ]; then
          echo "ℹ️ Symlinking ${_src} → ${HOME}/.local/bin/${_bin}" >&2
          ln -sf "$_src" "${HOME}/.local/bin/${_bin}"
        fi
      done
    else
      echo "ℹ️ Skipping symlink creation (non-root: method=nvm or prefix is ${HOME}/.local)." >&2
    fi
  fi

  echo "↩️ Function exit: _node_create_symlinks" >&2
  return 0
}

# _node_write_nvm_rc
# Writes the nvm shell-initialisation snippet to startup files.
# Arguments: [--home <dir>]  (omit for system-wide write)
_node_write_nvm_rc() {
  echo "↪️ Function entry: _node_write_nvm_rc" >&2
  local _home=""
  while [ "$#" -gt 0 ]; do
    case $1 in
      --home)
        shift
        _home="$1"
        shift
        ;;
      *) shift ;;
    esac
  done

  local _content
  _content="$(
    cat << NVMRC
export NVM_SYMLINK_CURRENT=true
export NVM_DIR="${NVM_DIR}"
# shellcheck disable=SC1090
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && . "\$NVM_DIR/bash_completion"
NVMRC
  )"
  local _marker="nvm init (install-node)"

  if [ -z "$_home" ]; then
    # System-wide
    local _files
    _files="$(shell__system_path_files --profile_d 'nvm_init.sh')"
    shell__sync_block --files "$_files" --marker "$_marker" --content "$_content"
  else
    # Per-user
    local _files
    _files="$(shell__user_init_files --home "$_home")"
    shell__sync_block --files "$_files" --marker "$_marker" --content "$_content"
  fi

  echo "↩️ Function exit: _node_write_nvm_rc" >&2
  return 0
}

# _node_configure_path
# Writes PATH and shell-init exports to startup files.
_node_configure_path() {
  echo "↪️ Function entry: _node_configure_path" >&2
  if [ -z "${EXPORT_PATH}" ] && [ "${EXPORT_PATH+defined}" ]; then
    echo "ℹ️ export_path='' — skipping all PATH writes." >&2
    echo "↩️ Function exit: _node_configure_path (skipped)" >&2
    return 0
  fi

  if [ "$METHOD" = "nvm" ]; then
    # System-wide nvm init snippet
    _node_write_nvm_rc

    # Per-user nvm init snippets
    for _u in "${_RESOLVED_USERS[@]}"; do
      [[ -z "$_u" ]] && continue
      local _home
      _home="$(shell__resolve_home "$_u")"
      [ -z "$_home" ] && continue
      _node_write_nvm_rc --home "$_home"
    done

  elif [ "$METHOD" = "binary" ]; then
    # Binaries already on PATH when prefix is /usr/local
    if [ "$PREFIX" = "/usr/local" ]; then
      echo "ℹ️ prefix=/usr/local — PATH write not needed (already on PATH)." >&2
    else
      local _content="export PATH=\"${PREFIX}/bin:\${PATH}\""
      local _marker="node PATH (install-node)"

      # System-wide
      local _sys_files
      if [ "$EXPORT_PATH" != "auto" ]; then
        _sys_files="$EXPORT_PATH"
      else
        _sys_files="$(shell__system_path_files --profile_d 'node_path.sh')"
      fi
      shell__sync_block --files "$_sys_files" --marker "$_marker" --content "$_content"

      # Per-user
      for _u in "${_RESOLVED_USERS[@]}"; do
        [[ -z "$_u" ]] && continue
        local _home
        _home="$(shell__resolve_home "$_u")"
        [ -z "$_home" ] && continue
        local _user_files
        _user_files="$(shell__user_path_files --home "$_home")"
        shell__sync_block --files "$_user_files" --marker "$_marker" --content "$_content"
      done
    fi
  fi

  echo "↩️ Function exit: _node_configure_path" >&2
  return 0
}

# _node_install_pnpm
# Installs pnpm globally after Node.js is installed.
_node_install_pnpm() {
  echo "↪️ Function entry: _node_install_pnpm" >&2
  if [ "$PNPM_VERSION" = "none" ]; then
    echo "↩️ Function exit: _node_install_pnpm (skipped: pnpm_version=none)" >&2
    return 0
  fi
  if [ "$VERSION" = "none" ]; then
    echo "⚠️ Skipping pnpm install: no Node.js version was installed (version=none)." >&2
    echo "↩️ Function exit: _node_install_pnpm (skipped: version=none)" >&2
    return 0
  fi

  echo "ℹ️ Installing pnpm@${PNPM_VERSION}..." >&2
  if [ "$METHOD" = "nvm" ]; then
    su "$_NVM_USER" -c ". '${NVM_DIR}/nvm.sh' && npm install -g 'pnpm@${PNPM_VERSION}'"
  else
    npm install -g "pnpm@${PNPM_VERSION}"
  fi

  pnpm --version
  echo "✅ pnpm installed." >&2
  echo "↩️ Function exit: _node_install_pnpm" >&2
  return 0
}

# _node_install_yarn
# Installs Yarn globally after Node.js is installed.
_node_install_yarn() {
  echo "↪️ Function entry: _node_install_yarn" >&2
  if [ "$YARN_VERSION" = "none" ]; then
    echo "↩️ Function exit: _node_install_yarn (skipped: yarn_version=none)" >&2
    return 0
  fi
  if [ "$VERSION" = "none" ]; then
    echo "⚠️ Skipping yarn install: no Node.js version was installed (version=none)." >&2
    echo "↩️ Function exit: _node_install_yarn (skipped: version=none)" >&2
    return 0
  fi

  echo "ℹ️ Installing yarn@${YARN_VERSION}..." >&2

  local _install_cmd
  if [ "$YARN_VERSION" = "latest" ]; then
    if command -v corepack > /dev/null 2>&1; then
      _install_cmd="corepack enable"
    else
      _install_cmd="npm install -g yarn"
    fi
  else
    _install_cmd="npm install -g 'yarn@${YARN_VERSION}'"
  fi

  if [ "$METHOD" = "nvm" ]; then
    su "$_NVM_USER" -c ". '${NVM_DIR}/nvm.sh' && ${_install_cmd}"
  else
    eval "$_install_cmd"
  fi

  yarn --version
  echo "✅ yarn installed." >&2
  echo "↩️ Function exit: _node_install_yarn" >&2
  return 0
}

# shellcheck source=lib/github.sh
. "${_SELF_DIR}/_lib/github.sh"
# shellcheck source=lib/checksum.sh
. "${_SELF_DIR}/_lib/checksum.sh"
# shellcheck source=lib/shell.sh
. "${_SELF_DIR}/_lib/shell.sh"
# shellcheck source=lib/users.sh
. "${_SELF_DIR}/_lib/users.sh"

os__require_root

# =============================================================================
# Resolve user list
# =============================================================================

mapfile -t _RESOLVED_USERS < <(users__resolve_list)

# _NVM_USER: the user under whom nvm operations are run.
# When set_permissions=true and running as root, use the first resolved user.
# Otherwise fall back to the current user.
_NVM_USER=""
if [ "$SET_PERMISSIONS" = "true" ] && [ "${#_RESOLVED_USERS[@]}" -gt 0 ] && [ -n "${_RESOLVED_USERS[0]}" ]; then
  _NVM_USER="${_RESOLVED_USERS[0]}"
else
  _NVM_USER="$(id -nu)"
fi

# =============================================================================
# Resolve auto values
# =============================================================================

_node_resolve_nvm_dir

# =============================================================================
# OS base dependencies (always — ensures curl is available for binary method)
# =============================================================================

echo "ℹ️ Installing base OS dependencies..." >&2
ospkg__run --manifest "${_BASE_DIR}/dependencies/base.yaml" --skip_installed

# =============================================================================
# Pre-install check
# =============================================================================

# For binary method: resolve exact version now (before if_exists check)
# so the version comparison can be made.
_NODE_VERSION=""
if [ "$METHOD" = "binary" ] && [ "$VERSION" != "none" ]; then
  echo "ℹ️ Resolving Node.js version for binary install..." >&2
  mkdir -p "$INSTALLER_DIR"
  net__fetch_url_file \
    "https://nodejs.org/dist/index.json" \
    "${INSTALLER_DIR}/index.json"
  _NODE_VERSION="$(_node_resolve_binary_version "$VERSION" "${INSTALLER_DIR}/index.json")"
  echo "ℹ️ Resolved Node.js version: ${_NODE_VERSION}" >&2
fi

_node_check_if_exists

# =============================================================================
# Method-specific OS dependencies
# =============================================================================

if [ "$METHOD" = "nvm" ]; then
  echo "ℹ️ Installing nvm OS dependencies..." >&2
  ospkg__run --manifest "${_BASE_DIR}/dependencies/nvm.yaml" --skip_installed
fi

if [ "$NODE_GYP_DEPS" = "true" ]; then
  # Skip node-gyp deps on Alpine+nvm (already covered by nvm.yaml build toolchain)
  if [ "$METHOD" = "nvm" ] && [ "$(os__platform)" = "alpine" ]; then
    echo "ℹ️ Alpine+nvm detected — node-gyp build tools already provided by nvm.yaml; skipping node-gyp.yaml." >&2
  else
    echo "ℹ️ Installing node-gyp build dependencies..." >&2
    ospkg__run --manifest "${_BASE_DIR}/dependencies/node-gyp.yaml" --skip_installed
    if [ "$(os__platform)" = "macos" ]; then
      echo "ℹ️ node-gyp build dependencies on macOS require Xcode Command Line Tools." >&2
      echo "   Install them with: xcode-select --install" >&2
    fi
  fi
fi

if [ "$METHOD" = "binary" ]; then
  if [ "$(os__platform)" = "alpine" ]; then
    echo "⛔ method=binary is not supported on Alpine Linux (glibc-only binaries)." >&2
    echo "   Use method=nvm instead — nvm will compile Node.js from source on Alpine." >&2
    exit 1
  fi
  echo "ℹ️ Installing binary extraction OS dependencies..." >&2
  ospkg__run --manifest "${_BASE_DIR}/dependencies/binary.yaml" --skip_installed
fi

# =============================================================================
# Main installation logic
# =============================================================================

if [ "$METHOD" = "nvm" ]; then
  _node_install_via_nvm
elif [ "$METHOD" = "binary" ]; then
  _node_install_via_binary
fi

_node_create_symlinks
_node_configure_path

# Additional package managers
if [ "$PNPM_VERSION" != "none" ] && [ "$VERSION" != "none" ]; then
  _node_install_pnpm
fi

if [ "$YARN_VERSION" != "none" ] && [ "$VERSION" != "none" ]; then
  _node_install_yarn
fi

# =============================================================================
# Verification
# =============================================================================

if [ "$VERSION" != "none" ] && [ -n "${_NODE_VERSION:-}" ]; then
  echo "ℹ️ Verifying Node.js installation..." >&2
  if [ "$METHOD" = "nvm" ]; then
    su "$_NVM_USER" -c ". '${NVM_DIR}/nvm.sh' && node --version && npm --version"
  else
    node --version
    npm --version
  fi
  echo "✅ Node.js ${_NODE_VERSION} is ready." >&2
fi
