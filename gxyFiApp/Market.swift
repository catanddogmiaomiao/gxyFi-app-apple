import CoreFoundation
import Foundation

struct RefreshPayload: Equatable {
    var quotes: [QuoteRecord]
    var fxUpdates: [String: FXQuote]
    var errors: [String]
}

enum Market {
    nonisolated static func prepare(_ input: HoldingInput) throws -> HoldingInput {
        let symbol = try canonicalSymbol(market: input.market, symbol: input.symbol)
        var currency = input.currency.isEmpty ? "CNY" : input.currency
        if input.market == "US" { currency = "USD" }
        if input.market == "A" || input.market == "GOLD" { currency = "CNY" }
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return HoldingInput(
            name: name.isEmpty ? symbol : name,
            symbol: symbol,
            market: input.market,
            quantity: input.quantity,
            currency: currency,
            avgCost: input.avgCost,
            manualPrice: input.manualPrice,
            accountLabel: input.accountLabel,
            note: input.note
        )
    }

    nonisolated static func canonicalSymbol(market: String, symbol: String) throws -> String {
        switch market {
        case "A":
            return String(try sinaSymbol(symbol).dropFirst(2))
        case "US":
            return try yahooSymbol(symbol)
        case "GOLD":
            return try canonicalGold(symbol)
        default:
            let text = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { throw LedgerError("请填写代码") }
            return text
        }
    }

    nonisolated static func refresh(holdings: [HoldingRecord], token: String) async -> RefreshPayload {
        var seen = Set<String>()
        var quotes: [QuoteRecord] = []
        for holding in holdings where ["US", "A", "GOLD"].contains(holding.market) && !holding.symbol.isEmpty {
            let key = "\(holding.market)|\(holding.symbol)"
            if seen.contains(key) { continue }
            seen.insert(key)
            quotes.append(await lookup(market: holding.market, symbol: holding.symbol, token: token))
        }
        var fx: [String: FXQuote] = [:]
        var errors: [String] = []
        for (code, yahoo) in [("USD", "CNY=X"), ("HKD", "HKDCNY=X")] {
            do {
                let parsed = try await fetchFX(yahoo)
                fx[code] = FXQuote(rate: parsed.price, source: "Yahoo Finance", at: parsed.quotedAt)
            } catch {
                errors.append("\(code): \(error.localizedDescription)")
            }
        }
        return RefreshPayload(quotes: quotes, fxUpdates: fx, errors: errors)
    }

    nonisolated static func lookup(market: String, symbol: String, token: String) async -> QuoteRecord {
        do {
            let parsed: ParsedQuote
            let canonical: String
            let currency: String
            switch market {
            case "GOLD":
                parsed = try await fetchGold(symbol)
                canonical = try canonicalGold(symbol)
                currency = "CNY"
            case "A":
                parsed = try await fetchAShare(symbol)
                canonical = String(try sinaSymbol(symbol).dropFirst(2))
                currency = "CNY"
            case "US":
                parsed = try await fetchUS(symbol, token: token)
                canonical = try yahooSymbol(symbol)
                currency = parsed.currency.isEmpty ? "USD" : parsed.currency
            default:
                return failed(market: market, symbol: symbol, message: "其他资产请填写手工现价")
            }
            return QuoteRecord(
                market: market, symbol: canonical, name: parsed.name.isEmpty ? canonical : parsed.name,
                price: parsed.price, prevClose: parsed.prevClose, currency: currency,
                quotedAt: parsed.quotedAt, source: parsed.source, fetchedAt: "", ok: true, message: ""
            )
        } catch {
            let shown = (try? canonicalSymbol(market: market, symbol: symbol)) ?? symbol
            return failed(market: market, symbol: shown, message: error.localizedDescription)
        }
    }

