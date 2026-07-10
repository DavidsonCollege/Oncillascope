import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// A fixed, named palette for user-assigned network colors. Stored by name so the choice
/// is stable and Codable; `.none` means "no color assigned".
enum NetworkColor: String, CaseIterable, Codable, Identifiable {
    case none, red, orange, yellow, green, teal, blue, purple, gray

    var id: String { rawValue }

    /// The SwiftUI color, or nil for `.none`.
    var color: Color? {
        switch self {
        case .none:   return nil
        case .red:    return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green:  return .green
        case .teal:   return .teal
        case .blue:   return .blue
        case .purple: return .purple
        case .gray:   return .gray
        }
    }

    var label: String {
        switch self {
        case .none: return "None"
        default:    return rawValue.capitalized
        }
    }
}

/// A user annotation attached to one network. The `ssid`/`bssid` are snapshotted at edit
/// time purely so exports remain meaningful even after the network drops out of range.
struct NetworkAnnotation: Codable, Equatable {
    var color: NetworkColor = .none
    var note: String = ""
    var ssid: String?
    var bssid: String?

    var isEmpty: Bool { color == .none && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Persistent per-network colors and notes, keyed by `BSSObservation.id` (BSSID when
/// available, else a stable SSID+channel fallback). Backed by UserDefaults JSON so
/// annotations survive relaunch. Pure local storage — never transmitted.
@MainActor
final class AnnotationStore: ObservableObject {
    @Published private(set) var items: [String: NetworkAnnotation] = [:]

    private let defaultsKey = "networkAnnotations"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func annotation(for id: String) -> NetworkAnnotation {
        items[id] ?? NetworkAnnotation()
    }

    func color(for id: String) -> NetworkColor { items[id]?.color ?? .none }

    func setColor(_ color: NetworkColor, for id: String, ssid: String?, bssid: String?) {
        update(id: id, ssid: ssid, bssid: bssid) { $0.color = color }
    }

    func setNote(_ note: String, for id: String, ssid: String?, bssid: String?) {
        update(id: id, ssid: ssid, bssid: bssid) { $0.note = note }
    }

    func clear(id: String) {
        guard items[id] != nil else { return }
        items[id] = nil
        save()
    }

    private func update(id: String, ssid: String?, bssid: String?,
                        _ mutate: (inout NetworkAnnotation) -> Void) {
        var a = items[id] ?? NetworkAnnotation()
        a.ssid = ssid
        a.bssid = bssid
        mutate(&a)
        if a.isEmpty { items[id] = nil } else { items[id] = a }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: NetworkAnnotation].self, from: data)
        else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    // MARK: - Export

    /// CSV of every annotation: key, ssid, bssid, color, note.
    func annotationsCSV() -> String {
        func escape(_ s: String) -> String {
            (s.contains(",") || s.contains("\"") || s.contains("\n"))
                ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                : s
        }
        var rows = ["key,ssid,bssid,color,note"]
        for (key, a) in items.sorted(by: { $0.key < $1.key }) {
            rows.append([key, a.ssid ?? "", a.bssid ?? "", a.color.rawValue, a.note]
                .map(escape).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    func exportAnnotationsCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "oncillascope-annotations.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        let csv = annotationsCSV()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? csv.data(using: .utf8)?.write(to: url)
        }
    }
}

/// A compact menu that shows the assigned color as a swatch and lets the user pick one.
/// Used in the networks table and grouped list.
struct ColorSwatchMenu: View {
    // Injected explicitly, NOT via @EnvironmentObject: Table cells and Menu content are
    // re-evaluated in a detached attribute-graph branch on macOS where ancestor
    // .environmentObject values can be absent (e.g. row churn after sleep/wake), and
    // @EnvironmentObject responds to that with fatalError. Seen crashing in the field.
    @ObservedObject var annotations: AnnotationStore
    let id: String
    let ssid: String?
    let bssid: String?

    var body: some View {
        let current = annotations.color(for: id)
        Menu {
            ForEach(NetworkColor.allCases) { c in
                Button {
                    annotations.setColor(c, for: id, ssid: ssid, bssid: bssid)
                } label: {
                    Label {
                        Text(c.label)
                    } icon: {
                        if c == current { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            SwatchDot(color: current.color)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Assign a color to this network")
    }
}

/// The visual swatch: a filled dot for an assigned color, an outlined dot for none.
struct SwatchDot: View {
    let color: Color?
    var body: some View {
        Group {
            if let color {
                Circle().fill(color)
            } else {
                Circle().strokeBorder(.secondary.opacity(0.5), lineWidth: 1)
            }
        }
        .frame(width: 12, height: 12)
    }
}

/// A horizontal row of selectable color swatches for the inspector.
struct ColorPickerRow: View {
    // Injected explicitly for the same reason as ColorSwatchMenu: this lives in the
    // inspector panel, a presentation context that (like sheets — see
    // EmailExportSheetPresenter) does not reliably inherit environment objects.
    @ObservedObject var annotations: AnnotationStore
    let id: String
    let ssid: String?
    let bssid: String?

    var body: some View {
        let current = annotations.color(for: id)
        HStack(spacing: 8) {
            ForEach(NetworkColor.allCases) { c in
                Button {
                    annotations.setColor(c, for: id, ssid: ssid, bssid: bssid)
                } label: {
                    ZStack {
                        SwatchDot(color: c.color)
                        if c == current {
                            Circle().strokeBorder(.primary, lineWidth: 2)
                                .frame(width: 18, height: 18)
                        }
                    }
                    .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help(c.label)
            }
        }
    }
}
