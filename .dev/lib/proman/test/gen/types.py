"""Shared data contracts for the test-generation pipeline.

Every rule is a pure function of `(FeatureFacts, GenerationConfig)` producing
`list[GeneratedScenario]` — see rules_base.Rule. Keeping the contract here
(rather than importing rule modules from one another) is what lets rules be
added/removed independently: nothing but this module and rules_base is
shared code a new rule file needs to know about.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal, TypedDict


class CheckItem(TypedDict, total=False):
    """One checks.yaml check entry — see test/features/checks.schema.json."""

    title: str
    cmd: str | list[str]
    kind: Literal["check", "fail", "multiple", "install_failure"]
    min: int
    pattern: str
    debug: str
    on_fail: str


class CheckGroup(TypedDict, total=False):
    """One checks.yaml top-level group — see test/features/checks.schema.json."""

    description: str
    checks: list[CheckItem]
    pre: str
    post: str
    on_failure: str


@dataclass(frozen=True)
class GeneratedScenario:
    """One generated scenario plus the check group(s) it references.

    `checks` maps check-group id -> CheckGroup. Most rules emit exactly one
    group, named the same as the scenario; some (e.g. method_matrix's
    package_default/source_default/...) instead point `scenario["tests"]` at
    an existing group (typically `default`) and leave `checks` empty.
    """

    name: str
    scenario: dict
    checks: dict[str, CheckGroup] = field(default_factory=dict)
