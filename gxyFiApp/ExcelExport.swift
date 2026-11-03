import Foundation

enum WorkbookExport {
    static func write(ledger: Ledger, to url: URL) throws {
        let summary = ledger.portfolioSummary()
        var sheets: [(String, String)] = []
        sheets.append(("总览", overview(summary)))
        sheets.append(("汇率", table(
            ["币种", "每 1 单位折合人民币", "来源", "行情时间"],
            summary.fx.map { code, item in
                [Cell.text(code), Cell.number(item.rate, "0.0000"), Cell.text(item.source), Cell.text(item.at)]
            }.sorted { $0[0].text < $1[0].text }
        )))
        sheets.append(("账户", table(
            ["账户", "机构", "类型", "币种", "最近余额", "截止日期", "折合人民币", "距今天数", "备注"],
            summary.accounts.map {
                [.text($0.name), .text($0.institution), .text($0.kind), .text($0.currency), .number($0.balance), .date($0.asOfDate), .number($0.cny), .number($0.age.map(Double.init), "0"), .text($0.note)]
            }
        )))
        sheets.append(("余额快照", table(
            ["账户", "机构", "币种", "日期", "余额", "备注"],
            ledger.allBalances().map { [.text($0.accountName), .text($0.institution), .text($0.currency), .date($0.asOfDate), .number($0.balance), .text($0.note)] }
        )))
        sheets.append(("投资持仓", table(
            ["名称", "代码", "市场", "数量", "币种", "成本价", "现价", "收益率", "价格来源", "行情时间",
             "成本（人民币）", "市值（人民币）", "浮盈（人民币）", "占比", "账户", "备注"],
            summary.holdings.map {
                [.text($0.name), .text($0.symbol), .text(LedgerKind.marketLabel[$0.market] ?? $0.market), .number($0.quantity, "0.0000"), .text($0.currency), .number($0.avgCost, "0.0000"), .number($0.price, "0.0000"), .number(FiFormat.round4($0.ret), "0.00%"), .text($0.source), .text($0.quotedAt), .number(FiFormat.round2($0.costCny)), .number(FiFormat.round2($0.cny)), .number(FiFormat.round2($0.pnlCny)), .number(FiFormat.round4($0.weight), "0.00%"), .text($0.accountLabel), .text($0.note)]
            }
        )))
        sheets.append(("不动产", table(
            ["名称", "类型", "城市", "地址", "面积平方米", "购入日", "购入价", "现值", "估值日", "贷款余额", "净值", "月租金", "备注"],
            summary.properties.map {
                [.text($0.name), .text($0.kind), .text($0.city), .text($0.address), .number($0.areaSqm), .date($0.acquiredOn), .number($0.purchasePrice), .number($0.currentValue), .date($0.valuedOn), .number($0.mortgageBalance), .number($0.equity), .number($0.monthlyRent), .text($0.note)]
            }
        )))
        sheets.append(("支出", table(
            ["日期", "类别", "金额（人民币）", "对象", "备注"],
            ledger.expenses().map { [.date($0.occurredOn), .text($0.category), .number($0.amount), .text($0.payee), .text($0.note)] }
        )))
        sheets.append(("预算", table(
            ["年份", "类别", "年度预算（人民币）", "备注"],
            ledger.budgetLines().map { [.number(Double($0.year), "0"), .text($0.category), .number($0.amount), .text($0.note)] }
        )))
        sheets.append(("行情", table(
            ["市场", "代码", "名称", "价格", "昨收", "币种", "行情时间", "来源", "本机刷新时间", "状态", "说明"],
            ledger.quotes().map {
                [.text(LedgerKind.marketLabel[$0.market] ?? $0.market), .text($0.symbol), .text($0.name), .number($0.price, "0.0000"), .number($0.prevClose, "0.0000"), .text($0.currency), .text($0.quotedAt), .text($0.source), .text($0.fetchedAt), .text($0.ok ? "成功" : "失败"), .text($0.message)]
            }
        )))
        let bytes = try package(sheets)
        try bytes.write(to: url, options: .atomic)
    }

    private static func overview(_ summary: PortfolioSummary) -> String {
        let rows: [[Cell]] = [
            [.text("储蓄"), .number(summary.savingsCNY), .text("各账户最近一次手工余额")],
            [.text("投资市值"), .number(summary.investCNY), .text("手工现价优先，否则用最近行情")],
            [.text("不动产净值"), .number(summary.propertyEquityCNY), .text("现值减去登记的贷款余额")],
            [.text("净资产"), .number(summary.netCNY), .text("以上三项合计")],
            [.text("本月支出"), .number(summary.monthExpense), .text(String(summary.today.prefix(7)))],
            [.text("本年预算"), .number(summary.budgetTotal), .text(String(summary.today.prefix(4)))],
            [.text("本年已支出"), .number(summary.yearExpense), .text("")],
        ]
        let note = "本表由 gxyFi 导出，只反映手工台账和最近一次行情估值。行情有延迟，不构成投资建议。贷款若已在账户里记成负数，就不要在不动产里再填贷款余额。"
        return table(["指标", "金额（人民币）", "备注"], rows, extra: "<c r=\"E1\" s=\"1\" t=\"inlineStr\"><is><t>说明</t></is></c>", note: note)
    }

