import Foundation

/// MVP 只做中英互译：`.auto` 会依据输入内容自动识别中/英文并决定翻译方向；
/// 另外两个是手动强制方向，用于自动识别不准时兜底。
enum TranslationDirection: String, CaseIterable, Codable {
    case auto
    case zhToEn
    case enToZh

    var label: String {
        switch self {
        case .auto: return "自动识别"
        case .zhToEn: return "中 → 英"
        case .enToZh: return "英 → 中"
        }
    }

    /// 根据当前方向设置和实际输入文字，解析出翻译的源/目标语言。
    func resolve(for text: String) -> (source: String, target: String) {
        switch self {
        case .auto:
            return LanguageDetector.isPrimarilyChinese(text) ? ("中文", "英文") : ("英文", "中文")
        case .zhToEn:
            return ("中文", "英文")
        case .enToZh:
            return ("英文", "中文")
        }
    }

    mutating func cycle() {
        switch self {
        case .auto: self = .zhToEn
        case .zhToEn: self = .enToZh
        case .enToZh: self = .auto
        }
    }
}

enum TranslationError: LocalizedError {
    case emptyInput
    case apiKeyMissing
    case network(String)
    case timeout
    case invalidResponse
    case unsupportedLanguagePack

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
        case .unsupportedLanguagePack:
            return "系统翻译语言包尚未就绪，请前往系统设置下载"
        }
    }
}

protocol TranslationEngine {
    var name: String { get }
    func translate(_ text: String, from source: String, to target: String) async throws -> String
}
