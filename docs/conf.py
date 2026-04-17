# Configuration file for the Sphinx documentation builder.
# https://www.sphinx-doc.org/en/master/usage/configuration.html

from __future__ import annotations

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


# ── Pygments lexer aliases ─────────────────────────────────────────────────────


def setup(app):
    """Register unknown lexer aliases so jsonc/gitconfig blocks render correctly."""
    from pygments.lexers.data import JsonLexer
    from pygments.lexers.configs import IniLexer

    app.add_lexer("jsonc", JsonLexer)
    app.add_lexer("gitconfig", IniLexer)

# ── OpenGraph ──────────────────────────────────────────────────────────────────

ogp_site_url = "https://quantized8.github.io/sysset/"
ogp_description_length = 200
