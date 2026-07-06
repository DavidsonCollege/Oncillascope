# Email Exports to Helpdesk — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user email Oncillascope's exports to the IT helpdesk via their own Mail client — no SMTP, no stored credentials.

**Architecture:** A pure recipient-resolution helper in the `Telemetry` kit module (home of `Exporter`, unit-tested). App-side, an `EmailExporter` generates the user-selected exports to temp files (reusing the existing `Exporter.*` / `AnnotationStore.annotationsCSV()` generators) and hands them to `NSSharingService(.composeEmail)`; a SwiftUI sheet drives the selection; a File-menu item opens it.

**Tech Stack:** Swift 6, SwiftPM (Telemetry module + XCTest), SwiftUI, AppKit (`NSSharingService`, `NSWorkspace`), the hand-crafted Xcode pbxproj (objectVersion 77, `PBXFileSystemSynchronizedRootGroup` — files under `App/Oncillascope/` are auto-included, so no pbxproj edits are needed for new app source files).

## Global Constraints

- No SMTP, no stored credentials — send only via the user's configured Mail client. (spec)
- Baked default recipient: **`ti@davidson.edu`**; overridable by managed preference key **`helpdeskEmail`** (`UserDefaults.standard`), then by the user in the sheet. (spec)
- Reuse the existing four exports; add no new export formats (no `.pcap`). (spec)
- Swift tools 6.0; macOS 14 floor. No third-party runtime deps; no network calls.
- Follow existing app style: exports live in `ExportActions.swift`; menu items in `OncillascopeApp.swift`; the app already links the `Telemetry` module (via `ExportActions.swift`).

---

## File Structure

- Create: `Sources/Telemetry/HelpdeskRecipient.swift` — pure recipient resolution + email validation.
- Create: `Tests/TelemetryTests/HelpdeskRecipientTests.swift` — unit tests.
- Create: `App/Oncillascope/EmailExport.swift` — `ExportKind`, `EmailExporter` (temp-file generation + `NSSharingService` + fallback).
- Create: `App/Oncillascope/EmailExportSheet.swift` — the SwiftUI selection sheet.
- Modify: `App/Oncillascope/OncillascopeApp.swift` — add the **File ▸ Email Exports to Helpdesk…** menu item + sheet presentation state.

No pbxproj edits: new files live under `App/Oncillascope/` (auto-synced group), and `HelpdeskRecipient` lands in the already-linked `Telemetry` module.

---

### Task 1: `HelpdeskRecipient` (pure, TDD, in Telemetry)

**Files:**
- Create: `Sources/Telemetry/HelpdeskRecipient.swift`
- Test: `Tests/TelemetryTests/HelpdeskRecipientTests.swift`

**Interfaces:**
- Produces:
```swift
public enum HelpdeskRecipient {
    public static let defaultAddress = "ti@davidson.edu"
    public static let defaultsKey = "helpdeskEmail"
    public static func resolve(_ defaults: UserDefaults) -> String
    public static func isValid(_ email: String) -> Bool
}
```

- [ ] **Step 1: Write the failing test**

`Tests/TelemetryTests/HelpdeskRecipientTests.swift`:
```swift
import XCTest
@testable import Telemetry

final class HelpdeskRecipientTests: XCTestCase {
    private func defaults(_ value: String?) -> UserDefaults {
        let d = UserDefaults(suiteName: "HelpdeskRecipientTests")!
        d.removePersistentDomain(forName: "HelpdeskRecipientTests")
        if let value { d.set(value, forKey: HelpdeskRecipient.defaultsKey) }
        return d
    }
    func testFallsBackToBakedDefault() {
        XCTAssertEqual(HelpdeskRecipient.resolve(defaults(nil)), "ti@davidson.edu")
    }
    func testManagedPreferenceWins() {
        XCTAssertEqual(HelpdeskRecipient.resolve(defaults("it-team@davidson.edu")),
                       "it-team@davidson.edu")
    }
    func testBlankManagedPreferenceFallsBack() {
        XCTAssertEqual(HelpdeskRecipient.resolve(defaults("   ")), "ti@davidson.edu")
    }
    func testValidation() {
        XCTAssertTrue(HelpdeskRecipient.isValid("a@b.co"))
        XCTAssertTrue(HelpdeskRecipient.isValid("ti@davidson.edu"))
        XCTAssertFalse(HelpdeskRecipient.isValid("nope"))
        XCTAssertFalse(HelpdeskRecipient.isValid("a@b"))
        XCTAssertFalse(HelpdeskRecipient.isValid(""))
        XCTAssertFalse(HelpdeskRecipient.isValid("a b@c.com"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HelpdeskRecipientTests`
