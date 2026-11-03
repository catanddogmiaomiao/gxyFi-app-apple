import SwiftUI

struct AccountsView: View {
    @Environment(AppModel.self) private var model
    @State private var sheet: Sheet?
    @State private var confirmDelete = false
    @State private var deleteBalance = false

    private enum Sheet: Identifiable {
        case account(AccountRecord?)
        case balance(BalanceRecord?)
        var id: String {
            switch self {
            case .account(let value): "account-\(value?.id ?? 0)"
            case .balance(let value): "balance-\(value?.id ?? 0)"
            }
        }
    }

    var body: some View {
        PageChrome(
            title: "储蓄",
            subtitle: "账户余额只来自你定时录入的快照，程序不会去银行取数。修改币种不会换算已经记下的数字。贷款如果记成负余额，不动产页就不要再填贷款。"
        ) {
            FiButton(title: "新增账户", kind: .primary) { sheet = .account(nil) }
            FiButton(title: "编辑账户") { editAccount() }
            FiButton(title: "删除账户", kind: .danger) { confirmDelete = selectedAccount != nil }
            FiButton(title: "录入余额", kind: .primary) { addBalance() }
            FiButton(title: "删除这条余额", kind: .danger) { deleteBalance = selectedBalance != nil }
        } content: {
            VStack(spacing: 12) {
                FiTable(
                    columns: ["账户", "机构", "类型", "币种", "最近余额", "截止日期", "距今", "折合人民币"],
                    rows: model.summary.accounts,
                    selection: model.selectedAccountID,
                    onSelect: { id in
                        model.selectedAccountID = id
                        model.reloadBalances()
                    },
                    onOpen: { _ in editAccount() }
                ) { row in
                    let age = row.age.map { "\($0) 天" } ?? "尚未录入"
                    let ageColor: Color = (row.age == nil || (row.age ?? 0) > LedgerKind.staleDays) ? FiColor.up : FiColor.flat
                    return [
                        (row.name, FiColor.ink), (row.institution.isEmpty ? "—" : row.institution, FiColor.ink),
                        (row.kind, FiColor.ink), (row.currency, FiColor.ink),
                        (row.balance.map { FiFormat.money($0) } ?? "—", FiColor.ink),
                        (row.asOfDate ?? "—", FiColor.ink), (age, ageColor), (FiFormat.cny(row.cny), FiColor.ink),
                    ]
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("选中账户的余额记录").font(.system(size: 12)).foregroundStyle(FiColor.muted)
                    FiTable(
                        columns: ["日期", "余额", "备注"],
                        rows: model.balances,
                        selection: selectedBalanceID,
                        onSelect: { selectedBalanceID = $0 },
                        onOpen: { id in
                            selectedBalanceID = id
                            if let row = model.balances.first(where: { $0.id == id }) { sheet = .balance(row) }
                        }
                    ) { row in
                        [(row.asOfDate, FiColor.ink), (FiFormat.money(row.balance), FiColor.ink), (row.note, FiColor.ink)]
                    }
                }
                .frame(height: 220)
            }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .account(let account):
                AccountForm(initial: account, onCancel: { sheet = nil }) { input in
                    model.saveAccount(input, id: account?.id)
                    sheet = nil
                }
            case .balance(let balance):
                BalanceForm(accounts: model.summary.accounts, initial: balance, presetAccountID: model.selectedAccountID, onCancel: { sheet = nil }) { input in
                    model.saveBalance(input, id: balance?.id)
                    sheet = nil
                }
            }
        }
        .confirmationDialog("删除账户会同时删除它的全部余额快照。", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let id = model.selectedAccountID { model.deleteAccount(id) }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("删除这条余额快照？", isPresented: $deleteBalance, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let id = selectedBalanceID { model.deleteBalance(id) }
            }
            Button("取消", role: .cancel) {}
        }
    }

    @State private var selectedBalanceID: Int64?

    private var selectedAccount: AccountRecord? {
        model.summary.accounts.first { $0.id == model.selectedAccountID }
    }

    private var selectedBalance: BalanceRecord? {
        model.balances.first { $0.id == selectedBalanceID }
    }

    private func editAccount() {
        guard let account = model.ledger.account(model.selectedAccountID ?? -1) else {
            model.alert = "请先选择一个账户。"
            return
        }
        sheet = .account(account)
    }

    private func addBalance() {
        if model.summary.accounts.isEmpty {
            model.alert = "请先新增一个账户，再录入余额。"
            return
        }
        sheet = .balance(nil)
    }
}

