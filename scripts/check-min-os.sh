#!/bin/bash
# 按 Package.swift 声明的最低系统版本（macOS 11）对全部源码与测试做类型检查。
#
# 新版 Xcode 能部署到的最低版本可能高于我们支持的版本（Xcode 27 最低只到 macOS 12），
# 这时 `swift build` 会悄悄按更高的版本检查 API 可用性，漏掉“只在新系统上才有”的调用。
# 这里绕过构建系统，直接用 swiftc 按最低版本逐个模块检查，任何可用性错误都会让脚本失败。
# 发布版本由 CI 上能部署到 macOS 11 的 Xcode 真实构建（见 .github/workflows）。
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TARGET="arm64-apple-macosx$MIN_MACOS"
SDK="$(xcrun --show-sdk-path)"
PLATFORM="$(xcrun --show-sdk-platform-path)"
TOOLCHAIN_LIB="$(dirname "$(xcrun --find swiftc)")/../lib"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# SwiftPM 为带资源的目标生成 Bundle.module；类型检查时用一个同签名的替身。
printf 'import Foundation\nextension Foundation.Bundle { static let module = Bundle.main }\n' > "$WORK/BundleModule.swift"

COMMON=(-parse-as-library -target "$TARGET" -sdk "$SDK" -swift-version 6 -enable-testing -I "$WORK"
        -F "$PLATFORM/Developer/Library/Frameworks" -I "$PLATFORM/Developer/usr/lib"
        -plugin-path "$TOOLCHAIN_LIB/swift/host/plugins/testing")
sources() { find "$ROOT/$1" -name '*.swift' | sort; }

failed=0
check() { # check <说明> <swiftc 参数...>
  local label="$1"; shift
  if ! xcrun swiftc "${COMMON[@]}" "$@" > "$WORK/log.txt" 2>&1 || grep -q "error:" "$WORK/log.txt"; then
    echo "✘ $label"; grep -E "^/.*error:" "$WORK/log.txt" | sed "s|$ROOT/||" | sort -u | head -40; failed=1
  else
    echo "✔ $label"
  fi
}

echo "按 macOS $MIN_MACOS 检查（$(xcrun swiftc --version 2>/dev/null | head -1)）"
check "FidgetCore"   -emit-module -module-name FidgetCore   -emit-module-path "$WORK/FidgetCore.swiftmodule"   $(sources Sources/FidgetCore)
check "FidgetSystem" -emit-module -module-name FidgetSystem -emit-module-path "$WORK/FidgetSystem.swiftmodule" $(sources Sources/FidgetSystem)
check "FidgetApp（release）" -typecheck -module-name FidgetApp $(sources Sources/FidgetApp) "$WORK/BundleModule.swift"
check "FidgetApp（debug）"   -emit-module -module-name FidgetApp -DDEBUG -emit-module-path "$WORK/FidgetApp.swiftmodule" $(sources Sources/FidgetApp) "$WORK/BundleModule.swift"
for tests in FidgetCoreTests FidgetSystemTests FidgetAppTests; do
  check "$tests" -typecheck -module-name "$tests" $(sources "Tests/$tests")
done
exit $failed
