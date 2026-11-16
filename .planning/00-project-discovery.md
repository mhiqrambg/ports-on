# 00 — Project Discovery (Stage 1)

**Stage owner:** software-architect
**Status:** Complete

## Inputs
- Product-owner brief (Indonesian): build a macOS app, targeting Tahoe 26.7.3, that manages ports — showing which ports are active/in use and which service owns them (nginx, docker, opencode, omp, nodejs, nextjs, astro, etc.). Plan the work; use MCP servers and skills where helpful.
- Verified host environment (see `_shared-context.md`).
- Sibling reference project: `~/Documents/Projects/nginx-proxy-helper` (Python nginx management CLI).

## Completion condition
A problem statement, scoped v1 capability boundary, target platform decision, and explicit out-of-scope list exist, and are consistent with the delegated requirement/architecture stages. PASS when the scope below is concrete enough to brief every specialist stage without further discovery.

## Problem statement
On a local development machine, many services silently bind TCP/UDP ports: reverse proxies (nginx), container runtimes (docker), dev servers (nodejs, nextjs, astro), local agent CLIs (opencode, omp), and system daemons. When a port is already taken, the failure surfaces as an opaque "address already in use" or a misrouted request. The user's current remedy is ad-hoc terminal forensics (`lsof -i :PORT`, `netstat -an | grep LISTEN`). This is high-friction, easy to get wrong (wrong PID, missing sudo, misreading output), and gives no standing view of what is listening right now.

**Ports On** turns port forensics into a standing, at-a-glance macOS-native view: which ports are active, which process owns each, which known service that process corresponds to, and a safe, gated way to stop or restart the offender.

## Who it is for
A single-user developer/power-user on their own Apple Silicon Mac running macOS Tahoe. Not a fleet/enterprise fleet-management tool; not a server product.

## Core value loop
1. **See** — list every active listener (port, protocol, address) with its owning process.
2. **Identify** — map each port/process to a human-meaningful service name (nginx, docker, nodejs, nextjs, astro, opencode, omp), using known ports + process fingerprinting + user overrides.
3. **Inspect** — drill into a port to see command line, working directory, user, protocol, bind address.
4. **Act** — stop or restart a process, gated by a safety/permission model so the user cannot accidentally kill the wrong or a system-critical process.
5. **Watch** — keep the view current without the user re-triggering it.

## Target platform decision
- **OS:** macOS 26 "Tahoe" is the design target (host is 26.7.3). Minimum supported version is an explicit ADR (see `04-architecture-decisions.md`, ADR on supported range). The deliberate default is to target macOS 26 and use current SwiftUI/APIs, with the supported-range decision owned by ADR rather than assumed here.
- **Architecture:** Apple Silicon (arm64) only. Host is arm64; no Intel build is in scope for v1.
- **Toolchain:** Xcode 27.2, Swift 6.4.2, SDK `arm64-apple-macosx26.0`.
- **UI:** SwiftUI, menu-bar (extra) + main window presentation.

## In scope for v1 (capability boundary)
- Enumerate active **TCP** listeners with owning PID/process (UDP is a deliberate ADR/open question; TCP-first).
- Resolve PID → command line, working directory, user, bind address.
- Identify service via known-port table + process-name fingerprint + user-defined overrides.
- Live refresh with an adaptive cadence (see `08-performance-strategy.md`).
- Inspect detail view.
- Stop/restart a process the user owns, with a confirm + warn/deny-list safety model.
- Stop/restart of other users'/root processes via a privileged helper is **planned but treated as a gated capability** — final v1 inclusion is an open question for the product owner (see Open questions).
- Menu-bar live summary + main window with full table and detail.
- Local-only persistence of preferences and user service overrides.

## Explicitly out of scope (v1)
- No remote/network API, no server component, no fleet management.
- No remote database; persistence is local only.
- No firewall/packet filtering (PF) management — observation only, not network enforcement.
- No port forwarding or proxy configuration (this is the sibling `nginx-proxy-helper`'s territory, and stays there).
- No process launching/"start a service" orchestration beyond stop/restart of an already-running process.
- No Windows/Linux support.
- No telemetry/analytics.

## Relationship to the sibling project
`~/Documents/Projects/nginx-proxy-helper` is a Python CLI for managing nginx sites and install/uninstall scripts. It is **reference context only** (it shows the product owner's domain familiarity with reverse-proxy port conflicts). Ports On is a native Swift/SwiftUI app and shares no code with it. See `02-repository-assessment.md`.

## Open questions for the product owner (block v1 scope, not planning)
1. **Privileged stop in v1?** Does v1 ship the SMAppService privileged helper for stopping other users'/root processes, or is v1 limited to processes the current user owns (no helper, simpler security surface)?
2. **UDP in v1?** TCP-only, or TCP+UDP listeners from day one?
3. **Minimum macOS version?** macOS 26 only, or also 15/14?
4. **Distribution:** personal use / direct download (Developer ID + notarization), or Mac App Store (no privileged helper allowed — would force the TCP-only, own-process scope)?

These are recorded in `11-risk-register.md` and `12-architecture-review.md`; they gate implementation, not this planning pass.

## Skill provenance
**Skills read in full before Stage 1:** `ios-design`, `backend-development`, `security-review`, `diagram-design`, `antislop`, `tdd`.
- `ios-design` (Apple-platform UI guidance) → shaped the macOS-native, SwiftUI menu-bar + window presentation framing and the "limit permissions to what the feature needs" stance reflected in scope.
- `security-review` (research-before-flagging, least-privilege) → reinforced treating privileged stop as a gated, researched capability rather than a default.
- `backend-development` / `diagram-design` / `tdd` / `antislop` → informed delegation briefs (internal provider API, Mermaid diagrams, seam-based testing, no-boilerplate docs) rather than this discovery file's content.
- Skills are guidance, not a stage; no skill altered the scope decisions above.