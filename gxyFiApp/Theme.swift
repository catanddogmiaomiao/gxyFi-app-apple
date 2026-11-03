import SwiftUI

enum FiColor {
    static let background = Color(red: 0x0C / 255, green: 0x10 / 255, blue: 0x16 / 255)
    static let sidebar = Color(red: 0x09 / 255, green: 0x0C / 255, blue: 0x11 / 255)
    static let card = Color(red: 0x14 / 255, green: 0x19 / 255, blue: 0x22 / 255)
    static let field = Color(red: 0x10 / 255, green: 0x15 / 255, blue: 0x1C / 255)
    static let gold = Color(red: 0xC6 / 255, green: 0xA1 / 255, blue: 0x5B / 255)
    static let cream = Color(red: 0xF4 / 255, green: 0xE7 / 255, blue: 0xC6 / 255)
    static let ink = Color(red: 0xE7 / 255, green: 0xE1 / 255, blue: 0xD6 / 255)
    static let muted = Color(red: 0x8C / 255, green: 0x87 / 255, blue: 0x7C / 255)
    static let line = Color(red: 0x2C / 255, green: 0x26 / 255, blue: 0x1C / 255)
    static let up = Color(red: 0xC4 / 255, green: 0x78 / 255, blue: 0x6A / 255)
    static let down = Color(red: 0x7F / 255, green: 0x9E / 255, blue: 0x93 / 255)
    static let flat = Color(red: 0xB7 / 255, green: 0xB1 / 255, blue: 0xA6 / 255)
    static let mix = [
        Color(red: 0xC6 / 255, green: 0xA1 / 255, blue: 0x5B / 255),
        Color(red: 0x8C / 255, green: 0x9B / 255, blue: 0xAB / 255),
        Color(red: 0x8A / 255, green: 0x70 / 255, blue: 0x44 / 255),
    ]
    static let selected = Color(red: 0x2A / 255, green: 0x24 / 255, blue: 0x18 / 255)
    static let track = Color(red: 0x1C / 255, green: 0x22 / 255, blue: 0x2C / 255)
    static let categoryPalette = [
        "#C6A15B", "#8C9BAB", "#7F9E93", "#C4786A", "#9A86A6",
        "#D8C79E", "#5F8A8B", "#A0695A", "#8A7044", "#6F7F95",
    ].map(hex)

    /// 按类别的固定顺序分配颜色，同一类别在各个图里颜色一致。
    static func categoryColors(_ names: [String]) -> [String: Color] {
        var colors: [String: Color] = [:]
        for (index, name) in names.enumerated() {
            colors[name] = categoryPalette[index % categoryPalette.count]
        }
        if colors[Spending.other] == nil { colors[Spending.other] = muted }
        return colors
    }

    nonisolated private static func hex(_ text: String) -> Color {
        let value = Int(text.dropFirst(), radix: 16) ?? 0
        return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

struct FiButton: View {
    enum Kind { case primary, ghost, danger }
    var title: String
    var kind: Kind = .ghost
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 15, weight: kind == .primary ? .semibold : .regular))
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(background)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(border, lineWidth: kind == .primary ? 0 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .disabled(disabled)
            .opacity(disabled ? 0.55 : 1)
    }

    private var foreground: Color {
        switch kind {
        case .primary: FiColor.background
        case .ghost: FiColor.ink
        case .danger: FiColor.up
        }
    }

    private var background: Color {
        kind == .primary ? FiColor.gold : .clear
    }

    private var border: Color {
        kind == .danger ? Color(red: 0x6A / 255, green: 0x40 / 255, blue: 0x3A / 255) : FiColor.line
    }
}

struct PageChrome<Toolbar: View, Content: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var toolbar: () -> Toolbar
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.custom("Palatino", size: 28))
                .foregroundStyle(FiColor.cream)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(FiColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { toolbar() }
            }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FiColor.background)
    }
}

