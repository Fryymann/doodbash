# DoodBash v0 Architecture

Status: Draft
Target host: Jupiter, Ubuntu under WSL
Installed Bash baseline on target: 5.2.21
Minimum supported Bash for v0: 4.4

## System Model

DoodBash has two execution paths:

1. **Interactive shell path** — sourced by Bash; must be fast, idempotent, and side-effect-free.
2. **Command path** — executed through `dood`; may perform diagnostics or explicit guarded operations.

The command path may reuse configuration and output libraries. It must not require the interactive shell path to have been loaded.

```text
Bash startup                     Explicit command
     |                                |
     v                                v
  bashrc                           bin/dood
     |                                |
     +--> core/bootstrap.sh           +--> core/runtime.sh
             |                                |
             +--> core/path.sh                +--> core/config.sh
             +--> core/config.sh              +--> core/output.sh
             +--> modules.list                +--> commands/registry.sh
             +--> enabled shell modules       +--> selected handler
```

## Project Layout

```text
~/.doodbash/
├── bashrc                         # Interactive entrypoint
├── profile                        # Login environment entrypoint
├── bin/
│   └── dood                       # Command dispatcher
├── core/
│   ├── bootstrap.sh               # Shell startup orchestration
│   ├── config.sh                  # Literal KEY=VALUE parser and layering
│   ├── module.sh                  # Explicit module loader
│   ├── output.sh                  # Human/structured output primitives
│   ├── path.sh                    # PATH manipulation
│   └── runtime.sh                 # Command-path bootstrap
├── modules/
│   ├── shell/
│   ├── tools/
│   └── koad/
├── commands/
│   ├── registry.sh
│   ├── status.sh
│   ├── doctor.sh
│   └── config.sh
├── config/
│   ├── defaults.conf
│   ├── modules.list
│   ├── profiles/
│   │   └── personal.conf
│   └── hosts/
│       └── jupiter.conf
├── completions/
│   └── dood.bash
├── tests/
│   ├── helpers/
│   ├── startup.bats
│   ├── config.bats
│   ├── path.bats
│   ├── dispatcher.bats
│   ├── status.bats
│   └── doctor.bats
└── docs/
```

Only files required by the active milestone are created. The layout reserves clear ownership boundaries; it does not require placeholder implementations.

## Interactive Entrypoint

`bashrc` performs only these steps:

1. Return immediately for a non-interactive shell.
2. Return when `DOODBASH_DISABLE=1`.
3. Return when the current shell already loaded the same DoodBash root.
4. Resolve the DoodBash root from `BASH_SOURCE`, with an explicit test override.
5. Source `core/bootstrap.sh`.

It does not:

- Probe the network, Git, systemd, Citadel, CASS, or KoadOS.
- Refresh credentials.
- start tmux or an agent.
- install tools.
- repair configuration.
- print banners during a normal successful startup.

### Emergency bypass

A user can always run:

```bash
DOODBASH_DISABLE=1 bash --noprofile --norc
```

The eventual live `.bashrc` integration must also use a single removable, guarded source block so the user can comment out or delete one block during recovery.

## Bootstrap Sequence

The fixed v0 sequence is:

```text
core/path.sh
core/config.sh
config layers
core/module.sh
config/modules.list
explicit enabled modules
completion setup
```

No directory glob determines load order.

Each sourced library uses an idempotence sentinel scoped to DoodBash. Loading a second time must not duplicate PATH entries, completion entries, prompt hooks, or module effects.

## Configuration Grammar

DoodBash configuration is literal data.

Accepted records:

```text
# comment
KEY=value
EMPTY=
```

Key grammar:

```text
[A-Z][A-Z0-9_]*
```

Value rules:

- Everything after the first `=` is the literal value.
- No variable expansion.
- No command substitution.
- No backslash interpretation.
- No inline comments.
- No shell quoting requirement.
- Carriage return at end-of-line is removed for CRLF tolerance.
- Leading whitespace before a key is invalid.
- Blank lines and lines whose first character is `#` are ignored.

Examples:

```text
DOOD_PROFILE=personal
DOOD_COLOR=auto
DOOD_EDITOR=nvim
DOOD_PROJECT_ROOT=/home/ideans/data/projects
```

