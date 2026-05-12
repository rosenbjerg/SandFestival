<p align="center">
  <img src="Icon.png" alt="Sand Festival" width="160" />
</p>

<h1 align="center">Sand Festival</h1>

<p align="center">macOS dashboard for many parallel Claude Code sessions.</p>

---

Sand Festival replaces "many Terminal tabs each running `claude` in a different
project" with a single window: a sidebar listing every project and a real
embedded terminal for the selected one. Sessions live for as long as the app
does; when something needs your attention, the dock badge and a notification
tell you which project, and you jump in with one click.

## Install

```sh
brew install --cask rosenbjerg/sandfestival/sandfestival
```

The long form auto-taps the formula repo — no separate `brew tap` step needed.

### Requirements

- macOS 26 (Tahoe) or later
- [Claude Code](https://docs.claude.com/en/docs/claude-code/) on your `PATH`
- [`nono`](https://github.com/always-further/nono) on your `PATH` — the
  capability-based sandbox Sand Festival uses by default to run Claude Code
  with OS-enforced isolation:

  ```sh
  brew install nono
  ```

By default each project spawns:

```sh
nono run --allow-cwd --profile claude-code --allow-launch-services -- claude --enable-auto-mode
```

You can change the `command` and `args` per project in the project settings,
so running Claude Code directly (`claude`) or under a different wrapper is a
one-field edit. If you do that, `nono` is no longer required.

### Update / uninstall

```sh
brew upgrade --cask sandfestival
brew uninstall --cask sandfestival            # leaves user data in place
brew uninstall --zap --cask sandfestival      # also removes projects, prefs, caches
```

## What it does

- **One session per project, all running in parallel.** Each gets its own
  embedded terminal with persistent scrollback. Switching projects is instant
  because nothing is torn down.
- **Hook-based status detection.** Sand Festival installs lightweight hook
  entries in `~/.claude/settings.json` so it knows exactly when a session
  starts, finishes a turn, or is waiting on you — no PTY scraping, no
  guessing.
- **Dock-badge attention indicator.** A glance at the dock tells you how
  many sessions need input; tap the notification to jump straight to that
  project.
- **Drag-to-reorder sidebar.** Or let the most recently active project float
  to the top automatically.
- **Token-scoped local listener.** The hook receiver binds to
  `127.0.0.1:51789` and validates a per-install bearer token stored in the
  macOS Keychain. The token is never written to `settings.json`.

## How it works

An agent-neutral `Core` (session manager, state machine, project store) plus
a `ClaudeCode` adapter that owns the hook listener and the merge of hook
entries into `~/.claude/settings.json`. Adding another agent would mean
writing a sibling adapter, not touching `Core`.

## Building from source

Open `SandFestival.xcodeproj` in Xcode and run the `SandFestival` scheme.
Requires Xcode 26 or later (matches the macOS 26 deployment target).

For a reproducible signed/notarized build, see
[`scripts/README.md`](scripts/README.md) and `scripts/release.sh`.

## Project status

Pre-1.0. Working day-to-day for the author but expect rough edges and
occasional breaking changes between releases.

## License

MIT — see [LICENSE](LICENSE).
