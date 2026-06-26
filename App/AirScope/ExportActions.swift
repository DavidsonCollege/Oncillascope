import Foundation
import AppKit
import UniformTypeIdentifiers
import Telemetry
import WiFiModel

/// Export + rolling-log behavior (spec §4.6). All disk writes are user-initiated; the
/// rolling log is off by default and writes only to a user-chosen location.
extension AppModel {

    func exportNetworksCSV() {
        save(suggested: "airscope-networks.csv", type: .commaSeparatedText) {
            Exporter.networksCSV(self.networks).data(using: .utf8)
        }
    }

    func exportTelemetryCSV() {
        save(suggested: "airscope-telemetry.csv", type: .commaSeparatedText) {
            Exporter.samplesCSV(self.samples).data(using: .utf8)
        }
    }

    func exportSnapshotJSON() {
        save(suggested: "airscope-snapshot.json", type: .json) {
            try? Exporter.json(self.currentSnapshot())
        }
    }

    private func save(suggested: String, type: UTType, makeData: @escaping () -> Data?) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggested
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url, let data = makeData() else { return }
            try? data.write(to: url)
        }
    }
}
