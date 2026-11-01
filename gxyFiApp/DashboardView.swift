import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let summary = model.summary
        let missing = missingNotes(summary)
        PageChrome(
            title: "总览",
            subtitle: "储蓄看最近一次手工余额，投资看持仓乘以现价，不动产看现值减去贷款。右上角可以导出全部 Excel。本机账本不会自动上传到网站。"
        ) {
            EmptyView()
        } content: {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                MetricCard(title: "储蓄", value: FiFormat.cny(summary.savingsCNY), note: "\(summary.accounts.count) 个账户" + (summary.savingsMissing ? " · 有余额未折算" : ""))
                MetricCard(title: "投资", value: FiFormat.cny(summary.investCNY), note: "\(summary.holdings.count) 笔持仓" + (summary.unpriced > 0 ? " · \(summary.unpriced) 笔无价格" : ""))
                MetricCard(title: "不动产净值", value: FiFormat.cny(summary.propertyEquityCNY), note: "登记月租金 \(FiFormat.cny(summary.rentMonthly))")
                MetricCard(title: "净资产", value: FiFormat.cny(summary.netCNY), note: missing.isEmpty ? "储蓄 + 投资 + 不动产净值" : missing.joined(separator: " · "))
                MetricCard(title: "本月支出", value: FiFormat.cny(summary.monthExpense), note: String(summary.today.prefix(7)))
                MetricCard(
                    title: "本年预算",
                    value: FiFormat.cny(summary.budgetTotal),
                    note: "已支出 \(FiFormat.cny(summary.yearExpense)) · " + (summary.budgetTotal == 0 ? "尚未设置预算" : "已用 \(FiFormat.percent(summary.budgetRatio))")
                )
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("资产结构").font(.system(size: 12)).foregroundStyle(FiColor.gold)
                    MixBar(parts: [("储蓄", summary.savingsCNY), ("投资", summary.investCNY), ("不动产", summary.propertyEquityCNY)])
                }
                MonthBars(points: summary.monthlyExpenses)
            }
            Text(staleText(summary))
                .font(.system(size: 12))
                .foregroundStyle(FiColor.muted)
        }
    }

    private func missingNotes(_ summary: PortfolioSummary) -> [String] {
        var notes: [String] = []
        if summary.savingsMissing || summary.investMissing { notes.append("有外币还没有汇率") }
        if summary.unpriced > 0 { notes.append("\(summary.unpriced) 笔持仓没有价格") }
        if summary.propertyMissing { notes.append("有不动产未填现值") }
        return notes
    }

    private func staleText(_ summary: PortfolioSummary) -> String {
        guard !summary.staleAccounts.isEmpty else {
            return "余额按你手工录入的快照计算。投资价格优先用手工现价，没有时才用行情。"
        }
        let names = summary.staleAccounts.prefix(4).map { "\($0.name)（\($0.age ?? 0) 天）" }.joined(separator: "、")
        return "这些账户超过 \(LedgerKind.staleDays) 天没有更新余额：\(names)"
    }
}
