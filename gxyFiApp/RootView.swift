import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    private let pages = ["总览", "储蓄", "投资", "不动产", "支出", "预算", "行情"]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                Rectangle().fill(FiColor.gold).frame(height: 2)
                topBar
                page
                statusBar
            }
        }
        .background(FiColor.background)
        .preferredColorScheme(.dark)
        .alert("gxyFi", isPresented: alertPresented) {
            Button("好") { model.alert = nil }
        } message: {
            Text(model.alert ?? "")
        }
    }

    private var alertPresented: Binding<Bool> {
        Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 2) {
                Text("gxyFi")
                    .font(.custom("Palatino", size: 26))
                    .foregroundStyle(Color(red: 0xE4 / 255, green: 0xC9 / 255, blue: 0x8A / 255))
                Text("家庭资产台账")
                    .font(.system(size: 12))
                    .foregroundStyle(FiColor.muted)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
            ForEach(Array(pages.enumerated()), id: \.offset) { index, title in
                Button {
                    model.page = index
                } label: {
                    Text(String(format: "%02d    %@", index + 1, title))
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 18)
                        .foregroundStyle(model.page == index ? FiColor.cream : Color(red: 0xA3 / 255, green: 0x9E / 255, blue: 0x94 / 255))
                        .background(model.page == index ? Color(red: 0x16 / 255, green: 0x13 / 255, blue: 0x0E / 255) : Color.clear)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(model.page == index ? FiColor.gold : Color.clear)
                                .frame(width: 2)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("手工记账\n行情只用于估值")
                .font(.system(size: 12))
                .foregroundStyle(FiColor.muted)
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
        }
        .padding(.top, 36)
        .frame(width: 220)
        .background(FiColor.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(FiColor.line).frame(width: 1) }
    }

    private var topBar: some View {
        HStack {
            Text(model.fxLabel)
                .font(.system(size: 12))
                .foregroundStyle(FiColor.muted)
            Spacer()
            FiButton(title: model.refreshing ? "刷新中…" : "刷新行情", disabled: model.refreshing) {
                model.refreshQuotes()
            }
            FiButton(title: "导出 Excel", kind: .primary) { model.exportExcel() }
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
    }

    @ViewBuilder private var page: some View {
        switch model.page {
        case 0: DashboardView()
        case 1: AccountsView()
        case 2: HoldingsView()
        case 3: PropertyView()
        case 4: ExpensesView()
        case 5: BudgetView()
        default: MarketView()
        }
    }

    private var statusBar: some View {
        HStack {
            Text(model.status).lineLimit(1)
            Spacer()
            Text("仅保存在这台电脑")
        }
        .font(.system(size: 12))
        .foregroundStyle(FiColor.muted)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .overlay(alignment: .top) { Rectangle().fill(FiColor.line).frame(height: 1) }
    }
}
