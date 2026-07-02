import Foundation

// MARK: - Airtime helper

/// Approximate on-air time of a frame: bits / Mbps == microseconds (Mbps = bits/µs).
public func frameAirtimeMicroseconds(bytes: Int, rateMbps: Double) -> Double {
    guard rateMbps > 0 else { return 0 }
    return Double(bytes * 8) / rateMbps
}

// MARK: - BSS accumulator (hidden SSID resolution)

public struct PassiveBSS: Equatable, Sendable {
    public var bssid: String
    public var ssid: String?
    public var channel: Int?
    public var signalDBm: Int?
    public var hiddenResolved: Bool
}

public final class PassiveBSSAccumulator {
    public private(set) var bsses: [String: PassiveBSS] = [:]
    public init() {}

    public func ingest(_ f: CapturedFrame) {
        guard f.header.type == .management, let bssid = f.header.addr3 else { return }
        let incomingName = f.ies?.ssid
        var bss = bsses[bssid] ?? PassiveBSS(bssid: bssid, ssid: nil, channel: nil,
                                             signalDBm: nil, hiddenResolved: false)
        if let ch = f.channel { bss.channel = ch }
        if let s = f.radiotap.signalDBm { bss.signalDBm = s }

        let alreadyKnown = bsses[bssid] != nil
        let wasHidden = (bss.ssid ?? "").isEmpty
        if let name = incomingName, !name.isEmpty {
            if alreadyKnown && wasHidden { bss.hiddenResolved = true }
            bss.ssid = name
        } else if bss.ssid == nil {
            bss.ssid = ""   // seen, but hidden so far
        }

        bsses[bssid] = bss
    }
}

// MARK: - Airtime accumulator

public final class AirtimeAccumulator {
    private var busy: [Int: Double] = [:]   // channel -> microseconds
    public init() {}

    public func ingest(_ f: CapturedFrame) {
        guard let ch = f.channel, let rate = f.radiotap.rateMbps else { return }
        busy[ch, default: 0] += frameAirtimeMicroseconds(bytes: f.rawLength, rateMbps: rate)
    }

    public func busyMicroseconds(channel: Int) -> Double { busy[channel] ?? 0 }

    public func utilization(channel: Int, elapsedSeconds: Double) -> Double {
        guard elapsedSeconds > 0 else { return 0 }
        return min(1.0, (busy[channel] ?? 0) / (elapsedSeconds * 1_000_000))
    }
}

// MARK: - Station tracker

public struct Station: Equatable, Sendable {
    public var mac: String
    public var signalDBm: Int?
    public var probing: Bool
}

public final class StationTracker {
    public private(set) var stations: [String: Station] = [:]
    public init() {}

    public func ingest(_ f: CapturedFrame) {
        // Clients reveal themselves as the source (addr2) of probe requests and data frames.
        let isProbe = f.header.type == .management && f.header.subtype == Dot11Subtype.probeReq
        let isData = f.header.type == .data
        guard isProbe || isData, let mac = f.header.addr2, isUnicast(mac) else { return }
        var st = stations[mac] ?? Station(mac: mac, signalDBm: nil, probing: false)
        if let s = f.radiotap.signalDBm { st.signalDBm = s }
        if isProbe { st.probing = true }
        stations[mac] = st
    }

    private func isUnicast(_ mac: String) -> Bool {
        guard let first = mac.split(separator: ":").first,
              let byte = UInt8(first, radix: 16) else { return false }
        return (byte & 0x01) == 0   // group/broadcast bit clear
    }
}

// MARK: - Retry accumulator

public struct RetryStat: Equatable, Sendable {
    public var total: Int
    public var retries: Int
    public var rate: Double
}

public final class RetryAccumulator {
    private var totals: [String: Int] = [:]
    private var retries: [String: Int] = [:]
    public init() {}

    public func ingest(_ f: CapturedFrame) {
        guard let bssid = f.header.addr3 else { return }
        totals[bssid, default: 0] += 1
        if f.header.isRetry { retries[bssid, default: 0] += 1 }
    }

    public func stat(bssid: String) -> RetryStat? {
        guard let total = totals[bssid], total > 0 else { return nil }
        let r = retries[bssid] ?? 0
        return RetryStat(total: total, retries: r, rate: Double(r) / Double(total))
    }
}
