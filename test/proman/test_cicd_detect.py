"""Tests for proman.cicd.detect — glob matching, matrix helpers, and parse utilities."""

from pathlib import Path

import proman.cicd.detect as cd
import proman.config as cfg
import pytest
from proman.test.effective import EffectiveTests

_CICD_MAIN = """\
name: TestProject
name_slug: testproject
owner: testowner
owner_slug: testowner
namespace: testowner/testproject
repo_url: https://github.com/testowner/testproject
oci_base: ghcr.io/testowner/testproject
path:
  features: features
  library: lib
  feature_library: ${{ path.library }}$
  src: src
  test: test
  test_features: ${{ path.test }}$/features
  test_features_shared_defaults: ${{ path.test_features }}$/defaults.shared.yaml
  test_environments: ${{ path.test }}$/environments.yaml
  test_lib: test/lib
  test_lib_scenarios: ${{ path.test_lib }}$/scenarios.yaml
  dev_scripts_test: .dev/scripts/test
  devcontainer: .devcontainer
  shared_metadata: features/metadata.shared.yaml
  metadata_schema: features/metadata.schema.json
  install_script_template: features/install.tmpl.bash
filename:
  feature_metadata: metadata.yaml
  feature_scenarios: scenarios.yaml
features:
  lifecycle_hook_keys:
    - onCreateCommand
"""

_MINIMAL_CI = """\
image:
  suffix: "-devcontainer"
artifacts:
  retention_days: 7
  src:
    name: testproject-src
    path: src/
  dist:
    name: testproject-dist
    path: dist/
  pages:
    name: github-pages
    path: .local/build/docs/website.tar
publish:
  registry: ghcr.io
triggers: {}
"""

# ── any_match ─────────────────────────────────────────────────────────────────


def test_recursive_double_star_matches_nested_paths() -> None:
    """Verify ** patterns match files nested at any depth."""
    changed = [
        "lib/foo/bar.baz",
        "test/unit/subsuite/example.bats",
        ".devcontainer/.dev/nested/config.json",
    ]
    assert cd.any_match(changed, ["lib/**"])
    assert cd.any_match(changed, ["test/unit/**"])
    assert cd.any_match(changed, [".devcontainer/.dev/**"])


def test_no_pattern_match_returns_false() -> None:
    """Verify any_match returns False when no pattern matches."""
    changed = ["docs/source/index.md", "README.md"]
    assert not cd.any_match(changed, ["lib/**", "test/unit/**"])


# ── _bool_inp ─────────────────────────────────────────────────────────────────


def test_bool_inp_true() -> None:
    """Verify 'true' parses to True."""
    assert cd._bool_inp("true") is True


def test_bool_inp_false() -> None:
    """Verify 'false' parses to False."""
    assert cd._bool_inp("false") is False


def test_bool_inp_empty_default_true() -> None:
    """Verify empty string returns the default True."""
    assert cd._bool_inp("") is True


def test_bool_inp_empty_default_false() -> None:
    """Verify empty string returns the supplied default False."""
    assert cd._bool_inp("", default=False) is False


def test_workflow_dispatch_input_str_bool_json() -> None:
    """Verify JSON-style booleans normalize to lowercase strings."""
    assert cd._workflow_dispatch_input_str(raw=True) == "true"
    assert cd._workflow_dispatch_input_str(raw=False) == "false"


def test_workflow_dispatch_input_str_none_uses_default() -> None:
    """Verify absent inputs fall back to the default string."""
    assert cd._workflow_dispatch_input_str(None, default="false") == "false"


# ── _parse_feature_list ───────────────────────────────────────────────────────


def test_parse_feature_list_json_array() -> None:
    """Verify JSON array strings are parsed into a list."""
    assert cd._parse_feature_list('["a", "b", "c"]') == ["a", "b", "c"]


def test_parse_feature_list_comma_sep() -> None:
    """Verify comma-separated strings are split into a list."""
    assert cd._parse_feature_list("a, b, c") == ["a", "b", "c"]


def test_parse_feature_list_comma_sep_filters_empty() -> None:
    """Verify empty tokens from consecutive commas are filtered out."""
    assert cd._parse_feature_list("a,,b") == ["a", "b"]


