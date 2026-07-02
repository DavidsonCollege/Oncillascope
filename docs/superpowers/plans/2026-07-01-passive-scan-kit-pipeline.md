# Passive Scan — Kit Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure-Swift, hardware-free logic core for passive Wi-Fi capture: parse raw monitor-mode frames and derive hidden SSIDs, measured channel utilization, nearby stations, and retry rates.

**Architecture:** A new `Sources/PassiveCapture` SwiftPM module. Raw captured frames (radiotap header + 802.11 frame) are decoded by `RadiotapParser` and `Dot11FrameParser`, combined by `FrameIngestor` into a normalized `CapturedFrame` (reusing the existing `IEParser` for management-frame IEs), then fed to four independent accumulators. No CoreWLAN, no libpcap, no XPC — those live in Plans 2 and 3. Everything here is unit-tested against hand-crafted byte fixtures.

**Tech Stack:** Swift 6, SwiftPM, XCTest. Depends only on the existing `WiFiModel` and `IEParser` targets.

## Global Constraints

- Swift tools version 6.0; platform floor macOS 14. (copied from `Package.swift`)
- No third-party runtime dependencies. No network calls.
- Every parser is fully bounds-checked and returns `nil`/partial on malformed or truncated input — never traps. Captured bytes are attacker-adjacent (arbitrary over-the-air input).
- No `Date()` / wall-clock inside pure logic; timestamps are passed in as parameters so tests are deterministic.
- Module name `PassiveCapture`; follow the existing kit style (public value types, `Sendable`, doc comments).

---

## File Structure

- Create: `Sources/PassiveCapture/ChannelMapping.swift` — frequency→channel helper.
- Create: `Sources/PassiveCapture/RadiotapParser.swift` — radiotap header decode → `RadiotapInfo`.
- Create: `Sources/PassiveCapture/Dot11FrameParser.swift` — 802.11 MAC header decode → `Dot11Header`.
- Create: `Sources/PassiveCapture/FrameIngestor.swift` — `CapturedFrame` + orchestration (reuses `IEParser`).
- Create: `Sources/PassiveCapture/Accumulators.swift` — `PassiveBSSAccumulator`, `AirtimeAccumulator`, `StationTracker`, `RetryAccumulator`.
- Modify: `Package.swift` — add the `PassiveCapture` target + `PassiveCaptureTests` test target.
- Create: `Tests/PassiveCaptureTests/Fixtures.swift` — shared byte fixtures.
- Create: `Tests/PassiveCaptureTests/RadiotapParserTests.swift`
- Create: `Tests/PassiveCaptureTests/Dot11FrameParserTests.swift`
- Create: `Tests/PassiveCaptureTests/FrameIngestorTests.swift`
- Create: `Tests/PassiveCaptureTests/AccumulatorTests.swift`

---

### Task 1: Module scaffold + frequency→channel mapping

**Files:**
- Modify: `Package.swift`
- Create: `Sources/PassiveCapture/ChannelMapping.swift`
- Test: `Tests/PassiveCaptureTests/ChannelMappingTests.swift`

**Interfaces:**
- Consumes: `WiFiModel` (for `Band`).
- Produces: `func channelNumber(forFrequencyMHz freq: Int) -> Int?` and `func band(forFrequencyMHz freq: Int) -> Band?`.

- [ ] **Step 1: Add the module + test target to `Package.swift`**

Add to `products`:
```swift
        .library(name: "PassiveCapture", targets: ["PassiveCapture"]),
```
Add to `targets` (after the `Telemetry` target):
```swift
        // Pure-Swift decode + derivation for monitor-mode capture (no libpcap/XPC here).
        .target(name: "PassiveCapture", dependencies: ["WiFiModel", "IEParser"]),
```
Add to the test targets:
```swift
        .testTarget(name: "PassiveCaptureTests", dependencies: ["PassiveCapture", "WiFiModel", "IEParser"]),
```

- [ ] **Step 2: Write the failing test**