struct HoldingsView: View {
    @Environment(AppModel.self) private var model
    @State private var sheet: HoldingRecord??
    @State private var showing = false
    @State private var confirm = false
    @State private var selectedID: Int64?
    @State private var selectedPlanID: Int64?
    @State private var selectedRecordID: Int64?
    @State private var planSheet: DCAPlanRecord??
    @State private var recordSheet: DCARecord??
    @State private var confirmPlan = false
    @State private var confirmRecord = false

    var body: some View {
        let holdings = model.summary.holdings
        let plans = model.summary.dcaPlans
        let records = model.dcaRecords.filter { $0.planID == selectedPlanID }
        PageChrome(
            title: "投资",
            subtitle: "收益率 = 现价 ÷ 成本价 − 1，按原币计算；成本、市值、浮盈按当前汇率折成人民币。当日涨跌看「行情」页。"
                + "基金定投记在下面：先建计划，再记每一期确认。同一只基金不要在两处各记一份份额。"
        ) {
            FiButton(title: "新增持仓", kind: .primary) { sheet = .some(nil); showing = true }
            FiButton(title: "编辑") { edit() }
            FiButton(title: "删除", kind: .danger) { confirm = selected != nil }
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !holdings.isEmpty {
                        Text(totalsText(HoldingTotals(holdings)))
                            .font(.system(size: 13))
                            .foregroundStyle(FiColor.cream)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    FiTable(
                        columns: ["名称", "代码", "市场", "数量", "成本价", "现价", "收益率", "成本¥", "市值¥", "浮盈¥", "占比", "来源"],
                        rows: holdings,
                        selection: selectedID,
                        onSelect: { selectedID = $0 },
                        onOpen: { _ in edit() }
                    ) { row in
                        [
                            (row.name, FiColor.ink), (row.symbol, FiColor.ink),
                            (LedgerKind.marketLabel[row.market] ?? row.market, FiColor.ink),
                            (FiFormat.price(row.quantity), FiColor.ink),
                            row.avgCost == nil ? ("未填", FiColor.flat) : (FiFormat.price(row.avgCost), FiColor.ink),
                            (FiFormat.price(row.price), FiColor.ink), (FiFormat.percent(row.ret), .pnl(row.ret)),
                            (FiFormat.cny(row.costCny), FiColor.ink), (FiFormat.cny(row.cny), FiColor.ink),
                            (FiFormat.cny(row.pnlCny), .pnl(row.pnlCny)), (FiFormat.percent(row.weight), FiColor.ink),
                            (sourceText(row), FiColor.ink),
                        ]
                    }
                    .frame(height: tableHeight(holdings.count))

                    Text("基金定投")
                        .font(.custom("Palatino", size: 20))
                        .foregroundStyle(FiColor.cream)
                        .padding(.top, 6)
                    Text(planSummary(plans))
                        .font(.system(size: 13))
                        .foregroundStyle(FiColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FiButton(title: "新增计划", kind: .primary) { planSheet = .some(nil) }
                            FiButton(title: "编辑计划") { editPlan() }
                            FiButton(title: "删除计划", kind: .danger) { confirmPlan = selectedPlan != nil }
                            FiButton(title: "记一笔", kind: .primary) { addRecord() }
                            FiButton(title: "编辑记录") { editRecord() }
                            FiButton(title: "删除记录", kind: .danger) { confirmRecord = selectedRecord != nil }
                        }
                    }
                    FiTable(
                        columns: ["基金", "代码", "每期", "周期", "状态", "份额", "成本", "净值", "市值¥", "浮盈¥"],
                        rows: plans,
                        selection: selectedPlanID,
                        onSelect: { selectedPlanID = $0; selectedRecordID = nil },
                        onOpen: { selectedPlanID = $0; editPlan() }
                    ) { row in
                        [
                            (row.name, FiColor.ink), (row.symbol, FiColor.ink), (FiFormat.cny(row.amount), FiColor.ink),
                            (row.cycleLabel, FiColor.ink), (row.status, row.status == "进行中" ? FiColor.ink : FiColor.flat),
                            (FiFormat.price(row.shares), FiColor.ink), (FiFormat.cny(row.cost), FiColor.ink),
                            (FiFormat.price(row.nav), FiColor.ink), (FiFormat.cny(row.marketValue), FiColor.ink),
                            (FiFormat.cny(row.pnl), .pnl(row.pnl)),
                        ]
                    }
                    .frame(height: tableHeight(plans.count))

                    if let plan = selectedPlan {
                        Text("「\(plan.name)」的确认记录 · \(records.count) 笔" + (plan.navSource.isEmpty ? "" : " · 净值来自\(plan.navSource)"))
                            .font(.system(size: 13))
                            .foregroundStyle(FiColor.cream)
                        FiTable(
                            columns: ["日期", "类型", "金额", "净值", "份额", "手续费", "备注"],
                            rows: records,
                            selection: selectedRecordID,
                            onSelect: { selectedRecordID = $0 },
                            onOpen: { selectedRecordID = $0; editRecord() }
                        ) { row in
                            [
                                (row.tradeDate, FiColor.ink), (row.kind, FiColor.ink), (FiFormat.cny(row.amount), FiColor.ink),
                                (FiFormat.price(row.nav), FiColor.ink), (FiFormat.price(row.shares), FiColor.ink),
                                (FiFormat.cny(row.fee), FiColor.ink), (row.note, FiColor.ink),
                            ]
                        }
                        .frame(height: tableHeight(records.count))
                    } else if !plans.isEmpty {
                        Text("点一个定投计划，查看每一期的确认记录。")
                            .font(.system(size: 13))
                            .foregroundStyle(FiColor.muted)
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .sheet(isPresented: $showing) {
            HoldingForm(initial: sheet ?? nil, onCancel: { showing = false }) { input in
                let editing = sheet ?? nil
                model.saveHolding(input, id: editing?.id)
                showing = false
            }
        }
        .sheet(isPresented: Binding(get: { planSheet != nil }, set: { if !$0 { planSheet = nil } })) {
            DCAPlanForm(initial: planSheet ?? nil, onCancel: { planSheet = nil }) { input in
                model.saveDCAPlan(input, id: (planSheet ?? nil)?.id)
                planSheet = nil
            }
        }
        .sheet(isPresented: Binding(get: { recordSheet != nil }, set: { if !$0 { recordSheet = nil } })) {
            DCARecordForm(initial: recordSheet ?? nil, onCancel: { recordSheet = nil }) { input in
                if let planID = selectedPlanID {
                    model.saveDCARecord(input, planID: planID, id: (recordSheet ?? nil)?.id)
                }
                recordSheet = nil
            }
        }
        .confirmationDialog("删除这笔持仓？行情缓存还会留着。", isPresented: $confirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let id = selectedID { model.deleteHolding(id) }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("删除这个定投计划？已经记下的确认记录会一起删除。", isPresented: $confirmPlan, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let id = selectedPlanID { model.deleteDCAPlan(id); selectedPlanID = nil }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("删除这条确认记录？", isPresented: $confirmRecord, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let id = selectedRecordID { model.deleteDCARecord(id); selectedRecordID = nil }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var selected: HoldingRecord? { model.summary.holdings.first { $0.id == selectedID } }
    private var selectedPlan: DCAPlanRecord? { model.summary.dcaPlans.first { $0.id == selectedPlanID } }
    private var selectedRecord: DCARecord? { model.dcaRecords.first { $0.id == selectedRecordID && $0.planID == selectedPlanID } }

    private func tableHeight(_ count: Int) -> CGFloat {
        max(CGFloat(count) * 43 + 36, 100)
    }

    private func totalsText(_ totals: HoldingTotals) -> String {
        var text = "市值 \(FiFormat.cny(totals.value)) · 成本 \(FiFormat.cny(totals.cost)) · 浮盈 \(FiFormat.signed(totals.pnl))"
        if let ret = totals.ret { text += "（\(FiFormat.percent(ret))）" }
        if totals.withoutCost > 0 { text += " · \(totals.withoutCost) 笔未填成本，不计入收益" }
        return text
    }

    private func planSummary(_ plans: [DCAPlanRecord]) -> String {
        guard !plans.isEmpty else { return "还没有定投计划。先点「新增计划」，再选中计划「记一笔」。只知道当前份额时记一笔期初。" }
        let value = plans.reduce(0) { $0 + ($1.marketValue ?? 0) }
        let priced = plans.filter { $0.marketValue != nil }
        let cost = priced.reduce(0) { $0 + $1.cost }
        var text = "\(plans.count) 个计划 · 市值 \(FiFormat.cny(value)) · 成本 \(FiFormat.cny(cost)) · 浮盈 \(FiFormat.signed(value - cost))"
        if cost > 0 { text += "（\(FiFormat.percent((value - cost) / cost))）" }
        let unpriced = plans.filter { $0.shares > 0 && $0.nav == nil }.count
        if unpriced > 0 { text += " · \(unpriced) 个没有净值" }
        return text
    }

    private func sourceText(_ row: HoldingRecord) -> String {
        let source = row.source.isEmpty ? "—" : row.source
        return row.quotedAt.isEmpty ? source : "\(source) · \(row.quotedAt)"
    }

    private func edit() {
        guard let selected else {
            model.alert = "请先选择一笔持仓。"
            return
        }
        sheet = selected
        showing = true
    }

    private func editPlan() {
        guard let plan = selectedPlan else {
            model.alert = "请先选择一个定投计划。"
            return
        }
        planSheet = plan
    }

    private func addRecord() {
        guard selectedPlan != nil else {
            model.alert = "请先选择一个定投计划。"
            return
        }
        recordSheet = .some(nil)
    }

    private func editRecord() {
        guard let record = selectedRecord else {
            model.alert = selectedPlan == nil ? "请先选择一个定投计划。" : "请先选择一条确认记录。"
            return
        }
        recordSheet = record
    }
}

struct PropertyView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: PropertyRecord?
    @State private var showing = false
    @State private var isNew = false
    @State private var confirm = false
    @State private var selectedID: Int64?

    var body: some View {
        PageChrome(title: "不动产", subtitle: "金额按人民币登记。净值 = 现值 − 贷款余额。没有填写现值的资产不计入总览。") {
            FiButton(title: "新增", kind: .primary) { isNew = true; editing = nil; showing = true }
            FiButton(title: "编辑") { open() }
            FiButton(title: "删除", kind: .danger) { confirm = selected != nil }
        } content: {
            FiTable(
                columns: ["名称", "类型", "城市", "面积", "购入价", "现值", "贷款", "净值", "月租金"],
                rows: model.summary.properties,
                selection: selectedID,
                onSelect: { selectedID = $0 },
                onOpen: { _ in open() }
            ) { row in
                [
                    (row.name, FiColor.ink), (row.kind, FiColor.ink), (row.city.isEmpty ? "—" : row.city, FiColor.ink),
                    (row.areaSqm.map { FiFormat.money($0) } ?? "—", FiColor.ink),
                    (FiFormat.cny(row.purchasePrice), FiColor.ink), (FiFormat.cny(row.currentValue), FiColor.ink),
                    (FiFormat.cny(row.mortgageBalance), FiColor.ink), (FiFormat.cny(row.equity), FiColor.ink),
                    (FiFormat.cny(row.monthlyRent), FiColor.ink),
                ]
            }
        }
        .sheet(isPresented: $showing) {
            PropertyForm(initial: isNew ? nil : editing, onCancel: { showing = false }) { input in
                model.saveProperty(input, id: isNew ? nil : editing?.id)
                showing = false
            }
        }
        .confirmationDialog("删除这处不动产？", isPresented: $confirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let id = selectedID { model.deleteProperty(id) }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var selected: PropertyRecord? { model.summary.properties.first { $0.id == selectedID } }

    private func open() {
        guard let selected else {
            model.alert = "请先选择一处不动产。"
            return
        }
        editing = model.ledger.properties().first { $0.id == selected.id }
        isNew = false
        showing = true
    }
}