struct MetricCard: View {
    var title: String
    var value: String
    var note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12)).foregroundStyle(FiColor.gold)
            Text(value).font(.system(size: 26)).foregroundStyle(FiColor.cream).lineLimit(1).minimumScaleFactor(0.6)
            Text(note).font(.system(size: 12)).foregroundStyle(FiColor.muted).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .background(FiColor.card)
        .overlay(alignment: .top) { Rectangle().fill(FiColor.gold).frame(height: 1) }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(FiColor.line))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct FiTable<Row: Identifiable>: View {
    var columns: [String]
    var rows: [Row]
    var selection: Row.ID?
    var onSelect: (Row.ID) -> Void
    var onOpen: ((Row.ID) -> Void)?
    var cells: (Row) -> [(String, Color)]

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(columns, id: \.self) { column in
                            Text(column)
                                .font(.system(size: 12))
                                .foregroundStyle(FiColor.gold)
                                .frame(width: columnWidth, alignment: .leading)
                                .padding(.horizontal, 8)
                        }
                    }
                    .padding(.vertical, 8)
                    .background(Color(red: 0x1A / 255, green: 0x16 / 255, blue: 0x0F / 255))
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { row in
                                let selected = row.id == selection
                                HStack(spacing: 0) {
                                    ForEach(Array(cells(row).enumerated()), id: \.offset) { _, cell in
                                        Text(cell.0)
                                            .font(.system(size: 15))
                                            .foregroundStyle(cell.1)
                                            .lineLimit(1)
                                            .frame(width: columnWidth, alignment: .leading)
                                            .padding(.horizontal, 8)
                                    }
                                }
                                .padding(.vertical, 12)
                                .background(selected ? Color(red: 0x2A / 255, green: 0x24 / 255, blue: 0x18 / 255) : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(row.id) }
                                .contextMenu {
                                    if onOpen != nil {
                                        Button("编辑") { onOpen?(row.id) }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(minWidth: max(proxy.size.width, CGFloat(columns.count) * columnWidth))
                .frame(height: proxy.size.height)
            }
        }
        .background(Color(red: 0x12 / 255, green: 0x17 / 255, blue: 0x1F / 255))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(FiColor.line))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var columnWidth: CGFloat { 108 }
}

struct MixBar: View {
    var parts: [(String, Double)]

    var body: some View {
        let total = parts.map { max($0.1, 0) }.reduce(0, +)
        VStack(alignment: .leading, spacing: 12) {
            if total <= 0 {
                Text("录入资产后，这里显示储蓄、投资和不动产的结构")
                    .foregroundStyle(FiColor.muted)
                    .frame(maxWidth: .infinity, minHeight: 70)
            } else {
                GeometryReader { proxy in
                    HStack(spacing: 4) {
                        ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(FiColor.mix[index % FiColor.mix.count])
                                .frame(width: max(proxy.size.width * max(part.1, 0) / total - 4, 0))
                        }
                    }
                }
                .frame(height: 18)
                Text(parts.filter { $0.1 > 0 }.map { "\($0.0)  \(Int(($0.1 / total) * 100))%" }.joined(separator: "    "))
                    .font(.system(size: 12))
                    .foregroundStyle(FiColor.muted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(FiColor.card)
        .overlay(alignment: .top) { Rectangle().fill(FiColor.gold).frame(height: 1) }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(FiColor.line))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct FiPanel<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 12)).foregroundStyle(FiColor.gold)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(FiColor.card)
        .overlay(alignment: .top) { Rectangle().fill(FiColor.gold).frame(height: 1) }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(FiColor.line))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// 每个类别一行：名称、占比条、金额与占比。有预算时在条上画出预算线。点一行选中，再点取消。
struct CategoryBars: View {
    var rows: [CategorySpend]
    var colors: [String: Color]
    var budgets: [Int64: Double]
    var selected: Int64?
    var onPick: (Int64?) -> Void

    var body: some View {
        if rows.isEmpty {
            Text("这一期还没有支出。可以记一笔，或在电脑端把导入的明细归类。")
                .font(.system(size: 13))
                .foregroundStyle(FiColor.muted)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            let scale = max(rows.map(\.amount).max() ?? 0, budgets.values.max() ?? 0, 1)
            VStack(spacing: 2) {
                ForEach(rows) { row in
                    line(row, scale: scale)
                }
            }
        }
    }

