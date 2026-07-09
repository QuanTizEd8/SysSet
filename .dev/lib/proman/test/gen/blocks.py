"""Exact content of the shell blocks the framework writes.

The byte-for-byte mirror of `lib/shell.bash`'s block composition, so generated
`block_equals` checks can assert the *whole* written block, not just its
existence.

Kept deliberately as the single source of truth for these strings: a drift
between this module and `lib/shell.bash` is exactly the class of bug the
generated content checks exist to catch, and `test/proman/test_gen_blocks.py`
asserts this module still matches the live `lib/shell.bash` text so the mirror
can't silently rot.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from proman.test.gen.facts import FeatureFacts

# The generic PATH-prepend function `shell__prefix_export_path` writes for a
# POSIX shell (bash/zsh, and the system-wide /etc/profile.d drop-in) when the
# feature declares no custom per-shell snippet. Byte-identical to the heredoc +
# two appended lines at lib/shell.bash:1794-1805.
_GENERIC_PREPEND_FN = (
    "_shell__df_prepend_path() {",
    '  local _d="$1" _p="${PATH:-}" _r="" _e',
    '  while [ -n "$_p" ]; do',
    '    _e="${_p%%:*}"; [ "$_p" = "${_p#*:}" ] && _p="" || _p="${_p#*:}"',
    '    [ "$_e" = "$_d" ] || _r="${_r:+${_r}:}${_e}"',
    "  done",
    '  export PATH="${_d}${_r:+:${_r}}"',
    "}",
)

# The /etc/profile.d system drop-in path, keyed off the harness-injected basename
# env var so no project namespace is hardcoded (mirrors path_export_present_check).
PROFILE_D_EXPR = "/etc/profile.d/${_FEAT_PROFILE_D_FILE}"


def export_marker(facts: FeatureFacts) -> str:
    """Return the PATH-export block marker, per install.tmpl.bash:1535.

    `<primary_bin> PATH (<feat_id>)`, or `PATH (<feat_id>)` when the feature has
    no contract primary bin. Uses `prefix.bins[0]` (the framework's
    `_FEAT_CONTRACT_PRIMARY_BIN`), which can differ from `verify.cmd`.
    """
    contract_bin = facts.bins[0] if facts.bins else ""
    prefix = f"{contract_bin} " if contract_bin else ""
    return f"{prefix}PATH ({facts.feature_id})"


def _expand_placeholders(snippet: str, resolved_prefix: str, env_attrs: dict) -> str:
    """Resolve the `{feat.prefix}`/`{plat.*}` placeholders a discovery snippet may use.

    Only `{feat.prefix}` is common; `{plat.kernel}`/`{plat.machine_release}` are
    substituted from the chosen env's attributes when the snippet references
    them (verified against metadata.shared's discovery_snippet doc).
    """
    out = snippet.replace("{feat.prefix}", resolved_prefix)
    kernel = env_attrs.get("plat.kernel")
    if kernel is not None:
        out = out.replace("{plat.kernel}", str(kernel))
    machine = env_attrs.get("plat.machine_release")
    if machine is not None and not isinstance(machine, list):
        out = out.replace("{plat.machine_release}", str(machine))
    return out


def posix_export_content(
    facts: FeatureFacts,
    bin_dir: str,
    resolved_prefix: str,
    env_attrs: dict,
) -> list[str]:
    """Exact lines written inside the PATH-export block of the /etc/profile.d drop-in.

    The system drop-in is POSIX, so it receives the bash content:
    the feature's declared `discovery_snippet.bash` (with placeholders resolved)
    when present, else the generic prepend function called on `bin_dir`.
    """
    snippet = facts.prefix.get("discovery_snippet", {}).get("bash")
    if snippet:
        resolved = _expand_placeholders(snippet, resolved_prefix, env_attrs)
        return resolved.split("\n")
    return [
        *_GENERIC_PREPEND_FN,
        f'_shell__df_prepend_path "{bin_dir}"',
        "unset -f _shell__df_prepend_path",
    ]