Expected: FAIL — `HelpdeskRecipient` not found.

- [ ] **Step 3: Write minimal implementation**

`Sources/Telemetry/HelpdeskRecipient.swift`:
```swift
import Foundation

/// Resolves the helpdesk email recipient and validates addresses. Pure so it can be unit
/// tested; lives in Telemetry alongside `Exporter` (the export machinery it serves).
public enum HelpdeskRecipient {
    /// Baked default when no managed preference is set.
    public static let defaultAddress = "ti@davidson.edu"
    /// Managed-preference key IT can set (MDM profile / `defaults write`).
    public static let defaultsKey = "helpdeskEmail"

    /// Managed preference (if a non-blank string) else the baked default.
    public static func resolve(_ defaults: UserDefaults) -> String {
        if let v = defaults.string(forKey: defaultsKey) {
            let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return defaultAddress
    }

    /// Minimal syntactic check: non-empty local part, "@", a domain with a dot, no spaces.
    public static func isValid(_ email: String) -> Bool {
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let local = parts[0], domain = parts[1]
        guard !local.isEmpty, !domain.isEmpty else { return false }
        guard !email.contains(" ") else { return false }
        // domain must have a dot with non-empty labels on both sides
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return false }
        return true
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter HelpdeskRecipientTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Telemetry/HelpdeskRecipient.swift Tests/TelemetryTests/HelpdeskRecipientTests.swift
git commit -m "feat(email): helpdesk recipient resolution + validation (Telemetry)"
```

---

### Task 2: `EmailExporter` + `ExportKind` (app; generation + NSSharingService)

**Files:**
- Create: `App/Oncillascope/EmailExport.swift`

**Interfaces:**
- Consumes: `Exporter.networksCSV(_:)`, `Exporter.samplesCSV(_:)`, `Exporter.json(_ snapshot:)` (throws → `Data`), `AnnotationStore.annotationsCSV()`, `AppModel.networks`, `AppModel.samples`, `AppModel.currentSnapshot()`, `HelpdeskRecipient` (Task 1).
- Produces:
```swift
enum ExportKind: String, CaseIterable, Identifiable {
    case networks, telemetry, snapshot, annotations
    var id: String { rawValue }
    var displayName: String
    var fileName: String
}
struct EmailComposeResult { let attached: [String]; let skipped: [String]; let usedFallback: Bool }
enum EmailExporter {
    /// Generate the selected exports to temp files and open a pre-addressed compose window
    /// (or the mailto+Finder fallback). Returns what was attached/skipped.
    @MainActor static func compose(recipient: String, kinds: Set<ExportKind>,
                                   model: AppModel, annotations: AnnotationStore) -> EmailComposeResult
}
```

**Notes for the implementer:**
- Empty-skip rule: `networks` when `model.networks.isEmpty`; `telemetry` when `model.samples.isEmpty`; `annotations` when `annotations.items.isEmpty`; `snapshot` is never skipped (always has the current connection/timestamp).
- Temp files: write under `FileManager.default.temporaryDirectory.appendingPathComponent("oncillascope-email-\(UUID().uuidString)")` (create the dir); leave for the OS to reap.
- `NSSharingService` items: `[bodyString as NSString] + fileURLs`. Set `.recipients = [recipient]` and `.subject`. Gate on `canPerform(withItems:)`; else fallback.
- Fallback: open `mailto:<recipient>?subject=<enc>` via `NSWorkspace.shared.open(_:)`, then `NSWorkspace.shared.activateFileViewerSelecting(fileURLs)` to reveal the files for manual attachment.

- [ ] **Step 1: Implement**

