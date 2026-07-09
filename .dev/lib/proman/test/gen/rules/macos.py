"""macOS-native scenarios (`modes: [macos]`).

Currently generates `macos_package_default`: `method=package` installed via
Homebrew on a native macOS runner — the scenario repeated by hand across
install-{act,claude,copilot,git,lefthook,taskfile}. Requires the
`environments.macos_brew_env` pointer (a macOS env with Homebrew) and that the
feature's `package` method is feasible there. The runner (`run.py`'s
`_run_macos`) already supports `modes: [macos]`; only generation was missing.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from proman.test.gen import checks_builtin, context, default_checks
from proman.test.gen import outcome as outcome_mod
from proman.test.gen.registry import register
from proman.test.gen.scenarios_builtin import base_scenario
from proman.test.gen.types import CheckGroup, CheckItem, GeneratedScenario

if TYPE_CHECKING:
    from proman.test.gen.config import GenerationConfig
    from proman.test.gen.facts import FeatureFacts

_FAMILY = "macos"


@register
class MacosRule:
    """Generates the macOS-native scenario family."""

    family = _FAMILY
    check_generation = "full"

    def applies(self, facts: FeatureFacts, cfg: GenerationConfig) -> bool:
        """Whether a macOS env is configured and the feature has a brew package."""
        return bool(cfg.macos_brew_env) and "package" in facts.methods

    def generate(
        self,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,
    ) -> list[GeneratedScenario]:
        """Generate macos_package_default when the package method is brew-feasible."""
        pkg = self._brew_package(facts, cfg, envs)
        if pkg is None:
            return []
        return [pkg]

    def _brew_package(
        self,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,
    ) -> GeneratedScenario | None:
        env = cfg.macos_brew_env
        ctx = context.for_env(env, envs)
        outcome = outcome_mod.compute(facts, ctx, method="package")
        if outcome is None:  # package not feasible on the brew env
            return None
        pkg_name = facts.package_name("package", "brew")
        scenario = base_scenario([env], cfg, _FAMILY, options={"method": "package"})
        scenario["modes"] = ["macos"]
        # Clean slate: a shared macOS runner may already have the formula.
        scenario["setup"] = (
            f"brew list --formula {pkg_name} >/dev/null 2>&1 "
            f"&& brew uninstall --formula {pkg_name} || true\n"
        )
        scenario["tests"] = ["macos_package_default"]

        checks: list[CheckItem] = [
            CheckItem(title="brew is on PATH", cmd="command -v brew"),
            *default_checks.build(facts, cfg, outcome, method_pinned=True),
            checks_builtin.pm_managed_check(
                facts.primary_bin, {"brew": pkg_name}, ["brew"]
            ),
        ]
        group = CheckGroup(
            description=f"method=package on macOS installs {facts.primary_bin} from "
            f"the standard Homebrew formula. Verifies it is on PATH, functional, "
            f"brew-managed, and records installed-method=package.",
            checks=checks,
        )
        return GeneratedScenario(
            name="macos_package_default",
            scenario=scenario,
            checks={"macos_package_default": group},
        )
