"""`version_pinned`/`version_legacy` scenarios.

Installs an explicit version, then cross-validates it was actually installed
(not just "a" version). Trigger: `_options.version.test_pins.{pinned,legacy}`
declared in metadata.yaml.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from proman.test.gen import checks_builtin, envselect
from proman.test.gen.naming import legacy_scenario_name, pinned_scenario_name
from proman.test.gen.registry import register
from proman.test.gen.scenarios_builtin import base_scenario
from proman.test.gen.types import CheckGroup, GeneratedScenario

if TYPE_CHECKING:
    from proman.test.gen.config import GenerationConfig
    from proman.test.gen.facts import FeatureFacts

_FAMILY = "version_pinning"


@register
class VersionPinningRule:
    """Generates one scenario per declared `test_pins.pinned`/`.legacy` entry."""

    family = _FAMILY
    check_generation = "full"

    def applies(self, facts: FeatureFacts, cfg: GenerationConfig) -> bool:  # noqa: ARG002
        """Whether this feature declares any pinned or legacy test versions."""
        pinned, legacy = facts.test_pins
        return bool(pinned or legacy)

    def generate(
        self,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,
    ) -> list[GeneratedScenario]:
        """One scenario per declared pinned/legacy version value."""
        pinned, legacy = facts.test_pins
        env = cfg.primary_env
        method = envselect.first_feasible_method(facts, envs, env)
        results: list[GeneratedScenario] = []
        for index, value in enumerate(pinned):
            name = pinned_scenario_name(index, len(pinned))
            results.append(self._scenario(name, value, env, method, facts, cfg))
        for index, value in enumerate(legacy):
            name = legacy_scenario_name(index, len(legacy))
            results.append(self._scenario(name, value, env, method, facts, cfg))
        return results

    def _scenario(
        self,
        name: str,
        value: str,
        env: str,
        method: str | None,
        facts: FeatureFacts,
        cfg: GenerationConfig,
    ) -> GeneratedScenario:
        options = {"version": value}
        if method is not None:
            options["method"] = method
        scenario = base_scenario([env], cfg, _FAMILY, options=options)
        scenario["tests"] = [name]

        primary = facts.primary_bin
        resolved_path = facts.resolved_bin_path(facts.default_prefix_root, primary)
        checks = [
            *checks_builtin.existence_triad(primary, path=resolved_path),
            checks_builtin.version_exact_check(primary, facts.version_flag, value),
        ]
        functional = facts.functional
        if functional is not None:
            cmd_template, description = functional
            checks.append(
                checks_builtin.functional_check(
                    cmd_template, description, resolved_path
                ),
            )
        group = CheckGroup(
            description=f"version={value}: installs and verifies this exact version.",
            checks=checks,
        )
        return GeneratedScenario(name=name, scenario=scenario, checks={name: group})
