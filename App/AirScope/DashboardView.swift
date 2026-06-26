import SwiftUI
import WiFiModel

struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(plainEnglishTooltipsKey) private var plainEnglish = false

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
            MetricTile(title: "Signal (RSSI)", value: "\(c.rssi) dBm", color: Quality.rssiColor(c.rssi),
                       help: Help.rssi.resolved(plain: plainEnglish))
            MetricTile(title: "Noise", value: "\(c.noise) dBm", help: Help.noise.resolved(plain: plainEnglish))
            MetricTile(title: "SNR", value: "\(c.snr) dB",
                       subtitle: Quality.snrLabel(c.snr), color: Quality.snrColor(c.snr),
                       help: Help.snr.resolved(plain: plainEnglish))
            MetricTile(title: "Tx Rate", value: String(format: "%.0f Mbps", c.txRate), help: Help.txRate.resolved(plain: plainEnglish))
            efficiencyTile(c)
            if let tp = c.transmitPower {
                MetricTile(title: "Tx Power", value: "\(tp) mW",
                           subtitle: c.transmitPowerDBm.map { "≈ \($0) dBm" }, help: Help.txPower.resolved(plain: plainEnglish))
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
                color: eff > 0.6 ? .green : (eff > 0.3 ? .yellow : .red),
                help: Help.maxRate.resolved(plain: plainEnglish)
            )
        } else {
            MetricTile(title: "Max PHY Rate", value: "—",
                       subtitle: model.phyMetricsAvailable ? nil : "needs admin", help: Help.maxRate.resolved(plain: plainEnglish))
        }
    }

    // MARK: - PHY tiles (wdutil)

    @ViewBuilder private func phyTiles(_ c: ConnectionInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PHY Layer").font(.headline)
            if model.phyMetricsAvailable {
                LazyVGrid(columns: grid, spacing: 12) {
                    MetricTile(title: "MCS Index", value: c.mcsIndex.map(String.init) ?? "—",
                               help: Help.mcs.resolved(plain: plainEnglish))
                    MetricTile(title: "Spatial Streams (NSS)", value: c.nss.map(String.init) ?? "—",
                               help: Help.nss.resolved(plain: plainEnglish))
                    MetricTile(title: "Guard Interval",
                               value: c.guardInterval.map { "\($0) ns" } ?? "—", help: Help.guardInterval.resolved(plain: plainEnglish))
                    MetricTile(title: "CCA (busy)", value: c.cca.map { "\($0)%" } ?? "—",
                               color: c.cca.map { Quality.utilizationColor(Double($0)) } ?? .primary,
                               help: Help.cca.resolved(plain: plainEnglish))
                }
            } else {
                Text("MCS / NSS / guard interval / CCA require a one-time administrator authorization. Use the banner above to enable them.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var grid: [GridItem] { [GridItem(.adaptive(minimum: 150), spacing: 12)] }
}
