#!/bin/bash
# 检查组装好的 Fidget.app：架构、最低系统版本、动态库能否在最低系统上解析、签名，最后实际启动几秒。
# 用法: scripts/verify-app.sh path/to/Fidget.app
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

APP="${1:?用法: verify-app.sh path/to/Fidget.app}"
BINARY="$APP/Contents/MacOS/Fidget"
failures=0
pass() { echo "✔ $*"; }
fail() { echo "✘ $*" >&2; failures=$((failures + 1)); }

archs="$(lipo -archs "$BINARY")"
[ "$archs" = "arm64" ] && pass "架构: $archs" || fail "架构应只有 arm64，实际: $archs"

minos="$(otool -l "$BINARY" | awk '/LC_BUILD_VERSION/ { found = 1 } found && $1 == "minos" { print $2; exit }')"
plist_min="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
[ "$minos" = "$plist_min" ] && pass "最低系统: macOS ${minos}（Info.plist 一致）" || fail "二进制最低系统 $minos 与 Info.plist 的 $plist_min 不一致"

# 每个依赖要么来自系统（/System、/usr/lib），要么经 @rpath 指向应用内的 Frameworks。
while read -r dependency; do
  case "$dependency" in
    /System/Library/*|/usr/lib/*) ;;
    @rpath/*)
      lib="${dependency#@rpath/}"
      if [ -f "$APP/Contents/Frameworks/$lib" ]; then
        pass "内嵌: ${lib}（$(lipo -archs "$APP/Contents/Frameworks/$lib")）"
      else
        fail "@rpath/$lib 没有放进 Contents/Frameworks"
      fi
      ;;
    *) fail "引用了构建机上的库: $dependency" ;;
  esac
done < <(otool -L "$BINARY" | tail -n +2 | awk '{ print $1 }')

# macOS 12 以下系统里没有 Swift 并发运行时，必须内嵌；rpath 顺序决定新系统仍优先用系统自带的那份。
rpaths="$(otool -l "$BINARY" | awk '$1 == "cmd" && $2 == "LC_RPATH" { getline; getline; print $2 }' | paste -sd ' ' -)"
if version_le 12.0 "$minos"; then
  [ "$rpaths" = "/usr/lib/swift @executable_path/../Frameworks" ] && pass "rpath: $rpaths" || fail "rpath 顺序不对: $rpaths"
else
  otool -L "$BINARY" | grep "@rpath/libswift_Concurrency.dylib" > /dev/null \
    && pass "Swift 并发运行时经 @rpath 引用（macOS $minos 上用内嵌版本）" \
    || fail "部署到 macOS $minos 时 Swift 并发运行时必须经 @rpath 引用"
  [ "$rpaths" = "/usr/lib/swift @executable_path/../Frameworks" ] && pass "rpath: $rpaths" || fail "rpath 顺序不对: $rpaths"
fi

# 内嵌的运行时必须导出二进制从它那里引用的每个符号，否则旧系统上会在启动时报 “Symbol not found”。
for library in "$APP"/Contents/Frameworks/*.dylib; do
  [ -f "$library" ] || continue
  name="$(basename "$library" .dylib)"
  missing="$(comm -23 \
    <(nm -m "$BINARY" | grep "(from $name)" | sed -E 's/.*external ([^ ]+) \(from.*/\1/' | sort -u) \
    <(nm -gU -arch arm64 "$library" | awk '{ print $NF }' | sort -u))"
  if [ -z "$missing" ]; then
    pass "${name} 导出了二进制用到的全部 $(nm -m "$BINARY" | grep -c "(from $name)") 个符号"
  else
    fail "${name} 缺少符号: $(echo "$missing" | paste -sd ' ' -)"
  fi
done

# 在线更新：框架里不该有 XPC 服务（只给沙盒应用用），更新源与验证更新用的公钥都要在 Info.plist 里。
sparkle="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$sparkle" ]; then
  [ ! -e "$sparkle/Versions/Current/XPCServices" ] && pass "Sparkle 已内嵌（$(lipo -archs "$sparkle/Versions/Current/Autoupdate")），不含 XPC 服务" || fail "Sparkle 里还有 XPC 服务"
  feed="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$APP/Contents/Info.plist" 2> /dev/null || true)"
  key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist" 2> /dev/null || true)"
  [[ "$feed" == https://* && -n "$key" ]] && pass "更新源: $feed" || fail "Info.plist 缺少 SUFeedURL（https）或 SUPublicEDKey"
else
  fail "没有内嵌 Sparkle.framework"
fi

codesign --verify --deep --strict "$APP" 2> /dev/null && pass "签名有效（含内嵌框架）" || fail "签名无效"

# 实际启动：动态库解析失败、启动即崩溃都会在这里暴露。使用临时配置目录，不碰真实设置。
config="$(mktemp -d)"
FIDGET_CONFIG_DIR="$config" "$BINARY" > "$config/stdout.log" 2>&1 &
pid=$!
sleep 5
if kill -0 "$pid" 2> /dev/null; then
  pass "启动 5 秒后仍在运行"
  kill "$pid"
  wait "$pid" 2> /dev/null || true
else
  wait "$pid" 2> /dev/null && status=0 || status=$?
  fail "启动后退出（状态 ${status}）："
  cat "$config/stdout.log" >&2
fi
rm -rf "$config"

[ "$failures" -eq 0 ] || { echo "共 $failures 项检查未通过" >&2; exit 1; }
