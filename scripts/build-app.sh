#!/bin/bash
# 用 SwiftPM 构建并组装 Fidget.app（仅 Apple Silicon）。
# 用法: scripts/build-app.sh [debug|release]
# 环境变量: CODESIGN_IDENTITY（默认 "-" 即 ad-hoc）、BUNDLE_ID、BUILD_NUMBER、APP_OUTPUT_DIR、
#           STRICT_MIN_OS=1（产物的最低系统版本必须等于 Package.swift 声明的版本，发布时使用）
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CONFIG="${1:-release}"
APP_NAME="Fidget"
BUNDLE_ID="${BUNDLE_ID:-com.lacdon.fidget}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"
OUT_DIR="${APP_OUTPUT_DIR:-$ROOT/build}"
APP="$OUT_DIR/$APP_NAME.app"
LANGUAGES=(en zh-Hans)

if [ "$(uname -m)" != "arm64" ]; then
  echo "错误: Fidget 只支持在 Apple Silicon 上构建（当前: $(uname -m)）" >&2
  exit 1
fi

echo "▶ swift build -c $CONFIG"
swift build -c "$CONFIG" --product "$APP_NAME" --package-path "$ROOT"
BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"

# 产物实际的最低系统版本。新版 Xcode 能部署到的最低版本可能高于 Package.swift 的声明（Xcode 27 最低 macOS 12），
# 这时构建会被悄悄抬高；Info.plist 必须与二进制一致，发布构建则直接失败。
MIN_OS="$(otool -l "$BIN_DIR/$APP_NAME" | awk '/LC_BUILD_VERSION/ { found = 1 } found && $1 == "minos" { print $2; exit }')"
if [ "$MIN_OS" != "$MIN_MACOS" ]; then
  message="当前 Xcode（$(xcodebuild -version 2>/dev/null | head -1)）构建出的最低系统版本是 macOS ${MIN_OS}，而 Package.swift 声明支持 macOS $MIN_MACOS"
  if [ "${STRICT_MIN_OS:-0}" = "1" ]; then
    echo "错误: ${message}。请换用能部署到 macOS $MIN_MACOS 的 Xcode（见 scripts/select-xcode.sh）。" >&2
    exit 1
  fi
  echo "⚠ ${message}；本次产物只能在 macOS $MIN_OS 及以上运行。发布版本由 CI 构建。"
fi

echo "▶ 组装 ${APP}（最低 macOS ${MIN_OS}）"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
EXECUTABLE="$APP/Contents/MacOS/$APP_NAME"
cp "$BIN_DIR/$APP_NAME" "$EXECUTABLE"
sed -e "s/\$(EXECUTABLE_NAME)/$APP_NAME/g" \
    -e "s/\$(PRODUCT_NAME)/$APP_NAME/g" \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/g" \
    -e "s/\$(MARKETING_VERSION)/$VERSION/g" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILD_NUMBER/g" \
    -e "s/\$(MACOSX_DEPLOYMENT_TARGET)/$MIN_OS/g" \
    "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# 部署到 macOS 12 以下时，Swift 并发运行时不在系统里：二进制改为经 @rpath 引用，需要把工具链里的
# 向后部署版本放进 Contents/Frameworks。
RPATH_LIBS="$(otool -L "$EXECUTABLE" | awk '$1 ~ /^@rpath\// { sub("@rpath/", "", $1); print $1 }')"
if [ -n "$RPATH_LIBS" ]; then
  TOOLCHAIN_LIB="$(cd "$(dirname "$(xcrun --find swiftc)")/../lib" && pwd)"
  mkdir -p "$APP/Contents/Frameworks"
  for lib in $RPATH_LIBS; do
    source_lib="$(ls -d "$TOOLCHAIN_LIB"/swift-*/macosx/"$lib" 2>/dev/null | sort -V | tail -1)"
    if [ -z "$source_lib" ]; then
      echo "错误: 找不到 @rpath/$lib 的向后部署版本（在 $TOOLCHAIN_LIB/swift-*/macosx 下）" >&2
      exit 1
    fi
    # 工具链里的是通用二进制，应用只有 arm64，只保留这一份。
    lipo "$source_lib" -thin arm64 -output "$APP/Contents/Frameworks/$lib" 2> /dev/null || cp "$source_lib" "$APP/Contents/Frameworks/$lib"
    echo "  内嵌 ${lib}（来自 ${source_lib#"$TOOLCHAIN_LIB/"}）"
  done
fi
# rpath 只保留两项且顺序固定：先 /usr/lib/swift，新系统优先用系统自带的运行时；再是应用内的 Frameworks。
# SwiftPM 写入的构建目录、工具链等绝对路径一并去掉，不把构建机的路径带进发布产物。
for rpath in $(otool -l "$EXECUTABLE" | awk '$1 == "cmd" && $2 == "LC_RPATH" { getline; getline; print $2 }'); do
  install_name_tool -delete_rpath "$rpath" "$EXECUTABLE"
done
install_name_tool -add_rpath /usr/lib/swift "$EXECUTABLE"
if [ -n "$RPATH_LIBS" ]; then install_name_tool -add_rpath @executable_path/../Frameworks "$EXECUTABLE"; fi

# SwiftPM 资源包 + 把本地化目录提升到主包，便于系统按用户语言选择。
# 不同版本的 SwiftPM 生成的资源包结构不同：新版放在 Contents/Resources/ 下，旧版直接放在包根目录，
# 旧版还会把目录名改成小写（zh-hans.lproj）；这里统一改回 Info.plist 里登记的写法。
RESOURCE_BUNDLE="$BIN_DIR/${APP_NAME}_FidgetApp.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
  cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
  for lproj in "$RESOURCE_BUNDLE"/Contents/Resources/*.lproj "$RESOURCE_BUNDLE"/*.lproj; do
    [ -d "$lproj" ] || continue
    name="$(basename "$lproj" .lproj)"
    for lang in "${LANGUAGES[@]}"; do
      if [ "$(tr '[:upper:]' '[:lower:]' <<< "$name")" = "$(tr '[:upper:]' '[:lower:]' <<< "$lang")" ]; then name="$lang"; fi
    done
    cp -R "$lproj" "$APP/Contents/Resources/$name.lproj"
  done
fi
# 语言文件必须在主包里；缺了会在启动时退回 SwiftPM 资源包查找并崩溃，因此直接让构建失败。
for lang in "${LANGUAGES[@]}"; do
  if ! ls "$APP/Contents/Resources" | grep -x "$lang.lproj" > /dev/null || [ ! -f "$APP/Contents/Resources/$lang.lproj/Localizable.strings" ]; then
    echo "错误: $APP 缺少 $lang.lproj/Localizable.strings" >&2
    exit 1
  fi
done

"$ROOT/scripts/sign.sh" "$APP"
echo "✔ 完成: $APP (v$VERSION build ${BUILD_NUMBER}，最低 macOS $MIN_OS)"
