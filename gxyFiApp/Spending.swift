import Foundation

/// 支出按类别、按月份汇总，供支出页和总览的图表使用。退款是负数，冲减所在类别。
/// 期间写成「2026-11」表示一个月，「2026」表示一年，nil 表示全部月份。
struct CategorySpend: Identifiable, Equatable {
    var categoryID: Int64
    var category: String
    var amount: Double
    var count: Int
    var refund: Double
    var share: Double

    var id: Int64 { categoryID }
}

struct MonthStack: Equatable {
    var keys: [String]
    var names: [String]
    var cells: [String: [String: Double]]
}

enum Spending {
    static let other = "其他类别"

    static func inPeriod(_ row: ExpenseRecord, _ period: String?) -> Bool {
        guard let period else { return true }
        return row.occurredOn.hasPrefix(period)
    }

    static func previousPeriod(_ period: String?) -> String? {
        guard let period, let year = Int(period.prefix(4)) else { return nil }
        if period.count == 4 { return String(format: "%04d", year - 1) }
        guard let month = Int(period.suffix(2)) else { return nil }
        return month == 1 ? String(format: "%04d-12", year - 1) : String(format: "%04d-%02d", year, month - 1)
    }

    static func periodLabel(_ period: String?) -> String {
        guard let period, let year = Int(period.prefix(4)) else { return "全部月份" }
        if period.count == 4 { return "\(year) 年" }
        return "\(year) 年 \(Int(period.suffix(2)) ?? 0) 月"
    }

    /// 按金额从大到小。
    static func byCategory(_ expenses: [ExpenseRecord], period: String?) -> [CategorySpend] {
        var groups: [Int64: CategorySpend] = [:]
        var order: [Int64] = []
        for row in expenses where inPeriod(row, period) {
            if groups[row.categoryID] == nil {
                groups[row.categoryID] = CategorySpend(categoryID: row.categoryID, category: row.category, amount: 0, count: 0, refund: 0, share: 0)
                order.append(row.categoryID)
            }
            groups[row.categoryID]!.amount += row.amount
            groups[row.categoryID]!.count += 1
            if row.amount < 0 { groups[row.categoryID]!.refund += -row.amount }
        }
        var rows = order.compactMap { groups[$0] }.map { item in
            var item = item
            item.amount = round2(item.amount)
            item.refund = round2(item.refund)
            return item
        }
        let total = rows.reduce(0) { $0 + max($1.amount, 0) }
        for index in rows.indices {
            rows[index].share = total == 0 ? 0 : max(rows[index].amount, 0) / total
        }
        return rows.sorted { $0.amount != $1.amount ? $0.amount > $1.amount : $0.category < $1.category }
    }

    static func total(_ expenses: [ExpenseRecord], period: String?) -> Double {
        round2(expenses.filter { inPeriod($0, period) }.reduce(0) { $0 + $1.amount })
    }

    static func monthKeys(_ count: Int, today: Date = .now) -> [String] {
        let parts = FiFormat.day(today).split(separator: "-").compactMap { Int($0) }
        var year = parts[0], month = parts[1]
        var keys: [String] = []
        for _ in 0..<count {
            keys.append(String(format: "%04d-%02d", year, month))
            if month == 1 { year -= 1; month = 12 } else { month -= 1 }
        }
        return keys.reversed()
    }

    /// 近 count 个月每月各类别金额。只单独列出合计最多的 top 类，其余并成「其他类别」。
    static func monthlyStack(_ expenses: [ExpenseRecord], count: Int = 6, top: Int = 5, today: Date = .now) -> MonthStack {
        let keys = monthKeys(count, today: today)
        let wanted = Set(keys)
        var cells: [String: [String: Double]] = Dictionary(uniqueKeysWithValues: keys.map { ($0, [:]) })
        var totals: [String: Double] = [:]
        var seen: [String] = []
        for row in expenses {
            let key = String(row.occurredOn.prefix(7))
            guard wanted.contains(key) else { continue }
            cells[key, default: [:]][row.category, default: 0] += row.amount
            if totals[row.category] == nil { seen.append(row.category) }
            totals[row.category, default: 0] += row.amount
        }
        let ranked = seen.filter { (totals[$0] ?? 0) > 0 }.sorted { (totals[$0] ?? 0) > (totals[$1] ?? 0) }
        let kept = Array(ranked.prefix(top))
        var out: [String: [String: Double]] = [:]
        for key in keys {
            var month: [String: Double] = [:]
            for (name, value) in cells[key] ?? [:] {
                month[kept.contains(name) ? name : other, default: 0] += value
            }
            out[key] = month.filter { $0.value > 0 }.mapValues { round2($0) }
        }
        return MonthStack(keys: keys, names: kept + (ranked.count > top ? [other] : []), cells: out)
    }

    /// 按月看用年度预算的十二分之一，按年看用全年，全部月份不比较。
    static func budgetFor(_ period: String?, budgets: [BudgetProgress]) -> [Int64: Double] {
        guard let period else { return [:] }
        let share = period.count == 4 ? 1 : 1.0 / 12
        var out: [Int64: Double] = [:]
        for row in budgets where row.planned != 0 {
            out[row.id] = round2(row.planned * share)
        }
        return out
    }

    /// 算日均用的天数：当月、当年只算到今天。
    static func days(_ period: String?, today: Date = .now) -> Int? {
        guard let period, let year = Int(period.prefix(4)) else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.dateComponents([.year, .month, .day], from: today)
        func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
            calendar.date(from: DateComponents(year: y, month: m, day: d)) ?? today
        }
        func span(_ start: Date, _ end: Date) -> Int {
            (calendar.dateComponents([.day], from: start, to: end).day ?? 0)
        }
        if period.count == 4 {
            let end = year == now.year ? date(year, now.month!, now.day!) : date(year, 12, 31)
            return span(date(year, 1, 1), end) + 1
        }
        let month = Int(period.suffix(2)) ?? 1
        if year == now.year, month == now.month { return now.day }
        let next = month == 12 ? date(year + 1, 1, 1) : date(year, month + 1, 1)
        return span(date(year, month, 1), next)
    }

    private static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}
