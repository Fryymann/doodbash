# DoodBash Constitution

Status: Draft v0
Target: Jupiter first, portable by construction
Primary interface: `dood`

## Mission

DoodBash is Ian's configurable Bash environment and Crew operations console. It provides a fast, understandable interactive shell plus explicit commands for environment diagnostics, tool integration, KoadOS, Citadel, and Crew workflows.

DoodBash must remain smaller and easier to reason about than the collection it replaces.

## Ownership

DoodBash owns:

- Bash login and interactive-shell composition.
- PATH, environment, aliases, functions, history, prompt, and completions.
- Declarative user, profile, host, and local configuration.
- Optional tool integrations.
- Read-only environment, KoadOS, Citadel, Crew, and tmux diagnostics.
- Safe launch ergonomics for fresh agent runtimes.
- Explicitly guarded administrative commands.

DoodBash does not own:

- KoadOS agent identity, role, rank, bio, session, or CASS partition.
- Agent credentials or global secret injection.
- Citadel's internal lifecycle implementation.
- Agent model/provider configuration.
- General Git, package-manager, SSH, or Tailscale replacement commands without a demonstrated recurring need.

KoadOS is authoritative for identity and session state. DoodBash may observe and present that state, but must not synthesize or mutate it.

## Architectural Decision 001: Thin Shell, Strong Command Suite

Interactive Bash loads a small deterministic shell layer. Heavy work runs only when the user invokes `dood`.

Proposed shape:

```text
~/.doodbash/
├── bashrc
├── profile
├── bin/dood
├── core/
├── modules/
├── commands/
├── config/
├── completions/
├── tests/
└── docs/
```

Shell startup and command execution are separate products sharing small core libraries.

## Architectural Decision 002: Jupiter First

DoodBash v0 targets Ian's Ubuntu environment under WSL on Jupiter.

Portable-by-construction means:

- Host-specific values live in host configuration.
- Optional tools are capability-detected.
- Paths are configurable rather than duplicated throughout modules.
- Core code does not assume KoadOS is installed or online.
- Another host is added only when there is a real onboarding target.

It does not mean v0 must support every Linux distribution, macOS, or generic fleet deployment.

## Architectural Decision 003: Literal Configuration Data

DoodBash uses restricted `KEY=VALUE` files for defaults, profiles, hosts, and local overrides. The parser treats values literally and never uses `source`, `eval`, interpolation, or command substitution. Configuration is not automatically exported to the process environment.

The full grammar and provenance model are defined in `docs/ARCHITECTURE.md`.

## Startup Contract

Shell startup must:

- Be deterministic and idempotent.
- Use an explicit module manifest; never wildcard-source directories.
- Avoid network, Git, service, and credential probes.
- Avoid `eval` of command output.
- Avoid mutating KoadOS identity or sessions.
- Degrade gracefully when optional tools are missing.
- Keep login environment separate from interactive UI.
- Make each loaded module attributable and diagnosable.
- Preserve an emergency bypass that starts plain Bash without DoodBash.

## Configuration Contract

Initial precedence:

```text
defaults -> selected profile -> detected host -> untracked local override -> command-scoped override
```

Requirements:

- Later layers override earlier layers predictably.
- Tracked configuration contains no secrets.
- Local configuration is optional and untracked.
- Configuration is data rather than arbitrary executable shell wherever practical.
- Unknown keys and invalid values produce actionable diagnostics.
- A command can explain the origin of an effective value.

## Module Contract

A module must be:

- Explicitly enabled.
- Independently removable.
- Safe to source more than once.
- Fast and side-effect-free during startup.
- Responsible for one coherent capability.
- Accompanied by a diagnostic check when it has external dependencies.
- Tested without sourcing the live user shell.

A module may add aliases, functions, completions, environment values, prompt segments, or `dood` subcommands. It must not silently take ownership of unrelated behavior.

## Command Contract

The primary executable is `dood`.

Initial command surface:

