"""Generate feature documentation from metadata.yaml and note files."""

import json
from typing import Any

import mdit

from proman.const import LIFECYCLE_COMMAND_KEYS
from proman.sync.pipeline import resolve_lifecycle_command

#: Required level-1 heading (page title) for the ``notes`` child page.
NOTES_HEADING = "# Notes"
#: Required level-1 heading (page title) for the ``dev-notes`` child page.
DEV_NOTES_HEADING = "# Developer Notes"


def generate(
    metadata: dict[str, Any],
    child_pages: list[str] | None = None,
) -> str:
    """Generate a feature's ``index.md`` page.

    Parameters
    ----------
    metadata
        Feature metadata dict (as produced by the metadata loader).
    child_pages
        Docname stems of sibling pages (e.g. ``["notes", "dev-notes"]``) that
        exist under the feature's docs directory. When non-empty, a hidden
        ``{toctree}`` linking them is appended so they render as children of
        this page in the site navigation.

    Returns
    -------
    str
        The Markdown content of the feature ``index.md`` page. Note that,
        unlike earlier revisions, feature notes are **not** appended here; they
        are emitted as separate sibling pages linked via the child toctree.
    """
    name = metadata["name"]
    description = metadata["description"].strip()
    long_description = metadata.get("_long_description", "").strip()
    options = _generate_options_sections(metadata)
    example = _generate_usage_tabset(metadata)
    keywords = _generate_keyword_badges(metadata)
    parts = [
        f"# {name}",
        description,
        keywords,
        long_description,
        _generate_spec_summary(metadata),
        "## Example Usage",
        example,
        "## Options",
        options,
    ]

    lifecycle_notes = _generate_lifecycle_notes(metadata)
    if lifecycle_notes:
        parts.extend(["## Lifecycle Commands", lifecycle_notes])

    installs_after = _generate_installs_after(metadata)
    if installs_after:
        parts.extend(["## Installation Order", installs_after])

    extensions_section = _generate_extensions_section(metadata)
    if extensions_section:
        parts.extend(["## VS Code Extensions", extensions_section])

    doc = "\n\n".join(parts).strip() + "\n"

    toctree = _generate_child_toctree(child_pages or [])
    if toctree:
        doc = f"{doc}\n{toctree}"
    return doc


def render_child_page(content: str, heading: str) -> str:
    """Return a note page guaranteed to start with the required H1 ``heading``.

    Child pages (``notes.md`` / ``dev-notes.md``) are standalone documents and
    therefore need a level-1 heading to supply the page title. If the source
    content does not already start with the required heading, it is prepended
    (a defensive measure until per-feature note content is migrated to include
    the heading itself).

    Parameters
    ----------
    content
        Raw source content of the feature's note file.
    heading
        Required level-1 heading, e.g. :data:`NOTES_HEADING`.

    Returns
    -------
    str
        Page content beginning with ``heading`` and ending in a single newline.
    """
    body = content.lstrip("\n")
    first_line = body.split("\n", 1)[0].strip() if body else ""
    if first_line == heading:
        page = body
    elif body:
        page = f"{heading}\n\n{body}"
    else:
        page = heading
    return page.rstrip("\n") + "\n"


def _generate_child_toctree(child_pages: list[str]) -> str:
    """Render a hidden MyST ``{toctree}`` linking the given child docnames."""
    if not child_pages:
        return ""
    lines = ["```{toctree}", ":hidden:", "", *child_pages, "```"]
    return "\n".join(lines) + "\n"


def _generate_keyword_badges(metadata: dict[str, Any]) -> str:
    keywords = metadata.get("keywords", [])
    if not keywords:
        return ""
    badges = " ".join(f"{{bdg-info}}`{kw}`" for kw in keywords)
    return f'<div style="text-align:center">\n\n{badges}\n\n</div>\n\n'


