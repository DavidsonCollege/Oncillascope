# Passive-scan / monitor-mode feasibility spike

**Question:** Can Oncillascope close its biggest capability gap — passive
scanning (monitor mode) for hidden SSIDs, real airtime/retry stats, and frames from
non-beaconing devices — *on the stock built-in adapter*, without external hardware?

**Short answer: yes, and it's within Apple's permitted envelope.** The README/HANDOFF
claim "No monitor mode on the built-in adapter" is incorrect. macOS supports RF monitor
mode on `en0` via libpcap — the same path Wireshark and `tcpdump -I` use on a Mac. The
cost is real but it's *operational* (root + disassociation + channel hopping), not a
platform prohibition.

---

## Findings on this machine (the spike target)

- Hardware: **Mac14,2** (M2 MacBook Air, built-in Broadcom-class Wi-Fi).
- OS: **macOS 26.5.1** (build 25F80).
- `tcpdump -D` enumerates `en0` as a libpcap **Wireless** device, and also exposes a
  secondary `ap1 [Wireless, Not associated]` virtual interface. en0 is a valid pcap
  capture target.
- The datalink-type probe (`tcpdump -L -i en0`) and any capture require root (BPF device
  permission). **Not yet run live** — needs an interactive sudo step that briefly
  disassociates Wi-Fi (see "Live confirmation" below).

Strong prior evidence this works on this exact class of machine: Wireshark's macOS docs
describe monitor-mode capture on the built-in adapter of Apple Silicon Macs. The live
step below confirms it on *this* unit.

---

## What passive scanning unlocks (vs. our current active scan)

| Capability | Today (CoreWLAN active scan) | With passive capture |
|---|---|---|
| Hidden SSIDs | Invisible (beacon SSID blank) | Recoverable from probe-response / data frames |
| Channel utilization | BSS Load IE only (if AP advertises it) | **Measured** airtime from observed frame durations |
| Retry rate / frame errors | Unavailable | From the 802.11 retry bit + FCS |
| Non-beaconing devices / clients | Invisible | Visible (probe requests, data frames) |
| Per-frame RSSI | Per-scan aggregate | Per-frame, from radiotap header |
| Management frame detail | Beacon IEs only | Beacons + probes + assoc + auth/deauth |

The first two rows are the headline capabilities that passive capture unlocks.

---

## Mechanism (the macOS-supported path)

1. **Capture:** open `en0` with libpcap in monitor mode (`pcap_set_rfmon` / `tcpdump -I`).
   Datalink is `IEEE802_11_RADIO` — each frame is prefixed with a **radiotap** header
   (channel, RSSI, noise, rate, flags) followed by the raw 802.11 frame.
2. **Channel hopping:** monitor mode locks to one channel. To sweep the band, retune with
   `CWInterface.setWLANChannel(_:)` (still present and functional in CoreWLAN) on a timer —
   e.g. dwell ~200–300 ms per channel. This is exactly how Pro scanners cover all channels.
3. **Parse:** strip radiotap, parse the 802.11 MAC header (addr1–3, type/subtype, retry
   bit), then hand the frame body's tagged parameters straight to **our existing
   `IEParser`** — beacon/probe-response IEs are the same elements we already decode for the
   inspector. **A large fraction of the parsing work already exists.**

### Constraints (these are the real cost — surface them honestly in the UI)

- **Root.** BPF + rfmon need privilege. We already ship the **SMAppService helper**; extend
  its XPC contract with a capture operation (or have it open the BPF fd and pass it back).
  No new trust model — same signed-same-team enforcement.
