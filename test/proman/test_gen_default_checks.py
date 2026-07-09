"""Tests for the default-check bundle, focused on the off-PATH install shape.

A binary installed to a skip-symlink+skip-export prefix (homebrew, texlive) is
not on the default (non-login) PATH the generated .sh runs in, so its checks
must use the absolute install path plus a `bash -lc` login-shell reachability
probe rather than a bare `command -v`.
"""

from __future__ import annotations

from proman.test.gen import config as gen_config
from proman.test.gen import default_checks
from proman.test.gen import outcome as outcome_mod
from proman.test.gen.facts import FeatureFacts
from proman.test.gen.method_resolver import ResolveContext

UBUNTU = {"os.id": "ubuntu", "plat.pm": "apt", "plat.kernel": "linux"}


def _off_path_facts() -> FeatureFacts:
    """Build a homebrew-like fixture: off-PATH via a discovery snippet.

    Script method, skip-symlink + a discovery snippet (so it is off-PATH /
    login-shell-reachable, not self-managed), plus a functional.
    """
    return FeatureFacts(
        feature_id="install-fixture",
        verify={
            "args": "--version",
            "functional": {"description": "tool runs", "cmd": "{bin} config"},
        },
        methods={"script": {}},
        prefix={
            "root": "/home/linuxbrew/.linuxbrew",
            "bins": ["brew"],
            "symlink": {"skip": True},
            "discovery_snippet": {"bash": 'eval "$(brew shellenv)"'},
        },
    )


def _cmds(items: list) -> list[str]:
    return [i["cmd"] for i in items]


def test_off_path_uses_absolute_paths_not_command_v() -> None:
    """Existence/version/functional are asserted by absolute path, not command -v."""
    facts = _off_path_facts()
    cfg = gen_config.load()
    out = outcome_mod.compute(facts, ResolveContext(attrs=UBUNTU))
    assert out is not None
    assert out.on_path is False
    cmds = _cmds(default_checks.build(facts, cfg, out, method_pinned=True))
    prefix_bin = "/home/linuxbrew/.linuxbrew/bin"
    # Absolute-path existence, not a bare `command -v brew` (which runs in the
    # non-login test shell where brew isn't yet on PATH).
    assert f"test -x {prefix_bin}/brew" in cmds
    assert "command -v brew" not in cmds
    # Version + functional run the absolute binary.
    assert any(f"{prefix_bin}/brew --version" in c for c in cmds)
    assert any(f"{prefix_bin}/brew config" in c for c in cmds)


def test_off_path_adds_login_shell_probe() -> None:
    """A `bash -lc 'command -v ...'` probe asserts login-shell reachability."""
    facts = _off_path_facts()
    cfg = gen_config.load()
    out = outcome_mod.compute(facts, ResolveContext(attrs=UBUNTU))
    cmds = _cmds(default_checks.build(facts, cfg, out, method_pinned=False))
    assert "bash -lc 'command -v brew'" in cmds


def test_on_path_asserts_exact_install_location() -> None:
    """A normal on-PATH install asserts the EXACT install path and PATH resolution.

    The comprehensive bundle no longer settles for a bare `command -v tool`: it
    asserts the binary is at the precise metadata-derived path, is executable,
    and that `command -v` resolves (through any symlink) to exactly that path.
    """
    facts = FeatureFacts(
        feature_id="install-fixture",
        verify={
            "args": "--version",
            "functional": {"description": "tool runs", "cmd": "{bin} check"},
        },
        methods={"binary": {"when": {"plat.machine_release": ["amd64"]}}},
        prefix={"bins": ["tool"]},
    )
    cfg = gen_config.load()
    out = outcome_mod.compute(
        facts, ResolveContext(attrs={**UBUNTU, "plat.machine_release": ["amd64"]})
    )
    cmds = _cmds(default_checks.build(facts, cfg, out, method_pinned=False))
    # Exact location, executable, and PATH-resolves-there — not a bare command -v.
    assert "test -f /usr/local/bin/tool" in cmds
    assert "test -x /usr/local/bin/tool" in cmds
    assert any("command -v tool" in c and "readlink -f" in c for c in cmds)
    # On-PATH install: no login-shell probe.
    assert not any("bash -lc" in c for c in cmds)
