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
) -> str | None:
    """Pick the first declared method (declaration order) feasible on `env_name`.

    Returns None if the feature declares no methods (or none are feasible
    there). Used to pick an explicit `method:` for scenarios that pin a
    method rather than leaving it to `auto` resolution.
    """
    attrs = resolve_attributes(env_name, envs)
    for name, method_config in facts.methods.items():
        if when_util.match(method_config.get("when"), attrs):
            return name
    return None
