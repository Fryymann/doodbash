# PimpedBash Feature Mining Inventory

Status: Initial classification
Source: `~/.pimpedbash` on `refactor/portable-command-center` at `e7a446a`
Destination: DoodBash

This inventory classifies behavior, not ownership of PimpedBash files. No bulk copy is authorized. Each implementation must be reviewed again before reuse.

## Classification Rules

- **Port**: concept and implementation pattern are suitable with DoodBash naming and tests.
- **Rewrite**: behavior is valuable, but implementation, ownership, coupling, or interface should change.
- **Defer**: potentially useful after the v0 kernel and KoadOS/Crew module.
- **Retire**: omit unless a new concrete use case overturns the decision.

## Port Early

### Deterministic startup order

Source evidence:

- `shell/bashrc`
- `shell/lib/core.sh`
- `shell/lib/path.sh`
- `shell/lib/config.sh`
- `docs/load-order.md`
- `tests/startup.bats`
- `tests/load-order.bats`

Keep:

- Explicit source order.
- Login environment separated from interactive UI.
- Idempotent loading.
- Optional capability detection.
- No wildcard sourcing.

DoodBash change:

- Reduce the number of startup stages.
- Make the module manifest the only startup registry.
- Add a documented plain-Bash bypass from the beginning.

### PATH composition and deduplication

Source evidence:

- `shell/lib/path.sh`

Keep:

- Add/prepend helpers.
- Duplicate prevention.
- Capability-aware paths.

DoodBash change:

- Keep host paths in host configuration.
- Make effective PATH provenance visible through `dood config explain PATH` or an equivalent diagnostic.

### Layered configuration

Source evidence:

- `shell/lib/config.sh`
- `config/defaults.conf`
- `config/profiles/*.conf`
- `config/hosts/*.conf`
- `config/tools.conf`
- `tests/config-parser.bats`
- `tests/host-selection.bats`

Keep:

```text
defaults -> profile -> host -> untracked local override -> command override
```

DoodBash change:

- Rename all state and variables cleanly; no `PB_*` compatibility surface.
- Start with one profile and one host while retaining the layering contract.
- Validate unknown keys and explain value provenance.

### Status, doctor, and output conventions

Source evidence:

- `libexec/pimpedbash/status`
- `libexec/pimpedbash/doctor`
- `libexec/pimpedbash/security-check`
- `libexec/pimpedbash/_common`
- `tests/status.bats`
- `tests/output.bats`

Keep:

- Distinct pass, warning, failure, and recommendation states.
- Graceful handling of absent optional tools.
- Human-readable and structured output modes.
- Stable exit behavior.

DoodBash change:

- `dood status` reports facts and never repairs.
- `dood doctor` diagnoses and recommends but does not silently mutate.
- Repair actions, if later added, are separate explicit commands.

### Test strategy

Source evidence:

- Focused Bats suites for startup, configuration, output, prompt, navigation, agent runtime, Citadel, tmux, and lifecycle behavior.
- ShellCheck and shfmt quality gates in the existing Makefile workflow.

Keep:

- Disposable HOME and shell-process tests.
- Syntax checks for every sourced and executable Bash file.
- ShellCheck and shfmt.
- Tests for idempotence, missing dependencies, and mutation guards.

DoodBash change:

- Do not vendor the Bats repository into the first scaffold unless offline installation requires it.
- Keep the project test tree visually separate from third-party test fixtures.

## Rewrite Early

### Command dispatcher and registry

Source evidence:

- `bin/pb`
- `libexec/pimpedbash/registry`
- `libexec/pimpedbash/_manifest`
- `tests/dispatcher.bats`

Valuable behavior:

- One discoverable command surface.
- Domain and verb dispatch.
- Help and completion derived from a registry.

Rewrite because:

- DoodBash v0 needs far fewer commands.
- Command metadata, dispatch, help, and completion should have one compact source of truth.
- The initial registry should not anticipate plugin marketplace requirements.

Target:

```text
dood <command> [subcommand] [arguments]
```

Use nested domains only where they clarify real workflows (`crew`, `citadel`, `config`).

### KoadOS shell integration

Source evidence:

- `shell/integrations/koad.sh`
- `docs/integrations/koad-cli-contract.md`

Valuable behavior:

- KoadOS remains authoritative.
- Read-only aliases and queries.
- Refusal to switch identity in place.
- Fresh runtime recommendation.

Rewrite because:

- KoadOS CLI behavior must be re-verified at implementation time.
- Short aliases should be admitted individually rather than copied as a bundle.
- `koad saveup` must not be represented as a harmless generic convenience when its operational behavior can include shutdown-related effects in this deployment.

Target:

- No KoadOS work during shell startup beyond command availability detection.
- KoadOS status and Crew ergonomics live under `dood crew` and `dood citadel`.
- Any shell aliases are optional and separately enabled.

### Crew runtime management

Source evidence:

- `config/agents/*.conf`
- `libexec/pimpedbash/_agent`
- `agent-list`, `agent-status`, `agent-start`, `agent-attach`, `agent-resume`, `agent-stop`, `agent-doctor`, `agent-env`
- `tests/agent-runtime.bats`

Valuable behavior:

- Dedicated named tmux runtimes.
- Fresh-process identity boundaries.
- Status, attach, resume, and stop workflows.
- Forbidden environment-key checks.

Rewrite because:

- Agent identity and boot policy must come from current KoadOS/harness contracts, not static DoodBash agent definitions.
- Runtime templates may describe terminal ergonomics but must not duplicate identity canon.
- `agent-env` behavior must never expose values or broaden credential scope.

