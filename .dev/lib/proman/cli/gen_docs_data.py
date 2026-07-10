"""CLI: generate docs build context JSON for Sphinx and cross-environment use."""

from __future__ import annotations

import argparse
import json
import sys
from typing import TYPE_CHECKING

from proman.config import load as load_config
from proman.docs import feat_doc_gen, lib_doc_gen
from proman.docs.parse_lib import parse_lib_module
from proman.git import git_owner_repo, git_repo_root
from proman.metadata import MetadataLoader
from proman.sync import remove_file, sync_file

if TYPE_CHECKING:
    from pathlib import Path


def _iter_lib_module_paths(lib_dir: Path) -> list[Path]:
    """Return sorted lib module source files, excluding the aggregate loader."""
    return sorted(
        (
            path
            for path in lib_dir.iterdir()
            if path.is_file()
            and path.name != "__init__.bash"
            and path.suffix in {".bash", ".sh"}
        ),
        key=lambda path: path.name,
    )


def main() -> int:
    """Generate docs_build_context.json and per-feature/library Markdown files."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--include-private",
        action="store_true",
        default=False,
        help="Include private functions (names starting with _) in library docs.",
    )
    args = parser.parse_args()
    config = load_config()

    repo = git_repo_root()
    features_dir = config.absolute_path("path.features")
    lib_dir = config.absolute_path("path.library")
    data_transfer_dir = config.absolute_path("path.data_transfer")
    data_transfer_dir.mkdir(parents=True, exist_ok=True)
    # Per-feature note sources → child docs: (source filename, output docname
    # stem, required level-1 heading supplying the child page title).
    feature_child_page_specs = (
        (str(config["filename.feature_notes"]), "notes", feat_doc_gen.NOTES_HEADING),
        (
            str(config["filename.feature_dev_notes"]),
            "dev-notes",
            feat_doc_gen.DEV_NOTES_HEADING,
        ),
    )

    owner, repo_name = git_owner_repo()

    # ── Feature metadata ──────────────────────────────────────────────────────

    all_metadata = MetadataLoader().load()

    # ── Library module metadata ───────────────────────────────────────────────

    lib_module_paths = _iter_lib_module_paths(lib_dir)
    lib_modules: dict[str, str] = {}
    for module_path in lib_module_paths:
        module = parse_lib_module(module_path)
        if not module.summary:
            print(
                "⚠️  gen-docs-data: "
                f"{module_path.name} has no module-level docs; skipping",
                file=sys.stderr,
            )
            continue
        lib_modules[module.name] = module.summary

    # ── Write docs_build_context.json ─────────────────────────────────────────

    docs_data = {
        "repo_owner": owner,
        "repo_name": repo_name,
        "features": all_metadata,
        "lib_modules": lib_modules,
    }
    docs_build_context_path = data_transfer_dir / str(
        config["filename.docs_build_context"]
    )
    docs_build_context_content = json.dumps(docs_data, indent=2, ensure_ascii=False)
    sync_file(docs_build_context_path, docs_build_context_content)

    # ── Feature docs ──────────────────────────────────────────────────────────
    #
    # Each feature is emitted as a directory ``<id>/`` holding an ``index.md``
    # (the generated reference page) plus optional ``notes.md`` / ``dev-notes.md``
    # child pages, linked from ``index.md`` through a hidden toctree so the nav
    # renders each feature with its note pages as children.

    feat_doc_dir = config.absolute_path("path.docs_source_features")
    feat_doc_dir.mkdir(parents=True, exist_ok=True)
    for feat_id, feat_metadata in all_metadata.items():
        feat_dir = feat_doc_dir / feat_id
        child_pages: list[str] = []
        expected_files = {"index.md"}
        for src_name, stem, heading in feature_child_page_specs:
            src_path = features_dir / feat_id / src_name
            if not src_path.exists():
                continue
            page = feat_doc_gen.render_child_page(
                src_path.read_text(encoding="utf-8"),
                heading,
            )
            sync_file(feat_dir / f"{stem}.md", page)
            child_pages.append(stem)
            expected_files.add(f"{stem}.md")
        index_content = feat_doc_gen.generate(feat_metadata, child_pages=child_pages)
        sync_file(feat_dir / "index.md", index_content)
        for stale in sorted(feat_dir.glob("*.md")):
            if stale.name not in expected_files:
                remove_file(stale)

    # Prune artifacts of prior layouts and deleted features: any top-level
    # ``<id>.md`` (old flat layout) and any directory without a backing feature.
    expected_dirs = set(all_metadata)
    for entry in sorted(feat_doc_dir.iterdir()):
        if entry.is_file() and entry.suffix == ".md":
            remove_file(entry)
        elif entry.is_dir() and entry.name not in expected_dirs:
            for stale_file in sorted(entry.glob("*")):
                if stale_file.is_file():
                    remove_file(stale_file)
            entry.rmdir()

    # ── Library docs ──────────────────────────────────────────────────────────

    lib_doc_dir = config.absolute_path("path.docs_source_library")
    lib_doc_dir.mkdir(parents=True, exist_ok=True)
    expected_docs: set[str] = set()
    for module_path in lib_module_paths:
        module = parse_lib_module(module_path)
        doc_content = lib_doc_gen.generate(module, include_private=args.include_private)
        doc_name = f"{module.name}.md"
        expected_docs.add(doc_name)
        doc_path = lib_doc_dir / doc_name
        sync_file(doc_path, doc_content)
    for stale_doc in lib_doc_dir.glob("*.md"):
        if stale_doc.name not in expected_docs:
            stale_doc.unlink()

    print(
        f"docs build context:"
        f" {len(all_metadata)} features, {len(lib_modules)} lib modules"
        f" → {docs_build_context_path.relative_to(repo)}"
        f" + {feat_doc_dir.relative_to(repo)}/*/index.md"
        f" + {lib_doc_dir.relative_to(repo)}/*.md",
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
