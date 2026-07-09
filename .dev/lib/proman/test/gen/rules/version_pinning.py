"""`version_pinned`/`version_legacy` scenarios.

Installs an explicit version, then cross-validates it was actually installed
(not just "a" version). Trigger: `_options.version.test_pins.{pinned,legacy}`
declared in metadata.yaml.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from proman.test.gen import checks_builtin, context, default_checks, envselect
from proman.test.gen import outcome as outcome_mod
from proman.test.gen.naming import legacy_scenario_name, pinned_scenario_name
from proman.test.gen.registry import register
from proman.test.gen.scenarios_builtin import base_scenario
from proman.test.gen.types import CheckGroup, GeneratedScenario

if TYPE_CHECKING:
    from proman.test.gen.config import GenerationConfig
    from proman.test.gen.facts import FeatureFacts

_FAMILY = "version_pinning"


def _pin_method(facts: FeatureFacts, envs: dict, env: str, value: str):  # noqa: ANN202
    """Pick the method + expected outcome for a pinned exact version, on `env`.

    `first_feasible_method(version=value)` picks the canonical-first method that
    is *feasible for this specific version* — so an exact-semver pin is never
    assigned to `package`/`upstream-package`, which cannot resolve an arbitrary
    upstream version host-side (the zsh/rust class of bug).
    """
    method = envselect.first_feasible_method(facts, envs, env, version=value)
    ctx = context.for_env(env, envs, version_input=value, resolved_version=value)
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
        env = facts.install_env or cfg.primary_env
        results: list[GeneratedScenario] = []
        for index, value in enumerate(pinned):
            name = pinned_scenario_name(index, len(pinned))
            results.append(self._scenario(name, value, env, facts, cfg, envs))
        for index, value in enumerate(legacy):
            name = legacy_scenario_name(index, len(legacy))
            results.append(self._scenario(name, value, env, facts, cfg, envs))
        # Partial-semver input: `version: X.Y` must resolve to the latest X.Y.z.
        # Distinct from the exact pins (different version input) — exercises the
        # resolver's partial-match path, which nothing else covers.
        if pinned:
            partial = self._partial(pinned[0], env, facts, cfg, envs)
            if partial is not None:
                results.append(partial)
        return results

    def _partial(
        self,
        exact: str,
        env: str,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,
    ) -> GeneratedScenario | None:
        """Build a `version: X.Y` scenario from the exact pin's major.minor."""
        parts = exact.split(".")
        min_semver_parts = 3  # need X.Y.Z to shorten to a distinct X.Y
        if len(parts) < min_semver_parts:
            return None
        xy = ".".join(parts[:2])
        # Upstream-resolving methods only (binary/source/npm/cargo): they resolve
        # X.Y against the release list, unlike package (PM availability varies).
        method = envselect.first_feasible_method(
            facts, envs, env, version=xy, allowed=facts.prefix_capable_methods
        )
        if method is None:
            return None
        scenario = base_scenario(
            [env], cfg, _FAMILY, options={"version": xy, "method": method}
        )
        scenario["tests"] = ["version_partial"]
        ctx = context.for_env(env, envs, version_input=xy)
        outcome = outcome_mod.compute(facts, ctx, method=method)
        # Full outcome bundle (with a generic version-format check) PLUS the
        # partial-semver assertion that the resolved version is X.Y.z.
        checks = default_checks.build(facts, cfg, outcome, method_pinned=True)
        checks.append(
            checks_builtin.version_prefix_check(
                facts.primary_bin, facts.version_flag, xy
            )
        )
        group = CheckGroup(
            description=f"version={xy} (partial semver) resolves to the latest {xy}.z.",
            checks=checks,
        )
        return GeneratedScenario(
            name="version_partial", scenario=scenario, checks={"version_partial": group}
        )

    def _scenario(
        self,
        name: str,
        value: str,
        env: str,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,
    ) -> GeneratedScenario:
        method, outcome = _pin_method(facts, envs, env, value)
        options = {"version": value}
        if method is not None:
            options["method"] = method
        scenario = base_scenario([env], cfg, _FAMILY, options=options)
        scenario["tests"] = [name]

        # The comprehensive outcome bundle: exact install location(s), the
        # cross-validated pinned version (outcome.version=value drives the exact
        # version check), functional, recorded method, and symlink/export
        # present-or-absent — the full state, not just "the pinned version runs".
        checks = default_checks.build(
            facts, cfg, outcome, method_pinned=method is not None
        )
        group = CheckGroup(
            description=f"version={value}: installs and verifies this exact version.",
            checks=checks,
        )
        return GeneratedScenario(name=name, scenario=scenario, checks={name: group})
