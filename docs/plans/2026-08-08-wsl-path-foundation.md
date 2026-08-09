# WSL PATH Foundation Implementation Plan

> **For Hermes:** Use subagent-driven-development to implement this plan task-by-task, with strict RED-GREEN-REFACTOR and independent review before each commit.

**Goal:** Build a deterministic, startup-safe PATH foundation that keeps Jupiter's agentic-development stack Linux-native while preserving an explicit, curated Windows 11 and WezTerm interoperability tier.

**Architecture:** Add a builtin-only platform detector and a literal PATH composition library. The library classifies entries, preserves safe precedence, and supports `preserve`, `curated`, and `linux-only` policies without editing WSL or Windows configuration. Diagnostics consume the same model later through `dood status` and `dood doctor`.

**Tech Stack:** Bash 4.4+, dependency-free Bash tests, WSL 2, Windows interoperability, WezTerm; optional ShellCheck and shfmt when installed.

---

## Spec Evaluation Gate

### Intent

Jupiter must behave as a dependable Linux agentic-development workstation, not a Linux shell accidentally inheriting a large Windows application PATH. Linux Git, language runtimes, Docker, KoadOS, and Crew commands must win while selected Windows GUI/development tools remain intentionally reachable.

### Fixed constraints

- No live `.bashrc`, `.profile`, `/etc/wsl.conf`, `.wslconfig`, or `.wezterm.lua` edits.
- No external command runs during normal PATH startup composition.
- No `eval` or sourcing of configuration data.
- Minimum Bash remains 4.4.
- WSL environment variables are supporting evidence, not required truth.
- Current rollout policy is `preserve`; `curated` becomes Jupiter's default only after canary approval.
- Project files remain under `/home/ideans` unless Windows ownership is required.

### Top risks

1. A Windows executable shadows a Linux development or KoadOS command.
2. PATH normalization corrupts entries containing spaces or hostile shell text.
3. Platform detection works interactively but fails in sanitized agent/service environments.

### Resolved design questions

1. **Should Jupiter immediately disable WSL's broad Windows PATH append?** No; preserve the host setting until DoodBash canaries prove curated composition.
2. **Should curated Windows interoperability be global or host-specific?** Host-specific, because installation paths and usernames vary.
3. **Should DoodBash own WezTerm configuration?** No; DoodBash detects and diagnoses WezTerm while its Windows Lua configuration remains separately owned.

### Safer counterproposal adopted

Do not disable WSL's `appendWindowsPath` globally during this phase. First implement deterministic filtering and a read-only audit inside disposable shells. Consider `/etc/wsl.conf` changes only as a separate, explicit host-administration decision after DoodBash can operate safely with either setting.

### Acceptance examples

- Given a mixed PATH containing Linux and Windows Git, when `curated` composition runs, Linux Git remains first and Windows Git is absent unless explicitly allowlisted.
- Given `microsoft-standard-WSL2` with no WSL environment variables, platform detection returns `wsl`.
- Given a path containing spaces or `$(touch ...)`, normalization preserves it literally and executes nothing.
- Given repeated bootstrap, PATH is byte-for-byte unchanged after the first composition.
- Given `TERM_PROGRAM=WezTerm`, platform metadata records WezTerm without invoking `wezterm.exe`.

## Worktree and branch

Implement from the clean pushed baseline:

```bash
cd /home/ideans/.doodbash
git switch -c feature/wsl-path-foundation
```

Do not implement directly on `main`.

## Task 1: Add deterministic PATH test fixtures

**Objective:** Represent Linux-only, mixed WSL/Windows, duplicate, hostile, and space-containing PATH inputs without consulting the live environment.

**Files:**

- Create: `tests/fixtures/path/linux.path`
- Create: `tests/fixtures/path/mixed-wsl.path`
- Create: `tests/fixtures/path/duplicates.path`
- Create: `tests/fixtures/path/hostile.path`
- Create: `tests/test-path.sh`

**Step 1: Write a failing fixture-loader test**

Use one PATH entry per fixture line. `tests/test-path.sh` must read fixtures into indexed arrays without sourcing them.

```bash
path_fixture_load() {
  local fixture="$1" line
  PATH_FIXTURE=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    PATH_FIXTURE+=("$line")
  done <"$fixture"
}
```

Test that `mixed-wsl.path` preserves `/mnt/c/Program Files/WezTerm` as one element.

**Step 2: Run the focused test**

```bash
bash tests/test-path.sh
```

Expected: FAIL because fixture helpers or files do not yet exist.