    private static func table(_ headers: [String], _ records: [[Cell]], extra: String = "", note: String = "") -> String {
        var xml = sheetOpen()
        xml += "<sheetData>"
        xml += "<row r=\"1\" ht=\"22\" customHeight=\"1\">"
        for (index, header) in headers.enumerated() {
            xml += "<c r=\"\(column(index + 1))1\" s=\"1\" t=\"inlineStr\"><is><t>\(escape(header))</t></is></c>"
        }
        xml += extra
        xml += "</row>"
        for (rowIndex, record) in records.enumerated() {
            let row = rowIndex + 2
            xml += "<row r=\"\(row)\">"
            for (index, cell) in record.enumerated() {
                xml += cell.xml(reference: "\(column(index + 1))\(row)")
            }
            if row == 2, !note.isEmpty {
                xml += "<c r=\"E2\" s=\"4\" t=\"inlineStr\"><is><t>\(escape(note))</t></is></c>"
            }
            xml += "</row>"
        }
        xml += "</sheetData>"
        let last = max(records.count + 1, 1)
        let lastColumn = column(headers.count)
        xml += "<autoFilter ref=\"A1:\(lastColumn)\(last)\"/>"
        if !note.isEmpty { xml += "<mergeCells count=\"1\"><mergeCell ref=\"E2:G5\"/></mergeCells>" }
        xml += sheetClose()
        return xml
    }

    private static func package(_ sheets: [(String, String)]) throws -> Data {
        var items: [(String, Data)] = []
        items.append(("[Content_Types].xml", contentTypes(sheets.count).data(using: .utf8)!))
        items.append(("_rels/.rels", rootRels.data(using: .utf8)!))
        items.append(("docProps/core.xml", coreXML.data(using: .utf8)!))
        items.append(("docProps/app.xml", appXML(sheets.map(\.0)).data(using: .utf8)!))
        items.append(("xl/styles.xml", styles.data(using: .utf8)!))
        items.append(("xl/workbook.xml", workbook(sheets.map(\.0)).data(using: .utf8)!))
        items.append(("xl/_rels/workbook.xml.rels", workbookRels(sheets.count).data(using: .utf8)!))
        for (index, sheet) in sheets.enumerated() {
            items.append(("xl/worksheets/sheet\(index + 1).xml", sheet.1.data(using: .utf8)!))
        }
        return ZipStore.archive(items)
    }

    private static func contentTypes(_ count: Int) -> String {
        var overrides = ""
        for index in 1...count {
            overrides += "<Override PartName=\"/xl/worksheets/sheet\(index).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
        <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
        \(overrides)
        </Types>
        """
    }

    private static func workbook(_ names: [String]) -> String {
        let sheets = names.enumerated().map { index, name in
            "<sheet name=\"\(escape(name))\" sheetId=\"\(index + 1)\" r:id=\"rId\(index + 1)\"/>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets>\(sheets)</sheets>
        </workbook>
        """
    }

    private static func workbookRels(_ count: Int) -> String {
        var items = (1...count).map {
            "<Relationship Id=\"rId\($0)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\($0).xml\"/>"
        }.joined()
        items += "<Relationship Id=\"rId\(count + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(items)</Relationships>"
    }

    private static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
    <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
    </Relationships>
    """

    private static let coreXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:creator>gxyFi</dc:creator><dc:title>gxyFi 家庭资产台账</dc:title>
    </cp:coreProperties>
    """

    private static func appXML(_ names: [String]) -> String {
        "<Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\"><Application>gxyFi</Application><TitlesOfParts><vt:vector xmlns:vt=\"http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes\" size=\"\(names.count)\" baseType=\"lpstr\">\(names.map { "<vt:lpstr>\(escape($0))</vt:lpstr>" }.joined())</vt:vector></TitlesOfParts></Properties>"
    }

    private static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    <fonts count="3">
    <font><sz val="11"/><name val="Calibri"/></font>
    <font><b/><sz val="11"/><color rgb="FFF4E7C6"/><name val="Calibri"/></font>
    <font><i/><sz val="10"/><color rgb="FF6B6560"/><name val="Calibri"/></font>
    </fonts>
    <fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF1C1914"/></patternFill></fill></fills>
    <borders count="2"><border/><border><left style="thin"><color rgb="FFE6E0D6"/></left><right style="thin"><color rgb="FFE6E0D6"/></right><top style="thin"><color rgb="FFE6E0D6"/></top><bottom style="thin"><color rgb="FFE6E0D6"/></bottom></border></borders>
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
    <cellXfs count="8">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment horizontal="center"/></xf>
    <xf numFmtId="2" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1"/>
    <xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1"/>
    <xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment wrapText="1" vertical="top"/></xf>
    <xf numFmtId="165" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1"/>
    <xf numFmtId="1" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1"/>
    <xf numFmtId="10" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1"/>
    </cellXfs>
    <numFmts count="2"><numFmt numFmtId="164" formatCode="yyyy-mm-dd"/><numFmt numFmtId="165" formatCode="0.0000"/></numFmts>
    </styleSheet>
    """

    private static func sheetOpen() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetViews><sheetView workbookViewId="0" zoomScale="110"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
        """
    }

