import SwiftUI

/// View-menu toggle (⇧⌘E) switching dashboard tooltips between the technical and
/// plain-English explanations. Backed by @AppStorage so the choice persists and every
/// tooltip updates live.
private struct PlainEnglishTooltipsToggle: View {
    @AppStorage(plainEnglishTooltipsKey) private var plainEnglish = false
    var body: some View {
        Toggle("Plain-English Tooltips", isOn: $plainEnglish)
            .keyboardShortcut("e", modifiers: [.command, .shift])
    }
}

/// Menu commands for the privileged helper that powers continuous PHY metrics.
/// State-aware: shows install/approve/disable depending on the daemon's lifecycle.
private struct HelperMenu: View {
    @ObservedObject var model: AppModel
    var body: some View {
        switch model.helperStatus {
        case .enabled:
            Button("Disable PHY Metrics Helper") { model.disableHelper() }
        case .requiresApproval:
            Button("Approve PHY Metrics Helper…") { model.openHelperSettings() }
            Button("I Approved the Helper") { model.confirmHelperApproval() }
        case .notRegistered:
            Button("Enable Continuous PHY Metrics…") { model.enableHelper() }
        case .notFound, .failed:
            Button("Enable Continuous PHY Metrics…") { model.enableHelper() }
                .disabled(true)
        }
    }
}

@main
struct OncillascopeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                // Set ideal size only (no minimum — a min frame collapses the split
                // view). This makes the window open at ~1100x720 instead of adopting
                // the content's runaway ideal height, while staying freely resizable.
                .frame(idealWidth: 1100, idealHeight: 720)
                .onAppear { model.start() }
                .onDisappear { model.stop() }
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(after: .sidebar) {
                PlainEnglishTooltipsToggle()
                Divider()
                HelperMenu(model: model)
                Divider()
            }
            CommandGroup(after: .newItem) {
                Button("Scan Now") { model.scanNow() }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("Export Networks as CSV…") { model.exportNetworksCSV() }
                Button("Export Telemetry as CSV…") { model.exportTelemetryCSV() }
                Button("Export Snapshot as JSON…") { model.exportSnapshotJSON() }
            }
        }
    }
}
