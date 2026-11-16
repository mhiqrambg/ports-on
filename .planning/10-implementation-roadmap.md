# 10 — Implementation Roadmap (Stage 11)

**Stage owner:** software-architect
**Status:** Complete

## Inputs
- `00-project-discovery.md` (scope, v1 boundary, open questions)
- `01-requirements.md` (FR-001..FR-029, NFR-001..NFR-009, OQ-1..OQ-7)
- `03-system-architecture.md` + `04-architecture-decisions.md` (ADR-001..ADR-007)
- `05-database-design.md`, `06-api-contracts.md`, `07-security-architecture.md`, `08-performance-strategy.md`, `09-testing-strategy.md`
- `02-repository-assessment.md` (greenfield; no code, no CI)

## Completion condition
A phased, dependency-ordered plan exists that sequences implementation from a validated enumeration spike to a releasable v1, states the gate between phases, and ties each phase to the requirement/ADR IDs it delivers. PASS when a reader can start Phase 0 tomorrow and knows what "done" means at each phase boundary and which owner decisions must land first.

## Decision gate BEFORE Phase 0 (blocking)
Three open questions change the shape of the work and must be answered by the product owner before implementation starts. They are restated here because they gate phases, not just documents:
- **OQ-1 — privileged stop in v1?** If YES, the SMAppService helper target, XPC protocol (`06-api-contracts.md`), and the entire `07-security-architecture.md` helper threat model are in the critical path. If NO, v1 is own-user-only and the helper is deferred (large scope/attack-surface reduction).
- **OQ-4 — distribution channel?** Mac App Store forbids the privileged helper; Developer ID + notarization allows it. This must be decided before signing/building the helper.
- **OQ-2 — minimum macOS.** ADR-001 assumes Tahoe 26.x only; confirm.

Everything in Phases 0–2 is independent of these answers except the helper target, which is deliberately isolated in Phase 4 so the answer to OQ-1 does not block the core.

## Phase plan

### Phase 0 — Enumeration spike (throwaway, ~2–4 days)
**Goal:** retire the single biggest technical risk (see `11-risk-register.md`, RISK-01) before any architecture is committed to code.
- Write a small throwaway command-line spike (not the app) that reads `sysctl net.inet.tcp.pcblist` and resolves listening sockets → PID via `libproc proc_pidinfo` on the host (macOS 26.7.3).
- Validate: correct PID attribution, struct layout assumptions, behavior with/without sudo, behavior for other users' sockets, `proc_pidinfo` owner-PID availability without Full Disk Access.
- Cross-check the spike's output against `lsof -nP -iTCP -sTCP:LISTEN` (the fallback in ADR-002) as a source of truth.
- **Exit gate:** spike attributes ports→PIDs correctly for own-user sockets, and we know exactly what FDA/sudo changes. If the programmatic path is unreliable, fall back to the `lsof` primary and update ADR-002 before proceeding.
- Delivers: validated ADR-002; resolves perf open question "`proc_pidinfo` owner-PID without FDA" (`08-performance-strategy.md` §10) and API open question 1/3 (`06-api-contracts.md`).

### Phase 1 — Core skeleton, own-user TCP (the vertical tracer bullet)
**Goal:** one end-to-end slice that proves the whole architecture, not a set of parallel layers.
- App target (SwiftUI, macOS 26, arm64, sandbox+hardened runtime ON per ADR-003) with a basic main window.
- `PortEnumerator` + `ProcessResolver` (own-user sockets only) behind the protocols in `06-api-contracts.md`.
- `ServiceRegistry` three-tier identification (ADR-007) with the bundled known-port + process-fingerprint tables.
- Main-window table (port, protocol, address, process, service) + detail view (command line, user, cwd) — FR-001, FR-003/004/005, FR-014, FR-015.
- Fixed-cadence polling, enumeration off the main actor (ADR-006, REQ-102).
- **TDD per `09-testing-strategy.md`:** build the `ServiceRegistry` mapping seam (S1) and the stop-decision-policy seam (S4) test-first; fake `PortEnumerator`/`ProcessResolver` (S2/S3) so UI/logic is testable without real sysctl.
- **Exit gate:** app lists own-user TCP listeners, identifies common services, refreshes live, and the S1/S4 unit tests pass.