`Tests/PassiveCaptureTests/ChannelMappingTests.swift`:
```swift
import XCTest
import WiFiModel
@testable import PassiveCapture

final class ChannelMappingTests: XCTestCase {
    func testTwoPointFour() {
        XCTAssertEqual(channelNumber(forFrequencyMHz: 2412), 1)
        XCTAssertEqual(channelNumber(forFrequencyMHz: 2437), 6)
        XCTAssertEqual(channelNumber(forFrequencyMHz: 2484), 14)
        XCTAssertEqual(band(forFrequencyMHz: 2412), .ghz2_4)
    }
    func testFiveAndSix() {
        XCTAssertEqual(channelNumber(forFrequencyMHz: 5180), 36)
        XCTAssertEqual(band(forFrequencyMHz: 5180), .ghz5)
        XCTAssertEqual(channelNumber(forFrequencyMHz: 5955), 1)
        XCTAssertEqual(band(forFrequencyMHz: 5955), .ghz6)
    }
    func testOutOfRange() {
        XCTAssertNil(channelNumber(forFrequencyMHz: 100))
        XCTAssertNil(band(forFrequencyMHz: 100))
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter ChannelMappingTests`
Expected: FAIL — `PassiveCapture` module / `channelNumber` not found.

- [ ] **Step 4: Write minimal implementation**

`Sources/PassiveCapture/ChannelMapping.swift`:
```swift
import WiFiModel

/// Map a radiotap primary-channel frequency (MHz) to an 802.11 channel number.
/// Returns nil for frequencies outside the known 2.4/5/6 GHz plans.
public func channelNumber(forFrequencyMHz freq: Int) -> Int? {
    switch freq {
    case 2484:              return 14
    case 2412...2472:       return (freq - 2407) / 5
    case 5160...5885:       return (freq - 5000) / 5
    case 5955...7115:       return (freq - 5950) / 5
    default:                return nil
    }
}

/// Band for a primary-channel frequency (MHz), or nil if unknown.
public func band(forFrequencyMHz freq: Int) -> Band? {
    switch freq {
    case 2412...2484:       return .ghz2_4
    case 5160...5885:       return .ghz5
    case 5955...7115:       return .ghz6
    default:                return nil
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter ChannelMappingTests`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/PassiveCapture/ChannelMapping.swift Tests/PassiveCaptureTests/ChannelMappingTests.swift
git commit -m "feat(passive): scaffold PassiveCapture module + frequency->channel mapping"
```

---

### Task 2: Shared test fixtures

**Files:**
- Create: `Tests/PassiveCaptureTests/Fixtures.swift`

**Interfaces:**
- Produces: `enum Fixtures` with `static let radiotapHeader: [UInt8]`, `beaconVisible: [UInt8]`, `beaconHidden: [UInt8]`, and `frame(_ dot11: [UInt8]) -> [UInt8]` (prepends the radiotap header).

These byte arrays are the ground truth every later task asserts against. Values are hand-computed (documented inline) so the parsers can be verified without capturing real traffic.

- [ ] **Step 1: Write the fixtures file**

`Tests/PassiveCaptureTests/Fixtures.swift`:
```swift
import Foundation

/// Hand-crafted, byte-exact fixtures. See inline comments for field derivations.
enum Fixtures {
    /// 16-byte radiotap header:
    /// version=0, pad=0, it_len=16, present=0x6E (Flags|Rate|Channel|dBmSignal|dBmNoise).
    /// Flags=0x00 (FCS ok), Rate=0x0C (12*500kbps = 6 Mbps),
    /// Channel freq=2412 (LE 6C 09), channel flags=0x00C0,
    /// signal=-50 dBm (0xCE), noise=-95 dBm (0xA1).
    static let radiotapHeader: [UInt8] = [
        0x00, 0x00,             // version, pad
        0x10, 0x00,             // it_len = 16
        0x6E, 0x00, 0x00, 0x00, // it_present
        0x00,                   // Flags
        0x0C,                   // Rate (6 Mbps)
        0x6C, 0x09,             // Channel frequency 2412
        0xC0, 0x00,             // Channel flags
        0xCE,                   // signal -50 dBm
        0xA1,                   // noise -95 dBm
    ]

    /// 802.11 beacon MAC header + fixed params + one SSID IE ("Test").
    /// FC=0x8000 (mgmt/beacon), dur=0, addr1=broadcast, addr2=addr3=00:11:22:33:44:55,
    /// seq=0, timestamp=0, interval=0x0064, caps=0x0001, SSID IE = 00 04 "Test".
    static let beaconVisible: [UInt8] = [
        0x80, 0x00,                         // frame control (beacon)
        0x00, 0x00,                         // duration
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // addr1 (DA broadcast)
        0x00, 0x11, 0x22, 0x33, 0x44, 0x55, // addr2 (SA)
        0x00, 0x11, 0x22, 0x33, 0x44, 0x55, // addr3 (BSSID)
        0x00, 0x00,                         // sequence control
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // timestamp
        0x64, 0x00,                         // beacon interval
        0x01, 0x00,                         // capabilities
        0x00, 0x04, 0x54, 0x65, 0x73, 0x74, // SSID IE: "Test"
    ]

