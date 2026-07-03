"""Single merge point for a feature's hand-written + generated test definitions.

Historically, `FeatureTestLoader`, `gen_devcontainer.generate()`, and
`cicd/detect.py`'s CI-matrix builders each independently read
`test/features/<id>/scenarios.yaml` off disk. Every one of those now delegates
to `load_effective()` instead, so "what `just test-feats` runs" and "what CI's
matrix contains" can never desync the way three independent readers could.

Schema/cross-file validation of the *merged* result still happens entirely in
`FeatureTestLoader` (unchanged) — this module's only job is producing that
merged (defaults, scenarios, checks) triple, plus resolving suppress/augment
directives from the feature's own `generation:` block.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Literal

import yaml

from proman.config import load as load_config
from proman.metadata import MetadataLoader
from proman.test import gen
from proman.test.environments import load as load_environments
from proman.test.gen import config as gen_config

if TYPE_CHECKING:
    from pathlib import Path

    from proman.config import Config

Provenance = Literal["generated", "handwritten"]


class FeatureTestError(ValueError):
    """Raised when checks.yaml/scenarios.yaml/generation fail to load or merge.

    The authoritative error type for the whole feature-test loading stack —
    re-exported unchanged from `proman.test.loader` for existing importers.
    """


@dataclass(frozen=True)
class EffectiveTests:
    """Merged (hand-written + generated) test definitions for one feature."""

    feature_id: str
    defaults: dict
    scenarios: dict
    checks: dict
    provenance: dict[str, Provenance] = field(default_factory=dict)


def _read_yaml(path: Path) -> dict:
    if not path.is_file():
        return {}
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return data if isinstance(data, dict) else {}


def _read_handwritten(
    feature_dir: Path,
    checks_name: str,
    scenarios_name: str,
) -> tuple[dict, dict, dict, dict]:
    """Read one feature's hand-written files, if present.

    Returns (defaults, generation_block, scenarios, checks) — none schema-
    validated here; that still happens in FeatureTestLoader, on the merged
    result.
    """
    scenarios_doc = _read_yaml(feature_dir / scenarios_name)
    checks = _read_yaml(feature_dir / checks_name)

    defaults = scenarios_doc.get("defaults") or {}
    generation = scenarios_doc.get("generation") or {}
    scenarios = {
        key: value
        for key, value in scenarios_doc.items()
        if key not in ("defaults", "generation")
    }
    return defaults, generation, scenarios, checks


def _generated_content(feature_id: str, config: Config) -> tuple[dict, dict]:
    """Run the generation pipeline for one feature.

    Returns (scenarios, checks), empty when generation doesn't apply to this
    feature or it has no metadata.yaml.
    """
    cfg = gen_config.load()
    if not cfg.applies_to(feature_id):
        return {}, {}
    try:
        metadata = MetadataLoader().load(feature_id)[feature_id]
    except (KeyError, FileNotFoundError):
        return {}, {}
    envs = load_environments(config.absolute_path("path.test_environments"))
    result = gen.generate_feature_tests(feature_id, metadata, cfg, envs)
    return result.scenarios, result.checks


def load_effective(feature_id: str) -> EffectiveTests:
    """Load, generate, and merge one feature's effective scenarios/checks.

    Collision policy: a generated scenario/check-group name that also exists
    hand-written is a hard error unless the feature's `generation.suppress`
    explicitly drops the generated one — never a silent hand-written-wins.
    """
    config = load_config()
    feature_dir = config.absolute_path("path.test_features") / feature_id
    checks_name = str(config["filename.feature_checks"])
    scenarios_name = str(config["filename.feature_scenarios"])

    defaults, generation, handwritten_scenarios, handwritten_checks = _read_handwritten(
        feature_dir, checks_name, scenarios_name
    )
    generated_scenarios, generated_checks = _generated_content(feature_id, config)

    suppress = generation.get("suppress", {})
    suppressed_scenarios = set(suppress.get("scenarios", ()))
    suppressed_checks = set(suppress.get("checks", ()))
    augment_tests = generation.get("augment_tests", {})

    scenarios = dict(handwritten_scenarios)
    checks = dict(handwritten_checks)
    provenance: dict[str, Provenance] = dict.fromkeys(
        handwritten_scenarios,
        "handwritten",
    )

    for name, body in generated_scenarios.items():
        if name in suppressed_scenarios:
            continue
        if name in handwritten_scenarios:
            msg = (
                f"{feature_id}: generated scenario '{name}' collides with a "
                f"hand-written scenario of the same name in {scenarios_name}. "
                "Rename the hand-written scenario, or add "
                f"'{name}' to generation.suppress.scenarios in {scenarios_name} "
                "to intentionally keep only the hand-written one."
            )
            raise FeatureTestError(msg)
        effective_body = body
        if name in augment_tests:
            effective_body = {
                **body,
                "tests": [*body.get("tests", []), *augment_tests[name]],
            }
        scenarios[name] = effective_body
        provenance[name] = "generated"

    for group_id, group in generated_checks.items():
        if group_id in suppressed_checks:
            continue
        if group_id in handwritten_checks:
            msg = (
                f"{feature_id}: generated check group '{group_id}' collides "
                f"with a hand-written group of the same name in {checks_name}. "
                "Rename the hand-written group, or add "
                f"'{group_id}' to generation.suppress.checks in {scenarios_name} "
                "to intentionally keep only the hand-written one."
            )
            raise FeatureTestError(msg)
        checks[group_id] = group

    return EffectiveTests(
        feature_id=feature_id,
        defaults=defaults,
        scenarios=scenarios,
        checks=checks,
        provenance=provenance,
    )
