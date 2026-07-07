import Foundation

/// Semantic version used by the release pipeline and the Sparkle appcast.
///
/// A git tag `vMAJOR.MINOR.PATCH` maps to a display string (`CFBundleShortVersionString`)
/// and a monotonic integer (`CFBundleVersion`) via `major*10000 + minor*100 + patch`.
/// Sparkle orders updates by `CFBundleVersion`, so `Comparable` mirrors that exactly.
public struct AppcastVersion: Equatable, Comparable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses `"v1.2.3"` or `"1.2.3"`. Returns `nil` on anything else.
    public init?(tag: String) {
        var s = tag
        if s.hasPrefix("v") { s.removeFirst() }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        guard let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2]),
              a >= 0, b >= 0, c >= 0 else { return nil }
        self.init(major: a, minor: b, patch: c)
    }

    public var shortVersionString: String { "\(major).\(minor).\(patch)" }

    public var bundleVersion: Int { major * 10000 + minor * 100 + patch }

    public static func < (lhs: AppcastVersion, rhs: AppcastVersion) -> Bool {
        lhs.bundleVersion < rhs.bundleVersion
    }
}
