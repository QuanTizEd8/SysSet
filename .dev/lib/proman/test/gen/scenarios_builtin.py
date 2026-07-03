"""Small, composable scenario-body builders shared by every rule.

Mirrors `checks_builtin.py`'s philosophy one level up: the repeated
"envs + modes-from-config" scaffold that every generated scenario needs is
one function here, not copy-pasted into each rule module.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from proman.test.gen.config import GenerationConfig


def base_scenario(
    envs: list[str],
    cfg: GenerationConfig,
    family: str,
    *,
    options: dict | None = None,
) -> dict:
    """Build a scenario dict with `envs:`, family-configured `modes:`, and `options:`.

    `modes:` is omitted entirely when the family has no configured override,
    letting the existing scenarios.yaml-consumer default (`[devcontainer,
    standalone]`) apply — the same behavior as a hand-written scenario that
    doesn't set `modes:`.
    """
    scenario: dict = {"envs": list(envs)}
    fam_cfg = cfg.families.get(family)
    if fam_cfg and fam_cfg.modes:
        scenario["modes"] = list(fam_cfg.modes)
    if options:
        scenario["options"] = dict(options)
    return scenario
