"""Feature metadata: read, augment, and enumerate metadata.yaml files.

This is the single authoritative source for loading feature metadata.
It is consumed by the sync pipeline, the docs pipeline, and CLI commands.
"""

import functools

import pyserials
from jsonschema.exceptions import ValidationError

from proman.config import load as load_config
from proman.manifest_util import inject_dep_commands, serialize_manifest
from proman.schema_bundle import get_validator
from proman.when_util import (
    serialize_path_entries,
    serialize_value_entries,
    serialize_when,
    serialize_when_flow,
)

_PM_FAMILIES = frozenset({"apt", "apk", "brew", "dnf", "yum", "pacman", "zypper"})
_SOURCE_MODIFIER_KEYS = frozenset({"repos", "keys", "ppas", "taps", "copr", "modules"})
_SOURCE_MODIFIER_PM_HINTS = {
    "ppas": frozenset({"apt"}),
    "taps": frozenset({"brew"}),
    "copr": frozenset({"dnf"}),
    "modules": frozenset({"dnf"}),
}
_INSTALL_ENTRY_KEYS = frozenset({"packages", "casks"})
_AUTO_METHOD_RESTRICTION_KEYS = frozenset(
    {
        "os.id",
        "os.id_like",
        "os.version_id",
        "os.version_id_major",
        "os.version_codename",
        "plat.kernel",
        "plat.machine_release",
    }
)
_EXPANDABLE_WHEN_KEYS = (
    "plat.pm",
    "os.id",
    "os.id_like",
    "os.version_id",
    "os.version_id_major",
    "os.version_codename",
    "plat.kernel",
    "plat.machine_release",
)


