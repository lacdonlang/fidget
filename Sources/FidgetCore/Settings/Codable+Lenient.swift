import Foundation

extension KeyedDecodingContainer {
    /// 宽松解码：键缺失或类型不匹配时回退到默认值。
    /// 这样旧版本（或被手工编辑过）的配置文件永远不会让应用启动失败。
    func lenient<T: Decodable>(_ key: Key, default defaultValue: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? defaultValue
    }
}
