import Foundation

/// 全局快捷键模型。键码为 macOS 虚拟键码（kVK_*），修饰键为与平台无关的位集合。
public struct HotKey: Codable, Equatable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// 按 macOS 习惯顺序（⌃⌥⇧⌘）输出符号。
        public var symbols: String {
            var s = ""
            if contains(.control) { s += "⌃" }
            if contains(.option) { s += "⌥" }
            if contains(.shift) { s += "⇧" }
            if contains(.command) { s += "⌘" }
            return s
        }
    }

    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var displayString: String { modifiers.symbols + KeyCodeNames.name(for: keyCode) }

    /// 没有修饰键的普通按键不允许作为全局快捷键（功能键除外），避免吞掉正常输入。
    public var isValid: Bool {
        if KeyCodeNames.isFunctionKey(keyCode) { return true }
        return modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option)
    }
}

/// 虚拟键码到显示名称的映射（ANSI 布局）。
public enum KeyCodeNames {
    private static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3",
        21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]",
        31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L", 38: "J", 39: "'", 40: "K",
        41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`",
        51: "⌫", 53: "⎋", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 107: "F14", 109: "F10", 111: "F12", 113: "F15", 114: "Help", 115: "↖", 116: "⇞",
        117: "⌦", 118: "F4", 119: "↘", 120: "F2", 121: "⇟", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    private static let functionKeys: Set<UInt16> = [96, 97, 98, 99, 100, 101, 103, 105, 107, 109, 111, 113, 118, 120, 122]

    public static func name(for keyCode: UInt16) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }

    public static func isFunctionKey(_ keyCode: UInt16) -> Bool { functionKeys.contains(keyCode) }
}
