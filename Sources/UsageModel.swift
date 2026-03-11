import Foundation
import SwiftUI
private let log = FileLog.shared

enum AppState: Equatable {
    case loading
    case loaded
    case unauthenticated
    case error(String)
}

@MainActor
class UsageModel: NSObject, ObservableObject {
    @Published var state: AppState = .loading
    @Published var usage: UsageData?
    @Published var lastUpdated: Date?

    private var pollTimer: Timer?
    private var countdownTimer: Timer?
    // Triggers view updates every second for live countdowns
    @Published var tick: UInt64 = 0

    // API allows ~10 requests/hour. 10 min interval = 6/hour, leaves room for manual refresh.
    private let normalPollInterval: TimeInterval = 600
    private let errorPollInterval: TimeInterval = 1800  // 30 min when in error state
    private var isRefreshing = false
    private var started = false
    private var consecutiveErrors = 0

    override init() {
        super.init()
        start()
    }

    var menuBarText: String {
        switch state {
        case .loading:
            return "..."
        case .loaded:
            if let u = usage {
                return "\(Int(u.fiveHour.utilization))%"
            }
            return "..."
        case .unauthenticated:
            return "–"
        case .error:
            return "!"
        }
    }

    var menuBarColor: Color {
        guard let u = usage else { return .secondary }
        let pct = u.fiveHour.utilization
        if pct >= 85 { return .red }
        if pct >= 60 { return .yellow }
        return .green
    }

    var fiveHourCountdown: String {
        guard let date = usage?.fiveHour.resetsAtDate else { return "–" }
        return Self.formatCountdown(until: date)
    }

    var sevenDayCountdown: String {
        guard let date = usage?.sevenDay.resetsAtDate else { return "–" }
        return Self.formatCountdown(until: date)
    }

    var lastUpdatedText: String {
        guard let date = lastUpdated else { return "never" }
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        return "\(seconds / 60)m ago"
    }

    func start() {
        guard !started else { return }
        started = true
        Task { await refresh() }
        schedulePollTimer(interval: normalPollInterval)
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.tick &+= 1 }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func schedulePollTimer(interval: TimeInterval) {
        pollTimer?.invalidate()
        log.info("Poll timer set to \(Int(interval))s")
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.refresh() }
        }
    }

    private func onSuccess() {
        let wasInErrorState = consecutiveErrors > 0
        consecutiveErrors = 0
        if wasInErrorState {
            schedulePollTimer(interval: normalPollInterval)
        }
    }

    private func onError() {
        consecutiveErrors += 1
        // Slow down polling when errors accumulate
        if consecutiveErrors >= 3 {
            schedulePollTimer(interval: errorPollInterval)
            log.warning("Slowed polling to \(Int(errorPollInterval))s after \(consecutiveErrors) consecutive errors")
        }
    }

    func refresh() async {
        guard !isRefreshing else {
            log.debug("refresh() skipped — already refreshing")
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        // Layer 1: Keychain read
        guard let credentials = KeychainManager.readCredentials() else {
            log.error("Layer 1 FAIL: Keychain read returned nil")
            state = .unauthenticated
            onError()
            return
        }
        let tokenExpired = credentials.expiresAt < Date()
        log.debug("Layer 1 OK: token=...\(String(credentials.accessToken.suffix(6))) expired=\(tokenExpired)")

        var accessToken = credentials.accessToken

        // Layer 2: Token refresh (if expired)
        if tokenExpired {
            log.info("Layer 2: Token expired, attempting refresh")
            do {
                let tokenResponse = try await UsageService.refreshAccessToken(
                    refreshToken: credentials.refreshToken)
                let newExpiry = Date().addingTimeInterval(Double(tokenResponse.expiresIn))
                _ = KeychainManager.updateAccessToken(tokenResponse.accessToken, expiresAt: newExpiry)
                accessToken = tokenResponse.accessToken
                log.info("Layer 2 OK: Token refreshed")
            } catch {
                log.error("Layer 2 FAIL: Refresh error: \(error)")
                // Don't try the API with an expired token — it'll just waste requests
                state = .unauthenticated
                onError()
                return
            }
        }

        // Layer 3: Usage API call
        log.info("Layer 3: Calling usage API")
        do {
            let data = try await UsageService.fetchUsage(accessToken: accessToken)
            usage = data
            lastUpdated = Date()
            state = .loaded
            onSuccess()
            log.info("Layer 3 OK: 5h=\(Int(data.fiveHour.utilization))% 7d=\(Int(data.sevenDay.utilization))%")
        } catch UsageServiceError.unauthenticated {
            log.error("Layer 3 FAIL: 401/403 — token rejected")
            // Token was valid per expiry but server rejected it.
            // Try ONE refresh, then give up until next poll.
            do {
                let tokenResponse = try await UsageService.refreshAccessToken(
                    refreshToken: credentials.refreshToken)
                let newExpiry = Date().addingTimeInterval(Double(tokenResponse.expiresIn))
                _ = KeychainManager.updateAccessToken(tokenResponse.accessToken, expiresAt: newExpiry)

                let data = try await UsageService.fetchUsage(accessToken: tokenResponse.accessToken)
                usage = data
                lastUpdated = Date()
                state = .loaded
                onSuccess()
                log.info("Layer 3 OK (after refresh): 5h=\(Int(data.fiveHour.utilization))%")
            } catch {
                log.error("Layer 3 FAIL: Still failing after refresh: \(error)")
                state = .unauthenticated
                onError()
            }
        } catch UsageServiceError.rateLimited(let retryAfter) {
            let waitSeconds = max(retryAfter, Int(errorPollInterval))
            log.warning("Layer 3 FAIL: Rate limited, retry-after=\(retryAfter)s, will wait \(waitSeconds)s")
            if usage == nil {
                let mins = waitSeconds / 60
                state = .error("Rate limited — retrying in \(mins)m")
            }
            // Respect the server's retry-after. Don't use onError() here because
            // we set a specific timer based on the retry-after header value.
            schedulePollTimer(interval: TimeInterval(waitSeconds))
            consecutiveErrors += 1
        } catch {
            log.error("Layer 3 FAIL: \(error)")
            if usage == nil {
                state = .error(error.localizedDescription)
            }
            onError()
        }
    }

    func openClaude() {
        if let url = URL(string: "https://claude.ai") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func formatCountdown(until date: Date) -> String {
        let seconds = Int(date.timeIntervalSinceNow)
        if seconds <= 0 { return "now" }

        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
