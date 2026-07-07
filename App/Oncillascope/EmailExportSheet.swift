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
        if !r.failed.isEmpty { parts.append("Failed to write: \(r.failed.joined(separator: ", "))") }
        if r.usedFallback { parts.append("No mail client found — opened a blank message and revealed the files in Finder to attach manually.") }
        return parts.joined(separator: "\n")
    }
}

/// A focused-scene action: the File-menu command triggers the email sheet on the
/// frontmost window only. (WindowGroup can have several windows; a global broadcast would
/// open the sheet on all of them at once.)
struct EmailExportAction: Equatable {
    let id: UUID
    let trigger: () -> Void
    static func == (lhs: EmailExportAction, rhs: EmailExportAction) -> Bool { lhs.id == rhs.id }
}

struct EmailExportActionKey: FocusedValueKey { typealias Value = EmailExportAction }

extension FocusedValues {
    var emailExportAction: EmailExportAction? {
        get { self[EmailExportActionKey.self] }
        set { self[EmailExportActionKey.self] = newValue }
    }
}

/// Presents EmailExportSheet for this window and publishes the trigger as a focused-scene
/// value so the menu command reaches only the frontmost window.
struct EmailExportSheetPresenter: ViewModifier {
    @State private var show = false
    @State private var actionID = UUID()   // stable per window → no focused-value churn
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $show) { EmailExportSheet() }
            .focusedSceneValue(\.emailExportAction, EmailExportAction(id: actionID) { show = true })
    }
}
