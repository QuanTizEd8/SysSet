"""Self-registering rule plugin registry.

Rules never need to be listed anywhere else: a rule module decorates its one
class with `@register`, and `proman.test.gen.rules` (imported once by
`engine.generate_feature_tests`) imports every submodule for the registration
side effect. Adding a scenario family is adding one new file under `rules/`;
removing one is deleting its file — nothing else references a rule by name.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, TypeVar

if TYPE_CHECKING:
    from proman.test.gen.rules_base import Rule

_RuleClass = TypeVar("_RuleClass", bound="type[Rule]")

_RULES: dict[str, Rule] = {}


def register(rule_cls: _RuleClass) -> _RuleClass:
    """Class decorator: instantiate `rule_cls` and register it under its `family`."""
    instance: Rule = rule_cls()
    if instance.family in _RULES:
        msg = f"duplicate rule family registered: {instance.family!r}"
        raise ValueError(msg)
    _RULES[instance.family] = instance
    return rule_cls


def all_rules() -> list[Rule]:
    """Every registered rule instance, in registration order."""
    return list(_RULES.values())


def clear() -> None:
    """Reset the registry. Test-only — production code never calls this."""
    _RULES.clear()
