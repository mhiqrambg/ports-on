# Stage 8 — Security Architecture (Ports On)

## Inputs

- `.planning/_shared-context.md` (Phase 1 brief): product scope, verified host facts (macOS Tahoe 26.7.3, arm64, Xcode 27.2), researched grounding on enumeration (`lsof`, `netstat`, `sysctl`/`libproc`), App Sandbox + Hardened Runtime, `SMAppService`, TCC `SystemPolicyAllFiles`, Developer ID notarization, and the fact that signalling another user's/root's process requires a root helper.
- Skills read for structure: `security-review` (severity + confidence framing, threat-per-finding shape) and `antislop` (no fabricated security/compliance claims, every decision has a stated reason).
- Planning-only constraint: this document specifies controls and requirements. It contains no application source code and no Xcode project.

## Completion condition

A reader can answer, for Ports On specifically: which sandbox/hardened-runtime entitlements the app takes and refuses; how the privileged helper is registered, validated, and constrained; when Full Disk Access is and is not required and what degrades without it; which actions are gated, confirmed, and audited; what is stored at rest; and how app + helper are signed and notarized. Every control has an ID, a launch stage, and an enforcement point (authoritative vs advisory), and residual risk is stated rather than papered over.

---

## 1. Assets, actors, trust boundaries, attack surfaces

**Assets**

- A1 — Process/port inventory (PIDs, owning users, command lines). Command lines can contain secrets passed as argv (tokens, passwords). Highest-sensitivity data the app touches.
- A2 — The privileged helper's ability to `signal()` an arbitrary PID as root. This is the single most dangerous capability in the product.
- A3 — Local persistence: user overrides DB + optional audit log.
- A4 — The app's own identity (Developer ID signature), which is what authorizes the helper to trust it.

**Actors**

- The local user (legitimate operator). Assumed to control the machine they are seated at.
- Another local user / a malicious local process running as a different uid. Can it influence the helper?
- A trojan or spoofed binary impersonating the Ports On UI to reach the helper.
- A supply-chain attacker (compromised build/dependency) — addressed at the signing/notarization layer.

**Trust boundaries**

- TB1 — macOS App Sandbox around the UI process. Everything the UI reads about *other* processes crosses this boundary.
- TB2 — The XPC connection between the sandboxed UI and the root helper. This is the privilege-escalation boundary and the most important one in the design.
- TB3 — TCC (`SystemPolicyAllFiles`). Gates visibility into other users' processes and full command lines.
- TB4 — Process signal authority (uid ownership). A process may generally signal only what it owns; crossing this requires the root helper.

**Attack surfaces**

- The XPC service endpoint exposed by the helper (the "kill anything" oracle risk).
- Parsing of process command lines / socket tables (untrusted, kernel- or tool-sourced strings rendered in the UI).
- The local DB and audit log on disk.
- The build/packaging pipeline (helper must be correctly signed *inside* the app bundle).

---

## 2. Sandbox + Hardened Runtime posture

Ports On splits into two processes with deliberately different postures. This is the architecture Apple documents for the case where a sandboxed app needs a capability it must not hold itself: keep the UI sandboxed, move the extra capability into a separate helper.

### 2.1 The UI app (the app the user launches)

- **App Sandbox: ENABLED.** This is the default posture and the reason the UI cannot be tricked into signalling arbitrary processes directly.
- **Hardened Runtime: ENABLED.** Mandatory for notarization; also required so the helper's code-signing validation of the app (REQ-015) has a trustworthy anchor.

**Entitlements the app TAKES (minimum set):**

| Entitlement | Why | Notes |
|---|---|---|
| `com.apple.security.app-sandbox` | Core confinement of the UI | Required baseline |
| *None for network* | Enumeration reads the local kernel socket tables via `sysctl` (`net.inet.tcp/udp.pcblist`) + `libproc`, or shells `lsof`/`netstat`. None of these is an outbound/inbound network connection by the app. | See REQ-001 |

**Entitlements the app DELIBERATELY AVOIDS (and the reason each is a trap):**