    private static func sheetClose() -> String {
        """
        <pageMargins left="0.5" right="0.5" top="0.7" bottom="0.6" header="0.3" footer="0.3"/>
        <pageSetup orientation="landscape" paperSize="9" fitToWidth="1" fitToHeight="0"/>
        <headerFooter><oddHeader>&amp;LgxyFi</oddHeader><oddFooter>&amp;L台账导出，不构成投资建议&amp;R第 &amp;P 页</oddFooter></headerFooter>
        </worksheet>
        """
    }

    private static func column(_ index: Int) -> String {
        var value = index
        var letters = ""
        while value > 0 {
            let remainder = (value - 1) % 26
            letters = String(UnicodeScalar(65 + remainder)!) + letters
            value = (value - 1) / 26
        }
        return letters
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private enum Cell {
        case string(String)
        case amount(Double?, String)
        case day(String?)

        static func text(_ value: String) -> Cell { .string(value) }
        static func number(_ value: Double?, _ format: String = "#,##0.00") -> Cell { .amount(value, format) }
        static func date(_ value: String?) -> Cell { .day(value) }

        var text: String {
            if case .string(let value) = self { return value }
            return ""
        }

        func xml(reference: String) -> String {
            switch self {
            case .string(let value):
                return "<c r=\"\(reference)\" s=\"0\" t=\"inlineStr\"><is><t>\(WorkbookExport.escape(value))</t></is></c>"
            case .amount(let value, let format):
                guard let value else { return "<c r=\"\(reference)\" s=\"0\"/>" }
                let style = ["0.0000": 5, "0": 6, "0.00%": 7][format] ?? 2
                return "<c r=\"\(reference)\" s=\"\(style)\"><v>\(value)</v></c>"
            case .day(let value):
                guard let value, let serial = excelSerial(value) else {
                    return "<c r=\"\(reference)\" s=\"0\" t=\"inlineStr\"><is><t></t></is></c>"
                }
                return "<c r=\"\(reference)\" s=\"3\"><v>\(serial)</v></c>"
            }
        }
    }
}

private func excelSerial(_ text: String) -> Double? {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    guard let date = formatter.date(from: String(text.prefix(10))),
          let epoch = formatter.date(from: "1899-12-30") else { return nil }
    return date.timeIntervalSince(epoch) / 86_400
}

private enum ZipStore {
    static func archive(_ items: [(String, Data)]) -> Data {
        var output = Data()
        var central = Data()
        var offset: UInt32 = 0
        for (name, data) in items {
            let filename = Data(name.utf8)
            let crc = crc32(data)
            let size = UInt32(data.count)
            var local = Data()
            local.append(le32(0x04034b50))
            local.append(le16(20)); local.append(le16(0)); local.append(le16(0))
            local.append(le16(0)); local.append(le16(0))
            local.append(le32(crc)); local.append(le32(size)); local.append(le32(size))
            local.append(le16(UInt16(filename.count))); local.append(le16(0))
            local.append(filename); local.append(data)
            var entry = Data()
            entry.append(le32(0x02014b50))
            entry.append(le16(20)); entry.append(le16(20))
            entry.append(le16(0)); entry.append(le16(0)); entry.append(le16(0)); entry.append(le16(0))
            entry.append(le32(crc)); entry.append(le32(size)); entry.append(le32(size))
            entry.append(le16(UInt16(filename.count))); entry.append(le16(0)); entry.append(le16(0))
            entry.append(le16(0)); entry.append(le16(0)); entry.append(le32(0)); entry.append(le32(offset))
            entry.append(filename)
            output.append(local)
            central.append(entry)
            offset += UInt32(local.count)
        }
        let start = UInt32(output.count)
        output.append(central)
        output.append(le32(0x06054b50))
        output.append(le16(0)); output.append(le16(0))
        output.append(le16(UInt16(items.count))); output.append(le16(UInt16(items.count)))
        output.append(le32(UInt32(central.count))); output.append(le32(start)); output.append(le16(0))
        return output
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func le16(_ value: UInt16) -> Data { Data([UInt8(value & 0xFF), UInt8(value >> 8)]) }
    private static func le32(_ value: UInt32) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)])
    }
}
