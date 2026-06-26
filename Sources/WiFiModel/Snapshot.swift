import Foundation

/// Current-connection info: CoreWLAN live stats fused with parsed `wdutil` PHY metrics.
public struct ConnectionInfo: Codable, Sendable, Hashable {
    public var ssid: String?
    public var bssid: String?
    public var vendor: String?

    public var rssi: Int        // dBm
    public var noise: Int       // dBm
    /// Signal-to-noise ratio in dB. Derived: rssi - noise.
    public var snr: Int { rssi - noise }

    public var txRate: Double           // Mbps (CoreWLAN transmitRate)
    public var maxTheoreticalRate: Double?  // Mbps, derived from capabilities

    public var phyMode: PHYGeneration
    public var channel: ChannelInfo
    public var security: SecurityMode

    // From wdutil (nil when admin auth declined).
    public var mcsIndex: Int?
    public var nss: Int?
    public var guardInterval: Int?  // nanoseconds (e.g. 800 / 400)
    public var cca: Int?            // % channel busy

    public var transmitPower: Int?
    public var countryCode: String?

    /// Link efficiency 0...1: actual Tx rate vs the BSS's theoretical max.
    public var efficiency: Double? {
        guard let maxRate = maxTheoreticalRate, maxRate > 0 else { return nil }
        return min(1.0, txRate / maxRate)
    }

    /// `transmitPower` is milliwatts (per CoreWLAN). Convert to dBm for a readable
    /// figure: dBm = 10·log10(mW). Returns nil for non-positive/absent values.
    public var transmitPowerDBm: Int? {
        guard let mw = transmitPower, mw > 0 else { return nil }
        return Int((10 * log10(Double(mw))).rounded())
    }

    public init(
        ssid: String? = nil,
        bssid: String? = nil,
        vendor: String? = nil,
        rssi: Int = 0,
        noise: Int = 0,
        txRate: Double = 0,
        maxTheoreticalRate: Double? = nil,
        phyMode: PHYGeneration = .unknown,
        channel: ChannelInfo = ChannelInfo(number: 0),
        security: SecurityMode = .unknown,
        mcsIndex: Int? = nil,
        nss: Int? = nil,
        guardInterval: Int? = nil,
        cca: Int? = nil,
        transmitPower: Int? = nil,
        countryCode: String? = nil
    ) {
        self.ssid = ssid
        self.bssid = bssid
        self.vendor = vendor
        self.rssi = rssi
        self.noise = noise
        self.txRate = txRate
        self.maxTheoreticalRate = maxTheoreticalRate
        self.phyMode = phyMode
        self.channel = channel
        self.security = security
        self.mcsIndex = mcsIndex
        self.nss = nss
        self.guardInterval = guardInterval
        self.cca = cca
        self.transmitPower = transmitPower
        self.countryCode = countryCode
    }
}

/// One observed BSS (one row in the nearby-networks table).
public struct BSSObservation: Codable, Sendable, Hashable, Identifiable {
    public var ssid: String?
    public var bssid: String?
    public var vendor: String?

    public var rssi: Int
    public var noise: Int
    public var snr: Int { rssi - noise }

    public var channel: ChannelInfo
    public var security: SecurityMode
    public var phyGeneration: PHYGeneration
    public var beaconInterval: Int
    public var isIBSS: Bool
    public var countryCode: String?

    public var bssLoad: BSSLoad?
    public var capabilities: CapabilitySet?
    public var maxTheoreticalRate: Double?

    /// Decoded IEs for the inspector.
    public var rawIEs: [InformationElement]

    /// Stable identity: prefer the BSSID; fall back to SSID + channel when redacted.
    public var id: String {
        if let bssid, !bssid.isEmpty, bssid != "<redacted>" { return bssid }
        return "\(ssid ?? "?")@\(channel.number)"
    }

    public init(
        ssid: String? = nil,
        bssid: String? = nil,
        vendor: String? = nil,
        rssi: Int = 0,
        noise: Int = 0,
        channel: ChannelInfo = ChannelInfo(number: 0),
        security: SecurityMode = .unknown,
        phyGeneration: PHYGeneration = .unknown,
        beaconInterval: Int = 0,
        isIBSS: Bool = false,
        countryCode: String? = nil,
        bssLoad: BSSLoad? = nil,
        capabilities: CapabilitySet? = nil,
        maxTheoreticalRate: Double? = nil,
        rawIEs: [InformationElement] = []
    ) {
        self.ssid = ssid
        self.bssid = bssid
        self.vendor = vendor
        self.rssi = rssi
        self.noise = noise
        self.channel = channel
        self.security = security
        self.phyGeneration = phyGeneration
        self.beaconInterval = beaconInterval
        self.isIBSS = isIBSS
        self.countryCode = countryCode
        self.bssLoad = bssLoad
        self.capabilities = capabilities
        self.maxTheoreticalRate = maxTheoreticalRate
        self.rawIEs = rawIEs
    }
}

/// A point-in-time capture of the whole RF environment.
public struct WiFiSnapshot: Codable, Sendable {
    public var timestamp: Date
    public var current: ConnectionInfo?
    public var networks: [BSSObservation]

    public init(timestamp: Date, current: ConnectionInfo? = nil, networks: [BSSObservation] = []) {
        self.timestamp = timestamp
        self.current = current
        self.networks = networks
    }
}
