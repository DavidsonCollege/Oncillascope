import SwiftUI
import WiFiModel

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

/// A small labeled metric tile.
struct MetricTile: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title2, design: .rounded)).fontWeight(.semibold)
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
            if let subtitle {
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
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
