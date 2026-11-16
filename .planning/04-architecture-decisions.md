# Ports On — Architecture Decision Records (Stage 5)

## Inputs
- `.planning/_shared-context.md` (verified env: macOS 26.7.3 Tahoe, Apple Silicon arm64, Xcode 27.2, Swift 6.4.2; no backend; local-only persistence).
- Stage 4 component architecture (`.planning/03-system-architecture.md`).
- Grounding: sysctl+libproc vs lsof, App Sandbox + Hardened Runtime, SMAppService+XPC, TCC Full Disk Access, notarization.

## Completion condition
This document is complete when it records 5–8 ADRs covering: minimum macOS version, enumeration mechanism, sandbox/hardened-runtime + privileged helper strategy, privileged-helper approach, persistence choice, and live-update strategy — each with ID, Title, Status, Context, Decision, Consequences, and Alternatives considered. No application code is written.

---

## ADR-001 — Minimum supported macOS version: Tahoe 26.x only

**Status:** Accepted
**Proposed by:** System Architecture Analyst
**Approver:** User (pending)

**Context.** The verified host is macOS 26.7.3 (Tahoe), Apple Silicon, SDK `arm64-apple-macosx26.0`. The product brief targets "macOS Tahoe 26.x". The programmatic enumeration path relies on semi-private sysctls (`net.inet.tcp.pcblist`) whose struct layouts are version-sensitive (shared brief).

**Decision.** Target macOS 26.0 as the deployment target. Do not spend effort supporting older macOS in Phase 1.

**Consequences.**
- Simplest build: one OS baseline, one sysctl struct layout to validate, one SDK.
- Users on older macOS cannot run the app — acceptable for a personal/dev tool whose confirmed host is Tahoe.
- If broad support is ever required, the enumeration fallback (ADR-002) becomes the compatibility path and struct layouts must be branched per OS.

**Alternatives considered.**
- *Support macOS 13/14/15+* — rejected: unconfirmed driver, multiplies sysctl struct handling and QA for no stated user need.
- *Support 26.x only but pin to 26.7* — rejected: point-version pinning adds friction with no benefit.

---

## ADR-002 — Enumeration mechanism: sysctl + libproc primary, lsof subprocess fallback

**Status:** Accepted
**Proposed by:** System Architecture Analyst
**Approver:** User (pending)

**Context.** Two viable sources for port→PID (shared brief): (a) CLI subprocess `lsof -nP -iTCP -sTCP:LISTEN` (sudo for other users); (b) programmatic `sysctl` (`net.inet.tcp.pcblist`/`udp.pcblist`) + `libproc` (`proc_pidinfo`). `lsof` itself uses these private sysctls (Apple Forums 728731; spenceruresk PortMon). `netstat -an` has no PID; `NWPathMonitor` reports path status only.

**Decision.** Primary: sysctl + libproc, no subprocess. Fallback: parse `lsof` into the same `PortSnapshot` when the sysctl parse fails or the user enables Compatibility mode.

**Consequences.**
- No per-refresh subprocess spawn → cheap enough for a 2s polling cadence (ADR-006).
- Requires careful, defensively-sized struct parsing per OS; uses semi-private interfaces that could change (mitigated by the lsof fallback).
- Both sources normalize to one `PortSnapshot` so the swap is invisible to UI.

**Alternatives considered.**
- *lsof as primary* — rejected: subprocess-per-tick cost and privilege complexity for the same underlying data.
- *netstat* — rejected: no owning PID.
- *NWPathMonitor* — rejected: not a listener enumerator.

---

## ADR-003 — Sandbox & hardened runtime: sandboxed app + hardened runtime + privileged helper for elevated actions

**Status:** Accepted
**Proposed by:** System Architecture Analyst
**Approver:** User (pending)

**Context.** The app must enumerate and stop processes owned by other users/root, which App Sandbox blocks (shared brief). Hardened Runtime is required for notarization, which is required for Developer ID distribution.

**Decision.** Ship the app with App Sandbox ON and Hardened Runtime ON. Enumerate via sysctl within the sandbox. For any action needing privilege beyond the sandbox (stop other-user/root process), delegate to the privileged helper (ADR-004) rather than adding broad entitlements to the app.

**Consequences.**
- Notarizable and distributable outside the App Store.
- Sandbox keeps the app's own attack surface small; elevation is confined to a minimal helper.
- Full command lines of other users' processes may still require the user to grant Full Disk Access (TCC `SystemPolicyAllFiles`); the UI shows a "restricted" marker and prompts rather than failing silently.

**Alternatives considered.**
- *No sandbox* — rejected: loses the documented security posture and complicates notarization review.
- *Grant the app broad entitlements instead of a helper* — rejected: App Sandbox entitlements do not confer the ability to signal other users' processes; a separate elevated helper is Apple's documented pattern.

---

## ADR-004 — Privileged helper: SMAppService + XPC daemon (not SMJobBless / AuthorizationExecuteWithPrivileges)

**Status:** Accepted
**Proposed by:** System Architecture Analyst
**Approver:** User (pending)

**Context.** Stopping another user's/root's process requires root. `SMJobBless` and `AuthorizationExecuteWithPrivileges` are deprecated (shared brief). `SMAppService` (ServiceManagement) is the modern way to register a launchd daemon/agent running elevated, communicating over XPC. WWDC23 "Protect your Mac app with environment constraints" governs helper security.

