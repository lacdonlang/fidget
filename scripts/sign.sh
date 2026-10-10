#!/bin/bash
# 对 .app 进行代码签名（启用 Hardened Runtime）。
# 用法: scripts/sign.sh path/to/Fidget.app   环境变量: CODESIGN_IDENTITY（见 lib.sh）
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

APP="${1:?用法: sign.sh path/to/Fidget.app}"

# 先签内嵌的动态库（macOS 11 用的 Swift 并发运行时）与资源包，再签主应用（codesign 不再推荐 --deep）。
if [ -d "$APP/Contents/Frameworks" ]; then
  find "$APP/Contents/Frameworks" -name "*.dylib" -maxdepth 1 -type f | while read -r library; do
    codesign "${SIGN_ARGS[@]}" --options runtime "$library"
  done
fi
find "$APP/Contents/Resources" -name "*.bundle" -maxdepth 1 -type d | while read -r bundle; do
  codesign "${SIGN_ARGS[@]}" --options runtime "$bundle"
done
codesign "${SIGN_ARGS[@]}" --options runtime --entitlements "$ROOT/Resources/Fidget.entitlements" "$APP"
codesign --verify --strict --verbose=2 "$APP"
echo "✔ 已签名 ($CODESIGN_IDENTITY): $APP"
