import Foundation

/// Implements the XPC contract, running as **root** (launchd `UserName = root`).
///
/// The only privileged operation is shelling out to `/usr/bin/wdutil info`, which requires
/// root for every option. We deliberately expose nothing more general than that — no
/// arbitrary command execution — so a compromised client can't turn the daemon into a
/// root shell.
final class HelperService: NSObject, OncillascopeHelperProtocol {

    func getVersion(withReply reply: @escaping (String) -> Void) {
        reply(HelperConstants.version)
    }

    func fetchWdutilInfo(withReply reply: @escaping (String?, String?) -> Void) {
        let wdutil = "/usr/bin/wdutil"
        guard FileManager.default.isExecutableFile(atPath: wdutil) else {
            reply(nil, "The system tool /usr/bin/wdutil was not found.")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: wdutil)
        process.arguments = ["info"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            reply(nil, "Failed to launch wdutil: \(error.localizedDescription)")
            return
        }
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: outData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8) ?? ""
            reply(text.isEmpty ? nil : text,
                  "wdutil exited with status \(process.terminationStatus): \(errText)")
            return
        }
        reply(text, nil)
    }
}
