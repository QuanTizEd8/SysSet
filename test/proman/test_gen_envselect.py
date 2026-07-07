"""Tests for envselect.auto_install_env.

A method=auto scenario must run where the feature can actually auto-install:
the primary env when feasible there, else the first env-pool member where a
method resolves (install-tokei on ubuntu-stable resolves nothing).
"""

from __future__ import annotations

from proman.test.gen import envselect
from proman.test.gen.config import GenerationConfig
from proman.test.gen.facts import FeatureFacts

_ENVS = {
    "ubuntu-stable": {
        "attributes": {
            "os.id": "ubuntu",
            "plat.pm": "apt",
            "plat.kernel": "linux",
            "plat.machine_release": ["amd64", "arm64"],
        },
    },
    "alpine-current": {
        "attributes": {
            "os.id": "alpine",
            "plat.pm": "apk",
            "plat.kernel": "linux",
            "plat.machine_release": ["amd64", "arm64"],
        },
    },
}

_CFG = GenerationConfig(
    enabled=True,
    rollout_mode="all",
    allowlist=frozenset(),
    denylist=frozenset(),
    primary_env="ubuntu-stable",
    nonroot_env="ubuntu-stable",
    env_pool=("ubuntu-stable", "alpine-current"),
)


def _facts(methods: dict) -> FeatureFacts:
    return FeatureFacts(
        feature_id="install-fixture",
        verify={"args": "--version"},
        methods=methods,
        prefix={"bins": ["tool"]},
    )


def test_prefers_primary_env_when_feasible() -> None:
    """When the feature auto-installs on the primary env, that env is used."""
    facts = _facts({"binary": {"when": {"plat.machine_release": ["amd64", "arm64"]}}})
    assert envselect.auto_install_env(facts, _CFG, _ENVS) == "ubuntu-stable"


def test_falls_back_to_feasible_pool_env() -> None:
    """No method feasible on the primary env → first pool env where one is."""
    # package restricted to apk: infeasible on ubuntu (apt), feasible on alpine.
    facts = _facts({"package": {"when": {"plat.pm": "apk"}}})
    assert envselect.auto_install_env(facts, _CFG, _ENVS) == "alpine-current"
