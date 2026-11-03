import Foundation
import Testing
@testable import gxyFiApp

struct DCATests {
    private func record(_ id: Int64, _ input: DCARecordInput) throws -> DCARecord {
        let row = try DCA.normalizeRecord(input)
        return DCARecord(id: id, planID: 7, kind: row.kind, tradeDate: row.tradeDate, amount: row.amount ?? 0, nav: row.nav, shares: row.shares ?? 0, fee: row.fee ?? 0, note: row.note)
    }

    @Test func fundSymbolKeepsLeadingZeros() throws {
        #expect(try DCA.normalizeSymbol("20") == "000020")
        #expect(throws: LedgerError.self) { try DCA.normalizeSymbol("AB1234") }
    }

    @Test func installmentsRedemptionAndDividend() throws {
        let opening = try record(1, DCARecordInput(kind: "期初", tradeDate: "2026-01-01", amount: 100, nav: 1, shares: 100, fee: nil, note: ""))
        let buy = try record(2, DCARecordInput(kind: "定投", tradeDate: "2026-02-08", amount: 200, nav: 2, shares: nil, fee: nil, note: ""))
        #expect(buy.shares == 100)
        let sell = try record(3, DCARecordInput(kind: "赎回", tradeDate: "2026-03-01", amount: 160, nav: 1.6, shares: 100, fee: nil, note: ""))
        let dividend = try record(4, DCARecordInput(kind: "红利再投", tradeDate: "2026-03-15", amount: 10, nav: 1.5, shares: 10, fee: nil, note: ""))
        let position = try DCA.applyPosition([opening, buy, sell, dividend])
        #expect(position.shares == 110)
        #expect(position.cost == 150)
        let plan = DCAPlanRecord(id: 7, name: "沪深300", symbol: "000300", amount: 200, cycle: "每月", debitDay: 8, status: "进行中", startedOn: nil, manualNav: nil, note: "")
        let valued = DCA.value(plan, records: [opening, buy, sell, dividend])
        #expect(valued.marketValue == 165)
        #expect(valued.pnl == 15)
        #expect(valued.navSource == "最近确认")
        #expect(valued.cycleLabel == "每月 8 日")
    }

    @Test func redemptionCannotExceedShares() throws {
        let opening = try record(1, DCARecordInput(kind: "期初", tradeDate: "2026-01-01", amount: 100, nav: nil, shares: 100, fee: nil, note: ""))
        let sell = try record(2, DCARecordInput(kind: "赎回", tradeDate: "2026-02-01", amount: nil, nav: nil, shares: 150, fee: nil, note: ""))
        #expect(throws: LedgerError.self) { try DCA.applyPosition([opening, sell]) }
        #expect(throws: LedgerError.self) {
            try DCA.normalizeRecord(DCARecordInput(kind: "定投", tradeDate: "2026-02-01", amount: 100, nav: nil, shares: nil, fee: nil, note: ""))
        }
    }

    @Test func plansCountTowardInvestmentAndMirror() throws {
        let ledger = try Ledger(path: FileManager.default.temporaryDirectory.appending(path: "gxyfi-dca-\(UUID().uuidString).db").path(percentEncoded: false))
        let planID = try ledger.saveDCAPlan(
            DCAPlanInput(name: "沪深300联接", symbol: "300", amount: 500, cycle: "每月", debitDay: 8, status: "进行中", startedOn: nil, manualNav: nil, note: ""),
            id: nil
        )
        try ledger.saveDCARecord(DCARecordInput(kind: "期初", tradeDate: "2026-10-01", amount: 1000, nav: 1, shares: 1000, fee: nil, note: ""), planID: planID, id: nil)
        try ledger.saveDCARecord(DCARecordInput(kind: "定投", tradeDate: "2026-10-08", amount: 500, nav: 1.25, shares: nil, fee: nil, note: ""), planID: planID, id: nil)
        #expect(throws: LedgerError.self) {
            try ledger.saveDCARecord(DCARecordInput(kind: "赎回", tradeDate: "2026-09-01", amount: nil, nav: nil, shares: 10, fee: nil, note: ""), planID: planID, id: nil)
        }
        var summary = ledger.portfolioSummary()
        #expect(summary.dcaPlans.first?.symbol == "000300")
        #expect(summary.dcaPlans.first?.shares == 1400)
        #expect(summary.investCNY == 1750)
        #expect(ledger.recordCount() == 3)

        try ledger.mirror([
            "categories": [["id": 41, "name": "餐饮", "sort_order": 0]],
            "dcaPlans": [["id": 12, "name": "中证500", "symbol": "000510", "amount": 300, "cycle": "每周", "debit_day": 2, "status": "进行中", "started_on": NSNull(), "manual_nav": 1.5, "note": "", "created_at": "2026-11-01 08:00:00"]],
            "dcaRecords": [["id": 30, "plan_id": 12, "kind": "期初", "trade_date": "2026-10-01", "amount": 900, "nav": NSNull(), "shares": 1000, "fee": 0, "note": "", "created_at": "2026-11-01 08:00:00"]],
        ])
        summary = ledger.portfolioSummary()
        #expect(summary.dcaPlans.map(\.id) == [12])
        #expect(summary.dcaPlans.first?.cycleLabel == "每周 周二")
        #expect(summary.dcaPlans.first?.marketValue == 1500)
        #expect(summary.dcaPlans.first?.navSource == "手工")
        #expect(summary.investCNY == 1500)
    }
}
