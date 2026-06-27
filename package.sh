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

# Pin the bundle in place. By default pkgbuild marks app bundles as relocatable,
# so if a copy with the same bundle id already exists anywhere on disk (e.g. a
# dev build under build/), the installer "updates" that copy instead of writing
# to /Applications — and the app never shows up in Launchpad. Disable it.
COMPONENT="$ROOT/dist/component.plist"
pkgbuild --analyze --root "$STAGE" "$COMPONENT" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$COMPONENT"

pkgbuild \
  --root "$STAGE" \
  --component-plist "$COMPONENT" \
  --identifier com.codepet.app \
  --version "$VERSION" \
  --install-location /Applications \
  --scripts "$SCRIPTS" \
  "$OUT"

rm -rf "$STAGE"
echo "✓ $OUT  ($(du -h "$OUT" | cut -f1))"
