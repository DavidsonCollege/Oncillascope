import SwiftUI
import WiFiCore

/// Surfaces *why* data is missing and offers a one-click remedy (spec §4.7).
/// Never let the user see `<redacted>` or blanks without an explanation.
struct DegradedModeBanner: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.location.access != .granted {
                banner(
                    icon: "location.slash.fill",
                    tint: .orange,
                    title: locationTitle,
                    message: "macOS redacts network SSIDs and BSSIDs unless Oncillascope has Location Services access. This is required by macOS for Wi-Fi identity — Oncillascope does not track your location.",
                    actionTitle: model.location.access == .notDetermined ? "Grant Access" : "Open Settings",
                    action: {
                        // Register the app + show the native prompt on a properly-signed
                        // build, then always open the Location Services pane so the user
                        // can enable it (the prompt alone is a no-op on unsigned builds).
                        if model.location.access == .notDetermined { model.location.request() }
                        model.location.openSettings()
                    }
                )
            }

            if case .needsAuth = model.wdutil {
                banner(
                    icon: "lock.fill",
                    tint: .blue,
                    title: "PHY metrics need admin authorization",
                    message: "MCS index, spatial streams (NSS), guard interval, and CCA require a one-time administrator authorization. Authorize once to enable them.",
                    actionTitle: "Authorize",
                    action: { Task { await model.refreshWdutil() } }
                )
            }

            if case .unavailable(let reason) = model.wdutil {
                banner(icon: "exclamationmark.triangle.fill", tint: .secondary,
                       title: "PHY metrics unavailable", message: reason,
                       actionTitle: "Retry", action: { Task { await model.refreshWdutil() } })
            }

            if !model.interfaceAvailable {
                banner(icon: "wifi.slash", tint: .red, title: "Wi-Fi is off",
                       message: "No powered Wi-Fi interface was found. Turn Wi-Fi on to collect data.",
                       actionTitle: nil, action: {})
            }

            if let err = model.scanError {
                banner(icon: "exclamationmark.triangle", tint: .red, title: "Scan issue",
                       message: err, actionTitle: "Retry", action: { model.scanNow() })
            }
        }
    }

    private var locationTitle: String {
        model.location.access == .notDetermined
            ? "Location access required for network names"
            : "Location access denied — SSIDs/BSSIDs are redacted"
    }

    @ViewBuilder
    private func banner(icon: String, tint: Color, title: String, message: String,
                        actionTitle: String?, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout).fontWeight(.semibold)
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let actionTitle {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(10)
        .background(tint.opacity(0.10))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(tint.opacity(0.25)), alignment: .bottom)
    }
}
