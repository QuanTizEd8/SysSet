"""Tests for the host-side upstream version resolvers.

Pure helpers and the resolution logic are tested deterministically against
recorded fixture responses (HTTP monkeypatched); a few resilient live smoke
tests exercise the real endpoints when the network is reachable.
"""

from __future__ import annotations

import pytest
from proman.test.gen import version_resolve as vr

# --- pure helpers -----------------------------------------------------------


def test_extract_version_strips_prefix_and_keeps_suffix() -> None:
    """Leading non-numeric prefixes are stripped; suffixes kept by default."""
    assert vr.extract_version("v1.2.3") == "1.2.3"
    assert vr.extract_version("jq-1.7.1") == "1.7.1"
    assert vr.extract_version("go version go1.26.4 linux") == "1.26.4"
    assert vr.extract_version("v1.2.3-rc1") == "1.2.3-rc1"
    assert vr.extract_version("3.13.0a4") == "3.13.0a4"
    assert vr.extract_version("no version here") == ""


def test_is_final() -> None:
    """Pure numeric (optionally +build) is final; prereleases are not."""
    assert vr.is_final("1.2.3")
    assert vr.is_final("v1.2.3")
    assert vr.is_final("1.2.3+build.5")
    assert not vr.is_final("1.2.3-rc1")
    assert not vr.is_final("3.13.0a4")


def test_resolve_from_list_stable_picks_first_final() -> None:
    """`stable` returns the first non-prerelease entry, newest-first."""
    versions = ["2.0.0-rc1", "1.9.0", "1.8.0"]
    assert vr.resolve_from_list(versions, "stable") == "1.9.0"


def test_resolve_from_list_latest_is_first() -> None:
    """`latest` returns the first entry regardless of prerelease status."""
    versions = ["2.0.0-rc1", "1.9.0"]
    assert vr.resolve_from_list(versions, "latest") == "2.0.0-rc1"


def test_resolve_from_list_exact_before_prefix() -> None:
    """An exact bare match wins over a longer prefix match (5.9 vs 5.9.1)."""
    versions = ["5.9.1", "5.9", "5.8"]
    assert vr.resolve_from_list(versions, "5.9") == "5.9"


def test_resolve_from_list_partial_prefix() -> None:
    """A partial spec resolves to the newest final version under it."""
    versions = ["1.2.5", "1.2.4", "1.20.0", "1.1.0"]
    assert vr.resolve_from_list(versions, "1.2") == "1.2.5"
    # `1.2` must NOT match `1.20.0` (boundary is `.`/`-`/end).
    assert vr.resolve_from_list(["1.20.0", "1.1.0"], "1.2") is None


def test_resolve_from_list_tagged_entries() -> None:
    """Bare-version comparison sees through `v`/name prefixes on each entry."""
    versions = ["v2.1.0", "v2.0.0"]
    assert vr.resolve_from_list(versions, "2.0") == "v2.0.0"


def test_resolve_from_list_empty() -> None:
    """An empty list resolves to None."""
    assert vr.resolve_from_list([], "stable") is None


# --- sidecar parsing --------------------------------------------------------


def test_sidecar_versions_extracts_and_sorts() -> None:
    """Filenames matching the pattern yield versions, newest-first."""
    text = (
        "abc  zsh-5.9.1.tar.xz\n"
        "def  zsh-5.9.tar.xz\n"
        "ghi  zsh-5.8.tar.xz\n"
        "jkl  zsh-doc-5.9.tar.xz\n"
    )
    versions = vr._sidecar_versions(text, "zsh-[version].tar.xz")
    assert versions == ["5.9.1", "5.9", "5.8"]


def test_sidecar_versions_strips_html() -> None:
    """HTML tags around href filenames are stripped before matching."""
    text = '<a href="foo-1.2.3.tar.gz">foo-1.2.3.tar.gz</a>'
    assert vr._sidecar_versions(text, "foo-[version].tar.gz") == ["1.2.3"]


# --- endpoint derivation ----------------------------------------------------


def test_endpoint_for_github() -> None:
    """github_release derives the API base from gh_repo."""
    ep = vr.endpoint_for("github_release", gh_repo="jqlang/jq")
    assert ep is not None
    assert ep.uri == "https://api.github.com/repos/jqlang/jq"


def test_endpoint_for_npm() -> None:
    """Npm derives the registry doc URL from the package name."""
    ep = vr.endpoint_for("npm", npm_package="@devcontainers/cli")
    assert ep is not None
    assert ep.uri == "https://registry.npmjs.org/@devcontainers/cli"


def test_endpoint_for_sidecar() -> None:
    """Sidecar uses the explicit version_uri + pattern."""
    ep = vr.endpoint_for(
        "sidecar",
        version_uri="https://www.zsh.org/pub/SHA256SUM",
        version_pattern="zsh-[version].tar.xz",
    )
    assert ep is not None
    assert ep.pattern == "zsh-[version].tar.xz"


def test_endpoint_for_none() -> None:
    """Resolutions with no live endpoint return None."""
    assert vr.endpoint_for("none") is None
    assert vr.endpoint_for("git_ref") is None


