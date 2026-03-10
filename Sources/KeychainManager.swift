import Foundation
import Security

struct OAuthCredentials {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

enum KeychainManager {
    private static let serviceName = "Claude Code-credentials"

    static func readCredentials() -> OAuthCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String,
              let refreshToken = oauth["refreshToken"] as? String,
              let expiresAtMs = oauth["expiresAt"] as? Double
        else {
            return nil
        }

        return OAuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date(timeIntervalSince1970: expiresAtMs / 1000.0)
        )
    }

    static func updateAccessToken(_ newToken: String, expiresAt: Date) -> Bool {
        // Read existing data first
        let readQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(readQuery as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data,
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var oauth = json["claudeAiOauth"] as? [String: Any]
        else {
            return false
        }

        oauth["accessToken"] = newToken
        oauth["expiresAt"] = expiresAt.timeIntervalSince1970 * 1000.0
        json["claudeAiOauth"] = oauth

        guard let updatedData = try? JSONSerialization.data(withJSONObject: json) else {
            return false
        }

        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: updatedData
        ]

        return SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary) == errSecSuccess
    }
}
