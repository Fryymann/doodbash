# WSL, Windows 11, and WezTerm PATH Strategy

Status: Accepted design for the next development phase

Target host: Jupiter, Ubuntu under WSL 2

Date: 2026-08-08

## Decision Summary

Jupiter's WSL installation is a dedicated agentic-development environment. DoodBash therefore treats Linux as the execution authority for development, KoadOS, agents, Git, language runtimes, containers, and project files. Windows 11 remains an explicitly supported interoperability tier for GUI applications and selected Windows-native tools. WezTerm is an official tool in that tier and the primary terminal frontend.

The target steady state is:

1. Linux-native tools and WSL-resident projects first.
2. KoadOS and agent launchers remain Linux-native and ahead of Windows paths.
3. Selected Windows tools are available through a curated tail of `PATH` or explicit `dood win` commands.
4. Broad inherited Windows `PATH` is not trusted as an undifferentiated extension of Linux `PATH`.
5. DoodBash audits before it mutates and never edits `/etc/wsl.conf` or Windows WezTerm configuration during shell startup.

## Current Jupiter Baseline

Observed on 2026-08-08:

- Ubuntu runs under WSL 2 with systemd enabled.
- `/etc/wsl.conf` sets only `systemd=true` and the default user; Windows interoperability defaults remain active.
- WezTerm uses `WSL:Ubuntu` as its default domain.
- The active shell advertises `TERM_PROGRAM=WezTerm` and true color.
- The current inherited `PATH` has 47 entries: 19 Linux paths, 28 Windows-mounted paths, and 5 exact duplicates.
- Linux-native `git`, `gh`, Docker, Node, npm, Python, KoadOS, Hermes, and Clyde currently resolve before Windows alternatives.
- Windows-native WezTerm, PowerShell, Explorer, Visual Studio Code, and LM Studio remain reachable through WSL interoperability.
- The current `.bashrc` and `.profile` prepend some Linux paths repeatedly, contributing to duplicates.
- The Hermes service environment does not reliably retain `WSL_DISTRO_NAME` or `WSL_INTEROP`; platform detection cannot depend on those variables alone.

This baseline is evidence for design and tests. It is not a hard-coded configuration contract.

## Scope

In scope:

- WSL detection without external commands during startup.
- PATH classification, normalization, precedence, and policy selection.
- Curated Windows interoperability.
- Path conversion at explicit command time.
- WezTerm environment detection and diagnostics.
- Security and performance checks for mixed Linux/Windows execution.
- Disposable-shell tests and a Jupiter canary.

Out of scope:

- Editing `/etc/wsl.conf` automatically.
- Editing `%UserProfile%\.wslconfig` automatically.
- Owning the Windows WezTerm Lua configuration.
- Installing or updating Windows applications.
- Running project repositories from `/mnt/c` by default.
- Replacing WSL's interoperability mechanism.
- Adding every Windows executable directory to `PATH`.

## Filesystem Contract

Agentic-development repositories, package stores, virtual environments, build outputs, KoadOS state, and Unix sockets belong in the WSL filesystem under `/home/ideans`.

Use `/mnt/c` only when a Windows application must own or directly consume the files. Windows GUI access to WSL files should use `\\wsl.localhost\Ubuntu\...` rather than relocating Linux projects to NTFS.

Reasons:

- Microsoft recommends storing Linux-command-line projects in the WSL filesystem for performance.
- Linux permissions, symlinks, sockets, case sensitivity, and watcher behavior are more predictable on the WSL filesystem.
- Package managers and Git avoid DrvFS metadata and I/O penalties.
- Windows tools can still access WSL files through the WSL UNC namespace.

`dood doctor` should warn when a recognized development repository is under `/mnt/<drive>` but must not move it.

## Platform Detection

Startup detection must use Bash builtins only.

Detection order:

1. A test-only injected kernel-release value.
2. `/proc/sys/kernel/osrelease`, read with Bash builtins.
3. `WSL_INTEROP` or `WSL_DISTRO_NAME` as supporting evidence only.
4. Otherwise classify the host as ordinary Linux.

The kernel release containing `microsoft` or `Microsoft`, including `microsoft-standard-WSL2`, is sufficient for WSL classification. Environment variables are optional because services, schedulers, and agent harnesses may sanitize them.

No `uname`, `wsl.exe`, PowerShell, network call, or filesystem traversal runs during normal startup.

## PATH Tier Model

DoodBash composes PATH in explicit tiers:

