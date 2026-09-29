import Foundation

/// 支持的语言。`code` 是 BCP-47 标识，同时喂给 Translation framework
/// 和 LLM prompt（后者用 `name` 的中文名）。
struct AppLanguage: Hashable, Identifiable {
    let code: String
    let name: String

    var id: String { code }

    /// 与另一种语言是否同属一个"语族"（zh-Hans / zh-Hant 都算中文）。
    func matches(_ other: String) -> Bool {
        Self.baseCode(code) == Self.baseCode(other)
    }

    static func baseCode(_ code: String) -> String {
        String(code.split(separator: "-").first ?? Substring(code)).lowercased()
    }

    static let all: [AppLanguage] = [
        AppLanguage(code: "zh-Hans", name: "简体中文"),
        AppLanguage(code: "zh-Hant", name: "繁体中文"),
        AppLanguage(code: "en", name: "英文"),
        AppLanguage(code: "ja", name: "日文"),
        AppLanguage(code: "ko", name: "韩文"),
        AppLanguage(code: "fr", name: "法文"),
        AppLanguage(code: "de", name: "德文"),
        AppLanguage(code: "es", name: "西班牙文"),
        AppLanguage(code: "ru", name: "俄文")
    ]

    static func named(_ code: String) -> AppLanguage {
        all.first { $0.code == code }
            ?? all.first { $0.matches(code) }
            ?? AppLanguage(code: code, name: Locale(identifier: "zh-Hans").localizedString(forIdentifier: code) ?? code)
    }

    /// 方向按钮上用的单字简称，如"中""英"。
    var shortName: String {
        switch Self.baseCode(code) {
        case "zh": return "中"
        case "en": return "英"
        case "ja": return "日"
        case "ko": return "韩"
        case "fr": return "法"
        case "de": return "德"
        case "es": return "西"
        case "ru": return "俄"
        default: return String(name.prefix(1))
        }
    }
}

/// `.auto` 依据输入内容识别语言：是母语就译成外语，否则译成母语；
/// 另外两个是手动强制方向，用于自动识别不准时兜底。
enum TranslationDirection: String, CaseIterable, Codable {
    case auto
    case toSecondary
    case toPrimary

    func label(primary: AppLanguage, secondary: AppLanguage) -> String {
        switch self {
        case .auto: return "自动识别"
        case .toSecondary: return "\(primary.shortName) → \(secondary.shortName)"
        case .toPrimary: return "→ \(primary.shortName)"
        }
    }

    func resolve(for text: String, primary: AppLanguage, secondary: AppLanguage) -> TranslationRequest.Languages {
        let detected = LanguageDetector.detect(text)
        switch self {
        case .auto:
            if let detected, primary.matches(detected) {
                return .init(source: detected, target: secondary.code)
            }
            return .init(source: detected, target: primary.code)
        case .toSecondary:
            return .init(source: primary.code, target: secondary.code)
        case .toPrimary:
            let source = detected.flatMap { primary.matches($0) ? nil : $0 } ?? secondary.code
            return .init(source: source, target: primary.code)
        }
    }

    mutating func cycle() {
        switch self {
        case .auto: self = .toSecondary
        case .toSecondary: self = .toPrimary
        case .toPrimary: self = .auto
        }
    }
}

struct TranslationRequest {
    struct Languages: Equatable {
        /// nil 表示没能识别出源语言，交给引擎自己判断。
        var source: String?
        var target: String
    }

    enum Mode {
        /// 普通段落翻译
        case text
        /// 单个词：LLM 会给出词典式释义
        case word
    }

    var text: String
    var languages: Languages
    var mode: Mode = .text

    var sourceName: String { languages.source.map { AppLanguage.named($0).name } ?? "原文所用语言" }
    var targetName: String { AppLanguage.named(languages.target).name }
}

enum TranslationError: LocalizedError {
    case emptyInput
    case apiKeyMissing
    case network(String)
    case timeout
    case invalidResponse
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "请输入要翻译的文字"
        case .apiKeyMissing:
            return "尚未配置 API Key，请前往设置填写"
        case .network(let message):
            return "网络请求失败：\(message)"
        case .timeout:
            return "请求超时，请稍后重试"
        case .invalidResponse:
            return "翻译服务返回了无法识别的结果"
        case .unavailable(let reason):
            return reason
        }
    }
}

protocol TranslationEngine {
    var name: String { get }

    /// 以流的形式返回译文：每次 yield 的都是**截至目前的完整译文**，
    /// 不支持流式的引擎只 yield 一次最终结果。
    func translate(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error>
}

extension TranslationEngine {
    /// 把一次性的 async 翻译包装成只 yield 一次的流，供非流式引擎复用。
    func singleShot(_ work: @escaping @Sendable () async throws -> String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(try await work())
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