**Step 3: Add minimal fixture data and helper**

Include:

```text
/home/ideans/.local/bin
/usr/bin
/mnt/c/Program Files/WezTerm
/mnt/c/Windows/System32
```

The hostile fixture includes a literal string such as `/tmp/$(touch SHOULD_NOT_EXIST)` and asserts no marker is created.

**Step 4: Run tests**

```bash
bash tests/test-path.sh
tests/run
```

Expected: PASS.

**Step 5: Commit**

```bash
git add tests/fixtures/path tests/test-path.sh
git commit -m "test: add mixed path fixtures"
```

## Task 2: Detect WSL with Bash builtins

**Objective:** Detect ordinary Linux versus WSL even when harnesses sanitize WSL environment variables.

**Files:**

- Create: `core/platform.sh`
- Extend: `tests/test-path.sh`

**Step 1: Write failing tests**

Test these inputs:

```text
6.6.87.2-microsoft-standard-WSL2 -> wsl
5.15.0-Microsoft-standard-WSL2  -> wsl
6.8.0-60-generic                -> linux
```

Also test `DOOD_TEST_KERNEL_RELEASE` and absence of `WSL_DISTRO_NAME`/`WSL_INTEROP`.

**Step 2: Verify RED**

```bash
bash tests/test-path.sh
```

Expected: FAIL because `dood_platform_detect` is undefined.

**Step 3: Implement the minimal detector**

Required API:

```bash
dood_platform_detect
dood_platform_is_wsl
dood_terminal_detect
```

Implementation constraints:

- Read `/proc/sys/kernel/osrelease` with `IFS= read -r`.
- Use a test override before `/proc`.
- Case-fold using Bash parameter expansion.
- Return `wsl`, `linux`, or `unknown`.
- Return `wezterm` from terminal detection only when `TERM_PROGRAM=WezTerm`; otherwise `other`.
- Do not invoke `uname`, `wsl.exe`, PowerShell, or WezTerm.

**Step 4: Verify GREEN**

```bash
bash -n core/platform.sh tests/test-path.sh
bash tests/test-path.sh
tests/run
```

Expected: PASS.

**Step 5: Commit**

```bash
git add core/platform.sh tests/test-path.sh
git commit -m "feat: detect wsl without startup subprocesses"
```

## Task 3: Split and join PATH literally

**Objective:** Convert PATH strings to indexed arrays and back without evaluating entries.

**Files:**

- Create: `core/path.sh`
- Extend: `tests/test-path.sh`

**Step 1: Write failing tests**

Required behaviors:

- Preserve spaces.
- Preserve literal `$()`, backticks, semicolons, backslashes, and glob characters.
- Preserve entry order.
- Represent empty entries for audit before normalization.
- Join with exactly one `:` delimiter between entries.

Required API:

```bash
dood_path_split STRING ARRAY_NAME
dood_path_join ARRAY_NAME
```

Use Bash 4.4 namerefs only after validating the supplied array name against `[a-zA-Z_][a-zA-Z0-9_]*`. Raw PATH entries are values, never variable names or associative-array keys.

**Step 2: Verify RED**

```bash
bash tests/test-path.sh
```

Expected: FAIL because `core/path.sh` does not exist.

**Step 3: Implement with indexed arrays**

Use `IFS=:` and `read -r -a` only after adding tests for leading, trailing, and adjacent delimiters. If Bash `read -a` loses required empty entries, implement a bounded builtin-only parser instead.

**Step 4: Verify GREEN**

```bash
bash -n core/path.sh
bash tests/test-path.sh
tests/run
```

Expected: PASS and no hostile marker.

**Step 5: Commit**

```bash
git add core/path.sh tests/test-path.sh
git commit -m "feat: add literal path parsing primitives"
```

## Task 4: Classify and normalize PATH entries

**Objective:** Identify Linux and Windows-mounted entries and deduplicate them safely.

**Files:**

- Extend: `core/path.sh`
- Extend: `tests/test-path.sh`

**Step 1: Write failing classification tests**

Required API:

```bash
dood_path_classify ENTRY
dood_path_normalize STRING
```

Expected classifications:

```text
/usr/bin                            linux
/home/ideans/.local/bin             linux
/mnt/c/Windows/System32             windows
/mnt/D/Tools                        windows
relative/bin                        relative
""                                  empty
```

Normalization tests must prove:

