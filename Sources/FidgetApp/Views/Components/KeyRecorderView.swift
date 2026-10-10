import AppKit
import Carbon.HIToolbox
import FidgetCore
import SwiftUI

/// 快捷键录制控件：点击（或获得焦点后按空格 / 回车）开始录制，按下组合键即可记录，Esc 取消。
/// 外观是设置窗口深色底上的玻璃胶囊，录制时描边换成当前页面的主题色。尺寸取 NSView 的固有尺寸（150×28）。
struct KeyRecorderView: NSViewRepresentable {
    @Binding var hotKey: HotKey?

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let view = KeyRecorderNSView()
        view.onChange = { hotKey = $0 }
        view.hotKey = hotKey
        return view
    }

    func updateNSView(_ nsView: KeyRecorderNSView, context: Context) {
        // 只在值变化时写入：写入会刷新显示，正在录制时会冲掉已按下的修饰键提示。
        if nsView.hotKey != hotKey { nsView.hotKey = hotKey }
        nsView.onChange = { hotKey = $0 }
        nsView.accentColor = context.environment.theme.nsAccent
    }
}

final class KeyRecorderNSView: NSView {
    var onChange: ((HotKey?) -> Void)?
    var hotKey: HotKey? { didSet { refresh() } }
    var accentColor: NSColor = .controlAccentColor { didSet { if accentColor != oldValue { needsDisplay = true } } }
    private var isRecording = false { didSet { refresh() } }
    private var invalidAttempt = false
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        label.alignment = .center
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 6),
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 28) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    /// 只是获得焦点（窗口打开时自动聚焦、按 Tab 切换过来）不开始录制，否则打开设置后随手按键就会被录成快捷键。
    override func becomeFirstResponder() -> Bool {
        true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        invalidAttempt = false
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            if event.keyCode == UInt16(kVK_Space) || event.keyCode == UInt16(kVK_Return) {
                isRecording = true
            } else {
                super.keyDown(with: event)
            }
            return
        }
        if event.keyCode == UInt16(kVK_Escape) { // 取消
            isRecording = false
            window?.makeFirstResponder(nil)
            return
        }
        if event.keyCode == UInt16(kVK_Delete), event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty { // 退格清除
            hotKey = nil
            onChange?(nil)
            isRecording = false
            window?.makeFirstResponder(nil)
            return
        }
        let candidate = HotKey(keyCode: event.keyCode, modifiers: Self.modifiers(from: event.modifierFlags))
        guard candidate.isValid else {
            invalidAttempt = true
            refresh()
            return
        }
        invalidAttempt = false
        hotKey = candidate
        onChange?(candidate)
        isRecording = false
        window?.makeFirstResponder(nil)
    }

    override func flagsChanged(with event: NSEvent) {
        if isRecording { refresh(modifiers: Self.modifiers(from: event.modifierFlags)) }
    }

    /// 图层颜色是解析好的 CGColor，不会自己跟着外观变；在当前外观下重新解析，外观切换时重绘。
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = (isRecording ? accentColor : Self.border).cgColor
            layer?.borderWidth = isRecording ? 1.5 : 1
            layer?.backgroundColor = (isRecording ? Self.recordingBackground : Self.background).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private static let background = NSColor.dynamic(light: .black(0.06), dark: .white(0.1))
    private static let recordingBackground = NSColor.dynamic(light: .black(0.09), dark: .white(0.14))
    private static let border = NSColor.dynamic(light: .black(0.1), dark: .white(0.12))

    private func refresh(modifiers: HotKey.Modifiers? = nil) {
        if isRecording {
            if invalidAttempt {
                label.stringValue = L.t("keyRecorder.invalid")
            } else if let modifiers, !modifiers.isEmpty {
                label.stringValue = modifiers.symbols
            } else {
                label.stringValue = L.t("keyRecorder.recording")
            }
            label.textColor = .secondaryLabelColor
        } else if let hotKey {
            label.stringValue = hotKey.displayString
            label.textColor = .labelColor
        } else {
            label.stringValue = L.t("keyRecorder.prompt")
            label.textColor = .secondaryLabelColor
        }
        needsDisplay = true
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> HotKey.Modifiers {
        var m: HotKey.Modifiers = []
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.shift) { m.insert(.shift) }
        return m
    }
}
