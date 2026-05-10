# Sand Festival — Project Brief

## What we're building

Sand Festival is a native macOS app that hosts multiple long-running coding-agent
sessions, one per project, and gives the user a single dashboard to see what
each session is doing. Today the only supported agent is Claude Code running
inside the `nono` sandbox wrapper, but the app's internals are designed so
additional agents can be added later without touching the core.

The user's current workflow is "many Terminal.app tabs, each running
`nono claude` in a different project directory." Sand Festival replaces that
with one window: a sidebar listing every project, a main pane embedding a
real terminal for the selected project, and a menu bar item that surfaces
which sessions need attention. Sessions are owned by the app — when the app
quits, all sessions die. There is no detach/reattach.

Primary user goal: **glance at the menu bar, know if any session needs me, jump
to it in one click.** Auto-mode usage is the common case, where Claude Code
runs unattended for long stretches and only occasionally needs human input.

## Hard architectural decisions already made

These are not open questions. Don't relitigate them unless you discover a
concrete blocker.

- **Native macOS app, SwiftUI.** Targeting current macOS (whatever's modern
  when you build). No Catalyst, no cross-platform.
- **Embedded terminal via SwiftTerm.** Each project gets its own
  `LocalProcessTerminalView`. All sessions stay alive in memory; only the
  selected one is visible. Switching projects must preserve scrollback.
  - Repo: https://github.com/migueldeicaza/SwiftTerm
- **App owns all processes.** Spawn on demand (or auto-start), SIGTERM on app
  quit with a short grace period before SIGKILL. No tmux, no detach.
- **Agent-agnostic core, Claude Code as the first concrete adapter.** See
  the `AgentAdapter` section below. The MVP only ships the Claude Code
  adapter, but the boundary must be clean from day one.
- **Sandbox wrapper is just a configurable command, not an abstraction.**
  Each project stores `command` (default `"nono"`) and `args`
  (default `["claude"]`). If a user wants to use a different wrapper or run
  the agent unwrapped, they edit those fields. No `Sandbox` protocol.
- **Hooks-driven state detection for Claude Code, not PTY scraping.**
  Claude Code emits structured JSON hook events at lifecycle points; we
  receive them over a local HTTP listener. PTY scraping may exist later as
  a fallback for sessions that somehow don't have hooks installed, but it's
  not part of the MVP.
- **No notifications, no event persistence, no global hotkey in v1.** The
  menu bar is the entire ambient signal. Live state only — when the app
  quits, history is gone.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                       Sand Festival (SwiftUI)                    │
│                                                                  │
│  ┌──────────────┐    ┌──────────────────────────────────────┐    │
│  │   Sidebar    │    │           Main Pane                  │    │
│  │  ● proj A 🟢│    │   SwiftTerm.LocalProcessTerminalView  │    │
│  │  ● proj B 🟠│    │   (one per project, hidden when not   │    │
│  │  ● proj C 🔵│    │    selected)                          │    │
│  │  ● proj D 🔴│    │                                       │    │
│  └──────────────┘    └──────────────────────────────────────┘    │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐      │
│  │  Core (agent-neutral)                                  │      │
│  │  • SessionManager: spawns processes, owns PTYs         │      │
│  │  • Per-session state machine consuming AgentEvent      │      │
│  │  • Project persistence                                 │      │
│  │  • Sidebar / menu bar UI                               │      │
│  └────────────────────────────────────────────────────────┘      │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐      │
│  │  ClaudeCodeAdapter                                     │      │
│  │  • Owns NWListener on 127.0.0.1:<port>                 │      │
│  │  • Owns ~/.claude/settings.json merge/uninstall        │      │
│  │  • Owns bearer token                                   │      │
│  │  • Translates Claude Code hook events → AgentEvent     │      │
│  └────────────────────────────────────────────────────────┘      │
└──────────────────────────────────────────────────────────────────┘
                            ▲
                            │ HTTP POST per hook
              ┌─────────────┴──────────────────────┐
              │   nono claude (per project)        │
              │   spawned by app, PTY owned by     │
              │   the SwiftTerm view               │
              │   hooks fire from global config    │
              └────────────────────────────────────┘
```

## The `AgentAdapter` boundary

The core knows nothing about Claude Code specifically. It talks to whatever
agent runs through this protocol (sketch — adjust naming/shape as you build):

```swift
protocol AgentAdapter: AnyObject {
    static var id: String { get }              // e.g. "claude-code"
    static var displayName: String { get }     // e.g. "Claude Code"
    var defaultCommand: String { get }         // e.g. "claude"
    var defaultArgs: [String] { get }          // adapter's recommended flags

