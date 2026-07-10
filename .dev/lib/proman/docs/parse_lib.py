"""Parse structured @brief + body comments from lib shell modules.

Each public function in a ``lib/*.bash`` or ``lib/*.sh`` file is documented
with a comment block
immediately before the function definition:

    # @brief funcname [<args>...] — One-line description.
    #
    # Long description paragraph.  May span multiple lines and contain
    # multiple paragraphs separated by a blank comment line (#).
    #
    # Args:
    #   <arg>         Description.
    #   --flag <val>  Description.
    #
    # Stdout: one-line description of what is printed to stdout.
    funcname() {

Module-level docs use this convention (immediately after the shebang):

    # Short single-line summary.
    #
    # Longer description with light markdown.
    # Can span multiple lines.

Exported types:
    LibModule    — parsed module (name, summary, description, functions)
    LibFunction  — parsed function (name, signature, description, body)
    ParagraphBlock — a block of prose lines
    SectionBlock   — a labelled section (Args, Stdout, Returns, …)

Exported functions:
    parse_lib_module(path) → LibModule
    parse_lib_file(path)   → list[LibFunction]
"""

from __future__ import annotations

import re
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from pathlib import Path

# ── Data types ────────────────────────────────────────────────────────────────


class ParagraphBlock:
    """A block of plain prose lines between two blank comment lines."""

    def __init__(self, lines: list[str]) -> None:
        self.lines = lines

    def __repr__(self) -> str:  # pragma: no cover
        """Return debug representation."""
        return f"ParagraphBlock({self.lines!r})"


class SectionBlock:
    """A labelled section: a title line followed by indented items.

    Two forms are recognised:
    - Multi-item:  "Args:" on its own line + indented items on subsequent lines.
    - Inline:      "Stdout: text" or "Returns: text" as the sole line in a block.
    """

    def __init__(self, title: str, items: list[str]) -> None:
        self.title = title
        self.items = items

    def __repr__(self) -> str:  # pragma: no cover
        """Return debug representation."""
        return f"SectionBlock({self.title!r}, {self.items!r})"


class LibFunction:
    """One public function parsed from a lib shell module."""

    def __init__(
        self,
        name: str,
        signature: str,
        description: str,
        body: list,
    ) -> None:
        self.name = name
        self.signature = signature
        self.description = description
        self.body: list[ParagraphBlock | SectionBlock] = body

    def __repr__(self) -> str:  # pragma: no cover
        """Return debug representation."""
        return f"LibFunction({self.name!r})"


class LibModule:
    """A parsed lib shell module with filename, docs, and public functions."""

    def __init__(
        self,
        name: str,
        summary: str,
        description: str,
        functions: list[LibFunction],
    ) -> None:
        self.name = name
        self.summary = summary
        self.description = description
        self.functions = functions

    def __repr__(self) -> str:  # pragma: no cover
        """Return debug representation."""
        return f"LibModule({self.name!r})"


# ── Internal helpers ──────────────────────────────────────────────────────────

# "Args:" on its own line — multi-item section header.
_SECTION_HEADER_RE = re.compile(r"^([A-Z][A-Za-z]+):$")
# "Stdout: text" or "Returns: text" — single-line labelled section.
_INLINE_SECTION_RE = re.compile(r"^([A-Z][A-Za-z]+): (.+)$")


def _strip_comment_prefix(raw: str) -> str | None:
    """Strip the leading '# ' or '#' from one raw source line.

    Returns the content string (possibly empty), or None if the line is not
    a comment (i.e. it ends the comment block).
    """
    s = raw.strip()
    if s == "#":
        return ""
    if s.startswith("# "):
        return s[2:]
    if s.startswith("#"):
        # '#word' without a space — treat as comment content.
        return s[1:]
    # Non-comment line (blank line, code, etc.) — ends the block.
    return None


def _group_section_items(lines: list[str]) -> list[str]:
    """Group continuation lines with their preceding item.

    Lines with a 2-space indent base (third character is not a space) start a
    new item. Lines indented by 3 or more spaces are continuations of the
    preceding item and are joined to it with a newline.
    """
    items: list[str] = []
    current_parts: list[str] = []
    for ln in lines:
        if ln.startswith("   "):  # 3+ spaces → continuation of current item
            if current_parts:
                current_parts.append(ln.lstrip())
        else:  # 2-space base → new item
            if current_parts:
                items.append("\n".join(current_parts))
            current_parts = [ln.lstrip()]
    if current_parts:
        items.append("\n".join(current_parts))
    return items


