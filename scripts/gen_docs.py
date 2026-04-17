#!/usr/bin/env python3
"""scripts/gen_docs.py — Documentation injection tool for sysset.

Reads structured @brief annotations from lib/*.sh and devcontainer-feature.json
files to inject auto-generated content between special marker comments in
documentation files.

Injection markers (HTML comments preserved in Markdown):
    <!-- START <tag> MARKER -->
    ...replaced content...
    <!-- END <tag> MARKER -->

Usage:
    python3 scripts/gen_docs.py [--lib] [--json] [--check]
    make gen-docs          # run all modes
    make gen-docs-check    # --check (CI mode, exits 1 if anything would change)

Modes (default: all):
    --lib    Inject lib API tables into lib.instructions.md and
             docs/dev-guide/writing-features.md
    --json   Inject options blocks from src/*/devcontainer-feature.json
             into docs/ref/*/api.md files that carry the JSON marker
    --check  Dry-run: print what would change and exit 1 if anything differs

Parsers live in separate modules:
    parse_lib.py          — @brief + structured body parser for lib/*.sh
    parse_feature_json.py — devcontainer-feature.json options renderer
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from parse_lib import LibFunction, parse_lib_file
from parse_feature_json import render_json_block

# ── Paths ──────────────────────────────────────────────────────────────────────

REPO = Path(__file__).resolve().parent.parent
LIB_DIR = REPO / "lib"
SRC_DIR = REPO / "src"
DOCS_REF_DIR = REPO / "docs" / "ref"

LIB_INSTRUCTIONS = REPO / ".github" / "instructions" / "lib.instructions.md"
WRITING_FEATURES = REPO / "docs" / "dev-guide" / "writing-features.md"

# ── Canonical module order (matches writing-features.md section order) ─────────

LIB_MODULE_ORDER = [
    "logging.sh",
    "os.sh",
    "ospkg.sh",
    "net.sh",
    "git.sh",
    "shell.sh",
    "github.sh",
    "checksum.sh",
    "users.sh",
]

# ── Marker injection ───────────────────────────────────────────────────────────


def _find_markers(content: str, tag: str) -> tuple[int, int] | None:
    """Return (after_start_newline, before_end) char positions, or None."""
    start_marker = f"<!-- START {tag} MARKER -->"
    end_marker = f"<!-- END {tag} MARKER -->"

    start_pos = content.find(start_marker)
    if start_pos == -1:
        return None
    end_pos = content.find(end_marker, start_pos)
    if end_pos == -1:
        return None

    # Position just after the newline that follows the start marker
    after = start_pos + len(start_marker)
    if after < len(content) and content[after] == "\n":
        after += 1
    return after, end_pos


def has_markers(content: str, tag: str) -> bool:
    return _find_markers(content, tag) is not None


def inject_block(content: str, tag: str, new_block: str) -> tuple[str, bool]:
    """
    Replace content between START/END markers for <tag>.
    Returns (new_content, changed).  Returns (content, False) if markers absent.
    """
    positions = _find_markers(content, tag)
    if positions is None:
        return content, False

    after_start, before_end = positions

    # Normalise: block must end with exactly one newline
    new_block = new_block.rstrip("\n") + "\n"

    old_block = content[after_start:before_end]
    if old_block == new_block:
        return content, False

    return content[:after_start] + new_block + content[before_end:], True


# ── Compact table (lib.instructions.md) ───────────────────────────────────────


def render_compact_table(modules: dict[str, list[LibFunction]]) -> str:
    """Render the | Module | Key API | table for lib.instructions.md."""
    lines = ["| Module | Key API |", "|---|---|"]
    for module in LIB_MODULE_ORDER:
        if module not in modules or not modules[module]:
            continue
        sigs = " \u00b7 ".join(f"`{fn.signature}`" for fn in modules[module])
        lines.append(f"| `{module}` | {sigs} |")
    return "\n".join(lines) + "\n"


# ── Per-module detail table (writing-features.md) ─────────────────────────────


def render_module_table(functions: list[LibFunction]) -> str:
    """Render the | Function | Signature | Description | table for one module."""
    if not functions:
        return ""
    lines = [
        "| Function | Signature | Description |",
        "|---|---|---|",
    ]
    for fn in functions:
        lines.append(f"| `{fn.name}` | `{fn.signature}` | {fn.description} |")
    return "\n".join(lines) + "\n"


# ── File processing ────────────────────────────────────────────────────────────


def process_file(
    path: Path,
    injections: list[tuple[str, str]],
    check: bool,
) -> bool:
    """
    Apply all (tag, new_block) injections to a file.
    Returns True if any change was made (or would be made in --check mode).
    In check mode, prints a message but does not write.
    """
    content = path.read_text(encoding="utf-8")
    changed = False

    for tag, new_block in injections:
        if not has_markers(content, tag):
            rel = path.relative_to(REPO)
            print(f"  ⚠  {rel}: markers for '{tag}' not found — skipping.")
            continue
        new_content, did_change = inject_block(content, tag, new_block)
        if did_change:
            content = new_content
            changed = True

    if changed:
        rel = path.relative_to(REPO)
        if check:
            print(f"  ✗  {rel}: would be updated (run 'make gen-docs' to regenerate)")
        else:
            path.write_text(content, encoding="utf-8")
            print(f"  ✓  {rel}: updated")

    return changed


# ── Mode: lib ──────────────────────────────────────────────────────────────────


def run_lib(check: bool) -> bool:
    """
    Parse @brief from lib/*.sh, inject tables into lib.instructions.md and
    docs/dev-guide/writing-features.md.  Returns True if any file changed.
    """
    modules: dict[str, list[dict]] = {}
    for module in LIB_MODULE_ORDER:
        lib_path = LIB_DIR / module
        if not lib_path.exists():
            continue
        functions = parse_lib_file(lib_path)
        if functions:
            modules[module] = functions

    any_changed = False

    # lib.instructions.md — compact | Module | Key API | table
    compact = render_compact_table(modules)
    if process_file(LIB_INSTRUCTIONS, [("lib-api", compact)], check):
        any_changed = True

    # writing-features.md — per-module | Function | Signature | Description | tables
    injections: list[tuple[str, str]] = []
    for module, functions in modules.items():
        stem = module.removesuffix(".sh")
        tag = f"lib-{stem}-table"
        table = render_module_table(functions)
        injections.append((tag, table))

    if process_file(WRITING_FEATURES, injections, check):
        any_changed = True

    return any_changed


# ── Mode: json ─────────────────────────────────────────────────────────────────


def run_json(check: bool) -> bool:
    """
    Parse devcontainer-feature.json files and inject options blocks into
    docs/ref/*/api.md files that carry the JSON injection markers.
    Returns True if any file changed.
    """
    any_changed = False
    tag = "devcontainer-feature.json"

    for api_doc in sorted(DOCS_REF_DIR.glob("*/api.md")):
        content = api_doc.read_text(encoding="utf-8")
        if not has_markers(content, tag):
            # Not an error — some api.md files may not use JSON injection yet
            continue

        feature_name = api_doc.parent.name
        json_path = SRC_DIR / feature_name / "devcontainer-feature.json"
        if not json_path.exists():
            rel = api_doc.relative_to(REPO)
            print(
                f"  ⚠  {rel}: no JSON at src/{feature_name}/devcontainer-feature.json"
                " — skipping."
            )
            continue

        data = json.loads(json_path.read_text(encoding="utf-8"))
        block = render_json_block(data)
        if process_file(api_doc, [(tag, block)], check):
            any_changed = True

    return any_changed


# ── Entry point ────────────────────────────────────────────────────────────────


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--lib", action="store_true", help="Inject lib API tables")
    parser.add_argument("--json", action="store_true", help="Inject JSON options blocks")
    parser.add_argument(
        "--check",
        action="store_true",
        help="Dry-run: exit 1 if any file would change",
    )
    args = parser.parse_args()

    run_all = not args.lib and not args.json
    any_changed = False

    if run_all or args.lib:
        print("── lib ──────────────────────────────────────────────────────────────")
        if run_lib(args.check):
            any_changed = True

    if run_all or args.json:
        print("── json ─────────────────────────────────────────────────────────────")
        if run_json(args.check):
            any_changed = True

    if any_changed:
        if args.check:
            print(
                "\n✗ Some docs are out of date. Run 'make gen-docs' to regenerate."
            )
            return 1
        return 0

    print("\n✓ All docs are up to date.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
