# Configuration file for the Sphinx documentation builder.
# https://www.sphinx-doc.org/en/master/usage/configuration.html

from __future__ import annotations

from pathlib import Path

# ── Project information ────────────────────────────────────────────────────────

project = "SysSet"
copyright = "2024–2025, SysSet contributors"
author = "SysSet contributors"

# ── General configuration ──────────────────────────────────────────────────────

extensions = [
    # Core Markdown + notebook support
    "myst_parser",
    # External TOC (docs/_toc.yml)
    "sphinx_external_toc",
    # pydata theme extras
    "sphinx_design",
    "sphinx_copybutton",
    "sphinx_togglebutton",
    # Diagrams
    "sphinxcontrib.mermaid",
    # OpenGraph meta tags
    "sphinxext.opengraph",
    # Last-updated timestamps from git
    "sphinx_last_updated_by_git",
    # 404 page
    "notfound.extension",
    # Bibliography / cite role
    "sphinxcontrib.bibtex",
]

# sphinx-external-toc: path relative to confdir
external_toc_path = "_toc.yml"
external_toc_exclude_missing = False

# MyST options
myst_enable_extensions = [
    "colon_fence",      # ::: directive shorthand
    "deflist",          # definition lists
    "fieldlist",        # field lists
    "substitution",     # |sub| substitutions
    "tasklist",         # - [ ] checkboxes
    "attrs_inline",     # inline attribute syntax
]
myst_heading_anchors = 3
myst_links_external_new_tab = True

suppress_warnings = [
    "myst.xref_missing",         # suppress missing cross-ref warnings during early dev
    "bibtex.key_not_found",      # .bib file not yet populated
    "misc.highlighting_failure", # jsonc blocks with ... ellipsis retry in relaxed mode (harmless)
    "etoc.toctree",              # sphinx-external-toc manages all toctrees
]

templates_path = ["_templates"]
exclude_patterns = [
    "_build",
    "website",
    "**.ipynb_checkpoints",
    "environment.yaml",
    # Flat stub superseded by ref/install-pixi/ subdirectory
    "ref/install-pixi.md",
]

# ── HTML output ────────────────────────────────────────────────────────────────

html_theme = "pydata_sphinx_theme"
html_title = "SysSet"
html_logo = None  # add docs/_static/logo.svg when available

html_theme_options = {
    "github_url": "https://github.com/quantized8/sysset",
    "use_edit_page_button": True,
    "show_toc_level": 2,
    "navigation_with_keys": True,
    "navbar_align": "left",
    "footer_start": ["copyright"],
    "footer_end": ["theme-version"],
    "secondary_sidebar_items": ["page-toc", "edit-this-page", "sourcelink"],
    "pygments_light_style": "friendly",
    "pygments_dark_style": "monokai",
}

html_context = {
    "github_user": "quantized8",
    "github_repo": "sysset",
    "github_version": "main",
    "doc_path": "docs",
}

html_static_path = ["_static"]
html_css_files = []

# sphinx-copybutton: strip prompt characters from copied shell blocks
copybutton_prompt_text = r"^\$ |^# "
copybutton_prompt_is_regexp = True

# sphinxcontrib-bibtex
bibtex_bibfiles = []


# ── Feature reference preamble injection ───────────────────────────────────────
# At build time, prepend each feature's H1 title, description, and ## Options
# table (read from the canonical devcontainer-feature.json source) to the
# stripped reference pages, replacing what was previously stored in the source
# files and injected via marker comments.
#
# The source md files now contain only the "Details / Usage Examples" sections
# (no H1, no description, no options table) — gen_docs.py --json is superseded.

import sys as _sys

_REPO = Path(__file__).resolve().parent.parent
_sys.path.insert(0, str(_REPO / "scripts"))

from parse_feature_json import render_json_block as _render_json_block  # noqa: E402

# Map Sphinx docname → feature directory name (under src/)
_FEATURE_DOC_MAP = {
    # Flat single-file references
    "ref/install-shell": "install-shell",
    "ref/install-fonts": "install-fonts",
    "ref/install-os-pkg": "install-os-pkg",
    "ref/install-podman": "install-podman",
    "ref/install-homebrew": "install-homebrew",
    "ref/setup-user": "setup-user",
    "ref/setup-shim": "setup-shim",
    # Subdirectory api.md references
    "ref/install-node/api": "install-node",
    "ref/install-gh/api": "install-gh",
    "ref/install-git/api": "install-git",
    "ref/install-pixi/api": "install-pixi",
}


def _parse_jsonc(text: str) -> dict:
    """Parse JSON with ``//`` line comments and trailing commas stripped."""
    import json
    import re

    in_string = False
    escaped = False
    result: list[str] = []
    i = 0
    while i < len(text):
        c = text[i]
        if escaped:
            escaped = False
            result.append(c)
        elif c == "\\" and in_string:
            escaped = True
            result.append(c)
        elif c == '"':
            in_string = not in_string
            result.append(c)
        elif (
            not in_string
            and c == "/"
            and i + 1 < len(text)
            and text[i + 1] == "/"
        ):
            while i < len(text) and text[i] != "\n":
                i += 1
            continue
        else:
            result.append(c)
        i += 1
    # Remove trailing commas before ] or } (not valid in strict JSON)
    cleaned = re.sub(r",(\s*[}\]])", r"\1", "".join(result))
    return json.loads(cleaned)


def _inject_feature_preamble(app, docname, source):  # noqa: ANN001
    """Prepend H1 + description + options table to feature reference pages."""
    feature_id = _FEATURE_DOC_MAP.get(docname)
    if feature_id is None:
        return

    json_path = _REPO / "src" / feature_id / "devcontainer-feature.json"
    if not json_path.exists():
        return

    data = _parse_jsonc(json_path.read_text(encoding="utf-8"))
    feature_name = data.get("name", feature_id)
    block = _render_json_block(data)
    preamble = f"# {feature_name}\n\n{block}\n---\n\n"
    source[0] = preamble + source[0]


# ── Pygments lexer aliases ─────────────────────────────────────────────────────


def setup(app):
    """Register lexer aliases and connect build-time feature preamble injection."""
    from pygments.lexers.data import JsonLexer
    from pygments.lexers.configs import IniLexer

    app.add_lexer("jsonc", JsonLexer)
    app.add_lexer("gitconfig", IniLexer)
    app.connect("source-read", _inject_feature_preamble)

# ── OpenGraph ──────────────────────────────────────────────────────────────────

ogp_site_url = "https://quantized8.github.io/sysset/"
ogp_description_length = 200
