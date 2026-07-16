# shellcheck shell=bash

__detect_existing_path__() {
  __run_feature_hook__ __detect_existing_path_pre
  declare -g _FEAT_EXISTING_PATH=""
  declare -g _FEAT_EXISTING=false
  # Primary: tlmgr symlink created by instopt_adjustpath (the default)
  _FEAT_EXISTING_PATH="$(command -v tlmgr 2> /dev/null || true)"
  if [[ -n "${_FEAT_EXISTING_PATH}" ]]; then
    logging__detect "Found 'tlmgr' at '${_FEAT_EXISTING_PATH}'."
  fi
  # Fallback: search inside the configured prefix (instopt_adjustpath=false installs)
  if [[ -z "${_FEAT_EXISTING_PATH}" && -n "${_RESOLVED_PREFIX:-}" && -d "${_RESOLVED_PREFIX}" ]]; then
    if bootstrap__find; then
      _FEAT_EXISTING_PATH="$(find "${_RESOLVED_PREFIX}" -maxdepth 5 -name "tlmgr" -type f 2> /dev/null | head -1 || true)"
      if [[ -n "${_FEAT_EXISTING_PATH}" ]]; then
        logging__detect "Found 'tlmgr' inside prefix '${_RESOLVED_PREFIX}' at '${_FEAT_EXISTING_PATH}'."
      fi
    else
      logging__warn "find unavailable; cannot search prefix '${_RESOLVED_PREFIX}' for existing 'tlmgr'."
    fi
  fi
  if [[ -z "${_FEAT_EXISTING_PATH}" ]]; then
    logging__detect "No existing 'tlmgr' found."
  fi
  __run_feature_hook__ __detect_existing_path_post
  if [[ -n "${_FEAT_EXISTING_PATH}" ]]; then _FEAT_EXISTING=true; fi
}

__installed_version() {
  tlmgr --version 2> /dev/null |
    grep -oE 'version [0-9]{4}' | grep -oE '[0-9]{4}' | tail -n1
}

__update_run__() {
  local _installed_year
  _installed_year="$(__installed_version)"
  local _target="${VERSION}"
  if [[ "$_target" == "latest" || "$_target" == "$_installed_year" ]]; then
    logging__update "Updating TeX Live ${_installed_year} packages via tlmgr."
    tlmgr update --self --all
  else
    logging__update "Year change ${_installed_year} → ${_target}: triggering fresh install."
    __reinstall__
  fi
}