**Decision.** Use a separate helper executable in the app bundle, registered as a root launchd daemon via `SMAppService`, invoked over a validated XPC endpoint. The daemon verifies the connecting client's code signature (environment constraints), re-checks the target PID before signaling, and performs `kill` / `launchctl bootout`/`kickstart`. Install on first elevated action; helper is Developer ID–signed and notarized with the app.

**Consequences.**
- Modern, non-deprecated elevation path aligned with current Apple guidance.
- Helper must be signed/notarized; adds one more artifact to build and verify.
- If the user declines helper install, elevated actions are disabled but enumeration and own-user actions keep working.

**Alternatives considered.**
- *SMJobBless* — rejected: deprecated.
- *AuthorizationExecuteWithPrivileges* — rejected: deprecated and inherently less secure.
- *Ask user to run a sudo command manually* — rejected as the default: poor UX; retained only as a documented manual workaround.

---

## ADR-005 — Persistence: SwiftData

**Status:** Accepted
**Proposed by:** System Architecture Analyst
**Approver:** User (pending)

**Context.** Persistence is local-only (confirmed driver): app preferences, user-defined service overrides, and a cached known-port table. Confirmed env provides Swift 6.4.2 and a modern toolchain. There is no backend and no sync requirement.

**Decision.** Use SwiftData for three small models: `AppPreference`, `ServiceOverride`, `ServiceAlias`.

**Consequences.**
- Native, low-boilerplate, integrated with SwiftUI/Swift concurrency; no third-party dependency.
- Store file is managed by the framework (file-locked); no manual SQLite schema/migration burden at Phase 1.
- Ties the app to the SwiftData API; if requirements later demand complex queries or cross-process access, raw SQLite/Core Data could be revisited.

**Alternatives considered.**
- *Raw SQLite (SQLite.swift/GRDB)* — rejected for Phase 1: more boilerplate than the three-model need justifies; reconsider if query complexity grows.
- *UserDefaults only* — rejected: poor fit for a growing override/alias list with query needs.
- *Core Data* — rejected: heavier than SwiftData for this scope.

---

## ADR-006 — Live-update strategy: polling at 2s (window) / 5s (menu bar), paused when idle

**Status:** Accepted
**Proposed by:** System Architecture Analyst
**Approver:** User (pending)

**Context.** There is no public macOS API that emits bind/listen events; `kqueue EVFILT_PROC` signals fork/exec/exit but not socket listen transitions. Any "event-driven" design would still be built by diffing the same sysctl table (shared brief). The sysctl read is a single kernel copy and is cheap at this scale.

**Decision.** Poll. Default cadence 2.0s while the main window is visible, 5.0s while only the menu bar is shown, and pause when the app is otherwise idle. Enrich only new/changed PIDs each tick (cache the rest). Expose Off/1s/2s/5s/10s in prefs plus a manual "Refresh now".

**Consequences.**
- Simple, predictable, no event-subsystem complexity.
- Bounded background cost via the menu-bar-only and idle pause tiers.
- Sub-second latency to changes is not guaranteed (bounded by cadence); acceptable for a port inspector.

**Alternatives considered.**
- *Event-driven (kqueue/notifications)* — rejected: no reliable listen/bind event source; would reintroduce sysctl diffing under more complexity.
- *Aggressive 1s default everywhere* — rejected as default: higher background cost for little perceived benefit; offered as a user option instead.

---

## ADR-007 — Service identification: layered registry (overrides > process fingerprint > known-port)

**Status:** Proposed
**Proposed by:** System Architecture Analyst
**Approver:** User (pending)

**Context.** The product must label a port's owner as a friendly service (nginx, docker, node/next, astro, opencode, omp, …). No single source is complete: well-known ports miss dev servers; process names are ambiguous; users have personal conventions.

**Decision.** Resolve identity in three tiers, first match wins with a `confidence`: (1) user overrides from persistence; (2) bundled process-name fingerprint table; (3) bundled known-port table. Unmatched → `Unknown` showing the raw command line.

**Consequences.**
- User intent always wins; builtin data improves without touching user data.
- Two bundled static tables to curate; confidence field lets the UI show certainty.
- Fingerprints can mislabel look-alike processes; overrides are the correction path.

**Alternatives considered.**
- *Known-port table only* — rejected: misses dev-tool processes that motivated the app.
- *Process-name only* — rejected: no port context and ambiguous names.
- *Online service lookup* — rejected: local-only tool, no network dependency (confirmed driver).

## Skill provenance
none

## Stage 12 review integration
Reviewed and cross-checked against `01`, `03`, `05`–`12`. Dispositions recorded in `12-architecture-review.md`:
- **C-1 (ADR-005 model names):** superseded by the canonical `05-database-design.md` schema (`UserPreference` / `ServiceOverride` / `ProcessFingerprint` / `ActionLogEntry`). Align at implementation start.
- **C-3 (governance):** ADR-001..006 are recorded "Accepted" but with "Approver: User (pending)"; ADR-007 "Proposed". Given the approval gate, treat all seven as **recommendations pending owner sign-off** until decisions D-1..D-10 in `11-risk-register.md` are answered. This review does not constitute approval to build.