```text
dood status
dood doctor
dood config show
dood config explain <key>
dood crew list
dood crew info <agent>
dood crew start <agent>
dood crew status [agent]
dood citadel status
dood citadel doctor
dood citadel logs
dood citadel start|stop|restart --confirm
```

Rules:

- Read-only is the default.
- Mutations preview before execution.
- Destructive or service-affecting actions require explicit confirmation.
- `sudo` is visible and interactive; it is never hidden or silently bypassed.
- Human-readable output is the default; structured output may be requested explicitly.
- Exit codes are stable enough for scripts.
- Command discovery and completion derive from one registry rather than duplicate lists.

## KoadOS and Crew Contract

DoodBash may:

- Query registered agents and active identity using official `koad` commands.
- Present KoadOS, Citadel, CASS, and Crew status.
- Start an agent in a fresh process or dedicated tmux runtime.
- Provide read-only shortcuts and completions.

DoodBash must not:

- Write `KOAD_AGENT_NAME`, `KOAD_AGENT_ROLE`, `KOAD_AGENT_RANK`, `KOAD_AGENT_BIO`, or CASS partition variables.
- Switch an already hydrated shell from one agent to another.
- Evaluate KoadOS-generated shell exports.
- Load vault secrets into every shell.
- Guess identity from the current directory or repository metadata.
- Treat tmux pane state as canonical task, memory, or identity state.

## Feature Admission Gate

A feature enters DoodBash only if:

1. Ian has a concrete recurring use for it.
2. DoodBash is the correct owner.
3. It cannot be handled more clearly by an existing tool or a small wrapper.
4. It does not add work to every shell unless startup truly requires it.
5. It has a removable module boundary.
6. Its failure mode and rollback path are known.
7. It has focused verification.

Convenience alone is insufficient when the maintenance burden is unclear.

## PimpedBash Migration Policy

PimpedBash is a read-only source mine until an explicit retirement phase.

Every candidate feature is classified as:

- Port: behavior and implementation are both suitable.
- Rewrite: behavior is valuable but ownership or implementation is wrong.
- Defer: potentially useful but not part of v0.
- Retire: obsolete, unsafe, duplicated, or not worth maintaining.

No bulk copy is allowed. No compatibility layer is assumed. DoodBash must earn each feature independently.

The current PimpedBash branch, commit, untracked files, and stash remain protected. DoodBash development must not modify or install from that worktree.

## DoodBash v0 Kernel

The first implementation milestone contains only:

- A bypassable Bash bootstrap.
- Deterministic explicit loading.
- Configuration layering.
- PATH composition and deduplication.
- A minimal module registry.
- `dood status`.
- `dood doctor`.
- Disposable-shell tests.

KoadOS/Crew is the first module after the kernel, not part of the bootstrap.

## v0 Acceptance Contract

Given a clean disposable Bash environment:

- Loading DoodBash succeeds without KoadOS or optional tools.
- Loading it twice does not duplicate PATH entries, hooks, or prompt commands.
- Disabled modules have no effect.
- Invalid configuration fails with a useful source and key message.
- `dood status` reports host, profile, loaded modules, and capability state without mutation.
- `dood doctor` distinguishes pass, warning, failure, and recommendation.
- A plain-shell bypass remains available if DoodBash is broken.

Given an active KoadOS agent shell:

- DoodBash preserves the existing identity unchanged.
- Starting a different agent in place is refused.
- Crew launch creates a fresh runtime through KoadOS-owned boot behavior.

Given a Citadel lifecycle command:

- The default invocation previews the action.
- Execution requires an explicit confirmation flag.
- Unsupported hosts are refused.
- Service names and the visible `sudo` command are shown before execution.

## Non-Goals for v0

- General dotfile synchronization.
- Cross-platform shell support beyond Bash.
- A public plugin marketplace.
- Automatic package installation.
- Fleet-wide host orchestration.
- Replacing Git, SSH, Tailscale, tmux, systemd, or KoadOS.
- Live migration from PimpedBash.

## Change Rule

This constitution changes before implementation when a principle proves wrong. It does not silently drift through incidental code. New scope requires an explicit decision and corresponding acceptance criteria.
