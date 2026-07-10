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
        """Whether the feature *explicitly* declares brew support for `package`.

        Only when `package.when` names `plat.pm: brew` (or `plat.kernel: Darwin`)
        — an unconstrained `when` (all PMs) is not enough: many such tools (jq,
        git) are pre-installed on the macOS runner, so the feature detects the
        existing copy and skips the brew install, and the scenario can't verify a
        clean brew-managed install. Explicit brew intent is the reliable signal
        that a macos_package_default is meaningful and testable.
        """
        return (
            bool(cfg.macos_brew_env)
            and "package" in facts.methods
            and self._package_explicitly_brew(facts)
        )

    @staticmethod
    def _package_explicitly_brew(facts: FeatureFacts) -> bool:
        """Whether the package method's `when` names brew/Darwin explicitly."""
        when = facts.methods.get("package", {}).get("when")
        if when is None:
            return False
        for clause in when if isinstance(when, list) else [when]:
            pm = clause.get("plat.pm")
            if pm == "brew" or (isinstance(pm, list) and "brew" in pm):
                return True
            if clause.get("plat.kernel") == "Darwin":
                return True
        return False

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
        # The macOS runner user has write access to /usr/local (Homebrew owns it),
        # so the feature resolves to the *privileged* profile and records the
        # installed-method state under _FEAT_SHARE_DIR_ROOT (/usr/local/share),
        # verified in a real run — not the non-root ~/.local/share.
        ctx = context.for_env(env, envs, privileged=True)
        outcome = outcome_mod.compute(facts, ctx, method="package")
        if outcome is None:  # package not feasible on the brew env
            return None
        brew_pkg = facts.brew_package()
        name, is_cask = brew_pkg if brew_pkg is not None else (facts.primary_bin, False)
        kind = "cask" if is_cask else "formula"
        scenario = base_scenario([env], cfg, _FAMILY, options={"method": "package"})
        scenario["modes"] = ["macos"]
        # Clean slate: a shared macOS runner may already have the formula/cask.
        # Use the correct `--cask`/`--formula` kind and name (best-effort; casks
        # and formula-name overrides like go-task both occur).
        scenario["setup"] = (
            f"brew list --{kind} {name} >/dev/null 2>&1 "
            f"&& brew uninstall --{kind} {name} || true\n"
        )
        scenario["tests"] = ["macos_package_default"]

        checks: list[CheckItem] = [
            CheckItem(title="brew is on PATH", cmd="command -v brew"),
            # method_either_scope: a system-prefix feature records installed-method
            # under the root share dir, but one with a user-home prefix (rust's
            # ${HOME}/.cargo) records under nonroot even on the privileged macOS
            # runner — accept either.
            *default_checks.build(
                facts, cfg, outcome, method_pinned=True, method_either_scope=True
            ),
            checks_builtin.brew_managed_check(facts.primary_bin, name, is_cask=is_cask),
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
