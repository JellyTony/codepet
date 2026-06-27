#!/usr/bin/env bash
# Build CodePet and assemble a downloadable release zip:
#   dist/CodePet-macos.zip  →  CodePet.app + double-click installers.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE="$ROOT/dist/CodePet"
OUT="$ROOT/dist/CodePet-macos.zip"

echo "━━━ Packaging CodePet ━━━"
bash "$ROOT/build.sh"

echo "› Staging release …"
rm -rf "$ROOT/dist"; mkdir -p "$STAGE"
cp -R "$ROOT/build/CodePet.app" "$STAGE/"
cp "$ROOT/dist-assets/Install CodePet.command"   "$STAGE/"
cp "$ROOT/dist-assets/Uninstall CodePet.command" "$STAGE/"
chmod +x "$STAGE/Install CodePet.command" "$STAGE/Uninstall CodePet.command"

cat > "$STAGE/READ ME FIRST.txt" <<'TXT'
CodePet — a desktop pet for Claude Code
=======================================

1. Double-click  "Install CodePet.command"
   If macOS blocks it, right-click it → Open → Open.

2. It copies CodePet to /Applications, clears the download quarantine, wires
   Claude Code's hooks, installs the skills, and launches the pet.
   Look for 🐾 in the menu bar — start a Claude Code session and it reacts.

Requires macOS 13+ and Node.js (https://nodejs.org) for the Claude Code hooks.
Source & full docs:  https://github.com/JellyTony/codepet
中文文档:            https://github.com/JellyTony/codepet/blob/main/README.zh-CN.md
TXT

echo "› Zipping …"
rm -f "$OUT"
ditto -c -k --sequesterRsrc --keepParent "$STAGE" "$OUT"
echo "✓ $OUT  ($(du -h "$OUT" | cut -f1))"
