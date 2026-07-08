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

        // Drain both pipes *before* waiting on exit: a child that writes more than the
        // ~64 KB pipe buffer while nobody reads would block forever against
        // waitUntilExit. stderr drains on a background queue, stdout on this thread.
        let errBuffer = PipeBuffer()
        let errHandle = stderr.fileHandleForReading
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errBuffer.data = errHandle.readDataToEndOfFile()
            group.leave()
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        let text = String(data: outData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let errText = String(data: errBuffer.data, encoding: .utf8) ?? ""
            reply(text.isEmpty ? nil : text,
                  "wdutil exited with status \(process.terminationStatus): \(errText)")
            return
        }
        reply(text, nil)
    }
}

/// Reference-type byte sink so the concurrent stderr reader can fill it while the
/// calling thread drains stdout. Synchronized by the DispatchGroup barrier above.
private final class PipeBuffer: @unchecked Sendable {
    var data = Data()
}
