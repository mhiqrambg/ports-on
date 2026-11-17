# Ports On

A menu bar and window app for macOS that lists every TCP port currently listening on your Mac, the process that owns each one, and which user it runs as. You can stop a process you own from the window.

## Status

Early MVP. The enumeration and stop paths work and are covered by tests. It has not been signed or notarized, so distributing it to other people still needs that work.

## Build and run

From the repo root:

```bash
swift build                 # compile (Apple Silicon only)
swift test                  # unit and live integration tests
./bundle.sh                 # build a universal binary and bundle it as "Ports On.app"
open ".build/Ports On.app"  # launch
```

By default `swift build` produces an arm64 binary. `bundle.sh` builds a universal binary (arm64 and x86_64) so the app runs on Apple Silicon and Intel Macs.

Requirements: Xcode with the macOS 26 SDK, on Apple Silicon. Targets `macosx26.0`.

## How it works

`LsofPortEnumerator` runs `lsof -nP -iTCP -sTCP:LISTEN -F0pnLct` and parses its NUL-delimited output. The `c` field carries the full process name, which matters because the usual human-readable column truncates names to about 9 characters and escapes spaces as `\x20`. `ps -o comm=` was not usable either: it returns a full path, and `ucomm=` truncates to 15 characters. lsof's `c` field gives the clean name directly.

Sockets on the same port and PID get merged into one row, so a service bound to both IPv4 and IPv6 shows up once. The Bind column shows the address and the families (`IPv4+IPv6`).

`ServiceResolver` identifies services by process name. Port numbers are only a fallback hint, because most dev servers let you configure the port and the number changes between runs.

`StopService` sends SIGTERM with `kill(2)`. It only signals processes the current user owns, checks ownership again right before the signal to narrow the PID-reuse window, and refuses a fixed list of critical system processes.

## Settings

Open Settings from the menu bar popover.

| Setting | State |
|---------|-------|
| Refresh interval (1s to 30s) | Works. Drives how often the list re-scans. |
| Launch at login | Works. Uses `SMAppService`. |
| Check for updates automatically | The toggle saves, but it does nothing yet. |

Auto-update needs a signed, notarized build with Sparkle. That is distribution-phase work, separate from the app itself.

## Scope decisions for v1

- Shows the current user's processes only, so there is no Full Disk Access prompt.
- TCP only.
- You can stop your own processes. Stopping other users' or root processes is deferred.

The full planning set is in `.planning/`.
