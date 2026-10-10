#!/bin/bash
# 对 .app 进行代码签名（启用 Hardened Runtime）。
# 用法: scripts/sign.sh path/to/Fidget.app   环境变量: CODESIGN_IDENTITY（见 lib.sh）
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

APP="${1:?用法: sign.sh path/to/Fidget.app}"

# Hardened Runtime 只在真实证书签名（要公证）时开启：ad-hoc 签名没有 Team ID，开启后的库校验
# 会拒绝加载同样是 ad-hoc 签名的 Sparkle.framework，应用一启动就退出（CI 的验证构建即如此）。
sign() {
  if [ "$CODESIGN_IDENTITY" = "-" ]; then
    codesign "${SIGN_ARGS[@]}" "$@"
  else
    codesign "${SIGN_ARGS[@]}" --options runtime "$@"
  fi
}

# 由内向外签名（codesign 不再推荐 --deep）：内嵌的动态库（macOS 11 用的 Swift 并发运行时）、
# 框架里的辅助程序（Sparkle 的 Autoupdate 与 Updater.app）、框架本身、资源包，最后是主应用。
if [ -d "$APP/Contents/Frameworks" ]; then
  find "$APP/Contents/Frameworks" -name "*.dylib" -maxdepth 1 -type f | while read -r library; do
    sign "$library"
  done
  find "$APP/Contents/Frameworks" -name "*.framework" -maxdepth 1 -type d | while read -r framework; do
    for helper in "$framework"/Versions/Current/Autoupdate "$framework"/Versions/Current/Updater.app; do
      if [ -e "$helper" ]; then sign "$helper"; fi
    done
    sign "$framework"
  done
fi
find "$APP/Contents/Resources" -name "*.bundle" -maxdepth 1 -type d | while read -r bundle; do
  sign "$bundle"
done
sign --entitlements "$ROOT/Resources/Fidget.entitlements" "$APP"
codesign --verify --strict --verbose=2 "$APP"
echo "✔ 已签名 ($CODESIGN_IDENTITY): $APP"