@pytest.fixture(autouse=True)
def _reset_config_singleton() -> None:
    """Ensure isolated tests do not leave a cached Config pointing at another repo."""
    yield
    cfg.clear_cache()


def _use_tmp_repo(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    """Redirect proman config and detect git root to a temporary repository layout."""
    proman_dir = tmp_path / ".config" / "proman"
    proman_dir.mkdir(parents=True)
    (proman_dir / "_main.yaml").write_text(_CICD_MAIN, encoding="utf-8")
    (proman_dir / "ci.yaml").write_text(_MINIMAL_CI, encoding="utf-8")
    monkeypatch.setattr(cfg, "git_repo_root", lambda: tmp_path)
    cfg.clear_cache()
    monkeypatch.setattr(cd, "git_repo_root", lambda: tmp_path)


# ── helpers ───────────────────────────────────────────────────────────────────


def _write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


# ── compute_macos_matrix ──────────────────────────────────────────────────────


def test_compute_macos_matrix_from_scenarios_yaml(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Verify macOS matrix is built from scenarios that reference macOS envs."""
    _use_tmp_repo(monkeypatch, tmp_path)
    _write(
        tmp_path / "test/environments.yaml",
        """\
macos-latest:
  image: macos-latest
ubuntu-latest:
  image: ubuntu-latest
""",
    )
    _write(
        tmp_path / "test/features/install-foo/scenarios.yaml",
        """\
default:
  envs: [ubuntu-latest]
  tests: [default]
macos_default:
  envs: [macos-latest]
  tests: [macos_default]
""",
    )
    _write(
        tmp_path / "test/features/install-bar/scenarios.yaml",
        """\
linux_only:
  envs: [ubuntu-latest]
  tests: [linux_only]
""",
    )
    result = cd.compute_macos_matrix(["install-bar", "install-foo"])
    assert result == [
        {
            "feature": "install-foo",
            "runner": "macos-latest",
            "scenario": "macos_default.macos-latest",
        },
    ]


def test_compute_macos_matrix_empty_when_no_macos(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Verify macOS matrix is empty when no scenario references a macOS env."""
    _use_tmp_repo(monkeypatch, tmp_path)
    _write(
        tmp_path / "test/environments.yaml",
        "ubuntu-latest:\n  image: ubuntu-latest\n",
    )
    _write(
        tmp_path / "test/features/install-foo/scenarios.yaml",
        "default:\n  envs: [ubuntu-latest]\n  tests: [default]\n",
    )
    result = cd.compute_macos_matrix(["install-foo"])
    assert result == []


def test_compute_macos_matrix_one_entry_per_scenario(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Verify each macOS scenario gets its own matrix entry for runner isolation."""
    _use_tmp_repo(monkeypatch, tmp_path)
    _write(
        tmp_path / "test/environments.yaml",
        "macos-latest:\n  image: macos-latest\n",
    )
    _write(
        tmp_path / "test/features/install-foo/scenarios.yaml",
        """\
scenario_a:
  envs: [macos-latest]
  tests: [a]
scenario_b:
  envs: [macos-latest]
  tests: [b]
""",
    )
    result = cd.compute_macos_matrix(["install-foo"])
    assert result == [
        {
            "feature": "install-foo",
            "runner": "macos-latest",
            "scenario": "scenario_a.macos-latest",
        },
        {
            "feature": "install-foo",
            "runner": "macos-latest",
            "scenario": "scenario_b.macos-latest",
        },
    ]


# ── compute_feature_matrix ────────────────────────────────────────────────────


def test_compute_feature_matrix_default_modes_in_both_linux_lists(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Verify default-modes scenario is in both devcontainer and linux lists."""
    _use_tmp_repo(monkeypatch, tmp_path)
    _write(
        tmp_path / "test/environments.yaml",
        "ubuntu-latest:\n  image: ubuntu-latest\n",
    )
    _write(
        tmp_path / "test/features/install-foo/scenarios.yaml",
        "default:\n  envs: [ubuntu-latest]\n  tests: [default]\n",
    )
    result = cd.compute_feature_matrix(["install-foo"], [])
    assert result == [
        {
            "feature": "install-foo",
            "devcontainer_scenarios": ["default.ubuntu-latest"],
            "linux_scenarios": ["default.ubuntu-latest"],
            "macos_scenarios": [],
        },
    ]


def test_compute_feature_matrix_standalone_only_excluded_from_devcontainer(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Verify modes: [standalone] excludes scenario from devcontainer but not linux."""
    _use_tmp_repo(monkeypatch, tmp_path)
    _write(
        tmp_path / "test/environments.yaml",
        "ubuntu-latest:\n  image: ubuntu-latest\n",
    )
    _write(
        tmp_path / "test/features/install-foo/scenarios.yaml",
        """\
only_standalone:
  envs: [ubuntu-latest]
  modes: [standalone]
  tests: [t]
""",
    )
    result = cd.compute_feature_matrix(["install-foo"], [])
    assert result == [
        {
            "feature": "install-foo",
            "devcontainer_scenarios": [],
            "linux_scenarios": ["only_standalone.ubuntu-latest"],
            "macos_scenarios": [],
        },
    ]


def test_compute_feature_matrix_macos_env_only_in_macos_scenarios(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Verify a macOS-env scenario appears only in macos_scenarios."""
    _use_tmp_repo(monkeypatch, tmp_path)
    _write(
        tmp_path / "test/environments.yaml",
        "macos-latest:\n  image: macos-latest\n",
    )
    _write(
        tmp_path / "test/features/install-foo/scenarios.yaml",
        "mac_sc:\n  envs: [macos-latest]\n  tests: [mac]\n",
    )
    result = cd.compute_feature_matrix([], ["install-foo"])
    assert result == [
        {
            "feature": "install-foo",
            "devcontainer_scenarios": [],
            "linux_scenarios": [],
            "macos_scenarios": [
                {"scenario": "mac_sc.macos-latest", "runner": "macos-latest"}
            ],
        },
    ]


def test_compute_feature_matrix_includes_fully_generated_feature(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A fully generated feature (no scenarios.yaml on disk) stays in the matrix.

    Regression: the matrix used to skip any feature without a scenarios.yaml on
    disk, dropping fully generated features (e.g. install-oras) so their tests
    never ran under change-detection.
    """
    _use_tmp_repo(monkeypatch, tmp_path)
    _write(
        tmp_path / "test/environments.yaml",
        "ubuntu-latest:\n  image: ubuntu-latest\n",
    )

    # Deliberately no test/features/install-gen/scenarios.yaml on disk.
    def _fake(fid: str) -> EffectiveTests:
        scenarios = (
            {
                "default": {
                    "envs": ["ubuntu-latest"],
                    "modes": ["standalone"],
                    "tests": ["default"],
                },
            }
            if fid == "install-gen"
            else {}
        )
        return EffectiveTests(
            feature_id=fid, defaults={}, scenarios=scenarios, checks={}
        )

    monkeypatch.setattr(cd, "load_effective", _fake)
    result = cd.compute_feature_matrix(["install-gen"], [])
    assert [e["feature"] for e in result] == ["install-gen"]
    assert result[0]["linux_scenarios"] == ["default.ubuntu-latest"]


def test_compute_feature_matrix_feature_in_both_linux_and_macos(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Verify a feature in both linux_ids and macos_ids gets all three lists."""
    _use_tmp_repo(monkeypatch, tmp_path)
    _write(
        tmp_path / "test/environments.yaml",
        "ubuntu-latest:\n  image: ubuntu-latest\n"
        "macos-latest:\n  image: macos-latest\n",
    )
    _write(
        tmp_path / "test/features/install-foo/scenarios.yaml",
        """\
default:
  envs: [ubuntu-latest]
  tests: [default]
mac_sc:
  envs: [macos-latest]
  tests: [mac]
""",
    )
    result = cd.compute_feature_matrix(["install-foo"], ["install-foo"])
    assert result == [
        {
            "feature": "install-foo",
            "devcontainer_scenarios": ["default.ubuntu-latest"],
            "linux_scenarios": ["default.ubuntu-latest"],
            "macos_scenarios": [
                {"scenario": "mac_sc.macos-latest", "runner": "macos-latest"}
            ],
        },
    ]


def test_compute_feature_matrix_macos_only_id_excludes_linux_scenarios(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Verify a feature in only macos_ids (not linux_ids) has empty linux lists."""
    _use_tmp_repo(monkeypatch, tmp_path)
    _write(
        tmp_path / "test/environments.yaml",
        "ubuntu-latest:\n  image: ubuntu-latest\n"
        "macos-latest:\n  image: macos-latest\n",
    )
    _write(
        tmp_path / "test/features/install-foo/scenarios.yaml",
        """\
default:
  envs: [ubuntu-latest]
  tests: [default]
mac_sc:
  envs: [macos-latest]
  tests: [mac]
""",
    )
    result = cd.compute_feature_matrix([], ["install-foo"])
    assert result == [
        {
            "feature": "install-foo",
            "devcontainer_scenarios": [],
            "linux_scenarios": [],
            "macos_scenarios": [
                {"scenario": "mac_sc.macos-latest", "runner": "macos-latest"}
            ],
        },
    ]


def test_compute_feature_matrix_missing_scenarios_file_excluded(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Verify a feature with no scenarios.yaml file is excluded from the result."""
    _use_tmp_repo(monkeypatch, tmp_path)
    _write(
        tmp_path / "test/environments.yaml",
        "ubuntu-latest:\n  image: ubuntu-latest\n",
    )
    result = cd.compute_feature_matrix(["install-missing"], [])
    assert result == []


def test_compute_feature_matrix_empty_inputs(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Verify empty linux_ids and macos_ids returns an empty list."""
    _use_tmp_repo(monkeypatch, tmp_path)
    _write(
        tmp_path / "test/environments.yaml",
        "ubuntu-latest:\n  image: ubuntu-latest\n",
    )
    result = cd.compute_feature_matrix([], [])
    assert result == []


def test_apply_dispatch_feature_matrix_filters_drops_row_when_all_stripped() -> None:
    """Verify dispatch filter removes a feature row when no modalities remain."""
    raw = [
        {
            "feature": "install-foo",
            "devcontainer_scenarios": ["a"],
            "linux_scenarios": ["b"],
            "macos_scenarios": [],
        },
    ]
    assert (
        cd.apply_dispatch_feature_matrix_filters(
            raw,
            run_devcontainer=False,
            run_linux=False,
        )
        == []
    )


def test_apply_dispatch_feature_matrix_filters_keeps_macos_when_linux_off() -> None:
    """Verify macOS scenarios survive when Linux-only modalities are disabled."""
    raw = [
        {
            "feature": "install-foo",
            "devcontainer_scenarios": ["dc"],
            "linux_scenarios": ["lx"],
            "macos_scenarios": [{"scenario": "m", "runner": "macos-latest"}],
        },
    ]
    out = cd.apply_dispatch_feature_matrix_filters(
        raw,
        run_devcontainer=False,
        run_linux=False,
    )
    assert out == [
        {
            "feature": "install-foo",
            "devcontainer_scenarios": [],
            "linux_scenarios": [],
            "macos_scenarios": [{"scenario": "m", "runner": "macos-latest"}],
        },
    ]


def test_select_feature_test_ids_shared_metadata_triggers_all(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Verify shared metadata changes match scenario_test and select all features."""
    _use_tmp_repo(monkeypatch, tmp_path)
    _write(
        tmp_path / "test/environments.yaml", "ubuntu-latest:\n  image: ubuntu-latest\n"
    )
    (tmp_path / "features" / "install-foo").mkdir(parents=True)
    (tmp_path / "features" / "install-bar").mkdir(parents=True)
    groups = {
        "scenario_test": [
            "features/install.sh",
            "lib/**",
            "features/metadata.shared.yaml",
        ],
    }
    changed = ["features/metadata.shared.yaml"]
    linux, macos = cd.select_feature_test_ids(
        changed,
        ["install-bar", "install-foo"],
        groups,
    )
    assert linux == ["install-bar", "install-foo"]
    assert macos == []


def test_select_feature_test_ids_per_feature_metadata(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Verify a single feature metadata.yaml change selects only that feature."""
    _use_tmp_repo(monkeypatch, tmp_path)
    _write(
        tmp_path / "test/environments.yaml", "ubuntu-latest:\n  image: ubuntu-latest\n"
    )
    groups = {
        "scenario_test": [
            "features/install.sh",
            "lib/**",
            "features/metadata.shared.yaml",
        ],
    }
    changed = ["features/install-foo/metadata.yaml"]
    linux, macos = cd.select_feature_test_ids(
        changed,
        ["install-bar", "install-foo"],
        groups,
    )
    assert linux == ["install-foo"]
    assert macos == []


def test_select_feature_test_ids_per_feature_paths(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Verify unrelated feature paths select only the touched feature."""
    _use_tmp_repo(monkeypatch, tmp_path)
    _write(
        tmp_path / "test/environments.yaml", "ubuntu-latest:\n  image: ubuntu-latest\n"
    )
    groups = {"scenario_test": ["features/install.sh", "lib/**"]}
    changed = ["features/install-foo/install.bash"]
    linux, macos = cd.select_feature_test_ids(
        changed,
        ["install-bar", "install-foo"],
        groups,
    )
    assert linux == ["install-foo"]
    assert macos == []


def test_merge_release_feature_test_ids_unions_changed(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Release mode keeps path-selected features alongside releasable ones."""
    _use_tmp_repo(monkeypatch, tmp_path)
    _write(
        tmp_path / "test/environments.yaml", "ubuntu-latest:\n  image: ubuntu-latest\n"
    )
    groups = {"scenario_test": ["features/install.sh", "lib/**"]}
    releasable = [
        {"feature": "install-foo", "version": "1.0.0", "tag": "install-foo/1.0.0"},
    ]
    changed = ["features/install-bar/metadata.yaml"]
    linux, macos = cd.merge_release_feature_test_ids(
        releasable,
        changed,
        ["install-bar", "install-foo"],
        groups,
    )
    assert linux == ["install-bar", "install-foo"]
    assert macos == []


# ── compute_unit_env_matrix ───────────────────────────────────────────────────


def test_compute_unit_env_matrix(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Verify unit env matrix is built from scenarios.yaml entries."""
    _use_tmp_repo(monkeypatch, tmp_path)
    _write(
        tmp_path / "test/lib/scenarios.yaml",
        """\
defaults:
  options:
    log_level: trace
ubuntu-stable:
  env: ubuntu-latest
debian-bookworm:
  env: debian-latest
""",
    )
    result = cd.compute_unit_env_matrix()
    assert result == [
        {"name": "ubuntu-stable", "env": "ubuntu-latest"},
        {"name": "debian-bookworm", "env": "debian-latest"},
    ]


# ── compute_unit_macos_matrix ─────────────────────────────────────────────────


def test_compute_unit_macos_matrix(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Verify unit macOS matrix enumerates each macOS env with full fields."""
    _use_tmp_repo(monkeypatch, tmp_path)
    _write(
        tmp_path / "test/environments.yaml",
        """\
ubuntu-latest:
  image: ubuntu-latest
macos-current:
  image: macos-26
  clean_path: true
macos-current+brew:
  image: macos-26
  clean_path: true
  path_prepend: /opt/homebrew/bin:/usr/local/bin
debian-latest:
  image: debian-latest
""",
    )
    result = cd.compute_unit_macos_matrix()
    # Only macos-current+brew (path_prepend set) is included;
    # bare macos-current is excluded
    # because bootstrap functions need Homebrew to install tools.
    assert result == [
        {
            "env": "macos-current+brew",
            "runner": "macos-26",
            "clean_path": True,
            "path_prepend": "/opt/homebrew/bin:/usr/local/bin",
            "integration": True,
        },
    ]


def test_compute_unit_macos_matrix_empty_when_no_macos(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Verify unit macOS matrix is empty when no macOS environments exist."""
    _use_tmp_repo(monkeypatch, tmp_path)
    _write(
        tmp_path / "test/environments.yaml",
        "ubuntu-latest:\n  image: ubuntu-latest\n",
    )
    result = cd.compute_unit_macos_matrix()
    assert result == []
