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
