import SwiftUI

struct FormSheet<Content: View>: View {
    var title: String
    var error: String?
    var onCancel: () -> Void
    var onSave: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    content()
                    if let error {
                        Text(error).font(.system(size: 13)).foregroundStyle(FiColor.up)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(FiColor.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: onSave)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
    }
}

struct FieldLabel: View {
    var title: String
    var body: some View {
        Text(title).font(.system(size: 13)).foregroundStyle(FiColor.muted)
    }
}

struct AccountForm: View {
    var initial: AccountRecord?
    var onCancel: () -> Void
    var onSave: (AccountInput) -> Void
    @State private var name = ""
    @State private var institution = ""
    @State private var kind = "活期"
    @State private var currency = "CNY"
    @State private var note = ""
    @State private var error: String?

    var body: some View {
        FormSheet(title: "账户", error: error, onCancel: onCancel, onSave: save) {
            formRow("名称") { TextField("例如 工资卡", text: $name) }
            formRow("机构") { TextField("银行或券商", text: $institution) }
            formRow("类型") { Picker("", selection: $kind) { ForEach(LedgerKind.accountKinds, id: \.self, content: Text.init) }.labelsHidden() }
            formRow("币种") { Picker("", selection: $currency) { ForEach(LedgerKind.currencies, id: \.self, content: Text.init) }.labelsHidden() }
            formRow("备注") { TextField("", text: $note) }
        }
        .onAppear {
            name = initial?.name ?? ""
            institution = initial?.institution ?? ""
            kind = initial?.kind ?? "活期"
            currency = initial?.currency ?? "CNY"
            note = initial?.note ?? ""
        }
    }

    private func save() {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            error = "请填写账户名称"
            return
        }
        onSave(AccountInput(name: name, institution: institution, kind: kind, currency: currency, note: note))
    }
}

struct BalanceForm: View {
    var accounts: [AccountRecord]
    var initial: BalanceRecord?
    var presetAccountID: Int64?
    var onCancel: () -> Void
    var onSave: (BalanceInput) -> Void
    @State private var accountID: Int64 = 0
    @State private var date = Date()
    @State private var balance = ""
    @State private var note = ""
    @State private var error: String?

    var body: some View {
        FormSheet(title: "余额快照", error: error, onCancel: onCancel, onSave: save) {
            formRow("账户") {
                Picker("", selection: $accountID) {
                    ForEach(accounts) { account in Text(account.name).tag(account.id) }
                }.labelsHidden()
            }
            formRow("日期") { DatePicker("", selection: $date, displayedComponents: .date).labelsHidden() }
            formRow("余额") { TextField("可为负数，表示透支或贷款", text: $balance) }
            formRow("备注") { TextField("例如 月末对账", text: $note) }
            Text("同一账户同一天再次保存，会覆盖那天的余额。")
                .font(.system(size: 12)).foregroundStyle(FiColor.muted)
        }
        .onAppear {
            accountID = initial?.accountID ?? presetAccountID ?? accounts.first?.id ?? 0
            if let text = initial?.asOfDate, let parsed = FiFormat.parseDay(text) { date = parsed }
            balance = initial.map { decimalText($0.balance) } ?? ""
            note = initial?.note ?? ""
        }
    }

