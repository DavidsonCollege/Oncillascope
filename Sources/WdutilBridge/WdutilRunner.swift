import Foundation

/// Runs `wdutil info` and returns parsed PHY metrics.
///
/// `wdutil` requires root for every option (spec §2), so this must be invoked through
/// an authorized path. v1 supports two strategies:
///
///  - `.directSudo`: spawn `/usr/bin/sudo -n /usr/bin/wdutil info`. Works only if the
///    caller already holds a non-interactive sudo grant; otherwise it fails fast and the
///    UI falls back to a "needs admin auth" state. Useful for CLI/dev runs.
///  - `.privilegedHelper`: hand the command to an installed `SMAppService` helper. The
///    helper itself lives in the app bundle; this bridge just defines the contract.
///
/// The runner never blocks the main thread — call it from a background task.
public struct WdutilRunner: Sendable {

    public enum Strategy: Sendable {
        case directSudo
        /// Show the native admin password dialog via AppleScript, once per grant window.
        case osascriptAdmin
        case helper(invoke: @Sendable () async throws -> String)
    }

    public enum WdutilError: Error, Sendable, Equatable {
        case notAuthorized
        case userCancelled
        case executableMissing
        case nonZeroExit(Int32)
        case emptyOutput
    }

    public var strategy: Strategy

    public init(strategy: Strategy = .directSudo) {
        self.strategy = strategy
    }

    /// Fetch and parse metrics. Throws `WdutilError` on auth/exec failure so the UI can
    /// distinguish "declined auth" from "parsed nothing".
    public func fetchMetrics() async throws -> WdutilMetrics {
        let text = try await rawOutput()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WdutilError.emptyOutput
        }
        return WdutilParser.parse(text)
    }

    /// Raw `wdutil info` text.
    public func rawOutput() async throws -> String {
        switch strategy {
        case .helper(let invoke):
            return try await invoke()
        case .directSudo:
            return try Self.runDirectSudo()
        case .osascriptAdmin:
            return try Self.runOsascriptAdmin()
        }
    }

    /// Run `wdutil info` via AppleScript with administrator privileges. This presents
    /// the native macOS password dialog once and caches the grant for a few minutes,
    /// so the "Authorize" button works without a Terminal step or a privileged helper.
    static func runOsascriptAdmin() throws -> String {
        let osa = "/usr/bin/osascript"
        let script = "do shell script \"/usr/bin/wdutil info\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: osa)
        process.arguments = ["-e", script]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do { try process.run() } catch { throw WdutilError.executableMissing }
        process.waitUntilExit()
        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            // osascript exits non-zero and prints "User canceled. (-128)" if dismissed.
            if err.contains("-128") || err.lowercased().contains("cancel") {
                throw WdutilError.userCancelled
            }
            throw WdutilError.notAuthorized
        }
        return out
    }

    /// Spawn `sudo -n wdutil info`. `-n` means "never prompt": if no cached credential
    /// exists it exits non-zero immediately instead of hanging on a TTY prompt.
    static func runDirectSudo() throws -> String {
        let sudo = "/usr/bin/sudo"
        let wdutil = "/usr/bin/wdutil"
        guard FileManager.default.isExecutableFile(atPath: wdutil) else {
            throw WdutilError.executableMissing
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sudo)
        process.arguments = ["-n", wdutil, "info"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw WdutilError.executableMissing
        }
        process.waitUntilExit()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            // sudo -n exits 1 when it would need a password → treat as not authorized.
            if text.isEmpty { throw WdutilError.notAuthorized }
            throw WdutilError.nonZeroExit(process.terminationStatus)
        }
        return text
    }
}
