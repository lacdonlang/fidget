import Foundation

/// 与语言无关的时长格式化（倒计时样式）。带单位的人类可读格式由界面层用系统本地化 API 处理。
public enum DurationFormatting {
    /// "0:42"、"12:05"、"1:02:03"。
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// 取整到“好看”的刻度：1 分钟以下取 5 秒，5 分钟以下取 15 秒，1 小时以下取 1 分钟，否则取 5 分钟。
    public static func snapToNiceSeconds(_ seconds: Double) -> Double {
        let step: Double
        switch seconds {
        case ..<60: step = 5
        case ..<300: step = 15
        case ..<3600: step = 60
        default: step = 300
        }
        return (seconds / step).rounded() * step
    }
}