| Avoided entitlement | Why refuse |
|---|---|
| `com.apple.security.network.server` | Would let the app bind/listen on a port. Ports On is a *local viewer*, not a server. Granting this widens the surface for no product benefit. |
| `com.apple.security.network.client` | Not needed. Enumeration is local; no telemetry, no update-phoning-home in Phase 1. |
| Any entitlement that grants reading other processes | There is no App Sandbox entitlement that means "see every process's command line." That capability comes from running un-sandboxed/rooted (the helper) or from TCC Full Disk Access, not from a sandbox key. Do not reach for a broad entitlement to fake it. |

**Requirement — REQ-001 (no network entitlements):** The UI app must be buildable and fully functional for *its own user's* port/process view with **no** `network.client` and **no** `network.server` entitlement. Launch stage: limited beta. Rationale: least privilege; the product is a local tool.

**Requirement — REQ-002 (enumeration stays in-process where possible):** Prefer the no-subprocess path (`sysctl` + `libproc`) for the default view so the app does not spawn `lsof` per refresh. This is a hardening *and* performance choice: fewer child processes, less argv surfaced, less parsing of tool output. Launch stage: limited beta. (Grounded: shared-context "programmatic, no-subprocess path".)

**Requirement — REQ-003 (treat enumerated strings as untrusted):** Command lines, process names, and user names pulled from the kernel/`lsof` are attacker-influenced data (a malicious process can name itself anything). They must never be executed, must be safely truncated, and must be rendered as inert text in the UI (no rich interpretation of argv). Launch stage: limited beta. This maps to the injection class in the `security-review` skill: the "input" here is other processes' argv, and it is not to be trusted.

---

## 3. Privileged helper threat model

### 3.1 Why a helper, and what it is for

A process can generally signal only processes it owns. Stopping/restarting **another user's** or a **root** process therefore needs root authority. Ports On gets that authority from a single, narrow launchd daemon registered via `SMAppService` (ServiceManagement), reached over XPC. `SMJobBless` and `AuthorizationExecuteWithPrivileges` are deprecated and must not be used.

```mermaid
flowchart LR
    subgraph UI["Ports On UI (App Sandbox + Hardened Runtime, uid=user)"]
        A[Enumerate own-user ports<br/>sysctl + libproc]
        B[Confirm + audit<br/>stop/restart intent]
    end
    subgraph TB2["XPC trust boundary (validated connection)"]
        X((XPC))
    end
    subgraph H["Privileged helper daemon (launchd, root, Hardened Runtime)"]
        P[Validate sender code signature]
        Q[Apply policy: allow/deny/warn]
        R[signal() target PID]
    end
    K["Other users' / root processes"]
    A --> UI
    B --> X --> P --> Q --> R --> K
```

### 3.2 Helper validation (the boundary that matters)

The helper is a root-level service. If it accepts a signal request from *any* local process, it is a "kill anything" oracle. Preventing that is the core of this design.

**Requirement — REQ-015 (authoritative sender validation):** On every XPC connection the helper must verify the connecting client's code signature: the client must be signed with the **same Apple Developer Team ID** as the helper and carry the Ports On **bundle identifier**. A connection failing this check is dropped before any request is processed. This is the **authoritative** enforcement point for "only Ports On may drive the helper." Launch stage: limited beta.

**Requirement — REQ-016 (environment constraints per WWDC23):** The helper's launchd configuration must apply ServiceManagement/launchd environment constraints so the daemon cannot be trivially re-targeted or run in an attacker-chosen environment: fixed `Program`/`ProgramArguments` path inside the app bundle, no inherited user environment, restricted `MachServices` to only the helper's own XPC endpoint, and **no** `Sockets` (the helper has zero network listeners). Launch stage: limited beta. (Grounded: shared-context WWDC23 "Protect your Mac app with environment constraints".)

