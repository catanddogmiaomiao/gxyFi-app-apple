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
            .font(.system(size: 13, weight: kind == .primary ? .semibold : .regular))
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
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
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.custom("Palatino", size: 24))
                .foregroundStyle(FiColor.cream)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(FiColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) { toolbar() }
            content()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(columns, id: \.self) { column in
                    Text(column)
                        .font(.system(size: 12))
                        .foregroundStyle(FiColor.gold)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                                    .font(.system(size: 13))
                                    .foregroundStyle(cell.1)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                            }
                        }
                        .padding(.vertical, 8)
                        .background(selected ? Color(red: 0x2A / 255, green: 0x24 / 255, blue: 0x18 / 255) : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(row.id) }
                        .onTapGesture(count: 2) { onOpen?(row.id) }
                    }
                }
            }
        }
        .background(Color(red: 0x12 / 255, green: 0x17 / 255, blue: 0x1F / 255))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(FiColor.line))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
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

struct MonthBars: View {
    var points: [MonthPoint]

    var body: some View {
        let peak = points.map(\.amount).max() ?? 0
        VStack(alignment: .leading, spacing: 8) {
            Text("近六月支出").font(.system(size: 12)).foregroundStyle(FiColor.gold)
            if peak <= 0 {
                Text("近几个月还没有支出").foregroundStyle(FiColor.muted).frame(maxWidth: .infinity, minHeight: 120)
            } else {
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(points) { point in
                        VStack(spacing: 4) {
                            Text(point.amount > 0 ? String(format: "%.0f", point.amount) : "")
                                .font(.system(size: 10))
                                .foregroundStyle(FiColor.cream)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(FiColor.gold)
                                .frame(height: max(4, 110 * point.amount / peak))
                            Text(String(point.month.suffix(5)))
                                .font(.system(size: 11))
                                .foregroundStyle(FiColor.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 150)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(FiColor.card)
        .overlay(alignment: .top) { Rectangle().fill(FiColor.gold).frame(height: 1) }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(FiColor.line))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

extension Color {
    static func pnl(_ value: Double?) -> Color {
        guard let value, abs(value) > 0.000_000_001 else { return FiColor.flat }
        return value > 0 ? FiColor.up : FiColor.down
    }
}
