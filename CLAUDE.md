# Sand Festival

macOS dashboard hosting long-running Claude Code sessions. This file captures
conventions that have emerged in code.

## Build & test

- `~/.claude/scripts/xcode-proxy-client --platform macos build SandFestival`
- `~/.claude/scripts/xcode-proxy-client --platform macos test SandFestival [SuiteName]` — Swift Testing only; no UI tests in v1
- `~/.claude/scripts/check-localizations.ts` — run after touching any user-facing string
- App Sandbox is intentionally **off** (the target spawns nono/claude from PATH, binds 127.0.0.1:51789, edits ~/.claude/settings.json). Don't re-enable.

## Release

- Distribution is **Developer ID + notarization, direct download via Homebrew cask** — not the Mac App Store. The sandbox-off architecture rules out MAS.
- `scripts/release.sh` runs the full pipeline: archive → exportArchive (Developer ID) → codesign verify → `notarytool submit --wait` → staple → DMG → sha256. See `scripts/README.md` for env-var setup (`NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `NOTARY_KEY_PATH`).
- Version source of truth is `MARKETING_VERSION` in pbxproj (six occurrences, all kept in sync). The release script reads it directly.
- `build/` is the artifact directory and is gitignored.

## Layout

- `SandFestival/Core/` — agent-neutral: `Project`, `Session`, `SessionManager`, `SessionStateMachine`, `AgentAdapter` protocol
- `SandFestival/Adapters/ClaudeCode/` — Claude Code adapter implementation
- `SandFestival/UI/` — SwiftUI views
- `SandFestival/` is a `PBXFileSystemSynchronizedRootGroup` — new files auto-included; no pbxproj edits needed

## Hook entries (~/.claude/settings.json)

- `type: "command"` (curl with `--max-time 1 … >/dev/null 2>&1 || true`), **not** `type: "http"` — keeps Claude Code from showing "ECONNREFUSED" when SandFestival isn't running
- Identified by the `?source=sand-festival` sentinel in either the URL field (legacy) or the command string. `HookEntryFactory.isOurEntry` recognizes both
- `SettingsJSONManager.detectInstallState` → `notInstalled` / `outdated` / `current`. `outdated` is silently rewritten on adapter start; the consent sheet only appears for `notInstalled`
- Atomic write: tempfile + fsync + rename(2) (POSIX C). Never overwrite a malformed settings.json — surface the error
- Port is **fixed** at `HookListener.defaultPort = 51789` in production. Don't reintroduce probing — stable hook entries beat fallback availability. The instance `port` is configurable via init for test isolation only

## Auth flow

1. UUID token in Keychain (`KeychainTokenStore`, service `app.sandfestival.claudecode.token`). Adapter accepts `any TokenStore` — tests pass an in-memory stub
2. `ClaudeCodeAdapter.prepareSpawn` injects `SAND_FESTIVAL_TOKEN=<uuid>` into the spawn env
3. Hook command's shell expands `$SAND_FESTIVAL_TOKEN` into `Authorization: Bearer …` at fire time
4. `HookListener` validates against the same Keychain token; 401s otherwise

The token never appears in settings.json. **Don't** add code that logs it.

## Spawn env injection — every path or none

`Session.spawnEnvProvider` is a closure `SessionManager.makeSession` wires once. Every launch path — toolbar/overlay Start and Continue, auto-restart-after-stop, `SessionManager.startSession` — funnels through the private `Session.launch(extraAgentArgs:)` (which `start()` and `startContinuing()` both call). Removing or bypassing the closure means sessions launch without `SAND_FESTIVAL_TOKEN` and every hook 401s silently.

PATH precedence in `Session.composeEnvironment(inherited:projectEnv:extra:)`: project/adapter override → inherited parent PATH → `CommandResolver.defaultPathString`. Don't revert to clobbering — that silently breaks mise/asdf/non-default installs.

## Continuation (resume previous conversation)

"Continue" launches the agent with resume flags instead of a fresh start. The flags come from `AgentAdapter.continuationArgs` (Claude Code: `["--continue"]`; default empty, so `Session.canContinue` is false and the UI hides Continue for agents without the concept). `Session.composeArgs(base:extraAgentArgs:)` appends them to the **agent** portion — after the `--` separator when there is one, else to the whole argv. The launch flavor is remembered in `Session.extraAgentArgs` and replayed on auto-restart, so restarting a continued session continues again rather than dropping to a fresh start. If there's no prior conversation, claude exits with its own error, which the startup-failure path surfaces in the not-running overlay.

## Canonical helpers — don't duplicate

- `SessionState.displayLabel` — localized one-word status name; use anywhere the UI describes session state
- `SessionManager.attentionSessions` — sessions in attention states, in sidebar order
- `SessionManager.focus(projectID:)` — select + activate + bring window front; route every "open this project" path through here

## Session routing (ClaudeCodeAdapter)

- Routing is keyed by **project id, not cwd**. `prepareSpawn` injects `SAND_FESTIVAL_PROJECT_ID=<project.id>` into the spawn env (alongside the token) and registers the id as a one-shot pending spawn plus a longer-lived live entry. The hook command forwards the id as the `X-Sand-Festival-Project` header (`HookEntryFactory.projectHeaderName`); the shell expands the env var at fire time, just like the bearer token. This is what lets two projects share a cwd — a "Duplicate…" without a worktree points the child at the parent's path — without their sessions colliding. Don't reintroduce cwd-based binding
- First `SessionStart` for that project id consumes the pending entry and binds `session_id → projectID` (`SessionBindingStore`)
- Later `SessionStart`s for a still-live project id rebind, so `/resume` and `/clear` (which mint a new session_id over the same live process) attach the new session_id to the same project
- `SessionBindingStore.bindOnSessionStart(sessionID:projectID:)` returns a `BindOutcome` (`.freshSpawn` vs `.rebound`), not a bare id. A `.rebound` SessionStart is `/resume` or `/clear` over a live process, so the adapter translates its `.started` into `.sessionRestarted` — same state-machine transitions, but `Session.apply` also clears the stale OSC-set `terminalTitle` so a previous conversation's summary doesn't outlive it
- The live entry is cleared only by `unbindAll(projectID:)`, which is called from `adapter.willTerminateSession`. `Session.onDidTerminate` fires this on natural process exit, so a stray claude run for the same project after the process dies doesn't attach to the dead session
- `SessionEnd` is **not** a `.stopped` signal — process death comes from the OS-level termination callback in `Session.handleProcessTerminated`. `SessionEnd` fires for `/resume` and `/clear` over a live process, so translating it would push a running session into the "not running" overlay
- Subsequent non-SessionStart events route by `session_id` only — `cd` mid-session can't detach a session
- Unknown session_ids are silently dropped (claude run from elsewhere)
- Adapters resolve to a `Project.ID` before reporting — `AgentEventSink.report(projectID:event:)` takes the resolved id directly. Per-agent mapping logic (cwd, session_id, etc.) stays inside the adapter

## State machine

- `SessionStateMachine.next(from:event:)` is pure — test without a live process
- `Session.enteredCurrentStateAt` is stamped on transitions, **not** on same-state events. Sidebar reads it as "waiting Xm"
- Same-state events in `Session.apply(event:)` are no-ops

## Attention surfaces

- `AttentionNotifier` is the single sink turning session-state transitions into dock badge, dock bounce, and user notifications. It's wired once via `SessionManager.sessionStateObserver` — don't add a second observer for the same purpose
- `AttentionDecision.decide` is pure — no AppKit, no Focus center. Same split as `SessionStateMachine.next`: `decide` answers "what should fire?", the notifier owns the side effects. Test the policy without spinning up AppKit
- Dock badge always mirrors `attentionSessions.count`. Dock bounce fires only on transitions *into* an attention state, only when SandFestival isn't frontmost, and only when system Focus is off (Focus is treated as off when `INFocusStatusCenter` authorization hasn't been granted — bouncing is the conservative default)
- Notifications are opt-in (`AttentionPreferences`). One notification identifier **per project**, so a later transition updates the same banner instead of stacking; resolving the attention state withdraws it. Clicking a notification routes through `SessionManager.focus(projectID:)`

## Terminal lifetime

Each `Session` owns its `LocalProcessTerminalView` for the whole app lifetime. `DetailPaneView` ZStacks every session's view and `TerminalPaneView` flips `NSView.isHidden` per selection (not `.opacity` — at alpha 0 the layer is still asked to paint dirty rects on every PTY update). **Never** swap views by selection, that destroys scrollback.

`SessionTerminalView` sets `allowMouseReporting = false`. SwiftTerm clears the text selection on every feed (`feedPrepare`) and every linefeed, both gated only on that flag — so without it, streaming output wiped any drag-selection before the user could copy. `feedPrepare` is `internal` and not overridable, so the flag is the only lever; turning it off is SwiftTerm's documented way to preserve selection during output. The trade is that mouse events stop forwarding to mouse-aware apps, which is fine here (the session is the Claude Code TUI, primary-buffer + linefeeds, never mouse mode). Don't re-enable it to gain app-side mouse support without restoring selection some other way.

`SessionTerminalView.dataReceived` pins the viewport when the user has scrolled up, so streaming output doesn't yank it to the bottom. SwiftTerm's core supports this (`Terminal.scroll` only resets `yDisp` when its `userScrolling` flag is false) but the macOS view layer never sets that flag from the scroll position, and the flag is `internal` to the package — so we save the row before `super.dataReceived` and restore it after (skipping when already at the bottom or in the alternate buffer). PTY data is delivered on `DispatchQueue.main` (LocalProcess's default queue), so the `scrollTo` is main-thread-safe. Exact until the scrollback buffer fills; after that the pinned content drifts toward the bottom because SwiftTerm doesn't expose the trim count. Re-test scrolling after any SwiftTerm bump — the override depends on `dataReceived` staying `open` and the scroll APIs keeping their semantics (and becomes a harmless no-op if upstream ever wires `userScrolling` itself).

## Persistence

- Projects: `~/Library/Application Support/SandFestival/projects.json` (Codable + atomic write)
- Settings: `~/.claude/settings.json` (POSIX tempfile + fsync + rename)
- Terminal font size: UserDefaults `terminal.fontSize`, registered via `UserDefaults.register(defaults:)` (don't use a 0-fallback)

## Localization

- All visible strings go through `Localizable.xcstrings` even though we ship English only
- Keys follow `xxx.yyy.zzz` (e.g. `sidebar.row.label.permission`)
- For format substitution: `String(format: String(localized: "k"), arg)` — `String(localized: defaultValue:)` does **not** substitute %@

## Concurrency

- Default actor isolation is `MainActor` (pbxproj `SWIFT_DEFAULT_ACTOR_ISOLATION`). Default args calling MainActor initializers warn — accept `nil` and resolve inside the init body
- `HookListener` is `@unchecked Sendable`; NWListener callbacks run on its serial queue and hop to MainActor via `Task { @MainActor in … }`