__install_register_dummy__() {
  # Skip for package/upstream-package: real PM packages are already installed
  case "${METHOD}" in
    package | upstream-package)
      logging__skip "METHOD='${METHOD}'; skipping dummy registration."
      return 0
      ;;
  esac
  local _year
  _year="$(__installed_version)"
  # Provides list mirrors https://tug.org/texlive/files/debian-equivs-2023-ex.txt
  # so that apt dependencies on any Debian/Ubuntu texlive-* or latex-* package are
  # satisfied without pulling in distro packages.
  ospkg__register_dummy "texlive" "${_year:-9999}" \
    --provides asymptote \
    --provides biblatex \
    --provides biblatex-dw \
    --provides chktex \
    --provides cm-super \
    --provides cm-super-minimal \
    --provides context \
    --provides dvidvi \
    --provides dvipng \
    --provides feynmf \
    --provides fragmaster \
    --provides jadetex \
    --provides lacheck \
    --provides latex-beamer \
    --provides latex-cjk-all \
    --provides latex-cjk-chinese \
    --provides latex-cjk-chinese-arphic-bkai00mp \
    --provides latex-cjk-chinese-arphic-bsmi00lp \
    --provides latex-cjk-chinese-arphic-gbsn00lp \
    --provides latex-cjk-chinese-arphic-gkai00mp \
    --provides latex-cjk-common \
    --provides latex-cjk-japanese \
    --provides latex-cjk-japanese-wadalab \
    --provides latex-cjk-korean \
    --provides latex-cjk-thai \
    --provides latexdiff \
    --provides latexmk \
    --provides latex-sanskrit \
    --provides latex-xcolor \
    --provides lcdf-typetools \
    --provides lmodern \
    --provides luatex \
    --provides musixtex \
    --provides passivetex \
    --provides pgf \
    --provides preview-latex-style \
    --provides prosper \
    --provides ps2eps \
    --provides psutils \
    --provides purifyeps \
    --provides t1utils \
    --provides tex4ht \
    --provides tex4ht-common \
    --provides tex-gyre \
    --provides texinfo \
    --provides texlive \
    --provides texlive-base \
    --provides texlive-bibtex-extra \
    --provides texlive-binaries \
    --provides texlive-common \
    --provides texlive-extra-utils \
    --provides texlive-fonts-extra \
    --provides texlive-fonts-extra-doc \
    --provides texlive-fonts-recommended \
    --provides texlive-fonts-recommended-doc \
    --provides texlive-font-utils \
    --provides texlive-formats-extra \
    --provides texlive-full \
    --provides texlive-games \
    --provides texlive-generic-extra \
    --provides texlive-generic-recommended \
    --provides texlive-humanities \
    --provides texlive-humanities-doc \
    --provides texlive-lang-african \
    --provides texlive-lang-all \
    --provides texlive-lang-arabic \
    --provides texlive-lang-chinese \
    --provides texlive-lang-cjk \
    --provides texlive-lang-cyrillic \
    --provides texlive-lang-czechslovak \
    --provides texlive-lang-english \
    --provides texlive-lang-european \
    --provides texlive-lang-french \
    --provides texlive-lang-german \
    --provides texlive-lang-greek \
    --provides texlive-lang-indic \
    --provides texlive-lang-italian \
    --provides texlive-lang-japanese \
    --provides texlive-lang-korean \
    --provides texlive-lang-other \
    --provides texlive-lang-polish \
    --provides texlive-lang-portuguese \
    --provides texlive-lang-spanish \
    --provides texlive-latex-base \
    --provides texlive-latex-base-doc \
    --provides texlive-latex-extra \
    --provides texlive-latex-extra-doc \
    --provides texlive-latex-recommended \
    --provides texlive-latex-recommended-doc \
    --provides texlive-luatex \
    --provides texlive-math-extra \
    --provides texlive-metapost \
    --provides texlive-metapost-doc \
    --provides texlive-music \
    --provides texlive-omega \
    --provides texlive-pictures \
    --provides texlive-pictures-doc \
    --provides texlive-plain-extra \
    --provides texlive-plain-generic \
    --provides texlive-pstricks \
    --provides texlive-pstricks-doc \
    --provides texlive-publishers \
    --provides texlive-publishers-doc \
    --provides texlive-science \
    --provides texlive-science-doc \
    --provides texlive-xetex \
    --provides thailatex \
    --provides tipa \
    --provides tipa-doc \
    --provides xindy \
    --provides xindy-rules \
    --provides xmltex \
    --description "devfeats: TeX Live ${_year:-latest} (non-PM install)"
}

# ── mirror resolution ─────────────────────────────────────────────────────────

_tl_probe_year_mirror() {
  # Probe the standard historic mirror candidates for TeX Live <year>.
  # Stdout: the first reachable mirror URL. Returns 0 on success, 1 if none reachable.
  local _year="$1"
  local -a _candidates=(
    "https://ftp.math.utah.edu/pub/tex/historic/systems/texlive/${_year}/tlnet-final"
    "https://ftp.tu-chemnitz.de/pub/tug/historic/systems/texlive/${_year}/tlnet-final"
    "https://texlive.info/tlnet-archive/last-of-${_year}/tlnet"
    "https://mirror.ctan.org/systems/texlive/tlnet-archived/${_year}"
  )
  local _url
  for _url in "${_candidates[@]}"; do
    if net__probe_url "${_url}/install-tl-unx.tar.gz" --retries 2 --delay 1 --connect-timeout 10 --max-time 15; then
      printf '%s\n' "${_url}"
      return 0
    elif ! command -v curl > /dev/null 2>&1 && ! command -v wget > /dev/null 2>&1; then
      printf '%s\n' "${_candidates[0]}"
      return 0
    fi
  done
  return 1
}

