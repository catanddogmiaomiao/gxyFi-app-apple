import SwiftUI

struct ExpensesView: View {
    @Environment(AppModel.self) private var model
    @State private var month = String(FiFormat.day(.now).prefix(7))
    @State private var editing: ExpenseRecord?
    @State private var showingExpense = false
    @State private var showingCategory = false
    @State private var isNew = false
    @State private var confirm = false
    @State private var selectedID: Int64?

    private var months: [String] {
        var values = ["全部月份"]
        let calendar = Calendar.current
        var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: .now)) ?? .now
        for _ in 0..<24 {
            values.append(String(FiFormat.day(cursor).prefix(7)))
            cursor = calendar.date(byAdding: .month, value: -1, to: cursor) ?? cursor
        }
        return values
    }

    private var visible: [ExpenseRecord] {
        guard month != "全部月份" else { return model.expenses }
        return model.expenses.filter { $0.occurredOn.hasPrefix(month) }
    }

    var body: some View {
        PageChrome(title: "支出", subtitle: "支出按人民币登记，用来和年度预算对照。默认看本月。") {
            Picker("月份", selection: $month) {
                ForEach(months, id: \.self, content: Text.init)
            }
            .labelsHidden()
            .frame(width: 140)
            FiButton(title: "记一笔", kind: .primary) { isNew = true; editing = nil; showingExpense = true }
            FiButton(title: "编辑") { open() }
            FiButton(title: "删除", kind: .danger) { confirm = selected != nil }
            FiButton(title: "新类别") { showingCategory = true }
            Text("合计 \(FiFormat.cny(visible.reduce(0) { $0 + $1.amount }))")
                .font(.system(size: 12)).foregroundStyle(FiColor.muted)
        } content: {
            FiTable(
                columns: ["日期", "类别", "金额", "对象", "备注"],
                rows: visible,
                selection: selectedID,
                onSelect: { selectedID = $0 },
                onOpen: { _ in open() }
            ) { row in
                [
                    (row.occurredOn, FiColor.ink), (row.category, FiColor.ink),
                    (FiFormat.cny(row.amount), FiColor.ink), (row.payee, FiColor.ink), (row.note, FiColor.ink),
                ]
            }
        }
        .sheet(isPresented: $showingExpense) {
            ExpenseForm(categories: model.categories, initial: isNew ? nil : editing, onCancel: { showingExpense = false }) { input in
                model.perform { try model.ledger.saveExpense(input, id: isNew ? nil : editing?.id) }
                showingExpense = false
            }
        }
        .sheet(isPresented: $showingCategory) {
            CategoryForm(onCancel: { showingCategory = false }) { name in
                model.perform { _ = try model.ledger.saveCategory(name) }
                showingCategory = false
            }
        }
        .confirmationDialog("删除这笔支出？", isPresented: $confirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let id = selectedID {
                    model.ledger.deleteExpense(id)
                    model.reload()
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var selected: ExpenseRecord? { visible.first { $0.id == selectedID } }

    private func open() {
        guard let selected else {
            model.alert = "请先选择一笔支出。"
            return
        }
        editing = selected
        isNew = false
        showingExpense = true
    }
}

struct BudgetView: View {
    @Environment(AppModel.self) private var model
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var rows: [BudgetProgress] = []
    @State private var selectedID: Int64?
    @State private var showing = false
    @State private var confirm = false

    var body: some View {
        let planned = rows.reduce(0) { $0 + $1.planned }
        let actual = rows.reduce(0) { $0 + $1.actual }
        PageChrome(title: "预算", subtitle: "按日历年、按支出类别设置。执行率 = 本年该类已支出 ÷ 年度预算。") {
            Picker("年份", selection: $year) {
                ForEach((2000...2100), id: \.self) { Text(String($0)).tag($0) }
            }
            .labelsHidden()
            .frame(width: 100)
            FiButton(title: "设置预算", kind: .primary) { open() }
            FiButton(title: "复制上一年") { confirm = true }
            Text("预算 \(FiFormat.cny(planned)) · 已支出 \(FiFormat.cny(actual)) · \(planned == 0 ? "—" : FiFormat.percent(actual / planned))")
                .font(.system(size: 12)).foregroundStyle(FiColor.muted)
        } content: {
            FiTable(
                columns: ["类别", "年度预算", "已支出", "剩余", "执行率"],
                rows: rows,
                selection: selectedID,
                onSelect: { selectedID = $0 },
                onOpen: { _ in open() }
            ) { row in
                let color: Color = row.remain < 0 ? FiColor.up : FiColor.flat
                return [
                    (row.category, FiColor.ink), (FiFormat.cny(row.planned), FiColor.ink),
                    (FiFormat.cny(row.actual), FiColor.ink), (FiFormat.signed(row.remain), color),
                    (FiFormat.percent(row.ratio), color),
                ]
            }
        }
        .onAppear(perform: reload)
        .onChange(of: year) { _, _ in reload() }
        .onChange(of: model.summary.today) { _, _ in reload() }
        .sheet(isPresented: $showing) {
            if let row = rows.first(where: { $0.id == selectedID }) {
                BudgetForm(category: row.category, amount: row.planned, note: row.note, onCancel: { showing = false }) { amount, note in
                    model.ledger.saveBudget(year: year, categoryID: row.id, amount: amount, note: note)
                    model.reload()
                    reload()
                    showing = false
                }
            }
        }
        .confirmationDialog("用 \(year - 1) 年的预算覆盖 \(year) 年？", isPresented: $confirm, titleVisibility: .visible) {
            Button("覆盖") {
                model.perform { _ = try model.ledger.copyBudget(from: year - 1, to: year) }
                reload()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func reload() { rows = model.ledger.budgetProgress(year: year) }

    private func open() {
        guard selectedID != nil else {
            model.alert = "请先选择一个类别。"
            return
        }
        showing = true
    }
}

struct MarketView: View {
    @Environment(AppModel.self) private var model
    @State private var market = "GOLD"
    @State private var symbol = ""
    @State private var result = "查询结果会显示在这里，不会自动变成持仓。"
    @State private var looking = false
    @State private var showingFX = false

    var body: some View {
        let fx = model.summary.fx
        let token = (model.ledger.setting("finnhub_token") ?? "").isEmpty ? "美股未设置 Finnhub，使用 Yahoo Finance" : "已保存 Finnhub Token"
        PageChrome(
            title: "行情",
            subtitle: "只查询你持仓里的代码。黄金来自上金所延时行情，A 股先用新浪、失败再用东方财富，美股默认用 Yahoo Finance。这些来源都没有服务等级承诺，所以最后一次成功的价格会留在本机。"
        ) {
            FiButton(title: "汇率与 Token", kind: .primary) { showingFX = true }
            Text("\(rateText("USD", fx))    \(rateText("HKD", fx))    \(token)")
                .font(.system(size: 12)).foregroundStyle(FiColor.muted)
        } content: {
            HStack {
                Picker("", selection: $market) {
                    Text("黄金").tag("GOLD")
                    Text("A股").tag("A")
                    Text("美股").tag("US")
                }.labelsHidden().frame(width: 100)
                TextField("Au(T+D) / 600519 / AAPL", text: $symbol).textFieldStyle(.plain)
                FiButton(title: looking ? "查询中…" : "查询这个代码", disabled: looking) { lookup() }
            }
            Text(result).font(.system(size: 12)).foregroundStyle(FiColor.muted)
            FiTable(
                columns: ["市场", "代码", "名称", "价格", "涨跌", "行情时间", "来源", "状态"],
                rows: model.quotes,
                selection: nil,
                onSelect: { _ in }
            ) { row in
                let day: Double? = {
                    guard let price = row.price, let prev = row.prevClose, prev != 0 else { return nil }
                    return (price - prev) / prev
                }()
                return [
                    (LedgerKind.marketLabel[row.market] ?? row.market, FiColor.ink),
                    (row.symbol, FiColor.ink), (row.name.isEmpty ? "—" : row.name, FiColor.ink),
                    (row.price.map { FiFormat.money($0, digits: 4) } ?? "—", FiColor.ink),
                    (FiFormat.percent(day), .pnl(day)),
                    (row.quotedAt.isEmpty ? row.fetchedAt : row.quotedAt, FiColor.ink),
                    (row.source.isEmpty ? "—" : row.source, FiColor.ink),
                    (row.ok ? "成功" : (row.message.isEmpty ? "失败" : row.message), row.ok ? FiColor.flat : FiColor.up),
                ]
            }
        }
        .sheet(isPresented: $showingFX) {
            FXForm(fx: model.summary.fx, onCancel: { showingFX = false }) { usd, hkd, token, clear in
                var updates: [String: FXQuote] = [:]
                updates["USD"] = FXQuote(rate: usd, source: usd == nil ? "未设置" : "手工", at: usd == nil ? "" : FiFormat.stamp())
                updates["HKD"] = FXQuote(rate: hkd, source: hkd == nil ? "未设置" : "手工", at: hkd == nil ? "" : FiFormat.stamp())
                model.ledger.saveFX(updates)
                if clear { model.ledger.setSetting("finnhub_token", "") }
                else if !token.trimmingCharacters(in: .whitespaces).isEmpty { model.ledger.setSetting("finnhub_token", token.trimmingCharacters(in: .whitespaces)) }
                model.reload()
                showingFX = false
            }
        }
    }

    private func rateText(_ code: String, _ fx: [String: FXQuote]) -> String {
        guard let item = fx[code], let rate = item.rate else { return "\(code) 未设置" }
        return String(format: "%@ %.4f（%@）", code, rate, item.source)
    }

    private func lookup() {
        let text = symbol.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            model.alert = "请先填写代码。"
            return
        }
        looking = true
        result = "正在查询…"
        let chosen = market
        let token = model.ledger.setting("finnhub_token") ?? ""
        Task {
            let quote = await Market.lookup(market: chosen, symbol: text, token: token)
            looking = false
            if quote.ok {
                model.ledger.saveQuotes([quote])
                model.reload()
                result = "\(quote.name.isEmpty ? quote.symbol : quote.name)  \(FiFormat.money(quote.price, digits: 4)) \(quote.currency)  ·  \(quote.source)  ·  \(quote.quotedAt)"
            } else {
                result = quote.message.isEmpty ? "没有查到价格" : quote.message
            }
        }
    }
}
