import Foundation

/// Entry point for the privileged helper daemon.
///
/// launchd starts this process on demand when a message arrives on the registered Mach
/// service (see `edu.davidson.oncillascope.helper.plist`). It vends a single XPC object
/// implementing `OncillascopeHelperProtocol`, validating that every connecting client is
/// the genuine, same-team Oncillascope app before accepting it.
final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Reject anything that isn't our signed app. `setCodeSigningRequirement` is the
        // modern (macOS 13+) replacement for manual audit-token validation.
        newConnection.setCodeSigningRequirement(HelperConstants.clientRequirement)

        newConnection.exportedInterface = NSXPCInterface(with: OncillascopeHelperProtocol.self)
        newConnection.exportedObject = HelperService()
        newConnection.resume()
        return true
    }
}

let delegate = HelperListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()
// Block forever; launchd owns this process's lifecycle.
RunLoop.main.run()
