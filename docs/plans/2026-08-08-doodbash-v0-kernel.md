# DoodBash v0 Kernel Implementation Plan

> **For Hermes:** Use strict test-driven development for each behavior slice. Do not modify live shell startup files.

**Goal:** Build an isolated, dependency-light DoodBash kernel with literal configuration layering, deterministic module loading, PATH helpers, and read-only `dood status`/`doctor` commands.

**Architecture:** Interactive shell startup and explicit command execution are separate paths sharing trusted configuration and output libraries. Tests run with temporary HOME/XDG directories and source only the isolated project. PimpedBash is never sourced or modified.

**Tech Stack:** Bash 4.4+, Git, dependency-free Bash test harness initially; optional ShellCheck, shfmt, and Bats gates when those tools are installed.

---

## Safety Contract

- Work only under `/home/ideans/.doodbash`.
- Do not edit `~/.bashrc`, `~/.profile`, `~/.bash_profile`, or `~/.pimpedbash`.
- Do not source DoodBash into the current Hermes shell.
- Do not invoke agent launch, Citadel lifecycle, sudo, package installation, or network operations.
- Tests must use temporary HOME/XDG roots and clean them up.
- No production function is added without first observing its focused test fail for the expected missing behavior.

## Task 1: Initialize the isolated repository and test harness

**Objective:** Establish version control and a dependency-free test runner without creating live integration.

**Files:**

- Create: `.gitignore`
- Create: `VERSION`
- Create: `tests/testlib.sh`
- Create: `tests/run`

**Steps:**

1. Initialize Git with branch `main` in `/home/ideans/.doodbash`.
2. Add ignore rules for local configuration, caches, state, coverage, and temporary files.
3. Set initial version `0.0.0-dev`.
4. Implement test assertions and temporary-root setup in `tests/testlib.sh`.
5. Implement `tests/run` to execute ordered `tests/test-*.sh` files in fresh Bash processes.
6. Run the empty harness; expect exit 0 and zero production behavior.

## Task 2: Configuration parser tracer bullet

**Objective:** Parse one literal `KEY=VALUE` file without executing its value.

**Files:**

- Create test first: `tests/test-config.sh`
- Create after RED: `core/config.sh`
- Create after RED: `config/defaults.conf`

**RED behavior:**

- Loading `DOOD_COLOR=auto` stores `auto`.
- Loading `DANGER=$(touch PATH)` stores the literal string and does not create PATH.
- Source provenance includes file and line.

**GREEN API:**

```bash
dood_config_reset
dood_config_set KEY VALUE SOURCE
dood_config_load_file PATH required|optional
dood_config_get KEY [DEFAULT]
dood_config_has KEY
dood_config_source KEY
```

**Follow-up TDD slices:**

- Reject missing `=`.
- Reject invalid keys and leading whitespace.
- Ignore blank and leading-`#` comment lines.
- Preserve additional `=` characters in values.
- Remove trailing carriage return.
- Missing optional file succeeds; missing required file fails.
- Later file overrides value and provenance.

Run after each slice:

```bash
tests/test-config.sh
tests/run
```

## Task 3: Configuration layer resolver

**Objective:** Resolve defaults, profile, host, and local files in fixed order.

**Files:**

- Extend test first: `tests/test-config.sh`
- Modify after RED: `core/config.sh`
- Create after RED: `config/profiles/personal.conf`
- Create after RED: `config/hosts/jupiter.conf`

**RED behavior:**

- Defaults are required.
- Profile is required.
- Host and local files are optional.
- Local wins over host, host over profile, profile over defaults.
- `DOOD_PROFILE` and `DOOD_HOST_OVERRIDE` select layers.
- Provenance identifies the winning layer.

**GREEN API:**

```bash
dood_config_load_layers ROOT
```

The test supplies temporary root and XDG paths; it does not depend on the live hostname.

## Task 4: PATH helpers

**Objective:** Compose PATH deterministically without external processes.

**Files:**

- Create test first: `tests/test-path.sh`
- Create after RED: `core/path.sh`

**TDD slices:**

1. `dood_path_contains` finds exact path entries.
2. `dood_path_prepend` does not duplicate an existing entry.
3. `dood_path_append` does not duplicate an existing entry.
4. `dood_path_remove` removes all exact duplicates.
5. `dood_path_normalize` preserves first occurrence and removes empty entries.

Run after each slice:

