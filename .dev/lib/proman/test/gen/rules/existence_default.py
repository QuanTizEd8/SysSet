"""`default` scenario: PATH/binary existence, version-format, and functional checks.

Trigger: `_options.verify` present (virtually every `install-*` feature).
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from proman.test.gen import default_checks
from proman.test.gen.registry import register
from proman.test.gen.scenarios_builtin import base_scenario
from proman.test.gen.types import CheckGroup, GeneratedScenario

if TYPE_CHECKING:
    from proman.test.gen.config import GenerationConfig
    from proman.test.gen.facts import FeatureFacts

_FAMILY = "existence_default"


@register
class ExistenceDefaultRule:
    """Generates the `default` scenario for any feature with method/version/verify."""

    family = _FAMILY
    check_generation = "full"

    def applies(self, facts: FeatureFacts, cfg: GenerationConfig) -> bool:  # noqa: ARG002
        """Whether this feature has verify/method/version semantics to test.

        `_options.verify` alone would miss git-clone-only features (e.g.
        install-ohmybash/install-ohmyzsh), which declare neither `verify`
        nor `prefix.bins` but still need a `default` install-works scenario.
        """
        return bool(facts.verify or facts.methods or facts.version)

    def generate(
        self,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,  # noqa: ARG002
    ) -> list[GeneratedScenario]:
        """Generate the single `default` scenario."""
        scenario = base_scenario([cfg.primary_env], cfg, _FAMILY)
        scenario["tests"] = ["default"]
        group = CheckGroup(
            description="Verifies the default install puts a functional tool on PATH.",
            checks=default_checks.build(facts, cfg),
        )
        return [
            GeneratedScenario(
                name="default", scenario=scenario, checks={"default": group}
            ),
        ]
