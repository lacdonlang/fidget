#!/bin/bash
# 在 CI 上选择能部署到 Package.swift 所声明最低系统（macOS 11）的最新 Xcode。
#
# 新版 Xcode 会抬高能部署到的最低版本（Xcode 27 最低 macOS 12），直接选最新版会让发布产物悄悄失去对旧系统的支持。
# 这里读取各 Xcode 自带 SDK 的 SDKSettings.plist 里的 MinimumDeploymentTarget 判断。
# （同一文件里的 SwiftConcurrencyMinimumDeploymentTarget 表示“系统从哪个版本起自带并发运行时”，
#   低于它的部署目标由 build-app.sh 内嵌向后部署库解决，不是部署下限。）
# 用法: scripts/select-xcode.sh   （需要 sudo 权限执行 xcode-select）
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

setting() { # setting <SDKSettings.plist> <键>：读取 macOS 平台的部署目标设置，缺失时输出空串
  /usr/libexec/PlistBuddy -c "Print :SupportedTargets:macosx:$2" "$1" 2>/dev/null || true
}

for xcode in $(ls -d /Applications/Xcode*.app | sort -V -r); do
  settings="$xcode/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/SDKSettings.plist"
  [ -f "$settings" ] || continue
  minimum="$(setting "$settings" MinimumDeploymentTarget)"
  echo "$(basename "$xcode"): 最低部署 macOS ${minimum:-?}"
  if [ -n "$minimum" ] && version_le "$minimum" "$MIN_MACOS"; then
    sudo xcode-select -s "$xcode"
    echo "✔ 选用 ${xcode}（可部署到 macOS ${MIN_MACOS}）"
    exit 0
  fi
done
echo "错误: 没有能部署到 macOS $MIN_MACOS 的 Xcode" >&2
exit 1
