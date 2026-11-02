import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Rectangle().fill(FiColor.gold).frame(height: 2)
            Text(model.status)
                .font(.system(size: 12))
                .foregroundStyle(FiColor.muted)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            TabView(selection: $model.page) {
                DashboardView()
                    .tabItem { Label("总览", systemImage: "square.grid.2x2") }
                    .tag(0)
                AccountsView()
                    .tabItem { Label("储蓄", systemImage: "creditcard") }
                    .tag(1)
                HoldingsView()
                    .tabItem { Label("投资", systemImage: "chart.line.uptrend.xyaxis") }
                    .tag(2)
                ExpensesView()
                    .tabItem { Label("支出", systemImage: "list.bullet") }
                    .tag(3)
                MoreView()
                    .tabItem { Label("更多", systemImage: "ellipsis") }
                    .tag(4)
            }
            .tint(FiColor.gold)
        }
        .background(FiColor.background)
        .preferredColorScheme(.dark)
        .task { await model.pull() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.pull() } }
        }
        .alert("gxyFi", isPresented: alertPresented) {
            Button("好") { model.alert = nil }
        } message: {
            Text(model.alert ?? "")
        }
        .fileExporter(
            isPresented: $model.showExport,
            document: model.exportDocument,
            contentType: FiFile.xlsx,
            defaultFilename: model.exportName
        ) { result in
            switch result {
            case .success:
                model.status = "Excel 已交给系统保存"
                model.alert = "请在弹出的位置里选择保存到“文件”或其他 App。"
            case .failure(let error):
                model.alert = error.localizedDescription
            }
        }
    }

    private var alertPresented: Binding<Bool> {
        Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })
    }
}

struct MoreView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    SyncView()
                } label: {
                    moreRow("网页同步", note: model.cloudUser.map { model.cloudExpired ? "\($0) · 登录已过期" : "已连接 \($0)" } ?? "未登录 · 账只在这台手机")
                }
                NavigationLink {
                    PropertyView()
                } label: {
                    moreRow("不动产", note: "现值减去贷款")
                }
                NavigationLink {
                    BudgetView()
                } label: {
                    moreRow("预算", note: "按日历年和类别")
                }
                NavigationLink {
                    MarketView()
                } label: {
                    moreRow("行情", note: "黄金、A 股、美股和汇率")
                }
            }
            .scrollContentBackground(.hidden)
            .background(FiColor.background)
            .navigationTitle("更多")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(model.refreshing ? "刷新中" : "刷新行情") { model.refreshQuotes() }
                        .disabled(model.refreshing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("导出") { model.exportExcel() }
                }
            }
        }
    }

    private func moreRow(_ title: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(FiColor.cream)
            Text(note).font(.system(size: 12)).foregroundStyle(FiColor.muted)
        }
        .padding(.vertical, 4)
        .listRowBackground(FiColor.card)
    }
}

enum FiFile {
    static let xlsx = UTType("org.openxmlformats.spreadsheetml.sheet")
        ?? UTType(filenameExtension: "xlsx")
        ?? .data
}
