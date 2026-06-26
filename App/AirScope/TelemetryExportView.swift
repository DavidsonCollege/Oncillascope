import SwiftUI

struct TelemetryExportView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            SwiftUI.Section("Live Capture") {
                LabeledContent("Samples buffered", value: "\(model.samples.count)")
                LabeledContent("Events (roam / channel)", value: "\(model.markers.count)")
                HStack {
                    Text("Refresh interval")
                    Slider(value: $model.refreshInterval, in: 0.5...10, step: 0.5)
                    Text("\(model.refreshInterval, specifier: "%.1f") s").monospacedDigit()
                }
                Toggle("Auto-rescan nearby networks (~20s)", isOn: $model.autoScan)
                Button("Clear telemetry buffer", role: .destructive) { model.clearTelemetry() }
            }

            SwiftUI.Section("Export") {
                Button("Export nearby networks as CSV…") { model.exportNetworksCSV() }
                Button("Export telemetry as CSV…") { model.exportTelemetryCSV() }
                Button("Export snapshot as JSON…") { model.exportSnapshotJSON() }
            }

            SwiftUI.Section("Rolling Log to Disk") {
                if model.isLogging {
                    LabeledContent("Logging to", value: model.logURL?.lastPathComponent ?? "—")
                    Button("Stop logging", role: .destructive) { model.stopLogging() }
                } else {
                    Text("Off by default. Appends each sample to a CSV file you choose.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Start logging…") { model.startLogging() }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
    }
}