- First occurrence wins.
- Linux comparison is case-sensitive.
- Windows-mounted comparison is ASCII case-insensitive.
- Trailing `/` is ignored except for `/`.
- Original spelling of the first occurrence survives.
- Raw paths are never associative-array keys.

**Step 2: Verify RED**

```bash
bash tests/test-path.sh
```

Expected: FAIL on missing classifier/normalizer.

**Step 3: Implement minimal linear comparison**

Use indexed arrays and nested direct string comparisons. PATH length is small; O(n²) startup work avoids unsafe associative subscripts and is acceptable after benchmarking.

**Step 4: Verify GREEN**

```bash
bash tests/test-path.sh
tests/run
```

Expected: PASS.

**Step 5: Commit**

```bash
git add core/path.sh tests/test-path.sh
git commit -m "feat: classify and normalize mixed paths"
```

## Task 5: Compose explicit PATH policies

**Objective:** Implement `preserve`, `curated`, and `linux-only` without touching live PATH unless the caller explicitly applies the result.

**Files:**

- Extend: `core/path.sh`
- Extend: `tests/test-path.sh`

**Step 1: Write failing policy tests**

Required API:

```bash
dood_path_compose POLICY INHERITED WINDOWS_ALLOWLIST
dood_path_apply STRING
```

`dood_path_compose` prints or stores a result and never exports PATH. Only `dood_path_apply` exports an already-composed value.

Assertions:

- `preserve` removes empty and exact duplicate entries while preserving inherited precedence.
- `curated` removes inherited Windows entries, retains Linux entries, and appends approved Windows entries.
- `linux-only` removes all Windows entries.
- Unknown policies return exit 2.
- All policies are idempotent.

**Step 2: Verify RED**

```bash
bash tests/test-path.sh
```

Expected: FAIL.

**Step 3: Implement minimal policy composition**

Do not check directory existence during composition. Keep validation for diagnostics.

**Step 4: Verify GREEN**

```bash
bash tests/test-path.sh
tests/run
```

Expected: PASS.

**Step 5: Commit**

```bash
git add core/path.sh tests/test-path.sh
git commit -m "feat: compose explicit path policies"
```

## Task 6: Load the Jupiter Windows allowlist as data

**Objective:** Define the selected Windows interoperability tier without sourcing host configuration.

**Files:**

- Create: `config/hosts/jupiter.windows-paths`
- Extend: `core/path.sh`
- Extend: `tests/test-path.sh`

**Step 1: Write failing parser tests**

Required API:

```bash
dood_path_load_allowlist FILE required|optional
```

Tests cover blank lines, leading-`#` comments, spaces, CRLF, missing required/optional files, relative entries, and unreadable files. A failed load must leave the prior allowlist unchanged.

**Step 2: Verify RED**

```bash
bash tests/test-path.sh
```

Expected: FAIL.

**Step 3: Add the reviewed Jupiter list**

Initial candidates:

```text
/mnt/c/Windows
/mnt/c/Windows/System32
/mnt/c/Program Files/PowerShell/7
/mnt/c/Program Files/WezTerm
/mnt/c/Users/idean/AppData/Local/Programs/Microsoft VS Code/bin
/mnt/c/Program Files/LM Studio
```

Do not add Windows Git, Node, Python, npm-global, `WindowsApps`, Chocolatey, Scoop, or SDK directories during this task.

**Step 4: Verify GREEN**

```bash
bash tests/test-path.sh
tests/run
```

Expected: PASS.

**Step 5: Commit**

```bash
git add config/hosts/jupiter.windows-paths core/path.sh tests/test-path.sh
git commit -m "feat: add jupiter windows interop allowlist"
```

## Task 7: Produce read-only audit findings

**Objective:** Build structured findings for later `status` and `doctor` commands without executing candidate tools.

**Files:**

- Extend: `core/path.sh`
- Extend: `tests/test-path.sh`

**Step 1: Write failing tests**

Required API:

```bash
dood_path_audit STRING
dood_path_resolve_all TOOL STRING
```

Findings must cover:

- Empty and relative entries.
- Exact and Windows-equivalent duplicates.
- Windows entries before Linux system paths.
- Critical command candidates found in Windows paths.
- Critical KoadOS commands resolving under `/mnt/<drive>`.

Tests use fake executable files under temporary Linux and `/tmp`-modeled Windows trees. Do not inspect the live PATH.

**Step 2: Verify RED**

```bash
bash tests/test-path.sh
```

Expected: FAIL.

**Step 3: Implement structured results**

Store findings in indexed arrays with stable tab-separated fields. Do not add human formatting or JSON yet; `core/output.sh`, `status`, and `doctor` will consume the results later.

