#!/usr/bin/env bash
# Build CodePet, wire it into Claude Code's hooks, install the hatch skill,
# and launch the pet. Safe to re-run (idempotent).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "━━━ CodePet install ━━━"

# 1. Build the native app.
bash "$ROOT/build.sh"

# 2. Wire the Claude Code hooks (state.json driver).
echo "› Wiring Claude Code hooks…"
node "$ROOT/tools/install-hooks.js" install "$ROOT"

# 3. Install the CodePet skills for Claude Code.
mkdir -p "$HOME/.claude/skills"
link_skill() { # <src-dir> <dest-name> <label>
  if [ -d "$1" ]; then
    rm -rf "$HOME/.claude/skills/$2"
    ln -s "$1" "$HOME/.claude/skills/$2"
    echo "› Installed $3 skill"
  fi
}
link_skill "$ROOT/skills/hatch-pet" "codepet-hatch"  "/codepet-hatch"
link_skill "$ROOT/skills/petdex"    "codepet-petdex" "/codepet-petdex"

# 4. Seed default config if absent.
mkdir -p "$HOME/.codepet"
if [ ! -f "$HOME/.codepet/config.json" ]; then
  printf '{"corner":"bottomRight","pet":"built-in:blob","scale":1}\n' > "$HOME/.codepet/config.json"
fi

# 5. Launch (relaunch) the pet.
pkill -f "CodePet.app/Contents/MacOS/CodePet" 2>/dev/null || true
sleep 0.5
open "$ROOT/build/CodePet.app"

cat <<EOF

✓ CodePet is live in your menu bar (🐾) and bottom-right corner.

  • Start a Claude Code session — the pet reacts automatically:
      working… / needs you / ready for review / something failed
  • Switch forms or corner:   menu-bar 🐾
  • Install a Petdex pet:     node "$ROOT/tools/petdex.js" boba
                              (browse petdex.crafter.run · or ask /codepet-petdex)
  • Hatch a new pet:          node "$ROOT/tools/hatch.js" "My Pet"
                              (or ask Claude: /codepet-hatch)
  • Uninstall:                bash "$ROOT/uninstall.sh"
EOF
