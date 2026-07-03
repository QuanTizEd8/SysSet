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
# `default` check group verbatim rather than emitting their own. `npm` and
# `cargo` are handled separately (each needs a pre-provisioned env — see
# `_npm_default`/`_cargo_default`).
_VERBATIM_METHODS = frozenset(
    {"binary", "source", "npm-bundled", "script", "git-clone"},
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
        if method in ("package", "upstream-package"):
            return self._pm_managed_default(method, when, facts, cfg, envs)
        if method == "npm":
            return self._npm_default(when, facts, cfg, envs)
        if method == "cargo":
            return self._cargo_default(when, facts, cfg, envs)
        if method == "git-clone" and not facts.is_git_clone_only:
            # Only a distinct scenario when git-clone is one of *several*
            # methods — if it's the only one, `default` already covers it.
            return self._single_env("git_clone_default", method, when, cfg, envs)
        if method in _VERBATIM_METHODS and method != "git-clone":
            return self._single_env(
                method_scenario_name(method), method, when, cfg, envs
            )
        return None

    def _pm_managed_default(
        self,
        method: str,
        when: dict | list | None,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,
    ) -> GeneratedScenario | None:
        """Shared body for `package`/`upstream-package`: one env per feasible PM.

        Both install via the OS package manager and are equally likely to have
        per-PM setup code (repo/key configuration for `upstream-package`, or
        just differing package availability for `package`) that a single-env
        test would leave unexercised for every PM but one.
        """
        selected = envselect.select_envs(
            when,
            envs,
            candidates=list(cfg.env_pool),
            policy="one_per_pm",
            primary_env=cfg.primary_env,
        )
        if not selected:
            return None
        name = method_scenario_name(method)
        scenario = base_scenario(selected, cfg, _FAMILY, options={"method": method})
        scenario["tests"] = [name]
        pkg_name = facts.package_name(method)
        pms = sorted({resolve_attributes(e, envs).get("plat.pm") for e in selected})
        checks = [
            *default_checks.build(facts, cfg),
            checks_builtin.pm_managed_check(facts.primary_bin, pkg_name, pms),
        ]
        verb = (
            "the OS package manager's standard configured sources"
            if method == "package"
            else "the OS package manager after adding/altering package-source "
            "configuration"
        )
        group = CheckGroup(
            description=f"method={method}: installs via {verb}.",
            checks=checks,
        )
        return GeneratedScenario(name=name, scenario=scenario, checks={name: group})

    def _npm_default(
        self,
        when: dict | list | None,
        facts: FeatureFacts,  # noqa: ARG002
        cfg: GenerationConfig,
        envs: dict,
    ) -> GeneratedScenario | None:
        """`npm` needs Node.js/npm already installed — not a WhenSpec attribute.

        None of the AI-CLI-tool features declare a `method-npm` dependency
        block (by design — Node.js is expected to be pre-installed, e.g. via
        `install-node`), so this can't use the normal `when:`-driven env pool
        the way other methods do. `cfg.npm_env` points at a pre-provisioned
        environment instead; still respects the method's own `when:` (if any)
        via `feasible_envs`, so a feature that further restricts `npm` to a
        specific platform is not silently tested on an incompatible one.
        """
        if not envselect.feasible_envs(when, envs, candidates=[cfg.npm_env]):
            return None
        scenario = base_scenario([cfg.npm_env], cfg, _FAMILY, options={"method": "npm"})
        scenario["tests"] = ["default"]
        return GeneratedScenario(
            name=method_scenario_name("npm"),
            scenario=scenario,
            checks={},
        )

    def _cargo_default(
        self,
        when: dict | list | None,
        facts: FeatureFacts,  # noqa: ARG002
        cfg: GenerationConfig,
        envs: dict,
    ) -> GeneratedScenario | None:
        """`cargo` needs a Rust toolchain already installed — not a WhenSpec attribute.

        Features declaring a `cargo` method only list build tools (make, a C
        compiler) in `_dependencies.build.method-cargo` — cargo/rustc itself is
        assumed pre-installed, not bootstrapped by the feature. Confirmed via a
        real Docker run: method=cargo on the bare primary env (no rustc) fails
        outright. `cfg.cargo_env` points at a pre-provisioned environment
        instead, mirroring `_npm_default`.
        """
        if not envselect.feasible_envs(when, envs, candidates=[cfg.cargo_env]):
            return None
        scenario = base_scenario(
            [cfg.cargo_env], cfg, _FAMILY, options={"method": "cargo"}
        )
        scenario["tests"] = ["default"]
        return GeneratedScenario(
            name=method_scenario_name("cargo"),
            scenario=scenario,
            checks={},
        )

    def _single_env(
        self,
        name: str,
        method: str,
        when: dict | list | None,
        cfg: GenerationConfig,
        envs: dict,
    ) -> GeneratedScenario | None:
        """Single-env, verbatim reuse of the `default` check group.

        For methods whose observable result is identical to whatever `default`
        already verifies — no method-specific assertion is needed.
        """
        selected = envselect.select_envs(
            when,
            envs,
            candidates=list(cfg.env_pool),
            policy="primary",
            primary_env=cfg.primary_env,
        )
        if not selected:
            return None
        scenario = base_scenario(selected, cfg, _FAMILY, options={"method": method})
        scenario["tests"] = ["default"]
        return GeneratedScenario(name=name, scenario=scenario, checks={})
