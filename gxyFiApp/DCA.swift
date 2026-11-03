import Foundation

/// 基金定投：先建计划，再记每一期确认。份额和成本由确认记录推算，规则与电脑端、网页端一致。
struct DCAPlanInput {
    var name: String
    var symbol: String
    var amount: Double
    var cycle: String
    var debitDay: Int
    var status: String
    var startedOn: String?
    var manualNav: Double?
    var note: String
}

struct DCARecordInput {
    var kind: String
    var tradeDate: String
    var amount: Double?
    var nav: Double?
    var shares: Double?
    var fee: Double?
    var note: String
}

struct DCAPlanRecord: Identifiable, Equatable {
    var id: Int64
    var name: String
    var symbol: String
    var amount: Double
    var cycle: String
    var debitDay: Int
    var status: String
    var startedOn: String?
    var manualNav: Double?
    var note: String
    var shares: Double = 0
    var cost: Double = 0
    var nav: Double? = nil
    var navSource: String = ""
    var marketValue: Double? = nil
    var pnl: Double? = nil
    var recordCount: Int = 0

    var cycleLabel: String { DCA.cycleLabel(cycle, debitDay) }
}

struct DCARecord: Identifiable, Equatable {
    var id: Int64
    var planID: Int64
    var kind: String
    var tradeDate: String
    var amount: Double
    var nav: Double?
    var shares: Double
    var fee: Double
    var note: String
}

enum DCA {
    static let cycles = ["每月", "每周", "每两周"]
    static let statuses = ["进行中", "已暂停", "已结束"]
    static let kinds = ["期初", "定投", "赎回", "红利再投"]
    static let weekdays = ["", "周一", "周二", "周三", "周四", "周五"]

    static let kindHints = [
        "期初": "期初只记当前份额和总成本。之后的明细不要再把这段份额记一遍。",
        "定投": "扣款金额按实际扣款填写。确认份额可留空，按（扣款金额 − 手续费）÷ 确认净值计算。",
        "赎回": "赎回按份额减少持仓，成本按当时的平均成本等比例扣减。到账金额只留作记录。",
        "红利再投": "红利再投增加份额，不增加成本。",
    ]

    static let amountHints = ["期初": "总成本", "定投": "扣款金额", "赎回": "到账金额，可留空", "红利再投": "红利金额，可留空"]

    static func cycleLabel(_ cycle: String, _ debitDay: Int) -> String {
        if cycle == "每月" { return "每月 \(debitDay) 日" }
        if (1...5).contains(debitDay) { return "\(cycle) \(weekdays[debitDay])" }
        return "\(cycle) \(debitDay)"
    }

