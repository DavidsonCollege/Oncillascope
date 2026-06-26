import SwiftUI
import WiFiModel

/// Per-BSS detail with the fully decoded IE tree (spec §4.5).
struct IEInspectorView: View {
    let network: BSSObservation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summary
                Divider()
                Text("Information Elements").font(.headline)
                if network.rawIEs.isEmpty {
                    Text("No raw IE data (CoreWLAN returned none for this BSS).")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(network.rawIEs) { ie in IERow(ie: ie) }
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(network.ssid?.isEmpty == false ? network.ssid! : "<hidden>")
                .font(.title2).fontWeight(.bold)
            row("BSSID", network.bssid ?? "—")
            row("Vendor", network.vendor ?? "—")
            row("Channel", "\(network.channel.label) · \(network.channel.band.rawValue)")
            row("Security", network.security.rawValue)
            row("PHY", "\(network.phyGeneration.standardLabel) (\(network.phyGeneration.wifiLabel))")
            row("RSSI / SNR", "\(network.rssi) dBm / \(network.snr) dB")
            row("Beacon interval", "\(network.beaconInterval) TU")
            if let rate = network.maxTheoreticalRate {
                row("Max PHY rate", String(format: "%.0f Mbps", rate))
            }
            if let caps = network.capabilities {
                capabilityChips(caps)
            }
            if let load = network.bssLoad {
                row("Channel utilization", "\(Int(load.channelUtilization))%")
                row("Associated stations", "\(load.stationCount)")
            }
        }
    }

    @ViewBuilder private func capabilityChips(_ c: CapabilitySet) -> some View {
        FlowChips(chips: [
            c.spatialStreams.map { "\($0) streams" },
            c.maxMCS.map { "MCS \($0)" },
            c.maxWidth.map { $0.label },
            (c.supportsMUMIMO == true) ? "MU-MIMO" : nil,
            (c.supportsOFDMA == true) ? "OFDMA" : nil,
            (c.supports160MHz == true) ? "160 MHz" : nil,
        ].compactMap { $0 })
    }

    @ViewBuilder private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            Text(v).textSelection(.enabled)
        }
        .font(.callout)
    }
}

/// One expandable decoded element with hex dump + interpretation.
private struct IERow: View {
    let ie: InformationElement
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(ie.summary, id: \.self) { line in
                    Text("• " + line).font(.caption)
                }
                if !ie.bytes.isEmpty {
                    Text(ie.hexDump)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary).textSelection(.enabled)
                        .padding(6)
                        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.leading, 8).padding(.top, 4)
        } label: {
            HStack {
                Text(ie.name).fontWeight(.medium)
                Spacer()
                Text(idLabel).font(.caption2).foregroundStyle(.secondary)
                Text("\(ie.bytes.count) B").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var idLabel: String {
        if ie.elementID == 255, let ext = ie.extensionID { return "ID 255 / ext \(ext)" }
        return "ID \(ie.elementID)"
    }
}

/// Simple wrapping chip row.
private struct FlowChips: View {
    let chips: [String]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { chipViews }
            VStack(alignment: .leading) { chipViews }
        }
    }
    @ViewBuilder private var chipViews: some View {
        ForEach(chips, id: \.self) { Badge(text: $0, color: .accentColor) }
    }
}
