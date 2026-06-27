#!/usr/bin/env bash
set -euo pipefail

# Build a drag-to-Applications Portico.dmg from a fresh release bundle.
# The app is ad-hoc signed (no Developer ID / notarization), so first launch
# needs right-click -> Open, or: xattr -dr com.apple.quarantine /Applications/Portico.app

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/Portico.app"
DMG="$ROOT/Portico.dmg"
VOL="Portico"

cd "$ROOT"

# Always build a fresh bundle so the DMG can't ship stale code.
"$ROOT/Scripts/make-app.sh"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create \
  -volname "$VOL" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$DMG"

echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
