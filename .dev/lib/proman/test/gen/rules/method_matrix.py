"""One scenario per declared `_options.method.*`.

Isolation-tests each method explicitly, in addition to `default` (which
exercises whatever `auto` picks). Trigger: `_options.method` declared.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from proman.test.environments import resolve_attributes
from proman.test.gen import checks_builtin, context, default_checks, envselect
from proman.test.gen import outcome as outcome_mod
from proman.test.gen.method_resolver import declared_in_order
from proman.test.gen.naming import method_scenario_name
from proman.test.gen.registry import register
from proman.test.gen.scenarios_builtin import base_scenario
from proman.test.gen.types import CheckGroup, GeneratedScenario

if TYPE_CHECKING:
    from proman.test.gen.config import GenerationConfig
    from proman.test.gen.facts import FeatureFacts

_FAMILY = "method_matrix"

# Methods whose observable result is a working binary, verified via the same
# existence/version/functional bundle as `default` — each still emits its OWN
# group (asserting *its* recorded method + install location), rather than
# reusing the auto-resolved `default` group. `npm`/`cargo` need a pre-
# provisioned env (see `_npm_default`/`_cargo_default`).
_VERBATIM_METHODS = frozenset(
    {"binary", "source", "npm-bundled", "script", "git-clone"},
)


def _method_ctx(env: str, envs: dict, method: str):  # noqa: ANN202
    """Resolve context for an explicit-method scenario on `env` (run as root)."""
    return context.for_env(
        env,
        envs,
        privileged=True,
        has_npm=method == "npm",
        has_cargo=method == "cargo",
        has_git=method == "git-clone",
    )


def _method_group(
    facts: FeatureFacts,
    cfg: GenerationConfig,
    envs: dict,
    method: str,
    env: str,
    description: str,
) -> tuple[CheckGroup, outcome_mod.ExpectedOutcome | None]:
    """Build a per-method check group (own installed-method + location asserts)."""
    ctx = _method_ctx(env, envs, method)
    outcome = outcome_mod.compute(facts, ctx, method=method)
    group = CheckGroup(
        description=description, checks=default_checks.build(facts, cfg, outcome)
    )
    return group, outcome


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
        for method in declared_in_order(facts):
            when = facts.methods[method].get("when")
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
            return self._single_env("git_clone_default", method, when, facts, cfg, envs)
        if method in _VERBATIM_METHODS and method != "git-clone":
            return self._single_env(
                method_scenario_name(method), method, when, facts, cfg, envs
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
        # install_env (a tool pre-installed on the pool, e.g. bash): its package
        # install runs fresh only where the tool is absent, so pin that env
        # (filtered by the method's when) instead of fanning across the pool.
        if facts.install_env:
            selected = envselect.feasible_envs(
                when, envs, candidates=[facts.install_env]
            )
        else:
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
        pms = sorted({resolve_attributes(e, envs).get("plat.pm") for e in selected})
        pkg_names = {pm: facts.package_name(method, pm) for pm in pms}
        verb = (
            "the OS package manager's standard configured sources"
            if method == "package"
            else "the OS package manager after adding/altering package-source "
            "configuration"
        )
        group, _ = _method_group(
            facts,
            cfg,
            envs,
            method,
            selected[0],
            f"method={method}: installs via {verb}.",
        )
        group["checks"].append(
            checks_builtin.pm_managed_check(facts.primary_bin, pkg_names, pms),
        )
        return GeneratedScenario(name=name, scenario=scenario, checks={name: group})

    def _provisioned_env_default(
        self,
        method: str,
        when: dict | list | None,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,
        env: str,
    ) -> GeneratedScenario | None:
        """`npm`/`cargo` on a pre-provisioned env (npm/cargo not a WhenSpec attr).

        None of these features declare a dependency block bootstrapping the
        toolchain (Node/Rust is expected pre-installed), so the normal
        `when:`-driven env pool doesn't apply — `env` points at a pre-
        provisioned environment. Still respects the method's own `when:` (if
        any) via `feasible_envs`.
        """
        if not envselect.feasible_envs(when, envs, candidates=[env]):
            return None
        name = method_scenario_name(method)
        scenario = base_scenario([env], cfg, _FAMILY, options={"method": method})
        scenario["tests"] = [name]
        group, _ = _method_group(
            facts,
            cfg,
            envs,
            method,
            env,
            f"method={method}: installs on a pre-provisioned env.",
        )
        return GeneratedScenario(name=name, scenario=scenario, checks={name: group})

    def _npm_default(
        self,
        when: dict | list | None,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,
    ) -> GeneratedScenario | None:
        """`npm` isolation test on the pre-provisioned Node env."""
        return self._provisioned_env_default("npm", when, facts, cfg, envs, cfg.npm_env)

    def _cargo_default(
        self,
        when: dict | list | None,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,
    ) -> GeneratedScenario | None:
        """`cargo` isolation test on the pre-provisioned Rust env."""
        return self._provisioned_env_default(
            "cargo", when, facts, cfg, envs, cfg.cargo_env
        )

    def _single_env(
        self,
        name: str,
        method: str,
        when: dict | list | None,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,
    ) -> GeneratedScenario | None:
        """Single-env method scenario emitting its own outcome-verifying group.

        The observable result is a working binary (same shape as `default`),
        but the group asserts *this* method's recorded installed-method and
        install location — not the auto-resolved one.
        """
        if facts.install_env:
            selected = envselect.feasible_envs(
                when, envs, candidates=[facts.install_env]
            )
        else:
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
        scenario["tests"] = [name]
        group, _ = _method_group(
            facts,
            cfg,
            envs,
            method,
            selected[0],
            f"method={method}: installs a working tool.",
        )
        return GeneratedScenario(name=name, scenario=scenario, checks={name: group})
