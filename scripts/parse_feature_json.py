#!/usr/bin/env python3
"""Parse devcontainer-feature.json files and render Markdown option blocks.

Exported function:
    render_json_block(data) → str    — Markdown string for injection between
                                       devcontainer-feature.json markers.
"""

from __future__ import annotations


# ── Internal helpers ──────────────────────────────────────────────────────────


def _format_feature_description(raw: str) -> str:
    """Format a JSON description string as Markdown.

    The JSON value may contain literal newlines.  Double-newlines become
    paragraph breaks; single newlines are joined within a paragraph.
    """
    paragraphs: list[str] = []
    for block in raw.strip().split("\n\n"):
        paragraph = " ".join(
            line.strip() for line in block.splitlines() if line.strip()
        )
        if paragraph:
            paragraphs.append(paragraph)
    return "\n\n".join(paragraphs)


def _option_type_str(opt: dict) -> str:
    t = opt.get("type", "string")
    if t == "string":
        if "enum" in opt:
            return "string (enum)"
        if "proposals" in opt:
            return "string (proposals)"
    return t


def _option_default_str(opt: dict) -> str:
    default = opt.get("default")
    if default is None:
        return ""
    if isinstance(default, bool):
        return f"`{'true' if default else 'false'}`"
    if isinstance(default, str):
        return f'`"{default}"`'
    return f"`{default}`"


def _option_desc_full(opt: dict) -> str:
    """Full option description collapsed to a single line for a table cell.

    Joins all non-empty lines with a space, so multi-line JSON descriptions
    are not truncated.
    """
    desc = opt.get("description", "")
    return " ".join(line.strip() for line in desc.splitlines() if line.strip())


# ── Public API ────────────────────────────────────────────────────────────────


def render_json_block(data: dict) -> str:
    """Render feature description + options table from a devcontainer-feature.json dict.

    Args:
        data  Parsed JSON dict (top-level object from devcontainer-feature.json).

    Returns a Markdown string suitable for injection between
    <!-- START devcontainer-feature.json MARKER --> markers.
    """
    parts: list[str] = []

    desc_raw = data.get("description", "")
    if desc_raw:
        parts.append(_format_feature_description(desc_raw))

    options = data.get("options", {})
    if options:
        rows = [
            "## Options",
            "",
            "| Option | Type | Default | Description |",
            "|---|---|---|---|",
        ]
        for opt_name, opt in options.items():
            type_str = _option_type_str(opt)
            default_str = _option_default_str(opt)
            desc_str = _option_desc_full(opt)
            rows.append(
                f"| `{opt_name}` | {type_str} | {default_str} | {desc_str} |"
            )
        parts.append("\n".join(rows))

    return "\n\n".join(parts) + "\n"
