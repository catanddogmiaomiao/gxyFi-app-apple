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

    var body: some View {
        PageChrome(
            title: "投资",
            subtitle: "黄金按克、股票按股。填了手工现价就用手工现价；留空则用刷新到的行情。Au(T+D) 的价格是人民币/克。"
        ) {
            FiButton(title: "新增持仓", kind: .primary) { sheet = .some(nil); showing = true }
            FiButton(title: "编辑") { edit() }
            FiButton(title: "删除", kind: .danger) { confirm = selected != nil }
        } content: {
            FiTable(
                columns: ["名称", "代码", "市场", "数量", "成本价", "现价", "涨跌", "市值¥", "浮盈¥", "来源"],
                rows: model.summary.holdings,
                selection: selectedID,
                onSelect: { selectedID = $0 },
                onOpen: { _ in edit() }
            ) { row in
                [
                    (row.name, FiColor.ink), (row.symbol, FiColor.ink),
                    (LedgerKind.marketLabel[row.market] ?? row.market, FiColor.ink),
                    (FiFormat.price(row.quantity), FiColor.ink), (FiFormat.price(row.avgCost), FiColor.ink),
                    (FiFormat.price(row.price), FiColor.ink), (FiFormat.percent(row.dayChange), .pnl(row.dayChange)),
                    (FiFormat.cny(row.cny), FiColor.ink), (FiFormat.cny(row.pnlCny), .pnl(row.pnlCny)),
                    (row.source.isEmpty ? "—" : row.source, FiColor.ink),
                ]
            }
        }
        .sheet(isPresented: $showing) {
            HoldingForm(initial: sheet ?? nil, onCancel: { showing = false }) { input in
                let editing = sheet ?? nil
                model.saveHolding(input, id: editing?.id)
                showing = false
            }
        }
        .confirmationDialog("删除这笔持仓？行情缓存还会留着。", isPresented: $confirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let id = selectedID { model.deleteHolding(id) }
            }
            Button("取消", role: .cancel) {}
        }
    }

    @State private var selectedID: Int64?
    private var selected: HoldingRecord? { model.summary.holdings.first { $0.id == selectedID } }

    private func edit() {
        guard let selected else {
            model.alert = "请先选择一笔持仓。"
            return
        }
        sheet = selected
        showing = true
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
