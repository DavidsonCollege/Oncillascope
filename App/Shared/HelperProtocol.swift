import Foundation

/// XPC contract between Oncillascope.app and its privileged helper daemon.
///
/// This file is compiled into **both** the app target and the helper target (a single
/// physical file referenced by each), so the `@objc` protocol gets the same Objective-C
/// runtime name on both sides — which is what `NSXPCInterface` matches on. Keep it free of
/// any app- or helper-specific imports so it links cleanly into a plain command-line tool.
@objc public protocol OncillascopeHelperProtocol {
    /// Run `wdutil info` as root and return its raw stdout.
    /// - reply: `(output, error)` — exactly one is non-nil. `output` is the raw text;
    ///   `error` is a human-readable failure reason.
    func fetchWdutilInfo(withReply reply: @escaping (_ output: String?, _ error: String?) -> Void)

    /// The helper's own version string, so the app can detect a stale installed copy and
    /// re-register a newer one.
    func getVersion(withReply reply: @escaping (_ version: String) -> Void)
}

/// Shared identifiers + code-signing requirements. Single source of truth for both targets.
public enum HelperConstants {
    /// launchd `Label` == Mach service name == helper bundle id == plist filename stem.
    public static let machServiceName = "edu.davidson.oncillascope.helper"
    /// File name of the launchd plist embedded at `Contents/Library/LaunchDaemons/`.
    public static let plistName = "edu.davidson.oncillascope.helper.plist"
    /// Bumped whenever the helper's behavior changes; compared against the installed copy.
    public static let version = "1.0.0"

    public static let teamID = "4Z539UE4TT"
    public static let appBundleID = "edu.davidson.oncillascope"

    /// Requirement the **helper** enforces on connecting clients: only the genuine,
    /// same-team Oncillascope app may talk to the root daemon.
    public static var clientRequirement: String {
        "identifier \"\(appBundleID)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
    }

    /// Requirement the **app** enforces on the daemon it connects to: only our genuine,
    /// same-team helper may answer.
    public static var helperRequirement: String {
        "identifier \"\(machServiceName)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
    }
}
