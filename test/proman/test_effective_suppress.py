"""Tests for effective.py's check-item suppression + the activation-block check.

`_drop_check_items` is the finer-grained escape hatch (below group-level
`suppress.checks`): it removes individual generated check items by title prefix
while keeping the rest of the group — used where one generated assertion is
genuinely inapplicable to a feature (conda's dual bin/condabin entrypoints
defeat the exact on-PATH-resolves check). The activation-block builder asserts
the marker across the union of shell RC + profile.d locations, not just
profile.d (an interactive-only snippet never touches profile.d).
"""

from __future__ import annotations

from proman.test.effective import _drop_check_items
from proman.test.gen import checks_builtin


def _group() -> dict:
    return {
        "description": "g",
        "checks": [
            {"title": "conda binary is at /opt/conda/condabin/conda"},
            {"title": "conda on PATH resolves to /opt/conda/condabin/conda"},
            {"title": "mamba on PATH resolves to /opt/conda/condabin/mamba"},
        ],
    }


def test_drop_check_items_removes_only_prefix_matches() -> None:
    """Only checks whose title starts with a listed prefix are removed."""
    out = _drop_check_items(_group(), ("conda on PATH resolves to",))
    titles = [c["title"] for c in out["checks"]]
    assert "conda on PATH resolves to /opt/conda/condabin/conda" not in titles
    # The binary-at check and the mamba resolve check are kept.
    assert "conda binary is at /opt/conda/condabin/conda" in titles
    assert "mamba on PATH resolves to /opt/conda/condabin/mamba" in titles


def test_drop_check_items_prefix_covers_per_scenario_path() -> None:
    """One prefix entry covers a title whose path differs by scenario."""
    group = {
        "description": "g",
        "checks": [
            {"title": "conda on PATH resolves to /opt/conda-test/condabin/conda"},
        ],
    }
    out = _drop_check_items(group, ("conda on PATH resolves to",))
    assert out["checks"] == []


def test_drop_check_items_noop_when_empty() -> None:
    """No prefixes → the group is returned unchanged (same object)."""
    group = _group()
    assert _drop_check_items(group, ()) is group


def test_activation_block_check_probes_union_not_just_profile_d() -> None:
    """The activation check greps shell RC files, not only /etc/profile.d.

    Regression guard for the class of failure where direnv/fzf/conda write their
    interactive-only activation snippet to /etc/bash.bashrc etc. (never
    profile.d), so a profile.d-only grep always failed.
    """
    item = checks_builtin.activation_block_present_check("install-direnv")
    cmd = item["cmd"]
    assert item["title"] == "shell-activation block written"
    assert "# >>> prefix activation (install-direnv) >>>" in cmd
    # Union of interactive RC + profile.d, not profile.d alone.
    for loc in ("/etc/bash.bashrc", "/etc/zsh", "/etc/fish", "/etc/profile.d"):
        assert loc in cmd
    assert "grep -rqsF" in cmd
