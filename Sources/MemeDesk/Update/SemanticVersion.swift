import Foundation

/// 版本号。
///
/// 只认「点分数字 + 可选预发布后缀」，够用且能避开最常见的坑：
/// **不能拿字符串比大小** —— 那样 `"0.0.10" < "0.0.9"`，升级会永远推不动。
///
/// 预发布（`1.0.0-beta.1`）按语义化版本规则排在正式版**之前**。
/// GitHub 的 `/releases/latest` 本来就不会返回预发布版本，这里只是留个正确的底。
struct SemanticVersion: Equatable, Comparable, CustomStringConvertible, Sendable {

    /// 点分数字段，例如 `0.1.0` → `[0, 1, 0]`。
    let components: [Int]
    /// 预发布后缀（`-` 之后的内容），没有则为 nil。
    let prerelease: String?
    /// 去掉前导 `v` 之后的原始写法，用于展示。
    let display: String

    init?(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        guard !s.isEmpty else { return nil }

        var pre: String?
        if let dash = s.firstIndex(of: "-") {
            pre = String(s[s.index(after: dash)...])
            s = String(s[..<dash])
        }
        // `1.0.0+build5` 里的构建元数据不参与比较，直接丢掉。
        if let plus = s.firstIndex(of: "+") {
            s = String(s[..<plus])
        }

        var numbers: [Int] = []
        for piece in s.split(separator: ".", omittingEmptySubsequences: false) {
            guard let n = Int(piece) else { return nil }
            numbers.append(n)
        }
        guard !numbers.isEmpty else { return nil }

        components = numbers
        prerelease = (pre?.isEmpty == false) ? pre : nil
        display = s
    }

    var description: String { display }

    /// 补齐到相同长度后再逐段比 —— 这样 `0.1` 与 `0.1.0` 相等。
    ///
    /// 相等也必须走同一套补齐逻辑：`Equatable` 一旦交给合成实现，就会按
    /// `components` 数组逐元素比，于是 `0.1 != 0.1.0` 而同一次比较里
    /// `0.1 < 0.1.0` 又是假的 —— 两个运算符口径不一致，早晚要出事。
    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let a = i < lhs.components.count ? lhs.components[i] : 0
            let b = i < rhs.components.count ? rhs.components[i] : 0
            if a != b { return false }
        }
        return lhs.prerelease == rhs.prerelease
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let a = i < lhs.components.count ? lhs.components[i] : 0
            let b = i < rhs.components.count ? rhs.components[i] : 0
            if a != b { return a < b }
        }
        // 数字段相同：有预发布后缀的更低（1.0.0-beta < 1.0.0）
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (nil, .some): return false
        case (.some, nil): return true
        case let (.some(l), .some(r)): return l < r
        }
    }
}