    private func line(_ row: CategorySpend, scale: Double) -> some View {
        let budget = budgets[row.categoryID]
        let over = budget.map { row.amount > $0 } ?? false
        var detail = "\(row.count) 笔"
        if row.refund != 0 { detail += " · 含退款 \(FiFormat.money(row.refund))" }
        if let budget, budget != 0 { detail += " · 预算 \(Int((row.amount / budget * 100).rounded()))%" }
        return HStack(spacing: 8) {
            Text(row.category)
                .font(.system(size: 14))
                .foregroundStyle(FiColor.cream)
                .lineLimit(1)
                .frame(width: 58, alignment: .leading)
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(FiColor.track)
                    if row.amount > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(colors[row.category] ?? FiColor.gold)
                            .frame(width: max(width * row.amount / scale, 3))
                    }
                    if let budget, budget != 0 {
                        Rectangle()
                            .fill(over ? FiColor.up : FiColor.cream)
                            .frame(width: 2, height: 20)
                            .offset(x: min(width * budget / scale, width - 2))
                    }
                }
                .frame(height: 12)
                .frame(maxHeight: .infinity)
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(FiFormat.money(row.amount))  \(Int((row.share * 100).rounded()))%")
                    .font(.system(size: 13))
                    .foregroundStyle(over ? FiColor.up : FiColor.cream)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(FiColor.muted)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 128, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 4).fill(row.categoryID == selected ? FiColor.selected : .clear))
        .contentShape(Rectangle())
        .onTapGesture { onPick(row.categoryID == selected ? nil : row.categoryID) }
    }
}

/// 近几个月的支出，每月一根柱子，按类别分段。可以点柱子切换到那个月。
struct StackedMonths: View {
    var stack: MonthStack
    var colors: [String: Color]
    var current: String? = nil
    var onPick: ((String) -> Void)? = nil

    var body: some View {
        let totals = stack.keys.map { key in stack.cells[key, default: [:]].values.reduce(0, +) }
        let peak = totals.max() ?? 0
        if peak <= 0 {
            Text("近几个月还没有支出")
                .font(.system(size: 13))
                .foregroundStyle(FiColor.muted)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 4) {
                    ForEach(stack.names, id: \.self) { name in
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(colors[name] ?? FiColor.muted).frame(width: 9, height: 9)
                            Text(name).font(.system(size: 11)).foregroundStyle(FiColor.muted).lineLimit(1)
                        }
                    }
                }
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(stack.keys.enumerated()), id: \.element) { index, key in
                        column(key, total: totals[index], peak: peak)
                    }
                }
                .frame(height: 170)
            }
        }
    }

    private func column(_ key: String, total: Double, peak: Double) -> some View {
        let cells = stack.cells[key, default: [:]]
        return VStack(spacing: 4) {
            Spacer(minLength: 0)
            Text(total > 0 ? FiFormat.money(total, digits: 0) : "")
                .font(.system(size: 10))
                .foregroundStyle(FiColor.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            VStack(spacing: 0) {
                ForEach(stack.names.reversed(), id: \.self) { name in
                    if let value = cells[name], value > 0 {
                        Rectangle()
                            .fill(colors[name] ?? FiColor.muted)
                            .frame(height: max(120 * value / peak, 1))
                    }
                }
            }
            Text("\(Int(key.suffix(2)) ?? 0) 月")
                .font(.system(size: 11))
                .foregroundStyle(FiColor.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 3)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 4).fill(key == current ? FiColor.selected : .clear))
        .contentShape(Rectangle())
        .onTapGesture { onPick?(key) }
    }
}

extension Color {
    static func pnl(_ value: Double?) -> Color {
        guard let value, abs(value) > 0.000_000_001 else { return FiColor.flat }
        return value > 0 ? FiColor.up : FiColor.down
    }
}
