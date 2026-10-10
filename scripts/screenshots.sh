#!/bin/bash
# 生成 README 截图：调试构建的 Fidget 在进程内用固定示例数据渲染各个界面，不需要任何系统权限。
# 每种界面语言、每种外观各一套，写到 <输出目录>/<语言>/<外观>/，例如 docs/images/en/dark/。
# 用法: scripts/screenshots.sh [path/to/Fidget.app] [输出目录]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

APP="${1:-$ROOT/build/Fidget.app}"
OUT="${2:-$ROOT/docs/images}"
BINARY="$APP/Contents/MacOS/Fidget"

# 渲染模式只编进调试构建；发布构建会忽略参数并作为普通应用一直运行下去。
if ! nm "$BINARY" 2>/dev/null | grep ScreenshotRenderer > /dev/null; then
  echo "✘ $APP 不是调试构建，请先执行 make app-debug" >&2
  exit 1
fi

for language in en zh-Hans; do
  for appearance in dark light; do
    "$BINARY" --render-screenshots "$OUT/$language/$appearance" --language "$language" --appearance "$appearance"
  done
done
find "$OUT" -type f | sort
