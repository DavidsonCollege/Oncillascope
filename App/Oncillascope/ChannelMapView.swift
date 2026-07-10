import SwiftUI
import Charts
import WiFiModel

/// 2.4/5/6 GHz occupancy view: overlapping signal curves per BSS, plus an advisory
/// best-channel recommendation (spec §4.4).
struct ChannelMapView: View {
    @EnvironmentObject var model: AppModel
    @State private var band: Band = .ghz2_4
    @State private var hovered: BSSObservation?
    @State private var hoverPoint: CGPoint = .zero

    private let floorDBm = -100

    private var networksInBand: [BSSObservation] {
        model.networks.filter { $0.channel.band == band && $0.channel.primaryCenterMHz != nil }
    }

    /// Detected networks that can't be placed on any band tab (unknown band or an
    /// unmappable channel number). Surfaced as a count instead of silently dropped.
    private var unmappableCount: Int {
        model.networks.filter { $0.channel.primaryCenterMHz == nil }.count
    }

    /// Whether this Mac's radio supports the selected band. Unknown (empty set, e.g.
    /// Wi-Fi off) is treated as supported to avoid a false "unsupported" claim.
    private var bandSupported: Bool {
        model.supportedBands.isEmpty || model.supportedBands.contains(band)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Picker("Band", selection: $band) {
                        ForEach([Band.ghz2_4, .ghz5, .ghz6], id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).fixedSize()
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(networksInBand.count) BSS in band").font(.caption).foregroundStyle(.secondary)
                        Text("All detected networks — ignores the Networks table's filters")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }

                // Networks that can't be plotted would otherwise vanish silently and
                // read as a mismatch against the Networks table.
                if unmappableCount > 0 {
                    Label("\(unmappableCount) network\(unmappableCount == 1 ? "" : "s") with an unknown channel can't be plotted (still listed in the Networks table).",
                          systemImage: "questionmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if !bandSupported {
                    ContentUnavailableView {
                        Label("\(band.rawValue) not supported", systemImage: "antenna.radiowaves.left.and.right.slash")
                    } description: {
                        Text("This Mac's Wi-Fi radio does not support the \(band.rawValue) band, so no \(band.rawValue) networks can be detected.")
                    }
                    .frame(maxWidth: .infinity, minHeight: 360)
                } else if networksInBand.isEmpty {
                    ContentUnavailableView {
                        Label("No networks in \(band.rawValue)", systemImage: "chart.bar.xaxis")
                    } description: {
                        Text("No \(band.rawValue) networks were found in the most recent scan.")
                    }
                    .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    recommendation
                    spectrumChart
                }
            }
            .padding(16)
        }
    }

    // MARK: - Spectrum chart

    private var spectrumChart: some View {
        Chart {
            ForEach(networksInBand) { net in
                ForEach(curvePoints(for: net), id: \.mhz) { pt in
                    LineMark(x: .value("Freq (MHz)", pt.mhz),
                             y: .value("RSSI", pt.dbm),
                             series: .value("BSS", net.id))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(color(for: net))
                    // Highlight the hovered curve; dim the rest. Stale networks
                    // (missed the latest scan pass) draw faded, matching the table.
                    .opacity((hovered == nil ? 0.85 : (hovered?.id == net.id ? 1.0 : 0.18))
                             * (model.isStale(net.id) ? 0.35 : 1.0))
                    .lineStyle(StrokeStyle(lineWidth: hovered?.id == net.id ? 3 : 1.6))
                }
            }
        }
        .chartYScale(domain: floorDBm...(-20))
        .chartXScale(domain: bandFrequencyRange)
        .chartXAxisLabel("Frequency (MHz)")
        .chartYAxisLabel("RSSI (dBm)")
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            guard let anchor = proxy.plotFrame else { return }
                            let plot = geo[anchor]
                            let fx: Int? = proxy.value(atX: loc.x - plot.minX)
                            let fy: Int? = proxy.value(atY: loc.y - plot.minY)
                            if let f = fx, let y = fy {
                                hovered = networkNear(freqMHz: f, dbm: y)
                                hoverPoint = loc
                            }
                        case .ended:
                            hovered = nil
                        }
                    }
                if let h = hovered {
                    tooltip(h)
                        .fixedSize()
                        .position(x: min(max(hoverPoint.x, 90), geo.size.width - 90),
                                  y: max(hoverPoint.y - 46, 30))
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: 420)
        .padding(8)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Tooltip shown when hovering a curve: SSID + BSSID + channel + RSSI.
    private func tooltip(_ net: BSSObservation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(net.ssid?.isEmpty == false ? net.ssid! : "<hidden>")
                .font(.caption).bold()
            Text(net.bssid ?? "<redacted>")
                .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
            Text("ch \(net.channel.label) · \(net.rssi) dBm")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(color(for: net).opacity(0.6)))
        .shadow(radius: 3)
    }

    /// The network whose curve passes nearest the hovered (frequency, RSSI) point.
    private func networkNear(freqMHz: Int, dbm: Int) -> BSSObservation? {
        var best: (net: BSSObservation, dist: Double)?
        for net in networksInBand {
            guard let span = net.channel.frequencySpanMHz,
                  let center = net.channel.primaryCenterMHz,
                  freqMHz >= span.low, freqMHz <= span.high else { continue }
            // Linear-interpolate the triangular curve's height at this frequency.
            let t: Double = freqMHz <= center
                ? Double(freqMHz - span.low) / Double(max(1, center - span.low))
                : Double(span.high - freqMHz) / Double(max(1, span.high - center))
            let curveY = Double(floorDBm) + t * Double(net.rssi - floorDBm)
            let dist = abs(curveY - Double(dbm))
            if best == nil || dist < best!.dist { best = (net, dist) }
        }
        return best?.net
    }

    /// X-axis frequency span for the selected band (MHz). Without this, Swift Charts
    /// auto-scales from 0 and crushes every curve into a thin spike on the right.
    private var bandFrequencyRange: ClosedRange<Int> {
        switch band {
        case .ghz2_4: return 2400...2500
        case .ghz5: return 5150...5895
        case .ghz6: return 5925...7125
        case .unknown: return 0...1
        }
    }

    /// Three points forming a peak centered on the channel, spanning its width.
    private func curvePoints(for net: BSSObservation) -> [(mhz: Int, dbm: Int)] {
        guard let span = net.channel.frequencySpanMHz, let center = net.channel.primaryCenterMHz else { return [] }
        return [(span.low, floorDBm), (center, net.rssi), (span.high, floorDBm)]
    }

    private func color(for net: BSSObservation) -> Color {
        // Deterministic hue from the BSS id so each network keeps a stable color.
        let hash = abs(net.id.hashValue)
        return Color(hue: Double(hash % 360) / 360.0, saturation: 0.65, brightness: 0.9)
    }

    // MARK: - Best-channel recommendation (advisory heuristic)

    private var recommendation: some View {
        let best = bestChannel()
        return HStack(spacing: 8) {
            Image(systemName: "wand.and.stars").foregroundStyle(.yellow)
            if let best {
                Text("Suggested channel for \(band.rawValue): ")
                    + Text("\(best.channel)").bold()
                    + Text("  (\(best.count) overlapping network\(best.count == 1 ? "" : "s"))")
                    .foregroundColor(.secondary)
            } else {
                Text("Not enough data for a recommendation.")
            }
            Spacer()
            Text("Advisory only").font(.caption2).foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.quaternary.opacity(0.4), in: Capsule())
        }
        .font(.callout)
        .padding(10)
        .background(.yellow.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Pick the candidate primary channel with the least overlapping linear signal.
    private func bestChannel() -> (channel: Int, count: Int)? {
        let candidates: [Int]
        switch band {
        case .ghz2_4: candidates = [1, 6, 11]
        case .ghz5: candidates = [36, 40, 44, 48, 149, 153, 157, 161]
        case .ghz6: candidates = [37, 53, 69, 85, 101, 117]
        case .unknown: return nil
        }
        var best: (channel: Int, score: Double, count: Int)?
        for cand in candidates {
            let candInfo = ChannelInfo(number: cand, width: .mhz20, band: band)
            guard let candCenter = candInfo.primaryCenterMHz else { continue }
            var score = 0.0
            var count = 0
            for net in networksInBand {
                guard let span = net.channel.frequencySpanMHz else { continue }
                if candCenter >= span.low && candCenter <= span.high {
                    // Convert dBm to linear mW and accumulate interference.
                    score += pow(10.0, Double(net.rssi) / 10.0)
                    count += 1
                }
            }
            if best == nil || score < best!.score { best = (cand, score, count) }
        }
        return best.map { ($0.channel, $0.count) }
    }
}
