import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct ExcelDocument: FileDocument {
    static var readableContentTypes: [UTType] { [FiFile.xlsx] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@Observable
final class AppModel {
    let ledger: Ledger
    var page = 0
    var summary: PortfolioSummary
    var quotes: [QuoteRecord]
    var expenses: [ExpenseRecord]
    var categories: [CategoryRecord]
    var dcaRecords: [DCARecord]
    var balances: [BalanceRecord]
    var status = "行情只用于估值，有延迟，不构成投资建议"
    var refreshing = false
    var alert: String?
    var selectedAccountID: Int64?
    var showExport = false
    var exportDocument: ExcelDocument?
    var exportName = "gxyFi.xlsx"
    var revision = 0

    var cloudServer: String
    var cloudUser: String?
    var cloudExpired = false
    var syncing = false
    var lastSync = ""
    private var client: CloudClient?

    private static let tokenKey = "session"

    init(ledger: Ledger) {
        self.ledger = ledger
        summary = ledger.portfolioSummary()
        quotes = ledger.quotes()
        expenses = ledger.expenses()
        categories = ledger.categories()
        dcaRecords = ledger.dcaRecords()
        balances = []
        cloudServer = ledger.setting("cloud_server") ?? ""
        selectedAccountID = summary.accounts.first?.id
        reloadBalances()
        if let user = ledger.setting("cloud_user"), !user.isEmpty,
           let url = try? CloudClient.serverURL(cloudServer),
           let token = Keychain.read(Self.tokenKey) {
            cloudUser = user
            client = CloudClient(base: url, token: token)
        }
    }

    static func live() -> AppModel {
        let ledger = (try? Ledger(path: Ledger.defaultPath())) ?? {
            let fallback = FileManager.default.temporaryDirectory.appending(path: "gxyfi-fallback.db").path(percentEncoded: false)
            return try! Ledger(path: fallback)
        }()
        return AppModel(ledger: ledger)
    }

    var isCloud: Bool { client != nil }

    var storageLabel: String {
        guard let cloudUser else { return "账本只在这台手机。登录网页账号后，手机和网页用同一本账。" }
        if cloudExpired { return "网页账号 \(cloudUser) 登录已过期，现在看到的是上次同步的内容。" }
        return "已连接网页账号 \(cloudUser)，在手机上记的账会直接存到网页端。"
    }

    var fxLabel: String {
        guard let usd = summary.fx["USD"], let rate = usd.rate else {
            return "美元汇率未设置 · 外币持仓暂不折合人民币"
        }
        return String(format: "USD/CNY %.4f · %@", rate, usd.source)
    }

    func reload() {
        summary = ledger.portfolioSummary()
        quotes = ledger.quotes()
        expenses = ledger.expenses()
        categories = ledger.categories()
        dcaRecords = ledger.dcaRecords()
        if let id = selectedAccountID, !summary.accounts.contains(where: { $0.id == id }) { selectedAccountID = nil }
        if selectedAccountID == nil { selectedAccountID = summary.accounts.first?.id }
        reloadBalances()
        revision += 1
    }

    func reloadBalances() {
        balances = selectedAccountID.map { ledger.balances(accountID: $0) } ?? []
    }

    func perform(_ work: () throws -> Void) {
        do {
            try work()
            reload()
        } catch {
            alert = error.localizedDescription
        }
    }

    // MARK: - Web account

    /// Signs in, then either uploads the phone's records or replaces them with the web account's.
    func connect(server: String, username: String, password: String, upload: Bool) async throws {
        let url = try CloudClient.serverURL(server)
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || password.isEmpty { throw CloudError(message: "请填写用户名和密码") }
        let next = CloudClient(base: url)
        try await next.login(username: name, password: password)

        syncing = true
        defer { syncing = false }
        let hadRecords = ledger.recordCount() > 0
        let wasMirror = ledger.setting("cloud_user")?.isEmpty == false
        if hadRecords, !wasMirror {
            try ledger.backup(to: Self.backupPath())
        }
        var sent = 0
        if upload, hadRecords, !wasMirror {
            status = "正在把手机上的账上传到网页端…"
            sent = try await CloudUpload.run(ledger: ledger, client: next)
        }
        let state = try await next.state()
        try ledger.mirror(state)

        Keychain.write(Self.tokenKey, next.token)
        ledger.setSetting("cloud_server", url.absoluteString)
        ledger.setSetting("cloud_user", name)
        cloudServer = url.absoluteString
        cloudUser = name
        cloudExpired = false
        client = next
        lastSync = FiFormat.stamp()
        status = sent > 0 ? "已上传 \(sent) 条记录，手机和网页端现在是同一本账。" : "已连接网页账号 \(name)。"
        reload()
    }

    func disconnect() async {
        await client?.logout()
        Keychain.delete(Self.tokenKey)
        ledger.setSetting("cloud_user", "")
        client = nil
        cloudUser = nil
        cloudExpired = false
        lastSync = ""
        do {
            try ledger.clearRecords()
        } catch {
            alert = error.localizedDescription
        }
        status = "已退出网页账号。账仍保存在网页端，这台手机上的缓存已清空。"
        selectedAccountID = nil
        reload()
    }

    func pull() async {
        guard let client, !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            try ledger.mirror(try await client.state())
            cloudExpired = false
            lastSync = FiFormat.stamp()
            reload()
        } catch {
            handle(error)
        }
    }

    static func backupPath() -> String {
        let name = "gxyfi-上传前备份-\(FiFormat.day(.now)).db"
        return URL.documentsDirectory.appending(path: name).path(percentEncoded: false)
    }

    private func handle(_ error: Error) {
        if let cloud = error as? CloudError, cloud.unauthorized { cloudExpired = true }
        alert = error.localizedDescription
    }

    /// Runs one write against the web account when signed in, otherwise against the phone ledger.
    private func write(_ remote: @escaping (CloudClient) async throws -> CloudState, local: () throws -> Void) {
        guard let client else {
            perform(local)
            return
        }
        if cloudExpired {
            alert = CloudError.expired.message
            return
        }
        syncing = true
        Task {
            defer { syncing = false }
            do {
                try ledger.mirror(try await remote(client))
                lastSync = FiFormat.stamp()
                reload()
            } catch {
                handle(error)
            }
        }
    }

    // MARK: - Writes

    func saveAccount(_ input: AccountInput, id: Int64?) {
        let data: [String: Any] = [
            "name": input.name, "institution": input.institution, "kind": input.kind,
            "currency": input.currency, "note": input.note,
        ]
        write({ try await $0.mutate("account", op: id == nil ? "create" : "update", id: id, data: data) }) {
            _ = try ledger.saveAccount(input, id: id)
        }
    }

    func deleteAccount(_ id: Int64) {
        write({ try await $0.mutate("account", op: "delete", id: id) }) {
            ledger.deleteAccount(id)
            selectedAccountID = nil
        }
    }

    func saveBalance(_ input: BalanceInput, id: Int64?) {
        let old = id.flatMap { id in ledger.balanceEntries().first { $0.id == id } }
        let data: [String: Any] = [
            "account_id": input.accountID, "as_of_date": input.asOfDate, "balance": input.balance, "note": input.note,
        ]
        write({ client in
            var state = try await client.mutate("balance", op: "upsert", data: data)
            if let old, old.accountID != input.accountID || old.asOfDate != input.asOfDate {
                state = try await client.mutate("balance", op: "delete", id: old.id)
            }
            return state
        }) {
            try ledger.saveBalance(input, id: id)
        }
    }

    func deleteBalance(_ id: Int64) {
        write({ try await $0.mutate("balance", op: "delete", id: id) }) {
            ledger.deleteBalance(id)
        }
    }

    func saveHolding(_ input: HoldingInput, id: Int64?) {
        let prepared: HoldingInput
        do {
            prepared = try Market.prepare(input)
        } catch {
            alert = error.localizedDescription
            return
        }
        let data = CloudUpload.holdingData(prepared)
        write({ try await $0.mutate("holding", op: id == nil ? "create" : "update", id: id, data: data) }) {
            _ = try ledger.saveHolding(prepared, id: id)
        }
    }

    func deleteHolding(_ id: Int64) {
        write({ try await $0.mutate("holding", op: "delete", id: id) }) {
            ledger.deleteHolding(id)
        }
    }

    func saveDCAPlan(_ input: DCAPlanInput, id: Int64?) {
        let plan: DCAPlanInput
        do {
            plan = try DCA.preparePlan(input)
        } catch {
            alert = error.localizedDescription
            return
        }
        let data = CloudUpload.planData(plan)
        write({ try await $0.mutate("dca_plan", op: id == nil ? "create" : "update", id: id, data: data) }) {
            _ = try ledger.saveDCAPlan(plan, id: id)
        }
    }

    func deleteDCAPlan(_ id: Int64) {
        write({ try await $0.mutate("dca_plan", op: "delete", id: id) }) {
            ledger.deleteDCAPlan(id)
        }
    }

    func saveDCARecord(_ input: DCARecordInput, planID: Int64, id: Int64?) {
        let record: DCARecordInput
        do {
            record = try DCA.normalizeRecord(input)
        } catch {
            alert = error.localizedDescription
            return
        }
        let data = CloudUpload.recordData(record, planID: planID)
        write({ try await $0.mutate("dca_record", op: id == nil ? "create" : "update", id: id, data: data) }) {
            try ledger.saveDCARecord(record, planID: planID, id: id)
        }
    }

    func deleteDCARecord(_ id: Int64) {
        write({ try await $0.mutate("dca_record", op: "delete", id: id) }) {
            try ledger.deleteDCARecord(id)
        }
    }

    func saveProperty(_ input: PropertyInput, id: Int64?) {
        let data = CloudUpload.propertyData(input)
        write({ try await $0.mutate("property", op: id == nil ? "create" : "update", id: id, data: data) }) {
            _ = try ledger.saveProperty(input, id: id)
        }
    }

    func deleteProperty(_ id: Int64) {
        write({ try await $0.mutate("property", op: "delete", id: id) }) {
            ledger.deleteProperty(id)
        }
    }

    func saveCategory(_ name: String) {
        write({ try await $0.mutate("category", op: "create", data: ["name": name]) }) {
            _ = try ledger.saveCategory(name)
        }
    }

    func saveExpense(_ input: ExpenseInput, id: Int64?) {
        let data: [String: Any] = [
            "category_id": input.categoryID, "occurred_on": input.occurredOn, "amount": input.amount,
            "payee": input.payee, "note": input.note,
        ]
        write({ try await $0.mutate("expense", op: id == nil ? "create" : "update", id: id, data: data) }) {
            try ledger.saveExpense(input, id: id)
        }
    }

    func deleteExpense(_ id: Int64) {
        write({ try await $0.mutate("expense", op: "delete", id: id) }) {
            ledger.deleteExpense(id)
        }
    }

    func saveBudget(year: Int, categoryID: Int64, amount: Double, note: String) {
        let data: [String: Any] = ["year": year, "category_id": categoryID, "amount": amount, "note": note]
        write({ try await $0.mutate("budget", op: "upsert", data: data) }) {
            ledger.saveBudget(year: year, categoryID: categoryID, amount: amount, note: note)
        }
    }

    func copyBudget(from source: Int, to target: Int) {
        let lines = ledger.budgetEntries().filter { $0.year == source }
        if isCloud, lines.isEmpty {
            alert = "\(source) 年还没有预算"
            return
        }
        write({ client in
            var state: CloudState = [:]
            for line in lines {
                state = try await client.mutate("budget", op: "upsert", data: [
                    "year": target, "category_id": line.categoryID, "amount": line.amount, "note": line.note,
                ])
            }
            return state
        }) {
            _ = try ledger.copyBudget(from: source, to: target)
        }
    }

    func saveFX(usd: Double?, hkd: Double?) {
        var updates: [String: FXQuote] = [:]
        updates["USD"] = FXQuote(rate: usd, source: usd == nil ? "未设置" : "手工", at: usd == nil ? "" : FiFormat.stamp())
        updates["HKD"] = FXQuote(rate: hkd, source: hkd == nil ? "未设置" : "手工", at: hkd == nil ? "" : FiFormat.stamp())
        let rates = [("USD", usd), ("HKD", hkd)].compactMap { code, rate in rate.map { (code, $0) } }
        if isCloud, rates.isEmpty { return }
        write({ client in
            var state: CloudState = [:]
            for (code, rate) in rates {
                state = try await client.mutate("fx", op: "upsert", data: ["code": code, "rate": rate])
            }
            return state
        }) {
            ledger.saveFX(updates)
        }
    }

    // MARK: - Quotes and export

    func refreshQuotes() {
        if refreshing { return }
        if let client {
            refreshing = true
            status = "网页端正在获取黄金、A 股、美股和汇率…"
            Task {
                defer { refreshing = false }
                do {
                    let state = try await client.refreshQuotes()
                    try ledger.mirror(state)
                    lastSync = FiFormat.stamp()
                    let errors = state["quoteErrors"] as? [String] ?? []
                    reload()
                    status = quoteMessage(ledger.quotes(), errors: errors)
                } catch {
                    handle(error)
                    status = "行情没有刷新"
                }
            }
            return
        }
        refreshing = true
        status = "正在获取黄金、A 股、美股和汇率…"
        let holdings = ledger.holdings()
        let token = ledger.setting("finnhub_token") ?? ""
        Task {
            let payload = await Market.refresh(holdings: holdings, token: token)
            ledger.saveQuotes(payload.quotes)
            if !payload.fxUpdates.isEmpty { ledger.saveFX(payload.fxUpdates) }
            status = quoteMessage(payload.quotes, errors: payload.errors)
            refreshing = false
            reload()
        }
    }

    private func quoteMessage(_ quotes: [QuoteRecord], errors: [String]) -> String {
        let ok = quotes.filter(\.ok).count
        var message = "行情已更新 \(ok)/\(quotes.count)。"
        let failed = quotes.filter { !$0.ok }.prefix(5).map(\.symbol)
        if !failed.isEmpty { message += " 失败：" + failed.joined(separator: "、") + "。" }
        if !errors.isEmpty { message += " 汇率：" + errors.prefix(2).joined(separator: "；") + "。" }
        return message + " 仅供估值，有延迟，不构成投资建议。"
    }

    func exportExcel() {
        let name = "gxyFi-台账-\(FiFormat.day(.now).replacingOccurrences(of: "-", with: "")).xlsx"
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        do {
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: url)
            }
            try WorkbookExport.write(ledger: ledger, to: url)
            exportName = name
            exportDocument = ExcelDocument(data: try Data(contentsOf: url))
            showExport = true
        } catch {
            alert = error.localizedDescription
        }
    }
}
