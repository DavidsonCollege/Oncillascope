import SwiftUI
import WiFiModel

struct DashboardView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let c = model.current {
                    header(c)
                    signalTiles(c)
                    phyTiles(c)
                    ChartsView()
                } else {
                    ContentUnavailableView(
                        "Not connected to Wi-Fi",
                        systemImage: "wifi.slash",
                        description: Text("Connect to a network to see live link metrics.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Header (identity)

    @ViewBuilder private func header(_ c: ConnectionInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(c.ssid ?? "Unknown SSID").font(.title).fontWeight(.bold)
                Badge(text: c.phyMode.wifiLabel, color: c.phyMode.badgeColor)
                Badge(text: c.channel.band.rawValue, color: c.channel.band.tint)
                Badge(text: c.security.rawValue,
                      color: c.security.isOpen ? .red : .green)
            }
            HStack(spacing: 14) {
                label("BSSID", redactable(c.bssid))
                if let v = c.vendor { label("Vendor", v) }
                label("Channel", c.channel.label)
                if let cc = c.countryCode { label("Country", cc) }
            }
            .font(.callout)
        }
    }

    private func redactable(_ s: String?) -> String {
        guard let s, !s.isEmpty, s != "<redacted>" else { return "—" }
        return s
    }

    @ViewBuilder private func label(_ k: String, _ v: String) -> some View {
        HStack(spacing: 4) {
            Text(k + ":").foregroundStyle(.secondary)
            Text(v).fontWeight(.medium).textSelection(.enabled)
        }
    }

    // MARK: - Signal tiles

    @ViewBuilder private func signalTiles(_ c: ConnectionInfo) -> some View {
        LazyVGrid(columns: grid, spacing: 12) {
            MetricTile(title: "Signal (RSSI)", value: "\(c.rssi) dBm", color: Quality.rssiColor(c.rssi))
            MetricTile(title: "Noise", value: "\(c.noise) dBm")
            MetricTile(title: "SNR", value: "\(c.snr) dB",
                       subtitle: Quality.snrLabel(c.snr), color: Quality.snrColor(c.snr))
            MetricTile(title: "Tx Rate", value: String(format: "%.0f Mbps", c.txRate))
            efficiencyTile(c)
            if let tp = c.transmitPower {
                MetricTile(title: "Tx Power", value: "\(tp)")
            }
        }
    }

    @ViewBuilder private func efficiencyTile(_ c: ConnectionInfo) -> some View {
        if let maxRate = c.maxTheoreticalRate {
            let eff = c.efficiency ?? 0
            MetricTile(
                title: "Max PHY Rate",
                value: String(format: "%.0f Mbps", maxRate),
                subtitle: String(format: "%.0f%% efficiency", eff * 100),
                color: eff > 0.6 ? .green : (eff > 0.3 ? .yellow : .red)
            )
        } else {
            MetricTile(title: "Max PHY Rate", value: "—",
                       subtitle: model.phyMetricsAvailable ? nil : "needs wdutil")
        }
    }

    // MARK: - PHY tiles (wdutil)

    @ViewBuilder private func phyTiles(_ c: ConnectionInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PHY Layer (wdutil)").font(.headline)
            if model.phyMetricsAvailable {
                LazyVGrid(columns: grid, spacing: 12) {
                    MetricTile(title: "MCS Index", value: c.mcsIndex.map(String.init) ?? "—")
                    MetricTile(title: "Spatial Streams (NSS)", value: c.nss.map(String.init) ?? "—")
                    MetricTile(title: "Guard Interval",
                               value: c.guardInterval.map { "\($0) ns" } ?? "—")
                    MetricTile(title: "CCA (busy)", value: c.cca.map { "\($0)%" } ?? "—",
                               color: c.cca.map { Quality.utilizationColor(Double($0)) } ?? .primary)
                }
            } else {
                Text("MCS / NSS / guard interval / CCA require admin authorization for `wdutil`. Use the banner above to enable them.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var grid: [GridItem] { [GridItem(.adaptive(minimum: 150), spacing: 12)] }
}
