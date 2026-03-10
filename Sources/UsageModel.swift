import Foundation
import SwiftUI

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

    private let pollInterval: TimeInterval = 60
    private var isRefreshing = false
    private var started = false
    private var consecutiveRateLimits = 0

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
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.refresh() }
        }
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

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let credentials = KeychainManager.readCredentials() else {
            state = .unauthenticated
            return
        }

        var accessToken = credentials.accessToken

        // If token is expired, try to refresh first
        if credentials.expiresAt < Date() {
            do {
                let tokenResponse = try await UsageService.refreshAccessToken(
                    refreshToken: credentials.refreshToken)
                let newExpiry = Date().addingTimeInterval(Double(tokenResponse.expiresIn))
                _ = KeychainManager.updateAccessToken(tokenResponse.accessToken, expiresAt: newExpiry)
                accessToken = tokenResponse.accessToken
            } catch UsageServiceError.unauthenticated {
                state = .unauthenticated
                return
            } catch {
                // Refresh failed, try with existing token anyway
            }
        }

        do {
            let data = try await UsageService.fetchUsage(accessToken: accessToken)
            usage = data
            lastUpdated = Date()
            state = .loaded
            consecutiveRateLimits = 0
        } catch UsageServiceError.unauthenticated {
            // Try token refresh if we haven't already
            do {
                let tokenResponse = try await UsageService.refreshAccessToken(
                    refreshToken: credentials.refreshToken)
                let newExpiry = Date().addingTimeInterval(Double(tokenResponse.expiresIn))
                _ = KeychainManager.updateAccessToken(tokenResponse.accessToken, expiresAt: newExpiry)

                let data = try await UsageService.fetchUsage(accessToken: tokenResponse.accessToken)
                usage = data
                lastUpdated = Date()
                state = .loaded
            } catch UsageServiceError.unauthenticated {
                state = .unauthenticated
            } catch {
                state = .unauthenticated
            }
        } catch UsageServiceError.rateLimited {
            consecutiveRateLimits += 1
            let backoff = min(60.0 * pow(2.0, Double(consecutiveRateLimits - 1)), 600.0)
            if usage != nil {
                // Have data, silently schedule a delayed retry
            } else {
                let mins = Int(backoff) / 60
                let secs = Int(backoff) % 60
                let waitText = mins > 0 ? "\(mins)m \(secs)s" : "\(secs)s"
                state = .error("Rate limited — retrying in \(waitText)")
            }
            // Schedule a one-off retry after backoff
            let delay = backoff
            Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await refresh()
            }
        } catch {
            if usage != nil {
                // Keep showing stale data on transient errors
            } else {
                state = .error(error.localizedDescription)
            }
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
