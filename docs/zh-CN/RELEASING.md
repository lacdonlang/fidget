# 发布流程

[English](../en/RELEASING.md) · **简体中文**

Fidget 不走 App Store，而是用 Developer ID 签名并公证后分发（原因见[架构设计](ARCHITECTURE.md)）。

## 一次性准备

1. 在 [developer.apple.com](https://developer.apple.com/account/resources/certificates/list) 创建 **Developer ID Application** 证书（需要 Account Holder 身份），或在 Xcode → Settings → Accounts → Manage Certificates 里创建，然后确认钥匙串里有它：
   ```bash
   security find-identity -v -p codesigning   # 应列出 "Developer ID Application: 你的名字 (TEAMID)"
   ```
2. 保存公证凭据（App 专用密码在 appleid.apple.com 生成）：
   ```bash
   xcrun notarytool store-credentials fidget-notary \
     --apple-id "<Apple ID>" --team-id "<TEAMID>" --password "<App 专用密码>"
   ```
3. 在仓库根目录创建 `.signing.env`。它不入库，所有脚本默认用它签名；环境变量 `CODESIGN_IDENTITY` 可以临时覆盖：
   ```bash
   echo 'CODESIGN_IDENTITY="Developer ID Application: 你的名字 (TEAMID)"' > .signing.env
   ```

## 本地构建发布版

```bash
make app        # build/Fidget.app，Hardened Runtime + 时间戳签名
make notarize   # 公证并装订
make dmg        # dist/Fidget-<版本>.dmg（同样签名）
scripts/notarize.sh dist/Fidget-<版本>.dmg   # 可选：DMG 也公证
```

没有配置签名身份时用 ad-hoc 签名，且不开启 Hardened Runtime（否则 Sparkle 无法加载）。版本号来自 `VERSION` 文件；构建号由它推出（1.3.0 → 10300），可用 `BUILD_NUMBER` 覆盖。

也可以用 Xcode：运行 `make xcodeproj && open Fidget.xcodeproj`（需要 `brew install xcodegen`），在 `Config/Signing.xcconfig` 里设置 `DEVELOPMENT_TEAM`、`CODE_SIGN_STYLE = Automatic` 与 `CODE_SIGN_IDENTITY = Apple Development`，然后 Product → Archive → Distribute App → Developer ID。

## CI

- `.github/workflows/ci.yml`：每次 push 与 PR 时构建、测试，产出 ad-hoc 签名的应用，仅用于验证。
- `.github/workflows/release.yml`：推送 `v*` 标签时运行：测试 → 构建并签名 → 公证应用 → 打包 DMG 与 zip → 给 zip 签名并生成更新清单 → 公证 DMG → 创建 GitHub Release，上传 DMG、zip、`appcast.xml` 与 `appcast.zh-CN.xml`。缺少证书时产出 ad-hoc 签名的版本，缺少公证凭据时跳过公证。

| Secret | 内容 |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | Developer ID Application 证书导出的 .p12，base64 编码 |
| `MACOS_CERTIFICATE_PASSWORD` | .p12 的密码 |
| `CODESIGN_IDENTITY` | `Developer ID Application: 名字 (TEAMID)` |
| `NOTARY_APPLE_ID` / `NOTARY_TEAM_ID` / `NOTARY_PASSWORD` | 公证凭据 |
| `SPARKLE_ED_PRIVATE_KEY` | 给更新包签名的 EdDSA 私钥（见下） |

## 在线更新的签名密钥

- 密钥对用 Sparkle 的 `generate_keys` 生成，私钥存在维护者的登录钥匙串里（账号 `com.lacdon.fidget`）：
  ```bash
  GENERATE_KEYS=.build/artifacts/sparkle/Sparkle/bin/generate_keys
  $GENERATE_KEYS --account com.lacdon.fidget                 # 生成密钥（只需一次）
  $GENERATE_KEYS --account com.lacdon.fidget -p              # 打印公钥
  $GENERATE_KEYS --account com.lacdon.fidget -x private.key  # 导出私钥
  ```
- 公钥写在 `Resources/Info.plist` 的 `SUPublicEDKey`。导出的私钥用 `gh secret set SPARKLE_ED_PRIVATE_KEY < private.key` 存进 CI，用完删掉文件。
- **一定要备份私钥**（随钥匙串一起备份）。私钥丢了，已安装的版本就再也收不到更新，因为新签名对不上它们内置的公钥。要换密钥，只能先发一个带新公钥、但仍用旧私钥签名的版本。
- 仓库必须保持公开：已安装的应用要匿名从最新的 Release 下载更新清单与 zip。

## 发布步骤

1. 修改 `VERSION`（以及 `project.yml` 里的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`）。
2. 在 `CHANGELOG.md`（只写英文）与 `CHANGELOG.zh-CN.md` 里各加一节 `## <版本>`，每条说明一行，以 `- ` 开头。它们就是更新说明；任一份缺少这一节，`scripts/make-appcast.sh` 都会失败。
3. 运行 `make test`，并按[测试](TESTING.md)里的清单手动验收。
4. 提交后打标签并推送：`git tag v<版本> && git push origin v<版本>`，其余交给 CI。
5. 在旧版本里用“检查更新…”确认能装上新版本，且辅助功能授权仍在。

## 本地开发与 TCC

macOS 按代码签名识别应用。ad-hoc 签名每次构建都会变，重新构建后辅助功能授权就会失效。开发时可以用 Apple Development 证书签名（`CODESIGN_IDENTITY="Apple Development: 你的名字 (TEAMID)" make app`），或在 Xcode 里用自动签名运行。

- 授权列表里出现多个 Fidget，或开关已开却不生效时，运行 `tccutil reset Accessibility com.lacdon.fidget` 后重新授权（应用里的“重置权限”做的是同一件事）。
- 同一台机器上有多份 `Fidget.app`（例如 `build/` 与 Xcode 的 DerivedData）时，`open fidget://…` 可能交给另一份处理，可用 `open -a /绝对路径/Fidget.app "fidget://…"` 指定。

## 校验产物

```bash
codesign -dv --verbose=4 build/Fidget.app           # 查看签名信息
spctl --assess --type execute -vv build/Fidget.app  # Gatekeeper 评估：公证后应为 accepted
xcrun stapler validate build/Fidget.app
```