Invalid examples:

```text
 export DOOD_COLOR=auto
DOOD-COLOR=auto
DOOD_COLOR
```

Strings such as `$HOME`, `$(command)`, backticks, semicolons, and spaces remain literal characters. They are never executed.

## Configuration Storage

The parser stores values and provenance in associative arrays:

```text
DOOD_CFG[KEY]=value
DOOD_CFG_SOURCE[KEY]=/path/file.conf:line
```

Configuration is not automatically exported. Code requests values from the configuration API, and only a small documented allowlist may enter child-process environments.

Required API shape:

```text
dood_config_set KEY VALUE SOURCE
dood_config_load_file PATH REQUIRED|OPTIONAL
dood_config_get KEY [DEFAULT]
dood_config_has KEY
dood_config_source KEY
dood_config_validate
```

No API uses `eval`.

## Layer Resolution

The fixed order is:

```text
config/defaults.conf
config/profiles/${DOOD_PROFILE:-personal}.conf
config/hosts/${DOOD_HOST_OVERRIDE:-detected-host}.conf
${XDG_CONFIG_HOME:-$HOME/.config}/doodbash/local.conf
command-scoped override
```

Rules:

- Defaults are required.
- The selected profile is required.
- Host and local files are optional.
- Missing optional layers are not warnings.
- Missing required layers are configuration errors.
- A later layer replaces an earlier value and provenance atomically.
- `DOOD_PROFILE` and `DOOD_HOST_OVERRIDE` are selection inputs, not values read from an arbitrary lower-precedence configuration file.
- Host detection uses the short hostname only when no explicit test/command override exists.

## Module Manifest

`config/modules.list` is an explicit ordered list:

```text
shell.history
shell.navigation
shell.aliases
```

Grammar:

```text
[a-z][a-z0-9_-]*(\.[a-z][a-z0-9_-]*)+
```

Blank lines and leading-`#` comments are ignored. Duplicate module IDs are errors.

Each module ID maps through trusted loader code to one repository-relative file. The manifest never supplies an arbitrary filesystem path.

Initial v0 should enable no optional behavior beyond the minimum shell kernel. Prompt, aliases, navigation, and KoadOS are introduced in later milestones.

## Module Interface

A shell module is sourced and may define one optional diagnostic function:

```text
dood_module_<normalized_id>_doctor
```

Normalization replaces dots and hyphens with underscores.

A module must:

- Guard repeated loading.
- Avoid output on successful load.
- Avoid external probes during load.
- Avoid mutating unrelated hooks or variables.
- Report missing optional dependencies through doctor, not startup noise.

The first implementation does not need general lifecycle hooks, dependency graphs, priorities, or third-party module discovery.

## PATH and Platform Contract

The full WSL/Windows/WezTerm design is recorded in `docs/WSL_WIN11_WEZTERM_PATH.md`.

`core/platform.sh` detects WSL and terminal context with Bash builtins. It does not require `WSL_DISTRO_NAME` or `WSL_INTEROP`, because agent and service environments may sanitize those variables.

`core/path.sh` provides literal parsing, classification, normalization, policy composition, and read-only audit primitives. Initial public behavior includes:

```text
dood_path_split STRING
dood_path_join
dood_path_classify ENTRY
dood_path_normalize STRING
dood_path_compose preserve|curated|linux-only INHERITED ALLOWLIST
dood_path_apply STRING
dood_path_audit STRING
```

Rules:

- Linux development, KoadOS, and Crew paths precede Windows interoperability paths.
- Preserve first occurrence when normalizing.
- Remove empty entries before applying a composed PATH.
- Compare Linux paths case-sensitively.
- Compare `/mnt/<drive>` paths case-insensitively while preserving first spelling.
- Do not use raw path strings as associative-array subscripts.
- Ignore empty additions.
- Do not require a path to exist during composition.
- Do not invoke external utilities during normal startup.
- Do not edit `/etc/wsl.conf`, `.wslconfig`, or `.wezterm.lua`.
- Export PATH only after explicit composition is complete.
- Start rollout with `preserve`; admit `curated` as Jupiter's default only after disposable and live canary verification.
- Keep Windows 11 tools in a host-specific allowlist at the tail of PATH.
- Detect WezTerm through environment metadata but never invoke it during startup.

