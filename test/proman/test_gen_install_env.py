"""Tests for the _options.verify.install_env override.

A feature whose primary binary is pre-installed on the standard pool distros
(e.g. bash, Essential everywhere) names a clean env for install-expecting
scenarios; the generator must route default / method-matrix / version-pinning /
prefix-symlink / log_file / if_exists-reinstall onto it (and its non-root
counterpart for the non-root prefix scenario), while features without the
override are untouched.
"""

from __future__ import annotations

from proman.test.gen.config import GenerationConfig
from proman.test.gen.facts import FeatureFacts
from proman.test.gen.rules.existence_default import ExistenceDefaultRule
from proman.test.gen.rules.method_matrix import MethodMatrixRule
from proman.test.gen.rules.prefix_symlink import PrefixSymlinkRule
from proman.test.gen.rules.version_pinning import VersionPinningRule

_CLEAN = "alpine-clean"
_CLEAN_NONROOT = "alpine-clean+vscode"

_ENVS = {
    "ubuntu-stable": {"attributes": {"os.id": "ubuntu", "plat.pm": "apt"}},
    "ubuntu-stable+vscode": {"attributes": {"os.id": "ubuntu", "plat.pm": "apt"}},
    _CLEAN: {"attributes": {"os.id": "alpine", "plat.pm": "apk"}},
    _CLEAN_NONROOT: {"attributes": {"os.id": "alpine", "plat.pm": "apk"}},
}

_CFG = GenerationConfig(
    enabled=True,
    rollout_mode="all",
    allowlist=frozenset(),
    denylist=frozenset(),
    primary_env="ubuntu-stable",
    nonroot_env="ubuntu-stable+vscode",
    env_pool=("ubuntu-stable",),
)


def _facts(*, install_env: str | None) -> FeatureFacts:
    verify: dict = {
        "args": "--version",
        "functional": {"cmd": "{bin} --version", "description": "runs"},
    }
    if install_env is not None:
        verify["install_env"] = install_env
        verify["install_env_nonroot"] = _CLEAN_NONROOT
    return FeatureFacts(
        feature_id="install-fixture",
        verify=verify,
        methods={"source": {}},
        version={"test_pins": {"pinned": ["1.2.3"]}},
        prefix={"bins": ["tool"]},
    )


def _envs_of(scenarios) -> dict[str, list]:  # noqa: ANN001
    return {s.name: s.scenario["envs"] for s in scenarios}


def test_install_env_routes_install_scenarios_to_clean_env() -> None:
    """Default / source / version_pinned / custom-prefix run on install_env."""
    facts = _facts(install_env=_CLEAN)
    default = _envs_of(ExistenceDefaultRule().generate(facts, _CFG, _ENVS))
    assert default["default"] == [_CLEAN]

    method = _envs_of(MethodMatrixRule().generate(facts, _CFG, _ENVS))
    assert method["source_default"] == [_CLEAN]

    pins = _envs_of(VersionPinningRule().generate(facts, _CFG, _ENVS))
    assert pins["version_pinned"] == [_CLEAN]

    prefix = _envs_of(PrefixSymlinkRule().generate(facts, _CFG, _ENVS))
    assert prefix["custom_prefix_symlink"] == [_CLEAN]
    assert prefix["custom_prefix_no_symlink"] == [_CLEAN]
    # The non-root prefix scenario uses the non-root clean env.
    assert prefix["custom_prefix_symlink_nonroot"] == [_CLEAN_NONROOT]


def test_no_install_env_uses_primary() -> None:
    """Without the override, install scenarios stay on the primary/pool envs."""
    facts = _facts(install_env=None)
    default = _envs_of(ExistenceDefaultRule().generate(facts, _CFG, _ENVS))
    assert default["default"] == ["ubuntu-stable"]

    prefix = _envs_of(PrefixSymlinkRule().generate(facts, _CFG, _ENVS))
    assert prefix["custom_prefix_symlink"] == ["ubuntu-stable"]
    assert prefix["custom_prefix_symlink_nonroot"] == ["ubuntu-stable+vscode"]