    private func save() {
        do {
            let value = try FiFormat.parseNumber(balance, label: "余额", required: true, allowNegative: true)
            onSave(BalanceInput(accountID: accountID, asOfDate: FiFormat.day(date), balance: value ?? 0, note: note))
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct HoldingForm: View {
    var initial: HoldingRecord?
    var onCancel: () -> Void
    var onSave: (HoldingInput) -> Void
    @State private var market = "GOLD"
    @State private var symbol = ""
    @State private var name = ""
    @State private var quantity = ""
    @State private var avgCost = ""
    @State private var manual = ""
    @State private var currency = "CNY"
    @State private var accountLabel = ""
    @State private var note = ""
    @State private var error: String?

    var body: some View {
        FormSheet(title: "持仓", error: error, onCancel: onCancel, onSave: save) {
            formRow("市场") {
                Picker("", selection: $market) {
                    ForEach(LedgerKind.marketChoices, id: \.1) { Text($0.0).tag($0.1) }
                }.labelsHidden()
            }
            formRow("代码") { TextField(placeholder, text: $symbol) }
            formRow("名称") { TextField("可留空，将使用代码", text: $name) }
            formRow("数量") { TextField("黄金按克，股票按股", text: $quantity) }
            formRow("成本价") { TextField("不知道可留空", text: $avgCost) }
            formRow("手工现价") { TextField("留空则使用行情", text: $manual) }
            formRow("币种") {
                Picker("", selection: $currency) {
                    ForEach(LedgerKind.currencies, id: \.self, content: Text.init)
                }.labelsHidden().disabled(market != "OTHER")
            }
            formRow("所在账户") { TextField("例如 华泰证券，只是备注", text: $accountLabel) }
            formRow("备注") { TextField("", text: $note) }
        }
        .onAppear(perform: load)
        .onChange(of: market) { _, value in
            if value == "US" { currency = "USD" }
            if value == "A" || value == "GOLD" { currency = "CNY" }
        }
    }

    private var placeholder: String {
        switch market {
        case "US": "AAPL 或 BRK.B"
        case "A": "600519"
        case "GOLD": "Au(T+D)"
        default: "自定义代码"
        }
    }

    private func load() {
        market = initial?.market ?? "GOLD"
        symbol = initial?.symbol ?? ""
        name = initial?.name ?? ""
        quantity = initial.map { decimalText($0.quantity) } ?? ""
        avgCost = initial?.avgCost.map(decimalText) ?? ""
        manual = initial?.manualPrice.map(decimalText) ?? ""
        currency = initial?.currency ?? "CNY"
        accountLabel = initial?.accountLabel ?? ""
        note = initial?.note ?? ""
    }

    private func save() {
        do {
            if symbol.trimmingCharacters(in: .whitespaces).isEmpty { throw LedgerError("请填写代码") }
            let qty = try FiFormat.parseNumber(quantity, label: "数量", required: true, allowZero: false)
            let cost = try FiFormat.parseNumber(avgCost, label: "成本价")
            let price = try FiFormat.parseNumber(manual, label: "手工现价")
            onSave(HoldingInput(name: name, symbol: symbol, market: market, quantity: qty ?? 0, currency: currency, avgCost: cost, manualPrice: price, accountLabel: accountLabel, note: note))
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct PropertyForm: View {
    var initial: PropertyRecord?
    var onCancel: () -> Void
    var onSave: (PropertyInput) -> Void
    @State private var name = ""
    @State private var kind = "住宅"
    @State private var city = ""
    @State private var address = ""
    @State private var area = ""
    @State private var acquired = ""
    @State private var purchase = ""
    @State private var current = ""
    @State private var valued = ""
    @State private var mortgage = "0"
    @State private var rent = "0"
    @State private var note = ""
    @State private var error: String?

    var body: some View {
        FormSheet(title: "不动产", error: error, onCancel: onCancel, onSave: save) {
            formRow("名称") { TextField("", text: $name) }
            formRow("类型") { Picker("", selection: $kind) { ForEach(LedgerKind.propertyKinds, id: \.self, content: Text.init) }.labelsHidden() }
            formRow("城市") { TextField("", text: $city) }
            formRow("地址") { TextField("", text: $address) }
            formRow("面积") { TextField("平方米，可留空", text: $area) }
            formRow("购入日") { TextField("YYYY-MM-DD，可留空", text: $acquired) }
            formRow("购入价") { TextField("人民币，可留空", text: $purchase) }
            formRow("现值") { TextField("人民币，用于计算净值", text: $current) }
            formRow("估值日") { TextField("留空则在填写现值时记为今天", text: $valued) }
            formRow("贷款余额") { TextField("没有贷款就填 0", text: $mortgage) }
            formRow("月租金") { TextField("没有出租就填 0", text: $rent) }
            formRow("备注") { TextField("", text: $note) }
            Text("金额按人民币登记。贷款若已在储蓄账户记为负数，这里请填 0，避免净资产被减两次。")
                .font(.system(size: 12)).foregroundStyle(FiColor.muted)
        }
        .onAppear {
            guard let initial else { return }
            name = initial.name
            kind = initial.kind
            city = initial.city
            address = initial.address
            area = initial.areaSqm.map(decimalText) ?? ""
            acquired = initial.acquiredOn ?? ""
            purchase = initial.purchasePrice.map(decimalText) ?? ""
            current = initial.currentValue.map(decimalText) ?? ""
            valued = initial.valuedOn ?? ""
            mortgage = decimalText(initial.mortgageBalance)
            rent = decimalText(initial.monthlyRent)
            note = initial.note
        }
    }

    private func save() {
        do {
            if name.trimmingCharacters(in: .whitespaces).isEmpty { throw LedgerError("请填写名称") }
            let areaValue = try FiFormat.parseNumber(area, label: "面积")
            let purchaseValue = try FiFormat.parseNumber(purchase, label: "购入价")
            let currentValue = try FiFormat.parseNumber(current, label: "现值")
            let mortgageValue = try FiFormat.parseNumber(mortgage, label: "贷款余额")
            let rentValue = try FiFormat.parseNumber(rent, label: "月租金")
            try checkDate(acquired, label: "购入日")
            try checkDate(valued, label: "估值日")
            onSave(PropertyInput(
                name: name, kind: kind, city: city, address: address, areaSqm: areaValue,
                acquiredOn: blank(acquired), purchasePrice: purchaseValue, currentValue: currentValue,
                valuedOn: blank(valued), mortgageBalance: mortgageValue ?? 0, monthlyRent: rentValue ?? 0, note: note
            ))
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ExpenseForm: View {
    var categories: [CategoryRecord]
    var initial: ExpenseRecord?
    var onCancel: () -> Void
    var onSave: (ExpenseInput) -> Void
    @State private var date = Date()
    @State private var categoryID: Int64 = 0
    @State private var amount = ""
    @State private var payee = ""
    @State private var note = ""
    @State private var error: String?

    var body: some View {
        FormSheet(title: "支出", error: error, onCancel: onCancel, onSave: save) {
            formRow("日期") { DatePicker("", selection: $date, displayedComponents: .date).labelsHidden() }
            formRow("类别") {
                Picker("", selection: $categoryID) {
                    ForEach(categories) { category in Text(category.name).tag(category.id) }
                }.labelsHidden()
            }
            formRow("金额") { TextField("", text: $amount) }
            formRow("对象") { TextField("商户或对象，可留空", text: $payee) }
            formRow("备注") { TextField("", text: $note) }
        }
        .onAppear {
            categoryID = initial?.categoryID ?? categories.first?.id ?? 0
            if let text = initial?.occurredOn, let parsed = FiFormat.parseDay(text) { date = parsed }
            amount = initial.map { decimalText($0.amount) } ?? ""
            payee = initial?.payee ?? ""
            note = initial?.note ?? ""
        }
    }

    private func save() {
        do {
            let value = try FiFormat.parseNumber(amount, label: "金额", required: true, allowZero: false)
            onSave(ExpenseInput(categoryID: categoryID, occurredOn: FiFormat.day(date), amount: value ?? 0, payee: payee, note: note))
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct BudgetForm: View {
    var category: String
    var amount: Double
    var note: String
    var onCancel: () -> Void
    var onSave: (Double, String) -> Void
    @State private var value = ""
    @State private var noteText = ""
    @State private var error: String?

    var body: some View {
        FormSheet(title: "年度预算", error: error, onCancel: onCancel, onSave: save) {
            formRow("类别") { Text(category).foregroundStyle(FiColor.cream) }
            formRow("年度预算") { TextField("这一年这一类的预算，人民币", text: $value) }
            formRow("备注") { TextField("", text: $noteText) }
        }
        .onAppear {
            value = decimalText(amount)
            noteText = note
        }
    }

    private func save() {
        do {
            let parsed = try FiFormat.parseNumber(value, label: "预算", required: true)
            onSave(parsed ?? 0, noteText)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct CategoryForm: View {
    var onCancel: () -> Void
    var onSave: (String) -> Void
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        FormSheet(title: "新的支出类别", error: error, onCancel: onCancel, onSave: save) {
            formRow("类别名称") { TextField("例如 父母赡养", text: $name) }
        }
    }

    private func save() {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            error = "请填写类别名称"
            return
        }
        onSave(name)
    }
}

struct FXForm: View {
    var fx: [String: FXQuote]
    var onCancel: () -> Void
    var onSave: (Double?, Double?, String, Bool) -> Void
    @State private var usd = ""
    @State private var hkd = ""
    @State private var token = ""
    @State private var clearToken = false
    @State private var error: String?

    var body: some View {
        FormSheet(title: "汇率与美股备用源", error: error, onCancel: onCancel, onSave: save) {
            formRow("美元汇率") { TextField("1 美元折合人民币", text: $usd) }
            formRow("港币汇率") { TextField("1 港币折合人民币", text: $hkd) }
            formRow("Finnhub Token") { SecureField("不修改请留空。填写后美股优先走 Finnhub", text: $token) }
            Toggle("清除已保存的 Token", isOn: $clearToken).foregroundStyle(FiColor.ink)
            Text("这里保存的是手工汇率。点主界面的“刷新行情”会用 Yahoo Finance 覆盖美元和港币汇率。Token 只留在本机，导出 Excel 时不会带出。")
                .font(.system(size: 12)).foregroundStyle(FiColor.muted)
        }
        .onAppear {
            usd = fx["USD"]?.rate.map(decimalText) ?? ""
            hkd = fx["HKD"]?.rate.map(decimalText) ?? ""
        }
    }

    private func save() {
        do {
            let usdValue = try FiFormat.parseNumber(usd, label: "美元汇率")
            let hkdValue = try FiFormat.parseNumber(hkd, label: "港币汇率")
            if let usdValue, usdValue <= 0 { throw LedgerError("美元汇率需要大于 0") }
            if let hkdValue, hkdValue <= 0 { throw LedgerError("港币汇率需要大于 0") }
            onSave(usdValue, hkdValue, token, clearToken)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private func formRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        FieldLabel(title: title)
        content()
            .textFieldStyle(.plain)
            .foregroundStyle(FiColor.cream)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(FiColor.field)
    .overlay(RoundedRectangle(cornerRadius: 4).stroke(FiColor.line))
}

private func checkDate(_ text: String, label: String) throws {
    let raw = text.trimmingCharacters(in: .whitespaces)
    if raw.isEmpty { return }
    if FiFormat.parseDay(raw) == nil { throw LedgerError("\(label)请写成 YYYY-MM-DD") }
}

private func decimalText(_ value: Double) -> String {
    String(format: "%g", value)
}

private func blank(_ text: String) -> String? {
    let raw = text.trimmingCharacters(in: .whitespaces)
    return raw.isEmpty ? nil : raw
}
