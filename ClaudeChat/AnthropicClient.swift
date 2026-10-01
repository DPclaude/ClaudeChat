import Foundation

enum APIError: LocalizedError {
    case badURL
    case http(Int, String)
    case stream(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "API 地址无效"
        case .http(let code, let message): return "HTTP \(code)：\(message)"
        case .stream(let message): return message
        }
    }
}

/// Anthropic Messages API 格式（/v1/messages）的流式客户端，兼容中转站。
struct AnthropicClient {
    let host: String
    let apiKey: String

    var endpoint: URL? {
        var base = host.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/v1/messages") { return URL(string: base) }
        if base.hasSuffix("/v1") { return URL(string: base + "/messages") }
        return URL(string: base + "/v1/messages")
    }

    func stream(model: String, system: String, maxTokens: Int, effort: String,
                messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try self.makeRequest(model: model, system: system, maxTokens: maxTokens,
                                                       effort: effort, messages: messages)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if status != 200 {
                        var data = Data()
                        for try await byte in bytes {
                            data.append(byte)
                            if data.count > 16_384 { break }
                        }
                        throw APIError.http(status, Self.errorMessage(from: data))
                    }
                    for try await line in bytes.lines {
                        if let text = try Self.parse(line: line) {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeRequest(model: String, system: String, maxTokens: Int, effort: String,
                             messages: [ChatMessage]) throws -> URLRequest {
        guard let url = endpoint else { throw APIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "messages": messages.compactMap(Self.encode),
        ]
        if !system.isEmpty { body["system"] = system }
        if !effort.isEmpty { body["output_config"] = ["effort": effort] }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func encode(_ message: ChatMessage) -> [String: Any]? {
        if message.isError { return nil }
        if message.role == .assistant {
            guard !message.text.isEmpty else { return nil }
            return ["role": "assistant", "content": message.text]
        }

        var blocks: [[String: Any]] = []
        for attachment in message.attachments {
            switch attachment.kind {
            case .image:
                blocks.append([
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": attachment.mediaType,
                        "data": attachment.data.base64EncodedString(),
                    ],
                ])
            case .pdf:
                blocks.append([
                    "type": "document",
                    "source": [
                        "type": "base64",
                        "media_type": "application/pdf",
                        "data": attachment.data.base64EncodedString(),
                    ],
                ])
            case .text:
                let content = String(decoding: attachment.data, as: UTF8.self)
                blocks.append(["type": "text", "text": "附件《\(attachment.name)》内容：\n\(content)"])
            }
        }
        if !message.text.isEmpty {
            blocks.append(["type": "text", "text": message.text])
        }
        guard !blocks.isEmpty else { return nil }
        return ["role": "user", "content": blocks]
    }

    private static func parse(line: String) throws -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return nil }

        switch type {
        case "content_block_delta":
            guard let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta" else { return nil }
            return delta["text"] as? String
        case "message_delta":
            let stop = (event["delta"] as? [String: Any])?["stop_reason"] as? String
            if stop == "max_tokens" { return "\n\n（已达到最大输出长度）" }
            if stop == "refusal" { return "\n\n（模型拒绝了这个请求）" }
            return nil
        case "error":
            let message = (event["error"] as? [String: Any])?["message"] as? String
            throw APIError.stream(message ?? "流式响应出错")
        default:
            return nil
        }
    }

    private static func errorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
                return message
            }
            if let message = object["message"] as? String {
                return message
            }
        }
        let text = String(decoding: data, as: UTF8.self)
        return text.isEmpty ? "无响应内容" : String(text.prefix(300))
    }
}