    /// Called once at app startup. Adapter does whatever setup it needs
    /// (install hooks, start listeners, watch logs, etc.) and reports
    /// state changes via the sink.
    func start(eventSink: AgentEventSink) async throws
    func stop() async

    /// Called when a session is about to be spawned. Adapter can inject env
    /// vars or otherwise prepare the launch context.
    func prepareSpawn(project: Project) -> SpawnEnvironment

    /// Called when a session has been spawned. Adapter can use this to
    /// register the session for routing future events.
    func didSpawnSession(_ session: SessionHandle)
    func willTerminateSession(_ session: SessionHandle)
}

protocol AgentEventSink: AnyObject {
    func report(matching: SessionMatcher, event: AgentEvent)
}

enum SessionMatcher {
    case sessionID(String)        // adapter's own session ID
    case workingDirectory(URL)    // route by cwd
    case projectID(UUID)          // app's project ID, if adapter knows it
    case pid(pid_t)
}

enum AgentEvent {
    case started
    case working
    case heartbeat
    case idle
    case waitingForPermission
    case waitingForInput
    case blockedByAutoMode
    case errored(reason: String)
    case stopped
}
```

The state machine consumes `AgentEvent` and is unaware of Claude Code. For
the MVP, ship `ClaudeCodeAdapter` and a `MockAdapter` (used in tests and
SwiftUI previews to drive the UI without a real agent).

Do **not** build adapter discovery, plugin loading, or a registration
mechanism. Adapters are compiled in. The MVP UI shows no agent picker — every
new project is a Claude Code project. Add an `agentID: String` field to the
`Project` struct anyway, defaulted to `"claude-code"`, so the schema doesn't
need migration when a second adapter lands.

## State machine (per session)

```
states: starting | idle | working | waiting_permission | waiting_idle
        | blocked_auto_mode | errored | stopped

