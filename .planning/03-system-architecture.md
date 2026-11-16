## Stage 12 review integration
Reviewed and cross-checked against `01`, `04`–`12`. Two reconciliations recorded in `12-architecture-review.md`:
- **C-1 (naming):** the persistence models named here (`AppPreference`, `ServiceOverride`, `ServiceAlias`) are superseded by the canonical schema in `05-database-design.md` (`UserPreference`, `ServiceOverride`, `ProcessFingerprint`, `ActionLogEntry`). `ServiceAlias` ≡ `ProcessFingerprint`; `ActionLogEntry` is an addition to reflect in the action layer. Align naming at implementation start.
- **C-2 (polling):** the 2s-window / 5s-menu-bar / paused-idle cadence here matches ADR-006 and governs; `08-performance-strategy.md`'s three-tier scheme is a refinement to validate against AC-P1..P6 in Phase 3, not a competing decision.

## Stage 12 review integration
Reviewed and cross-checked against `01`, `04`–`12`. Two reconciliations recorded in `12-architecture-review.md`:
- **C-1 (naming):** the persistence models named here (`AppPreference`, `ServiceOverride`, `ServiceAlias`) are superseded by the canonical schema in `05-database-design.md` (`UserPreference`, `ServiceOverride`, `ProcessFingerprint`, `ActionLogEntry`). `ServiceAlias` ≡ `ProcessFingerprint`; `ActionLogEntry` is an addition to reflect in the action layer. Align naming at implementation start.
- **C-2 (polling):** the 2s-window / 5s-menu-bar / paused-idle cadence here matches ADR-006 and governs; `08-performance-strategy.md`'s three-tier scheme is a refinement to validate against AC-P1..P6 in Phase 3, not a competing decision.
