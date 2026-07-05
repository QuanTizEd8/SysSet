"""`version_pinned`/`version_legacy` scenarios.

Installs an explicit version, then cross-validates it was actually installed
(not just "a" version). Trigger: `_options.version.test_pins.{pinned,legacy}`
declared in metadata.yaml.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from proman.test.gen import checks_builtin, context, envselect
from proman.test.gen import outcome as outcome_mod
from proman.test.gen.method_resolver import feasible_methods
from proman.test.gen.naming import legacy_scenario_name, pinned_scenario_name
from proman.test.gen.registry import register
from proman.test.gen.scenarios_builtin import base_scenario
from proman.test.gen.types import CheckGroup, GeneratedScenario

if TYPE_CHECKING:
    from proman.test.gen.config import GenerationConfig
    from proman.test.gen.facts import FeatureFacts

_FAMILY = "version_pinning"


def _pin_method(facts: FeatureFacts, cfg: GenerationConfig, envs: dict, value: str):  # noqa: ANN202
    """Pick the method a pinned exact version should install with, on the primary env.

    Returns the first declared method (canonical priority order) that is
    *feasible for this specific version* — so an exact-semver pin is never
    assigned to `package`/`upstream-package`, which cannot resolve an arbitrary
    upstream version host-side (the zsh/rust class of bug). Falls back to the
    when-only `first_feasible_method` when the resolver finds none feasible, so
    a feature with only PM methods still gets a (best-effort) pinned scenario
    rather than silently losing coverage.
    """
    ctx = context.for_env(
        cfg.primary_env, envs, version_input=value, resolved_version=value
    )
    feasible = feasible_methods(facts, ctx)
    method = (
        feasible[0]
        if feasible
        else envselect.first_feasible_method(facts, envs, cfg.primary_env)
    )
    outcome = (
        outcome_mod.compute(facts, ctx, method=method, version=value)
        if method is not None
        else None
    )
    return method, outcome


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
        results: list[GeneratedScenario] = []
        for index, value in enumerate(pinned):
            name = pinned_scenario_name(index, len(pinned))
            results.append(self._scenario(name, value, env, facts, cfg, envs))
        for index, value in enumerate(legacy):
            name = legacy_scenario_name(index, len(legacy))
            results.append(self._scenario(name, value, env, facts, cfg, envs))
        return results

    def _scenario(
        self,
        name: str,
        value: str,
        env: str,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,
    ) -> GeneratedScenario:
        method, outcome = _pin_method(facts, cfg, envs, value)
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
        # Outcome verification: an explicit method pin records that exact method
        # in the installed-method state file — assert it (mirrors method_matrix).
        if outcome is not None and outcome.method is not None:
            checks.append(
                checks_builtin.installed_method_check(
                    outcome.method, outcome.share_dir_var
                ),
            )
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
