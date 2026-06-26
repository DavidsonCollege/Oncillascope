import SwiftUI

@main
struct AirScopeApp: App {
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
