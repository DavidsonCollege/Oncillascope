# Oncillascope — native macOS Wi-Fi analyzer

A free, open-source macOS app that surfaces **as much RF / Wi-Fi detail as the native
Apple wireless adapter and its system APIs allow** — for the current connection and for
all visible nearby networks. It aims to match or exceed commercial Wi-Fi analyzers while
staying inside what Apple permits on stock hardware: no external USB radios, no kernel
extensions, and no disruptive monitor-mode capture in the default flow.

The defining feature is **completeness**: Oncillascope fuses every available data source —
CoreWLAN (identity, live stats, scan, raw IEs), parsed `wdutil info` (PHY-layer metrics),
and a pure-Swift 802.11 Information Element parser — into one view.

> **Status:** v1.0. The full core (parsing, fusion, telemetry, export) is implemented and
> unit-tested (34/34); the SwiftUI app builds and runs on macOS 14–26 and ships **signed +
> notarized** under Developer ID. An optional **privileged helper** (SMAppService) enables
> prompt-free, continuous PHY metrics.

---

## What it shows

- **Current-connection dashboard** — SSID, BSSID, vendor, band/channel/width, security,
  PHY generation, RSSI / noise / **SNR** (color-coded), Tx rate, transmit power, country.
  Plus **MCS index, spatial streams (NSS), guard interval, and CCA** from `wdutil`, and a
  **max-theoretical-rate vs actual** efficiency indicator.
- **Live time-series charts** — RSSI, noise, SNR, Tx rate, MCS, CCA over a selectable
  1/5/15/60-min window, with automatic markers on **roam** (BSSID change) and channel change.
  PHY-layer series (MCS / CCA) refresh **continuously** when the optional privileged helper
  is enabled (see below); otherwise they update one-shot per manual refresh.
- **Nearby-networks table** — one row per BSS with sort, free-text + structured filters
  (band, generation, min RSSI), and **group-by-SSID** to collapse multi-BSSID APs.
  Channel utilization and station count come from the **BSS Load** IE.
- **Channel map** — 2.4 / 5 / 6 GHz occupancy curves with overlap, plus an advisory
  best-channel recommendation per band.
- **IE inspector** — expand any network to the fully decoded Information Element tree
  (raw hex + human-readable interpretation), including HT/VHT/HE/EHT capabilities.
- **Export & logging** — CSV (networks, telemetry) and JSON (full snapshot); optional
  rolling log to a user-chosen file (off by default).

---

## The macOS reality (this bounds the whole project)

Apple has progressively restricted Wi-Fi telemetry. Oncillascope is designed *around* these
constraints, not against them:

| Constraint | How Oncillascope handles it |
|---|---|
| The `airport` CLI was removed (macOS 14.4+). | Never used. |
| `wdutil` needs `sudo` for every option. | Either a one-time **privileged-helper** approval (no more prompts; enables continuous metrics) or a per-session admin auth; clearly degraded if both are declined. |
| CoreWLAN can't return MCS / NSS / guard interval. | Those come **only** from parsing `wdutil info`. |
| Real BSSIDs require a signed app **+** Location Services. | Signing + a clear Location prompt; otherwise honest degraded-mode messaging. |
| `wdutil` redacts SSID/BSSID/MAC. | Treated as a PHY-metrics source only; identity comes from CoreWLAN. |
| Monitor mode *is* available on the built-in adapter, but it disassociates Wi-Fi and needs root + channel hopping. | The default scan is non-disruptive (CoreWLAN active scan); channel "utilization" comes from the **BSS Load IE**. A passive/monitor-mode scan is feasible future work — see [`PASSIVE-SCAN.md`](PASSIVE-SCAN.md). |

If Location is denied or admin auth is declined, Oncillascope **tells you exactly which
fields are redacted and why**, and offers a one-click path to fix it — never silent blanks.

---

## Privileged helper (continuous PHY metrics)

PHY-layer metrics (MCS / NSS / guard interval / CCA) can only come from `wdutil`, which
requires root. Rather than prompt for an admin password every time, Oncillascope ships an
optional **SMAppService privileged helper** (`OncillascopeHelper`):

- A one-time approval in **System Settings ▸ Login Items & Extensions** registers an
  on-demand root daemon (no idle root process — launchd starts it only when needed).
- The app talks to it over **XPC**, with both sides enforcing a code-signing requirement
  (same Team ID, genuine signature) — the helper exposes exactly one operation
  (`wdutil info`) and nothing else.
