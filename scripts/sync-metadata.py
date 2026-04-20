#!/usr/bin/env python3
"""Generate devcontainer-feature.json from metadata.yaml for each feature.

Usage:
    python3 scripts/sync-metadata.py          # write/update all JSON files
    python3 scripts/sync-metadata.py --check  # verify JSON files are up to date (CI)

Each features/*/metadata.yaml is the single source of truth for feature metadata.
devcontainer-feature.json is a generated artifact (git-ignored) produced by:

  1. Loading the YAML.
  2. Stripping markdown syntax from all ``description`` fields (feature-level
     and per-option) so the JSON description is plain text as the devcontainer
     spec recommends.
  3. Dropping custom ``x_*`` extension fields that are meaningful only to our
     tooling (docs, CI) and are not part of the devcontainer feature schema.
  4. Serialising to indented JSON.

Requires: PyYAML (pip install pyyaml / conda install pyyaml).
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print(
        "ERROR: PyYAML is required.  Install with: pip install pyyaml",
        file=sys.stderr,
    )
    sys.exit(1)

_REPO = Path(__file__).resolve().parent.parent
_FEATURES = _REPO / "features"
_SRC = _REPO / "src"


# ---------------------------------------------------------------------------
# Markdown stripping
# ---------------------------------------------------------------------------


def strip_markdown(text: str) -> str:
    """Strip markdown formatting from a description string.

    Handles:
    - Images:   ![alt](url)        → alt
    - Links:    [text](url)        → text
    - Bold:     **text** / __text__ → text
    - Italic:   *text*              → text   (``_text_`` is intentionally left
                                              alone — too ambiguous with
                                              shell variables and identifiers)
    - HTML tags: <tag ...> / </tag> → (removed)
      Only real HTML is stripped: closing tags (</...>) and opening tags that
      carry attributes (contain whitespace).  Single-word angle-bracket tokens
      like <version>, <shell>, <home_dir> used as documentation placeholders
      are intentionally left untouched.

    Backtick code spans are intentionally preserved: they remain readable
    in plain text and are common in technical option descriptions.
    """
    if not text:
        return text
    # Images before links (avoid double-processing)
    text = re.sub(r"!\[([^\]]*)\]\([^)]*\)", r"\1", text)
    # Links
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    # Bold
    text = re.sub(r"\*\*([^*]+)\*\*", r"\1", text)
    text = re.sub(r"__([^_]+)__", r"\1", text)
    # Italic (asterisk only)
    text = re.sub(r"\*([^*\n]+)\*", r"\1", text)
    # HTML tags: closing tags </foo> and opening tags with attributes <foo ...>
    # Single-word tokens like <version> or <shell> are NOT matched.
    text = re.sub(r"</[a-zA-Z][^>]*>", "", text)
    text = re.sub(r"<[a-zA-Z][^>]*\s[^>]*>", "", text)
    return text


def _normalize_description(text: str) -> str:
    """Strip markdown and normalize whitespace for JSON output.

    Strips leading/trailing whitespace and collapses multiple consecutive
    blank lines to a single blank line, while preserving intentional
    paragraph structure.
    """
    text = strip_markdown(text)
    lines = [line.rstrip() for line in text.splitlines()]
    # Collapse runs of blank lines
    result: list[str] = []
    prev_blank = False
    for line in lines:
        blank = not line.strip()
        if blank:
            if not prev_blank:
                result.append("")
            prev_blank = True
        else:
            result.append(line)
            prev_blank = False
    # Strip leading/trailing blank lines
    while result and not result[0]:
        result.pop(0)
    while result and not result[-1]:
        result.pop()
    return "\n".join(result)


# ---------------------------------------------------------------------------
# JSON generation
# ---------------------------------------------------------------------------


def _process_value(key: str, value: object) -> object:
    """Recursively process a value, stripping markdown from description fields."""
    if key == "description" and isinstance(value, str):
        return _normalize_description(value)
    if key == "options" and isinstance(value, dict):
        return {
            opt_name: {
                k: (
                    _normalize_description(v)
                    if k == "description" and isinstance(v, str)
                    else "string"
                    if k == "type" and v == "array"
                    else v
                )
                for k, v in opt.items()
                if not k.startswith("x_")  # drop option-level extension fields
            }
            for opt_name, opt in value.items()
        }
    return value


# ---------------------------------------------------------------------------
# Derived (synthetic) options — loaded from shared YAML
# ---------------------------------------------------------------------------

_DERIVED_OPTIONS_PATH = Path(__file__).parent / "derived-options.yaml"
with _DERIVED_OPTIONS_PATH.open(encoding="utf-8") as _fh:
    _DERIVED_OPTIONS: dict = yaml.safe_load(_fh)

# All keys that the generators manage (strip from raw metadata before re-injecting).
_DERIVED_OPTION_KEYS: frozenset[str] = frozenset(_DERIVED_OPTIONS)


def _synthetic(key: str) -> dict:
    """Return the option schema for a derived key, stripping the 'inject' meta-field."""
    return {k: v for k, v in _DERIVED_OPTIONS[key].items() if k != "inject"}

# Keys in metadata.yaml that are internal to this project and must not be
# written to devcontainer-feature.json (which follows the devcontainer spec).
_INTERNAL_KEYS: frozenset[str] = frozenset({"dependencies"})


def _drop_extensions(data: dict) -> dict:
    """Drop x_* custom extension fields and internal-only keys."""
    return {
        k: v
        for k, v in data.items()
        if not k.startswith("x_") and k not in _INTERNAL_KEYS
    }


def generate_json(data: dict) -> str:
    """Generate devcontainer-feature.json content from parsed YAML data.

    Returns the JSON string (with trailing newline).
    """
    # Determine whether this feature uses ospkg (dependencies key is present,
    # even if empty) to decide whether to inject the keep_cache option.
    # has_build_deps is true when the feature has a `dependencies.build` sub-map.
    has_ospkg: bool = data.get("dependencies") is not None
    deps = data.get("dependencies") or {}
    has_build_deps: bool = bool(deps.get("build"))

    # Build a patched data dict with derived options stripped from the raw
    # options dict and replaced with canonical synthetic definitions.
    # keep_cache is only stripped when has_ospkg (it will be re-injected);
    # keep_build_deps is only stripped when has_build_deps (it will be re-injected);
    # for features without those characteristics, they may be legitimate declared options.
    raw_options: dict = data.get("options") or {}
    always_strip = _DERIVED_OPTION_KEYS - {"keep_cache", "keep_build_deps"}
    keys_to_strip = always_strip | ({"keep_cache"} if has_ospkg else set()) | ({"keep_build_deps"} if has_build_deps else set())
    core_options: dict = {
        k: v for k, v in raw_options.items() if k not in keys_to_strip
    }
    synthetic_options: dict = {}
    if has_ospkg:
        synthetic_options["keep_cache"] = _synthetic("keep_cache")
    if has_build_deps:
        synthetic_options["keep_build_deps"] = _synthetic("keep_build_deps")
    synthetic_options["debug"] = _synthetic("debug")
    synthetic_options["logfile"] = _synthetic("logfile")

    patched: dict = {**data, "options": {**core_options, **synthetic_options}}
    processed = {k: _process_value(k, v) for k, v in patched.items()}
    clean = _drop_extensions(processed)
    return json.dumps(clean, indent=3, ensure_ascii=False) + "\n"


# ---------------------------------------------------------------------------
# Discovery and main
# ---------------------------------------------------------------------------


def find_features() -> list[Path]:
    """Return sorted list of features/*/metadata.yaml paths."""
    return sorted(_FEATURES.glob("*/metadata.yaml"))


