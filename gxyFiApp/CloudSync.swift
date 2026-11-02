import Foundation
import Security

typealias CloudState = [String: Any]

struct CloudError: LocalizedError {
    var message: String
    var unauthorized = false
    var errorDescription: String? { message }

    static let expired = CloudError(message: "网页端登录已过期，请在「更多 → 网页同步」重新登录。", unauthorized: true)
}

final class CloudClient {
    let base: URL
    var token: String
    private let session: URLSession

    init(base: URL, token: String = "") {
        self.base = base
        self.token = token
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 25
        session = URLSession(configuration: config)
    }

    static func serverURL(_ text: String) throws -> URL {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { throw CloudError(message: "请填写网页端地址") }
        if !raw.contains("://") { raw = "https://" + raw }
        guard var parts = URLComponents(string: raw), let scheme = parts.scheme?.lowercased(),
              let host = parts.host, !host.isEmpty
        else { throw CloudError(message: "网页端地址无效") }
        let local = host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local")
        if scheme != "https", !(scheme == "http" && local) {
            throw CloudError(message: "网页端地址需要以 https:// 开头")
        }
        parts.path = ""
        parts.query = nil
        parts.fragment = nil
        guard let url = parts.url else { throw CloudError(message: "网页端地址无效") }
        return url
    }

    func login(username: String, password: String) async throws {
        let url = base.appending(path: "api/login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["username": username, "password": password])
        let (data, response) = try await send(request)
        guard response.statusCode == 200 else { throw failure(data, response, login: true) }
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }
        let cookie = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url).first { $0.name == "gxyfi_session" }
        guard let value = cookie?.value, !value.isEmpty else {
            throw CloudError(message: "网页端没有返回登录凭证")
        }
        token = value.removingPercentEncoding ?? value
    }

    func logout() async {
        _ = try? await call("api/logout", method: "POST", body: [:])
    }

    func state() async throws -> CloudState {
        try await call("api/state", method: "GET", body: nil)
    }

    func mutate(_ entity: String, op: String, id: Int64? = nil, data: [String: Any] = [:]) async throws -> CloudState {
        var body: [String: Any] = ["entity": entity, "op": op, "data": data]
        if let id { body["id"] = id }
        return try await call("api/mutate", method: "POST", body: body)
    }

    func refreshQuotes() async throws -> CloudState {
        try await call("api/quotes/refresh", method: "POST", body: [:])
    }

    private func call(_ path: String, method: String, body: [String: Any]?) async throws -> CloudState {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await send(request)
        if response.statusCode == 401 { throw CloudError.expired }
        guard (200..<300).contains(response.statusCode) else { throw failure(data, response, login: false) }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? CloudState else {
            throw CloudError(message: "网页端返回的内容无法识别")
        }
        return object
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CloudError(message: "连不上网页端：\(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else { throw CloudError(message: "网页端没有响应") }
        return (data, http)
    }

    private func failure(_ data: Data, _ response: HTTPURLResponse, login: Bool) -> CloudError {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let message = object?["error"] as? String, !message.isEmpty {
            return CloudError(message: message, unauthorized: response.statusCode == 401 && !login)
        }
        return CloudError(message: "网页端返回 \(response.statusCode)")
    }
}

