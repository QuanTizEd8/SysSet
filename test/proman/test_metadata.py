"""Tests for proman.metadata — the central feature metadata module."""

from __future__ import annotations

from pathlib import Path

import proman.config as cfg
import pytest
import yaml
from proman.metadata import MetadataLoader
from proman.schema_bundle import clear_validator_cache, get_validator
from proman.when_util import serialize_path_entries, serialize_value_entries

_REPO_ROOT = Path(__file__).resolve().parents[2]

_MINIMAL_SHARED = """\
_lifecycle_key_prefix: myowner-test--
_env_vars:
  _FEAT_SHARE_DIR_ROOT: /usr/local/share/myowner/test/${{ id }}$
options:
  shared_opt:
    type: string
    default: hello
    description: Injected shared option.
  locked_opt:
    type: string
    default: from-shared
    description: Shared option that must not be overridden.
"""


def _minimal_feature_metadata(**overrides: object) -> dict:
    """Return metadata.yaml content that passes schema validation."""
    base = {
        "version": "1.0.0",
        "name": "Test Feature",
        "description": "Short description.",
        "_long_description": "Longer description for docs.",
        "keywords": ["test"],
        "options": {},
    }
    base.update(overrides)
    return base


@pytest.fixture(autouse=True)
def _reset_config_singleton() -> None:
    """Ensure isolated tests do not leave a patched config or validator cached."""
    yield
    cfg.clear_cache()
    clear_validator_cache()


_MINIMAL_MAIN = """\
name: Test
name_slug: test
owner: myowner
owner_slug: myowner
namespace: myowner/test
repo_url: https://github.com/myowner/test
oci_base: ghcr.io/myowner/test
docs:
  website_base_url: https://example.com/docs
path:
  features: features
  library: lib
  shared_metadata: features/metadata.shared.yaml
  metadata_schema: features/metadata.schema.json
filename:
  feature_metadata: metadata.yaml
features:
  lifecycle_hook_keys:
    - onCreateCommand
"""


@pytest.fixture
def repo_root() -> Path:
    """Return the repository root path."""
    return Path(__file__).resolve().parents[2]


@pytest.fixture
def features_dir(repo_root: Path) -> Path:
    """Return the path to the features/ directory."""
    return repo_root / "features"


def _write_test_repo(
    tmp_path: Path,
    *,
    feature_metadata: dict | None = None,
    shared_yaml: str = _MINIMAL_SHARED,
) -> Path:
    """Create a minimal repo layout under *tmp_path* for MetadataLoader tests."""
    proman_dir = tmp_path / ".config" / "proman"
    proman_dir.mkdir(parents=True)
    (proman_dir / "_main.yaml").write_text(_MINIMAL_MAIN, encoding="utf-8")

    features = tmp_path / "features"
    features.mkdir()
    (features / "metadata.shared.yaml").write_text(shared_yaml, encoding="utf-8")

    schema_src = (
        Path(__file__).resolve().parents[2] / "features" / "metadata.schema.json"
    )
    (features / "metadata.schema.json").write_text(
        schema_src.read_text(encoding="utf-8"),
        encoding="utf-8",
    )
    manifest_src = (
        Path(__file__).resolve().parents[2]
        / "features"
        / "install-os-pkg"
        / "manifest.schema.json"
    )
    manifest_dest = features / "install-os-pkg"
    manifest_dest.mkdir(parents=True)
    (manifest_dest / "manifest.schema.json").write_text(
        manifest_src.read_text(encoding="utf-8"),
        encoding="utf-8",
    )

    if feature_metadata is not None:
        feat_dir = features / "test-feature"
        feat_dir.mkdir()
        (feat_dir / "metadata.yaml").write_text(
            yaml.dump(feature_metadata),
            encoding="utf-8",
        )
    return tmp_path


