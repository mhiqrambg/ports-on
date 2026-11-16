## Stage 12 review integration
Reviewed and cross-checked against `01`, `03`, `05`–`08`, and `12`. Consistency notes in `12-architecture-review.md`:
- Seams S1–S6 align with the components in `03` and the contracts in `06`; the S4 stop-decision seam is correctly identified as the highest-value safety seam and maps to the helper deny/warn policy in `07`.
- Integration smoke test (T-L1) asserting the process's **own** loopback socket is correctly marked environment-dependent; the privileged-helper, TCC-prompt, and other-user-kill checks are correctly delegated to the manual checklist (§6) rather than automation.
- ADR-002 mechanism choice (sysctl+libproc primary) is consistent with the fake `PortEnumerator` boundary used for testability.
