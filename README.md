<p align="center">
  <img src="assets/hero.gif" alt="ClawdHub — keyboard gesture to switch between Claude Code agents" width="700">
</p>

<h3 align="center">Cmd+Tab for your Claude Code agents.</h3>

<p align="center">
  One keyboard gesture to see, switch, and jump between every Claude Code session on your Mac.
</p>

<p align="center">
  <a href="#installation">Install</a> &nbsp;&bull;&nbsp;
  <a href="#how-it-works">How It Works</a> &nbsp;&bull;&nbsp;
  <a href="#features">Features</a> &nbsp;&bull;&nbsp;
  <a href="#supported-terminals">Terminals</a>
</p>

---

## The Problem

You fire up three Claude Code agents across different terminals. Hand off tasks. Go grab coffee.

Come back — one agent has been stuck waiting for permission for **12 minutes**. You didn't know. Now you're Alt-Tabbing through windows trying to find it, losing context, breaking flow.

This is the multi-agent tax: the more agents you run, the more time you spend managing windows instead of shipping code.

## The Fix

**Hold ⌥⌘.** Every agent appears in a floating panel — name, status, what it's working on. **Tap ⌘** to cycle. **Release ⌥** to jump straight to that terminal.

Under a second. Your hands never leave the keyboard.

> Think Cmd+Tab, but for your AI fleet. The gesture becomes muscle memory after a few uses — just like app switching.

ClawdHub also watches in the background. When an agent gets stuck waiting for permission, you get a **macOS notification** immediately — no need to keep checking.

## Installation

### Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15+ (full IDE, not just Command Line Tools — the build uses `xcodebuild`)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed

### One-liner

```bash
git clone https://github.com/ManmeetSethi/clawdhub.git && cd clawdhub && bash scripts/build.sh
```

Builds, installs to `/Applications`, and launches. The onboarding wizard handles the rest.

### Or open in Xcode

```bash
git clone https://github.com/ManmeetSethi/clawdhub.git
open clawdhub/ClawdHub/ClawdHub.xcodeproj
```

Hit ⌘R to build and run.

### Uninstalling

```bash
rm -rf /Applications/ClawdHub.app ~/.clawdhub
defaults delete com.clawdhub.app
```

To also remove hooks, delete ClawdHub entries from `~/.claude/settings.json` under `hooks`.

## How It Works

### The Gesture

| Action | What Happens |
|--------|-------------|
| Hold **⌥ + ⌘** | Panel appears — all your agents at a glance |
| Tap **⌘** (keep holding ⌥) | Cycle through agents one by one |
| Release **⌥** | Jump to the selected agent's terminal |

Three moves, under a second.

**Persistent mode:** Hold ⌥⌘ for more than a second, then release both. The panel stays pinned. Press **1–9** to jump by number, or **Esc** to dismiss.

### Behind the Scenes

ClawdHub installs lightweight shell hooks into Claude Code's [hook system](https://docs.anthropic.com/en/docs/claude-code/hooks). These write session state to `~/.clawdhub/sessions.json` whenever an agent starts, finishes, or needs input. ClawdHub watches this file and keeps the panel in sync — no polling, no API calls.

| Event | What Gets Tracked |
|-------|-------------------|
| You send a message | Session created as **Running** |
| Claude uses a tool | Current tool + file captured |
| Claude needs permission | Status → **Waiting** + notification |
| Claude finishes | Status → **Done** |
| Session ends | Removed from panel |

## Features

- **Real-time status** — Running, Waiting, Done — with live activity (current tool, file, command)
- **Instant notifications** — macOS alerts the moment an agent needs attention
- **Menubar indicator** — Color-coded dot: green (all clear), orange pulsing (needs attention)
- **Multi-terminal** — Detects and switches to the correct window across 9 terminals
- **Zero config** — No API keys, no server, no accounts. Fully local.

## Supported Terminals

| Terminal | Focus Method |
|----------|-------------|
| Terminal.app | AppleScript (TTY window matching) |
| iTerm2 | AppleScript (TTY session matching) |
| Cursor | CLI (`cursor -r`) + activation |
| VS Code | CLI (`code -r`) + activation |
| Ghostty | Bundle ID activation |
| WezTerm | Bundle ID activation |
| Alacritty | Bundle ID activation |
| Kitty | Bundle ID activation |
| Warp | Bundle ID activation |

## Notes

- **New sessions only.** Claude Code reads hooks at startup — restart running sessions after installing ClawdHub.
- **Hooks auto-refresh.** ClawdHub redeploys hooks on every launch.
- **TCC reset after rebuild.** If accessibility breaks: `tccutil reset Accessibility com.clawdhub.app`

## License

All rights reserved.
