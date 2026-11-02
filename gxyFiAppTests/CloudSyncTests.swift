import Foundation
import Testing
@testable import gxyFiApp

struct CloudMirrorTests {
    @Test func mirrorKeepsServerIDsAndTotals() throws {
        let ledger = try Ledger(path: FileManager.default.temporaryDirectory.appending(path: "gxyfi-mirror-\(UUID().uuidString).db").path(percentEncoded: false))
        let state: CloudState = [
            "categories": [["id": 41, "name": "餐饮", "sort_order": 0], ["id": 42, "name": "交通", "sort_order": 1]],
            "accounts": [["id": 7, "name": "工资卡", "institution": "", "kind": "活期", "currency": "CNY", "note": "", "created_at": "2026-11-01 08:00:00"]],
            "balances": [["id": 9, "account_id": 7, "as_of_date": "2026-10-31", "balance": 1200.5, "note": "", "created_at": "2026-11-01 08:00:00"]],
            "holdings": [],
            "quotes": [],
            "properties": [],
            "expenses": [["id": 3, "category_id": 41, "occurred_on": "2026-11-01", "amount": 36, "payee": "午饭", "note": "", "created_at": "2026-11-01 12:00:00"]],
            "budgets": [["id": 1, "year": 2026, "category_id": 41, "amount": 1000, "note": ""]],
            "fx": [["code": "USD", "rate": 7.1, "source": "Yahoo", "quoted_at": "2026-11-01"]],
        ]
        try ledger.mirror(state)
        let summary = ledger.portfolioSummary(on: FiFormat.parseDay("2026-11-01")!)
        #expect(summary.accounts.map(\.id) == [7])
        #expect(summary.savingsCNY == 1200.5)
        #expect(ledger.expenses().first?.categoryID == 41)
        #expect(ledger.budgetProgress(year: 2026).first { $0.id == 41 }?.planned == 1000)
        #expect(ledger.fxRates()["USD"]?.rate == 7.1)

        try ledger.mirror(["categories": [["id": 41, "name": "餐饮", "sort_order": 0]]])
        #expect(ledger.recordCount() == 0)
    }

    @Test func serverAddressNeedsHTTPS() throws {
        #expect(try CloudClient.serverURL("fi.example.com/app?x=1").absoluteString == "https://fi.example.com")
        #expect(try CloudClient.serverURL("http://127.0.0.1:8787/").absoluteString == "http://127.0.0.1:8787")
        #expect(throws: CloudError.self) { try CloudClient.serverURL("http://fi.example.com") }
    }
}

/// Runs against a real gxyFi-web Worker when TEST_RUNNER_GXYFI_TEST_SERVER is set (with GXYFI_TEST_USER / GXYFI_TEST_PASSWORD).
struct CloudServerTests {
    static let server = ProcessInfo.processInfo.environment["GXYFI_TEST_SERVER"] ?? ""

    @Test(.enabled(if: !server.isEmpty)) func phoneRecordsReachTheWebAccount() async throws {
        let env = ProcessInfo.processInfo.environment
        let ledger = try Ledger(path: FileManager.default.temporaryDirectory.appending(path: "gxyfi-cloud-\(UUID().uuidString).db").path(percentEncoded: false))
        let tag = String(UUID().uuidString.prefix(6))
        let accountID = try ledger.saveAccount(AccountInput(name: "手机卡\(tag)", institution: "", kind: "活期", currency: "CNY", note: ""), id: nil)
        try ledger.saveBalance(BalanceInput(accountID: accountID, asOfDate: "2026-11-01", balance: 888.8, note: ""), id: nil)
        let food = try #require(ledger.categories().first { $0.name == "餐饮" })
        try ledger.saveExpense(ExpenseInput(categoryID: food.id, occurredOn: "2026-11-01", amount: 23.5, payee: "早餐\(tag)", note: ""), id: nil)

        let model = AppModel(ledger: ledger)
        try await model.connect(
            server: Self.server, username: env["GXYFI_TEST_USER"] ?? "", password: env["GXYFI_TEST_PASSWORD"] ?? "", upload: true
        )
        #expect(model.isCloud)

        let web = CloudClient(base: try CloudClient.serverURL(Self.server))
        try await web.login(username: env["GXYFI_TEST_USER"] ?? "", password: env["GXYFI_TEST_PASSWORD"] ?? "")
        var state = try await web.state()
        let accounts = state["accounts"] as? [[String: Any]] ?? []
        let account = try #require(accounts.first { ($0["name"] as? String) == "手机卡\(tag)" })
        let balances = state["balances"] as? [[String: Any]] ?? []
        #expect(balances.contains { ($0["account_id"] as? NSNumber) == (account["id"] as? NSNumber) && ($0["balance"] as? NSNumber)?.doubleValue == 888.8 })
        let expenses = state["expenses"] as? [[String: Any]] ?? []
        #expect(expenses.contains { ($0["payee"] as? String) == "早餐\(tag)" && ($0["category"] as? String) == "餐饮" })

        let traffic = try #require(ledger.categories().first { $0.name == "交通" })
        model.saveExpense(ExpenseInput(categoryID: traffic.id, occurredOn: "2026-11-02", amount: 4, payee: "地铁\(tag)", note: ""), id: nil)
        for _ in 0..<50 where model.syncing { try await Task.sleep(for: .milliseconds(100)) }
        #expect(model.alert == nil)
        state = try await web.state()
        #expect((state["expenses"] as? [[String: Any]] ?? []).contains { ($0["payee"] as? String) == "地铁\(tag)" })
        #expect(ledger.expenses().contains { $0.payee == "地铁\(tag)" })

        await model.disconnect()
        #expect(!model.isCloud)
        #expect(ledger.recordCount() == 0)
    }
}
