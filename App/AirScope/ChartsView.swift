import SwiftUI
import Charts
import Telemetry

/// Rolling time-series charts (spec §4.2) with a selectable window and roam markers.
struct ChartsView: View {
    @EnvironmentObject var model: AppModel
    @State private var window: Window = .min5

    enum Window: String, CaseIterable, Identifiable {
        case min1 = "1 min", min5 = "5 min", min15 = "15 min", min60 = "1 hr"
        var id: String { rawValue }
        var seconds: TimeInterval {
            switch self { case .min1: 60; case .min5: 300; case .min15: 900; case .min60: 3600 }
        }
    }

    private var visible: [TelemetrySample] {
        let cutoff = Date().addingTimeInterval(-window.seconds)
        return model.samples.filter { $0.timestamp >= cutoff }
    }

    private var visibleMarkers: [TimelineMarker] {
        let cutoff = Date().addingTimeInterval(-window.seconds)
        return model.markers.filter { $0.timestamp >= cutoff }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Live Telemetry").font(.headline)
                Spacer()
                Picker("Window", selection: $window) {
                    ForEach(Window.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).fixedSize()
            }

            if visible.count < 2 {
                Text("Collecting samples…").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                chart("Signal & Noise (dBm)") {
                    series(\.rssi, "RSSI", .green)
                    series(\.noise, "Noise", .gray)
                }
                chart("SNR (dB)") { series(\.snr, "SNR", .blue) }
                chart("Tx Rate (Mbps)") { seriesDouble(\.txRate, "Tx Rate", .teal) }
                if model.phyMetricsAvailable {
                    chart("MCS Index") { seriesOptional(\.mcsIndex, "MCS", .purple) }
                    chart("CCA — Channel Busy (%)") { seriesOptional(\.cca, "CCA", .orange) }
                }
            }
        }
    }

    // MARK: - Chart builders

    @ViewBuilder
    private func chart<Content: ChartContent>(_ title: String,
                                              @ChartContentBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Chart {
                content()
                ForEach(visibleMarkers) { marker in
                    RuleMark(x: .value("Time", marker.timestamp))
                        .foregroundStyle(marker.kind == .roam ? .pink : .indigo)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text(marker.kind == .roam ? "roam" : "ch")
                                .font(.system(size: 8)).foregroundStyle(.secondary)
                        }
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .frame(height: 120)
            .padding(8)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func series(_ key: KeyPath<TelemetrySample, Int>, _ name: String, _ color: Color) -> some ChartContent {
        ForEach(visible, id: \.timestamp) { s in
            LineMark(x: .value("Time", s.timestamp),
                     y: .value(name, s[keyPath: key]),
                     series: .value("Metric", name))
            .foregroundStyle(color)
        }
    }

    private func seriesDouble(_ key: KeyPath<TelemetrySample, Double>, _ name: String, _ color: Color) -> some ChartContent {
        ForEach(visible, id: \.timestamp) { s in
            LineMark(x: .value("Time", s.timestamp),
                     y: .value(name, s[keyPath: key]),
                     series: .value("Metric", name))
            .foregroundStyle(color)
        }
    }

    private func seriesOptional(_ key: KeyPath<TelemetrySample, Int?>, _ name: String, _ color: Color) -> some ChartContent {
        ForEach(visible.filter { $0[keyPath: key] != nil }, id: \.timestamp) { s in
            LineMark(x: .value("Time", s.timestamp),
                     y: .value(name, s[keyPath: key] ?? 0),
                     series: .value("Metric", name))
            .foregroundStyle(color)
        }
    }
}
