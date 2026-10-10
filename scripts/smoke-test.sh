#!/bin/bash
# 冒烟测试：用临时配置目录直接运行 build/Fidget.app 的可执行文件（继承终端的辅助功能授权），
# 验证引擎在闲置后真的移动了指针，日志与统计被写入。
# 用法: scripts/smoke-test.sh [path/to/Fidget.app]   环境变量: THRESHOLD(默认 5) WAIT(默认 16)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

APP="${1:-$ROOT/build/Fidget.app}"
CFG="$(mktemp -d)"
THRESHOLD="${THRESHOLD:-5}"
WAIT="${WAIT:-16}"

cat > "$CFG/settings.json" <<JSON
{
  "idleThresholdSeconds": $THRESHOLD,
  "jiggleIntervalSeconds": 5,
  "movement": { "invisibleMode": true },
  "general": { "hasCompletedOnboarding": true },
  "advanced": { "fileLoggingEnabled": true }
}
JSON

echo "▶ 启动 ${APP}（配置目录 ${CFG}）"
FIDGET_CONFIG_DIR="${CFG}" "${APP}/Contents/MacOS/Fidget" > "${CFG}/stdout.log" 2>&1 &
PID=$!
# 应用内处理 SIGTERM 并走正常退出流程；5 秒内没退出才强杀。
stop_app() {
  kill -TERM "$PID" 2>/dev/null || return 0
  for _ in 1 2 3 4 5; do kill -0 "$PID" 2>/dev/null || return 0; sleep 1; done
  kill -9 "$PID" 2>/dev/null || true
}
trap stop_app EXIT
sleep 2
if ! kill -0 "$PID" 2>/dev/null; then echo "✘ 进程提前退出"; exit 1; fi
echo "▶ 等待 ${WAIT} 秒（期间请不要碰鼠标/键盘）"
sleep "$WAIT"

LOG="$CFG/Logs/fidget.log"
echo "▶ 关键日志："
grep -E "状态|移动完成|指针没有移动|电源断言|启动" "$LOG" || true
MOVES="$(grep -c "移动完成" "$LOG" || true)"

echo "▶ 优雅退出"
stop_app
trap - EXIT

echo "▶ 统计文件: $(cat "$CFG/statistics.json" 2>/dev/null || echo '(未写入)')"
echo "移动次数: $MOVES"
if [ "${MOVES:-0}" -ge 1 ]; then
  echo "✔ 冒烟测试通过"
else
  echo "✘ 没有观察到移动（若期间有真实输入属正常，可重试）"
  exit 1
fi
