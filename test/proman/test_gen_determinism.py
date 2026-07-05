"""Generator determinism: method *declaration* order must not affect output.

The method-dependent rules select via method_resolver's canonical priority
order, so the same feature with its `_options.method` keys declared in a
different order must generate byte-identical scenarios/checks. Guards the
first_feasible_method/feasible_methods canonical-order contract at the rule
level (the resolver-level guard lives in test_gen_method_resolver).
"""

from __future__ import annotations

import itertools

from proman.test.gen.config import GenerationConfig
from proman.test.gen.facts import FeatureFacts
from proman.test.gen.rules.if_exists import IfExistsRule
from proman.test.gen.rules.prefix_symlink import PrefixSymlinkRule
from proman.test.gen.rules.version_pinning import VersionPinningRule

_ENVS = {
    "ubuntu-stable": {
        "attributes": {
            "os.id": "ubuntu",
            "plat.pm": "apt",
            "plat.kernel": "linux",
            "plat.machine_release": ["amd64", "arm64"],
        },
    },
    "ubuntu-stable+vscode": {"from": "ubuntu-stable"},
}

_CFG = GenerationConfig(
    enabled=True,
    rollout_mode="all",
    allowlist=frozenset(),
    denylist=frozenset(),
    primary_env="ubuntu-stable",
    nonroot_env="ubuntu-stable+vscode",
)

_AMD_ARM = {"plat.machine_release": ["amd64", "arm64"]}

# A rich multi-method shape (install-rust/ruff-like): PM + prefix-capable +
# a version-gated binary, declared in a deliberately non-canonical order.
_METHOD_CONFIGS = {
    "package": {},
    "source": {},
    "binary": {"when": _AMD_ARM},
    "script": {},
}


def _facts(methods: dict) -> FeatureFacts:
    return FeatureFacts(
        feature_id="install-fixture",
        verify={"args": "--version"},
        methods=methods,
        version={"test_pins": {"pinned": ["1.2.3"], "legacy": ["1.0"]}},
        prefix={"bins": ["tool"]},
    )


def _generate_all(methods: dict) -> list:
    facts = _facts(methods)
    out = [
        (scenario.name, scenario.scenario, scenario.checks)
        for rule in (VersionPinningRule(), PrefixSymlinkRule(), IfExistsRule())
        for scenario in rule.generate(facts, _CFG, _ENVS)
    ]
    return sorted(out, key=lambda item: item[0])


def test_output_invariant_under_method_key_shuffle() -> None:
    """Every declaration-order permutation yields identical generated output."""
    keys = list(_METHOD_CONFIGS)
    baseline = _generate_all(_METHOD_CONFIGS)
    assert baseline  # sanity: the shape actually generates something
    for perm in itertools.permutations(keys):
        shuffled = {k: _METHOD_CONFIGS[k] for k in perm}
        assert _generate_all(shuffled) == baseline
