# Portico — Design Spec

**Date:** 2026-06-26
**Status:** Approved for planning
**Platform:** macOS 13+ (developed on macOS 26.5, Swift 6.2)

## Summary

Portico is a native macOS menu bar app that monitors every SSH connection and
port forward on the machine and lets the user control them — kill, restart, or
start tunnels — without leaving the status bar. It is a full control panel, not
just a viewer.

The app is the always-running agent: there is no separate background daemon. A
timer drives periodic scans of system `ssh` processes and forwarded ports, the
results are rendered in a `MenuBarExtra` dropdown, and actions shell out to the
standard `ssh`/`kill` binaries.

All operations target the current user's own processes, so **no root or
privileged helper is required**.

## Goals

- See, at a glance from the menu bar, how many SSH tunnels are up and whether
  they are healthy (color-coded badge).
- List all active `ssh`/`autossh` sessions grouped by host, each showing its
  forwards (`-L`/`-R`/`-D`) and a per-forward reachability indicator.
- Control sessions: kill a hung one, restart a dropped one, and start a new
  tunnel from a catalog of hosts defined in `~/.ssh/config`.
- Feel like a real Mac app: low memory, native widgets, launch-at-login.

## Non-Goals (YAGNI)

- No control of other users' processes or any root/privileged operations.
- No SFTP, file browsing, or terminal emulation.
- No editing of `~/.ssh/config` from the UI — the catalog is read-only.
- No Linux/Windows support.
- No Mac App Store distribution (runs unsandboxed; personal tool).
- Deferred to later versions: drop notifications, global hotkey, per-tunnel
  auto-restart/watchdog.

## Scope Decisions (locked)

| Question | Decision |
|----------|----------|
| What it does | Full control panel (monitor + kill + restart + start) |
| Stack | Native Swift, SwiftUI `MenuBarExtra` |
| Visibility | See **all** system `ssh` processes; control any of them |
| Restart of foreign sessions | Reconstruct argv from `ps`; flag "restart unavailable" if not reproducible |
| Poll interval | 3s default, configurable 1–30s |
| Forward reachability | TCP-connect local `-L` ports; listener/process-only check for `-R`/`-D` |
| Health rollup | green = all forwards healthy; yellow = any forward degraded; red = any session dead / forward down |
| Launch at login | In scope (v1), via `SMAppService` |

## Architecture

The app is structured as small, single-purpose units communicating through
plain value types. Parsers are pure (string in → struct out) so they can be
unit-tested against fixture strings without touching the system.

```
Timer (3s)
   │
   ▼
MonitorStore.refresh()  ──►  ProcessScanner ─┐
                             PortProbe      ─┼─►  merge ─► [SSHSession] (@Published)
                             SSHConfigCatalog┘                     │
                                                                   ▼
                                                            MenuBarView (SwiftUI)
                                                                   │ user action
                                                                   ▼
                                                            TunnelController
                                                                   │ side effect (spawn/kill)
                                                                   └──► reflected on next poll
```

### Components

#### `ProcessScanner`
- Runs `ps -axww -o pid=,ppid=,lstart=,etime=,command=` and keeps lines whose
  command is an `ssh`/`autossh` **client** invocation (exclude `sshd`, exclude
  the ControlMaster mux child where appropriate).
- Parses each argv into an `SSHSession`:
  - `pid`, `ppid`, started-at / elapsed time
  - `user`, `host`, resolved alias (best-effort), `identityFile`
  - forwards: array of `Forward { kind: .local/.remote/.dynamic, bindAddr, bindPort, host, hostPort }` parsed from `-L`/`-R`/`-D` and their `=`/`:` forms
  - `controlPath` / `controlMaster` if present
  - raw argv (kept for restart)
- Pure function: `parse(psOutput: String) -> [SSHSession]`. The process
  execution is injected via a `CommandRunner` protocol.

#### `PortProbe`
- Input: the set of forwards across all sessions.
- For `.local` forwards: confirm a listener exists on `bindAddr:bindPort`
  (cross-checked against `lsof -nP -iTCP -sTCP:LISTEN`) **and** attempt a short
  (≤500ms) TCP connect to mark `reachable`.
- For `.remote`/`.dynamic` forwards: only confirm the local listener/process is
  alive — do not probe the far side.
- Output: `[ForwardID: ForwardHealth]` where health ∈ {reachable, listenerOnly,
  down}. Probes run concurrently with a timeout; one slow probe never blocks the
  refresh.
- Interpretation by forward kind (drives the rollup below):
  - `.local`: `reachable` = healthy; `listenerOnly` (listener up but TCP connect
    failed) = degraded; `down` (no listener) = unhealthy.
  - `.remote`/`.dynamic`: `listenerOnly` **is the healthy state** (the far side
    is intentionally not probed); `down` = unhealthy. `reachable` is not
    produced for these kinds.

#### `SSHConfigCatalog`
- Parses `~/.ssh/config` (including `Include` directives, best-effort) into
  `[HostEntry { alias, hostName, user, forwards: [Forward] }]`.
- Drives the "Start tunnel" submenu: known hosts and their declared forwards.
- Pure function: `parse(configText: String, includeLoader:) -> [HostEntry]`.

