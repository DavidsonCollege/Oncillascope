import SwiftUI
import WiFiModel

/// Per-BSS detail with the fully decoded IE tree (spec §4.5).
struct IEInspectorView: View {
    let network: BSSObservation
    @AppStorage(plainEnglishTooltipsKey) private var plainEnglish = false

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
                    ForEach(network.rawIEs) { ie in
                        IERow(ie: ie, help: Help.ieDescription(elementID: ie.elementID, extID: ie.extensionID))
                    }
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(network.ssid?.isEmpty == false ? network.ssid! : "<hidden>")
                .font(.title2).fontWeight(.bold)
            row("BSSID", network.bssid ?? "—", Help.bssid)
            row("Vendor", network.vendor ?? "—", Help.vendor)
            row("Channel", "\(network.channel.label) · \(network.channel.band.rawValue)", Help.channelInfo)
            row("Security", network.security.rawValue, Help.security)
            row("PHY", "\(network.phyGeneration.standardLabel) (\(network.phyGeneration.wifiLabel))", Help.phyGen)
            row("RSSI / SNR", "\(network.rssi) dBm / \(network.snr) dB", Help.snr)
            row("Beacon interval", "\(network.beaconInterval) TU", Help.beaconInterval)
            if let rate = network.maxTheoreticalRate {
                row("Max PHY rate", String(format: "%.0f Mbps", rate), Help.maxRate)
            }
            if let caps = network.capabilities {
                capabilityChips(caps)
            }
            if let load = network.bssLoad {
                row("Channel utilization", "\(Int(load.channelUtilization))%", Help.utilization)
                row("Associated stations", "\(load.stationCount)", Help.stations)
            }
        }
    }

    private func capabilityChips(_ c: CapabilitySet) -> some View {
        var items: [(text: String, help: String)] = []
        if let n = c.spatialStreams { items.append(("\(n) streams", Help.nss.resolved(plain: plainEnglish))) }
        if let m = c.maxMCS { items.append(("MCS \(m)", Help.mcs.resolved(plain: plainEnglish))) }
        if let w = c.maxWidth { items.append((w.label, Help.channelWidth.resolved(plain: plainEnglish))) }
        if c.supportsMUMIMO == true { items.append(("MU-MIMO", Help.muMIMO.resolved(plain: plainEnglish))) }
        if c.supportsOFDMA == true { items.append(("OFDMA", Help.ofdma.resolved(plain: plainEnglish))) }
        if c.supports160MHz == true { items.append(("160 MHz", Help.channelWidth.resolved(plain: plainEnglish))) }
        return FlowChips(chips: items)
    }

    @ViewBuilder private func row(_ k: String, _ v: String, _ help: Help.Entry) -> some View {
        HStack(alignment: .top) {
            Text(k).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            Text(v).textSelection(.enabled)
        }
        .font(.callout)
        .help(help.resolved(plain: plainEnglish))
    }
}

/// One expandable decoded element with hex dump + interpretation.
private struct IERow: View {
    let ie: InformationElement
    let help: String
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
            .contentShape(Rectangle())
            .help(help)
        }
    }

    private var idLabel: String {
        if ie.elementID == 255, let ext = ie.extensionID { return "ID 255 / ext \(ext)" }
        return "ID \(ie.elementID)"
    }
}

/// Simple wrapping chip row; each chip carries its own hover tooltip.
private struct FlowChips: View {
    let chips: [(text: String, help: String)]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { chipViews }
            VStack(alignment: .leading) { chipViews }
        }
    }
    @ViewBuilder private var chipViews: some View {
        ForEach(chips, id: \.text) { chip in
            Badge(text: chip.text, color: .accentColor).help(chip.help)
        }
    }
}
