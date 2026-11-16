# Stage 10 — Testing Strategy (Ports On)

## Inputs

- `.planning/_shared-context.md` — verified environment (macOS 26.7.3 Tahoe, arm64, Xcode 27.2, Swift 6.4.2), the enumeration research (`lsof`, `netstat`, `sysctl`+`libproc` programmatic path), sandbox/hardened-runtime/`SMAppService` privileged-helper facts, TCC/Full Disk Access, and the kill-permission constraint (a process can only signal what it owns; other users' processes need a root helper).
- Greenfield repo — empty except `.git`/`.planning/`. No code, no test files exist yet. This doc is planning only.
- TDD skill grounding (`~/.agents/skills/tdd/SKILL.md`, `mocking.md`): test at **pre-agreed seams** through public interfaces; mock only at **system boundaries**; don't mock your own classes; work in **vertical slices** (one test → one implementation); red before green.

## Completion condition

A written strategy exists that (a) names the pre-agreed seams Ports On will be tested at, each with what it catches/misses, (b) assigns test levels, (c) walks a representative TDD red-green slice, (d) defines fixture/fake strategy for synthesizing `PortEntry` samples, (e) lists what cannot be automated plus a manual verification checklist, and (f) defines quality gates. Every item traces to a seam or a stated risk; no coverage-percentage target is used as an objective.

---

## 1. Pre-agreed seams (the only places tests go)

Per the TDD skill, no test is written at an unconfirmed seam. These six are proposed as the pre-agreed set for Ports On. They are all **logic or system boundaries**, chosen because they are where a defect would silently produce a wrong port list, a wrong service label, or an unsafe stop action.

| Seam | Kind | What it catches | What it misses |
|---|---|---|---|
| **S1 — ServiceRegistry mapping** (`port + process-name → ServiceProfile`) | Pure logic | Mis-mapping a known server to the wrong service (e.g. port 80 + `nginx` must resolve to the nginx profile, not a generic "web server"); unknown port/process falling through to the "Unknown" fallback; case/whitespace normalization of process names. | Whether the real process name on the box matches the names in the registry (that's the resolver/enumerator's job), and whether a service is actually running. |
| **S2 — PortEnumerator protocol boundary** (`PortEnumerator` → `[PortEntry]`) | System boundary (kernel) | Anything downstream of enumeration: UI, mapping, and decision logic can all be exercised against a **fixed** `PortEntry` stream without touching `sysctl`/`lsof`. Also catches the app's handling of empty results, duplicate ports, and IPv4/IPv6/UDP shapes. | Whether the real `sysctl`/`libproc` struct parsing is correct on a given macOS build — that is *not* unit-testable and is covered by the integration smoke test (T-L1) and manual checks. |
| **S3 — ProcessResolver protocol boundary** (`pid → ProcessInfo{name, user, path}`) | System boundary (`libproc`) | Downstream logic given a resolved process: how the app treats a vanished PID, a PID it lacks permission to inspect, and name/owner normalization fed into S1 and the decision policy. | Whether `proc_pidinfo` itself returns truth on a protected/other-user process (needs a real, sometimes privileged, environment). |
| **S4 — Stop-action decision policy** (`PortEntry + ProcessInfo + rules → Allow / Warn(reason) / Deny(reason)`) | Pure logic | The safety core: deny-list (e.g. never offer stop on system/PID 1/launchd/sandbox-critical), warn-list (own-process but risky), ownership check (not your process → deny without a helper path), and that a deny always carries a user-facing reason. Highest-value seam — a bug here lets a user kill something critical. | Whether the OS actually permits the resulting signal — enforcement lives in the helper/kernel and is manually verified. |
| **S5 — Override persistence** (`PortEntry/identity → user override`, load/save) | Boundary (local store) | That a user-labelled port survives save → reload → restart, that overrides key correctly (port+family, not display string), and that corrupt/absent store degrades to defaults rather than crashing. | Real multi-process write contention on the store file; verified by convention, not concurrency tests. |
| **S6 — XPC helper request validation** (app → privileged helper: validate/authorize a stop request) | Boundary (IPC + privilege) | That the helper **refuses** unsigned/unauthorized/malformed requests, refuses to signal a deny-listed target, refuses a request outside the caller's entitlement, and that a valid request maps to the intended PID+signal. This is the security seam. | Whether the daemon is actually registered/elevated and whether the kernel honors the signal — manual verification (§6), because it needs a real installed, privileged daemon. |

> Mocking rule applied (per `mocking.md`): S2, S3, S6 are genuine **system boundaries** (kernel, `libproc`, privileged IPC) and get fakes/protocol stubs injected via dependency injection. S1, S4, S5 are **our own logic** and are tested **directly and for real** — no mocks of internal collaborators. Time-dependence in S5 (timestamps) uses an injected clock, the one allowed non-boundary fake.

## 2. Test levels

- **T-L0 — Unit (in-process, no I/O).** S1 mapping, S4 decision policy, and the pure parts of S5 (override keying/normalization). These run in milliseconds with no daemon, no network, no `sysctl`. This is where the bulk of assertions live because these seams are pure and cheap. Fakes for S2/S3 are plain value arrays, not mocks of our own code.
- **T-L1 — Integration (in-process against real local state where safe).** A **real enumeration smoke test** (S2 against the live implementation) asserts that *at least the loopback listener is found* when a known listener is up. **Environment-dependent — mark accordingly:** it needs a listener to exist (the test opens its own `127.0.0.1` socket), and permission scope varies by user. It asserts presence of *its own* socket, never a specific third-party port, so it stays deterministic. Also integration: S5 load/save round-trip against a real on-disk store in a temp dir.
- **T-L2 — Manual / scripted verification.** The privileged-helper path (S6 end-to-end), TCC prompts, and killing another user's process. Not automatable in CI; see §6 checklist.

**macOS UI automation limits.** There is no CI-stable UI-driver for a SwiftUI/AppKit macOS app we can rely on here: XCUITest can drive this app, but it is slow, brittle against window focus/accessibility quirks, and unreliable on a headless/locked CI Mac. Decision: **no automated UI-level tests as a gate.** UI behavior is covered indirectly by asserting the view-model/presentation seam (the `[PortEntry]` → row-model transformation, treated as part of S1/S2 downstream logic), and the visual/interaction behavior is verified manually (§6). This is a deliberate scope choice, stated so it isn't mistaken for an omission.

## 3. TDD red-green workflow — representative slice

Vertical slice: *"Map listening port 80 owned by process `nginx` to the nginx service, and offer stop because the current user owns it."*

1. **Red (test first).** At S1: write one failing test — given a fixed `PortEntry(port: 80, proto: .tcp, pid: 4242)` and a resolved `ProcessInfo(name: "nginx", user: currentUser)`, the mapping yields the nginx `ServiceProfile`. Run it; it fails because no registry/mapping exists yet. One test, one seam.
2. **Green (minimal code).** Implement only enough registry + mapping to make that single case pass — a registry containing the nginx entry and a lookup that normalizes the process name. No speculative ports, no caching, no UI yet.
3. **Next red (grow the slice).** At S4: a failing test that the same input yields `.allow` (or `.warn` per policy) for a user-owned process — then implement the ownership branch.
4. **Next red (the deny path).** A failing test that a deny-listed target (e.g. PID 1 / `launchd`) yields `.deny(reason:)`; implement the deny-list.
5. **Refactor is *not* in this loop.** Per the TDD skill, refactoring happens at review, not inside red→green.

Each cycle is a tracer bullet: one failing test → smallest passing implementation → observe what it teaches → next test. Tests assert **behavior through the public seam** (input → returned profile/decision), never internal structure, so a later refactor of the registry doesn't break them.

## 4. Fixtures and fakes — synthesizing `PortEntry` samples

- **`PortEntry` is a plain value type**, so fixtures are literal arrays — no mocking framework. A small in-test factory builds representative sets: a single loopback TCP listener, an IPv6 listener, a UDP entry, a wildcard (`*:port`) listener, duplicate ports across protocols, and an empty list. These cover the shapes S1/S2/S4 must handle.
- **Fake enumerators/resolvers** (`FakePortEnumerator`, `FakeProcessResolver`) implement the S2/S3 protocols and return these fixed arrays. They are injected, so S1/S4 logic is tested without a kernel call — the "design for mockability via dependency injection" rule applied at a real system boundary.
- **Independent source of truth** (anti-tautology rule): expected values in S1 tests are **hand-written literals** (e.g. the literal string `"nginx"` profile), never recomputed by calling the registry's own lookup — otherwise the test passes by construction.
- **Override store fixture:** S5 round-trips against a temp-directory store; a "corrupt store" fixture (invalid bytes) verifies graceful fallback to defaults.
- **No production data.** Every fixture is synthetic and self-contained; nothing is read from the user's real process table except the marked T-L1 loopback smoke test, which uses a socket the test itself creates.

## 5. Requirement → test map

| ID | Requirement (testing) | Seam / Level |
|---|---|---|
| REQ-101 | Port+process-name maps to the correct service profile; unknown inputs fall back to "Unknown". | S1 / T-L0 |
| REQ-102 | Process-name normalization (case/whitespace) before lookup. | S1 / T-L0 |
| REQ-103 | Downstream logic handles empty, duplicate, IPv4/IPv6/UDP, and wildcard listener shapes. | S2 / T-L0 (fake) |
| REQ-104 | Logic tolerates vanished / permission-denied PIDs from the resolver. | S3 / T-L0 (fake) |
| REQ-105 | Decision policy returns Allow / Warn(reason) / Deny(reason); deny-list and warn-list enforced; deny always carries a reason. | S4 / T-L0 |
| REQ-106 | Ownership check: a process not owned by the current user is never offered as a direct stop. | S4 / T-L0 |
| REQ-107 | User overrides persist across save→reload; corrupt/absent store degrades to defaults without crashing. | S5 / T-L0 + T-L1 |
| REQ-108 | Real enumeration finds a listener the test itself opens (loopback). **Environment-dependent — marked.** | S2 / T-L1 |
| REQ-109 | Privileged helper validates requests: refuses unauthorized, malformed, deny-listed, or out-of-entitlement stop requests. | S6 / T-L2 (manual) |
| REQ-110 | Row-model transformation of `[PortEntry]` for display is correct (the UI is verified via this seam, not UI automation). | S1/S2 downstream / T-L0 |

**Quality gates.**
- **Merge-blocking:** all T-L0 (S1, S4, S5-pure; REQ-102/105/106) green; build + unit test target pass. Owner: any reviewer; waiver: none for S4/REQ-105/106 (safety core).
- **Merge-blocking:** no new failure in the T-L1 loopback smoke test (REQ-108) when run on a dev Mac. Owner: author. Waiver: lead may waive for a known environment break, with a note.
- **Release-blocking (manual sign-off):** the §6 privileged-helper/TCC/kill checklist completed and recorded. Owner: release lead; waiver: release lead only, documented.

No coverage-percentage gate is set; coverage is a signal, not the objective.

## 6. Hard / impossible to automate — manual verification checklist

These cannot be honestly automated on this host and are verified by hand, recorded per release:

- [ ] **Privileged helper install/registration** (S6, REQ-109): `SMAppService` daemon registers, is elevated, and authorizes correctly. Needs a real installed, notarized, signed daemon — not reproducible in a unit target.
- [ ] **XPC end-to-end stop** (S6): a valid, authorized stop request actually signals the target process and the process exits.
- [ ] **Helper refuses bad requests** (REQ-109): invoke the helper with an unauthorized/malformed/deny-listed request (via a debug harness) and confirm refusal — the *validation logic* is unit-tested where it's pure, but the *running daemon's* enforcement is manual.
- [ ] **TCC / Full Disk Access prompt** for reading other users' processes / full command lines: confirm the prompt appears and that granting/denying changes what's visible.
- [ ] **Killing another user's / root's process**: confirm it is denied without the helper and succeeds only through the elevated helper path.
- [ ] **Real enumeration correctness on this build** (S2 integration limit): spot-check `lsof`/`netstat` output against the app's list on macOS 26.7.3, since `sysctl`/`libproc` parsing uses semi-private interfaces that can shift per macOS version.
- [ ] **UI interactions** (refresh, select, stop confirmation flow): manual pass, since automated macOS UI driving is not used as a gate (§2).

## Skill provenance

- Read `~/.agents/skills/tdd/SKILL.md` — adopted: test only at **pre-agreed seams** (drove §1's seam table and the catch/miss format), vertical slices / red-before-green (drove §3), no coverage target as objective (§ gates).
- Read `~/.agents/skills/tdd/mocking.md` — adopted: mock only at system boundaries, don't mock own classes, dependency injection for mockability, and independent source of truth against tautological tests (drove §1 note, §4 fixtures).
- All other skills: not read; not applicable to this stage.

## Stage 12 review integration
Reviewed and cross-checked against `01`, `03`, `05`–`08`, and `12`. Consistency notes in `12-architecture-review.md`:
- Seams S1–S6 align with the components in `03` and the contracts in `06`; the S4 stop-decision seam is correctly identified as the highest-value safety seam and maps to the helper deny/warn policy in `07`.
- Integration smoke test (T-L1) asserting the process's **own** loopback socket is correctly marked environment-dependent; the privileged-helper, TCC-prompt, and other-user-kill checks are correctly delegated to the manual checklist (§6) rather than automation.
- ADR-002 mechanism choice (sysctl+libproc primary) is consistent with the fake `PortEnumerator` boundary used for testability.
