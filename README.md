# Ports On

A native macOS Tahoe (26.x) menu-bar + window app that shows which TCP ports are listening on
your Mac, which process owns each, and a friendly service name (nginx, Docker, Next.js, Astro,
Node, Redis, …) — with a security-gated stop action for processes you own.

## Status

MVP. The enumeration → service-resolution pipeline and stop action are implemented and tested
against live `lsof` on macOS 26.7.3. Not yet signed/notarized; App Store or Developer-ID
distribution still needs signing.

## Build & run

```bash
cd PortsOn
swift build                 # compile
swift test                  # unit + live integration tests
./bundle.sh                 # bundle into "Ports On.app"
open ".build/Ports On.app"  # launch
```

Requirements: Xcode with the macOS 26 SDK, Apple Silicon. Targets `macosx26.0`.

## Architecture (short)

- **`PortEnumerator`** — `LsofPortEnumerator` parses `lsof -nP -iTCP -sTCP:LISTEN`. ADR-002
  wanted sysctl/libproc as primary, but libproc's private struct parsing isn't safely doable in
  a first cut, so lsof ships as primary behind the `PortEnumerating` seam (swap later).
- **`ServiceResolver`** — layered registry (ADR-007): known-port match → process-name
  fingerprint → raw process name fallback.
- **`StopService`** — security-gated `kill(SIGTERM)`. Refuses a fixed deny-list of critical
  system processes, only signals processes the current user owns, and re-validates (pid, uid,
  name) immediately before the signal to shrink the PID-reuse TOCTOU window (RISK-02/03/09).
- **`PortListView` / `MenuBarView`** — SwiftUI, native Table + searchable, real loading / empty /
  error states. Menu-bar popover shows the port count + top few (decision D-7).

## Scope decisions (from Phase 1 planning)

- Current-user visibility only (no Full Disk Access prompt).
- TCP only for v1.
- Stop limited to processes you own; privileged (root) stop is deferred to v1.1 (decision D-1).

Full planning set lives in `../.planning/`.