def _generate_spec_summary(metadata: dict[str, Any]) -> str:
    feat_id = metadata["id"]
    feat_ver = metadata["version"]
    ghcr = metadata["_oci_ref"]
    summary = (
        f":**Latest Version**: `{feat_ver}`\n"
        f":**Feature ID**: `{feat_id}`\n"
        f":**OCI Reference**: `{ghcr}`"
    )
    sys_req = metadata.get("_system_requirements", {})
    if sys_req:
        summary += _render_system_requirements(sys_req)
    return summary


def _generate_usage_tabset(metadata: dict[str, Any]) -> str:
    feat_id = metadata.get("id", "")
    major = metadata.get("version", "1").split(".")[0]
    feature_ref = f"{metadata['_oci_ref']}:{major}"

    options = metadata.get("options", {})
    defaults = {k: v.get("default") for k, v in options.items()}

    dc_json_lines = json.dumps(
        {"features": {feature_ref: defaults}},
        indent=2,
    ).splitlines()
    dc_json = "\n".join(
        [
            *dc_json_lines[:-2],
            "    // other features...",
            dc_json_lines[-2],
            "  // other properties...",
            dc_json_lines[-1],
        ],
    )

    items = list(defaults.items())
    cli_lines = [f"{feat_id} \\"]
    for i, (k, v) in enumerate(items):
        flag = f"--{k.replace('_', '-')}"
        val = str(v).lower() if isinstance(v, bool) else (v if v != "" else '""')
        suffix = " \\" if i < len(items) - 1 else ""
        cli_lines.append(f"  {flag} {val}{suffix}")
    cli_code = "\n".join(cli_lines)

    ts = mdit.element.tab_set()
    ts.append(
        mdit.element.code_block(
            dc_json,
            language="json",
            caption="{fas}`file-code` devcontainer.json",
        ),
        title="Dev Container",
    )
    ts.append(
        mdit.element.code_block(
            cli_code,
            language="bash",
            caption="{fas}`terminal` Terminal",
        ),
        title="CLI",
    )
    tabset_str = ts.source(target="sphinx")
    description = (
        "For demonstration purposes, all available options are explicitly"
        " included with their default values. "
        "In real usage, you only need to specify the options you want to override. "
        "For more information on installing features, see the"
        " [Installation Guide](/user-guide/installation.md)."
    )
    return f"{description}\n\n{tabset_str}"


def _generate_options_sections(data: dict) -> str:
    """Render the feature options section from the metadata dict.

    Parameters
    ----------
    data : dict
        Feature metadata dict (from devcontainer-feature.json or
        metadata.yaml — same structure).

    Returns
    -------
    str
        Markdown string for the options section, or empty string if no options.
    """
    options = data.get("options", {})
    if not options:
        return ""
    rows = []
    for opt_name, opt in options.items():
        opt_type = opt["type"]

        default_str = "\\n".join(_option_default_str(opt).splitlines())
        rows.extend(
            [
                f"### `{opt_name}`",
                _option_desc_full(opt),
                f"- Type: `{opt_type}`",
                f"- Default: {default_str}",
            ],
        )

        if "_applies_when" in opt:
            conditions: list[dict] = opt["_applies_when"]
            conditions_str = [_render_option_condition(cond) for cond in conditions]
            if len(conditions) == 1:
                rows.append(f"- Applies when: {conditions_str[0]}")
            else:
                rows.append("- Applies when:")
                rows.extend(f"  - {cond_str}" for cond_str in conditions_str)

        if "enum" in opt:
            rows.append("- Allowed values:")
            rows.extend(
                f'  - `"{e["value"]}"`: {e["description"].strip()}' for e in opt["enum"]
            )
        elif "proposals" in opt:
            rows.append("- Examples:")
            rows.extend(
                f'  - `"{p["value"]}"`: {p["description"].strip()}'
                for p in opt["proposals"]
            )

    return "\n".join(rows) + "\n"


