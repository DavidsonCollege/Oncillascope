# Oncillascope — handoff

A native macOS Wi-Fi / RF analyzer (Swift + SwiftUI). This doc orients a new agent fast.
Read alongside `README.md` (what it does), `SIGNING.md` (signing/notarization), and
`NAMING.md` (name vetting history).

## TL;DR status (2026-07-08)

- ✅ Core + app **built, tested (full SwiftPM suite, green in CI), signed, NOTARIZED, and installed**.
- ✅ Shareable notarized build: `~/Downloads/Oncillascope-1.0.zip`; installed at
  `/Applications/Oncillascope.app` (Gatekeeper: "accepted / Notarized Developer ID").
- ✅ Name **Oncillascope** finalized (was "AirScope" — taken on the Mac App Store).
- ✅ Icon: user-supplied wildcat-eye + Wi-Fi + waveform (source in `design/`).
- ✅ **SMAppService privileged helper built, signed, NOTARIZED & stapled** (second target
  `OncillascopeHelper`): team 4Z539UE4TT, hardened runtime, embedded helper deep-strict
  verifies, `spctl` → "Notarized Developer ID". Stapled build at `~/Downloads/Oncillascope-1.0.zip`.
  **Not yet end-to-end tested** — registration/approval is interactive (System Settings ▸
  Login Items & Extensions); install the new build and run the approval flow. See
  "Privileged helper" below.
- 🔑 notarytool creds now stored in the Keychain profile **`OncillascopeNotary`** — notarize
  with `xcrun notarytool submit <zip> --keychain-profile OncillascopeNotary --wait` (no
  password needed). Re-store with `notarytool store-credentials` after rotating the
  app-specific password.
- Repo lives at **github.com/DavidsonCollege/Oncillascope** (public). `main` is
  protected (PRs + green CI required); releases are tag-triggered and gated behind a
  manual approval on the `release` environment.

## What it is

Surfaces as much Wi-Fi/RF detail as macOS allows, fusing three sources: CoreWLAN
(identity, live stats, scan, raw IEs), parsed `wdutil info` (PHY metrics: MCS/NSS/guard
interval/CCA — needs admin), and a pure-Swift 802.11 Information Element parser. Panes:
Dashboard (live tiles + Swift Charts), Nearby Networks (sortable/filterable table + IE
inspector), Channel Map (spectrum curves + best-channel advice), Telemetry & Export.

## Repo layout

- `Package.swift` — SwiftPM package **`WiFiAnalyzerKit`** (internal name, never user-facing).
  - `Sources/WiFiModel` — value types + OFDM PHY-rate calculator (HT/VHT/HE/EHT).
  - `Sources/IEParser` — pure-Swift 802.11 IE decoder (the crown jewel; heavily tested).
  - `Sources/WdutilBridge` — `wdutil info` parser + runner (strategies: directSudo /
    osascriptAdmin / helper closure).
  - `Sources/OUIResolver` — offline BSSID→vendor (bundled `Resources/oui.csv`).
  - `Sources/Telemetry` — ring buffers + CSV/JSON export + roam/channel markers.
  - `Sources/WiFiCore` — CoreWLAN + CoreLocation wrappers; fuses everything.
  - `Tests/*` — unit tests (IEParser, WdutilBridge, OUIResolver, Telemetry; run in CI).
