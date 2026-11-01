import Foundation
import SQLite3

struct FXQuote: Codable, Equatable {
    var rate: Double?
    var source: String
    var at: String
}

struct AccountInput {
    var name: String
    var institution: String
    var kind: String
    var currency: String
    var note: String
}

struct AccountRecord: Identifiable, Equatable {
    var id: Int64
    var name: String
    var institution: String
    var kind: String
    var currency: String
    var note: String
    var balance: Double?
    var asOfDate: String?
    var balanceNote: String
    var cny: Double?
    var age: Int?
}

struct BalanceInput {
    var accountID: Int64
    var asOfDate: String
    var balance: Double
    var note: String
}

struct BalanceRecord: Identifiable, Equatable {
    var id: Int64
    var accountID: Int64
    var asOfDate: String
    var balance: Double
    var note: String
}

struct HoldingInput {
    var name: String
    var symbol: String
    var market: String
    var quantity: Double
    var currency: String
    var avgCost: Double?
    var manualPrice: Double?
    var accountLabel: String
    var note: String
}

struct HoldingRecord: Identifiable, Equatable {
    var id: Int64
    var name: String
    var symbol: String
    var market: String
    var quantity: Double
    var currency: String
    var avgCost: Double?
    var manualPrice: Double?
    var accountLabel: String
    var note: String
    var price: Double?
    var source: String
    var prevClose: Double?
    var quotedAt: String
    var marketValue: Double?
    var pnl: Double?
    var cny: Double?
    var pnlCny: Double?
    var dayChange: Double?
}

struct QuoteRecord: Identifiable, Equatable {
    var market: String
    var symbol: String
    var name: String
    var price: Double?
    var prevClose: Double?
    var currency: String
    var quotedAt: String
    var source: String
    var fetchedAt: String
    var ok: Bool
    var message: String

    var id: String { "\(market)|\(symbol)" }
}

struct PropertyInput {
    var name: String
    var kind: String
    var city: String
    var address: String
    var areaSqm: Double?
    var acquiredOn: String?
    var purchasePrice: Double?
    var currentValue: Double?
    var valuedOn: String?
    var mortgageBalance: Double
    var monthlyRent: Double
    var note: String
}

struct PropertyRecord: Identifiable, Equatable {
    var id: Int64
    var name: String
    var kind: String
    var city: String
    var address: String
    var areaSqm: Double?
    var acquiredOn: String?
    var purchasePrice: Double?
    var currentValue: Double?
    var valuedOn: String?
    var mortgageBalance: Double
    var monthlyRent: Double
    var note: String
    var equity: Double?
}

struct CategoryRecord: Identifiable, Equatable {
    var id: Int64
    var name: String
}

struct ExpenseInput {
    var categoryID: Int64
    var occurredOn: String
    var amount: Double
    var payee: String
    var note: String
}

struct ExpenseRecord: Identifiable, Equatable {
    var id: Int64
    var categoryID: Int64
    var category: String
    var occurredOn: String
    var amount: Double
    var payee: String
    var note: String
}

struct BudgetProgress: Identifiable, Equatable {
    var id: Int64
    var category: String
    var planned: Double
    var actual: Double
    var remain: Double
    var ratio: Double?
    var note: String
}

struct BudgetLineRecord {
    var year: Int
    var category: String
    var amount: Double
    var note: String
}

struct BalanceExportRow {
    var accountName: String
    var institution: String
    var currency: String
    var asOfDate: String
    var balance: Double
    var note: String
}

struct MonthPoint: Identifiable, Equatable {
    var month: String
    var amount: Double
    var id: String { month }
}

struct PortfolioSummary: Equatable {
    var accounts: [AccountRecord]
    var savingsCNY: Double
    var savingsMissing: Bool
    var holdings: [HoldingRecord]
    var investCNY: Double
    var investMissing: Bool
    var unpriced: Int
    var properties: [PropertyRecord]
    var propertyEquityCNY: Double
    var propertyMissing: Bool
    var rentMonthly: Double
    var monthExpense: Double
    var yearExpense: Double
    var budgetTotal: Double
    var budgetRows: [BudgetProgress]
    var budgetRatio: Double?
    var monthlyExpenses: [MonthPoint]
    var staleAccounts: [AccountRecord]
    var fx: [String: FXQuote]
    var today: String

