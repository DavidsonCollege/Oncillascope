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

    // MARK: - Per-BSS inspector readings

    static let bssid = Entry(
        technical: """
        Basic Service Set Identifier — the MAC address of this specific access-point radio. An AP \
        usually broadcasts a separate BSSID per band/SSID; this is the exact radio you'd associate with.
        """,
        plain: """
        The hardware ID of this one access point. A router can broadcast several (one per band or \
        network name) — this is the specific one for this entry.
        """)

    static let vendor = Entry(
        technical: """
        Manufacturer resolved locally from the BSSID's first 24 bits (the OUI). "Locally administered" \
        means the AP uses a randomized or virtual BSSID, so no real vendor can be derived.
        """,
        plain: """
        Who made the access point, looked up from its hardware ID. "Locally administered" means that \
        ID is randomized, so the maker can't be identified.
        """)

    static let channelInfo = Entry(
        technical: """
        The operating channel number, bonded channel width (20/40/80/160/320 MHz), and band \
        (2.4/5/6 GHz). Wider channels carry more data but overlap more neighboring networks.
        """,
        plain: """
        Which channel and how wide a slice of the airwaves this network uses, and on which band. \
        Wider is faster but bumps into more nearby networks.
        """)

    static let security = Entry(
        technical: """
        The authentication + encryption suite advertised in the RSN element — e.g. WPA2/WPA3 Personal \
        or Enterprise, or Open. WPA3 (SAE) resists offline password-guessing attacks.
        """,
        plain: """
        How the network protects its traffic. WPA3 is the newest and strongest; "Open" means no \
        encryption at all.
        """)

    static let phyGen = Entry(
        technical: """
        The newest 802.11 PHY generation this BSS advertises (n/ac/ax/be = Wi-Fi 4/5/6/7), inferred from \
        its HT/VHT/HE/EHT capability elements. Newer generations add wider channels, higher-order \
        modulation, and OFDMA/MU-MIMO.
        """,
        plain: """
        The Wi-Fi generation the access point supports (Wi-Fi 4/5/6/7). Newer ones are faster and cope \
        better with lots of devices.
        """)

    static let beaconInterval = Entry(
        technical: """
        How often the AP transmits a beacon, in Time Units (1 TU = 1.024 ms). 100 TU ≈ 102.4 ms is the \
        common default; shorter intervals speed discovery/roaming at the cost of more airtime overhead.
        """,
        plain: """
        How often the access point announces itself. The usual value (100) is about ten times a second.
        """)

    static let channelWidth = Entry(
        technical: """
        The widest channel width this BSS advertises (20/40/80/160/320 MHz). Each doubling roughly \
        doubles peak throughput but consumes more spectrum and is more exposed to interference.
        """,
        plain: """
        How wide a slice of airwaves the network can use. Wider means faster, but more likely to clash \
        with neighbors.
        """)

    static let muMIMO = Entry(
        technical: """
        Multi-User MIMO — the AP transmits to several clients at once over different spatial streams, \
        improving efficiency with many devices (downlink in Wi-Fi 5; up- and downlink in Wi-Fi 6).
        """,
        plain: """
        Lets the access point talk to several devices at the same time instead of one at a time, so a \
        busy network stays quicker.
        """)

    static let ofdma = Entry(
        technical: """
        Orthogonal Frequency-Division Multiple Access (Wi-Fi 6+) — divides a channel into sub-carrier \
        "resource units" so the AP serves many clients in a single transmission, cutting latency under load.
        """,
        plain: """
        A Wi-Fi 6 feature that splits one channel among many devices at once, which lowers lag when lots \
        of devices are connected.
        """)

    static let utilization = Entry(
        technical: """
        From the BSS Load element: the fraction of time the AP sensed the channel busy (carrier sense), \
        scaled from a 0–255 byte to a percentage. High values mean airtime congestion that caps real throughput.
        """,
        plain: """
        How busy this network says its channel is. High means lots of competing traffic, which slows \
        everyone down.
        """)

    static let stations = Entry(
        technical: """
        From the BSS Load element: the number of client devices currently associated with this AP. More \
        associated clients means more contention for airtime.
        """,
        plain: """
        How many devices are currently connected to this access point. They all share the same airtime.
        """)

    /// Accurate one-line description of an 802.11 Information Element, for the IE tree.
    static func ieDescription(elementID: Int, extID: Int?) -> String {
        if elementID == 255 {
            switch extID {
            case 35: return "802.11ax (Wi-Fi 6) capabilities: OFDMA, up to 1024-QAM, 160 MHz, BSS coloring, and target wake time."
            case 36: return "802.11ax operating parameters, including BSS color and (where present) 6 GHz operation info."
            case 106, 108: return "802.11be (Wi-Fi 7): up to 320 MHz channels, 4096-QAM, and multi-link operation."
            case 59: return "HE 6 GHz band capabilities — parameters specific to operating in the 6 GHz band."
            default: return "An 802.11 extension element (newer-generation capability/operation data)."
            }
        }
        switch elementID {
        case 0:     return "The network name (SSID). An empty value means a hidden or wildcard (broadcast) network."
        case 1, 50: return "The data rates this BSS supports, in Mb/s; rates flagged 'basic' are mandatory to join. (High-throughput rates live in the HT/VHT/HE elements instead.)"
        case 3:     return "DS Parameter Set — the BSS's primary 20 MHz channel number, the anchor clients tune to."
        case 5:     return "TIM (Traffic Indication Map) — a power-save bitmap flagging which sleeping clients have buffered frames, and (as a DTIM) when buffered broadcast/multicast will be sent."
        case 7:     return "Country (802.11d) — the regulatory domain: country code plus, per channel sub-band, the allowed channels and maximum transmit power in dBm."
        case 11:    return "BSS Load (QBSS) — AP-reported load: associated-station count, channel-busy utilization, and remaining admission capacity for QoS traffic."
        case 32:    return "Power Constraint (802.11h) — a local reduction (dB) below the regulatory maximum transmit power for this channel, so clients lower their power to match (5 GHz)."
        case 35:    return "TPC Report (802.11h Transmit Power Control) — the transmit power used for this frame and the link margin (signal headroom above what's needed)."
        case 42:    return "ERP Information — 802.11g compatibility flags, e.g. whether legacy 802.11b stations are present."
        case 45:    return "HT Capabilities (802.11n / Wi-Fi 4) — supported MCS rates, 20/40 MHz width, spatial streams, and short guard interval."
        case 48:    return "RSN — the Robust Security Network element: the encryption ciphers and authentication (AKM) suites offered. This is where WPA2 vs WPA3 (SAE) is advertised."
        case 61:    return "HT Operation (802.11n) — primary channel and secondary-channel offset (whether 40 MHz bonding is active)."
        case 70:    return "RM Enabled Capabilities (802.11k) — radio-measurement support, e.g. the AP can hand out neighbor-AP lists to help clients roam."
        case 127:   return "Extended Capabilities — a bitmap advertising optional features such as 802.11v BSS Transition Management (assisted roaming)."
        case 191:   return "VHT Capabilities (802.11ac / Wi-Fi 5) — up to 160 MHz width, 256-QAM, spatial streams, and MU-MIMO support."
        case 192:   return "VHT Operation (802.11ac) — the operating channel width and center-frequency segment(s) in use."
        case 195:   return "VHT Transmit Power Envelope — per-bandwidth maximum transmit-power limits."
        case 201:   return "Reduced Neighbor Report — compact info about the AP's other-band radios (e.g. its 6 GHz BSS), aiding fast discovery."
        case 221:   return "Vendor Specific — vendor-defined data keyed by an OUI: e.g. WMM/WME QoS, WPS, or manufacturer extensions beyond the standard elements."
        default:    return "An 802.11 information element broadcast in this network's beacon / probe response."
        }
    }
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