### Phase 2 — Identification depth + persistence + action (own-user)
**Goal:** make it genuinely useful and safe for the user's own processes.
- Persistence via SwiftData (ADR-005) using the canonical schema from `05-database-design.md` (`UserPreference`, `ServiceOverride`, `ProcessFingerprint`, `ActionLogEntry`); ship `SchemaV1` + empty `SchemaMigrationPlan` (REQ-609).
- User service overrides + pinned ports + notes (FR around settings/persistence); override wins over fingerprint over known-port.
- Stop/restart for **own-user** processes with the confirm + warn/deny-list model (S4 policy enforced), audited to `ActionLogEntry` (lazy cap per REQ-608).
- Menu-bar item with live summary (FR-021; resolve OQ-7 display default).
- Adaptive polling tiers + diffing (REQ-096/097/098) and lazy detail resolution (REQ-093/094/095).
- **Exit gate:** user can identify, inspect, override, and stop their OWN processes; overrides persist across relaunch; stop is confirmed and audited; deny-list blocks critical processes.

### Phase 3 — Hardening, permissions, performance validation
**Goal:** meet the non-functional bar and degrade gracefully.
- TCC/FDA handling: graceful degradation + "restricted" marker + non-blocking banner when permission is absent (REQ-030/031/032) — resolves OQ-5 behavior for the no-helper path.
- argv-as-untrusted-data hygiene (REQ-003) and secret-hygiene in displayed command lines (REQ-033).
- Performance validation against the `08-performance-strategy.md` §7 budget table and acceptance criteria AC-P1..AC-P6 (these are targets; measure now, do not assume).
- Accessibility pass (NFR-006): VoiceOver labels, keyboard navigation, Dynamic Type.
- **Exit gate:** idle/open CPU and refresh latency measured within targets (or targets corrected with evidence); no permission prompt harms first-run; accessibility checks pass.

### Phase 4 — Privileged helper (ONLY if OQ-1 = YES)
**Goal:** safely add stop/restart of other-user/root processes.
- Separate helper executable, Developer ID–signed and notarized (build/sign helper first per REQ-062), registered as root launchd daemon via `SMAppService` (ADR-004).
- XPC endpoint per `PortsOnHelperProtocol` (`06-api-contracts.md`): version handshake, code-signing pinning, reverse peer validation, `NSSecureCoding`, `requestID` dedupe.
- Helper-side **authoritative** policy: deny-list enforcement, (pid, uid, name) re-validation before signal, restart only via launchd re-kick of an already-registered label (REQ-018/019) — never executing a client-supplied path.
- Opt-in install on first elevated action; app degrades to view-only for other-user rows if declined (FR-020).
- **Exit gate:** manual verification checklist (`09-testing-strategy.md` §6) passes end-to-end: helper installs, refuses bad/unauthorized requests, denies deny-listed targets, stops an other-user process, and is notarized. All of R-SEC-1..R-SEC-5 residual risks acknowledged.

### Phase 5 — Release readiness
**Goal:** shippable, notarized v1.
- Notarize app (+ helper); verify hardened-runtime/notarization compatibility (NFR-005).
- Resolve remaining owner decisions: R-SEC-3 (audit retention), R-SEC-4 (final deny/warn list for Tahoe 26.x), R-SEC-5 (cross-user visibility via FDA vs helper).
- Manual release sign-off checklist (`09-testing-strategy.md` §5 release gate).
- **Exit gate:** notarized build runs clean on a fresh Tahoe machine; open questions that gated scope are closed or explicitly deferred with owner sign-off.

## Traceability (phase → primary deliverables)
| Phase | Delivers (IDs) | Key ADRs exercised |
|---|---|---|
| 0 | validated ADR-002; closes perf/API enumeration questions | ADR-002 |
| 1 | FR-001/003/004/005/014/015; S1–S3 seams | ADR-001,002,003,006,007 |
| 2 | override/persistence FRs; own-user stop + audit; menu bar FR-021 | ADR-005,006,007 |
| 3 | NFR-002/003/006; REQ-030..033; AC-P1..P6 | ADR-003 |
| 4 | FR-020; XPC/helper contract; REQ-015..019 | ADR-003,004 |
| 5 | NFR-005; notarization; owner decisions R-SEC-3/4/5 | ADR-003,004 |

## What is deliberately NOT scheduled in v1
UDP (pending OQ-3), event-driven (non-polling) updates, any remote/network feature, and cross-user *visibility* beyond what FDA/helper decision (R-SEC-5) allows. Each is deferred, not silently dropped (see `11-risk-register.md`).

## Skill provenance
- Read in full before this stage: `tdd` (vertical-slice/tracer-bullet sequencing → Phase 1 is deliberately one end-to-end slice, not parallel layers), `ios-design` (Apple-platform phasing/permission-limiting stance → permissions asked only when a feature needs them, Phase 3/4).
- `backend-development`, `security-review`, `diagram-design`, `antislop` were read this session and informed the delegated stages and the phase gates rather than the roadmap structure itself.