"""Utilities for serializing ospkg manifest blocks from feature metadata."""

from __future__ import annotations

import copy
import re

import pyserials

# Package-manager families whose per-group sub-blocks (``{apt: {packages: …}}``)
# hold their own package lists. Mirrors ``ospkg-manifest.jq``'s structure so the
# command-guard walker reaches every package entry.
_PM_FAMILIES = frozenset({"apt", "apk", "brew", "dnf", "yum", "pacman", "zypper"})


def inject_dep_commands(
    content: dict | list | None,
    command_map: dict[str, str],
    *,
    guard: bool = True,
) -> dict | list | None:
    """Return *content* with ``command:`` guards injected from *command_map*.

    Walks the manifest structure (the same shape ``ospkg-manifest.jq`` consumes:
    top-level and PM-scoped ``packages`` arrays plus nested ``when`` groups) and,
    for every package entry, fills in ``command`` when **all** hold:

    * the entry's logical name (``name:`` field, or a bare string) is a key in
      *command_map*,
    * the entry has no explicit ``command`` (author override / opt-out wins),
    * the entry has no ``version`` (pinned deps must always install).

    A matching bare string is promoted to ``{name: …, command: …}``. The input
    is never mutated (a deep copy is returned). When *guard* is false (e.g. a
    feature opting out via ``_internal.no_command_guard``) or *command_map* is
    empty, *content* is returned unchanged.

    Group scoping (which lifecycle/group to guard) is decided by the caller in
    ``metadata.shared.yaml`` — this function guards whatever it is handed.
    """
    if not guard or not content or not command_map:
        return content
    content = copy.deepcopy(content)
    if isinstance(content, list):
        return [_inject_package_entry(entry, command_map) for entry in content]
    _walk_manifest_node(content, command_map)
    return content


def _walk_manifest_node(node: dict, command_map: dict[str, str]) -> None:
    """Inject commands into a group/manifest node's package lists in place."""
    if not isinstance(node, dict):
        return
    pkgs = node.get("packages")
    if isinstance(pkgs, list):
        node["packages"] = [_inject_package_entry(p, command_map) for p in pkgs]
    for pm in _PM_FAMILIES:
        sub = node.get(pm)
        if isinstance(sub, dict) and isinstance(sub.get("packages"), list):
            sub["packages"] = [
                _inject_package_entry(p, command_map) for p in sub["packages"]
            ]


def _inject_package_entry(
    pkg: object,
    command_map: dict[str, str],
) -> object:
    """Inject ``command`` into one package entry (string / object / group)."""
    if isinstance(pkg, str):
        cmd = command_map.get(pkg)
        return {"name": pkg, "command": cmd} if cmd else pkg
    if not isinstance(pkg, dict):
        return pkg
    # Nested group object (e.g. ``{when: …, packages: [...]}``): recurse.
    if isinstance(pkg.get("packages"), list) or any(
        isinstance(pkg.get(pm), dict) for pm in _PM_FAMILIES
    ):
        _walk_manifest_node(pkg, command_map)
        return pkg
    # Leaf package object.
    name = pkg.get("name")
    if not isinstance(name, str) or "command" in pkg or "version" in pkg:
        return pkg
    cmd = command_map.get(name)
    if cmd:
        pkg["command"] = cmd
    return pkg


def serialize_manifest(content: dict) -> str:
    r"""Serialize a manifest dict to YAML for option ``default`` values.

    Non-empty output always ends with a trailing newline so ``ospkg__run`` treats
    the value as inline YAML rather than a URI/path, and so ``install.bash``
    codegen emits ANSI-C-quoted defaults (preserving embedded single quotes).

    Output is unescaped canonical YAML. Devcontainer-specific escaping for
    ``devcontainer-feature.json`` defaults is applied separately by
    :func:`escape_devcontainer_default` during sync.
    """
    return (
        pyserials.write.to_yaml_string(
            content,
            end_of_file_newline=True,
        )
        if content
        else ""
    )


def escape_devcontainer_default(value: str) -> str:
    r"""Escape ``$`` and ``"`` for ``devcontainer-feature.json`` option defaults.

    The devcontainer CLI wraps every option value in double quotes when writing
    ``devcontainer-features.env`` and may also surface defaults in Dockerfile
    ``ENV`` instructions. Escaping prevents premature shell expansion and keeps
    multiline values syntactically valid.

    Already-escaped sequences (``\$``, ``\"``) are left unchanged so metadata
    defaults that intentionally use ``\${VAR}`` (e.g. ``runtime_path``) are not
    double-escaped.
    """
    if not value:
        return value
    return re.sub(r'(?<!\\)([$"])', r"\\\1", value)


def generate_dep_trigger_specs(metadata: dict) -> list[str]:
    """Return tab-separated trigger spec lines for option-bound manifest installs."""
    options: dict = metadata.get("options") or {}
    lines: list[str] = []

    for group in metadata.get("_dependencies", {}).get("run", {}):
        if not group.startswith("option-"):
            continue
        name = group.removeprefix("option-")
        opt = options.get(name)
        if not opt or opt.get("type") != "boolean":
            continue
        manifest_var = f"OSPKG_MANIFEST_OPTION_{name.upper().replace('-', '_')}"
        boolean_var = name.upper().replace("-", "_")
        lines.append(f"{name}\t{manifest_var}\t{boolean_var}")

    return lines