enum CloudUpload {
    /// Replays every record in the phone ledger as creates on the signed-in web account.
    static func run(ledger: Ledger, client: CloudClient) async throws -> Int {
        var state = try await client.state()
        var sent = 0

        var categoryIDs: [Int64: Int64] = [:]
        for category in ledger.categories() {
            if let existing = id(named: category.name, in: state["categories"]) {
                categoryIDs[category.id] = existing
                continue
            }
            state = try await client.mutate("category", op: "create", data: ["name": category.name])
            categoryIDs[category.id] = id(named: category.name, in: state["categories"])
        }

        var accountIDs: [Int64: Int64] = [:]
        for account in ledger.accounts() {
            let before = state
            state = try await client.mutate("account", op: "create", data: [
                "name": account.name, "institution": account.institution, "kind": account.kind,
                "currency": account.currency, "note": account.note,
            ])
            accountIDs[account.id] = newID("accounts", before: before, after: state)
            sent += 1
        }

        for balance in ledger.balanceEntries() {
            guard let accountID = accountIDs[balance.accountID] else { continue }
            state = try await client.mutate("balance", op: "create", data: [
                "account_id": accountID, "as_of_date": balance.asOfDate, "balance": balance.balance, "note": balance.note,
            ])
            sent += 1
        }

        for holding in ledger.holdings() {
            state = try await client.mutate("holding", op: "create", data: holdingData(holding))
            sent += 1
        }

        for property in ledger.properties() {
            state = try await client.mutate("property", op: "create", data: propertyData(property))
            sent += 1
        }

        for expense in ledger.expenses() {
            guard let categoryID = categoryIDs[expense.categoryID] else { continue }
            state = try await client.mutate("expense", op: "create", data: [
                "category_id": categoryID, "occurred_on": expense.occurredOn, "amount": expense.amount,
                "payee": expense.payee, "note": expense.note,
            ])
            sent += 1
        }

        for line in ledger.budgetEntries() {
            guard let categoryID = categoryIDs[line.categoryID] else { continue }
            state = try await client.mutate("budget", op: "upsert", data: [
                "year": line.year, "category_id": categoryID, "amount": line.amount, "note": line.note,
            ])
            sent += 1
        }

        for (code, item) in ledger.fxRates() {
            guard let rate = item.rate, rate > 0 else { continue }
            state = try await client.mutate("fx", op: "upsert", data: ["code": code, "rate": rate])
        }
        return sent
    }

    static func holdingData(_ input: HoldingInput) -> [String: Any] {
        [
            "name": input.name, "symbol": input.symbol, "market": input.market, "quantity": input.quantity,
            "currency": input.currency, "avg_cost": json(input.avgCost), "manual_price": json(input.manualPrice),
            "account_label": input.accountLabel, "note": input.note,
        ]
    }

    static func holdingData(_ holding: HoldingRecord) -> [String: Any] {
        holdingData(HoldingInput(
            name: holding.name, symbol: holding.symbol, market: holding.market, quantity: holding.quantity,
            currency: holding.currency, avgCost: holding.avgCost, manualPrice: holding.manualPrice,
            accountLabel: holding.accountLabel, note: holding.note
        ))
    }

    static func propertyData(_ input: PropertyInput) -> [String: Any] {
        [
            "name": input.name, "kind": input.kind, "city": input.city, "address": input.address,
            "area_sqm": json(input.areaSqm), "acquired_on": json(input.acquiredOn),
            "purchase_price": json(input.purchasePrice), "current_value": json(input.currentValue),
            "valued_on": json(input.valuedOn), "mortgage_balance": input.mortgageBalance,
            "monthly_rent": input.monthlyRent, "note": input.note,
        ]
    }

    static func propertyData(_ property: PropertyRecord) -> [String: Any] {
        propertyData(PropertyInput(
            name: property.name, kind: property.kind, city: property.city, address: property.address,
            areaSqm: property.areaSqm, acquiredOn: property.acquiredOn, purchasePrice: property.purchasePrice,
            currentValue: property.currentValue, valuedOn: property.valuedOn,
            mortgageBalance: property.mortgageBalance, monthlyRent: property.monthlyRent, note: property.note
        ))
    }

    static func json(_ value: Double?) -> Any { value.map { $0 as Any } ?? NSNull() }
    static func json(_ value: String?) -> Any {
        guard let value, !value.isEmpty else { return NSNull() }
        return value
    }

    static func ids(_ list: Any?) -> [Int64] {
        (list as? [[String: Any]] ?? []).compactMap { ($0["id"] as? NSNumber)?.int64Value }
    }

    static func newID(_ key: String, before: CloudState, after: CloudState) -> Int64? {
        let old = Set(ids(before[key]))
        return ids(after[key]).filter { !old.contains($0) }.max()
    }

    private static func id(named name: String, in list: Any?) -> Int64? {
        (list as? [[String: Any]] ?? []).first { ($0["name"] as? String) == name }
            .flatMap { ($0["id"] as? NSNumber)?.int64Value }
    }
}

enum Keychain {
    private static let service = "gxyApp.gxyFiApp.cloud"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ account: String, _ value: String) {
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
