#!/usr/bin/env python3
"""Parse structured @brief + body comments from lib/*.sh files.

Each public function in a lib/*.sh file is documented with a comment block
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

Exported types:
    LibFunction   — parsed function (name, signature, description, body)
    ParagraphBlock — a block of prose lines
    SectionBlock   — a labelled section (Args, Stdout, Returns, …)

Exported function:
    parse_lib_file(path) → list[LibFunction]
"""

from __future__ import annotations

import re
from pathlib import Path

# ── Data types ────────────────────────────────────────────────────────────────


class ParagraphBlock:
    """A block of plain prose lines between two blank comment lines."""

    def __init__(self, lines: list[str]) -> None:
        self.lines = lines

    def __repr__(self) -> str:  # pragma: no cover
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
        return f"SectionBlock({self.title!r}, {self.items!r})"


class LibFunction:
    """One public function parsed from a lib/*.sh file."""

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
        return f"LibFunction({self.name!r})"


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


def _classify_block(lines: list[str]) -> ParagraphBlock | SectionBlock:
    """Classify a non-empty list of stripped comment lines.

    Recognition rules (applied in order):
    1. Multi-item section: first line matches /^Word:$/ and all remaining
       lines are indented by at least two spaces.
    2. Inline section: exactly one line matching /^Word: text$/.
    3. Everything else: ParagraphBlock.
    """
    first = lines[0]

    # Rule 1: "Args:" header + indented items.
    m = _SECTION_HEADER_RE.match(first)
    if m and len(lines) > 1 and all(l[:2] == "  " for l in lines[1:]):
        return SectionBlock(
            title=m.group(1),
            items=[l.lstrip() for l in lines[1:]],
        )

    # Rule 2: "Stdout: text" / "Returns: text" inline label.
    m = _INLINE_SECTION_RE.match(first)
    if m and len(lines) == 1:
        return SectionBlock(title=m.group(1), items=[m.group(2)])

    return ParagraphBlock(lines=lines)


def _parse_body(raw_lines: list[str]) -> list[ParagraphBlock | SectionBlock]:
    """Group raw stripped comment-body lines into ParagraphBlock / SectionBlock
    objects, splitting on blank lines.
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


# ── Public API ────────────────────────────────────────────────────────────────


def parse_lib_file(path: Path) -> list[LibFunction]:
    """Parse @brief annotations and full comment bodies from a lib/*.sh file.

    Scans every line for '# @brief' to find annotated public functions.
    For each function, collects all comment lines between the @brief line and
    the function definition, then parses them into structured blocks.

    Args:
        path  Absolute path to the lib/*.sh file.

    Returns a list of LibFunction objects in source order.
    """
    functions: list[LibFunction] = []
    lines = path.read_text(encoding="utf-8").splitlines()

    i = 0
    while i < len(lines):
        s = lines[i].strip()
        if not s.startswith("# @brief "):
            i += 1
            continue

        brief = s[len("# @brief "):].strip()

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
            )
        )
        i = j

    return functions
