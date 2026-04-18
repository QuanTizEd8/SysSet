---
description: "Use when writing or editing devcontainer-feature.json files. Covers required options, enum vs proposals, versioning, lifecycle commands, and feature ID conventions."
applyTo: "features/**/metadata.yaml"
---

# devcontainer-feature.json Conventions

## Required Options (every feature must include these)

```jsonc
"debug":   { "type": "boolean", "default": false,  "description": "Enable debug output (set -x)." },
"logfile": { "type": "string",  "default": "",      "description": "Append install log to this file path." }
```

## `enum` vs `proposals`

These are distinct fields with different semantics:

| Field | Behavior |
|-------|---------|
| `enum` | **Strict** — tooling rejects any value not in the list. Use for closed option sets. |
| `proposals` | **Suggestive** — UI surfaces as autocomplete suggestions, but the user can type any value. Use for open-ended inputs where common values are known. |

```jsonc
// Strict: only "zsh", "bash", or "none" are accepted
"set_user_shells": {
  "type": "string",
  "default": "none",
  "enum": ["zsh", "bash", "none"]
}

// Suggestive: any version string is valid; these are common defaults shown in UI
"version": {
  "type": "string",
  "default": "0.66.0",
  "proposals": ["latest", "0.66.0", "0.65.0"]
}
```

## Feature ID and Versioning

- `id` must exactly match the directory name under `src/`
- Version follows semver: patch for bug fixes, minor for new backward-compatible options, major for breaking changes

## Lifecycle Commands

Use object form (named steps) rather than a plain string — it makes CI logs readable:

```jsonc
"postCreateCommand": {
  "step_name": "command to run after container creation"
}
```

## Common Patterns

```jsonc
// Mount a named volume to persist data across rebuilds
"mounts": [{
  "source": "${localWorkspaceFolderBasename}-cache",
  "target": "/home/vscode/.cache",
  "type": "volume"
}]

// Expose container env vars
"containerEnv": {
  "PATH": "/opt/tool/bin:${PATH}"
}

// Declare feature dependencies
"dependsOn": {
  "ghcr.io/quantized8/sysset/setup-user": {}
}
```

## Further Reading

- `docs/dev-guide/writing-features.md` — feature anatomy, options, scripts, full library reference


## Key References

- [JSON Schema for devcontainer-feature.json](https://raw.githubusercontent.com/devcontainers/spec/refs/heads/main/schemas/devContainerFeature.schema.json)
- [Full JSON Schema for devcontainer.json](https://raw.githubusercontent.com/devcontainers/spec/refs/heads/main/schemas/devContainer.schema.json)
- [Core JSON Schema for devcontainer.json](https://raw.githubusercontent.com/devcontainers/spec/refs/heads/main/schemas/devContainer.base.schema.json)
