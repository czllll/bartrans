import Foundation
import NaturalLanguage

enum LanguageDetector {
    static func isPrimarilyChinese(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        switch recognizer.dominantLanguage {
        case .simplifiedChinese, .traditionalChinese:
            return true
        case .english:
            return false
        default:
            // NLLanguageRecognizer 对很短的文字（如几个单词）经常判断不准，
            // 兜底用 CJK 字符占比来判断。
            return chineseCharacterRatio(in: trimmed) > 0.2
        }
    }

    private static func chineseCharacterRatio(in text: String) -> Double {
        let scalars = text.unicodeScalars
        guard !scalars.isEmpty else { return 0 }
        let chineseCount = scalars.filter { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) || // CJK 统一表意文字
            (0x3400...0x4DBF).contains(scalar.value)    // CJK 扩展 A
        }.count
        return Double(chineseCount) / Double(scalars.count)
    }
}
