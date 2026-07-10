import Foundation
import SwiftUI
import AppKit
import WiFiModel
import WiFiCore
import WdutilBridge
import Telemetry
import OUIResolver

/// A scan failure carried across the actor boundary (String is not an Error).
struct ScanFailure: Error, Sendable { let message: String }

/// State of the `wdutil` PHY-metrics source (spec §4.7 degraded-mode transparency).
enum WdutilState: Equatable {
    case unknown                 // not yet attempted
    case needsAuth               // admin auth required / declined
    case unavailable(String)     // wdutil missing or errored
    case ready(WdutilMetrics)    // parsed metrics available
}

/// Central app state. Owns the refresh + scan loops, fuses the data sources, and
/// derives the degraded-mode flags the UI surfaces.
@MainActor
final class AppModel: ObservableObject {

    // Current connection (CoreWLAN + wdutil fused).
    @Published private(set) var current: ConnectionInfo?
    // Nearby networks from the last scan.
    @Published private(set) var networks: [BSSObservation] = []
    // Live telemetry mirror for charts.
    @Published private(set) var samples: [TelemetrySample] = []
    @Published private(set) var markers: [TimelineMarker] = []

    @Published private(set) var isScanning = false
    @Published private(set) var lastScanDate: Date?
    @Published private(set) var scanError: String?
    @Published private(set) var wdutil: WdutilState = .unknown
    @Published private(set) var interfaceAvailable = true
    /// Bands this Mac's radio supports (empty = unknown, e.g. Wi-Fi off).
    @Published private(set) var supportedBands: Set<Band> = []

    // User controls.
    @Published var refreshInterval: Double = 2.0
    @Published var isPaused = false
    @Published var autoScan = true

    // Rolling log (off by default; user-chosen location — spec §4.6).
    @Published private(set) var isLogging = false
    @Published private(set) var logURL: URL?
    private var logHandle: FileHandle?

    let location = LocationAuthorization()

    private let telemetry = TelemetryStore(capacity: 3600)
    private let iface = WiFiInterface()

    // Merges scan passes so marginal networks don't flicker in and out of the UI:
    // a BSS survives 90 s after it was last heard; rows that missed the latest pass
    // are marked stale (dimmed in the table / channel map).
    private var aggregator = ScanAggregator()

    // Privileged helper daemon. When approved it provides continuous, prompt-free PHY
    // metrics over XPC; otherwise we fall back to a per-session in-process admin prompt.
    private let helper = HelperManager()
    /// Mirrors the daemon's lifecycle for the UI (banner + View menu).
    @Published private(set) var helperStatus: HelperManager.Status = .notRegistered

    private var refreshTask: Task<Void, Never>?
    private var lastScanTick = Date.distantPast

    // MARK: - Degraded-mode derivations (spec §4.7)

    /// True when identity fields are redacted — the build is unsigned or Location is off.
    var bssidRedacted: Bool {
        if location.access != .granted { return true }
        if let b = current?.bssid, b == "<redacted>" || b.isEmpty { return true }
        // If a scan returned rows but every BSSID is redacted, identity is blocked.
        if !networks.isEmpty, networks.allSatisfy({ ($0.bssid ?? "").isEmpty || $0.bssid == "<redacted>" }) {
            return true
        }
        return false
    }

    var phyMetricsAvailable: Bool {
        if case .ready = wdutil { return true }
        return false
    }

    // MARK: - Lifecycle

