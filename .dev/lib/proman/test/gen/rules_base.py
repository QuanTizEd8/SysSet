"""The `Rule` protocol every scenario-family generator implements."""

from __future__ import annotations

from typing import TYPE_CHECKING, Literal, Protocol

if TYPE_CHECKING:
    from proman.test.gen.config import GenerationConfig
    from proman.test.gen.facts import FeatureFacts
    from proman.test.gen.types import GeneratedScenario


class Rule(Protocol):
    """One scenario-family generator: a pure function of (facts, cfg).

    Rules never branch on feature id — only on metadata shape (via `facts`) and
    global settings (via `cfg`). Per-feature exceptions belong in that feature's
    hand-written `scenarios.yaml` (`generation.suppress`/`generation.augment_tests`),
    never inside a rule.
    """

    family: str
    """Matches a key under generation.yaml's `families:` block."""

    check_generation: Literal["full", "scaffold_only"]
    """`full`: every check is generator-produced. `scaffold_only`: the rule emits
    scenario bodies but points `tests:` at check-group ids that must be
    hand-authored in the feature's checks.yaml (e.g. configure_users)."""

    def applies(self, facts: FeatureFacts, cfg: GenerationConfig) -> bool:
        """Whether this feature's metadata shape triggers this family at all."""
        ...

    def generate(
        self,
        facts: FeatureFacts,
        cfg: GenerationConfig,
        envs: dict,
    ) -> list[GeneratedScenario]:
        """Produce this family's scenarios for one feature.

        Includes check groups too, for `check_generation="full"` rules. Only
        called when `applies()` is True and the family is enabled in `cfg`.
        `envs` is the loaded `test/environments.yaml` data, passed explicitly
        (rather than read as global state) so rules stay pure functions of
        their arguments — used via `proman.test.gen.envselect` for any
        environment selection.
        """
        ...
