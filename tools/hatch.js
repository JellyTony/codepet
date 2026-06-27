#!/usr/bin/env node
"use strict";
/*
 * codepet hatch — create a new pet, the CodePet analogue of Codex's hatch-pet
 * skill. Writes ~/.codepet/pets/<slug>/pet.json describing a vector pet that
 * the app renders with the built-in animation engine (all 9 Codex states).
 *
 * Usage:
 *   node hatch.js "<Display Name>" [--form blob|cat|robot|ghost]
 *                                  [--color "#rrggbb"] [--desc "..."]
 *
 * If --form / --color are omitted, a form and palette are picked from the name
 * so "hatch me a calm owl" still yields a stable, repeatable pet.
 */
const fs = require("fs");
const os = require("os");
const path = require("path");

const FORMS = ["blob", "cat", "robot", "ghost"];
const PALETTE = [
  "#46BDC6", "#F29E4D", "#8C99B8", "#A385EB",
  "#E0607E", "#5BAE6F", "#E8C341", "#6FA8DC",
];

function slugify(s) {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "pet";
}

// Stable hash so the same name maps to the same form/colour every time.
function hash(s) {
  let h = 5381;
  for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) >>> 0;
  return h;
}

function parseArgs(argv) {
  const out = { name: null, form: null, color: null, desc: null };
  const rest = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--form") out.form = argv[++i];
    else if (a === "--color") out.color = argv[++i];
    else if (a === "--desc") out.desc = argv[++i];
    else rest.push(a);
  }
  out.name = rest.join(" ").trim();
  return out;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.name) {
    console.error('Usage: hatch.js "<Display Name>" [--form blob|cat|robot|ghost] [--color "#rrggbb"] [--desc "..."]');
    process.exit(1);
  }
  const h = hash(args.name);
  const form = FORMS.includes(args.form) ? args.form : FORMS[h % FORMS.length];
  let color = args.color || PALETTE[(h >> 3) % PALETTE.length];
  if (!/^#?[0-9a-fA-F]{6}$/.test(color)) {
    console.error(`Invalid --color "${color}" (expected #rrggbb)`);
    process.exit(1);
  }
  if (!color.startsWith("#")) color = "#" + color;

  const slug = slugify(args.name);
  const petsDir = path.join(os.homedir(), ".codepet", "pets", slug);
  fs.mkdirSync(petsDir, { recursive: true });

  const manifest = {
    id: slug,
    displayName: args.name,
    description: args.desc || `A ${form} pet hatched for ${args.name}.`,
    form,
    color,
  };
  fs.writeFileSync(
    path.join(petsDir, "pet.json"),
    JSON.stringify(manifest, null, 2) + "\n"
  );

  console.log(`🥚 Hatched "${args.name}"`);
  console.log(`   form:  ${form}`);
  console.log(`   color: ${color}`);
  console.log(`   path:  ${path.join(petsDir, "pet.json")}`);
  console.log(`\nIn the menu-bar 🐾 → Pet → Refresh Pets, then pick "${args.name}".`);
}

main();
