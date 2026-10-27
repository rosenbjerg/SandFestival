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
- `scripts/release.sh` runs the full pipeline: archive → exportArchive (Developer ID) → codesign verify → notarize + staple the app → DMG → notarize + staple the DMG → sha256. The DMG is a **second** `notarytool submit`: stapler looks the ticket up by the hash of the file it's stapling, so a DMG built around an already-notarized app still has no ticket of its own. Don't drop either submission. See `scripts/README.md` for env-var setup (`NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `NOTARY_KEY_PATH`).
- Version source of truth is `MARKETING_VERSION` in pbxproj — the **two app-target occurrences** (Debug + Release). The other four occurrences belong to a separate target pinned at `0.1.0` and are not bumped. The release script reads the first match directly. When bumping, change only the occurrences whose value matches that first match (same rule for the `CURRENT_PROJECT_VERSION` build number).
- `build/` is the artifact directory and is gitignored.

## Layout

- `SandFestival/Core/` — agent-neutral: `Project`, `Session`, `SessionManager`, `SessionStateMachine`, `AgentAdapter` protocol
- `SandFestival/Adapters/ClaudeCode/` — Claude Code adapter implementation
- `SandFestival/UI/` — SwiftUI views
- `Packages/SwiftTermMacOS/` — local wrapper that pins SwiftTerm with its default traits off (see Terminal lifetime)
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

## Process termination

- Sessions are spawned through `forkpty`, whose child `setsid`s, so the pid we hold (the nono wrapper) is its own group leader and every descendant inherits the group. `ProcessGroupTerminator` signals the **group**: nono outlives its child on purpose (it can sit on the PTY asking about denied paths), and a SIGKILLed wrapper leaves the agent orphaned under launchd with its cwd still open
- `target(leader:processGroup:)` degrades to `.single` when `getpgid` ≠ pid — that shape means a recycled pid or an unexpected spawn, and the group would belong to strangers. `liveMembers` must resolve the **same** target: `KERN_PROC_PGRP` for a `.single` pid matches nothing, and an empty sweep reads as "confirmed gone" — which is what `ProjectRemovalView` waits on before `git worktree remove`
- `descendants(ofAnyOf:)` is captured **before** the first signal. A descendant that `setsid`s is invisible to the group query; its parent chain is the only link, and that breaks when the parent dies. `TrackedProcess` carries the start time so a re-signal on a later sweep can't hit a recycled pid; tracked pids are signalled individually, never with `killpg`
- Zombies count as dead (no fds, no cwd) and a failed `sysctl` counts as alive. The failure modes are asymmetric: a false survivor is a refused removal the user can retry, a false empty deletes a worktree under a live agent
- `Session.stop()` sends SIGINT to the wrapper pid rather than calling SwiftTerm's `terminate()`, which closes the PTY and kills nono's post-stop prompt. `forceStopAndWait` guards on `LocalProcess.running`, not `state`, and afterward waits (up to ~1s) for our termination callback so `.stopped` and `onDidTerminate` land before the caller proceeds. SwiftTerm reaps the child itself on its own waiter thread, then drains output for up to 0.5s before calling `processTerminated` — `running` stays true through that drain
- `startProcess` is silently ignored until the previous process has fully wound down to idle; restarting from inside the termination callback is safe. Launch failures arrive via `processFailedToStart`, which `Session` turns into `lastError` + `.stopped` so the not-running overlay shows them
- Known gap: a process forked after the last snapshot that `setsid`s and whose parent dies before the next sweep is unreachable. Closing it needs `kqueue`/`EVFILT_PROC` with `NOTE_TRACK` armed before the spawn

## Continuation (resume previous conversation)

"Continue" launches the agent with resume flags instead of a fresh start. The flags come from `AgentAdapter.continuationArgs` (Claude Code: `["--continue"]`; default empty, so `Session.canContinue` is false and the UI hides Continue for agents without the concept). `Session.composeArgs(base:extraAgentArgs:)` appends them to the **agent** portion — after the `--` separator when there is one, else to the whole argv. The launch flavor is remembered in `Session.extraAgentArgs` and replayed on auto-restart, so restarting a continued session continues again rather than dropping to a fresh start. If there's no prior conversation, claude exits with its own error, which the startup-failure path surfaces in the not-running overlay.

## Canonical helpers — don't duplicate

- `SessionState.displayLabel` — localized one-word status name; use anywhere the UI describes session state
- `SessionManager.attentionSessions` — sessions in attention states, in sidebar order
- `SessionManager.focus(projectID:)` — select + activate + bring window front; route every "open this project" path through here
- `SessionManager.focusNextAttention()` / `focusPreviousAttention()` — cycle through `attentionSessions` from the current selection; the wrap-around rule is the pure static `nextAttentionProjectID(in:after:forward:)`

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

## Hook → event mapping (HookPayloadTranslator)

- Adding a case to `HookEvent` is enough to ship a new hook: an install missing any event reads `outdated` and is silently rewritten on adapter start, no consent sheet
- `StopFailure` (turn ended on an API error — rate limit, overloaded, auth) maps to `.idle`, same as `Stop`, because Claude Code fires it **instead of** `Stop`. Without it the session sat in `.working` forever and held keep-awake. Not `.errored`: that state means "no process" (`SessionState.isRunning` is false), so it would cover a live terminal with the not-running overlay and re-enable Start
- `Notification` is classified by `notification_type` (`permission_prompt`, `idle_prompt`). Any other type is ignored even if its message mentions "permission". The message-text heuristic runs only when the field is absent, for CLIs that predate it
- `PermissionRequest` is the immediate permission signal. `permission_prompt` arrives only after the prompt has sat ~6s, and never if it was answered sooner. Keep both: sandboxed network-request prompts fire `permission_prompt` but no `PermissionRequest`. Our hook must stay silent (exit 0, empty stdout). Any `decision` it printed would answer the prompt for the user
- `PostToolUse` / `PostToolUseFailure` for any tool emit `.toolCompleted`, which resolves only `.waitingForPermission` / `.blockedByAutoMode` back to `.working`: the approved tool ran. It's deliberately **not** `.working`. Tool calls from background subagents keep firing after the main turn's `Stop`, and `.working` would flip `.idle` back to busy with no `Stop` coming to end it. Known imprecision: a tool finishing concurrently (parallel call, background subagent) while a different call's prompt is up resolves that prompt early. `PermissionRequest` carries no `tool_use_id` to pair them by. `AskUserQuestion` keeps its own `.working` pair with `PreToolUse`, so other tools can't resolve `.waitingForIdle`
- No hook fires when the user interrupts with Esc — `Stop` explicitly doesn't run. The session stays `.working` until the next prompt; that's a known gap, not something a hook can close

## State machine

- `SessionStateMachine.next(from:event:)` is pure — test without a live process
- `Session.enteredCurrentStateAt` is stamped on transitions, **not** on same-state events. Sidebar reads it as "waiting Xm"
- Same-state events in `Session.apply(event:)` are no-ops

## Attention surfaces

- `AttentionNotifier` is the single sink turning session-state transitions into dock badge, dock bounce, and user notifications. It's wired once via `SessionManager.sessionStateObserver` — don't add a second observer for the same purpose
- `AttentionDecision.decide` is pure — no AppKit, no Focus center. Same split as `SessionStateMachine.next`: `decide` answers "what should fire?", the notifier owns the side effects. Test the policy without spinning up AppKit
- Dock badge always mirrors `attentionSessions.count`. Dock bounce fires only on transitions *into* an attention state, only when SandFestival isn't frontmost, and only when system Focus is off (Focus is treated as off when `INFocusStatusCenter` authorization hasn't been granted — bouncing is the conservative default)
- Notifications are opt-in (`AttentionPreferences`). One notification identifier **per project**, so a later transition updates the same banner instead of stacking; resolving the attention state withdraws it. Clicking a notification routes through `SessionManager.focus(projectID:)`
- The toolbar bell (`DetailPaneView.attentionMenu`) and the Go menu (⌘⇧] / ⌘⇧[) are read-only views over `attentionSessions` that route through `focus(projectID:)`; they don't observe transitions, so they need no observer slot. The bell stays visible when nothing needs attention so the toolbar doesn't reflow as sessions come and go
- `Session.hasUnseenOutput` is the sidebar's unread dot: set when a turn finishes (`AttentionEvent.finishedOutputting` — the one definition of "finished", shared with notifications) while the session isn't viewed (selected **and** app active, `SessionManager.isAppActive` injectable for tests); cleared by `markSelectedSessionSeen()` from ContentView's selection-change and `didBecomeActive` sites, and by any transition out of `.idle`. Lives in `SessionManager.trackUnseenOutput`, part of the `onStateChanged` fan-out — not a new observer slot

## Keep awake

- `KeepAwake` holds an idle-sleep assertion while **any** session is `.working`, gated on `KeepAwakePreferences` (on by default, plugged-in-only by default) and the live power source. Attention states don't hold it — nothing is progressing and the user isn't there
- The assertion is `ProcessInfo.beginActivity(.idleSystemSleepDisabled)` — verified to be `PreventUserIdleSystemSleep`, i.e. `caffeinate -i`. Display sleep and lid-close sleep are untouched. It's in-process on purpose: powerd drops it when we die, and `pmset -g assertions` attributes it to SandFestival. Don't replace it with a spawned `caffeinate` — an orphan keeps the Mac awake forever
- `KeepAwake.shouldHold` is pure; the instance owns the side effect and reconciles on any input change. Same split as `AttentionDecision.decide`. `SleepAssertion` and `PowerSourceMonitor` are protocols so tests count holds/releases and flip the charger without IOKit
- Power source: `IOPSCreateLimitedPowerNotification`, which posts only on AC↔battery transitions — not `IOPSNotificationCreateRunLoopSource`, which fires on every percent tick. The callback carries no payload, so `isPluggedIn` re-reads `IOPSGetProvidingPowerSourceType` each time. The source is scheduled on the main run loop and the callback uses `MainActor.assumeIsolated`; don't move it to another loop
- Driven by `SessionManager.anyWorkingDidChange`, which fires only when "is any session working?" flips — a **third** slot next to `sessionStateObserver` and `sessionDidFinishWork`, same rule: don't merge. It's recomputed from the transition fan-out and from `removeProject`, so removing a working project releases without waiting for its `.stopped`
- The hold is only as correct as the state: a live claude whose hooks stopped reaching us stays `.working` and keeps the Mac awake. That's a visible sidebar bug to fix at the source, not something to paper over with an assertion timeout — multi-hour runs are legitimate

## Worktree status

- `WorktreeStatusStore` is the single cache of per-project git state. Only projects with `worktreeInfo != nil` are sampled — each sample is a subprocess, and nothing else renders one. It owns no timer, and coalesces: one sample per project in flight at a time
- Sampling is driven by `SessionManager.sessionDidFinishWork`, which fires on every transition *out of* `.working` — that's when the tree just finished changing. It's a **separate slot** from `sessionStateObserver` (the attention pipeline's); don't merge them or make either one fan out
- `ContentView` owns the only timer: a 30s backstop for the **selected** project, idle while the app is inactive, plus `refreshAll` on `didBecomeActive`. `refreshAll` is also what reaps entries for deleted projects — removals never reach the store directly
- `GitWorktree.status` passes `--no-optional-locks`. Without it `git status` refreshes and rewrites `.git/index` on every poll, contending with the agent's own git commands inside that same worktree
- `GitStatus.parse` is pure and takes porcelain **v2** — v1 has no `# branch.ab`, so ahead/behind wouldn't be available at all. Test the grammar without a repo, same split as `SessionStateMachine.next`
- Ahead/behind is measured against `WorktreeInfo.baseBranch` when the worktree recorded one, else the upstream; `GitStatus.comparisonRef` says which. A branch created with `-b` has **no upstream**, so without the recorded base the numbers would read zero in the most common case. A base that has since been deleted falls back to the upstream rather than erroring
- Two different "base branch" memories, don't conflate them: `WorktreeInfo.baseBranch` is the fork point of *this* worktree (persisted per project, drives divergence), while `WorktreeBaseBranchStore` is only the duplicate sheet's remembered *default* per lineage. Existing-branch duplicates record `nil` — they were never forked from anything
- Sidebar worktree rows show the **live** branch from the sample, not `WorktreeInfo.branch` — that's a creation-time snapshot and goes stale the moment an agent switches branches. The git line replaces the path line, which for `.worktrees/<branch>` only restated the row's own name. The branch is dropped from the git line while it equals the project name (the default for worktree duplicates), and a line left with nothing to show is omitted

## Sidebar filter

- `SidebarFilter.visibleIDs` is pure and decides which rows a query keeps (name, `displayPath`, live worktree branch; a hit never orphans its parent or children). Test it without a view, same split as `SessionStateMachine.next`
- While a query is active the List's `.onMove` is `nil` and collapse state is ignored. `moveTopLevelBlocks` maps List offsets onto the *unfiltered* top-level order, so a drag on a filtered list would reorder the wrong rows — don't re-enable it under a filter without rewriting that mapping

## Claude Code login

"Log In to Claude Code…" opens a `Window` — not a sheet, because the flow leaves for the browser and comes back, so the main window has to stay usable — running `claude auth login` in its own terminal.

- `ClaudeCodeLogin.args` is `Project.defaultArgs`' wrapper **plus** `--allow-launch-services`. That flag is deliberately absent from the session default: nono's browser broker does not shim `open(1)` for a plain `nono run`, so without it the OAuth hop dies with `_LSOpenURLsWithCompletionHandler` error -54. It belongs to one short user-initiated process, not to every unattended agent. Don't move it back into `Project.defaultArgs`, and don't drop it here
- `--profile claude-code` is load-bearing on both counts: it carries the paired `allow_launch_services: true` profile gate (the CLI flag alone hits a closed gate on `default`) *and* the `$HOME/Library/Keychains` bypass plus `~/.claude.json` write the credential needs. On `default` the browser opens, the user signs in, and the credential then silently fails to persist — the worst failure shape, because it looks like it worked
- Launched from a fresh empty scratch directory under `NSTemporaryDirectory()`, removed on close. `--allow-cwd` grants read+write to the working directory, so an empty throwaway makes that grant worth nothing. Don't point it at the project path or `$HOME`
- `ClaudeCodeLoginController` is **not** a `Session`: no project, no hooks, and no `SAND_FESTIVAL_TOKEN` / `SAND_FESTIVAL_PROJECT_ID` in its environment, so nothing it spawns can bind to a project or reach the sidebar. It shares `Session.inheritedEnvironment()` only so both spawn paths resolve `nono` and `claude` off the same PATH
- Restarting sessions afterward is an offered button, not a default — the opposite of "Update Claude Code", where a new binary genuinely cannot reach a live process. Whether a running session picks up refreshed credentials on its own is unverified

## Terminal lifetime

SwiftTerm is pinned to an **exact version** (`exact:` in `Packages/SwiftTermMacOS/Package.swift`), so "Update to Latest Package Versions" can't move it. The app links that local wrapper package, not SwiftTerm directly, because only a manifest can depend on SwiftTerm with `traits: []`: its default `PortableGraphics` trait pulls in swift-png and, through it, `rarestype/h` — a PNG decoder for non-Apple platforms that macOS never compiles. With the trait off SwiftPM prunes both from the graph entirely, so they're never fetched and their manifests never run. Don't add SwiftTerm back as a direct package reference in the project: trait sets unify across the graph, and one default-traits reference brings both back. Terminal behavior here leans on version-specific upstream internals — see the viewport-pinning note below — so bumps are deliberate: raise the version, then re-test scrolling and selection by hand. Since 1.99 the mutable `Terminal` is not reachable from outside (`getTerminal()` is gone, `terminal` is internal) — go through the view's thread-safe surface: `changeScrollback`, `terminalDimensions`, `getBufferAsData`. A build-tool plugin (`SwiftTermBuildInfoPlugin`) ships with it, so a fresh checkout needs it trusted in Xcode once before `xcodebuild` will build.

Each `Session` owns its `LocalProcessTerminalView` for the whole app lifetime. The login window's terminal is the one exception — it belongs to the window and dies with it. `DetailPaneView` ZStacks every session's view and `TerminalPaneView` flips `NSView.isHidden` per selection (not `.opacity` — at alpha 0 the layer is still asked to paint dirty rects on every PTY update). **Never** swap views by selection, that destroys scrollback.

`SessionTerminalView` sets `allowMouseReporting = false`. SwiftTerm clears the text selection on every feed (`feedPrepare`) and every linefeed, both gated only on that flag — so without it, streaming output wiped any drag-selection before the user could copy. `feedPrepare` is `internal` and not overridable, so the flag is the only lever; turning it off is SwiftTerm's documented way to preserve selection during output. The trade is that mouse events stop forwarding to mouse-aware apps, which is fine here (the session is the Claude Code TUI, primary-buffer + linefeeds, never mouse mode). Don't re-enable it to gain app-side mouse support without restoring selection some other way.

Viewport pinning (scrolled-up sessions not getting yanked to the bottom by streaming output) is **SwiftTerm's job as of 1.14.0** — don't reintroduce a `dataReceived` override for it, for pinning or anything else: since 1.99 process output bypasses `dataReceived` entirely (it's parsed on a background thread by a private adapter), so an override compiles and is never called. The **New output** pill observes via `setProcessOutputHandler`, which runs on the parse thread after each batch is applied; the handler bumps a pending-batch counter and hops to main, where `outputApplied()` compares the public `scrollPosition` against the last observed one and, when the viewport is scrolled up and the position dropped, reports "output below viewport". It never sets scroll state. `scrolled(source:position:)` also fires from SwiftTerm's main-thread frame drain when output moved the scroll, in arbitrary order relative to our hop — so it updates the baseline only while the pending counter is zero (a user scroll); otherwise it would swallow the drop. Two details are load-bearing: the position compare (not "bytes arrived") is what keeps Claude Code's in-place spinner redraws from raising the pill, and the flag is forwarded only on change — `scrolled(source:position:)` fires per scrolled line while pinned at the bottom, and the SwiftUI listener re-renders on every call it gets. `terminal.userScrolling` is internal to SwiftTerm, so `canScroll && scrollPosition < 1` is the "scrolled up" test. `AppleTerminalView.updateUserScrollingState` sets `terminal.userScrolling` from every `scrollTo`/`scroll(toPosition:)` — which is what `Terminal.scroll` has always gated on — and the wheel path reaches it via `scrollUp`/`scrollDown`. That also makes the scrollback-full case exact: the trim branch decrements `yDisp` per trimmed line to hold the text still, where our old override could only clamp and so drifted toward the bottom. Typing resets it, because `TerminalView.send(data:)` calls `ensureCaretIsVisible`. Through 1.13 the view layer set only its own same-named property (scrollbar-knob drags, never read), which is why the workaround existed at all; we carried it until the 1.18.0 bump only because the pin before that was an untagged May 2026 `main` revision predating the fix. If pinning regresses after a bump, check that wiring before re-adding anything here.

## Clipboard

Agents never read the clipboard themselves. SandFestival reads it on the user's paste and hands over only what was pasted.

- **Terminal side, always on.** SwiftTerm answers OSC 52 clipboard *queries* by default, which gives any process on the PTY the clipboard text from outside its sandbox. `SessionTerminalView` sets `terminalDelegate` to a `TerminalClipboardGuard` that returns `nil` from `clipboardRead` and empty `kittyClipboardCapabilities` (SwiftTerm 1.99's OSC 5522, which reads and writes the clipboard by MIME type; with no capabilities SwiftTerm refuses every 5522 request before asking the delegate), and forwards everything else to the view. `clipboardRead`/`clipboardCopy` are `public`, not `open`, so a stand-in delegate is the only lever. On every SwiftTerm bump, diff `TerminalViewDelegate` against the guard: a requirement the guard doesn't forward falls back to the protocol default without any error. OSC 52 *writes* still go through
- **Sandbox side, `SessionManager.blocksAgentClipboard` (on by default).** For nono commands, `Session.launch` gets its wrapper argv from `sandboxedArgsProvider`. `AgentSandboxProfile.sandboxing` writes a profile file whose `extends` is the project's own `--profile` value, then swaps the file's path in as the `--profile` (or adds `--profile` after `run` when there was none). That's the same single path as env injection, and it isn't stored in `Project.args`, so existing projects pick it up. Don't go back to `--extends`, for two reasons verified on nono 0.80. First, both `--extends` and the JSON `extends` field take only a profile *name*, never a path, so passing our file fails at startup. Second, nono honors `unsafe_macos_seatbelt_rules` only when the *selected* profile is a user or path-loaded one. Under a package profile like `claude-code`, a deny rule inherited from an `--extends` base is dropped with nothing more than a log warning, and the agent starts unblocked. `--profile` can't be given twice, so the base has to be extended by name from inside our file. A project whose `--profile` is itself a file path can't be extended, so its launch fails with an explanation The profile always grants read on `ImagePaste.directory`. When blocking is on, it also adds `(deny mach-lookup (global-name "com.apple.pasteboard.1"))`, which wins over nono's blanket `(allow mach-lookup)`. If the profile can't be written, the launch fails: failing closed beats silently starting an unblocked agent. The login window doesn't get it, because it isn't an agent
- **Image paste.** For adapters with `acceptsPastedImagePaths` (Claude Code), Cmd+V with only an image, or Ctrl+V with any image, writes a PNG to `ImagePaste.directory` and bracket-pastes its path; Claude Code attaches a pasted image path like a dropped file. Cmd+V with text behaves as before. Ctrl+V is caught by an `NSEvent` local key-down monitor, installed while the view is in a window, because neither `keyDown` nor `performKeyEquivalent` is `open` (as of SwiftTerm 1.99). The kitty keyboard protocol changes Ctrl+V's bytes so they can't be matched in `send`. `ImagePaste.shouldPasteImage` is pure. Files are purged on launch and quit, not per paste, because nothing tells us when the agent has read them
- Finder file copies carry an icon TIFF, so `hasImage` is false whenever a file URL is present

## Dictation

Same principle as the clipboard: SandFestival holds the microphone and hands the agent only the finished text.

- Speech runs on-device through `SpeechAnalyzer` (`SpeechAnalyzerEngine`): `SpeechTranscriber` when `isAvailable`, else `DictationTranscriber`, in the system locale. The model is fetched through `AssetInventory` on first use, with progress shown in the overlay
- The microphone needs `ENABLE_RESOURCE_ACCESS_AUDIO_INPUT = YES`, which emits `com.apple.security.device.audio-input`. Under the hardened runtime, a build without it gets no microphone, and Debug builds can hide that until the notarized release
- `SpeechEngine` is a protocol so `DictationControllerTests` can script results without audio. The tap block is installed from a `static` func so it isn't actor-isolated: Core Audio calls it on its real-time thread
- `DictationController` pastes through `pasteText` (bracketed paste) plus a trailing space, and never sends Return. It only pastes while the target is `.idle` or `.working`. In any other state the text is held in the overlay with Copy and Paste Anyway, because pasted text could answer a permission prompt
- Held text blocks every session's mic (`canToggle`) until it's pasted, copied or discarded, because starting a new dictation would silently drop it. It stops blocking once its target session is gone, since the target is held weakly. A dictation whose target disappears mid-listen is discarded on the next audio event
- Listening also ends when audio stops arriving for `audioStallTimeout`, which is wall-clock. A route change, such as headphones connecting, stops `AVAudioEngine`, and the audio-time endpointer then never gets another tick
- Don't give the overlay keyboard shortcuts. The terminal keeps focus, so Return would be stolen from the prompt, and Esc there is Claude's interrupt
- Transcript clean-up runs between finish and paste through `TranscriptRefiner`, with `TranscriptRefinement` holding the shared prompt and the plausibility gate. Any failure, timeout, Skip, or a result whose word count suggests the model answered rather than cleaned falls back to the raw transcript. The text is never lost to a refiner
- Core stays provider-agnostic: a model provider's refiner is offered only through `AgentAdapter.transcriptRefinement` (name, description, refiner; nil by default). `DictationPreferences.cleanup` is `.automatic` by default, and `TranscriptCleanup.source` (pure) picks on-device when available, else the agent's model. Explicit choices never substitute the other model. Don't name a provider or model in Core or UI. Its strings live under the adapter's `adapter.<id>.` keys
- On-device clean-up needs Apple Intelligence turned on; `OnDeviceTranscriptRefiner.unavailableReason` is what Settings shows when it's off
- `ClaudeTranscriptRefiner` runs `claude -p --model haiku` under nono, using `Project.defaultArgs`' wrapper (the `claude-code` profile, the same as sessions and login) plus `--silent`, because the output is parsed from stdout. It runs from an empty temporary directory, so `--allow-cwd` grants nothing, and it's a tool-less one-shot: `--tools ""`, `--strict-mcp-config`, hooks off via `--settings`. Don't use `--bare`, which never reads OAuth, so subscription logins fail. `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1` is load-bearing: without it the user's CLAUDE.md is sent along and steers the rewrite. The prompt goes in argv, not stdin, because writing to a child that already exited raises SIGPIPE in the app
- `SpeechDetector` is not a usable silence signal (verified on 26.5). Alone it traps with "use with a transcriber module", and alongside a transcriber it reported no results. End-of-speech has to come from the transcript
- `DictationEndpointer` is pure and works in **audio** time (frames fed), never wall-clock, same split as `SessionStateMachine.next`. Speech is "the words changed" (`DictationTranscript.words` ignores punctuation and case, because the model adds a trailing `.` about a second after speech ends) or "a final result with words ended here" (`range.end` marks the true end of speech). Results arrive in batches about 1 s apart, so the stop lands between the timeout and the timeout plus 1 s after the last word, and the slider's 1.5 s floor leaves headroom for slow batches. The endpointer is `@ObservationIgnored`: it changes per audio buffer, about 10 times a second

## Persistence

- Projects: `~/Library/Application Support/SandFestival/projects.json` (Codable + atomic write)
- Settings: `~/.claude/settings.json` (POSIX tempfile + fsync + rename)
- Terminal font size: UserDefaults `terminal.fontSize`, registered via `UserDefaults.register(defaults:)` (don't use a 0-fallback)
- Terminal font family: UserDefaults `terminal.fontFamily`, empty meaning the system monospaced font. `TerminalFont.resolve` falls back to it whenever the family doesn't resolve, and the picker only offers `isFixedPitch` families — a proportional terminal font shreds SwiftTerm's cell grid
- Interface text size: UserDefaults `interface.textSize` via `InterfacePreferences` (`InterfaceTextSize` raw value; absent or unknown means `.medium`)
- Worktree base branch: UserDefaults `duplicate.baseBranch` via `WorktreeBaseBranchStore` — a `lineage-id → branch` map, written only on a successful new-branch duplicate. Keyed by `ProjectDuplicateDraft.resolvedParentProjectID` (the top-level ancestor), so a parent and all its worktree children share one memory; keying by path would fragment it because duplicating a child passes *that child's* worktree path as the source repo. An absent entry means "Current HEAD", so picking the sentinel forgets rather than stores

## Interface text size

- macOS SwiftUI **ignores** `dynamicTypeSize` (verified: an override changes nothing), so app text scales only because we do it. Every user-facing `Text`/`Label` uses `.interfaceFont(.caption)` rather than `.font(.caption)`; `InterfaceFont.resolve` reads the `interfaceTextScale` environment value and rebuilds the style off `NSFont.preferredFont(forTextStyle:)` at the scaled point size, weight included
- At `.medium` the modifier hands back the plain style font and the root override is `nil`, so the default install renders byte-identical to before the setting existed. Keep that property — it's what makes the whole pass safe
- `.interfaceTextScale(_:)` is applied per **scene** (main window, login window, Settings); sheets inherit it from their presenter. A new scene that forgets it silently renders at 1.0. It also sets the root `.font`, which is what scales unstyled text and control labels
- Literal `.font(.system(size:))` glyphs (`StatusDot`, the empty-state icon) are deliberately left out — they sit in fixed frames and would clip. The menu bar and window chrome belong to macOS and don't scale either

## Localization

- All visible strings go through `Localizable.xcstrings` even though we ship English only
- Keys follow `xxx.yyy.zzz` (e.g. `sidebar.row.label.permission`)
- For format substitution: `String(format: String(localized: "k"), arg)` — `String(localized: defaultValue:)` does **not** substitute %@

## Concurrency

- Default actor isolation is `MainActor` (pbxproj `SWIFT_DEFAULT_ACTOR_ISOLATION`). Default args calling MainActor initializers warn — accept `nil` and resolve inside the init body
- Types whose code runs off the main actor (subprocess helpers called from detached tasks or `nonisolated` statics, `HookListener` and everything its queue calls) are declared `nonisolated` at the type level, not member by member. The compiler reports only the first isolation hop, so after marking a type check the build again for the next layer down
- The test target deliberately has **no** default isolation. Suites over main-actor types are `@MainActor` per suite; suites that block on subprocesses (`GitWorktreeTests`, `ProcessGroupTerminatorTests`) stay nonisolated, and the types they assert on are `nonisolated` in the app. Don't set `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on the test target: the blocking suites then hold the main actor and the run slows ~8×. Tests that wait on main-actor work should await it (e.g. `persistDebounceTask`), not sleep a fixed interval
- `HookListener` is `@unchecked Sendable`; NWListener callbacks run on its serial queue and hop to MainActor via `Task { @MainActor in … }`
