.PHONY: fmt fmt-check lint sync test-unit

# Apply shfmt formatting to all tracked shell files.
fmt:
	shfmt -w --apply-ignore .

# Check formatting without writing — exit non-zero if any file differs.
# Used in CI; run 'make fmt' to fix locally.
fmt-check:
	shfmt -d --apply-ignore .

# Run shellcheck on all tracked shell files (no-op if shellcheck is not on PATH).
lint:
	command -v shellcheck >/dev/null 2>&1 && shellcheck $(shell git ls-files -- '*.sh' '*.bash') || echo "shellcheck not found, skipping"

# Sync generated _lib/ copies and install.sh stubs from canonical sources.
sync:
	bash sync-lib.sh

# Run lib/ unit tests via bats-core (requires git submodules to be initialised).
test-unit:
	bash test/run-unit.sh
