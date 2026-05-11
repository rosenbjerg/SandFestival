# Sand Festival

macOS dashboard hosting long-running Claude Code sessions. **SPEC.md** is the
authoritative architecture doc; this file captures conventions that have
emerged in code.

## Build & test

- `~/.claude/scripts/xcode-proxy-client --platform macos build SandFestival`
- `~/.claude/scripts/xcode-proxy-client --platform macos test SandFestival [SuiteName]` — Swift Testing only; no UI tests in v1
- `~/.claude/scripts/check-localizations.ts` — run after touching any user-facing string
- App Sandbox is intentionally **off** (the target spawns nono/claude from PATH, binds 127.0.0.1:51789, edits ~/.claude/settings.json). Don't re-enable.

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

`Session.spawnEnvProvider` is a closure `SessionManager.makeSession` wires once. Toolbar Start, the not-running overlay's Start, auto-restart-after-stop, and `SessionManager.startSession` all hit `Session.start()`. Removing or bypassing the closure means sessions launch without `SAND_FESTIVAL_TOKEN` and every hook 401s silently.

PATH precedence in `Session.composeEnvironment(inherited:projectEnv:extra:)`: project/adapter override → inherited parent PATH → `CommandResolver.defaultPathString`. Don't revert to clobbering — that silently breaks mise/asdf/non-default installs.

## Canonical helpers — don't duplicate

- `SessionState.displayLabel` — localized one-word status name; use anywhere the UI describes session state
- `SessionManager.attentionSessions` — sessions in attention states, in sidebar order
- `SessionManager.focus(projectID:)` — select + activate + bring window front; route every "open this project" path through here
- `AgentMetadata.permissionMode` flows hook payload → `Session.metadata` → `SidebarView` capsule. Extend `AgentMetadata` + the badge site when surfacing new adapter metadata

## Session routing (ClaudeCodeAdapter)

- `prepareSpawn` records `(projectID, cwd)` as a pending spawn
- First `SessionStart` hook for that cwd binds `session_id → projectID` (`SessionBindingStore`)
- Subsequent events route by `session_id` only — `cd` mid-session can't detach a session
- Unknown session_ids are silently dropped (claude run from elsewhere)
- Adapters emit only `.projectID(uuid)` matchers to the sink — the sink doesn't resolve session_ids

## State machine

- `SessionStateMachine.next(from:event:)` is pure — test without a live process
- `Session.enteredCurrentStateAt` is stamped on transitions, **not** on heartbeats. Sidebar reads it as "waiting Xm"
- Same-state events in `Session.apply(event:)` are no-ops

## Terminal lifetime

Each `Session` owns its `LocalProcessTerminalView` for the whole app lifetime. `DetailPaneView` ZStacks every session's view and toggles `.opacity` per selection — **never** swap views by selection, that destroys scrollback.

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