```text
1. DoodBash command entrypoint
2. KoadOS and Crew command paths
3. User Linux tools and active Linux runtimes
4. Linux local administration paths
5. Linux system paths
6. Optional Linux distribution paths such as /snap/bin
7. Curated Windows interoperability paths
```

The invariant is more important than any individual directory:

> A Windows executable must not shadow the Linux-native development tool of the same name.

Examples:

- Linux `git` wins over Windows Git.
- Linux Node/npm wins over Windows Node/npm.
- Linux Python and pyenv win over Windows Python.
- Linux Docker CLI wins over Docker Desktop's Windows CLI path.
- KoadOS, Hermes, and Clyde resolve only from Linux paths.
- Windows `pwsh.exe`, `wezterm.exe`, `explorer.exe`, `code`, and selected LM Studio tools remain intentionally available.

Project-local executable directories such as `node_modules/.bin` are not permanent global PATH entries.

## PATH Policies

DoodBash supports three explicit policies.

### `preserve`

- Preserve inherited ordering.
- Remove empty entries and exact duplicates while preserving the first occurrence.
- Classify and report risks.
- Make no cross-platform precedence correction.

This is the safe rollout default before canary approval.

### `curated`

- Remove inherited `/mnt/<drive>` PATH entries.
- Compose Linux tiers deterministically.
- Append only host-approved Windows directories.
- Warn when an expected approved directory is unavailable.

This is the intended Jupiter steady-state policy after disposable and canary verification.

### `linux-only`

- Remove all Windows-mounted PATH entries.
- Keep explicit interoperability commands available through configured absolute paths where possible.
- Intended for debugging, CI, and high-isolation shells.

Unknown policies are configuration errors. Policy changes never edit `/etc/wsl.conf`.

## Normalization Rules

Normalization is lexical and startup-safe:

- Preserve the first occurrence.
- Remove empty entries.
- Remove trailing `/` except for `/` itself.
- Compare Linux entries case-sensitively.
- Compare `/mnt/<drive>` entries using an ASCII case-folded key because ordinary Windows directories are case-insensitive.
- Preserve the original spelling of the first occurrence.
- Do not call `realpath`, `readlink`, `cygpath`, PowerShell, or `wslpath` during startup.
- Do not require entries to exist unless a caller explicitly requests validation.

PATH values are untrusted strings. Implementation must use numeric arrays and direct string comparison, not associative-array subscripts keyed by raw paths. This avoids Bash 4.4 subscript re-expansion hazards.

## Jupiter Windows Allowlist

The host-specific allowlist will be a literal line-oriented file, for example:

```text
# Core Windows interoperability
/mnt/c/Windows
/mnt/c/Windows/System32

# Explicit development frontends
/mnt/c/Program Files/PowerShell/7
/mnt/c/Program Files/WezTerm
/mnt/c/Users/idean/AppData/Local/Programs/Microsoft VS Code/bin
/mnt/c/Program Files/LM Studio
```

Rules:

- Blank lines and leading-`#` comments are ignored.
- Paths are WSL-form absolute paths.
- Spaces are literal and require no shell quoting.
- The list is data, never sourced.
- Missing entries generate doctor warnings, not startup output.
- Windows Git, Node, Python, npm-global, package-manager, SDK, and `WindowsApps` directories are excluded unless a concrete workflow proves they are required.

The allowlist is host-specific because Windows installation paths and usernames are not portable defaults.

## Windows Command Boundary

Cross-platform translation happens only for explicit commands.

Planned command surface:

```text
dood path audit
dood path explain TOOL
dood win path --to-windows PATH
dood win path --to-linux PATH
dood win open [PATH]
dood wezterm status
```

Rules:

- Use `wslpath` only at explicit command time.
- Quote every path as one argument.
- Never build a command with `eval`.
- Never reinterpret Linux metacharacters in PowerShell or `cmd.exe`.
- Prefer direct `.exe` invocation with an argument array.
- Use `WSLENV` only for narrowly documented variables and translation flags; do not export the full DoodBash configuration.
- Structured output must distinguish Linux paths, WSL mount paths, Windows drive paths, and WSL UNC paths.

## WezTerm Contract

WezTerm is the official terminal frontend but remains a separate owner.

DoodBash may:

- Detect `TERM_PROGRAM=WezTerm` without spawning a process.
- Report whether the Windows `wezterm.exe` command is available.
- Emit documented shell-integration escape sequences through a dedicated, optional module.
- Support OSC 7 current-directory reporting and WezTerm user variables after isolated testing.
- Diagnose tmux passthrough requirements when user variables are enabled.