    /// Same beacon but with a zero-length (hidden) SSID IE.
    static let beaconHidden: [UInt8] = Array(beaconVisible[0..<36]) + [0x00, 0x00]

    /// A retried beacon: FC flags byte (octet 1) has the Retry bit (0x08) set.
    static let beaconVisibleRetry: [UInt8] = {
        var f = beaconVisible; f[1] = 0x08; return f
    }()

    /// A probe request from a client 66:77:88:99:AA:BB carrying SSID "Test".
    /// FC=0x4000 (mgmt/probe-req, subtype 4). No fixed params; body is IEs.
    static let probeRequest: [UInt8] = [
        0x40, 0x00,                         // frame control (probe request)
        0x00, 0x00,                         // duration
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // addr1 (broadcast)
        0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB, // addr2 (client)
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // addr3
        0x00, 0x00,                         // sequence control
        0x00, 0x04, 0x54, 0x65, 0x73, 0x74, // SSID IE: "Test"
    ]

    /// Prepend the radiotap header to an 802.11 frame to form a full captured frame.
    static func frame(_ dot11: [UInt8]) -> [UInt8] { radiotapHeader + dot11 }
}
```

- [ ] **Step 2: Verify it compiles with the existing suite**

Run: `swift test --filter ChannelMappingTests`
Expected: PASS (fixtures compile alongside; no new tests yet).

- [ ] **Step 3: Commit**

```bash
git add Tests/PassiveCaptureTests/Fixtures.swift
git commit -m "test(passive): add byte-exact radiotap/802.11 fixtures"
```

---

### Task 3: RadiotapParser

**Files:**
- Create: `Sources/PassiveCapture/RadiotapParser.swift`
- Test: `Tests/PassiveCaptureTests/RadiotapParserTests.swift`

**Interfaces:**
- Consumes: nothing kit-side.
- Produces:
```swift
public struct RadiotapInfo: Equatable, Sendable {
    public var headerLength: Int      // it_len; where the 802.11 frame begins
    public var frequencyMHz: Int?
    public var signalDBm: Int?
    public var noiseDBm: Int?
    public var rateMbps: Double?
    public var badFCS: Bool
}
public enum RadiotapParser {
    public static func parse(_ bytes: [UInt8]) -> RadiotapInfo?
}
```

- [ ] **Step 1: Write the failing test**

`Tests/PassiveCaptureTests/RadiotapParserTests.swift`:
```swift
import XCTest
@testable import PassiveCapture

