# Email Exports to Helpdesk — design

**Status:** approved design, pre-implementation.
**Date:** 2026-07-06.

## Goal

Let a user send Oncillascope's exports to the IT helpdesk from within the app, **without any
SMTP setup or stored credentials**. The user picks which exports to attach; the app generates
them and hands them to the user's configured Mail client, pre-addressed.

## Non-goals

- **No SMTP / no stored credentials.** Neither app-baked shared credentials (leakable) nor
  per-user SMTP config (friction, keychain burden). Excluded by design.
- **No automated/headless sending.** A human sends from their own mail client. Auto-filed
  tickets would need a server-side API — out of scope.
- **No new export formats.** Reuses the existing four exports. (A `.pcap` export was
  considered and rejected: the app holds scan summaries + raw IEs, not captured frames, so a
  pcap would be a misleading synthetic artifact. It belongs with a future real-capture
  feature, not here.)

## Mechanism

`NSSharingService(named: .composeEmail)` — opens the user's default Mail client with
attachments, recipient, and subject pre-filled. Sends under the user's authenticated
identity; leaves a Sent-folder audit trail; zero credentials in the app.

- **Availability gate:** call `service.canPerform(withItems:)` before offering/enabling the
  action. If false (no mail client configured), use the fallback.
- **Fallback (no mail client):** open a `mailto:` URL with recipient + subject (no
  attachment — `mailto` can't attach) **and** reveal the generated export files in Finder so
  the user can attach manually. The sheet states this clearly.

## Recipient configuration (managed-friendly)

Resolve the default recipient in order:
1. Managed preference `helpdeskEmail` (read from `UserDefaults.standard.string(forKey:)`) —
   IT sets it via an MDM configuration profile or `defaults write edu.davidson.oncillascope
   helpdeskEmail …`, no rebuild.
2. Baked default: **`ti@davidson.edu`**.

The resolved value pre-fills an **editable** recipient field in the sheet, so IT controls
the default while the user can still correct it before sending. Basic validation: the
Compose button is disabled if the recipient field isn't a syntactically valid address.

## Components

This is app-only (no kit module).

- `App/Oncillascope/EmailExport.swift`:
  - `HelpdeskRecipient.resolve(defaults:) -> String` — pure recipient resolution (managed
    pref → baked default). Unit-testable.
  - `enum ExportKind { case networks, telemetry, snapshot, annotations }` with, per kind, a
    display name, filename, and a `data()` closure that calls the existing generator
    (`Exporter.networksCSV`, `Exporter.samplesCSV`, `Exporter.json`,
    `AnnotationStore.annotationsCSV`). A kind whose `data()` is empty/nil is **skipped** (see
    error handling).
  - `EmailExporter.compose(recipient:kinds:model:annotations:)` — generates each selected
    export to a per-invocation temp subdir, builds `[body String] + [file URLs]`, and invokes
    `NSSharingService` (or the fallback). Returns a result the sheet can surface (sent / no
    mail client / nothing to attach).
- `App/Oncillascope/EmailExportSheet.swift` — SwiftUI sheet: editable recipient field
  (pre-filled), four checkboxes (all checked by default), **Compose Email** (disabled if no
  valid recipient or nothing checked) + **Cancel**. Shows the fallback note when
  `canPerform` is false.
- Menu: **File ▸ Email Exports to Helpdesk…** in the commands block of
  `App/Oncillascope/OncillascopeApp.swift`, alongside the existing export items. Opens the
  sheet.

## Data flow

`user picks kinds + recipient → EmailExporter generates selected exports to temp files
(reusing Exporter.*/annotationsCSV) → [body] + [fileURLs] → NSSharingService.composeEmail
(pre-addressed) → user reviews + sends in their mail client`.

Subject: `Oncillascope export — <hostname> — <ISO timestamp>`. Body: a one-line note listing
the attached files and the app version (context for the helpdesk).

## Error handling

- **No mail client** (`canPerform` false): fallback (`mailto:` + reveal-in-Finder); the sheet
  explains it.
- **Selected export has no data** (e.g. telemetry buffer empty, no annotations): skip that
  attachment and note it in the sheet's result ("Telemetry was empty — not attached") rather
  than attach a zero-byte file or block the send.
- **All selected exports empty:** disable Compose / show "Nothing to attach yet."
- **Temp write failure:** surface the error string; don't send a partial set silently.
- Temp files: written under a per-invocation subdir of `FileManager.default.temporaryDirectory`;
  left for the OS to reap (the compose window needs them to persist past the call).

## Testing

- **Pure, unit-tested:** `HelpdeskRecipient.resolve(defaults:)` — managed pref present →
  returns it; absent → returns `ti@davidson.edu`. And a recipient-validity check.
- **Manual verification** (system UI, can't unit-test): with a mail client configured,
  the sheet → Compose opens a pre-addressed message to `ti@davidson.edu` with the checked
  exports attached; unchecking removes them; empty exports are skipped with a note; with no
  mail client, the fallback path fires.
- **Test target note:** the SwiftPM kit has the test targets; the app target has none today.
  The plan will place `HelpdeskRecipient` (and the pure selection→filename mapping) so it's
  unit-testable — either a tiny new app-adjacent test target or, if cleaner, a
  dependency-free helper the kit tests can cover. Decide during planning.

## Out of scope / future

- Automated ticket filing via a helpdesk API (server-side; not the client's job).
- `.pcap` export (rides with a future real-capture feature, if ever).
