import Foundation
import Testing
@testable import gxyFiApp

struct LedgerTests {
    @Test func savingsAndBudgetStayOnThisMachine() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "gxyfi-test-\(UUID().uuidString).db")
        let ledger = try Ledger(path: url.path(percentEncoded: false))
        let accountID = try ledger.saveAccount(
            AccountInput(name: "工资卡", institution: "本地银行", kind: "活期", currency: "CNY", note: ""),
            id: nil
        )
        try ledger.saveBalance(
            BalanceInput(accountID: accountID, asOfDate: "2026-10-31", balance: 1200.5, note: "月末"),
            id: nil
        )
        let summary = ledger.portfolioSummary(on: FiFormat.parseDay("2026-11-01")!)
        #expect(summary.savingsCNY == 1200.5)
        #expect(summary.accounts.count == 1)

        let category = try #require(ledger.categories().first { $0.name == "餐饮" })
        try ledger.saveExpense(
            ExpenseInput(categoryID: category.id, occurredOn: "2026-11-01", amount: 36, payee: "午饭", note: ""),
            id: nil
        )
        ledger.saveBudget(year: 2026, categoryID: category.id, amount: 1000, note: "")
        let progress = ledger.budgetProgress(year: 2026).first { $0.id == category.id }
        #expect(progress?.actual == 36)
        #expect(progress?.planned == 1000)

        let exported = url.deletingLastPathComponent().appending(path: "gxyfi-test.xlsx")
        try WorkbookExport.write(ledger: ledger, to: exported)
        let data = try Data(contentsOf: exported)
        #expect(data.starts(with: [0x50, 0x4B, 0x03, 0x04]))
    }

    @Test func manualPriceBeatsQuote() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "gxyfi-hold-\(UUID().uuidString).db")
        let ledger = try Ledger(path: url.path(percentEncoded: false))
        let prepared = try Market.prepare(HoldingInput(
            name: "", symbol: "au(t+d)", market: "GOLD", quantity: 10,
            currency: "USD", avgCost: 500, manualPrice: 600, accountLabel: "", note: ""
        ))
        #expect(prepared.symbol == "Au(T+D)")
        #expect(prepared.currency == "CNY")
        #expect(prepared.name == "Au(T+D)")
        _ = try ledger.saveHolding(prepared, id: nil)
        let valued = ledger.portfolioSummary().holdings.first
        #expect(valued?.price == 600)
        #expect(valued?.source == "手工")
        #expect(valued?.cny == 6000)
        #expect(valued?.costCny == 5000)
        #expect(valued?.ret == 0.2)
        #expect(valued?.weight == 1)
    }

    @Test func holdingTotalsSkipMissingCost() {
        func row(_ id: Int64, cny: Double?, cost: Double?) -> HoldingRecord {
            HoldingRecord(
                id: id, name: "", symbol: "", market: "US", quantity: 1, currency: "CNY", avgCost: cost,
                manualPrice: nil, accountLabel: "", note: "", price: nil, source: "", prevClose: nil, quotedAt: "",
                marketValue: cny, pnl: nil, cny: cny, pnlCny: nil, dayChange: nil, costCny: cost
            )
        }
        let totals = HoldingTotals([row(1, cny: 1200, cost: 1000), row(2, cny: 300, cost: nil), row(3, cny: nil, cost: 50)])
        #expect(totals.value == 1500)
        #expect(totals.cost == 1000)
        #expect(totals.pnl == 200)
        #expect(totals.ret == 0.2)
        #expect(totals.withoutCost == 1)
    }
}

struct SpendingTests {
    private func expense(_ day: String, _ categoryID: Int64, _ category: String, _ amount: Double) -> ExpenseRecord {
        ExpenseRecord(id: 0, categoryID: categoryID, category: category, occurredOn: day, amount: amount, payee: "", note: "")
    }

