## Stage 12 review integration
Reviewed and cross-checked against `03`, `04` (ADR-006), `09`, and `12`. Dispositions in `12-architecture-review.md`:
- **C-2 (polling cadence):** ADR-006 (2s window / 5s menu-bar / paused) governs. The three-tier adaptive scheme here (~10s closed / ~2s open-idle / ~1s interacting) is a **refinement** to validate against AC-P1..P6 in Phase 3, not a competing decision. Do not implement both.
- **All §7 quantitative targets are ASSUMED, not measured** — this is honest and intentional; Phase 3 measures them (AC-P1..P6) and corrects with evidence. Never present them as benchmarks.
- **Enumeration cost rationale (§2)** aligns with ADR-002 (programmatic primary). The owner-PID-without-FDA question is resolved empirically in Phase 0.