    var netCNY: Double { savingsCNY + investCNY + propertyEquityCNY }
}

private enum SQLValue {
    case null
    case int(Int64)
    case real(Double)
    case text(String)
}

private extension Dictionary where Key == String, Value == SQLValue {
    func text(_ key: String, default fallback: String = "") -> String {
        switch self[key] {
        case .text(let value): return value
        case .int(let value): return String(value)
        case .real(let value): return String(value)
        default: return fallback
        }
    }

    func int(_ key: String) -> Int64 {
        switch self[key] {
        case .int(let value): return value
        case .real(let value): return Int64(value)
        case .text(let value): return Int64(value) ?? 0
        default: return 0
        }
    }

    func real(_ key: String) -> Double? {
        switch self[key] {
        case .real(let value): return value
        case .int(let value): return Double(value)
        case .text(let value): return Double(value)
        default: return nil
        }
    }

    func optionalText(_ key: String) -> String? {
        let value = text(key)
        return value.isEmpty ? nil : value
    }
}

final class Ledger {
    nonisolated(unsafe) private var handle: OpaquePointer?
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static func defaultPath() -> String {
        if let override = ProcessInfo.processInfo.environment["GXYFI_DB"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            return override
        }
        let base = URL.applicationSupportDirectory.appending(path: "gxyFi", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appending(path: "gxyfi.db").path(percentEncoded: false)
    }

    init(path: String) throws {
        if sqlite3_open(path, &handle) != SQLITE_OK {
            throw LedgerError("无法打开账本")
        }
        try exec("PRAGMA foreign_keys = ON")
        try exec(Self.schema)
        let count = try rows("SELECT COUNT(*) AS n FROM expense_categories").first?.int("n") ?? 0
        if count == 0 {
            for (index, name) in LedgerKind.categories.enumerated() {
                try run("INSERT INTO expense_categories(name, sort_order) VALUES(?, ?)", [.text(name), .int(Int64(index))])
            }
        }
        if try rows("SELECT 1 FROM settings WHERE key='fx'").isEmpty {
            let blank = FXQuote(rate: nil, source: "未设置", at: "")
            let data = try JSONEncoder().encode(["USD": blank, "HKD": blank])
            try run("INSERT INTO settings(key, value) VALUES('fx', ?)", [.text(String(decoding: data, as: UTF8.self))])
        }
    }

    deinit {
        if handle != nil { sqlite3_close(handle) }
    }

    func setting(_ key: String) -> String? {
        (try? rows("SELECT value FROM settings WHERE key=?", [.text(key)]).first)?.text("value")
    }

    func setSetting(_ key: String, _ value: String) {
        try? run(
            "INSERT INTO settings(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            [.text(key), .text(value)]
        )
    }

    func fxRates() -> [String: FXQuote] {
        let raw = setting("fx") ?? ""
        let decoded = (try? JSONDecoder().decode([String: FXQuote].self, from: Data(raw.utf8))) ?? [:]
        var output: [String: FXQuote] = [:]
        for code in ["USD", "HKD"] {
            output[code] = decoded[code] ?? FXQuote(rate: nil, source: "未设置", at: "")
        }
        return output
    }

    func saveFX(_ updates: [String: FXQuote]) {
        var current = fxRates()
        for (code, item) in updates { current[code] = item }
        if let data = try? JSONEncoder().encode(current) {
            setSetting("fx", String(decoding: data, as: UTF8.self))
        }
    }

    func toCNY(_ amount: Double?, currency: String, rates: [String: FXQuote]? = nil) -> Double? {
        guard let amount else { return nil }
        if currency == "CNY" { return amount }
        let table = rates ?? fxRates()
        guard let rate = table[currency]?.rate else { return nil }
        return amount * rate
    }

    func accounts() -> [AccountRecord] {
        (try? rows("SELECT * FROM accounts ORDER BY id"))?.map(accountOnly) ?? []
    }

    func account(_ id: Int64) -> AccountRecord? {
        try? rows("SELECT * FROM accounts WHERE id=?", [.int(id)]).first.map(accountOnly)
    }

    @discardableResult
    func saveAccount(_ input: AccountInput, id: Int64?) throws -> Int64 {
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { throw LedgerError("请填写账户名称") }
        let fields: [SQLValue] = [
            .text(name),
            .text(input.institution.trimmingCharacters(in: .whitespacesAndNewlines)),
            .text(input.kind.isEmpty ? "活期" : input.kind),
            .text(input.currency.isEmpty ? "CNY" : input.currency),
            .text(input.note.trimmingCharacters(in: .whitespacesAndNewlines)),
        ]
        if let id {
            try run("UPDATE accounts SET name=?, institution=?, kind=?, currency=?, note=? WHERE id=?", fields + [.int(id)])
            return id
        }
        try run(
            "INSERT INTO accounts(name, institution, kind, currency, note, created_at) VALUES(?, ?, ?, ?, ?, ?)",
            fields + [.text(FiFormat.stamp())]
        )
        return sqlite3_last_insert_rowid(handle)
    }

    func deleteAccount(_ id: Int64) {
        try? run("DELETE FROM accounts WHERE id=?", [.int(id)])
    }

    func balances(accountID: Int64) -> [BalanceRecord] {
        (try? rows(
            "SELECT * FROM balance_entries WHERE account_id=? ORDER BY as_of_date DESC, id DESC",
            [.int(accountID)]
        ))?.map(balanceRow) ?? []
    }

    func saveBalance(_ input: BalanceInput, id: Int64?) throws {
        let balance = FiFormat.round2(input.balance) ?? input.balance
        let note = input.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id {
            do {
                try run(
                    "UPDATE balance_entries SET account_id=?, as_of_date=?, balance=?, note=? WHERE id=?",
                    [.int(input.accountID), .text(input.asOfDate), .real(balance), .text(note), .int(id)]
                )
            } catch {
                throw LedgerError("这个账户在这一天已经有一条余额")
            }
            return
        }
        try run(
            """
            INSERT INTO balance_entries(account_id, as_of_date, balance, note, created_at)
            VALUES(?, ?, ?, ?, ?)
            ON CONFLICT(account_id, as_of_date) DO UPDATE SET balance=excluded.balance, note=excluded.note
            """,
            [.int(input.accountID), .text(input.asOfDate), .real(balance), .text(note), .text(FiFormat.stamp())]
        )
    }

    func deleteBalance(_ id: Int64) {
        try? run("DELETE FROM balance_entries WHERE id=?", [.int(id)])
    }

    func allBalances() -> [BalanceExportRow] {
        (try? rows(
            """
            SELECT b.*, a.name AS account_name, a.currency, a.institution
            FROM balance_entries b JOIN accounts a ON a.id = b.account_id
            ORDER BY b.as_of_date, a.name
            """
        ))?.map {
            BalanceExportRow(
                accountName: $0.text("account_name"),
                institution: $0.text("institution"),
                currency: $0.text("currency"),
                asOfDate: $0.text("as_of_date"),
                balance: $0.real("balance") ?? 0,
                note: $0.text("note")
            )
        } ?? []
    }

    func holdings() -> [HoldingRecord] {
        (try? rows("SELECT * FROM holdings ORDER BY market, symbol, id"))?.map { holdingOnly($0) } ?? []
    }

    @discardableResult
    func saveHolding(_ input: HoldingInput, id: Int64?) throws -> Int64 {
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let symbol = input.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || symbol.isEmpty { throw LedgerError("请填写名称和代码") }
        guard let quantity = FiFormat.round4(input.quantity), quantity > 0 else {
            throw LedgerError("数量需要大于 0")
        }
        let fields: [SQLValue] = [
            .text(name), .text(symbol), .text(input.market), .real(quantity), .text(input.currency),
            input.avgCost.map { .real(FiFormat.round4($0) ?? $0) } ?? .null,
            input.manualPrice.map { .real(FiFormat.round4($0) ?? $0) } ?? .null,
            .text(input.accountLabel.trimmingCharacters(in: .whitespacesAndNewlines)),
            .text(input.note.trimmingCharacters(in: .whitespacesAndNewlines)),
        ]
        if let id {
            try run(
                """
                UPDATE holdings SET name=?, symbol=?, market=?, quantity=?, currency=?,
                avg_cost=?, manual_price=?, account_label=?, note=? WHERE id=?
                """,
                fields + [.int(id)]
            )
            return id
        }
        try run(
            """
            INSERT INTO holdings(name, symbol, market, quantity, currency, avg_cost, manual_price, account_label, note, created_at)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            fields + [.text(FiFormat.stamp())]
        )
        return sqlite3_last_insert_rowid(handle)
    }

    func deleteHolding(_ id: Int64) {
        try? run("DELETE FROM holdings WHERE id=?", [.int(id)])
    }

    func quotes() -> [QuoteRecord] {
        (try? rows("SELECT * FROM quotes ORDER BY market, symbol"))?.map(quoteRow) ?? []
    }

    func saveQuotes(_ quotes: [QuoteRecord]) {
        for quote in quotes {
            try? run(
                """
                INSERT INTO quotes(market, symbol, name, price, prev_close, currency, quoted_at, source, fetched_at, ok, message)
                VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(market, symbol) DO UPDATE SET
                    name=excluded.name, price=excluded.price, prev_close=excluded.prev_close,
                    currency=excluded.currency, quoted_at=excluded.quoted_at, source=excluded.source,
                    fetched_at=excluded.fetched_at, ok=excluded.ok, message=excluded.message
                """,
                [
                    .text(quote.market), .text(quote.symbol), .text(quote.name),
                    quote.price.map(SQLValue.real) ?? .null,
                    quote.prevClose.map(SQLValue.real) ?? .null,
                    .text(quote.currency), .text(quote.quotedAt), .text(quote.source),
                    .text(FiFormat.stamp()), .int(quote.ok ? 1 : 0), .text(quote.message),
                ]
            )
        }
    }

    func properties() -> [PropertyRecord] {
        (try? rows("SELECT * FROM properties ORDER BY id"))?.map { propertyRow($0, equity: nil) } ?? []
    }

    @discardableResult
    func saveProperty(_ input: PropertyInput, id: Int64?) throws -> Int64 {
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { throw LedgerError("请填写不动产名称") }
        var valuedOn = input.valuedOn
        let current = FiFormat.round2(input.currentValue)
        if current != nil, valuedOn == nil || valuedOn?.isEmpty == true {
            valuedOn = FiFormat.day(.now)
        }
        let fields: [SQLValue] = [
            .text(name), .text(input.kind.isEmpty ? "住宅" : input.kind),
            .text(input.city.trimmingCharacters(in: .whitespacesAndNewlines)),
            .text(input.address.trimmingCharacters(in: .whitespacesAndNewlines)),
            optionalReal(input.areaSqm), optionalText(input.acquiredOn), optionalReal(input.purchasePrice),
            optionalReal(current), optionalText(valuedOn),
            .real(FiFormat.round2(input.mortgageBalance) ?? 0),
            .real(FiFormat.round2(input.monthlyRent) ?? 0),
            .text(input.note.trimmingCharacters(in: .whitespacesAndNewlines)),
        ]
        if let id {
            try run(
                """
                UPDATE properties SET name=?, kind=?, city=?, address=?, area_sqm=?, acquired_on=?,
                purchase_price=?, current_value=?, valued_on=?, mortgage_balance=?, monthly_rent=?, note=?
                WHERE id=?
                """,
                fields + [.int(id)]
            )
            return id
        }
        try run(
            """
            INSERT INTO properties(name, kind, city, address, area_sqm, acquired_on, purchase_price,
            current_value, valued_on, mortgage_balance, monthly_rent, note, created_at)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            fields + [.text(FiFormat.stamp())]
        )
        return sqlite3_last_insert_rowid(handle)
    }

    func deleteProperty(_ id: Int64) {
        try? run("DELETE FROM properties WHERE id=?", [.int(id)])
    }

    func categories() -> [CategoryRecord] {
        (try? rows("SELECT * FROM expense_categories ORDER BY sort_order, id"))?.map {
            CategoryRecord(id: $0.int("id"), name: $0.text("name"))
        } ?? []
    }

    @discardableResult
    func saveCategory(_ name: String) throws -> Int64 {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { throw LedgerError("请填写类别名称") }
        let order = (try? rows("SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM expense_categories").first?.int("n")) ?? 0
        do {
            try run("INSERT INTO expense_categories(name, sort_order) VALUES(?, ?)", [.text(cleaned), .int(order)])
        } catch {
            throw LedgerError("这个类别已经存在")
        }
        return sqlite3_last_insert_rowid(handle)
    }

    func expenses() -> [ExpenseRecord] {
        (try? rows(
            """
            SELECT e.*, c.name AS category FROM expenses e
            JOIN expense_categories c ON c.id = e.category_id
            ORDER BY e.occurred_on DESC, e.id DESC
            """
        ))?.map {
            ExpenseRecord(
                id: $0.int("id"), categoryID: $0.int("category_id"), category: $0.text("category"),
                occurredOn: $0.text("occurred_on"), amount: $0.real("amount") ?? 0,
                payee: $0.text("payee"), note: $0.text("note")
            )
        } ?? []
    }

    func saveExpense(_ input: ExpenseInput, id: Int64?) throws {
        guard let amount = FiFormat.round2(input.amount), amount > 0 else {
            throw LedgerError("支出金额需要大于 0")
        }
        let fields: [SQLValue] = [
            .int(input.categoryID), .text(input.occurredOn), .real(amount),
            .text(input.payee.trimmingCharacters(in: .whitespacesAndNewlines)),
            .text(input.note.trimmingCharacters(in: .whitespacesAndNewlines)),
        ]
        if let id {
            try run("UPDATE expenses SET category_id=?, occurred_on=?, amount=?, payee=?, note=? WHERE id=?", fields + [.int(id)])
            return
        }
        try run(
            "INSERT INTO expenses(category_id, occurred_on, amount, payee, note, created_at) VALUES(?, ?, ?, ?, ?, ?)",
            fields + [.text(FiFormat.stamp())]
        )
    }

    func deleteExpense(_ id: Int64) {
        try? run("DELETE FROM expenses WHERE id=?", [.int(id)])
    }

    func budgetProgress(year: Int) -> [BudgetProgress] {
        let spentRows = (try? rows(
            "SELECT category_id, SUM(amount) AS amount FROM expenses WHERE occurred_on >= ? AND occurred_on < ? GROUP BY category_id",
            [.text("\(year)-01-01"), .text("\(year + 1)-01-01")]
        )) ?? []
        let spent = Dictionary(uniqueKeysWithValues: spentRows.map { ($0.int("category_id"), $0.real("amount") ?? 0) })
        let budgets = Dictionary(uniqueKeysWithValues: ((try? rows("SELECT * FROM budget_lines WHERE year=?", [.int(Int64(year))])) ?? []).map { ($0.int("category_id"), $0) })
        return categories().map { category in
            let planned = budgets[category.id]?.real("amount") ?? 0
            let actual = spent[category.id] ?? 0
            return BudgetProgress(
                id: category.id, category: category.name, planned: planned, actual: actual,
                remain: planned - actual, ratio: planned == 0 ? nil : actual / planned,
                note: budgets[category.id]?.text("note") ?? ""
            )
        }
    }

    func saveBudget(year: Int, categoryID: Int64, amount: Double, note: String) {
        try? run(
            """
            INSERT INTO budget_lines(year, category_id, amount, note) VALUES(?, ?, ?, ?)
            ON CONFLICT(year, category_id) DO UPDATE SET amount=excluded.amount, note=excluded.note
            """,
            [.int(Int64(year)), .int(categoryID), .real(FiFormat.round2(amount) ?? 0), .text(note.trimmingCharacters(in: .whitespacesAndNewlines))]
        )
    }

    @discardableResult
    func copyBudget(from sourceYear: Int, to targetYear: Int) throws -> Int {
        let source = (try? rows("SELECT * FROM budget_lines WHERE year=?", [.int(Int64(sourceYear))])) ?? []
        if source.isEmpty { throw LedgerError("\(sourceYear) 年还没有预算") }
        for row in source {
            saveBudget(year: targetYear, categoryID: row.int("category_id"), amount: row.real("amount") ?? 0, note: row.text("note"))
        }
        return source.count
    }

    func budgetLines() -> [BudgetLineRecord] {
        (try? rows(
            """
            SELECT b.*, c.name AS category FROM budget_lines b
            JOIN expense_categories c ON c.id = b.category_id
            ORDER BY b.year, c.sort_order
            """
        ))?.map {
            BudgetLineRecord(year: Int($0.int("year")), category: $0.text("category"), amount: $0.real("amount") ?? 0, note: $0.text("note"))
        } ?? []
    }

    func portfolioSummary(on today: Date = .now) -> PortfolioSummary {
        let rates = fxRates()
        let day = FiFormat.day(today)
        var accounts: [AccountRecord] = []
        var savings = 0.0
        var savingsMissing = false
        var stale: [AccountRecord] = []
        for account in self.accounts() {
            let latest = try? rows(
                "SELECT * FROM balance_entries WHERE account_id=? ORDER BY as_of_date DESC, id DESC LIMIT 1",
                [.int(account.id)]
            ).first
            var row = account
            row.balance = latest?.real("balance")
            row.asOfDate = latest?.optionalText("as_of_date")
            row.balanceNote = latest?.text("note") ?? ""
            row.cny = row.balance == nil ? nil : toCNY(row.balance, currency: row.currency, rates: rates)
            if row.balance != nil, row.cny == nil { savingsMissing = true }
            if let cny = row.cny { savings += cny }
            if let asOf = row.asOfDate, let start = FiFormat.parseDay(asOf) {
                let age = Calendar.current.dateComponents([.day], from: start, to: today).day ?? 0
                row.age = age
                if age > LedgerKind.staleDays { stale.append(row) }
            }
            accounts.append(row)
        }

        let quoteMap = Dictionary(uniqueKeysWithValues: quotes().map { ("\($0.market)|\($0.symbol)", $0) })
        var valued: [HoldingRecord] = []
        var invest = 0.0
        var investMissing = false
        for holding in holdings() {
            var row = holding
            let quote = quoteMap["\(holding.market)|\(holding.symbol)"]
            if let manual = holding.manualPrice {
                row.price = manual
                row.source = "手工"
                row.prevClose = quote?.prevClose
            } else if let quote, quote.ok, let price = quote.price {
                row.price = price
                row.source = quote.source
                row.prevClose = quote.prevClose
                row.quotedAt = quote.quotedAt
            } else {
                row.price = nil
                row.source = quote?.message.isEmpty == false ? (quote?.message ?? "") : (quote == nil ? "" : "未取得行情")
            }
            if let price = row.price {
                row.marketValue = price * holding.quantity
                if let cost = holding.avgCost {
                    row.pnl = row.marketValue! - cost * holding.quantity
                }
            }
            row.cny = row.marketValue == nil ? nil : toCNY(row.marketValue, currency: holding.currency, rates: rates)
            row.pnlCny = row.pnl == nil ? nil : toCNY(row.pnl, currency: holding.currency, rates: rates)
            if row.marketValue != nil, row.cny == nil { investMissing = true }
            if let cny = row.cny { invest += cny }
            if let price = row.price, let prev = row.prevClose, prev != 0 {
                row.dayChange = (price - prev) / prev
            }
            valued.append(row)
        }

        var properties: [PropertyRecord] = []
        var equityTotal = 0.0
        var rentTotal = 0.0
        var propertyMissing = false
        for item in self.properties() {
            var row = item
            if let current = item.currentValue {
                row.equity = current - item.mortgageBalance
                equityTotal += row.equity ?? 0
            } else {
                propertyMissing = true
            }
            rentTotal += item.monthlyRent
            properties.append(row)
        }

        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? today
        let year = calendar.component(.year, from: today)
        let budgets = budgetProgress(year: year)
        let planned = budgets.reduce(0) { $0 + $1.planned }
        let yearExpense = expenseTotal(start: "\(year)-01-01", end: "\(year + 1)-01-01")
        return PortfolioSummary(
            accounts: accounts, savingsCNY: savings, savingsMissing: savingsMissing,
            holdings: valued, investCNY: invest, investMissing: investMissing,
            unpriced: valued.filter { $0.price == nil }.count,
            properties: properties, propertyEquityCNY: equityTotal, propertyMissing: propertyMissing,
            rentMonthly: rentTotal,
            monthExpense: expenseTotal(start: FiFormat.day(monthStart), end: FiFormat.day(monthEnd)),
            yearExpense: yearExpense, budgetTotal: planned, budgetRows: budgets,
            budgetRatio: planned == 0 ? nil : yearExpense / planned,
            monthlyExpenses: monthlyExpenses(count: 6, today: today),
            staleAccounts: stale, fx: rates, today: day
        )
    }

    private func expenseTotal(start: String, end: String) -> Double {
        (try? rows(
            "SELECT COALESCE(SUM(amount), 0) AS amount FROM expenses WHERE occurred_on>=? AND occurred_on<?",
            [.text(start), .text(end)]
        ).first?.real("amount")) ?? 0
    }

    private func monthlyExpenses(count: Int, today: Date) -> [MonthPoint] {
        let calendar = Calendar.current
        var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        var points: [MonthPoint] = []
        for _ in 0..<count {
            let end = calendar.date(byAdding: .month, value: 1, to: cursor) ?? cursor
            let key = String(FiFormat.day(cursor).prefix(7))
            points.append(MonthPoint(month: key, amount: expenseTotal(start: FiFormat.day(cursor), end: FiFormat.day(end))))
            cursor = calendar.date(byAdding: .month, value: -1, to: cursor) ?? cursor
        }
        return points.reversed()
    }

    private func accountOnly(_ row: [String: SQLValue]) -> AccountRecord {
        AccountRecord(
            id: row.int("id"), name: row.text("name"), institution: row.text("institution"),
            kind: row.text("kind"), currency: row.text("currency"), note: row.text("note"),
            balance: nil, asOfDate: nil, balanceNote: "", cny: nil, age: nil
        )
    }

    private func balanceRow(_ row: [String: SQLValue]) -> BalanceRecord {
        BalanceRecord(
            id: row.int("id"), accountID: row.int("account_id"), asOfDate: row.text("as_of_date"),
            balance: row.real("balance") ?? 0, note: row.text("note")
        )
    }

    private func holdingOnly(_ row: [String: SQLValue]) -> HoldingRecord {
        HoldingRecord(
            id: row.int("id"), name: row.text("name"), symbol: row.text("symbol"), market: row.text("market"),
            quantity: row.real("quantity") ?? 0, currency: row.text("currency"), avgCost: row.real("avg_cost"),
            manualPrice: row.real("manual_price"), accountLabel: row.text("account_label"), note: row.text("note"),
            price: nil, source: "", prevClose: nil, quotedAt: "", marketValue: nil, pnl: nil, cny: nil, pnlCny: nil, dayChange: nil
        )
    }

    private func quoteRow(_ row: [String: SQLValue]) -> QuoteRecord {
        QuoteRecord(
            market: row.text("market"), symbol: row.text("symbol"), name: row.text("name"),
            price: row.real("price"), prevClose: row.real("prev_close"), currency: row.text("currency"),
            quotedAt: row.text("quoted_at"), source: row.text("source"), fetchedAt: row.text("fetched_at"),
            ok: row.int("ok") != 0, message: row.text("message")
        )
    }

    private func propertyRow(_ row: [String: SQLValue], equity: Double?) -> PropertyRecord {
        PropertyRecord(
            id: row.int("id"), name: row.text("name"), kind: row.text("kind"), city: row.text("city"),
            address: row.text("address"), areaSqm: row.real("area_sqm"), acquiredOn: row.optionalText("acquired_on"),
            purchasePrice: row.real("purchase_price"), currentValue: row.real("current_value"),
            valuedOn: row.optionalText("valued_on"), mortgageBalance: row.real("mortgage_balance") ?? 0,
            monthlyRent: row.real("monthly_rent") ?? 0, note: row.text("note"), equity: equity
        )
    }

    private func optionalReal(_ value: Double?) -> SQLValue {
        guard let value else { return .null }
        return .real(FiFormat.round2(value) ?? value)
    }

    private func optionalText(_ value: String?) -> SQLValue {
        guard let value, !value.isEmpty else { return .null }
        return .text(value)
    }

    private func rows(_ sql: String, _ args: [SQLValue] = []) throws -> [[String: SQLValue]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw LedgerError(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        try bind(statement, args)
        var result: [[String: SQLValue]] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_ROW {
                var row: [String: SQLValue] = [:]
                let count = sqlite3_column_count(statement)
                for index in 0..<count {
                    let name = String(cString: sqlite3_column_name(statement, index))
                    row[name] = column(statement, index)
                }
                result.append(row)
            } else if code == SQLITE_DONE {
                return result
            } else {
                throw LedgerError(String(cString: sqlite3_errmsg(handle)))
            }
        }
    }

    private func run(_ sql: String, _ args: [SQLValue] = []) throws {
        _ = try rows(sql, args)
    }

    private func exec(_ sql: String) throws {
        if sqlite3_exec(handle, sql, nil, nil, nil) != SQLITE_OK {
            throw LedgerError(String(cString: sqlite3_errmsg(handle)))
        }
    }

    private func bind(_ statement: OpaquePointer?, _ args: [SQLValue]) throws {
        for (offset, value) in args.enumerated() {
            let index = Int32(offset + 1)
            let code: Int32
            switch value {
            case .null:
                code = sqlite3_bind_null(statement, index)
            case .int(let number):
                code = sqlite3_bind_int64(statement, index, number)
            case .real(let number):
                code = sqlite3_bind_double(statement, index, number)
            case .text(let text):
                code = text.withCString { sqlite3_bind_text(statement, index, $0, -1, sqliteTransient) }
            }
            if code != SQLITE_OK { throw LedgerError(String(cString: sqlite3_errmsg(handle))) }
        }
    }

    private func column(_ statement: OpaquePointer?, _ index: Int32) -> SQLValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .int(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            guard let pointer = sqlite3_column_text(statement, index) else { return .null }
            return .text(String(cString: pointer))
        default:
            return .null
        }
    }