    private var rows: [ExpenseRecord] {
        [
            expense("2026-10-28", 2, "餐饮", 21.89),
            expense("2026-10-30", 2, "餐饮", 38.40),
            expense("2026-11-01", 21, "税费", 2657.80),
            expense("2026-11-01", 3, "交通", 100.00),
            expense("2026-11-01", 2, "餐饮", 20.54),
            expense("2026-11-02", 2, "餐饮", -5.00),
            expense("2026-11-02", 10, "其他", 10.00),
        ]
    }

    @Test func byCategoryNetsRefundsAndSorts() {
        let groups = Spending.byCategory(rows, period: "2026-11")
        #expect(groups.map(\.category) == ["税费", "交通", "餐饮", "其他"])
        let food = groups.first { $0.category == "餐饮" }
        #expect(food?.amount == 15.54)
        #expect(food?.count == 2)
        #expect(food?.refund == 5)
        #expect(abs(groups.reduce(0) { $0 + $1.share } - 1) < 1e-9)
        #expect(Spending.total(rows, period: "2026-11") == 2783.34)
        #expect(Spending.total(rows, period: nil) == 2843.63)
    }

    @Test func periods() {
        #expect(Spending.previousPeriod("2026-01") == "2025-12")
        #expect(Spending.previousPeriod("2026-11") == "2026-10")
        #expect(Spending.previousPeriod("2026") == "2025")
        #expect(Spending.previousPeriod(nil) == nil)
        #expect(Spending.periodLabel("2026-03") == "2026 年 3 月")
        let today = FiFormat.parseDay("2026-11-03")!
        #expect(Spending.days("2026-11", today: today) == 3)
        #expect(Spending.days("2026-02", today: today) == 28)
        #expect(Spending.days("2025", today: today) == 365)
    }

    @Test func monthlyStackMergesSmallCategories() {
        let stack = Spending.monthlyStack(rows, count: 3, top: 2, today: FiFormat.parseDay("2026-11-03")!)
        #expect(stack.keys == ["2026-09", "2026-10", "2026-11"])
        #expect(stack.names == ["税费", "交通", Spending.other])
        #expect(stack.cells["2026-10"] == [Spending.other: 60.29])
        #expect(stack.cells["2026-11"] == ["税费": 2657.8, "交通": 100.0, Spending.other: 25.54])
        #expect(stack.cells["2026-09"] == [:])
    }

    @Test func budgetForPeriod() {
        let budgets = [
            BudgetProgress(id: 2, category: "餐饮", planned: 1200, actual: 0, remain: 0, ratio: nil, note: ""),
            BudgetProgress(id: 3, category: "交通", planned: 0, actual: 0, remain: 0, ratio: nil, note: ""),
        ]
        #expect(Spending.budgetFor("2026-11", budgets: budgets) == [2: 100])
        #expect(Spending.budgetFor("2026", budgets: budgets) == [2: 1200])
        #expect(Spending.budgetFor(nil, budgets: budgets) == [:])
    }
}

struct FormatTests {
    @Test func amountsUseThousandsSeparators() {
        #expect(FiFormat.cny(1_234_567.891) == "¥1,234,567.89")
        #expect(FiFormat.money(0) == "0.00")
        #expect(FiFormat.money(-1200.5) == "-1,200.50")
        #expect(FiFormat.price(588.1200) == "588.12")
        #expect(FiFormat.price(12_345) == "12,345")
    }
}

struct MarketSymbolTests {
    @Test func recognizesShareCodes() throws {
        #expect(try Market.canonicalSymbol(market: "A", symbol: "600519") == "600519")
        #expect(try Market.canonicalSymbol(market: "A", symbol: "sz000001") == "000001")
        #expect(try Market.canonicalSymbol(market: "US", symbol: "brk.b") == "BRK-B")
        #expect(throws: LedgerError.self) {
            try Market.canonicalSymbol(market: "GOLD", symbol: "XAU")
        }
    }
}
