# Signing, Location Services & notarization

Un-redacted Wi-Fi scan data (real SSIDs/BSSIDs) is gated by macOS on **two** things:

1. The app is signed with a **stable** code signature (a Developer ID, or at least a
   stable Apple Development identity), **and**
2. The user has granted the app **Location Services** access.

An ad-hoc build (`codesign -s -`, which is what a plain `xcodebuild` produces here)
changes its signature on every build, so macOS treats it as a new app each time and
Location grants don't stick — you'll see `<redacted>` BSSIDs. That is expected, and the
app says so in its degraded-mode banner.

---

## 1. Run a signed dev build (un-redacted, local)

In Xcode, select the **Oncillascope** target → **Signing & Capabilities**:

- Set **Team** to your Apple ID team.
- Signing style **Automatic** is fine for local dev.

Or via build settings / command line:

```bash
xcodebuild -scheme Oncillascope -configuration Debug \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  build
```

Launch it once and **grant Location access** when prompted (or System Settings →
Privacy & Security → Location Services → Oncillascope). BSSIDs are now real.

> The Location prompt text is in `App/Info.plist`
> (`NSLocationUsageDescription` / `NSLocationWhenInUseUsageDescription`) and explains the
> permission is required by macOS for Wi-Fi identity — not for tracking.

---

## 2. Developer ID build for distribution

**Team ID:** `4Z539UE4TT` (Davidson College developer account).

**Prerequisite — install the cert (one-time):** a "Developer ID Application"
certificate + private key must be in the login keychain. As of last check there were
**none** (`security find-identity -v -p codesigning` → "0 valid identities found").
Create it via Xcode ▸ Settings ▸ Accounts ▸ (select team) ▸ Manage Certificates ▸ **+**
▸ **Developer ID Application** (only the team's Account Holder can create it). Then verify:

```bash
security find-identity -v -p codesigning
# expect: …  "Developer ID Application: <name> (4Z539UE4TT)"
```

Once the cert is present, build a signed Release:

```bash
xcodebuild -scheme Oncillascope -configuration Release \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM=4Z539UE4TT \
  -derivedDataPath build \
  build
```

`ENABLE_HARDENED_RUNTIME = YES` is already set (required for notarization). The app is
**non-sandboxed** by default (`App/Oncillascope.entitlements`) so it can spawn `wdutil`; see
that file for how to adopt the App Sandbox + an `SMAppService` privileged helper instead.

---

## 3. Notarize

```bash
# Zip the .app
ditto -c -k --keepParent build/Build/Products/Release/Oncillascope.app Oncillascope.zip

# Submit (store credentials once with `xcrun notarytool store-credentials`)
xcrun notarytool submit Oncillascope.zip --keychain-profile "AC_NOTARY" --wait

# Staple the ticket
xcrun stapler staple build/Build/Products/Release/Oncillascope.app
```

---

## 4. `wdutil` privilege handling

`wdutil info` needs root. v1 uses `WdutilRunner(strategy: .directSudo)`, which runs
`sudo -n wdutil info` — it succeeds only if a non-interactive sudo grant already exists,
and otherwise fails fast so the UI shows the "needs admin authorization" banner.

For a smoother single-prompt experience, `WdutilRunner.Strategy.helper` accepts a closure
that invokes an installed privileged helper (the intended production path via
`SMAppService`). The bridge defines the contract; wiring the helper bundle is the next
milestone.
