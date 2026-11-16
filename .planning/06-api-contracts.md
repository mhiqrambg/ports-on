## Stage 12 review integration
Reviewed and cross-checked against `03`, `05`, `07`, and `12`. Dispositions in `12-architecture-review.md`:
- **Enumeration source (open q.3)** resolved by ADR-002: sysctl+libproc primary, `lsof` fallback; the contracts here are source-agnostic by design and remain valid either way.
- **UDP "listeners" (open q.4)** deferred to owner decision D-4; `includeUDP` parameter stands.
- **FDA dependency (open q.1)** and **restart fragility (open q.2)** remain open and are gated by Phase 0 evidence / owner decisions (D-1, D-10, RISK-06). The `notPermitted(needsFullDiskAccess:)` path must stay reachable until FDA-bypass is settled.
- **Override granularity (open q.5)** needs a data-model decision before the override store is built (Phase 1), per `05-database-design.md`.
