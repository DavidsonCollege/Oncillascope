import SwiftUI
import Sparkle

/// Owns the Sparkle updater for the app. Notify-and-prompt only: `startingUpdater: true`
/// lets Sparkle schedule background checks, but with no `SUEnableAutomaticChecks` in
/// Info.plist Sparkle asks the user for permission on first launch before any network call.
final class UpdaterController: ObservableObject {
    let updaterController: SPUStandardUpdaterController
    @Published var canCheckForUpdates = false

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }
}

/// Menu command that mirrors the existing focused-command pattern (EmailExportCommandButton):
/// a titled button disabled while the updater is mid-check.
struct CheckForUpdatesCommand: View {
    @ObservedObject var updater: UpdaterController
    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}
