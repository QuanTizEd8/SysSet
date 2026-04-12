.PHONY: fmt fmt-check lint sync test-unit

# Apply shfmt formatting to all tracked shell files.
# test/unit/bats/** is excluded via .editorconfig ignore = true.
fmt:
	shfmt -w --apply-ignore .

# Check formatting without writing — exit non-zero if any file differs.
# Used in CI; run 'make fmt' to fix locally.
fmt-check:
	shfmt -d --apply-ignore .

# Run shellcheck on all tracked shell files (no-op if shellcheck is not on PATH).
# Parallelised with xargs -P to offset the cost of external-sources=true
# re-analysing the lib/ source chain for every file.
lint:
	command -v shellcheck >/dev/null 2>&1 && git ls-files -- '*.sh' '*.bash' | xargs -P$$(nproc 2>/dev/null || sysctl -n hw.logicalcpu) -n8 shellcheck || echo "shellcheck not found, skipping"

# Sync generated _lib/ copies and install.sh stubs from canonical sources.
sync:
	bash sync-lib.sh

# Run lib/ unit tests via bats-core (requires git submodules to be initialised).
test-unit:
	bash test/run-unit.sh

# Build standalone distribution artifacts into dist/.
# Accepts an optional VERSION variable: make artifacts VERSION=v1.0.0
artifacts:
	bash build-artifacts.sh $(VERSION)