    private static let schema = """
    CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS accounts (
        id INTEGER PRIMARY KEY, name TEXT NOT NULL, institution TEXT NOT NULL DEFAULT '',
        kind TEXT NOT NULL DEFAULT '活期', currency TEXT NOT NULL DEFAULT 'CNY',
        note TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS balance_entries (
        id INTEGER PRIMARY KEY, account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        as_of_date TEXT NOT NULL, balance REAL NOT NULL, note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL, UNIQUE (account_id, as_of_date));
    CREATE TABLE IF NOT EXISTS holdings (
        id INTEGER PRIMARY KEY, name TEXT NOT NULL, symbol TEXT NOT NULL, market TEXT NOT NULL,
        quantity REAL NOT NULL, currency TEXT NOT NULL, avg_cost REAL, manual_price REAL,
        account_label TEXT NOT NULL DEFAULT '', note TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS quotes (
        market TEXT NOT NULL, symbol TEXT NOT NULL, name TEXT NOT NULL DEFAULT '', price REAL,
        prev_close REAL, currency TEXT NOT NULL DEFAULT '', quoted_at TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL DEFAULT '', fetched_at TEXT NOT NULL, ok INTEGER NOT NULL,
        message TEXT NOT NULL DEFAULT '', PRIMARY KEY (market, symbol));
    CREATE TABLE IF NOT EXISTS properties (
        id INTEGER PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL DEFAULT '住宅',
        city TEXT NOT NULL DEFAULT '', address TEXT NOT NULL DEFAULT '', area_sqm REAL,
        acquired_on TEXT, purchase_price REAL, current_value REAL, valued_on TEXT,
        mortgage_balance REAL NOT NULL DEFAULT 0, monthly_rent REAL NOT NULL DEFAULT 0,
        note TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS expense_categories (
        id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE, sort_order INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS expenses (
        id INTEGER PRIMARY KEY, category_id INTEGER NOT NULL REFERENCES expense_categories(id),
        occurred_on TEXT NOT NULL, amount REAL NOT NULL, payee TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS budget_lines (
        id INTEGER PRIMARY KEY, year INTEGER NOT NULL, category_id INTEGER NOT NULL REFERENCES expense_categories(id),
        amount REAL NOT NULL, note TEXT NOT NULL DEFAULT '', UNIQUE (year, category_id));
    """
}
