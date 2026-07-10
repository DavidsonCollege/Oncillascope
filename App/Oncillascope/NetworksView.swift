import SwiftUI
import WiFiModel

struct NetworksView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var annotations: AnnotationStore

    @State private var search = ""
    @State private var bandFilter: Band? = nil
    @State private var genFilter: PHYGeneration? = nil
    @State private var minRSSI: Double = -100
    @State private var groupBySSID = false
    @State private var selection: BSSObservation.ID?
    @State private var sortOrder = [KeyPathComparator(\BSSObservation.rssi, order: .reverse)]

    private var filtered: [BSSObservation] {
        model.networks.filter { n in
            (search.isEmpty
                || (n.ssid ?? "").localizedCaseInsensitiveContains(search)
                || (n.bssid ?? "").localizedCaseInsensitiveContains(search)
                || (n.vendor ?? "").localizedCaseInsensitiveContains(search))
            && (bandFilter == nil || n.channel.band == bandFilter)
            && (genFilter == nil || n.phyGeneration == genFilter)
            && Double(n.rssi) >= minRSSI
        }
    }

    private var selectedNetwork: BSSObservation? {
        model.networks.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            if filtered.isEmpty {
                ContentUnavailableView("No networks match",
                                       systemImage: "wifi.exclamationmark",
                                       description: Text("Adjust filters or scan again."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groupBySSID {
                groupedList
            } else {
                table
            }
        }
        .inspector(isPresented: .constant(selection != nil)) {
            if let net = selectedNetwork {
                IEInspectorView(network: net, annotations: annotations)
                    .inspectorColumnWidth(min: 320, ideal: 380, max: 520)
            } else {
                Text("Select a network").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        // Lay out on one row when there's room; wrap to two rows when narrow.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                searchField.frame(minWidth: 160, maxWidth: 260)
                controls
                Spacer()
                countLabel
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack { searchField.frame(maxWidth: 320); Spacer(); countLabel }
                HStack(spacing: 12) { controls; Spacer() }
            }
        }
        .padding(10)
    }

    private var searchField: some View {
        TextField("Search SSID, BSSID, vendor", text: $search)
            .textFieldStyle(.roundedBorder)
    }

    @ViewBuilder private var controls: some View {
        Picker("Band", selection: $bandFilter) {
            Text("All bands").tag(Band?.none)
            ForEach([Band.ghz2_4, .ghz5, .ghz6], id: \.self) { Text($0.rawValue).tag(Band?.some($0)) }
        }.fixedSize()

        Picker("Generation", selection: $genFilter) {
            Text("All").tag(PHYGeneration?.none)
            ForEach([PHYGeneration.be, .ax, .ac, .n], id: \.self) {
                Text($0.standardLabel).tag(PHYGeneration?.some($0))
            }
        }.fixedSize()

        VStack(alignment: .leading, spacing: 0) {
            Text("Min RSSI: \(Int(minRSSI)) dBm").font(.caption2).foregroundStyle(.secondary)
            Slider(value: $minRSSI, in: -100...(-30)).frame(width: 130)
        }

        Toggle("Group by SSID", isOn: $groupBySSID).toggleStyle(.checkbox)
    }

    private var countLabel: some View {
        Text("\(filtered.count) of \(model.networks.count)")
            .font(.caption).foregroundStyle(.secondary)
    }

    // MARK: - Table

    private var table: some View {
        // Table caps the builder at 10 columns, so the swatch + note indicator live
        // inside the SSID cell rather than as standalone columns.
        Table(filtered.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
            TableColumn("SSID") { n in
                HStack(spacing: 6) {
                    ColorSwatchMenu(annotations: annotations, id: n.id, ssid: n.ssid, bssid: n.bssid)
                    Text(n.ssid?.isEmpty == false ? n.ssid! : "<hidden>")
                        .foregroundStyle(annotations.color(for: n.id).color ?? .primary)
                    let note = annotations.annotation(for: n.id).note
                    if !note.isEmpty {
                        Image(systemName: "note.text")
                            .font(.caption2).foregroundStyle(.secondary).help(note)
                    }
                }
            }
            TableColumn("BSSID") { Text(redact($0.bssid)).font(.system(.body, design: .monospaced)) }
            TableColumn("Vendor") { Text($0.vendor ?? "—") }
            TableColumn("Band") { Badge(text: $0.channel.band.rawValue, color: $0.channel.band.tint) }
            TableColumn("Ch", value: \.channel.number) { Text($0.channel.label) }
            TableColumn("RSSI", value: \.rssi) {
                Text("\($0.rssi)").foregroundStyle(Quality.rssiColor($0.rssi))
            }
            TableColumn("SNR", value: \.snr) {
                Text("\($0.snr)").foregroundStyle(Quality.snrColor($0.snr))
            }
            TableColumn("Security") { Text($0.security.rawValue).font(.caption) }
            TableColumn("PHY") { Badge(text: $0.phyGeneration.standardLabel, color: $0.phyGeneration.badgeColor) }
            TableColumn("Util · Sta") { n in
                if let load = n.bssLoad {
                    Text("\(Int(load.channelUtilization))% · \(load.stationCount)")
                        .foregroundStyle(Quality.utilizationColor(load.channelUtilization))
                } else { Text("—").foregroundStyle(.secondary) }
            }
        }
    }

    // MARK: - Grouped list (group by SSID → physical AP w/ multiple BSSIDs)

    private var groupedList: some View {
        List(selection: $selection) {
            ForEach(groups, id: \.0) { (name, members) in
                SwiftUI.Section(header: Text("\(name)  ·  \(members.count) BSS")) {
                    ForEach(members) { n in
                        HStack {
                            ColorSwatchMenu(annotations: annotations, id: n.id, ssid: n.ssid, bssid: n.bssid)
                            Text(redact(n.bssid)).font(.system(.body, design: .monospaced))
                            Badge(text: n.channel.label, color: n.channel.band.tint)
                            Badge(text: n.phyGeneration.standardLabel, color: n.phyGeneration.badgeColor)
                            Spacer()
                            Text("\(n.rssi) dBm").foregroundStyle(Quality.rssiColor(n.rssi))
                        }
                        .tag(n.id)
                    }
                }
            }
        }
    }

    private var groups: [(String, [BSSObservation])] {
        Dictionary(grouping: filtered) { $0.ssid?.isEmpty == false ? $0.ssid! : "<hidden>" }
            .map { ($0.key, $0.value.sorted { $0.rssi > $1.rssi }) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    private func redact(_ s: String?) -> String {
        guard let s, !s.isEmpty, s != "<redacted>" else { return "<redacted>" }
        return s
    }
}
