# Shared Context — Ports On (Phase 1 planning brief for specialists)

Read this before writing your document. You are planning ONLY. Do not write application source code, do not create an Xcode project, do not install dependencies. You produce one planning markdown file at an exact path.

## Product
**Ports On** is a native macOS app for macOS Tahoe (26.x). It shows which network ports are active/in use on the local machine and which process/service owns each (e.g. nginx, docker, opencode, omp, nodejs, nextjs, astro). It lets the user inspect a port→process→service mapping and (security-gated) stop/restart a process.

This is a LOCAL desktop tool, not a server. There is no remote database and no backend service. Persistence is local only.

## Verified environment facts (do NOT re-verify)
- Host: macOS 26.7.3 (Tahoe), build 25G342, Apple Silicon arm64.
- Xcode 27.2 (build 27B52), Swift 6.4.2, target SDK `arm64-apple-macosx26.0`.
- Available on host: `lsof`, `/usr/sbin/netstat`, `launchctl`, docker (Homebrew `/opt/homebrew/bin`), brew, node v24.11.1 (nvm), npm, pnpm. There is NO `ss` on macOS.
- Repo `/Users/mhiqrambg/Documents/Projects/ports-on` is EMPTY (greenfield; only `.git` and `.planning/`).

## Technical grounding already researched (cite/extend, don't contradict)
- **Enumeration options on macOS:**
  - `lsof -nP -iTCP -sTCP:LISTEN` (add `sudo` to see all users + full command lines). Works, familiar, but spawns a subprocess per refresh and needs privilege for other users' processes.
  - `/usr/sbin/netstat -an` + grep LISTEN gives listening sockets but NO owning PID.
  - There is no `/proc` on macOS. `lsof` on macOS uses private sysctls (`net.inet.tcp.pcblist`), not `/proc` (Apple Developer Forums, thread 728731; spenceruresk.com PortMon article).
  - **Programmatic, no-subprocess path:** read the kernel socket tables via `sysctl` (`net.inet.tcp.pcblist` / `net.inet.udp.pcblist`) and map each socket to a PID using `libproc` (`proc_pidinfo` / `proc_pid_fdinfo`). This is what `lsof` and apps like PortMon/Portia do under the hood. Higher performance, but uses semi-private interfaces and requires careful struct handling per macOS version.
  - `Network.framework` (`NWPathMonitor`) reports path status only — it does NOT enumerate listeners. Not suitable as the enumeration source.
- **Sandbox / hardened runtime:** App Sandbox restricts access to other processes' resources. Apple's documented options when a sandboxed app needs a capability it lacks: (a) add an App Sandbox entitlement, (b) distribute a separate helper tool with the extra capability (Apple: "Discovering and diagnosing App Sandbox violations", "Configuring the macOS App Sandbox"). Hardened Runtime is required for notarization (Apple: "Hardened Runtime", "Configuring the hardened runtime").
- **Privileged helper:** `SMAppService` (ServiceManagement) is the modern way to register a launchd daemon/agent that runs with elevated privilege; communicate over XPC. `SMJobBless` and `AuthorizationExecuteWithPrivileges` are deprecated (Apple: "SMAppService", "Updating helper executables from earlier versions of macOS", "AuthorizationExecuteWithPrivileges"). WWDC23 "Protect your Mac app with environment constraints" is relevant to helper security.
- **TCC / privacy:** reading other users' processes / full command lines can require **Full Disk Access** (TCC service `SystemPolicyAllFiles`). Sandbox consent prompts apply to protected folders (eclecticlight.co articles on Privacy/Files & Folders/Full Disk Access; machardening.com TCC/PPPC overview).
- **Notarization:** Developer ID–signed software distributed outside the App Store must be notarized (Apple: "Notarizing macOS software before distribution"). Helper executables must also be signed/notarized.
- **Kill permissions:** a process can generally signal only processes it owns; stopping another user's/root's process requires a root helper (Portia, getportia.app "How Ports and Processes Work on macOS").

## Your output contract
- Write ONE markdown file to the exact path given in your task.
- Keep it tight and specific to Ports On. No generic boilerplate, no filler.
- Every requirement you state gets a unique ID (e.g. REQ-0NN). Reference other requirements by ID.
- Each doc starts with: `## Inputs`, `## Completion condition`, then the body.
- Use Mermaid for diagrams where your task asks (```mermaid fenced blocks).
- Record a `## Skill provenance` section listing any skills you read and what changed as a result; an empty section (state "none") is valid, but never name a skill you did not actually read.
- Do NOT touch anything outside your one file. Do NOT create app code.