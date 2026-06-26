import SwiftUI

@main
struct AirScopeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear { model.start() }
                .onDisappear { model.stop() }
        }
        .windowResizability(.contentMinSize)
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
