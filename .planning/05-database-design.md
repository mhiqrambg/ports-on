## Stage 12 review integration
Reviewed and cross-checked against `03`/`04` (ADR-005), `06`, and `09`. Dispositions in `12-architecture-review.md`:
- **This schema is canonical** for persistence model naming (resolves C-1). `03`/`04` must align `AppPreference`→`UserPreference`, `ServiceAlias`→`ProcessFingerprint`, and account for `ActionLogEntry`.
- **C-2 (polling):** this doc is unaffected; ADR-006 cadence governs.
- **Open items carried forward:** history-cap value (R-SEC-3 / D-8) and the `ServiceKey` override granularity (`06` open q.5) must be pinned before the override store is built (Phase 1).