def _classify_block(lines: list[str]) -> ParagraphBlock | SectionBlock:
    """Classify a non-empty list of stripped comment lines.

    Recognition rules (applied in order):
    1. Multi-item section: first line matches /^Word:$/ and all remaining
       lines are indented by at least two spaces.
    2. Inline section: exactly one line matching /^Word: text$/.
    3. Everything else: ParagraphBlock.
    """
    first = lines[0]

    # Rule 1: "Args:" header + indented items (with optional continuation lines).
    m = _SECTION_HEADER_RE.match(first)
    if m and len(lines) > 1 and all(ln[:2] == "  " for ln in lines[1:]):
        return SectionBlock(
            title=m.group(1),
            items=_group_section_items(lines[1:]),
        )

    # Rule 2: "Stdout: text" / "Returns: text" inline label.
    m = _INLINE_SECTION_RE.match(first)
    if m and len(lines) == 1:
        return SectionBlock(title=m.group(1), items=[m.group(2)])

    return ParagraphBlock(lines=lines)


def _parse_body(raw_lines: list[str]) -> list[ParagraphBlock | SectionBlock]:
    """Group raw stripped comment-body lines into blocks, splitting on blank lines.

    Produces ParagraphBlock and SectionBlock objects from stripped comment
    lines, using blank lines as delimiters.
    """
    # Drop leading blank lines.
    while raw_lines and not raw_lines[0]:
        raw_lines = raw_lines[1:]

    blocks: list = []
    current: list[str] = []

    for line in raw_lines:
        if line == "":
            if current:
                blocks.append(_classify_block(current))
                current = []
        else:
            current.append(line)

    if current:
        blocks.append(_classify_block(current))

    return blocks


def _parse_module_header(lines: list[str]) -> tuple[str, str]:
    """Extract (summary, long_description) from the initial comment block.

    Reads the consecutive comment lines immediately after the shebang or a
    leading ``# shellcheck`` directive. The first non-empty line is the
    summary; lines after the first blank comment line form the long description.

    Returns
    -------
    tuple[str, str]
        ``(summary, long_description)``, both empty strings if absent.
    """
    start = 1 if lines and lines[0].startswith("#!") else 0
    raw: list[str] = []
    for line in lines[start:]:
        content = _strip_comment_prefix(line)
        if content is None:
            break
        raw.append(content)

    # Drop leading blank lines.
    while raw and not raw[0]:
        raw.pop(0)

    # Library modules are sourced, not executed, so they begin with a
    # `# shellcheck shell=bash` directive instead of a shebang. Skip leading
    # shellcheck directive lines so the human summary — not the linter
    # directive — becomes the module summary.
    while raw and raw[0].startswith("shellcheck"):
        raw.pop(0)
    while raw and not raw[0]:
        raw.pop(0)

    if not raw:
        return "", ""

    summary = raw[0].strip()

    # Long description follows the first blank comment line.
    try:
        blank_idx = raw.index("", 1)
    except ValueError:
        return summary, ""

    desc_lines = raw[blank_idx + 1 :]
    while desc_lines and not desc_lines[-1]:
        desc_lines.pop()
    return summary, "\n".join(desc_lines).strip()


# ── Public API ────────────────────────────────────────────────────────────────


def parse_lib_module(path: Path) -> LibModule:
    """Parse a lib shell module; return module-level docs and @brief functions.

    Parameters
    ----------
    path : Path
        Absolute path to the ``lib/*.bash`` or ``lib/*.sh`` file.

    Returns
    -------
    LibModule
        Module filename, summary, long description, and list of functions.
    """
    lines = path.read_text(encoding="utf-8").splitlines()
    summary, description = _parse_module_header(lines)
    functions = parse_lib_file(path)
    return LibModule(
        name=path.name,
        summary=summary,
        description=description,
        functions=functions,
    )


def parse_lib_file(path: Path) -> list[LibFunction]:
    """Parse @brief annotations and full comment bodies from a lib shell module.

    Scans every line for '# @brief' to find annotated public functions.
    For each function, collects all comment lines between the @brief line and
    the function definition, then parses them into structured blocks.

    Parameters
    ----------
    path : Path
        Absolute path to the ``lib/*.bash`` or ``lib/*.sh`` file.

    Returns
    -------
    list[LibFunction]
        LibFunction objects in source order.
    """
    functions: list[LibFunction] = []
    lines = path.read_text(encoding="utf-8").splitlines()

    i = 0
    while i < len(lines):
        s = lines[i].strip()
        if not s.startswith("# @brief "):
            i += 1
            continue

        brief = s[len("# @brief ") :].strip()

        # Split signature from description on em-dash (preferred) or ' - '.
        if "\u2014" in brief:
            sig, desc = brief.split("\u2014", 1)
        elif " - " in brief:
            sig, desc = brief.split(" - ", 1)
        else:
            sig, desc = brief, ""

        sig = sig.strip()
        desc = desc.strip()
        name = sig.split()[0] if sig else ""

        # Collect body: all comment lines after @brief until the function def.
        raw_body: list[str] = []
        j = i + 1
        while j < len(lines):
            content = _strip_comment_prefix(lines[j])
            if content is None:
                break
            raw_body.append(content)
            j += 1

        functions.append(
            LibFunction(
                name=name,
                signature=sig,
                description=desc,
                body=_parse_body(raw_body),
            ),
        )
        i = j

    return functions
