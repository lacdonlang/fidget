import Foundation
import Testing
@testable import FidgetApp
@testable import FidgetCore

@Suite("状态展示映射")
struct StatusPresentationTests {
    let settings = FidgetCore.Settings.default
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("关闭态")
    func off() {
        let p = StatusPresentation.make(status: .off, settings: settings, now: now)
        #expect(p.kind == .off)
        #expect(p.symbolName == "cursorarrow.slash")
        #expect(p.countdown == nil)
        #expect(p.title == L.t("status.off.title"))
    }

    @Test("缺少权限")
    func blocked() {
        let p = StatusPresentation.make(status: .blocked(.accessibilityPermission), settings: settings, now: now)
        #expect(p.kind == .blocked)
        #expect(p.symbolName == "exclamationmark.triangle")
    }

    @Test("暂停原因文案")
    func paused() {
        let indefinite = StatusPresentation.make(status: .paused(.manual(until: nil)), settings: settings, now: now)
        #expect(indefinite.kind == .paused)
        #expect(indefinite.detail == L.t("status.paused.manual.indefinite"))
        #expect(indefinite.symbolName == "pause.circle")
        let locked = StatusPresentation.pauseDetail(.screenLocked, now: now, calendar: .current)
        #expect(locked == L.t("status.paused.screenLocked"))
        let never = StatusPresentation.pauseDetail(.outsideSchedule(resumesAt: nil), now: now, calendar: .current)
        #expect(never == L.t("status.paused.schedule.never"))
        let app = StatusPresentation.pauseDetail(.app(AppRule(bundleIdentifier: "x", displayName: "Zoom")), now: now, calendar: .current)
        #expect(app.contains("Zoom"))
        let until = StatusPresentation.pauseDetail(.manual(until: now.addingTimeInterval(600)), now: now, calendar: .current)
        #expect(!until.isEmpty && until != L.t("status.paused.manual.until"))
    }

    @Test("监测中与工作中带倒计时")
    func watchingAndActive() {
        let w = StatusPresentation.make(status: .watching(idleSeconds: 10, remainingSeconds: 50), settings: settings, now: now)
        #expect(w.kind == .watching)
        #expect(w.countdown == "0:50")
        #expect(w.symbolName == "cursorarrow")
        let a = StatusPresentation.make(status: .active(idleSeconds: 100, jiggleCount: 3, nextJiggleInSeconds: 30), settings: settings, now: now)
        #expect(a.kind == .active)
        #expect(a.countdown == "0:30")
        #expect(a.symbolName == "cursorarrow.motionlines")
        #expect(a.detail.contains("3"))
    }

    @Test("图标风格表", arguments: MenuBarIconStyle.allCases)
    func iconStyles(style: MenuBarIconStyle) {
        var s = FidgetCore.Settings.default
        s.general.menuBarIconStyle = style
        let active = StatusPresentation.make(status: .active(idleSeconds: 1, jiggleCount: 1, nextJiggleInSeconds: 1), settings: s, now: now)
        let watching = StatusPresentation.make(status: .watching(idleSeconds: 1, remainingSeconds: 1), settings: s, now: now)
        let off = StatusPresentation.make(status: .off, settings: s, now: now)
        #expect(!active.symbolName.isEmpty && !watching.symbolName.isEmpty && !off.symbolName.isEmpty)
        #expect(active.symbolName != off.symbolName)
        #expect(StatusPresentation.previewSymbol(for: style) == active.symbolName)
    }

    @Test("时间字符串：同日只有时刻，异日带星期")
    func timeStrings() {
        let sameDay = StatusPresentation.timeString(now.addingTimeInterval(60), now: now, calendar: .current)
        let otherDay = StatusPresentation.timeString(now.addingTimeInterval(3 * 86_400), now: now, calendar: .current)
        #expect(!sameDay.isEmpty && !otherDay.isEmpty)
        #expect(otherDay.count > sameDay.count)
    }

    @Test("人类可读时长非空")
    func humanDuration() {
        #expect(!StatusPresentation.humanDuration(90).isEmpty)
        #expect(!StatusPresentation.humanDuration(0).isEmpty)
    }
}
