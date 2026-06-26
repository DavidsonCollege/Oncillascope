import Foundation

/// BSS Load (IE 11): live occupancy hints broadcast by the AP.
public struct BSSLoad: Codable, Sendable, Hashable {
    /// Number of associated stations.
    public var stationCount: Int
    /// Channel utilization as a percentage (0...100). Derived from the 0...255 raw byte.
    public var channelUtilization: Double
    /// Available admission capacity in units of 32 µs/s.
    public var availableAdmissionCapacity: Int

    public init(stationCount: Int, channelUtilization: Double, availableAdmissionCapacity: Int) {
        self.stationCount = stationCount
        self.channelUtilization = channelUtilization
        self.availableAdmissionCapacity = availableAdmissionCapacity
    }
}

/// Decoded high-throughput capability summary across 802.11n/ac/ax/be.
///
/// Each generation contributes the fields it defines; absent generations leave nils.
public struct CapabilitySet: Codable, Sendable, Hashable {
    public var generation: PHYGeneration

    // Spatial streams (NSS) advertised in the capability/operation IEs.
    public var spatialStreams: Int?
    // Highest MCS index supported (best-effort from the MCS map).
    public var maxMCS: Int?
    // Widest channel width the BSS advertises support for.
    public var maxWidth: ChannelWidth?
    // Short guard interval support (HT/VHT SGI bit; HE/EHT use GI in the rate calc).
    public var shortGuardInterval: Bool?

    // Feature flags surfaced in the inspector.
    public var supportsMUMIMO: Bool?
    public var supportsOFDMA: Bool?
    public var supports160MHz: Bool?
    public var dfsRequired: Bool?

    public init(
        generation: PHYGeneration,
        spatialStreams: Int? = nil,
        maxMCS: Int? = nil,
        maxWidth: ChannelWidth? = nil,
        shortGuardInterval: Bool? = nil,
        supportsMUMIMO: Bool? = nil,
        supportsOFDMA: Bool? = nil,
        supports160MHz: Bool? = nil,
        dfsRequired: Bool? = nil
    ) {
        self.generation = generation
        self.spatialStreams = spatialStreams
        self.maxMCS = maxMCS
        self.maxWidth = maxWidth
        self.shortGuardInterval = shortGuardInterval
        self.supportsMUMIMO = supportsMUMIMO
        self.supportsOFDMA = supportsOFDMA
        self.supports160MHz = supports160MHz
        self.dfsRequired = dfsRequired
    }
}

/// One decoded 802.11 Information Element for the inspector tree.
public struct InformationElement: Codable, Sendable, Hashable, Identifiable {
    /// Element ID (the first byte). 255 means an Extension element.
    public var elementID: Int
    /// Extension ID (the byte after 255), when `elementID == 255`.
    public var extensionID: Int?
    /// Human-readable name, e.g. "HT Capabilities".
    public var name: String
    /// Raw payload bytes (excluding the id/length header).
    public var bytes: [UInt8]
    /// Decoded human-readable summary lines for this element.
    public var summary: [String]

    /// Stable identity for SwiftUI lists: element id + ext id + payload length.
    public var id: String {
        let ext = extensionID.map { ".\($0)" } ?? ""
        return "\(elementID)\(ext)#\(bytes.count)"
    }

    public init(elementID: Int, extensionID: Int? = nil, name: String, bytes: [UInt8], summary: [String] = []) {
        self.elementID = elementID
        self.extensionID = extensionID
        self.name = name
        self.bytes = bytes
        self.summary = summary
    }

    /// Hex dump of the payload, grouped in bytes.
    public var hexDump: String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
