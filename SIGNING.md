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

> **Prerequisite that bit us once:** the *Apple Development* cert was present but showed
> as **untrusted / "0 valid identities"** because the current **Apple WWDR G3** intermediate
> (valid 2020–2030) was missing — only the expired 2013–2023 WWDR was installed. Fix:
> ```bash
> curl -fsSL -o AppleWWDRCAG3.cer https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
> security import AppleWWDRCAG3.cer -k ~/Library/Keychains/login.keychain-db
> security find-identity -v -p codesigning     # now lists "Apple Development: … (4Z539UE4TT)"
> ```
> Working local-signing command (universal, hardened runtime, stable team signature):
> ```bash
> xcodebuild -scheme Oncillascope -configuration Release -derivedDataPath build \
>   CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Development" \
>   DEVELOPMENT_TEAM=4Z539UE4TT PROVISIONING_PROFILE_SPECIFIER="" build
> ```
> This signs with TeamIdentifier 4Z539UE4TT so Location/TCC grants persist. It's for
> **local use only** — an Apple Development signature isn't notarized (Gatekeeper will
> warn on *other* Macs) and the cert expires in a year. Distribution still needs the
> **Developer ID Application** cert below.


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

Once the cert is present, build a signed Release. **Two flags matter** (learned the hard
way): `--timestamp` (secure timestamp, required by notarization) and
`CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` (otherwise Xcode injects
`com.apple.security.get-task-allow`, the debug "let a debugger attach" entitlement, and
**notarization rejects it** with "critical validation errors"):

```bash
xcodebuild -scheme Oncillascope -configuration Release -derivedDataPath build \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM=4Z539UE4TT \
  PROVISIONING_PROFILE_SPECIFIER="" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build

# sanity: entitlements should be ONLY network.client (no get-task-allow)
codesign -d --entitlements :- build/Build/Products/Release/Oncillascope.app
```

`ENABLE_HARDENED_RUNTIME = YES` is already set (required for notarization). The app is
**non-sandboxed** by default (`App/Oncillascope.entitlements`) so it can spawn `wdutil`; see
that file for how to adopt the App Sandbox + an `SMAppService` privileged helper instead.

---

## 3. Notarize + staple (verified working 2026-06-26)

```bash
APP=build/Build/Products/Release/Oncillascope.app
ditto -c -k --keepParent "$APP" Oncillascope.zip

# App-specific password from appleid.apple.com ▸ Sign-In & Security ▸ App-Specific Passwords.
xcrun notarytool submit Oncillascope.zip \
  --apple-id jdmills@davidson.edu --team-id 4Z539UE4TT --password "<app-specific-pw>" --wait
# → "status: Accepted". On "Invalid", read the reason:
#   xcrun notarytool log <submission-id> --apple-id … --team-id … --password …

xcrun stapler staple "$APP"               # embed the ticket (works offline)
xcrun stapler validate "$APP"
spctl -a -t exec -vvv "$APP"              # → accepted / source=Notarized Developer ID
```

Distribute the **stapled** `.app` (e.g. zipped). Colleagues then open it with no Gatekeeper
block — at most a normal "downloaded from the internet" confirmation.

---

## 4. `wdutil` privilege handling

`wdutil info` needs root. v1 uses `WdutilRunner(strategy: .directSudo)`, which runs
`sudo -n wdutil info` — it succeeds only if a non-interactive sudo grant already exists,
and otherwise fails fast so the UI shows the "needs admin authorization" banner.

For a smoother single-prompt experience, `WdutilRunner.Strategy.helper` accepts a closure
that invokes an installed privileged helper (the intended production path via
`SMAppService`). The bridge defines the contract; wiring the helper bundle is the next
milestone.
