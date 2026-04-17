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
# table to the stripped reference pages.
#
# metadata.yaml is the single source of truth.  The raw markdown description
# (including links) is used verbatim so MyST renders it correctly.  The
# ## Options table is generated from the options dict in metadata.yaml.
# devcontainer-feature.json is a generated artifact and not read here.

import sys as _sys

import yaml as _yaml  # noqa: E402 (pyyaml; available in sysset-website env via myst-parser)

_REPO = Path(__file__).resolve().parent.parent
_sys.path.insert(0, str(_REPO / "scripts"))

from parse_feature_json import render_options_table as _render_options_table  # noqa: E402

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


def _inject_feature_preamble(app, docname, source):  # noqa: ANN001
    """Prepend H1 + description + options table to feature reference pages."""
    feature_id = _FEATURE_DOC_MAP.get(docname)
    if feature_id is None:
        return

    meta_path = _REPO / "src" / feature_id / "metadata.yaml"
    if not meta_path.exists():
        return

    with meta_path.open(encoding="utf-8") as fh:
        data = _yaml.safe_load(fh)

    feature_name = data.get("name", feature_id)
    # Use the raw description from YAML verbatim so markdown links render.
    desc_raw = (data.get("description") or "").strip()
    options_block = _render_options_table(data)

    parts = [f"# {feature_name}"]
    if desc_raw:
        parts.append(desc_raw)
    if options_block:
        parts.append(options_block)
    parts.append("---\n")
    preamble = "\n\n".join(parts) + "\n"
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
