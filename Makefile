.PHONY: format format-check lint sync sync-check test-unit gen-docs gen-docs-check docs docs-serve

# Apply shfmt formatting to all tracked shell files.
# test/unit/bats/** is excluded via .editorconfig ignore = true.
# Pass FILES="f1 f2 ..." to format specific files only.
# No-op if shfmt is not on PATH.
format:
ifdef FILES
	shfmt -w $(FILES)
else
	shfmt -w --apply-ignore .
endif

# Check formatting without writing — exit non-zero if any file differs.
# Used in CI; run 'make format' to fix locally.
# Pass FILES="f1 f2 ..." to check specific files only (used by lefthook).
# No-op if shfmt is not on PATH.
format-check:
ifdef FILES
	shfmt -d $(FILES)
else
	shfmt -d --apply-ignore .
endif

# Run shellcheck on all tracked shell files (no-op if shellcheck is not on PATH).
# Parallelised with xargs -P to offset the cost of external-sources=true
# re-analysing the lib/ source chain for every file.
# Pass FILES="f1 f2 ..." to check specific files only (used by lefthook).
# features/*/install.bash are body-only (no header); lint the assembled src/ copies.
lint:
ifdef FILES
	echo $(FILES) | xargs -P$$(nproc 2>/dev/null || sysctl -n hw.logicalcpu) -n8 shellcheck
else
	{ git ls-files -- '*.sh' '*.bash' | grep -v '^features/[^/]*/install\.bash$$'; find src -maxdepth 2 -name 'install.bash' 2>/dev/null; } | sort -u | xargs -P$$(nproc 2>/dev/null || sysctl -n hw.logicalcpu) -n8 shellcheck
endif

# Sync generated artifacts from canonical sources (features/ + lib/ + bootstrap.sh → src/):
#   features/*/metadata.yaml  → src/*/devcontainer-feature.json  (via scripts/sync-metadata.py)
#   features/*/metadata.yaml  → src/*/dependencies/*.yaml         (via scripts/sync-deps.py)
#   features/*/install.bash   → src/*/install.bash (header prepended by scripts/sync-argparse.py)
#   lib/                      → src/*/_lib/
#   bootstrap.sh              → src/*/install.sh
sync:
	bash sync-lib.sh

# Verify all generated artifacts are up to date (CI-style, no writes).
# Exits non-zero if any file is missing or stale.
sync-check:
	bash sync-lib.sh --check

# Run lib/ unit tests via bats-core (requires git submodules to be initialised).
test-unit:
	bash test/run-unit.sh

# Build standalone distribution artifacts into dist/.
# Accepts an optional VERSION variable: make build-dist VERSION=v1.0.0
artifacts:
	bash build-artifacts.sh $(VERSION)

# Inject auto-generated content (lib API tables, JSON options blocks) into docs.
gen-docs:
	python3 scripts/gen_docs.py

# Dry-run: exits non-zero if any doc file would be changed by gen-docs.
# Used in CI to enforce that generated docs are up to date.
gen-docs-check:
	python3 scripts/gen_docs.py --check

# Build the Sphinx documentation into docs/website/.build/.
# Requires the sysset-website conda environment (docs/environment.yaml).
docs:
	conda run -n sysset-website --no-capture-output \
		python -m sphinx -b dirhtml docs docs/website/.build \
		--keep-going --color --jobs auto

# Live-preview the docs with auto-rebuild on file changes.
# Requires the sysset-website conda environment (docs/environment.yaml).
docs-serve:
	conda run -n sysset-website --no-capture-output \
		python -m sphinx_autobuild docs docs/website/.build \
		-b dirhtml --open-browser --watch docs