- `App/Oncillascope.xcodeproj` — **hand-crafted** pbxproj (objectVersion 77, uses a
  `PBXFileSystemSynchronizedRootGroup`, so source files aren't listed individually).
  - `App/Oncillascope/` — SwiftUI sources + `Assets.xcassets` (AppIcon, AccentColor).
  - `App/Info.plist`, `App/Oncillascope.entitlements` (at SRCROOT, not in the sync folder).
- `design/oncillascope-icon-source-1254.png` — canonical icon art.

## Build / test / run

```bash
swift test                                   # 34 core tests
xcodebuild -scheme Oncillascope -configuration Release build   # the app
```
- **Always use `-scheme Oncillascope`, never `-target`** — `-target` splits the build graph
  and the SwiftPM resource-bundle copy (`WiFiAnalyzerKit_OUIResolver.bundle`) fails.
- Plain builds are **ad-hoc signed** → degraded mode (BSSIDs redacted, Location won't stick).
- Bundle id `edu.davidson.oncillascope`, scheme/target/product `Oncillascope`.

## Signing & notarization (WORKING — full recipe in SIGNING.md)

- **Team ID `4Z539UE4TT`** = "The Trustees of Davidson College" (org account).
- Identities now in the keychain: **Developer ID Application** (cert+key imported from
  `~/Downloads/Davidson Apple Developer ID Application.p12`, pw was "application") and an
  Apple Development cert. Required installing the **WWDR G3** intermediate first
  (`security import AppleWWDRCAG3.cer`) or certs showed as untrusted/"0 valid identities".
- Signed Release recipe (two non-obvious flags):
  ```bash
  xcodebuild -scheme Oncillascope -configuration Release -derivedDataPath build \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" \
    DEVELOPMENT_TEAM=4Z539UE4TT PROVISIONING_PROFILE_SPECIFIER="" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build
  ```
  `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` is **mandatory** — otherwise notarization rejects
  the injected `com.apple.security.get-task-allow` debug entitlement ("Invalid").
- Notarize: `xcrun notarytool submit … --apple-id jdmills@davidson.edu --team-id 4Z539UE4TT
  --password <app-specific> --wait`, then `xcrun stapler staple <app>`.
- **Security note:** an app-specific password was shared in chat; user should rotate it at
  appleid.apple.com. Nothing in the repo depends on it.

## Key decisions & hard-won gotchas

- **Distribution model = Developer ID (NOT Mac App Store).** The App Store sandbox forbids
  running `wdutil` as root, which would kill the PHY-metrics feature. So we ship signed +
  notarized outside the store. App is **non-sandboxed**, hardened-runtime on.
- **SwiftUI layout traps (all fixed, don't reintroduce):**
  - Never put `.frame(minWidth:…)` on the `NavigationSplitView` root — it collapses the
    sidebar + detail to blank. Size via the scene; cap the **detail's** ideal size instead.
  - The window ballooned (1470×3541) because scrolling panels reported a tall ideal height;
    fixed by capping the detail's `idealHeight` while keeping `maxHeight: .infinity`.
  - Debug builds use an Xcode "debug dylib"/preview thunk that renders flaky when launched
    via `open` outside Xcode — use **Release** for screenshot/QA.
- **macOS specifics:** macOS does NOT auto-round app icons (unlike iOS) — icon art has the
  ~22.37% continuous-corner rounding baked in. `tccutil` can't remove orphaned Location
  Services rows (SIP-protected); a reboot prunes them.
- **wdutil admin prompt:** done **in-process** via `NSAppleScript` (`do shell script … with
  administrator privileges with prompt "…"`) so the dialog is attributed to *Oncillascope*
  with a tool-agnostic message — NOT by spawning `/usr/bin/osascript` (which showed
  "osascript"). See `App/Oncillascope/WdutilAuth.swift`.

## Features implemented

Dashboard (equal-height metric tiles, color-coded SNR/efficiency, live RSSI/Noise/SNR/
TxRate/MCS/CCA charts with roam markers); Nearby Networks table (sort/filter/group-by-SSID,
Location-aware redaction); Channel Map (per-band spectrum curves with **hover tooltips**
showing SSID/BSSID, advisory best-channel, **6 GHz "not supported" detection** on radios
that lack it — this Mac is a Mac14,2 w/ no 6 GHz); IE inspector (decoded tree). **Tooltips**
on every dashboard + inspector reading and every 802.11 IE, with a **View ▸ Plain-English
Tooltips** menu toggle (`@AppStorage` key `plainEnglishTooltips`) switching technical↔plain
(see `Help` enum in `App/Oncillascope/UIHelpers.swift`). Tx Power shown in mW + dBm.
Degraded-mode banners explain redaction; "Grant Access" opens Location Services settings.
**Per-network annotations**: a named color palette + free-text
note per BSS, persisted in UserDefaults (`AnnotationStore`, key `networkAnnotations`, keyed
by `BSSObservation.id`). Swatch + note glyph live in the SSID table cell (Table's 10-column
builder cap blocks adding columns — `Group` can't mix sortable/non-sortable columns); editor
is in the IE inspector; "Export Annotations as CSV…" in the File menu. See
`App/Oncillascope/Annotations.swift`.

## Privileged helper (SMAppService)

Second Xcode target **`OncillascopeHelper`** — a `com.apple.product-type.tool` daemon that
runs as **root** and vends one XPC method (`fetchWdutilInfo`). Files:

- `App/Shared/HelperProtocol.swift` — the `@objc OncillascopeHelperProtocol` + `HelperConstants`
  (mach service / label / bundle id `edu.davidson.oncillascope.helper`, team id, and the
  code-signing requirement strings). **Compiled into both targets** (one physical file, two
  explicit pbxproj references) so the ObjC protocol name matches across the XPC boundary —
  no separate package module, no static/dynamic-link question.
- `App/OncillascopeHelper/{main.swift,HelperService.swift}` — `NSXPCListener` on the mach
  service; `setCodeSigningRequirement` rejects any client that isn't the genuine same-team
  app; `HelperService` shells `/usr/bin/wdutil info`. Only that one operation is exposed (no
  general command execution).
- `App/edu.davidson.oncillascope.helper.plist` — launchd plist embedded at
  `Contents/Library/LaunchDaemons/`. `BundleProgram = Contents/MacOS/OncillascopeHelper`,
  `MachServices` + `Label` = the service name, `AssociatedBundleIdentifiers` = the app,
  `UserName = root`. **On-demand** (no `RunAtLoad`/`KeepAlive`): launchd starts it when a
  message hits the mach service, so there's no idle root process.
- `App/Oncillascope/HelperManager.swift` — app side. `SMAppService.daemon(plistName:)` for
  `register()`/`unregister()`/status; `openSystemSettingsLoginItems()`; and the XPC client
  (`NSXPCConnection(machServiceName:options:.privileged)` + `setCodeSigningRequirement`)
  that backs `WdutilRunner.Strategy.helper(invoke:)`. A once-guard wraps the continuation
  (reply vs. error-handler race).
- Integration: `AppModel` mirrors `helperStatus`; `refreshWdutil()` uses the helper when
  approved else the AppleScript prompt; `tick()` refreshes wdutil every cycle when approved.
  UI: `DegradedModeBanner` branches on `helperStatus` (Enable / Approve / one-shot), and
  `View ▸ Enable Continuous PHY Metrics` (`HelperMenu` in `OncillascopeApp.swift`).

**pbxproj wiring (hand-crafted, objectVersion 77).** New UUIDs `EA…0040–0056`: the helper
native target + its Debug/Release configs (`CREATE_INFOPLIST_SECTION_IN_BINARY=YES` so the
tool carries a bundle id for the codesign `identifier` requirement; `ENABLE_HARDENED_RUNTIME`,
`SKIP_INSTALL`), a `PBXTargetDependency` (app → helper), and two `PBXCopyFilesBuildPhase`s in
the app target: **Embed Helper Daemon** (`dstSubfolderSpec=6` Executables, `CodeSignOnCopy`)
and **Embed Launch Daemon plist** (`dstSubfolderSpec=1` Wrapper, `Contents/Library/LaunchDaemons`).
Build/sign with the same SIGNING.md recipe — the command-line signing overrides apply to
both targets. Verified: `codesign --verify --deep --strict` validates the embedded helper,
both binaries carry team `4Z539UE4TT`, `spctl` accepts as Developer ID.

## What comes next

1. **SMAppService privileged helper — BUILT, needs interactive verification + notarization.**
   Replaces the per-session admin prompt with a one-time approval (System Settings ▸ Login
   Items & Extensions) + XPC, and unlocks **continuous live PHY metrics** (the tick loop now
   refreshes wdutil every cycle when the helper is approved; otherwise it stays one-shot via
   the AppleScript fallback). Implementation (see "Privileged helper" section below).
   **Remaining (interactive):** install the notarized build to `/Applications`, launch, click
   *Enable Helper* (or View menu ▸ *Enable Continuous PHY Metrics*), approve in System
   Settings ▸ Login Items & Extensions, and confirm PHY metrics flow with no password prompt.
   The build is notarized; only the GUI approval step is left.
2. **Passive / monitor-mode scan (biggest passive-capture gap).** Spike done —
   see `PASSIVE-SCAN.md`. Monitor mode + radiotap **confirmed working on en0** (Mac14,2,
   macOS 26.5.1); the old "no monitor mode on the built-in adapter" claim was wrong and is
   now corrected in README. Live capture got 0 frames because the radio parks on a silent
   channel after disassociation ⇒ **channel steering via `CWInterface.setWLANChannel` is
   mandatory**, and the scan must be a modal mode that reconnects afterward. Would unlock
   hidden SSIDs + measured airtime; reuses `IEParser`. Next: prototype radiotap + 802.11
   MAC-header parsing against a captured pcap, then a `PassiveCapture` module + helper
   capture op.
3. **Optional polish:** a simplified 16px icon variant (current art is busy at menu-bar size);
   Sparkle auto-update; CI to build+notarize on tag.
4. **Housekeeping:** decide whether to push the repo to `DavidsonCollege` org; rotate the
   leaked app-specific password.

## Environment

Built/verified on macOS 26.5 (Tahoe), Xcode 26.6, Apple Silicon. Min target macOS 14.
User: JD Mills (jdmills@davidson.edu). Prefers concise responses, root-cause fixes, no
emojis; "just build" (skip brainstorming). Memory note lives at the agent's
`memory/oncillascope.md`.
