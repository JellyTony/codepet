# Contributing to CodePet

Thanks for your interest in improving CodePet! This is a small, focused native
macOS app — contributions of all sizes are welcome.

## Getting set up

Requirements: **macOS 13+** and the Xcode command-line tools (`xcode-select --install`).

```bash
git clone https://github.com/JellyTony/codepet.git
cd codepet
bash build.sh        # compiles build/CodePet.app
bash install.sh      # builds + wires Claude Code hooks + launches the pet
```

`build.sh` compiles all of `Sources/CodePet/*.swift` into a self-contained,
ad-hoc-signed `CodePet.app`. There is no Xcode project — just `swiftc`.

To iterate: edit sources → `bash build.sh` → relaunch with
`open build/CodePet.app`.

## Project layout

```
Sources/CodePet/      The native app (AppKit overlay + SwiftUI/Canvas renderer)
  Action.swift          PetAction + SpriteContract — the animation contract
  Behavior.swift        activity → PetAction + motion choreography
  SpriteAtlas.swift     loads Petdex/Codex spritesheets (.webp/.png), lazily
  VectorPet.swift       procedural built-in pets
  PetView.swift         corner pet + sprite/vector stages
  PetWindow.swift       borderless overlay + mouse interaction
  SessionsPanel.swift   the white task-card stack (incl. inline quick-reply)
  Session.swift         per-session model + attention priority
  ProjectResolver.swift cwd → project name (git root aware)
  StateStore.swift      hook server, file watching, aggregate state
  HookServer.swift      loopback HTTP server for Claude Code hooks
  HookProcessor.swift   hook event → state + transcript parsing
  TerminalFocus.swift   bring a session's terminal forward
  TerminalInput.swift   send a quick reply into a session's terminal
  PetCatalog.swift      discover pets (~/.petdex, ~/.codepet, ~/.codex, built-ins)
  PetdexGallery.swift   in-app Petdex browser/installer
tools/                  Node hooks + helper scripts
skills/                 Claude Code skills (/codepet-hatch, /codepet-petdex)
```

## How it talks to Claude Code

CodePet reacts via Claude Code **hooks** (see the README's "How it talks to
Claude Code"). High-frequency events are POSTed to a loopback HTTP server;
`SessionStart` uses a command hook to capture terminal identity. `install.sh`
wires these idempotently into `~/.claude/settings.json`.

## Guidelines

- **Keep it native and dependency-free.** No SwiftPM/CocoaPods/npm runtime deps.
- **Match the surrounding style** — comment density, naming, and the minimal
  Codex-pets aesthetic for UI.
- **Don't commit build output** (`build/` is gitignored).
- For behavior changes, describe how you verified them (the project favors
  building and observing the real app over mocks).
- Open an issue first for larger changes so we can align on direction.

## Submitting a PR

1. Fork and branch from `main`.
2. `bash build.sh` must succeed with no new warnings.
3. Describe what changed and how you tested it.

By contributing you agree your contributions are licensed under the project's
[MIT License](LICENSE).
