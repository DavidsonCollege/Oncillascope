import SwiftUI
import WiFiModel

/// UserDefaults key for the View ▸ Plain-English Tooltips menu toggle.
let plainEnglishTooltipsKey = "plainEnglishTooltips"

/// Explanations of each measurement, in two registers: a precise **technical** version
/// (RF/Wi-Fi terminology) and a **plain-English** version for technical-but-not-wireless
/// folks. The View menu toggles which one the dashboard tooltips show.
enum Help {
    struct Entry {
        let technical: String
        let plain: String
        func resolved(plain usePlain: Bool) -> String { usePlain ? plain : technical }
    }

    static let rssi = Entry(
        technical: """
        Received Signal Strength Indicator — how strong the access point's signal is at your \
        Mac, in dBm (closer to 0 is stronger). It sets the ceiling for range and data rate; \
        below about −70 dBm, throughput and reliability start to fall off.
        """,
        plain: """
        How strong the Wi-Fi signal from your router is where you're sitting — like the bars \
        on a phone. Stronger is better; a weak signal means slower, less reliable Wi-Fi.
        """)

    static let noise = Entry(
        technical: """
        The RF noise floor in dBm — background interference from other radios, microwaves, and \
        the environment. A lower (more negative) noise floor means a cleaner channel and more \
        headroom for a fast link.
        """,
        plain: """
        How much background radio "static" is in the air from other devices and appliances. \
        Less static means your Wi-Fi signal stands out more clearly.
        """)

    static let snr = Entry(
        technical: """
        Signal-to-Noise Ratio (RSSI − noise), in dB — the single best predictor of link quality. \
        Higher SNR lets the radio use faster modulation. Roughly: >25 dB excellent, 15–25 dB \
        marginal, <15 dB poor.
        """,
        plain: """
        How much louder your Wi-Fi signal is than the background static — the best single number \
        for connection quality. Like hearing someone clearly across a noisy room: higher is better.
        """)

    static let txRate = Entry(
        technical: """
        The PHY transmit rate currently negotiated with the AP, in Mbps. It rises and falls in \
        real time as the radio adapts its modulation to changing signal conditions (rate control).
        """,
        plain: """
        The speed your Mac and router are talking at right now, in megabits per second. It \
        automatically speeds up or slows down as conditions change.
        """)

    static let maxRate = Entry(
        technical: """
        The theoretical maximum PHY rate this link could reach given its spatial streams, MCS, \
        channel width, and guard interval. Comparing it to the actual Tx rate shows how \
        efficiently the link is performing.
        """,
        plain: """
        The fastest this connection could go in theory right now. If the actual speed is far \
        below it, something — distance, interference, or congestion — is holding it back.
        """)

    static let txPower = Entry(
        technical: """
        Your Mac's Wi-Fi transmit power (shown in mW with the dBm equivalent). Higher power \
        extends uplink reach, but a good connection needs both ends to hear each other — a strong \
        download doesn't guarantee a strong upload.
        """,
        plain: """
        How loudly your Mac "talks back" to the router. A good connection needs both sides to \
        hear each other — a strong download doesn't guarantee a strong upload.
        """)

    static let mcs = Entry(
        technical: """
        Modulation and Coding Scheme index — the modulation (e.g. 64-QAM, 256-QAM, 1024-QAM) and \
        coding rate in use. Higher MCS packs more bits per symbol for greater speed, but requires \
        a higher SNR to stay error-free.
        """,
        plain: """
        How tightly data is packed into the signal. Higher numbers mean more speed, but they \
        only work when the signal is clean and strong.
        """)

    static let nss = Entry(
        technical: """
        Number of simultaneous MIMO spatial streams. Each additional stream multiplies throughput \
        — but only when the antennas and a rich multipath environment can support independent \
        streams.
        """,
        plain: """
        How many separate data "lanes" the Wi-Fi uses at once, like extra lanes on a highway. \
        More lanes mean more speed when conditions allow it.
        """)

    static let guardInterval = Entry(
        technical: """
        The gap inserted between OFDM symbols (e.g. 800 or 400 ns) to absorb echoes from \
        multipath. A shorter guard interval raises throughput in clean, low-multipath conditions; \
        a longer one is more robust.
        """,
        plain: """
        A tiny pause between bursts of data that keeps signal echoes from garbling things. A \
        shorter pause squeezes out a bit more speed when the airwaves are clean.
        """)

    static let cca = Entry(
        technical: """
        Clear Channel Assessment — the share of time the channel is sensed busy. High CCA means \
        airtime congestion or contention, which caps real-world throughput even when your signal \
        is strong.
        """,
        plain: """
        How often the channel is already busy with other devices' traffic. When it's high, \
        everyone competes for airtime and real-world speed drops — like a crowded highway.
        """)
}

/// Signal-quality thresholds + colors shared across the dashboard, table, and charts.
enum Quality {
    /// SNR (dB) → color. >25 good, 15–25 marginal, <15 poor.
    static func snrColor(_ snr: Int) -> Color {
        switch snr {
        case 25...: return .green
        case 15..<25: return .yellow
        default: return .red
        }
    }

    /// RSSI (dBm) → color. >-60 good, -75…-60 marginal, < -75 poor.
    static func rssiColor(_ rssi: Int) -> Color {
        switch rssi {
        case (-60)...: return .green
        case (-75)..<(-60): return .yellow
        default: return .red
        }
    }

    /// Channel utilization (%) → color. Higher = more congested.
    static func utilizationColor(_ pct: Double) -> Color {
        switch pct {
        case ..<40: return .green
        case 40..<70: return .yellow
        default: return .red
        }
    }

    static func snrLabel(_ snr: Int) -> String {
        switch snr {
        case 25...: return "Excellent"
        case 15..<25: return "Marginal"
        default: return "Poor"
        }
    }
}

extension Band {
    var tint: Color {
        switch self {
        case .ghz2_4: return .orange
        case .ghz5: return .blue
        case .ghz6: return .purple
        case .unknown: return .gray
        }
    }
}

extension PHYGeneration {
    var badgeColor: Color {
        switch self {
        case .be: return .purple
        case .ax: return .blue
        case .ac: return .teal
        case .n: return .gray
        default: return .secondary
        }
    }
}

/// A small labeled metric tile. All tiles render the same three rows (title, value,
/// subtitle) and fill their grid cell, so every block is the same height. A non-nil
/// `help` adds a "?" cue and a hover tooltip explaining the measurement.
struct MetricTile: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    var color: Color = .primary
    var help: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title.uppercased())
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if help != nil {
                    Image(systemName: "questionmark.circle")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.system(.title2, design: .rounded)).fontWeight(.semibold)
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
            // Always reserve the subtitle line so tiles with/without one match height.
            Text(subtitle ?? " ")
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1)
                .opacity(subtitle == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .help(help ?? "")
    }
}

/// A colored pill badge (PHY generation, band, security).
struct Badge: View {
    let text: String
    var color: Color = .accentColor
    var body: some View {
        Text(text)
            .font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
