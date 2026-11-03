import SwiftUI

struct ExpensesView: View {
    @Environment(AppModel.self) private var model
    /// 空字符串表示全部月份，「2026」表示全年，「2026-11」表示一个月。
    @State private var period = String(FiFormat.day(.now).prefix(7))
    @State private var categoryFilter: Int64?
    @State private var editing: ExpenseRecord?
    @State private var showingExpense = false
    @State private var showingCategory = false
    @State private var isNew = false
    @State private var confirm = false
    @State private var selectedID: Int64?

    private var periods: [(String, String)] {
        let year = Calendar.current.component(.year, from: .now)
        var values = [("", "全部月份"), (String(year), "\(year) 全年"), (String(year - 1), "\(year - 1) 全年")]
        values += Spending.monthKeys(24).reversed().map { ($0, Spending.periodLabel($0)) }
        return values
    }

    private var currentPeriod: String? { period.isEmpty ? nil : period }

    private var visible: [ExpenseRecord] {
        model.expenses.filter { Spending.inPeriod($0, currentPeriod) && (categoryFilter == nil || $0.categoryID == categoryFilter) }
    }

    var body: some View {
        let expenses = model.expenses
        let colors = FiColor.categoryColors(model.categories.map(\.name))
        let groups = Spending.byCategory(expenses, period: currentPeriod)
        let year = currentPeriod.flatMap { Int($0.prefix(4)) } ?? Calendar.current.component(.year, from: .now)
        let budgets = Spending.budgetFor(currentPeriod, budgets: model.ledger.budgetProgress(year: year))
        let rows = visible
        PageChrome(title: "支出", subtitle: "支出按人民币登记，用来和年度预算对照。点「分类构成」里的一类只看这一类，点柱子切换到那个月。") {
            Picker("期间", selection: $period) {
                ForEach(periods, id: \.0) { Text($0.1).tag($0.0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            FiButton(title: "记一笔", kind: .primary) { isNew = true; editing = nil; showingExpense = true }
            FiButton(title: "编辑") { open() }
            FiButton(title: "删除", kind: .danger) { confirm = selected != nil }
            FiButton(title: "新类别") { showingCategory = true }
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                        cards(expenses: expenses, groups: groups, budgets: budgets)
                    }
                    FiPanel(title: "分类构成") {
                        CategoryBars(rows: groups, colors: colors, budgets: budgets, selected: categoryFilter) { categoryFilter = $0 }
                    }
                    FiPanel(title: "近六个月 · 按类别") {
                        StackedMonths(
                            stack: Spending.monthlyStack(expenses),
                            colors: colors,
                            current: currentPeriod?.count == 7 ? currentPeriod : nil
                        ) { period = $0 }
                    }
                    HStack {
                        Text(filterText(rows: rows, groups: groups))
                            .font(.system(size: 13))
                            .foregroundStyle(FiColor.cream)
                        Spacer()
                        if categoryFilter != nil {
                            FiButton(title: "显示全部类别") { categoryFilter = nil }
                        }
                    }
                    FiTable(
                        columns: ["日期", "类别", "金额", "对象", "备注"],
                        rows: rows,
                        selection: selectedID,
                        onSelect: { selectedID = $0 },
                        onOpen: { _ in open() }
                    ) { row in
                        [
                            (row.occurredOn, FiColor.ink), (row.category, colors[row.category] ?? FiColor.ink),
                            (FiFormat.cny(row.amount), row.amount < 0 ? FiColor.down : FiColor.ink),
                            (row.payee, FiColor.ink), (row.note, FiColor.ink),
                        ]
                    }
                    .frame(height: max(CGFloat(rows.count) * 43 + 36, 120))
                }
                .padding(.bottom, 16)
            }
        }
        .onChange(of: period) { _, _ in categoryFilter = nil }
        .onChange(of: groups.map(\.categoryID)) { _, ids in
            if let filter = categoryFilter, !ids.contains(filter) { categoryFilter = nil }
        }
        .sheet(isPresented: $showingExpense) {
            ExpenseForm(categories: model.categories, initial: isNew ? nil : editing, onCancel: { showingExpense = false }) { input in
                model.saveExpense(input, id: isNew ? nil : editing?.id)
                showingExpense = false
            }
        }
        .sheet(isPresented: $showingCategory) {
            CategoryForm(onCancel: { showingCategory = false }) { name in
                model.saveCategory(name)
                showingCategory = false
            }
        }
        .confirmationDialog("删除这笔支出？", isPresented: $confirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let id = selectedID { model.deleteExpense(id) }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var selected: ExpenseRecord? { visible.first { $0.id == selectedID } }

    @ViewBuilder
    private func cards(expenses: [ExpenseRecord], groups: [CategorySpend], budgets: [Int64: Double]) -> some View {
        let amount = Spending.total(expenses, period: currentPeriod)
        let count = groups.reduce(0) { $0 + $1.count }
        let days = Spending.days(currentPeriod)
        MetricCard(title: "本期支出", value: FiFormat.cny(amount), note: "\(count) 笔" + (days.map { " · 日均 \(FiFormat.cny(amount / Double($0)))" } ?? ""))

        if let before = Spending.previousPeriod(currentPeriod) {
            let last = Spending.total(expenses, period: before)
            if last != 0 {
                let change = (amount - last) / last
                MetricCard(title: "比上期", value: (change > 0 ? "+" : "") + FiFormat.percent(change), note: "\(Spending.periodLabel(before)) \(FiFormat.cny(last))")
            } else {
                MetricCard(title: "比上期", value: "—", note: "\(Spending.periodLabel(before)) 没有支出")
            }
        } else {
            MetricCard(title: "比上期", value: "—", note: "选一个月或一年才能和上期比较")
        }

        if let top = groups.first, top.amount > 0 {
            MetricCard(title: "最多的一类", value: top.category, note: "\(FiFormat.cny(top.amount)) · 占 \(Int((top.share * 100).rounded()))%")
        } else {
            MetricCard(title: "最多的一类", value: "—", note: "")
        }

        let planned = budgets.values.reduce(0, +)
        if currentPeriod == nil {
            MetricCard(title: "本期预算", value: "—", note: "选一个月或一年才能对照预算")
        } else if planned == 0 {
            MetricCard(title: "本期预算", value: "未设置", note: "在「更多 → 预算」按类别设置年度预算")
        } else {
            let budgeted = groups.filter { budgets[$0.categoryID] != nil }
            let spent = budgeted.reduce(0) { $0 + $1.amount }
            let over = budgeted.filter { $0.amount > (budgets[$0.categoryID] ?? 0) }.prefix(3).map(\.category)
            let scope = currentPeriod?.count == 7 ? "按年度预算的十二分之一" : "全年预算"
            MetricCard(
                title: "本期预算",
                value: "已用 \(Int((spent / planned * 100).rounded()))%",
                note: "\(scope) \(FiFormat.cny(planned))" + (over.isEmpty ? "" : " · 超出：\(over.joined(separator: "、"))")
            )
        }
    }

    private func filterText(rows: [ExpenseRecord], groups: [CategorySpend]) -> String {
        if let filter = categoryFilter, let name = groups.first(where: { $0.categoryID == filter })?.category {
            return "只看「\(name)」 · \(rows.count) 笔 · 合计 \(FiFormat.cny(rows.reduce(0) { $0 + $1.amount }))"
        }
        return "\(Spending.periodLabel(currentPeriod)) · \(rows.count) 笔明细"
    }

    private func open() {
        guard let selected else {
            model.alert = "请先选择一笔支出。"
            return
        }
        if selected.amount < 0 {
            model.alert = "这是一笔退款，来自账户明细。要改类别或金额，请在电脑端或网页端的「归类明细」里改。"
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
            .pickerStyle(.menu)
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
        .onChange(of: model.revision) { _, _ in reload() }
        .sheet(isPresented: $showing) {
            if let row = rows.first(where: { $0.id == selectedID }) {
                BudgetForm(category: row.category, amount: row.planned, note: row.note, onCancel: { showing = false }) { amount, note in
                    model.saveBudget(year: year, categoryID: row.id, amount: amount, note: note)
                    showing = false
                }
            }
        }
        .confirmationDialog("用 \(year - 1) 年的预算覆盖 \(year) 年？", isPresented: $confirm, titleVisibility: .visible) {
            Button("覆盖") { model.copyBudget(from: year - 1, to: year) }
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
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Picker("", selection: $market) {
                        Text("黄金").tag("GOLD")
                        Text("A股").tag("A")
                        Text("美股").tag("US")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    TextField("Au(T+D) / 600519 / AAPL", text: $symbol)
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
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
                if clear { model.ledger.setSetting("finnhub_token", "") }
                else if !token.trimmingCharacters(in: .whitespaces).isEmpty { model.ledger.setSetting("finnhub_token", token.trimmingCharacters(in: .whitespaces)) }
                model.saveFX(usd: usd, hkd: hkd)
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
