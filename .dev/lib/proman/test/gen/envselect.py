"""Resolve which test/environments.yaml keys satisfy a metadata `when:` clause.

Bridges the WhenSpec grammar used throughout metadata.yaml
(`_options.method.*.when`, `_dependencies.*.when`, `_system_requirements.platforms`)
to concrete `test/environments.yaml` keys, using each environment's flattened
`attributes:` (see `proman.test.environments.resolve_attributes`) and the
generic `proman.when_util.match()` predicate.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Literal

from proman import when_util
from proman.test.environments import resolve_attributes
from proman.test.gen import context
from proman.test.gen.method_resolver import feasible_methods

if TYPE_CHECKING:
    from proman.test.gen.facts import FeatureFacts

SelectPolicy = Literal["primary", "one_per_pm", "all"]


def feasible_envs(
    when: dict | list | None,
    envs: dict,
    *,
    candidates: list[str] | None = None,
) -> list[str]:
    """Environment keys whose flattened attributes satisfy `when`.

    Considers `candidates`, or every key in `envs` if omitted. A `None`/empty
    `when` matches every candidate.
    """
    pool = candidates if candidates is not None else list(envs.keys())
    return [
        name for name in pool if when_util.match(when, resolve_attributes(name, envs))
    ]


def select_envs(
    when: dict | list | None,
    envs: dict,
    *,
    candidates: list[str],
    policy: SelectPolicy,
    primary_env: str,
) -> list[str]:
    """Apply an env-selection policy on top of `feasible_envs()`.

    - "primary": the configured `primary_env` if it's feasible; otherwise the
      first feasible candidate (a family still gets an env to run in, rather
      than silently generating a scenario with an empty `envs:`).
    - "one_per_pm": one feasible env per distinct `plat.pm` attribute value —
      e.g. jq's `package_default`: one apt/apk/dnf environment each.
    - "all": every feasible candidate.

    Returns an empty list when nothing is feasible; callers treat that as
    "this scenario/method is not generated for this feature".
    """
    feasible = feasible_envs(when, envs, candidates=candidates)
    if not feasible or policy == "all":
        return feasible
    if policy == "one_per_pm":
        seen_pms: set[object] = set()
        selected: list[str] = []
        for name in feasible:
            pm = resolve_attributes(name, envs).get("plat.pm")
            if pm in seen_pms:
                continue
            seen_pms.add(pm)
            selected.append(name)
        return selected
    # "primary"
    return [primary_env] if primary_env in feasible else [feasible[0]]


def first_feasible_method(
    facts: FeatureFacts,
    envs: dict,
    env_name: str,
    *,
    allowed: list[str] | None = None,
    version: str | None = None,
    privileged: bool = True,
    has_npm: bool = False,
    has_cargo: bool = False,
    has_git: bool = False,
) -> str | None:
    """Pick the method a scenario should pin on `env_name` for `version`.

    The first declared method in *canonical priority order* that is fully
    feasible under the resolver's gates (`method_resolver.is_feasible`) — the
    same method a `METHOD=auto` install would land on — not merely the first
    declaration-order method whose `when:` clause matches. This aligns pinned
    scenarios with the runtime auto-resolver (16 features declare methods in
    non-canonical order) and makes selection version-channel aware: an exact
    `version` is judged against package/upstream-package's channel gates, so a
    specific-version pin never lands on a PM method that can't resolve it.

    Returns None if the feature declares no methods, or none are feasible here
    under the given provisioning (`has_npm`/`has_cargo`/`has_git` default to a
    bare env — an npm/cargo/git-only method is infeasible unless provisioned).

    `allowed`, when given, additionally restricts the pick to method names in
    that list — e.g. `facts.prefix_compatible_methods`, so a scenario that
    depends on PREFIX/PATH resolution never pins a method for which `--prefix`
    would be silently ignored.
    """
    ctx = context.for_env(
        env_name,
        envs,
        privileged=privileged,
        version_input=version,
        resolved_version=version,
        has_npm=has_npm,
        has_cargo=has_cargo,
        has_git=has_git,
    )
    for name in feasible_methods(facts, ctx):
        if allowed is None or name in allowed:
            return name
    return None
