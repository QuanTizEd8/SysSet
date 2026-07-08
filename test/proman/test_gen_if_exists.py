"""Tests for the if_exists rule's fake-stub seeding.

Guards the multi-word version-flag case: a feature whose verify.args is more
than one token (e.g. pixi's "info --extended") must still produce a stub that
reports the fake version, so if_exists detection and the version-unchanged/
mutated rechecks work. The stub matches "$*" (all args, space-joined), not
"$1" — a "$1" test would see only the first token and never match.
"""

from __future__ import annotations

from proman.test.gen import config as gen_config
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


def _git_clone_facts() -> FeatureFacts:
    """Build a git-clone-only feature: no bins, a git-clone method, a prefix root."""
    return FeatureFacts(
        feature_id="install-fixture",
        methods={"git-clone": {"uri": "https://example.com/repo"}},
        version={"resolution": "git_ref", "default": "master"},
        prefix={"root": "/usr/local/share/repo", "nonroot": "${HOME}/.repo"},
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


def _off_path_facts() -> FeatureFacts:
    """homebrew-like: script method installing to a skip-symlink off-PATH prefix."""
    return FeatureFacts(
        feature_id="install-fixture",
        verify={
            "args": "--version",
            "functional": {"description": "runs", "cmd": "{bin} --prefix"},
        },
        methods={"script": {}},
        prefix={
            "root": "/home/linuxbrew/.linuxbrew",
            "bins": ["brew"],
            "symlink": {"skip": True},
            "exports": {"skip": True},
        },
    )


def test_off_path_if_exists_uses_absolute_path() -> None:
    """Off-PATH skip/fail existence checks probe the absolute stub path.

    A bare `command -v` would fail for a binary the feature deliberately keeps
    off the default PATH (reachable only via a login-shell discovery snippet).
    """
    cfg = gen_config.load()
    rule = IfExistsRule()
    facts = _off_path_facts()
    skip = rule._skip(facts, cfg, off_path=True)
    cmds = [c["cmd"] for c in skip.checks["if_exists_skip"]["checks"]]
    assert "test -x /home/linuxbrew/.linuxbrew/bin/brew" in cmds
    assert "command -v brew" not in cmds
    # On-PATH features keep the bare command -v probe (no regression).
    on = rule._skip(_facts("--version"), cfg, off_path=False)
    on_cmds = [c["cmd"] for c in on.checks["if_exists_skip"]["checks"]]
    assert "command -v tool" in on_cmds


def test_git_clone_generates_only_skip_and_fail() -> None:
    """A git-clone-only feature gets skip+fail, never reinstall/update.

    reinstall/update re-clone / `git pull`, which a seeded bare `.git` cannot
    stand in for, so they are deliberately excluded for git-clone-only features.
    """
    cfg = gen_config.load()
    scenarios = IfExistsRule().generate(_git_clone_facts(), cfg, envs={})
    names = [s.name for s in scenarios]
    assert names == ["if_exists_skip", "if_exists_fail"]


def test_git_clone_seeds_dotgit_and_sentinel() -> None:
    """Seed `{prefix}/.git` plus a survivable sentinel for skip/fail.

    `{prefix}/.git` is how the framework detects an existing git-clone install;
    the sentinel lets skip/fail assert the existing clone was left untouched.
    """
    cfg = gen_config.load()
    by_name = {s.name: s for s in IfExistsRule().generate(_git_clone_facts(), cfg, {})}

    skip = by_name["if_exists_skip"]
    assert "mkdir -p /usr/local/share/repo/.git" in skip.scenario["setup"]
    assert IfExistsRule._GIT_CLONE_SENTINEL in skip.scenario["setup"]
    # No fake-stub binary machinery leaks in (a git-clone feature has no bin).
    assert "chmod +x" not in skip.scenario["setup"]
    skip_cmds = [c["cmd"] for c in skip.checks["if_exists_skip"]["checks"]]
    assert "test -d /usr/local/share/repo/.git" in skip_cmds
    assert any(IfExistsRule._GIT_CLONE_SENTINEL in c for c in skip_cmds)

    fail = by_name["if_exists_fail"]
    assert fail.scenario["expect_install_failure"] is True
    fail_checks = fail.checks["if_exists_fail"]["checks"]
    assert any(c.get("kind") == "install_failure" for c in fail_checks)
