# Oncillascope — native macOS Wi-Fi analyzer

A free, open-source macOS app that surfaces **as much RF / Wi-Fi detail as the native
Apple wireless adapter and its system APIs allow** — for the current connection and for
all visible nearby networks. It aims to match or exceed paid tools (WiFi Explorer Pro,
WiFi Signal) while staying inside what Apple permits on stock hardware: no external USB
radios, no kernel extensions, no monitor mode.

The defining feature is **completeness**: Oncillascope fuses every available data source —
CoreWLAN (identity, live stats, scan, raw IEs), parsed `wdutil info` (PHY-layer metrics),
and a pure-Swift 802.11 Information Element parser — into one view.

> **Status:** v1.0 foundation. The full core (parsing, fusion, telemetry, export) is
> implemented and unit-tested; the SwiftUI app builds and runs on macOS 14–26.

---

## What it shows

- **Current-connection dashboard** — SSID, BSSID, vendor, band/channel/width, security,
  PHY generation, RSSI / noise / **SNR** (color-coded), Tx rate, transmit power, country.
  Plus **MCS index, spatial streams (NSS), guard interval, and CCA** from `wdutil`, and a
  **max-theoretical-rate vs actual** efficiency indicator.
- **Live time-series charts** — RSSI, noise, SNR, Tx rate, MCS, CCA over a selectable
  1/5/15/60-min window, with automatic markers on **roam** (BSSID change) and channel change.
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
| `wdutil` needs `sudo` for every option. | One up-front admin auth; clearly degraded if declined. |
| CoreWLAN can't return MCS / NSS / guard interval. | Those come **only** from parsing `wdutil info`. |
| Real BSSIDs require a signed app **+** Location Services. | Signing + a clear Location prompt; otherwise honest degraded-mode messaging. |
| `wdutil` redacts SSID/BSSID/MAC. | Treated as a PHY-metrics source only; identity comes from CoreWLAN. |
| No monitor mode on the built-in adapter. | No packet capture / sniffing / true spectrum analysis. Channel "utilization" is read from the **BSS Load IE** only. |

If Location is denied or admin auth is declined, Oncillascope **tells you exactly which
fields are redacted and why**, and offers a one-click path to fix it — never silent blanks.

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

No third-party runtime dependencies. No telemetry, no network calls (OUI lookups are
fully local).

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
be redacted). For un-redacted scan data you need a real signature + Location Services —
see [`SIGNING.md`](SIGNING.md).

**Requirements:** macOS 14 (Sonoma) or later; Xcode 16+. Verified building on macOS 26
(Tahoe) with Xcode 26 on Apple Silicon. Release builds a universal (arm64 + x86_64) binary.

---

## Out of scope / known limitations

- **No monitor-mode packet capture, no traffic sniffing, no true spectrum analysis** —
  the built-in adapter doesn't allow it. Channel "utilization" is read from the BSS Load
  IE only.
- **No external USB-adapter support.**
- Identity fields (SSID/BSSID) depend on signing + Location Services. The degraded-mode
  messaging exists so you always know *why* something is redacted.
- `wdutil` output is undocumented and changes between macOS releases. The parser is
  key-driven and tolerant; fixtures live in `Tests/WdutilBridgeTests`.
- The bundled OUI database is a curated common subset. Drop in the full IEEE registry for
  complete vendor coverage (see `Sources/OUIResolver/Resources/oui.csv`).

---

## License

MIT. See [LICENSE](LICENSE).

Prior art studied (not copied): `chbrown/macos-wifi`, `mikaellofgren/wandra`,
`nolze/tiny-wifi-analyzer`, `jaisonerick/macwifi`.
