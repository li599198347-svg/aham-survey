import Foundation

/// LLM 服务协议 — 平台级，所有模块共享
protocol LLMProvider: Sendable {
    func chat(messages: [LLMMessage], options: LLMOptions) async throws -> String
    func chatStream(messages: [LLMMessage], options: LLMOptions) -> AsyncThrowingStream<String, Error>
    func testConnection() async -> Bool
}

/// 消息角色
enum LLMRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

/// 聊天消息
struct LLMMessage: Codable, Sendable {
    let role: LLMRole
    let content: String
}

/// 调用选项
struct LLMOptions: Sendable {
    var maxTokens: Int = 600
    var temperature: Double = 0.3
    var timeout: TimeInterval = 8
    var enableThinking: Bool = false  // Qwen3: 关闭深度思考，用快速模式

    static let `default` = LLMOptions()
    static let polishing = LLMOptions(maxTokens: 500, timeout: 10)
    static let followup = LLMOptions(maxTokens: 400, timeout: 8)
    static let document = LLMOptions(maxTokens: 1500, timeout: 60)
}

// MARK: - API 配置模型

/// 通用 API 配置（兼容 Dashscope / OpenAI / 任何 OpenAI 兼容端点）
struct LLMConfig: Codable, Equatable {
    var provider: String       // "dashscope", "openai", "custom"
    var endpoint: String       // API base URL
    var apiKey: String
    var model: String

    static let `default` = LLMConfig(
        provider: "dashscope",
        endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1",
        apiKey: "",
        model: "qwen-plus"
    )
}

// MARK: - OpenAI 兼容实现

/// 通用 OpenAI 兼容 API 实现（Dashscope / OpenAI / 第三方）
final class OpenAICompatibleProvider: LLMProvider, @unchecked Sendable {
    private let config: LLMConfig
    private let session: URLSession

    init(config: LLMConfig) {
        self.config = config
        self.session = URLSession(configuration: .default)
    }

    func chat(messages: [LLMMessage], options: LLMOptions) async throws -> String {
        let request = try buildRequest(messages: messages, options: options, stream: false)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        return try parseResponse(data: data)
    }

    func chatStream(messages: [LLMMessage], options: LLMOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try buildRequest(messages: messages, options: options, stream: true)
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        throw LLMError.invalidResponse
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6))
                        if jsonStr == "[DONE]" { break }

                        if let data = jsonStr.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let choices = json["choices"] as? [[String: Any]],
                           let delta = choices.first?["delta"] as? [String: Any],
                           let content = delta["content"] as? String {
                            continuation.yield(content)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func testConnection() async -> Bool {
        let messages = [LLMMessage(role: .user, content: "Hi")]
        let options = LLMOptions(maxTokens: 10, timeout: 5)
        do {
            _ = try await chat(messages: messages, options: options)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private

    private func buildRequest(messages: [LLMMessage], options: LLMOptions, stream: Bool) throws -> URLRequest {
        let endpoint = config.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(endpoint)/chat/completions") else {
            throw LLMError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = options.timeout

        var body: [String: Any] = [
            "model": config.model,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "max_tokens": options.maxTokens,
            "temperature": options.temperature,
            "stream": stream
        ]

        if !options.enableThinking {
            body["enable_thinking"] = false
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func parseResponse(data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.parseError
        }
        return content
    }
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case notConfigured
    case invalidEndpoint
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parseError
    case degraded

    var errorDescription: String? {
        switch self {
        case .notConfigured: "LLM 服务未配置"
        case .invalidEndpoint: "API 端点无效"
        case .invalidResponse: "API 响应无效"
        case .apiError(let code, let msg): "API 错误 (\(code)): \(msg.prefix(100))"
        case .parseError: "响应解析失败"
        case .degraded: "服务已降级，请稍后重试"
        }
    }
}

// MARK: - JSON 解析工具

enum LLMJSONParser {
    /// 容错 JSON 解析：支持原始 JSON、Markdown 代码块、裸 {} 对象
    static func parse(_ text: String) -> Any? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 直接尝试
        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            return json
        }

        // 提取 ```json ... ``` 代码块
        if let range = trimmed.range(of: "```json"),
           let endRange = trimmed.range(of: "```", range: range.upperBound..<trimmed.endIndex) {
            let jsonStr = String(trimmed[range.upperBound..<endRange.lowerBound])
            if let data = jsonStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) {
                return json
            }
        }

        // 提取第一个 { ... } 或 [ ... ]（处理字符串内的转义大括号）
        if let start = trimmed.firstIndex(where: { $0 == "{" || $0 == "[" }) {
            let opener: Character = trimmed[start]
            let closer: Character = opener == "{" ? "}" : "]"
            var depth = 0
            var end = start
            var inString = false
            var prevChar: Character = "\0"
            for i in trimmed[start...].indices {
                let ch = trimmed[i]
                if ch == "\"" && prevChar != "\\" {
                    inString.toggle()
                }
                if !inString {
                    if ch == opener { depth += 1 }
                    if ch == closer { depth -= 1 }
                }
                if depth == 0 { end = i; break }
                prevChar = ch
            }
            let jsonStr = String(trimmed[start...end])
            if let data = jsonStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) {
                return json
            }
        }

        return nil
    }
}
