import Foundation

private enum LLMHTTP {
    /// 等待首个字节的超时；流式响应开始后不再受限于总时长。
    static let requestTimeout: TimeInterval = 15

    static func makeRequest(url: URL, headers: [String: String], body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// 发起 SSE 请求，逐个产出 `data:` 行解析后的 JSON 对象。
    static func events(for request: URLRequest) -> AsyncThrowingStream<[String: Any], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response): (URLSession.AsyncBytes, URLResponse)
                    do {
                        (bytes, response) = try await URLSession.shared.bytes(for: request)
                    } catch let error as URLError where error.code == .timedOut {
                        throw TranslationError.timeout
                    } catch let error as URLError where error.code == .cancelled {
                        throw CancellationError()
                    } catch {
                        throw TranslationError.network(error.localizedDescription)
                    }

                    guard let http = response as? HTTPURLResponse else {
                        throw TranslationError.invalidResponse
                    }
                    guard (200...299).contains(http.statusCode) else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw TranslationError.network(errorMessage(from: data) ?? "HTTP \(http.statusCode)")
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard
                            let data = payload.data(using: .utf8),
                            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        if let message = errorMessage(from: json) {
                            throw TranslationError.network(message)
                        }
                        continuation.yield(json)
                    }
                    continuation.finish()
                } catch let error as URLError where error.code == .timedOut {
                    continuation.finish(throwing: TranslationError.timeout)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8).flatMap { $0.isEmpty ? nil : String($0.prefix(200)) }
        }
        return errorMessage(from: json)
    }

    private static func errorMessage(from json: [String: Any]) -> String? {
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let message = json["error"] as? String {
            return message
        }
        return nil
    }
}

private enum LLMPrompt {
    static func make(for request: TranslationRequest) -> String {
        switch request.mode {
        case .text:
            return "将以下\(request.sourceName)文本翻译为\(request.targetName)，只输出译文，不要任何解释或额外内容：\n\n\(request.text)"
        case .word:
            return """
            你是一部简明词典。请用\(request.targetName)解释下面这个\(request.sourceName)词语，严格按以下格式输出，不要任何多余说明：
            第一行：音标或读音（没有就省略这一行）
            之后每行一个义项："词性. 释义"，最多 4 行
            最后一行：一个简短例句及其译文（用" — "分隔）

            词语：\(request.text)
            """
        }
    }
}

