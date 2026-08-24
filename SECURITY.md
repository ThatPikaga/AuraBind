# Security Policy

## Supported Versions

AuraBind is developed against the `master` branch and distributed through the
Omarchy Marketplace, which syncs from `master`. Only the current release line
receives security updates.

| Version | Supported          |
| ------- | ------------------ |
| 3.x (latest / `master`) | :white_check_mark: |
| < 3.0   | :x:                |

## Reporting a Vulnerability

**Please do not report security vulnerabilities in public GitHub issues.**

Instead:

1. Prefer GitHub's private vulnerability reporting: go to the repository's
   **Security** tab and choose **Report a vulnerability** (draft security advisory).
2. If that is unavailable, open a minimal issue stating that you have a
   security concern, or contact the maintainer (`ThatPikaga`) directly through
   GitHub, and share the details privately.

Please include:

- A description of the vulnerability and its potential impact
- Step-by-step reproduction instructions (or a proof of concept)
- The affected version or commit hash
- Your Omarchy / Hyprland / Quickshell versions, where relevant

### What to expect

- **Acknowledgement** within 72 hours (best effort — this is a
  community-maintained project).
- **Status updates** at least every 7 days until the report is resolved.
- **If accepted:** a fix is prepared and merged to `master`; the Marketplace
  picks it up on its next sync cycle. You will be credited in the release
  notes unless you prefer to stay anonymous.
- **If declined:** you will receive a clear explanation of why the report does
  not qualify as a vulnerability.

## Security Design & Scope

AuraBind is a local-only tool: it runs inside your own Quickshell instance
with your own user privileges and only reads/writes your own configuration
files. The following design decisions are intentional and define what counts
as a vulnerability:

### In scope

- **Arbitrary code execution regressions.** `LuaConfig.js` deliberately parses
  Lua binding sources as *plain text only*. Any regression that makes AuraBind
  load or execute untrusted Lua (e.g. reintroducing `read.lua`-style
  execution) is a critical vulnerability.
- **Writes outside the managed block.** AuraBind must only ever modify the
  fenced managed block in `~/.config/hypr/bindings.lua`. Any path that
  overwrites or destroys user content outside the fence, or writes to other
  files, is a vulnerability.
- **Command injection** through values AuraBind interpolates into shell
  commands (e.g. the scanner `Process` calls).
- **IPC abuse** beyond the intended `open` / `close` / `toggle` handlers.

### Out of scope

- Commands the user intentionally binds — AuraBind executes keybinding
  commands on the user's behalf *by design*; running a user-configured command
  is not a vulnerability.
- Vulnerabilities in upstream dependencies (Quickshell, Qt, Hyprland,
  Omarchy) — please report those to the respective projects.
- Issues requiring physical access or an already-compromised user session.
- Social engineering.

## Safe Harbor

Good-faith security research on your own installation is welcome. Please only
test against systems and accounts that you own or control.