final class RadiotapParserTests: XCTestCase {
    func testParsesKnownHeader() {
        let info = RadiotapParser.parse(Fixtures.radiotapHeader)
        XCTAssertEqual(info?.headerLength, 16)
        XCTAssertEqual(info?.frequencyMHz, 2412)
        XCTAssertEqual(info?.signalDBm, -50)
        XCTAssertEqual(info?.noiseDBm, -95)
        XCTAssertEqual(info?.rateMbps, 6.0)
        XCTAssertEqual(info?.badFCS, false)
    }
    func testBadFCSFlag() {
        var bytes = Fixtures.radiotapHeader
        bytes[8] = 0x40   // Flags field: bad-FCS bit
        XCTAssertEqual(RadiotapParser.parse(bytes)?.badFCS, true)
    }
    func testTooShortReturnsNil() {
        XCTAssertNil(RadiotapParser.parse([0x00, 0x00, 0x04]))
        XCTAssertNil(RadiotapParser.parse([]))
    }
    func testTruncatedFieldsAreNilNotCrash() {
        // Claims it_len=16 but only 10 bytes present.
        let bytes: [UInt8] = [0x00,0x00, 0x10,0x00, 0x6E,0x00,0x00,0x00, 0x00,0x0C]
        let info = RadiotapParser.parse(bytes)
        XCTAssertEqual(info?.headerLength, 16)
        XCTAssertNil(info?.signalDBm)   // ran off the end; degraded, no trap
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RadiotapParserTests`
Expected: FAIL — `RadiotapParser` not found.

- [ ] **Step 3: Write minimal implementation**

`Sources/PassiveCapture/RadiotapParser.swift`:
```swift
import Foundation

public struct RadiotapInfo: Equatable, Sendable {
    public var headerLength: Int
    public var frequencyMHz: Int?
    public var signalDBm: Int?
    public var noiseDBm: Int?
    public var rateMbps: Double?
    public var badFCS: Bool

    public init(headerLength: Int, frequencyMHz: Int? = nil, signalDBm: Int? = nil,
                noiseDBm: Int? = nil, rateMbps: Double? = nil, badFCS: Bool = false) {
        self.headerLength = headerLength
        self.frequencyMHz = frequencyMHz
        self.signalDBm = signalDBm
        self.noiseDBm = noiseDBm
        self.rateMbps = rateMbps
        self.badFCS = badFCS
    }
}

/// Decode the little-endian radiotap header. Fields are laid out in bit order with
/// per-field alignment; we honor `it_len` and read only the fields we use, skipping the
/// rest. Any read past the end degrades to nil rather than trapping.
public enum RadiotapParser {

    // Radiotap "present" bit positions we care about.
    private enum Bit {
        static let flags = 1, rate = 2, channel = 3, signal = 5, noise = 6
    }
    // Field flag: 0x40 in the Flags field means the FCS failed.
    private static let flagBadFCS: UInt8 = 0x40

    public static func parse(_ bytes: [UInt8]) -> RadiotapInfo? {
        guard bytes.count >= 8 else { return nil }
        let itLen = Int(bytes[2]) | (Int(bytes[3]) << 8)
        guard itLen >= 8 else { return nil }

        // Read the (possibly chained) presence bitmaps.
        var present = UInt32(bytes[4]) | (UInt32(bytes[5]) << 8)
                    | (UInt32(bytes[6]) << 16) | (UInt32(bytes[7]) << 24)
        var offset = 8
        // Extended-presence: high bit set → another 32-bit word follows.
        while (present & (1 << 31)) != 0 {
            guard offset + 4 <= bytes.count else { break }
            present = UInt32(bytes[offset]) | (UInt32(bytes[offset+1]) << 8)
                    | (UInt32(bytes[offset+2]) << 16) | (UInt32(bytes[offset+3]) << 24)
            offset += 4
        }

        var info = RadiotapInfo(headerLength: itLen)
        func has(_ bit: Int) -> Bool { (present & (1 << bit)) != 0 }
        func align(_ n: Int) { if offset % n != 0 { offset += n - (offset % n) } }
        func u8() -> UInt8? { guard offset < bytes.count else { return nil }; defer { offset += 1 }; return bytes[offset] }
        func u16() -> Int? {
            align(2)
            guard offset + 2 <= bytes.count else { return nil }
            defer { offset += 2 }
            return Int(bytes[offset]) | (Int(bytes[offset+1]) << 8)
        }

        if has(Bit.flags) { if let f = u8() { info.badFCS = (f & flagBadFCS) != 0 } }
        if has(Bit.rate)  { if let r = u8() { info.rateMbps = Double(r) * 0.5 } }
        if has(Bit.channel) {
            info.frequencyMHz = u16()
            _ = u16() // channel flags — skipped
        }
        if has(Bit.signal) { if let s = u8() { info.signalDBm = Int(Int8(bitPattern: s)) } }
        if has(Bit.noise)  { if let n = u8() { info.noiseDBm = Int(Int8(bitPattern: n)) } }

        return info
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RadiotapParserTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/PassiveCapture/RadiotapParser.swift Tests/PassiveCaptureTests/RadiotapParserTests.swift
git commit -m "feat(passive): radiotap header parser"
```

---

### Task 4: Dot11FrameParser

**Files:**
- Create: `Sources/PassiveCapture/Dot11FrameParser.swift`
- Test: `Tests/PassiveCaptureTests/Dot11FrameParserTests.swift`

**Interfaces:**
- Consumes: nothing kit-side.
- Produces:
```swift
public enum Dot11Type: Equatable, Sendable { case management, control, data, unknown }
public struct Dot11Header: Equatable, Sendable {
    public var type: Dot11Type
    public var subtype: UInt8
    public var isRetry: Bool
    public var isProtected: Bool
    public var addr1: String?
    public var addr2: String?
    public var addr3: String?
    public var taggedBodyRange: Range<Int>?   // IE bytes, for beacon/probe-resp/probe-req
}
public enum Dot11Subtype { // management subtypes we name
    public static let assocReq: UInt8 = 0, assocResp: UInt8 = 1
    public static let reassocReq: UInt8 = 2, reassocResp: UInt8 = 3
    public static let probeReq: UInt8 = 4, probeResp: UInt8 = 5
    public static let beacon: UInt8 = 8
}
public enum Dot11FrameParser { public static func parse(_ bytes: [UInt8]) -> Dot11Header? }
```

- [ ] **Step 1: Write the failing test**

`Tests/PassiveCaptureTests/Dot11FrameParserTests.swift`:
```swift
import XCTest
@testable import PassiveCapture

final class Dot11FrameParserTests: XCTestCase {
    func testBeaconHeader() {
        let h = Dot11FrameParser.parse(Fixtures.beaconVisible)
        XCTAssertEqual(h?.type, .management)
        XCTAssertEqual(h?.subtype, Dot11Subtype.beacon)
        XCTAssertEqual(h?.isRetry, false)
        XCTAssertEqual(h?.addr2, "00:11:22:33:44:55")
        XCTAssertEqual(h?.addr3, "00:11:22:33:44:55")
        // Beacon fixed params are 12 bytes after the 24-byte MAC header.
        XCTAssertEqual(h?.taggedBodyRange, 36..<Fixtures.beaconVisible.count)
    }
    func testRetryBit() {
        XCTAssertEqual(Dot11FrameParser.parse(Fixtures.beaconVisibleRetry)?.isRetry, true)
    }
    func testProbeRequestBodyStartsAfterHeader() {
        let h = Dot11FrameParser.parse(Fixtures.probeRequest)
        XCTAssertEqual(h?.subtype, Dot11Subtype.probeReq)
        XCTAssertEqual(h?.addr2, "66:77:88:99:AA:BB")
        XCTAssertEqual(h?.taggedBodyRange, 24..<Fixtures.probeRequest.count)  // no fixed params
    }
    func testTruncatedReturnsNil() {
        XCTAssertNil(Dot11FrameParser.parse([0x80, 0x00]))
        XCTAssertNil(Dot11FrameParser.parse([]))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter Dot11FrameParserTests`
Expected: FAIL — `Dot11FrameParser` not found.

- [ ] **Step 3: Write minimal implementation**

`Sources/PassiveCapture/Dot11FrameParser.swift`:
```swift
import Foundation

public enum Dot11Type: Equatable, Sendable { case management, control, data, unknown }

public struct Dot11Header: Equatable, Sendable {
    public var type: Dot11Type
    public var subtype: UInt8
    public var isRetry: Bool
    public var isProtected: Bool
    public var addr1: String?
    public var addr2: String?
    public var addr3: String?
    public var taggedBodyRange: Range<Int>?
}

public enum Dot11Subtype {
    public static let assocReq: UInt8 = 0, assocResp: UInt8 = 1
    public static let reassocReq: UInt8 = 2, reassocResp: UInt8 = 3
    public static let probeReq: UInt8 = 4, probeResp: UInt8 = 5
    public static let beacon: UInt8 = 8
}

/// Parse the 802.11 MAC header. Bounds-checked: returns nil if the mandatory 24-byte header
/// isn't fully present.
public enum Dot11FrameParser {
    private static let macHeaderLength = 24
    // Management subtypes whose body begins with 12 bytes of fixed params before the IEs.
    private static let fixedParamSubtypes: Set<UInt8> =
        [Dot11Subtype.beacon, Dot11Subtype.probeResp,
         Dot11Subtype.assocResp, Dot11Subtype.reassocResp]

    public static func parse(_ bytes: [UInt8]) -> Dot11Header? {
        guard bytes.count >= macHeaderLength else { return nil }
        let fc0 = bytes[0], fc1 = bytes[1]
        let type: Dot11Type
        switch (fc0 >> 2) & 0x3 {
        case 0: type = .management
        case 1: type = .control
        case 2: type = .data
        default: type = .unknown
        }
        let subtype = (fc0 >> 4) & 0xF
        let isRetry = (fc1 & 0x08) != 0
        let isProtected = (fc1 & 0x40) != 0

        func mac(_ start: Int) -> String {
            bytes[start..<start+6].map { String(format: "%02X", $0) }.joined(separator: ":")
        }
        let addr1 = mac(4), addr2 = mac(10), addr3 = mac(16)

        // Body offset: management frames put IEs after the 24-byte header, plus 12 fixed
        // bytes for the subtypes that carry them (beacon/probe-resp/assoc-resp).
        var bodyStart = macHeaderLength
        if type == .management, fixedParamSubtypes.contains(subtype) { bodyStart += 12 }
        let taggedBodyRange: Range<Int>? =
            (type == .management && bodyStart <= bytes.count) ? bodyStart..<bytes.count : nil

        return Dot11Header(type: type, subtype: subtype, isRetry: isRetry,
                           isProtected: isProtected, addr1: addr1, addr2: addr2,
                           addr3: addr3, taggedBodyRange: taggedBodyRange)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter Dot11FrameParserTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/PassiveCapture/Dot11FrameParser.swift Tests/PassiveCaptureTests/Dot11FrameParserTests.swift
git commit -m "feat(passive): 802.11 MAC header parser"
```

---

### Task 5: FrameIngestor (reuses IEParser)

**Files:**
- Create: `Sources/PassiveCapture/FrameIngestor.swift`
- Test: `Tests/PassiveCaptureTests/FrameIngestorTests.swift`

**Interfaces:**
- Consumes: `RadiotapParser`, `Dot11FrameParser`, `channelNumber(forFrequencyMHz:)`, `band(forFrequencyMHz:)`, `IEParser.parse(_:band:)` (existing), `ParsedIEs` (existing).
- Produces:
```swift
public struct CapturedFrame: Sendable {
    public var radiotap: RadiotapInfo
    public var header: Dot11Header
    public var channel: Int?
    public var ies: ParsedIEs?
    public var rawLength: Int
}
public enum FrameIngestor { public static func ingest(_ raw: [UInt8]) -> CapturedFrame? }
```

- [ ] **Step 1: Write the failing test**

`Tests/PassiveCaptureTests/FrameIngestorTests.swift`:
```swift
import XCTest
import IEParser
@testable import PassiveCapture

final class FrameIngestorTests: XCTestCase {
    func testVisibleBeaconResolvesSSIDAndChannel() {
        let f = FrameIngestor.ingest(Fixtures.frame(Fixtures.beaconVisible))
        XCTAssertEqual(f?.channel, 1)
        XCTAssertEqual(f?.radiotap.signalDBm, -50)
        XCTAssertEqual(f?.header.subtype, Dot11Subtype.beacon)
        XCTAssertEqual(f?.ies?.ssid, "Test")
    }
    func testHiddenBeaconHasEmptyOrNilSSID() {
        let f = FrameIngestor.ingest(Fixtures.frame(Fixtures.beaconHidden))
        XCTAssertEqual(f?.header.subtype, Dot11Subtype.beacon)
        XCTAssertTrue((f?.ies?.ssid ?? "").isEmpty)
    }
    func testRadiotapFailureYieldsNil() {
        XCTAssertNil(FrameIngestor.ingest([0x00]))  // too short for radiotap
    }
    func testShortDot11AfterHeaderYieldsNil() {
        // Valid radiotap header but no 802.11 frame after it.
        XCTAssertNil(FrameIngestor.ingest(Fixtures.radiotapHeader))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FrameIngestorTests`
Expected: FAIL — `FrameIngestor` not found.

- [ ] **Step 3: Write minimal implementation**

`Sources/PassiveCapture/FrameIngestor.swift`:
```swift
import Foundation
import WiFiModel
import IEParser

public struct CapturedFrame: Sendable {
    public var radiotap: RadiotapInfo
    public var header: Dot11Header
    public var channel: Int?
    public var ies: ParsedIEs?
    public var rawLength: Int
}

/// Orchestrates the decode of one raw captured frame (radiotap + 802.11). Reuses the
/// existing `IEParser` for management-frame tagged parameters — no IE decoding is
/// duplicated here.
public enum FrameIngestor {
    public static func ingest(_ raw: [UInt8]) -> CapturedFrame? {
        guard let rt = RadiotapParser.parse(raw),
              rt.headerLength <= raw.count else { return nil }
        let dot11 = Array(raw[rt.headerLength...])
        guard let header = Dot11FrameParser.parse(dot11) else { return nil }

        let channel = rt.frequencyMHz.flatMap(channelNumber(forFrequencyMHz:))
        let bnd = rt.frequencyMHz.flatMap(band(forFrequencyMHz:)) ?? .unknown

        var ies: ParsedIEs?
        if let r = header.taggedBodyRange, r.lowerBound <= dot11.count {
            let clamped = r.lowerBound..<min(r.upperBound, dot11.count)
            ies = IEParser.parse(Array(dot11[clamped]), band: bnd)
        }
        return CapturedFrame(radiotap: rt, header: header, channel: channel,
                             ies: ies, rawLength: raw.count)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FrameIngestorTests`
Expected: PASS (4 tests). If `ParsedIEs.ssid` for a zero-length SSID IE is `nil` rather than `""`, the `isEmpty` assertion still holds.

- [ ] **Step 5: Commit**

```bash
git add Sources/PassiveCapture/FrameIngestor.swift Tests/PassiveCaptureTests/FrameIngestorTests.swift
git commit -m "feat(passive): frame ingestor combining radiotap + 802.11 + IEParser"
```

---

### Task 6: Accumulators (hidden SSID, airtime, stations, retries)

**Files:**
- Create: `Sources/PassiveCapture/Accumulators.swift`
- Test: `Tests/PassiveCaptureTests/AccumulatorTests.swift`

**Interfaces:**
- Consumes: `CapturedFrame`, `Dot11Type`, `Dot11Subtype`.
- Produces:
```swift
public struct PassiveBSS: Equatable, Sendable {
    public var bssid: String; public var ssid: String?; public var channel: Int?
    public var signalDBm: Int?; public var hiddenResolved: Bool
}
public final class PassiveBSSAccumulator {
    public private(set) var bsses: [String: PassiveBSS]
    public init(); public func ingest(_ f: CapturedFrame)
}
public final class AirtimeAccumulator {
    public init()
    public func ingest(_ f: CapturedFrame)
    public func busyMicroseconds(channel: Int) -> Double
    public func utilization(channel: Int, elapsedSeconds: Double) -> Double  // 0...1
}
public struct Station: Equatable, Sendable { public var mac: String; public var signalDBm: Int?; public var probing: Bool }
public final class StationTracker {
    public private(set) var stations: [String: Station]
    public init(); public func ingest(_ f: CapturedFrame)
}
public struct RetryStat: Equatable, Sendable { public var total: Int; public var retries: Int; public var rate: Double }
public final class RetryAccumulator {
    public init(); public func ingest(_ f: CapturedFrame); public func stat(bssid: String) -> RetryStat?
}
public func frameAirtimeMicroseconds(bytes: Int, rateMbps: Double) -> Double
```

- [ ] **Step 1: Write the failing test**

`Tests/PassiveCaptureTests/AccumulatorTests.swift`:
```swift
import XCTest
@testable import PassiveCapture

final class AccumulatorTests: XCTestCase {
    private func ingest(_ dot11: [UInt8]) -> CapturedFrame {
        FrameIngestor.ingest(Fixtures.frame(dot11))!
    }

    func testHiddenSSIDFilledFromLaterFrame() {
        let acc = PassiveBSSAccumulator()
        acc.ingest(ingest(Fixtures.beaconHidden))          // blank name first
        XCTAssertTrue((acc.bsses["00:11:22:33:44:55"]?.ssid ?? "").isEmpty)
        acc.ingest(ingest(Fixtures.beaconVisible))         // name arrives
        XCTAssertEqual(acc.bsses["00:11:22:33:44:55"]?.ssid, "Test")
        XCTAssertEqual(acc.bsses["00:11:22:33:44:55"]?.hiddenResolved, true)
        XCTAssertEqual(acc.bsses["00:11:22:33:44:55"]?.channel, 1)
    }

    func testAirtimeMath() {
        // 1000 bytes at 6 Mbps = 8000 bits / 6 = 1333.33 µs.
        XCTAssertEqual(frameAirtimeMicroseconds(bytes: 1000, rateMbps: 6), 8000.0/6.0, accuracy: 0.01)
    }

    func testAirtimeUtilizationPerChannel() {
        let acc = AirtimeAccumulator()
        let f = ingest(Fixtures.beaconVisible)             // channel 1, 6 Mbps
        acc.ingest(f); acc.ingest(f)
        let expected = 2 * frameAirtimeMicroseconds(bytes: f.rawLength, rateMbps: 6)
        XCTAssertEqual(acc.busyMicroseconds(channel: 1), expected, accuracy: 0.01)
        // Over a 1-second window: fraction = busyMicros / 1_000_000.
        XCTAssertEqual(acc.utilization(channel: 1, elapsedSeconds: 1.0),
                       expected / 1_000_000, accuracy: 1e-9)
    }

    func testStationTrackerCollectsProbingClient() {
        let acc = StationTracker()
        acc.ingest(ingest(Fixtures.probeRequest))
        XCTAssertEqual(acc.stations["66:77:88:99:AA:BB"]?.probing, true)
        // A beacon's broadcast addr1 must NOT be listed as a station.
        acc.ingest(ingest(Fixtures.beaconVisible))
        XCTAssertNil(acc.stations["FF:FF:FF:FF:FF:FF"])
    }

    func testRetryRate() {
        let acc = RetryAccumulator()
        acc.ingest(ingest(Fixtures.beaconVisible))         // not a retry
        acc.ingest(ingest(Fixtures.beaconVisibleRetry))    // retry
        let s = acc.stat(bssid: "00:11:22:33:44:55")
        XCTAssertEqual(s?.total, 2)
        XCTAssertEqual(s?.retries, 1)
        XCTAssertEqual(s?.rate, 0.5)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AccumulatorTests`
Expected: FAIL — accumulator types not found.

- [ ] **Step 3: Write minimal implementation**

`Sources/PassiveCapture/Accumulators.swift`:
```swift
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
        // Fill (or resolve a previously-hidden) name when a non-empty one arrives.
        if let name = incomingName, !name.isEmpty {
            if (bss.ssid ?? "").isEmpty && bss.ssid != name { bss.hiddenResolved = bss.ssid != nil || bss.hiddenResolved }
            if (bss.ssid ?? "").isEmpty { bss.hiddenResolved = bsses[bssid] != nil }
            bss.ssid = name
        } else if bss.ssid == nil {
            bss.ssid = ""   // record that we've seen it hidden
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
```

- [ ] **Step 4: Simplify the hidden-resolved logic before running**

The `hiddenResolved` lines above are tangled. Replace the name-fill block in `PassiveBSSAccumulator.ingest` with this clear version:
```swift
        let alreadyKnown = bsses[bssid] != nil
        let wasHidden = (bss.ssid ?? "").isEmpty
        if let name = incomingName, !name.isEmpty {
            if alreadyKnown && wasHidden { bss.hiddenResolved = true }
            bss.ssid = name
        } else if bss.ssid == nil {
            bss.ssid = ""   // seen, but hidden so far
        }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter AccumulatorTests`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/PassiveCapture/Accumulators.swift Tests/PassiveCaptureTests/AccumulatorTests.swift
git commit -m "feat(passive): BSS/airtime/station/retry accumulators"
```

---

### Task 7: Full-suite regression + module export check

**Files:** none (verification only).

- [ ] **Step 1: Run the entire test suite**

Run: `swift test`
Expected: PASS — the original 34 tests plus the new `PassiveCaptureTests` (all tasks above), zero failures.

- [ ] **Step 2: Confirm the module builds as a product**

Run: `swift build --target PassiveCapture`
Expected: `Build complete`.

- [ ] **Step 3: Commit any final touch-ups (if needed)**

```bash
git commit --allow-empty -m "test(passive): full kit-pipeline suite green"
```

---

## Self-Review

**Spec coverage** (against `2026-07-01-passive-scan-monitor-mode-design.md`, "New kit module" + "Derivation"):
- `RadiotapParser` → Task 3. ✅
- `Dot11FrameParser` → Task 4. ✅
- `FrameIngestor` reusing `IEParser` → Task 5. ✅
- `CapturedFrame` → Task 5. ✅
- `PassiveBSSAccumulator` (hidden SSID) → Task 6. ✅
- `AirtimeAccumulator` (measured utilization) → Task 6. ✅
- `StationTracker` (client discovery) → Task 6. ✅
- `RetryAccumulator` (retry rate) → Task 6. ✅
- Defensive/bounds-checked parsing → tested in Tasks 3–5 (too-short/truncated cases). ✅
- Deterministic (no wall-clock) → airtime takes `elapsedSeconds`/frame data, no `Date()`. ✅

Out of scope for this plan (deferred to Plans 2–3, as intended): libpcap C shim, `CaptureEngine`, channel hopping, XPC contract, watchdog/reconnect, `PassiveScanController`, UI, re-notarization.

**Placeholder scan:** no TBD/TODO; every code step has complete code; Task 6 Step 4 explicitly replaces the one tangled block rather than leaving it vague.

**Type consistency:** `CapturedFrame`, `Dot11Header`/`Dot11Subtype`, `RadiotapInfo`, and accumulator signatures are used identically in tests and impl across Tasks 3–6. `IEParser.parse(_:band:)` and `ParsedIEs.ssid` match the existing API confirmed in `Sources/IEParser/IEParser.swift`.
