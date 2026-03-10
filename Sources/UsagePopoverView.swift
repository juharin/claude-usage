import SwiftUI

struct UsagePopoverView: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.state {
            case .loaded:
                loadedContent
            case .loading:
                loadingContent
            case .unauthenticated:
                unauthenticatedContent
            case .error(let message):
                errorContent(message)
            }

            Divider().padding(.vertical, 4)
            footerButtons
        }
        .padding(12)
        .frame(width: 240)
    }

    @ViewBuilder
    private var loadedContent: some View {
        if let usage = model.usage {
            // Consume tick to trigger view updates for countdowns
            let _ = model.tick

            usageSection(
                title: "5-Hour Usage",
                utilization: usage.fiveHour.utilization,
                countdown: model.fiveHourCountdown
            )

            Divider().padding(.vertical, 8)

            usageSection(
                title: "7-Day Usage",
                utilization: usage.sevenDay.utilization,
                countdown: model.sevenDayCountdown
            )

            if usage.sevenDayOpus != nil || usage.sevenDaySonnet != nil {
                Divider().padding(.vertical, 8)

                if let opus = usage.sevenDayOpus {
                    modelRow(name: "Opus (7d)", utilization: opus.utilization)
                }
                if let sonnet = usage.sevenDaySonnet {
                    modelRow(name: "Sonnet (7d)", utilization: sonnet.utilization)
                }
            }

            Divider().padding(.vertical, 8)

            Text("Updated \(model.lastUpdatedText)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func usageSection(title: String, utilization: Double, countdown: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(utilization))%")
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .foregroundStyle(colorForUtilization(utilization))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(colorForUtilization(utilization))
                        .frame(width: geo.size.width * min(utilization / 100.0, 1.0))
                }
            }
            .frame(height: 6)

            Text("Resets in \(countdown)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func modelRow(name: String, utilization: Double) -> some View {
        HStack {
            Text(name)
                .font(.caption)
            Spacer()
            Text("\(Int(utilization))%")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(colorForUtilization(utilization))
        }
    }

    private var loadingContent: some View {
        HStack {
            Spacer()
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading...")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 12)
    }

    private var unauthenticatedContent: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("Not Authenticated")
                    .font(.headline)
            }

            Text("Claude Code credentials not found or expired.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Open Claude.ai") {
                model.openClaude()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func errorContent(_ message: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Error")
                    .font(.headline)
            }

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var footerButtons: some View {
        HStack {
            Button("Refresh") {
                Task { await model.refresh() }
            }
            .buttonStyle(.borderless)
            .font(.caption)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }

    private func colorForUtilization(_ pct: Double) -> Color {
        if pct >= 85 { return .red }
        if pct >= 60 { return .yellow }
        return .green
    }
}