/// 把增量文本片段累积成"截至目前的完整译文"流。
private func accumulate(
    _ events: AsyncThrowingStream<[String: Any], Error>,
    delta: @escaping ([String: Any]) -> String?
) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            var text = ""
            do {
                for try await event in events {
                    guard let piece = delta(event), !piece.isEmpty else { continue }
                    text += piece
                    continuation.yield(text.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw TranslationError.invalidResponse
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

private func failing(_ error: Error) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { $0.finish(throwing: error) }
}

/// 调用 Anthropic Messages API (`api.anthropic.com/v1/messages`)，SSE 流式输出。
final class AnthropicEngine: TranslationEngine {
    let name = "LLM (Anthropic)"

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    private let settings: AppSettings
    private let keychain: KeychainHelper
    /// 设置页"测试"时用输入框里尚未保存的 Key / 指定模型
    private let apiKeyOverride: String?
    private let modelOverride: String?

    init(settings: AppSettings, keychain: KeychainHelper = .shared, apiKeyOverride: String? = nil, modelOverride: String? = nil) {
        self.settings = settings
        self.keychain = keychain
        self.apiKeyOverride = apiKeyOverride
        self.modelOverride = modelOverride
    }

    func translate(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error> {
        let trimmed = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return failing(TranslationError.emptyInput) }
        guard let apiKey = apiKeyOverride ?? keychain.load(for: .anthropicAPIKey), !apiKey.isEmpty else {
            return failing(TranslationError.apiKeyMissing)
        }

        var request = request
        request.text = trimmed
        let configuredModel = modelOverride ?? MainActor.assumeIsolated { settings.anthropicModel }
        let model = configuredModel.trimmingCharacters(in: .whitespacesAndNewlines)

        let body: [String: Any] = [
            "model": model.isEmpty ? AppSettings.defaultAnthropicModel : model,
            "max_tokens": 4096,
            "stream": true,
            "messages": [
                ["role": "user", "content": LLMPrompt.make(for: request)]
            ]
        ]

        do {
            let urlRequest = try LLMHTTP.makeRequest(
                url: Self.endpoint,
                headers: ["x-api-key": apiKey, "anthropic-version": "2023-06-01"],
                body: body
            )
            // 事件格式：{"type":"content_block_delta","delta":{"type":"text_delta","text":"…"}}
            return accumulate(LLMHTTP.events(for: urlRequest)) { event in
                guard
                    event["type"] as? String == "content_block_delta",
                    let delta = event["delta"] as? [String: Any],
                    delta["type"] as? String == "text_delta"
                else { return nil }
                return delta["text"] as? String
            }
        } catch {
            return failing(TranslationError.invalidResponse)
        }
    }
}

/// 调用任意 OpenAI Chat Completions 兼容接口
/// （OpenAI 官方、Azure OpenAI、DeepSeek、Ollama/LM Studio 本地代理等），SSE 流式输出。
/// Base URL 与模型名由用户在设置里填写。
final class OpenAICompatibleEngine: TranslationEngine {
    let name = "LLM (OpenAI 兼容)"

    private let settings: AppSettings
    private let keychain: KeychainHelper
    /// 设置页"测试"时用输入框里尚未保存的 Key / 指定模型
    private let apiKeyOverride: String?
    private let modelOverride: String?

    init(settings: AppSettings, keychain: KeychainHelper = .shared, apiKeyOverride: String? = nil, modelOverride: String? = nil) {
        self.settings = settings
        self.keychain = keychain
        self.apiKeyOverride = apiKeyOverride
        self.modelOverride = modelOverride
    }

    func translate(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error> {
        let trimmed = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return failing(TranslationError.emptyInput) }

        let (baseURL, configuredModel) = MainActor.assumeIsolated { (settings.openAIBaseURL, settings.openAIModel) }
        let model = modelOverride ?? configuredModel
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let isLocal = trimmedBase.contains("localhost") || trimmedBase.contains("127.0.0.1")

        // 本地模型（Ollama / LM Studio）通常不需要 Key
        let apiKey = apiKeyOverride ?? keychain.load(for: .openAICompatibleAPIKey) ?? ""
        guard !apiKey.isEmpty || isLocal else { return failing(TranslationError.apiKeyMissing) }

        let endpointString = trimmedBase.hasSuffix("/") ? trimmedBase + "chat/completions" : trimmedBase + "/chat/completions"
        guard !trimmedBase.isEmpty, let endpoint = URL(string: endpointString) else {
            return failing(TranslationError.network("LLM Base URL 无效"))
        }
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            return failing(TranslationError.network("尚未设置模型名称"))
        }

        var request = request
        request.text = trimmed
        let body: [String: Any] = [
            "model": trimmedModel,
            "stream": true,
            "messages": [
                ["role": "user", "content": LLMPrompt.make(for: request)]
            ]
        ]

        do {
            let headers = apiKey.isEmpty ? [:] : ["Authorization": "Bearer \(apiKey)"]
            let urlRequest = try LLMHTTP.makeRequest(url: endpoint, headers: headers, body: body)
            // 事件格式：{"choices":[{"delta":{"content":"…"}}]}
            return accumulate(LLMHTTP.events(for: urlRequest)) { event in
                guard
                    let choices = event["choices"] as? [[String: Any]],
                    let delta = choices.first?["delta"] as? [String: Any]
                else { return nil }
                return delta["content"] as? String
            }
        } catch {
            return failing(TranslationError.invalidResponse)
        }
    }
}

/// 根据用户在设置里选择的 provider，把调用路由到 Anthropic 或 OpenAI 兼容引擎。
final class LLMEngine: TranslationEngine {
    var name: String {
        switch MainActor.assumeIsolated({ settings.llmProvider }) {
        case .anthropic: return anthropic.name
        case .openAICompatible: return openAICompatible.name
        }
    }

    private let anthropic: AnthropicEngine
    private let openAICompatible: OpenAICompatibleEngine
    private let settings: AppSettings

    init(settings: AppSettings, keychain: KeychainHelper = .shared) {
        self.settings = settings
        self.anthropic = AnthropicEngine(settings: settings, keychain: keychain)
        self.openAICompatible = OpenAICompatibleEngine(settings: settings, keychain: keychain)
    }

    func translate(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error> {
        switch MainActor.assumeIsolated({ settings.llmProvider }) {
        case .anthropic:
            return anthropic.translate(request)
        case .openAICompatible:
            return openAICompatible.translate(request)
        }
    }
}

/// 设置页的"测试"：用一句很短的话实际请求一次，报告是否可用、首字延迟和总耗时。
enum LLMConnectionTester {
    struct Report {
        var model: String
        var output: String
        var firstTokenLatency: TimeInterval
        var totalLatency: TimeInterval
    }

    static let sample = "Hello, world! Translation looks good."

    @MainActor
    static func run(provider: LLMProvider, model: String, apiKey: String, settings: AppSettings) async throws -> Report {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let engine: TranslationEngine
        switch provider {
        case .anthropic:
            engine = AnthropicEngine(settings: settings, apiKeyOverride: key, modelOverride: model)
        case .openAICompatible:
            engine = OpenAICompatibleEngine(settings: settings, apiKeyOverride: key, modelOverride: model)
        }

        let request = TranslationRequest(text: sample, languages: .init(source: "en", target: settings.primaryLanguage))
        let start = Date()
        var firstToken: TimeInterval?
        var output = ""
        for try await partial in engine.translate(request) {
            if firstToken == nil { firstToken = Date().timeIntervalSince(start) }
            output = partial
        }
        let total = Date().timeIntervalSince(start)
        return Report(model: model, output: output, firstTokenLatency: firstToken ?? total, totalLatency: total)
    }
}
