import Foundation

struct SyncEntry: Codable {
    var updatedAt: Date
    var deleted: Bool
}

/// 远端 index.json：记录每个对话的最后修改时间和是否已删除。
struct SyncIndex: Codable {
    var entries: [String: SyncEntry] = [:]
}

enum SyncError: LocalizedError {
    case auth
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .auth: return "WebDAV 账号或密码错误"
        case .http(let code): return "WebDAV 请求失败（HTTP \(code)）"
        }
    }
}

struct WebDAVClient {
    let folder: URL
    let authorization: String

    init?(urlString: String, user: String, password: String) {
        var base = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !user.isEmpty else { return nil }
        if !base.hasSuffix("/") { base += "/" }
        guard let url = URL(string: base + "ClaudeChat/") else { return nil }
        folder = url
        authorization = "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
    }

    func ensureFolder() async throws {
        let (_, code) = try await perform("MKCOL", folder)
        // 201 新建成功；405 表示目录已存在
        guard [200, 201, 301, 405].contains(code) else { throw SyncError.http(code) }
    }

    func get(_ name: String) async throws -> Data? {
        let (data, code) = try await perform("GET", folder.appendingPathComponent(name))
        if code == 404 { return nil }
        guard (200..<300).contains(code) else { throw SyncError.http(code) }
        return data
    }

    func put(_ name: String, data: Data) async throws {
        let (_, code) = try await perform("PUT", folder.appendingPathComponent(name), body: data)
        guard (200..<300).contains(code) else { throw SyncError.http(code) }
    }

    func delete(_ name: String) async throws {
        _ = try await perform("DELETE", folder.appendingPathComponent(name))
    }

    func fetchIndex() async throws -> SyncIndex {
        guard let data = try await get("index.json") else { return SyncIndex() }
        return try JSONDecoder().decode(SyncIndex.self, from: data)
    }

    func putIndex(_ index: SyncIndex) async throws {
        try await put("index.json", data: JSONEncoder().encode(index))
    }

    private func perform(_ method: String, _ url: URL, body: Data? = nil) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { throw SyncError.auth }
        return (data, code)
    }
}
