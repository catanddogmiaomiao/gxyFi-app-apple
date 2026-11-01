import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@Observable
final class AppModel {
    let ledger: Ledger
    var page = 0
    var summary: PortfolioSummary
    var quotes: [QuoteRecord]
    var expenses: [ExpenseRecord]
    var categories: [CategoryRecord]
    var balances: [BalanceRecord]
    var status = "行情只用于估值，有延迟，不构成投资建议"
    var refreshing = false
    var alert: String?
    var selectedAccountID: Int64?

    init(ledger: Ledger) {
        self.ledger = ledger
        summary = ledger.portfolioSummary()
        quotes = ledger.quotes()
        expenses = ledger.expenses()
        categories = ledger.categories()
        balances = []
        selectedAccountID = summary.accounts.first?.id
        reloadBalances()
    }

    static func live() -> AppModel {
        let ledger = (try? Ledger(path: Ledger.defaultPath())) ?? {
            let fallback = FileManager.default.temporaryDirectory.appending(path: "gxyfi-fallback.db").path(percentEncoded: false)
            return try! Ledger(path: fallback)
        }()
        return AppModel(ledger: ledger)
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
        if selectedAccountID == nil { selectedAccountID = summary.accounts.first?.id }
        reloadBalances()
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

    func refreshQuotes() {
        if refreshing { return }
        refreshing = true
        status = "正在获取黄金、A 股、美股和汇率…"
        let holdings = ledger.holdings()
        let token = ledger.setting("finnhub_token") ?? ""
        Task {
            let payload = await Market.refresh(holdings: holdings, token: token)
            ledger.saveQuotes(payload.quotes)
            if !payload.fxUpdates.isEmpty { ledger.saveFX(payload.fxUpdates) }
            let ok = payload.quotes.filter(\.ok).count
            var message = "行情已更新 \(ok)/\(payload.quotes.count)。"
            let failed = payload.quotes.filter { !$0.ok }.prefix(5).map(\.symbol)
            if !failed.isEmpty { message += " 失败：" + failed.joined(separator: "、") + "。" }
            if !payload.errors.isEmpty { message += " 汇率：" + payload.errors.prefix(2).joined(separator: "；") + "。" }
            message += " 仅供估值，有延迟，不构成投资建议。"
            status = message
            refreshing = false
            reload()
        }
    }

    func exportExcel() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .data]
        panel.nameFieldStringValue = "gxyFi-台账-\(FiFormat.day(.now).replacingOccurrences(of: "-", with: "")).xlsx"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try WorkbookExport.write(ledger: ledger, to: url)
            status = "已导出 \(url.path)"
            alert = "已导出到 \(url.path)"
        } catch {
            alert = error.localizedDescription
        }
    }
}
