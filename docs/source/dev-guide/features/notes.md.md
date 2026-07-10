# `notes.md`

`features/<feature-id>/notes.md` is an optional markdown document for user-facing supplemental documentation that does not fit in `metadata.yaml`. Its content is appended to the auto-generated feature reference page on the docs site by `proman-gen-docs-data`.

:::{note}
Do not confuse `notes.md` with the other optional per-feature docs, which are **not** published to the site and are **not** read by the build pipeline:

- **`dev-notes.md`** — developer-only notes (design decisions, research, implementation rationale).
- **`tool-ref.md`** — a developer research reference on the tool's installation methods (templated from `features/tool-ref.template.md`).

Only `notes.md` feeds the generated feature page.
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

- Use only level-2 (`##`) headings and deeper — no H1 (`#`). The page title is injected by the generator.
- Each H2 should represent a distinct topic.
- All sections are optional; include only what is relevant to the specific feature.

## Common Section Topics

These are common but not required — include them when they apply:

**`## Supported Installation Methods`** — explain the methods available, their trade-offs, platform limitations, and any method-specific behavior the user should know before choosing.

**`## Version Selection`** — explain how version selection works, especially if behavior varies by method or platform.

**`## Installation Path`** — explain path configuration, platform differences, and PATH export behavior.

**`## User Configuration`** — explain how per-user configuration works, who gets configured, and any root-vs-non-root differences.
