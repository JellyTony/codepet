#!/usr/bin/env bash
# Remove CodePet hooks + skill and stop the app. Leaves ~/.codepet (your pets
# and config) intact; delete it manually if you want a clean slate.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "━━━ CodePet uninstall ━━━"

node "$ROOT/tools/install-hooks.js" uninstall "$ROOT"

SKILL_DST="$HOME/.claude/skills/codepet-hatch"
[ -L "$SKILL_DST" ] && rm -f "$SKILL_DST" && echo "› Removed /codepet-hatch skill"

pkill -f "CodePet.app/Contents/MacOS/CodePet" 2>/dev/null && echo "› Stopped CodePet" || true

echo "✓ Done. (Your pets/config remain in ~/.codepet)"