_tl_resolve_mirror() {
  # Stdout: the TeX Live repository URL to use for installation.
  local _version="${VERSION}"

  # Explicit SCRIPT_ASSET_URI: strip /install-tl-unx.tar.gz suffix to get mirror base
  if [[ -v SCRIPT_ASSET_URI && -n "${SCRIPT_ASSET_URI}" ]]; then
    local _base="${SCRIPT_ASSET_URI%/install-tl-unx.tar.gz}"
    printf '%s\n' "${_base%/}"
    return 0
  fi

  # Explicit repository (not 'ctan'): use verbatim
  if [[ -v REPOSITORY && "${REPOSITORY}" != "ctan" && -n "${REPOSITORY}" ]]; then
    printf '%s\n' "${REPOSITORY%/}"
    return 0
  fi

  # latest → live CTAN mirror pool
  if [[ "${_version}" == "latest" ]]; then
    printf 'https://mirror.ctan.org/systems/texlive/tlnet\n'
    return 0
  fi

  # stable → most recent annual TeX Live release; probe current year, fall back to previous
  if [[ "${_version}" == "stable" ]]; then
    local _year _try_year _mirror
    _year="$(date +%Y)"
    for _try_year in "${_year}" "$((_year - 1))"; do
      _mirror="$(_tl_probe_year_mirror "${_try_year}")" || continue
      logging__info "Resolved 'stable' to TeX Live ${_try_year} (${_mirror})."
      printf '%s\n' "${_mirror}"
      return 0
    done
    logging__error "Could not resolve 'stable': no reachable mirror for TeX Live ${_year} or $((_year - 1))."
    return 1
  fi

  # YYYY-MM-DD → daily snapshot archive
  if [[ "${_version}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    printf 'https://texlive.info/tlnet-archive/%s/tlnet\n' "${_version}"
    return 0
  fi

  # YYYY → historic frozen snapshot; probe mirrors via HEAD request and pick first
  if [[ "${_version}" =~ ^[0-9]{4}$ ]]; then
    local _mirror
    _mirror="$(_tl_probe_year_mirror "${_version}")" || {
      logging__error "No reachable historic mirror found for TeX Live ${_version}."
      return 1
    }
    printf '%s\n' "${_mirror}"
    return 0
  fi

  logging__error "Unsupported version format '${_version}'. Use 'stable', 'latest', a 4-digit year (e.g. '2025'), or a date (e.g. '2025-04-15')."
  return 1
}

# ── download and extract installer tarball ────────────────────────────────────

_tl_download_extract_installer() {
  local _mirror="$1"
  local _installer_url
  if [[ -v SCRIPT_ASSET_URI && -n "${SCRIPT_ASSET_URI}" ]]; then
    _installer_url="${SCRIPT_ASSET_URI}"
  else
    _installer_url="${_mirror%/}/install-tl-unx.tar.gz"
  fi
  local _archive="${INSTALLER_DIR}/install-tl-unx.tar.gz"

  logging__download "Downloading TeX Live installer from '${_installer_url}'."
  # Bound per-attempt time: the 'latest'/'stable' mirror is a redirect pool
  # (mirror.ctan.org) that resolves each request to a different backend, some of
  # which stall or present untrusted certs. --connect-timeout drops unreachable
  # mirrors quickly and --max-time caps a stalled transfer of the small (~5 MB)
  # installer, so the shared retry loop can cycle to a healthy mirror instead of
  # hanging for minutes per attempt.
  net__fetch_url_file "${_installer_url}" "${_archive}" --connect-timeout 15 --max-time 180

  if [[ "${VERIFY_DOWNLOADS}" == "true" ]]; then
    local _checksum_file="${_archive}.sha512"
    logging__download "Downloading SHA512 checksum."
    if net__fetch_url_file "${_installer_url}.sha512" "${_checksum_file}" 2> /dev/null; then
      logging__install "Verifying installer archive integrity."
      local -a _sha512_cmd=()
      if command -v sha512sum > /dev/null 2>&1; then
        _sha512_cmd=(sha512sum)
      elif command -v shasum > /dev/null 2>&1; then
        _sha512_cmd=(shasum -a 512)
      fi
      if [[ "${#_sha512_cmd[@]}" -gt 0 ]]; then
        (cd "${INSTALLER_DIR}" && "${_sha512_cmd[@]}" -c "${_checksum_file}") || {
          logging__error "SHA512 verification failed for installer archive."
          return 1
        }
      else
        logging__warn "No sha512 tool found; skipping integrity check."
      fi
      file__rm -f "${_checksum_file}"
    else
      logging__warn "SHA512 checksum unavailable at '${_installer_url}.sha512'; skipping integrity check."
    fi
  fi

  logging__install "Extracting TeX Live installer archive."
  file__extract_archive "${_archive}" "${INSTALLER_DIR}" --strip 1
  file__rm -f "${_archive}"
}

# ── profile generation ────────────────────────────────────────────────────────

_tl_write_profile() {
  local _profile_dest="${INSTALLER_DIR}/texlive.profile"

  if [[ -n "${PROFILE:-}" ]]; then
    if [[ "${PROFILE}" == *$'\n'* ]]; then
      # Inline content
      printf '%s' "${PROFILE}" > "${_profile_dest}"
    else
      # Path or URI: resolve to local file, passing shared fetch credentials
      local -a _resolve_args=()
      if [[ "${#FETCH_HEADERS[@]}" -gt 0 ]]; then
        local _h
        for _h in "${FETCH_HEADERS[@]}"; do
          [[ -n "${_h}" ]] && _resolve_args+=(--header "${_h}")
        done
      fi
      [[ -n "${FETCH_NETRC:-}" ]] && _resolve_args+=(--netrc-file "${FETCH_NETRC}")
      local _resolved
      _resolved="$(uri__resolve_line "${PROFILE}" "${INSTALLER_DIR}" "${_resolve_args[@]}")"
      if [[ "${_resolved}" != "${_profile_dest}" ]]; then
        cp "${_resolved}" "${_profile_dest}"
      fi
    fi
    logging__install "Using provided profile '${_profile_dest}'."
    return 0
  fi

  logging__install "Generating texlive.profile."

  # Resolve collections outside the brace group (local declarations inside { } > file
  # blocks affect the same scope but hurt readability and can interact with set -e).
  local -a _cols=("${COLLECTIONS[@]}")
  local -a _nonempty_cols=()
  local _c
  for _c in "${_cols[@]}"; do
    [[ -n "${_c}" ]] && _nonempty_cols+=("${_c}")
  done

  {
    # Installation root (TEXDIR)
    printf 'TEXDIR %s\n' "${_RESOLVED_PREFIX}"

    # TEXMFLOCAL, TEXMFSYSVAR, TEXMFSYSCONFIG: always set explicitly to keep them
    # within the prefix tree. When TEXDIR does not end in a year component, the
    # installer computes these defaults relative to $tex_prefix/$year (the year-
    # stamped path), not relative to the profile-provided TEXDIR. Pinning them
    # here ensures the entire installation is self-contained under the prefix.
    printf 'TEXMFLOCAL %s\n' "${TEXMFLOCAL:-${_RESOLVED_PREFIX}/texmf-local}"
    printf 'TEXMFSYSCONFIG %s\n' "${TEXMFSYSCONFIG:-${_RESOLVED_PREFIX}/texmf-config}"
    printf 'TEXMFSYSVAR %s\n' "${TEXMFSYSVAR:-${_RESOLVED_PREFIX}/texmf-var}"
    [[ -n "${TEXMFHOME:-}" ]] && printf 'TEXMFHOME %s\n' "${TEXMFHOME}"
    [[ -n "${TEXMFCONFIG:-}" ]] && printf 'TEXMFCONFIG %s\n' "${TEXMFCONFIG}"
    [[ -n "${TEXMFVAR:-}" ]] && printf 'TEXMFVAR %s\n' "${TEXMFVAR}"

    # Scheme: infraonly + explicit collections, or named scheme
    if [[ "${#_nonempty_cols[@]}" -gt 0 ]]; then
      printf 'selected_scheme scheme-infraonly\n'
      for _c in "${_nonempty_cols[@]}"; do
        printf 'collection-%s 1\n' "${_c}"
      done
    else
      printf 'selected_scheme scheme-%s\n' "${SCHEME}"
    fi

    # instopt_* keys
    printf 'instopt_adjustpath %s\n' "$([[ "${INSTOPT_ADJUSTPATH}" == "true" ]] && printf '1' || printf '0')"
    printf 'instopt_adjustrepo %s\n' "$([[ "${INSTOPT_ADJUSTREPO}" == "true" ]] && printf '1' || printf '0')"
    printf 'instopt_letter %s\n' "$([[ "${INSTOPT_LETTER}" == "letter" ]] && printf '1' || printf '0')"
    printf 'instopt_portable %s\n' "$([[ "${INSTOPT_PORTABLE}" == "true" ]] && printf '1' || printf '0')"
    printf 'instopt_write18_restricted %s\n' "$([[ "${INSTOPT_WRITE18_RESTRICTED}" == "true" ]] && printf '1' || printf '0')"

    # tlpdbopt_* keys
    printf 'tlpdbopt_install_docfiles %s\n' "$([[ "${TLPDBOPT_INSTALL_DOCFILES}" == "true" ]] && printf '1' || printf '0')"
    printf 'tlpdbopt_install_srcfiles %s\n' "$([[ "${TLPDBOPT_INSTALL_SRCFILES}" == "true" ]] && printf '1' || printf '0')"
    [[ "${TLPDBOPT_SYS_BIN:-auto}" != "auto" ]] && printf 'tlpdbopt_sys_bin %s\n' "${TLPDBOPT_SYS_BIN}"
    [[ -n "${TLPDBOPT_SYS_MAN:-}" ]] && printf 'tlpdbopt_sys_man %s\n' "${TLPDBOPT_SYS_MAN}"
    [[ -n "${TLPDBOPT_SYS_INFO:-}" ]] && printf 'tlpdbopt_sys_info %s\n' "${TLPDBOPT_SYS_INFO}"
    printf 'tlpdbopt_create_formats %s\n' "$([[ "${TLPDBOPT_CREATE_FORMATS}" == "true" ]] && printf '1' || printf '0')"
    printf 'tlpdbopt_post_code %s\n' "$([[ "${TLPDBOPT_POST_CODE}" == "true" ]] && printf '1' || printf '0')"
    printf 'tlpdbopt_generate_updmap %s\n' "$([[ "${TLPDBOPT_GENERATE_UPDMAP}" == "true" ]] && printf '1' || printf '0')"
    printf 'tlpdbopt_autobackup %s\n' "${TLPDBOPT_AUTOBACKUP}"
    if [[ -n "${TLPDBOPT_BACKUPDIR:-}" ]]; then printf 'tlpdbopt_backupdir %s\n' "${TLPDBOPT_BACKUPDIR}"; fi
  } > "${_profile_dest}"
}

# ── post-install detection ────────────────────────────────────────────────────

_tl_detect_texdir_sysbin() {
  # Sets globals _TL_TEXDIR and _TL_SYSBIN by parsing the written profile,
  # then falling back to kpsewhich.
  declare -g _TL_TEXDIR="" _TL_SYSBIN=""
  local _profile="${INSTALLER_DIR}/texlive.profile"

  if [[ -f "${_profile}" ]]; then
    _TL_TEXDIR="$(awk '/^TEXDIR /{print $2; exit}' "${_profile}")"
    local _sysbin_raw
    _sysbin_raw="$(awk '/^tlpdbopt_sys_bin /{print $2; exit}' "${_profile}")"
    [[ "${_sysbin_raw:-auto}" != "auto" && -n "${_sysbin_raw}" ]] && _TL_SYSBIN="${_sysbin_raw}"
  fi

  if [[ -z "${_TL_TEXDIR}" ]]; then
    _TL_TEXDIR="$(kpsewhich -var-value=TEXMFROOT 2> /dev/null || true)"
  fi
  if [[ -z "${_TL_TEXDIR}" ]]; then
    _TL_TEXDIR="${_RESOLVED_PREFIX}"
  fi

  if [[ -z "${_TL_SYSBIN}" && "${TLPDBOPT_SYS_BIN:-auto}" != "auto" ]]; then
    _TL_SYSBIN="${TLPDBOPT_SYS_BIN}"
  fi
  if [[ -z "${_TL_SYSBIN}" ]]; then
    _TL_SYSBIN="$([[ "$(id -u)" == "0" ]] && printf '/usr/local/bin' || printf '%s/.local/bin' "${HOME}")"
  fi

  if [[ -z "${_TL_TEXDIR}" ]]; then
    logging__error "Could not determine TeX Live installation directory."
    return 1
  fi
  logging__info "Detected TEXDIR='${_TL_TEXDIR}', SYS_BIN='${_TL_SYSBIN}'."
}

# ── ensure tlmgr is in PATH after a no-adjustpath install ─────────────────────

_tl_ensure_path() {
  # When instopt_adjustpath=false, tlmgr and other TeX Live binaries are NOT
  # symlinked to SYS_BIN.  Temporarily add the arch-specific bin dir to PATH so
  # post-install calls (tlmgr install, tlmgr option, command -v context, …) work.
  [[ "${INSTOPT_ADJUSTPATH}" == "true" ]] && return 0
  local _tl_arch_bin
  _tl_arch_bin="$(file__first_child_dir "${_TL_TEXDIR}/bin")"
  if [[ -n "${_tl_arch_bin}" ]]; then
    export PATH="${_tl_arch_bin}:${PATH}"
    logging__info "Added '${_tl_arch_bin}' to PATH for post-install steps."
  fi
}

# ── patches ───────────────────────────────────────────────────────────────────

_tl_apply_patches() {
  command -v context > /dev/null 2>&1 || return 0
  local _mtxrun="${_TL_TEXDIR}/texmf-dist/scripts/context/lua/mtxrun.lua"
  [[ -f "${_mtxrun}" ]] || return 0
  logging__install "Applying ConTeXt mtxrun.lua symlink-path patch."
  # luametatex (used by ConTeXt in TL 2022+) resolves the binary path from argv[0]
  # without following symlinks. When instopt_adjustpath creates PATH symlinks, running
  # ConTeXt through those symlinks sets SELFAUTOPARENT to the symlink dir rather than
  # the TL bin dir, causing ConTeXt to fail to find texmfcnf.lua. This one-liner inserts
  # lfs.symlinktarget resolution before kpse is blocked. Needed for TL 2022 through at
  # least TL 2026; upstream luametatex has no fix as of April 2026.
  sed -i \
    '/package.loaded\["data-ini"\]/a if os.selfpath then environment.ownbin=lfs.symlinktarget(os.selfpath..io.fileseparator..os.selfname);environment.ownpath=environment.ownbin:match("^.*"..io.fileseparator) else environment.ownpath=kpse.new("luatex"):var_value("SELFAUTOLOC");environment.ownbin=environment.ownpath..io.fileseparator..(arg[-2] or arg[-1] or arg[0] or "luatex"):match("[^"..io.fileseparator.."]*$") end' \
    "${_mtxrun}" || true
}

# ── post-install steps ────────────────────────────────────────────────────────

_tl_has_packages() {
  # Returns 0 when the installation includes TeX packages beyond bare infraonly
  # infrastructure. Used to guard tlmgr options that require the tlpdb to have
  # package-level options registered (paper size, verify-repo).
  [[ "${SCHEME}" != "infraonly" ]] && return 0
  if [[ -v COLLECTIONS ]]; then
    local _c
    for _c in "${COLLECTIONS[@]}"; do [[ -n "${_c}" ]] && return 0; done
  fi
  if [[ -v PACKAGES ]]; then
    local _p
    for _p in "${PACKAGES[@]}"; do [[ -n "${_p}" ]] && return 0; done
  fi
  return 1
}

_tl_maybe_install_jre() {
  command -v java > /dev/null 2>&1 && return 0
  local _texmf_dist=""
  if [[ -n "${_TL_TEXDIR:-}" ]]; then
    _texmf_dist="${_TL_TEXDIR}/texmf-dist"
  else
    _texmf_dist="$(kpsewhich -var-value=TEXMFDIST 2> /dev/null || true)"
  fi
  [[ -n "${_texmf_dist}" && -d "${_texmf_dist}" ]] || return 0
  if ! bootstrap__find; then
    logging__warn "find unavailable; skipping Java-tools detection in TeX Live tree."
    return 0
  fi
  find "${_texmf_dist}/scripts" -name "*.jar" 2> /dev/null | grep -q . || return 0
  logging__install "Java tools detected in TeX Live tree; installing JRE."
  __dep_install_from_env__ OSPKG_MANIFEST_OPTION_JRE run option-jre
}

_tl_setup_fontconfig() {
  logging__install "Configuring system font paths for TL-shipped fonts."
  if command -v luaotfload-tool > /dev/null 2>&1; then
    luaotfload-tool -u || true
  fi
  local _fontconf=""
  if [[ -n "${_TL_TEXDIR:-}" ]]; then
    if bootstrap__find; then
      _fontconf="$(find "${_TL_TEXDIR}" -name texlive-fontconfig.conf 2> /dev/null | head -n1 || true)"
    else
      logging__warn "find unavailable; skipping TeX Live fontconfig snippet lookup."
    fi
  fi
  if [[ -n "${_fontconf}" ]]; then
    mkdir -p /etc/fonts/conf.d
    cp "${_fontconf}" /etc/fonts/conf.d/09-texlive-fonts.conf || true
  fi
  fc-cache -fsv || true
}

_tl_generate_caches() {
  logging__install "Generating ConTeXt file-database and format caches."
  if command -v context > /dev/null 2>&1; then
    # Generate file database for LuaMetaTeX (LMTX/MKXL, the default ConTeXt engine).
    mtxrun --generate || true
    # Generate file database for the classic LuaTeX engine (used by 'context --luatex').
    # Use the full path via _TL_SYSBIN rather than PATH, which may not be set yet when
    # instopt_adjustpath=false.
    if [[ -f "${_TL_SYSBIN}/mtxrun.lua" ]]; then
      "${_TL_SYSBIN}/texlua" "${_TL_SYSBIN}/mtxrun.lua" --luatex --generate || true
    fi
    context --make || true
    context --luatex --make || true
  fi
}

_tl_post_install() {
  # Pass "true" as $1 when TeX packages are guaranteed (e.g. from package method);
  # otherwise _tl_has_packages inspects SCHEME/COLLECTIONS/PACKAGES.
  local _guaranteed_packages="${1:-false}"

  # Additional packages via tlmgr
  if [[ -v PACKAGES && "${#PACKAGES[@]}" -gt 0 ]]; then
    local _pkg
    for _pkg in "${PACKAGES[@]}"; do
      [[ -z "${_pkg}" ]] && continue
      tlmgr install "${_pkg}" ||
        logging__warn "tlmgr install '${_pkg}' failed; continuing."
    done
  fi

  # Paper size and verify-repo require package-level options registered in the tlpdb.
  # A bare infraonly install (no packages, no collections) does not register them;
  # tlmgr would report "Option not supported". Only apply when packages are present.
  if [[ "${_guaranteed_packages}" == "true" ]] || _tl_has_packages; then
    local _paper
    _paper="$([[ "${INSTOPT_LETTER}" == "letter" ]] && printf 'letter' || printf 'a4')"
    tlmgr option paper "${_paper}" || true

    if [[ -n "${TLMGR_VERIFY_REPO:-}" ]]; then
      tlmgr option verify-repo "${TLMGR_VERIFY_REPO}" || true
    fi

    _tl_setup_fontconfig
    _tl_maybe_install_jre
  fi

  # Post-install update
  if [[ "${TLMGR_UPDATE}" == "true" ]]; then
    logging__update "Running tlmgr update --self --all."
    tlmgr update --self --all --reinstall-forcibly-removed
  fi

  # ConTeXt cache generation (guarded by option; only meaningful when ConTeXt is installed)
  if [[ "${GENERATE_CACHES}" == "true" ]]; then
    _tl_generate_caches
  fi
}

_tl_alpine_linuxmusl_workaround() {
  # On Alpine (musl libc), install-tl places binaries in bin/<arch>-linuxmusl/ but the
  # installer's instopt_adjustpath path-setup mechanism looks for bin/<arch>-linux/.
  # Pre-create the symlink so the installer finds the correct arch dir and tlmgr path add
  # works correctly during installation.
  # Ref: https://github.com/reitzig/texlive-docker (Alpine Dockerfile workaround)
  local _pm
  _pm="$(ospkg__pm 2> /dev/null || true)"
  [[ "${_pm}" != "apk" ]] && return 0
  local _arch
  _arch="$(uname -m)"
  local _tl_bin="${_RESOLVED_PREFIX}/bin"
  mkdir -p "${_tl_bin}"
  if [[ ! -e "${_tl_bin}/${_arch}-linux" ]]; then
    logging__install "Alpine musl: pre-creating ${_arch}-linux → ${_arch}-linuxmusl symlink."
    ln -s "${_arch}-linuxmusl" "${_tl_bin}/${_arch}-linux"
  fi
}

# ── script install override ───────────────────────────────────────────────────

__install_run_script__() {
  __run_feature_hook__ __install_run_script_pre

  local _mirror
  _mirror="$(_tl_resolve_mirror)"

  _tl_download_extract_installer "${_mirror}"
  _tl_write_profile
  _tl_alpine_linuxmusl_workaround

  local -a _install_args=(
    -no-interaction
    -repository "${_mirror}"
    -profile "${INSTALLER_DIR}/texlive.profile"
  )
  [[ "${VERIFY_DOWNLOADS}" != "true" ]] && _install_args+=(--no-verify-downloads)

  logging__install "Running TeX Live installer."
  net__fetch_with_retry --retries 5 --delay 30 -- \
    env TEXLIVE_INSTALL_NO_CONTEXT_CACHE=1 TEXLIVE_INSTALL_NO_DISKCHECK=1 \
    TEXLIVE_INSTALL_ENV_NOCHECK=1 TEXLIVE_INSTALL_NO_WELCOME=1 NOPERLDOC=1 \
    perl "${INSTALLER_DIR}/install-tl" "${_install_args[@]}"

  _tl_detect_texdir_sysbin
  _tl_ensure_path
  _tl_apply_patches
  _tl_post_install

  __run_feature_hook__ __install_run_script_post
}

# ── package install override ──────────────────────────────────────────────────

__install_run_package__() {
  __run_feature_hook__ __install_run_package_pre

  local _scheme="${SCHEME}"
  local _pm
  _pm="$(ospkg__pm)"
  local -a _pkgs=()

  case "${_pm}" in
    apt-get)
      case "${_scheme}" in
        full) _pkgs=(texlive-full) ;;
        medium) _pkgs=(texlive texlive-latex-extra texlive-fonts-extra texlive-science) ;;
        small) _pkgs=(texlive texlive-latex-extra) ;;
        basic) _pkgs=(texlive-latex-base texlive-latex-recommended) ;;
        minimal | infraonly) _pkgs=(texlive-latex-base) ;;
        *) _pkgs=(texlive) ;;
      esac
      ;;
    apk)
      case "${_scheme}" in
        full) _pkgs=(texlive-full) ;;
        *) _pkgs=(texlive) ;;
      esac
      ;;
    dnf | microdnf | yum)
      _pkgs=("texlive-scheme-${_scheme}")
      ;;
    brew)
      _pkgs=(texlive)
      ;;
    *)
      _pkgs=(texlive)
      ;;
  esac

  ospkg__install "${_pkgs[@]}"
  # Package method always installs real TeX content; no infraonly check needed.
  if command -v tlmgr > /dev/null 2>&1; then
    _tl_post_install true
  fi

  # On Alpine, tlmgr is not shipped with the texlive apk package (apk manages
  # TeX packages directly). Override the verify cmd so the lifecycle hook checks
  # latex instead of tlmgr.
  if [[ "${_pm}" == "apk" ]]; then
    __install_finish_pre() {
      _FEAT_VERIFY_CMD="latex"
      INSTALL_VERIFICATION_ARGS="--version"
    }
  fi

  __run_feature_hook__ __install_run_package_post
}

