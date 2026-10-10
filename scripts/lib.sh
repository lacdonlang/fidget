# 各脚本共用的路径、版本与签名参数。用法: source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
# 支持的最低 macOS 版本，取自 Package.swift 的 platforms 声明（.macOS(.v11) → 11.0）。
MIN_MACOS="$(sed -nE 's/.*\.macOS\(\.v([0-9]+)(_([0-9]+))?\).*/\1.\3/p' "$ROOT/Package.swift" | head -1)"
MIN_MACOS="${MIN_MACOS%.}"; [[ "$MIN_MACOS" == *.* ]] || MIN_MACOS="$MIN_MACOS.0"
# 构建号由版本号推出（1.3.0 → 10300）：随版本单调递增，与 git 历史无关。Sparkle 按构建号判断有没有新版本。
VERSION_BUILD="$(awk -F. '{ printf "%d", $1 * 10000 + $2 * 100 + $3 }' <<< "$VERSION")"
# 版本号比较：version_le 11.0 12.0 → 真。
version_le() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]; }
# 本机签名配置（不入库，见 docs/SIGNING.md）。环境变量优先于文件。
if [ -z "${CODESIGN_IDENTITY:-}" ] && [ -f "$ROOT/.signing.env" ]; then source "$ROOT/.signing.env"; fi
# "-" 为 ad-hoc（默认）；发布请使用 "Developer ID Application: 名字 (TEAMID)"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
# 真实证书签名时加时间戳（公证要求）；ad-hoc 签名不能加。
SIGN_ARGS=(--force --sign "$CODESIGN_IDENTITY")
if [ "$CODESIGN_IDENTITY" != "-" ]; then SIGN_ARGS+=(--timestamp); fi
