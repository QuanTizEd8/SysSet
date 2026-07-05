"""Host-side port of the framework's upstream version resolvers.

Mirrors `__feat_resolve_version_spec__`'s github/npm/sidecar branches
(features/install.tmpl.bash) plus the `ver__*` helpers (lib/ver.bash), so the
generator can resolve a version input (`stable`/`latest`/`X`/`X.Y`/exact) to the
concrete version a real install would land on — computed live against the real
endpoint, so version-outcome expectations stay accurate as upstreams publish new
releases (no hardcoded pins to churn).

Package-manager resolution is *not* here: PM-available versions are image-
specific and are verified in-container by reusing `ospkg__resolve_version` (see
the Wave 3.5 plan, Part B.1).

Pure helpers (`extract_version`, `is_final`, `resolve_from_list`) are network-
free and unit-tested directly. The endpoint resolvers do live HTTP; tests cover
them with recorded fixtures plus a couple of live smoke checks. GitHub requests
are authenticated from `GITHUB_TOKEN`/`GH_TOKEN`/`gh auth token`; the token is
never emitted — `mask()` scrubs it from any surfaced string.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import urllib.error
import urllib.request
from dataclasses import dataclass

# ver__extract_version --keep-suffix (default, text-scanning mode): a dot-
# separated version with an optional inline label and separator suffixes, or a
# bare integer fallback. Matches the first occurrence, mirroring `grep -oE ...
# | head -1`.
_VERSION_DOTTED = re.compile(
    r"[0-9]+\.[0-9]+(?:\.[0-9]+)*(?:[a-zA-Z][a-zA-Z0-9]*)?(?:[._+~-][0-9A-Za-z]+)*",
)
_VERSION_BARE = re.compile(
    r"[0-9]+(?:[a-zA-Z][a-zA-Z0-9]*)?(?:[._+~-][0-9A-Za-z]+)*",
)
# ver__semver_is_final: purely numeric dot-separated, optional +build metadata.
_SEMVER_FINAL = re.compile(r"^[0-9]+(\.[0-9]+)*(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$")

_GITHUB_API = "https://api.github.com"


def extract_version(text: str, *, keep_suffix: bool = True) -> str:
    """Extract the first version from `text` (mirrors ver__extract_version)."""
    dotted = (
        _VERSION_DOTTED if keep_suffix else re.compile(r"[0-9]+\.[0-9]+(?:\.[0-9]+)*")
    )
    match = dotted.search(text)
    if match:
        return match.group(0)
    fallback = _VERSION_BARE.search(text) if keep_suffix else re.search(r"[0-9]+", text)
    return fallback.group(0) if fallback else ""


def is_final(version: str) -> bool:
    """Return whether `version` is a final (non-prerelease) semver.

    Mirrors `ver__semver_is_final` on the `v`-stripped bare version.
    """
    return bool(_SEMVER_FINAL.match(version.lstrip("v")))


def _bare(tag: str) -> str:
    """Strip a leading non-numeric prefix (`v`, `jq-`, ...) from a tag."""
    return re.sub(r"^[^0-9]*", "", tag)


def resolve_from_list(versions: list[str], spec: str) -> str | None:
    """Resolve `spec` against a newest-first version list (ver__resolve_from_list).

    `stable`/``: first final version. `latest`: first entry. A numeric spec:
    exact bare match first, else first final version whose bare part is
    `spec`-prefixed (followed by `.`/`-`/end). Returns the entry verbatim, or
    None when nothing matches.
    """
    if not versions:
        return None
    if spec in ("", "stable"):
        return next((v for v in versions if is_final(_bare(v))), None)
    if spec == "latest":
        return versions[0]
    return _resolve_numeric(versions, spec)


def _prefix_match(bare: str, norm: str) -> bool:
    """Whether `bare` equals `norm` or starts with it at a `.`/`-` boundary."""
    boundary = bare[len(norm) : len(norm) + 1]
    return bare == norm or (bare.startswith(norm) and boundary in (".", "-"))


def _resolve_numeric(versions: list[str], spec: str) -> str | None:
    """Resolve a numeric spec against finals: exact bare match, else prefix."""
    norm = extract_version(spec, keep_suffix=True)
    if not norm:
        return None
    finals = [v for v in versions if is_final(_bare(v))]
    exact = next((v for v in finals if _bare(v) == norm), None)
    if exact is not None:
        return exact
    return next((v for v in finals if _prefix_match(_bare(v), norm)), None)


# --- endpoint spec ----------------------------------------------------------


@dataclass(frozen=True)
class VersionEndpoint:
    """Where and how to resolve a feature's version input.

    `uri` is the framework's `VERSION_URI` default: the GitHub API base
    (`https://api.github.com/repos/<repo>`), the npm registry package doc, or
    the sidecar file URL. `pattern` is the sidecar `[version]` template.
    """

    resolution: str
    uri: str
    pattern: str = ""
    tag_prefix: str = ""


def endpoint_for(
    resolution: str,
    *,
    gh_repo: str = "",
    npm_package: str = "",
    version_uri: str = "",
    version_pattern: str = "",
    tag_prefix: str = "",
) -> VersionEndpoint | None:
    """Build a `VersionEndpoint` from a feature's version metadata.

    Mirrors `metadata.shared.yaml`'s `version_uri` default derivation. Returns
    None for resolutions with no live endpoint (`none`/`git_ref`/empty).
    """
    if resolution in ("github_release", "github_tag"):
        uri = version_uri or f"{_GITHUB_API}/repos/{gh_repo}"
        return VersionEndpoint(resolution, uri, tag_prefix=tag_prefix)
    if resolution == "npm":
        uri = version_uri or f"https://registry.npmjs.org/{npm_package}"
        return VersionEndpoint(resolution, uri)
    if resolution == "sidecar":
        return VersionEndpoint(resolution, version_uri, pattern=version_pattern)
    return None


# --- token handling / masking -----------------------------------------------


def _github_token() -> str:
    """Resolve a GitHub token from env, falling back to `gh auth token`."""
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        return token.strip()
    if shutil.which("gh"):
        result = subprocess.run(
            ["gh", "auth", "token"],
            capture_output=True,
            text=True,
            check=False,
        )
        return result.stdout.strip()
    return ""


def mask(text: str) -> str:
    """Scrub any resolved GitHub token from `text` before it is surfaced."""
    token = _github_token()
    return text.replace(token, "***") if token else text


# --- HTTP -------------------------------------------------------------------


def _http_json(url: str, *, token: str = "") -> object:
    headers = {
        "User-Agent": "devfeats-test-gen",
        "Accept": "application/vnd.github+json",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)  # noqa: S310 (https only)
    with urllib.request.urlopen(request, timeout=30) as response:  # noqa: S310
        return json.loads(response.read().decode("utf-8"))


def _http_text(url: str) -> str:
    headers = {"User-Agent": "devfeats-test-gen"}
    request = urllib.request.Request(url, headers=headers)  # noqa: S310
    with urllib.request.urlopen(request, timeout=30) as response:  # noqa: S310
        return response.read().decode("utf-8", errors="replace")


def _fetch_json(url: str, *, token: str = "") -> object:
    """Fetch+parse JSON, returning None on any network/parse failure."""
    try:
        return _http_json(url, token=token)
    except (urllib.error.URLError, TimeoutError, ValueError):
        return None


# --- github -----------------------------------------------------------------


def _github_release_tags(uri: str, token: str, *, pages: int = 5) -> list[str]:
    """Release tag names, newest-first, paginated (non-draft, any prerelease)."""
    tags: list[str] = []
    for page in range(1, pages + 1):
        try:
            data = _http_json(f"{uri}/releases?per_page=100&page={page}", token=token)
        except (urllib.error.URLError, TimeoutError):
            break
        if not isinstance(data, list) or not data:
            break
        tags.extend(
            str(r["tag_name"])
            for r in data
            if isinstance(r, dict) and not r.get("draft") and r.get("tag_name")
        )
        if len(data) < 100:
            break
    return tags


def _github_git_tags(uri: str, token: str, *, pages: int = 5) -> list[str]:
    """Git tag names, newest-first, paginated (tags API fallback)."""
    tags: list[str] = []
    for page in range(1, pages + 1):
        try:
            data = _http_json(f"{uri}/tags?per_page=100&page={page}", token=token)
        except (urllib.error.URLError, TimeoutError):
            break
        if not isinstance(data, list) or not data:
            break
        tags.extend(
            str(t["name"]) for t in data if isinstance(t, dict) and t.get("name")
        )
        if len(data) < 100:
            break
    return tags


def _github_prefixed(tags: list[str], prefix: str) -> list[str]:
    return [t for t in tags if not prefix or t.startswith(prefix)]


def _resolve_github(endpoint: VersionEndpoint, spec: str) -> str | None:
    token = _github_token()
    uri = endpoint.uri
    prefix = endpoint.tag_prefix
    use_releases = endpoint.resolution == "github_release"

    # `stable`/`latest` fast paths mirror the bash resolver's dedicated calls,
    # but the generic list-based resolution below is equivalent and simpler; we
    # gather candidate tags newest-first and resolve against them.
    tags: list[str] = []
    if use_releases:
        if spec in ("", "stable") and not prefix:
            try:
                latest = _http_json(f"{uri}/releases/latest", token=token)
                if isinstance(latest, dict) and latest.get("tag_name"):
                    tag = str(latest["tag_name"])
                    return extract_version(tag, keep_suffix=True) or None
            except (urllib.error.URLError, TimeoutError):
                pass  # fall through to list-based resolution / tags fallback
        tags = _github_prefixed(_github_release_tags(uri, token), prefix)

    if not tags:
        tags = _github_prefixed(_github_git_tags(uri, token), prefix)
    if not tags:
        return None

    resolved_tag = resolve_from_list(tags, spec)
    if resolved_tag is None:
        return None
    return extract_version(resolved_tag, keep_suffix=True) or None


# --- npm --------------------------------------------------------------------


def _resolve_npm(endpoint: VersionEndpoint, spec: str) -> str | None:
    doc = _fetch_json(endpoint.uri)
    if not isinstance(doc, dict):
        return None
    dist_tags = doc.get("dist-tags", {})
    if spec in ("", "stable"):
        return dist_tags.get("stable") or dist_tags.get("latest") or None
    if spec in dist_tags:  # a dist-tag name like "next"/"beta"
        return dist_tags[spec]
    times = doc.get("time", {})
    published = sorted(
        (v for v in doc.get("versions", {}) if v not in ("created", "modified")),
        key=lambda v: times.get(v, ""),
        reverse=True,
    )
    if spec == "latest":
        return published[0] if published else None
    return resolve_from_list(published, spec)


# --- sidecar ----------------------------------------------------------------


def _sidecar_match(word: str, prefix: str, suffix: str) -> str | None:
    """Return the `[version]` slice of `word` for the pattern, or None."""
    if prefix and not word.startswith(prefix):
        return None
    value = word[len(prefix) :]
    if suffix:
        if len(value) <= len(suffix) or not value.endswith(suffix):
            return None
        value = value[: len(value) - len(suffix)]
    return value if value[:1].isdigit() else None


def _sidecar_versions(text: str, pattern: str) -> list[str]:
    """Extract versions from a sidecar file (ver__resolve_from_sidecar's awk)."""
    prefix, _, suffix = pattern.partition("[version]")
    cleaned = re.sub(r"<[^>]*>", " ", text)  # strip HTML tags
    found = [
        v
        for word in cleaned.split()
        if (v := _sidecar_match(word, prefix, suffix)) is not None
    ]
    # sort -V -r (newest first) via a semver-ish key.
    found.sort(key=_version_sort_key, reverse=True)
    return found


def _version_sort_key(version: str) -> list:
    return [
        (0, int(chunk)) if chunk.isdigit() else (1, chunk)
        for chunk in re.split(r"[._+~-]", version)
    ]


def _resolve_sidecar(endpoint: VersionEndpoint, spec: str) -> str | None:
    if not endpoint.pattern or "[version]" not in endpoint.pattern:
        return None
    try:
        text = _http_text(endpoint.uri)
    except (urllib.error.URLError, TimeoutError):
        return None
    versions = _sidecar_versions(text, endpoint.pattern)
    return resolve_from_list(versions, spec)


# --- dispatch ---------------------------------------------------------------


def resolve(endpoint: VersionEndpoint, spec: str) -> str | None:
    """Resolve `spec` against `endpoint`, returning the bare version or None.

    Live HTTP; returns None on any network/parse failure so callers can skip a
    scenario rather than crash.
    """
    if endpoint.resolution in ("github_release", "github_tag"):
        return _resolve_github(endpoint, spec)
    if endpoint.resolution == "npm":
        return _resolve_npm(endpoint, spec)
    if endpoint.resolution == "sidecar":
        return _resolve_sidecar(endpoint, spec)
    return None
