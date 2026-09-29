import Foundation
import NaturalLanguage

enum LanguageDetector {
    /// 返回识别出的 BCP-47 语言代码（如 "en"、"zh-Hans"、"ja"），识别不出时返回 nil。
    static func detect(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // NLLanguageRecognizer 对很短的文字（如几个单词、两三个汉字）经常判断不准，
        // 先用字符集做一次粗判：假名 → 日文，谚文 → 韩文，汉字占比高 → 中文。
        let ratios = scriptRatios(in: trimmed)
        if ratios.kana > 0.1 { return "ja" }
        if ratios.hangul > 0.2 { return "ko" }
        if ratios.han > 0.2 {
            // 繁简判断：转成简体后有变化，说明原文含繁体字
            let simplified = trimmed.applyingTransform(StringTransform("Hant-Hans"), reverse: false)
            return simplified != nil && simplified != trimmed ? "zh-Hant" : "zh-Hans"
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [
            .english, .simplifiedChinese, .traditionalChinese, .japanese, .korean,
            .french, .german, .spanish, .russian, .italian, .portuguese
        ]
        // 短的拉丁字母文本在各语言间很难区分，偏向最常见的英文
        if trimmed.split(whereSeparator: \.isWhitespace).count <= 3 {
            recognizer.languageHints = [.english: 0.6]
        }
        recognizer.processString(trimmed)

        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first else {
            return ratios.latin > 0.5 ? "en" : nil
        }
        // 单个拉丁字母单词很容易被误判成法/德文，置信度不够时按英文处理。
        if confidence < 0.5, ratios.latin > 0.5 { return "en" }
        return language.rawValue
    }

    static func isPrimarilyChinese(_ text: String) -> Bool {
        detect(text).map { AppLanguage.baseCode($0) == "zh" } ?? false
    }

    private struct ScriptRatios {
        var han = 0.0, kana = 0.0, hangul = 0.0, latin = 0.0
    }

    private static func scriptRatios(in text: String) -> ScriptRatios {
        var han = 0, kana = 0, hangul = 0, latin = 0, total = 0
        for scalar in text.unicodeScalars where !scalar.properties.isWhitespace {
            total += 1
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF: han += 1
            case 0x3040...0x30FF: kana += 1
            case 0xAC00...0xD7AF, 0x1100...0x11FF: hangul += 1
            case 0x41...0x5A, 0x61...0x7A: latin += 1
            default: break
            }
        }
        guard total > 0 else { return ScriptRatios() }
        let t = Double(total)
        return ScriptRatios(han: Double(han) / t, kana: Double(kana) / t, hangul: Double(hangul) / t, latin: Double(latin) / t)
    }
}
