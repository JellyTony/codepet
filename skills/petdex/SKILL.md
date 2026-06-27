---
name: codepet-petdex
description: Install a pet from the Petdex gallery (petdex.crafter.run) into CodePet. Use when the user wants a specific animated pet from Petdex, asks to "install the <name> pet", browse the Petdex gallery, or add a real spritesheet creature to their CodePet. Downloads the pet and makes it selectable from the menu bar.
---

# Install a Petdex pet

[Petdex](https://petdex.crafter.run) is a gallery of animated spritesheet pets
(Codex / CodePet contract: 8×9 frame grid). CodePet loads them **verbatim** —
same `pet.json` + spritesheet format — so any Petdex pet works with zero config.

## The easiest way (no terminal)

CodePet has a built-in installer. Tell the user:

> **🐾 → Pet → Install from Petdex**, then click a pet.

CodePet downloads it and switches to it instantly — nothing else to do. Use this
unless the user specifically wants a pet not shown in that list.

## CLI install (for a specific slug)

1. Find the **slug**. It's the lowercase name under each pet on
   https://petdex.crafter.run (e.g. `boba`, `02`, `aurelion-sol`). If the user
   names a pet but not a slug, the slug is usually the name lowercased with
   spaces as `-`.

2. Run the installer (path is the CodePet repo this skill ships with):

   ```bash
   node <CODEPET_REPO>/tools/petdex.js <slug>
   ```

   This wraps `npx -y petdex install <slug>`, which downloads the pet into
   `~/.petdex/pets/<slug>/` and `~/.codex/pets/<slug>/`. No login or config.

3. Tell the user to open the menu-bar **🐾 → Pet** and pick the new pet — it's
   listed under **Petdex gallery**. No refresh or restart is needed; CodePet
   rediscovers installed pets every time the menu opens. If CodePet isn't
   running, suggest `open <CODEPET_REPO>/build/CodePet.app`.

## Notes
- Petdex pets are real spritesheets and animate through every state
  (idle / working / needs-you / ready / failed) via CodePet's `PetAction`
  contract — the same 9 animation rows Petdex sheets ship with.
- To make a **custom** pet instead of installing one, use `/codepet-hatch`.
