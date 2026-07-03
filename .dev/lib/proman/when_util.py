r"""Utilities for serializing `when` condition blocks.

Shared by the install-script generator (install_script.py) and the
metadata template filler (metadata.py / metadata.shared.yaml).

Serialization emits **YAML** blobs consumed by ``ctx__match_when`` / ``ctx__match_spec``
in ``lib/ctx.bash`` (evaluated via ``ctx-match.jq``).

When keys are validated by ``features/install-os-pkg/manifest.schema.json``
(``WhenSpec``/``WhenConditionObject.propertyNames``),
referenced from ``features/metadata.schema.json``;
this module only serializes already-valid metadata.
"""

from __future__ import annotations

import re
from itertools import zip_longest

import yaml

_SEMVER_RE = re.compile(r"^[0-9]+(\.[0-9]+)*(-[^+]*)?(\+.*)?$")


def _dump_when_yaml(data: object, *, flow: bool) -> str:
    """Dump a when dict or OR-list to YAML."""
    if not data:
        return ""
    if isinstance(data, dict):
        payload: object = dict(data)
    elif isinstance(data, list):
        payload = [dict(g) for g in data if g]
        if not payload:
            return ""
    else:
        return ""

    dumped = yaml.dump(
        payload,
        default_flow_style=flow,
        sort_keys=False,
        width=10_000 if flow else None,
        allow_unicode=True,
    )
    return dumped.strip() if flow else dumped.rstrip("\n")


def serialize_when(when: object) -> str:
    """Serialize a ``when`` block to multi-line YAML."""
    return _dump_when_yaml(when, flow=False)


def serialize_when_flow(when: dict | list) -> str:
    """Serialize a ``when`` block to single-line YAML."""
    return _dump_when_yaml(when, flow=True)


def serialize_sysreq_args(specs: list[dict]) -> str:
    """Build sys_req__require_platform argument list (one YAML blob per OR group)."""
    parts: list[str] = []
    for spec in specs:
        blob = serialize_when(spec)
        if not blob:
            continue
        escaped = blob.replace("\\", "\\\\").replace("'", "'\\''")
        parts.append(f"$'{escaped}'")
    return " ".join(parts)


def _serialize_value_when_entries(
    entries: list | None,
    *,
    value_key: str,
) -> str:
    """Serialize ``[{value_key, when}]`` metadata entries to option default lines."""
    if not entries:
        return ""
    lines: list[str] = []
    for entry in entries:
        if isinstance(entry, str):
            lines.append(entry)
            continue
        if isinstance(entry, dict):
            value = entry.get(value_key, "")
            when = entry.get("when")
            if when:
                yaml_when = serialize_when_flow(when)
                lines.append(f"{value}\t{yaml_when}" if yaml_when else value)
            else:
                lines.append(str(value))
            continue
        lines.append(str(entry))
    return "\n".join(lines)


def match(when: dict | list | None, attrs: dict[str, object]) -> bool:
    """Evaluate a WhenSpec (AND-object, or OR-list of AND-objects) against `attrs`.

    Used at test-generation time (Python side) to decide which `test/environments.yaml`
    entries satisfy a `_options.method.*.when`/`_dependencies.*.when`/
    `_system_requirements.platforms` clause, given that environment's flattened
    `attributes:`. This is a static, generation-time counterpart to the runtime
    evaluator (`ctx__match_when`/`ctx-match.jq` in `lib/ctx.bash`) that this module's
    other functions serialize `when:` blocks *for* — it never runs inside a container.

    A condition key missing from `attrs` never matches (unknown != satisfied).
    Bare scalar/list values are an `eq` shorthand (OR over the list). Attribute
    values that are themselves lists (e.g. an environment supporting multiple
    architectures) are compared by set overlap, not exact equality.
    """
    if not when:
        return True
    groups = when if isinstance(when, list) else [when]
    return any(_match_group(group, attrs) for group in groups)


def _match_group(group: dict, attrs: dict[str, object]) -> bool:
    return all(_match_condition(spec, attrs.get(key)) for key, spec in group.items())


def _match_condition(spec: object, actual: object) -> bool:
    if actual is None:
        return False
    if isinstance(spec, dict):
        if "eq" in spec:
            return _values_overlap(spec["eq"], actual)
        if "ne" in spec:
            return not _values_overlap(spec["ne"], actual)
        for op in ("lt", "lte", "gt", "gte"):
            if op in spec:
                return _semver_op(op, actual, spec[op])
        return False
    return _values_overlap(spec, actual)


def _values_overlap(spec_value: object, actual: object) -> bool:
    spec_set = {spec_value} if isinstance(spec_value, str) else set(spec_value)
    actual_set = {actual} if isinstance(actual, str) else set(actual)
    return bool(spec_set & actual_set)


def _semver_op(op: str, actual: object, spec_value: str) -> bool:
    if isinstance(actual, list):
        return any(_semver_op(op, item, spec_value) for item in actual)
    try:
        cmp = semver_cmp(actual, spec_value)
    except ValueError:
        return False
    if op == "lt":
        return cmp < 0
    if op == "lte":
        return cmp <= 0
    if op == "gt":
        return cmp > 0
    return cmp >= 0  # gte


def semver_cmp(a: str, b: str) -> int:
    """Compare two version strings per semver.org core+prerelease rules.

    Mirrors `lib/ver.bash`'s `ver__cmp` exactly (leading `v`/`V` stripped, dot-separated
    numeric core compared component-wise with missing trailing components treated as
    0, then pre-release: no pre-release outranks any pre-release, else case-insensitive
    string comparison) so the Python (generation-time) and bash (install-time) version
    orderings never diverge. Raises ValueError if either operand doesn't match the
    semver core+prerelease+build grammar.
    """
    a = a[1:] if a[:1] in ("v", "V") else a
    b = b[1:] if b[:1] in ("v", "V") else b
    if not _SEMVER_RE.match(a) or not _SEMVER_RE.match(b):
        msg = f"unparseable version(s) for semver comparison: {a!r}, {b!r}"
        raise ValueError(msg)
    core_a, pre_a = _split_semver_core_pre(a)
    core_b, pre_b = _split_semver_core_pre(b)
    parts_a = [int(p) for p in core_a.split(".")]
    parts_b = [int(p) for p in core_b.split(".")]
    for pa, pb in zip_longest(parts_a, parts_b, fillvalue=0):
        if pa != pb:
            return 1 if pa > pb else -1
    if not pre_a and not pre_b:
        return 0
    if not pre_a:
        return 1
    if not pre_b:
        return -1
    if pre_a.lower() == pre_b.lower():
        return 0
    return -1 if pre_a.lower() < pre_b.lower() else 1


def _split_semver_core_pre(v: str) -> tuple[str, str]:
    core = v.split("-", 1)[0].split("+", 1)[0]
    pre = v.split("-", 1)[1].split("+", 1)[0] if "-" in v else ""
    return core, pre


def serialize_path_entries(entries: list | None) -> str:
    """Serialize a list of ``{path, when?}`` entries to tab-delimited defaults."""
    return _serialize_value_when_entries(entries, value_key="path")


def serialize_value_entries(entries: list | None) -> str:
    """Serialize a list of ``{value, when?}`` entries to tab-delimited defaults."""
    return _serialize_value_when_entries(entries, value_key="value")
