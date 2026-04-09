# Install Fonts

Install fonts from multiple sources: [Nerd Fonts](https://www.nerdfonts.com/)
by name, arbitrary direct URLs (individual font files or archives), and
[GitHub release](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
assets. Suitable both as a Dev Container feature (runs as root at image build
time) and as a standalone script on a host machine (macOS or Linux) via CLI
flags.

---

## Usage

### As a Dev Container feature

```jsonc
// .devcontainer/devcontainer.json
{
  "features": {
    "ghcr.io/quantized8/sysset/install-fonts:0": {}
  }
}
```

With the defaults above, the feature will:

1. Install **Meslo** and **JetBrainsMono** Nerd Fonts into `/usr/share/fonts/`
2. Refresh the system font cache with `fc-cache`

### Nerd Fonts — custom selection

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-fonts:0": {
      "nerd_fonts": "Meslo,FiraCode,Hack,JetBrainsMono"
    }
  }
}
```

Font names must match the archive name used in
[nerd-fonts releases](https://github.com/ryanoasis/nerd-fonts/releases) —
for example, `Meslo` downloads `Meslo.tar.xz`.

### Skip Nerd Fonts entirely

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-fonts:0": {
      "nerd_fonts": ""
    }
  }
}
```

### Direct URL — individual font file

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-fonts:0": {
      "nerd_fonts": "",
      "font_urls": "https://example.com/fonts/MyFont-Regular.ttf"
    }
  }
}
```

Supported extensions for individual files: `.ttf`, `.otf`, `.woff`, `.woff2`.
The file lands flat in `font_dir` (e.g. `/usr/share/fonts/MyFont-Regular.ttf`).

### Direct URL — archive

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-fonts:0": {
      "nerd_fonts": "",
      "font_urls": "https://example.com/fonts/MyFont-2.0.tar.xz"
    }
  }
}
```

Supported archive formats: `.tar.xz`, `.tar.gz`, `.tgz`, `.zip`. The archive
extracts into `font_dir/<archive-name>/` (e.g.
`/usr/share/fonts/MyFont-2.0/`) and non-font files are removed.

### GitHub release — latest

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-fonts:0": {
      "nerd_fonts": "",
      "gh_release_fonts": "JetBrains/JetBrainsMono"
    }
  }
}
```

Fetches all font/archive assets from the latest release of
`github.com/JetBrains/JetBrainsMono`. Archives are preferred over individual
files when both are present. Assets install into `font_dir/JetBrainsMono/`.

### GitHub release — pinned tag

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-fonts:0": {
      "nerd_fonts": "",
      "gh_release_fonts": "JetBrains/JetBrainsMono@v2.304"
    }
  }
}
```

Appending `@<tag>` targets that specific release tag via the GitHub Releases
API instead of the latest endpoint.

### Powerlevel10k terminal fonts

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-fonts:0": {
      "p10k_fonts": true
    }
  }
}
```

Installs the four
[MesloLGS NF](https://github.com/romkatv/powerlevel10k-media) fonts required
by the [Powerlevel10k](https://github.com/romkatv/powerlevel10k) Zsh theme:
Regular, Bold, Italic, and Bold Italic. Fonts land in `font_dir/MesloLGS-NF/`.

### Custom font directory

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-fonts:0": {
      "font_dir": "/opt/fonts"
    }
  }
}
```

Overrides the auto-detected installation directory. Useful when building
images that will be used both as devcontainers and as production images with
non-standard font paths.

### All sources combined

```jsonc
{
  "features": {
    "ghcr.io/quantized8/sysset/install-fonts:0": {
      "nerd_fonts": "Meslo,FiraCode",
      "font_urls": "https://example.com/MyFont.tar.gz,https://example.com/Extra.ttf",
      "gh_release_fonts": "JetBrains/JetBrainsMono@v2.304",
      "p10k_fonts": true
    }
  }
}
```

All four sources are processed in sequence within a single feature run.

