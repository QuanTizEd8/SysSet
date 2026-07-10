# Notes

## Source priority and deduplication

All four font sources are processed in a single run, in fixed priority order:
`p10k_fonts` → `nerd_fonts` → `gh_release_fonts` → `font_urls`.

Before installing, the feature scans the resolved font directory and indexes
the PostScript name of every `.ttf`/`.otf` already present. Each candidate font
is then checked against this index, so the same font is never installed twice —
whether the duplicate is an already-installed file or comes from another source
earlier in the same run. On a name collision the higher-priority source wins and
the duplicate is skipped (with a logged message).

Set `overwrite: true` to invert this: colliding fonts are always replaced, so
the **last** source to provide a given PostScript name wins. When every requested
font is already registered, the run installs nothing new.

## Install layout

Every font installed in a single run lands under one timestamped directory,
created lazily on the first write and named with the Unix epoch at the start of
the run:

```
<font_dir>/devfeats-install-fonts-<timestamp>/
  p10k/MesloLGS-NF/                # p10k_fonts
  nerd/<name>/                     # nerd_fonts
  gh/<owner>/<repo>/<tag>/<id>/    # gh_release_fonts
  url/<host>/<path>/               # font_urls
```

Archives preserve their internal directory structure under these namespaces. If
no new fonts are installed, the timestamped directory is never created. Re-running
the feature creates a new timestamped directory rather than modifying an existing
one.

## WOFF and WOFF2 are never deduplicated

PostScript-name deduplication relies on `fc-query`, which only reads TrueType and
OpenType fonts. `.woff` and `.woff2` files are copied unconditionally, are not
indexed, and are not registered with fontconfig — install them only when a
WOFF-aware consumer (e.g. a browser) will use them directly.

## Powerlevel10k terminal glyphs

If you use the `setup-shell` feature with the
[Powerlevel10k](https://github.com/romkatv/powerlevel10k) theme, set
`p10k_fonts: true` here so the required MesloLGS NF glyphs render in the terminal.
