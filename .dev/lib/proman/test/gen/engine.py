"""Orchestrator: runs every enabled, applicable rule for one feature.

Assembles their output into scenarios.yaml/checks.yaml-shaped data. This is
the only module that knows about the full registered rule set — rules
themselves never reference each other or list themselves anywhere but their
own file. See `proman.test.gen.registry` for the plugin mechanism.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import TYPE_CHECKING

from proman.test.gen import rules  # noqa: F401  (import for @register side effects)
from proman.test.gen.errors import GeneratorInternalError
from proman.test.gen.facts import extract
from proman.test.gen.registry import all_rules

if TYPE_CHECKING:
    from proman.test.gen.config import GenerationConfig
    from proman.test.gen.types import CheckGroup, GeneratedScenario


@dataclass(frozen=True)
class GeneratedTests:
    """All generated content for one feature.

    Shaped like a loaded scenarios.yaml (`scenarios`) + checks.yaml
    (`checks`) pair.
    """

    scenarios: dict[str, dict] = field(default_factory=dict)
    checks: dict[str, CheckGroup] = field(default_factory=dict)


def generate_feature_tests(
    feature_id: str,
    metadata: dict,
    cfg: GenerationConfig,
    envs: dict,
) -> GeneratedTests:
    """Generate scenarios/checks for one feature from its augmented metadata.yaml.

    Returns an empty `GeneratedTests` when generation is disabled globally or
    this feature isn't in scope per `cfg`'s rollout settings — the zero-effort
    "generation contributes nothing" state used while a feature (or the whole
    pipeline) hasn't been reviewed/enabled yet.
    """
    result = GeneratedTests()
    if not cfg.applies_to(feature_id):
        return result

    facts = extract(metadata)
    for rule in all_rules():
        if not cfg.family_enabled(rule.family):
            continue
        if not rule.applies(facts, cfg):
            continue
        for generated in rule.generate(facts, cfg, envs):
            _merge_one(result, rule.family, generated)
    return result


def _merge_one(
    result: GeneratedTests,
    family: str,
    generated: GeneratedScenario,
) -> None:
    if generated.name in result.scenarios:
        msg = (
            f"generator rule family {family!r} produced scenario "
            f"{generated.name!r}, which another enabled rule already produced "
            "for this feature — rules must be feature-shape-disjoint; this is "
            "a bug in the rule set, not a per-feature issue"
        )
        raise GeneratorInternalError(msg)
    result.scenarios[generated.name] = generated.scenario
    for group_id, group in generated.checks.items():
        if group_id in result.checks:
            msg = (
                f"generator rule family {family!r} produced check group "
                f"{group_id!r}, which another enabled rule already produced "
                "for this feature — rules must be feature-shape-disjoint; this "
                "is a bug in the rule set, not a per-feature issue"
            )
            raise GeneratorInternalError(msg)
        result.checks[group_id] = group
