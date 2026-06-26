import SwiftUI

enum Panel: String, CaseIterable, Identifiable, Hashable {
    case dashboard = "Dashboard"
    case networks = "Nearby Networks"
    case channels = "Channel Map"
    case logs = "Telemetry & Export"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .networks: return "wifi"
        case .channels: return "chart.bar.xaxis"
        case .logs: return "square.and.arrow.up"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection: Panel?

    init() {
        // Allow the initial panel to be chosen via env var (testing / screenshots):
        // AIRSCOPE_PANEL = dashboard | networks | channels | logs
        let env = ProcessInfo.processInfo.environment["AIRSCOPE_PANEL"]?.lowercased()
        let initial: Panel
        switch env {
        case "networks": initial = .networks
        case "channels": initial = .channels
        case "logs": initial = .logs
        default: initial = .dashboard
        }
        _selection = State(initialValue: initial)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(Panel.allCases) { panel in
                    Label(panel.rawValue, systemImage: panel.icon).tag(panel)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .safeAreaInset(edge: .bottom) { SidebarStatus() }
        } detail: {
            VStack(spacing: 0) {
                DegradedModeBanner()
                Group {
                    switch selection ?? .dashboard {
                    case .dashboard: DashboardView()
                    case .networks: NetworksView()
                    case .channels: ChannelMapView()
                    case .logs: TelemetryExportView()
                    }
                }
            }
            .toolbar { Toolbar() }
            .navigationTitle((selection ?? .dashboard).rawValue)
        }
    }
}

/// Bottom-of-sidebar live status summary.
private struct SidebarStatus: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            if let c = model.current, let ssid = c.ssid {
                Label(ssid, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.caption).lineLimit(1)
            } else {
                Label("Not associated", systemImage: "wifi.slash")
                    .foregroundStyle(.secondary).font(.caption)
            }
            Text("\(model.networks.count) networks nearby")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Toolbar: ToolbarContent {
    @EnvironmentObject var model: AppModel
    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.scanNow()
            } label: {
                if model.isScanning {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Scan", systemImage: "arrow.clockwise")
                }
            }
            .disabled(model.isScanning)
            .help("Scan for nearby networks")
        }
        ToolbarItem(placement: .automatic) {
            Toggle(isOn: $model.isPaused) {
                Label("Pause", systemImage: model.isPaused ? "play.fill" : "pause.fill")
            }
            .help(model.isPaused ? "Resume live updates" : "Pause live updates")
        }
    }
}
