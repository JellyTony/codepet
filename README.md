# 🐾 CodePet

[![build](https://github.com/JellyTony/codepet/actions/workflows/ci.yml/badge.svg)](https://github.com/JellyTony/codepet/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![platform: macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-AppKit%20%2B%20SwiftUI-orange?logo=swift)](https://swift.org)

A native macOS desktop pet for **Claude Code** — a faithful reimagining of
[Codex pets](https://developers.openai.com/codex/app/settings). A little animated
creature lives in the corner of your screen and reflects what your agents are
doing, at a glance, while you work in other apps.

> 🇨🇳 [中文说明文档](README.zh-CN.md)

<p align="center">
  <img src="docs/hero.png" width="440" alt="CodePet — a session card stack floating above the corner pet">
</p>

> Same idea, same overlay, same card-stack layout as Codex pets — built for
> Claude Code, and **multi-session aware**.

## Highlights

- 🐾 **Live state at a glance** — the corner creature mirrors *working / needs-you / ready / failed / idle*.
- 🗂️ **Multi-session aware** — one task card per Claude Code session, with the real task title, the live action, and progress.
- 💬 **Quick-reply from a card** — type straight back into a session's terminal without leaving what you're doing.
- 🎨 **Petdex gallery** — install animated pets in two clicks, no terminal, no config.
- 🌏 **Localized** — English / 简体中文 / 繁體中文 / 日本語, switches live.
- 📦 **Native & dependency-free** — one `swiftc` build, a ~1 MB app, no Electron, no packages.

## What it does

CodePet floats above every Space, always on top, in the corner of your choice.
It maps Claude Code's live activity to an animated creature plus a short progress
prompt — exactly like the Codex overlay:

| State | The pet… | Triggered by |
|-------|----------|--------------|
| **working…** (running) | runs, walks left/right, waves, jumps, a gear spins | `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `SubagentStop` |
| **needs you** (waiting) | stops, stares, twitches, a `?` bubble bobs | `Notification` |
| **ready for review** | sits, smiles, holds a code package, sparkles | `Stop` |
| **something failed** | shakes, frowns, sweat-drop, a `!` bubble | tool errors / error notifications |
| **idle** | breathes, blinks, drifts `z z z`, waves hello | `SessionStart` |

<p align="center">
  <img src="docs/states.png" width="760" alt="the pet's five states: working, needs you, ready, failed, idle">
</p>

Under the hood every renderer speaks in named **`PetAction`s** — the abstraction
that lets CodePet play any pet (built-in, Codex, or Petdex) with no per-pet code.
The action set *is* the Petdex / Codex 9-row spritesheet contract, in order:
`idle, walkRight, walkLeft, wave, jump, fail, wait, walk, review` (see
[`Action.swift`](Sources/CodePet/Action.swift)).

## Sessions dashboard — every session, at a glance

Run Claude Code in five terminals and the corner pet won't get confused: CodePet
tracks **each session independently** and shows them as a stack of white task
cards floating directly above the pet (the Codex pet layout):

- **Status light** per card — a spinning ring while *working*, a pulsing amber dot
  when it *needs you*, a green check when *ready for review*, a red triangle on
  *failure*.
- **A real task title** (the first thing you asked — slash commands become
  `command: <goal>`), the **project** it runs in, a live **summary** of what
  Claude is doing right now (its latest message, read from the session
  transcript), and **progress** metrics (`Edit · 42 actions · 3m`).
- **Click a card** to expand it: full task text, the recent-tool trail, the
  working directory, plus *Reveal in Finder* and *Copy session id*.
- The **corner pet reflects the aggregate** — it shows whichever session most
  wants your attention (needs-you ▸ failed ▸ ready ▸ working ▸ idle), and the
  menu-bar **🐾 badge counts** how many sessions need you.

It's **interactive**: the pet's eyes follow your cursor and it perks up on hover,
**click it** to collapse/expand the stack, and **drag it anywhere** — the cards
follow and the position is remembered.

## Petdex gallery — install a pet from the menu, no terminal

[Petdex](https://petdex.crafter.run) is a gallery of animated pets that ship in
the same spritesheet contract CodePet speaks. **Installing one is two clicks** —
no terminal, no login, no config:

> **🐾 → Pet → Install from Petdex → pick a pet.**

CodePet fetches the gallery, downloads the pet's spritesheet, writes it into
`~/.petdex/pets/<slug>/`, and switches to it immediately. That's it.

Prefer the command line? The same pet installs with the official CLI (or its
wrapper), and CodePet picks it up automatically:

```bash
npx -y petdex install boba          # or: node tools/petdex.js boba
```

…or ask Claude **`/codepet-petdex boba`**. Any of these lands the pet under the
**Petdex gallery** group in the 🐾 → Pet menu, with nothing to refresh or restart.

## Codex-format compatibility

Petdex pets are exactly the **Codex pet format**, so the same loader handles both.
Drop a `pet.json` + spritesheet (`.webp` or `.png`; atlas `1536×1872`, 8 columns ×
9 rows, `192×208` cells) into any of these and it renders verbatim:

```
~/.petdex/pets/<slug>/{pet.json, spritesheet.webp}   # petdex install …
~/.codex/pets/<name>/{pet.json, spritesheet.webp}    # your existing Codex pets
~/.codepet/pets/<name>/{pet.json, spritesheet.webp}  # hand-dropped pets
```

The same pet installed to both `~/.petdex` and `~/.codex` is de-duped to one menu
entry. Built-in **forms** (Blob, Stacky, Byte, Glitch) need no assets at all —
they're drawn and animated procedurally, so every state is fully animated out of
the box.

## Install

### Download (no build needed)

Grab `CodePet-macos.zip` from the [latest release](https://github.com/JellyTony/codepet/releases/latest),
unzip, and double-click **`Install CodePet.command`** (if macOS blocks it,
right-click → Open → Open). It copies CodePet to `/Applications`, clears the
download quarantine, wires the Claude Code hooks, and launches the pet.
Requires macOS 13+ and [Node.js](https://nodejs.org) for the hooks.

### Build from source

```bash
git clone https://github.com/JellyTony/codepet.git
cd codepet
bash install.sh
```

This builds `CodePet.app`, wires the Claude Code hooks into
`~/.claude/settings.json` (idempotent, existing settings preserved), installs the
`/codepet-hatch` and `/codepet-petdex` skills, and launches the pet. Start any
Claude Code session and the pet reacts automatically.

Requires macOS 13+ and the Xcode command-line toolchain (`swiftc`).

## Use

- **Click the pet** to show/hide the session cards; **drag it** to reposition;
  **drag the ⤢ handle** (bottom-right, on hover) to resize it.
- **Click a card** to bring that session's terminal to the front (auto-detects
  iTerm2/Terminal/VS Code/Warp/Ghostty/…); **right-click** for Reveal in Finder,
  Copy session id, and the recent-tool trail.
- **Quick-reply from a card** — hover a card (or a session that needs you) and a
  reply box appears; type and press return to send your message straight into
  that session's terminal, no switching. (First use prompts for macOS Automation
  permission to control your terminal.)
- **Menu bar 🐾** — show sessions, switch forms, choose a corner/snap back, pick a
  **language** (English / 简体中文 / 繁體中文 / 日本語 / System), preview states.
  The Pet submenu re-scans installed pets every time it opens. The badge shows
  how many sessions need you.
- **Install a Petdex pet** with no terminal: **🐾 → Pet → Install from Petdex**,
  then pick one — CodePet downloads it and switches to it on the spot. (CLI
  alternative: `node tools/petdex.js boba` / `npx -y petdex install boba`, or ask
  Claude **`/codepet-petdex boba`**.)
- **Hatch a new pet** (the CodePet take on Codex's `hatch-pet` skill):

  ```bash
  node tools/hatch.js "Pixel" --form cat --color "#A385EB"
  ```

  …or just ask Claude: **`/codepet-hatch`**. Then menu-bar 🐾 → Pet.

## Uninstall

```bash
bash uninstall.sh    # removes hooks + skill, stops the app; keeps your pets
```

## Layout

```
Sources/CodePet/      Swift app (AppKit overlay panel + SwiftUI/Canvas renderer)
  main.swift          NSPanel overlay, menu-bar control, panel wiring
  PetWindow.swift     corner panel + interactive container (hover/gaze/drag/click)
  SessionsPanel.swift the white task-card stack (one card per active session)
  Session.swift       per-session model + attention priority
  ProjectResolver.swift cwd → project name (git repo root aware)
  StateStore.swift    runs the hook server, watches ~/.codepet/, computes aggregate
  HookServer.swift    loopback HTTP server — receives Claude Code's HTTP hooks
  HookProcessor.swift event → state inference + transcript parsing (in-app)
  TerminalFocus.swift bring a session's terminal forward on card click
  TerminalInput.swift send a quick reply into a session's terminal
  Action.swift        PetAction + SpriteContract — the Petdex/Codex animation contract
  Behavior.swift      activity → PetAction + motion (walk/wave/jump/twitch/fail)
  SpriteAtlas.swift    loads Petdex/Codex spritesheets per SpriteContract (.webp/.png)
  VectorPet.swift     procedural animated pet (eyes track the cursor)
  PetCatalog.swift    discovers pets from ~/.petdex, ~/.codepet, ~/.codex, built-ins
  PetdexGallery.swift in-app Petdex browser/installer (menu → Install from Petdex)
tools/
  codepet-hook.js     SessionStart command hook → captures terminal identity
  install-hooks.js    safe, idempotent settings.json merge (HTTP + command hooks)
  petdex.js           install a pet from the Petdex gallery
  hatch.js            create a new pet
skills/hatch-pet/     /codepet-hatch skill for Claude Code
skills/petdex/        /codepet-petdex skill — install a Petdex pet
build.sh install.sh uninstall.sh
```

## How it talks to Claude Code

CodePet reacts to Claude Code through its **hooks** — the documented, stable
integration contract. To keep the cost off Claude's critical path, the two hook
transports are split by frequency:

- **High-frequency events** (`UserPromptSubmit`, `PreToolUse`, `PostToolUse`,
  `Notification`, `Stop`, `SubagentStop`) are **HTTP hooks**: Claude Code POSTs
  the event JSON straight to a tiny **loopback HTTP server** the app runs on
  `127.0.0.1` (`HookServer.swift`). No process spawn per tool call. The app
  (`HookProcessor.swift`) infers the state and parses the transcript for a task
  title + live summary — all in-app, off Claude's path. If the app isn't
  running the POST fails fast (non-blocking) and is simply ignored.
- **`SessionStart`** is a one-shot **command hook** (`codepet-hook.js`) so it can
  capture the terminal identity (`TERM_PROGRAM` / `ITERM_SESSION_ID`) from its
  process env — that's what lets "click a card → focus that terminal" work.

The loopback server is bound to `127.0.0.1` only (not reachable off-machine) and
guarded by a shared token (`~/.codepet/hook.json`) written into the hook headers
at install time. Both transports are wired idempotently into
`~/.claude/settings.json` by `install-hooks.js`.

## State files

The app writes one record **per session** under `~/.codepet/sessions/<id>.json`
(plus a legacy `~/.codepet/state.json` of the latest event for back-compat),
watches the directory (FS events + 1 s poll), and prunes sessions untouched for
6 h. Cards in the stack show only **live, active** sessions (working / needs-you /
ready / failed); idle and stale sessions are hidden to keep it focused.

```json
{
  "session_id": "…",
  "state": "running",
  "detail": "Edit",
  "cwd": "/path/to/project",
  "title": "the task you asked for",
  "summary": "what Claude just said it's doing",
  "prompt": "your most recent message",
  "last_tool": "Edit",
  "recent_tools": ["Read", "Grep", "Edit"],
  "tool_count": 42,
  "term_program": "iTerm.app",
  "started_at": 1782490700.0,
  "updated_at": 1782490847.2
}
```

`state` ∈ `idle | running | waiting | ready | failed`.

## Contributing

Issues and PRs are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for build
setup, the project layout, and guidelines. Please also read the
[Code of Conduct](CODE_OF_CONDUCT.md).

CodePet stays deliberately small and dependency-free: one `swiftc` build, no
SwiftPM/Xcode project, no runtime packages.

## License

[MIT](LICENSE) © 2026 JellyTony.

CodePet is an independent project and is not affiliated with Anthropic or OpenAI.
"Claude Code" and "Codex" are trademarks of their respective owners.
