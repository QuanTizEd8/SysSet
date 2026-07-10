# `notes.md`

`features/<feature-id>/notes.md` is an optional markdown document for user-facing supplemental documentation that does not fit in `metadata.yaml`. `proman-gen-docs-data` renders it as a **`Notes` child page** under the feature's generated reference page — each feature is emitted as a directory with an `index` page plus optional `notes` / `dev-notes` child pages.

:::{note}
Two sibling files are also optional:

- **`dev-notes.md`** — developer-facing notes (design decisions, implementation rationale). It is rendered as a separate **`Developer Notes` child page** and should start with a `# Developer Notes` H1.
- **`tool-ref.md`** — a developer research reference on the tool's installation methods (templated from `features/tool-ref.template.md`). Unlike the other two, it is **not** published to the site or read by the build pipeline.
:::

## What to Put Here

Focus on information that can't be expressed as YAML fields — usage notes, gotchas, and platform quirks:

- Platform-specific behavior or limitations, and workarounds
- Important interactions between options (e.g. "when using `method=source`, `version=latest` is not supported on Alpine")
- Schemas or contracts that users need to be aware of (e.g. environment variables written to the shell profile)
- Troubleshooting tips for common misconfigurations

## What to Omit

Do not repeat information already generated from `metadata.yaml`. The following sections are auto-generated and must not be added to `notes.md`:

- Example Usage
- Options (option descriptions come from `metadata.yaml`)
- Lifecycle Commands
- Installation Order
- VS Code Extensions

## Format Requirements

- Start with a single top-level `# Notes` H1, then use `##` and deeper for sections. (The generator prepends the `# Notes` heading if it is missing, but including it keeps the source self-describing.)
- Each H2 should represent a distinct topic.
- All sections are optional; include only what is relevant to the specific feature.

## Common Section Topics

These are common but not required — include them when they apply:

**`## Supported Installation Methods`** — explain the methods available, their trade-offs, platform limitations, and any method-specific behavior the user should know before choosing.

**`## Version Selection`** — explain how version selection works, especially if behavior varies by method or platform.

**`## Installation Path`** — explain path configuration, platform differences, and PATH export behavior.

**`## User Configuration`** — explain how per-user configuration works, who gets configured, and any root-vs-non-root differences.
