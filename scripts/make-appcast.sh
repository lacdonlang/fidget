#!/bin/bash
# 生成 Sparkle 的更新清单 appcast.xml（只含当前版本），发布流程在公证之后调用。
# 应用读取 https://github.com/lacdonlang/fidget/releases/latest/download/appcast.xml，即最新 Release 里的这个文件。
# 用法: scripts/make-appcast.sh <更新包.zip> <输出.xml>
# 环境变量: SPARKLE_ED_PRIVATE_KEY  EdDSA 私钥（generate_keys -x 导出的内容），用来给更新包签名；
#           SPARKLE_SIGNATURE       仅测试用：直接给出签名属性（sparkle:edSignature="…" length="…"），不签名。
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ARCHIVE="${1:?用法: make-appcast.sh <更新包.zip> <输出.xml>}"
OUT="${2:?用法: make-appcast.sh <更新包.zip> <输出.xml>}"
URL="https://github.com/lacdonlang/fidget/releases/download/v$VERSION/$(basename "$ARCHIVE")"

if [ -n "${SPARKLE_SIGNATURE:-}" ]; then
  attributes="$SPARKLE_SIGNATURE"
else
  key_file="$(mktemp)"
  trap 'rm -f "$key_file"' EXIT
  printf '%s' "${SPARKLE_ED_PRIVATE_KEY:?需要 SPARKLE_ED_PRIVATE_KEY}" > "$key_file"
  attributes="$("$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update" --ed-key-file "$key_file" "$ARCHIVE")"
fi

# 更新说明取 CHANGELOG.md 里本版本那一节的条目，在 Sparkle 的更新窗口里显示。
notes="$(awk -v heading="## $VERSION" '$0 == heading { found = 1; next } /^## / { if (found) exit } found && /^- / { sub(/^- /, ""); print }' "$ROOT/CHANGELOG.md" \
  | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/^/<li>/' -e 's#$#</li>#')"
if [ -z "$notes" ]; then
  echo "错误: CHANGELOG.md 里没有 “## $VERSION” 一节" >&2
  exit 1
fi

cat > "$OUT" << XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Fidget</title>
    <link>https://github.com/lacdonlang/fidget</link>
    <item>
      <title>Fidget $VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$VERSION_BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_MACOS</sparkle:minimumSystemVersion>
      <description><![CDATA[<ul>
$notes
</ul>]]></description>
      <enclosure url="$URL" $attributes type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML
echo "✔ appcast: $OUT"