- **Disassociation.** Monitor mode drops the active Wi-Fi connection for the duration of
  the scan. Passive scan must be an explicit, user-initiated *mode* ("Passive Scan — will
  disconnect Wi-Fi briefly"), never the always-on default.
- **No connectivity while scanning.** Can't run the live dashboard and a passive sweep at
  the same time on a single radio. UX: a distinct modal scan that returns a result set.
- **Channel dwell vs. coverage tradeoff.** Longer dwell = better airtime stats, slower full
  sweep. 6 GHz/PSC channels add more to cover.

---

## Architecture sketch (if we proceed)

- New `Sources/PassiveCapture` module (framework-independent, unit-testable like the rest):
  - `RadiotapParser` — decode the radiotap header → {channel, rssi, noise, rate, flags}.
  - `Dot11FrameParser` — MAC header (type/subtype/addrs/retry) + locate the IE/tagged body.
  - Feed the IE body into the existing `IEParser` (no duplication).
  - `AirtimeAccumulator` — sum observed frame airtime per channel → measured utilization.
- `CaptureEngine` (app or helper side) — libpcap session on `en0`, rfmon on.
- `ChannelHopper` — `CWInterface.setWLANChannel` on a timer; respects `supportedBands`.
- Helper change — add `startCapture`/`stopCapture` (or fd-passing) to `HelperProtocol`.
- UI — a "Passive Scan" action with an explicit disconnect warning; results merge into the
  existing networks table (hidden SSIDs now resolved; a "measured util" column).

Reuse is high: IEParser, OUIResolver, the BSS model, the helper, and the table all carry
over. The genuinely new code is radiotap + MAC-header parsing + the capture/hop loop.

---

## Live confirmation (interactive, ~10–20 s of Wi-Fi disconnect)

Run this to prove monitor mode + radiotap + beacon IEs on this Mac. It captures 30 beacon
frames on the current channel, then you reconnect automatically:

```bash
# 1) Confirm en0 offers the radiotap datalink (proves monitor mode is supported):
sudo tcpdump -L -i en0 | grep -i 802_11

# 2) Capture beacons in monitor mode (disassociates en0 for the capture window):
sudo tcpdump -I -i en0 -y IEEE802_11_RADIO -c 30 -w /tmp/oncilla-spike.pcap \
  'type mgt subtype beacon'

# 3) Inspect — confirm radiotap (RSSI/channel) + SSID IE (incl. blank = hidden):
tcpdump -e -r /tmp/oncilla-spike.pcap -v 2>/dev/null | head -40
```

Expected: frames decode with a radiotap header (signal in dBm, channel/freq) and an 802.11
beacon carrying the SSID + tagged parameters. A blank SSID with a non-blank BSSID is a
hidden network we could not see via the active scan.

---

## Live confirmation — RESULT (run 2026-06-30, this Mac14,2 / macOS 26.5.1)

Ran via a GUI admin prompt (the app's own `osascript … with administrator privileges`
path). **Monitor mode is confirmed working.** tcpdump stderr:

```
tcpdump: data link type IEEE802_11_RADIO
tcpdump: listening on en0, link-type IEEE802_11_RADIO (802.11 plus radiotap header),
         snapshot length 524288 bytes
```

en0 negotiated **rfmon + radiotap** — the README's "no monitor mode on the built-in
adapter" is definitively false on this hardware/OS.

Two empirical findings (both confirm the constraints above, now measured not assumed):

1. **0 frames captured** in a 20 s window. Once disassociated into monitor mode the radio
   parked on a channel with no beaconing APs and received nothing. ⇒ **Channel steering
   via `CWInterface.setWLANChannel` is mandatory**, not optional — opening rfmon alone
   yields silence. This is the first thing the feature prototype must implement.
2. **Disassociation is sticky.** en0 dropped the network and required a `networksetup
   -setairportpower` cycle to rejoin. ⇒ Passive scan must be an explicit modal mode that
   restores the connection afterward.

(`tcpdump -L -i en0` listed no 802.11 datalink, but `-I` authoritatively negotiated
radiotap — treat `-L` as inconclusive here, the `-I` negotiation is the real proof.)

## Recommendation

Proceed in two steps:

1. **Spike (≤1 day):** run the live confirmation above; if radiotap + IEs come through,
   prototype `RadiotapParser` + `Dot11FrameParser` against the captured pcap and prove we
   can extract BSSID/SSID/channel/RSSI and feed the body to `IEParser`. No UI yet.
2. **Feature (scoped):** add the `PassiveCapture` module, extend the helper, and a modal
   "Passive Scan" mode with the disconnect warning. Ship hidden-SSID resolution + measured
   utilization as the first deliverables — they're the clearest Pro-parity wins.

Also: **fix the README/HANDOFF wording.** "Apple doesn't permit monitor mode" is wrong and
currently rules out the single highest-value Pro-parity feature on incorrect grounds. The
honest framing is: monitor mode *is* available, but it's disruptive (root + disconnect +
hopping), so it's an opt-in mode rather than the default — and external spectrum analyzers
/ AirPcap-style hardware remain genuinely out of scope.
