"""Tests for the if_exists rule's fake-stub seeding.

Guards the multi-word version-flag case: a feature whose verify.args is more
than one token (e.g. pixi's "info --extended") must still produce a stub that
reports the fake version, so if_exists detection and the version-unchanged/
mutated rechecks work. The stub matches "$*" (all args, space-joined), not
"$1" — a "$1" test would see only the first token and never match.
"""

from __future__ import annotations

from proman.test.gen.facts import FeatureFacts
from proman.test.gen.rules.if_exists import IfExistsRule


def _facts(verify_args: str) -> FeatureFacts:
    return FeatureFacts(
        feature_id="install-fixture",
        verify={"args": verify_args},
        methods={"binary": {}},
        version={"test_pins": {"pinned": ["1.2.3"]}},
        prefix={"bins": ["tool"]},
    )


def test_stub_matches_multi_word_flag() -> None:
    """A multi-word verify.args stub matches the full arg list via "$*"."""
    setup = IfExistsRule()._setup(_facts("info --extended"))
    # The stub compares the joined args, so the whole "info --extended" string
    # is present as the test operand — and it is "$*", never "$1"/"${1-}".
    assert '"$*" = "info --extended"' in setup
    assert "${1-}" not in setup
    assert '"$1"' not in setup


def test_stub_matches_single_word_flag() -> None:
    """The common single-word "--version" case still matches (no regression)."""
    setup = IfExistsRule()._setup(_facts("--version"))
    assert '"$*" = "--version"' in setup