    func start() {
        interfaceAvailable = WiFiInterface.isAvailable
        let iface = self.iface
        Task { self.supportedBands = await Task.detached { iface.supportedBands() }.value }
        if location.access == .notDetermined { location.request() }
        // Don't auto-prompt for admin on launch — show the banner and let the user
        // click Authorize (one-shot prompt) or enable the helper (continuous, no prompt).
        helperStatus = helper.currentStatus()
        wdutil = .needsAuth
        scanNow()
        // If the helper is already approved, fetch PHY metrics immediately and let the loop
        // keep them live without any prompt.
        if helperStatus.isUsable { Task { await refreshWdutil() } }
        startLoop()
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func startLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: .seconds(max(0.5, self.refreshInterval)))
                if Task.isCancelled { return }
                await self.tick()
            }
        }
    }

    private func tick() async {
        guard !isPaused else { return }

        // With the helper approved, refresh PHY metrics every tick — XPC is silent, so
        // there's no prompt to avoid. Without it we leave wdutil one-shot (user-triggered)
        // so we never re-show the admin dialog.
        if helperStatus.isUsable { await refreshWdutil() }

        await refreshCurrent()

        // Re-publish from the aggregator so expired entries age out between scans
        // (and stale-row dimming updates) even when no new scan has landed.
        publishNetworks()

        // Periodic background rescan (radio retune; keep it infrequent).
        if autoScan, Date().timeIntervalSince(lastScanTick) > 20 {
            scanNow()
        }
    }

    // MARK: - Current connection

    func refreshCurrent() async {
        let iface = self.iface
        var base = await Task.detached { iface.currentConnection() }.value
        if let b = base, case .ready(let m) = wdutil {
            base = SnapshotBuilder.merge(b, with: m)
        }
        current = base

        if let c = base {
            let sample = TelemetrySample(timestamp: Date(), connection: c)
            telemetry.record(sample)
            samples = telemetry.samples
            markers = telemetry.markers
            appendLog(sample)
        }
    }

    // MARK: - Rolling log

    func startLogging() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "oncillascope-log.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            FileManager.default.createFile(atPath: url.path, contents: nil)
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            // Write the CSV header once (an empty sample list yields header only).
            handle.write(Data(Exporter.samplesCSV([]).utf8))
            self.logHandle = handle
            self.logURL = url
            self.isLogging = true
        }
    }

    func stopLogging() {
        try? logHandle?.close()
        logHandle = nil
        isLogging = false
    }

    /// Append one sample row to the rolling log (header already written).
    private func appendLog(_ sample: TelemetrySample) {
        guard isLogging, let handle = logHandle else { return }
        let csv = Exporter.samplesCSV([sample])
        // Drop the header line; keep only the data row.
        let rows = csv.split(separator: "\n", omittingEmptySubsequences: true)
        if rows.count >= 2 {
            handle.write(Data((rows[1] + "\n").utf8))
        }
    }

    // MARK: - Scanning

    func scanNow() {
        guard !isScanning else { return }
        isScanning = true
        lastScanTick = Date()
        let iface = self.iface
        Task {
            // Map any error to a String inside the detached task so nothing non-Sendable
            // crosses the actor boundary (Swift 6 strict concurrency).
            let result: Result<[BSSObservation], ScanFailure> = await Task.detached {
                do { return .success(try iface.scan()) }
                catch let e as WiFiInterface.ScanError { return .failure(ScanFailure(message: Self.describe(e))) }
                catch { return .failure(ScanFailure(message: error.localizedDescription)) }
            }.value
            switch result {
            case .success(let nets):
                self.aggregator.ingest(nets, at: Date())
                self.publishNetworks()
                self.scanError = nil
                self.lastScanDate = Date()
            case .failure(let failure):
                // The aggregator already retains recent passes for its ttl, so a
                // failed scan doesn't empty the table. Seed from the system's scan
                // cache only when we have nothing at all (e.g. first scan failed).
                if self.networks.isEmpty {
                    let cached = await Task.detached { iface.cachedScan() }.value
                    if !cached.isEmpty { self.aggregator.ingest(cached, at: Date()) }
                    self.publishNetworks()
                }
                self.scanError = failure.message
            }
            self.isScanning = false
        }
    }

    /// Refresh the published list from the aggregator (also ages out expired entries).
    private func publishNetworks() {
        networks = aggregator.observations(at: Date()).sorted { $0.rssi > $1.rssi }
    }

    /// True when this BSS missed the most recent scan pass and is coasting on its ttl.
    func isStale(_ id: String) -> Bool { aggregator.isStale(id: id, at: Date()) }

    /// Seconds since this BSS was last heard, for the "last seen" hint.
    func lastSeenAge(_ id: String) -> TimeInterval? {
        aggregator.lastSeen(id: id).map { Date().timeIntervalSince($0) }
    }

    nonisolated private static func describe(_ e: WiFiInterface.ScanError) -> String {
        switch e {
        case .noInterface: return "No Wi-Fi interface found."
        case .failed(let m): return "Scan failed: \(m)"
        }
    }

    // MARK: - wdutil PHY metrics

    func refreshWdutil() async {
        // Prefer the prompt-free helper when it's approved; otherwise fall back to the
        // in-process admin prompt (attributed to Oncillascope, not osascript).
        let invoke: @Sendable () async throws -> String
        if helperStatus.isUsable {
            let helper = self.helper
            invoke = { try await helper.fetchWdutilInfo() }
        } else {
            invoke = runWdutilInfoWithAdminPrompt
        }
        let runner = WdutilRunner(strategy: .helper(invoke: invoke))
        let outcome: WdutilState = await Task.detached {
            do {
                let m = try await runner.fetchMetrics()
                return .ready(m)
            } catch WdutilRunner.WdutilError.notAuthorized {
                return .needsAuth
            } catch WdutilRunner.WdutilError.userCancelled {
                return .needsAuth
            } catch WdutilRunner.WdutilError.executableMissing {
                return .unavailable("The system tool required for PHY metrics was not found.")
            } catch {
                return .unavailable(error.localizedDescription)
            }
        }.value
        wdutil = outcome
    }

    // MARK: - Privileged helper

    /// True when the helper is approved and feeding continuous metrics.
    var helperUsable: Bool { helperStatus.isUsable }

    /// Install the helper (and open Login Items if approval is pending). Idempotent.
    func enableHelper() {
        helperStatus = helper.register()
        if helperStatus.isUsable { Task { await refreshWdutil() } }
    }

    /// Re-check status after the user has been to System Settings, then start metrics.
    func confirmHelperApproval() {
        helperStatus = helper.currentStatus()
        if helperStatus.isUsable { Task { await refreshWdutil() } }
    }

    func openHelperSettings() { helper.openLoginItemsSettings() }

    func disableHelper() {
        Task {
            await helper.unregister()
            helperStatus = helper.currentStatus()
            // Drop back to the one-shot prompt path until re-enabled.
            wdutil = .needsAuth
        }
    }

    // MARK: - Telemetry control

    func clearTelemetry() {
        telemetry.reset()
        samples = []
        markers = []
    }

    // MARK: - Snapshot for export

    func currentSnapshot() -> WiFiSnapshot {
        WiFiSnapshot(timestamp: Date(), current: current, networks: networks)
    }
}