---

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `nerd_fonts` | string | `"Meslo,JetBrainsMono"` | Comma-separated [Nerd Fonts](https://www.nerdfonts.com/) archive names to install (e.g. `Meslo,FiraCode,Hack`). Set to empty string to skip Nerd Font downloads. |
| `font_urls` | string | `""` | Comma-separated direct URLs to download. Individual font files (`.ttf`, `.otf`, `.woff`, `.woff2`) land flat in `font_dir`; archives (`.tar.xz`, `.tar.gz`, `.tgz`, `.zip`) extract into `font_dir/<archive-name>/` with non-font files removed. |
| `gh_release_fonts` | string | `""` | Comma-separated GitHub slugs in `owner/repo` or `owner/repo@tag` form (e.g., [JetBrains/JetBrainsMono@v2.304](https://github.com/JetBrains/JetBrainsMono/releases/tag/v2.304)). All font and archive assets from the release are installed into `font_dir/<repo>/`. Without a tag, the latest release is used. |
| `font_dir` | string | `""` | Font installation directory. Leave empty to auto-detect (see [Font directory auto-detection](#font-directory-auto-detection)). |
| `p10k_fonts` | boolean | `false` | Install the four [MesloLGS NF](https://github.com/romkatv/powerlevel10k-media) fonts required by Powerlevel10k into `font_dir/MesloLGS-NF/`. |
| `debug` | boolean | `false` | Enable `set -x` trace output in all scripts. |

---

## Execution order

The installer runs as root at image build time in a single sequential pass.

### Bootstrap (`install.sh`)

The top-level `install.sh` is a POSIX sh script that invokes `install-os-pkg`
to install all declared package dependencies (including `bash` itself), then
hands off to `scripts/install.sh` via `exec bash`.

### Step 1 — Install packages

`install-os-pkg` reads `packages.txt` and installs the required tools
(`curl`, `fontconfig`, `xz-utils`, `unzip`, etc.) via the detected package
manager. This step is skipped automatically for any package that is already
present.

### Step 2 — Resolve font directory

`scripts/install.sh` parses options (CLI flags or environment variables), then
auto-detects `FONT_DIR` if it was not set explicitly. See
[Font directory auto-detection](#font-directory-auto-detection).

### Step 3 — Install Nerd Fonts

For each name in `nerd_fonts`:

1. Checks whether `font_dir/<name>/` already contains `.ttf` or `.otf` files
   (idempotent skip).
2. Downloads `<name>.tar.xz` from the
   [nerd-fonts latest release](https://github.com/ryanoasis/nerd-fonts/releases/latest)
   with up to 3 retries.
3. Extracts into `font_dir/<name>/` and removes non-font files (LICENSE,
   README, etc.).
4. Sets directory permissions to `755` and file permissions to `644`.

Skipped entirely when `nerd_fonts` is empty.

### Step 4 — Install fonts from direct URLs

For each URL in `font_urls`:

- **Archive** (`.tar.xz` / `.tar.gz` / `.tgz` / `.zip`): strips all
  extensions to derive a directory name, extracts into `font_dir/<dir>/`, and
  removes non-font files. Idempotent — skips if the directory already
  contains font files.
- **Font file** (`.ttf` / `.otf` / `.woff` / `.woff2`): downloads directly
  to `font_dir/<filename>`. Idempotent — skips if the file already exists.
- **Unknown extension**: emits a warning and skips without error.

Query strings in URLs are stripped before basename detection.

Skipped entirely when `font_urls` is empty.

### Step 5 — Install fonts from GitHub releases

For each slug in `gh_release_fonts`:

1. Splits `owner/repo@tag` into a repository path and an optional tag.
2. Calls the GitHub Releases API:
   - No tag → `GET /repos/<owner>/<repo>/releases/latest`
   - Tag present → `GET /repos/<owner>/<repo>/releases/tags/<tag>`
3. Parses `browser_download_url` values from the response (no `jq`
   dependency — uses `grep`/`sed`).
4. Filters for font (`.ttf`, `.otf`, `.woff`, `.woff2`) and archive
   (`.tar.xz`, `.tar.gz`, `.tgz`, `.zip`) assets. If archives are present,
   only archives are downloaded (individual font files are skipped to avoid
   duplication); otherwise individual font files are downloaded.
5. Extracts archives and copies individual font files into
   `font_dir/<repo>/`. Idempotent — skips if the directory already contains
   font files.

Skipped entirely when `gh_release_fonts` is empty.

### Step 6 — Install Powerlevel10k MesloLGS NF fonts

Downloads the four MesloLGS NF variants (Regular, Bold, Italic, Bold Italic)
from `github.com/romkatv/powerlevel10k-media` into `font_dir/MesloLGS-NF/`.
Idempotent — skips if the directory already contains `.ttf` files.

Skipped when `p10k_fonts` is `false`.

### Step 7 — Refresh font cache

Runs `fc-cache -f "$FONT_DIR"` to register the newly installed fonts with
fontconfig. Silently skipped if `fc-cache` is not available.

---

## Font directory auto-detection

When `font_dir` is left empty (the default), the installer detects the
appropriate directory at runtime:

| Condition | Resolved `font_dir` |
|---|---|
| Running as root (`$EUID -eq 0`) | `/usr/share/fonts` |
| macOS user (`uname == Darwin`) | `~/Library/Fonts` |
| Linux user (non-root) | `${XDG_DATA_HOME:-$HOME/.local/share}/fonts` |

Setting `font_dir` explicitly overrides this logic for all invocation modes.

---

## Font sources

### Nerd Fonts

[Nerd Fonts](https://www.nerdfonts.com/) patches popular programming fonts
with a large number of glyphs (icons) from popular icon sets. The `nerd_fonts`
option accepts a comma-separated list of archive names that match the filenames
used in the [ryanoasis/nerd-fonts](https://github.com/ryanoasis/nerd-fonts/releases)
releases (e.g. `Meslo` → `Meslo.tar.xz`).

Some common names: `Meslo`, `JetBrainsMono`, `FiraCode`, `Hack`,
`SourceCodePro`, `RobotoMono`, `DejaVuSansMono`, `Inconsolata`, `UbuntuMono`.

### Direct URLs (`font_urls`)

Accepts any publicly accessible URL. The installer branches on file extension:

- **Individual font file** — lands flat in `font_dir` (no subdirectory).
- **Archive** — all contents are extracted into `font_dir/<name>/` where
  `<name>` is the archive filename with all extensions stripped (e.g.
  `MyFont-2.0.tar.xz` → `MyFont-2.0`). Non-font files inside the archive
  are deleted after extraction.

Multiple URLs are separated by commas. Query strings (e.g. `?token=...`) in
URLs are stripped before the basename is extracted.

### GitHub Releases (`gh_release_fonts`)

Fetches release assets from any public GitHub repository using the
[GitHub Releases REST API](https://docs.github.com/en/rest/releases/releases).
No authentication or `jq` is required.

| Slug form | API endpoint |
|---|---|
| `owner/repo` | `GET /repos/owner/repo/releases/latest` |
| `owner/repo@tag` | `GET /repos/owner/repo/releases/tags/<tag>` |

When the release contains both archives and individual font files, only the
archives are downloaded (archives typically bundle the same fonts more
efficiently).

### Powerlevel10k MesloLGS NF (`p10k_fonts`)

The [Powerlevel10k](https://github.com/romkatv/powerlevel10k) Zsh theme
requires a patched version of MesloLGS NF to render icons and glyphs
correctly. The `p10k_fonts: true` option installs all four variants directly
from the [romkatv/powerlevel10k-media](https://github.com/romkatv/powerlevel10k-media)
repository, regardless of whether the standard Meslo Nerd Font is also
installed.

> **Note:** If you are using the `install-shell` feature with
> `ohmyzsh_theme: "romkatv/powerlevel10k"`, set `p10k_fonts: true` here to
> ensure terminal icons render correctly.

---

## System paths summary

| Path | Purpose |
|---|---|
| `/usr/share/fonts/` | Default font directory (root/container) |
| `~/Library/Fonts/` | Default font directory (macOS user) |
| `~/.local/share/fonts/` | Default font directory (Linux non-root user, XDG default) |
| `<font_dir>/<NerdFontName>/` | Nerd Font install directory (one per font family) |
| `<font_dir>/<archive-name>/` | Archive URL or GitHub release install directory |
| `<font_dir>/<filename.ttf>` | Individual font file (flat install) |
| `<font_dir>/MesloLGS-NF/` | Powerlevel10k MesloLGS NF fonts |

---

## Dependencies

`install-os-pkg` installs the following packages before the main script runs:

| Package | Purpose |
|---|---|
| `bash` | Required to run `scripts/install.sh` and `scripts/install_fonts.sh` |
| `curl` | Download font archives, individual files, and GitHub API responses |
| `ca-certificates` | TLS certificate verification for HTTPS downloads |
| `fontconfig` | Provides `fc-cache` for font cache refresh |
| `xz-utils` (apt) / `xz` (apk, dnf) | Decompress `.tar.xz` archives |
| `unzip` | Extract `.zip` archives |

This feature declares a hard dependency on
`ghcr.io/quantized8/sysset/install-os-pkg:0`. That feature provides the
`install-os-pkg` command and is guaranteed to run before `install-fonts`.

---

## Standalone CLI usage

`scripts/install.sh` accepts CLI flags and can be run directly on any machine
that has `bash`, `curl`, and `fontconfig` available. All options that are
available as Dev Container feature options map directly to `--<option>` flags.

### Linux host (user install)

```sh
# Install Meslo and FiraCode Nerd Fonts to ~/.local/share/fonts
bash scripts/install.sh --nerd_fonts "Meslo,FiraCode"
```

Font directory auto-detects to `~/.local/share/fonts` when running as a
non-root user on Linux.

### macOS host

```sh
# Install JetBrainsMono Nerd Font to ~/Library/Fonts
bash scripts/install.sh --nerd_fonts "JetBrainsMono"
```

Font directory auto-detects to `~/Library/Fonts` on macOS.

### Custom font directory

```sh
bash scripts/install.sh \
  --nerd_fonts "Meslo" \
  --font_dir "/opt/fonts"
```

### GitHub release (pinned)

```sh
bash scripts/install.sh \
  --nerd_fonts "" \
  --gh_release_fonts "JetBrains/JetBrainsMono@v2.304" \
  --font_dir "$HOME/.local/share/fonts"
```

### All options

```
Usage: install.sh [OPTIONS]

Options:
  --nerd_fonts <string>        Comma-separated Nerd Fonts archive names (default: "Meslo,JetBrainsMono")
  --font_urls <urls>           Comma-separated direct font URLs
  --gh_release_fonts <slugs>   Comma-separated GitHub slugs (owner/repo or owner/repo@tag)
  --font_dir <path>            Font installation directory (auto-detected when empty)
  --p10k_fonts                 Install Powerlevel10k MesloLGS NF fonts
  --debug                      Enable debug output (set -x)
  -h, --help                   Show this help
```

---

## File tree

```
src/install-fonts/
├── devcontainer-feature.json   # Feature metadata and options
├── install.sh                  # Bootstrap: installs packages, then execs scripts/install.sh
├── packages.txt                # Dependencies for install-os-pkg
└── scripts/
    ├── helpers.sh              # fetch_with_retry helper
    ├── install.sh              # Orchestrator: arg parsing, font_dir detection, calls install_fonts.sh
    └── install_fonts.sh        # Core installer: Nerd Fonts, URLs, GitHub releases, p10k, fc-cache
```

---

## Failure modes

- **Nerd Font download fails** — the font is skipped with a `⚠️` warning;
  remaining fonts in the list continue normally. The feature does not exit
  non-zero for a single font failure.
- **Direct URL download fails** — skipped with a warning after 3 retry
  attempts. Other URLs in `font_urls` are unaffected.
- **`.zip` extraction without `unzip`** — `unzip` is installed via
  `packages.txt`, but if it is unavailable for any reason, the specific
  `.zip` item is skipped with a warning.
- **Unknown URL extension** — any URL whose basename does not match a
  recognized font or archive extension is skipped with a warning.
- **GitHub API request fails** — the slug is skipped with a warning. Common
  causes: network unavailability, a private repository, or a non-existent tag.
- **GitHub release has no font/archive assets** — skipped with a warning.
- **`fc-cache` not available** — the font cache refresh step is silently
  skipped. Fonts are still installed on disk; the cache will be updated the
  next time `fc-cache` is run (e.g. on first login).
- **Font already present** — each installation step is idempotent. If the
  target directory (for archives and Nerd Fonts) or file (for individual font
  files) already exists and contains font data, the step is skipped with an
  `ℹ️` message. This makes repeated `devcontainer rebuild` runs fast.