Target:

```text
dood crew list
dood crew info NAME
dood crew start NAME
dood crew status [NAME]
dood crew attach NAME
dood crew stop NAME --confirm
```

### Citadel operations

Source evidence:

- `libexec/pimpedbash/_citadel`
- `citadel-status`, `citadel-doctor`, `citadel-logs`
- `citadel-start`, `citadel-stop`, `citadel-restart`, `citadel-save`
- `tests/citadel.bats`

Valuable behavior:

- Read-only status, doctor, and logs.
- Host allowlist.
- Preview by default.
- Explicit confirmation.
- Visible `sudo`.

Rewrite because:

- Service lists and current `koad` lifecycle semantics must be queried or configured rather than fossilized.
- `save` is not a generic lifecycle synonym and must not be ported until its current shutdown behavior is specified and tested.

Initial target:

- Port `status`, `doctor`, and `logs` first.
- Add start/stop/restart only after read-only commands and host guards pass.
- Retire `citadel save` from v0.

### Installer and rollback

Source evidence:

- `install`, `update`, `rollback`, `uninstall`
- `config/managed-files.conf`
- `tests/install.bats`
- `tests/update.bats`

Valuable behavior:

- Dry-run.
- Ownership checks.
- Backups.
- Rollback and convergent uninstall.

Rewrite later because:

- DoodBash must first prove itself in disposable shells.
- Initial development must not own `~/.bashrc`, `~/.profile`, or `~/.bash_profile`.
- The first canary should use explicit sourcing from an isolated shell command.

## Defer

### Prompt

Source evidence:

- `shell/modules/prompt.sh`
- `shell/lib/hooks.sh`
- `tests/prompt.bats`

Reason:

- Prompt hooks have historically caused every-command failures and hidden startup cost.
- v0 should use a deliberately plain prompt or preserve the current prompt externally until the kernel is stable.

Admission requirements:

- No network calls.
- No authentication refresh.
- Bounded Git probing.
- Composable `PROMPT_COMMAND` handling.
- Measured startup and prompt cost.

### Navigation and aliases

Source evidence:

- `shell/modules/navigation.sh`
- `shell/modules/aliases.sh`
- `config/projects.conf`
- `tests/navigation.bats`

Reason:

- Valuable personal ergonomics, but high risk of importing historical clutter.
- Port only aliases and destinations Ian identifies as currently used.

### tmux utility family

Source evidence:

- `tmux-list`, `tmux-status`, `tmux-capture`, `tmux-kill`
- `config/tmux-layouts.conf`
- `tests/tmux.bats`

Reason:

- Crew launching needs tmux, but a general tmux wrapper does not belong in the kernel.
- Add only the runtime functions required by `dood crew` first.

Security behavior worth retaining later:

- Private capture files with restrictive permissions.
- Sanitized filenames.
- Explicit target/socket handling.
- Confirmation for kill operations.

### Security check

Source evidence:

- `security-check`

Reason:

- Useful after DoodBash has an installer, local configuration, and credential boundaries to audit.
- Initial doctor should still detect obvious tracked-secret and permission mistakes relevant to the small v0 surface.

## Retire from v0

### Git fleet commands

Source evidence:

- `git-list`, `git-fetch`, `git-status`, `git-update`, `_git`

Decision:

- Retire from DoodBash v0.
- Reconsider as a separate project/fleet tool if a concrete workflow requires it.

### Package and harness orchestration

Source evidence:

- `pkg-detect`, `pkg-check`, `pkg-plan`, `pkg-apply`
- `harness-status`, `harness-plan`, `harness-apply`

Decision:

- Retire from DoodBash v0.
- These are host provisioning concerns, not interactive shell responsibilities.

### SSH command family

Source evidence:

- `ssh-list`, `ssh-info`, `ssh-check`

Decision:

- Retire from v0.
- Prefer OpenSSH configuration and direct commands until DoodBash has a demonstrated missing workflow.

### Tailscale command family

Source evidence:

- `tailscale-status`, `tailscale-peers`, `tailscale-down`

Decision:

- Retire from v0.
- Network-overlay lifecycle is not a shell-framework responsibility.

### Broad diagnostics

Source evidence:

- `diag-sys`, `diag-net`, `diag-proc`

Decision:

- Retire as a general command family.
- `dood doctor` may run narrowly scoped checks required to diagnose DoodBash and its enabled modules.

### Legacy compatibility shims

Decision:

- Retire.
- No `pb` alias, PimpedBash variable compatibility, legacy file emulation, or automatic migration during v0.
- Migration will be explicit, inspectable, and rollback-safe.

## Critical Port Order

1. Startup invariants and bypass.
2. PATH handling.
3. Configuration parsing and provenance.
4. Minimal module registry.
5. `dood status` and output conventions.
6. `dood doctor` and focused diagnostics.
7. KoadOS read-only contract verification.
8. Crew list/info/status.
9. Fresh Crew launch and tmux boundary.
10. Citadel read-only operations.
11. Guarded Citadel lifecycle operations.
12. Installer, backup, rollback, and retirement canary.

Prompt, aliases, navigation, and broader tool integrations come only after this sequence proves stable.

## Open Decisions

- Exact configuration file syntax for v0.
- Whether `dood` supports JSON in v0 or adds it with Crew integration.
- Minimum supported Bash version.
- Whether Bats is vendored, installed as a development dependency, or invoked from the existing PimpedBash copy during bootstrap.
- Naming convention for modules and command implementation files.
- Initial startup-time budget and measurement method.
