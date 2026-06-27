import Foundation
import WdutilBridge

/// Runs `wdutil info` with an administrator prompt presented **by this app**.
///
/// Spawning `/usr/bin/osascript` makes macOS attribute the auth dialog to "osascript".
/// Running the same AppleScript *in-process* via `NSAppleScript` attributes the request
/// to the host application, so the dialog reads "Oncillascope wants to make changes." instead.
///
/// Executed on a background queue so the (system-owned) password dialog never blocks the
/// main thread. This is the v1 approach; the cleaner production path is an SMAppService
/// privileged helper (single up-front grant, no AppleScript) — see SIGNING.md.
@Sendable
func runWdutilInfoWithAdminPrompt() async throws -> String {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
        DispatchQueue.global(qos: .userInitiated).async {
            // `with prompt` customizes the authentication dialog text (otherwise macOS
            // shows the generic "Oncillascope wants to make changes.").
            let prompt = "Oncillascope needs administrator access to read advanced Wi-Fi PHY-layer "
                + "metrics (MCS index, spatial streams, guard interval, and CCA) for the current connection."
            let source = "do shell script \"/usr/bin/wdutil info\" "
                + "with administrator privileges with prompt \"\(prompt)\""
            guard let script = NSAppleScript(source: source) else {
                cont.resume(throwing: WdutilRunner.WdutilError.executableMissing)
                return
            }
            var errorInfo: NSDictionary?
            let descriptor = script.executeAndReturnError(&errorInfo)
            if let errorInfo {
                // -128 == user cancelled the auth dialog.
                let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
                cont.resume(throwing: code == -128
                            ? WdutilRunner.WdutilError.userCancelled
                            : WdutilRunner.WdutilError.notAuthorized)
                return
            }
            cont.resume(returning: descriptor.stringValue ?? "")
        }
    }
}
