#if canImport(CoreLocation)
import CoreLocation
import Combine

/// Observes and requests Location Services authorization.
///
/// macOS redacts SSID/BSSID from CoreWLAN scan results unless the app holds Location
/// authorization (spec §2). This wrapper exposes the live status so the UI can drive
/// the degraded-mode messaging (spec §4.7) and offer a one-click grant path.
@MainActor
public final class LocationAuthorization: NSObject, ObservableObject, CLLocationManagerDelegate {

    public enum Access: Sendable, Equatable {
        case notDetermined
        case denied        // denied or restricted
        case granted       // authorizedAlways / authorized

        public var allowsUnredactedScan: Bool { self == .granted }
    }

    @Published public private(set) var access: Access = .notDetermined

    private let manager = CLLocationManager()

    public override init() {
        super.init()
        manager.delegate = self
        access = Self.map(manager.authorizationStatus)
    }

    /// Trigger the system authorization prompt (no-op if already determined).
    public func request() {
        manager.requestAlwaysAuthorization()
    }

    /// Open System Settings to the app's Location pane (used when already denied).
    public func openSettings() {
        #if canImport(AppKit)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            import_openURL(url)
        }
        #endif
    }

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.access = Self.map(status) }
    }

    static func map(_ status: CLAuthorizationStatus) -> Access {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted, .denied: return .denied
        case .authorizedAlways: return .granted
        @unknown default: return .denied
        }
    }
}

#if canImport(AppKit)
import AppKit
@MainActor private func import_openURL(_ url: URL) {
    NSWorkspace.shared.open(url)
}
#endif
#endif