    nonisolated private static func sinaSymbol(_ symbol: String) throws -> String {
        let text = symbol.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: " ", with: "")
        if text.hasPrefix("sh") || text.hasPrefix("sz") || text.hasPrefix("bj") {
            let code = String(text.dropFirst(2))
            if code.count == 6, code.allSatisfy(\.isNumber) { return text }
            throw LedgerError("A 股代码应为 6 位数字，或带 sh/sz/bj 前缀")
        }
        guard text.count == 6, text.allSatisfy(\.isNumber) else {
            throw LedgerError("A 股代码应为 6 位数字，例如 600519")
        }
        if shPrefixes.contains(where: { text.hasPrefix($0) }) { return "sh" + text }
        if szPrefixes.contains(where: { text.hasPrefix($0) }) { return "sz" + text }
        if bjPrefixes.contains(where: { text.hasPrefix($0) }) || text.hasPrefix("4") || text.hasPrefix("8") {
            return "bj" + text
        }
        throw LedgerError("无法识别的 A 股代码")
    }

    nonisolated private static func yahooSymbol(_ symbol: String) throws -> String {
        let text = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().replacingOccurrences(of: ".", with: "-")
        guard text.range(of: #"^[A-Z0-9^=\-]{1,16}$"#, options: .regularExpression) != nil else {
            throw LedgerError("美股代码无效，例如 AAPL 或 BRK.B")
        }
        return text
    }

    nonisolated private static func canonicalGold(_ symbol: String) throws -> String {
        let key = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().replacingOccurrences(of: " ", with: "")
        guard let value = goldSymbols[key] else {
            throw LedgerError("黄金代码请用 Au(T+D)、mAu(T+D)、Ag(T+D) 或 Au99.99")
        }
        return value
    }

    nonisolated private static func fetchGold(_ symbol: String) async throws -> ParsedQuote {
        let canonical = try canonicalGold(symbol)
        let body = "instid=\(percent(canonical, extra: "()"))".data(using: .ascii) ?? Data()
        let data = try await request(
            url: URL(string: "https://www.sge.com.cn/graph/quotations")!,
            headers: [
                "Referer": "https://www.sge.com.cn/",
                "X-Requested-With": "XMLHttpRequest",
                "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            ],
            body: body
        )
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LedgerError("上金所没有返回有效价格")
        }
        var parsed = try parseSGE(object)
        if parsed.name.isEmpty { parsed.name = canonical }
        parsed.source = "上海黄金交易所（延时）"
        return parsed
    }

    nonisolated private static func fetchAShare(_ symbol: String) async throws -> ParsedQuote {
        let sina = try sinaSymbol(symbol)
        var sinaError = "新浪不可用"
        do {
            let data = try await request(
                url: URL(string: "https://hq.sinajs.cn/list=\(sina)")!,
                headers: ["Referer": "https://finance.sina.com.cn"]
            )
            var parsed = try parseSina(decodeGBK(data))
            parsed.source = "新浪财经"
            return parsed
        } catch {
            sinaError = error.localizedDescription
        }
        let prefix = String(sina.prefix(2))
        let code = String(sina.dropFirst(2))
        let secid = "\(prefix == "sh" ? 1 : 0).\(code)"
        let data = try await request(
            url: URL(string: "https://push2.eastmoney.com/api/qt/stock/get?secid=\(secid)&fields=f43,f57,f58,f60,f59")!,
            headers: ["Referer": "https://quote.eastmoney.com/"]
        )
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LedgerError("东方财富没有返回这只代码")
        }
        var parsed = try parseEastMoney(object)
        if parsed.quotedAt.isEmpty { parsed.quotedAt = "回退源，时间以本机刷新为准" }
        parsed.source = "东方财富（新浪失败：\(sinaError)）"
        return parsed
    }

    nonisolated private static func fetchUS(_ symbol: String, token: String) async throws -> ParsedQuote {
        let yahoo = try yahooSymbol(symbol)
        var finnhubError = ""
        if !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let url = URL(string: "https://finnhub.io/api/v1/quote?symbol=\(percent(yahoo))&token=\(percent(token.trimmingCharacters(in: .whitespacesAndNewlines)))")!
                let data = try await request(url: url, headers: [:])
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw LedgerError("Finnhub 没有返回最新价")
                }
                var parsed = try parseFinnhub(object)
                parsed.name = yahoo
                parsed.source = "Finnhub"
                return parsed
            } catch {
                finnhubError = error.localizedDescription
            }
        }
        let data = try await request(
            url: URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(percent(yahoo))?interval=1d&range=5d")!,
            headers: [:]
        )
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LedgerError("Yahoo 没有返回行情")
        }
        var parsed = try parseYahoo(object)
        parsed.source = finnhubError.isEmpty ? "Yahoo Finance" : "Yahoo Finance（Finnhub 失败：\(finnhubError)）"
        return parsed
    }

    nonisolated private static func fetchFX(_ symbol: String) async throws -> ParsedQuote {
        let data = try await request(
            url: URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(percent(symbol))?interval=1d&range=1d")!,
            headers: [:]
        )
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LedgerError("Yahoo 没有返回汇率")
        }
        return try parseYahoo(object)
    }

    nonisolated private static func parseSGE(_ object: [String: Any]) throws -> ParsedQuote {
        let delay = object["delaystr"] as? String ?? ""
        let cutoff = delay.firstMatch(of: /(\d{2}:\d{2}):\d{2}/).map { String($0.1) }
        let times = object["times"] as? [Any] ?? []
        let values = object["data"] as? [Any] ?? []
        var lastPrice: Double?
        var lastTime = ""
        for pair in zip(times, values) {
            let stamp = String(describing: pair.0)
            let raw = String(describing: pair.1)
            if raw.isEmpty || raw == "-" || raw == "null" { continue }
            guard let price = Double(raw), price > 0 else { continue }
            if let cutoff, stamp >= cutoff { continue }
            lastPrice = price
            lastTime = stamp
        }
        if lastPrice == nil, let now = double(object["now"]), now > 0 { lastPrice = now }
        guard let lastPrice else { throw LedgerError("上金所没有返回有效价格") }
        var quoted = delay.trimmingCharacters(in: .whitespacesAndNewlines)
        if !lastTime.isEmpty, !quoted.isEmpty { quoted = "\(quoted) 最新点 \(lastTime)" }
        return ParsedQuote(name: object["heyue"] as? String ?? "", price: lastPrice, prevClose: nil, currency: "CNY", quotedAt: quoted, source: "")
    }

    nonisolated private static func parseSina(_ text: String) throws -> ParsedQuote {
        guard let match = text.firstMatch(of: /="(.*)"/), !String(match.1).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LedgerError("新浪没有返回这只代码")
        }
        let parts = String(match.1).split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4, let priceRaw = Double(parts[3]) else { throw LedgerError("新浪行情字段不完整") }
        let prev = parts[2].isEmpty ? nil : Double(parts[2])
        var price = priceRaw
        if price <= 0, let prev, prev > 0 { price = prev }
        if price <= 0 { throw LedgerError("新浪返回的价格无效") }
        var quoted = ""
        if parts.count > 31, !parts[30].isEmpty { quoted = "\(parts[30]) \(parts[31])".trimmingCharacters(in: .whitespaces) }
        return ParsedQuote(name: parts[0], price: price, prevClose: prev, currency: "CNY", quotedAt: quoted, source: "")
    }

    nonisolated private static func parseEastMoney(_ object: [String: Any]) throws -> ParsedQuote {
        guard let data = object["data"] as? [String: Any], let raw = double(data["f43"]) else {
            throw LedgerError("东方财富没有返回这只代码")
        }
        let scale = pow(10, double(data["f59"]) ?? 2)
        let price = raw / scale
        let prev = double(data["f60"]).map { $0 / scale }
        if price <= 0 { throw LedgerError("东方财富返回的价格无效") }
        return ParsedQuote(name: data["f58"] as? String ?? "", price: price, prevClose: prev, currency: "CNY", quotedAt: "", source: "")
    }

    nonisolated private static func parseYahoo(_ object: [String: Any]) throws -> ParsedQuote {
        guard let chart = object["chart"] as? [String: Any] else { throw LedgerError("Yahoo 没有返回行情") }
        guard let result = (chart["result"] as? [Any])?.first as? [String: Any] else {
            let error = ((chart["error"] as? [String: Any])?["description"] as? String) ?? "Yahoo 没有返回行情"
            throw LedgerError(error)
        }
        let meta = result["meta"] as? [String: Any] ?? [:]
        guard let price = double(meta["regularMarketPrice"]) else { throw LedgerError("Yahoo 没有返回最新价") }
        let prev = double(meta["chartPreviousClose"]) ?? double(meta["previousClose"])
        var quoted = ""
        if let stamp = double(meta["regularMarketTime"]) {
            quoted = FiFormat.stamp(Date(timeIntervalSince1970: stamp))
        }
        return ParsedQuote(
            name: (meta["shortName"] as? String) ?? (meta["symbol"] as? String) ?? "",
            price: price, prevClose: prev, currency: meta["currency"] as? String ?? "", quotedAt: quoted, source: ""
        )
    }

    nonisolated private static func parseFinnhub(_ object: [String: Any]) throws -> ParsedQuote {
        guard let price = double(object["c"]), price != 0 else { throw LedgerError("Finnhub 没有返回最新价") }
        var quoted = ""
        if let stamp = double(object["t"]), stamp != 0 {
            quoted = FiFormat.stamp(Date(timeIntervalSince1970: stamp))
        }
        return ParsedQuote(name: "", price: price, prevClose: double(object["pc"]), currency: "USD", quotedAt: quoted, source: "")
    }

    nonisolated private static func request(url: URL, headers: [String: String], body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LedgerError("请求失败 \(http.statusCode)")
        }
        return data
    }

    nonisolated private static func decodeGBK(_ data: Data) -> String {
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        return String(data: data, encoding: encoding) ?? ""
    }

    nonisolated private static func percent(_ text: String, extra: String = "") -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.insert(charactersIn: extra)
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    nonisolated private static func double(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    nonisolated private static func failed(market: String, symbol: String, message: String) -> QuoteRecord {
        QuoteRecord(market: market, symbol: symbol, name: "", price: nil, prevClose: nil, currency: "", quotedAt: "", source: "", fetchedAt: "", ok: false, message: message)
    }

    private struct ParsedQuote {
        var name: String
        var price: Double
        var prevClose: Double?
        var currency: String
        var quotedAt: String
        var source: String
    }

    nonisolated private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
    nonisolated private static let shPrefixes = ["60", "68", "69", "50", "51", "52", "56", "58", "11", "90"]
    nonisolated private static let szPrefixes = ["00", "30", "12", "15", "16", "18", "20"]
    nonisolated private static let bjPrefixes = ["43", "83", "87", "92"]
    nonisolated private static let goldSymbols = [
        "AU(T+D)": "Au(T+D)", "MAU(T+D)": "mAu(T+D)", "AG(T+D)": "Ag(T+D)",
        "AU99.99": "Au99.99", "AU99.95": "Au99.95", "AU100G": "Au100g", "IAU99.99": "iAu99.99",
    ]
}
