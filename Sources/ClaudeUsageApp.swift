import SwiftUI

@main
struct ClaudeUsageApp: App {
    @StateObject private var model = UsageModel()

    var body: some Scene {
        MenuBarExtra {
            UsagePopoverView(model: model)
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: ClaudeIcon.menuBarImage())
                Text(model.menuBarText)
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
