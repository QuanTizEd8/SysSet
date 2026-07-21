# Tests

The test suite has four layers, each targeting a different scope:

| Layer | Directory | Framework | Docker needed |
|-------|-----------|-----------|---------------|
| Library unit tests | `test/lib/` | BATS (Bash Automated Testing System) | Optional* |
| Install framework tests | `test/install/` | BATS + synced `install.bash` | No (CI: yes) |
| Feature scenario tests | `test/features/<id>/` | devcontainer CLI + plain Docker | Yes (Linux) |
| Build system tests | `test/proman/` | pytest | No |

\* Library tests run natively via `run-unit.sh` (used by `just test` and `just work`); matrix recipes select a logical platform, an ordinary/bootstrap workload, and (for ordinary) a tier. The complete command uses separate prepared and bare containers as documented in {doc}`tests/lib`.

::::{grid} 1
:gutter: 3

:::{grid-item-card} Quickstart
:class-title: sd-text-center
:link: tests/quickstart
:link-type: doc

Test directory layout, which test to add for which change, and the most common run commands.
:::

:::{grid-item-card} Feature Tests
:class-title: sd-text-center
:link: tests/features
:link-type: doc

How feature tests are **auto-generated** from `metadata.yaml` (and overridden); `scenarios.yaml`/`checks.yaml` formats; running modes (devcontainer / standalone / macOS); and writing effective assertions.
:::

:::{grid-item-card} Library Unit Tests
:class-title: sd-text-center
:link: tests/lib
:link-type: doc

BATS test anatomy, `reload_lib`, stubs, subprocess isolation, and common pitfalls.
:::

:::{grid-item-card} Install Framework Tests
:class-title: sd-text-center
:link: tests/install
:link-type: doc

Unit tests for `install.tmpl.bash` orchestration via sourced synced `install.bash`.
:::

:::{grid-item-card} Live Testing
:class-title: sd-text-center
:link: tests/live
:link-type: doc

Running features interactively in a dev container for manual verification.
:::

:::{grid-item-card} Build System Tests
:class-title: sd-text-center
:link: tests/dev
:link-type: doc

pytest tests for `proman` — the Python build system.
:::

::::