def main() -> None:
    check_mode = "--check" in sys.argv
    any_stale = False

    features = find_features()
    if not features:
        print(
            f"ERROR: No features/*/metadata.yaml files found under {_FEATURES}",
            file=sys.stderr,
        )
        sys.exit(1)

    for meta_path in features:
        feature_id = meta_path.parent.name
        json_path = _SRC / feature_id / "devcontainer-feature.json"

        with meta_path.open(encoding="utf-8") as fh:
            data = yaml.safe_load(fh)

        expected = generate_json(data)

        if check_mode:
            if not json_path.exists():
                print(f"⛔ {feature_id}: devcontainer-feature.json is missing", file=sys.stderr)
                any_stale = True
            elif json_path.read_text(encoding="utf-8") != expected:
                print(f"⛔ {feature_id}: devcontainer-feature.json is stale", file=sys.stderr)
                any_stale = True
            else:
                print(f"✅ {feature_id}: in sync", file=sys.stderr)
        else:
            json_path.parent.mkdir(parents=True, exist_ok=True)
            current = json_path.read_text(encoding="utf-8") if json_path.exists() else None
            if current == expected:
                print(f"✅ {feature_id}: devcontainer-feature.json unchanged", file=sys.stderr)
            else:
                json_path.write_text(expected, encoding="utf-8")
                print(f"✅ {feature_id}: generated devcontainer-feature.json", file=sys.stderr)

    if check_mode:
        if any_stale:
            print(
                "\n⛔ Stale devcontainer-feature.json files detected."
                "  Run: bash sync-lib.sh",
                file=sys.stderr,
            )
            sys.exit(1)
        else:
            print("✅ All devcontainer-feature.json files are up to date.", file=sys.stderr)


if __name__ == "__main__":
    main()
