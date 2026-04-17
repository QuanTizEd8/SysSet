#!/bin/sh
# shellcheck disable=SC3043  # 'local' is not POSIX but is supported by all targeted shells (dash, ash, macOS sh)
# POSIX sh compatible — safe to source from sh and bash scripts alike.
# Do not edit _lib/ copies directly — edit lib/ instead.

[ -n "${_FILE__LIB_LOADED-}" ] && return 0
_FILE__LIB_LOADED=1

# @brief file__extract_archive <archive_file> <dest_dir> [<original_name>] — Extract a `.tar.xz`, `.tar.gz`, `.tgz`, or `.zip` archive to `<dest_dir>`. Returns 1 on unrecognized format or missing tool.
#
# <original_name> is used for format detection when <archive_file> is a temp
# path with no meaningful extension (e.g. a mktemp output). When omitted,
# the basename of <archive_file> is used.
#
# Args:
#   <archive_file>   Path to the archive to extract.
#   <dest_dir>       Destination directory (created if absent).
#   <original_name>  Optional filename used for extension-based format detection.
file__extract_archive() {
  local _arc="$1" _dest="$2"
  local _name="${3:-$(basename "$_arc")}"
  mkdir -p "$_dest"
  case "$_name" in
    *.tar.xz) tar -xJf "$_arc" -C "$_dest" ;;
    *.tar.gz | *.tgz) tar -xzf "$_arc" -C "$_dest" ;;
    *.zip)
      if ! command -v unzip > /dev/null 2>&1; then
        echo "⚠️  'unzip' not found — cannot extract '$(basename "$_arc")'. Skipping." >&2
        return 1
      fi
      unzip -q -o "$_arc" -d "$_dest"
      ;;
    *)
      echo "⚠️  Unrecognized archive format: '$(basename "$_name")'. Skipping." >&2
      return 1
      ;;
  esac
  return 0
}
