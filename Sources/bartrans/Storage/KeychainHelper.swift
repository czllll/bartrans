import Foundation
import Security

enum KeychainAccount: String {
    case anthropicAPIKey = "anthropic-api-key"
    case openAICompatibleAPIKey = "openai-compatible-api-key"
}

final class KeychainHelper {
    static let shared = KeychainHelper()

    private let service = "com.transpop.bartrans.llmkey"
    private let legacyService = "com.transpop.menubartranslator.llmkey"

    /// 迁移推迟到第一次真正读写 Key 时再做：App 启动时不碰钥匙串，
    /// 避免签名变化后一启动就弹出钥匙串授权框。
    private var didMigrate = false

    private init() {}

    /// 改名前用的是 com.transpop.menubartranslator.llmkey 这个 service，
    /// 改名后老 Key 并没有丢，只是存在旧 service 名下；这里把它们
    /// 搬到新 service，搬完就清理旧条目，只做一次。
    private func migrateLegacyKeysIfNeeded() {
        guard !didMigrate else { return }
        didMigrate = true
        for account in [KeychainAccount.anthropicAPIKey, .openAICompatibleAPIKey] {
            guard load(for: account) == nil, let legacyValue = load(for: account, service: legacyService) else {
                continue
            }
            save(legacyValue, for: account)
            delete(for: account, service: legacyService)
        }
    }

    func save(_ key: String, for account: KeychainAccount) {
        migrateLegacyKeysIfNeeded()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue
        ]

        SecItemDelete(query as CFDictionary)

        guard !key.isEmpty else { return }

        var newItem = query
        newItem[kSecValueData as String] = Data(key.utf8)
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        SecItemAdd(newItem as CFDictionary, nil)
    }

    func load(for account: KeychainAccount, service: String? = nil) -> String? {
        if service == nil { migrateLegacyKeysIfNeeded() }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service ?? self.service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(for account: KeychainAccount, service: String? = nil) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service ?? self.service,
            kSecAttrAccount as String: account.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }
}
