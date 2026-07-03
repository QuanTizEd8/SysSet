"""`invalid_<option>` scenarios.

An out-of-range enum value fails with the exact argparse.bash error message.
Trigger: the feature declares at least one of the configurable enum-typed
options (default: `method`, `if_exists`).
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from proman.test.gen.naming import invalid_option_scenario_name
from proman.test.gen.registry import register
from proman.test.gen.scenarios_builtin import base_scenario
from proman.test.gen.types import CheckGroup, CheckItem, GeneratedScenario

if TYPE_CHECKING:
    from proman.test.gen.config import GenerationConfig
    from proman.test.gen.facts import FeatureFacts

_FAMILY = "invalid_enum"
_BOGUS_VALUE = "bogus-value"


@register
class InvalidEnumRule:
    """Generates one invalid-value scenario per configured, declared enum option."""

    family = _FAMILY
    check_generation = "full"

    def applies(self, facts: FeatureFacts, cfg: GenerationConfig) -> bool:
        """Whether at least one configured enum option is declared by this feature."""
        options = cfg.families[_FAMILY].options if _FAMILY in cfg.families else ()
        return any(facts.enum_values(option) is not None for option in options)

    def generate(
        self,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,  # noqa: ARG002
    ) -> list[GeneratedScenario]:
        """One `invalid_<option>` scenario per configured, declared enum option."""
        results = []
        for option in cfg.families[_FAMILY].options:
            values = facts.enum_values(option)
            if values is None:
                continue
            results.append(self._scenario(option, values, cfg))
        return results

    def _scenario(
        self,
        option: str,
        values: list[str],
        cfg: GenerationConfig,
    ) -> GeneratedScenario:
        name = invalid_option_scenario_name(option)
        scenario = base_scenario(
            [cfg.primary_env],
            cfg,
            _FAMILY,
            options={option: _BOGUS_VALUE},
        )
        scenario["expect_install_failure"] = True
        scenario["tests"] = [name]
        expected = ", ".join(values)
        pattern = (
            f"Invalid value for '{option}': '{_BOGUS_VALUE}' (expected: {expected})"
        )
        check = CheckItem(
            title=f"invalid {option} value fails with clear error",
            kind="install_failure",
            pattern=pattern,
        )
        group = CheckGroup(
            description=f"An out-of-range {option} value is rejected with a clear "
            "error.",
            checks=[check],
        )
        return GeneratedScenario(name=name, scenario=scenario, checks={name: group})
