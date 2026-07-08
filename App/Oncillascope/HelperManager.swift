import Foundation
import ServiceManagement
import WdutilBridge

/// Manages the privileged helper daemon: registration via `SMAppService`, status, and the
/// XPC client that fetches `wdutil info` without an admin password prompt.
///
/// Registering a daemon installs it but leaves it **disabled** until the user approves it in
/// System Settings ▸ Login Items & Extensions (macOS won't show a password prompt for this).
/// Once enabled, the app can call the daemon over XPC for continuous PHY metrics. The
/// `OncillascopeHelperProtocol` / `HelperConstants` types are compiled directly into the app
/// target from `App/Shared/HelperProtocol.swift`, so no import is needed.
@MainActor
final class HelperManager {

    /// User-facing helper lifecycle, derived from `SMAppService.Status`.
    enum Status: Equatable {
        case notRegistered          // never installed (or unregistered)
        case requiresApproval       // installed; waiting on the user in System Settings
        case enabled                // installed + approved; XPC is usable
        case notFound               // bundle is missing the daemon (build/signing problem)
        case failed(String)         // registration threw

        /// True only when the daemon is approved and we can talk to it.
        var isUsable: Bool { self == .enabled }
    }

    private var service: SMAppService { SMAppService.daemon(plistName: HelperConstants.plistName) }

    /// Map the framework status onto ours. Cheap; safe to call often.
    func currentStatus() -> Status {
        switch service.status {
        case .notRegistered:    return .notRegistered
        case .enabled:          return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound:         return .notFound
        @unknown default:       return .failed("Unknown SMAppService status.")
        }
    }

    /// Register (install) the daemon. Returns the resulting status. If approval is needed,
    /// also opens the Login Items pane so the user can flip the switch.
    @discardableResult
    func register() -> Status {
        do {
            try service.register()
        } catch let error as NSError {
            // Already-registered is benign — fall through to a status read. Anything else is
            // a real failure (e.g. unsigned/ad-hoc build can't register a daemon).
            let alreadyRegistered = error.domain == "SMAppServiceErrorDomain" && error.code == 1
            if !alreadyRegistered {
                return .failed(error.localizedDescription)
            }
        }
        let status = currentStatus()
        if status == .requiresApproval { openLoginItemsSettings() }
        return status
    }

    /// Remove the daemon entirely.
    func unregister() async {
        try? await service.unregister()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - XPC client

    /// Fetch raw `wdutil info` over XPC. Nonisolated so it can run off the main actor; the
    /// closure form is what `WdutilRunner.Strategy.helper(invoke:)` expects.
    nonisolated func fetchWdutilInfo() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let connection = NSXPCConnection(machServiceName: HelperConstants.machServiceName,
                                             options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: OncillascopeHelperProtocol.self)
            // Only accept replies from our genuine, same-team daemon.
            connection.setCodeSigningRequirement(HelperConstants.helperRequirement)

            // Guard against double-resume: an XPC message resolves via either the reply or
            // the error handler, never both — but invalidation races make a guard prudent.
            let resumer = ContinuationResumer(continuation, connection: connection)
            connection.resume()

            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                resumer.fail(WdutilRunner.WdutilError.notAuthorized)
            } as? OncillascopeHelperProtocol

            guard let proxy else {
                resumer.fail(WdutilRunner.WdutilError.notAuthorized)
                return
            }
            proxy.fetchWdutilInfo { output, error in
                if let output, !output.isEmpty {
                    resumer.succeed(output)
                } else if let error {
                    // Surface the helper's specific failure reason (e.g. "wdutil exited
                    // with status 2: …") instead of flattening it to "not authorized".
                    resumer.fail(WdutilRunner.WdutilError.failed(error))
                } else {
                    resumer.fail(WdutilRunner.WdutilError.notAuthorized)
                }
            }
        }
    }
}

/// Resolves a checked continuation exactly once and tears down the XPC connection.
private final class ContinuationResumer: @unchecked Sendable {
    private let continuation: CheckedContinuation<String, Error>
    private let connection: NSXPCConnection
    private let lock = NSLock()
    private var done = false

    init(_ continuation: CheckedContinuation<String, Error>, connection: NSXPCConnection) {
        self.continuation = continuation
        self.connection = connection
    }

    func succeed(_ value: String) { finish { $0.resume(returning: value) } }
    func fail(_ error: Error) { finish { $0.resume(throwing: error) } }

    private func finish(_ body: (CheckedContinuation<String, Error>) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        connection.invalidate()
        body(continuation)
    }
}
