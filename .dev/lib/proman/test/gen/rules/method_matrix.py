"""One scenario per declared `_options.method.*`.

Isolation-tests each method explicitly, in addition to `default` (which
exercises whatever `auto` picks). Trigger: `_options.method` declared.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from proman.test.environments import resolve_attributes
from proman.test.gen import checks_builtin, default_checks, envselect
from proman.test.gen.naming import method_scenario_name
from proman.test.gen.registry import register
from proman.test.gen.scenarios_builtin import base_scenario
from proman.test.gen.types import CheckGroup, GeneratedScenario

if TYPE_CHECKING:
    from proman.test.gen.config import GenerationConfig
    from proman.test.gen.facts import FeatureFacts

_FAMILY = "method_matrix"

# Methods whose observable result (a working binary, verified identically to
# `default`) doesn't depend on the install mechanism, so they reuse the
# `default` check group verbatim rather than emitting their own.
_VERBATIM_METHODS = frozenset(
    {"source", "npm", "npm-bundled", "cargo", "script", "git-clone"},
)


@register
class MethodMatrixRule:
    """Generates one isolation-test scenario per declared install method."""

    family = _FAMILY
    check_generation = "full"

    def applies(self, facts: FeatureFacts, cfg: GenerationConfig) -> bool:  # noqa: ARG002
        """Whether this feature declares any install methods."""
        return bool(facts.methods)

    def generate(
        self,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,
    ) -> list[GeneratedScenario]:
        """One scenario per declared method, per the method-specific handlers below."""
        results: list[GeneratedScenario] = []
        for method, method_config in facts.methods.items():
            when = method_config.get("when")
            generated = self._generate_one(method, when, facts, cfg, envs)
            if generated is not None:
                results.append(generated)
        return results

    def _generate_one(
        self,
        method: str,
        when: dict | list | None,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,
    ) -> GeneratedScenario | None:
        if method == "package":
            return self._package_default(when, facts, cfg, envs)
        if method == "upstream-package":
            return self._single_env(
                "upstream_package_default",
                method,
                when,
                facts,
                cfg,
                envs,
                pm_check=True,
            )
        if method == "git-clone" and not facts.is_git_clone_only:
            # Only a distinct scenario when git-clone is one of *several*
            # methods — if it's the only one, `default` already covers it.
            return self._single_env(
                "git_clone_default",
                method,
                when,
                facts,
                cfg,
                envs,
                pm_check=False,
            )
        if method in _VERBATIM_METHODS and method != "git-clone":
            return self._single_env(
                method_scenario_name(method),
                method,
                when,
                facts,
                cfg,
                envs,
                pm_check=False,
            )
        return None

    def _package_default(
        self,
        when: dict | list | None,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,
    ) -> GeneratedScenario | None:
        selected = envselect.select_envs(
            when,
            envs,
            candidates=list(cfg.env_pool),
            policy="one_per_pm",
            primary_env=cfg.primary_env,
        )
        if not selected:
            return None
        name = "package_default"
        scenario = base_scenario(selected, cfg, _FAMILY, options={"method": "package"})
        scenario["tests"] = [name]
        pkg_name = facts.package_name("package")
        pms = sorted({resolve_attributes(e, envs).get("plat.pm") for e in selected})
        checks = [
            *default_checks.build(facts, cfg),
            checks_builtin.pm_managed_check(facts.primary_bin, pkg_name, pms),
        ]
        group = CheckGroup(
            description="method=package: installs via the OS package manager's "
            "standard configured sources.",
            checks=checks,
        )
        return GeneratedScenario(name=name, scenario=scenario, checks={name: group})

    def _single_env(
        self,
        name: str,
        method: str,
        when: dict | list | None,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,
        *,
        pm_check: bool,
    ) -> GeneratedScenario | None:
        selected = envselect.select_envs(
            when,
            envs,
            candidates=list(cfg.env_pool),
            policy="primary",
            primary_env=cfg.primary_env,
        )
        if not selected:
            return None
        env = selected[0]
        scenario = base_scenario([env], cfg, _FAMILY, options={"method": method})
        if not pm_check:
            # Verbatim reuse: point at the existing `default` check group
            # instead of emitting a new one.
            scenario["tests"] = ["default"]
            return GeneratedScenario(name=name, scenario=scenario, checks={})
        scenario["tests"] = [name]
        pkg_name = facts.package_name(method)
        pm = resolve_attributes(env, envs).get("plat.pm")
        checks = [
            *default_checks.build(facts, cfg),
            checks_builtin.pm_managed_check(facts.primary_bin, pkg_name, [pm]),
        ]
        group = CheckGroup(
            description=f"method={method}: installs via the OS package manager "
            "after adding/altering package-source configuration.",
            checks=checks,
        )
        return GeneratedScenario(name=name, scenario=scenario, checks={name: group})
