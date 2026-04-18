#!/usr/bin/env python3
"""sync-deps.py — Generates dependencies/*.yaml files from metadata.yaml.

Each key under ``dependencies:`` in metadata.yaml becomes a
``dependencies/<key>.yaml`` file in the feature directory.  The value is
dumped as YAML using a consistent, deterministic format so that the
``--check`` mode can detect staleness with a byte-for-byte comparison.

Usage:
  python3 scripts/sync-deps.py           # generate all dependency files
  python3 scripts/sync-deps.py --check   # exit non-zero if any file is stale
"""

import sys
from pathlib import Path

import yaml

SCRIPT_DIR = Path(__file__).parent
FEATURES_DIR = SCRIPT_DIR.parent / "features"
SRC_DIR = SCRIPT_DIR.parent / "src"


def _dump(data: object) -> str:
    """Dump *data* to a YAML string using the canonical generated format."""
    return yaml.dump(data, default_flow_style=False, sort_keys=False, allow_unicode=True)


def main() -> int:
    check_mode = "--check" in sys.argv

    feature_dirs = sorted(FEATURES_DIR.glob("*/metadata.yaml"))
    if not feature_dirs:
        print(f"⛔ No metadata.yaml files found under {FEATURES_DIR}", file=sys.stderr)
        return 1

    any_stale = False
    any_error = False

    for meta_path in feature_dirs:
        feature_id = meta_path.parent.name
        feature_dir = SRC_DIR / feature_id

        with meta_path.open(encoding="utf-8") as fh:
            meta = yaml.safe_load(fh)

        deps = meta.get("dependencies") or {}
        if not deps:
            continue

        dep_dir = feature_dir / "dependencies"

        for lifecycle in ("run", "build"):
            groups = deps.get(lifecycle) or {}
            for dep_name, dep_content in groups.items():
                dep_path = dep_dir / lifecycle / f"{dep_name}.yaml"
                expected_text = _dump(dep_content)

                if check_mode:
                    if not dep_path.exists():
                        print(
                            f"⛔ {feature_id}: dependencies/{lifecycle}/{dep_name}.yaml is missing",
                            file=sys.stderr,
                        )
                        any_stale = True
                    elif dep_path.read_text(encoding="utf-8") != expected_text:
                        print(
                            f"⛔ {feature_id}: dependencies/{lifecycle}/{dep_name}.yaml is stale",
                            file=sys.stderr,
                        )
                        any_stale = True
                    else:
                        print(
                            f"✅ {feature_id}: dependencies/{lifecycle}/{dep_name}.yaml in sync",
                            file=sys.stderr,
                        )
                else:
                    (dep_dir / lifecycle).mkdir(parents=True, exist_ok=True)
                    if dep_path.exists() and dep_path.read_text(encoding="utf-8") == expected_text:
                        print(
                            f"✅ {feature_id}: dependencies/{lifecycle}/{dep_name}.yaml unchanged",
                            file=sys.stderr,
                        )
                    else:
                        dep_path.write_text(expected_text, encoding="utf-8")
                        print(
                            f"✅ {feature_id}: dependencies/{lifecycle}/{dep_name}.yaml updated",
                            file=sys.stderr,
                        )

    if check_mode and any_stale:
        print("", file=sys.stderr)
        print(
            "⛔ Stale dependency files detected. Run: bash sync-lib.sh",
            file=sys.stderr,
        )
        return 1

    if any_error:
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
