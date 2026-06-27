#!/usr/bin/env bash
# Double-click to install CodePet: copies the app to /Applications, clears the
# download quarantine (the app is open-source and ad-hoc signed, not notarized),
# wires Claude Code's hooks, installs the skills, and launches it.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/CodePet.app"
DEST="/Applications/CodePet.app"

echo "━━━ Installing CodePet ━━━"

if [ ! -d "$SRC" ]; then
  echo "✗ CodePet.app not found next to this installer."; exit 1
fi

# 1. Copy into /Applications and clear Gatekeeper quarantine.
echo "› Copying to /Applications …"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

RES="$DEST/Contents/Resources"

# 2. Wire Claude Code hooks (needs Node; the high-frequency HTTP hooks need only
#    the app, but SessionStart's terminal-identity capture runs a Node hook).
if command -v node >/dev/null 2>&1; then
  echo "› Wiring Claude Code hooks …"
  node "$RES/tools/install-hooks.js" install "$RES" || echo "  (hook wiring skipped)"
else
  echo "⚠︎ Node.js not found — install it from https://nodejs.org so CodePet can"
  echo "  react to Claude Code, then re-run this installer."
fi

# 3. Install the skills.
mkdir -p "$HOME/.claude/skills"
link_skill() { [ -d "$RES/skills/$1" ] && { rm -rf "$HOME/.claude/skills/$2"; ln -s "$RES/skills/$1" "$HOME/.claude/skills/$2"; }; }
link_skill "hatch-pet" "codepet-hatch"
link_skill "petdex"    "codepet-petdex"

# 4. Seed default config + launch.
mkdir -p "$HOME/.codepet"
[ -f "$HOME/.codepet/config.json" ] || printf '{"corner":"bottomRight","pet":"built-in:blob","scale":1}\n' > "$HOME/.codepet/config.json"
open "$DEST"

echo ""
echo "✓ CodePet installed to /Applications and launched (look for 🐾 in the menu bar)."
echo "  Start a Claude Code session and the pet reacts automatically."
echo "  You can close this window."