# ── uninstall overrides ───────────────────────────────────────────────────────

_tl_uninstall_script() {
  local _texdir
  _texdir="$(kpsewhich -var-value=TEXMFROOT 2> /dev/null || true)"
  local _texmfvar
  _texmfvar="$(kpsewhich -var-value=TEXMFVAR 2> /dev/null || true)"

  if [[ -n "${_texdir}" && -d "${_texdir}" ]]; then
    logging__remove "Removing TeX Live tree '${_texdir}'."
    file__rm -rf "${_texdir}"
  elif [[ -n "${_RESOLVED_PREFIX:-}" && -d "${_RESOLVED_PREFIX}" ]]; then
    logging__remove "Removing TeX Live prefix '${_RESOLVED_PREFIX}'."
    file__rm -rf "${_RESOLVED_PREFIX}"
  else
    logging__warn "Could not locate TeX Live installation directory; skipping tree removal."
  fi

  [[ -n "${_texmfvar}" && -d "${_texmfvar}" ]] && file__rm -rf "${_texmfvar}" || true
  ospkg__unregister_dummy "texlive" 2> /dev/null || true
}

__uninstall_run_package__() {
  __run_feature_hook__ __uninstall_run_package_pre
  logging__remove "Uninstalling TeX Live (package method)."
  local _pm
  _pm="$(ospkg__pm)"
  local -a _pkgs=()
  case "${_pm}" in
    apt-get) _pkgs=(texlive-full texlive texlive-latex-extra texlive-latex-base
      texlive-fonts-extra texlive-science texlive-latex-recommended) ;;
    apk) _pkgs=(texlive-full texlive) ;;
    dnf | microdnf | yum)
      _pkgs=("texlive-scheme-full" "texlive-scheme-medium" "texlive-scheme-small"
        "texlive-scheme-basic" "texlive-scheme-minimal" "texlive-scheme-infraonly")
      ;;
    *) logging__warn "No package uninstall mapping for PM '${_pm}'; skipping." ;;
  esac
  if [[ "${#_pkgs[@]}" -gt 0 ]]; then
    ospkg__remove_user "${_pkgs[@]}" || true
  fi
  __run_feature_hook__ __uninstall_run_package_post
}

__uninstall_run__() {
  __run_feature_hook__ __uninstall_run_pre

  logging__remove "Uninstalling via method='${_FEAT_EXISTING_METHOD:-unknown}' from '${_FEAT_EXISTING_PATH}'."

  case "${_FEAT_EXISTING_METHOD:-}" in
    package)
      __uninstall_run_package__
      ;;
    *)
      _tl_uninstall_script
      ;;
  esac

  logging__info "Uninstall run finished."

  __run_feature_hook__ __uninstall_run_post
}
