# Passive Scan (monitor-mode capture) — design

**Status:** approved design, pre-implementation.
**Date:** 2026-07-01.
**Prior art:** feasibility spike in [`PASSIVE-SCAN.md`](../../../PASSIVE-SCAN.md) — monitor mode +
radiotap confirmed working on the built-in `en0` adapter (Mac14,2, macOS 26.5.1).

## Goal

Add a **full passive Wi-Fi analyzer** to Oncillascope using monitor-mode capture on the
built-in adapter — the largest remaining parity gap with WiFi Explorer Pro. Deliverables:

1. **Hidden SSID resolution** — recover network names the active CoreWLAN scan can't see.
2. **Measured channel utilization** — real airtime busyness per channel, computed from
   observed frame durations (not the AP-advertised BSS Load IE).
3. **Client/device discovery** — surface non-AP stations (probe requests, data frames).
4. **Retry-rate stats** — per-network retry proportion as a link-health signal.

Interaction model: a **continuous start/stop mode** the user explicitly enters. It
disassociates Wi-Fi while active, hops channels continuously accumulating live stats, and
reconnects on stop.

## Non-goals

- External spectrum analyzers / AirPcap-style hardware (genuinely out of scope on stock HW).
- Running passive scan concurrently with the normal live dashboard (single radio).
- Packet-payload inspection / decryption. We parse only headers + management-frame IEs.

## Architecture

Split into a **dumb root capture engine** (helper) and a **testable parse/derive pipeline**
(kit), wired by an extended bidirectional XPC contract.

```
helper libpcap (rfmon, en0)          app / WiFiAnalyzerKit
   │  channel-hop loop                  │
   │  batch raw frames                  │
   └──── XPC: didCapture(batch) ───────▶ FrameIngestor
                                          ├─ RadiotapParser
                                          ├─ Dot11FrameParser
                                          └─ IEParser (REUSED)
                                                │
                                                ▼  CapturedFrame
                                          accumulators (BSS / airtime / stations / retries)
                                                │
                                                ▼  @Published passive state → SwiftUI view
```

**Rationale for this split (approach A, chosen over fd-passing / helper-side parsing):**
minimal root surface (the daemon only reads bytes and retunes the radio — no parsing logic
runs as root); all interesting logic lives in the unprivileged, unit-tested kit; reuses the
existing `SMAppService` helper + code-signing-requirement XPC model already shipped and
notarized.

### New kit module: `Sources/PassiveCapture`

Framework-independent, unit-tested like the rest of `WiFiAnalyzerKit`.

- `RadiotapParser` — decode the little-endian radiotap header. Walk the `present` bitmap
  (handle extended-presence words where the high bit chains another 32-bit word), honor
  field alignment, and extract the fields we use: **flags** (incl. bad-FCS), **channel
  freq + flags**, **antenna signal (dBm)**, **antenna noise (dBm)**, **rate / MCS**. Return
  `RadiotapInfo` + the offset where the 802.11 frame begins (via `it_len`). Skip unknown
  fields rather than fail.
- `Dot11FrameParser` — parse the frame-control field → **type** (mgmt/ctrl/data) + **subtype**
  (beacon, probe-req, probe-resp, assoc-req/resp, data, QoS-data, …), the **retry** and
  protected bits, and address fields (addr1/2/3 selected by type/ToDS/FromDS). For frames
  carrying a fixed body + tagged parameters (beacon/probe-resp: 12-byte fixed prefix of
  timestamp/beacon-interval/capabilities), return the byte range of the IE body.
- `FrameIngestor` — orchestrator. `Data → RadiotapParser → Dot11FrameParser →` hand the IE
  body to the **existing `IEParser`** (zero duplication) → emit a normalized
  `CapturedFrame { radiotap, mac, ies: [InformationElement]?, rawLen }`.
- Derivation types (see "Derivation"): `PassiveBSSAccumulator`, `AirtimeAccumulator`,
  `StationTracker`, `RetryAccumulator`.

**Defensive posture:** captured bytes are attacker-adjacent (arbitrary over-the-air input).
Every parser is fully bounds-checked and returns `nil`/partial on malformed or truncated
(snaplen-cut) input — never traps. Same discipline as `IEParser` / `WdutilParser` today.

### Helper side: `App/OncillascopeHelper/CaptureEngine`

- `pcap_bridge` — a small **C shim** linking the system `libpcap` (present on every Mac,
  stable API), rather than hand-rolling raw BPF `ioctl`s.
- Open sequence: `pcap_create("en0")` → `pcap_set_rfmon(1)` → `pcap_set_snaplen(N)` →
  `pcap_set_timeout(~100ms)` → `pcap_activate` → `pcap_set_datalink(DLT_IEEE802_11_RADIO)`.
- Read loop on a dedicated thread via `pcap_next_ex`; **batch** frames (flush every ~100 ms
  or N frames) into one XPC push to avoid a round-trip per beacon.
- **Channel hopping:** CoreWLAN `CWInterface.setWLANChannel(_:)` (works in a non-GUI root
  process) stepping through `supportedWLANChannels()` filtered to the requested bands,
  dwelling ~200–300 ms per channel. Respects the app's existing `supportedBands` (skips
  6 GHz on radios without it). Per-frame channel is taken from radiotap; the hop tracker is
  for coverage/telemetry only.
