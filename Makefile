# Fidget —— 常用命令
# 签名发布: CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" make app notarize dmg

.PHONY: build test ui-test check-min-os app app-debug verify run notarize dmg icon xcodeproj smoke screenshots clean

build:            ## 构建（debug）
	swift build

test:             ## 运行全部测试
	swift test

ui-test:          ## 真实弹出菜单栏面板检查位置（菜单栏会短暂出现图标并抢走焦点）
	FIDGET_UI_TESTS=1 swift test --filter PopoverPlacementTests

check-min-os:     ## 按支持的最低系统（macOS 11）对全部源码与测试做类型检查
	scripts/check-min-os.sh

app:              ## 构建 release 并组装/签名 build/Fidget.app
	scripts/build-app.sh release

app-debug:        ## 组装 debug 版 .app
	scripts/build-app.sh debug

verify:           ## 检查 build/Fidget.app 的架构、最低系统、依赖库、签名，并实际启动
	scripts/verify-app.sh build/Fidget.app

run: app-debug    ## 构建并启动 .app
	open build/Fidget.app

notarize:         ## 公证 build/Fidget.app（需要 notarytool 凭据）
	scripts/notarize.sh build/Fidget.app

dmg:              ## 生成 dist/Fidget-<版本>.dmg
	scripts/make-dmg.sh build/Fidget.app

icon:             ## 重新绘制应用图标
	swift scripts/make-icon.swift build/icon
	iconutil -c icns build/icon/AppIcon.iconset -o Resources/AppIcon.icns
	rm -rf Resources/Assets.xcassets/AppIcon.appiconset && cp -R build/icon/AppIcon.appiconset Resources/Assets.xcassets/
	cp build/icon/icon-1024.png Resources/AppIcon-1024.png

xcodeproj:        ## 用 XcodeGen 生成 Fidget.xcodeproj
	xcodegen generate

smoke: app-debug  ## 真机冒烟测试（需要终端已获辅助功能权限）
	scripts/smoke-test.sh build/Fidget.app

screenshots: app-debug ## 生成 README 截图到 docs/images
	scripts/screenshots.sh build/Fidget.app docs/images

clean:
	rm -rf .build build dist
