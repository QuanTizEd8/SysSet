#!/usr/bin/env bash
# This file must be sourced from bash (>=4.0), not sh.
# Do not edit _lib/ copies directly — edit lib/ instead.
#
# Small argv / string helpers. List-style results use one stdout line per item
# (see docs/dev-guide/writing-features.md — Shared library reference).

[[ -n "${_STR__LIB_LOADED-}" ]] && return 0
_STR__LIB_LOADED=1

# @brief str__basename_each [<path-token>...] — For each argument, strip spaces and print basename on its own line.
#
# Intended for path-like tokens (e.g. `owner/repo` slugs). Built-in names
# without `/` still pass through basename (e.g. `git` → `git`).
#
# Args:
#   <path-token>  One token per argument; pass a bash array as `"${arr[@]}"`.
#
# Stdout: one basename per line.
str__basename_each() {
  local _tok
  for _tok in "$@"; do
    _tok="${_tok// /}"
    [ -n "$_tok" ] && basename "$_tok"
  done
  return 0
}
