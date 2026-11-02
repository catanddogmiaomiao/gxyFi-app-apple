import Foundation

enum FiFormat {
    nonisolated static func price(_ value: Double?) -> String {
        guard let value else { return "—" }
        return grouped(value, minDigits: 0, maxDigits: 4)
    }

    nonisolated static func money(_ value: Double?, digits: Int = 2) -> String {
        guard let value else { return "—" }
        return grouped(value, minDigits: digits, maxDigits: digits)
    }

    nonisolated private static func grouped(_ value: Double, minDigits: Int, maxDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.decimalSeparator = "."
        formatter.minimumFractionDigits = minDigits
        formatter.maximumFractionDigits = maxDigits
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(maxDigits)f", value)
    }

    nonisolated static func cny(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "¥" + money(value)
    }

    nonisolated static func signed(_ value: Double?) -> String {
        guard let value else { return "—" }
        return (value > 0 ? "+" : "") + money(value)
    }

    nonisolated static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%%", value * 100)
    }

    nonisolated static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    nonisolated static func stamp(_ date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    nonisolated static func parseDay(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    static func round2(_ value: Double?) -> Double? {
        value.map { ($0 * 100).rounded() / 100 }
    }

    static func round4(_ value: Double?) -> Double? {
        value.map { ($0 * 10_000).rounded() / 10_000 }
    }

    static func parseNumber(
        _ text: String,
        label: String,
        required: Bool = false,
        allowNegative: Bool = false,
        allowZero: Bool = true
    ) throws -> Double? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "，", with: "")
        if raw.isEmpty {
            if required { throw LedgerError("请填写\(label)") }
            return nil
        }
        guard let value = Double(raw) else { throw LedgerError("\(label)不是有效数字") }
        if !allowNegative, value < 0 { throw LedgerError("\(label)不能为负数") }
        if !allowZero, value == 0 { throw LedgerError("\(label)需要大于 0") }
        return value
    }
}

enum LedgerKind {
    static let accountKinds = ["现金", "活期", "定期", "货币基金", "公积金", "其他"]
    static let propertyKinds = ["住宅", "商铺", "车位", "土地", "其他"]
    static let currencies = ["CNY", "USD", "HKD"]
    static let categories = ["居住", "餐饮", "交通", "教育", "医疗", "保险", "日用", "人情", "娱乐", "其他"]
    static let staleDays = 35
    static let marketChoices = [("美股", "US"), ("A股", "A"), ("黄金", "GOLD"), ("其他", "OTHER")]
    static let marketLabel = ["US": "美股", "A": "A股", "GOLD": "黄金", "OTHER": "其他"]
}

struct LedgerError: Error, CustomStringConvertible, LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
    var errorDescription: String? { message }
}
