"""Build a `ResolveContext` for a scenario's environment.

Bridges a `test/environments.yaml` env key (+ the scenario's version input and
any pre-provisioned toolchain) to the `method_resolver.ResolveContext` the
outcome model consumes, so rules don't each re-implement attribute flattening
and channel classification.
"""

from __future__ import annotations

from proman.test.environments import resolve_attributes
from proman.test.gen.method_resolver import ResolveContext, classify_channel


def for_env(
    env_name: str,
    envs: dict,
    *,
    privileged: bool = True,
    version_input: str | None = None,
    resolved_version: str | None = None,
    has_npm: bool = False,
    has_cargo: bool = False,
    has_git: bool = False,
) -> ResolveContext:
    """Build the resolve context for `env_name` under a scenario's request."""
    return ResolveContext(
        attrs=resolve_attributes(env_name, envs),
        privileged=privileged,
        version_channel=classify_channel(version_input),
        resolved_version=resolved_version,
        has_npm=has_npm,
        has_cargo=has_cargo,
        has_git=has_git,
    )
