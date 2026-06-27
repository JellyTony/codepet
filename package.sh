#!/usr/bin/env bash
# Build CodePet and produce a double-click macOS installer:  dist/CodePet.pkg
# Installing it drops CodePet into /Applications and launches it; the app wires
# the Claude Code hooks itself on first launch.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="${1:-0.1.0}"
STAGE="$ROOT/dist/pkgroot"
SCRIPTS="$ROOT/dist-assets/scripts"
OUT="$ROOT/dist/CodePet.pkg"

echo "━━━ Packaging CodePet.pkg (v$VERSION) ━━━"
bash "$ROOT/build.sh"

rm -rf "$ROOT/dist"; mkdir -p "$STAGE"
cp -R "$ROOT/build/CodePet.app" "$STAGE/CodePet.app"
chmod +x "$SCRIPTS/postinstall"

pkgbuild \
  --root "$STAGE" \
  --identifier com.codepet.app \
  --version "$VERSION" \
  --install-location /Applications \
  --scripts "$SCRIPTS" \
  "$OUT"

rm -rf "$STAGE"
echo "✓ $OUT  ($(du -h "$OUT" | cut -f1))"
