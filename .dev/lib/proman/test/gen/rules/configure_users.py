"""`configure_users_default` scenario scaffold.

Trigger: `_options.configure_users: true`. Scaffold-only: this rule emits only
the scenario body (envs/options/`tests:` wiring) — the actual per-feature
`__configure_user` assertion is irreducibly feature-specific, so it must be
hand-authored as a `configure_users_default` checks.yaml group. No special
enforcement is needed here: if that group is missing, the existing
`FeatureTestLoader` cross-validation already raises a clear "references test
'configure_users_default' but checks.yaml has no such group" error.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from proman.test.gen.registry import register
from proman.test.gen.scenarios_builtin import base_scenario
from proman.test.gen.types import GeneratedScenario

if TYPE_CHECKING:
    from proman.test.gen.config import GenerationConfig
    from proman.test.gen.facts import FeatureFacts

_FAMILY = "configure_users"


@register
class ConfigureUsersRule:
    """Generates the `configure_users_default` scenario scaffold."""

    family = _FAMILY
    check_generation = "scaffold_only"

    def applies(self, facts: FeatureFacts, cfg: GenerationConfig) -> bool:  # noqa: ARG002
        """Whether this feature declares `_options.configure_users: true`."""
        return facts.configure_users

    def generate(
        self,
        facts: FeatureFacts,  # noqa: ARG002
        cfg: GenerationConfig,
        envs: dict,  # noqa: ARG002
    ) -> list[GeneratedScenario]:
        """Generate the single scaffold scenario."""
        name = "configure_users_default"
        scenario = base_scenario(
            [cfg.nonroot_env],
            cfg,
            _FAMILY,
            options={"add_current_user": True},
        )
        scenario["tests"] = [name]
        return [GeneratedScenario(name=name, scenario=scenario, checks={})]