class MetadataLoader:
    """Feature metadata loader."""

    def __init__(self) -> None:
        self._config = load_config()
        self._feat_dirpath = self._config.absolute_path("path.features")
        self._feat_metadata_filename = str(self._config["filename.feature_metadata"])
        self._shared_metadata = pyserials.read.yaml_from_file(
            self._config.absolute_path("path.shared_metadata")
        )
        self._dep_command_map = self._load_dep_command_map()
        self._schema_validator = get_validator()

    def _load_dep_command_map(self) -> dict[str, str]:
        """Load the ``package -> command`` guard map, if configured and present.

        The map is optional: a repo (or minimal test harness) without a
        ``path.dep_command_map`` entry or file simply gets no command guards
        (``inject_dep_commands`` treats an empty map as a no-op).
        """
        try:
            map_path = self._config.absolute_path("path.dep_command_map")
        except TypeError:
            return {}
        if not map_path.is_file():
            return {}
        return pyserials.read.yaml_from_file(map_path) or {}

    def load(self, *feat_ids: str) -> dict[str, dict]:
        """Load and augment metadata for all features found in *features_dirpath*.

        Features whose ``metadata.yaml`` is missing or fails augmentation are
        skipped with a warning and omitted from the result.

        Returns
        -------
        dict[str, dict]
            Mapping of ``feature_id`` → fully augmented metadata dict.
        """
        feat_ids = feat_ids or [
            metadata_path.parent.name
            for metadata_path in sorted(
                self._feat_dirpath.glob(f"*/{self._feat_metadata_filename}")
            )
        ]

        all_metadata: dict[str, dict] = {}

        for feat_id in feat_ids:
            try:
                metadata = self._load_one(feat_id)
            except Exception as e:
                msg = f"Error loading metadata for feature '{feat_id}': {e}"
                raise ValueError(msg) from e

            all_metadata[feat_id] = metadata

        return all_metadata

    def _load_one(self, feature_id: str) -> dict:
        """Read and fully augment metadata for a single feature.

        Raises on missing files, parse errors, template fill failures, or schema
        validation errors.

        Augmentation steps (in order):
        1. Read ``metadata.yaml`` from disk.
        2. Set ``metadata["id"]`` and merge shared metadata.
        3. Normalize lifecycle command map keys.
        4. Filter shared ``options`` entries tagged with ``_apply_when``.
        5. Run :class:`pyserials.update.TemplateFiller` (including ``ospkg_manifest_*``
           option emission from ``metadata.shared.yaml``).
        6. Validate against ``features/metadata.schema.json``.
        """
        metadata_filepath = (
            self._feat_dirpath / feature_id / self._feat_metadata_filename
        )
        if not metadata_filepath.is_file():
            msg = (
                f"Metadata file not found for feature '{feature_id}':"
                f" {metadata_filepath}"
            )
            raise FileNotFoundError(msg)

        try:
            metadata: dict = pyserials.read.yaml_from_file(metadata_filepath)
        except Exception as e:
            msg = f"Error reading metadata.yaml for feature '{feature_id}': {e}"
            raise ValueError(msg) from e

        if not isinstance(metadata, dict):
            msg = f"Metadata for feature '{feature_id}' is not a YAML mapping (dict)."
            raise TypeError(msg)

        metadata["id"] = feature_id
        metadata["_project"] = self._config.asdict

        pyserials.update.recursive_update(
            source=metadata,
            addon=self._shared_metadata,
        )

        self._normalize_lifecycle_keys(metadata)
        metadata["options"] = self._filter_options(metadata)

        try:
            metadata = pyserials.update.TemplateFiller(
                code_context={
                    "serialize_when": serialize_when,
                    "serialize_when_flow": serialize_when_flow,
                    "serialize_path_entries": serialize_path_entries,
                    "serialize_value_entries": serialize_value_entries,
                    "serialize_manifest": serialize_manifest,
                    "inject_dep_commands": functools.partial(
                        inject_dep_commands,
                        command_map=self._dep_command_map,
                    ),
                },
            ).fill(metadata)
        except Exception as e:
            msg = (
                f"Error substituting variables in metadata for feature"
                f" '{feature_id}': {e}"
            )
            raise ValueError(msg) from e
        metadata.pop("_project")

        self._validate_schema(metadata)
        self._validate_method_manifests(metadata)

        return metadata

    def _filter_options(self, metadata: dict) -> dict:
        """Return ``options`` with conditional shared entries applied.

        Options tagged with ``_apply_when`` are only merged when the condition
        evaluates to ``True`` against the feature's full metadata dict.

        Pyserials mapping-unpack placeholders (dict keys containing ``*{{ … }}*``)
        are preserved with their null values so :meth:`TemplateFiller.fill` can
        expand them later; they are not real option definitions yet.
        """
        final_options: dict = {}
        for option_id, option_def in metadata.get("options", {}).items():
            if not isinstance(option_def, dict):
                # Let fully templated options pass through
                final_options[option_id] = option_def
                continue

            condition = option_def.get("_apply_when")

            if not condition:
                final_options[option_id] = option_def
                continue

            try:
                should_apply = pyserials.update.TemplateFiller().fill(
                    metadata,
                    condition,
                )
            except Exception as e:
                msg = (
                    f"Error substituting variables in _apply_when condition"
                    f" for option '{option_id}': {e}"
                )
                raise ValueError(msg) from e

            if should_apply:
                final_options[option_id] = {
                    k: v for k, v in option_def.items() if k != "_apply_when"
                }

        return final_options

    def _validate_schema(self, metadata: dict) -> None:
        """Validate metadata against the JSON schema.

        Raises :class:`ValueError` with all validation errors on failure.
        """
        errs = sorted(
            self._schema_validator.iter_errors(metadata),
            key=lambda e: (list(e.absolute_path), e.message),
        )
        if not errs:
            return

        lines = [f"Metadata validation failed with {len(errs)} error(s):"]
        for err in errs:
            lines.append(f"  • {_schema_error_path(err)}: {err.message}")
            lines.extend(
                f"    ↳ {_schema_error_path(sub)}: {sub.message}"
                for sub in sorted(
                    err.context, key=lambda e: (list(e.absolute_path), e.message)
                )
            )
        raise ValueError("\n".join(lines))

    def _validate_method_manifests(self, metadata: dict) -> None:
        """Enforce semantic separation between package-based install methods."""
        errs: list[str] = []
        dependencies = metadata.get("_dependencies") or {}
        method_options = (metadata.get("_options") or {}).get("method") or {}

        for lifecycle in ("run", "build"):
            manifests = dependencies.get(lifecycle) or {}

            package_manifest = manifests.get("method-package")
            if package_manifest:
                package_paths, _, _ = _collect_source_modifier_info(package_manifest)
                if package_paths:
                    joined = ", ".join(package_paths)
                    msg = (
                        f"_dependencies.{lifecycle}.method-package must not add "
                        "or alter package sources; move these entries to "
                        f"method-upstream-package instead: {joined}"
                    )
                    errs.append(msg)

            upstream_manifest = manifests.get("method-upstream-package")
            if not upstream_manifest:
                continue

            source_paths, source_pms, has_generic_source = (
                _collect_source_modifier_info(upstream_manifest)
            )
            if not source_paths:
                errs.append(
                    f"_dependencies.{lifecycle}.method-upstream-package must add or"
                    " alter package sources for at least one package manager."
                )
                continue

            declared_when = (method_options.get("upstream-package") or {}).get("when")
            if declared_when is None and isinstance(upstream_manifest, dict):
                declared_when = upstream_manifest.get("when")
            declared_pms = _extract_pm_values(declared_when)
            if declared_pms and not has_generic_source:
                missing = sorted(declared_pms - source_pms)
                if missing:
                    supported = ", ".join(sorted(declared_pms))
                    missing_joined = ", ".join(missing)
                    errs.append(
                        f"_dependencies.{lifecycle}.method-upstream-package "
                        f"declares support for package managers {supported} but "
                        "adds no package-source configuration for "
                        f"{missing_joined}."
                    )

        errs.extend(self._validate_method_resolution_when(metadata))

        if errs:
            lines = ["Method manifest validation failed:"]
            lines.extend(f"  • {err}" for err in errs)
            raise ValueError("\n".join(lines))

    def _validate_method_resolution_when(self, metadata: dict) -> list[str]:
        """Ensure auto-resolution method guards are not broader than manifests."""
        errs: list[str] = []
        dependencies = metadata.get("_dependencies") or {}
        method_options = (metadata.get("_options") or {}).get("method") or {}

        for lifecycle in ("run", "build"):
            manifests = dependencies.get(lifecycle) or {}
            for method_id in ("package", "upstream-package"):
                manifest = manifests.get(f"method-{method_id}")
                option_when = (method_options.get(method_id) or {}).get("when")
                if not manifest or not option_when:
                    continue

                support_clauses = _collect_install_support_clauses(manifest)
                if not support_clauses:
                    continue

                for option_clause in _expand_when_clauses(option_when):
                    clause_pms = _extract_pm_values(option_clause)
                    if not clause_pms:
                        continue

                    for pm in sorted(clause_pms):
                        compatible_support = [
                            clause
                            for clause in support_clauses
                            if _clause_matches_pm(clause, pm)
                            and _clauses_are_compatible(option_clause, clause)
                        ]
                        if not compatible_support:
                            continue

                        missing_keys = sorted(
                            _common_restriction_keys(
                                compatible_support,
                                present_keys=frozenset(option_clause),
                            )
                        )
                        if not missing_keys:
                            continue

                        errs.append(
                            f"_options.method.{method_id}.when clause "
                            f"{serialize_when_flow(option_clause)} is broader than "
                            f"_dependencies.{lifecycle}.method-{method_id} support "
                            f"for {pm}; add {', '.join(missing_keys)} or split "
                            "the clause into narrower branches."
                        )

        return errs

    def _normalize_lifecycle_keys(self, metadata: dict) -> None:
        """Rewrite lifecycle hook map keys to ``<prefix><task>``.

        *metadata* is updated in place. ``prefix`` comes from shared metadata
        (``_lifecycle_key_prefix``, e.g. ``quantized8-devfeats--``). Short YAML
        keys such as ``run`` become ``quantized8-devfeats--run``.
        """
        lifecycle_keys: list[str] = self._config["features.lifecycle_hook_keys"]
        key_prefix = metadata["_lifecycle_key_prefix"]
        for lifecycle_key in lifecycle_keys:
            if lifecycle_key not in metadata:
                continue
            block = metadata[lifecycle_key]
            new_block: dict[str, dict] = {}
            for entry_id, entry in block.items():
                full_key = f"{key_prefix}{entry_id}"
                new_block[full_key] = entry
            metadata[lifecycle_key] = new_block