def _generate_extensions_section(metadata: dict) -> str:
    extensions = (
        metadata.get("customizations", {}).get("vscode", {}).get("extensions", [])
    )
    if not extensions:
        return ""
    out = ["The following VS Code extensions are automatically installed:"]
    for ext in extensions:
        url = f"https://marketplace.visualstudio.com/items?itemName={ext}"
        out.append(f"- [{ext}]({url})")

    opt_out_text = (
        "You can [opt out](https://github.com/microsoft/vscode-docs/blob/main"
        "/remote-release-notes/v1_85.md#opt-out-of-extensions) "
        "of any of these extensions by listing them with a leading `-` in the"
        " `customizations.vscode.extensions` array "
        "of your `devcontainer.json` file. For example, to opt out of all"
        " extensions, your `devcontainer.json` should include the following:"
    )
    opt_out_dict = {
        "customizations": {"vscode": {"extensions": [f"-{ext}" for ext in extensions]}},
    }
    opt_out_json = json.dumps(opt_out_dict, indent=2)
    opt_out_code = mdit.element.code_block(
        opt_out_json,
        language="json",
        caption="{fas}`file-code` devcontainer.json",
    )
    opt_out_admo = mdit.element.admonition(
        title="Opt Out",
        body=mdit.block_container([opt_out_text, opt_out_code]),
        type="hint",
        dropdown=True,
    )
    opt_out_str = str(opt_out_admo.source(target="sphinx"))
    out.append(opt_out_str)
    return "\n\n".join(out)


def _generate_lifecycle_notes(metadata: dict) -> str:
    tab_set = mdit.element.tab_set()
    for key in LIFECYCLE_COMMAND_KEYS:
        if key not in metadata:
            continue
        unordered_list = mdit.element.unordered_list()
        for entry_id, entry in metadata[key].items():
            command_str = resolve_lifecycle_command(entry_id, entry, key, metadata)
            command_code = mdit.element.code_block(command_str, language="sh")
            command_desc = entry["description"]
            container = mdit.block_container([command_desc, command_code])
            unordered_list.append(container)
        tab_set.append(unordered_list, title=key)
    return str(tab_set.source(target="sphinx")) if tab_set.content else ""


def _generate_installs_after(metadata: dict) -> str:
    installs_after = metadata.get("installsAfter", [])
    if not installs_after:
        return ""
    out = ["This feature is best installed after the following features:"]
    out.extend(f"- `{feat}`" for feat in installs_after)
    return "\n".join(out)


# ── helpers ──────────────────────────────────────────────────────────


def _render_system_requirements(sys_req: dict) -> str:
    lines = []
    platforms: list[dict] | None = sys_req.get("platforms")
    if platforms:
        badges = " ".join(
            f"{{bdg-success}}`{_render_match_spec_str(spec)}`" for spec in platforms
        )
        lines.append(f"\n:**Supported Platforms**: {badges}")
    root = sys_req.get("root", False)
    if root is True:
        lines.append("\n:**Requires Root**: Yes")
    elif isinstance(root, list) and root:
        badges = " ".join(
            f"{{bdg-warning}}`{_render_match_spec_str(spec)}`" for spec in root
        )
        lines.append(f"\n:**Requires Root On**: {badges}")
    return "".join(lines)


def _render_match_spec_str(spec: dict) -> str:
    return " ".join(f"{k}={v}" for k, v in spec.items())


def _render_option_condition(condition: dict) -> str:
    """Render an option applicability condition to a human-readable string."""
    parts = []
    for key, values in condition.items():
        if isinstance(values, str):
            parts.append(f'`{key} = "{values}"`')
        elif isinstance(values, bool):
            parts.append(f"`{key} = {str(values).lower()}`")
        elif isinstance(values, list):
            values_str = ", ".join(f'"{v}"' for v in values)
            parts.append(f"`{key} ∈ {{{values_str}}}`")
        else:
            msg = f"Unsupported condition value type: {type(values)} for key {key}"
            raise TypeError(msg)
    return " and ".join(parts)


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
