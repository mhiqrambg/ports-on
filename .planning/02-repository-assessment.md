# 02 — Repository Assessment (Stage 3)

**Stage owner:** software-architect
**Status:** Complete

## Inputs
- Working directory `/Users/mhiqrambg/Documents/Projects/ports-on`.
- Sibling project `~/Documents/Projects/nginx-proxy-helper`.
- Verified environment facts in `_shared-context.md`.

## Completion condition
The greenfield state of the repo is documented, any reusable prior work is assessed (and dispositioned), and the implied starting point for implementation is stated. PASS when a reader knows exactly what exists today, what can be reused, and what must be built from scratch.

## Current repository state: greenfield / empty
The repository contains **no application source**. As verified at planning time the working tree holds only:
- `.git/` — version control initialized.
- `.planning/` — this Phase 1 planning set (created this pass).

There is:
- No Xcode project or workspace.
- No Swift/SwiftUI sources, no `Package.swift`, no app target.
- No `package.json`/lockfile, no dependency manifests.
- No tests, no CI configuration.
- No README or license.

**Conclusion:** this is a true greenfield build. There is no existing architecture to preserve, no migration to plan, and no technical debt to retire. Every capability in `00-project-discovery.md` must be built from zero. Phase 2 (design) and implementation begin from an empty tree.

## Reusability assessment — sibling project
`~/Documents/Projects/nginx-proxy-helper` was inspected for reuse potential.

| Dimension | Sibling project | Ports On | Reusable? |
|---|---|---|---|
| Language / runtime | Python (CLI) | Swift 6 / SwiftUI (native app) | **No** — different language, runtime, and packaging |
| Form factor | Command-line tool + install/uninstall shell scripts | Menu-bar + window SwiftUI app | **No** |
| Core concern | Manage nginx site configs, enable/disable, install/uninstall nginx | Enumerate OS-level ports and owning processes | **Overlaps in domain, not in code** |
| Privilege handling | Shell scripts, sudo-driven | SMAppService helper + XPC (planned) | **Pattern reference only** |

**Disposition: reference-only.** The sibling project is useful as *domain context* — it confirms the product owner regularly hits reverse-proxy port conflicts and is comfortable with privilege-gated operations. It contributes **no code, no scripts, and no data** to Ports On. Any apparent overlap (both touch nginx and ports) is conceptual: nginx-proxy-helper *configures* a proxy that binds ports; Ports On *observes* what binds ports across the whole system. Keep them as separate projects; do not couple them.

## Implied starting point for implementation
- New Xcode app target (macOS, SwiftUI, arm64, deployment target per ADR-001).
- New local persistence store (per `05-database-design.md`) — nothing to migrate; schema starts at v1.
- New privileged-helper target only if the product owner opts into privileged stop for v1 (see `00-project-discovery.md` Open question 1 and `07-security-architecture.md`).
- No CI exists; a minimal build/test workflow is an implementation-phase concern, not a planning blocker.

## Risks surfaced by the empty-repo state
- **No prior validation of the riskiest assumption.** The central technical bet — that the chosen enumeration mechanism works reliably on macOS 26 — is unvalidated because there is no prototype. This is the top technical risk; see `11-risk-register.md`. A short throwaway spike (not part of Phase 1) should validate enumeration before committing to the full architecture.
- **No existing conventions.** Module structure, naming, and test layout are defined fresh in `03-system-architecture.md` and `09-testing-strategy.md`; there is no inherited convention to conflict with.

## Skill provenance
None. This stage is a factual inventory of the working tree and sibling project; no skill materially informed it.