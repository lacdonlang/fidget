#!/bin/bash
# 生成带 Applications 快捷方式的 DMG。
# 用法: scripts/make-dmg.sh [path/to/Fidget.app] [输出.dmg]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

APP="${1:-$ROOT/build/Fidget.app}"
DMG="${2:-$ROOT/dist/Fidget-$VERSION.dmg}"
STAGING="$(mktemp -d)"

mkdir -p "$(dirname "$DMG")"
rm -f "$DMG"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Fidget" -srcfolder "$STAGING" -ov -format UDZO -fs HFS+ "$DMG"
rm -rf "$STAGING"
if [ "$CODESIGN_IDENTITY" != "-" ]; then
  codesign "${SIGN_ARGS[@]}" "$DMG"
fi
echo "✔ DMG: $DMG"