    static func normalizeSymbol(_ raw: String) throws -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...6).contains(text.count), text.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw LedgerError("基金代码是 6 位数字")
        }
        return String(repeating: "0", count: 6 - text.count) + text
    }

    static func preparePlan(_ input: DCAPlanInput) throws -> DCAPlanInput {
        var plan = input
        plan.name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if plan.name.isEmpty { throw LedgerError("请填写基金名称") }
        plan.symbol = try normalizeSymbol(input.symbol)
        if input.amount <= 0 { throw LedgerError("每期金额需要大于 0") }
        plan.amount = round2(input.amount)
        guard cycles.contains(input.cycle) else { throw LedgerError("扣款周期不正确") }
        let limit = input.cycle == "每月" ? 28 : 5
        guard (1...limit).contains(input.debitDay) else { throw LedgerError("扣款日不在可选范围内") }
        guard statuses.contains(input.status) else { throw LedgerError("状态不正确") }
        if let started = input.startedOn?.trimmingCharacters(in: .whitespaces), !started.isEmpty {
            guard FiFormat.parseDay(started) != nil, started.count == 10 else { throw LedgerError("开始日期请写成 YYYY-MM-DD") }
            plan.startedOn = started
        } else {
            plan.startedOn = nil
        }
        if let nav = input.manualNav {
            if nav <= 0 { throw LedgerError("最新净值需要大于 0") }
            plan.manualNav = round4(nav)
        }
        plan.note = input.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return plan
    }

    /// 定投没填份额时按（扣款金额 − 手续费）÷ 确认净值推算。
    static func normalizeRecord(_ input: DCARecordInput) throws -> DCARecordInput {
        guard kinds.contains(input.kind) else { throw LedgerError("类型只能是期初、定投、赎回或红利再投") }
        guard input.tradeDate.count == 10, FiFormat.parseDay(input.tradeDate) != nil else { throw LedgerError("确认日期请写成 YYYY-MM-DD") }
        let amount = input.amount ?? 0
        let fee = input.fee ?? 0
        if amount < 0 || fee < 0 { throw LedgerError("金额和手续费不能为负数") }
        if let nav = input.nav, nav <= 0 { throw LedgerError("确认净值需要大于 0") }
        var shares = input.shares
        if input.kind == "定投" {
            if amount <= 0 { throw LedgerError("定投需要填写扣款金额") }
            if shares == nil {
                guard let nav = input.nav else { throw LedgerError("请填写确认份额，或同时填写确认净值") }
                let net = amount - fee
                if net <= 0 { throw LedgerError("扣款金额需要大于手续费") }
                shares = net / nav
            }
        } else if (shares ?? 0) <= 0 {
            throw LedgerError("份额需要大于 0")
        }
        guard let shares, shares > 0 else { throw LedgerError("份额需要大于 0") }
        return DCARecordInput(
            kind: input.kind, tradeDate: input.tradeDate, amount: round2(amount),
            nav: input.nav.map(round4), shares: round4(shares), fee: round2(fee),
            note: input.note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// 按日期顺序推算持有份额和成本；赎回超过当时份额会报错。
    @discardableResult
    static func applyPosition(_ records: [DCARecord]) throws -> (shares: Double, cost: Double) {
        let ordered = records.sorted { $0.tradeDate != $1.tradeDate ? $0.tradeDate < $1.tradeDate : $0.id < $1.id }
        var shares = 0.0
        var cost = 0.0
        for row in ordered {
            switch row.kind {
            case "期初", "定投":
                shares += row.shares
                cost += row.amount
            case "赎回":
                if row.shares - shares > 0.0001 { throw LedgerError("\(row.tradeDate) 的赎回份额超过当时持有份额") }
                if shares <= 0 { throw LedgerError("\(row.tradeDate) 赎回时还没有持有份额") }
                let used = min(row.shares, shares)
                cost -= cost * (used / shares)
                shares -= used
            case "红利再投":
                shares += row.shares
            default:
                break
            }
            if shares <= 0.0001 {
                shares = 0
                cost = 0
            } else if cost < 0 {
                cost = 0
            }
        }
        return (round4(shares), round2(cost))
    }

    static func latestNav(manual: Double?, records: [DCARecord]) -> (nav: Double?, source: String) {
        if let manual { return (manual, "手工") }
        let dated = records.filter { $0.nav != nil }
        guard let last = dated.max(by: { $0.tradeDate != $1.tradeDate ? $0.tradeDate < $1.tradeDate : $0.id < $1.id }) else {
            return (nil, "")
        }
        return (last.nav, "最近确认")
    }

    static func value(_ plan: DCAPlanRecord, records: [DCARecord]) -> DCAPlanRecord {
        var row = plan
        let position = (try? applyPosition(records)) ?? (shares: 0, cost: 0)
        let priced = latestNav(manual: plan.manualNav, records: records)
        row.shares = position.shares
        row.cost = position.cost
        row.nav = priced.nav
        row.navSource = priced.source
        row.marketValue = priced.nav.flatMap { position.shares > 0 ? round2(position.shares * $0) : nil }
        row.pnl = row.marketValue.map { round2($0 - position.cost) }
        row.recordCount = records.count
        return row
    }

    static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }
    static func round4(_ value: Double) -> Double { (value * 10_000).rounded() / 10_000 }
}
