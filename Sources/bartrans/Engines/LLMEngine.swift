import Foundation

private enum LLMHTTP {
    static let requestTimeout: TimeInterval = 15

    static func post(url: URL, headers: [String: String], body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw TranslationError.timeout
        } catch {
            throw TranslationError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let detail = errorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)"
            throw TranslationError.network(detail)
        }

        return data
    }

    private static func errorMessage(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"] as? [String: Any],
            let message = error["message"] as? String
        else { return nil }
        return message
    }
}

private func translationPrompt(source: String, target: String, text: String) -> String {
    "将以下\(source)文本翻译为\(target)，只输出译文，不要任何解释或额外内容：\n\n\(text)"
}

/// 调用 Anthropic Messages API (`api.anthropic.com/v1/messages`)。
final class AnthropicEngine: TranslationEngine {
    let name = "LLM (Anthropic)"

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-sonnet-4-6"

    private let keychain: KeychainHelper

    init(keychain: KeychainHelper = .shared) {
        self.keychain = keychain
    }

    func translate(_ text: String, from source: String, to target: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyInput }

        guard let apiKey = keychain.load(for: .anthropicAPIKey), !apiKey.isEmpty else {
            throw TranslationError.apiKeyMissing
        }

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": translationPrompt(source: source, target: target, text: trimmed)]
            ]
        ]

        let data = try await LLMHTTP.post(
            url: Self.endpoint,
            headers: ["x-api-key": apiKey, "anthropic-version": "2023-06-01"],
            body: body
        )

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let firstBlock = content.first,
            let translatedText = firstBlock["text"] as? String
        else {
            throw TranslationError.invalidResponse
        }

        return translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 调用任意 OpenAI Chat Completions 兼容接口
/// （OpenAI 官方、Azure OpenAI、DeepSeek、Ollama/LM Studio 本地代理等）。
/// Base URL 与模型名由用户在设置里填写。
final class OpenAICompatibleEngine: TranslationEngine {
    let name = "LLM (OpenAI 兼容)"

    private let settings: AppSettings
    private let keychain: KeychainHelper

    init(settings: AppSettings, keychain: KeychainHelper = .shared) {
        self.settings = settings
        self.keychain = keychain
    }

    func translate(_ text: String, from source: String, to target: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyInput }

        guard let apiKey = keychain.load(for: .openAICompatibleAPIKey), !apiKey.isEmpty else {
            throw TranslationError.apiKeyMissing
        }

        let (baseURL, model) = await MainActor.run { (settings.openAIBaseURL, settings.openAIModel) }
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty, let endpoint = URL(string: trimmedBase.hasSuffix("/") ? trimmedBase + "chat/completions" : trimmedBase + "/chat/completions") else {
            throw TranslationError.network("LLM Base URL 无效")
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.network("尚未设置模型名称")
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": translationPrompt(source: source, target: target, text: trimmed)]
            ]
        ]

        let data = try await LLMHTTP.post(
            url: endpoint,
            headers: ["Authorization": "Bearer \(apiKey)"],
            body: body
        )

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let firstChoice = choices.first,
            let message = firstChoice["message"] as? [String: Any],
            let translatedText = message["content"] as? String
        else {
            throw TranslationError.invalidResponse
        }

        return translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 根据用户在设置里选择的 provider，把调用路由到 Anthropic 或 OpenAI 兼容引擎。
final class LLMEngine: TranslationEngine {
    let name = "LLM"

    private let anthropic: AnthropicEngine
    private let openAICompatible: OpenAICompatibleEngine
    private let settings: AppSettings

    init(settings: AppSettings, keychain: KeychainHelper = .shared) {
        self.settings = settings
        self.anthropic = AnthropicEngine(keychain: keychain)
        self.openAICompatible = OpenAICompatibleEngine(settings: settings, keychain: keychain)
    }

    func translate(_ text: String, from source: String, to target: String) async throws -> String {
        let provider = await MainActor.run { settings.llmProvider }
        switch provider {
        case .anthropic:
            return try await anthropic.translate(text, from: source, to: target)
        case .openAICompatible:
            return try await openAICompatible.translate(text, from: source, to: target)
        }
    }
}
