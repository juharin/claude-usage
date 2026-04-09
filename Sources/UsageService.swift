import Foundation
private let log = FileLog.shared

struct UsageWindow: Codable {
    let utilization: Double
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    var resetsAtDate: Date? {
        guard let resetsAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: resetsAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: resetsAt)
    }
}

struct UsageData: Codable {
    let fiveHour: UsageWindow
    let sevenDay: UsageWindow
    let sevenDaySonnet: UsageWindow?
    let sevenDayOpus: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
    }
}

struct TokenResponse: Codable {
    let accessToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}

enum UsageServiceError: LocalizedError {
    case unauthenticated
    case rateLimited(retryAfter: Int)
    case networkError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unauthenticated: return "Not authenticated"
        case .rateLimited(let seconds): return "Rate limited — retry after \(seconds)s"
        case .networkError(let msg): return msg
        case .invalidResponse: return "Invalid response"
        }
    }
}

enum UsageService {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let oauthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    static func fetchUsage(accessToken: String) async throws -> UsageData {
        var request = URLRequest(url: usageURL)
        request.timeoutInterval = 30
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("claude-code/1.0.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            log.error("fetchUsage: not an HTTP response")
            throw UsageServiceError.invalidResponse
        }

        log.info("fetchUsage: HTTP \(httpResponse.statusCode)")

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw UsageServiceError.unauthenticated
        }

        if httpResponse.statusCode == 429 {
            let retryAfter = Int(httpResponse.value(forHTTPHeaderField: "retry-after") ?? "0") ?? 0
            log.warning("fetchUsage: rate limited, retry-after=\(retryAfter)s")
            throw UsageServiceError.rateLimited(retryAfter: retryAfter)
        }

        guard httpResponse.statusCode == 200 else {
            throw UsageServiceError.networkError("HTTP \(httpResponse.statusCode)")
        }

        do {
            return try JSONDecoder().decode(UsageData.self, from: data)
        } catch {
            let bodyPreview = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
            log.error("fetchUsage: JSON decode failed: \(error) body=\(bodyPreview)")
            throw error
        }
    }

    static func refreshAccessToken(refreshToken: String) async throws -> TokenResponse {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("claude-code/1.0.0", forHTTPHeaderField: "User-Agent")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: oauthClientID),
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        log.info("refreshAccessToken: POSTing to \(tokenURL)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageServiceError.invalidResponse
        }

        log.info("refreshAccessToken: HTTP \(httpResponse.statusCode)")

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            let bodyPreview = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
            log.error("refreshAccessToken: auth failed: \(bodyPreview)")
            throw UsageServiceError.unauthenticated
        }

        guard httpResponse.statusCode == 200 else {
            let bodyPreview = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
            log.error("refreshAccessToken: failed HTTP \(httpResponse.statusCode): \(bodyPreview)")
            throw UsageServiceError.networkError("Token refresh failed: HTTP \(httpResponse.statusCode)")
        }

        log.info("refreshAccessToken: success")
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
}
