#!/usr/bin/env node
"use strict";
/*
 * codepet petdex — install a pet from the Petdex gallery (petdex.crafter.run)
 * and use it in CodePet. Zero config: Petdex's own CLI downloads the pet's
 * pet.json + spritesheet into ~/.petdex/pets/<slug>/ (and ~/.codex/pets/<slug>/),
 * which CodePet discovers automatically the next time you open the 🐾 menu.
 *
 * This is a thin convenience wrapper around the official installer:
 *     npx -y petdex install <slug>
 *
 * Usage:
 *   node petdex.js <slug>        # e.g. boba, 02, aurelion-sol
 *   node petdex.js install <slug>
 *
 * Browse slugs at https://petdex.crafter.run — the slug is the name shown
 * under each pet (the `petdex install <slug>` command on its page).
 */
const { spawnSync } = require("child_process");

function main() {
  const argv = process.argv.slice(2).filter((a) => a !== "install");
  const slug = argv[0];
  if (!slug) {
    console.error("Usage: petdex.js <slug>   (browse slugs at https://petdex.crafter.run)");
    process.exit(1);
  }

  console.log(`› Installing Petdex pet "${slug}" …`);
  const res = spawnSync("npx", ["-y", "petdex@latest", "install", slug], {
    stdio: "inherit",
  });
  if (res.status !== 0) {
    console.error(`\n✗ petdex install failed (exit ${res.status ?? "?"}).`);
    console.error("  Check the slug at https://petdex.crafter.run and that you have network access.");
    process.exit(res.status || 1);
  }

  console.log(`\n✓ Installed "${slug}".`);
  console.log("  Open the menu-bar 🐾 → Pet and pick it — no refresh or restart needed.");
  console.log("  (CodePet rediscovers ~/.petdex/pets every time the menu opens.)");
}

main();
