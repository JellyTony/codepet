---
name: codepet-hatch
description: Hatch a new CodePet — create a custom animated desktop pet for Claude Code. Use when the user asks to make/create/hatch a pet, customize their CodePet, or wants a new creature companion. Picks a form and identity colour from the user's concept and installs it.
---

# Hatch a CodePet

CodePet is a native macOS desktop companion that lives in the bottom-right
corner and reflects Claude Code's state (working / needs you / ready for review
/ something failed). This skill creates a **new pet** the user can switch to.

## How to hatch

1. Ask the user (only if not already clear) for:
   - a **name** for the pet (e.g. "Pixel", "Sir Barksalot"),
   - an optional **form**: `blob`, `cat`, `robot`, or `ghost`,
   - an optional **colour** as a hex like `#A385EB`.
   If they describe a concept ("a calm purple owl"), map it yourself:
   choose the closest form and a fitting hex colour.

2. Run the hatch tool (path is the CodePet repo this skill ships with):

   ```bash
   node <CODEPET_REPO>/tools/hatch.js "<Name>" --form <form> --color "<#hex>" --desc "<short description>"
   ```

   Omit `--form`/`--color` to let the tool derive stable values from the name.

3. Tell the user it's hatched, and that they should open the menu-bar **🐾 →
   Pet → Refresh Pets**, then select their new pet. If CodePet isn't running,
   suggest `open <CODEPET_REPO>/build/CodePet.app`.

## Notes
- The pet is written to `~/.codepet/pets/<slug>/pet.json` and animates through
  all of CodePet's states using the built-in vector engine — no image assets
  required.
- Real Codex spritesheet pets (`pet.json` + `spritesheet.webp`) dropped into
  `~/.codepet/pets/<name>/` or `~/.codex/pets/<name>/` are also picked up
  automatically and rendered verbatim.
