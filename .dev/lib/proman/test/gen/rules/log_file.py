"""`log_file` scenario.

The universal `log_file` option writes a real, non-empty install log with
the framework's own lifecycle markers. Trigger: always — every feature
exposes `log_file` (from `metadata.shared.yaml`), and the markers checked
here are framework-generic, not tool-specific (`logging__feature_entry`/
`__exit__` in install.tmpl.bash), so no feature-specific knowledge is
required.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from proman.test.gen import envselect
from proman.test.gen.registry import register
from proman.test.gen.scenarios_builtin import base_scenario
from proman.test.gen.types import CheckGroup, CheckItem, GeneratedScenario

if TYPE_CHECKING:
    from proman.test.gen.config import GenerationConfig
    from proman.test.gen.facts import FeatureFacts

_FAMILY = "log_file"


@register
class LogFileRule:
    """Generates the `log_file` scenario, universally."""

    family = _FAMILY
    check_generation = "full"

    def applies(self, facts: FeatureFacts, cfg: GenerationConfig) -> bool:  # noqa: ARG002
        """Apply always — every feature exposes the universal `log_file` option."""
        return True

    def generate(
        self,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,
    ) -> list[GeneratedScenario]:
        """Generate the single `log_file` scenario."""
        name = "log_file"
        path = f"/tmp/devfeats-test-{facts.feature_id}.log"  # noqa: S108
        # method=auto: run where the feature actually auto-installs (some can't
        # on the primary env — see envselect.auto_install_env; install_env
        # overrides for pre-installed tools like bash).
        env = facts.install_env or envselect.auto_install_env(facts, cfg, envs)
        scenario = base_scenario(
            [env],
            cfg,
            _FAMILY,
            options={"log_file": path},
        )
        scenario["tests"] = [name]
        checks = [
            CheckItem(title="log_file exists", cmd=f"test -f {path}"),
            CheckItem(title="log_file is non-empty", cmd=f"test -s {path}"),
            CheckItem(
                title="log_file contains script entry marker",
                cmd=f"grep -q 'Script entry: ' {path}",
            ),
            CheckItem(
                title="log_file contains successful completion marker",
                cmd=f"grep -q 'script finished successfully' {path}",
            ),
        ]
        group = CheckGroup(
            description=f"log_file={path}: install log captures lifecycle markers.",
            checks=checks,
        )
        return [GeneratedScenario(name=name, scenario=scenario, checks={name: group})]