def _schema_error_path(err: ValidationError) -> str:
    """Return a human-readable instance path for a jsonschema validation error."""
    if err.json_path and err.json_path != "$":
        return err.json_path
    if err.absolute_path:
        return " → ".join(str(part) for part in err.absolute_path)
    return "(root)"


def _collect_source_modifier_info(
    manifest: object,
) -> tuple[list[str], frozenset[str], bool]:
    """Return source-modifier paths, PM families hit, and whether scope is generic."""
    paths: list[str] = []
    pm_hits: set[str] = set()
    has_generic_scope = False

    def visit(
        node: object,
        *,
        path: tuple[str, ...] = (),
        scope_pms: frozenset[str] | None = None,
    ) -> None:
        nonlocal has_generic_scope
        if isinstance(node, dict):
            node_scope = _merge_pm_scopes(
                scope_pms, _extract_pm_values(node.get("when"))
            )
            for key, value in node.items():
                child_path = (*path, key)
                child_scope = node_scope
                if key in _PM_FAMILIES:
                    child_scope = _merge_pm_scopes(node_scope, frozenset({key}))
                if key in _SOURCE_MODIFIER_KEYS and value:
                    paths.append(_format_path(child_path))
                    modifier_scope = _merge_pm_scopes(
                        child_scope,
                        _SOURCE_MODIFIER_PM_HINTS.get(key),
                    )
                    if modifier_scope is None:
                        has_generic_scope = True
                    else:
                        pm_hits.update(modifier_scope)
                visit(value, path=child_path, scope_pms=child_scope)
            return

        if isinstance(node, list):
            for idx, entry in enumerate(node):
                visit(entry, path=(*path, f"[{idx}]"), scope_pms=scope_pms)

    visit(manifest)
    return paths, frozenset(pm_hits), has_generic_scope