def _loader_for(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> MetadataLoader:
    monkeypatch.setattr("proman.config.git_repo_root", lambda: tmp_path)
    cfg.clear_cache()
    return MetadataLoader()


# ── load (integration against real repo) ─────────────────────────────────────


def test_load_sets_id_and_oci_ref(features_dir: Path) -> None:
    """MetadataLoader sets ``id`` and ``_oci_ref`` on loaded features."""
    candidates = sorted(features_dir.glob("*/metadata.yaml"))
    assert candidates, "No real features found — check features/ directory."
    feat_id = candidates[0].parent.name
    result = MetadataLoader().load(feat_id)[feat_id]
    assert result["id"] == feat_id
    assert result["_oci_ref"].startswith("ghcr.io/")
    assert feat_id in result["_oci_ref"]


def test_load_returns_all_valid_features() -> None:
    """MetadataLoader.load() returns a non-empty dict keyed by feature IDs."""
    all_meta = MetadataLoader().load()
    assert len(all_meta) > 0
    for feat_id, meta in all_meta.items():
        assert meta["id"] == feat_id
        assert "_oci_ref" in meta


def test_load_injects_shared_options(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Shared options from the real metadata.shared.yaml appear in a feature."""
    root = _write_test_repo(
        tmp_path,
        feature_metadata=_minimal_feature_metadata(),
        shared_yaml=(_REPO_ROOT / "features" / "metadata.shared.yaml").read_text(
            encoding="utf-8"
        ),
    )
    result = _loader_for(root, monkeypatch).load("test-feature")["test-feature"]
    assert "log_level" in result["options"]


# ── load (isolated tmp_path repo) ─────────────────────────────────────────────


def test_load_missing_metadata_raises(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Missing metadata.yaml raises ValueError."""
    _write_test_repo(tmp_path)
    loader = _loader_for(tmp_path, monkeypatch)
    with pytest.raises(ValueError, match="Metadata file not found"):
        loader.load("ghost")


def test_load_invalid_yaml_raises(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Malformed YAML raises ValueError."""
    root = _write_test_repo(tmp_path)
    feat_dir = root / "features" / "bad-yaml"
    feat_dir.mkdir()
    (feat_dir / "metadata.yaml").write_text("key: [\n  invalid", encoding="utf-8")
    loader = _loader_for(tmp_path, monkeypatch)
    with pytest.raises(ValueError, match="Error reading metadata"):
        loader.load("bad-yaml")


def test_load_not_a_mapping_raises(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """YAML that parses to a non-dict raises ValueError."""
    root = _write_test_repo(
        tmp_path,
        feature_metadata=["not", "a", "dict"],  # type: ignore[arg-type]
    )
    loader = _loader_for(root, monkeypatch)
    with pytest.raises(ValueError, match="not a YAML mapping"):
        loader.load("test-feature")


def test_load_rejects_repo_modifiers_in_method_package(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """`method-package` manifests must not add repos/keys/PPAs/taps/etc."""
    root = _write_test_repo(
        tmp_path,
        feature_metadata=_minimal_feature_metadata(
            _options={"method": {"package": {}}},
            _dependencies={
                "run": {
                    "method-package": {
                        "apt": {
                            "repos": ["deb https://example.test stable main"],
                        },
                        "packages": ["tool"],
                    }
                }
            },
        ),
        shared_yaml=(_REPO_ROOT / "features" / "metadata.shared.yaml").read_text(
            encoding="utf-8"
        ),
    )
    loader = _loader_for(root, monkeypatch)
    with pytest.raises(ValueError, match="method-package must not add or alter"):
        loader.load("test-feature")


def test_load_rejects_upstream_package_pm_without_source_config(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Each declared upstream-package PM family must actually alter package sources."""
    root = _write_test_repo(
        tmp_path,
        feature_metadata=_minimal_feature_metadata(
            _options={
                "method": {"upstream-package": {"when": {"plat.pm": ["apt", "brew"]}}}
            },
            _dependencies={
                "run": {
                    "method-upstream-package": {
                        "apt": {
                            "repos": ["deb https://example.test stable main"],
                        },
                        "packages": [{"name": "tool", "version": "{feat.pm_version}"}],
                    }
                }
            },
        ),
        shared_yaml=(_REPO_ROOT / "features" / "metadata.shared.yaml").read_text(
            encoding="utf-8"
        ),
    )
    loader = _loader_for(root, monkeypatch)
    with pytest.raises(
        ValueError, match="adds no package-source configuration for brew"
    ):
        loader.load("test-feature")


def test_load_rejects_method_option_when_broader_than_manifest_support(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Auto-resolution `when` must not be broader than manifest install support."""
    root = _write_test_repo(
        tmp_path,
        feature_metadata=_minimal_feature_metadata(
            _options={"method": {"package": {"when": {"plat.pm": ["apt", "dnf"]}}}},
            _dependencies={
                "run": {
                    "method-package": {
                        "packages": [
                            {
                                "name": "tool",
                                "when": {"plat.pm": "apt", "os.id": "debian"},
                            },
                            {
                                "name": "tool",
                                "when": {"plat.pm": "dnf", "os.id": "fedora"},
                            },
                        ]
                    }
                }
            },
        ),
        shared_yaml=(_REPO_ROOT / "features" / "metadata.shared.yaml").read_text(
            encoding="utf-8"
        ),
    )
    loader = _loader_for(root, monkeypatch)
    with pytest.raises(
        ValueError,
        match=r"_options\.method\.package\.when clause .* broader than .* add os\.id",
    ):
        loader.load("test-feature")


def test_load_rejects_method_option_when_missing_version_guard(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Expanded OS clauses still need version guards when the manifest requires them."""
    root = _write_test_repo(
        tmp_path,
        feature_metadata=_minimal_feature_metadata(
            _options={
                "method": {
                    "package": {
                        "when": [
                            {
                                "plat.pm": "apt",
                                "os.id": ["debian", "ubuntu"],
                            }
                        ]
                    }
                }
            },
            _dependencies={
                "run": {
                    "method-package": {
                        "packages": [
                            {
                                "name": "tool",
                                "when": {"plat.pm": "apt", "os.id": "debian"},
                            },
                            {
                                "name": "tool",
                                "when": {
                                    "plat.pm": "apt",
                                    "os.id": "ubuntu",
                                    "os.version_id": ["25.04", "25.10"],
                                },
                            },
                        ]
                    }
                }
            },
        ),
        shared_yaml=(_REPO_ROOT / "features" / "metadata.shared.yaml").read_text(
            encoding="utf-8"
        ),
    )
    loader = _loader_for(root, monkeypatch)
    with pytest.raises(
        ValueError,
        match=(
            r"_options\.method\.package\.when clause "
            r".* broader than .* add os\.version_id"
        ),
    ):
        loader.load("test-feature")


def test_load_merges_shared_options(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Shared options are merged into the feature's options dict."""
    root = _write_test_repo(tmp_path, feature_metadata=_minimal_feature_metadata())
    result = _loader_for(root, monkeypatch).load("test-feature")["test-feature"]
    assert "shared_opt" in result["options"]


def test_load_feature_options_override_shared(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Feature-defined options take precedence over shared metadata defaults."""
    metadata = _minimal_feature_metadata(
        options={
            "locked_opt": {"type": "string", "default": "oops", "description": "x"},
        },
    )
    root = _write_test_repo(tmp_path, feature_metadata=metadata)
    result = _loader_for(root, monkeypatch).load("test-feature")["test-feature"]
    assert result["options"]["locked_opt"]["default"] == "oops"


def test_load_applies_shared_option_conditions(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Shared options with ``_apply_when`` are injected only when condition holds."""
    real_shared = (_REPO_ROOT / "features" / "metadata.shared.yaml").read_text(
        encoding="utf-8"
    )
    root = _write_test_repo(
        tmp_path,
        # fetch_headers is gated on _options.user_file_fetch: true
        feature_metadata=_minimal_feature_metadata(_options={"user_file_fetch": True}),
        shared_yaml=real_shared,
    )
    # Add a second feature that lacks user_file_fetch
    no_fetch_dir = tmp_path / "features" / "test-feature-no-fetch"
    no_fetch_dir.mkdir()
    (no_fetch_dir / "metadata.yaml").write_text(
        yaml.dump(_minimal_feature_metadata()), encoding="utf-8"
    )
    loader = _loader_for(root, monkeypatch)
    with_fetch = loader.load("test-feature")["test-feature"]
    without_fetch = loader.load("test-feature-no-fetch")["test-feature-no-fetch"]
    assert "fetch_headers" in with_fetch["options"]
    assert "fetch_headers" not in without_fetch["options"]


def test_load_emits_ospkg_manifest_options_via_pyserials() -> None:
    """``ospkg_manifest_*`` options come from shared-metadata pyserials, not Python."""
    jq = MetadataLoader().load("install-jq")["install-jq"]
    assert "ospkg_manifest_method_package_run" in jq["options"]
    pkg_desc = jq["options"]["ospkg_manifest_method_package_run"]["description"]
    assert "METHOD=package" in pkg_desc
    assert "runtime" in pkg_desc
    assert "\n" in jq["options"]["ospkg_manifest_method_package_run"]["default"]
    assert "jq" in jq["options"]["ospkg_manifest_method_package_run"]["default"]
    assert (
        "_normalize_escapes" not in jq["options"]["ospkg_manifest_method_package_run"]
    )

    bundle = MetadataLoader().load("install-os-pkg-bundle")["install-os-pkg-bundle"]
    archive_desc = bundle["options"]["ospkg_manifest_option_archive_tools"][
        "description"
    ]
    build_desc = bundle["options"]["ospkg_manifest_option_build_tools"]["description"]
    assert archive_desc != build_desc
    assert "archive_tools" in archive_desc
    assert "build_tools" in build_desc

    pnpm = MetadataLoader().load("install-pnpm")["install-pnpm"]
    assert not any(k.startswith("ospkg_manifest_") for k in pnpm["options"])


def test_load_substitutes_template_variables(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """${{ _project }} and ${{ _env_vars }} templates are expanded."""
    metadata = _minimal_feature_metadata(
        description="Test ${{ _project.name_slug }}$.",
        entrypoint={
            "command": (
                "${{ _env_vars._FEAT_SHARE_DIR_ROOT }}$/entrypoint.sh "
                "${containerWorkspaceFolder}"
            ),
        },
        onCreateCommand={
            "run": {
                "command": (
                    "sh ${{ _env_vars._FEAT_SHARE_DIR_ROOT }}$/on-create.sh || true"
                ),
                "description": "Run on-create hook.",
            },
        },
    )
    root = _write_test_repo(tmp_path, feature_metadata=metadata)
    result = _loader_for(root, monkeypatch).load("test-feature")["test-feature"]
    expected_share = "/usr/local/share/myowner/test/test-feature"
    assert result["entrypoint"] == {
        "command": f"{expected_share}/entrypoint.sh ${{containerWorkspaceFolder}}",
    }
    expected_lc_key = "myowner-test--run"
    assert list(result["onCreateCommand"].keys()) == [expected_lc_key]
    assert result["onCreateCommand"][expected_lc_key]["command"] == (
        f"sh {expected_share}/on-create.sh || true"
    )
    assert result["description"] == "Test test."


def test_schema_rejects_undeclared_method_dependency() -> None:
    """Schema if/then requires `_options.method.<id>` when `method-<id>` is declared."""
    metadata = _minimal_feature_metadata(
        _dependencies={
            "run": {"method-cargo": {"packages": ["rustc"]}},
        },
    )
    errors = list(get_validator().iter_errors(metadata))
    assert errors


def test_schema_rejects_option_manifest_under_build() -> None:
    """Schema rejects `option-*` manifest groups under `_dependencies.build`."""
    metadata = _minimal_feature_metadata(
        _dependencies={
            "build": {"option-tools": {"packages": ["make"]}},
        },
    )
    errors = list(get_validator().iter_errors(metadata))
    assert errors


def test_schema_rejects_unknown_method_dependency_key() -> None:
    """Schema rejects unknown `method-*` suffixes via `patternProperties`."""
    metadata = _minimal_feature_metadata(
        _options={"method": {"package": {}}},
        _dependencies={
            "run": {"method-not-a-method": {"packages": ["jq"]}},
        },
    )
    errors = list(get_validator().iter_errors(metadata))
    assert errors


def _when_spec_errors(when: object) -> list:
    metadata = _minimal_feature_metadata(
        _options={
            "method": {
                "binary": {
                    "when": when,
                },
            },
        },
    )
    return list(get_validator().iter_errors(metadata))


def test_schema_when_rejects_deprecated_version_lte() -> None:
    """Schema rejects unqualified legacy when keys such as version_lte."""
    errors = _when_spec_errors({"version_lte": "1.0.0"})
    assert errors
    assert any("version_lte" in e.message for e in errors)


def test_schema_when_accepts_semver_and_platform_keys() -> None:
    """Schema accepts qualified feat/os/plat when keys."""
    errors = _when_spec_errors(
        {
            "feat.version": {"lte": "1.0.0"},
            "plat.machine_release": "amd64",
            "os.version_id_major": ["8", "9", "10"],
            "os.version_codename": ["sid", "trixie"],
            "os.version_id": "22.04",
        }
    )
    assert not errors


def test_schema_when_accepts_or_groups() -> None:
    """Schema accepts OR-array when specs."""
    errors = _when_spec_errors(
        [{"plat.machine_release": "amd64"}, {"plat.kernel": "darwin"}]
    )
    assert not errors


def test_schema_when_rejects_deprecated_key_in_or_group() -> None:
    """Schema rejects deprecated keys inside OR groups."""
    errors = _when_spec_errors([{"arch": "amd64"}, {"version_lte": "1.0.0"}])
    assert errors


def test_schema_when_rejects_unknown_key() -> None:
    """Schema rejects unqualified or unknown when keys."""
    errors = _when_spec_errors({"bad-key": "x"})
    assert errors


def test_schema_binary_src_when_rejects_invalid_key() -> None:
    """Schema validates optional when on binary_src object entries."""
    metadata = _minimal_feature_metadata(
        _options={
            "method": {
                "binary": {
                    "binary_src": [
                        {"path": "tool", "when": {"version_lte": "1.0.0"}},
                    ],
                },
            },
        },
    )
    errors = list(get_validator().iter_errors(metadata))
    assert errors


def test_schema_source_install_bins_when_rejects_invalid_key() -> None:
    """Schema validates optional when on source.install_bins object entries."""
    metadata = _minimal_feature_metadata(
        _options={
            "method": {
                "source": {
                    "install_bins": [
                        {"path": "bin/tool", "when": {"version_lte": "1.0.0"}},
                    ],
                },
            },
        },
    )
    errors = list(get_validator().iter_errors(metadata))
    assert errors


def test_schema_source_build_env_when_rejects_invalid_key() -> None:
    """Schema validates optional when on source.build_env object entries."""
    metadata = _minimal_feature_metadata(
        _options={
            "method": {
                "source": {
                    "build_env": [
                        {"value": "GOTOOLCHAIN=auto", "when": {"version_lte": "1.0.0"}},
                    ],
                },
            },
        },
    )
    errors = list(get_validator().iter_errors(metadata))
    assert errors


def test_load_emits_source_install_bins_option(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """source_install_bins option is injected when source.install_bins is declared."""
    install_bins = [
        {"path": "bin/tool"},
        {"path": "bin/helper", "when": {"plat.kernel": "linux"}},
    ]
    root = _write_test_repo(
        tmp_path,
        feature_metadata=_minimal_feature_metadata(
            _options={
                "method": {
                    "source": {
                        "asset_uri": "https://example.com/tool.tar.gz",
                        "build_system": "make",
                        "install_bins": install_bins,
                    }
                }
            }
        ),
        shared_yaml=(_REPO_ROOT / "features" / "metadata.shared.yaml").read_text(
            encoding="utf-8"
        ),
    )
    result = _loader_for(root, monkeypatch).load("test-feature")["test-feature"]
    assert "source_install_bins" in result["options"]
    expected = serialize_path_entries(install_bins)
    assert result["options"]["source_install_bins"]["default"] == expected


def test_load_emits_source_build_env_option(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """source_build_env option is injected when source.build_env is declared."""
    build_env = [
        {"value": "MY_VAR=1"},
        {"value": "OTHER=on", "when": {"plat.kernel": "linux"}},
    ]
    root = _write_test_repo(
        tmp_path,
        feature_metadata=_minimal_feature_metadata(
            _options={
                "method": {
                    "source": {
                        "asset_uri": "https://example.com/tool.tar.gz",
                        "build_system": "make",
                        "build_env": build_env,
                    }
                }
            }
        ),
        shared_yaml=(_REPO_ROOT / "features" / "metadata.shared.yaml").read_text(
            encoding="utf-8"
        ),
    )
    result = _loader_for(root, monkeypatch).load("test-feature")["test-feature"]
    assert "source_build_env" in result["options"]
    assert result["options"]["source_build_env"]["default"] == serialize_value_entries(
        build_env
    )


def test_schema_when_rejects_flavor_suffix_in_key() -> None:
    """Schema rejects case-flavor suffixes in when keys (pattern-expand only)."""
    errors = _when_spec_errors({"plat.kernel:lower": "linux"})
    assert errors


def test_schema_when_rejects_ordering_op_array() -> None:
    """Schema rejects array values for ordering operators (gte/lt/…)."""
    errors = _when_spec_errors({"feat.version": {"gte": ["1.0.0"]}})
    assert errors


def test_schema_accepts_internal_and_files() -> None:
    """Schema accepts optional `_internal` and `_files` metadata fields."""
    metadata = _minimal_feature_metadata(
        _internal={"foo": "bar", "nested": {"count": 1}},
        _files=[{"path": "entrypoint.sh", "content": "#!/bin/sh\n"}],
    )
    errors = list(get_validator().iter_errors(metadata))
    assert not errors


def test_load_resolves_epel_rhel_family_from_internal() -> None:
    """Features reference ``_internal.epel_rhel_family`` via pyserials."""
    loader = MetadataLoader()
    shared = loader._shared_metadata
    epel = shared["_internal"]["epel_rhel_family"]

    for feat_id, package_name in (
        ("install-ripgrep", "ripgrep"),
        ("install-ruff", "ruff"),
        ("install-tokei", "tokei"),
    ):
        meta = loader.load(feat_id)[feat_id]
        packages = meta["_dependencies"]["run"]["method-upstream-package"]["packages"]
        epel_entries = [
            p
            for p in packages
            if isinstance(p, dict) and p.get("label") == epel["label"]
        ]
        assert len(epel_entries) == 1, feat_id
        entry = epel_entries[0]
        assert entry["when"] == epel["when"]
        assert entry["keys"] == epel["keys"]
        assert entry["repos"] == epel["repos"]

        manifest_default = meta["options"][
            "ospkg_manifest_method_upstream_package_run"
        ]["default"]
        assert "RHEL-family via EPEL" in manifest_default
        assert package_name in manifest_default
        assert "RPM-GPG-KEY-EPEL" in manifest_default


@pytest.mark.parametrize(
    "files_entry",
    [
        {"content": "x"},
        {"path": "foo.sh"},
        {"path": "foo.sh", "content": "x", "extra": "y"},
    ],
)
def test_schema_rejects_invalid_files_entries(files_entry: dict) -> None:
    """Schema rejects malformed `_files` entries."""
    metadata = _minimal_feature_metadata(_files=[files_entry])
    errors = list(get_validator().iter_errors(metadata))
    assert errors


def test_setup_shell_block_catalog_codegen() -> None:
    """setup-shell's _internal catalog generates block options and the registry.

    The block_* options and files/blocks.registry.bash are both generated from
    _internal.blocks/_internal.targets via pyserials templates in metadata.yaml
    (same splice pattern as the shared ospkg_manifest_* options); this guards
    the catalog → options → registry pipeline end to end.
    """
    meta = MetadataLoader().load()["setup-shell"]
    options = meta["options"]
    blocks = meta["_internal"]["blocks"]
    targets = meta["_internal"]["targets"]

    # Every catalog entry with an option emitted exactly one generated option.
    catalog_options = {b["option"] for b in blocks.values() if b.get("option")}
    generated = {k for k in options if k.startswith("block_")}
    assert generated == catalog_options
    assert len(generated) == 64

    # Spot-check option shapes.
    assert options["block_sys_bashrc_history"]["type"] == "boolean"
    assert options["block_sys_bashrc_history"]["default"] is True
    assert options["block_sys_shellenv_umask"]["default"] == "022"
    assert options["block_sys_shellenv_editor"]["enum"][0]["value"] == "auto"

    # The lifecycle knobs replaced the shared-name collision (if_exists_sys is
    # local; the shared if_exists keeps its clean, unduplicated 5-value enum).
    assert options["if_exists_sys"]["default"] == "auto"
    assert len(options["if_exists"]["enum"]) == 5

    # Registry file is generated with the associative arrays the engine reads,
    # and every target/block id appears in it.
    files = {f["path"]: f["content"] for f in meta["_files"]}
    registry = files["blocks.registry.bash"]
    for var in (
        "_FEAT_SS_TARGET_ORDER=(",
        "declare -gA _FEAT_SS_TARGET_SCOPE=(",
        "declare -gA _FEAT_SS_BLOCK_MARKER=(",
        "declare -gA _FEAT_SS_LINE_RESOLVER=(",
    ):
        assert var in registry
    for target in targets:
        assert f'["{target["id"]}"]' in registry
    for block_id in blocks:
        assert f'["{block_id}"]' in registry

    # Every fixed block's slice file exists on disk.
    files_dir = _REPO_ROOT / "features" / "setup-shell" / "files"
    blocks_dir = files_dir / "blocks"
    for block_id, block in blocks.items():
        if block.get("slice"):
            slice_path = files_dir / block["slice"]
            assert slice_path.is_file(), f"{block_id}: missing slice {block['slice']}"
        else:
            assert block.get("dynamic"), f"{block_id}: neither slice nor dynamic"
    assert blocks_dir.is_dir()
