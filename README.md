# Portico

A native macOS menu bar app that monitors every SSH session and forwarded port
on your machine and lets you kill, restart, and start tunnels from the status bar.

## Build & run

```bash
swift test          # run the test suite
swift build         # debug build
./Scripts/make-app.sh   # build Portico.app (release, signed ad-hoc)
open ./Portico.app
```

## What it shows

- All active `ssh`/`autossh` sessions, grouped by host, with elapsed time.
- Per-forward health dots: green = reachable (or healthy remote/dynamic),
  yellow = local listener up but not answering, red = no listener.
- A menu-bar glyph tinted by aggregate health.

## What it does

- **Kill** a session (SIGTERM).
- **Restart** a session — exact for tunnels Portico launched; best-effort
  (reconstructed from `ps`) for sessions started elsewhere.
- **Start** a tunnel from any host defined in `~/.ssh/config`.

## Requirements

macOS 13+. Runs unsandboxed; controls only your own user's processes (no root).

## Architecture

All logic lives in the `PorticoCore` library (parsers, probes, controllers,
state) and is unit-tested. The `Portico` executable is a thin SwiftUI
`MenuBarExtra` over `PorticoCore`. See `docs/superpowers/specs/` for the design.