def _extract_pm_values(when: object) -> frozenset[str] | None:
    """Return positively constrained PM families from a when-spec, if derivable."""
    result: frozenset[str] | None = None
    if not when:
        return result
    if isinstance(when, dict):
        pm_value = when.get("plat.pm")
        if pm_value is not None:
            result = _extract_pm_condition_values(pm_value)
    elif isinstance(when, list):
        pm_sets: list[frozenset[str]] = []
        for clause in when:
            clause_pms = _extract_pm_values(clause)
            if clause_pms is None:
                pm_sets = []
                break
            pm_sets.append(clause_pms)
        if pm_sets:
            result = frozenset().union(*pm_sets)
    return result


def _extract_pm_condition_values(value: object) -> frozenset[str] | None:
    """Return PM values from a positive equality condition, if derivable."""
    if isinstance(value, str):
        return frozenset({value}) if value in _PM_FAMILIES else None

    if isinstance(value, list):
        members = {
            item for item in value if isinstance(item, str) and item in _PM_FAMILIES
        }
        return frozenset(members) if members else None

    if isinstance(value, dict):
        eq_value = value.get("eq")
        if eq_value is None or "ne" in value:
            return None
        return _extract_pm_condition_values(eq_value)

    return None


def _merge_pm_scopes(
    left: frozenset[str] | None,
    right: frozenset[str] | None,
) -> frozenset[str] | None:
    """Intersect PM scopes when both are known, otherwise keep the known scope."""
    if left is None:
        return right
    if right is None:
        return left
    return left & right


def _format_path(path: tuple[str, ...]) -> str:
    """Render a tuple path using dotted components and list indices."""
    rendered = ""
    for part in path:
        if part.startswith("["):
            rendered += part
        elif not rendered:
            rendered = part
        else:
            rendered += f".{part}"
    return rendered


def _collect_install_support_clauses(manifest: object) -> list[dict[str, object]]:
    """Return effective install-support clauses emitted by a method manifest."""
    clauses: list[dict[str, object]] = []

    def visit(
        node: object,
        *,
        parent_clauses: list[dict[str, object]] | None = None,
    ) -> None:
        current_parent = parent_clauses or [{}]

        if isinstance(node, dict):
            node_clauses = _combine_clause_sets(
                current_parent,
                _expand_when_clauses(node.get("when")),
            )

            for install_key in _INSTALL_ENTRY_KEYS:
                entries = node.get(install_key)
                if not isinstance(entries, list):
                    continue
                for entry in entries:
                    entry_when = entry.get("when") if isinstance(entry, dict) else None
                    clauses.extend(
                        _combine_clause_sets(
                            node_clauses,
                            _expand_when_clauses(entry_when),
                        )
                    )

            for key, value in node.items():
                if key in _INSTALL_ENTRY_KEYS or key == "when":
                    continue
                child_clauses = node_clauses
                if key in _PM_FAMILIES:
                    child_clauses = _combine_clause_sets(
                        node_clauses,
                        [{"plat.pm": key}],
                    )
                visit(value, parent_clauses=child_clauses)
            return

        if isinstance(node, list):
            for entry in node:
                visit(entry, parent_clauses=current_parent)

    visit(manifest)
    return clauses


