# 11 — Risk Register (owned by software-architect)

**Stage owner:** software-architect
**Status:** Complete. Aggregates risks surfaced in Stages 1–10 into one register; owner decisions are listed separately so the product owner has a single sign-off list.

## Inputs
Risks, assumptions, and open questions surfaced in `00`..`09` (each doc's "Risks / open questions" sections), the ADR records (`04`), the security residual risks R-SEC-1..5 (`07`), and phase-gating questions in `00`/`01`.

## Completion condition
Every material risk across the planning set is captured with a severity, direction (avoid/mitigate/accept/escalate), mitigation, and owner; product-owner decision items are enumerated in one place; unknown-unknowns are confessed, not hidden. PASS above.

---

## A. Technical risks

| ID | Risk | Sev | Direction / mitigation | Owner | Stage source |
|---|---|---|---|---|---|
| RISK-01 | **Enumeration mechanism fails on Tahoe.** `sysctl pcblist` struct layouts are semi-private and version-sensitive; `proc_pidinfo` owner-PID resolution may differ per user/privilege. Unvalidated by any prototype. | High | **Mitigate first, before architecture is committed:** Phase 0 throwaway spike (see `10-implementation-roadmap.md`). `lsof` remains a shipping fallback (ADR-002). | architect | 02, 03, 04 (ADR-002), 08 §10 |
| RISK-02 | **Helper becomes a "kill anything" oracle.** Root helper that signals arbitrary PIDs is the highest-value target (TB2 in `07`). | High | Helper holds authoritative policy: deny-list enforced in-helper, (pid,uid,name) re-validation, restart only via launchd re-kick of a registered label, never client-supplied paths (REQ-018/019), code-signature pinned XPC (REQ-015). | security-auditor + architect | 07 |
| RISK-03 | **PID-reuse TOCTOU.** Signal-by-PID can hit a recycled PID after a process exits. | Med | Tight re-validation (pid,uid,name) immediately before signal; residual accepted (R-SEC-2). | architect | 07 |
| RISK-04 | **Root helper compromise is total.** If the signed helper/signing key is compromised, an attacker gains root signalling. | Med | Process/key custody; sign helper before app (REQ-062); minimal helper surface; **not** code-level solvable (R-SEC-1, accepted). | release/signing | 07 |
| RISK-05 | **No listen/bind event API.** "Event-driven" watch is not available; polling is the only honest option. | Low | Polling with adaptive tiers + diffing (ADR-006, REQ-096..098). Sub-second change latency not guaranteed and disclosed. | architect | 03, 04 (ADR-006), 08 |
| RISK-06 | **Restart fragility.** Relaunching a non-launchd, non-docker process from a recorded `exePath/argv` breaks (cwd/env/TTY). | Med | Restart only for launchd-managed labels via `launchctl`; standalone targets degrade to `.unsupportedRestart` (stop-only) in v1. | api-designer → architect | 06 open q.2, 07 REQ-019 |
| RISK-07 | **TCC/FDA friction.** Reading other users' command lines triggers Full Disk Access prompts and harms first-run UX. | Med | v1 default = current-user visibility only; opt-in elevation with a non-blocking banner; degrade to unattributed rows when restricted (REQ-030..032). | architect/UX | 01 (R-102), 07, 08 |

## B. Security & distribution risks

| ID | Risk | Sev | Direction / mitigation | Owner | Source |
|---|---|---|---|---|---|
| RISK-08 | **Notarization/signing failure** blocks all distribution (NFR-005). | Med | Developer ID + notarize app **and** helper; build helper first; verify in Phase 5. | release | 01 (NFR-005), 07 |
| RISK-09 | **User mistakes stop for a critical process.** Stopping launchd/WindowServer/loginwindow/nginx-under-oat etc. | Med | In-helper authoritative deny list + in-app warn list (no stop offered at all on deny list); audit log (S4 seam is the highest-value test). | security-auditor | 07, 09 (S4) |
| RISK-10 | **argv contains secrets** (tokens/passwords in command lines) displayed or logged. | Low | Treat argv as untrusted data (REQ-003); secret redaction in display/logging (REQ-033). | architect | 07 |
| RISK-11 | **Audit log misread as tamper-proof.** Local SwiftData log is disclosed as *not* tamper-proof. | Low | Disclose in UI/README; no security claims (REQ-051/063, antislop R-36). | architect | 07 |
| RISK-12 | **Semi-private sysctl surface could break in a future macOS update** even after Tahoe ships. | Low | `lsof` fallback (ADR-002) and quarterly compatibility check on new macOS. | architect | 04 (ADR-002) |

## C. Scope / delivery risks

| ID | Risk | Sev | Direction / mitigation | Owner | Source |
|---|---|---|---|---|---|
| RISK-13 | **Unvalidated performance targets.** Every §7 perf number is ASSUMED (perf doc is explicit). | Med | Measure in Phase 3 (AC-P1..P6); correct targets with evidence; never present as measurements. | architect | 08 |
| RISK-14 | **Scope creep toward a firewall/port-forwarding tool.** Easy to accrete from nginx domain familiarity. | Med | v1 boundary fixed in `00`; out-of-scope list explicit; revisit only by owner request. | architect | 00 |
| RISK-15 | **Requirement-ID fragmentation.** Docs use disjoint ID schemes (FR-/NFR-, REQ-0xx/09x/11x/6xx). No single registry. | Low | Adopt one REQ-ID registry at implementation start (mapping table in `12`); low cost, prevents traceability loss. | architect | 08 §10, observed |
| RISK-16 | **Model-name drift between architecture and data docs** (`AppPreference`/`ServiceAlias` in `03`/`04` vs `UserPreference`/`ProcessFingerprint`/`ActionLogEntry` in `05`). | Low | Canonical: `05-database-design.md` schema. Reconcile `03`/`04` naming at implementation. | architect | 12 (this register) |

---

## D. Product-owner decision items (one sign-off list, in priority order)

These are the OQ/R-SEC items that gate scope, cost, or security posture. They block **implementation**, not planning. Answers can be "defer to v1.x" — that is a valid decision.

| # | Decision | Options | Gates | Default recommendation |
|---|---|---|---|---|
| D-1 (OQ-1) | Privileged stop/restart of other-user/root processes in **v1**? | helper now / defer to v1.1 | FR-020, R-101, Phase 4, RISK-02/04 | **Defer to v1.1** if the user is the only account; include in v1 if other-user/root processes must be stoppable |
| D-2 (OQ-4) | Distribution channel? | Developer ID + notarization / Mac App Store | NFR-005, helper viability, RISK-08 | **Developer ID + notarization** (MAC forbids the helper, forcing own-user-only scope) |
| D-3 (OQ-2) | Minimum macOS version? | Tahoe 26.x only / also 15/14 | ADR-001, sysctl surface | **Tahoe 26.x only** for v1 |
| D-4 (OQ-3) | UDP endpoints in v1? | TCP-only / TCP+UDP | FR-002 | TCP-only v1; UDP following (low cost either way) |
| D-5 (OQ-5) | Cross-user **visibility** in v1? | current-user only / FDA-gated full | FR-014/015, RISK-07 | Current-user only in v1 (no FDA prompt) |
| D-6 (OQ-6) | Default refresh cadence | confirm 2s/5s/paused or valuate | NFR-003 | Accept 2s window / 5s menu-bar / paused (ADR-006) |
| D-7 (OQ-7) | Menu-bar default display | count / top port / glyph | FR-021 | Port count + one-line summary |
| D-8 (R-SEC-3) | Audit-log retention policy | size cap / age-based | Phase 5 | Lazy on-append cap (REQ-608 recommendation); confirm cap value |
| D-9 (R-SEC-4) | Final deny/warn list for Tahoe 26.x | confirm starter lists | Phase 5 | Sign off the deny list before public launch |
| D-10 (R-SEC-5) | Cross-user visibility via root helper or FDA only? | helper / FDA | Phase 4/5 | FDA preferred; helper reserved for signalling |

## E. Unknown unknowns (honest disclosure)
- Whether `sysctl pcblist` layout used by apps like PortMon/Portia is stable across Tahoe point releases (RISK-01 covers via spike + fallback).
- Whether a macOS 26.x security update adds TCC gating to `proc_pidinfo` (affects D-5, RISK-07) — resolved empirically in Phase 0/3, not assumable now.

## Skill provenance
- Read in full before this stage: `security-review` (confidence-tier and "investigate before flagging" discipline shaped A/B table separations and prevented manufacturing low-confidence rows); `antislop` (R-36 no-fabricated-claims → RISK-13/11 explicitly label ASSUMED vs measured and refuse false reassurance).
- `backend-development`, `tdd`, `ios-design`, `diagram-design` read earlier this session informed the delegated stage outputs this register aggregates.