**Requirement — REQ-017 (least privilege):** The helper runs as root but must do **only** two things: (a) validate and (b) `signal()` a target PID. It must **not** enumerate processes (that is the UI's job, see §4), must not execute arbitrary binaries, must not spawn shells, and must not read files. The smaller the helper's code, the smaller the oracle. Launch stage: limited beta.

**Requirement — REQ-018 (no "kill anything" oracle):** The helper must independently re-validate every request against a compiled-in policy before signalling. The UI's confirmation is **advisory**; the helper's policy check is **authoritative** (this is the control-placement rule from the Method section). The helper must reject, at minimum: any PID on the deny list (§5), any PID that does not exist at request time, and any request carrying a signal outside the allow-listed set (`SIGTERM`, `SIGKILL`, `SIGSTOP`, `SIGCONT`). Launch stage: limited beta.

**Requirement — REQ-019 (restart is not arbitrary code execution):** "Restart" must not mean "helper launches an attacker-chosen binary." Restart is only permitted for a target that is a launchd-managed service, performed via `launchctl` re-kick/start of that **already-registered** label, never by executing a path supplied by the client. If a target is not launchd-managed, restart is refused (stop-only). Launch stage: limited beta. This closes the most dangerous escalation: turning "restart" into "run this program as root."

**Requirement — REQ-020 (single-purpose, audited helper):** The helper writes a local record for every signal it performs (see §6). A root capability that is unlogged is unauditable. Launch stage: limited beta.

### 3.3 Residual risk for the helper (stated, not hidden)

- **Root compromise is total.** If the helper binary itself is replaced by a malicious, correctly-signed build on a developer machine, or if a signing key is stolen, REQ-015's anchor is broken. Mitigation is process-level (key custody, notarization, §7), not a code control. Residual: accepted, disclosed.
- **TOCTOU on PID reuse.** A PID validated at request time could be reused by a different process before `signal()` lands. The helper should validate (pid exists + matches the expected owning uid/label when known) as close to the `signal()` call as possible. Residual: low, but real; PID recycling races are inherent to signal-by-pid. Reduce by resolving targets to (pid, owning-uid, name) tuples and re-checking just before signalling.

---

## 4. TCC / privacy: when Full Disk Access is actually needed

Grounded: shared-context TCC note — reading **other users'** processes / **full** command lines can require Full Disk Access (TCC service `SystemPolicyAllFiles`).

| Capability | Needs Full Disk Access? | Mechanism |
|---|---|---|
| See **current user's** listening ports + owning PIDs | **No** | `sysctl`/`libproc` or `lsof` (own-user) — REQ-002 |
| See **other users'** listening ports + PIDs | Effectively **yes** (or run as root) | Requires privilege to cross TB4; without it the sockets are invisible or unattributed |
| See **full command lines** of other users' processes | **Yes** | `SystemPolicyAllFiles` gates the argv of processes the caller does not own |

**Requirement — REQ-030 (default view needs no elevated TCC):** The out-of-the-box experience must show the current user's own port→process map with **no** Full Disk Access prompt and **no** root helper invocation. Launch stage: limited beta. Reason: the majority of a developer's "what is on :3000" question is about their own processes; demanding Full Disk Access up front is both a privacy cost and an adoption cost.

**Requirement — REQ-031 (graceful degradation when FDA absent):** When Full Disk Access is not granted, the app must: (a) still show the current user's processes fully; (b) show other users' sockets as *present but unattributed* (port + state, owner shown as "another user"); (c) display a non-blocking, dismissible banner explaining that full attribution and cross-user stop/restart require enabling Full Disk Access and/or the helper, with a path to System Settings. It must **not** silently show an empty list or a broken view. Launch stage: limited beta. This is the empty/limited "state" the `antislop` skill demands for data views, applied to a privacy boundary.

**Requirement — REQ-032 (cross-user visibility is opt-in and explicit):** Elevating to see all users' processes must be a deliberate user action that names the cost ("Ports On will request Full Disk Access / will use its privileged helper"). Never request elevated visibility as a side effect of a routine refresh. Launch stage: limited beta.

**Requirement — REQ-033 (argv secrets are handled carefully):** Because command lines can contain secrets (A1), the app must not persist full argv for other users' processes, must truncate long argv in the UI, and must not copy secret-bearing argv to the clipboard or logs by default. Launch stage: limited beta. (Ties to §6 data-at-rest and the `security-review` data-protection class.)

---

## 5. Permission / action model for stop & restart

Stop and restart are destructive, privileged operations. They must be explicit, confirmed, audited, and policy-bounded.

**Requirement — REQ-040 (explicit intent):** There is no implicit or bulk stop. Every stop/restart is a discrete, deliberate user action on one identified target. No "stop all," no drag-to-kill. Launch stage: limited beta.

**Requirement — REQ-041 (confirmation):** Stopping or restarting any process requires an explicit confirmation step naming the process, its owner, and the port. Confirmation is rendered by the UI and is **advisory**; the helper's own policy check (REQ-018) is the authoritative gate. Launch stage: limited beta.

**Requirement — REQ-042 (own-process fast path):** Stopping a process the **current user owns** may use a lighter confirmation (single confirm), because no privilege boundary is crossed. Launch stage: limited beta.

**Requirement — REQ-043 (cross-user/root requires the helper + stronger confirm):** Stopping/restarting another user's or a root process routes through the helper (TB2) and requires a stronger confirmation that states the elevated consequence. Launch stage: limited beta.

**Deny list (hard refusal, never stoppable via Ports On):** `launchd` (pid 1), `WindowServer`, `loginwindow`, `kernel_task`, `coreaudiod`, `bluetoothd`, and other launchd-critical/system daemons the user cannot reasonably expect to kill safely. The helper must refuse these regardless of what the UI sends (REQ-018).

**Warn list (allowed only after an extra warning acknowledging system impact):** user-recognizable but system-relevant services (e.g. `dockerd`/Docker Desktop, `brew` services, common login items). Stopping these is permitted but must warn that dependent work may be interrupted.

**Requirement — REQ-044 (enforce deny/warn lists at the authoritative layer):** The deny list must be enforced in the **helper** (authoritative), not only in the UI (advisory). The warn list is surfaced in the UI confirm dialog and must also be re-checked in the helper. Launch stage: limited beta. (Control-placement rule: an advisory-only deny list is a design defect.)

**Requirement — REQ-045 (restart restricted to launchd-managed targets):** As REQ-019, restart of a non-launchd-managed target is refused, with the UI explaining why. Launch stage: limited beta.

---

## 6. Data at rest & audit

**Requirement — REQ-050 (DB holds no secrets):** The local database stores only: user overrides (custom process labels/aliases, "always ignore this port," pinned/suppressed rows), UI preferences, and (optionally) audit entries. It must **not** store credentials, tokens, or full argv of other users' processes. No encryption-at-rest is required *because nothing secret is stored*; if a future feature introduces a secret, encryption (Keychain) becomes mandatory. Launch stage: limited beta.

**Requirement — REQ-051 (audit log is optional and integrity-conscious):** The optional audit log records: timestamp, action (stop/restart), target (pid + name + owning uid + port), whether it crossed the privilege boundary (helper-mediated), and outcome. It is written locally only. It must be robust to partial writes and must never contain secret-bearing argv (REQ-033). It is **not** tamper-proof; state this honestly rather than claiming a security guarantee it does not have. Launch stage: limited beta for the audit trail; the helper's own action record (REQ-020) is the authoritative audit of privileged actions.

**Requirement — REQ-052 (logging hygiene):** No secrets from argv, no full environment, and no credentials in either the app's or the helper's logs. Map to the `security-review` data-protection/logging classes. Launch stage: limited beta.

---

## 7. Supply chain & notarization

**Requirement — REQ-060 (Developer ID + Hardened Runtime on both binaries):** Both the app and the helper must be signed with a Developer ID certificate and have Hardened Runtime enabled. Launch stage: limited beta.

**Requirement — REQ-061 (notarize app AND helper):** Both the app and the embedded helper must be notarized before distribution. The helper is embedded inside the app bundle (e.g. `Contents/Library/LaunchServices` style helper location used by ServiceManagement) and must be built and signed as a proper dependency so its signature validates at REQ-015. Launch stage: limited beta. (Grounded: shared-context notarization note; helper executables must also be signed/notarized.)

**Requirement — REQ-062 (build order guarantees valid helper signature):** The build pipeline must sign the helper first, then the app, so the app's seal covers the helper's signed binary. A helper signed *after* embedding invalidates the app's signature and breaks both notarization and REQ-015. This is a packaging correctness requirement, not a nicety. Launch stage: limited beta.

**Requirement — REQ-063 (no fabricated security claims):** Marketing/README must not claim certifications or guarantees (no "SOC 2", no "unhackable", no "enterprise-grade security") that this design does not establish. Grounded in the `antislop` skill (R-36) and the honesty bar in `security-review`. Launch stage: public launch copy review.

---

## 8. Threat table (threat -> mitigation)

Severity uses the `security-review` framing: impact + realistic preconditions, with a short rationale. "Stage" = the launch stage at which the control is required.

| ID | Threat | STRIDE | Precondition / realism | Impact | Severity rationale | Mitigation (control IDs) | Stage |
|---|---|---|---|---|---|---|---|
| T-01 | Malicious/spoofed local binary connects to the helper and asks it to kill arbitrary PIDs ("kill anything" oracle) | Elevation of Privilege / Spoofing | Any local process can attempt an XPC connect | Arbitrary process termination as root | High: root kill primitive, but requires a local process and a valid-looking request | REQ-015 (sender code-signing validation, authoritative), REQ-017 (least privilege), REQ-018 (helper-side policy) | limited beta |
| T-02 | "Restart" abused to execute an attacker-chosen binary as root | Elevation of Privilege | Client supplies a target the helper will launch | Root code execution | Critical if restart spawned arbitrary paths | REQ-019 / REQ-045 (restart only re-kicks an already-registered launchd label; no client-supplied path) | limited beta |
| T-03 | Deny-list bypass: UI tricked into asking helper to kill `launchd`/`WindowServer` | Tampering / DoS | User persuaded (UI bug/social) to stop a system process | System instability, forced reboot | Medium: high nuisance, needs user action; helper can refuse deterministically | REQ-044 + REQ-018 (deny list enforced in helper, authoritative) | limited beta |
| T-04 | PID reuse race -> signal lands on the wrong process | Tampering | PID recycled between validation and `signal()` | Kill an unintended process | Low-Medium: narrow window, real | Validation as close to `signal()` as possible; resolve to (pid, uid, name) and re-check (§3.3) | limited beta |
| T-05 | Secrets leaked via other users' command lines (argv) into UI, logs, or DB | Information Disclosure | Full Disk Access granted; another user ran a process with a token in argv | Credential exposure to the local viewer | Medium: depends on another user's bad habit of putting secrets in argv | REQ-033, REQ-050, REQ-052 (no persistence, truncation, log hygiene) | limited beta |
| T-06 | Over-broad entitlements widen the UI attack surface (network server/client) | Attack-surface bloat | N/A - design choice | Larger surface, no benefit | Low: prevented by not granting | REQ-001 (no network entitlements) | limited beta |
| T-07 | Enumeration output (argv/process names) interpreted as more than text (injection) | Tampering | A process names itself maliciously | UI misbehavior | Low: rendered as inert text | REQ-003 (untrusted-data handling, safe truncation) | limited beta |
| T-08 | Privacy over-reach: app requests Full Disk Access when unnecessary | Privacy | N/A - design choice | User trust cost, unnecessary consent | Low-Medium: trust/adoption | REQ-030, REQ-031, REQ-032 (default no-FDA view, opt-in elevation) | limited beta |
| T-09 | Helper replaced/unsigned on a tampered build; or signing key stolen | Spoofing / supply chain | Developer machine or key compromised | REQ-015 anchor broken -> oracle | High impact, low likelihood, accepted | REQ-060, REQ-061, REQ-062 (sign + notarize both; correct build order); key custody is process control | public launch |
| T-10 | Unprivileged app claims to have stopped a process it could not (false success) | Repudiation | Signal fails silently | User misdiagnoses a port | Low | REQ-051 audit records outcome; UI reflects actual result, including failure | limited beta |

---

## 9. Control placement review (authoritative vs advisory)

Per the Method: a design that relies on an advisory check as its only protection is defective.

| Control | Authoritative enforcement point | Advisory layer(s) | Verdict |
|---|---|---|---|
| Only Ports On may drive the helper | Helper: XPC sender code-signing validation (REQ-015) | UI (won't expose the helper) | Correct |
| Never kill deny-listed system processes | Helper: compiled-in deny list (REQ-044, REQ-018) | UI warn/confirm dialog | Correct - UI-only would be a defect |
| Restart cannot run arbitrary binaries | Helper: launchd-label-only restart (REQ-019/REQ-045) | UI disables restart for non-launchd targets | Correct |
| Stop/restart is user-intended | UI confirmation (REQ-040/041) is **advisory**; helper policy (REQ-018) is authoritative | - | Intentional split; documented |
| No network capability in UI | Build/entitlements (REQ-001) | - | Correct (compile-time) |
| Secrets not persisted | App: DB writer (REQ-050) + log hygiene (REQ-052) | - | Correct |

**Inconsistency guard:** any future change that makes the UI the *only* place a deny/warn decision is made, or that lets the helper launch client-supplied paths, breaks this architecture and must be rejected at review.

---

## 10. Operational mechanisms (background security-relevant work)

- **Session/daemon lifecycle:** the helper is a launchd daemon managed by `SMAppService`; it is launched on demand by XPC and does not need a background sweeper. No long-running privileged process idling as root.
- **Token/key rotation:** there are no long-lived secrets or tokens in Ports On Phase 1 (nothing to rotate). The only "key" material is the Developer ID signing identity, whose custody is a human/process control (REQ-060, §7 residual).
- **Audit growth:** the optional audit log (REQ-051) needs a defined retention/rotation approach before public launch so it cannot grow unbounded. Limited beta: document a simple size cap or rotate-on-launch; public launch: explicit retention setting.

---

## 11. Missing controls / defense-in-depth (recommended, not blocking limited beta)

- **Hardened Runtime runtime exceptions kept minimal:** do not add `com.apple.security.cs.allow-jit`, `allow-unsigned-executable-memory`, or `disable-library-validation` unless a concrete, documented need arises. Each widens the surface. (Map to `security-review` misconfiguration class.)
- **XPC reply/timeout discipline:** bound every XPC call with a timeout and a typed reply so a hung helper cannot wedge the UI; fail closed (report failure, do not claim success - supports T-10).
- **Rate-limit stop/restart:** cap privileged stop/restart operations per unit time in the helper to blunt scripted abuse if the boundary is ever weakened.
- **Clear "why am I elevated" affordance:** a persistent, honest indicator in the UI whenever the helper is armed/available, so elevation is never invisible (pairs with REQ-032).

---

## 12. Residual risks & decisions requiring an owner

- **R-SEC-1 (accepted):** Root helper compromise is total if the signed helper binary or signing key is compromised. Control is process/key custody, not code. Owner: release/signing process.
- **R-SEC-2 (residual):** PID-reuse TOCTOU cannot be fully eliminated with signal-by-pid; mitigated by tight (pid, uid, name) re-validation.
- **R-SEC-3 (decision needed before public launch):** Audit-log retention/rotation policy (§10) must be pinned down; limited beta ships a size cap only.
- **R-SEC-4 (decision needed):** Final deny/warn list contents (§5). The lists above are a starting set; the owner should confirm the exact system daemons that are hard-denied for macOS Tahoe 26.x before public launch.
- **R-SEC-5 (decision):** Whether cross-user *visibility* (not just stop/restart) is offered via the root helper, or gated purely behind Full Disk Access. This doc assumes visibility prefers FDA (REQ-031/032) and the helper is reserved for signalling; confirm with the UX/privacy owner.

This is a design-stage review. It does not assert that any implementation is secure or compliant; it specifies the controls Ports On must implement and the residual risks it must disclose.

## Skill provenance

- `security-review` - used its severity/confidence framing and per-finding shape to structure the threat table (§8) and to map controls to vulnerability classes (injection -> REQ-003, data protection/logging -> REQ-033/050/052, misconfiguration -> §11). Its "distinguish authoritative vs advisory / trace where input comes from" discipline drove §9 (control placement) and REQ-018.
- `antislop` - used its no-fabricated-claims rule (R-36) for REQ-063 and the honest-placeholder/limitation honesty bar for the graceful-degradation requirement (REQ-031) and the audit-log "not tamper-proof" disclosure (REQ-051).

## Stage 12 review integration
Reviewed and cross-checked against `03`, `04` (ADR-003/004), `06`, and `12`. Dispositions in `12-architecture-review.md`:
- **Helper inclusion is gated by owner decision D-1 (OQ-1).** If privileged stop is deferred, this doc's helper threat model (TB2, REQ-015..019) is retained as a design requirement for the v1.1 helper but is not on the v1 critical path.
- **C-5 (cross-user visibility mechanism)** remains unresolved: whether the root helper bypasses Full Disk Access for command-line reads is an empirical question resolved in Phase 0; R-SEC-5 (D-10) records the owner decision.
- **Owner decisions carried to Phase 5:** R-SEC-3 (audit retention / D-8), R-SEC-4 (final deny/warn list / D-9), R-SEC-5 (D-10). Residual risks R-SEC-1..5 are registered as RISK-02/03/04/09/10/11 in `11-risk-register.md`.
