"""Load and validate test/features/generation.yaml.

The only per-feature things this config touches are rollout allowlist/denylist
membership (migration scaffolding, retired once every feature is covered) —
everything else here is a global, cross-feature setting. Feature-specific
test-generation facts (functional smoke-test command, version pins) live in
each feature's own metadata.yaml instead; see proman.test.gen.facts.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import TYPE_CHECKING

import yaml
from jsonschema.exceptions import ValidationError

from proman.config import load as load_config
from proman.schema_bundle import get_generation_validator
from proman.test.gen.errors import GenerationConfigError

if TYPE_CHECKING:
    from pathlib import Path


@dataclass(frozen=True)
class FamilyConfig:
    """One `families.<name>` entry."""

    enabled: bool
    modes: tuple[str, ...] | None = None
    select: str | None = None
    options: tuple[str, ...] = ()
    reason: str = ""


@dataclass(frozen=True)
class GenerationConfig:
    """Validated, parsed test/features/generation.yaml."""

    enabled: bool
    rollout_mode: str
    allowlist: frozenset[str]
    denylist: frozenset[str]
    primary_env: str
    nonroot_env: str
    npm_env: str = ""
    cargo_env: str = ""
    macos_env: str = ""
    macos_brew_env: str = ""
    env_pool: tuple[str, ...] = ()
    families: dict[str, FamilyConfig] = field(default_factory=dict)
    require_anchored_regex: bool = True
    version_cross_validate: bool = True
    functional_smoke_required: bool = True

    def family_enabled(self, family: str) -> bool:
        """Whether `family` should generate anything at all, globally."""
        fam = self.families.get(family)
        return self.enabled and fam is not None and fam.enabled

    def applies_to(self, feature_id: str) -> bool:
        """Whether generation should run at all for this feature (rollout gating).

        Family-level enablement (`family_enabled`) is checked separately per rule.
        """
        if not self.enabled or feature_id in self.denylist:
            return False
        if self.rollout_mode == "allowlist":
            return feature_id in self.allowlist
        return True  # "denylist" or "all": denylist membership already excluded above


_DISABLED = GenerationConfig(
    enabled=False,
    rollout_mode="denylist",
    allowlist=frozenset(),
    denylist=frozenset(),
    primary_env="",
    nonroot_env="",
)


def _read_yaml(path: Path) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8")) or {}


def load() -> GenerationConfig:
    """Load, schema-validate, and parse test/features/generation.yaml.

    Returns a fully-disabled config when this repo checkout hasn't set up the
    generation pipeline (no `path.test_generation_config` configured, or no
    `generation.yaml` file present yet) — generation is strictly additive
    infrastructure, so its absence must never break anything that doesn't use
    it (e.g. isolated `FeatureTestLoader` unit tests with a minimal fake repo).
    """
    try:
        path = load_config().absolute_path("path.test_generation_config")
    except TypeError:
        return _DISABLED
    if not path.is_file():
        return _DISABLED
    data = _read_yaml(path)
    try:
        get_generation_validator().validate(data)
    except ValidationError as exc:
        msg = f"{path}: generation config schema validation failed: {exc.message}"
        raise GenerationConfigError(msg) from exc

    rollout = data["rollout"]
    families = {
        name: FamilyConfig(
            enabled=fam["enabled"],
            modes=tuple(fam["modes"]) if "modes" in fam else None,
            select=fam.get("select"),
            options=tuple(fam.get("options", ())),
            reason=fam.get("reason", ""),
        )
        for name, fam in data["families"].items()
    }
    assertions = data.get("assertions", {})
    return GenerationConfig(
        enabled=data["enabled"],
        rollout_mode=rollout["mode"],
        allowlist=frozenset(rollout.get("allowlist", ())),
        denylist=frozenset(rollout.get("denylist", ())),
        primary_env=data["environments"]["primary"],
        nonroot_env=data["environments"]["nonroot_env"],
        npm_env=data["environments"]["npm_env"],
        cargo_env=data["environments"]["cargo_env"],
        macos_env=data["environments"].get("macos_env", ""),
        macos_brew_env=data["environments"].get("macos_brew_env", ""),
        env_pool=tuple(data["environments"]["pool"]),
        families=families,
        require_anchored_regex=assertions.get("require_anchored_regex", True),
        version_cross_validate=assertions.get("version_cross_validate", True),
        functional_smoke_required=assertions.get("functional_smoke_required", True),
    )