```bash
tests/test-path.sh
tests/run
```

## Task 5: Interactive bootstrap and module manifest

**Objective:** Load the isolated shell kernel once and support a hard bypass.

**Files:**

- Create test first: `tests/test-startup.sh`
- Create after RED: `bashrc`
- Create after RED: `core/bootstrap.sh`
- Create after RED: `core/module.sh`
- Create after RED: `config/modules.list`

**TDD slices:**

1. Non-interactive sourcing has no effect.
2. `DOODBASH_DISABLE=1` has no effect.
3. Interactive sourcing sets one loaded-root sentinel.
4. Repeated sourcing is idempotent.
5. Empty module manifest succeeds.
6. Invalid or duplicate module IDs fail in a disposable shell with an actionable message.
7. Manifest IDs cannot provide arbitrary paths.

Test using fresh `bash --noprofile --norc` subprocesses; never source into the parent Hermes shell.

## Task 6: Command runtime, registry, and dispatcher

**Objective:** Provide a discoverable `dood` executable with direct function dispatch.

**Files:**

- Create test first: `tests/test-dispatcher.sh`
- Create after RED: `bin/dood`
- Create after RED: `core/runtime.sh`
- Create after RED: `core/output.sh`
- Create after RED: `commands/registry.sh`

**TDD slices:**

1. `dood --version` prints `VERSION`.
2. `dood --help` lists registered commands.
3. Unknown command fails with usage exit 2.
4. Registry resolves exact command paths without `eval`.
5. `--no-color` and non-TTY output contain no ANSI escapes.
6. `--format` accepts only `human` and `json`.

Do not implement dynamic plugins or mutation commands.

## Task 7: Read-only status

**Objective:** Report effective DoodBash state without deep probes or mutation.

**Files:**

- Create test first: `tests/test-status.sh`
- Create after RED: `commands/status.sh`
- Modify after RED: `commands/registry.sh`

**TDD slices:**

- Report version and root.
- Report selected profile and host.
- Report loaded layers and configured modules.
- Report command availability for core optional tools without invoking them.
- Human output is stable.
- JSON output is valid and contains no ANSI sequences.

A fake PATH provides deterministic capability tests.

## Task 8: Read-only doctor

**Objective:** Diagnose only DoodBash kernel integrity.

**Files:**

- Create test first: `tests/test-doctor.sh`
- Create after RED: `commands/doctor.sh`
- Modify after RED: `commands/registry.sh`

**TDD slices:**

- Pass supported Bash version.
- Fail missing required project file.
- Fail invalid configuration.
- Fail duplicate/invalid module IDs.
- Warn for optional missing tools.
- Detect duplicate PATH entries.
- Never create, repair, install, start, stop, or modify external state.

## Task 9: Project quality gates

**Objective:** Make the verified kernel easy to check without taking over the live shell.

**Files:**

- Create: `Makefile`
- Create: `README.md`
- Create: `docs/DEVELOPMENT.md`

**Commands:**

```bash
make syntax
make test
make check
```

Rules:

- `syntax` runs `bash -n` over tracked Bash sources and executables.
- `test` runs `tests/run`.
- `check` runs syntax and tests, then ShellCheck/shfmt only when installed; absent optional linters are reported as skipped, not falsely passed.
- README documents isolated use only and states that no live installer exists yet.

## Task 10: Pre-canary review

**Objective:** Prove the scaffold is isolated and ready for review, not live cutover.

**Verification:**

1. `git status --short` shows only intended DoodBash files.
2. `git diff --check` passes.
3. `make check` passes.
4. Search production files for `eval`, `sudo`, `systemctl`, `koad boot`, network clients, and writes to shell startup paths; expect none in the v0 kernel.
5. Confirm `~/.bashrc`, `~/.profile`, `~/.bash_profile`, and `~/.pimpedbash` were not modified by this work.
6. Run an ad-hoc temporary-HOME smoke test.
7. Request review before any installer, symlink, source block, KoadOS module, or PimpedBash retirement work.

## Commit Strategy

Commit only after each vertical slice is green:

```text
chore: initialize doodbash test harness
feat: add literal configuration parser
feat: resolve layered configuration
feat: add deterministic path helpers
feat: add bypassable shell bootstrap
feat: add dood command dispatcher
feat: add read-only status command
feat: add read-only doctor command
docs: document isolated v0 kernel
```

No push or remote creation is part of this plan.