`App/Oncillascope/EmailExport.swift`:
```swift
import Foundation
import AppKit
import Telemetry

/// The four exports that can be attached to a helpdesk email.
enum ExportKind: String, CaseIterable, Identifiable {
    case networks, telemetry, snapshot, annotations
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .networks:    return "Nearby Networks (CSV)"
        case .telemetry:   return "Telemetry (CSV)"
        case .snapshot:    return "Snapshot (JSON)"
        case .annotations: return "Annotations (CSV)"
        }
    }
    var fileName: String {
        switch self {
        case .networks:    return "oncillascope-networks.csv"
        case .telemetry:   return "oncillascope-telemetry.csv"
        case .snapshot:    return "oncillascope-snapshot.json"
        case .annotations: return "oncillascope-annotations.csv"
        }
    }
}

struct EmailComposeResult {
    let attached: [String]
    let skipped: [String]
    let usedFallback: Bool
}

enum EmailExporter {
    /// Bytes for a kind, or nil if there's nothing meaningful to attach (skip it).
    @MainActor
    private static func data(for kind: ExportKind,
                             model: AppModel, annotations: AnnotationStore) -> Data? {
        switch kind {
        case .networks:
            guard !model.networks.isEmpty else { return nil }
            return Exporter.networksCSV(model.networks).data(using: .utf8)
        case .telemetry:
            guard !model.samples.isEmpty else { return nil }
            return Exporter.samplesCSV(model.samples).data(using: .utf8)
        case .snapshot:
            return try? Exporter.json(model.currentSnapshot())
        case .annotations:
            guard !annotations.items.isEmpty else { return nil }
            return annotations.annotationsCSV().data(using: .utf8)
        }
    }

    @MainActor
    static func compose(recipient: String, kinds: Set<ExportKind>,
                        model: AppModel, annotations: AnnotationStore) -> EmailComposeResult {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("oncillascope-email-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var urls: [URL] = []
        var attached: [String] = [], skipped: [String] = []
        for kind in ExportKind.allCases where kinds.contains(kind) {
            guard let data = data(for: kind, model: model, annotations: annotations) else {
                skipped.append(kind.displayName); continue
            }
            let url = dir.appendingPathComponent(kind.fileName)
            do { try data.write(to: url); urls.append(url); attached.append(kind.displayName) }
            catch { skipped.append(kind.displayName) }
        }

        let host = ProcessInfo.processInfo.hostName
        let subject = "Oncillascope export — \(host)"
        let body = "Attached: \(attached.isEmpty ? "(none)" : attached.joined(separator: ", ")). " +
                   "Generated by Oncillascope on \(host)."

        let items: [Any] = [body as NSString] + urls
        if let service = NSSharingService(named: .composeEmail), service.canPerform(withItems: items) {
            service.recipients = [recipient]
            service.subject = subject
            service.perform(withItems: items)
            return EmailComposeResult(attached: attached, skipped: skipped, usedFallback: false)
        }

        // Fallback: no Mail client configured. Open a pre-addressed mailto (no attachment)
        // and reveal the files so the user can attach them manually.
        let enc = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let mailto = URL(string: "mailto:\(recipient)?subject=\(enc)") {
            NSWorkspace.shared.open(mailto)
        }
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        return EmailComposeResult(attached: attached, skipped: skipped, usedFallback: true)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
xcodebuild -project App/Oncillascope.xcodeproj -scheme Oncillascope -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -20
```
Expected: `BUILD SUCCEEDED`. (No unit test — this touches AppKit/system services; verified by build + Task 3's manual E2E.)

- [ ] **Step 3: Commit**

```bash
git add App/Oncillascope/EmailExport.swift
git commit -m "feat(email): EmailExporter generates selected exports + composes via NSSharingService"
```

---

### Task 3: Selection sheet + menu wiring + manual verification

**Files:**
- Create: `App/Oncillascope/EmailExportSheet.swift`
- Modify: `App/Oncillascope/OncillascopeApp.swift`

**Interfaces:**
- Consumes: `ExportKind`, `EmailExporter.compose(...)`, `EmailComposeResult` (Task 2); `HelpdeskRecipient.resolve(_:)` / `.isValid(_:)` (Task 1); `AppModel` + `AnnotationStore` (EnvironmentObjects).

- [ ] **Step 1: Implement the sheet**

`App/Oncillascope/EmailExportSheet.swift`:
```swift
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
```

- [ ] **Step 2: Wire the menu + sheet in `OncillascopeApp.swift`**

Add sheet-presentation state and a menu item. In `OncillascopeApp`, add to the `WindowGroup`'s content a sheet trigger driven by a shared `@State`, and add the command. Concretely:

Add a `@State private var showEmailSheet = false` is not directly reachable from `.commands`; instead route through a notification. Add near the top of `OncillascopeApp.swift`:
```swift
extension Notification.Name { static let showEmailExport = Notification.Name("showEmailExport") }
```
In the `WindowGroup` content chain (after `.environmentObject(annotations)`), add:
```swift
                .modifier(EmailExportSheetPresenter())
```
And define the presenter in `EmailExportSheet.swift`:
```swift
/// Presents EmailExportSheet when the menu posts `.showEmailExport`.
struct EmailExportSheetPresenter: ViewModifier {
    @State private var show = false
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .showEmailExport)) { _ in show = true }
            .sheet(isPresented: $show) { EmailExportSheet() }
    }
}
```
In the `.commands` `CommandGroup(after: .newItem)` block, after the existing export buttons, add:
```swift
                Button("Email Exports to Helpdesk…") {
                    NotificationCenter.default.post(name: .showEmailExport, object: nil)
                }
```

- [ ] **Step 3: Build**

Run:
```bash
xcodebuild -project App/Oncillascope.xcodeproj -scheme Oncillascope -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -20
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Manual end-to-end verification**

Run the app (`open` the built Release app or ⌘R in Xcode). With a Mail client configured:
1. **File ▸ Email Exports to Helpdesk…** opens the sheet; recipient pre-filled `ti@davidson.edu`; all four checked.
2. Click **Compose Email** → a new message opens, addressed to `ti@davidson.edu`, subject `Oncillascope export — <host>`, with the checked exports attached; sheet dismisses.
3. Re-open, uncheck all but Networks → only that file attaches.
4. Empty-skip: if telemetry/annotations are empty, they're listed as "Skipped (empty)" in the sheet note and not attached.
5. Recipient validation: clear the field → "Compose Email" disables; type `nope` → shows "Not a valid email address" and stays disabled.
6. (Optional) Managed pref: `defaults write edu.davidson.oncillascope helpdeskEmail qa@davidson.edu`, relaunch → recipient pre-fills `qa@davidson.edu`. Clean up: `defaults delete edu.davidson.oncillascope helpdeskEmail`.
7. (Optional) Fallback: temporarily with no default Mail client, Compose reveals files in Finder + opens a mailto; the sheet shows the fallback note.

- [ ] **Step 5: Commit**

```bash
git add App/Oncillascope/EmailExportSheet.swift App/Oncillascope/OncillascopeApp.swift
git commit -m "feat(email): selection sheet + File-menu item + manual E2E verified"
```

---

## Self-Review

**Spec coverage** (against `2026-07-06-email-export-design.md`):
- NSSharingService compose-email, no SMTP/credentials → Task 2. ✅
- `canPerform` gate + `mailto:` + reveal-in-Finder fallback → Task 2. ✅
- Recipient resolution (managed `helpdeskEmail` → baked `ti@davidson.edu`) + editable, validated → Tasks 1, 3. ✅
- Four-checkbox sheet, all-checked default, reuse `Exporter.*`/`annotationsCSV` → Tasks 2, 3. ✅
- Empty-export skip with a note → Task 2 (`data(for:)` returns nil) + Task 3 (summary note). ✅
- Menu item alongside existing exports → Task 3. ✅
- Subject/body with host context → Task 2. ✅
- Pure recipient logic unit-tested; compose flow manually verified → Tasks 1 (tests), 3 (manual). ✅
- No `.pcap`, no new formats → not built. ✅

**Placeholder scan:** no TBD/TODO; every code step has complete code; the menu-wiring note gives the exact notification-routing code rather than "wire it up."

**Type consistency:** `ExportKind`, `EmailComposeResult`, `EmailExporter.compose(recipient:kinds:model:annotations:)`, and `HelpdeskRecipient.resolve/.isValid` are used identically across Tasks 1–3. Generators match confirmed APIs: `Exporter.networksCSV([BSSObservation])`, `Exporter.samplesCSV([TelemetrySample])`, `Exporter.json(WiFiSnapshot) throws`, `AnnotationStore.annotationsCSV()`, `AppModel.networks/samples/currentSnapshot()`.
