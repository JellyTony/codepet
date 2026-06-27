#!/usr/bin/env bash
# Compile the CodePet Swift sources into a self-contained CodePet.app bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$ROOT/build/CodePet.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

echo "› Building CodePet.app …"
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

# Compile all Swift sources into one executable.
xcrun swiftc \
  -O \
  -target "arm64-apple-macos13.0" \
  -framework AppKit -framework SwiftUI -framework Combine -framework Network \
  -o "$MACOS/CodePet" \
  "$ROOT"/Sources/CodePet/*.swift

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# App icon. Regenerate from source if iconutil is available and it's missing,
# otherwise use the committed icns.
if [ ! -f "$ROOT/Resources/AppIcon.icns" ] && command -v iconutil >/dev/null 2>&1; then
  xcrun swift "$ROOT/tools/make-icon.swift" "$ROOT" >/dev/null 2>&1 || true
  iconutil -c icns "$ROOT/build/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns" 2>/dev/null || true
fi
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$RES/AppIcon.icns"

# Ad-hoc code signature so macOS will run it locally.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
  echo "  (codesign skipped — app still runs locally)"

echo "✓ Built $APP"
