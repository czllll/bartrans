import AppKit
import AVFoundation
import CoreServices

/// macOS 自带「词典」App 的离线查词（Dictionary Services）。
/// 使用的是用户在词典 App 偏好设置里启用的词典，例如「牛津英汉汉英词典」。
enum DictionaryLookup {
    static func definition(for word: String) -> String? {
        let term = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return nil }
        let range = CFRange(location: 0, length: (term as NSString).length)
        guard let raw = DCSCopyTextDefinition(nil, term as CFString, range)?.takeRetainedValue() as String? else {
            return nil
        }
        return format(raw)
    }

    static func openInDictionaryApp(_ word: String) {
        guard
            let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: "dict://\(encoded)")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// Dictionary Services 返回的是一整行纯文本，义项之间用 ▶ / 数字分隔，
    /// 这里拆成多行，读起来更像词典。
    private static func format(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "▶", with: "\n▶")
        // 义项编号：英汉词典用 ①②…，英英词典用 "1 "、"2 "…
        if let regex = try? NSRegularExpression(pattern: "\\s*(?=[\\u2460-\\u2473])|\\s(?=(?:[1-9]|1[0-9]) (?=\\S))") {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "\n")
        }
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// 判断选中的内容是否适合当作"查词"而不是段落翻译。
    static func isWordLike(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40, !trimmed.contains(where: \.isNewline) else { return false }

        if LanguageDetector.isPrimarilyChinese(trimmed) {
            return trimmed.count <= 4 && trimmed.allSatisfy { $0.isLetter }
        }
        // 最多两个词（如 "take off"、"ad hoc"），只允许字母、连字符、撇号
        let words = trimmed.split(separator: " ")
        guard words.count <= 2 else { return false }
        return trimmed.allSatisfy { $0.isLetter || $0 == "-" || $0 == "'" || $0 == "’" || $0 == " " }
    }
}

/// 朗读：用系统语音合成，按语言挑选音色。
@MainActor
final class Speaker {
    static let shared = Speaker()

    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, language: String?) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        let code = language ?? LanguageDetector.detect(text) ?? "en"
        utterance.voice = AVSpeechSynthesisVoice(language: Self.voiceLanguage(for: code))
        synthesizer.speak(utterance)
    }

    private static func voiceLanguage(for code: String) -> String {
        switch code {
        case "zh-Hans": return "zh-CN"
        case "zh-Hant": return "zh-TW"
        case "en": return "en-US"
        case "ja": return "ja-JP"
        case "ko": return "ko-KR"
        default: return code
        }
    }
}
