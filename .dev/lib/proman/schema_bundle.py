"""JSON Schema $ref / $id handling for validation and the published docs site."""

from __future__ import annotations

import json
from copy import deepcopy
from functools import cache
from typing import TYPE_CHECKING, Any

from jsonschema import Draft202012Validator
from referencing import Registry
from referencing.jsonschema import DRAFT202012

from proman.config import load as load_config

if TYPE_CHECKING:
    from pathlib import Path

    from proman.config import Config


def get_validator() -> Draft202012Validator:
    """Return a Draft 2020-12 validator for ``metadata.yaml`` with local schema URIs."""
    return _build_metadata_validator()


def get_checks_validator() -> Draft202012Validator:
    """Return a Draft 2020-12 validator for ``test/features/*/checks.yaml``."""
    return _build_validator("path.checks_schema")


def get_scenarios_validator() -> Draft202012Validator:
    """Return a Draft 2020-12 validator for ``test/features/*/scenarios.yaml``."""
    return _build_validator("path.scenarios_schema")


def get_environments_validator() -> Draft202012Validator:
    """Return a Draft 2020-12 validator for ``test/environments.yaml``."""
    return _build_validator("path.environments_schema")


def get_generation_validator() -> Draft202012Validator:
    """Return a Draft 2020-12 validator for ``test/features/generation.yaml``."""
    return _build_validator("path.generation_schema")


@cache
def _build_metadata_validator() -> Draft202012Validator:
    """Build and cache the metadata schema validator with its extended registry."""
    config = load_config()
    schema_path = config.absolute_path("path.metadata_schema")
    schema, registry = _registry_for_schema_file(schema_path)
    registry = _extend_metadata_registry(registry, config, schema_path)
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema, registry=registry)


@cache
def _build_validator(config_key: str) -> Draft202012Validator:
    """Build and cache a Draft 2020-12 validator for a self-contained schema file."""
    config = load_config()
    schema_path = config.absolute_path(config_key)
    schema, registry = _registry_for_schema_file(schema_path)
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema, registry=registry)


def _registry_for_schema_file(schema_path: Path) -> tuple[dict[str, Any], Registry]:
    """Load one schema file; return it with a single-document registry."""
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    uri = schema_path.as_uri()
    _set_root_id(schema, uri)
    registry = Registry().with_resource(uri, DRAFT202012.create_resource(schema))
    return schema, registry


def _extend_metadata_registry(
    registry: Registry,
    config: Config,
    root_schema_path: Path,
) -> Registry:
    """Register lib/ and features/ schemas referenced from metadata.schema.json."""
    lib_dirpath = config.absolute_path("path.library")
    features_dirpath = config.absolute_path("path.features")
    stem_to_uri = lib_schema_stem_to_uri(lib_dirpath)
    # metadata.schema.json uses $ref paths relative to features/ (e.g.
    # install-os-pkg/manifest.schema.json) so IDE yaml.schemas can load them;
    # jsonschema resolves those against the root schema URI once $id is set.
    for stem, uri in stem_to_uri.items():
        path = lib_dirpath / f"{stem}.schema.json"
        if not path.is_file():
            continue
        doc = deepcopy(json.loads(path.read_text(encoding="utf-8")))
        _walk_replace_bare_stem_refs(doc, stem_to_uri)
        _set_root_id(doc, uri)
        registry = registry.with_resource(uri, DRAFT202012.create_resource(doc))
    for feat_schema in sorted(features_dirpath.rglob("*.schema.json")):
        if feat_schema.resolve() == root_schema_path.resolve():
            continue
        uri = feat_schema.as_uri()
        doc = deepcopy(json.loads(feat_schema.read_text(encoding="utf-8")))
        _set_root_id(doc, uri)
        registry = registry.with_resource(uri, DRAFT202012.create_resource(doc))
    return registry


def schema_stem_from_path(schema_path: Path) -> str:
    """Logical name for ``*.schema.json`` (e.g. ``ospkg-manifest``)."""
    name = schema_path.name
    if name.endswith(".schema.json"):
        return name[: -len(".schema.json")]
    if name.endswith(".json"):
        return name[: -len(".json")]
    return name


def published_schema_basename(stem: str) -> str:
    """Filename under ``/schema/`` on the site (``{stem}.json``)."""
    return f"{stem}.json"


def _walk_replace_bare_stem_refs(obj: object, stem_to_target: dict[str, str]) -> None:
    """Replace ``$ref`` values that are bare local stems (no fragment, no URI)."""
    if isinstance(obj, dict):
        for k, v in list(obj.items()):
            if k == "$ref" and isinstance(v, str):
                if v.startswith("#"):
                    continue
                if "://" in v:
                    continue
                if v in stem_to_target:
                    obj[k] = stem_to_target[v]
            else:
                _walk_replace_bare_stem_refs(v, stem_to_target)
    elif isinstance(obj, list):
        for item in obj:
            _walk_replace_bare_stem_refs(item, stem_to_target)


def _set_root_id(schema: dict[str, Any], uri: str) -> None:
    schema["$id"] = uri


def build_materialized_schemas_for_website(
    *,
    repo_root: Path,
    base_url: str,
    publish_relpaths: list[str],
) -> dict[str, dict[str, Any]]:
    """Return ``stem → schema`` dicts with ``$id`` and ``$ref`` URLs for publishing."""
    base = base_url if base_url.endswith("/") else f"{base_url}/"
    stems: list[str] = []
    paths: list[Path] = []
    for rel in publish_relpaths:
        p = (repo_root / rel).resolve()
        if not p.is_file():
            msg = f"JSON schema publish list entry not found: {p}"
            raise FileNotFoundError(msg)
        paths.append(p)
        stems.append(schema_stem_from_path(p))
    stem_to_public_url = {
        s: f"{base}schema/{published_schema_basename(s)}" for s in stems
    }
    out: dict[str, dict[str, Any]] = {}
    for stem, path in zip(stems, paths, strict=True):
        data = deepcopy(json.loads(path.read_text(encoding="utf-8")))
        _walk_replace_bare_stem_refs(data, stem_to_public_url)
        _set_root_id(data, stem_to_public_url[stem])
        out[stem] = data
    return out


def publish_website_schemas(
    repo_root: Path,
    build_dir: Path,
    *,
    base_url: str | None = None,
) -> None:
    """Write rewritten schemas under ``build_dir / "schema"`` for static hosting."""
    config = load_config()
    docs_config = config["docs"]
    pub = docs_config.get("json_schemas_publish")
    if not pub:
        return
    override = base_url
    if override is None:
        override = docs_config.get("website_base_url")
    if isinstance(override, str) and override.strip():
        base = override.rstrip("/") + "/"
    else:
        base = docs_config["website_base_url"]
    materialized = build_materialized_schemas_for_website(
        repo_root=repo_root,
        base_url=base,
        publish_relpaths=list(pub),
    )
    schema_out = build_dir / "schema"
    schema_out.mkdir(parents=True, exist_ok=True)
    for stem, doc in materialized.items():
        dest = schema_out / published_schema_basename(stem)
        dest.write_text(
            json.dumps(doc, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )


def lib_schema_stem_to_uri(lib_dirpath: Path) -> dict[str, str]:
    """Map each ``*.schema.json`` stem under ``lib/`` to a ``file://`` URI."""
    return {
        schema_stem_from_path(p): p.resolve().as_uri()
        for p in sorted(lib_dirpath.glob("*.schema.json"))
    }


def clear_validator_cache() -> None:
    """Clear cached JSON Schema validators."""
    _build_metadata_validator.cache_clear()
    _build_validator.cache_clear()