**Step 4: Verify GREEN**

```bash
bash tests/test-path.sh
tests/run
```

Expected: PASS.

**Step 5: Commit**

```bash
git add core/path.sh tests/test-path.sh
git commit -m "feat: audit mixed path resolution"
```

## Task 8: Integrate platform and PATH metadata into the kernel plan

**Objective:** Make bootstrap, status, and doctor consume one platform/PATH model without implementing live startup cutover.

**Files:**

- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/plans/2026-08-08-doodbash-v0-kernel.md`
- Extend: `tests/test-path.sh`

**Step 1: Add integration expectations**

Document this bootstrap order:

```text
core/platform.sh
core/path.sh
core/config.sh
configuration layers
PATH policy composition
module loader
```

`status` reports policy/platform/terminal. `doctor` consumes audit findings. Neither invokes Windows commands.

**Step 2: Add an idempotence test**

Compose and apply the same fixture twice in a disposable Bash subprocess. Assert byte-identical PATH after the second application.

**Step 3: Verify**

```bash
bash tests/test-path.sh
tests/run
git diff --check
```

Expected: PASS.

**Step 4: Commit**

```bash
git add docs/ARCHITECTURE.md docs/plans/2026-08-08-doodbash-v0-kernel.md tests/test-path.sh
git commit -m "docs: integrate wsl path model into kernel"
```

## Task 9: Add a disposable Jupiter canary

**Objective:** Compare policies against the real inherited environment without editing shell startup state.

**Files:**

- Create: `tests/canary/path-jupiter.sh`
- Create: `docs/PATH_CANARY.md`

**Step 1: Implement a read-only canary**

The script must:

- Refuse to run unless WSL is detected.
- Snapshot inherited PATH.
- Compute all three policies without applying them to the parent shell.
- Resolve Git, gh, Docker, Node, npm, Python, KoadOS, Hermes, Clyde, PowerShell, WezTerm, Explorer, VS Code, and LM Studio candidates.
- Print a diff-like report.
- Exit nonzero if curated PATH shadows a critical Linux/KoadOS tool.
- Never edit files outside its temporary directory.

**Step 2: Verify in a disposable shell**

```bash
env -i HOME="$HOME" USER="$USER" TERM=xterm-256color \
  bash --noprofile --norc tests/canary/path-jupiter.sh --fixture tests/fixtures/path/mixed-wsl.path
```

Expected: PASS using fixture mode.

**Step 3: Run live audit mode only after review**

```bash
bash tests/canary/path-jupiter.sh --audit-live
```

Expected: read-only report; parent PATH unchanged.

**Step 4: Measure overhead**

Compare 50 disposable shell launches with and without sourcing `core/platform.sh` and `core/path.sh`. Target added median overhead: no more than 5 ms on Jupiter. Record the observed result; do not fabricate a pass if the measurement exceeds the target.

**Step 5: Commit**

```bash
git add tests/canary/path-jupiter.sh docs/PATH_CANARY.md
git commit -m "test: add jupiter path canary"
```

## Task 10: Final verification and merge readiness

**Objective:** Prove the PATH foundation is safe to integrate into the remaining v0 kernel.

**Verification:**

```bash
bash -n core/platform.sh core/path.sh tests/test-path.sh tests/canary/path-jupiter.sh
tests/run
git diff --check
git status --short --branch
```

When installed, also run:

```bash
shellcheck core/platform.sh core/path.sh tests/test-path.sh tests/canary/path-jupiter.sh
shfmt -d core/platform.sh core/path.sh tests/test-path.sh tests/canary/path-jupiter.sh
```

Request independent fail-closed review focused on:

- Bash 4.4 compatibility.
- Raw PATH strings never used as associative-array subscripts.
- No command execution from PATH/config data.
- Policy idempotence.
- Windows/Linux precedence.
- No live configuration writes.

After review passes:

```bash
git push -u origin feature/wsl-path-foundation
```

Do not merge, change the Jupiter host default to `curated`, or edit live startup files as part of this plan.

## Phase Handoff

After this foundation is green, resume the v0 kernel in this order:

1. Configuration layer resolution.
2. Bypassable bootstrap using the platform/PATH model.
3. Module manifest.
4. `dood` dispatcher.
5. `dood status` with platform/PATH metadata.
6. `dood doctor` with PATH audit findings.
7. First read-only KoadOS/Crew module.
8. Disposable and Jupiter canary review before migration.
