import Carbon.HIToolbox
import FidgetCore
import Foundation

/// 用 Carbon RegisterEventHotKey 注册全局快捷键；无需辅助功能权限。
@MainActor
public final class HotKeyCenter {
    public var onTrigger: (@MainActor () -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x4644_4754 // "FDGT"

    public init() {}

    public var isRegistered: Bool { hotKeyRef != nil }

    public func register(_ hotKey: HotKey?) {
        unregister()
        guard let hotKey, hotKey.isValid else { return }
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(UInt32(hotKey.keyCode), Self.carbonModifiers(hotKey.modifiers), id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRef = ref
        } else {
            Log.shared.error("注册全局快捷键失败: \(status)", category: .system)
        }
    }

    public func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { center.onTrigger?() }
            return noErr
        }, 1, &eventType, userData, &handlerRef)
    }

    static func carbonModifiers(_ modifiers: HotKey.Modifiers) -> UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }
}