DoodBash must not:

- Rewrite `.wezterm.lua` during startup.
- Assume every WSL shell was launched by WezTerm.
- Change fonts, themes, launch menus, key bindings, or domains.
- Invoke `wezterm.exe` during ordinary startup.
- Duplicate WezTerm profile identity as KoadOS identity authority.

The current WezTerm default domain, profile markers, and per-pane visual behavior are integration evidence, not DoodBash-owned state.

## Security Model

Mixed PATH creates executable-shadowing risk, especially from user-writable Windows directories.

`dood path audit` and `dood doctor` should detect:

- Windows paths before Linux system/toolchain paths.
- Linux/Windows command collisions for critical tools.
- Duplicate paths.
- Empty path entries, which imply the current directory.
- Relative path entries.
- World-writable Linux path entries.
- Broad Windows user application, package-manager, and global npm paths under the curated policy.
- Critical KoadOS or agent commands resolving through `/mnt/<drive>`.

Audits are read-only. DoodBash does not silently repair inherited PATH.

## Diagnostics Contract

`dood path audit` reports:

- Active policy.
- Host/platform classification.
- Ordered PATH tiers.
- Exact and Windows-equivalent duplicates.
- Relative and empty entries.
- Critical command resolution.
- Windows paths excluded or admitted by the policy.

`dood path explain TOOL` reports all matching executables in resolution order and classifies each as Linux or Windows. It does not execute the tool.

Human output uses PASS/WARN/FAIL. JSON output contains the same findings without ANSI escapes.

## Test Matrix

All implementation uses disposable environment fixtures.

Required scenarios:

1. Ordinary Linux with no Windows paths.
2. WSL kernel marker with no WSL environment variables.
3. WSL environment variables with a sanitized kernel fixture.
4. Mixed inherited PATH with Linux tools before Windows tools.
5. Windows tool before a critical Linux tool.
6. Repeated Linux paths.
7. Repeated Windows paths with case and trailing-slash differences.
8. Windows paths containing spaces.
9. Empty and relative PATH entries.
10. Missing curated Windows directories.
11. `preserve`, `curated`, and `linux-only` policies.
12. WezTerm and non-WezTerm terminals.
13. Repeated bootstrap with no PATH growth.
14. Literal hostile strings that must never be evaluated.

Tests must never change live PATH, `/etc/wsl.conf`, `.wezterm.lua`, or shell startup files.

## Canary and Rollback

Rollout stages:

1. Unit tests with synthetic PATH fixtures.
2. Disposable `env -i bash --noprofile --norc` shell.
3. Read-only audit of the live inherited PATH.
4. Jupiter canary shell using `DOOD_PATH_POLICY=curated` without editing startup files.
5. Compare command resolution for Git, gh, Docker, Node, npm, Python, KoadOS, Hermes, Clyde, PowerShell, WezTerm, Explorer, VS Code, and LM Studio.
6. Measure startup overhead.
7. Only then consider making `curated` the Jupiter host default.

Rollback is immediate: launch with `DOODBASH_DISABLE=1` or `DOOD_PATH_POLICY=preserve`. No WSL shutdown or configuration edit is required for DoodBash-only canaries.

## Acceptance Contract

The phase is complete when:

- WSL detection works without relying on environment variables.
- PATH composition invokes no external commands during startup.
- Linux development and KoadOS commands cannot be shadowed by curated Windows paths.
- Approved Windows tools remain callable.
- Duplicate, empty, relative, and cross-platform collision findings are test-covered.
- Repeated startup does not grow PATH.
- WezTerm integration is detected but not invoked during startup.
- Disposable and Jupiter canary checks pass.
- No live startup file or WSL configuration was modified by development or tests.

## Sources

Primary references consulted:

- Microsoft Learn, "Working across Windows and Linux file systems": https://learn.microsoft.com/en-us/windows/wsl/filesystems
- Microsoft Learn, "Advanced settings configuration in WSL": https://learn.microsoft.com/en-us/windows/wsl/wsl-config
- WezTerm documentation, `default_domain`: https://wezterm.org/config/lua/config/default_domain.html
- WezTerm documentation, shell integration: https://wezterm.org/shell-integration.html
- Current Jupiter `/etc/wsl.conf`, inherited PATH, command resolution, and Windows WezTerm configuration

Current machine observations are mutable evidence. Microsoft and WezTerm documentation define the external platform contracts.