#### `TunnelController`
- The action layer. Operations:
  - `kill(session)` — SIGTERM, then SIGKILL after a grace period if still alive.
  - `restart(session)` — kill, then re-exec stored argv (app-launched) or argv
    reconstructed from `ps` (foreign); surfaces an error if not reproducible.
  - `start(host)` / `start(host, forward)` — spawn `ssh -fN [<-L/-R/-D ...>]
    <host>` detached; record the resulting PID in an app registry.
- Spawning/killing is injected via a `ProcessSpawner` protocol so command
  construction is unit-tested without launching real `ssh`.
- Maintains a small registry (in `Application Support/Portico/registry.json`) of
  PIDs/argv the app launched, so restart of its own tunnels is exact.

#### `MonitorStore` (`ObservableObject`, `@MainActor`)
- Owns the refresh `Timer` (interval from settings).
- On each tick: run `ProcessScanner` + `SSHConfigCatalog`, then `PortProbe`,
  merge into `[SSHSession]` with attached `ForwardHealth`, diff, and publish.
- Exposes `@Published var sessions`, `@Published var catalog`, and a computed
  aggregate health for the menu bar badge.
- Errors are captured per-source and surfaced non-fatally (a failed scan keeps
  the last good state and shows a small warning).

#### `MenuBarView` (SwiftUI)
- `MenuBarExtra` with `.menuBarExtraStyle(.window)` for a rich dropdown.
- Sessions grouped by host; each row: health dot, host/user, elapsed time,
  forward list (e.g. `localhost:5501 → terry:5501 ✓`), and a row action menu
  (Kill / Restart / Copy command).
- "Start tunnel" submenu populated from `SSHConfigCatalog`.
- Footer: aggregate status, manual Refresh, Settings, Quit.
- Settings window: poll interval slider (1–30s), launch-at-login toggle
  (`SMAppService`).

### Menu bar icon

- SF Symbol glyph (e.g. `point.3.connected.trianglepath.dotted`) with a small
  count badge = number of healthy tunnels.
- Tint reflects aggregate health: green (all forwards healthy) / yellow (any
  degraded `-L` forward) / red (any dead session or down forward).

## Data Flow

1. Timer fires (default every 3s).
2. `MonitorStore.refresh()` runs `ProcessScanner` and `SSHConfigCatalog`,
   then `PortProbe` over the discovered forwards.
3. Results merge into `[SSHSession]` (with per-forward health), diffed against
   the previous snapshot, and published.
4. SwiftUI re-renders the dropdown and badge.
5. User actions call `TunnelController`; the side effect (spawn/kill) becomes
   visible on the next poll. A manual Refresh can be triggered immediately after
   an action for snappier feedback.

## Permissions & Distribution

- Runs **unsandboxed** so it can execute `/usr/bin/ssh`, `ps`, `lsof`, `kill`
  and read `~/.ssh/config`. No special entitlements; no privileged helper.
- Distributed as a developer-signed `.app` (ad-hoc or Developer ID); not App
  Store. Hardened Runtime is optional for a personal build.
- All controlled processes belong to the current user — no authorization
  prompts required for `kill`/spawn.

## Error Handling

- **Parse failures** are per-row: a single unparseable `ps` line or config block
  is skipped and logged, never aborts the whole list.
- **Probe failures/timeouts** mark a forward `down`/`listenerOnly`, never block
  the refresh.
- **Action failures** (kill denied, ssh spawn error) surface as a transient
  inline message on the affected row.
- **Non-reproducible restart** (foreign session whose argv can't be
  reconstructed) disables the Restart action with an explanatory tooltip.
- **Scan failure** keeps the last good snapshot and shows a small warning in the
  footer.

## Testing Strategy

- `ProcessScanner.parse` — unit tests against captured real `ps` output
  fixtures (Warp ControlMaster session, `-L`/`-R`/`-D` forms, autossh, a
  multi-forward line).
- `SSHConfigCatalog.parse` — unit tests against sample config fixtures
  including `Include`, wildcards, and multiple forwards per host.
- `TunnelController` — tests assert the exact argv constructed for
  `start`/`restart` via a mock `ProcessSpawner`; no real `ssh` is launched.
- `PortProbe` — tests over a local listener fixture (open a throwaway socket)
  to validate reachable vs. down classification and timeout behavior.
- `MonitorStore` — merge/diff logic tested with injected scanner/probe stubs.

## Components by File (initial shape)

```
portico/
  Portico.xcodeproj                (or Package.swift + app shell)
  Sources/Portico/
    PorticoApp.swift               // @main, MenuBarExtra
    Models/
      SSHSession.swift             // SSHSession, Forward, ForwardHealth
      HostEntry.swift
    Scanning/
      ProcessScanner.swift
      PortProbe.swift
      SSHConfigCatalog.swift
      CommandRunner.swift          // protocol + real impl
    Control/
      TunnelController.swift
      ProcessSpawner.swift         // protocol + real impl
      LaunchRegistry.swift
    State/
      MonitorStore.swift
      Settings.swift
    Views/
      MenuBarView.swift
      SessionRow.swift
      StartTunnelMenu.swift
      SettingsView.swift
  Tests/PorticoTests/
    ProcessScannerTests.swift
    SSHConfigCatalogTests.swift
    TunnelControllerTests.swift
    PortProbeTests.swift
    Fixtures/
```

## Open Questions / Future

- Drop notifications (UserNotifications) when a tracked tunnel dies — v1.1.
- Global hotkey to open the panel — v1.1.
- Optional watchdog that auto-restarts a flapping app-launched tunnel — later.