starting     ─(.started)─────────────────────────> idle
idle         ─(.working)─────────────────────────> working
working      ─(.heartbeat)───────────────────────> working
working      ─(.idle)────────────────────────────> idle
working      ─(.waitingForPermission)────────────> waiting_permission
working      ─(.waitingForInput)─────────────────> waiting_idle
working      ─(.blockedByAutoMode)───────────────> blocked_auto_mode
working      ─(.errored)─────────────────────────> errored
waiting_*    ─(.working)─────────────────────────> working
*            ─(.stopped | process exit)──────────> stopped
```

Attention states (for menu bar / sidebar coloring):
`waiting_permission`, `waiting_idle`, `blocked_auto_mode`, `errored`.

Every state transition timestamps `lastActivityAt` on the session for the
sidebar's relative-time display.

## Claude Code adapter — concrete details

### Hook events we consume

The adapter installs hooks for these events (see
https://code.claude.com/docs/en/hooks for full schemas):

| Hook event             | Maps to `AgentEvent`                |
|------------------------|-------------------------------------|
| `SessionStart`         | `.started` (also binds session_id → project) |
| `UserPromptSubmit`     | `.working`                          |
| `PostToolBatch`        | `.heartbeat`                        |
| `Notification` matcher `permission_prompt`  | `.waitingForPermission` |
| `Notification` matcher `idle_prompt`        | `.waitingForInput`      |
| `PermissionDenied`     | `.blockedByAutoMode`                |
| `Stop`                 | `.idle`                             |
| `StopFailure`          | `.errored(reason: <error type>)`    |
| `SessionEnd`           | `.stopped`                          |

Adapter only consumes events; never blocks. All hook handlers must return
2xx with empty body so Claude Code never thinks the dashboard is gating
anything. Use `PostToolUse`/`PreToolUse` *only* if `PostToolBatch` heartbeats
turn out to be insufficient — `PostToolBatch` is preferred because it fires
once per agentic-loop iteration rather than per parallel tool call.

### Hook installation

On adapter `start()`:

1. Generate a bearer token if one isn't persisted yet (UUID, store in macOS
   Keychain under a service name like `app.sandfestival.claudecode.token`).
2. Pick a port (start from a sensible high default like 51789; if taken,
   probe upward). Persist the chosen port to the app's support directory
   so we can reuse it across launches.
3. Bind `NWListener` to `127.0.0.1` on that port. Use Apple's
   `Network.framework` (no SwiftNIO/Vapor — overkill).
4. Read `~/.claude/settings.json` (create if missing). Merge in our hook
   entries. Each hook handler:
   ```json
   {
     "type": "http",
     "url": "http://127.0.0.1:<port>/event?source=sand-festival",
     "headers": { "Authorization": "Bearer $SAND_FESTIVAL_TOKEN" },
     "allowedEnvVars": ["SAND_FESTIVAL_TOKEN"]
   }
   ```
   The `?source=sand-festival` query param is our sentinel for finding our
   own entries on uninstall — do **not** rely on undocumented JSON fields.
5. Set `SAND_FESTIVAL_TOKEN` in the environment of every spawned session
   (via `prepareSpawn`). The token reaches Claude Code through the spawn
   env, which Claude Code then interpolates into the hook header.
6. Atomic write of settings.json: write to a sibling tempfile in the same
   directory, `fsync`, then `rename(2)` over the original. A crash during
   this step must not destroy the user's existing settings.

On adapter `stop()` (and on a "Disconnect" UI action): walk the hooks
config, remove every hook handler whose URL contains
`?source=sand-festival`, atomic-write back. Idempotent.

On `start()`, before installing, also remove any pre-existing
`source=sand-festival` entries (e.g. from a previous run with a different
port). This makes start idempotent.

### First-run UX

On first launch, before installing hooks, the app shows a sheet:

> Sand Festival needs to add HTTP hook entries to your global Claude Code
> settings (`~/.claude/settings.json`) so it can detect when sessions
> need attention.
>
> [View changes]   [Skip]   [Install]

"View changes" pops a diff. "Skip" runs the app with reduced functionality
(state machine never leaves `idle`/`working`/`stopped` — derive what we can
from process exit and PTY activity). "Install" merges the hooks and
proceeds. The sheet only appears if our entries aren't already present.

### Routing events to projects

Hook payloads include `session_id`, `cwd`, and `permission_mode`. They do
**not** include the spawning process's PID.

Routing strategy:

1. App spawns a session, records `(projectID, workingDirectory)` keyed by
   the spawn-time pending state.
2. First event we see for a new session is `SessionStart`, which carries
   `session_id` and `cwd`. Match `cwd` against pending spawns to bind
   `session_id → projectID`. Save this binding.
3. All subsequent events for that `session_id` route to the same project,
   regardless of `cwd` (handles `cd` mid-session, `CwdChanged` events,
   nested project paths).
4. Events whose `session_id` we don't recognize and whose `cwd` doesn't
   match any registered project are silently dropped — they're sessions
   from outside Sand Festival (the user running `claude` in some other
   terminal entirely, since our hooks are installed globally).
5. On `SessionEnd`, drop the binding.

### Adapter-specific metadata for the UI

The adapter exposes per-session metadata the UI can show:
- `permission_mode` (default / plan / accept-edits / auto / dont-ask /
  bypass) — small badge in the sidebar
- `effort` level if present — small badge

Define an `AgentMetadata` struct with optional fields the core UI knows how
to render generically; don't make the core UI special-case Claude Code.

## Project model

```swift
struct Project: Codable, Identifiable {
    let id: UUID
    var name: String
    var path: URL                 // working directory
    var agentID: String           // "claude-code" for now
    var command: String           // e.g. "nono"
    var args: [String]            // e.g. ["claude", "--dangerously-skip-permissions"]
    var env: [String: String]     // merged onto inherited env at spawn time
    var autoStart: Bool
}
```

Persist to `~/Library/Application Support/SandFestival/projects.json`.
Atomic write. JSON, pretty-printed for hand-editability.

Project editor sheet (add/edit) needs:
- Name (text)
- Path (folder picker)
- Command (text, default from adapter)
- Args (one-per-line text editor or token field)
- Env (key/value table with add/remove)
- Auto-start toggle

For the MVP, no agent picker in the UI — every project is implicitly
Claude Code. Just persist `agentID` so we don't need a migration later.

## UI

### Window layout

- `NavigationSplitView` (or equivalent): sidebar on the left, detail on the
  right.
- Sidebar rows: status dot (color matches state), name, path subtitle in
  smaller secondary text, relative time of last activity, badge if in
  attention state and not currently selected.
- Status colors:
  - `idle` — gray
  - `working` — blue
  - `waiting_permission`, `waiting_idle` — orange
  - `blocked_auto_mode`, `errored` — red
  - `stopped` — gray, dimmed
  - `starting` — gray, animated
- Sidebar footer: "+ Add Project" button.
- Detail pane: the `LocalProcessTerminalView` for the selected project,
  fills the whole pane. Toolbar above with Restart / Kill / Open in Finder /
  Edit Project actions. If no project selected, show empty state.
- A small "not running" overlay on the terminal pane when the session has
  exited, with a Start button.

### Menu bar item

- `NSStatusItem` with a custom icon.
- Idle (no attention sessions): neutral icon.
- Any session in an attention state: icon switches to attention color,
  shows badge count of attention sessions.
- Click drops down a menu: list of sessions in attention states (state +
  project name), each clickable to focus the app on that project. Below
  that: "Show Sand Festival" (focus app), "Quit Sand Festival".
- Update menu bar on every state transition. Use template image so it
  respects light/dark mode.

### Sheets / dialogs

- Project add/edit sheet (see Project model)
- First-run hook installation sheet (see Hook installation)
- Confirmation on quit if any sessions are in `working` (optional polish,
  skip if it's annoying)

## Build order

Do these in this order. Each step's deliverable should be runnable.

### Step 1 — SwiftTerm spike

A throwaway window, hardcoded path, hardcoded `nono claude`, one
`LocalProcessTerminalView`. Verify:

- Claude Code's TUI renders correctly (alternate screen buffer, spinner,
  prompts, syntax highlighting).
- Resize works without artifacts.
- Input lag is acceptable.
- App quit cleanly kills the child (no orphan `claude` processes after
  quitting — check with `ps -ef | grep claude`).
- `nono` propagates signals correctly.

If any of this is broken, **stop and report back before continuing**. The
rest of the architecture assumes SwiftTerm works.

### Step 2 — Multi-session shell

- `Project` model and persistence.
- `SessionManager` that tracks live sessions.
- Sidebar + main pane layout.
- Multiple sessions alive concurrently, switching preserves scrollback.
- Add Project / Edit Project / Remove Project / Start / Stop / Restart.
- All status displays default to "running" or "stopped"; no real state
  detection yet.

### Step 3 — `AgentAdapter` protocol + `MockAdapter`

- Define the protocol per the sketch above.
- `MockAdapter` that emits canned `AgentEvent`s on a timer for testing.
- Wire the state machine so MockAdapter events drive sidebar colors.
- This proves the boundary is clean before you commit to it with the real
  adapter.

### Step 4 — `ClaudeCodeAdapter`

- `NWListener` on 127.0.0.1.
- Bearer token in keychain.
- Settings.json read/merge/atomic-write/uninstall.
- First-run install sheet.
- Hook event → `AgentEvent` translation.
- Session routing (`session_id` binding).

### Step 5 — Menu bar

- `NSStatusItem` with state-driven icon and badge.
- Drop-down menu listing attention sessions.
- Click-to-focus.

### Step 6 — Polish

- Process exit detection wires through to state machine.
- Restart button works mid-session.
- Edit-project takes effect on next start.
- "Open in Finder" / "Reveal" actions.
- Empty states, error states, settings.json failure recovery.

## Things to be careful about

- **Settings.json corruption.** Always atomic-write. If the file is
  malformed JSON when we read it, do not overwrite — surface an error to
  the user and let them fix it.
- **Token leak.** The bearer token must never be logged. The HTTP listener
  must reject any request without a matching `Authorization: Bearer <token>`
  header with 401. Bind only to `127.0.0.1`, never `0.0.0.0`.
- **PTY orphan processes.** Test app-quit cleanup with several active
  sessions. SwiftTerm should propagate SIGHUP on view teardown but verify.
- **`nono` quirks.** Confirm `nono claude` runs cleanly under SwiftTerm
  before the spike. If `nono` doesn't `exec` its child, signal propagation
  may be sketchy.
- **Hook event flood.** `PostToolBatch` can fire frequently. The state
  machine should debounce `working → heartbeat` so the sidebar isn't
  re-rendering 20 times per second. Sub-second granularity is fine.
- **Reentrant settings.json.** If the user manually edits settings.json
  while the app is running, our next read should pick up their changes;
  our writes should not clobber additions they made unless they're
  conflicting hook entries. Always re-read before writing.

## Out of scope for v1

Don't build any of these. They're listed only so you know they're
intentional omissions, not oversights:

- Detach/reattach (no tmux integration)
- Persistent event/transcript history
- Notifications (system / banner / sound)
- Global hotkey
- Token / cost surfacing
- Plugin / dylib adapter loading
- Adapter picker UI (every project is Claude Code)
- Multiple windows
- Remote sessions / SSH

## Open questions for the implementer

These weren't fully decided in design and are fine to make a judgment call
on. Document the call you made.

- Whether to use `LocalProcessTerminalView` directly or own the PTY read
  loop with `TerminalView` — start with the former; switch only if you hit
  rendering or perf issues during the spike.
- Whether to use `NSStatusItem` directly or `MenuBarExtra` (SwiftUI). Either
  is fine; pick whichever lets you update the icon on state changes most
  cleanly.
- File watching for settings.json edits while the app is running — nice to
  have, not required.
- Where to draw the line between adapter setup errors that block app launch
  vs. errors that surface as a banner. Default to the latter; the app
  should remain usable even if the Claude Code adapter fails to start.
