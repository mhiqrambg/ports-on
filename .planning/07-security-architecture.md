## Stage 12 review integration
Reviewed and cross-checked against `03`, `04` (ADR-003/004), `06`, and `12`. Dispositions in `12-architecture-review.md`:
- **Helper inclusion is gated by owner decision D-1 (OQ-1).** If privileged stop is deferred, this doc's helper threat model (TB2, REQ-015..019) is retained as a design requirement for the v1.1 helper but is not on the v1 critical path.
- **C-5 (cross-user visibility mechanism)** remains unresolved: whether the root helper bypasses Full Disk Access for command-line reads is an empirical question resolved in Phase 0; R-SEC-5 (D-10) records the owner decision.
- **Owner decisions carried to Phase 5:** R-SEC-3 (audit retention / D-8), R-SEC-4 (final deny/warn list / D-9), R-SEC-5 (D-10). Residual risks R-SEC-1..5 are registered as RISK-02/03/04/09/10/11 in `11-risk-register.md`.

## Stage 12 review integration
Reviewed and cross-checked against `03`, `04` (ADR-003/004), `06`, and `12`. Dispositions in `12-architecture-review.md`:
- **Helper inclusion is gated by owner decision D-1 (OQ-1).** If privileged stop is deferred, this doc's helper threat model (TB2, REQ-015..019) is retained as a design requirement for the v1.1 helper but is not on the v1 critical path.
- **C-5 (cross-user visibility mechanism)** remains unresolved: whether the root helper bypasses Full Disk Access for command-line reads is an empirical question resolved in Phase 0; R-SEC-5 (D-10) records the owner decision.
- **Owner decisions carried to Phase 5:** R-SEC-3 (audit retention / D-8), R-SEC-4 (final deny/warn list / D-9), R-SEC-5 (D-10). Residual risks R-SEC-1..5 are registered as RISK-02/03/04/09/10/11 in `11-risk-register.md`.