- **LOAD-BEARING RISK to validate first in implementation:** that `setWLANChannel` retunes
  cleanly while an rfmon pcap session is live on `en0`. Pro scanners do this; prove it early
  with a throwaway before building the full loop.

### Extended XPC contract (`App/Shared/HelperProtocol.swift`, compiled into both targets)

`OncillascopeHelperProtocol` gains:
- `startCapture(bands: [String], dwellMs: Int, withReply: (Bool, String?) -> Void)` — begin
  the rfmon session + hop loop; reply confirms start or returns a failure reason.
- `stopCapture(reassociate: Bool, withReply: () -> Void)` — stop the loop, close pcap
  (releasing rfmon), and if `reassociate` run `networksetup -setairportpower en0 off/on` as
  root to force rejoin via stored credentials.

New `OncillascopeCaptureClientProtocol` (app-**exported**; helper calls back):
- `didCapture(frameBatch: [Data])` — a batch of raw frames (each = radiotap + 802.11 bytes).
- `didHop(toChannel: Int)` — hop progress for the UI.
- `didStop(reason: String?)` — capture ended (normal, error, or watchdog).

This upgrades the connection from one-shot request/reply to a **persistent bidirectional**
session: the app sets `exportedInterface`/`exportedObject`; the helper holds the client
proxy and streams into it. Existing code-signing-requirement enforcement stays on **both**
directions (`clientRequirement` on the helper, `helperRequirement` on the app).

### App side: `PassiveScanController`

Owns the persistent XPC connection, the `FrameIngestor`, and the accumulators. Exposes
`@Published` passive state. Surfaced through `AppModel` and consumed by the new SwiftUI view.
Mirrors the existing `HelperManager` XPC patterns (continuation/resumer discipline, code-
signing requirement).

## Derivation (all are running tallies over `CapturedFrame`s)

1. **Hidden SSID resolution** (`PassiveBSSAccumulator`) — key BSSes by BSSID. When a beacon
   has a blank/zero-length SSID IE but a probe-response / (re)assoc frame for the same BSSID
   carries the name, fill it in.
2. **Measured channel utilization** (`AirtimeAccumulator`) — per channel, estimate each
   frame's airtime from its length + PHY rate (from radiotap) and sum over a sliding window;
   divide by wall-clock to get % busy. Approximate (we can't see frames while parked on
   other channels) — label it "measured (sampled)" to be honest about the dwell caveat.
3. **Client/device discovery** (`StationTracker`) — collect non-AP source addresses seen in
   probe requests and data frames; list as nearby devices with last-seen + signal.
4. **Retry rate** (`RetryAccumulator`) — per BSS, count frames with the retry bit set over
   total; surface as a health signal.

## UI

- **Entry:** a "Passive Scan" button + menu item. First click shows a confirmation
  explaining Wi-Fi will disconnect and return on stop.
- **Active state:** a prominent banner ("Passive scan running — Wi-Fi is off; listening on
  channel N…") with a **Stop** button. Live-updating results.
- **Dedicated view:** networks heard (incl. hidden names), reusing the existing table look;
  panels for the four derived insights; per-network colors/notes (from the annotations
  feature) carry over since it's the same BSS identity.
- **Separation:** passive scan is a distinct mode; the normal Dashboard / Nearby / Channel
  Map views are unchanged and keep working. Entering/leaving passive scan is explicit.

## Safety, failures, lifecycle

**Three independent guarantees Wi-Fi always returns:**
1. Normal Stop reconnects.
2. **Crash watchdog:** the helper installs `invalidationHandler`/`interruptionHandler` on the
   client connection; if the app quits/crashes mid-scan, the helper stops capture and
   reassociates on its own. *(Most important safety property.)*
3. **Max-duration backstop:** the helper self-stops after a hard cap (e.g. 10 min).

**Failure handling (each plain-English, safe fallback, never a silent hang or dead link):**
- Helper not approved → route to the existing enable flow (same as PHY metrics).
- Capture won't start (Wi-Fi off, rfmon refused) → message, stay on the normal view, do
  **not** disassociate.
- Malformed frame → skipped quietly (expected).

## Testing

- **Parsers:** feed real captures (the spike `.pcap`) + hand-crafted good/malformed/truncated
  frames through `FrameIngestor`; assert SSID, signal, channel, type/subtype, retry. Include
  deliberately broken frames to prove no traps.
- **Derivation:** fixed-input unit tests for each accumulator with known expected outputs
  (hidden-name fill-in, airtime %, station list, retry %).
- **Helper:** stays "dumb" (moves bytes, retunes radio) — minimal logic to unit-test; the
  reconnect/watchdog behavior gets a **manual hardware checklist** (normal stop, force-quit
  mid-scan, max-duration) since it needs a real radio.

## Implementation staging (for the plan)

1. **De-risk:** prove `setWLANChannel` works during a live rfmon session (throwaway).
2. **Parsers:** `RadiotapParser`, `Dot11FrameParser`, `FrameIngestor` + tests against the
   spike pcap. No capture, no UI.
3. **Helper capture engine + XPC contract:** `pcap_bridge`, `CaptureEngine`, protocol
   additions, bidirectional connection, watchdog + reconnect.
4. **Derivation accumulators** + tests.
5. **App wiring:** `PassiveScanController`, `AppModel` integration.
6. **UI:** entry/confirm/banner/stop + dedicated view.
7. **Signing/notarization:** rebuild signed + notarized (helper contract changed → re-verify
   embedded-helper signature and the whole notarization round-trip).