def _expand_when_clauses(when: object) -> list[dict[str, object]]:
    """Normalize an OR-when spec and split exact-value lists into distinct clauses."""
    expanded: list[dict[str, object]] = []
    for clause in _normalize_when_clauses(when):
        expanded.extend(_expand_clause(clause))
    return expanded or [{}]


def _normalize_when_clauses(when: object) -> list[dict[str, object]]:
    """Return a when-spec as a list of AND-clauses."""
    if when is None:
        return [{}]
    if isinstance(when, dict):
        return [when]
    if isinstance(when, list):
        clauses: list[dict[str, object]] = []
        for clause in when:
            clauses.extend(_normalize_when_clauses(clause))
        return clauses or [{}]
    return [{}]


def _expand_clause(clause: dict[str, object]) -> list[dict[str, object]]:
    """Expand exact-value lists in a clause into separate OR branches."""
    clauses = [dict(clause)]
    for key in _EXPANDABLE_WHEN_KEYS:
        values = _extract_exact_values(clause.get(key))
        if not values:
            continue

        normalized_values = sorted(values)
        if len(normalized_values) == 1:
            for entry in clauses:
                entry[key] = normalized_values[0]
            continue

        expanded: list[dict[str, object]] = []
        for entry in clauses:
            for value in normalized_values:
                new_entry = dict(entry)
                new_entry[key] = value
                expanded.append(new_entry)
        clauses = expanded

    return clauses


def _combine_clause_sets(
    left: list[dict[str, object]],
    right: list[dict[str, object]],
) -> list[dict[str, object]]:
    """Combine OR-clause sets by AND-ing each left/right pair."""
    out: list[dict[str, object]] = []
    for left_clause in left or [{}]:
        for right_clause in right or [{}]:
            merged = dict(left_clause)
            merged.update(right_clause)
            out.append(merged)
    return out or [{}]


def _clause_matches_pm(clause: dict[str, object], pm: str) -> bool:
    """Return whether *clause* can apply to the given package-manager family."""
    pm_condition = clause.get("plat.pm")
    if pm_condition is None:
        return True

    exact_values = _extract_exact_values(pm_condition)
    if exact_values is not None:
        return pm in exact_values

    excluded_values = _extract_excluded_values(pm_condition)
    if excluded_values is not None:
        return pm not in excluded_values

    return True


def _clauses_are_compatible(
    option_clause: dict[str, object],
    support_clause: dict[str, object],
) -> bool:
    """Return whether two when-clauses can match the same platform."""
    shared_keys = frozenset(option_clause) & frozenset(support_clause)
    for key in shared_keys:
        if not _conditions_overlap(option_clause[key], support_clause[key]):
            return False
    return True


def _conditions_overlap(left: object, right: object) -> bool:
    """Return whether two scalar/list equality-style conditions can overlap."""
    left_exact = _extract_exact_values(left)
    right_exact = _extract_exact_values(right)
    if left_exact is not None and right_exact is not None:
        return bool(left_exact & right_exact)

    left_excluded = _extract_excluded_values(left)
    if left_excluded is not None and right_exact is not None:
        return any(value not in left_excluded for value in right_exact)

    right_excluded = _extract_excluded_values(right)
    if right_excluded is not None and left_exact is not None:
        return any(value not in right_excluded for value in left_exact)

    return True


def _extract_exact_values(value: object) -> frozenset[str] | None:
    """Return exact match values from a condition, if it is equality-based."""
    if isinstance(value, str):
        return frozenset({value})

    if isinstance(value, list):
        members = {item for item in value if isinstance(item, str)}
        return frozenset(members) if members else None

    if isinstance(value, dict):
        eq_value = value.get("eq")
        if eq_value is None or "ne" in value:
            return None
        return _extract_exact_values(eq_value)

    return None


def _extract_excluded_values(value: object) -> frozenset[str] | None:
    """Return exact values excluded by a ``ne`` condition, if derivable."""
    if not isinstance(value, dict):
        return None
    ne_value = value.get("ne")
    if ne_value is None or "eq" in value:
        return None
    return _extract_exact_values(ne_value)


def _common_restriction_keys(
    clauses: list[dict[str, object]],
    *,
    present_keys: frozenset[str],
) -> frozenset[str]:
    """Return restriction keys shared by every clause but absent from the option."""
    if not clauses:
        return frozenset()

    common = set(_AUTO_METHOD_RESTRICTION_KEYS)
    for clause in clauses:
        common &= {key for key in clause if key in _AUTO_METHOD_RESTRICTION_KEYS}
    return frozenset(common - set(present_keys))
