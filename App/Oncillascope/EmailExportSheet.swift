import SwiftUI
import Telemetry

/// Sheet to pick which exports to email to the helpdesk. Recipient is pre-filled from the
/// managed preference (or the baked default) and is editable.
struct EmailExportSheet: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var annotations: AnnotationStore
    @Environment(\.dismiss) private var dismiss

    @State private var recipient = HelpdeskRecipient.resolve(.standard)
    @State private var selected: Set<ExportKind> = Set(ExportKind.allCases)
    @State private var resultNote: String?

    private var recipientValid: Bool { HelpdeskRecipient.isValid(recipient) }
    private var canSend: Bool { recipientValid && !selected.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Email Exports to Helpdesk").font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("To").font(.caption).foregroundStyle(.secondary)
                TextField("recipient@davidson.edu", text: $recipient)
                    .textFieldStyle(.roundedBorder)
                if !recipient.isEmpty && !recipientValid {
                    Text("Not a valid email address.").font(.caption).foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Attachments").font(.caption).foregroundStyle(.secondary)
                ForEach(ExportKind.allCases) { kind in
                    Toggle(kind.displayName, isOn: Binding(
                        get: { selected.contains(kind) },
                        set: { on in if on { selected.insert(kind) } else { selected.remove(kind) } }
                    )).toggleStyle(.checkbox)
                }
            }

            if let note = resultNote {
                Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Compose Email") {
                    let r = EmailExporter.compose(recipient: recipient, kinds: selected,
                                                  model: model, annotations: annotations)
                    resultNote = summary(r)
                    if !r.usedFallback { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSend)
            }
        }
        .padding(18)
        .frame(width: 380)
    }

    private func summary(_ r: EmailComposeResult) -> String {
        var parts: [String] = []
        if !r.skipped.isEmpty { parts.append("Skipped (empty): \(r.skipped.joined(separator: ", "))") }
        if r.usedFallback { parts.append("No mail client found — opened a blank message and revealed the files in Finder to attach manually.") }
        return parts.joined(separator: "\n")
    }
}

/// Presents EmailExportSheet when the menu posts `.showEmailExport`.
struct EmailExportSheetPresenter: ViewModifier {
    @State private var show = false
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .showEmailExport)) { _ in show = true }
            .sheet(isPresented: $show) { EmailExportSheet() }
    }
}