The fixed bootstrap sequence becomes:

```text
core/platform.sh
core/path.sh
core/config.sh
configuration layers
PATH policy composition
core/module.sh
explicit enabled modules
completion setup
```

Explicit `dood win` commands may use `wslpath` or Windows executables at command time. Startup PATH composition may not.

## Command Dispatcher

`bin/dood`:

1. Resolves its repository root.
2. Loads `core/runtime.sh`.
3. Parses global flags.
4. Resolves a command through `commands/registry.sh`.
5. Invokes one handler directly.

Initial global flags:

```text
--help
--version
--no-color
--format human|json
```

Initial commands:

```text
status
doctor
config show
config explain KEY
```

Unknown commands return a non-zero exit code and a concise suggestion.

## Command Registry

The trusted Bash registry is the single source of truth for:

- command path,
- handler function,
- one-line summary,
- mutation class,
- completion metadata.

Initial mutation classes:

```text
read
preview
confirm
```

The dispatcher refuses a `confirm` command unless its handler receives and validates the required confirmation contract. v0 kernel commands are all `read`.

Do not design dynamic third-party registration in v0.

## Output Contract

Human output uses stable semantic states:

```text
PASS
WARN
FAIL
INFO
NEXT
```

Color is presentation only and is disabled when:

- stdout is not a terminal,
- `NO_COLOR` is set,
- `--no-color` is supplied,
- configuration disables it.

JSON output contains no ANSI codes and writes one complete JSON document to stdout. Diagnostics and unexpected internal errors go to stderr.

Initial exit convention:

```text
0  requested operation completed; warnings may exist
1  operational failure
2  usage or configuration error
3  guard/refusal prevented a mutation
```

More codes require a demonstrated scripting need.

## Status Contract

`dood status` is read-only and reports:

- DoodBash version/root.
- Selected profile and detected host.
- Loaded configuration layers.
- Enabled modules.
- Core tool capability presence.
- Whether KoadOS is available, without invoking it in the kernel milestone.

It does not run deep health checks.

## Doctor Contract

`dood doctor` is read-only and runs focused checks for:

- Bash version.
- Required project files.
- Configuration syntax and required keys.
- Duplicate or invalid modules.
- PATH duplicates.
- Command handler registry integrity.
- Optional tool availability as warnings.

Doctor recommends commands or files to inspect. It does not repair automatically.

## XDG Boundaries

```text
Tracked project:      ~/.doodbash
Local configuration:  ${XDG_CONFIG_HOME:-~/.config}/doodbash/local.conf
Cache:                ${XDG_CACHE_HOME:-~/.cache}/doodbash
State:                ${XDG_STATE_HOME:-~/.local/state}/doodbash
```

The v0 kernel should not need persistent cache or state. Directories are created only by features that use them.

## Security Boundaries

- No tracked secrets.
- No global secret file sourcing.
- No `eval` in configuration, dispatch, or KoadOS integration.
- No identity derivation from cwd or repository anchors.
- No startup-time mutation.
- No hidden `sudo`.
- No network activity in bootstrap.
- No arbitrary paths from the module manifest.
- No lifecycle command without preview and explicit confirmation.

## Verification Strategy

Before any live-shell integration:

1. Run `bash -n` on every Bash source and executable.
2. Run ShellCheck.
3. Run shfmt check mode.
4. Run Bats tests with a temporary HOME.
5. Spawn disposable interactive Bash processes and verify idempotence.
6. Verify `DOODBASH_DISABLE=1` bypass.
7. Verify absence of writes outside temporary test roots.
8. Measure startup separately from command diagnostics.

No passing test result authorizes a live cutover by itself. Cutover requires a separate backup and Jupiter canary plan.

## Deferred Decisions

- Final prompt design.
- Alias and navigation inventory.
- JSON implementation dependency or pure-Bash encoder boundary.
- Crew tmux naming and runtime topology.
- Citadel service discovery mechanism.
- Installer ownership and rollback format.
- Io onboarding.
