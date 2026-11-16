# 12 — Architecture Review (Stage 12)

**Stage owner:** software-architect
**Status:** Complete. Cross-checks every planning document against every other; records contradictions, missing decisions, and residual questions.

## Inputs
The full planning set `00`–`11` in `.planning/` (all read in full or via targeted sections during review).

## Completion condition
Every document is checked against every other for contradictions, duplicated subject matter, missing decisions, and requirement-ID consistency; contradictions are either fixed in place (trivial) or recorded with an owner; the blueprint is confirmed coherent and ready for owner review. PASS when the contradiction/decision tables below are complete and each row has a disposition.

---

## 1. Stage completion check (evidence per stage)

| Stage | Doc | Owner | Status | Evidence |
|---|---|---|---|---|
| 1 Discovery | `00-project-discovery.md` | architect | PASS | Problem, scope, out-of-scope, platform decision, 4 open questions present |
| 2 Requirements | `01-requirements.md` | requirements-analyst | PASS | 29 FR + 9 NFR, unique IDs, priorities, acceptance criteria, OQ-1..7 |
| 3 Repo assessment | `02-repository-assessment.md` | architect | PASS | Greenfield documented; sibling project dispositioned reference-only |
| 4 Architecture | `03-system-architecture.md` | system-architecture-analyst | PASS | Component + context + sequence Mermaid; 6 concerns resolved; ADR-002 mechanism chosen |
| 5 ADRs | `04-architecture-decisions.md` | system-architecture-analyst | PASS | ADR-001..007, each with context/decision/consequences/alternatives |
| 6 Database | `05-database-design.md` | database-designer | PASS | SwiftData chosen; 4 entities; Mermaid ERD; indexes; migration; REQ-601..610 |
| 7 API contracts | `06-api-contracts.md` | api-designer | PASS | 5 provider protocols + XPC `PortsOnHelperProtocol`; shared types; REQ-111..119 |
| 8 Security | `07-security-architecture.md` | security-auditor | PASS | Sandbox/hardened posture; helper threat model; TCC table; deny/warn; notarization; REQ-0xx; R-SEC-1..5 |
| 9 Performance | `08-performance-strategy.md` | performance-analyst | PASS | Workload model; enumeration cost; lazy resolution; adaptive polling; budget table (ASSUMED); AC-P1..P6 |
| 10 Testing | `09-testing-strategy.md` | test-architect | PASS | Seams S1–S6; levels T-L0..T-L2; TDD slice; fixtures; manual checklist; gates |
| 11 Roadmap | `10-implementation-roadmap.md` | architect | PASS | Phases 0–5, dependency-ordered, gated, traceable to FR/ADR |
| 12 Review | `12-architecture-review.md` | architect | PASS | This document |
| — Risk register | `11-risk-register.md` | architect | PASS | RISK-01..16 + D-1..D-10 owner decisions |

All 13 files present in `.planning/`. Each specialist doc opens with `## Inputs`/`## Completion condition` and closes with `## Skill provenance`, per contract.

## 2. Contradictions found and dispositioned

| # | Conflict | Docs | Severity | Disposition |
|---|---|---|---|---|
| C-1 | **Persistence model names/counts differ.** Architecture/ADR-005 list `AppPreference`, `ServiceOverride`, `ServiceAlias` (3 models). Database design lists `UserPreference`, `ServiceOverride`, `ProcessFingerprint`, `ActionLogEntry` (4 models). | 03, 04 (ADR-005) vs 05 | Low (naming) | **Resolved — `05` is canonical.** Adopt `UserPreference` / `ServiceOverride` / `ProcessFingerprint` / `ActionLogEntry`. `ServiceAlias` ≡ `ProcessFingerprint` (rename), `AppPreference` ≡ `UserPreference`, `ActionLogEntry` is an *addition* the architecture must reflect. Recorded in `10`/`11`; reconcile `03`/`04` prose at implementation start. |
| C-2 | **Polling cadence tiers differ.** ADR-006/`03` = 2s window / 5s menu-bar / paused idle. `08` = ~10s closed / ~2s open-idle / ~1s interacting. | 03, 04 (ADR-006) vs 08 | Medium | **Resolved — ADR-006 governs** (it is the accepted decision). `08`'s three-tier adaptive scheme is a *refinement* of ADR-006, to be validated against AC-P1..P6 in Phase 3. D-6 asks the owner to confirm. Do not implement both. |
| C-3 | **ADR status vs approval.** ADR-001..006 marked "Status: Accepted" but "Approver: User (pending)"; ADR-007 "Proposed". | 04 | Low (governance) | **Recorded, not silently resolved.** Given the approval gate, all ADRs should read "Proposed — pending owner sign-off" until D-1..D-10 are answered. The architect recommends treating 001–007 as *recommendations*, not accepted decisions, until the owner approves. Owner action. |
| C-4 | **Requirement-ID schemes are disjoint.** FR-/NFR- (01), REQ-6xx (05), REQ-11x (06), REQ-0xx (07), REQ-09x/10x (08). No unified registry. | 01, 05, 06, 07, 08 | Low | **Recorded as RISK-15.** Perf doc itself flagged this. Not a blocker for planning; a single REQ-ID registry + crosswalk must be created at the start of implementation (Phase 1). Not auto-merged here because renumbering 5 docs risks introducing errors. |
| C-5 | **Cross-user visibility mechanism ambiguity.** `07` (R-SEC-5) assumes visibility prefers FDA and the helper is reserved for signalling; `06` open q.1 asks whether the root helper bypasses FDA for `detail(of:)`. | 06 vs 07 | Medium | **Not resolved — owner decision D-10 / Phase 0 evidence.** Whether the helper bypasses FDA for command-line reads is an empirical question resolved in Phase 0; until then `06`'s `notPermitted(needsFullDiskAccess:)` path must remain reachable. No doc is "wrong"; the dependency is stated. |

