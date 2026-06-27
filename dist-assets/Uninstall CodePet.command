#!/usr/bin/env bash
# Double-click to uninstall CodePet: stops the app, removes the Claude Code
# hooks and skills, and deletes the app. Your installed pets in ~/.codepet and
# ~/.petdex are kept.
set -uo pipefail

DEST="/Applications/CodePet.app"
RES="$DEST/Contents/Resources"

echo "━━━ Uninstalling CodePet ━━━"

pkill -f "CodePet.app/Contents/MacOS/CodePet" 2>/dev/null || true

if command -v node >/dev/null 2>&1 && [ -f "$RES/tools/install-hooks.js" ]; then
  node "$RES/tools/install-hooks.js" uninstall "$RES" || true
fi

rm -f "$HOME/.claude/skills/codepet-hatch" "$HOME/.claude/skills/codepet-petdex"
rm -rf "$DEST"

echo "✓ CodePet removed. Your pets (~/.codepet, ~/.petdex) were kept."
echo "  You can close this window."
