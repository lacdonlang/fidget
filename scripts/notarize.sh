#!/bin/bash
# 公证并装订（staple）。需要先执行一次:
#   xcrun notarytool store-credentials fidget-notary --apple-id <Apple ID> --team-id <TEAMID> --password <App 专用密码>
# 用法: scripts/notarize.sh path/to/Fidget.app  （或 .dmg）
# 环境变量: NOTARY_PROFILE（默认 fidget-notary）
set -euo pipefail

TARGET="${1:?用法: notarize.sh path/to/Fidget.app|Fidget.dmg}"
PROFILE="${NOTARY_PROFILE:-fidget-notary}"

if [[ "$TARGET" == *.app ]]; then
  ZIP="${TARGET%.app}-notarize.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$TARGET" "$ZIP"
  SUBMIT="$ZIP"
else
  SUBMIT="$TARGET"
fi

echo "▶ 提交公证: $SUBMIT"
xcrun notarytool submit "$SUBMIT" --keychain-profile "$PROFILE" --wait
echo "▶ 装订"
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
[[ "$TARGET" == *.app ]] && rm -f "$ZIP"
echo "✔ 公证完成: $TARGET"
