"""Tests for the exact-block-content mirror and the block check builders.

The critical one is `test_generic_prepend_fn_matches_lib_shell`: `blocks.py`
hand-mirrors `lib/shell.bash`'s PATH-prepend function so generated
`block_equals` checks can assert the whole written block byte-for-byte. If the
library helper ever changes and this mirror doesn't, the generated content
checks would assert stale text — this test fails the instant they drift.
"""

from __future__ import annotations

import pathlib
import re

from proman.test.gen import blocks, checks_builtin
from proman.test.gen.facts import FeatureFacts


def test_generic_prepend_fn_matches_lib_shell() -> None:
    """blocks._GENERIC_PREPEND_FN is byte-identical to lib/shell.bash's heredoc."""
    txt = pathlib.Path("lib/shell.bash").read_text(encoding="utf-8")
    match = re.search(r"<< 'EOBLOCK'.*?\n(.*?)\nEOBLOCK", txt, re.DOTALL)
    assert match is not None, "could not find the EOBLOCK heredoc in lib/shell.bash"
    live = match.group(1).splitlines()
    assert live == list(blocks._GENERIC_PREPEND_FN)


def test_export_marker_format() -> None:
    """The marker is `<primary_bin> PATH (<feat_id>)` (install.tmpl.bash:1535)."""
    facts = FeatureFacts(feature_id="install-brew", prefix={"bins": ["brew"]})
    assert blocks.export_marker(facts) == "brew PATH (install-brew)"


def test_export_content_uses_declared_snippet_with_prefix_resolved() -> None:
    """A discovery snippet's `{feat.prefix}` is resolved to the install prefix."""
    facts = FeatureFacts(
        feature_id="install-brew",
        prefix={
            "bins": ["brew"],
            "discovery_snippet": {"bash": 'eval "$({feat.prefix}/bin/brew shellenv)"'},
        },
    )
    prefix = "/home/linuxbrew/.linuxbrew"
    lines = blocks.posix_export_content(facts, "/x/bin", prefix, {})
    assert lines == [f'eval "$({prefix}/bin/brew shellenv)"']


def test_export_content_generic_prepend_when_no_snippet() -> None:
    """Without a snippet, the generic prepend fn called on the bin dir is used."""
    facts = FeatureFacts(feature_id="install-tool", prefix={"bins": ["tool"]})
    lines = blocks.posix_export_content(facts, "/opt/tool/bin", "/opt/tool", {})
    assert lines[0] == "_shell__df_prepend_path() {"
    assert lines[-2] == '_shell__df_prepend_path "/opt/tool/bin"'
    assert lines[-1] == "unset -f _shell__df_prepend_path"


def test_block_equals_check_is_single_line_and_carries_expected() -> None:
    """block_equals emits a single-line cmd embedding the exact @NL@-joined block."""
    item = checks_builtin.block_equals_check(
        "/etc/profile.d/${_FEAT_PROFILE_D_FILE}",
        "brew PATH (install-brew)",
        ['eval "$(/x/bin/brew shellenv)"'],
        title="export block content is exact",
    )
    cmd = item["cmd"]
    assert "\n" not in cmd  # single line — never trips codegen's multi-line branch
    # The double-quoted file path lets the check-script shell expand the env var.
    assert '"/etc/profile.d/${_FEAT_PROFILE_D_FILE}"' in cmd
    # The expected block (markers + content, @NL@-joined) is present.
    assert "# >>> brew PATH (install-brew) >>>@NL@" in cmd
    assert 'eval "$(/x/bin/brew shellenv)"' in cmd


def test_block_absent_check_passes_when_file_missing_or_no_block() -> None:
    """block_absent is satisfied by an absent file or a file lacking the marker."""
    item = checks_builtin.block_absent_check(
        "/etc/profile.d/${_FEAT_PROFILE_D_FILE}",
        "brew PATH (install-brew)",
        title="no PATH export block",
    )
    cmd = item["cmd"]
    assert "! test -e" in cmd
    assert "grep -qF" in cmd


def test_install_location_uses_type_p_not_command_v() -> None:
    """The resolve check uses `type -P` so a shadowing shell function can't fool it."""
    items = checks_builtin.install_location_checks("conda", "/opt/conda/condabin/conda")
    resolve = next(i for i in items if "resolves to" in i["title"])
    assert "type -P conda" in resolve["cmd"]
    assert "command -v" not in resolve["cmd"]