## 3. Missing decisions / gaps (nothing contradicts, but something is undecided)

| # | Gap | Docs affected | Owner decision |
|---|---|---|---|
| G-1 | UDP in v1 (OQ-3) undecided; affects enumeration, `Visibility`, list model. | 01 (FR-002), 06 (open q.4) | D-4 |
| G-2 | History cap value (row-count vs age) not pinned (R-SEC-3). | 05 (§6), 07 | D-8 |
| G-3 | Final deny/warn list contents for Tahoe 26.x not confirmed (R-SEC-4). | 07 (§5), 09 (S4) | D-9 |
| G-4 | Menu-bar default display behavior (OQ-7) unspecified. | 01 (FR-021) | D-7 |
| G-5 | `ServiceKey` override granularity (per-port vs per-process-name) unspecified. | 06 (open q.5), 05 | Architect, Phase 1 (schema needs it before override store build) |
| G-6 | Whether privileged helper adds per-refresh XPC cost worth budgeting. | 08 (§10) | Measure in Phase 2/3 |
| G-7 | Helper FDA bypass (C-5) empirical resolution. | 06, 07 | Phase 0 spike |

## 4. Duplication check (reuse, not redundancy)
- Subject overlap between `03` (architecture) and `04` (ADRs) is intentional and separated by role: `03` = *what the system is*; `04` = *why each choice*. The mechanism comparison (sysctl vs lsof) appears in `03`, `04`, `08` at different depths (architecture choice / ADR record / performance rationale) — this is deliberate traceability, not duplication.
- Sandbox/notarization appears in `03`, `07`, and `10`; each covers a different axis (structural / threat model / phase gate). No doc restates another verbatim.

## 5. Requirement coverage sanity (spot-check, not full audit)
- Core enumeration → FR-001/005 ↔ `03` PortEnumerationEngine, `06` PortEnumerator, `09` S2. Consistent.
- Service identification → FR service IDs ↔ `03` ServiceRegistry, `04` ADR-007, `05` override/fingerprint tables, `09` S1. Consistent.
- Stop/restart → FR-020 ↔ `03` ActionLayer, `06` ActionService + XPC, `07` helper policy, `09` S4, `10` Phase 4. Consistent and privilege-gated consistently across all.
- Live refresh → FR refresh/NFR-003 ↔ ADR-006, `08` adaptive polling, `09` diffing. Consistent **subject to C-2**.

No requirement in `01` was found to have no architectural or contractual home, and no component in `03` lacked a requirement or contract.

## 6. Verdict
The blueprint is **internally coherent and ready for product-owner review**, with two conditions recorded rather than hidden:
1. **C-2 (polling cadence)** is resolved by fiat in favor of ADR-006; the owner should confirm via D-6.
2. **C-3 (ADR status)** — all ADRs are recommendations pending owner sign-off; the approval gate in the parent brief is respected (this review does NOT constitute approval to build).

The single largest unresolved scope/cost/security lever is **D-1 (privileged stop in v1)**; the single largest technical risk is **RISK-01 (enumeration on Tahoe)**, retired first via the Phase 0 spike. Implementation must not begin until D-1, D-2, D-3 are answered and the Phase 0 spike validates enumeration.

## 7. Residual open questions for the product owner
Consolidated in `11-risk-register.md` §D (D-1..D-10). The four most consequential, restated:
- D-1: privileged stop in v1?
- D-2: distribution channel (constrains helper)?
- D-3: minimum macOS?
- D-5: cross-user visibility in v1?

## Skill provenance
- Read in full before this stage: `code-review` was not read; this is a design-stage cross-check, not a code review. `security-review` (confidence/severity framing → C-1..C-5 disposition table separates resolved vs recorded-not-resolved and refuses to rubber-stamp unresolved security questions like C-5); `antislop` (R-36 → refuses to present unvalidated ADR/perf claims as settled; C-3 explicitly downgrades "Accepted" ADRs to pending-owner).
- `backend-development`, `tdd`, `ios-design`, `diagram-design` read earlier this session informed the delegated stage outputs this review cross-checks.