# --- masking ----------------------------------------------------------------


def test_mask_scrubs_token(monkeypatch: pytest.MonkeyPatch) -> None:
    """A resolved token is scrubbed from any surfaced string."""
    monkeypatch.setenv("GITHUB_TOKEN", "ghp_secretvalue123")
    masked = vr.mask("failed with ghp_secretvalue123 in header")
    assert masked == "failed with *** in header"


def test_mask_noop_without_token(monkeypatch: pytest.MonkeyPatch) -> None:
    """With no token, masking is a no-op."""
    monkeypatch.delenv("GITHUB_TOKEN", raising=False)
    monkeypatch.delenv("GH_TOKEN", raising=False)
    monkeypatch.setattr(vr.shutil, "which", lambda _: None)
    assert vr.mask("nothing to hide") == "nothing to hide"


# --- resolver logic against recorded fixtures (no network) ------------------


def test_resolve_github_release_stable_uses_latest_endpoint(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """github_release `stable` reads /releases/latest and extracts the version."""
    monkeypatch.setattr(vr, "_github_token", lambda: "")

    def fake_json(url: str, *, token: str = "") -> object:  # noqa: ARG001
        assert url.endswith("/releases/latest")
        return {"tag_name": "jq-1.8.1"}

    monkeypatch.setattr(vr, "_http_json", fake_json)
    ep = vr.endpoint_for("github_release", gh_repo="jqlang/jq")
    assert vr.resolve(ep, "stable") == "1.8.1"


def test_resolve_github_release_specific_paginates_releases(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A specific spec resolves against the paginated release list."""
    monkeypatch.setattr(vr, "_github_token", lambda: "")

    def fake_json(url: str, *, token: str = "") -> object:  # noqa: ARG001
        if "page=1" in url:
            return [
                {"tag_name": "v2.1.0", "draft": False},
                {"tag_name": "v2.0.0", "draft": False},
                {"tag_name": "v1.9.0", "draft": False},
            ]
        return []

    monkeypatch.setattr(vr, "_http_json", fake_json)
    ep = vr.endpoint_for("github_release", gh_repo="o/r")
    assert vr.resolve(ep, "2.0") == "2.0.0"


def test_resolve_npm_stable_prefers_stable_dist_tag(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Npm `stable` prefers the `stable` dist-tag, else `latest`."""

    def fake_json(url: str, *, token: str = "") -> object:  # noqa: ARG001
        return {"dist-tags": {"stable": "2.1.153", "latest": "2.2.0"}}

    monkeypatch.setattr(vr, "_http_json", fake_json)
    ep = vr.endpoint_for("npm", npm_package="pkg")
    assert vr.resolve(ep, "stable") == "2.1.153"


def test_resolve_npm_specific_prefix(monkeypatch: pytest.MonkeyPatch) -> None:
    """Npm resolves a numeric prefix against published versions, newest-first."""

    def fake_json(url: str, *, token: str = "") -> object:  # noqa: ARG001
        return {
            "dist-tags": {"latest": "1.3.0"},
            "versions": {"1.2.3": {}, "1.2.4": {}, "1.3.0": {}},
            "time": {
                "1.2.3": "2024-01-01",
                "1.2.4": "2024-02-01",
                "1.3.0": "2024-03-01",
            },
        }

    monkeypatch.setattr(vr, "_http_json", fake_json)
    ep = vr.endpoint_for("npm", npm_package="pkg")
    assert vr.resolve(ep, "1.2") == "1.2.4"


def test_resolve_sidecar_stable(monkeypatch: pytest.MonkeyPatch) -> None:
    """Sidecar resolution parses the fetched file and resolves the spec."""
    monkeypatch.setattr(
        vr,
        "_http_text",
        lambda _url: "a  zsh-5.9.1.tar.xz\nb  zsh-5.9.tar.xz\n",
    )
    ep = vr.endpoint_for(
        "sidecar",
        version_uri="https://example/SHA256SUM",
        version_pattern="zsh-[version].tar.xz",
    )
    assert vr.resolve(ep, "stable") == "5.9.1"
    assert vr.resolve(ep, "5.9") == "5.9"


# --- live smoke tests (skipped when the endpoint is unreachable) ------------


@pytest.mark.parametrize(
    ("resolution", "kwargs", "spec"),
    [
        ("github_release", {"gh_repo": "jqlang/jq"}, "stable"),
        ("npm", {"npm_package": "@devcontainers/cli"}, "stable"),
        (
            "sidecar",
            {
                "version_uri": "https://www.zsh.org/pub/SHA256SUM",
                "version_pattern": "zsh-[version].tar.xz",
            },
            "stable",
        ),
    ],
)
def test_live_resolution_smoke(resolution: str, kwargs: dict, spec: str) -> None:
    """Live endpoints resolve `stable` to a plausible semver (or skip if offline)."""
    ep = vr.endpoint_for(resolution, **kwargs)
    assert ep is not None
    resolved = vr.resolve(ep, spec)
    if resolved is None:
        pytest.skip(f"{resolution} endpoint unreachable — skipping live smoke test")
    assert vr.is_final(resolved), f"expected a final version, got {resolved!r}"