- Once approved, PHY metrics refresh **every tick with no further prompts**, powering the
  continuous MCS / CCA charts. Without it, the app falls back to a per-session in-process
  admin prompt (attributed to Oncillascope) for one-shot metrics.

Enable it from the degraded-mode banner or **View ▸ Enable Continuous PHY Metrics**.

---

## Architecture

A SwiftPM package (`WiFiAnalyzerKit`) holds the framework-independent, unit-tested core;
a thin SwiftUI app (`App/`) sits on top.

| Module | Role |
|---|---|
| `WiFiModel` | Shared value types + OFDM PHY-rate calculator (HT/VHT/HE/EHT). |
| `IEParser` | Pure-Swift 802.11 Information Element decoder — the crown jewel. |
| `WdutilBridge` | Defensive, version-tolerant `wdutil info` parser + runner. |
| `OUIResolver` | Offline, privacy-preserving BSSID → vendor lookup. |
| `Telemetry` | Bounded ring buffers + CSV/JSON export + roam/channel markers. |
| `WiFiCore` | CoreWLAN + CoreLocation wrapper; fuses all three data sources. |

On top sits the SwiftUI app (`App/Oncillascope/`) plus the optional root XPC daemon
(`App/OncillascopeHelper/`), which share a single `HelperProtocol.swift` compiled into both
targets so the XPC contract stays in lockstep.

No third-party runtime dependencies in the core (`WiFiAnalyzerKit`); the app shell bundles
**Sparkle** solely for updates. No telemetry. OUI lookups are fully local. The only network
activity is the **optional** Sparkle update check against GitHub Releases, which you opt into
on first launch and can disable anytime in the update dialog.

---

## Build & run

### Core library + tests (no signing needed)

```bash
swift build
swift test     # 34 tests
```

### The app

```bash
open App/Oncillascope.xcodeproj      # then ⌘R in Xcode
# or headless:
xcodebuild -scheme Oncillascope -configuration Debug build
```

A plain build is **ad-hoc signed** and runs in clearly-labeled degraded mode (BSSIDs may
be redacted). For un-redacted scan data you need a real signature + Location Services, and
the privileged helper requires a Developer ID signature + notarization — see
[`SIGNING.md`](SIGNING.md). Always build with `-scheme Oncillascope` (not `-target`); the
signed Release recipe builds and embeds the `OncillascopeHelper` daemon automatically.

**Requirements:** macOS 14 (Sonoma) or later; Xcode 16+. Verified building on macOS 26
(Tahoe) with Xcode 26 on Apple Silicon. Release builds a universal (arm64 + x86_64) binary.

---

## Out of scope / known limitations

- **No passive/monitor-mode capture in the current build** — not because the adapter
  forbids it (monitor mode + radiotap *do* work on the built-in card; confirmed in
  [`PASSIVE-SCAN.md`](PASSIVE-SCAN.md)) but because it disassociates Wi-Fi and needs root +
  channel hopping, so it's deferred to an explicit future mode. Channel "utilization" is
  read from the BSS Load IE only. **External spectrum analyzers and AirPcap-style hardware
  remain genuinely out of scope.**
- **No external USB-adapter support.**
- Identity fields (SSID/BSSID) depend on signing + Location Services. The degraded-mode
  messaging exists so you always know *why* something is redacted.
- `wdutil` output is undocumented and changes between macOS releases. The parser is
  key-driven and tolerant; fixtures live in `Tests/WdutilBridgeTests`.
- The bundled OUI database is a curated common subset. Drop in the full IEEE registry for
  complete vendor coverage (see `Sources/OUIResolver/Resources/oui.csv`).

---

## Updating

Oncillascope updates itself via [Sparkle](https://sparkle-project.org). On first launch it
asks whether to check for updates automatically. When a newer signed release is available it
shows the release notes and an **Install & Relaunch** button — updates are never installed
silently. You can also trigger a check anytime from **Oncillascope ▸ Check for Updates…**.

Every update is protected by two independent signatures: the app's Developer ID + Apple
notarization (checked by macOS), and an EdDSA signature on the appcast (checked by Sparkle),
so a compromised feed host cannot ship a tampered build. Releases and the update feed are
produced automatically by the CI pipeline described in [`RELEASING.md`](RELEASING.md).

## License

MIT. See [LICENSE](LICENSE).
